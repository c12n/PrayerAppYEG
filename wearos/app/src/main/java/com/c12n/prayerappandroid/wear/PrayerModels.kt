package com.c12n.prayerappandroid.wear

import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

// Prayer day model and next-prayer snapshot logic - a port of the phone
// apps' prayer_models behaviour. All times follow the mosque's time zone
// (America/Edmonton), like the phone apps.

/** America/Edmonton as an explicit transition table.
 *
 * Alberta stays on Mountain Daylight Time permanently from the
 * March 2026 spring-forward (the mosque's published timetable and
 * current system tzdata both keep Edmonton at UTC-6 after that). The
 * phone apps build the location from this same table:
 * MST (UTC-7) / MDT (UTC-6) with transitions on 2025-03-09 (09:00 UTC),
 * 2025-11-02 (08:00 UTC) and 2026-03-08 (09:00 UTC, then MDT forever).
 * java.time's bundled zone rules still carry the pre-2026 Alberta
 * rules, so the offset is resolved from this table instead. */
object Edmonton {
    private val MST: ZoneOffset = ZoneOffset.ofHours(-7)
    private val MDT: ZoneOffset = ZoneOffset.ofHours(-6)

    private val T1: Instant = Instant.parse("2025-03-09T09:00:00Z")
    private val T2: Instant = Instant.parse("2025-11-02T08:00:00Z")
    private val T3: Instant = Instant.parse("2026-03-08T09:00:00Z")

    fun offsetAt(instant: Instant): ZoneOffset = when {
        instant < T1 -> MST
        instant < T2 -> MDT
        instant < T3 -> MST
        else -> MDT
    }

    fun localDateTime(instant: Instant): LocalDateTime =
        LocalDateTime.ofInstant(instant, offsetAt(instant))

    fun localDate(instant: Instant): LocalDate = localDateTime(instant).toLocalDate()

    /** The instant of a local wall-clock time. Two passes so times near a
     *  transition resolve with the offset in effect at that wall time. */
    fun instantOf(local: LocalDateTime): Instant {
        val firstGuess = local.toInstant(MST)
        return local.toInstant(offsetAt(firstGuess))
    }

    fun instantOf(date: LocalDate, time: LocalTime): Instant =
        instantOf(LocalDateTime.of(date, time))
}

enum class Prayer(val displayName: String) {
    FAJR("Fajr"),
    SUNRISE("Sunrise"),
    DHUHR("Dhuhr"),
    ASR("Asr"),
    MAGHRIB("Maghrib"),
    ISHA("Isha");

    /** Sunrise is shown in the schedule but is not a prayer
     *  (no Iqamah, never "next prayer"). */
    val isPrayer: Boolean get() = this != SUNRISE
}

/** Iqamah offsets in minutes after Adhan (same defaults as the phone
 *  apps): Fajr +20, Dhuhr +10, Asr +10, Maghrib +5, Isha +10. */
fun iqamahOffsetMinutes(prayer: Prayer): Int? = when (prayer) {
    Prayer.FAJR -> 20
    Prayer.SUNRISE -> null
    Prayer.DHUHR -> 10
    Prayer.ASR -> 10
    Prayer.MAGHRIB -> 5
    Prayer.ISHA -> 10
}

class PrayerSlot(
    val prayer: Prayer,
    val adhan: Instant,
    val iqamah: Instant?,
    val isJumuah: Boolean,
) {
    val name: String get() = if (isJumuah) "Jumu'ah" else prayer.displayName
    val iqamahLabel: String get() = if (isJumuah) "Khutbah" else "Iqamah"
}

class PrayerDay(
    /** The Edmonton civil date this schedule belongs to. */
    val date: LocalDate,
    val adhanTimes: Map<Prayer, Instant>,
    val iqamahTimes: Map<Prayer, Instant>,
    val hijriDate: String,
    val isFriday: Boolean,
    val jumuahKhutbah: Instant?,
) {
    fun adhan(prayer: Prayer): Instant = adhanTimes.getValue(prayer)
    fun iqamah(prayer: Prayer): Instant? = iqamahTimes[prayer]

    /** All six rows. On Fridays the Dhuhr row becomes Jumu'ah with the
     *  Khutbah time in the Iqamah column. */
    val slots: List<PrayerSlot> = Prayer.values().map { prayer ->
        val jumuah = isFriday && prayer == Prayer.DHUHR
        val second = if (jumuah) (jumuahKhutbah ?: iqamah(prayer)) else iqamah(prayer)
        PrayerSlot(prayer, adhan(prayer), second, jumuah)
    }

    /** The five prayers (no Sunrise) - used for "next prayer" logic. */
    val prayerSlots: List<PrayerSlot> = slots.filter { it.prayer.isPrayer }
}

class PrayerSnapshot(
    val now: Instant,
    val day: PrayerDay,
    val next: PrayerSlot,
    val previousBoundary: Instant,
    val isShowingTomorrow: Boolean,
) {
    fun isNext(slot: PrayerSlot): Boolean =
        slot.prayer == next.prayer && slot.adhan == next.adhan
}

object PrayerProvider {
    /** Computes the full PrayerDay for an Edmonton civil date. */
    fun computeDay(date: LocalDate): PrayerDay {
        val times = PrayerCalculator.timesFor(date)
        val adhanTimes = mapOf(
            Prayer.FAJR to times.fajr,
            Prayer.SUNRISE to times.sunrise,
            Prayer.DHUHR to times.dhuhr,
            Prayer.ASR to times.asr,
            Prayer.MAGHRIB to times.maghrib,
            Prayer.ISHA to times.isha,
        )
        val iqamahTimes = mutableMapOf<Prayer, Instant>()
        for (prayer in Prayer.values()) {
            val offset = iqamahOffsetMinutes(prayer)
            if (offset != null) {
                iqamahTimes[prayer] = adhanTimes.getValue(prayer).plus(Duration.ofMinutes(offset.toLong()))
            }
        }

        val isFriday = date.dayOfWeek == DayOfWeek.FRIDAY
        // Jumu'ah Khutbah at 1:30 PM local, as in the phone apps.
        val khutbah = if (isFriday) {
            Edmonton.instantOf(date, LocalTime.of(13, 30))
        } else {
            null
        }

        return PrayerDay(
            date = date,
            adhanTimes = adhanTimes,
            iqamahTimes = iqamahTimes,
            hijriDate = UmmAlQuraCalendar.hijriString(date.year, date.monthValue, date.dayOfMonth),
            isFriday = isFriday,
            jumuahKhutbah = khutbah,
        )
    }

    /** State at an arbitrary instant: the next upcoming prayer and the
     *  day whose schedule should be displayed (switches to tomorrow
     *  after Isha) - mirrors the phone apps' snapshot logic. */
    fun snapshot(now: Instant): PrayerSnapshot {
        val today = Edmonton.localDate(now)
        val days = (-1..2).map { computeDay(today.plusDays(it.toLong())) }
        val candidates = days.flatMap { day -> day.slots.map { day to it } }
            .filter { it.second.prayer.isPrayer }
        for (i in candidates.indices) {
            val (day, slot) = candidates[i]
            if (slot.adhan.isAfter(now)) {
                val previous = if (i > 0) {
                    candidates[i - 1].second.adhan
                } else {
                    slot.adhan.minus(Duration.ofHours(6))
                }
                return PrayerSnapshot(
                    now = now,
                    day = day,
                    next = slot,
                    previousBoundary = previous,
                    isShowingTomorrow = day.date.isAfter(today),
                )
            }
        }
        // Defensive fallback: tomorrow's Fajr is always after `now`.
        val fallbackDay = computeDay(today.plusDays(1))
        return PrayerSnapshot(
            now = now,
            day = fallbackDay,
            next = fallbackDay.prayerSlots.first(),
            previousBoundary = now,
            isShowingTomorrow = true,
        )
    }
}

// MARK: - Formatting (always in the mosque's time zone)

object PrayerFormat {
    private val timeFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("h:mm a", Locale.US)
    private val shortDateFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US)

    /** "1:19 PM" */
    fun time(instant: Instant): String =
        Edmonton.localDateTime(instant).format(timeFormatter)

    /** "Tue, Nov 11" */
    fun shortDate(instant: Instant): String =
        Edmonton.localDateTime(instant).format(shortDateFormatter)

    /** "2:14:33" countdown text. */
    fun countdown(duration: Duration): String {
        var d = duration
        if (d.isNegative) d = Duration.ZERO
        val h = d.toHours()
        val m = (d.toMinutes() % 60).toString().padStart(2, '0')
        val s = (d.seconds % 60).toString().padStart(2, '0')
        return "$h:$m:$s"
    }

    /** "2h 14m" / "45m" - compact form for tiles and complications. */
    fun countdownShort(duration: Duration): String {
        var d = duration
        if (d.isNegative) d = Duration.ZERO
        val h = d.toHours()
        val m = d.toMinutes() % 60
        return if (h > 0) "${h}h ${m}m" else "${m}m"
    }
}
