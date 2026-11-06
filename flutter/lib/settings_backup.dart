// Settings backup file (v2.0.0, workstream 9) — the Android side of
// the format shared with iOS: one JSON document, canonical keys,
// no secrets. Export goes through the share sheet; cloud backup
// goes to the app's Google Drive appDataFolder via the native
// 'alrashid/backup' channel (DriveBackup.kt); import reads a file
// picked through the same channel. Canonical keys match iOS except
// the per-prayer alert toggles, translated both ways below
// (iOS 'alerts.prayer.fajr' <-> Android 'alerts.fajr').

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'prayer_models.dart';

class SettingsBackup {
  static const _channel = MethodChannel('alrashid/backup');

  /// Canonical keys whose values travel in the backup. Per-prayer
  /// alert/sound keys are generated from the Prayer enum.
  static List<String> get _scalarKeys => [
        AppSettings.modeKey,
        AppSettings.primaryKey,
        AppSettings.accentKey,
        AppSettings.textKey,
        AppSettings.savedThemesKey,
        AppSettings.languageKey,
        AppSettings.textSizeKey,
        AppSettings.notificationsEnabledKey,
        AppSettings.reminderEnabledKey,
        AppSettings.reminderLeadKey,
        AppSettings.jumuahReminderEnabledKey,
        AppSettings.alertSoundKey,
        AppSettings.hijriOffsetKey,
        AppSettings.iqamahFirstKey,
        AppSettings.leaveLeadKey,
        AppSettings.taraweehOffsetKey,
        AppSettings.hapticsEnabledKey,
        AppSettings.widgetColorModeKey,
        AppSettings.homeWidgetThemeKey,
        AppSettings.minimalModeKey,
        AppSettings.fastingMonThuKey,
        AppSettings.fastingWhiteDaysKey,
      ];

  static String _canonical(String localKey) {
    for (final p in Prayer.values) {
      if (localKey == AppSettings.alertKey(p)) {
        return 'alerts.prayer.${p.name}';
      }
    }
    return localKey;
  }

  static String _local(String canonicalKey) {
    for (final p in Prayer.values) {
      if (canonicalKey == 'alerts.prayer.${p.name}') {
        return AppSettings.alertKey(p);
      }
    }
    return canonicalKey;
  }

  static Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object?>{};
    final localKeys = <String>[
      ..._scalarKeys,
      for (final p in Prayer.values) AppSettings.alertKey(p),
      for (final p in Prayer.values) AppSettings.prayerSoundKey(p),
    ];
    for (final key in localKeys) {
      final value = prefs.get(key);
      if (value != null) values[_canonical(key)] = value;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'AlRashidPrayer',
      'kind': 'settings-backup',
      'version': 1,
      'values': values,
    });
  }

  /// Applies a backup document. Returns false for anything that is
  /// not an Al Rashid settings backup. Unknown keys are ignored.
  static Future<bool> importJson(String text) async {
    try {
      final doc = jsonDecode(text) as Map<String, dynamic>;
      if (doc['kind'] != 'settings-backup') return false;
      final values = doc['values'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      for (final entry in values.entries) {
        final key = _local(entry.key);
        final value = entry.value;
        if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setInt(key, value.toInt());
        } else if (value is String) {
          await prefs.setString(key, value);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Google Drive (appDataFolder) via the native channel ---

  static Future<bool> driveBackup() async {
    try {
      return await _channel.invokeMethod<bool>(
              'driveBackup', {'json': await exportJson()}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> driveRestore(AppSettings settings) async {
    try {
      final json = await _channel.invokeMethod<String>('driveRestore');
      if (json == null) return false;
      if (!await importJson(json)) return false;
      await settings.reload();
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Epoch millis of the last successful Drive backup, or null.
  static Future<int?> driveLastBackupMillis() async {
    try {
      return await _channel.invokeMethod<int>('driveLastBackup');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> pickAndImport(AppSettings settings) async {
    try {
      final json = await _channel.invokeMethod<String>('pickFile');
      if (json == null) return false;
      if (!await importJson(json)) return false;
      await settings.reload();
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
