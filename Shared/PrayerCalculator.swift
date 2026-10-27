//
//  PrayerCalculator.swift
//  AlRashid Prayer Widget
//
//  SHARED FILE: Target Membership = AlRashidWidget + PrayerWidgetExtension
//
//  Self-contained, offline prayer-time calculator using the standard solar algorithm
//  (Julian day -> solar declination & equation of time -> hour angles).
//  Dhuhr = solar noon. Hour-angle cosines are clamped to [-1, 1] so high-latitude
//  summer nights never produce NaN; a configurable high-latitude rule then places
//  Fajr / Isha sensibly when twilight never reaches the configured depression angle.
//

import Foundation

struct PrayerCalculator: Sendable, Equatable {

    // MARK: - Configuration types

    struct Coordinates: Sendable, Equatable {
        var latitude: Double
        var longitude: Double
        var elevation: Double

        init(latitude: Double, longitude: Double, elevation: Double = 0) {
            self.latitude = latitude
            self.longitude = longitude
            self.elevation = elevation
        }
    }

    struct Method: Sendable, Equatable {
        var name: String
        var fajrAngle: Double
        var ishaAngle: Double
        var maghribMinutes: Double

        /// AlRashid Mosque profile, fitted to the mosque's published timetable:
        /// Fajr depression 18.25°, Isha depression 17.5° (used as the base for
        /// the calibrated Isha interval), Maghrib 5 minutes after sunset.
        static let alRashidMosque = Method(name: "AlRashid Mosque", fajrAngle: 18.25, ishaAngle: 17.5, maghribMinutes: 5)
    }

    enum AsrMethod: String, Sendable, Equatable {
        /// Shafi'i / Maliki / Hanbali — shadow factor 1.
        case standard
        /// Hanafi — shadow factor 2.
        case hanafi

        var shadowFactor: Double {
            switch self {
            case .standard: 1
            case .hanafi: 2
            }
        }
    }

    enum HighLatitudeRule: String, Sendable, Equatable {
        /// Keep the clamped astronomical result (Fajr/Isha fall back to solar midnight).
        case disabled
        /// Fajr/Isha no further than half the night from sunrise/sunset.
        case middleOfNight
        /// Fajr/Isha no further than one seventh of the night from sunrise/sunset.
        case seventhOfNight
        /// Fajr/Isha no further than (angle / 60) of the night from sunrise/sunset.
        case angleBased
    }

    struct Times: Sendable, Equatable {
        let fajr: Date
        let sunrise: Date
        let dhuhr: Date
        let asr: Date
        let maghrib: Date
        let isha: Date
    }

    // MARK: - Properties

    var coordinates: Coordinates
    var method: Method
    var asrMethod: AsrMethod
    var highLatitudeRule: HighLatitudeRule
    var timeZone: TimeZone

    init(
        coordinates: Coordinates,
        method: Method,
        asrMethod: AsrMethod,
        highLatitudeRule: HighLatitudeRule,
        timeZone: TimeZone
    ) {
        self.coordinates = coordinates
        self.method = method
        self.asrMethod = asrMethod
        self.highLatitudeRule = highLatitudeRule
        self.timeZone = timeZone
    }

    /// AlRashid Mosque, 13070 113 St NW, Edmonton — mosque timetable profile, Asr standard.
    static let alRashid = PrayerCalculator(
        coordinates: Coordinates(latitude: 53.591189, longitude: -113.515598),
        method: .alRashidMosque,
        asrMethod: .standard,
        highLatitudeRule: .angleBased,
        timeZone: TimeZone(identifier: "America/Edmonton") ?? .current
    )

    // MARK: - Public API

    /// Prayer times for the local calendar day (in `timeZone`) that contains `date`.
    /// All returned values are absolute instants rounded to the nearest minute.
    func times(for date: Date) -> Times {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2000
        let month = parts.month ?? 1
        let day = parts.day ?? 1

        // Julian day at local mean midnight.
        let julianDay = Self.julianDay(year: year, month: month, day: day)
            - coordinates.longitude / (15.0 * 24.0)

        var solar = SolarTimes(
            fajr: 5, sunrise: 6, dhuhr: 12, asr: 13,
            sunset: 18, isha: 18, fajrClamped: false, ishaClamped: false
        )
        for _ in 0..<2 {
            solar = computeSolarTimes(julianDay: julianDay, estimates: solar)
        }
        solar = applyHighLatitudeRule(to: solar)

        // Mosque timetable calibration. The raw solar results are adjusted to
        // reproduce Al Rashid Mosque's own published timetable (see
        // MosqueCalibration below): small seasonal corrections on Sunrise,
        // Sunset, Fajr, Asr and Dhuhr, Isha as a calibrated
        // interval after Maghrib, and — when the sun is high (declination
        // >= 10°) — Fajr as a calibrated interval before Sunrise instead of
        // the raw depression-angle time, matching the mosque's summer
        // schedule convention.
        let dayOfYear = localCalendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let declination = sunPosition(julianDay: julianDay + solar.dhuhr / 24.0).declination
        let calibratedSunrise = solar.sunrise - Self.MosqueCalibration.sunriseBiasMinutes(dayOfYear: dayOfYear) / 60.0
        let calibratedSunset = solar.sunset - Self.MosqueCalibration.sunsetBiasMinutes(dayOfYear: dayOfYear) / 60.0
        let calibratedMaghrib = calibratedSunset + method.maghribMinutes / 60.0
        let calibratedFajr: Double
        if declination >= 10 {
            calibratedFajr = calibratedSunrise - Self.MosqueCalibration.fajrSummerPortionMinutes(declination: declination) / 60.0
        } else {
            calibratedFajr = solar.fajr - Self.MosqueCalibration.fajrBiasMinutes(dayOfYear: dayOfYear) / 60.0
        }
        let calibratedIsha = calibratedMaghrib + Self.MosqueCalibration.ishaIntervalMinutes(declination: declination) / 60.0

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? timeZone
        let utcMidnight = utcCalendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? localCalendar.startOfDay(for: date)
        let longitudeHours = coordinates.longitude / 15.0

        // Local mean solar hours -> UTC hours -> absolute Date (DST-independent).
        func instant(_ localSolarHours: Double) -> Date {
            let utcHours = localSolarHours - longitudeHours
            return Self.roundedToMinute(utcMidnight.addingTimeInterval(utcHours * 3600.0))
        }

        return Times(
            fajr: instant(calibratedFajr),
            sunrise: instant(calibratedSunrise),
            dhuhr: instant(solar.dhuhr + Self.MosqueCalibration.dhuhrCorrectionMinutes(dayOfYear: dayOfYear) / 60.0),
            asr: instant(solar.asr + Self.MosqueCalibration.asrCorrectionMinutes(dayOfYear: dayOfYear) / 60.0),
            maghrib: instant(calibratedMaghrib),
            isha: instant(calibratedIsha)
        )
    }

    // MARK: - Solar computation

    private struct SolarTimes: Sendable {
        var fajr: Double
        var sunrise: Double
        var dhuhr: Double
        var asr: Double
        var sunset: Double
        var isha: Double
        var fajrClamped: Bool
        var ishaClamped: Bool
    }

    private var riseSetAngle: Double {
        0.833 + 0.0347 * max(coordinates.elevation, 0).squareRoot()
    }

    private func computeSolarTimes(julianDay: Double, estimates: SolarTimes) -> SolarTimes {
        let fajr = sunAngleTime(julianDay: julianDay, angle: method.fajrAngle, hours: estimates.fajr, counterClockwise: true)
        let sunrise = sunAngleTime(julianDay: julianDay, angle: riseSetAngle, hours: estimates.sunrise, counterClockwise: true)
        let dhuhr = midDay(julianDay: julianDay, hours: estimates.dhuhr)
        let asr = asrTime(julianDay: julianDay, hours: estimates.asr)
        let sunset = sunAngleTime(julianDay: julianDay, angle: riseSetAngle, hours: estimates.sunset, counterClockwise: false)
        let isha = sunAngleTime(julianDay: julianDay, angle: method.ishaAngle, hours: estimates.isha, counterClockwise: false)
        return SolarTimes(
            fajr: fajr.hours, sunrise: sunrise.hours, dhuhr: dhuhr, asr: asr.hours,
            sunset: sunset.hours, isha: isha.hours,
            fajrClamped: fajr.clamped, ishaClamped: isha.clamped
        )
    }

    /// Sun declination (degrees) and equation of time (hours) for a Julian day.
    private func sunPosition(julianDay: Double) -> (declination: Double, equation: Double) {
        let d = julianDay - 2451545.0
        let g = Self.fixAngle(357.529 + 0.98560028 * d)
        let q = Self.fixAngle(280.459 + 0.98564736 * d)
        let l = Self.fixAngle(q + 1.915 * Self.dSin(g) + 0.020 * Self.dSin(2 * g))
        let e = 23.439 - 0.00000036 * d
        let rightAscension = Self.fixHour(Self.dArcTan2(Self.dCos(e) * Self.dSin(l), Self.dCos(l)) / 15.0)
        let equation = q / 15.0 - rightAscension
        let declination = Self.dArcSin(Self.dSin(e) * Self.dSin(l))
        return (declination, equation)
    }

    /// Solar noon (Dhuhr) in local mean hours.
    private func midDay(julianDay: Double, hours: Double) -> Double {
        let equation = sunPosition(julianDay: julianDay + hours / 24.0).equation
        return Self.fixHour(12.0 - equation)
    }

    /// Time at which the sun reaches `angle` degrees below the horizon
    /// (negative angle = above the horizon), before (ccw) or after (cw) noon.
    private func sunAngleTime(julianDay: Double, angle: Double, hours: Double, counterClockwise: Bool) -> (hours: Double, clamped: Bool) {
        let declination = sunPosition(julianDay: julianDay + hours / 24.0).declination
        let noon = midDay(julianDay: julianDay, hours: hours)
        let latitude = coordinates.latitude
        let numerator = -Self.dSin(angle) - Self.dSin(declination) * Self.dSin(latitude)
        let denominator = Self.dCos(declination) * Self.dCos(latitude)
        var cosine = numerator / denominator
        var clamped = false
        if cosine.isNaN {
            cosine = -1
            clamped = true
        }
        if cosine > 1 {
            cosine = 1
            clamped = true
        } else if cosine < -1 {
            cosine = -1
            clamped = true
        }
        let hourAngle = Self.dArcCos(cosine) / 15.0
        return (noon + (counterClockwise ? -hourAngle : hourAngle), clamped)
    }

    private func asrTime(julianDay: Double, hours: Double) -> (hours: Double, clamped: Bool) {
        let declination = sunPosition(julianDay: julianDay + hours / 24.0).declination
        let angle = -Self.dArcCot(asrMethod.shadowFactor + Self.dTan(abs(coordinates.latitude - declination)))
        return sunAngleTime(julianDay: julianDay, angle: angle, hours: hours, counterClockwise: false)
    }

    // MARK: - Mosque timetable calibration

    /// Empirical calibration to AlRashid Mosque's published monthly timetable
    /// (alrashidfoundation.ca), fitted against every published day of
    /// May–December 2026 (245 days). The mosque does not use plain ISNA:
    /// its Fajr/Isha follow larger depression angles (18.25° / 17.5°) with
    /// its own generator's seasonal wobble, Maghrib is sunset + 5 minutes,
    /// and in summer it switches to fixed conventions (Isha 75 minutes
    /// after Maghrib; Fajr a near-constant interval before Sunrise).
    ///
    /// Model: seasonal harmonic curves for Sunrise, Sunset, (winter)
    /// Fajr, Asr and Dhuhr; Isha as a declination-indexed interval after
    /// the calibrated Maghrib; summer Fajr as a declination-indexed
    /// interval before Sunrise. Validated against the published
    /// timetable (exact to the minute after rounding): Dhuhr 98% of
    /// days, Asr 96%, Isha 83%, Sunrise 82%, Maghrib 73%, Fajr 63%;
    /// the remaining days are almost all a single minute off.
    private enum MosqueCalibration {
        /// Day-of-year harmonic curve (minutes) of the raw solar result:
        /// coefficients are [constant, sin, cos, sin2, cos2, (sin3, cos3)].
        private static func harmonicBias(_ c: [Double], dayOfYear: Int) -> Double {
            let w = 2.0 * Double.pi * Double(dayOfYear) / 365.25
            var value = c[0] + c[1] * sin(w) + c[2] * cos(w) + c[3] * sin(2 * w) + c[4] * cos(2 * w)
            if c.count > 6 {
                value += c[5] * sin(3 * w) + c[6] * cos(3 * w)
            }
            return value
        }

        static func sunriseBiasMinutes(dayOfYear: Int) -> Double {
            harmonicBias([0.6475, -1.2198, -0.3848, 0.0040, -0.1097], dayOfYear: dayOfYear)
        }

        static func sunsetBiasMinutes(dayOfYear: Int) -> Double {
            harmonicBias([1.7673, 2.1719, -0.2507, -0.0982, -0.3486], dayOfYear: dayOfYear)
        }

        static func fajrBiasMinutes(dayOfYear: Int) -> Double {
            harmonicBias([-0.1420, 1.7990, 1.1200, 0.6390, -2.1960], dayOfYear: dayOfYear)
        }

        /// Correction ADDED to the raw Asr (fitted as mosque minus raw, so
        /// unlike the biases above it is not subtracted).
        static func asrCorrectionMinutes(dayOfYear: Int) -> Double {
            harmonicBias([0.8720, -1.6200, -0.2740, -0.8510, 0.1490, -0.4220, 0.3900], dayOfYear: dayOfYear)
        }

        /// Correction ADDED to the raw Dhuhr (same convention as Asr).
        static func dhuhrCorrectionMinutes(dayOfYear: Int) -> Double {
            harmonicBias([0.8760, -0.3990, -0.1690, -0.6410, 0.1900, -0.3960, 0.3790], dayOfYear: dayOfYear)
        }

        /// Piecewise-linear lookup on a declination grid (degrees).
        private static func piecewise(_ grid: [(Double, Double)], _ x: Double) -> Double {
            if x <= grid[0].0 { return grid[0].1 }
            if x >= grid[grid.count - 1].0 { return grid[grid.count - 1].1 }
            for i in 0..<(grid.count - 1) where x >= grid[i].0 && x <= grid[i + 1].0 {
                let f = (x - grid[i].0) / (grid[i + 1].0 - grid[i].0)
                return grid[i].1 + f * (grid[i + 1].1 - grid[i].1)
            }
            return grid[grid.count - 1].1
        }

        /// Minutes from the calibrated Maghrib to Isha, by solar
        /// declination. Fitted on (mosque Isha − calibrated Maghrib) so it
        /// also absorbs the Maghrib fractional-minute offset.
        static func ishaIntervalMinutes(declination: Double) -> Double {
            piecewise([
                (-24, 122.1), (-22, 120.3), (-20, 116.7), (-18, 114.0),
                (-16, 111.5), (-14, 109.8), (-12, 108.2), (-10, 107.6),
                (-8, 107.0), (-6, 107.3), (-4, 107.7), (-2, 108.6),
                (0, 109.6), (2, 105.0), (4, 99.0), (6, 93.6),
                (8, 87.8), (10, 81.9), (12, 76.3), (14, 75.3),
                (16, 75.5), (18, 75.3), (20, 75.2), (22, 74.9), (24, 74.8)
            ], declination)
        }

        /// Minutes from Fajr to Sunrise in the mosque's summer schedule
        /// (used when declination >= 10°).
        static func fajrSummerPortionMinutes(declination: Double) -> Double {
            piecewise([
                (8, 135.0), (10, 140.2), (12, 142.0), (14, 136.2),
                (16, 131.1), (18, 124.2), (20, 118.2), (22, 122.3), (24, 126.7)
            ], declination)
        }
    }

    // MARK: - High latitude handling

    private func applyHighLatitudeRule(to times: SolarTimes) -> SolarTimes {
        guard highLatitudeRule != .disabled else { return times }
        var adjusted = times
        let night = Self.timeDifference(from: times.sunset, to: times.sunrise)

        let fajrPortion = nightPortion(angle: method.fajrAngle, night: night)
        let fajrGap = Self.timeDifference(from: times.fajr, to: times.sunrise)
        if times.fajrClamped || !times.fajr.isFinite || fajrGap > fajrPortion {
            adjusted.fajr = times.sunrise - fajrPortion
        }

        let ishaPortion = nightPortion(angle: method.ishaAngle, night: night)
        let ishaGap = Self.timeDifference(from: times.sunset, to: times.isha)
        if times.ishaClamped || !times.isha.isFinite || ishaGap > ishaPortion {
            adjusted.isha = times.sunset + ishaPortion
        }

        adjusted.fajrClamped = false
        adjusted.ishaClamped = false
        return adjusted
    }

    private func nightPortion(angle: Double, night: Double) -> Double {
        switch highLatitudeRule {
        case .disabled, .middleOfNight: return night / 2.0
        case .seventhOfNight: return night / 7.0
        case .angleBased: return night * angle / 60.0
        }
    }

    // MARK: - Math helpers

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year)
        var m = Double(month)
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = floor(y / 100.0)
        let b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + b - 1524.5
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }
    private static func degrees(_ radians: Double) -> Double { radians * 180.0 / .pi }
    private static func dSin(_ d: Double) -> Double { sin(radians(d)) }
    private static func dCos(_ d: Double) -> Double { cos(radians(d)) }
    private static func dTan(_ d: Double) -> Double { tan(radians(d)) }
    private static func dArcSin(_ x: Double) -> Double { degrees(asin(x)) }
    private static func dArcCos(_ x: Double) -> Double { degrees(acos(x)) }
    private static func dArcTan2(_ y: Double, _ x: Double) -> Double { degrees(atan2(y, x)) }
    private static func dArcCot(_ x: Double) -> Double { degrees(atan(1.0 / x)) }

    private static func fix(_ value: Double, _ modulus: Double) -> Double {
        let result = value - modulus * floor(value / modulus)
        return result < 0 ? result + modulus : result
    }

    private static func fixAngle(_ angle: Double) -> Double { fix(angle, 360.0) }
    private static func fixHour(_ hour: Double) -> Double { fix(hour, 24.0) }
    private static func timeDifference(from start: Double, to end: Double) -> Double { fixHour(end - start) }

    private static func roundedToMinute(_ date: Date) -> Date {
        let minutes = (date.timeIntervalSinceReferenceDate / 60.0).rounded()
        return Date(timeIntervalSinceReferenceDate: minutes * 60.0)
    }
}
