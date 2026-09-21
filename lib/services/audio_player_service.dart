import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../models/skip_config.dart';

/// 睡眠定时模式
enum SleepTimerMode { off, countdown, afterChapter, afterNChapters }

/// 睡眠定时状态
class SleepTimerState {
  final SleepTimerMode mode;

  /// countdown：总分钟数
  final int minutes;

  /// afterNChapters：剩余集数
  final int chaptersRemaining;

  /// countdown：到期时间
  final DateTime? endAt;

  const SleepTimerState({
    this.mode = SleepTimerMode.off,
    this.minutes = 0,
    this.chaptersRemaining = 0,
    this.endAt,
  });

  static const off = SleepTimerState();

  String get label {
    switch (mode) {
      case SleepTimerMode.off:
        return '未开启';
      case SleepTimerMode.countdown:
        return '倒计时 $minutes 分钟';
      case SleepTimerMode.afterChapter:
        return '播完本集停止';
      case SleepTimerMode.afterNChapters:
        return '播完 $chaptersRemaining 集停止';
    }
  }

  /// 倒计时剩余描述
  String remainingLabel() {
    if (mode != SleepTimerMode.countdown || endAt == null) return label;
    final diff = endAt!.difference(DateTime.now());
    if (diff.isNegative) return '即将停止';
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return '剩 $m:${s.toString().padLeft(2, '0')}';
  }
}

/// 播放服务：封装 just_audio 播放器。
/// - 后台播放 / 通知栏 / 锁屏控制：just_audio_background（MediaItem 标签自动生成）
/// - 倍速 0.5~4.0x
/// - 睡眠定时：倒计时 / 播完本集 / 播完 N 集
/// - 片头自动 seek、片尾接近时自动切下一集
class AudioPlayerService {
  final AudioPlayer player = AudioPlayer();

  Book? _book;
  List<Chapter> _chapters = [];
  List<String> _audioUrls = [];
  SkipConfig _skip = const SkipConfig();
  SleepTimerState _sleep = SleepTimerState.off;
  Timer? _countdownTimer;
  Timer? _remainingTicker;
  int _sleepChaptersRemaining = 0;
  int _lastIndex = -1;
  bool _chapterEndedNaturally = false;
  bool _skippingOutro = false;
  DateTime _lastProgressSave = DateTime.now();
  StreamSubscription<PlaybackEvent>? _playbackEventSub;

  /// lazy 模式：切章前解析 URL
  Future<String> Function(int index)? _lazyResolve;
  bool get isLazyMode => _lazyResolve != null;

  /// UI / 持久化回调（由 PlayerController 注入）
  void Function(String chapterId, String bookId, double position, double duration)?
      onProgressSave;
  void Function(String chapterId, int index)? onChapterChanged;
  void Function()? onSleepTimerEnd;
  void Function(Object error)? onPlaybackError;

  final ValueNotifier<SleepTimerState> sleepTimerState =
      ValueNotifier<SleepTimerState>(SleepTimerState.off);

  Book? get currentBook => _book;
  List<Chapter> get chapters => List.unmodifiable(_chapters);
  Chapter? get currentChapter {
    if (_chapters.isEmpty) return null;
    // lazy：播放器只有单曲，必须以业务章节下标为准
    if (_lazyResolve != null) {
      if (_lastIndex < 0 || _lastIndex >= _chapters.length) return null;
      return _chapters[_lastIndex];
    }
    final idx = player.currentIndex;
    if (idx == null || idx < 0 || idx >= _chapters.length) return null;
    return _chapters[idx];
  }

  int get chapterIndex {
    if (_lazyResolve != null) return _lastIndex < 0 ? 0 : _lastIndex;
    return player.currentIndex ?? (_lastIndex < 0 ? 0 : _lastIndex);
  }

  bool get hasNext => chapterIndex + 1 < _chapters.length;

  bool get hasPrevious => chapterIndex > 0;

  AudioPlayerService() {
    _init();
  }

  Future<void> _init() async {
    // 音频会话：处理来电 / 其他应用抢占音频焦点
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.duck) {
          player.setVolume(0.3);
        } else {
          player.pause();
        }
      } else {
        if (event.type == AudioInterruptionType.duck) {
          player.setVolume(1.0);
        }
      }
    });

    // 整个播放列表结束
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (_lazyResolve != null) {
          _handleLazyChapterCompleted();
        } else {
          _handlePlaylistCompleted();
        }
      }
    });

    // 章节切换（含自动连播与手动切换）
    // lazy 模式由 _playLazyIndex 自行维护章节语义，忽略单曲源的 index=0 事件
    player.currentIndexStream.listen((idx) {
      if (_lazyResolve != null) return;
      if (idx == null || idx == _lastIndex) return;
      final wasNaturalAdvance = _chapterEndedNaturally || _lastIndex == -1;
      _chapterEndedNaturally = false;
      _lastIndex = idx;
      _onChapterStart(idx, naturalAdvance: wasNaturalAdvance);
    });

    // 位置流：片尾检测 + 进度保存
    player.positionStream.listen(_onPosition);

    // 播放失败（直链过期 / 网络中断等）→ 交给上层重解析重试
    _playbackEventSub = player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        onPlaybackError?.call(e);
      },
    );
  }

  /// 播放一本书的章节列表
  ///
  /// [audioUrls] 与 [chapters] 等长，为解析后（离线优先）的播放地址。
  /// [lazyResolve] 非空时进入 lazy 模式：只加载 [startIndex] 一章，切章时再解析。
  Future<void> playBook(
    Book book,
    List<Chapter> chapters,
    List<String> audioUrls,
    int startIndex, {
    Duration? startAt,
    required SkipConfig skip,
    double speed = 1.0,
    Future<String> Function(int index)? lazyResolve,
  }) async {
    assert(lazyResolve != null || chapters.length == audioUrls.length);
    _book = book;
    _chapters = List.of(chapters);
    _audioUrls = List.of(audioUrls);
    _skip = skip;
    _lastIndex = -1;
    _lazyResolve = lazyResolve;

    final index = startIndex.clamp(0, chapters.length - 1);

    if (lazyResolve != null) {
      final url = audioUrls.isNotEmpty &&
              index < audioUrls.length &&
              audioUrls[index].isNotEmpty &&
              !audioUrls[index].startsWith('lazy://')
          ? audioUrls[index]
          : await lazyResolve(index);
      if (index < _audioUrls.length) {
        _audioUrls[index] = url;
      }
      await _setSingleChapterSource(index, url);
      _lastIndex = index;
    } else {
      final sources = <AudioSource>[];
      for (var i = 0; i < chapters.length; i++) {
        sources.add(_sourceFor(chapters[i], audioUrls[i], book));
      }
      await player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: index,
        preload: true,
      );
      _lastIndex = index;
    }

    await player.setSpeed(speed.clamp(0.5, 4.0));

    // 起播位置：断点续播位置与片头跳过取较大值
    final intro = Duration(seconds: skip.intro);
    final seekTo = startAt != null && startAt > intro ? startAt : intro;
    if (seekTo > Duration.zero) {
      await player.seek(seekTo);
    }
    await player.play();
  }

  AudioSource _sourceFor(Chapter ch, String audioUrl, Book book) {
    final uri = audioUrl.startsWith('/') ||
            (audioUrl.length > 2 && audioUrl[1] == ':')
        ? Uri.file(audioUrl)
        : Uri.parse(audioUrl);
    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: ch.id,
        title: ch.title,
        album: book.title,
        artist: book.author,
        artUri: book.coverUrl != null && book.coverUrl!.startsWith('http')
            ? Uri.tryParse(book.coverUrl!)
            : null,
      ),
    );
  }

  Future<void> _setSingleChapterSource(int index, String audioUrl) async {
    final book = _book;
    if (book == null || index < 0 || index >= _chapters.length) return;
    final ch = _chapters[index];
    await player.setAudioSource(
      _sourceFor(ch, audioUrl, book),
      preload: true,
    );
  }

  /// 倍速（0.5 ~ 4.0）
  Future<void> setSpeed(double speed) async {
    await player.setSpeed(speed.clamp(0.5, 4.0));
  }

  Future<void> play() => player.play();

  Future<void> pause() async {
    await _flushProgress();
    await player.pause();
  }

  Future<void> seek(Duration position) => player.seek(position);

  /// 上一集 / 下一集
  Future<void> next() async {
    if (_lazyResolve != null) {
      final next = chapterIndex + 1;
      if (next >= _chapters.length) return;
      await _playLazyIndex(next, naturalAdvance: false);
      return;
    }
    if (hasNext) await player.seekToNext();
  }

  Future<void> previous() async {
    if (_lazyResolve != null) {
      final prev = chapterIndex - 1;
      if (prev < 0) return;
      await _playLazyIndex(prev, naturalAdvance: false);
      return;
    }
    if (player.hasPrevious) await player.seekToPrevious();
  }

  /// 跳转到指定章节
  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    if (_lazyResolve != null) {
      await _playLazyIndex(index, naturalAdvance: false);
      return;
    }
    await player.seek(Duration.zero, index: index);
  }

  Future<void> _playLazyIndex(int index, {required bool naturalAdvance}) async {
    final resolve = _lazyResolve;
    if (resolve == null) return;
    final url = await resolve(index);
    while (_audioUrls.length <= index) {
      _audioUrls.add('');
    }
    _audioUrls[index] = url;
    await _setSingleChapterSource(index, url);
    if (_skip.intro > 0) {
      await player.seek(Duration(seconds: _skip.intro));
    }
    _lastIndex = index;
    onChapterChanged?.call(_chapters[index].id, index);
    if (naturalAdvance) {
      _onChapterStart(index, naturalAdvance: true);
    }
    await player.play();
  }

  /// 用新 URL 重载当前章并尽量恢复进度（播放失败重试用）
  Future<void> reloadChapterUrl(
    int index,
    String url, {
    Duration? resumeAt,
  }) async {
    final book = _book;
    if (book == null || index < 0 || index >= _chapters.length) return;
    while (_audioUrls.length < _chapters.length) {
      _audioUrls.add('');
    }
    _audioUrls[index] = url;

    if (_lazyResolve != null) {
      await _setSingleChapterSource(index, url);
      if (resumeAt != null && resumeAt > Duration.zero) {
        await player.seek(resumeAt);
      } else if (_skip.intro > 0) {
        await player.seek(Duration(seconds: _skip.intro));
      }
      _lastIndex = index;
      await player.play();
      return;
    }

    final sources = <AudioSource>[];
    for (var i = 0; i < _chapters.length; i++) {
      final u =
          _audioUrls[i].isNotEmpty ? _audioUrls[i] : _chapters[i].audioUrl;
      sources.add(_sourceFor(_chapters[i], u, book));
    }
    await player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: index,
      initialPosition: resumeAt ?? Duration.zero,
      preload: true,
    );
    _lastIndex = index;
    await player.play();
  }

  Future<void> _handleLazyChapterCompleted() async {
    _chapterEndedNaturally = true;
    final cur = _lastIndex >= 0 ? _lastIndex : 0;
    if (cur + 1 >= _chapters.length) {
      _handlePlaylistCompleted();
      return;
    }
    // 睡眠：播完本集
    if (_sleep.mode == SleepTimerMode.afterChapter) {
      _stopForSleep();
      return;
    }
    await _playLazyIndex(cur + 1, naturalAdvance: true);
  }

  /// 设置睡眠定时
  void setSleepTimer(SleepTimerState state) {
    _countdownTimer?.cancel();
    _remainingTicker?.cancel();

    if (state.mode == SleepTimerMode.countdown) {
      final minutes = state.minutes.clamp(1, 24 * 60);
      final endAt =
          state.endAt ?? DateTime.now().add(Duration(minutes: minutes));
      final resolved = SleepTimerState(
        mode: SleepTimerMode.countdown,
        minutes: minutes,
        endAt: endAt,
      );
      _sleep = resolved;
      sleepTimerState.value = resolved;
      final wait = endAt.difference(DateTime.now());
      if (wait.isNegative || wait == Duration.zero) {
        _stopForSleep();
        return;
      }
      _countdownTimer = Timer(wait, _stopForSleep);
      // 每秒换新实例，驱动 UI 刷新剩余时间
      _remainingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        sleepTimerState.value = SleepTimerState(
          mode: SleepTimerMode.countdown,
          minutes: minutes,
          endAt: endAt,
        );
      });
      return;
    }

    if (state.mode == SleepTimerMode.afterNChapters) {
      final n = state.chaptersRemaining.clamp(1, 999);
      final resolved = SleepTimerState(
        mode: SleepTimerMode.afterNChapters,
        chaptersRemaining: n,
      );
      _sleep = resolved;
      _sleepChaptersRemaining = n;
      sleepTimerState.value = resolved;
      return;
    }

    _sleep = state;
    _sleepChaptersRemaining = state.chaptersRemaining;
    sleepTimerState.value = state;
  }

  SleepTimerState get sleepTimer => _sleep;

  /// 更新当前书籍的片头片尾配置（立即生效）
  void updateSkipConfig(SkipConfig skip) {
    _skip = skip;
  }

  void _stopForSleep() {
    player.pause();
    _countdownTimer?.cancel();
    _remainingTicker?.cancel();
    _sleep = SleepTimerState.off;
    sleepTimerState.value = SleepTimerState.off;
    onSleepTimerEnd?.call();
  }

  void _onChapterStart(int index, {required bool naturalAdvance}) {
    if (index >= _chapters.length) return;
    final ch = _chapters[index];
    onChapterChanged?.call(ch.id, index);

    // 睡眠定时：播完本集 / 播完 N 集（自然连播触发，手动切集不触发）
    // 「播完本集」：停在本章结束，不进入下一集开播（由 completed / lazy 完成路径处理）
    if (naturalAdvance && _sleep.mode != SleepTimerMode.off) {
      switch (_sleep.mode) {
        case SleepTimerMode.afterChapter:
          // 列表模式会先切到下一集再触发本回调：立刻暂停，避免听完本集却开播下一集
          _stopForSleep();
          return;
        case SleepTimerMode.afterNChapters:
          _sleepChaptersRemaining--;
          _sleep = SleepTimerState(
            mode: SleepTimerMode.afterNChapters,
            chaptersRemaining: _sleepChaptersRemaining,
          );
          sleepTimerState.value = _sleep;
          if (_sleepChaptersRemaining <= 0) {
            _stopForSleep();
            return;
          }
          break;
        case SleepTimerMode.countdown:
        case SleepTimerMode.off:
          break;
      }
    }

    // 片头跳过：新章节起播位置低于片头秒数时自动 seek
    if (_skip.intro > 0) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (player.currentIndex == index &&
            player.position.inSeconds < _skip.intro) {
          player.seek(Duration(seconds: _skip.intro));
        }
      });
    }
  }

  void _onPosition(Duration position) {
    // 标记当前章节已自然播放到结尾附近（用于睡眠定时「播完本集」判定）
    final duration = player.duration;
    if (duration != null && duration > Duration.zero) {
      if (position >= duration - const Duration(seconds: 2)) {
        _chapterEndedNaturally = true;
      }
    }

    // 片尾跳过：接近片尾时自动切下一集（lazy 与普通列表统一走 next 语义）
    if (_skip.outro > 0 && duration != null && duration > Duration.zero) {
      final outroStart = duration - Duration(seconds: _skip.outro);
      if (outroStart > const Duration(seconds: 1) &&
          position >= outroStart &&
          hasNext &&
          !_skippingOutro) {
        _skippingOutro = true;
        _chapterEndedNaturally = true;
        unawaited(_advancePastOutro());
        return;
      }
    }

    // 进度保存节流（每 5 秒）
    final now = DateTime.now();
    if (now.difference(_lastProgressSave) >= const Duration(seconds: 5)) {
      _lastProgressSave = now;
      final ch = currentChapter;
      if (ch != null && _book != null) {
        onProgressSave?.call(
          ch.id,
          _book!.id,
          position.inMilliseconds / 1000,
          (duration?.inMilliseconds ?? 0) / 1000,
        );
      }
    }
  }

  Future<void> _advancePastOutro() async {
    try {
      if (_lazyResolve != null) {
        final next = chapterIndex + 1;
        if (next >= _chapters.length) return;
        await _playLazyIndex(next, naturalAdvance: true);
      } else {
        await player.seekToNext();
      }
    } finally {
      _skippingOutro = false;
    }
  }

  Future<void> _flushProgress() async {
    final ch = currentChapter;
    final book = _book;
    if (ch == null || book == null) return;
    final duration = player.duration;
    onProgressSave?.call(
      ch.id,
      book.id,
      player.position.inMilliseconds / 1000,
      (duration?.inMilliseconds ?? 0) / 1000,
    );
    _lastProgressSave = DateTime.now();
  }

  void _handlePlaylistCompleted() {
    final ch = currentChapter;
    if (ch != null && _book != null) {
      final duration = player.duration;
      onProgressSave?.call(
        ch.id,
        _book!.id,
        (duration?.inMilliseconds ?? 0) / 1000,
        (duration?.inMilliseconds ?? 0) / 1000,
      );
    }
    if (_sleep.mode != SleepTimerMode.off) {
      _stopForSleep();
    }
  }

  /// 释放资源（应用退出时）
  Future<void> dispose() async {
    _countdownTimer?.cancel();
    _remainingTicker?.cancel();
    await _playbackEventSub?.cancel();
    await player.dispose();
  }
}
