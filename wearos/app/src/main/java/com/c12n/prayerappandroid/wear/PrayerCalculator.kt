package com.c12n.prayerappandroid.wear

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlin.math.tan

// Self-contained, offline prayer-time calculator using the standard solar
// algorithm (Julian day -> solar declination & equation of time -> hour
// angles), calibrated to Al Rashid Mosque Edmonton's published timetable.
//
// This is a faithful port of the phone apps' calculator
// (PrayerCalculator.swift / prayer_calculator.dart) - same solar math,
// same mosque calibration (fitted against every published day of
// May-December 2026, 245 days).
//
// Times are computed for a Gregorian civil date as observed in
// America/Edmonton and returned as UTC instants (java.time.Instant),
// rounded to the nearest minute - identical semantics to the phone apps.

class PrayerTimesResult(
    val fajr: Instant,
    val sunrise: Instant,
    val dhuhr: Instant,
    val asr: Instant,
    val maghrib: Instant,
    val isha: Instant,
)

private class SolarTimes(
    var fajr: Double,
    var sunrise: Double,
    var dhuhr: Double,
    var asr: Double,
    var sunset: Double,
    var isha: Double,
    var fajrClamped: Boolean,
    var ishaClamped: Boolean,
)

object PrayerCalculator {
    const val LATITUDE = 53.591189
    const val LONGITUDE = -113.515598
    const val FAJR_ANGLE = 18.25
    const val ISHA_ANGLE = 17.5
    const val MAGHRIB_MINUTES = 5.0

    private const val RISE_SET_ANGLE = 0.833 // elevation 0

    /** Prayer times for the Edmonton civil date [date]. */
    fun timesFor(date: LocalDate): PrayerTimesResult {
        val year = date.year
        val month = date.monthValue
        val day = date.dayOfMonth
        val julianDay = julianDay(year, month, day) - LONGITUDE / (15.0 * 24.0)

        var solar = SolarTimes(5.0, 6.0, 12.0, 13.0, 18.0, 18.0, false, false)
        repeat(2) { solar = computeSolarTimes(julianDay, solar) }
        solar = applyHighLatitudeRule(solar)

        val dayOfYear = date.dayOfYear
        val declination = sunPosition(julianDay + solar.dhuhr / 24.0).first
        val calibratedSunrise =
            solar.sunrise - MosqueCalibration.sunriseBiasMinutes(dayOfYear) / 60.0
        val calibratedSunset =
            solar.sunset - MosqueCalibration.sunsetBiasMinutes(dayOfYear) / 60.0
        val calibratedMaghrib = calibratedSunset + MAGHRIB_MINUTES / 60.0
        val calibratedFajr: Double = if (declination >= 10) {
            calibratedSunrise -
                MosqueCalibration.fajrSummerPortionMinutes(declination) / 60.0
        } else {
            solar.fajr - MosqueCalibration.fajrBiasMinutes(dayOfYear) / 60.0
        }
        val calibratedIsha = calibratedMaghrib +
            MosqueCalibration.ishaIntervalMinutes(declination) / 60.0

        val utcMidnightMs =
            date.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
        val longitudeHours = LONGITUDE / 15.0

        fun instant(localSolarHours: Double): Instant {
            val utcHours = localSolarHours - longitudeHours
            val micros = roundHalfAwayFromZero(utcHours * 3600.0 * 1000000)
            val ms = utcMidnightMs + micros / 1000
            // Round to the nearest minute (ties away from zero, like the
            // phone apps).
            val rounded = roundHalfAwayFromZero(ms / 60000.0) * 60000
            return Instant.ofEpochMilli(rounded)
        }

        return PrayerTimesResult(
            fajr = instant(calibratedFajr),
            sunrise = instant(calibratedSunrise),
            dhuhr = instant(
                solar.dhuhr + MosqueCalibration.dhuhrCorrectionMinutes(dayOfYear) / 60.0
            ),
            asr = instant(
                solar.asr + MosqueCalibration.asrCorrectionMinutes(dayOfYear) / 60.0
            ),
            maghrib = instant(calibratedMaghrib),
            isha = instant(calibratedIsha),
        )
    }

    // MARK: - Solar computation

    private fun computeSolarTimes(julianDay: Double, est: SolarTimes): SolarTimes {
        val fajr = sunAngleTime(julianDay, FAJR_ANGLE, est.fajr, counterClockwise = true)
        val sunrise =
            sunAngleTime(julianDay, RISE_SET_ANGLE, est.sunrise, counterClockwise = true)
        val dhuhr = midDay(julianDay, est.dhuhr)
        val asr = asrTime(julianDay, est.asr)
        val sunset =
            sunAngleTime(julianDay, RISE_SET_ANGLE, est.sunset, counterClockwise = false)
        val isha = sunAngleTime(julianDay, ISHA_ANGLE, est.isha, counterClockwise = false)
        return SolarTimes(
            fajr.first, sunrise.first, dhuhr, asr.first, sunset.first, isha.first,
            fajr.second, isha.second,
        )
    }

    /** (declination degrees, equation of time hours) for a Julian day. */
    private fun sunPosition(julianDay: Double): Pair<Double, Double> {
        val d = julianDay - 2451545.0
        val g = fixAngle(357.529 + 0.98560028 * d)
        val q = fixAngle(280.459 + 0.98564736 * d)
        val l = fixAngle(q + 1.915 * dSin(g) + 0.020 * dSin(2 * g))
        val e = 23.439 - 0.00000036 * d
        val rightAscension = fixHour(dArcTan2(dCos(e) * dSin(l), dCos(l)) / 15.0)
        val equation = q / 15.0 - rightAscension
        val declination = dArcSin(dSin(e) * dSin(l))
        return Pair(declination, equation)
    }

    private fun midDay(julianDay: Double, hours: Double): Double {
        val equation = sunPosition(julianDay + hours / 24.0).second
        return fixHour(12.0 - equation)
    }

    private fun sunAngleTime(
        julianDay: Double,
        angle: Double,
        hours: Double,
        counterClockwise: Boolean,
    ): Pair<Double, Boolean> {
        val declination = sunPosition(julianDay + hours / 24.0).first
        val noon = midDay(julianDay, hours)
        val numerator = -dSin(angle) - dSin(declination) * dSin(LATITUDE)
        val denominator = dCos(declination) * dCos(LATITUDE)
        var cosine = numerator / denominator
        var clamped = false
        if (cosine.isNaN()) {
            cosine = -1.0
            clamped = true
        }
        if (cosine > 1) {
            cosine = 1.0
            clamped = true
        } else if (cosine < -1) {
            cosine = -1.0
            clamped = true
        }
        val hourAngle = dArcCos(cosine) / 15.0
        return Pair(noon + if (counterClockwise) -hourAngle else hourAngle, clamped)
    }

    private fun asrTime(julianDay: Double, hours: Double): Pair<Double, Boolean> {
        val declination = sunPosition(julianDay + hours / 24.0).first
        // Standard (Shafi'i) shadow factor 1, as in the phone apps.
        val angle = -dArcCot(1 + dTan(abs(LATITUDE - declination)))
        return sunAngleTime(julianDay, angle, hours, counterClockwise = false)
    }

    // MARK: - High latitude handling (angle-based rule, as in the phone apps)

    private fun applyHighLatitudeRule(times: SolarTimes): SolarTimes {
        val adjusted = SolarTimes(
            times.fajr, times.sunrise, times.dhuhr, times.asr,
            times.sunset, times.isha, false, false,
        )
        val night = timeDifference(times.sunset, times.sunrise)

        val fajrPortion = night * FAJR_ANGLE / 60.0
        val fajrGap = timeDifference(times.fajr, times.sunrise)
        if (times.fajrClamped || !times.fajr.isFinite() || fajrGap > fajrPortion) {
            adjusted.fajr = times.sunrise - fajrPortion
        }

        val ishaPortion = night * ISHA_ANGLE / 60.0
        val ishaGap = timeDifference(times.sunset, times.isha)
        if (times.ishaClamped || !times.isha.isFinite() || ishaGap > ishaPortion) {
            adjusted.isha = times.sunset + ishaPortion
        }
        return adjusted
    }

    // MARK: - Math helpers

    private fun julianDay(yearIn: Int, monthIn: Int, day: Int): Double {
        var y = yearIn.toDouble()
        var m = monthIn.toDouble()
        if (m <= 2) {
            y -= 1
            m += 12
        }
        val a = floor(y / 100.0)
        val b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (y + 4716)) +
            floor(30.6001 * (m + 1)) +
            day + b - 1524.5
    }

    private fun radians(degrees: Double) = degrees * PI / 180.0
    private fun degrees(radians: Double) = radians * 180.0 / PI
    private fun dSin(d: Double) = sin(radians(d))
    private fun dCos(d: Double) = cos(radians(d))
    private fun dTan(d: Double) = tan(radians(d))
    private fun dArcSin(x: Double) = degrees(asin(x))
    private fun dArcCos(x: Double) = degrees(acos(x))
    private fun dArcTan2(y: Double, x: Double) = degrees(atan2(y, x))
    private fun dArcCot(x: Double) = degrees(atan(1.0 / x))

    private fun fix(value: Double, modulus: Double): Double {
        val result = value - modulus * floor(value / modulus)
        return if (result < 0) result + modulus else result
    }

    private fun fixAngle(angle: Double) = fix(angle, 360.0)
    private fun fixHour(hour: Double) = fix(hour, 24.0)
    private fun timeDifference(start: Double, end: Double) = fixHour(end - start)

    /** Round to the nearest long, ties away from zero (Dart/Swift semantics). */
    private fun roundHalfAwayFromZero(x: Double): Long =
        if (x >= 0) floor(x + 0.5).toLong() else -floor(-x + 0.5).toLong()
}

/// Empirical calibration to Al Rashid Mosque's published monthly timetable
/// (alrashidfoundation.ca), fitted against every published day of
/// May-December 2026 (245 days) - identical constants to the phone apps.
private object MosqueCalibration {
    private fun harmonicBias(c: DoubleArray, dayOfYear: Int): Double {
        val w = 2.0 * PI * dayOfYear / 365.25
        var value = c[0] +
            c[1] * sin(w) +
            c[2] * cos(w) +
            c[3] * sin(2 * w) +
            c[4] * cos(2 * w)
        if (c.size > 6) {
            value += c[5] * sin(3 * w) + c[6] * cos(3 * w)
        }
        return value
    }

    fun sunriseBiasMinutes(dayOfYear: Int) = harmonicBias(
        doubleArrayOf(0.6475, -1.2198, -0.3848, 0.0040, -0.1097), dayOfYear
    )

    fun sunsetBiasMinutes(dayOfYear: Int) = harmonicBias(
        doubleArrayOf(1.7673, 2.1719, -0.2507, -0.0982, -0.3486), dayOfYear
    )

    fun fajrBiasMinutes(dayOfYear: Int) = harmonicBias(
        doubleArrayOf(-0.1420, 1.7990, 1.1200, 0.6390, -2.1960), dayOfYear
    )

    /** Correction ADDED to the raw Asr (fitted as mosque minus raw). */
    fun asrCorrectionMinutes(dayOfYear: Int) = harmonicBias(
        doubleArrayOf(0.8720, -1.6200, -0.2740, -0.8510, 0.1490, -0.4220, 0.3900),
        dayOfYear,
    )

    /** Correction ADDED to the raw Dhuhr (same convention as Asr). */
    fun dhuhrCorrectionMinutes(dayOfYear: Int) = harmonicBias(
        doubleArrayOf(0.8760, -0.3990, -0.1690, -0.6410, 0.1900, -0.3960, 0.3790),
        dayOfYear,
    )

    private fun piecewise(grid: Array<Pair<Double, Double>>, x: Double): Double {
        if (x <= grid[0].first) return grid[0].second
        if (x >= grid[grid.size - 1].first) return grid[grid.size - 1].second
        for (i in 0 until grid.size - 1) {
            if (x >= grid[i].first && x <= grid[i + 1].first) {
                val f = (x - grid[i].first) / (grid[i + 1].first - grid[i].first)
                return grid[i].second + f * (grid[i + 1].second - grid[i].second)
            }
        }
        return grid[grid.size - 1].second
    }

    /** Minutes from the calibrated Maghrib to Isha, by solar declination. */
    fun ishaIntervalMinutes(declination: Double) = piecewise(
        arrayOf(
            -24.0 to 122.1, -22.0 to 120.3, -20.0 to 116.7, -18.0 to 114.0,
            -16.0 to 111.5, -14.0 to 109.8, -12.0 to 108.2, -10.0 to 107.6,
            -8.0 to 107.0, -6.0 to 107.3, -4.0 to 107.7, -2.0 to 108.6,
            0.0 to 109.6, 2.0 to 105.0, 4.0 to 99.0, 6.0 to 93.6,
            8.0 to 87.8, 10.0 to 81.9, 12.0 to 76.3, 14.0 to 75.3,
            16.0 to 75.5, 18.0 to 75.3, 20.0 to 75.2, 22.0 to 74.9,
            24.0 to 74.8,
        ),
        declination,
    )

    /** Minutes from Fajr to Sunrise in the mosque's summer schedule
     *  (used when declination >= 10 degrees). */
    fun fajrSummerPortionMinutes(declination: Double) = piecewise(
        arrayOf(
            8.0 to 135.0, 10.0 to 140.2, 12.0 to 142.0, 14.0 to 136.2,
            16.0 to 131.1, 18.0 to 124.2, 20.0 to 118.2, 22.0 to 122.3,
            24.0 to 126.7,
        ),
        declination,
    )
}
