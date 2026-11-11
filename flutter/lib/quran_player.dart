// Quran player (v3.0.0) — the Android counterpart of the iOS
// QuranPlayer: a just_audio engine streaming one MP3 per surah
// from the catalogue CDN (or playing the downloaded file), with
// the same queue / shuffle / repeat / rate / sleep-timer / ayah
// loop behavior and the same quran.* persistence keys as iOS.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_downloads.dart';
import 'quran_models.dart';

enum QuranRepeatMode { off, all, one }

enum QuranAudioLanguage { arabic, english }

/// Sleep timer choices (iOS: SleepOption). [minutes] null with
/// [endOfSurah] false means off.
class QuranSleepOption {
  final int? minutes;
  final bool endOfSurah;
  const QuranSleepOption.off()
      : minutes = null,
        endOfSurah = false;
  const QuranSleepOption.minutes(this.minutes) : endOfSurah = false;
  const QuranSleepOption.end()
      : minutes = null,
        endOfSurah = true;

  bool get isOff => minutes == null && !endOfSurah;
}

/// Listening statistics (iOS: QuranPlayer.ListeningStats), persisted
/// as JSON under `quran.stats.v1` and shown in the prayer tracker.
class QuranListeningStats {
  int completedTotal = 0;

  /// Completion counts keyed by surah number (as a string).
  Map<String, int> perSurah = {};
  double secondsListened = 0;

  Map<String, dynamic> toJson() => {
        'completedTotal': completedTotal,
        'perSurah': perSurah,
        'secondsListened': secondsListened,
      };

  static QuranListeningStats fromJson(Map<String, dynamic> json) {
    final s = QuranListeningStats();
    s.completedTotal = (json['completedTotal'] as num?)?.toInt() ?? 0;
    final per = json['perSurah'] as Map<String, dynamic>? ?? {};
    s.perSurah = per.map((k, v) => MapEntry(k, (v as num).toInt()));
    s.secondsListened = (json['secondsListened'] as num?)?.toDouble() ?? 0;
    return s;
  }
}

class _AyahLoop {
  double start;
  double end;

  /// Plays left including the current pass; null loops forever.
  int? remainingPlays;
  String label;
  _AyahLoop({
    required this.start,
    required this.end,
    required this.remainingPlays,
    required this.label,
  });
}

class QuranPlayer extends ChangeNotifier {
  // MARK: Persistence keys (same as iOS)
  static const _kLastSurah = 'quran.lastSurah';
  static const _kLastPosition = 'quran.lastPosition';
  static const _kReciter = 'quran.reciterId';
  static const _kFavorites = 'quran.favorites';
  static const _kRepeatMode = 'quran.repeatMode';
  static const _kShuffle = 'quran.shuffle';
  static const _kRate = 'quran.rate';
  static const _kAudioLanguage = 'quran.audioLanguage';
  static const _kStats = 'quran.stats.v1';

  static const allowedRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const sleepMinutes = [5, 10, 15, 30, 45, 60];

  static const _widgetChannel = MethodChannel('alrashid/widgets');

  final AudioPlayer _player = AudioPlayer();
  SharedPreferences? _prefs;

  // MARK: State (iOS @Published equivalents)
  QuranSurah? currentSurah;
  bool isPlaying = false;
  double currentTime = 0;
  double? itemDuration;
  List<int> queue = [];
  String contextLabel = '';
  Set<int> favorites = {};
  String reciterId = '';
  QuranRepeatMode repeatMode = QuranRepeatMode.off;
  bool shuffle = false;
  double rate = 1.0;
  QuranSleepOption sleepOption = const QuranSleepOption.off();
  QuranAudioLanguage audioLanguage = QuranAudioLanguage.arabic;
  QuranListeningStats stats = QuranListeningStats();
  String? ayahLoopLabel;

  _AyahLoop? _ayahLoop;
  List<int> _traversal = [];
  int _traversalPos = 0;
  int _loadToken = 0;
  double? _pendingSeek;
  DateTime? _sleepDeadline;
  Timer? _ticker;
  int _lastSavedSecond = -1;
  double _lastObservedPlaybackTime = 0;
  double _unflushedListenSeconds = 0;
  DateTime _lastWidgetReload = DateTime.fromMillisecondsSinceEpoch(0);

  /// The best duration known for the current surah: the player
  /// item's own duration once loaded, else the bundled stream
  /// duration for the active language / reciter.
  double get duration {
    if (itemDuration != null && itemDuration! > 0) return itemDuration!;
    final surah = currentSurah;
    if (surah == null) return 0;
    return (QuranLibrary.durationSeconds(surah.number, activeReciterId) ?? 0)
        .toDouble();
  }

  /// The reciter whose audio is actually playing: the English
  /// translation voice while the language is English.
  QuranReciter? get currentReciter => audioLanguage == QuranAudioLanguage.english
      ? QuranLibrary.englishReciter
      : QuranLibrary.reciter(reciterId);

  /// The id downloads and file lookups key on for the active
  /// language ("english" in English mode).
  String get activeReciterId => audioLanguage == QuranAudioLanguage.english
      ? QuranLibrary.englishReciterId
      : reciterId;

  /// Duration to display for a surah in lists: follows the active
  /// language, like playback does.
  double? displayDuration(QuranSurah surah) =>
      QuranLibrary.durationSeconds(surah.number, activeReciterId)?.toDouble();

  /// The surah that plays after the current one, if any.
  QuranSurah? get upNextSurah {
    if (_traversalPos + 1 >= _traversal.length) return null;
    return QuranLibrary.surah(queue[_traversal[_traversalPos + 1]]);
  }

  bool get hasQueue => queue.isNotEmpty;

  // MARK: Init & restore

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final storedReciter = prefs.getString(_kReciter) ?? '';
    reciterId = QuranLibrary.reciter(storedReciter) != null
        ? storedReciter
        : (QuranLibrary.defaultReciter?.id ?? '');
    favorites = (prefs.getStringList(_kFavorites) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final storedRepeat = prefs.getInt(_kRepeatMode) ?? 0;
    repeatMode = QuranRepeatMode
        .values[storedRepeat.clamp(0, QuranRepeatMode.values.length - 1)];
    shuffle = prefs.getBool(_kShuffle) ?? false;
    final storedRate = prefs.getDouble(_kRate) ?? 1.0;
    rate = allowedRates.contains(storedRate) ? storedRate : 1.0;
    audioLanguage = prefs.getString(_kAudioLanguage) == 'english'
        ? QuranAudioLanguage.english
        : QuranAudioLanguage.arabic;
    final statsRaw = prefs.getString(_kStats);
    if (statsRaw != null) {
      try {
        stats = QuranListeningStats.fromJson(
            jsonDecode(statsRaw) as Map<String, dynamic>);
      } catch (_) {}
    }

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleItemEnd();
      }
    });
    _player.durationStream.listen((d) {
      if (d != null && d.inMilliseconds > 0) {
        final seconds = d.inMilliseconds / 1000.0;
        if (itemDuration != seconds) {
          itemDuration = seconds;
          notifyListeners();
        }
      }
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    await _restoreLastSession();
    notifyListeners();
  }

  Future<void> _restoreLastSession() async {
    final number = _prefs?.getInt(_kLastSurah) ?? 0;
    if (number <= 0) return;
    final surah = QuranLibrary.surah(number);
    if (surah == null) return;
    queue = QuranLibrary.surahs.map((s) => s.number).toList();
    contextLabel = 'All Surahs';
    _rebuildTraversal(keepingCurrentFirst: false);
    final pos = _traversal.indexWhere((i) => queue[i] == number);
    if (pos >= 0) _traversalPos = pos;
    final position = _prefs?.getDouble(_kLastPosition) ?? 0;
    await _load(surah, startAt: position, autoplay: false);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _player.dispose();
    super.dispose();
  }

  // MARK: - Loading & playback

  /// Starts a surah as part of a queue (surah numbers, in display
  /// order) under a context label ("All Surahs", "Favorites", ...).
  void play(int surahNumber,
      {required List<int> queue, required String contextLabel}) {
    final surah = QuranLibrary.surah(surahNumber);
    if (surah == null) return;
    // A fresh queue starts in its own order (iOS build 39).
    if (shuffle) {
      shuffle = false;
      _prefs?.setBool(_kShuffle, false);
    }
    this.queue = queue.isEmpty ? [surahNumber] : List.of(queue);
    this.contextLabel = contextLabel;
    _rebuildTraversal(keepingCurrentFirst: false);
    final pos = _traversal.indexWhere((i) => this.queue[i] == surahNumber);
    _traversalPos = pos >= 0 ? pos : 0;
    _load(surah, startAt: 0, autoplay: true);
    notifyListeners();
  }

  /// Jumps to a surah already in the current queue.
  void playFromQueue(int surahNumber) {
    if (!queue.contains(surahNumber)) return;
    final pos = _traversal.indexWhere((i) => queue[i] == surahNumber);
    final surah = QuranLibrary.surah(surahNumber);
    if (pos < 0 || surah == null) return;
    _traversalPos = pos;
    _load(surah, startAt: 0, autoplay: true);
    notifyListeners();
  }

  /// Inserts a surah into the queue immediately after the current
  /// one, so it plays next whether shuffle is on or off.
  void playNext(int surahNumber) {
    if (QuranLibrary.surah(surahNumber) == null) return;
    if (queue.isEmpty || _traversal.isEmpty || currentSurah == null) {
      play(surahNumber,
          queue: [surahNumber],
          contextLabel: contextLabel.isEmpty ? 'All Surahs' : contextLabel);
      return;
    }
    final insertAt = _traversal[_traversalPos] + 1;
    queue.insert(insertAt, surahNumber);
    _traversal = _traversal.map((i) => i >= insertAt ? i + 1 : i).toList();
    _traversal.insert(_traversalPos + 1, insertAt);
    notifyListeners();
  }

  /// Appends a surah to the end of the queue.
  void enqueue(int surahNumber) {
    if (QuranLibrary.surah(surahNumber) == null) return;
    if (queue.isEmpty || currentSurah == null) {
      play(surahNumber,
          queue: [surahNumber],
          contextLabel: contextLabel.isEmpty ? 'All Surahs' : contextLabel);
      return;
    }
    queue.add(surahNumber);
    _traversal.add(queue.length - 1);
    notifyListeners();
  }

  void togglePlayPause() => isPlaying ? pause() : resume();

  void resume() {
    if (currentSurah == null) return;
    _player.setVolume(1);
    _applyPlay();
    isPlaying = true;
    _persistPosition();
    notifyListeners();
  }

  void pause() {
    _player.pause();
    _player.setVolume(1);
    isPlaying = false;
    _flushListenStats();
    _persistPosition();
    _writeWidgetSnapshot(force: true);
    notifyListeners();
  }

  void next() => _advance(manual: true);

  void previous() {
    if (currentTime > 3) {
      seek(0);
      return;
    }
    if (_traversalPos > 0) {
      _traversalPos -= 1;
      _load(_queueSurah, startAt: 0, autoplay: true);
    } else if (repeatMode == QuranRepeatMode.all && _traversal.isNotEmpty) {
      _traversalPos = _traversal.length - 1;
      _load(_queueSurah, startAt: 0, autoplay: true);
    } else {
      seek(0);
    }
    notifyListeners();
  }

  void seek(double seconds) {
    final target = math.max(0.0, seconds);
    // A manual seek out of an armed ayah loop disarms it.
    final loop = _ayahLoop;
    if (loop != null && (target < loop.start || target >= loop.end)) {
      clearAyahLoop();
    }
    currentTime = target;
    _lastObservedPlaybackTime = target;
    _player.seek(Duration(milliseconds: (target * 1000).round()));
    _persistPosition();
    notifyListeners();
  }

  void setRate(double newRate) {
    if (!allowedRates.contains(newRate)) return;
    rate = newRate;
    _prefs?.setDouble(_kRate, newRate);
    _player.setSpeed(newRate);
    notifyListeners();
  }

  void cycleRepeatMode() {
    repeatMode = switch (repeatMode) {
      QuranRepeatMode.off => QuranRepeatMode.all,
      QuranRepeatMode.all => QuranRepeatMode.one,
      QuranRepeatMode.one => QuranRepeatMode.off,
    };
    _prefs?.setInt(_kRepeatMode, repeatMode.index);
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    _prefs?.setBool(_kShuffle, shuffle);
    _rebuildTraversal(keepingCurrentFirst: true);
    notifyListeners();
  }

  /// Changes the reciter; a loaded surah reloads at the same
  /// position, playing or paused as it was.
  void setReciter(String newReciterId) {
    if (newReciterId == reciterId || QuranLibrary.reciter(newReciterId) == null) {
      return;
    }
    reciterId = newReciterId;
    _prefs?.setString(_kReciter, newReciterId);
    itemDuration = null;
    final surah = currentSurah;
    if (surah != null) {
      _load(surah, startAt: currentTime, autoplay: isPlaying);
    }
    notifyListeners();
  }

  /// Switches between the Arabic reciters and the English
  /// translation; a loaded surah reloads at the same position.
  void setAudioLanguage(QuranAudioLanguage newLanguage) {
    if (newLanguage == audioLanguage) return;
    audioLanguage = newLanguage;
    _prefs?.setString(_kAudioLanguage, newLanguage.name);
    itemDuration = null;
    final surah = currentSurah;
    if (surah != null) {
      _load(surah, startAt: currentTime, autoplay: isPlaying);
    }
    notifyListeners();
  }

  // MARK: Listening stats

  int get completedSurahsTotal => stats.completedTotal;
  double get totalSecondsListened => stats.secondsListened;

  int completionCount(int surahNumber) => stats.perSurah['$surahNumber'] ?? 0;

  void _flushListenStats() {
    if (_unflushedListenSeconds <= 0) return;
    stats.secondsListened += _unflushedListenSeconds;
    _unflushedListenSeconds = 0;
    _saveStats();
  }

  /// A surah reached its natural end (not a skip): count it.
  void _recordCompletion(QuranSurah surah) {
    _flushListenStats();
    stats.completedTotal += 1;
    stats.perSurah['${surah.number}'] =
        (stats.perSurah['${surah.number}'] ?? 0) + 1;
    _saveStats();
  }

  void _saveStats() {
    _prefs?.setString(_kStats, jsonEncode(stats.toJson()));
  }

  // MARK: Sleep timer

  void setSleepOption(QuranSleepOption option) {
    sleepOption = option;
    _sleepDeadline = null;
    _player.setVolume(1);
    final minutes = option.minutes;
    if (minutes != null) {
      _sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
    }
    notifyListeners();
  }

  /// Sleep fade-out (iOS build 31): during the last 30 seconds
  /// before a sleep stop the volume ramps down to zero. Called
  /// from the ticker.
  void _updateSleepFade() {
    double? remaining;
    if (sleepOption.minutes != null) {
      final deadline = _sleepDeadline;
      remaining =
          deadline == null ? null : deadline.difference(DateTime.now()).inMilliseconds / 1000.0;
    } else if (sleepOption.endOfSurah) {
      remaining = duration > 0 ? duration - currentTime : null;
    }
    if (remaining != null && remaining <= 30 && isPlaying) {
      _player.setVolume((remaining / 30).clamp(0.0, 1.0));
    }
  }

  // MARK: Ayah loop (memorization)

  void repeatCurrentAyah({int? plays}) {
    final surah = currentSurah;
    if (surah == null || duration <= 0) return;
    final ayahs = QuranTextData.ayahsBySurah[surah.number];
    if (ayahs == null) return;
    final index = quranCurrentAyahIndex(ayahs, currentTime, duration);
    repeatAyah(index, plays: plays);
  }

  void repeatAyah(int index, {int? plays}) {
    final surah = currentSurah;
    if (surah == null || duration <= 0) return;
    final ayahs = QuranTextData.ayahsBySurah[surah.number];
    if (ayahs == null || index < 0 || index >= ayahs.length) return;
    _ayahLoop = _AyahLoop(
      start: quranAyahStartTime(ayahs, index, duration),
      end: quranAyahEndTime(ayahs, index, duration),
      remainingPlays: plays,
      label: 'Ayah ${ayahs[index].n}',
    );
    ayahLoopLabel = _ayahLoop!.label;
    if (currentTime < _ayahLoop!.start || currentTime >= _ayahLoop!.end) {
      seek(_ayahLoop!.start);
    }
    notifyListeners();
  }

  void loopAyahs(int fromIndex, int toIndex) {
    final surah = currentSurah;
    if (surah == null || duration <= 0) return;
    final ayahs = QuranTextData.ayahsBySurah[surah.number];
    if (ayahs == null ||
        fromIndex < 0 ||
        toIndex >= ayahs.length ||
        fromIndex > toIndex) {
      return;
    }
    _ayahLoop = _AyahLoop(
      start: quranAyahStartTime(ayahs, fromIndex, duration),
      end: quranAyahEndTime(ayahs, toIndex, duration),
      remainingPlays: null,
      label: 'Ayahs ${ayahs[fromIndex].n} to ${ayahs[toIndex].n}',
    );
    ayahLoopLabel = _ayahLoop!.label;
    if (currentTime < _ayahLoop!.start || currentTime >= _ayahLoop!.end) {
      seek(_ayahLoop!.start);
    }
    notifyListeners();
  }

  void clearAyahLoop() {
    _ayahLoop = null;
    ayahLoopLabel = null;
    notifyListeners();
  }

  /// When playback reaches the loop's end, jump back to its start
  /// (or disarm on the last counted pass and let playback go on).
  void _checkAyahLoop() {
    final loop = _ayahLoop;
    if (loop == null || !isPlaying) return;
    if (currentTime < loop.end - 0.15) return;
    if (loop.remainingPlays == 1) {
      clearAyahLoop();
      return;
    }
    if (loop.remainingPlays != null) {
      loop.remainingPlays = loop.remainingPlays! - 1;
    }
    seek(loop.start);
  }

  // MARK: Favorites

  bool isFavorite(int surahNumber) => favorites.contains(surahNumber);

  void toggleFavorite(int surahNumber) {
    if (!favorites.remove(surahNumber)) {
      favorites.add(surahNumber);
    }
    _prefs?.setStringList(
        _kFavorites, favorites.map((n) => '$n').toList()..sort());
    notifyListeners();
  }

  // MARK: - Queue traversal

  QuranSurah get _queueSurah {
    final number = queue[_traversal[_traversalPos]];
    return QuranLibrary.surah(number) ?? QuranLibrary.surahs.first;
  }

  void _rebuildTraversal({required bool keepingCurrentFirst}) {
    final currentNumber = currentSurah?.number;
    var indices = [for (var i = 0; i < queue.length; i++) i];
    if (shuffle) {
      indices.shuffle(math.Random());
      if (keepingCurrentFirst && currentNumber != null) {
        final at = indices.indexWhere((i) => queue[i] == currentNumber);
        if (at > 0) {
          indices.removeAt(at);
          indices.insert(0, at);
        }
      }
    }
    _traversal = indices;
    if (currentNumber != null) {
      final pos = _traversal.indexWhere((i) => queue[i] == currentNumber);
      _traversalPos = pos >= 0 ? pos : 0;
    } else {
      _traversalPos = 0;
    }
  }

  void _advance({required bool manual}) {
    if (_traversal.isEmpty) return;
    if (_traversalPos + 1 < _traversal.length) {
      _traversalPos += 1;
      _load(_queueSurah, startAt: 0, autoplay: true);
    } else if (repeatMode == QuranRepeatMode.all) {
      _traversalPos = 0;
      _load(_queueSurah, startAt: 0, autoplay: true);
    } else if (!manual) {
      _finishPlayback();
    }
    notifyListeners();
  }

  void _finishPlayback() {
    _player.pause();
    isPlaying = false;
    _flushListenStats();
    _persistPosition();
    notifyListeners();
  }

  // MARK: - Item loading

  Future<void> _load(QuranSurah surah,
      {required double startAt, required bool autoplay}) async {
    clearAyahLoop();
    _player.setVolume(1);
    final token = ++_loadToken;
    final local = QuranDownloads.localFile(activeReciterId, surah.number);
    try {
      if (local != null) {
        await _player.setFilePath(local.path);
      } else {
        await _player.setUrl(
            QuranLibrary.audioUrl(surah.number, activeReciterId));
      }
    } catch (_) {
      if (token == _loadToken) {
        isPlaying = false;
        notifyListeners();
      }
      return;
    }
    if (token != _loadToken) return;
    currentSurah = surah;
    itemDuration = null;
    currentTime = startAt;
    _lastObservedPlaybackTime = startAt;
    _pendingSeek = startAt > 0 ? startAt : null;
    _lastSavedSecond = -1;
    _prefs?.setInt(_kLastSurah, surah.number);
    _persistPosition();
    if (_pendingSeek != null) {
      final target = _pendingSeek!;
      _pendingSeek = null;
      await _player.seek(Duration(milliseconds: (target * 1000).round()));
    }
    await _player.setSpeed(rate);
    if (autoplay) {
      _applyPlay();
      isPlaying = true;
    } else {
      isPlaying = false;
    }
    _writeWidgetSnapshot(force: true);
    notifyListeners();
  }

  void _handleItemEnd() {
    final finished = currentSurah;
    if (finished != null) _recordCompletion(finished);
    if (sleepOption.endOfSurah) {
      sleepOption = const QuranSleepOption.off();
      _finishPlayback();
      notifyListeners();
      return;
    }
    if (repeatMode == QuranRepeatMode.one) {
      seek(0);
      _applyPlay();
      isPlaying = true;
      notifyListeners();
      return;
    }
    _advance(manual: false);
  }

  void _applyPlay() {
    _player.setSpeed(rate);
    _player.play();
  }

  void _persistPosition() {
    _prefs?.setDouble(_kLastPosition, currentTime);
    _lastSavedSecond = currentTime.floor();
    _writeWidgetSnapshot(force: false);
  }

  // MARK: - Continue Listening widget snapshot

  /// Mirrors the session into shared preferences for the Continue
  /// Listening widget (the Kotlin provider reads the same keys the
  /// iOS widget reads from its App Group suite). Reload pings are
  /// throttled to one per 30 seconds, with pause forcing one.
  void _writeWidgetSnapshot({required bool force}) {
    final surah = currentSurah;
    final prefs = _prefs;
    if (surah == null || prefs == null) return;
    prefs.setString('quran.widget.surah', surah.english);
    prefs.setString('quran.widget.arabic', surah.arabic);
    prefs.setString('quran.widget.reciter', currentReciter?.name ?? '');
    // Whole seconds as ints: the Kotlin widget reads them as Long,
    // the same unambiguous encoding as the other widget keys.
    prefs.setInt('quran.widget.number', surah.number);
    prefs.setInt('quran.widget.position', currentTime.floor());
    prefs.setInt('quran.widget.duration', duration.floor());
    prefs.setBool('quran.widget.has', true);
    if (force ||
        DateTime.now().difference(_lastWidgetReload) >
            const Duration(seconds: 30)) {
      _lastWidgetReload = DateTime.now();
      _widgetChannel.invokeMethod('refreshListening').catchError((_) => null);
    }
  }

  // MARK: - Ticker (the iOS time observer's duties)

  void _tick() {
    final position = _player.position.inMilliseconds / 1000.0;
    if (position >= 0 && (position - currentTime).abs() > 0.01) {
      currentTime = position;
    }
    // Listening stats: credit the position delta while playing
    // (small, forward only, so seeks and stalls never inflate it).
    final delta = currentTime - _lastObservedPlaybackTime;
    if (isPlaying && delta > 0 && delta <= 2) {
      _unflushedListenSeconds += delta;
    }
    _lastObservedPlaybackTime = currentTime;
    if (_unflushedListenSeconds >= 10) _flushListenStats();
    // Sleep timer expiry (the fade runs in _updateSleepFade).
    final deadline = _sleepDeadline;
    if (deadline != null && !DateTime.now().isBefore(deadline)) {
      _sleepDeadline = null;
      sleepOption = const QuranSleepOption.off();
      pause();
      notifyListeners();
      return;
    }
    _updateSleepFade();
    _checkAyahLoop();
    final whole = currentTime.floor();
    if ((whole - _lastSavedSecond).abs() >= 5) {
      _persistPosition();
    }
    notifyListeners();
  }
}
