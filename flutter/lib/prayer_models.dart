// Prayer day model, next-prayer snapshot logic and formatting — a port of
// the iOS app's PrayerModels.swift behaviour. All times are computed in
// the mosque's time zone (America/Edmonton), like the iOS app.

import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'hijri_calendar.dart';
import 'prayer_calculator.dart';

class MosqueInfo {
  static const String name = 'Al Rashid Mosque';
  static const String address = '13070 113 St NW, Edmonton, AB';
  static const String directionsAddress = '13070 113 St NW, Edmonton, AB, Canada';
  static const String timeZoneIdentifier = 'America/Edmonton';
  static const int jumuahKhutbahHour = 13;
  static const int jumuahKhutbahMinute = 30;
  static const String websiteUrl = 'https://alrashidmosque.ca';
  static String get directionsUrl =>
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(directionsAddress)}';
}

/// America/Edmonton as an explicit transition table.
///
/// The tz database bundled with package:timezone (0.10.x) still carries
/// the pre-2026 Alberta rules — spring forward and fall back every year.
/// Alberta stays on Mountain Daylight Time permanently from the
/// March 2026 spring-forward: the mosque's published timetable and
/// current system tzdata both keep Edmonton at UTC-6 after that, with
/// no fall-back. The bundled database would put every time one hour
/// early from November 2026 on, so the location is built directly:
/// MST (UTC-7) / MDT (UTC-6) with transitions on 2025-03-09 (09:00 UTC),
/// 2025-11-02 (08:00 UTC) and 2026-03-08 (09:00 UTC, then MDT forever).
tz.Location edmontonLocation() {
  const mst = tz.TimeZone(-7 * 3600 * 1000, isDst: false, abbreviation: 'MST');
  const mdt = tz.TimeZone(-6 * 3600 * 1000, isDst: true, abbreviation: 'MDT');
  int ms(int year, int month, int day, int hourUtc) =>
      DateTime.utc(year, month, day, hourUtc).millisecondsSinceEpoch;
  return tz.Location(
    MosqueInfo.timeZoneIdentifier,
    [0, ms(2025, 3, 9, 9), ms(2025, 11, 2, 8), ms(2026, 3, 8, 9)],
    const [0, 1, 0, 1],
    const [mst, mdt],
  );
}

enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PrayerInfo on Prayer {
  String get displayName => switch (this) {
        Prayer.fajr => 'Fajr',
        Prayer.sunrise => 'Sunrise',
        Prayer.dhuhr => 'Dhuhr',
        Prayer.asr => 'Asr',
        Prayer.maghrib => 'Maghrib',
        Prayer.isha => 'Isha',
      };

  /// Sunrise is shown in the schedule but is not a prayer
  /// (no Iqamah, never "next prayer").
  bool get isPrayer => this != Prayer.sunrise;
}

/// Iqamah offsets in minutes after Adhan (Al Rashid defaults, same as iOS):
/// Fajr +20, Dhuhr +10, Asr +10, Maghrib +5, Isha +10.
int? iqamahOffsetMinutes(Prayer prayer) => switch (prayer) {
      Prayer.fajr => 20,
      Prayer.sunrise => null,
      Prayer.dhuhr => 10,
      Prayer.asr => 10,
      Prayer.maghrib => 5,
      Prayer.isha => 10,
    };

class PrayerSlot {
  final Prayer prayer;
  final tz.TZDateTime adhan;
  final tz.TZDateTime? iqamah;
  final bool isJumuah;
  const PrayerSlot({
    required this.prayer,
    required this.adhan,
    required this.iqamah,
    required this.isJumuah,
  });

  String get name => isJumuah ? "Jumu'ah" : prayer.displayName;
  String get iqamahLabel => isJumuah ? 'Khutbah' : 'Iqamah';
}

class PrayerDay {
  /// Start of the local (America/Edmonton) calendar day.
  final tz.TZDateTime date;
  final Map<Prayer, tz.TZDateTime> adhanTimes;
  final Map<Prayer, tz.TZDateTime> iqamahTimes;
  final String hijriDate;
  final bool isFriday;
  final tz.TZDateTime? jumuahKhutbah;

  const PrayerDay({
    required this.date,
    required this.adhanTimes,
    required this.iqamahTimes,
    required this.hijriDate,
    required this.isFriday,
    required this.jumuahKhutbah,
  });

  tz.TZDateTime adhan(Prayer prayer) => adhanTimes[prayer]!;
  tz.TZDateTime? iqamah(Prayer prayer) => iqamahTimes[prayer];

  /// All six rows. On Fridays the Dhuhr row becomes Jumu'ah with the
  /// Khutbah time in the Iqamah column.
  List<PrayerSlot> get slots => Prayer.values.map((prayer) {
        final jumuah = isFriday && prayer == Prayer.dhuhr;
        final second =
            jumuah ? (jumuahKhutbah ?? iqamah(prayer)) : iqamah(prayer);
        return PrayerSlot(
          prayer: prayer,
          adhan: adhan(prayer),
          iqamah: second,
          isJumuah: jumuah,
        );
      }).toList();

  /// The five prayers (no Sunrise) — used for "next prayer" logic.
  List<PrayerSlot> get prayerSlots =>
      slots.where((s) => s.prayer.isPrayer).toList();
}

class PrayerSnapshot {
  final tz.TZDateTime date;
  final PrayerDay day;
  final PrayerSlot next;
  final tz.TZDateTime previousBoundary;
  final bool isShowingTomorrow;

  const PrayerSnapshot({
    required this.date,
    required this.day,
    required this.next,
    required this.previousBoundary,
    required this.isShowingTomorrow,
  });

  bool isNext(PrayerSlot slot) =>
      slot.prayer == next.prayer && slot.adhan == next.adhan;

  double get progress {
    final total = next.adhan.difference(previousBoundary).inSeconds;
    final done = date.difference(previousBoundary).inSeconds;
    if (total <= 0) return 0;
    return (done / total).clamp(0.0, 1.0);
  }
}

class PrayerProvider {
  static tz.Location get _edmonton => edmontonLocation();

  static tz.TZDateTime _startOfDay(tz.TZDateTime t) =>
      tz.TZDateTime(_edmonton, t.year, t.month, t.day);

  /// Civil day arithmetic (safe across DST transitions, like Calendar).
  static tz.TZDateTime _plusDays(tz.TZDateTime startOfDay, int days) =>
      tz.TZDateTime(
          _edmonton, startOfDay.year, startOfDay.month, startOfDay.day + days);

  /// Computes the full PrayerDay for the Edmonton civil day containing [date].
  static PrayerDay computeDay(tz.TZDateTime date) {
    final start = _startOfDay(date);
    final times =
        AlRashidCalculator.timesFor(start.year, start.month, start.day);
    tz.TZDateTime local(DateTime utc) => tz.TZDateTime.from(utc, _edmonton);

    final adhanTimes = <Prayer, tz.TZDateTime>{
      Prayer.fajr: local(times.fajr),
      Prayer.sunrise: local(times.sunrise),
      Prayer.dhuhr: local(times.dhuhr),
      Prayer.asr: local(times.asr),
      Prayer.maghrib: local(times.maghrib),
      Prayer.isha: local(times.isha),
    };
    final iqamahTimes = <Prayer, tz.TZDateTime>{};
    for (final prayer in Prayer.values) {
      final offset = iqamahOffsetMinutes(prayer);
      if (offset != null) {
        iqamahTimes[prayer] = adhanTimes[prayer]!.add(Duration(minutes: offset));
      }
    }

    final isFriday = start.weekday == DateTime.friday;
    final khutbah = isFriday
        ? tz.TZDateTime(_edmonton, start.year, start.month, start.day,
            MosqueInfo.jumuahKhutbahHour, MosqueInfo.jumuahKhutbahMinute)
        : null;

    return PrayerDay(
      date: start,
      adhanTimes: adhanTimes,
      iqamahTimes: iqamahTimes,
      hijriDate:
          UmmAlQuraCalendar.hijriString(start.year, start.month, start.day),
      isFriday: isFriday,
      jumuahKhutbah: khutbah,
    );
  }

  static PrayerDay dayFor(tz.TZDateTime date) => computeDay(date);

  /// State at an arbitrary instant: the next upcoming prayer and the day
  /// whose schedule should be displayed (switches to tomorrow after Isha).
  /// [enabled] (v1.0.5) optionally restricts which times the countdown
  /// moves to — the user's Widget Countdown choices from Settings; it may
  /// include Sunrise. Null means the five prayers, as before.
  static PrayerSnapshot snapshot(tz.TZDateTime now, {Set<Prayer>? enabled}) {
    final start = _startOfDay(now);
    final days = <PrayerDay>[
      for (var offset = -1; offset <= 2; offset++)
        computeDay(_plusDays(start, offset)),
    ];
    final candidates = <(PrayerDay, PrayerSlot)>[
      for (final day in days)
        for (final slot in day.slots)
          if (enabled == null
              ? slot.prayer.isPrayer
              : enabled.contains(slot.prayer)) (day, slot),
    ];
    for (var i = 0; i < candidates.length; i++) {
      final (day, slot) = candidates[i];
      if (slot.adhan.isAfter(now)) {
        final previous = i > 0
            ? candidates[i - 1].$2.adhan
            : slot.adhan.subtract(const Duration(hours: 6));
        return PrayerSnapshot(
          date: now,
          day: day,
          next: slot,
          previousBoundary: previous,
          isShowingTomorrow: day.date.isAfter(start),
        );
      }
    }
    // Defensive fallback: tomorrow's Fajr is always after `now`.
    final fallbackDay = computeDay(_plusDays(start, 1));
    final fallbackSlot = fallbackDay.prayerSlots.first;
    return PrayerSnapshot(
      date: now,
      day: fallbackDay,
      next: fallbackSlot,
      previousBoundary: now,
      isShowingTomorrow: true,
    );
  }
}

// MARK: - Formatting (always in the mosque's time zone)

class PrayerFormat {
  /// "1:18 PM"
  static String time(tz.TZDateTime date) => DateFormat.jm('en_US').format(date);

  /// "Tuesday, October 27, 2026"
  static String longDate(tz.TZDateTime date) =>
      DateFormat('EEEE, MMMM d, y', 'en_US').format(date);

  /// "Tue, Oct 27"
  static String shortDate(tz.TZDateTime date) =>
      DateFormat('EEE, MMM d', 'en_US').format(date);

  /// Jumu'ah Khutbah time (1:30 PM local).
  static String khutbahTime() {
    final loc = edmontonLocation();
    final t = tz.TZDateTime(loc, 2026, 1, 2,
        MosqueInfo.jumuahKhutbahHour, MosqueInfo.jumuahKhutbahMinute);
    return time(t);
  }

  /// "2:14:33" countdown text.
  static String countdown(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
