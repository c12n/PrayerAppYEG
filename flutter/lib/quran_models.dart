// Quran layer (v3.0.0) — the Android counterpart of the iOS Quran
// models: the bundled surah catalogue (surahs.json), the ayah text
// store (quran_text.json — Arabic Uthmani + Saheeh International),
// ayah bookmarks, and the character-weighted ayah timing estimates
// the lyrics view and the memorization loop share, all ported from
// QuranModels.swift / QuranLyrics.swift.

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuranReciter {
  final String id;
  final String name;
  const QuranReciter({required this.id, required this.name});

  factory QuranReciter.fromJson(Map<String, dynamic> json) => QuranReciter(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class QuranSurah {
  final int number;
  final String arabic;
  final String english;
  final String meaning;
  final int ayahs;

  /// "Makki" or "Madani".
  final String revelation;

  /// Stream duration in seconds, keyed by reciter id.
  final Map<String, int> durations;

  const QuranSurah({
    required this.number,
    required this.arabic,
    required this.english,
    required this.meaning,
    required this.ayahs,
    required this.revelation,
    required this.durations,
  });

  factory QuranSurah.fromJson(Map<String, dynamic> json) => QuranSurah(
        number: json['number'] as int,
        arabic: json['arabic'] as String,
        english: json['english'] as String,
        meaning: json['meaning'] as String,
        ayahs: json['ayahs'] as int,
        revelation: json['revelation'] as String,
        durations: (json['durations'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      );

  int get id => number;

  int? durationFor(String reciterId) => durations[reciterId];
}

/// The bundled catalogue, loaded once from assets (iOS: QuranLibrary).
class QuranLibrary {
  static List<QuranReciter> reciters = [];
  static List<QuranSurah> surahs = [];
  static String audioBase = '';
  static Map<int, int> englishDurations = {};
  static bool _loaded = false;

  /// The pseudo-reciter id for the English translation audio; it
  /// keys the downloads folder exactly like a reciter id (iOS).
  static const englishReciterId = 'english';
  static const englishReciter =
      QuranReciter(id: englishReciterId, name: 'Ibrahim Walk (English)');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await rootBundle.loadString('assets/quran/surahs.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    reciters = (decoded['reciters'] as List)
        .map((e) => QuranReciter.fromJson(e as Map<String, dynamic>))
        .toList();
    audioBase = decoded['audioBase'] as String;
    surahs = (decoded['surahs'] as List)
        .map((e) => QuranSurah.fromJson(e as Map<String, dynamic>))
        .toList();
    final enRaw = await rootBundle.loadString('assets/quran/en_durations.json');
    final en = jsonDecode(enRaw) as Map<String, dynamic>;
    englishDurations = {
      for (final entry in en.entries)
        if (int.tryParse(entry.key) != null)
          int.parse(entry.key): (entry.value as num).toInt(),
    };
  }

  static QuranSurah? surah(int number) {
    for (final s in surahs) {
      if (s.number == number) return s;
    }
    return null;
  }

  static QuranReciter? reciter(String id) {
    for (final r in reciters) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The first reciter in the catalogue (Alafasy) — the default.
  static QuranReciter? get defaultReciter =>
      reciters.isEmpty ? null : reciters.first;

  /// "{audioBase}/{reciterId}/{number}.mp3" — a 128 kbps stream.
  static String streamUrl(int surahNumber, String reciterId) =>
      '$audioBase/$reciterId/$surahNumber.mp3';

  /// Full-surah English translation MP3s (Ibrahim Walk), hosted by
  /// QuranicAudio; surah number zero-padded to three digits.
  static String englishStreamUrl(int surahNumber) =>
      'https://download.quranicaudio.com/quran/ibrahim_walk/'
      '${surahNumber.toString().padLeft(3, '0')}.mp3';

  /// The stream URL for any reciter id, English included.
  static String audioUrl(int surahNumber, String reciterId) =>
      reciterId == englishReciterId
          ? englishStreamUrl(surahNumber)
          : streamUrl(surahNumber, reciterId);

  static int? durationSeconds(int surahNumber, String reciterId) =>
      reciterId == englishReciterId
          ? englishDurations[surahNumber]
          : surah(surahNumber)?.durationFor(reciterId);

  /// "7:02" under an hour, "2:05:40" above it.
  static String formatDuration(num seconds) {
    final total = seconds < 0 ? 0 : seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }
}

/// A named playlist of surahs, shown as a card in the library (iOS).
class QuranCollection {
  final String id;
  final String titleKey;
  final String subtitleKey;
  final List<int> surahNumbers;
  const QuranCollection({
    required this.id,
    required this.titleKey,
    required this.subtitleKey,
    required this.surahNumbers,
  });

  List<QuranSurah> get surahs =>
      surahNumbers.map(QuranLibrary.surah).whereType<QuranSurah>().toList();

  static const collections = [
    QuranCollection(
      id: 'ramadan',
      titleKey: 'ramadan',
      subtitleKey: 'colRamadanSub',
      surahNumbers: [2, 36, 18, 55, 67, 97, 12, 19, 78, 112, 113, 114],
    ),
    QuranCollection(
      id: 'eid',
      titleKey: 'colEid',
      subtitleKey: 'colEidSub',
      surahNumbers: [87, 88, 50, 54, 109, 112, 113, 114],
    ),
  ];
}

// MARK: - Ayah text (quran_text.json)

class QuranAyahText {
  /// Ayah number within the surah.
  final int n;
  final String ar;
  final String en;
  const QuranAyahText({required this.n, required this.ar, required this.en});

  factory QuranAyahText.fromJson(Map<String, dynamic> json) => QuranAyahText(
        n: json['n'] as int,
        ar: json['ar'] as String,
        en: json['en'] as String,
      );
}

/// Loads quran_text.json once and caches it (iOS: QuranTextData).
class QuranTextData {
  static Map<int, List<QuranAyahText>> ayahsBySurah = {};
  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      final raw = await rootBundle.loadString('assets/quran/quran_text.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = <int, List<QuranAyahText>>{};
      for (final entry in decoded.entries) {
        final number = int.tryParse(entry.key);
        if (number == null) continue;
        parsed[number] = (entry.value as List)
            .map((e) => QuranAyahText.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      ayahsBySurah = parsed;
      _loaded = true;
    }();
  }
}

// MARK: - Ayah timing estimates (character-weighted, as iOS)

int _weight(QuranAyahText ayah) => ayah.ar.length < 1 ? 1 : ayah.ar.length;

/// Estimated current ayah index: playback fraction applied across
/// the ayahs weighted by Arabic character count.
int quranCurrentAyahIndex(List<QuranAyahText> ayahs, double time, double duration) {
  if (ayahs.isEmpty || duration <= 0) return 0;
  final weights = ayahs.map(_weight).toList();
  final total = weights.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return 0;
  var target = (time / duration) * total;
  for (var i = 0; i < weights.length; i++) {
    if (target < weights[i]) return i;
    target -= weights[i];
  }
  return ayahs.length - 1;
}

/// Start time of an ayah under the same weighted estimate.
double quranAyahStartTime(List<QuranAyahText> ayahs, int index, double duration) {
  if (index < 0 || index >= ayahs.length || duration <= 0) return 0;
  final weights = ayahs.map(_weight).toList();
  final total = weights.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return 0;
  final before = weights.sublist(0, index).fold<int>(0, (a, b) => a + b);
  return duration * before / total;
}

/// End time of an ayah under the same weighted estimate.
double quranAyahEndTime(List<QuranAyahText> ayahs, int index, double duration) {
  if (index < 0 || index >= ayahs.length || duration <= 0) return 0;
  if (index + 1 >= ayahs.length) return duration;
  return quranAyahStartTime(ayahs, index + 1, duration);
}

// MARK: - Ayah bookmarks (iOS: QuranBookmarks)

/// One saved ayah: a surah number + ayah number within it.
class QuranBookmark {
  final int surah;
  final int ayah;
  final DateTime createdAt;
  const QuranBookmark({
    required this.surah,
    required this.ayah,
    required this.createdAt,
  });

  String get id => '$surah:$ayah';

  Map<String, dynamic> toJson() => {
        'surah': surah,
        'ayah': ayah,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory QuranBookmark.fromJson(Map<String, dynamic> json) => QuranBookmark(
        surah: json['surah'] as int,
        ayah: json['ayah'] as int,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      );
}

/// Persisted ayah bookmarks (`quran.bookmarks.v1` JSON, like iOS).
class QuranBookmarks extends ChangeNotifier {
  static const _key = 'quran.bookmarks.v1';
  List<QuranBookmark> bookmarks = [];
  SharedPreferences? _prefs;

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        bookmarks = (jsonDecode(raw) as List)
            .map((e) => QuranBookmark.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {
        bookmarks = [];
      }
    }
    notifyListeners();
  }

  bool isBookmarked(int surah, int ayah) =>
      bookmarks.any((b) => b.surah == surah && b.ayah == ayah);

  void toggle(int surah, int ayah) {
    if (isBookmarked(surah, ayah)) {
      bookmarks.removeWhere((b) => b.surah == surah && b.ayah == ayah);
    } else {
      bookmarks.insert(
          0, QuranBookmark(surah: surah, ayah: ayah, createdAt: DateTime.now()));
    }
    _save();
    notifyListeners();
  }

  void remove(QuranBookmark bookmark) {
    bookmarks.removeWhere((b) => b.id == bookmark.id);
    _save();
    notifyListeners();
  }

  void _save() {
    _prefs?.setString(
        _key, jsonEncode(bookmarks.map((b) => b.toJson()).toList()));
  }
}

/// Player brand colors (iOS: QuranTheme) — the deep green / gold
/// palette the mini player and Now Playing wear regardless of theme.
class QuranThemeColors {
  static const deepGreen = Color(0xFF0B3D2E);
  static const midGreen = Color(0xFF0E5A3F);
  static const darkestGreen = Color(0xFF06231A);
  static const accentGreen = Color(0xFF0B7A55);
  static const gold = Color(0xFFD4AF37);
  static const lightGold = Color(0xFFE9D48A);
  static const mutedOnGreen = Color(0xFFBFD8CC);
  static const heartRed = Color(0xFFE5484D);
}
