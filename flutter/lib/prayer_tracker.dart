// Prayer tracker (v3.0.0) — the Android counterpart of the iOS
// PrayerTracker: a daily check-off of the five obligatory prayers,
// persisted as JSON under `tracker.prayers.v1` in shared_preferences
// ([yyyy-MM-dd: [prayerName]]), plus the Home card and a detail page
// with the last 7 days, totals, the full-day streak, and the Quran
// listening stats.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'prayer_models.dart';
import 'quran_player.dart';
import 'strings.dart';

class TrackerStore extends ChangeNotifier {
  /// The tracked prayers, in day order. Friday's Dhuhr (Jumu'ah)
  /// is tracked as "Dhuhr" (iOS).
  static const prayerNames = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
  static const storageKey = 'tracker.prayers.v1';

  Map<String, List<String>> prayersByDay = {};
  SharedPreferences? _prefs;

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        prayersByDay = decoded.map(
            (k, v) => MapEntry(k, (v as List).map((e) => '$e').toList()));
      } catch (_) {
        prayersByDay = {};
      }
    }
    notifyListeners();
  }

  // MARK: Day keys

  static String dayKey(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  // MARK: Queries

  Set<String> prayersOn(DateTime date) =>
      Set.of(prayersByDay[dayKey(date)] ?? const <String>[]);

  bool isDone(String prayer, DateTime date) => prayersOn(date).contains(prayer);

  int countOn(DateTime date) => prayersOn(date).length;

  bool isFullDay(DateTime date) =>
      prayerNames.every((name) => prayersOn(date).contains(name));

  /// Total prayers checked off in the 7 days ending today.
  int countThisWeek([DateTime? today]) {
    final end = today ?? DateTime.now();
    var sum = 0;
    for (var offset = 0; offset < 7; offset++) {
      sum += countOn(DateTime(end.year, end.month, end.day - offset));
    }
    return sum;
  }

  /// Consecutive full days ending today — or ending yesterday
  /// while today is still in progress.
  int fullDayStreak([DateTime? today]) {
    var day = today ?? DateTime.now();
    var streak = 0;
    if (!isFullDay(day)) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    while (isFullDay(day)) {
      streak += 1;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return streak;
  }

  // MARK: Mutation

  void toggle(String prayer, [DateTime? date]) {
    final day = date ?? DateTime.now();
    final key = dayKey(day);
    final set = Set.of(prayersByDay[key] ?? const <String>[]);
    if (!set.remove(prayer)) {
      set.add(prayer);
    }
    prayersByDay[key] = prayerNames.where(set.contains).toList();
    _prefs?.setString(storageKey, jsonEncode(prayersByDay));
    notifyListeners();
  }
}

/// Gives the widget tree access to the tracker.
class TrackerScope extends InheritedWidget {
  final TrackerStore tracker;
  const TrackerScope({super.key, required this.tracker, required super.child});

  static TrackerStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TrackerScope>()!.tracker;

  @override
  bool updateShouldNotify(TrackerScope oldWidget) =>
      tracker != oldWidget.tracker;
}

// MARK: - Card (Home)

/// "Today's Prayers": five tappable chips on the Home screen; a tap
/// anywhere else on the card opens the detail page (iOS card).
class PrayerTrackerCard extends StatelessWidget {
  final QuranPlayer player;
  const PrayerTrackerCard({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final tracker = TrackerScope.of(context);
    final settings = SettingsScope.of(context);
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final now = DateTime.now();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PrayerTrackerDetailPage(player: player),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist, size: 20),
                  const SizedBox(width: 8),
                  Text(S.t('todaysPrayers'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    S.f('ofFiveFmt', {'count': '${tracker.countOn(now)}'}),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: accentFor(Theme.of(context).brightness, settings),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final name in TrackerStore.prayerNames)
                    Expanded(
                      child: _chip(context, tracker, name, now),
                    ),
                ],
              ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, TrackerStore tracker, String name,
      DateTime now) {
    final done = tracker.isDone(name, now);
    final prayer = Prayer.values.asNameMap()[name.toLowerCase()];
    final label = prayer?.displayName ?? name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => tracker.toggle(name),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFF0E5A40).withValues(alpha: 0.14)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: done
                    ? const Color(0xFF0E5A40)
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: done
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: - Detail page

class PrayerTrackerDetailPage extends StatelessWidget {
  final QuranPlayer player;
  const PrayerTrackerDetailPage({super.key, required this.player});

  String get _listenedLabel {
    final total = player.totalSecondsListened.round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    return hours > 0
        ? S.f('listenedHoursFmt',
            {'hours': '$hours', 'minutes': '$minutes'})
        : S.f('listenedMinutesFmt', {'minutes': '$minutes'});
  }

  @override
  Widget build(BuildContext context) {
    final tracker = TrackerScope.of(context);
    final settings = SettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.t('trackerTitle'))),
      body: AnimatedBuilder(
        animation: Listenable.merge([tracker, player]),
        builder: (context, _) {
          final now = DateTime.now();
          final days = [
            for (var i = 0; i < 7; i++)
              DateTime(now.year, now.month, now.day - i),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _sectionLabel(context, S.t('last7Days')),
              Card(
                child: Column(
                  children: [
                    for (final day in days) _dayRow(context, tracker, day),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionLabel(context, S.t('totals')),
              Card(
                child: Column(
                  children: [
                    _valueRow(context, S.t('prayersThisWeek'),
                        '${tracker.countThisWeek()}'),
                    const Divider(height: 1),
                    _valueRow(
                        context,
                        S.t('fullDayStreak'),
                        S.f('daysFmt',
                            {'count': '${tracker.fullDayStreak()}'})),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionLabel(context, S.t('quranListening')),
              Card(
                child: Column(
                  children: [
                    _valueRow(context, S.t('surahsCompleted'),
                        '${player.completedSurahsTotal}'),
                    const Divider(height: 1),
                    _valueRow(context, S.t('timeListened'), _listenedLabel),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _valueRow(BuildContext context, String label, String value) =>
      ListTile(
        title: Text(label),
        trailing: Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      );

  Widget _dayRow(BuildContext context, TrackerStore tracker, DateTime day) {
    final isToday = day.day == DateTime.now().day &&
        day.month == DateTime.now().month &&
        day.year == DateTime.now().year;
    final locale = LanguageState.current.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday
                      ? S.t('today')
                      : DateFormat('EEE', locale).format(day),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  DateFormat('MMM d', locale).format(day),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          for (final name in TrackerStore.prayerNames)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                tracker.isDone(name, day)
                    ? Icons.circle
                    : Icons.circle_outlined,
                size: 13,
                color: tracker.isDone(name, day)
                    ? const Color(0xFF0E5A40)
                    : Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.4),
              ),
            ),
          SizedBox(
            width: 34,
            child: Text(
              '${tracker.countOn(day)}/5',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
