// Settings page (v1.0.5) — the Android counterpart of the iOS Settings
// page: appearance mode, theme colors with presets and a color picker,
// designed themes, save-your-own themes, widget countdown choices,
// privacy notes and Reset to Defaults. Changes are saved immediately
// (shared_preferences) and the home-screen widgets read the same values.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'alert_health.dart';
import 'alerts.dart';
import 'layout.dart';
import 'app_settings.dart';
import 'live_notification.dart';
import 'prayer_models.dart';
import 'settings_backup.dart';
import 'strings.dart';

class SettingsPage extends StatelessWidget {
  final AppSettings settings;
  const SettingsPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        // The sections as blocks (v3.0.0), so expanded windows
        // can flow them down two columns; compact and medium
        // windows render the same single list as always.
        final blocks = <Widget>[
          _block([
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
          ]),
          _block([
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
          ]),
          _block([
            _sectionHeader(context, S.t('minimalMode')),
              SwitchListTile(
                secondary: const Icon(Icons.view_agenda_outlined),
                title: Text(S.t('minimalMode')),
                value: settings.minimalMode,
                onChanged: (v) =>
                    settings.update(() => settings.minimalMode = v),
              ),
              _sectionNote(context, S.t('minimalModeFooter')),
          ]),
          _block([
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
          ]),
          _block([
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
          ]),
          _block([
            _sectionHeader(context, S.t('widgetColors')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'match',
                        label: Text(S.t('widgetColorMatch')),
                        icon: const Icon(Icons.link)),
                    ButtonSegment(
                        value: 'separate',
                        label: Text(S.t('widgetColorSeparate')),
                        icon: const Icon(Icons.tune)),
                  ],
                  selected: {settings.widgetColorMode},
                  onSelectionChanged: (sel) => settings
                      .update(() => settings.widgetColorMode = sel.first),
                ),
              ),
              if (settings.widgetColorMode == 'separate') ...[
                ListTile(
                  title: Text(S.t('widgetPartHome')),
                  subtitle: Text(settings.homeWidgetTheme?.name ?? S.t('appTheme')),
                ),
                for (final theme in presetThemes)
                  _ThemeRow(
                    theme: theme,
                    subtitle: S.t('designedTheme'),
                    isActive: settings.homeWidgetTheme?.primaryHex == theme.primaryHex &&
                        settings.homeWidgetTheme?.accentHex == theme.accentHex &&
                        settings.homeWidgetTheme?.textHex == theme.textHex,
                    onTap: () =>
                        settings.update(() => settings.homeWidgetTheme = theme),
                  ),
                for (final theme in settings.savedThemes)
                  _ThemeRow(
                    theme: theme,
                    subtitle: S.t('savedTheme'),
                    isActive: settings.homeWidgetTheme?.primaryHex == theme.primaryHex &&
                        settings.homeWidgetTheme?.accentHex == theme.accentHex &&
                        settings.homeWidgetTheme?.textHex == theme.textHex,
                    onTap: () =>
                        settings.update(() => settings.homeWidgetTheme = theme),
                  ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: Text(S.t('appTheme')),
                  onTap: () =>
                      settings.update(() => settings.homeWidgetTheme = null),
                ),
              ],
              _sectionNote(
                  context,
                  S.t(settings.widgetColorMode == 'separate'
                      ? 'widgetColorsNoteSeparate'
                      : 'widgetColorsNoteMatch')),
          ]),
          _block([
            _sectionHeader(context, S.t('iqamahFirst')),
              SwitchListTile(
                title: Text(S.t('iqamahFirst')),
                value: settings.iqamahFirst,
                onChanged: (v) =>
                    settings.update(() => settings.iqamahFirst = v),
              ),
              if (settings.iqamahFirst)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final lead in [0, 5, 10, 15, 20])
                        ChoiceChip(
                          label: Text(lead == 0
                              ? S.t('leaveOff')
                              : S.f('leaveMinutes',
                                  {'minutes': '$lead'})),
                          selected: settings.leaveLeadMinutes == lead,
                          onSelected: (_) => settings.update(
                              () => settings.leaveLeadMinutes = lead),
                        ),
                    ],
                  ),
                ),
              _sectionNote(context, S.t('iqamahFirstFooter')),
          ]),
          _block([
            _sectionHeader(context, S.t('ramadan')),
              ListTile(
                title: Text(S.t('taraweehAfterIsha')),
                subtitle: Text(S.t('taraweeh')),
                trailing: DropdownButton<int>(
                  value: settings.taraweehOffsetMinutes,
                  items: [
                    for (final m in [0, 15, 30, 45, 60])
                      DropdownMenuItem(
                        value: m,
                        child: Text(
                            S.f('taraweehOffset', {'minutes': '$m'})),
                      ),
                  ],
                  onChanged: (v) => settings
                      .update(() => settings.taraweehOffsetMinutes = v ?? 15),
                ),
              ),
              _sectionNote(context, S.t('ramadanFooter')),
          ]),
          _block([
            _sectionHeader(context, S.t('fasting')),
              SwitchListTile(
                title: Text(S.t('fastingMonThu')),
                value: settings.fastingMonThu,
                onChanged: (v) {
                  settings.update(() => settings.fastingMonThu = v);
                  AlertScheduler.refresh(settings);
                },
              ),
              SwitchListTile(
                title: Text(S.t('fastingWhiteDays')),
                value: settings.fastingWhiteDays,
                onChanged: (v) {
                  settings.update(() => settings.fastingWhiteDays = v);
                  AlertScheduler.refresh(settings);
                },
              ),
              _sectionNote(context, S.t('fastingFooter')),
          ]),
          _block([
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
          ]),
          _block([
            _sectionHeader(context, S.t('hijriDate')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: -1, label: Text('-1')),
                    ButtonSegment(value: 0, label: Text('0')),
                    ButtonSegment(value: 1, label: Text('+1')),
                  ],
                  selected: {settings.hijriOffsetDays},
                  onSelectionChanged: (sel) => settings
                      .update(() => settings.hijriOffsetDays = sel.first),
                ),
              ),
              _sectionNote(context, S.t('hijriOffsetFooter')),
          ]),
          _block([
            _sectionHeader(context, S.t('alerts')),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active),
                title: Text(S.t('adhanNotifications')),
                subtitle: Text(S.t('notificationsBody')),
                value: settings.notificationsEnabled,
                onChanged: (v) {
                  settings.update(() => settings.notificationsEnabled = v);
                  AlertScheduler.refresh(settings, askPermission: v);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.alarm),
                title: Text(S.t('reminder')),
                subtitle: Text(S.t('reminderBody')),
                value: settings.reminderEnabled,
                onChanged: (v) {
                  settings.update(() => settings.reminderEnabled = v);
                  AlertScheduler.refresh(settings);
                },
              ),
              if (settings.reminderEnabled)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(S.f('minutesBefore',
                      {'minutes': '${settings.reminderLeadMinutes}'})),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickLeadMinutes(context),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.mosque),
                title: Text(S.t('jumuahReminder')),
                subtitle: Text(S.t('jumuahReminderBody')),
                value: settings.jumuahReminderEnabled,
                onChanged: (v) {
                  settings.update(() => settings.jumuahReminderEnabled = v);
                  AlertScheduler.refresh(settings);
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: Text(S.t('alertSound')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(S.t('sound.${settings.alertSound}')),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _pickSound(context),
              ),
          ]),
          _block([
            _sectionHeader(context, S.t('prayerSounds')),
              for (final prayer in Prayer.values)
                ListTile(
                  leading: Icon(_prayerIcon(prayer)),
                  title: Text(prayer == Prayer.dhuhr
                      ? S.t('dhuhrFriday')
                      : prayer.displayName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(settings.prayerSoundOverrides[prayer] != null
                          ? S.t(
                              'sound.${settings.prayerSoundOverrides[prayer]}')
                          : S.t('useAppSound')),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _pickPrayerSound(context, prayer),
                ),
              _sectionNote(context, S.t('prayerSoundsFooter')),
          ]),
          _block([
            _sectionHeader(context, S.t('alertHealth')),
              ListTile(
                leading: const Icon(Icons.favorite),
                title: Text(S.t('alertHealth')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AlertHealthPage(settings: settings),
                  ),
                ),
              ),
              _sectionNote(context, S.t('alertHealthFooter')),
          ]),
          _block([
            _sectionHeader(context, S.t('qibla')),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: Text(S.t('haptics')),
                subtitle: Text(S.t('hapticsBody')),
                value: settings.hapticsEnabled,
                onChanged: (v) =>
                    settings.update(() => settings.hapticsEnabled = v),
              ),
          ]),
          _block([
            _sectionHeader(context, S.t('widgetCountdown')),
              for (final prayer in Prayer.values)
                SwitchListTile(
                  secondary: Icon(_prayerIcon(prayer)),
                  title: Text(prayer == Prayer.dhuhr
                      ? S.t('dhuhrFriday')
                      : prayer.displayName),
                  value: settings.alerts[prayer] ?? false,
                  onChanged: (v) {
                    settings.update(() => settings.alerts[prayer] = v);
                    AlertScheduler.refresh(settings);
                  },
                ),
              _sectionNote(context, S.t('widgetCountdownNote')),
          ]),
          _block([
            _sectionHeader(context, S.t('assistant')),
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(S.t('silenceNext')),
                onTap: () => _silenceNext(context, settings),
              ),
              _sectionNote(context, S.t('assistantFooter')),
          ]),
          _BackupSection(settings: settings),
          _block([
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
          ]),
          _block([
            _sectionHeader(context, S.t('ongoingTitle')),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: Text(S.t('ongoingTitle')),
                subtitle: Text(S.t('ongoingBody')),
                value: settings.ongoingEnabled,
                onChanged: (v) {
                  settings.update(() => settings.ongoingEnabled = v);
                  OngoingNotification.sync(v);
                },
              ),
          ]),
          _block([
            _sectionHeader(context, S.t('appIcon')),
              ListTile(
                leading: const Icon(Icons.apps),
                title: Text(S.t('appIcon')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(S.t('icon.${_iconLabelKey(settings.appIcon)}')),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _pickAppIcon(context),
              ),
              _sectionNote(context, S.t('appIconNote')),
          ]),
          _block([
            _sectionHeader(context, S.t('resetHeader')),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Colors.red),
                title: Text(S.t('reset'),
                    style: const TextStyle(color: Colors.red)),
                onTap: () => _confirmReset(context),
              ),
              _sectionNote(context, S.t('resetNote')),
          ]),
          _block([
            Padding(
              padding: const EdgeInsets.only(top: 28),
                child: Center(
                  child: Text(
                    '${S.t('version')} $kAppVersion ($kAppBuildNumber)',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ]),
        ];
        return Scaffold(
          appBar: AppBar(title: Text(S.t('settings'))),
          body: windowSizeClassOf(context).isExpanded
              ? _twoColumnSettings(context, blocks)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: blocks,
                ),
        );
      },
    );
  }

  /// One settings section (header + contents + note) as a
  /// single block, so the expanded layout can distribute whole
  /// sections between columns without splitting one in half.
  Widget _block(List<Widget> children) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );

  /// Expanded windows (Chromebooks, tablets, unfolded
  /// foldables): the sections flow down two independently
  /// scrolling columns — the first half on the leading side,
  /// the rest (with the version footer last) on the trailing
  /// side.
  Widget _twoColumnSettings(BuildContext context, List<Widget> blocks) {
    final half = (blocks.length - 1) ~/ 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: blocks.sublist(0, half),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: blocks.sublist(half),
              ),
            ),
          ),
        ],
      ),
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
    if (ok == true) {
      settings.resetToDefaults();
      AlertScheduler.refresh(settings);
    }
  }

  Future<void> _pickLeadMinutes(BuildContext context) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(S.t('reminder')),
        children: [
          for (final minutes in AppSettings.reminderLeadOptions)
            ListTile(
              title: Text(S.f('minutesBefore', {'minutes': '$minutes'})),
              trailing: settings.reminderLeadMinutes == minutes
                  ? Icon(Icons.check_circle,
                      color:
                          accentFor(Theme.of(context).brightness, settings))
                  : null,
              onTap: () => Navigator.pop(context, minutes),
            ),
        ],
      ),
    );
    if (picked == null) return;
    settings.update(() => settings.reminderLeadMinutes = picked);
    AlertScheduler.refresh(settings);
  }

  /// App-wide Adhan sound picker (v1.8.0).
  Future<void> _pickSound(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(S.t('alertSound')),
        children: [
          for (final sound in alertSoundNames)
            ListTile(
              title: Text(S.t('sound.$sound')),
              // Build 34: a small play button hears the sound
              // without selecting it; the check still marks the
              // current selection. Default and Silent have no
              // bundled file to preview.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sound != 'default' && sound != 'silent')
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill),
                      color:
                          accentFor(Theme.of(context).brightness, settings),
                      onPressed: () => AlertScheduler.previewSound(sound),
                    ),
                  if (settings.alertSound == sound)
                    Icon(Icons.check_circle,
                        color: accentFor(
                            Theme.of(context).brightness, settings)),
                ],
              ),
              onTap: () => Navigator.pop(context, sound),
            ),
        ],
      ),
    );
    if (picked == null) return;
    settings.update(() => settings.alertSound = picked);
    AlertScheduler.refresh(settings);
  }

  /// Per-prayer sound picker (v1.8.0): "App default" clears the
  /// override; any sound sets one. The dialog returns '' for the
  /// "App default" row so a barrier dismiss (null) changes nothing.
  Future<void> _pickPrayerSound(BuildContext context, Prayer prayer) async {
    final current = settings.prayerSoundOverrides[prayer];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(prayer == Prayer.dhuhr
            ? S.t('dhuhrFriday')
            : prayer.displayName),
        children: [
          ListTile(
            title: Text(S.t('useAppSound')),
            trailing: current == null
                ? Icon(Icons.check_circle,
                    color: accentFor(Theme.of(context).brightness, settings))
                : null,
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final sound in alertSoundNames)
            ListTile(
              title: Text(S.t('sound.$sound')),
              trailing: current == sound
                  ? Icon(Icons.check_circle,
                      color:
                          accentFor(Theme.of(context).brightness, settings))
                  : null,
              onTap: () => Navigator.pop(context, sound),
            ),
        ],
      ),
    );
    if (picked == null) return; // Dismissed — no change.
    settings.update(() {
      if (picked.isEmpty) {
        settings.prayerSoundOverrides.remove(prayer);
      } else {
        settings.prayerSoundOverrides[prayer] = picked;
      }
    });
    AlertScheduler.refresh(settings);
  }

  /// The strings.dart suffix for an icon name ('midnight' -> the
  /// 'iconMidnight' key).
  static String _iconLabelKey(String name) =>
      name[0].toUpperCase() + name.substring(1);

  /// Launcher icon picker (v3.0.0): the same colorways as the iOS
  /// alternate icons, switched natively through activity-aliases.
  Future<void> _pickAppIcon(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(S.t('appIcon')),
        children: [
          for (final name in kAppIconNames)
            ListTile(
              title: Text(S.t('icon.${_iconLabelKey(name)}')),
              trailing: settings.appIcon == name
                  ? Icon(Icons.check_circle,
                      color:
                          accentFor(Theme.of(context).brightness, settings))
                  : null,
              onTap: () => Navigator.pop(context, name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    settings.update(() => settings.appIcon = picked);
    AppIconChanger.setIcon(picked);
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

/// Silence-next (v2.0.0): names the next upcoming Adhan in the
/// one-shot flag the alert plan honors, then rebuilds the plan.
Future<void> _silenceNext(BuildContext context, AppSettings settings) async {
    final now = tz.TZDateTime.now(edmontonLocation());
    final snapshot = PrayerProvider.snapshot(now);
    settings.update(() => settings.silenceNextEpochSeconds =
        snapshot.next.adhan.millisecondsSinceEpoch ~/ 1000);
    await AlertScheduler.refresh(settings);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.f('silenceNextDone', {
        'name': snapshot.next.name,
        'time': PrayerFormat.time(snapshot.next.adhan),
      })),
    ));
}

/// Settings Backup section (v2.0.0, workstream 9): Google Drive
/// (appDataFolder) back up / restore with the last-backup date,
/// plus the export / import file rows — the same JSON as iOS.
class _BackupSection extends StatefulWidget {
  final AppSettings settings;
  const _BackupSection({required this.settings});

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  int? _lastBackupMillis;
  String? _message;

  @override
  void initState() {
    super.initState();
    SettingsBackup.driveLastBackupMillis()
        .then((v) => mounted ? setState(() => _lastBackupMillis = v) : null);
  }

  Future<void> _run(Future<bool> Function() action,
      {String okKey = 'backupDone'}) async {
    final ok = await action();
    if (!mounted) return;
    setState(() => _message = ok ? S.t(okKey) : S.t('actionFailed'));
    if (ok) {
      final v = await SettingsBackup.driveLastBackupMillis();
      if (mounted) setState(() => _lastBackupMillis = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(S.t('backup'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700)),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(S.t('backupToDrive')),
          subtitle: Text(_lastBackupMillis == null
              ? S.t('noBackupYet')
              : S.f('lastBackup', {
                  'when': DateFormat.yMMMd()
                      .add_jm()
                      .format(DateTime.fromMillisecondsSinceEpoch(
                          _lastBackupMillis!)),
                })),
          onTap: () => _run(SettingsBackup.driveBackup),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text(S.t('restoreFromDrive')),
          onTap: () => _run(() async {
            final ok = await SettingsBackup.driveRestore(settings);
            if (ok) await AlertScheduler.refresh(settings);
            return ok;
          }, okKey: 'restoreDone'),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: Text(S.t('exportSettings')),
          onTap: () async {
            final json = await SettingsBackup.exportJson();
            await const MethodChannel('alrashid/share')
                .invokeMethod('share', {'text': json});
          },
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: Text(S.t('importSettings')),
          onTap: () => _run(() async {
            final ok = await SettingsBackup.pickAndImport(settings);
            if (ok) await AlertScheduler.refresh(settings);
            return ok;
          }, okKey: 'restoreDone'),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_message!,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(S.t('backupFooter'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
