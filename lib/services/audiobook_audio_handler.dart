import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_player_service.dart';

/// 薄 AudioHandler：通知栏 / 锁屏 / 线控。
///
/// - 上一集 / 下一集 → 业务 [AudioPlayerService.previous] / [next]
/// - 快退 / 快进 → [SeekHandler]（间隔见 [AudioServiceConfig]）
///
/// 不依赖 just_audio 播放列表是否有上下曲（lazy 单章也能显示 prev/next）。
class AudiobookAudioHandler extends BaseAudioHandler with SeekHandler {
  AudiobookAudioHandler(this._service) {
    _service.publishNowPlaying = setNowPlaying;
    _player.playbackEventStream.listen(_broadcastState);
    _player.playingStream.listen((_) => _broadcastState(_player.playbackEvent));
    _player.processingStateStream
        .listen((_) => _broadcastState(_player.playbackEvent));
    _player.durationStream.listen((d) {
      final item = mediaItem.valueOrNull;
      if (item == null || d == null || item.duration == d) return;
      mediaItem.add(item.copyWith(duration: d));
    });
    _broadcastState(_player.playbackEvent);
  }

  final AudioPlayerService _service;

  AudioPlayer get _player => _service.player;

  /// 由 [AudioPlayerService] 在起播 / 切章时推送封面与标题。
  void setNowPlaying(MediaItem item) {
    mediaItem.add(item);
    _broadcastState(_player.playbackEvent);
  }

  void clearNowPlaying() {
    mediaItem.add(null);
    _broadcastState(_player.playbackEvent);
  }

  /// 章节边界变化时刷新按钮可用性（prev/next 显隐）。
  void refreshControls() => _broadcastState(_player.playbackEvent);

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> stop() async {
    await _service.pause();
    try {
      await _player.stop();
    } catch (_) {}
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _service.next();

  @override
  Future<void> skipToPrevious() => _service.previous();

  @override
  Future<void> fastForward() =>
      _seekBy(AudioService.config.fastForwardInterval);

  @override
  Future<void> rewind() =>
      _seekBy(-AudioService.config.rewindInterval);

  Future<void> _seekBy(Duration offset) async {
    var pos = _player.position + offset;
    if (pos < Duration.zero) pos = Duration.zero;
    final dur = _player.duration;
    if (dur != null && pos > dur) pos = dur;
    await _service.seek(pos);
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    // 上一集 | -30s | 播停 | +30s | 下一集；边界处切集由 service 空操作。
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // 折叠通知：-30s | 播停 | +30s
      androidCompactActionIndices: const [1, 2, 3],
      processingState: _mapProcessing(_player.processingState),
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _service.chapterIndex,
    ));
  }

  static AudioProcessingState _mapProcessing(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
