// Background audio (v3.0.0) — the Android counterpart of the iOS
// player's Now Playing / remote-command integration
// (MPNowPlayingInfoCenter + MPRemoteCommandCenter). An
// audio_service handler running the media-playback foreground
// service, so Quran playback keeps going with the screen off or
// the app in the background, and the lock screen / notification
// media controls (previous surah, play/pause, next surah, seek)
// drive the same QuranPlayer the UI drives.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'quran_player.dart';

class QuranAudioHandler extends BaseAudioHandler {
  QuranPlayer? _player;
  String? _publishedItemId;
  int? _publishedItemDurationMs;

  /// Connects the handler to the app's player. The player is a
  /// ChangeNotifier that already ticks every 500 ms while a
  /// session exists, which is the cadence the media session's
  /// position is refreshed at.
  void attach(QuranPlayer player) {
    _player = player;
    // The mini player's swipe-down dismiss (v3.0.2) stops playback
    // through this handler's stop(), like the system media controls.
    player.serviceStop = stop;
    player.addListener(_sync);
    _sync();
  }

  @override
  Future<void> play() async => _player?.resume();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> stop() async {
    _player?.pause();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async =>
      _player?.seek(position.inMilliseconds / 1000.0);

  @override
  Future<void> skipToNext() async => _player?.next();

  @override
  Future<void> skipToPrevious() async => _player?.previous();

  AudioProcessingState _mapState(QuranPlayer player) {
    if (!player.isLoaded) return AudioProcessingState.idle;
    return switch (player.engineState) {
      ProcessingState.idle => AudioProcessingState.ready,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  /// Mirrors the player's state into the media session: the
  /// current surah as the media item (republished only when the
  /// item or its known duration actually changes) and a playback
  /// state carrying the iOS Now Playing control set.
  void _sync() {
    final player = _player;
    if (player == null) return;
    final item = player.nowPlayingMediaItem;
    if (item == null) {
      if (_publishedItemId != null) {
        _publishedItemId = null;
        _publishedItemDurationMs = null;
        mediaItem.add(null);
      }
    } else {
      final durationMs = item.duration?.inMilliseconds;
      if (item.id != _publishedItemId ||
          durationMs != _publishedItemDurationMs) {
        _publishedItemId = item.id;
        _publishedItemDurationMs = durationMs;
        mediaItem.add(item);
      }
    }
    final position =
        Duration(milliseconds: (player.currentTime * 1000).round());
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (player.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapState(player),
      playing: player.isPlaying,
      updatePosition: position,
      bufferedPosition: position,
      speed: 1.0,
    ));
  }
}
