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
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/date_symbol_data_local.dart';

import 'app_settings.dart';
import 'prayer_models.dart';
import 'settings_page.dart';
import 'daily_verse.dart';
import 'strings.dart';

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

class _HomePageState extends State<HomePage> {
  Timer? _timer;
  late tz.TZDateTime _now;

  tz.Location get _edmonton => edmontonLocation();

  @override
  void initState() {
    super.initState();
    _now = tz.TZDateTime.now(_edmonton);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = tz.TZDateTime.now(_edmonton));
    });
  }

  @override
  void dispose() {
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

  // Phone: single column.
  Widget _phoneLayout(
      BuildContext context, PrayerSnapshot snapshot, PrayerDay today) {
    return SingleChildScrollView(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HeaderSection(today: today, now: _now),
                  const SizedBox(height: 20),
                  NextPrayerCard(snapshot: snapshot),
                  const SizedBox(height: 20),
                  const DailyVerseCard(),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HeaderSection(today: today, now: _now),
                      const SizedBox(height: 24),
                      NextPrayerCard(snapshot: snapshot),
                      const SizedBox(height: 24),
                      const DailyVerseCard(),
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
                  child: ScheduleCard(snapshot: snapshot, large: true),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SingleChildScrollView(
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
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: S.t('settings'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SettingsPage(settings: SettingsScope.of(context)),
                  ),
                );
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
    final caption = snapshot.isShowingTomorrow
        ? S.t('nextPrayerTomorrow')
        : S.t('nextPrayer');
    final remaining = next.adhan.difference(snapshot.date);
    final c = SurfaceColors.of(context);
    return AdaptiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(prayerIcon(next.prayer), size: 18, color: c.accent),
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
                  next.name,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: c.primary,
                  ),
                ),
              ),
              Text(
                PrayerFormat.time(next.adhan),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
            ],
          ),
          if (next.iqamah != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.groups, size: 16, color: c.secondary),
                const SizedBox(width: 6),
                Text(
                  '${next.iqamahLabel} ${S.t('at')} ${PrayerFormat.time(next.iqamah!)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.secondary,
                  ),
                ),
              ],
            ),
          ],
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
              value: snapshot.progress,
              minHeight: 6,
              backgroundColor: c.panelTrack,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.f('untilAdhan', {'name': next.name}),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Schedule card

class ScheduleCard extends StatelessWidget {
  final PrayerDay day;
  final String title;
  final PrayerSlot? highlight;
  final bool large;

  ScheduleCard({
    super.key,
    required PrayerSnapshot snapshot,
    this.large = false,
  })  : day = snapshot.day,
        title = snapshot.isShowingTomorrow
            ? S.t('tomorrowTimes')
            : S.t('todayTimes'),
        highlight = snapshot.next;

  const ScheduleCard.forDay({
    super.key,
    required this.day,
    required this.title,
    this.large = false,
  }) : highlight = null;

  @override
  Widget build(BuildContext context) {
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
    return AdaptiveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Text(
                S.t('dailyVerse'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
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
        ],
      ),
    );
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
  static const _channel = EventChannel('alrashid/heading');
  StreamSubscription<dynamic>? _sub;
  double? _heading; // true-north compass heading, degrees
  bool _facing = false;

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
    _sub = _channel.receiveBroadcastStream().listen((event) {
      if (!mounted) return;
      final magnetic = (event as num).toDouble();
      setState(() {
        _heading = (magnetic + QiblaMath.magneticDeclination) % 360;
      });
      final offset = _offset;
      final facing = offset != null && offset.abs() <= 3;
      if (facing && !_facing) HapticFeedback.lightImpact();
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
    return AdaptiveCard(
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
        ],
      ),
    );
  }

  /// The dial rotates against the phone's heading; the Kaaba marker
  /// sits at the Qibla bearing, the fixed triangle at the top is where
  /// the phone points. Letters orbit via full-size rotated containers
  /// (their centers are the dial's center).
  Widget _dial(SurfaceColors c) {
    const size = 148.0;
    final headingRad = -(_heading ?? 0) * math.pi / 180;
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
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: c.secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Transform.rotate(
                      angle: _bearing * math.pi / 180,
                      child: const Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text('🕋', style: TextStyle(fontSize: 24)),
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
