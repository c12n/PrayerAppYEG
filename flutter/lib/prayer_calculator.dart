// Self-contained, offline prayer-time calculator using the standard solar
// algorithm (Julian day -> solar declination & equation of time -> hour
// angles), calibrated to Al Rashid Mosque Edmonton's published timetable.
//
// This is a faithful port of the iOS app's PrayerCalculator.swift — same
// solar math, same mosque calibration (fitted against every published day
// of May–December 2026, 245 days). Validated exact-to-the-minute rates
// against the mosque timetable: Dhuhr 98%, Asr 96%, Isha 83%, Sunrise 82%,
// Maghrib 73%, Fajr 63%; remaining days are almost all a single minute off.
//
// Times are computed for a Gregorian civil date as observed in
// America/Edmonton and returned as UTC instants (DateTime in UTC),
// rounded to the nearest minute — identical semantics to the iOS app.

import 'dart:math' as math;

class PrayerTimesResult {
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;
  const PrayerTimesResult({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });
}

class _SolarTimes {
  double fajr;
  double sunrise;
  double dhuhr;
  double asr;
  double sunset;
  double isha;
  bool fajrClamped;
  bool ishaClamped;
  _SolarTimes(this.fajr, this.sunrise, this.dhuhr, this.asr, this.sunset,
      this.isha, this.fajrClamped, this.ishaClamped);
}

class AlRashidCalculator {
  static const double latitude = 53.591189;
  static const double longitude = -113.515598;
  static const double fajrAngle = 18.25;
  static const double ishaAngle = 17.5;
  static const double maghribMinutes = 5.0;

  static double get _riseSetAngle => 0.833; // elevation 0

  /// Prayer times for the Edmonton civil date (year, month, day).
  static PrayerTimesResult timesFor(int year, int month, int day) {
    final julianDay = _julianDay(year, month, day) - longitude / (15.0 * 24.0);

    var solar = _SolarTimes(5, 6, 12, 13, 18, 18, false, false);
    for (var i = 0; i < 2; i++) {
      solar = _computeSolarTimes(julianDay, solar);
    }
    solar = _applyHighLatitudeRule(solar);

    final dayOfYear =
        DateTime.utc(year, month, day).difference(DateTime.utc(year, 1, 1)).inDays + 1;
    final declination = _sunPosition(julianDay + solar.dhuhr / 24.0).$1;
    final calibratedSunrise =
        solar.sunrise - _MosqueCalibration.sunriseBiasMinutes(dayOfYear) / 60.0;
    final calibratedSunset =
        solar.sunset - _MosqueCalibration.sunsetBiasMinutes(dayOfYear) / 60.0;
    final calibratedMaghrib = calibratedSunset + maghribMinutes / 60.0;
    final double calibratedFajr;
    if (declination >= 10) {
      calibratedFajr = calibratedSunrise -
          _MosqueCalibration.fajrSummerPortionMinutes(declination) / 60.0;
    } else {
      calibratedFajr =
          solar.fajr - _MosqueCalibration.fajrBiasMinutes(dayOfYear) / 60.0;
    }
    final calibratedIsha = calibratedMaghrib +
        _MosqueCalibration.ishaIntervalMinutes(declination) / 60.0;

    final utcMidnight = DateTime.utc(year, month, day);
    final longitudeHours = longitude / 15.0;

    DateTime instant(double localSolarHours) {
      final utcHours = localSolarHours - longitudeHours;
      final t = utcMidnight.add(Duration(
          microseconds: (utcHours * 3600.0 * 1000000).round()));
      // Round to the nearest minute (ties away from zero, like Swift).
      final ms = t.millisecondsSinceEpoch;
      final rounded = (ms / 60000.0).round() * 60000;
      return DateTime.fromMillisecondsSinceEpoch(rounded, isUtc: true);
    }

    return PrayerTimesResult(
      fajr: instant(calibratedFajr),
      sunrise: instant(calibratedSunrise),
      dhuhr: instant(
          solar.dhuhr + _MosqueCalibration.dhuhrCorrectionMinutes(dayOfYear) / 60.0),
      asr: instant(
          solar.asr + _MosqueCalibration.asrCorrectionMinutes(dayOfYear) / 60.0),
      maghrib: instant(calibratedMaghrib),
      isha: instant(calibratedIsha),
    );
  }

  // MARK: - Solar computation

  static _SolarTimes _computeSolarTimes(double julianDay, _SolarTimes est) {
    final fajr =
        _sunAngleTime(julianDay, fajrAngle, est.fajr, counterClockwise: true);
    final sunrise = _sunAngleTime(julianDay, _riseSetAngle, est.sunrise,
        counterClockwise: true);
    final dhuhr = _midDay(julianDay, est.dhuhr);
    final asr = _asrTime(julianDay, est.asr);
    final sunset = _sunAngleTime(julianDay, _riseSetAngle, est.sunset,
        counterClockwise: false);
    final isha =
        _sunAngleTime(julianDay, ishaAngle, est.isha, counterClockwise: false);
    return _SolarTimes(fajr.$1, sunrise.$1, dhuhr, asr.$1, sunset.$1, isha.$1,
        fajr.$2, isha.$2);
  }

  /// (declination degrees, equation of time hours) for a Julian day.
  static (double, double) _sunPosition(double julianDay) {
    final d = julianDay - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _dSin(g) + 0.020 * _dSin(2 * g));
    final e = 23.439 - 0.00000036 * d;
    final rightAscension =
        _fixHour(_dArcTan2(_dCos(e) * _dSin(l), _dCos(l)) / 15.0);
    final equation = q / 15.0 - rightAscension;
    final declination = _dArcSin(_dSin(e) * _dSin(l));
    return (declination, equation);
  }

  static double _midDay(double julianDay, double hours) {
    final equation = _sunPosition(julianDay + hours / 24.0).$2;
    return _fixHour(12.0 - equation);
  }

  static (double, bool) _sunAngleTime(
      double julianDay, double angle, double hours,
      {required bool counterClockwise}) {
    final declination = _sunPosition(julianDay + hours / 24.0).$1;
    final noon = _midDay(julianDay, hours);
    final numerator =
        -_dSin(angle) - _dSin(declination) * _dSin(latitude);
    final denominator = _dCos(declination) * _dCos(latitude);
    var cosine = numerator / denominator;
    var clamped = false;
    if (cosine.isNaN) {
      cosine = -1;
      clamped = true;
    }
    if (cosine > 1) {
      cosine = 1;
      clamped = true;
    } else if (cosine < -1) {
      cosine = -1;
      clamped = true;
    }
    final hourAngle = _dArcCos(cosine) / 15.0;
    return (noon + (counterClockwise ? -hourAngle : hourAngle), clamped);
  }

  static (double, bool) _asrTime(double julianDay, double hours) {
    final declination = _sunPosition(julianDay + hours / 24.0).$1;
    // Standard (Shafi'i) shadow factor 1, as in the iOS app.
    final angle = -_dArcCot(1 + _dTan((latitude - declination).abs()));
    return _sunAngleTime(julianDay, angle, hours, counterClockwise: false);
  }

  // MARK: - High latitude handling (angle-based rule, as in the iOS app)

  static _SolarTimes _applyHighLatitudeRule(_SolarTimes times) {
    final adjusted = _SolarTimes(times.fajr, times.sunrise, times.dhuhr,
        times.asr, times.sunset, times.isha, false, false);
    final night = _timeDifference(times.sunset, times.sunrise);

    final fajrPortion = night * fajrAngle / 60.0;
    final fajrGap = _timeDifference(times.fajr, times.sunrise);
    if (times.fajrClamped || !times.fajr.isFinite || fajrGap > fajrPortion) {
      adjusted.fajr = times.sunrise - fajrPortion;
    }

    final ishaPortion = night * ishaAngle / 60.0;
    final ishaGap = _timeDifference(times.sunset, times.isha);
    if (times.ishaClamped || !times.isha.isFinite || ishaGap > ishaPortion) {
      adjusted.isha = times.sunset + ishaPortion;
    }
    return adjusted;
  }

  // MARK: - Math helpers

  static double _julianDay(int year, int month, int day) {
    var y = year.toDouble();
    var m = month.toDouble();
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100.0).floorToDouble();
    final b = 2 - a + (a / 4.0).floorToDouble();
    return (365.25 * (y + 4716)).floorToDouble() +
        (30.6001 * (m + 1)).floorToDouble() +
        day +
        b -
        1524.5;
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;
  static double _degrees(double radians) => radians * 180.0 / math.pi;
  static double _dSin(double d) => math.sin(_radians(d));
  static double _dCos(double d) => math.cos(_radians(d));
  static double _dTan(double d) => math.tan(_radians(d));
  static double _dArcSin(double x) => _degrees(math.asin(x));
  static double _dArcCos(double x) => _degrees(math.acos(x));
  static double _dArcTan2(double y, double x) => _degrees(math.atan2(y, x));
  static double _dArcCot(double x) => _degrees(math.atan(1.0 / x));

  static double _fix(double value, double modulus) {
    final result = value - modulus * (value / modulus).floorToDouble();
    return result < 0 ? result + modulus : result;
  }

  static double _fixAngle(double angle) => _fix(angle, 360.0);
  static double _fixHour(double hour) => _fix(hour, 24.0);
  static double _timeDifference(double start, double end) =>
      _fixHour(end - start);
}

/// Empirical calibration to Al Rashid Mosque's published monthly timetable
/// (alrashidfoundation.ca), fitted against every published day of
/// May–December 2026 (245 days) — identical constants to the iOS app.
class _MosqueCalibration {
  static double _harmonicBias(List<double> c, int dayOfYear) {
    final w = 2.0 * math.pi * dayOfYear / 365.25;
    var value = c[0] +
        c[1] * math.sin(w) +
        c[2] * math.cos(w) +
        c[3] * math.sin(2 * w) +
        c[4] * math.cos(2 * w);
    if (c.length > 6) {
      value += c[5] * math.sin(3 * w) + c[6] * math.cos(3 * w);
    }
    return value;
  }

  static double sunriseBiasMinutes(int dayOfYear) => _harmonicBias(
      const [0.6475, -1.2198, -0.3848, 0.0040, -0.1097], dayOfYear);

  static double sunsetBiasMinutes(int dayOfYear) => _harmonicBias(
      const [1.7673, 2.1719, -0.2507, -0.0982, -0.3486], dayOfYear);

  static double fajrBiasMinutes(int dayOfYear) => _harmonicBias(
      const [-0.1420, 1.7990, 1.1200, 0.6390, -2.1960], dayOfYear);

  /// Correction ADDED to the raw Asr (fitted as mosque minus raw).
  static double asrCorrectionMinutes(int dayOfYear) => _harmonicBias(
      const [0.8720, -1.6200, -0.2740, -0.8510, 0.1490, -0.4220, 0.3900],
      dayOfYear);

  /// Correction ADDED to the raw Dhuhr (same convention as Asr).
  static double dhuhrCorrectionMinutes(int dayOfYear) => _harmonicBias(
      const [0.8760, -0.3990, -0.1690, -0.6410, 0.1900, -0.3960, 0.3790],
      dayOfYear);

  static double _piecewise(List<(double, double)> grid, double x) {
    if (x <= grid[0].$1) return grid[0].$2;
    if (x >= grid[grid.length - 1].$1) return grid[grid.length - 1].$2;
    for (var i = 0; i < grid.length - 1; i++) {
      if (x >= grid[i].$1 && x <= grid[i + 1].$1) {
        final f = (x - grid[i].$1) / (grid[i + 1].$1 - grid[i].$1);
        return grid[i].$2 + f * (grid[i + 1].$2 - grid[i].$2);
      }
    }
    return grid[grid.length - 1].$2;
  }

  /// Minutes from the calibrated Maghrib to Isha, by solar declination.
  static double ishaIntervalMinutes(double declination) => _piecewise(const [
        (-24, 122.1),
        (-22, 120.3),
        (-20, 116.7),
        (-18, 114.0),
        (-16, 111.5),
        (-14, 109.8),
        (-12, 108.2),
        (-10, 107.6),
        (-8, 107.0),
        (-6, 107.3),
        (-4, 107.7),
        (-2, 108.6),
        (0, 109.6),
        (2, 105.0),
        (4, 99.0),
        (6, 93.6),
        (8, 87.8),
        (10, 81.9),
        (12, 76.3),
        (14, 75.3),
        (16, 75.5),
        (18, 75.3),
        (20, 75.2),
        (22, 74.9),
        (24, 74.8)
      ], declination);

  /// Minutes from Fajr to Sunrise in the mosque's summer schedule
  /// (used when declination >= 10°).
  static double fajrSummerPortionMinutes(double declination) =>
      _piecewise(const [
        (8, 135.0),
        (10, 140.2),
        (12, 142.0),
        (14, 136.2),
        (16, 131.1),
        (18, 124.2),
        (20, 118.2),
        (22, 122.3),
        (24, 126.7)
      ], declination);
}
