import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/book_repository.dart';
import '../repositories/download_repository.dart';
import '../repositories/progress_repository.dart';
import '../repositories/source_repository.dart';
import '../services/settings_service.dart';
import '../services/source_auth_cache.dart';
import '../services/source_engine.dart';

/// 基础 Provider 汇总。SharedPreferences 在 main 中 override。

final sharedPreferencesProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('需在 main 中 override'));

final settingsServiceProvider =
    Provider<AppSettingsService>((ref) => AppSettingsService(ref.watch(sharedPreferencesProvider)));

final sourceAuthCacheProvider = Provider<SourceAuthCache>(
  (ref) => SourceAuthCache(ref.watch(sharedPreferencesProvider)),
);

final sourceEngineProvider = Provider<SourceEngine>(
  (ref) => SourceEngine(authCache: ref.watch(sourceAuthCacheProvider)),
);

final sourceRepositoryProvider = Provider<SourceRepository>((ref) => SourceRepository());
final bookRepositoryProvider = Provider<BookRepository>((ref) => BookRepository());
final progressRepositoryProvider =
    Provider<ProgressRepository>((ref) => ProgressRepository());
final downloadRepositoryProvider =
    Provider<DownloadRepository>((ref) => DownloadRepository());
