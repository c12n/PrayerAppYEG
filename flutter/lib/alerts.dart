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

  const PlannedNotification({
    required this.id,
    required this.epochMillis,
    required this.title,
    required this.body,
  });

  Map<String, dynamic> toChannelMap() => {
        'id': id,
        'epochMillis': epochMillis,
        'title': title,
        'body': body,
      };
}

class AlertScheduler {
  static const _channel = MethodChannel('alrashid/alerts');

  /// iOS allows 64 pending requests; keep the same budget (60).
  static const maxScheduled = 60;

  static const _reminderIdOffset = 100000000;
  static const _jumuahIdOffset = 200000000;

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
        items.add(PlannedNotification(
          id: _epochSeconds(slot.adhan),
          epochMillis: slot.adhan.millisecondsSinceEpoch,
          title: title,
          body: body,
        ));

        // Pre-prayer reminder: the five prayers only — Sunrise has
        // none, and the Jumu'ah slot has its own reminder below.
        if (settings.reminderEnabled &&
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

      // Jumu'ah reminder: one hour before the Friday Khutbah.
      final khutbah = day.jumuahKhutbah;
      if (day.isFriday && settings.jumuahReminderEnabled && khutbah != null) {
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
}
