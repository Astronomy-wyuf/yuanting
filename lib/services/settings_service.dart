import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 简单配置持久化（shared_preferences）：
/// 主题模式 / 默认倍速 / 全局跳过秒数 / 下载存储上限 / 首次启动标记
class AppSettingsService {
  final SharedPreferences prefs;
  AppSettingsService(this.prefs);

  /// 主题：light | dark | auto
  String get themeMode => prefs.getString(AppConstants.keyThemeMode) ?? 'auto';
  Future<void> setThemeMode(String value) => prefs.setString(AppConstants.keyThemeMode, value);

  /// 皮肤：day | night | paper | ink
  String get skin => prefs.getString(AppConstants.keySkin) ?? 'day';
  Future<void> setSkin(String value) => prefs.setString(AppConstants.keySkin, value);

  String? get preferredSourceId => prefs.getString(AppConstants.keyPreferredSourceId);
  Future<void> setPreferredSourceId(String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(AppConstants.keyPreferredSourceId);
    } else {
      await prefs.setString(AppConstants.keyPreferredSourceId, value);
    }
  }

  bool get wifiOnlyDownload =>
      prefs.getBool(AppConstants.keyWifiOnlyDownload) ?? true;
  Future<void> setWifiOnlyDownload(bool value) =>
      prefs.setBool(AppConstants.keyWifiOnlyDownload, value);

  double get defaultPlaybackRate =>
      prefs.getDouble(AppConstants.keyDefaultRate) ?? 1.0;
  Future<void> setDefaultPlaybackRate(double value) =>
      prefs.setDouble(AppConstants.keyDefaultRate, value);

  int get defaultSkipIntro => prefs.getInt(AppConstants.keyDefaultSkipIntro) ?? 0;
  Future<void> setDefaultSkipIntro(int value) =>
      prefs.setInt(AppConstants.keyDefaultSkipIntro, value);

  int get defaultSkipOutro => prefs.getInt(AppConstants.keyDefaultSkipOutro) ?? 0;
  Future<void> setDefaultSkipOutro(int value) =>
      prefs.setInt(AppConstants.keyDefaultSkipOutro, value);

  int get downloadMaxStorageMB =>
      prefs.getInt(AppConstants.keyDownloadMaxStorageMB) ??
      AppConstants.defaultDownloadMaxStorageMB;
  Future<void> setDownloadMaxStorageMB(int value) =>
      prefs.setInt(AppConstants.keyDownloadMaxStorageMB, value);

  /// 播放时自动下载后续 N 章（0 = 关闭）
  int get autoDownloadAhead =>
      prefs.getInt(AppConstants.keyAutoDownloadAhead) ??
      AppConstants.defaultAutoDownloadAhead;
  Future<void> setAutoDownloadAhead(int value) => prefs.setInt(
        AppConstants.keyAutoDownloadAhead,
        value.clamp(0, AppConstants.maxAutoDownloadAhead),
      );

  bool get isFirstLaunch => prefs.getBool(AppConstants.keyFirstLaunch) ?? true;
  Future<void> setFirstLaunchDone() => prefs.setBool(AppConstants.keyFirstLaunch, false);

  /// 搜索历史（最近在前，最多 12 条）
  List<String> get searchHistory =>
      prefs.getStringList(AppConstants.keySearchHistory) ?? const [];

  Future<void> addSearchHistory(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return;
    final list = List<String>.from(searchHistory);
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    if (list.length > 12) list.removeRange(12, list.length);
    await prefs.setStringList(AppConstants.keySearchHistory, list);
  }

  Future<void> removeSearchHistory(String keyword) async {
    final list = List<String>.from(searchHistory)..remove(keyword);
    await prefs.setStringList(AppConstants.keySearchHistory, list);
  }

  Future<void> clearSearchHistory() =>
      prefs.remove(AppConstants.keySearchHistory);
}
