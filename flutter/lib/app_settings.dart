// App settings (v1.0.5) — the Android counterpart of the iOS Settings
// page: appearance mode, theme colors (main / accent / text), designed
// themes, save-your-own themes, per-prayer countdown choices, and reset.
//
// Stored with shared_preferences, which on Android writes into
// FlutterSharedPreferences.xml (keys get a "flutter." prefix there) —
// the Kotlin home-screen widgets read the same values from that file,
// so the widgets follow the accent color and the prayer choices.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hijri_calendar.dart';
import 'prayer_models.dart';

/// App version identity (v2.0.0) — keep in step with pubspec.yaml's
/// version (2.0.0+16). Shown in the Settings footer and used by the
/// What's New sheet to decide whether to appear.
const kAppVersion = '2.0.1';
const kAppBuildNumber = '16';

/// The Adhan alert sounds (v1.8.0), mirroring iOS: the raw values are
/// what travel over the alerts MethodChannel and name the Android
/// notification channels.
const alertSoundNames = ['default', 'silent', 'chime', 'bell'];

class SavedTheme {
  final String id;
  final String name;
  final int primaryHex;
  final int accentHex;
  final int textHex;
  final ThemeMode mode;

  const SavedTheme({
    required this.id,
    required this.name,
    required this.primaryHex,
    required this.accentHex,
    required this.textHex,
    required this.mode,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'primaryHex': primaryHex,
        'accentHex': accentHex,
        'textHex': textHex,
        'mode': mode.name,
      };

  static SavedTheme fromJson(Map<String, dynamic> json) => SavedTheme(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Theme',
        primaryHex: (json['primaryHex'] as num?)?.toInt() ?? AppSettings.defaultPrimary,
        accentHex: (json['accentHex'] as num?)?.toInt() ?? AppSettings.defaultAccent,
        textHex: (json['textHex'] as num?)?.toInt() ?? AppSettings.defaultText,
        mode: ThemeMode.values.asNameMap()[json['mode'] as String?] ?? ThemeMode.system,
      );
}

class AppSettings extends ChangeNotifier {
  static const modeKey = 'appearance.mode';
  static const primaryKey = 'appearance.primaryHex';
  static const accentKey = 'appearance.accentHex';
  static const textKey = 'appearance.textHex';
  static const savedThemesKey = 'appearance.savedThemes';
  static const languageKey = 'language.code';
  static const textSizeKey = 'appearance.textSize';
  static String alertKey(Prayer p) => 'alerts.${p.name}';
  // Notification engine settings (v1.5, same keys/defaults as iOS).
  static const notificationsEnabledKey = 'alerts.notificationsEnabled';
  static const reminderEnabledKey = 'alerts.reminderEnabled';
  static const reminderLeadKey = 'alerts.reminderLeadMinutes';
  static const jumuahReminderEnabledKey = 'alerts.jumuahReminderEnabled';
  // Alert sounds (v1.8.0, same keys as iOS): one app-wide sound plus
  // optional per-prayer overrides (absent = follow the app sound).
  static const alertSoundKey = 'alerts.sound';
  static String prayerSoundKey(Prayer p) => 'alerts.sound.prayer.${p.name}';
  // Iqamah-first countdown (v2.0.0, same keys as iOS).
  static const iqamahFirstKey = 'countdown.iqamahFirst';
  static const leaveLeadKey = 'countdown.leaveLeadMinutes';
  // Minimal Mode, Sunnah fasting, one-shot silence (v2.0.0, same keys as iOS).
  static const minimalModeKey = 'appearance.minimalMode';
  static const fastingMonThuKey = 'fasting.mondayThursday';
  static const fastingWhiteDaysKey = 'fasting.whiteDays';
  static const silenceNextEpochKey = 'alerts.silenceNextEpoch';
  static const taraweehOffsetKey = 'ramadan.taraweehAfterIshaMinutes';
  // Widget colors (v2.0.0, same keys as iOS): 'match' (widgets follow
  // the app theme) or 'separate' (home widgets get their own theme).
  // Android has no Lock Screen widgets or Live Activities, so Home is
  // the only part stored here. The flat hex keys mirror the chosen
  // widget theme for the Kotlin widgets, which read raw prefs values.
  static const widgetColorModeKey = 'appearance.widgetColorMode';
  static const homeWidgetThemeKey = 'appearance.partTheme.home';
  static const widgetHomePrimaryKey = 'appearance.widgetTheme.home.primaryHex';
  static const widgetHomeAccentKey = 'appearance.widgetTheme.home.accentHex';
  static const widgetHomeTextKey = 'appearance.widgetTheme.home.textHex';
  static const hijriOffsetKey = 'hijri.offsetDays';
  static const hapticsEnabledKey = 'compass.hapticsEnabled';
  static const reminderLeadOptions = [5, 10, 15, 20, 30];

  static const defaultPrimary = 0x0B3D2E;
  static const defaultAccent = 0xD4AF37;
  static const defaultText = 0xFFFFFF;

  ThemeMode mode = ThemeMode.system;
  int primaryHex = defaultPrimary;
  int accentHex = defaultAccent;
  int textHex = defaultText;

  /// Widget colors (v2.0.0): 'match' or 'separate' (see keys above).
  String widgetColorMode = 'match';

  /// The home widgets' own theme in Separate mode; null = app theme.
  SavedTheme? homeWidgetTheme;

  /// The colors the home widgets should actually wear.
  int get effectiveWidgetPrimary =>
      (widgetColorMode == 'separate' ? homeWidgetTheme?.primaryHex : null) ?? primaryHex;
  int get effectiveWidgetAccent =>
      (widgetColorMode == 'separate' ? homeWidgetTheme?.accentHex : null) ?? accentHex;
  int get effectiveWidgetText =>
      (widgetColorMode == 'separate' ? homeWidgetTheme?.textHex : null) ?? textHex;

  /// False until the user actually picks a text color; while false the
  /// text color follows the defaults (white on colored surfaces, the
  /// deepened main color on white), exactly like the iOS app.
  bool textIsCustom = false;

  AppLanguage language = AppLanguage.en;
  AppTextSize textSize = AppTextSize.standard;

  List<SavedTheme> savedThemes = [];
  final Map<Prayer, bool> alerts = {
    for (final p in Prayer.values) p: p != Prayer.sunrise,
  };

  /// Notification engine (v1.5): master switch, pre-prayer reminder
  /// and Friday Jumu'ah reminder — all default ON, like iOS.
  bool notificationsEnabled = true;
  bool reminderEnabled = true;
  int reminderLeadMinutes = 10;
  bool jumuahReminderEnabled = true;

  /// Alert sounds (v1.8.0): the app-wide Adhan sound plus optional
  /// per-prayer overrides. See [effectiveSound].
  String alertSound = 'default';
  final Map<Prayer, String> prayerSoundOverrides = {};

  /// The sound an Adhan alert for [prayer] actually uses.
  String effectiveSound(Prayer prayer) =>
      prayerSoundOverrides[prayer] ?? alertSound;

  /// Hijri date adjustment (v1.5): −1..+1 days on the displayed date.
  int hijriOffsetDays = 0;

  /// Iqamah-first countdown (v2.0.0): hero counts down to the
  /// Iqamah after the Adhan; time-to-leave lead (0 = off).
  bool iqamahFirst = true;
  int leaveLeadMinutes = 0;

  /// Ramadan Taraweeh estimate offset (v2.0.0): minutes after the
  /// Isha Iqamah.
  int taraweehOffsetMinutes = 15;

  /// Minimal Mode (v2.0.0): essentials-only view layer; never
  /// changes any other setting.
  bool minimalMode = false;

  /// Sunnah fasting reminders (v2.0.0): Mondays & Thursdays, and
  /// the white days (13/14/15 Hijri). Both off by default.
  bool fastingMonThu = false;
  bool fastingWhiteDays = false;

  /// Epoch seconds of the one Adhan alert to skip (0 = none).
  int silenceNextEpochSeconds = 0;

  /// Facing-Qibla vibration in the full-screen compass only (v1.5).
  /// The home-screen Qibla card never buzzes.
  bool hapticsEnabled = true;

  SharedPreferences? _prefs;

  static Future<AppSettings> load() async {
    final s = AppSettings();
    final prefs = await SharedPreferences.getInstance();
    s._prefs = prefs;
    s.mode = switch (prefs.getString(modeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    s.primaryHex = prefs.getInt(primaryKey) ?? defaultPrimary;
    s.accentHex = prefs.getInt(accentKey) ?? defaultAccent;
    final storedText = prefs.getInt(textKey);
    if (storedText != null) {
      s.textHex = storedText;
      s.textIsCustom = true;
    }
    for (final p in Prayer.values) {
      final v = prefs.getBool(alertKey(p));
      if (v != null) s.alerts[p] = v;
    }
    s.notificationsEnabled =
        prefs.getBool(notificationsEnabledKey) ?? true;
    s.reminderEnabled = prefs.getBool(reminderEnabledKey) ?? true;
    final lead = prefs.getInt(reminderLeadKey) ?? 10;
    s.reminderLeadMinutes =
        reminderLeadOptions.contains(lead) ? lead : 10;
    s.jumuahReminderEnabled =
        prefs.getBool(jumuahReminderEnabledKey) ?? true;
    final storedSound = prefs.getString(alertSoundKey);
    if (storedSound != null && alertSoundNames.contains(storedSound)) {
      s.alertSound = storedSound;
    }
    for (final p in Prayer.values) {
      final override = prefs.getString(prayerSoundKey(p));
      if (override != null && alertSoundNames.contains(override)) {
        s.prayerSoundOverrides[p] = override;
      }
    }
    s.hijriOffsetDays =
        (prefs.getInt(hijriOffsetKey) ?? 0).clamp(-1, 1);
    s.iqamahFirst = prefs.getBool(iqamahFirstKey) ?? true;
    final leaveLead = prefs.getInt(leaveLeadKey) ?? 0;
    s.leaveLeadMinutes =
        [0, 5, 10, 15, 20].contains(leaveLead) ? leaveLead : 0;
    final taraweeh = prefs.getInt(taraweehOffsetKey);
    s.taraweehOffsetMinutes =
        [0, 15, 30, 45, 60].contains(taraweeh) ? taraweeh! : 15;
    HijriState.offsetDays = s.hijriOffsetDays;
    s.hapticsEnabled = prefs.getBool(hapticsEnabledKey) ?? true;
    s.minimalMode = prefs.getBool(minimalModeKey) ?? false;
    s.fastingMonThu = prefs.getBool(fastingMonThuKey) ?? false;
    s.fastingWhiteDays = prefs.getBool(fastingWhiteDaysKey) ?? false;
    s.silenceNextEpochSeconds = prefs.getInt(silenceNextEpochKey) ?? 0;
    s.language = AppLanguage.values.asNameMap()[prefs.getString(languageKey)] ??
        AppLanguage.en;
    LanguageState.current = s.language;
    s.textSize = AppTextSize.values.asNameMap()[prefs.getString(textSizeKey)] ??
        AppTextSize.standard;
    final raw = prefs.getString(savedThemesKey);
    if (raw != null) {
      try {
        s.savedThemes = (jsonDecode(raw) as List)
            .map((e) => SavedTheme.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        s.savedThemes = [];
      }
    }
    s.widgetColorMode =
        prefs.getString(widgetColorModeKey) == 'separate' ? 'separate' : 'match';
    final rawWidgetTheme = prefs.getString(homeWidgetThemeKey);
    if (rawWidgetTheme != null) {
      try {
        s.homeWidgetTheme =
            SavedTheme.fromJson(jsonDecode(rawWidgetTheme) as Map<String, dynamic>);
      } catch (_) {
        s.homeWidgetTheme = null;
      }
    }
    return s;
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(modeKey, mode.name);
    await prefs.setInt(primaryKey, primaryHex);
    await prefs.setInt(accentKey, accentHex);
    if (textIsCustom) {
      await prefs.setInt(textKey, textHex);
    } else {
      await prefs.remove(textKey);
    }
    for (final p in Prayer.values) {
      await prefs.setBool(alertKey(p), alerts[p] ?? false);
    }
    await prefs.setBool(notificationsEnabledKey, notificationsEnabled);
    await prefs.setBool(reminderEnabledKey, reminderEnabled);
    await prefs.setInt(reminderLeadKey, reminderLeadMinutes);
    await prefs.setBool(jumuahReminderEnabledKey, jumuahReminderEnabled);
    await prefs.setString(alertSoundKey, alertSound);
    for (final p in Prayer.values) {
      final override = prayerSoundOverrides[p];
      if (override != null) {
        await prefs.setString(prayerSoundKey(p), override);
      } else {
        await prefs.remove(prayerSoundKey(p));
      }
    }
    await prefs.setInt(hijriOffsetKey, hijriOffsetDays);
    await prefs.setBool(iqamahFirstKey, iqamahFirst);
    await prefs.setInt(leaveLeadKey, leaveLeadMinutes);
    await prefs.setInt(taraweehOffsetKey, taraweehOffsetMinutes);
    HijriState.offsetDays = hijriOffsetDays;
    await prefs.setBool(hapticsEnabledKey, hapticsEnabled);
    await prefs.setBool(minimalModeKey, minimalMode);
    await prefs.setBool(fastingMonThuKey, fastingMonThu);
    await prefs.setBool(fastingWhiteDaysKey, fastingWhiteDays);
    await prefs.setInt(silenceNextEpochKey, silenceNextEpochSeconds);
    await prefs.setString(
        savedThemesKey, jsonEncode(savedThemes.map((t) => t.toJson()).toList()));
    await prefs.setString(languageKey, language.name);
    await prefs.setString(textSizeKey, textSize.name);
    LanguageState.current = language;
    // Widget colors (v2.0.0): the JSON theme drives the Settings UI;
    // the flat hex keys are what the Kotlin widgets read.
    await prefs.setString(widgetColorModeKey, widgetColorMode);
    final widgetTheme = homeWidgetTheme;
    if (widgetTheme != null) {
      await prefs.setString(homeWidgetThemeKey, jsonEncode(widgetTheme.toJson()));
    } else {
      await prefs.remove(homeWidgetThemeKey);
    }
    await prefs.setInt(widgetHomePrimaryKey, effectiveWidgetPrimary);
    await prefs.setInt(widgetHomeAccentKey, effectiveWidgetAccent);
    await prefs.setInt(widgetHomeTextKey, effectiveWidgetText);
  }


  /// Re-reads every field from preferences (v2.0.0): used after a
  /// settings-backup import so the whole app picks the restored
  /// values up without a restart.
  Future<void> reload() async {
    final fresh = await AppSettings.load();
    mode = fresh.mode;
    primaryHex = fresh.primaryHex;
    accentHex = fresh.accentHex;
    textHex = fresh.textHex;
    textIsCustom = fresh.textIsCustom;
    widgetColorMode = fresh.widgetColorMode;
    homeWidgetTheme = fresh.homeWidgetTheme;
    language = fresh.language;
    textSize = fresh.textSize;
    savedThemes = fresh.savedThemes;
    alerts
      ..clear()
      ..addAll(fresh.alerts);
    notificationsEnabled = fresh.notificationsEnabled;
    reminderEnabled = fresh.reminderEnabled;
    reminderLeadMinutes = fresh.reminderLeadMinutes;
    jumuahReminderEnabled = fresh.jumuahReminderEnabled;
    alertSound = fresh.alertSound;
    prayerSoundOverrides
      ..clear()
      ..addAll(fresh.prayerSoundOverrides);
    hijriOffsetDays = fresh.hijriOffsetDays;
    iqamahFirst = fresh.iqamahFirst;
    leaveLeadMinutes = fresh.leaveLeadMinutes;
    taraweehOffsetMinutes = fresh.taraweehOffsetMinutes;
    hapticsEnabled = fresh.hapticsEnabled;
    minimalMode = fresh.minimalMode;
    fastingMonThu = fresh.fastingMonThu;
    fastingWhiteDays = fresh.fastingWhiteDays;
    silenceNextEpochSeconds = fresh.silenceNextEpochSeconds;
    notifyListeners();
  }

  /// Applies a change, notifies the UI and persists everything.
  void update(void Function() change) {
    change();
    notifyListeners();
    _save();
  }

  Set<Prayer> get enabledPrayers => {
        for (final p in Prayer.values)
          if (alerts[p] ?? false) p,
      };

  /// True when the current mode + colors exactly match a theme — its
  /// settings row then shows a checkmark instead of the chevron.
  bool isActiveTheme(SavedTheme theme) =>
      mode == theme.mode &&
      primaryHex == theme.primaryHex &&
      accentHex == theme.accentHex &&
      textHex == theme.textHex;

  void applyTheme(SavedTheme theme) => update(() {
        primaryHex = theme.primaryHex;
        accentHex = theme.accentHex;
        textHex = theme.textHex;
        textIsCustom = true;
        mode = theme.mode;
      });

  void resetToDefaults() => update(() {
        mode = ThemeMode.system;
        primaryHex = defaultPrimary;
        accentHex = defaultAccent;
        textHex = defaultText;
        textIsCustom = false;
        for (final p in Prayer.values) {
          alerts[p] = p != Prayer.sunrise;
        }
        notificationsEnabled = true;
        reminderEnabled = true;
        reminderLeadMinutes = 10;
        jumuahReminderEnabled = true;
        alertSound = 'default';
        prayerSoundOverrides.clear();
        hijriOffsetDays = 0;
        hapticsEnabled = true;
        widgetColorMode = 'match';
        homeWidgetTheme = null;
        iqamahFirst = true;
        leaveLeadMinutes = 0;
        taraweehOffsetMinutes = 15;
        minimalMode = false;
        fastingMonThu = false;
        fastingWhiteDays = false;
        silenceNextEpochSeconds = 0;
      });
}

/// Gives the widget tree access to the current [AppSettings].
class SettingsScope extends InheritedWidget {
  final AppSettings settings;
  const SettingsScope({super.key, required this.settings, required super.child});

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.settings;

  @override
  bool updateShouldNotify(SettingsScope oldWidget) =>
      settings != oldWidget.settings;
}

// MARK: - Color helpers (ports of the iOS contrast guards)

Color colorFromHex(int hex) => Color(0xFF000000 | (hex & 0xFFFFFF));

int hexFromColor(Color c) =>
    ((c.r * 255).round() << 16) | ((c.g * 255).round() << 8) | (c.b * 255).round();

Color lightenColor(Color c, double fraction) {
  final hsv = HSVColor.fromColor(c);
  return hsv
      .withValue(hsv.value + (1 - hsv.value) * fraction)
      .withSaturation(hsv.saturation * (1 - fraction * 0.35))
      .toColor();
}

Color darkenColor(Color c, double fraction) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withValue(hsv.value * (1 - fraction)).toColor();
}

/// Brighten for dark surfaces (brightness at least 0.82), like iOS.
Color adjustAccentForDark(Color c) {
  final hsv = HSVColor.fromColor(c);
  return hsv
      .withValue(math.max(hsv.value, 0.82))
      .withSaturation(math.min(hsv.saturation, 0.9))
      .toColor();
}

/// Deepen for light surfaces (brightness at most 0.42), like iOS.
Color adjustAccentForLight(Color c) {
  final hsv = HSVColor.fromColor(c);
  return hsv
      .withValue(math.min(hsv.value, 0.42))
      .withSaturation(hsv.saturation.clamp(0.55, 1.0))
      .toColor();
}

Color accentFor(Brightness brightness, AppSettings s) {
  final base = colorFromHex(s.accentHex);
  return brightness == Brightness.dark
      ? adjustAccentForDark(base)
      : adjustAccentForLight(base);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Color _ensureContrast(Color fg, Color bg, Color toward, double minimum) {
  if (_contrast(fg, bg) >= minimum) return fg;
  for (var step = 1; step <= 10; step++) {
    final blended = Color.lerp(fg, toward, step / 10)!;
    if (_contrast(blended, bg) >= minimum) return blended;
  }
  return toward;
}

/// The text color for adaptive surfaces, with the same rules as iOS:
/// defaults are white on the (dark) main color and the deepened main
/// color on white; a picked color is contrast-guarded to ~4.5:1.
Color resolvedTextColor({required bool darkSurface, required AppSettings s}) {
  final primary = colorFromHex(s.primaryHex);
  if (darkSurface) {
    if (!s.textIsCustom) return Colors.white;
    return _ensureContrast(colorFromHex(s.textHex), primary, Colors.white, 4.5);
  }
  if (!s.textIsCustom) return darkenColor(primary, 0.15);
  final picked = colorFromHex(s.textHex);
  if (picked.computeLuminance() > 0.75) return darkenColor(primary, 0.15);
  return _ensureContrast(picked, Colors.white, Colors.black, 4.5);
}

// MARK: - Presets (same values as iOS)

const accentPresets = <(String, int)>[
  ('Gold', 0xD4AF37),
  ('Emerald', 0x10B981),
  ('Teal', 0x14B8A6),
  ('Sky', 0x38BDF8),
  ('Blue', 0x3B82F6),
  ('Violet', 0x8B5CF6),
  ('Rose', 0xF43F5E),
  ('Orange', 0xF97316),
];

const primaryPresets = <(String, int)>[
  ('Mosque Green', 0x0B3D2E),
  ('Midnight', 0x0F2440),
  ('Ocean', 0x083344),
  ('Royal', 0x2E1065),
  ('Rosewood', 0x571233),
  ('Bronze', 0x6B4420),
  ('Forest', 0x14532D),
  ('Charcoal', 0x171717),
];

const textPresets = <(String, int)>[
  ('White', 0xFFFFFF),
  ('Warm White', 0xFFF8E7),
  ('Soft Gold', 0xF2CD5C),
  ('Deep Green', 0x0B3D2E),
  ('Black', 0x111111),
];

const presetThemes = <SavedTheme>[
  SavedTheme(id: 'preset-mosque', name: 'Mosque Green & Gold', primaryHex: 0x0B3D2E, accentHex: 0xD4AF37, textHex: 0xFFFFFF, mode: ThemeMode.system),
  SavedTheme(id: 'preset-midnight', name: 'Midnight Oasis', primaryHex: 0x0F2440, accentHex: 0x7DD3FC, textHex: 0xF0F9FF, mode: ThemeMode.dark),
  SavedTheme(id: 'preset-ocean', name: 'Ocean Depths', primaryHex: 0x083344, accentHex: 0x67E8F9, textHex: 0xECFEFF, mode: ThemeMode.dark),
  SavedTheme(id: 'preset-royal', name: 'Royal Amethyst', primaryHex: 0x2E1065, accentHex: 0xC4B5FD, textHex: 0xF5F3FF, mode: ThemeMode.dark),
  SavedTheme(id: 'preset-rose', name: 'Rose Garden', primaryHex: 0x571233, accentHex: 0xFDA4AF, textHex: 0xFFF1F2, mode: ThemeMode.dark),
  SavedTheme(id: 'preset-desert', name: 'Desert Dunes', primaryHex: 0x6B4420, accentHex: 0xF2C14E, textHex: 0xFFF8E7, mode: ThemeMode.system),
  SavedTheme(id: 'preset-forest', name: 'Forest Canopy', primaryHex: 0x14532D, accentHex: 0xFDE68A, textHex: 0xF0FDF4, mode: ThemeMode.system),
  SavedTheme(id: 'preset-charcoal', name: 'Charcoal Mono', primaryHex: 0x171717, accentHex: 0xE7E5E4, textHex: 0xFAFAF9, mode: ThemeMode.dark),
];
