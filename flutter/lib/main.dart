// Al Rashid Prayer — Flutter edition.
//
// Same app as the native iOS build: Al Rashid Mosque Edmonton prayer
// times (Adhan calibrated to the mosque's published timetable), Iqamah
// offsets, Umm al-Qura Hijri date, next-prayer countdown, and Friday
// Jumu'ah handling — computed fully on-device, offline.
//
// Responsive layouts:
//  - Phone (< 600dp): single column.
//  - Duo (600–1100dp): two panes — next prayer beside the schedule
//    (iPhone landscape / small tablets / foldables).
//  - Tablet (>= 1100dp): wide three-zone layout with today's and
//    tomorrow's schedules side by side (iPad / Android tablets).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'alerts.dart';
import 'app_settings.dart';
import 'hijri_calendar.dart';
import 'names_of_allah.dart';
import 'prayer_models.dart';
import 'settings_page.dart';
import 'daily_verse.dart';
import 'strings.dart';
import 'whats_new.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await initializeDateFormatting();
  final settings = await AppSettings.load();
  runApp(AlRashidApp(settings: settings));
}

// MARK: - Theme

class AppTheme {
  static const deepGreen = Color(0xFF0B3D2E);
  static const green = Color(0xFF0E5A40);
  static const gold = Color(0xFFD4AF37);
  static const lightGold = Color(0xFFF2CD5C);

  static Color adaptiveGold(Brightness b) =>
      b == Brightness.dark ? lightGold : const Color(0xFF7A5F10);

  // v1.0.5: the page background stays pure white in Light Mode and pure
  // black in Dark Mode (the user's request, same as iOS).
  static ThemeData light(AppSettings settings) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: colorFromHex(settings.primaryHex),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
      );

  static ThemeData dark(AppSettings settings) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: colorFromHex(settings.primaryHex),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      );
}

class AlRashidApp extends StatelessWidget {
  final AppSettings settings;
  const AlRashidApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => SettingsScope(
        settings: settings,
        child: MaterialApp(
          title: 'Al Rashid Prayer',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(settings),
          darkTheme: AppTheme.dark(settings),
          themeMode: settings.mode,
          locale: Locale(settings.language.name),
          builder: (context, child) => Directionality(
            textDirection: settings.language.isRTL
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.textSize.scale),
              ),
              child: child!,
            ),
          ),
          home: const HomePage(),
        ),
      ),
    );
  }
}

// MARK: - Home page

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _timer;
  late tz.TZDateTime _now;
  final ScrollController _scrollController = ScrollController();
  bool _statusBarHidden = false;

  tz.Location get _edmonton => edmontonLocation();

  @override
  void initState() {
    super.initState();
    _now = tz.TZDateTime.now(_edmonton);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = tz.TZDateTime.now(_edmonton));
    });
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // Arm the Adhan alerts (v1.5) and ask for the notification
    // permission on first launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlertScheduler.refresh(SettingsScope.of(context), askPermission: true);
      // Show the What's New dialog once after an update (v1.8.0).
      if (!SettingsScope.of(context).minimalMode) {
        WhatsNew.maybeShow(context);
      }
      _checkAssistantQuery();
    });
  }

  /// iOS v1.5.1 parity: once the home list scrolls past ~24px, hide
  /// the status bar so it never floats over the prayer cards
  /// mid-scroll (and screenshots taken while scrolled stay clean);
  /// it comes back near the top. The controller is shared by every
  /// home layout's scroll views, so the furthest-scrolled pane wins.
  void _onScroll() {
    var offset = 0.0;
    for (final position in _scrollController.positions) {
      if (position.pixels > offset) offset = position.pixels;
    }
    _setStatusBarHidden(offset > 24);
  }

  void _setStatusBarHidden(bool hidden) {
    if (hidden == _statusBarHidden) return;
    _statusBarHidden = hidden;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays:
          hidden ? const [SystemUiOverlay.bottom] : SystemUiOverlay.values,
    );
  }

  /// Assistant / Bixby deep links (v2.0.0, feature 7): MainActivity
  /// stores a pending query ('next' or a prayer name) in
  /// shared_preferences; when the app next surfaces, answer it in a
  /// dialog and clear it. Stale queries (> 2 minutes) are dropped.
  Future<void> _checkAssistantQuery() async {
    final prefs = await SharedPreferences.getInstance();
    final query = prefs.getString('assistant.queryPrayer');
    final at = prefs.getInt('assistant.queryAt') ?? 0;
    if (query == null) return;
    await prefs.remove('assistant.queryPrayer');
    await prefs.remove('assistant.queryAt');
    if (DateTime.now().millisecondsSinceEpoch - at > 120000) return;
    if (!mounted) return;
    final settings = SettingsScope.of(context);
    final today = PrayerProvider.dayFor(tz.TZDateTime.now(_edmonton));
    final String answer;
    if (query == 'next') {
      final next = PrayerProvider.snapshot(tz.TZDateTime.now(_edmonton),
              enabled: settings.enabledPrayers)
          .next;
      answer =
          '${next.name} — ${PrayerFormat.time(next.adhan)}';
    } else {
      final prayer = Prayer.values.asNameMap()[query];
      if (prayer == null) return;
      answer =
          '${prayer.displayName} — ${PrayerFormat.time(today.adhan(prayer))}';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('assistant')),
        content: Text(answer,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.t('done')),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the 7-day alert plan fresh, like iOS rescheduling on
    // every activation.
    if (state == AppLifecycleState.resumed) {
      AlertScheduler.refresh(SettingsScope.of(context));
      _checkAssistantQuery();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // Restore the default overlays when leaving the home page.
    _statusBarHidden = false;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final snapshot = PrayerProvider.snapshot(_now, enabled: settings.enabledPrayers);
    final today = PrayerProvider.dayFor(_now);
    final tomorrowStart =
        tz.TZDateTime(_edmonton, _now.year, _now.month, _now.day + 1);
    final tomorrow = PrayerProvider.computeDay(tomorrowStart);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [
              colorFromHex(settings.primaryHex).withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.35
                      : 0.07),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (settings.minimalMode) {
                return _minimalLayout(context, snapshot, today);
              }
              if (width >= 1100) {
                return _tabletLayout(context, snapshot, today, tomorrow);
              }
              if (width >= 600) {
                return _duoLayout(context, snapshot, today);
              }
              return _phoneLayout(context, snapshot, today);
            },
          ),
        ),
      ),
    );
  }

  // Minimal Mode (v2.0.0): essentials only at every width —
  // next prayer + plain countdown, today's list, and the fasting
  // row on fasting days and throughout Ramadan.
  Widget _minimalLayout(
      BuildContext context, PrayerSnapshot snapshot, PrayerDay today) {
    final settings = SettingsScope.of(context);
    final showFasting = RamadanMode.isRamadanDay(today) ||
        FastingDays.isFastingDay(
            today, settings.fastingMonThu, settings.fastingWhiteDays);
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderSection(today: today, now: _now),
          const SizedBox(height: 20),
          NextPrayerCard(snapshot: snapshot),
          if (showFasting) ...[
            const SizedBox(height: 20),
            _FastingTimesRow(day: today),
          ],
          const SizedBox(height: 20),
          ScheduleCard(snapshot: snapshot),
          const SizedBox(height: 20),
          const FooterSection(),
        ],
      ),
    );
  }

  // Phone: single column.
  Widget _phoneLayout(
      BuildContext context, PrayerSnapshot snapshot, PrayerDay today) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderSection(today: today, now: _now),
          const SizedBox(height: 20),
          NextPrayerCard(snapshot: snapshot),
          const SizedBox(height: 20),
          ScheduleCard(snapshot: snapshot),
          const SizedBox(height: 20),
          const DailyVerseCard(),
          const SizedBox(height: 20),
          const HijriCountdownCard(),
          const SizedBox(height: 20),
          const NamesEntryCard(),
          const SizedBox(height: 20),
          const QiblaCard(),
          const SizedBox(height: 20),
          const FooterSection(),
        ],
      ),
    );
  }

  // Duo: two panes side by side.
  Widget _duoLayout(
      BuildContext context, PrayerSnapshot snapshot, PrayerDay today) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HeaderSection(today: today, now: _now),
                  const SizedBox(height: 20),
                  NextPrayerCard(snapshot: snapshot),
                  const SizedBox(height: 20),
                  const DailyVerseCard(),
                  const SizedBox(height: 20),
                  const HijriCountdownCard(),
                  const SizedBox(height: 20),
                  const NamesEntryCard(),
                  const SizedBox(height: 20),
                  const QiblaCard(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  ScheduleCard(snapshot: snapshot),
                  const SizedBox(height: 20),
                  const FooterSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tablet: left rail + today's and tomorrow's schedules.
  Widget _tabletLayout(BuildContext context, PrayerSnapshot snapshot,
      PrayerDay today, PrayerDay tomorrow) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HeaderSection(today: today, now: _now),
                      const SizedBox(height: 24),
                      NextPrayerCard(snapshot: snapshot),
                      const SizedBox(height: 24),
                      const DailyVerseCard(),
                      const SizedBox(height: 24),
                      const HijriCountdownCard(),
                      const SizedBox(height: 24),
                      const NamesEntryCard(),
                      const SizedBox(height: 24),
                      const QiblaCard(),
                      const SizedBox(height: 24),
                      const FooterSection(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: ScheduleCard(snapshot: snapshot, large: true),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: ScheduleCard.forDay(
                    day: tomorrow,
                    title: S.t('tomorrowTimes'),
                    large: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// MARK: - Monthly calendar (v2.0.0, feature 2)

/// Full month grid: each cell shows Fajr + Maghrib; tapping a day
/// previews its full schedule; the month can be shared as a text
/// table (the share sheet offers print on most devices). On wide
/// screens the preview sits beside the grid.
class MonthlyCalendarPage extends StatefulWidget {
  const MonthlyCalendarPage({super.key});

  @override
  State<MonthlyCalendarPage> createState() => _MonthlyCalendarPageState();
}

class _MonthlyCalendarPageState extends State<MonthlyCalendarPage> {
  static const _shareChannel = MethodChannel('alrashid/share');
  static final _edmonton = PrayerProviderDayAccess.edmonton;

  late tz.TZDateTime _anchor;
  late tz.TZDateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = tz.TZDateTime.now(_edmonton);
    _anchor = tz.TZDateTime(_edmonton, now.year, now.month, 1);
    _selected = tz.TZDateTime(_edmonton, now.year, now.month, now.day);
  }

  List<tz.TZDateTime> get _monthDates {
    final daysInMonth =
        DateTime(_anchor.year, _anchor.month + 1, 0).day;
    return [
      for (var d = 1; d <= daysInMonth; d++)
        tz.TZDateTime(_edmonton, _anchor.year, _anchor.month, d),
    ];
  }

  PrayerDay _day(tz.TZDateTime date) => PrayerProvider.computeDay(date);

  void _shift(int delta) => setState(() {
        _anchor = tz.TZDateTime(_edmonton, _anchor.year, _anchor.month + delta, 1);
      });

  String get _monthTableText {
    final buffer = StringBuffer()
      ..writeln(
          '${MosqueInfo.name} — ${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}')
      ..writeln()
      ..writeln('Date\tFajr\tSunrise\tDhuhr\tAsr\tMaghrib\tIsha');
    for (final date in _monthDates) {
      final day = _day(date);
      final row = [
        for (final p in Prayer.values)
          PrayerFormat.time(day.adhan(p)),
      ];
      buffer.writeln(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}\t${row.join('\t')}');
    }
    buffer.writeln();
    buffer.writeln(
        'Iqamah: Fajr +20m · Dhuhr +10m · Asr +10m · Maghrib +5m · Isha +10m');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final selectedDay = _day(_selected);
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shift(-1),
            ),
            Expanded(
              child: Text(
                '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorFromHex(settings.primaryHex),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shift(1),
            ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 0.85,
          ),
          itemCount: _monthDates.length +
              ((_monthDates.first.weekday - DateTime.monday) % 7),
          itemBuilder: (context, index) {
            final blanks = (_monthDates.first.weekday - DateTime.monday) % 7;
            if (index < blanks) return const SizedBox.shrink();
            final date = _monthDates[index - blanks];
            final day = _day(date);
            final isSelected = date.day == _selected.day &&
                date.month == _selected.month &&
                date.year == _selected.year;
            return InkWell(
              onTap: () => setState(() => _selected = date),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorFromHex(settings.accentHex).withValues(alpha: 0.25)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${date.day}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(
                      '${Prayer.fajr.displayName} ${PrayerFormat.time(day.adhan(Prayer.fajr))}',
                      style: const TextStyle(fontSize: 8),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                    Text(
                      '${Prayer.maghrib.displayName} ${PrayerFormat.time(day.adhan(Prayer.maghrib))}',
                      style: const TextStyle(fontSize: 8),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
    final preview = ScheduleCard.forDay(
      day: selectedDay,
      title: PrayerFormat.longDate(_selected),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('monthlyCalendar')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: S.t('shareMonth'),
            onPressed: () =>
                _shareChannel.invokeMethod('share', {'text': _monthTableText}),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SingleChildScrollView(child: grid)),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 380,
                    child: SingleChildScrollView(child: preview),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [grid, const SizedBox(height: 16), preview],
            ),
          );
        },
      ),
    );
  }
}

/// Small accessor so the calendar page can build Edmonton dates
/// without duplicating the timezone lookup.
class PrayerProviderDayAccess {
  static tz.Location get edmonton => edmontonLocation();
}

// MARK: - Header

class HeaderSection extends StatelessWidget {
  final PrayerDay today;
  final tz.TZDateTime now;
  const HeaderSection({super.key, required this.today, required this.now});

  @override
  Widget build(BuildContext context) {
    final accent = SurfaceColors.of(context).accent;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.nightlight_round, size: 20, color: accent),
            const SizedBox(width: 8),
            Text(
              S.t('greeting'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
            const Spacer(),
            if (!SettingsScope.of(context).minimalMode)
              IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: S.t('monthlyCalendar'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MonthlyCalendarPage(),
                ),
              ),
              ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: S.t('settings'),
              onPressed: () async {
                final settings = SettingsScope.of(context);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(settings: settings),
                  ),
                );
                // Any settings change (language included) can change
                // the alert plan's contents — rebuild it on return.
                AlertScheduler.refresh(settings);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          MosqueInfo.name,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          today.hijriDate,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          PrayerFormat.longDate(now),
          style: TextStyle(fontSize: 15, color: secondary),
        ),
      ],
    );
  }
}

// MARK: - Adaptive card + surface colors (v1.0.4)
//
// Native Light & Dark Mode, mirroring the iOS app: cards are warm white
// with deep-green text in Light Mode and keep the green glass design in
// Dark Mode. Every text color comes from SurfaceColors, whose values are
// chosen for high contrast in both appearances (deep green on white
// ≈ 10.9:1, white on green ≈ 7.5:1+, adaptive gold ≈ 5.9:1 on white).

class SurfaceColors {
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color accent;
  final Color panelTrack;
  const SurfaceColors({
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.accent,
    required this.panelTrack,
  });

  /// v1.0.5: computed from the user's theme settings — the text color is
  /// the picked one (contrast-guarded, defaults as on iOS) and the accent
  /// is the picked accent adjusted for the current appearance.
  static SurfaceColors of(BuildContext context) {
    final settings = SettingsScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = resolvedTextColor(darkSurface: dark, s: settings);
    return SurfaceColors(
      primary: text,
      secondary: text.withValues(alpha: dark ? 0.85 : 0.84),
      muted: text.withValues(alpha: dark ? 0.72 : 0.74),
      accent: accentFor(
          dark ? Brightness.dark : Brightness.light, settings),
      panelTrack: dark
          ? const Color(0x33FFFFFF)
          : colorFromHex(settings.primaryHex).withValues(alpha: 0.12),
    );
  }
}

class AdaptiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AdaptiveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = colorFromHex(settings.primaryHex);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  lightenColor(primary, 0.16),
                  primary,
                  darkenColor(primary, 0.30),
                ]
              : const [Colors.white, Colors.white],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: dark
              ? accentFor(Brightness.dark, settings).withValues(alpha: 0.45)
              : primary.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: dark
                ? darkenColor(primary, 0.30).withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

// MARK: - Next prayer card

class NextPrayerCard extends StatelessWidget {
  final PrayerSnapshot snapshot;
  const NextPrayerCard({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final next = snapshot.next;
    // Iqamah-first (v2.0.0): between a prayer's Adhan and its
    // Iqamah, the hero flips to that prayer and counts down to the
    // Iqamah; the optional time-to-leave nudge shows near the end.
    final settings = SettingsScope.of(context);
    final phase =
        settings.iqamahFirst ? PrayerProvider.iqamahPhase(snapshot.date) : null;
    final hero = phase ?? next;
    final caption = phase != null
        ? S.t('iqamahNow')
        : (snapshot.isShowingTomorrow
            ? S.t('nextPrayerTomorrow')
            : S.t('nextPrayer'));
    final target = phase?.iqamah ?? next.adhan;
    final remaining = target.difference(snapshot.date);
    final progress = phase != null
        ? (snapshot.date.difference(phase.adhan).inSeconds /
                phase.iqamah!.difference(phase.adhan).inSeconds)
            .clamp(0.0, 1.0)
            .toDouble()
        : snapshot.progress;
    final showLeave = phase != null &&
        settings.leaveLeadMinutes > 0 &&
        !snapshot.date.isBefore(
            phase.iqamah!.subtract(Duration(minutes: settings.leaveLeadMinutes)));
    final c = SurfaceColors.of(context);
    return AdaptiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(prayerIcon(hero.prayer), size: 18, color: c.accent),
              const SizedBox(width: 6),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
              const Spacer(),
              if (RamadanMode.isRamadanDay(snapshot.day) &&
                  (hero.prayer == Prayer.maghrib || hero.prayer == Prayer.fajr))
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    S.t(hero.prayer == Prayer.maghrib ? 'iftar' : 'suhoor'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: c.accent,
                    ),
                  ),
                ),
              if (next.isJumuah)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    S.t('jumuahBadge'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: c.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  hero.name,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: c.primary,
                  ),
                ),
              ),
              Text(
                PrayerFormat.time(target),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(phase != null ? Icons.campaign : Icons.groups,
                  size: 16, color: c.secondary),
              const SizedBox(width: 6),
              Text(
                phase != null
                    ? S.f('adhanWasAt',
                        {'time': PrayerFormat.time(phase.adhan)})
                    : (next.iqamah != null
                        ? '${next.iqamahLabel} ${S.t('at')} ${PrayerFormat.time(next.iqamah!)}'
                        : ''),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            PrayerFormat.countdown(remaining),
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.bold,
              color: c.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: c.panelTrack,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            phase != null
                ? S.f('untilIqamah', {'name': phase.name})
                : S.f('untilAdhan', {'name': next.name}),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
          if (showLeave) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.directions_walk, size: 16, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  S.t('timeToLeave'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: c.accent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


// MARK: - Schedule card

class ScheduleCard extends StatefulWidget {
  final PrayerSnapshot? snapshot;
  final PrayerDay? fixedDay;
  final String? fixedTitle;
  final bool large;

  ScheduleCard({
    super.key,
    required PrayerSnapshot snapshot,
    this.large = false,
  })  : snapshot = snapshot,
        fixedDay = null,
        fixedTitle = null;

  const ScheduleCard.forDay({
    super.key,
    required PrayerDay day,
    required String title,
    this.large = false,
  })  : snapshot = null,
        fixedDay = day,
        fixedTitle = title;

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  /// Today/Tomorrow preview toggle (v1.5). Null follows the snapshot
  /// (today, switching to tomorrow after Isha); tapping a segment
  /// pins the card to that day until the snapshot's day catches up.
  bool? _showTomorrow;

  static bool _sameDay(tz.TZDateTime a, tz.TZDateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final PrayerDay day;
    final String title;
    final PrayerSlot? highlight;
    var showToggle = false;
    var wantTomorrow = false;
    if (snapshot == null) {
      day = widget.fixedDay!;
      title = widget.fixedTitle!;
      highlight = null;
    } else {
      final todayDay = PrayerProvider.dayFor(snapshot.date);
      wantTomorrow = _showTomorrow ?? snapshot.isShowingTomorrow;
      if (wantTomorrow == snapshot.isShowingTomorrow) {
        day = snapshot.day;
      } else if (wantTomorrow) {
        final start = todayDay.date;
        day = PrayerProvider.computeDay(tz.TZDateTime(
            start.location, start.year, start.month, start.day + 1));
      } else {
        day = todayDay;
      }
      title = _sameDay(day.date, todayDay.date)
          ? S.t('todayTimes')
          : S.t('tomorrowTimes');
      // The "next" highlight only applies on the snapshot's own day.
      highlight = _sameDay(day.date, snapshot.day.date) ? snapshot.next : null;
      showToggle = true;
    }
    final large = widget.large;
    final nameSize = large ? 18.0 : 16.0;
    final timeSize = large ? 18.0 : 16.0;
    final c = SurfaceColors.of(context);
    return AdaptiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
              Text(
                PrayerFormat.shortDate(day.date),
                style: TextStyle(
                  fontSize: 15,
                  color: c.secondary,
                ),
              ),
            ],
          ),
          if (showToggle) ...[
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(S.t('today'))),
                ButtonSegment(value: true, label: Text(S.t('tomorrow'))),
              ],
              selected: {wantTomorrow},
              onSelectionChanged: (sel) =>
                  setState(() => _showTomorrow = sel.first),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _ColumnHeader(S.t('colPrayer'))),
                SizedBox(
                    width: large ? 104 : 86,
                    child: _ColumnHeader(S.t('colAdhan'), right: true)),
                SizedBox(
                    width: large ? 104 : 86,
                    child: _ColumnHeader(S.t('colIqamah'), right: true)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final slot in day.slots)
            _ScheduleRow(
              slot: slot,
              isNext: highlight != null &&
                  slot.prayer == highlight!.prayer &&
                  slot.adhan == highlight!.adhan,
              nameSize: nameSize,
              timeSize: timeSize,
              timeWidth: large ? 104 : 86,
            ),
          if (RamadanMode.isRamadanDay(day)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.nightlight, size: 16, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  S.t('taraweeh'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  S.t('estimate'),
                  style: TextStyle(fontSize: 11, color: c.muted),
                ),
                const Spacer(),
                Text(
                  PrayerFormat.time(RamadanMode.taraweehTime(
                      day, SettingsScope.of(context).taraweehOffsetMinutes)),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ],
            ),
          ],
          if (day.isFriday) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.mosque, size: 16, color: c.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    S.f('jumuahReplaces', {'time': PrayerFormat.khutbahTime()}),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final String text;
  final bool right;
  const _ColumnHeader(this.text, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: SurfaceColors.of(context).muted,
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final PrayerSlot slot;
  final bool isNext;
  final double nameSize;
  final double timeSize;
  final double timeWidth;

  const _ScheduleRow({
    required this.slot,
    required this.isNext,
    required this.nameSize,
    required this.timeSize,
    required this.timeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final c = SurfaceColors.of(context);
    final Color color = isNext
        ? c.accent
        : (slot.prayer == Prayer.sunrise ? c.muted : c.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: isNext
          ? BoxDecoration(
              color: c.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.accent.withValues(alpha: 0.65)),
            )
          : null,
      child: Row(
        children: [
          Icon(slot.isJumuah ? Icons.mosque : prayerIcon(slot.prayer),
              size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.name,
                  style: TextStyle(
                    fontSize: nameSize,
                    fontWeight: isNext ? FontWeight.bold : FontWeight.w600,
                    color: color,
                  ),
                ),
                if (slot.isJumuah)
                  Text(
                    S.t('khutbahShown'),
                    style: TextStyle(
                      fontSize: 11,
                      color: c.muted,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: timeWidth,
            child: Text(
              PrayerFormat.time(slot.adhan),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: timeSize,
                fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: timeWidth,
            child: Text(
              slot.iqamah != null ? PrayerFormat.time(slot.iqamah!) : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: timeSize,
                fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData prayerIcon(Prayer prayer) => switch (prayer) {
      Prayer.fajr => Icons.wb_twilight,
      Prayer.sunrise => Icons.wb_sunny_outlined,
      Prayer.dhuhr => Icons.sunny,
      Prayer.asr => Icons.brightness_6,
      Prayer.maghrib => Icons.nightlight_outlined,
      Prayer.isha => Icons.dark_mode,
    };

// MARK: - Footer

class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FooterLine(icon: Icons.location_on, text: MosqueInfo.address, style: style),
        const SizedBox(height: 8),
        _FooterLine(
          icon: Icons.mosque,
          text: S.f('jumuahWeeklyAt', {'time': PrayerFormat.khutbahTime()}),
          style: style,
        ),
        const SizedBox(height: 8),
        _FooterLine(
          icon: Icons.lock,
          text: S.t('footerPrivacy'),
          style: style,
        ),
        const SizedBox(height: 12),
        Text(
          S.t('footerCalc'),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FooterLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle style;
  const _FooterLine({required this.icon, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: style.color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

// MARK: - Qibla compass (v1.1.0)

/// Qibla bearing math: initial great-circle bearing from the mosque
/// to the Kaaba, plus Edmonton's magnetic declination (degrees East)
/// so the phone's magnetic compass can be corrected to true north.
class QiblaMath {
  static const kaabaLatitude = 21.422487;
  static const kaabaLongitude = 39.826206;
  static const magneticDeclination = 12.6;

  static double get bearingFromMosque {
    final lat1 = MosqueInfo.latitude * math.pi / 180;
    final lat2 = kaabaLatitude * math.pi / 180;
    final dLon = (kaabaLongitude - MosqueInfo.longitude) * math.pi / 180;
    final y = math.sin(dLon);
    final x = math.cos(lat1) * math.tan(lat2) - math.sin(lat1) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }
}

/// The Quran quote of the day card (v1.1.1): today's verse in Arabic,
/// its translation in the chosen language, and the reference. The
/// verses are embedded (daily_verse.dart) — fully offline.
class DailyVerseCard extends StatelessWidget {
  const DailyVerseCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SurfaceColors.of(context);
    final language = LanguageState.current;
    final verse = verseOfTheDay();
    final translation = verse.translation(language);
    final hadith = hadithOfTheDay();
    final hadithTranslation = hadith.translation(language);
    return AdaptiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.t('dailyVerse'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.share, size: 20, color: c.accent),
                tooltip: S.t('share'),
                onPressed: () => _shareVerse(verse, translation, language),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verse.arabic,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.6,
              color: c.primary,
            ),
          ),
          if (translation != null) ...[
            const SizedBox(height: 8),
            Text(
              translation,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.secondary),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            verse.reference(language),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.accent,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // Hadith of the day (v2.3.0), under the verse like iOS.
          Row(
            children: [
              Icon(Icons.forum, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.t('dailyHadith'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.share, size: 20, color: c.accent),
                tooltip: S.t('share'),
                onPressed: () =>
                    _shareHadith(hadith, hadithTranslation, language),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hadith.arabic,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.6,
              color: c.primary,
            ),
          ),
          if (hadithTranslation != null) ...[
            const SizedBox(height: 8),
            Text(
              hadithTranslation,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.secondary),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            hadith.source(language),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.accent,
            ),
          ),
        ],
      ),
    );
  }

  void _shareHadith(
      DailyHadith hadith, String? translation, AppLanguage language) {
    final lines = <String>[
      hadith.arabic,
      if (translation != null) translation,
      '${hadith.source(language)} — ${MosqueInfo.name}',
    ];
    _shareChannel.invokeMethod('share', {'text': lines.join('\n')});
  }

  /// Shares the verse as one block of text (v1.5, mirroring iOS):
  /// the Arabic, the translation when there is one, then the
  /// reference and the mosque name — via the native share sheet.
  static const _shareChannel = MethodChannel('alrashid/share');

  void _shareVerse(
      DailyVerse verse, String? translation, AppLanguage language) {
    final lines = <String>[
      verse.arabic,
      if (translation != null) translation,
      '${verse.reference(language)} — ${MosqueInfo.name}',
    ];
    _shareChannel.invokeMethod('share', {'text': lines.join('\n')});
  }
}

/// Upcoming Islamic dates card (v2.3.0): the next event large with
/// its countdown, then the following two — mirroring the iOS
/// HijriCountdownCard.
class HijriCountdownCard extends StatelessWidget {
  const HijriCountdownCard({super.key});

  String _relativeLabel(int days) => switch (days) {
        0 => S.t('today'),
        1 => S.t('tomorrow'),
        _ => S.f('eventInDaysFmt', {'days': '$days'}),
      };

  @override
  Widget build(BuildContext context) {
    final c = SurfaceColors.of(context);
    final upcoming = HijriEvents.upcoming(DateTime.now(), count: 3);
    final locale = LanguageState.current.name;
    return AdaptiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.nightlight_round, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Text(
                S.t('upcomingEvents'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
            ],
          ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    S.t(upcoming.first.event.key),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: c.primary,
                    ),
                  ),
                ),
                Text(
                  _relativeLabel(upcoming.first.days),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: c.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE, MMMM d', locale).format(upcoming.first.date),
              style: TextStyle(fontSize: 12, color: c.secondary),
            ),
            for (final item in upcoming.skip(1)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      S.t(item.event.key),
                      style: TextStyle(fontSize: 14, color: c.primary),
                    ),
                  ),
                  Text(
                    _relativeLabel(item.days),
                    style: TextStyle(fontSize: 14, color: c.secondary),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Home entry row for the 99 Names list (v2.3.0).
class NamesEntryCard extends StatelessWidget {
  const NamesEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SurfaceColors.of(context);
    return AdaptiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NamesOfAllahPage()),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 20, color: c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                S.t('namesOfAllah'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.secondary),
          ],
        ),
      ),
    );
  }
}

/// Shared heading stream (v1.5): one platform subscription to the
/// native 'alrashid/heading' EventChannel, fanned out in Dart so the
/// Qibla card and the full-screen compass page can listen at the same
/// time (the platform channel supports a single subscriber). Values
/// are true-north degrees — Edmonton's magnetic declination is added
/// here, once.
class HeadingService {
  static const _channel = EventChannel('alrashid/heading');
  static StreamSubscription<dynamic>? _platformSub;
  static final StreamController<double> _controller =
      StreamController<double>.broadcast(onListen: _start, onCancel: _stop);

  static Stream<double> get stream => _controller.stream;

  static void _start() {
    _platformSub ??= _channel.receiveBroadcastStream().listen((event) {
      final magnetic = (event as num).toDouble();
      _controller.add((magnetic + QiblaMath.magneticDeclination) % 360);
    }, onError: (_) {});
  }

  static void _stop() {
    _platformSub?.cancel();
    _platformSub = null;
  }
}

/// The Qibla card: a live compass dial fed by the native heading
/// EventChannel (MainActivity), the bearing from the mosque, and a
/// "facing the Qibla" state within 3 degrees. No location permission
/// is used — the bearing is computed from the mosque's fixed position.
class QiblaCard extends StatefulWidget {
  const QiblaCard({super.key});

  @override
  State<QiblaCard> createState() => _QiblaCardState();
}

class _QiblaCardState extends State<QiblaCard> {
  StreamSubscription<double>? _sub;
  double? _heading; // true-north compass heading, degrees

  double get _bearing => QiblaMath.bearingFromMosque;

  double? get _offset {
    final heading = _heading;
    if (heading == null) return null;
    var diff = (_bearing - heading) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  @override
  void initState() {
    super.initState();
    // No facing haptic here on purpose (v1.5.1 parity): the card's
    // listener runs even while the card is scrolled off-screen, so a
    // buzz would fire as the phone drifts past the bearing in a
    // pocket. The vibration lives in the full-screen compass page
    // only; the card keeps its visual "facing the Qibla" indicator.
    _sub = HeadingService.stream.listen((heading) {
      if (!mounted) return;
      setState(() => _heading = heading);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SurfaceColors.of(context);
    final offset = _offset;
    final facing = offset != null && offset.abs() <= 3;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QiblaCompassPage()),
        );
      },
      child: AdaptiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.explore, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Text(
                S.t('qibla'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _dial(c),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_bearing.round()}°',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: c.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      S.t('fromNorth'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      S.t('qiblaFromMosque'),
                      style: TextStyle(fontSize: 13, color: c.secondary),
                    ),
                    if (facing) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: c.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              S.t('facingQibla'),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: c.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            S.t('qiblaHint'),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.open_in_full, size: 14, color: c.accent),
              const SizedBox(width: 6),
              Text(
                S.t('tapForCompass'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _dial(SurfaceColors c) => QiblaDial(
        heading: _heading,
        bearing: _bearing,
        colors: c,
        size: 148,
      );
}

/// The rotating compass dial, shared by the Qibla card and the
/// full-screen compass (v1.5). The dial rotates against the phone's
/// heading; the Kaaba marker sits at the Qibla bearing, the fixed
/// triangle at the top is where the phone points. Letters orbit via
/// full-size rotated containers (their centers are the dial's center).
class QiblaDial extends StatelessWidget {
  final double? heading; // true-north compass heading, degrees
  final double bearing;
  final SurfaceColors colors;
  final double size;

  const QiblaDial({
    super.key,
    required this.heading,
    required this.bearing,
    required this.colors,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final headingRad = -(heading ?? 0) * math.pi / 180;
    final letters = [S.t('dir.n'), S.t('dir.e'), S.t('dir.s'), S.t('dir.w')];
    return SizedBox(
      width: size,
      height: size + 14,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(Icons.arrow_drop_up, size: 20, color: c.accent),
          Positioned(
            top: 14,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.panelTrack.withValues(alpha: 0.35),
                border: Border.all(color: c.muted.withValues(alpha: 0.35)),
              ),
              child: Transform.rotate(
                angle: headingRad,
                child: Stack(
                  children: [
                    for (var q = 0; q < 4; q++)
                      Transform.rotate(
                        angle: q * math.pi / 2,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              letters[q],
                              style: TextStyle(
                                fontSize: size > 200 ? 14 : 11,
                                fontWeight: FontWeight.bold,
                                color: c.secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Transform.rotate(
                      angle: bearing * math.pi / 180,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('🕋',
                              style:
                                  TextStyle(fontSize: size > 200 ? 34 : 24)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen Qibla compass (v1.5), opened by tapping the Qibla card:
/// the same live heading stream and dial, large, with the bearing
/// readout and the "facing the Qibla" state.
class QiblaCompassPage extends StatefulWidget {
  const QiblaCompassPage({super.key});

  @override
  State<QiblaCompassPage> createState() => _QiblaCompassPageState();
}

class _QiblaCompassPageState extends State<QiblaCompassPage> {
  StreamSubscription<double>? _sub;
  double? _heading; // true-north compass heading, degrees
  bool _facing = false;
  AppSettings? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = SettingsScope.of(context);
  }

  double get _bearing => QiblaMath.bearingFromMosque;

  double? get _offset {
    final heading = _heading;
    if (heading == null) return null;
    var diff = (_bearing - heading) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  @override
  void initState() {
    super.initState();
    _sub = HeadingService.stream.listen((heading) {
      if (!mounted) return;
      setState(() => _heading = heading);
      final offset = _offset;
      final facing = offset != null && offset.abs() <= 3;
      // The facing haptic lives ONLY on this full-screen page
      // (v1.5.1 parity), and only when the user keeps haptics on
      // (Settings → Qibla).
      if (facing && !_facing && (_settings?.hapticsEnabled ?? true)) {
        HapticFeedback.lightImpact();
      }
      _facing = facing;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SurfaceColors.of(context);
    final offset = _offset;
    final facing = offset != null && offset.abs() <= 3;
    final dialSize = math.min(300.0, MediaQuery.of(context).size.width - 64);
    return Scaffold(
      appBar: AppBar(title: Text(S.t('qiblaCompass'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QiblaDial(
                  heading: _heading,
                  bearing: _bearing,
                  colors: c,
                  size: dialSize,
                ),
                const SizedBox(height: 24),
                Text(
                  '${_bearing.round()}°',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: c.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  S.t('fromNorth'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.t('qiblaFromMosque'),
                  style: TextStyle(fontSize: 15, color: c.secondary),
                ),
                if (facing) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 20, color: c.accent),
                      const SizedBox(width: 6),
                      Text(
                        S.t('facingQibla'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: c.accent,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  S.t('qiblaHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Suhoor / Iftar row for Minimal Mode (v2.0.0): shown on fasting
/// days and every day in Ramadan.
class _FastingTimesRow extends StatelessWidget {
  final PrayerDay day;
  const _FastingTimesRow({required this.day});

  @override
  Widget build(BuildContext context) {
    final accent = SurfaceColors.of(context).accent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.nightlight_round, size: 18, color: accent),
          const SizedBox(width: 6),
          Text('${S.t('suhoor')} · ${PrayerFormat.time(day.adhan(Prayer.fajr))}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Icon(Icons.wb_twilight, size: 18, color: accent),
          const SizedBox(width: 6),
          Text(
              '${S.t('iftar')} · ${PrayerFormat.time(day.adhan(Prayer.maghrib))}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
