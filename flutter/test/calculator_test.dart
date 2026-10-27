// Calculator validation: the Dart port must reproduce, to the minute, the
// reference implementation of the shipped iOS calculator (same solar math
// and mosque calibration constants) across seasons, plus the Umm al-Qura
// Hijri conversion. Expected values were generated from that reference
// implementation and spot-checked against Al Rashid Mosque's published
// timetable (2026-10-27: Fajr 6:25, Sunrise 8:23, Dhuhr 1:19 PM,
// Asr 3:43 PM, Maghrib 6:16 PM, Isha 8:05 PM — all reproduced exactly).

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:alrashidwidget/hijri_calendar.dart';
import 'package:alrashidwidget/prayer_calculator.dart';

void main() {
  tz_data.initializeTimeZones();
  final edmonton = tz.getLocation('America/Edmonton');

  int minutesOfDay(DateTime utc) {
    final local = tz.TZDateTime.from(utc, edmonton);
    return local.hour * 60 + local.minute;
  }

  // [fajr, sunrise, dhuhr, asr, maghrib, isha] as Edmonton minutes of day.
  const expected = <String, List<int>>{
    '2026-05-01': [226, 359, 813, 1057, 1266, 1341],
    '2026-05-15': [212, 333, 812, 1067, 1290, 1366],
    '2026-06-21': [178, 304, 817, 1084, 1331, 1405],
    '2026-07-04': [187, 311, 819, 1085, 1328, 1403],
    '2026-08-01': [223, 348, 822, 1074, 1294, 1370],
    '2026-09-21': [316, 436, 808, 1006, 1180, 1288],
    '2026-10-27': [385, 503, 799, 943, 1096, 1205],
    '2026-11-17': [420, 543, 801, 914, 1058, 1174],
    '2026-12-21': [457, 588, 814, 903, 1040, 1162],
    '2027-01-15': [454, 583, 824, 926, 1068, 1187],
    '2027-06-21': [178, 303, 817, 1084, 1331, 1405],
    '2025-03-01': [319, 441, 766, 932, 1094, 1201],
    '2026-02-10': [360, 483, 768, 904, 1057, 1167],
  };

  test('prayer calculator reproduces reference times to the minute', () {
    expected.forEach((date, want) {
      final parts = date.split('-').map(int.parse).toList();
      final t = AlRashidCalculator.timesFor(parts[0], parts[1], parts[2]);
      final got = [
        minutesOfDay(t.fajr),
        minutesOfDay(t.sunrise),
        minutesOfDay(t.dhuhr),
        minutesOfDay(t.asr),
        minutesOfDay(t.maghrib),
        minutesOfDay(t.isha),
      ];
      expect(got, want, reason: date);
    });
  });

  test('Umm al-Qura Hijri conversion', () {
    expect(UmmAlQuraCalendar.hijriString(2026, 10, 27), '16 Jumada I 1448 AH');
    expect(UmmAlQuraCalendar.hijriString(2026, 10, 28), '17 Jumada I 1448 AH');
    expect(UmmAlQuraCalendar.hijriString(2024, 1, 1), '19 Jumada II 1445 AH');
    expect(UmmAlQuraCalendar.hijriString(2030, 6, 15), '14 Safar 1452 AH');
    expect(UmmAlQuraCalendar.hijriString(2027, 1, 1), '23 Rajab 1448 AH');
  });
}
