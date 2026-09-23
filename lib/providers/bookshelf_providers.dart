import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book.dart';
import '../models/play_progress.dart';
import '../repositories/book_repository.dart';
import '../repositories/progress_repository.dart';
import 'app_providers.dart';

/// 书架控制器（含每本书最近进度，用于进度条）
class BookshelfController extends ChangeNotifier {
  final BookRepository repository;
  final ProgressRepository progressRepo;

  List<Book> books = [];
  Map<String, PlayProgress> latestProgress = {};
  bool loading = false;

  BookshelfController({
    required this.repository,
    required this.progressRepo,
  });

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

  Future<void> refresh() async {
    books = await repository.listShelf();
    await _loadProgress();
    notifyListeners();
  }
}

final bookshelfControllerProvider =
    ChangeNotifierProvider<BookshelfController>((ref) {
  return BookshelfController(
    repository: ref.watch(bookRepositoryProvider),
    progressRepo: ref.watch(progressRepositoryProvider),
  );
});
