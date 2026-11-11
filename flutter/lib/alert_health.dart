import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'alerts.dart';
import 'app_settings.dart';
import 'prayer_models.dart';
import 'strings.dart';

/// Alerts health check (v2.3.0) — the Android counterpart of the iOS
/// AlertHealthView, plus the two Android-only failure modes: exact
/// alarms (item 11: without them Android may delay an adhan while
/// the phone sleeps) and battery optimization (restricted apps can
/// have alerts dropped). Each problem row carries its own button
/// straight to the system screen that fixes it. The test alert
/// posts a real notification on the exact channel the next prayer
/// alert will use.
class AlertHealthPage extends StatefulWidget {
  final AppSettings settings;
  const AlertHealthPage({super.key, required this.settings});

  @override
  State<AlertHealthPage> createState() => _AlertHealthPageState();
}

class _AlertHealthPageState extends State<AlertHealthPage> {
  Map<String, dynamic>? _status;
  bool _testSent = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final status = await AlertScheduler.status();
    if (mounted) setState(() => _status = status);
  }

  Prayer get _nextPrayer {
    final now = tz.TZDateTime.now(edmontonLocation());
    final day = PrayerProvider.computeDay(now);
    for (final slot in day.prayerSlots) {
      if (slot.adhan.isAfter(now)) return slot.prayer;
    }
    final tomorrow = PrayerProvider.computeDay(now.add(const Duration(days: 1)));
    return tomorrow.prayerSlots.first.prayer;
  }

  bool get _timesReady {
    final now = tz.TZDateTime.now(edmontonLocation());
    return PrayerProvider.computeDay(now).slots.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final notificationsOn = status?['notificationsOn'] as bool? ?? false;
    final exactAlarms = status?['exactAlarms'] as bool? ?? true;
    final batteryExempt = status?['batteryExempt'] as bool? ?? false;
    final scheduledCount = status?['scheduledCount'] as int? ?? 0;
    final nextMillis = status?['nextEpochMillis'] as int? ?? 0;

    Widget okRow(String text) => ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(text),
        );
    Widget badRow(String text, String body, String button, VoidCallback fix) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: Text(text),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(body,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton(onPressed: fix, child: Text(button)),
            ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: Text(S.t('alertHealth'))),
      body: ListView(
        children: [
          if (status == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (notificationsOn)
              okRow(S.t('healthNotifOn'))
            else
              badRow(S.t('healthNotifOff'), S.t('healthNotifOffBody'),
                  S.t('healthAllow'), () async {
                await AlertScheduler.requestPermission();
                await _reload();
              }),
            if (scheduledCount > 0 && nextMillis > 0)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(S.f('healthScheduledFmt', {
                  'count': '$scheduledCount',
                  'time': PrayerFormat.time(
                      tz.TZDateTime.fromMillisecondsSinceEpoch(
                          edmontonLocation(), nextMillis)),
                })),
              )
            else if (notificationsOn)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(S.t('healthNoScheduled')),
              ),
            if (_timesReady)
              ListTile(
                leading: const Icon(Icons.access_time_filled),
                title: Text(S.t('healthTimesReady')),
              ),
            if (exactAlarms)
              okRow(S.t('healthExactOn'))
            else
              badRow(S.t('healthExactOff'), S.t('healthExactOffBody'),
                  S.t('healthOpen'), () async {
                await AlertScheduler.openExactAlarmSettings();
                await _reload();
              }),
            if (batteryExempt)
              okRow(S.t('healthBatteryOn'))
            else
              badRow(S.t('healthBatteryOff'), S.t('healthBatteryOffBody'),
                  S.t('healthAllow'), () async {
                await AlertScheduler.openBatterySettings();
                await _reload();
              }),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(S.t('healthRecheck')),
              onTap: _reload,
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(S.t('testAlertNote'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: Text(S.t('sendTestAlert')),
              onPressed: status == null || !notificationsOn
                  ? null
                  : () async {
                      await AlertScheduler.testAlert(
                        title: S.t('testAlertTitle'),
                        body: S.t('testAlertBody'),
                        sound: widget.settings.effectiveSound(_nextPrayer),
                      );
                      if (mounted) setState(() => _testSent = true);
                    },
            ),
          ),
          if (_testSent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(S.t('testAlertSent'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
