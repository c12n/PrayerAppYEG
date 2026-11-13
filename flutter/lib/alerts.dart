// Adhan notification scheduler (v1.5) — the Android counterpart of the
// iOS app's AdhanNotifications (AlRashidWidgetApp.swift). The plan for
// the next 7 days is computed here in Dart (same rules as iOS) and
// handed to the native side over the 'alrashid/alerts' MethodChannel;
// Alerts.kt persists it and chains AlarmManager alarms, so alerts fire
// even when the app is closed. iOS caps pending requests at 64 — the
// same budget is kept here: the earliest 60 items win.

import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_settings.dart';
import 'prayer_models.dart';
import 'strings.dart';

/// One scheduled notification in the plan sent to the native side.
class PlannedNotification {
  /// Stable id: epoch seconds of the EVENT time (the Adhan, or the
  /// Khutbah for the Jumu'ah reminder) plus a per-type offset, so the
  /// adhan alert, its reminder and the Jumu'ah reminder never collide.
  final int id;

  /// When the notification fires, epoch milliseconds.
  final int epochMillis;
  final String title;
  final String body;

  /// Alert sound name (v1.8.0): one of alertSoundNames ('default',
  /// 'silent', 'classic', 'makkah', 'madinah', 'quds', 'alafasy',
  /// 'makkahfajr' as of v3.0.2). The native side posts on the
  /// notification channel for this sound. Reminders keep the
  /// default sound, like iOS.
  final String sound;

  const PlannedNotification({
    required this.id,
    required this.epochMillis,
    required this.title,
    required this.body,
    this.sound = 'default',
  });

  Map<String, dynamic> toChannelMap() => {
        'id': id,
        'epochMillis': epochMillis,
        'title': title,
        'body': body,
        'sound': sound,
      };
}

class AlertScheduler {
  static const _channel = MethodChannel('alrashid/alerts');

  /// iOS allows 64 pending requests; keep the same budget (60).
  static const maxScheduled = 60;

  static const _reminderIdOffset = 100000000;
  static const _jumuahIdOffset = 200000000;
  static const _fastingIdOffset = 300000000;

  static int _epochSeconds(tz.TZDateTime t) =>
      t.millisecondsSinceEpoch ~/ 1000;

  /// Builds the next-7-days plan, mirroring iOS `reschedule()`:
  /// an Adhan alert for every enabled time, a pre-prayer reminder
  /// (the five prayers only — no Sunrise, no Jumu'ah slot) and the
  /// Friday reminder one hour before the Khutbah. Only future fire
  /// times are kept; the result is sorted by fire time and capped.
  static List<PlannedNotification> buildPlan(
      AppSettings settings, tz.TZDateTime now) {
    final items = <PlannedNotification>[];
    if (!settings.notificationsEnabled) return items;
    final lead = settings.reminderLeadMinutes;
    final loc = edmontonLocation();
    final todayStart = tz.TZDateTime(loc, now.year, now.month, now.day);

    for (var offset = 0; offset < 7; offset++) {
      final dayStart = tz.TZDateTime(
          loc, todayStart.year, todayStart.month, todayStart.day + offset);
      final day = PrayerProvider.computeDay(dayStart);

      for (final slot in day.slots) {
        if (!slot.adhan.isAfter(now)) continue;
        final enabled = settings.alerts[slot.prayer] ??
            (slot.prayer != Prayer.sunrise);
        if (!enabled) continue;

        final String title;
        final String body;
        if (slot.prayer == Prayer.sunrise) {
          title = S.f('mosqueTitle',
              {'name': slot.name, 'mosque': MosqueInfo.name});
          body = S.f('sunriseBody', {'time': PrayerFormat.time(slot.adhan)});
        } else if (slot.isJumuah) {
          title = S.f('mosqueTitle',
              {'name': slot.name, 'mosque': MosqueInfo.name});
          body = S.f('labelAtTime', {
            'label': slot.iqamahLabel,
            'time': PrayerFormat.time(slot.iqamah ?? slot.adhan),
          });
        } else {
          title = S.f(
              'notifTitle', {'name': slot.name, 'mosque': MosqueInfo.name});
          body = slot.iqamah != null
              ? S.f('labelAtTime', {
                  'label': slot.iqamahLabel,
                  'time': PrayerFormat.time(slot.iqamah!),
                })
              : S.f('adhanAtTime', {'time': PrayerFormat.time(slot.adhan)});
        }
        // Silence-next (v2.0.0): drop exactly this one Adhan alert
        // when the one-shot flag names it (Quick Settings tile /
        // in-app button). Its reminder and later alerts stay.
        if (_epochSeconds(slot.adhan) != settings.silenceNextEpochSeconds) {
          items.add(PlannedNotification(
          id: _epochSeconds(slot.adhan),
          epochMillis: slot.adhan.millisecondsSinceEpoch,
          title: title,
          body: body,
          // Per-prayer sound override wins, else the app sound (v1.8.0).
          // Jumu'ah slots carry prayer == dhuhr, like iOS.
          sound: settings.effectiveSound(slot.prayer),
          ));
        }

        // Pre-prayer reminder: the five prayers only — Sunrise has
        // none, and the Jumu'ah slot has its own reminder below.
        if (settings.reminderEnabled &&
            !settings.minimalMode &&
            slot.prayer.isPrayer &&
            !slot.isJumuah) {
          final fire = slot.adhan.subtract(Duration(minutes: lead));
          if (fire.isAfter(now)) {
            items.add(PlannedNotification(
              id: _epochSeconds(slot.adhan) + _reminderIdOffset,
              epochMillis: fire.millisecondsSinceEpoch,
              title: S.f('mosqueTitle',
                  {'name': slot.name, 'mosque': MosqueInfo.name}),
              body: S.f('inMinutes',
                  {'name': slot.name, 'minutes': '$lead'}),
            ));
          }
        }
      }

      // Sunnah fasting reminder (v2.0.0): 20:00 the evening before
      // each selected fasting day, with that day's Suhoor/Iftar.
      if (FastingDays.isFastingDay(
          day, settings.fastingMonThu, settings.fastingWhiteDays)) {
        final fire = tz.TZDateTime(
            loc, dayStart.year, dayStart.month, dayStart.day - 1, 20);
        if (fire.isAfter(now)) {
          items.add(PlannedNotification(
            id: _epochSeconds(dayStart) + _fastingIdOffset,
            epochMillis: fire.millisecondsSinceEpoch,
            title: S.f('mosqueTitle',
                {'name': S.t('fastingDay'), 'mosque': MosqueInfo.name}),
            body: S.f('fastingReminderBody', {
              'time1': PrayerFormat.time(day.adhan(Prayer.fajr)),
              'time2': PrayerFormat.time(day.adhan(Prayer.maghrib)),
            }),
          ));
        }
      }

      // Jumu'ah reminder: one hour before the Friday Khutbah.
      final khutbah = day.jumuahKhutbah;
      if (day.isFriday &&
          settings.jumuahReminderEnabled &&
          !settings.minimalMode &&
          khutbah != null) {
        final fire = khutbah.subtract(const Duration(minutes: 60));
        if (fire.isAfter(now)) {
          items.add(PlannedNotification(
            id: _epochSeconds(khutbah) + _jumuahIdOffset,
            epochMillis: fire.millisecondsSinceEpoch,
            title: S.f('mosqueTitle',
                {'name': PrayerInfo.jumuahName(), 'mosque': MosqueInfo.name}),
            body: S.f(
                'jumuahReminderNotif', {'time': PrayerFormat.time(khutbah)}),
          ));
        }
      }
    }

    items.sort((a, b) => a.epochMillis.compareTo(b.epochMillis));
    return items.take(maxScheduled).toList();
  }

  /// Asks the native side for the POST_NOTIFICATIONS runtime
  /// permission (Android 13+; immediately true before that).
  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Recomputes the plan and sends it to the native side (or cancels
  /// everything when the master switch is off). Called on app start,
  /// on resume, and after any alert-related settings change.
  static Future<void> refresh(AppSettings settings,
      {bool askPermission = false}) async {
    try {
      if (!settings.notificationsEnabled) {
        await _channel.invokeMethod('cancelAll');
        return;
      }
      if (askPermission) await requestPermission();
      final plan = buildPlan(settings, tz.TZDateTime.now(edmontonLocation()));
      await _channel.invokeMethod('schedule', {
        'items': plan.map((n) => n.toChannelMap()).toList(),
      });
      // The silence flag is one-shot: once its moment is inside the
      // scheduled window (or past), it has done its job.
      final silenced = settings.silenceNextEpochSeconds;
      if (silenced != 0 &&
          silenced <
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7 * 86400) {
        settings.update(() => settings.silenceNextEpochSeconds = 0);
      }
    } on PlatformException {
      // Native side unavailable — alerts simply don't arm.
    } on MissingPluginException {
      // No native implementation (e.g. widget tests) — ignore.
    }
  }

  /// Cancels every scheduled alert on the native side.
  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod('cancelAll');
    } on PlatformException {
      // Ignore — nothing was armed.
    } on MissingPluginException {
      // Ignore.
    }
  }

  /// Alerts health check (v2.3.0): the native side reports whether
  /// notifications are on, whether exact alarms are allowed
  /// (Android 12+), whether the app is exempt from battery
  /// optimization, and how many alerts are armed with the next
  /// one's epoch millis (0 when none). Null when unavailable.
  static Future<Map<String, dynamic>?> status() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('alertStatus');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Posts a real notification right now on the channel for
  /// [sound] (v2.3.0 test alert) — the same channel a real adhan
  /// alert for that sound uses, so permission, channel and sound
  /// are all proven at once.
  /// Plays a bundled alert sound from the picker (build 34) without
  /// selecting it or scheduling anything.
  static Future<void> previewSound(String sound) async {
    try {
      await _channel.invokeMethod('previewSound', {'sound': sound});
    } catch (_) {
      // Preview is a convenience; a platform hiccup stays silent.
    }
  }

  static Future<void> testAlert({
    required String title,
    required String body,
    required String sound,
  }) async {
    try {
      await _channel.invokeMethod('testAlert', {
        'title': title,
        'body': body,
        'sound': sound,
      });
    } on PlatformException {
      // Ignore — the health page still shows the status rows.
    } on MissingPluginException {
      // Ignore.
    }
  }

  /// Opens the system screen where the user can allow exact alarms
  /// for this app (v2.3.0, Android 12+; app details before that).
  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  /// Opens the system prompt to exempt this app from battery
  /// optimization (v2.3.0).
  static Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }
}
