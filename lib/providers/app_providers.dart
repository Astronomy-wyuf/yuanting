import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/book_repository.dart';
import '../repositories/download_repository.dart';
import '../repositories/progress_repository.dart';
import '../repositories/source_repository.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../services/source_auth_cache.dart';
import '../services/source_cookie_manager.dart';
import '../services/source_engine.dart';

/// 基础 Provider 汇总。SharedPreferences 在 main 中 override。

final sharedPreferencesProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('需在 main 中 override'));

final settingsServiceProvider =
    Provider<AppSettingsService>((ref) => AppSettingsService(ref.watch(sharedPreferencesProvider)));

final sourceAuthCacheProvider = Provider<SourceAuthCache>(
  (ref) => SourceAuthCache(ref.watch(sharedPreferencesProvider)),
);

/// 按书源隔离的持久化 Cookie（应用文档目录 cookies/ 下，每源一个子目录）。
final sourceCookieManagerProvider = Provider<SourceScopedCookieManager>(
  (ref) => SourceScopedCookieManager(
    resolveRootDir: () async {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/cookies';
    },
    fallbackJar: CookieJar(),
  ),
);

final sourceEngineProvider = Provider<SourceEngine>(
  (ref) => SourceEngine(
    authCache: ref.watch(sourceAuthCacheProvider),
    cookieManager: ref.watch(sourceCookieManagerProvider),
  ),
);

final sourceRepositoryProvider = Provider<SourceRepository>((ref) => SourceRepository());
final bookRepositoryProvider = Provider<BookRepository>((ref) => BookRepository());
final progressRepositoryProvider =
    Provider<ProgressRepository>((ref) => ProgressRepository());
final downloadRepositoryProvider =
    Provider<DownloadRepository>((ref) => DownloadRepository());

/// 本地备份（书架 + 进度 + 书源）
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    bookRepo: ref.watch(bookRepositoryProvider),
    progressRepo: ref.watch(progressRepositoryProvider),
    sourceRepo: ref.watch(sourceRepositoryProvider),
  );
});
