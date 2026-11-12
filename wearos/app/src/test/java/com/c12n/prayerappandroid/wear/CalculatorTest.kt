package com.c12n.prayerappandroid.wear

import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

// Calculator validation: this Kotlin port must reproduce, to the minute,
// the reference implementation of the shipped phone calculators (same
// solar math and mosque calibration constants) across seasons, plus the
// Umm al-Qura Hijri conversion. Expected values are the same vectors
// used by the Flutter/Dart test suite (flutter/test/calculator_test.dart),
// generated from the iOS reference implementation and spot-checked
// against the mosque's published timetable (2026-10-27: Fajr 6:25 AM,
// Sunrise 8:23 AM, Dhuhr 1:19 PM, Asr 3:43 PM, Maghrib 6:16 PM,
// Isha 8:05 PM - all reproduced exactly).
class CalculatorTest {

    private fun minutesOfDay(instant: Instant): Int {
        val local = Edmonton.localDateTime(instant)
        return local.hour * 60 + local.minute
    }

    @Test
    fun prayerCalculatorReproducesReferenceTimesToTheMinute() {
        // [fajr, sunrise, dhuhr, asr, maghrib, isha] as Edmonton minutes of day.
        val expected = mapOf(
            "2026-05-01" to listOf(226, 359, 813, 1057, 1266, 1341),
            "2026-05-15" to listOf(212, 333, 812, 1067, 1290, 1366),
            "2026-06-21" to listOf(178, 304, 817, 1084, 1331, 1405),
            "2026-07-04" to listOf(187, 311, 819, 1085, 1328, 1403),
            "2026-08-01" to listOf(223, 348, 822, 1074, 1294, 1370),
            "2026-09-21" to listOf(316, 436, 808, 1006, 1180, 1288),
            "2026-10-27" to listOf(385, 503, 799, 943, 1096, 1205),
            "2026-11-17" to listOf(420, 543, 801, 914, 1058, 1174),
            "2026-12-21" to listOf(457, 588, 814, 903, 1040, 1162),
            "2027-01-15" to listOf(454, 583, 824, 926, 1068, 1187),
            "2027-06-21" to listOf(178, 303, 817, 1084, 1331, 1405),
            "2025-03-01" to listOf(319, 441, 766, 932, 1094, 1201),
            "2026-02-10" to listOf(360, 483, 768, 904, 1057, 1167),
        )
        for ((date, want) in expected) {
            val t = PrayerCalculator.timesFor(LocalDate.parse(date))
            val got = listOf(
                minutesOfDay(t.fajr),
                minutesOfDay(t.sunrise),
                minutesOfDay(t.dhuhr),
                minutesOfDay(t.asr),
                minutesOfDay(t.maghrib),
                minutesOfDay(t.isha),
            )
            assertEquals(date, want, got)
        }
    }

    @Test
    fun ummAlQuraHijriConversion() {
        assertEquals("16 Jumada I 1448 AH", UmmAlQuraCalendar.hijriString(2026, 10, 27))
        assertEquals("17 Jumada I 1448 AH", UmmAlQuraCalendar.hijriString(2026, 10, 28))
        assertEquals("19 Jumada II 1445 AH", UmmAlQuraCalendar.hijriString(2024, 1, 1))
        assertEquals("14 Safar 1452 AH", UmmAlQuraCalendar.hijriString(2030, 6, 15))
        assertEquals("23 Rajab 1448 AH", UmmAlQuraCalendar.hijriString(2027, 1, 1))
    }

    @Test
    fun iqamahOffsetsMatchPhoneApps() {
        assertEquals(20, iqamahOffsetMinutes(Prayer.FAJR))
        assertEquals(null, iqamahOffsetMinutes(Prayer.SUNRISE))
        assertEquals(10, iqamahOffsetMinutes(Prayer.DHUHR))
        assertEquals(10, iqamahOffsetMinutes(Prayer.ASR))
        assertEquals(5, iqamahOffsetMinutes(Prayer.MAGHRIB))
        assertEquals(10, iqamahOffsetMinutes(Prayer.ISHA))
    }
}
