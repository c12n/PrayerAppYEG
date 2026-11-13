// Quran UI (v3.0.0) — the Android counterpart of the iOS Quran
// views: the library (search, Favorites / Downloaded / Bookmarks
// chips, collections, options), the Spotify-style Now Playing
// page, the lyrics page (tap-to-seek, bookmarks, memorization
// loop), the downloads manager, and the mini player bar.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'layout.dart';
import 'quran_downloads.dart';
import 'quran_models.dart';
import 'quran_player.dart';
import 'strings.dart';
import 'tab_nav.dart';
import 'prayer_models.dart' show LanguageState;

// MARK: - Scope

class QuranScope extends InheritedWidget {
  final QuranPlayer player;
  final QuranDownloads downloads;
  final QuranBookmarks bookmarks;
  const QuranScope({
    super.key,
    required this.player,
    required this.downloads,
    required this.bookmarks,
    required super.child,
  });

  static QuranScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QuranScope>()!;

  @override
  bool updateShouldNotify(QuranScope oldWidget) =>
      player != oldWidget.player ||
      downloads != oldWidget.downloads ||
      bookmarks != oldWidget.bookmarks;
}

// MARK: - Shared pieces

/// Deterministic per-surah colors (iOS: SurahPalette): a
/// golden-ratio hue walk.
Color surahColor(int surahNumber, double saturation, double brightness) {
  final hue = (surahNumber * 0.6180339887) % 1.0;
  return HSVColor.fromAHSV(1, hue * 360, saturation, brightness).toColor();
}

/// The generated cover tile: gradient + Arabic name + number.
class SurahArtwork extends StatelessWidget {
  final QuranSurah surah;
  final double size;
  final double cornerRadius;
  const SurahArtwork({
    super.key,
    required this.surah,
    required this.size,
    this.cornerRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cornerRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surahColor(surah.number, 0.55, 0.62),
            surahColor(surah.number, 0.65, 0.34),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                surah.arabic,
                style: TextStyle(
                  fontSize: size * 0.30,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                        color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SURAH ${surah.number}',
            style: TextStyle(
              fontSize: size * 0.075,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

String listenedLabel(QuranPlayer player) {
  final total = player.totalSecondsListened.round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  return hours > 0
      ? S.f('listenedHoursFmt', {'hours': '$hours', 'minutes': '$minutes'})
      : S.f('listenedMinutesFmt', {'minutes': '$minutes'});
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) {
    return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

// MARK: - Home entry card + Continue Listening

/// Home screen card: opens the Quran library; while a session
/// exists it doubles as the Continue Listening card (iOS widget
/// parity): last surah, voice, progress, resume.
class QuranEntryCard extends StatelessWidget {
  const QuranEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final player = scope.player;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final surah = player.currentSurah;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // The library is the Quran tab now (1:1 tab shell);
            // the push remains as a fallback for any context
            // outside the shell.
            onTap: () {
              final nav = TabNavScope.maybeOf(context);
              if (nav != null) {
                nav.goTo(TabNavController.quran);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QuranLibraryPage()),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.menu_book, size: 20),
                      const SizedBox(width: 8),
                      Text(S.t('quran'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.f('quranSubFmt',
                        {'reciter': player.currentReciter?.name ?? ''}),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (surah != null) ...[
                    const Divider(height: 20),
                    Row(
                      children: [
                        SurahArtwork(surah: surah, size: 46, cornerRadius: 10),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(S.t('continueListeningTitle'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  )),
                              Text(
                                '${surah.number}. ${surah.english}',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: player.duration > 0
                                    ? (player.currentTime / player.duration)
                                        .clamp(0.0, 1.0)
                                    : 0,
                                minHeight: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(player.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled),
                          iconSize: 38,
                          color: QuranThemeColors.midGreen,
                          onPressed: player.togglePlayPause,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// MARK: - Mini player

/// The pill bar floating over the library / home while a surah is
/// loaded (iOS: MiniPlayerView). Tap opens Now Playing.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = QuranScope.of(context).player;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final surah = player.currentSurah;
        if (surah == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: GestureDetector(
              // Swipe down on the pill dismisses the player
              // (v3.0.2, iOS parity): a deliberate downward flick
              // stops playback and unloads the surah. Taps still
              // reach the InkWell (open Now Playing) and the
              // transport buttons.
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 300) {
                  player.dismiss();
                }
              },
              child: Material(
              color: QuranThemeColors.deepGreen,
              borderRadius: BorderRadius.circular(16),
              elevation: 6,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NowPlayingPage()),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      SurahArtwork(surah: surah, size: 42, cornerRadius: 9),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${surah.number}. ${surah.english}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              player.currentReciter?.name ?? '',
                              style: const TextStyle(
                                color: QuranThemeColors.mutedOnGreen,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white),
                        onPressed: player.togglePlayPause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: player.next,
                      ),
                    ],
                  ),
                ),
              ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// MARK: - Library

class QuranLibraryPage extends StatefulWidget {
  /// In the tab shell the library is the Quran tab: the shell
  /// provides the mini player, so the page drops its own.
  final bool embedded;
  const QuranLibraryPage({super.key, this.embedded = false});

  @override
  State<QuranLibraryPage> createState() => _QuranLibraryPageState();
}

class _QuranLibraryPageState extends State<QuranLibraryPage> {
  String _search = '';
  bool _favoritesOnly = false;
  bool _downloadedOnly = false;
  bool _bookmarksOnly = false;

  /// Expanded windows show the player in a right-hand pane; this
  /// flips that pane between Now Playing and the lyrics view.
  bool _rightShowsLyrics = false;

  List<QuranSurah> _displayed(QuranScope scope) {
    var list = List.of(QuranLibrary.surahs);
    if (_favoritesOnly) {
      list = list.where((s) => scope.player.isFavorite(s.number)).toList();
    }
    if (_downloadedOnly) {
      list = list
          .where((s) => scope.downloads
              .isDownloaded(scope.player.activeReciterId, s.number))
          .toList();
    }
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((s) =>
              s.english.toLowerCase().contains(query) ||
              s.meaning.toLowerCase().contains(query) ||
              s.arabic.contains(_search.trim()) ||
              '${s.number}' == query)
          .toList();
    }
    return list;
  }

  String get _contextLabel {
    if (_favoritesOnly) return 'Favorites';
    if (_downloadedOnly) return 'Downloaded';
    return 'All Surahs';
  }

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final player = scope.player;
    return AnimatedBuilder(
      animation:
          Listenable.merge([player, scope.downloads, scope.bookmarks]),
      builder: (context, _) {
        final displayed = _displayed(scope);
        return Scaffold(
          appBar: AppBar(
            title: Text(S.t('quran')),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_horiz),
                tooltip: S.t('options'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QuranOptionsPage()),
                ),
              ),
            ],
          ),
          bottomNavigationBar:
              widget.embedded ? null : const MiniPlayerBar(),
          body: _body(context, scope, displayed),
        );
      },
    );
  }

  /// Compact and medium windows keep the single list the library
  /// has always been. Expanded windows (Chromebooks, tablets,
  /// unfolded foldables) split into two panes: the library list
  /// on the left and Now Playing (or the lyrics) on the right,
  /// with the split moved to the hinge on book-mode foldables.
  Widget _body(BuildContext context, QuranScope scope,
      List<QuranSurah> displayed) {
    if (!windowSizeClassOf(context).isExpanded) {
      return _listBody(context, scope, displayed);
    }
    final width = MediaQuery.sizeOf(context).width;
    final split = hingeSplit(context, width, startInset: 16, endInset: 16);
    final Widget rightPane = _rightShowsLyrics
        ? QuranLyricsPage(
            embedded: true,
            onClose: () => setState(() => _rightShowsLyrics = false),
          )
        : NowPlayingPage(
            embedded: true,
            onOpenLyrics: () => setState(() => _rightShowsLyrics = true),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (split != null) ...[
            SizedBox(
              width: split.firstWidth,
              child: _listBody(context, scope, displayed, inPane: true),
            ),
            SizedBox(width: split.gapWidth),
          ] else ...[
            Expanded(
              flex: 5,
              child: _listBody(context, scope, displayed, inPane: true),
            ),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: rightPane,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listBody(BuildContext context, QuranScope scope,
      List<QuranSurah> displayed,
      {bool inPane = false}) {
    final player = scope.player;
    final expanded = windowSizeClassOf(context).isExpanded;
    return ListView(
            padding: inPane
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                S.f('quranSubFmt',
                    {'reciter': player.currentReciter?.name ?? ''}),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                S.f('quranStatsFmt', {
                  'completed': '${player.completedSurahsTotal}',
                  'listened': listenedLabel(player),
                }),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: QuranThemeColors.midGreen,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  hintText: S.t('searchSurahs'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip(
                      context,
                      icon: Icons.favorite,
                      iconColor: QuranThemeColors.heartRed,
                      label: S.t('favorites'),
                      count: player.favorites.length,
                      isOn: _favoritesOnly,
                      onTap: () => setState(() {
                        _favoritesOnly = !_favoritesOnly;
                        if (_favoritesOnly) _bookmarksOnly = false;
                      }),
                    ),
                    _chip(
                      context,
                      icon: Icons.download_done,
                      iconColor: QuranThemeColors.midGreen,
                      label: S.t('downloadedFilter'),
                      count: scope.downloads.downloadedCount,
                      isOn: _downloadedOnly,
                      onTap: () => setState(() {
                        _downloadedOnly = !_downloadedOnly;
                        if (_downloadedOnly) _bookmarksOnly = false;
                      }),
                    ),
                    _chip(
                      context,
                      icon: Icons.bookmark,
                      iconColor: QuranThemeColors.gold,
                      label: S.t('bookmarks'),
                      count: scope.bookmarks.bookmarks.length,
                      isOn: _bookmarksOnly,
                      onTap: () => setState(() {
                        _bookmarksOnly = !_bookmarksOnly;
                        if (_bookmarksOnly) {
                          _favoritesOnly = false;
                          _downloadedOnly = false;
                        }
                      }),
                    ),
                    if (player.currentSurah != null)
                      _chip(
                        context,
                        icon: Icons.history,
                        iconColor: QuranThemeColors.midGreen,
                        label: S.t('continueListeningTitle'),
                        count: null,
                        isOn: false,
                        onTap: () {
                          player.resume();
                          if (expanded) {
                            setState(() => _rightShowsLyrics = false);
                          } else {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const NowPlayingPage()));
                          }
                        }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_bookmarksOnly)
                ..._bookmarkRows(context, scope)
              else ...[
                if (_search.isEmpty && !_favoritesOnly && !_downloadedOnly)
                  for (final collection in QuranCollection.collections)
                    _collectionCard(context, collection),
                if (_favoritesOnly && displayed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FilledButton.icon(
                      onPressed: () {
                        player.play(displayed.first.number,
                            queue: displayed.map((s) => s.number).toList(),
                            contextLabel: 'Favorites');
                        if (expanded) {
                          setState(() => _rightShowsLyrics = false);
                        } else {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const NowPlayingPage()));
                        }
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(S.t('playAllFavorites')),
                      style: FilledButton.styleFrom(
                        backgroundColor: QuranThemeColors.midGreen,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                if (displayed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      _favoritesOnly
                          ? S.t('noFavoritesYet')
                          : _downloadedOnly
                              ? S.t('noDownloadsYet')
                              : S.t('noSurahMatch'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                for (final surah in displayed)
                  SurahRow(
                    surah: surah,
                    onPlay: () {
                      player.play(surah.number,
                          queue: displayed.map((s) => s.number).toList(),
                          contextLabel: _contextLabel);
                      if (expanded) {
                        setState(() => _rightShowsLyrics = false);
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const NowPlayingPage()));
                      }
                    },
                  ),
              ],
            ],
          );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required int? count,
    required bool isOn,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FilterChip(
        avatar: Icon(icon, size: 18, color: iconColor),
        label: Text(count != null ? '$label  $count' : label),
        selected: isOn,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _collectionCard(BuildContext context, QuranCollection collection) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => CollectionDetailPage(collection: collection)),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [QuranThemeColors.midGreen, QuranThemeColors.deepGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t(collection.titleKey),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        )),
                    Text(S.t(collection.subtitleKey),
                        style: const TextStyle(
                            color: QuranThemeColors.mutedOnGreen,
                            fontSize: 13)),
                  ],
                ),
              ),
              Text(
                '${collection.surahNumbers.length}',
                style: const TextStyle(
                  color: QuranThemeColors.lightGold,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bookmarkRows(BuildContext context, QuranScope scope) {
    final expanded = windowSizeClassOf(context).isExpanded;
    final bookmarks = scope.bookmarks.bookmarks;
    if (bookmarks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            S.t('noBookmarksYet'),
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ];
    }
    return [
      for (final bookmark in bookmarks)
        Builder(builder: (context) {
          final surah = QuranLibrary.surah(bookmark.surah);
          if (surah == null) return const SizedBox.shrink();
          return ListTile(
            leading: SurahArtwork(surah: surah, size: 42, cornerRadius: 9),
            title: Text('${surah.english} · ${S.f('ayahFmt', {'n': '${bookmark.ayah}'})}'),
            subtitle: Text(surah.arabic),
            trailing: IconButton(
              icon: const Icon(Icons.bookmark_remove_outlined),
              onPressed: () => scope.bookmarks.remove(bookmark),
            ),
            onTap: () {
              // Play the surah and seek to the bookmarked ayah once
              // its duration is known (iOS playBookmark).
              final player = scope.player;
              player.play(surah.number,
                  queue: QuranLibrary.surahs.map((s) => s.number).toList(),
                  contextLabel: 'All Surahs');
              final ayahs = QuranTextData.ayahsBySurah[surah.number];
              if (ayahs != null) {
                final index =
                    ayahs.indexWhere((a) => a.n == bookmark.ayah);
                final known = player.displayDuration(surah);
                if (index >= 0 && known != null && known > 0) {
                  final target =
                      quranAyahStartTime(ayahs, index, known);
                  unawaited(Future.delayed(
                      const Duration(milliseconds: 900), () {
                    if (player.currentSurah?.number == surah.number) {
                      player.seek(target);
                    }
                  }));
                }
              }
              if (expanded) {
                setState(() => _rightShowsLyrics = false);
              } else {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NowPlayingPage()));
              }
            },
          );
        }),
    ];
  }
}

/// One library row: number tile, names, duration, download control,
/// favorite heart; long-press opens the actions sheet (iOS context
/// menu: Play, Play Next, Add to Queue, Favorite, Download).
class SurahRow extends StatelessWidget {
  final QuranSurah surah;
  final VoidCallback onPlay;
  const SurahRow({super.key, required this.surah, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final player = scope.player;
    final isCurrent = surah.number == player.currentSurah?.number;
    final isFridayPick = surah.number == 18;
    final reciterId = player.activeReciterId;
    return InkWell(
      onTap: onPlay,
      onLongPress: () => _showActions(context, scope),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isFridayPick
                      ? const [
                          QuranThemeColors.lightGold,
                          QuranThemeColors.gold
                        ]
                      : const [
                          QuranThemeColors.deepGreen,
                          QuranThemeColors.midGreen
                        ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${surah.number}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isFridayPick
                      ? QuranThemeColors.deepGreen
                      : QuranThemeColors.lightGold,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          surah.english,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isCurrent
                                ? QuranThemeColors.midGreen
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(surah.arabic,
                          style: const TextStyle(
                              fontSize: 16,
                              color: QuranThemeColors.deepGreen)),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Icon(
                          player.isPlaying
                              ? Icons.volume_up
                              : Icons.pause_circle_filled,
                          size: 16,
                          color: QuranThemeColors.midGreen,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${surah.meaning} | ${S.f('ayahsFmt', {'count': '${surah.ayahs}'})} | ${S.t(surah.revelation == 'Makki' ? 'makki' : 'madani')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (player.displayDuration(surah) != null)
              Text(
                QuranLibrary.formatDuration(player.displayDuration(surah)!),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            _downloadControl(context, scope, reciterId),
            IconButton(
              icon: Icon(
                player.isFavorite(surah.number)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: player.isFavorite(surah.number)
                    ? QuranThemeColors.heartRed
                    : Colors.grey,
              ),
              onPressed: () => player.toggleFavorite(surah.number),
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadControl(
      BuildContext context, QuranScope scope, String reciterId) {
    final downloads = scope.downloads;
    final progress = downloads.progress(reciterId, surah.number);
    if (progress != null) {
      return IconButton(
        icon: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(value: progress, strokeWidth: 2.5),
        ),
        onPressed: () => downloads.cancel(surah.number, reciterId),
      );
    }
    if (downloads.isDownloaded(reciterId, surah.number)) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.check_circle,
            color: QuranThemeColors.midGreen, size: 22),
      );
    }
    return IconButton(
      icon: const Icon(Icons.download_outlined, color: Colors.grey),
      onPressed: () => downloads.download(surah.number, reciterId),
    );
  }

  void _showActions(BuildContext context, QuranScope scope) {
    final player = scope.player;
    final downloads = scope.downloads;
    final reciterId = player.activeReciterId;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(S.t('play')),
              onTap: () {
                Navigator.pop(context);
                onPlay();
              },
            ),
            ListTile(
              leading: const Icon(Icons.skip_next),
              title: Text(S.t('playNext')),
              onTap: () {
                player.playNext(surah.number);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(S.t('addToQueue')),
              onTap: () {
                player.enqueue(surah.number);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(player.isFavorite(surah.number)
                  ? Icons.favorite
                  : Icons.favorite_border),
              title: Text(player.isFavorite(surah.number)
                  ? S.t('removeFromFavorites')
                  : S.t('addToFavorites')),
              onTap: () {
                player.toggleFavorite(surah.number);
                Navigator.pop(context);
              },
            ),
            if (downloads.isDownloading(reciterId, surah.number))
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: Text(S.t('cancelDownload')),
                onTap: () {
                  downloads.cancel(surah.number, reciterId);
                  Navigator.pop(context);
                },
              )
            else if (downloads.isDownloaded(reciterId, surah.number))
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(S.t('removeDownload')),
                onTap: () {
                  downloads.delete(surah.number, reciterId);
                  Navigator.pop(context);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(S.t('download')),
                onTap: () {
                  downloads.download(surah.number, reciterId);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Collection detail

class CollectionDetailPage extends StatelessWidget {
  final QuranCollection collection;
  const CollectionDetailPage({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    final player = QuranScope.of(context).player;
    final surahs = collection.surahs;
    return Scaffold(
      appBar: AppBar(title: Text(S.t(collection.titleKey))),
      bottomNavigationBar: const MiniPlayerBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(S.t(collection.subtitleKey),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              if (surahs.isEmpty) return;
              player.play(surahs.first.number,
                  queue: surahs.map((s) => s.number).toList(),
                  contextLabel: S.t(collection.titleKey));
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NowPlayingPage()));
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(S.t('play')),
            style: FilledButton.styleFrom(
              backgroundColor: QuranThemeColors.midGreen,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          for (final surah in surahs)
            SurahRow(
              surah: surah,
              onPlay: () {
                player.play(surah.number,
                    queue: surahs.map((s) => s.number).toList(),
                    contextLabel: S.t(collection.titleKey));
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NowPlayingPage()));
              },
            ),
        ],
      ),
    );
  }
}

// MARK: - Options

class QuranOptionsPage extends StatelessWidget {
  const QuranOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final player = scope.player;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(S.t('options'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _header(context, S.t('audioLanguage')),
              RadioGroup<QuranAudioLanguage>(
                groupValue: player.audioLanguage,
                onChanged: (v) {
                  if (v != null) player.setAudioLanguage(v);
                },
                child: Column(
                  children: [
                    RadioListTile<QuranAudioLanguage>(
                      value: QuranAudioLanguage.arabic,
                      title: Text(S.t('arabicLang')),
                    ),
                    RadioListTile<QuranAudioLanguage>(
                      value: QuranAudioLanguage.english,
                      title: Text(S.t('englishWalk')),
                    ),
                  ],
                ),
              ),
              if (player.audioLanguage == QuranAudioLanguage.arabic) ...[
                const SizedBox(height: 12),
                _header(context, S.t('reciterLabel')),
                RadioGroup<String>(
                  groupValue: player.reciterId,
                  onChanged: (v) {
                    if (v != null) player.setReciter(v);
                  },
                  child: Column(
                    children: [
                      for (final reciter in QuranLibrary.reciters)
                        RadioListTile<String>(
                          value: reciter.id,
                          title: Text(reciter.name),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(S.t('manageDownloads')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const QuranDownloadsManagerPage())),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

// MARK: - Downloads manager

class QuranDownloadsManagerPage extends StatelessWidget {
  const QuranDownloadsManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final downloads = scope.downloads;
    final voices = <QuranReciter>[
      ...QuranLibrary.reciters,
      QuranLibrary.englishReciter,
    ];
    return AnimatedBuilder(
      animation: downloads,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(S.t('downloads'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              for (final voice in voices) _voiceSection(context, scope, voice),
            ],
          ),
        );
      },
    );
  }

  Widget _voiceSection(
      BuildContext context, QuranScope scope, QuranReciter voice) {
    final downloads = scope.downloads;
    final count = downloads.downloadedCountFor(voice.id);
    final active = downloads.activeDownloadCount(voice.id);
    final bytes = downloads.bytesFor(voice.id);
    final items = <int>[
      for (var n = 1; n <= 114; n++)
        if (downloads.isDownloaded(voice.id, n) ||
            downloads.isDownloading(voice.id, n))
          n,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(voice.name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              S.f('downloadedOfFmt', {
                'count': '$count',
                'size': formatBytes(bytes),
              }),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (active > 0)
                  OutlinedButton.icon(
                    onPressed: () => downloads.cancelAll(voice.id),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(S.t('cancelAll')),
                  )
                else if (count < 114)
                  FilledButton.icon(
                    onPressed: () => downloads.downloadAll(voice.id),
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(S.t('downloadAll')),
                    style: FilledButton.styleFrom(
                        backgroundColor: QuranThemeColors.midGreen),
                  ),
                if (count > 0)
                  OutlinedButton.icon(
                    onPressed: () => downloads.deleteAll(voice.id),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(S.t('deleteAll')),
                  ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const Divider(height: 24),
              for (final n in items)
                Builder(builder: (context) {
                  final surah = QuranLibrary.surah(n);
                  if (surah == null) return const SizedBox.shrink();
                  final progress = downloads.progress(voice.id, n);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${surah.number}. ${surah.english}'),
                    subtitle: progress != null
                        ? LinearProgressIndicator(value: progress)
                        : null,
                    trailing: progress != null
                        ? IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: () => downloads.cancel(n, voice.id),
                          )
                        : IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => downloads.delete(n, voice.id),
                          ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}

// MARK: - Now Playing

class NowPlayingPage extends StatefulWidget {
  /// In the expanded Quran library the player lives in the
  /// right-hand pane: no Scaffold or AppBar of its own (the
  /// repeat-ayah menu floats over the artwork instead), and the
  /// lyrics strip swaps the pane to the lyrics view through
  /// [onOpenLyrics] instead of pushing a route.
  final bool embedded;
  final VoidCallback? onOpenLyrics;
  const NowPlayingPage({super.key, this.embedded = false, this.onOpenLyrics});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  double? _scrubValue;

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final player = scope.player;
    return AnimatedBuilder(
      animation: Listenable.merge([player, scope.bookmarks]),
      builder: (context, _) {
        final surah = player.currentSurah;
        final Widget content = surah == null
            ? Center(
                child: Text(S.t('nothingPlaying'),
                    style: const TextStyle(color: Colors.white70)),
              )
            : _body(context, scope, surah);
        if (widget.embedded) {
          return Material(
            color: QuranThemeColors.darkestGreen,
            child: Stack(
              children: [
                content,
                Positioned(
                  top: 4,
                  right: 4,
                  child: _repeatAyahButton(context, player),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: QuranThemeColors.darkestGreen,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              player.contextLabel,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            centerTitle: true,
            actions: [
              _repeatAyahButton(context, player),
            ],
          ),
          body: content,
        );
      },
    );
  }

  Widget _body(BuildContext context, QuranScope scope, QuranSurah surah) {
    final player = scope.player;
    final duration = player.duration;
    final position = _scrubValue ?? player.currentTime;
    final artwork = Center(child: SurahArtwork(surah: surah, size: 250));
    final titleRow = Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      surah.english,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      player.currentReciter?.name ?? '',
                      style: const TextStyle(
                          color: QuranThemeColors.mutedOnGreen, fontSize: 15),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  player.isFavorite(surah.number)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: player.isFavorite(surah.number)
                      ? QuranThemeColors.heartRed
                      : Colors.white,
                  size: 28,
                ),
                onPressed: () => player.toggleFavorite(surah.number),
              ),
            ],
          );
    // Scrubber (v3.0.3): the stock slider's thumb was a small
    // white dot that vanished against the white filled track.
    // The knob design (Youssef's spec, parity with iOS 3.0.3): a
    // large round gold thumb on a thicker track — gold is the
    // player theme's accent, so the knob reads against both the
    // filled (white) and unfilled (white24) parts of the track.
    // Dragging previews through _scrubValue; the seek itself
    // still lands on release via player.seek, as before.
    final slider = SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              trackShape: const RoundedRectSliderTrackShape(),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: QuranThemeColors.lightGold,
              overlayColor:
                  QuranThemeColors.lightGold.withValues(alpha: 0.18),
              thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 15, elevation: 3, pressedElevation: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
            ),
            child: Slider(
              value: duration > 0 ? position.clamp(0.0, duration) : 0,
              min: 0,
              max: duration > 0 ? duration : 1,
              onChanged: (v) => setState(() => _scrubValue = v),
              onChangeEnd: (v) {
                player.seek(v);
                setState(() => _scrubValue = null);
              },
            ),
          );
    final timesRow = Row(
            children: [
              Text(QuranLibrary.formatDuration(position),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                  '-${QuranLibrary.formatDuration(duration > position ? duration - position : 0)}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          );
    final transportRow = Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle,
                    color: player.shuffle
                        ? QuranThemeColors.lightGold
                        : Colors.white),
                onPressed: player.toggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous,
                    color: Colors.white, size: 36),
                onPressed: player.previous,
              ),
              IconButton(
                icon: Icon(
                    player.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 64),
                onPressed: player.togglePlayPause,
              ),
              IconButton(
                icon:
                    const Icon(Icons.skip_next, color: Colors.white, size: 36),
                onPressed: player.next,
              ),
              IconButton(
                icon: Icon(
                  player.repeatMode == QuranRepeatMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                  color: player.repeatMode != QuranRepeatMode.off
                      ? QuranThemeColors.lightGold
                      : Colors.white,
                ),
                onPressed: player.cycleRepeatMode,
              ),
            ],
          );
    final lyricsStrip = _lyricsStrip(context, scope, surah);
    final extrasRow = Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _extraButton(
                context,
                icon: Icons.bedtime_outlined,
                label: S.t('sleepTimer'),
                value: player.sleepOption.isOff
                    ? null
                    : player.sleepOption.endOfSurah
                        ? S.t('sleepEndOfSurah')
                        : S.f('sleepMinutesFmt',
                            {'minutes': '${player.sleepOption.minutes}'}),
                active: !player.sleepOption.isOff,
                onTap: () => _showSleepMenu(context, player),
              ),
              _extraButton(
                context,
                icon: Icons.queue_music,
                label: S.t('queueTitle'),
                value: player.upNextSurah == null
                    ? null
                    : '${S.t('upNext')}: ${player.upNextSurah!.english}',
                active: false,
                onTap: () => _showQueue(context, scope),
              ),
            ],
          );
    final hinge = widget.embedded ? null : tabletopHinge(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surahColor(surah.number, 0.50, 0.30),
            QuranThemeColors.darkestGreen,
          ],
        ),
      ),
      child: hinge == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                artwork,
                const SizedBox(height: 24),
                titleRow,
                const SizedBox(height: 8),
                slider,
                timesRow,
                const SizedBox(height: 8),
                transportRow,
                const SizedBox(height: 12),
                lyricsStrip,
                const SizedBox(height: 16),
                extrasRow,
              ],
            )
          : _tabletopLayout(
              context,
              hinge,
              artwork: artwork,
              titleRow: titleRow,
              lyricsStrip: lyricsStrip,
              slider: slider,
              timesRow: timesRow,
              transportRow: transportRow,
              extrasRow: extrasRow,
            ),
    );
  }

  /// Tabletop posture on a foldable: the screen splits at the
  /// fold — artwork, title and the lyrics strip in the region
  /// above it, the scrubber and the transport controls in the
  /// region below. Each region centers its content and scrolls
  /// internally if it runs short, so small folds degrade
  /// gracefully instead of overflowing.
  Widget _tabletopLayout(
    BuildContext context,
    ui.DisplayFeature hinge, {
    required Widget artwork,
    required Widget titleRow,
    required Widget lyricsStrip,
    required Widget slider,
    required Widget timesRow,
    required Widget transportRow,
    required Widget extrasRow,
  }) {
    final size = MediaQuery.sizeOf(context);
    final bodyTop = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bodyHeight = size.height - bodyTop;
    final fraction = bodyHeight > 0
        ? ((hinge.bounds.top - bodyTop) / bodyHeight).clamp(0.25, 0.75)
        : 0.5;
    final topFlex = (fraction * 1000).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Expanded(
            flex: topFlex,
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    artwork,
                    const SizedBox(height: 16),
                    titleRow,
                    const SizedBox(height: 10),
                    lyricsStrip,
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1000 - topFlex,
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    slider,
                    timesRow,
                    const SizedBox(height: 8),
                    transportRow,
                    const SizedBox(height: 12),
                    extrasRow,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lyricsStrip(
      BuildContext context, QuranScope scope, QuranSurah surah) {
    final player = scope.player;
    final ayahs = QuranTextData.ayahsBySurah[surah.number];
    String arabic = surah.arabic;
    String english = surah.meaning;
    if (ayahs != null && ayahs.isNotEmpty) {
      final index =
          quranCurrentAyahIndex(ayahs, player.currentTime, player.duration);
      arabic = ayahs[index].ar;
      english = ayahs[index].en;
    }
    return Material(
      color: surahColor(surah.number, 0.72, 0.52),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (widget.onOpenLyrics != null) {
            widget.onOpenLyrics!();
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const QuranLyricsPage()),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('lyrics'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                arabic,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                english,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _extraButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String? value,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            Icon(icon,
                color: active ? QuranThemeColors.lightGold : Colors.white,
                size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: active
                        ? QuranThemeColors.lightGold
                        : Colors.white70,
                    fontSize: 11)),
            if (value != null)
              Text(value,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _repeatAyahButton(BuildContext context, QuranPlayer player) {
    return IconButton(
      icon: const Icon(Icons.more_horiz, color: Colors.white),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(S.t('repeatAyahMenu'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final plays in [2, 3, 5])
                  ListTile(
                    leading: const Icon(Icons.repeat),
                    title: Text(S.f('timesFmt', {'count': '$plays'})),
                    onTap: () {
                      player.repeatCurrentAyah(plays: plays);
                      Navigator.pop(context);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.all_inclusive),
                  title: Text(S.t('keepRepeating')),
                  onTap: () {
                    player.repeatCurrentAyah();
                    Navigator.pop(context);
                  },
                ),
                if (player.ayahLoopLabel != null)
                  ListTile(
                    leading: const Icon(Icons.stop_circle_outlined,
                        color: Colors.red),
                    title: Text(S.f('stopRepeatingFmt',
                        {'label': player.ayahLoopLabel!})),
                    onTap: () {
                      player.clearAyahLoop();
                      Navigator.pop(context);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.list),
                  title: Text(S.t('lyrics')),
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.onOpenLyrics != null) {
                      widget.onOpenLyrics!();
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const QuranLyricsPage()));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSleepMenu(BuildContext context, QuranPlayer player) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(S.t('sleepTimer'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: Icon(player.sleepOption.isOff
                  ? Icons.check
                  : Icons.bedtime_outlined),
              title: Text(S.t('sleepOff')),
              onTap: () {
                player.setSleepOption(const QuranSleepOption.off());
                Navigator.pop(context);
              },
            ),
            for (final minutes in QuranPlayer.sleepMinutes)
              ListTile(
                leading: Icon(player.sleepOption.minutes == minutes
                    ? Icons.check
                    : Icons.timer_outlined),
                title: Text(S.f('sleepMinutesFmt', {'minutes': '$minutes'})),
                onTap: () {
                  player.setSleepOption(QuranSleepOption.minutes(minutes));
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: Icon(player.sleepOption.endOfSurah
                  ? Icons.check
                  : Icons.music_note_outlined),
              title: Text(S.t('sleepEndOfSurah')),
              onTap: () {
                player.setSleepOption(const QuranSleepOption.end());
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQueue(BuildContext context, QuranScope scope) {
    final player = scope.player;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(S.t('queueTitle'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final number in player.queue)
                    Builder(builder: (context) {
                      final surah = QuranLibrary.surah(number);
                      if (surah == null) return const SizedBox.shrink();
                      final isCurrent =
                          number == player.currentSurah?.number;
                      return ListTile(
                        leading: SurahArtwork(
                            surah: surah, size: 38, cornerRadius: 8),
                        title: Text('${surah.number}. ${surah.english}',
                            style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        trailing: isCurrent
                            ? Icon(
                                player.isPlaying
                                    ? Icons.volume_up
                                    : Icons.pause,
                                color: QuranThemeColors.midGreen)
                            : null,
                        onTap: () {
                          player.playFromQueue(number);
                          Navigator.pop(context);
                        },
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Lyrics

class QuranLyricsPage extends StatefulWidget {
  /// In the expanded Quran library the lyrics live in the
  /// right-hand pane: no Scaffold of their own — a header row
  /// (back button, title, mode switch) replaces the AppBar and
  /// the loop bar closes the column. [onClose] returns the pane
  /// to Now Playing.
  final bool embedded;
  final VoidCallback? onClose;
  const QuranLyricsPage({super.key, this.embedded = false, this.onClose});

  @override
  State<QuranLyricsPage> createState() => _QuranLyricsPageState();
}

class _QuranLyricsPageState extends State<QuranLyricsPage> {
  /// "both" | "arabic" | "english"
  String _mode = 'both';
  bool _liveScroll = true;
  bool _loopPicking = false;
  int? _loopStart;
  int _lastScrolledIndex = -1;
  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    // The ayah text parses once (2.3 MB JSON); rebuild when ready.
    QuranTextData.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  GlobalKey _keyFor(int index) => _rowKeys.putIfAbsent(index, GlobalKey.new);

  void _maybeScroll(int index, List<QuranAyahText> ayahs) {
    if (!_liveScroll || index == _lastScrolledIndex) return;
    _lastScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final keyContext = _rowKeys[index]?.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 350),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = QuranScope.of(context);
    final player = scope.player;
    return AnimatedBuilder(
      animation: Listenable.merge([player, scope.bookmarks]),
      builder: (context, _) {
        final surah = player.currentSurah;
        final ayahs =
            surah == null ? null : QuranTextData.ayahsBySurah[surah.number];
        final currentIndex = ayahs == null
            ? 0
            : quranCurrentAyahIndex(
                ayahs, player.currentTime, player.duration);
        if (ayahs != null && ayahs.isNotEmpty) {
          _maybeScroll(currentIndex, ayahs);
        }
        final Widget content = surah == null
              ? Center(
                  child: Text(S.t('nothingPlaying'),
                      style: const TextStyle(color: Colors.white70)))
              : ayahs == null
                  ? Center(
                      child: Text(S.t('loadingText'),
                          style: const TextStyle(color: Colors.white70)))
                  : ayahs.isEmpty
                      ? Center(
                          child: Text(S.t('noTextForSurah'),
                              style: const TextStyle(color: Colors.white70)))
                      : Container(
                          margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                          decoration: BoxDecoration(
                            color:
                                surahColor(surah.number, 0.72, 0.52),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                if (n is UserScrollNotification &&
                                    _liveScroll) {
                                  setState(() => _liveScroll = false);
                                }
                                return false;
                              },
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                itemCount: ayahs.length,
                                itemBuilder: (context, index) {
                                  final ayah = ayahs[index];
                                  final state = index == currentIndex
                                      ? 1
                                      : (index < currentIndex ? 0 : 2);
                                  return _ayahRow(
                                      context, scope, ayah, index, state);
                                },
                              ),
                            ),
                          ),
                        );
        // Reading column (v3.0.0, large screens): the lyrics
        // card never grows past a comfortable reading width and
        // stays centered. Below 748dp the constraint never
        // binds, so phones render exactly as before.
        final Widget framedContent = LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth > 748
                ? 720.0
                : constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: cardWidth,
                height: constraints.maxHeight,
                child: content,
              ),
            );
          },
        );
        final fab = !_liveScroll && ayahs != null
            ? FloatingActionButton.extended(
                onPressed: () {
                  setState(() {
                    _liveScroll = true;
                    _lastScrolledIndex = -1;
                  });
                },
                icon: const Icon(Icons.arrow_downward),
                label: Text(S.t('liveScroll')),
              )
            : null;
        if (widget.embedded) {
          return Container(
            color: QuranThemeColors.darkestGreen,
            child: Column(
              children: [
                _embeddedHeader(context, surah),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: framedContent),
                      if (fab != null)
                        Positioned(right: 16, bottom: 16, child: fab),
                    ],
                  ),
                ),
                _loopBar(context, scope),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: QuranThemeColors.darkestGreen,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(surah == null
                ? S.t('lyrics')
                : S.f('surahFmt', {'name': surah.english})),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _modeSegmented(),
              ),
            ],
          ),
          bottomNavigationBar: _loopBar(context, scope),
          body: framedContent,
          floatingActionButton: fab,
        );
      },
    );
  }

  /// The Both / Arabic / English switch — in the AppBar on the
  /// standalone page, in the header row when embedded in a pane.
  Widget _modeSegmented() {
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(value: 'both', label: Text(S.t('lyricsModeBoth'))),
        const ButtonSegment(value: 'arabic', label: Text('عربي')),
        const ButtonSegment(value: 'english', label: Text('EN')),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// The embedded pane's stand-in for the AppBar: back to Now
  /// Playing, the surah title, and the mode switch.
  Widget _embeddedHeader(BuildContext context, QuranSurah? surah) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 2),
      child: Row(
        children: [
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: widget.onClose,
            ),
          Expanded(
            child: Text(
              surah == null
                  ? S.t('lyrics')
                  : S.f('surahFmt', {'name': surah.english}),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _modeSegmented(),
        ],
      ),
    );
  }

  Widget _ayahRow(BuildContext context, QuranScope scope, QuranAyahText ayah,
      int index, int state) {
    final player = scope.player;
    final surah = player.currentSurah;
    final bookmarked = surah != null &&
        scope.bookmarks.isBookmarked(surah.number, ayah.n);
    final arabicColor = switch (state) {
      1 => Colors.white,
      0 => Colors.white.withValues(alpha: 0.55),
      _ => Colors.black.withValues(alpha: 0.85),
    };
    final englishColor = switch (state) {
      1 => Colors.white,
      0 => Colors.white.withValues(alpha: 0.42),
      _ => Colors.black.withValues(alpha: 0.62),
    };
    return Container(
      key: _keyFor(index),
      decoration: BoxDecoration(
        color: _loopPicking && _loopStart == index
            ? QuranThemeColors.gold.withValues(alpha: 0.18)
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: () => _handleTap(scope, index),
        onLongPress: () => _showAyahMenu(context, scope, ayah, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_mode != 'english')
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    ayah.ar,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: arabicColor,
                    ),
                  ),
                ),
              if (_mode != 'arabic') ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        ayah.en,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: englishColor,
                        ),
                      ),
                    ),
                    if (bookmarked)
                      const Padding(
                        padding: EdgeInsets.only(left: 6, top: 2),
                        child: Icon(Icons.bookmark,
                            size: 14, color: QuranThemeColors.gold),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(QuranScope scope, int index) {
    final player = scope.player;
    final surah = player.currentSurah;
    if (surah == null) return;
    final ayahs = QuranTextData.ayahsBySurah[surah.number];
    if (ayahs == null) return;
    if (_loopPicking) {
      if (_loopStart == null) {
        setState(() => _loopStart = index);
      } else {
        final start = _loopStart! < index ? _loopStart! : index;
        final end = _loopStart! < index ? index : _loopStart!;
        player.loopAyahs(start, end);
        setState(() {
          _loopPicking = false;
          _loopStart = null;
        });
      }
      return;
    }
    player.seek(quranAyahStartTime(ayahs, index, player.duration));
  }

  void _showAyahMenu(BuildContext context, QuranScope scope,
      QuranAyahText ayah, int index) {
    final player = scope.player;
    final surah = player.currentSurah;
    if (surah == null) return;
    final bookmarked = scope.bookmarks.isBookmarked(surah.number, ayah.n);
    final ayahs = QuranTextData.ayahsBySurah[surah.number];
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(bookmarked ? Icons.bookmark_remove : Icons.bookmark),
              title: Text(bookmarked
                  ? S.t('removeBookmark')
                  : S.t('bookmarkAyah')),
              onTap: () {
                scope.bookmarks.toggle(surah.number, ayah.n);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(S.t('repeatThisAyah'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final plays in [2, 3, 5])
              ListTile(
                leading: const Icon(Icons.repeat),
                title: Text(S.f('timesFmt', {'count': '$plays'})),
                onTap: () {
                  player.repeatAyah(index, plays: plays);
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: Text(S.t('keepRepeating')),
              onTap: () {
                player.repeatAyah(index);
                Navigator.pop(context);
              },
            ),
            if (ayahs != null)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(S.t('playFromHere')),
                onTap: () {
                  player.seek(
                      quranAyahStartTime(ayahs, index, player.duration));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _loopBar(BuildContext context, QuranScope scope) {
    final player = scope.player;
    return SafeArea(
      top: false,
      child: Container(
        color: QuranThemeColors.darkestGreen,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _loopPicking
            ? Row(
                children: [
                  const Icon(Icons.repeat,
                      color: QuranThemeColors.lightGold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _loopStart == null
                          ? S.t('tapFirstAyah')
                          : S.t('tapLastAyah'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _loopPicking = false;
                      _loopStart = null;
                    }),
                    child: Text(S.t('cancel')),
                  ),
                ],
              )
            : player.ayahLoopLabel != null
                ? Row(
                    children: [
                      const Icon(Icons.repeat,
                          color: QuranThemeColors.lightGold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          S.f('loopingFmt', {'label': player.ayahLoopLabel!}),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: player.clearAyahLoop,
                        child: Text(S.t('stopLoop')),
                      ),
                    ],
                  )
                : Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _loopPicking = true),
                      icon: const Icon(Icons.repeat,
                          color: QuranThemeColors.lightGold),
                      label: Text(S.t('loopAyahs'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
      ),
    );
  }
}

// Referenced by the library (language state read for potential RTL
// tweaks); kept to avoid an unused import warning elsewhere.
bool get quranUsesRtl => LanguageState.current.name == 'ar';
