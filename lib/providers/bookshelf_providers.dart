import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book.dart';
import '../models/play_progress.dart';
import '../repositories/book_repository.dart';
import '../repositories/progress_repository.dart';
import '../repositories/source_repository.dart';
import '../services/source_engine.dart';
import 'app_providers.dart';

/// 书架排序
enum ShelfSort { recentUpdated, recentPlayed, byTitle }

/// 书架分组（按收听状态）
enum ShelfGroup { all, unlistened, listening, finished }

extension ShelfGroupX on ShelfGroup {
  String get label {
    switch (this) {
      case ShelfGroup.all:
        return '全部';
      case ShelfGroup.unlistened:
        return '未听';
      case ShelfGroup.listening:
        return '在听';
      case ShelfGroup.finished:
        return '听完';
    }
  }

  int? get playState {
    switch (this) {
      case ShelfGroup.all:
        return null;
      case ShelfGroup.unlistened:
        return Book.stateUnlistened;
      case ShelfGroup.listening:
        return Book.stateListening;
      case ShelfGroup.finished:
        return Book.stateFinished;
    }
  }
}

/// 书架控制器（含每本书最近进度，用于进度条）
class BookshelfController extends ChangeNotifier {
  final BookRepository repository;
  final ProgressRepository progressRepo;

  BookshelfController({
    required this.repository,
    required this.progressRepo,
  });

  List<Book> books = [];
  Map<String, PlayProgress> latestProgress = {};
  bool loading = false;

  /// 当前排序 / 分组 / 关键字筛选（UI 状态）
  ShelfSort sort = ShelfSort.recentUpdated;
  ShelfGroup group = ShelfGroup.all;
  String query = '';

  /// 有更新红点的书籍 id 集合（书架角标）
  Set<String> get updatedBookIds =>
      books.where((b) => b.newChapters > 0).map((b) => b.id).toSet();

  /// 排序 + 分组 + 搜索后的可见书列表
  List<Book> get visibleBooks {
    Iterable<Book> list = books;
    final state = group.playState;
    if (state != null) {
      list = list.where((b) => b.playState == state);
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((b) =>
          b.title.toLowerCase().contains(q) ||
          (b.author ?? '').toLowerCase().contains(q));
    }
    final result = list.toList();
    switch (sort) {
      case ShelfSort.recentUpdated:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ShelfSort.recentPlayed:
        result.sort((a, b) {
          final at = a.lastPlayTime?.millisecondsSinceEpoch ?? 0;
          final bt = b.lastPlayTime?.millisecondsSinceEpoch ?? 0;
          if (at != bt) return bt.compareTo(at);
          return b.updatedAt.compareTo(a.updatedAt);
        });
      case ShelfSort.byTitle:
        result.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return result;
  }

  Future<void> load({bool byLastPlay = false}) async {
    loading = true;
    notifyListeners();
    try {
      books = byLastPlay
          ? await repository.listShelfByLastPlay()
          : await repository.listShelf();
      await _loadProgress();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProgress() async {
    final map = <String, PlayProgress>{};
    for (final book in books) {
      final p = await progressRepo.getLatestForBook(book.id);
      if (p != null) map[book.id] = p;
    }
    latestProgress = map;
  }

  /// 章节进度 0~1（有时长时用时间比例；否则按章节序号估算）
  double chapterProgress(Book book) {
    final p = latestProgress[book.id];
    if (p != null && p.duration > 0) {
      return (p.currentTime / p.duration).clamp(0.0, 1.0);
    }
    final id = book.lastPlayChapterId;
    final total = book.totalChapters;
    if (id == null || total == null || total <= 0) return 0;
    final prefix = '${book.id}::';
    if (!id.startsWith(prefix)) return 0;
    final idx = int.tryParse(id.substring(prefix.length));
    if (idx == null) return 0;
    return ((idx + 1) / total).clamp(0.0, 1.0);
  }

  Future<bool> isInShelf(String bookId) async =>
      await repository.get(bookId) != null;

  Future<void> addOrUpdate(Book book) async {
    await repository.upsert(book);
    await load();
  }

  Future<void> remove(String bookId) async {
    await repository.removeFromShelf(bookId);
    await load();
  }

  /// 手动设置收听状态
  Future<void> setPlayState(String bookId, int state) async {
    await repository.updatePlayStateFlag(bookId, state);
    final i = books.indexWhere((b) => b.id == bookId);
    if (i >= 0) {
      books[i] = books[i].copyWith(playState: state);
      notifyListeners();
    }
  }

  /// 清除某本书的更新红点
  Future<void> clearNewChapters(String bookId) async {
    await repository.updateNewChapters(bookId, 0);
    final i = books.indexWhere((b) => b.id == bookId);
    if (i >= 0) {
      books[i] = books[i].copyWith(newChapters: 0);
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    books = await repository.listShelf();
    await _loadProgress();
    notifyListeners();
  }
}

/// 章节更新检查（书架手动触发）：逐书抓目录并对比本地缓存条数。
/// 默认只查在听的书（未听/听完意义不大），失败静默跳过。
class ShelfUpdateChecker {
  final BookRepository bookRepo;
  final SourceRepository sourceRepo;
  final SourceEngine engine;

  ShelfUpdateChecker({
    required this.bookRepo,
    required this.sourceRepo,
    required this.engine,
  });

  /// 返回有更新的书籍数
  Future<int> checkAll({List<Book>? targets}) async {
    final list =
        targets ?? await bookRepo.listShelfByState(Book.stateListening);
    var updated = 0;
    for (final book in list) {
      try {
        final source = await sourceRepo.get(book.sourceId);
        if (source == null) continue;
        final remote = await engine.getChapters(source, book);
        final local = await bookRepo.getChapters(book.id);
        final extra = remote.length - local.length;
        if (extra > 0) {
          await bookRepo.updateNewChapters(book.id, extra);
          updated++;
        }
      } catch (_) {
        // 单书失败不影响其余
      }
    }
    return updated;
  }
}

final bookshelfControllerProvider =
    ChangeNotifierProvider<BookshelfController>((ref) {
  return BookshelfController(
    repository: ref.watch(bookRepositoryProvider),
    progressRepo: ref.watch(progressRepositoryProvider),
  );
});

final shelfUpdateCheckerProvider = Provider<ShelfUpdateChecker>((ref) {
  return ShelfUpdateChecker(
    bookRepo: ref.watch(bookRepositoryProvider),
    sourceRepo: ref.watch(sourceRepositoryProvider),
    engine: ref.watch(sourceEngineProvider),
  );
});
