import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import '../models/download_task.dart';
import '../models/play_progress.dart';
import '../models/skip_config.dart';
import '../repositories/book_repository.dart';
import '../repositories/download_repository.dart';
import '../repositories/progress_repository.dart';
import '../repositories/source_repository.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/settings_service.dart';
import '../services/source_engine.dart';
import '../utils/constants.dart';
import 'app_providers.dart';
import 'download_providers.dart';

/// 播放控制器：连接 UI 与 AudioPlayerService，
/// 负责章节加载（缓存优先）、离线优先播放地址解析、断点续播、进度持久化。
class PlayerController extends ChangeNotifier {
  final AudioPlayerService service;
  final BookRepository bookRepo;
  final ProgressRepository progressRepo;
  final DownloadRepository downloadRepo;
  final SourceRepository sourceRepo;
  final SourceEngine engine;
  final AppSettingsService settings;
  final DownloadService downloads;

  Book? currentBook;
  List<Chapter> chapters = [];
  int currentIndex = 0;
  bool loading = false;
  String? loadError;
  String? playbackError;

  // UI 镜像状态
  bool isPlaying = false;
  bool isBuffering = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double speed = 1.0;
  SkipConfig skipConfig = const SkipConfig();

  bool _retryingPlayback = false;
  int _playbackRetryCount = 0;
  static const _maxPlaybackRetries = 1;

  PlayerController({
    required this.service,
    required this.bookRepo,
    required this.progressRepo,
    required this.downloadRepo,
    required this.sourceRepo,
    required this.engine,
    required this.settings,
    required this.downloads,
  }) {
    speed = settings.defaultPlaybackRate;
    service.onProgressSave = _saveProgress;
    service.onChapterChanged = _onChapterChanged;
    service.onPlaybackError = _onPlaybackError;
    service.player.playerStateStream.listen((s) {
      isPlaying = s.playing;
      isBuffering = s.processingState == ProcessingState.buffering ||
          s.processingState == ProcessingState.loading;
      if (s.playing) {
        WakelockPlus.enable();
        playbackError = null;
        _playbackRetryCount = 0;
      } else {
        WakelockPlus.disable();
      }
      notifyListeners();
    });
    service.player.currentIndexStream.listen((i) {
      // lazy 单曲源 index 恒为 0，章节由 onChapterChanged 维护
      if (service.isLazyMode) return;
      if (i != null && i != currentIndex) {
        currentIndex = i;
        _playbackRetryCount = 0;
        notifyListeners();
      }
    });
    service.player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
    service.player.durationStream.listen((d) {
      if (d != null && d != duration) {
        duration = d;
        notifyListeners();
      }
    });
    service.sleepTimerState.addListener(() => notifyListeners());
    service.player.speedStream.listen((s) {
      speed = s;
    });
  }

  AudioPlayer get player => service.player;
  SleepTimerState get sleepTimer => service.sleepTimerState.value;
  Chapter? get currentChapter =>
      currentIndex >= 0 && currentIndex < chapters.length
          ? chapters[currentIndex]
          : null;
  bool get hasSession => currentBook != null;
  bool get hasNext => currentIndex < chapters.length - 1;
  bool get hasPrevious => currentIndex > 0;

  /// 播放指定书籍
  Future<void> playBook(Book book,
      {int startIndex = 0, Duration? startAt}) async {
    final previousBook = currentBook;
    final previousChapters = List<Chapter>.from(chapters);
    final previousIndex = currentIndex;

    loading = true;
    loadError = null;
    playbackError = null;
    _playbackRetryCount = 0;
    currentBook = book;
    chapters = [];
    currentIndex = startIndex;
    notifyListeners();
    try {
      // 1. 章节列表：DB 缓存优先，无缓存则经书源抓取
      var chs = await bookRepo.getChapters(book.id);
      var fromNetwork = false;
      var source = await sourceRepo.get(book.sourceId);
      if (chs.isEmpty) {
        if (source == null) {
          throw Exception('书源不存在或已被删除，无法获取章节列表');
        }
        chs = await engine.getChapters(source, book);
        fromNetwork = true;
      }
      if (chs.isEmpty) {
        throw Exception('暂无章节，无法播放');
      }

      // 2. 解析播放地址：lazy 仅解析当前章；否则离线优先 + 可选并发二次解析
      final lazy = source != null && engine.isLazyAudioResolve(source);
      final urls = lazy
          ? await _resolveLazySeedUrls(book, chs, source,
              index: startIndex.clamp(0, chs.length - 1))
          : await _resolveAudioUrls(book, chs, source);

      // 3. 片头片尾：书籍级 > 书源级 > 全局默认
      skipConfig = SkipConfig.effective(book, source, settings);

      // 4. 章节回填缓存与书籍信息
      if (fromNetwork) {
        await bookRepo.saveChapters(book.id, chs);
        final inShelf = await bookRepo.get(book.id);
        if (inShelf != null) {
          await bookRepo.upsert(inShelf.copyWith(
            totalChapters: chs.length,
            updatedAt: DateTime.now(),
          ));
        }
      } else if (book.totalChapters == null) {
        final inShelf = await bookRepo.get(book.id);
        if (inShelf != null) {
          await bookRepo.upsert(
              inShelf.copyWith(totalChapters: chs.length, updatedAt: DateTime.now()));
        }
      }

      final index = startIndex.clamp(0, chs.length - 1);
      currentBook = book;
      chapters = chs;
      currentIndex = index;
      loading = false;
      notifyListeners();

      await service.playBook(
        book,
        chs,
        urls,
        index,
        startAt: startAt,
        skip: skipConfig,
        speed: speed,
        lazyResolve: lazy
            ? (i) => _resolveOneChapter(book, chs[i], source)
            : null,
      );
      _onChapterChanged(chs[index].id, index);
    } catch (e) {
      loading = false;
      loadError = e.toString().replaceFirst('Exception: ', '');
      // 加载失败时勿留下「有书无章节」空壳会话
      if (chapters.isEmpty) {
        if (previousBook != null && previousChapters.isNotEmpty) {
          currentBook = previousBook;
          chapters = previousChapters;
          currentIndex = previousIndex;
        } else {
          currentBook = null;
        }
      }
      notifyListeners();
    }
  }

  /// 继续收听：根据上次的章节与进度断点续播；本章已听完则自动跳下一集
  Future<void> continueBook(Book book) async {
    // 以 DB 中最新进度为准，避免详情页持有过期 Book
    final fresh = await bookRepo.get(book.id);
    final b = fresh ?? book;
    var startIndex = 0;
    Duration? startAt;
    if (b.lastPlayChapterId != null) {
      final chs = await bookRepo.getChapters(b.id);
      final idx = chs.indexWhere((c) => c.id == b.lastPlayChapterId);
      if (idx >= 0) {
        final prog = await progressRepo.get(b.lastPlayChapterId!);
        if (prog != null && !prog.isNearlyFinished) {
          startIndex = idx;
          startAt = Duration(seconds: prog.currentTime.toInt());
        } else if (prog != null && prog.isNearlyFinished && idx < chs.length - 1) {
          // 上次已基本听完本章 → 下一集从头播
          startIndex = idx + 1;
        } else {
          startIndex = idx;
          startAt = Duration.zero;
        }
      }
    }
    await playBook(b, startIndex: startIndex, startAt: startAt);
  }

  /// 跳转到指定章节（当前会话内）
  Future<void> playChapter(int index) async {
    if (index < 0 || index >= chapters.length) return;
    currentIndex = index;
    notifyListeners();
    await service.skipToIndex(index);
    await ensureAutoAhead();
  }

  /// 播放时向后补齐 N 章（仅开新任务；暂停后不再触发）
  Future<void> ensureAutoAhead() async {
    final n = settings.autoDownloadAhead;
    final book = currentBook;
    if (n <= 0 || book == null || chapters.isEmpty) return;
    if (!isPlaying && !service.player.playing) return;

    final start = currentIndex + 1;
    final end = (start + n).clamp(0, chapters.length);
    if (start >= end) return;

    final slice = chapters.sublist(start, end);
    await downloads.startMany(book, slice);
  }

  /// 恢复上次会话（按最近收听时间，不立即播放）
  Future<void> restoreLastSession() async {
    if (hasSession) return;
    try {
      final last = await bookRepo.getLastPlayed();
      if (last == null) return;
      final chs = await bookRepo.getChapters(last.id);
      if (chs.isEmpty) return;
      currentBook = last;
      chapters = chs;
      final idx = chs.indexWhere((c) => c.id == last.lastPlayChapterId);
      currentIndex = idx >= 0 ? idx : 0;
      final prog = last.lastPlayChapterId != null
          ? await progressRepo.get(last.lastPlayChapterId!)
          : null;
      position = Duration(seconds: (prog?.currentTime ?? 0).toInt());
      duration = Duration(seconds: (prog?.duration ?? 0).toInt());
      notifyListeners();
    } catch (_) {
      // 恢复失败不影响启动
    }
  }

  /// 清空当前播放会话（关闭迷你条）
  Future<void> clearSession() async {
    try {
      await service.pause(); // 内含进度 flush
    } catch (_) {}
    currentBook = null;
    chapters = [];
    currentIndex = 0;
    position = Duration.zero;
    duration = Duration.zero;
    isPlaying = false;
    isBuffering = false;
    loadError = null;
    playbackError = null;
    _playbackRetryCount = 0;
    notifyListeners();
  }

  /// 播放 / 暂停（无音频源时从上次会话继续；失败态点播放则强制重解析）
  Future<void> togglePlay() async {
    if (currentBook == null) return;
    if (player.audioSource == null) {
      final book = currentBook!;
      currentBook = null;
      await continueBook(book);
      return;
    }
    if (player.playing) {
      await service.pause();
      return;
    }
    if (playbackError != null) {
      await retryPlayback();
      return;
    }
    await service.play();
  }

  /// 手动重试当前章（重置自动重试计数后重新解析）
  Future<void> retryPlayback() async {
    _playbackRetryCount = 0;
    playbackError = null;
    notifyListeners();
    await _onPlaybackError(Exception('手动重试'));
  }

  Future<void> next() => service.next();
  Future<void> previous() => service.previous();

  Future<void> seek(Duration position) => service.seek(position);

  /// 倍速（0.5 ~ 4.0），并持久化为全局默认
  Future<void> setSpeed(double value) async {
    final clamped = value.clamp(AppConstants.minSpeed, AppConstants.maxSpeed);
    speed = clamped;
    await service.setSpeed(clamped);
    await settings.setDefaultPlaybackRate(clamped);
    notifyListeners();
  }

  void setSleepTimer(SleepTimerState state) => service.setSleepTimer(state);

  /// 更新当前书籍的片头片尾覆盖配置（书籍级，null=清除恢复默认）
  Future<void> updateSkipForCurrentBook(int? intro, int? outro) async {
    final book = currentBook;
    if (book == null) return;
    final updated = book.copyWith(skipIntro: intro, skipOutro: outro);
    currentBook = updated;
    final inShelf = await bookRepo.get(book.id);
    if (inShelf != null) {
      await bookRepo.upsert(updated.copyWith(updatedAt: DateTime.now()));
    }
    final source = await sourceRepo.get(book.sourceId);
    skipConfig = SkipConfig.effective(updated, source, settings);
    service.updateSkipConfig(skipConfig);
    notifyListeners();
  }

  // ---------------- 内部实现 ----------------

  Future<void> _onPlaybackError(Object error) async {
    if (_retryingPlayback || currentBook == null || chapters.isEmpty) return;
    if (_playbackRetryCount >= _maxPlaybackRetries) {
      playbackError = '播放失败: ${error.toString()}';
      notifyListeners();
      return;
    }

    final book = currentBook!;
    final index = currentIndex.clamp(0, chapters.length - 1);
    final ch = chapters[index];
    final resumeAt = position;

    // 本地文件损坏不重解析
    if (!ch.audioUrl.startsWith('http') &&
        (ch.audioUrl.startsWith('/') ||
            (ch.audioUrl.length > 2 && ch.audioUrl[1] == ':'))) {
      playbackError = '本地文件播放失败';
      notifyListeners();
      return;
    }

    final source = await sourceRepo.get(book.sourceId);
    if (source == null) {
      playbackError = '播放失败，书源不可用';
      notifyListeners();
      return;
    }

    _retryingPlayback = true;
    _playbackRetryCount++;
    isBuffering = true;
    playbackError = '正在重新获取播放地址…';
    notifyListeners();
    try {
      final url = await _resolveOneChapter(book, ch, source);
      await service.reloadChapterUrl(index, url, resumeAt: resumeAt);
      playbackError = null;
    } catch (e) {
      playbackError = '播放失败: ${e.toString().replaceFirst('Exception: ', '')}';
    } finally {
      _retryingPlayback = false;
      isBuffering = false;
      notifyListeners();
    }
  }

  /// 解析各章播放地址：离线下载文件优先；需二次解析的书源并发解析（限制 6）
  Future<List<String>> _resolveAudioUrls(
      Book book, List<Chapter> chs, BookSource? source) async {
    final downloads = await downloadRepo.listByBook(book.id);
    final byChapter = <String, DownloadTask>{};
    for (final d in downloads) {
      if (d.status == DownloadStatus.completed && d.localPath != null) {
        byChapter[d.chapterId] = d;
      }
    }
    final needResolve = source != null && engine.needsAudioResolve(source);

    if (!needResolve) {
      final urls = <String>[];
      for (final ch in chs) {
        final dl = byChapter[ch.id];
        if (dl != null && await File(dl.localPath!).exists()) {
          urls.add(dl.localPath!);
        } else {
          urls.add(ch.audioUrl);
        }
      }
      return urls;
    }

    // 需要二次解析：并发限制 6，失败回退原始地址
    final urls = List<String>.filled(chs.length, '');
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < chs.length) {
        final i = cursor++;
        final ch = chs[i];
        final dl = byChapter[ch.id];
        if (dl != null && await File(dl.localPath!).exists()) {
          urls[i] = dl.localPath!;
          continue;
        }
        try {
          urls[i] = await engine.resolveAudio(source, ch, book: book);
        } catch (_) {
          urls[i] = ch.audioUrl;
        }
      }
    }

    await Future.wait(List.generate(6, (_) => worker()));
    return urls;
  }

  /// lazy：只准备当前章 URL（及离线文件），其余占位
  Future<List<String>> _resolveLazySeedUrls(
    Book book,
    List<Chapter> chs,
    BookSource source, {
    required int index,
  }) async {
    final urls = List<String>.filled(chs.length, '');
    if (chs.isEmpty) return urls;
    final i = index.clamp(0, chs.length - 1);
    urls[i] = await _resolveOneChapter(book, chs[i], source);
    return urls;
  }

  Future<String> _resolveOneChapter(
    Book book,
    Chapter ch,
    BookSource source,
  ) async {
    final downloads = await downloadRepo.listByBook(book.id);
    for (final d in downloads) {
      if (d.chapterId == ch.id &&
          d.status == DownloadStatus.completed &&
          d.localPath != null &&
          await File(d.localPath!).exists()) {
        return d.localPath!;
      }
    }
    return engine.resolveAudio(source, ch, book: book);
  }

  Future<void> _saveProgress(
      String chapterId, String bookId, double pos, double dur) async {
    await progressRepo.save(PlayProgress(
      chapterId: chapterId,
      bookId: bookId,
      currentTime: pos,
      duration: dur,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> _onChapterChanged(String chapterId, int index) async {
    final book = currentBook;
    if (book == null) return;
    currentIndex = index;
    await bookRepo.updatePlayState(book.id, chapterId);
    notifyListeners();
    await ensureAutoAhead();
  }
}

/// AudioPlayerService 实例 Provider（在 main 中 override 为真实实例）
final audioPlayerServiceProvider = Provider<AudioPlayerService>(
    (ref) => throw UnimplementedError('需在 main 中 override'));

final playerControllerProvider =
    ChangeNotifierProvider<PlayerController>((ref) {
  return PlayerController(
    service: ref.watch(audioPlayerServiceProvider),
    bookRepo: ref.watch(bookRepositoryProvider),
    progressRepo: ref.watch(progressRepositoryProvider),
    downloadRepo: ref.watch(downloadRepositoryProvider),
    sourceRepo: ref.watch(sourceRepositoryProvider),
    engine: ref.watch(sourceEngineProvider),
    settings: ref.watch(settingsServiceProvider),
    downloads: ref.watch(downloadServiceProvider),
  );
});
