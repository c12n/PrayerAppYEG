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

  /// One feature row of the dialog: an icon and a strings.dart key.
  static const Map<String, List<(IconData, String)>> _entries = {
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

  /// Called once after the first frame. Shows the dialog when the
  /// stored version differs from the current one and the current
  /// version has entries.
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_lastSeenKey);
    if (lastSeen == kAppVersion) return;
    await prefs.setString(_lastSeenKey, kAppVersion);
    if (lastSeen == null) return; // Fresh install: record silently.
    final entries = _entries[kAppVersion];
    if (entries == null || entries.isEmpty) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('whatsNew')),
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
