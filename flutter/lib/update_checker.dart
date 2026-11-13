// In-app update notification (v3.0.3) — the Android counterpart of
// the iOS 3.0.3 update checker. On app start (throttled to at most
// once every 6 hours) it fetches the small version manifest the
// project publishes on GitHub and compares its Android version with
// the running app's. When the manifest is strictly newer, a
// dismissible banner appears at the top of the Prayer tab and a row
// appears in Settings; dismissing is remembered per version. Every
// failure is silent: no network, a bad response, or an unparsable
// manifest simply leaves the app as it was.
//
// State lives in shared_preferences under 'update.*' keys (the
// WhatsNew pattern). Opening the update link goes through the
// 'alrashid/updater' MethodChannel, the codebase's established way
// of reaching the platform (there is no url_launcher dependency).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// Result of a manual check, so Settings can report back.
enum UpdateCheckOutcome { updateAvailable, upToDate, failed }

class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  static const manifestUrl =
      'https://raw.githubusercontent.com/c12n/PrayerAppYEG/main/version.json';
  static const _lastCheckKey = 'update.lastCheckMillis';
  static const _dismissedKey = 'update.dismissedVersion';
  static const _throttle = Duration(hours: 6);
  static const _channel = MethodChannel('alrashid/updater');

  String? _availableVersion;
  String? _updateUrl;
  String? _dismissedVersion;
  bool _loaded = false;
  bool _checking = false;

  /// The newer version the manifest advertises, if any.
  String? get availableVersion => _availableVersion;
  bool get updateAvailable => _availableVersion != null;

  /// The Prayer-tab banner shows only for a version the user has
  /// not already dismissed; a still newer version re-shows it.
  bool get bannerVisible =>
      _availableVersion != null && _dismissedVersion != _availableVersion;

  /// Numeric component-wise comparison ("3.0.10" > "3.0.9"):
  /// true only when [remote] is strictly newer than [current].
  static bool isNewer(String remote, String current) {
    List<int> parts(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final r = parts(remote);
    final c = parts(current);
    final n = r.length > c.length ? r.length : c.length;
    for (var i = 0; i < n; i++) {
      final rv = i < r.length ? r[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (rv != cv) return rv > cv;
    }
    return false;
  }

  Future<void> _load(SharedPreferences prefs) async {
    if (_loaded) return;
    _loaded = true;
    _dismissedVersion = prefs.getString(_dismissedKey);
  }

  /// App-start check: at most one fetch per [_throttle], and any
  /// failure is swallowed silently.
  Future<void> checkOnStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _load(prefs);
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _throttle.inMilliseconds) return;
      await _fetch(prefs);
    } catch (_) {
      // Silent by design: an update check must never disturb launch.
    }
  }

  /// Manual check from Settings: ignores the throttle and reports
  /// the outcome so the page can tell the user what happened.
  Future<UpdateCheckOutcome> checkNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _load(prefs);
      final ok = await _fetch(prefs);
      if (!ok) return UpdateCheckOutcome.failed;
      return updateAvailable
          ? UpdateCheckOutcome.updateAvailable
          : UpdateCheckOutcome.upToDate;
    } catch (_) {
      return UpdateCheckOutcome.failed;
    }
  }

  /// One fetch + compare. Stamps the throttle on every attempt.
  /// Returns false on any failure (state left untouched).
  Future<bool> _fetch(SharedPreferences prefs) async {
    if (_checking) return _availableVersion != null;
    _checking = true;
    try {
      await prefs.setInt(
          _lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client
            .getUrl(Uri.parse(manifestUrl))
            .timeout(const Duration(seconds: 8));
        final response = await request.close().timeout(
            const Duration(seconds: 8));
        if (response.statusCode != 200) return false;
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 8));
        final decoded = jsonDecode(body);
        if (decoded is! Map) return false;
        final android = decoded['android'];
        if (android is! Map) return false;
        final version = android['version'];
        final url = android['url'];
        if (version is! String || url is! String) return false;
        final newer = isNewer(version, kAppVersion);
        _availableVersion = newer ? version : null;
        _updateUrl = newer ? url : null;
        notifyListeners();
        return true;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    } finally {
      _checking = false;
    }
  }

  /// Remember that the user dismissed the banner for the version
  /// currently on offer; a newer version will show it again.
  Future<void> dismiss() async {
    final version = _availableVersion;
    if (version == null) return;
    _dismissedVersion = version;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissedKey, version);
    } catch (_) {
      // The in-memory dismissal still holds for this session.
    }
  }

  /// Open the manifest's update URL in the browser (Kotlin side).
  Future<void> openUpdate() async {
    final url = _updateUrl;
    if (url == null) return;
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (_) {
      // No browser / platform error: nothing useful to show.
    }
  }
}
