import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import '../utils/constants.dart';
import 'app_providers.dart';
import 'source_providers.dart';

/// 书源订阅同步：
/// - 启动时距上次同步超过 24 小时则后台自动同步一次；
/// - 设置页 / 书源页可手动触发。
class SourceSyncService extends ChangeNotifier {
  final SourcesController sources;
  final AppSettingsService settings;

  SourceSyncService({required this.sources, required this.settings});

  bool syncing = false;
  String? lastResult;

  /// 是否到了自动同步时间
  bool get dueForAutoSync {
    final last = settings.lastSourceSyncMs;
    if (last <= 0) return true; // 从未同步过
    return DateTime.now().millisecondsSinceEpoch - last >=
        AppConstants.sourceSyncIntervalMs;
  }

  /// 启动检查：到期才同步（静默，失败不打扰）
  Future<void> maybeAutoSync() async {
    if (!dueForAutoSync) return;
    await sync(quiet: true);
  }

  /// 手动 / 静默同步。返回是否成功。
  Future<bool> sync({bool quiet = false}) async {
    if (syncing) return false;
    syncing = true;
    if (!quiet) notifyListeners();
    try {
      final result = await sources.syncSubscribed();
      await settings.setLastSourceSyncMs(DateTime.now().millisecondsSinceEpoch);
      lastResult = result.errors.isEmpty
          ? '书源订阅已同步（${result.okCount} 个）'
          : '同步完成 ${result.okCount} 个，失败 ${result.errors.length} 个';
      return result.errors.isEmpty;
    } catch (e) {
      lastResult = '同步失败: $e';
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}

final sourceSyncServiceProvider = ChangeNotifierProvider<SourceSyncService>((ref) {
  return SourceSyncService(
    sources: ref.watch(sourcesControllerProvider),
    settings: ref.watch(settingsServiceProvider),
  );
});
