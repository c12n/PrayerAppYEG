// Settings page (v1.0.5) — the Android counterpart of the iOS Settings
// page: appearance mode, theme colors with presets and a color picker,
// designed themes, save-your-own themes, widget countdown choices,
// privacy notes and Reset to Defaults. Changes are saved immediately
// (shared_preferences) and the home-screen widgets read the same values.

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_settings.dart';
import 'prayer_models.dart';
import 'strings.dart';

class SettingsPage extends StatelessWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(S.t('settings'))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _sectionHeader(context, S.t('language')),
              for (final language in AppLanguage.values)
                ListTile(
                  title: Text(language.nativeName),
                  trailing: settings.language == language
                      ? Icon(Icons.check_circle,
                          color: accentFor(
                              Theme.of(context).brightness, settings))
                      : null,
                  onTap: () =>
                      settings.update(() => settings.language = language),
                ),
              _sectionNote(context, S.t('languageNote')),
              _sectionHeader(context, S.t('appearance')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(S.t('mode.system')), icon: const Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.light, label: Text(S.t('mode.light')), icon: const Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(S.t('mode.dark')), icon: const Icon(Icons.dark_mode)),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (sel) =>
                      settings.update(() => settings.mode = sel.first),
                ),
              ),
              _sectionNote(context, S.t('appearanceNote')),
              _sectionHeader(context, S.t('themeColors')),
              _ColorRow(
                title: S.t('mainColor'),
                caption: S.t('mainColorCaption'),
                presets: primaryPresets,
                currentHex: settings.primaryHex,
                onPick: (hex) => settings.update(() => settings.primaryHex = hex),
              ),
              _ColorRow(
                title: S.t('accentColor'),
                caption: S.t('accentColorCaption'),
                presets: accentPresets,
                currentHex: settings.accentHex,
                onPick: (hex) => settings.update(() => settings.accentHex = hex),
              ),
              _ColorRow(
                title: S.t('textColor'),
                caption: S.t('textColorCaption'),
                presets: textPresets,
                currentHex: settings.textHex,
                onPick: (hex) => settings.update(() {
                  settings.textHex = hex;
                  settings.textIsCustom = true;
                }),
              ),
              _sectionNote(context, S.t('colorsNote')),
              _sectionHeader(context, S.t('themes')),
              _themePreview(context, settings),
              for (final theme in presetThemes)
                _ThemeRow(
                  theme: theme,
                  subtitle: S.t('designedTheme'),
                  isActive: settings.isActiveTheme(theme),
                  onTap: () => settings.applyTheme(theme),
                ),
              for (final theme in settings.savedThemes)
                _ThemeRow(
                  theme: theme,
                  subtitle: S.t('savedTheme'),
                  isActive: settings.isActiveTheme(theme),
                  onTap: () => settings.applyTheme(theme),
                  onDelete: () => settings.update(() =>
                      settings.savedThemes =
                          settings.savedThemes.where((t) => t.id != theme.id).toList()),
                ),
              ListTile(
                leading: const Icon(Icons.bookmark_add),
                title: Text(S.t('saveCurrentTheme')),
                onTap: () => _saveTheme(context),
              ),
              _sectionNote(context, S.t('themesNote')),
              _sectionHeader(context, S.t('textSize')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<AppTextSize>(
                  segments: [
                    for (final size in AppTextSize.values)
                      ButtonSegment(
                          value: size, label: Text(S.t(size.l10nKey))),
                  ],
                  selected: {settings.textSize},
                  onSelectionChanged: (sel) =>
                      settings.update(() => settings.textSize = sel.first),
                ),
              ),
              _sectionNote(context, S.t('textSizeNote')),
              _sectionHeader(context, S.t('widgetCountdown')),
              for (final prayer in Prayer.values)
                SwitchListTile(
                  secondary: Icon(_prayerIcon(prayer)),
                  title: Text(prayer == Prayer.dhuhr
                      ? S.t('dhuhrFriday')
                      : prayer.displayName),
                  value: settings.alerts[prayer] ?? false,
                  onChanged: (v) =>
                      settings.update(() => settings.alerts[prayer] = v),
                ),
              _sectionNote(context, S.t('widgetCountdownNote')),
              _sectionHeader(context, S.t('privacy')),
              ListTile(
                leading: const Icon(Icons.pan_tool),
                title: Text(S.t('noDataCollected')),
                subtitle: Text(S.t('noDataBody')),
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: Text(S.t('staysOnDevice')),
                subtitle: Text(S.t('staysOnDeviceBody')),
              ),
              ListTile(
                leading: const Icon(Icons.link_off),
                title: Text(S.t('noExternalLinks')),
                subtitle: Text(S.t('noExternalLinksBody')),
              ),
              _sectionHeader(context, S.t('resetHeader')),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Colors.red),
                title: Text(S.t('reset'),
                    style: const TextStyle(color: Colors.red)),
                onTap: () => _confirmReset(context),
              ),
              _sectionNote(context, S.t('resetNote')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveTheme(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('saveTheme')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.t('themeName')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(S.t('save'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    settings.update(() {
      settings.savedThemes = [
        ...settings.savedThemes,
        SavedTheme(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          primaryHex: settings.primaryHex,
          accentHex: settings.accentHex,
          textHex: settings.textHex,
          mode: settings.mode,
        ),
      ];
    });
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('resetDialogTitle')),
        content: Text(S.t('resetDialogContent')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.t('resetButton'))),
        ],
      ),
    );
    if (ok == true) settings.resetToDefaults();
  }
}

/// A miniature next-prayer card in the current colors. It rebuilds the
/// instant a theme or color changes, so the effect of a tap is visible
/// right here in Settings — no need to leave the page to see the theme.
Widget _themePreview(BuildContext context, AppSettings settings) {
  final primary = colorFromHex(settings.primaryHex);
  final accent = colorFromHex(settings.accentHex);
  final onPrimary = resolvedTextColor(darkSurface: true, s: settings);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lightenColor(primary, 0.16), primary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('nextPrayerPreview'),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: onPrimary.withValues(alpha: 0.75))),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(Prayer.fajr.displayName,
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: onPrimary)),
              const Spacer(),
              Text(PrayerFormat.time(tz.TZDateTime(edmontonLocation(), 2026, 1, 2, 6, 28)),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: onPrimary)),
            ],
          ),
          const SizedBox(height: 2),
          Text('7:49:52',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    ),
  );
}

Widget _sectionHeader(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

Widget _sectionNote(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );

IconData _prayerIcon(Prayer prayer) => switch (prayer) {
      Prayer.fajr => Icons.wb_twilight,
      Prayer.sunrise => Icons.wb_sunny_outlined,
      Prayer.dhuhr => Icons.sunny,
      Prayer.asr => Icons.brightness_6,
      Prayer.maghrib => Icons.nightlight_outlined,
      Prayer.isha => Icons.dark_mode,
    };

class _ColorRow extends StatelessWidget {
  final String title;
  final String caption;
  final List<(String, int)> presets;
  final int currentHex;
  final void Function(int hex) onPick;

  const _ColorRow({
    required this.title,
    required this.caption,
    required this.presets,
    required this.currentHex,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(caption,
                        style: TextStyle(
                            fontSize: 12.5,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.color_lens),
                tooltip: S.t('customColorTooltip'),
                onPressed: () async {
                  final hex = await showDialog<int>(
                    context: context,
                    builder: (_) => _HsvPickerDialog(initialHex: currentHex),
                  );
                  if (hex != null) onPick(hex);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final (name, hex) in presets)
                Tooltip(
                  message: name,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onPick(hex),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorFromHex(hex),
                        border: Border.all(
                          color: hex == currentHex
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black26,
                          width: hex == currentHex ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A simple HSV color picker: preview + three sliders.
class _HsvPickerDialog extends StatefulWidget {
  final int initialHex;
  const _HsvPickerDialog({required this.initialHex});

  @override
  State<_HsvPickerDialog> createState() => _HsvPickerDialogState();
}

class _HsvPickerDialogState extends State<_HsvPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(colorFromHex(widget.initialHex));
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(S.t('pickColor')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(height: 8),
          _slider(S.t('hue'), _hsv.hue, 360,
              (v) => setState(() => _hsv = _hsv.withHue(v))),
          _slider(S.t('saturation'), _hsv.saturation, 1,
              (v) => setState(() => _hsv = _hsv.withSaturation(v))),
          _slider(S.t('brightness'), _hsv.value, 1,
              (v) => setState(() => _hsv = _hsv.withValue(v))),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.t('cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, hexFromColor(color)),
            child: Text(S.t('useThisColor'))),
      ],
    );
  }

  Widget _slider(
      String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 86, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final SavedTheme theme;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ThemeRow({
    required this.theme,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lightenColor(colorFromHex(theme.primaryHex), 0.16),
              colorFromHex(theme.primaryHex),
            ],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text('Aa',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorFromHex(theme.textHex))),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorFromHex(theme.accentHex),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(theme.name),
      subtitle: Text('$subtitle · ${S.t('mode.${theme.mode.name}')}'),
      trailing: onDelete != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Icon(Icons.check_circle,
                      color: colorFromHex(theme.accentHex)),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: S.t('deleteTheme'),
                  onPressed: onDelete,
                ),
              ],
            )
          : isActive
              ? Icon(Icons.check_circle, color: colorFromHex(theme.accentHex))
              : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
