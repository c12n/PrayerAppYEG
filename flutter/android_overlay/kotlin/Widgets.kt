package com.c12n.alrashidwidget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.widget.RemoteViews
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/// User settings written by the Flutter app (shared_preferences), read
/// back here so the widgets follow the same choices. shared_preferences
/// stores into "FlutterSharedPreferences" with a "flutter." key prefix;
/// ints land as Long, booleans as Boolean.
object WidgetPrefs {
    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /// Whether the countdown should move to this prayer (Settings →
    /// Widget Countdown). The five prayers default on, Sunrise off.
    fun countdownEnabled(context: Context, name: String): Boolean =
        prefs(context).getBoolean("flutter.alerts.${name.lowercase()}", name != "Sunrise")

    /// The user's accent color (Settings → Theme Colors), adjusted for
    /// the current appearance the same way the apps do it: brightened on
    /// dark surfaces, deepened on light ones. Null = not picked yet.
    /// The app's language (Settings → Language), "en"/"ar"/"fr".
    fun language(context: Context): String =
        prefs(context).getString("flutter.language.code", null) ?: "en"

    fun accentColor(context: Context): Int? {
        val raw = prefs(context).getLong("flutter.appearance.accentHex", -1L)
        if (raw < 0) return null
        val night = (context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val hsv = FloatArray(3)
        Color.colorToHSV((0xFF000000 or raw).toInt(), hsv)
        if (night) {
            hsv[1] = minOf(hsv[1], 0.9f)
            hsv[2] = maxOf(hsv[2], 0.82f)
        } else {
            hsv[1] = hsv[1].coerceIn(0.55f, 1.0f)
            hsv[2] = minOf(hsv[2], 0.42f)
        }
        return Color.HSVToColor(hsv)
    }
}

/// Localized widget strings (v1.1.0). Internal logic keeps English
/// prayer keys; only display strings go through here.
object WidgetStrings {
    private fun arabicDigits(input: String): String {
        val digits = "٠١٢٣٤٥٦٧٨٩"
        return input.map { ch -> if (ch in '0'..'9') digits[ch - '0'] else ch }
            .joinToString("")
    }

    fun locale(language: String): Locale = when (language) {
        "ar" -> Locale("ar")
        "fr" -> Locale("fr")
        else -> Locale.US
    }

    fun prayerName(english: String, language: String): String = when (language) {
        "ar" -> when (english) {
            "Fajr" -> "الفجر"; "Sunrise" -> "الشروق"; "Dhuhr" -> "الظهر"
            "Asr" -> "العصر"; "Maghrib" -> "المغرب"; "Isha" -> "العشاء"
            else -> english
        }
        "fr" -> if (english == "Sunrise") "Lever du soleil" else english
        else -> english
    }

    fun jumuah(language: String): String =
        if (language == "ar") "الجمعة" else "Jumu'ah"

    fun iqamahLabel(isJumuah: Boolean, language: String): String = when {
        isJumuah && language == "ar" -> "الخطبة"
        isJumuah -> "Khutbah"
        language == "ar" -> "الإقامة"
        else -> "Iqamah"
    }

    fun at(language: String): String = when (language) {
        "ar" -> "في"; "fr" -> "à"; else -> "at"
    }

    fun nextCaption(tomorrow: Boolean, caps: Boolean, language: String): String =
        when (language) {
            "ar" -> if (tomorrow) "الصلاة التالية · غدًا" else "الصلاة التالية"
            "fr" -> if (caps) {
                if (tomorrow) "PROCHAINE · DEMAIN" else "PROCHAINE PRIÈRE"
            } else {
                if (tomorrow) "Prochaine prière · Demain" else "Prochaine prière"
            }
            else -> if (caps) {
                if (tomorrow) "NEXT · TOMORROW" else "NEXT PRAYER"
            } else {
                if (tomorrow) "Next prayer · Tomorrow" else "Next prayer"
            }
        }

    fun countdown(now: Boolean, h: Long, m: Long, language: String): String =
        when (language) {
            "ar" -> if (now) "الآن" else "متبقي " + arabicDigits("%d:%02d".format(h, m))
            "fr" -> if (now) "maintenant" else when {
                h > 0 && m > 0 -> "dans ${h}h ${m}m"
                h > 0 -> "dans ${h}h"
                else -> "dans ${m}m"
            }
            else -> if (now) "now" else when {
                h > 0 && m > 0 -> "in ${h}h ${m}m"
                h > 0 -> "in ${h}h"
                else -> "in ${m}m"
            }
        }
}

/// Shared data builder for the home-screen widgets: computes today's
/// (and tomorrow's) schedule with the same calibrated calculator as the
/// app and finds the next prayer, mirroring the app's snapshot logic.
object WidgetData {
    data class Row(
        val name: String,
        val adhan: ZonedDateTime,
        val iqamah: ZonedDateTime?,
        val isNext: Boolean,
        val dimmed: Boolean
    )

    data class Model(
        val hijri: String,
        /// Gregorian date of the displayed day, "Wed, Oct 28" (v1.0.5).
        val dateText: String,
        val nextName: String,
        val nextTime: String,
        val nextIqamahText: String?,
        val countdownText: String,
        val showingTomorrow: Boolean,
        val rows: List<Row>,
        val isFriday: Boolean,
        /// Epoch millis of the next Adhan — the rollover alarm target.
        val nextAdhanMillis: Long
    )

    private fun timeFmt(language: String) =
        DateTimeFormatter.ofPattern("h:mm a", WidgetStrings.locale(language))
    private fun dateFmt(language: String) =
        DateTimeFormatter.ofPattern("EEE, MMM d", WidgetStrings.locale(language))

    fun formatTime(t: ZonedDateTime, language: String = "en"): String =
        timeFmt(language).format(t)

    private fun iqamahOffset(name: String): Int? = when (name) {
        "Fajr" -> 20
        "Dhuhr" -> 10
        "Asr" -> 10
        "Maghrib" -> 5
        "Isha" -> 10
        else -> null
    }

    private class DaySchedule(
        val date: LocalDate,
        val times: PrayerCalculator.Times,
        val isFriday: Boolean
    ) {
        val khutbah: ZonedDateTime? = if (isFriday) {
            ZonedDateTime.of(date.atTime(13, 30), PrayerCalculator.ZONE)
        } else null

        fun adhan(name: String): ZonedDateTime = when (name) {
            "Fajr" -> times.fajr
            "Sunrise" -> times.sunrise
            "Dhuhr" -> times.dhuhr
            "Asr" -> times.asr
            "Maghrib" -> times.maghrib
            else -> times.isha
        }

        fun iqamah(name: String): ZonedDateTime? {
            if (name == "Dhuhr" && isFriday) return khutbah
            val offset = iqamahOffset(name) ?: return null
            return adhan(name).plusMinutes(offset.toLong())
        }
    }

    private val allNames = listOf("Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha")
    private val prayerNames = listOf("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha")

    fun current(
        context: Context,
        now: ZonedDateTime = ZonedDateTime.now(PrayerCalculator.ZONE)
    ): Model {
        val language = WidgetPrefs.language(context)
        // The countdown rotation honors the user's Widget Countdown
        // choices (v1.0.5): prayers they turned off are skipped, and
        // Sunrise joins the rotation when they turned it on. If they
        // turned everything off, fall back to the five prayers.
        val rotation = allNames.filter { WidgetPrefs.countdownEnabled(context, it) }
            .ifEmpty { prayerNames }
        val today = now.toLocalDate()
        val days = (-1..2).map { offset ->
            val date = today.plusDays(offset.toLong())
            DaySchedule(
                date,
                PrayerCalculator.timesFor(date),
                date.dayOfWeek == DayOfWeek.FRIDAY
            )
        }

        // Next prayer = first prayer Adhan strictly after now.
        var nextDay = days.last()
        var nextName = "Fajr"
        var found = false
        for (day in days) {
            for (name in rotation) {
                if (day.adhan(name).isAfter(now)) {
                    nextDay = day
                    nextName = name
                    found = true
                    break
                }
            }
            if (found) break
        }

        val isJumuahNext = nextDay.isFriday && nextName == "Dhuhr"
        val displayName =
            if (isJumuahNext) WidgetStrings.jumuah(language)
            else WidgetStrings.prayerName(nextName, language)
        val nextAdhan = nextDay.adhan(nextName)
        val nextIqamah = nextDay.iqamah(nextName)
        val iqamahLabel = WidgetStrings.iqamahLabel(isJumuahNext, language)

        val rows = allNames.map { name ->
            val jumuah = nextDay.isFriday && name == "Dhuhr"
            Row(
                name = if (jumuah) WidgetStrings.jumuah(language)
                       else WidgetStrings.prayerName(name, language),
                adhan = nextDay.adhan(name),
                iqamah = nextDay.iqamah(name),
                isNext = name == nextName,
                dimmed = name == "Sunrise"
            )
        }

        return Model(
            hijri = UmmAlQuraCalendar.hijriString(
                nextDay.date.year, nextDay.date.monthValue, nextDay.date.dayOfMonth,
                language
            ),
            dateText = dateFmt(language).format(nextDay.date),
            nextName = displayName,
            nextTime = formatTime(nextAdhan, language),
            nextIqamahText = nextIqamah?.let {
                "$iqamahLabel ${WidgetStrings.at(language)} ${formatTime(it, language)}"
            },
            countdownText = countdownText(now, nextAdhan, language),
            showingTomorrow = nextDay.date.isAfter(today),
            rows = rows,
            isFriday = nextDay.isFriday,
            nextAdhanMillis = nextAdhan.toInstant().toEpochMilli()
        )
    }

    private fun countdownText(
        now: ZonedDateTime, target: ZonedDateTime, language: String
    ): String {
        val d = Duration.between(now, target)
        if (d.isNegative || d.toMinutes() == 0L) {
            return WidgetStrings.countdown(true, 0, 0, language)
        }
        return WidgetStrings.countdown(false, d.toHours(), d.toMinutes() % 60, language)
    }
}

abstract class BaseWidgetProvider : AppWidgetProvider() {
    abstract fun layoutId(): Int
    abstract fun buildViews(context: Context, model: WidgetData.Model): RemoteViews

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val model = WidgetData.current(context)
        for (id in appWidgetIds) {
            val views = buildViews(context, model)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            appWidgetManager.updateAppWidget(id, views)
        }
        scheduleRollover(context, model.nextAdhanMillis)
    }

    /// Automatic rollover (v1.0.4): chain an alarm to just after the next
    /// Adhan so the widgets swap to the following prayer on their own —
    /// Dhuhr hands over to Asr without the app being opened. Each update
    /// re-arms the alarm for the following Adhan. setAndAllowWhileIdle is
    /// inexact (Doze can delay it a few minutes) and needs no exact-alarm
    /// permission; the 30-minute updatePeriodMillis remains the backstop.
    private fun scheduleRollover(context: Context, nextAdhanMillis: Long) {
        val component = ComponentName(context, javaClass)
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(component)
        if (ids.isEmpty()) return
        val intent = Intent(context, javaClass).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        val pending = PendingIntent.getBroadcast(
            context, javaClass.name.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC, nextAdhanMillis + 15_000, pending
        )
    }
}

/// Small widget: next prayer with countdown.
class NextPrayerWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_next

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_caption,
            WidgetStrings.nextCaption(model.showingTomorrow, true, WidgetPrefs.language(context)))
        views.setTextViewText(R.id.widget_date, model.dateText)
        views.setTextViewText(R.id.widget_next_name, model.nextName)
        views.setTextViewText(R.id.widget_next_time, model.nextTime)
        views.setTextViewText(R.id.widget_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_iqamah, model.nextIqamahText ?: "")
        WidgetPrefs.accentColor(context)?.let { accent ->
            views.setTextColor(R.id.widget_caption, accent)
            views.setTextColor(R.id.widget_countdown, accent)
        }
        return views
    }
}

/// Medium widget: next prayer header + full day table.
class ScheduleWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_schedule

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_header_next,
            "${model.nextName} · ${model.nextTime}")
        views.setTextViewText(R.id.widget_header_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_date, model.dateText)
        WidgetPrefs.accentColor(context)?.let { accent ->
            views.setTextColor(R.id.widget_header_countdown, accent)
        }
        fillRows(context, views, model)
        return views
    }

    companion object {
        /// Row colors come from values/widget_colors.xml (+ values-night),
        /// so the table follows Light/Dark Mode like the layouts do. The
        /// "next" row uses the user's picked accent color when set.
        fun fillRows(context: Context, views: RemoteViews, model: WidgetData.Model) {
            val accent = WidgetPrefs.accentColor(context)
                ?: context.getColor(R.color.widget_accent)
            val primary = context.getColor(R.color.widget_primary)
            val muted = context.getColor(R.color.widget_muted)
            val nameIds = intArrayOf(
                R.id.row0_name, R.id.row1_name, R.id.row2_name,
                R.id.row3_name, R.id.row4_name, R.id.row5_name
            )
            val adhanIds = intArrayOf(
                R.id.row0_adhan, R.id.row1_adhan, R.id.row2_adhan,
                R.id.row3_adhan, R.id.row4_adhan, R.id.row5_adhan
            )
            val iqamahIds = intArrayOf(
                R.id.row0_iqamah, R.id.row1_iqamah, R.id.row2_iqamah,
                R.id.row3_iqamah, R.id.row4_iqamah, R.id.row5_iqamah
            )
            model.rows.forEachIndexed { i, row ->
                val color = when {
                    row.isNext -> accent
                    row.dimmed -> muted
                    else -> primary
                }
                views.setTextViewText(nameIds[i], row.name)
                val language = WidgetPrefs.language(context)
                views.setTextViewText(adhanIds[i], WidgetData.formatTime(row.adhan, language))
                views.setTextViewText(
                    iqamahIds[i],
                    row.iqamah?.let { WidgetData.formatTime(it, language) } ?: "—"
                )
                views.setTextColor(nameIds[i], color)
                views.setTextColor(adhanIds[i], color)
                views.setTextColor(iqamahIds[i], color)
            }
        }
    }
}

/// Large widget: mosque header + next prayer + full day table.
class LargeScheduleWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_large

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_hijri, "${model.dateText} · ${model.hijri}")
        views.setTextViewText(R.id.widget_next_label,
            WidgetStrings.nextCaption(model.showingTomorrow, false, WidgetPrefs.language(context)))
        views.setTextViewText(R.id.widget_next_name, model.nextName)
        views.setTextViewText(R.id.widget_next_time, model.nextTime)
        views.setTextViewText(R.id.widget_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_iqamah, model.nextIqamahText ?: "")
        WidgetPrefs.accentColor(context)?.let { accent ->
            views.setTextColor(R.id.widget_countdown, accent)
            views.setTextColor(R.id.widget_next_label, accent)
        }
        ScheduleWidgetProvider.fillRows(context, views, model)
        return views
    }
}
