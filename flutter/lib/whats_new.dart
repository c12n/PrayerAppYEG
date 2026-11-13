// What's New (v1.8.0) — the Android counterpart of the iOS What's
// New sheet. Shown once after an update to a version that has
// entries: a fresh install just records the current version, and
// later launches stay silent. Stored in shared_preferences under
// the same key as iOS ('whatsnew.lastSeenVersion').

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'strings.dart';

class WhatsNew {
  static const _lastSeenKey = 'whatsnew.lastSeenVersion';

  /// First-install welcome rows (v2.3.0, parity with iOS): a short
  /// tour shown once, instead of change notes.
  static const List<(IconData, String)> _welcomeEntries = [
    (Icons.wb_sunny, 'wnWelcome1'),
    (Icons.notifications_active, 'wnWelcome2'),
    (Icons.palette, 'wnWelcome3'),
    (Icons.menu_book, 'wnWelcome4'),
  ];

  /// One feature row of the dialog: an icon and a strings.dart key.
  static const Map<String, List<(IconData, String)>> _entries = {
    '3.0.3': [
      (Icons.system_update, 'wnUpdate303'),
      (Icons.linear_scale, 'wnScrub303'),
    ],
    '3.0.2': [
      (Icons.volume_up, 'wnSounds302'),
      (Icons.swipe_down, 'wnDismiss302'),
      (Icons.auto_fix_high, 'wnFixes302'),
    ],
    '3.0.0': [
      (Icons.drive_file_rename_outline, 'wnName300'),
      (Icons.play_circle_fill, 'wnQuran300'),
      (Icons.download, 'wnDownloads300'),
      (Icons.bedtime, 'wnSleep300'),
      (Icons.repeat, 'wnMemo300'),
      (Icons.checklist, 'wnTracker300'),
      (Icons.auto_awesome, 'wnNames230'),
      (Icons.palette, 'wnWidgets200'),
    ],
    '2.3.0': [
      (Icons.notifications_active, 'wnTest230'),
      (Icons.health_and_safety, 'wnHealth230'),
      (Icons.forum, 'wnHadith230'),
      (Icons.auto_awesome, 'wnNames230'),
      (Icons.nightlight_round, 'wnHijri230'),
    ],
    '2.0.0': [
      (Icons.palette, 'wnWidgets200'),
      (Icons.nightlight_round, 'wnRamadan200'),
      (Icons.calendar_month, 'wnCalendar200'),
      (Icons.timer, 'wnIqamah200'),
      (Icons.view_agenda, 'wnMinimal200'),
    ],
    '1.8.0': [
      (Icons.volume_up, 'wnSounds'),
      (Icons.backup, 'wnSync'),
      (Icons.text_fields, 'wnText'),
    ],
  };

  /// Called once after the first frame. A fresh install gets the
  /// one-time welcome dialog (v2.3.0); an update shows the dialog
  /// when the current version has entries.
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_lastSeenKey);
    if (lastSeen == kAppVersion) return;
    await prefs.setString(_lastSeenKey, kAppVersion);
    final welcome = lastSeen == null;
    final entries = welcome ? _welcomeEntries : _entries[kAppVersion];
    if (entries == null || entries.isEmpty) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(welcome ? S.t('welcomeTitle') : S.t('whatsNew')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, key) in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(S.t(key))),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.t('continue')),
          ),
        ],
      ),
    );
  }
}
