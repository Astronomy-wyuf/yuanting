import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import 'app_providers.dart';

/// 下载服务 Provider（ChangeNotifier：任务状态变化自动刷新 UI）
final downloadServiceProvider =
    ChangeNotifierProvider<DownloadService>((ref) {
  final engine = ref.watch(sourceEngineProvider);
  final bookRepo = ref.watch(bookRepositoryProvider);
  final sourceRepo = ref.watch(sourceRepositoryProvider);

  return DownloadService(
    repository: ref.watch(downloadRepositoryProvider),
    settings: ref.watch(settingsServiceProvider),
    urlResolver: (DownloadTask task) async {
      final book = await bookRepo.get(task.bookId);
      if (book == null) return task.url;
      final source = await sourceRepo.get(book.sourceId);
      if (source == null || !engine.needsAudioResolve(source)) {
        return task.url;
      }
      final chapters = await bookRepo.getChapters(book.id);
      for (final ch in chapters) {
        if (ch.id == task.chapterId) {
          return engine.resolveAudio(source, ch, book: book);
        }
      }
      return task.url;
    },
  );
});
