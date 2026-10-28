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

import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'prayer_models.dart';
import 'settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
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
          const ActionButtons(),
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
                  const ActionButtons(),
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
                      const ActionButtons(),
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
                    title: "Tomorrow's Prayer Times",
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
              'Assalamu Alaikum',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
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
    final caption =
        snapshot.isShowingTomorrow ? 'Next prayer · Tomorrow' : 'Next prayer';
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
                    "JUMU'AH",
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
                  '${next.iqamahLabel} at ${PrayerFormat.time(next.iqamah!)}',
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
            'until ${next.name} Adhan',
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
            ? "Tomorrow's Prayer Times"
            : "Today's Prayer Times",
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
                const Expanded(child: _ColumnHeader('PRAYER')),
                SizedBox(
                    width: large ? 104 : 86,
                    child: const _ColumnHeader('ADHAN', right: true)),
                SizedBox(
                    width: large ? 104 : 86,
                    child: const _ColumnHeader('IQAMAH', right: true)),
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
                    "Jumu'ah replaces Dhuhr · Khutbah at ${PrayerFormat.khutbahTime()}",
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
                    'Khutbah time shown',
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

// MARK: - Actions & footer

class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final primary = colorFromHex(settings.primaryHex);
    final accent = colorFromHex(settings.accentHex);
    return Row(
      children: [
        Expanded(
          child: _GradientButton(
            label: 'Directions',
            icon: Icons.directions_car,
            foreground: darkenColor(primary, 0.30),
            colors: [lightenColor(accent, 0.25), accent],
            onTap: () => _open(MosqueInfo.directionsUrl),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GradientButton(
            label: 'Website',
            icon: Icons.language,
            foreground: resolvedTextColor(darkSurface: true, s: settings),
            colors: [
              lightenColor(primary, 0.16),
              primary,
              darkenColor(primary, 0.30),
            ],
            borderColor: accent.withValues(alpha: 0.6),
            onTap: () => _open(MosqueInfo.websiteUrl),
          ),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foreground;
  final List<Color> colors;
  final Color? borderColor;
  final VoidCallback onTap;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.colors,
    required this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(16),
            border:
                borderColor != null ? Border.all(color: borderColor!) : null,
            boxShadow: [
              BoxShadow(
                color: darkenColor(
                        colorFromHex(SettingsScope.of(context).primaryHex),
                        0.30)
                    .withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
          text: "Jumu'ah Khutbah every Friday at ${PrayerFormat.khutbahTime()}",
          style: style,
        ),
        const SizedBox(height: 12),
        Text(
          "Adhan times are calculated on-device and calibrated to Al Rashid Mosque's published timetable. Iqamah times are fixed offsets from Adhan — please confirm with the mosque's official timetable.",
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
