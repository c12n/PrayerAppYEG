// Quran downloads (v3.0.0) — the Android counterpart of the iOS
// QuranDownloads: offline downloads of whole surahs. Files live at
// <app support>/QuranAudio/{reciterId}/{n}.mp3; the player prefers
// a downloaded file over the stream.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'quran_models.dart';

class _CancelToken {
  bool cancelled = false;
}

class QuranDownloads extends ChangeNotifier {
  /// In-flight progress (0..1) per key, only while downloading.
  final Map<String, double> progressByKey = {};

  /// Keys whose file is fully on disk. Refreshed from the folder.
  Set<String> downloadedKeys = {};

  final Map<String, _CancelToken> _tokens = {};
  static Directory? _root;

  static String key(String reciterId, int surahNumber) =>
      '$reciterId/$surahNumber';

  /// Resolves the download root once (called from main()).
  static Future<void> ensureInit() async {
    if (_root != null) return;
    final base = await getApplicationSupportDirectory();
    _root = Directory('${base.path}/QuranAudio');
  }

  static File fileFor(String reciterId, int surahNumber) =>
      File('${_root!.path}/$reciterId/$surahNumber.mp3');

  /// The on-disk file for a (reciter, surah), when fully downloaded.
  static File? localFile(String reciterId, int surahNumber) {
    if (_root == null) return null;
    final file = fileFor(reciterId, surahNumber);
    return file.existsSync() ? file : null;
  }

  QuranDownloads() {
    refreshDownloaded();
  }

  // MARK: State

  bool isDownloaded(String reciterId, int surahNumber) =>
      downloadedKeys.contains(key(reciterId, surahNumber));

  bool isDownloading(String reciterId, int surahNumber) =>
      progressByKey.containsKey(key(reciterId, surahNumber));

  double? progress(String reciterId, int surahNumber) =>
      progressByKey[key(reciterId, surahNumber)];

  int get downloadedCount => downloadedKeys.length;

  int downloadedCountFor(String reciterId) =>
      downloadedKeys.where((k) => k.startsWith('$reciterId/')).length;

  int activeDownloadCount(String reciterId) =>
      progressByKey.keys.where((k) => k.startsWith('$reciterId/')).length;

  int _bytesOf(Iterable<String> keys) {
    var total = 0;
    for (final k in keys) {
      final parts = k.split('/');
      if (parts.length != 2) continue;
      final number = int.tryParse(parts[1]);
      if (number == null || _root == null) continue;
      try {
        total += fileFor(parts[0], number).lengthSync();
      } catch (_) {}
    }
    return total;
  }

  /// Total bytes of downloaded audio on disk.
  int get totalBytes => _bytesOf(downloadedKeys);

  int bytesFor(String reciterId) =>
      _bytesOf(downloadedKeys.where((k) => k.startsWith('$reciterId/')));

  void refreshDownloaded() {
    final found = <String>{};
    final root = _root;
    if (root != null && root.existsSync()) {
      for (final reciterDir in root.listSync().whereType<Directory>()) {
        final reciterId = reciterDir.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last;
        for (final file in reciterDir.listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last;
          if (name.endsWith('.mp3')) {
            final number = int.tryParse(name.substring(0, name.length - 4));
            if (number != null) found.add(key(reciterId, number));
          }
        }
      }
    }
    downloadedKeys = found;
  }

  // MARK: Download / cancel / delete

  Future<void> download(int surahNumber, String reciterId) async {
    final k = key(reciterId, surahNumber);
    if (downloadedKeys.contains(k) || progressByKey.containsKey(k)) return;
    await ensureInit();
    final token = _CancelToken();
    _tokens[k] = token;
    progressByKey[k] = 0;
    notifyListeners();
    final tmp = File('${fileFor(reciterId, surahNumber).path}.part');
    try {
      final url = Uri.parse(QuranLibrary.audioUrl(surahNumber, reciterId));
      final client = HttpClient();
      try {
        final request = await client.getUrl(url);
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const HttpException('download failed');
        }
        final total = response.contentLength;
        await tmp.parent.create(recursive: true);
        final sink = tmp.openWrite();
        var received = 0;
        await for (final chunk in response) {
          if (token.cancelled) break;
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final value = received / total;
            final old = progressByKey[k] ?? 0;
            if (value - old >= 0.01 || value >= 1) {
              progressByKey[k] = value;
              notifyListeners();
            }
          }
        }
        await sink.close();
      } finally {
        client.close();
      }
      if (token.cancelled) {
        if (tmp.existsSync()) await tmp.delete();
        return;
      }
      final destination = fileFor(reciterId, surahNumber);
      if (destination.existsSync()) await destination.delete();
      await tmp.rename(destination.path);
      downloadedKeys.add(k);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
    } finally {
      _tokens.remove(k);
      progressByKey.remove(k);
      notifyListeners();
    }
  }

  void cancel(int surahNumber, String reciterId) {
    _tokens[key(reciterId, surahNumber)]?.cancelled = true;
  }

  void delete(int surahNumber, String reciterId) {
    cancel(surahNumber, reciterId);
    try {
      fileFor(reciterId, surahNumber).deleteSync();
    } catch (_) {}
    downloadedKeys.remove(key(reciterId, surahNumber));
    notifyListeners();
  }

  // MARK: Bulk operations

  /// Downloads every surah not already on disk for this voice,
  /// all at once — the same fire-everything behavior as the iOS
  /// downloads manager (1:1 parity; there is no worker cap).
  Future<void> downloadAll(String reciterId) async {
    final pending = [
      for (var n = 1; n <= 114; n++)
        if (!isDownloaded(reciterId, n) && !isDownloading(reciterId, n)) n,
    ];
    await Future.wait([for (final n in pending) download(n, reciterId)]);
  }

  void cancelAll(String reciterId) {
    for (final token in _tokens.entries
        .where((e) => e.key.startsWith('$reciterId/'))
        .map((e) => e.value)) {
      token.cancelled = true;
    }
  }

  void deleteAll(String reciterId) {
    cancelAll(reciterId);
    final root = _root;
    if (root != null) {
      try {
        Directory('${root.path}/$reciterId').deleteSync(recursive: true);
      } catch (_) {}
    }
    downloadedKeys.removeWhere((k) => k.startsWith('$reciterId/'));
    notifyListeners();
  }
}
