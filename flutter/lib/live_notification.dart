// Platform extras (v3.0.0): the ongoing countdown notification
// (the Live Activity equivalent) and alternate launcher icons,
// both driven over MethodChannels to the Kotlin side
// (OngoingNotification.kt and MainActivity.kt).

import 'package:flutter/services.dart';

class OngoingNotification {
  static const _channel = MethodChannel('alrashid/live');

  /// Tells the native side whether the persistent next-prayer
  /// notification should be up. Fire and forget: on platforms
  /// without the channel this simply does nothing.
  static Future<void> sync(bool enabled) async {
    try {
      await _channel.invokeMethod('setOngoing', {'enabled': enabled});
    } catch (_) {
      // No native side (tests, other platforms) — stay silent.
    }
  }

  /// Re-posts the notification with fresh times when enabled
  /// (called when the app resumes).
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('refreshOngoing');
    } catch (_) {}
  }
}

class AppIconChanger {
  static const _channel = MethodChannel('alrashid/icons');

  /// Switches the launcher icon to [name] ('default' or one of the
  /// kAppIconNames variants) by toggling the activity-aliases.
  static Future<void> setIcon(String name) async {
    try {
      await _channel.invokeMethod('setIcon', {'name': name});
    } catch (_) {}
  }
}

/// Refresh pings for the Kotlin home-screen widgets that the Dart
/// side feeds (the Continue Listening widget).
class WidgetRefresher {
  static const _channel = MethodChannel('alrashid/widgets');

  static Future<void> refreshListening() async {
    try {
      await _channel.invokeMethod('refreshListening');
    } catch (_) {}
  }
}
