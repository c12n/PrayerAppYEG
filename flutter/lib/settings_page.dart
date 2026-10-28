// Settings page (v1.0.5) — the Android counterpart of the iOS Settings
// page: appearance mode, theme colors with presets and a color picker,
// designed themes, save-your-own themes, widget countdown choices,
// privacy notes and Reset to Defaults. Changes are saved immediately
// (shared_preferences) and the home-screen widgets read the same values.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'prayer_models.dart';

class SettingsPage extends StatelessWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _sectionHeader(context, 'Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (sel) =>
                      settings.update(() => settings.mode = sel.first),
                ),
              ),
              _sectionNote(context,
                  "System follows your phone's Light/Dark setting. Light keeps the background white; Dark keeps it black."),
              _sectionHeader(context, 'Theme Colors'),
              _ColorRow(
                title: 'Main color',
                caption: 'Cards and buttons (the green)',
                presets: primaryPresets,
                currentHex: settings.primaryHex,
                onPick: (hex) => settings.update(() => settings.primaryHex = hex),
              ),
              _ColorRow(
                title: 'Accent color',
                caption: 'Countdowns and highlights (the gold)',
                presets: accentPresets,
                currentHex: settings.accentHex,
                onPick: (hex) => settings.update(() => settings.accentHex = hex),
              ),
              _ColorRow(
                title: 'Text color',
                caption: 'Text on the colored cards',
                presets: textPresets,
                currentHex: settings.textHex,
                onPick: (hex) => settings.update(() {
                  settings.textHex = hex;
                  settings.textIsCustom = true;
                }),
              ),
              _sectionNote(context,
                  'Tap a circle for a preset, or the color wheel for any color. Text is automatically adjusted when needed so it always stays easy to read. The widgets use the same accent color.'),
              _sectionHeader(context, 'Themes'),
              for (final theme in presetThemes)
                _ThemeRow(
                  theme: theme,
                  subtitle: 'Designed theme',
                  onTap: () => settings.applyTheme(theme),
                ),
              for (final theme in settings.savedThemes)
                _ThemeRow(
                  theme: theme,
                  subtitle: 'Your saved theme',
                  onTap: () => settings.applyTheme(theme),
                  onDelete: () => settings.update(() =>
                      settings.savedThemes =
                          settings.savedThemes.where((t) => t.id != theme.id).toList()),
                ),
              ListTile(
                leading: const Icon(Icons.bookmark_add),
                title: const Text('Save current colors as a theme'),
                onTap: () => _saveTheme(context),
              ),
              _sectionNote(context,
                  'Themes are ready-made color sets designed to look good together — main color, accent and text in one tap.'),
              _sectionHeader(context, 'Widget Countdown'),
              for (final prayer in Prayer.values)
                SwitchListTile(
                  secondary: Icon(_prayerIcon(prayer)),
                  title: Text(prayer == Prayer.dhuhr
                      ? "Dhuhr (Jumu'ah on Fridays)"
                      : prayer.displayName),
                  value: settings.alerts[prayer] ?? false,
                  onChanged: (v) =>
                      settings.update(() => settings.alerts[prayer] = v),
                ),
              _sectionNote(context,
                  'Choose which times the countdown moves to, in the app and in the home-screen widgets. Sunrise is off by default — turn it on to count down to the end of Fajr time too. Changes reach the widgets at their next refresh.'),
              _sectionHeader(context, 'Privacy'),
              const ListTile(
                leading: Icon(Icons.pan_tool),
                title: Text('No data collected'),
                subtitle: Text('No accounts, no tracking, no ads, no analytics.'),
              ),
              const ListTile(
                leading: Icon(Icons.lock),
                title: Text('Everything stays on this device'),
                subtitle: Text(
                    'Prayer times are calculated on your phone. Your settings never leave the device — the widgets read them locally.'),
              ),
              _sectionHeader(context, 'Reset'),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Colors.red),
                title: const Text('Reset to Defaults',
                    style: TextStyle(color: Colors.red)),
                onTap: () => _confirmReset(context),
              ),
              _sectionNote(context,
                  'Restores the original appearance, colors and countdown choices. Your saved themes are kept.'),
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
        title: const Text('Save Theme'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Theme name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
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
        title: const Text('Reset to Defaults?'),
        content: const Text(
            'This restores the original appearance, colors and countdown choices. Your saved themes are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) settings.resetToDefaults();
  }
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
                tooltip: 'Pick a custom color',
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
      title: const Text('Pick a color'),
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
          _slider('Hue', _hsv.hue, 360,
              (v) => setState(() => _hsv = _hsv.withHue(v))),
          _slider('Saturation', _hsv.saturation, 1,
              (v) => setState(() => _hsv = _hsv.withSaturation(v))),
          _slider('Brightness', _hsv.value, 1,
              (v) => setState(() => _hsv = _hsv.withValue(v))),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, hexFromColor(color)),
            child: const Text('Use this color')),
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
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ThemeRow({
    required this.theme,
    required this.subtitle,
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
      subtitle: Text('$subtitle · ${theme.mode.name[0].toUpperCase()}${theme.mode.name.substring(1)}'),
      trailing: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete theme',
              onPressed: onDelete,
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
