/// 全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '源听';
  static const String appNameEn = 'YuanTing';
  static const String dbFileName = 'yuanting.db';

  /// 下载文件存放的子目录（位于应用文档目录下）
  static const String downloadDirName = 'downloads';

  /// SharedPreferences 键
  static const String keyThemeMode = 'theme_mode';
  static const String keySkin = 'app_skin';
  static const String keyPreferredSourceId = 'preferred_source_id';
  static const String keyWifiOnlyDownload = 'wifi_only_download';
  static const String keyDefaultRate = 'default_playback_rate';
  static const String keyDefaultSkipIntro = 'default_skip_intro';
  static const String keyDefaultSkipOutro = 'default_skip_outro';
  static const String keyDownloadMaxStorageMB = 'download_max_storage_mb';
  static const String keyAutoDownloadAhead = 'auto_download_ahead';
  static const String keyFirstLaunch = 'first_launch';
  static const String keySearchHistory = 'search_history';

  /// 播放时自动向后补齐的章节数（0 = 关闭）
  static const int defaultAutoDownloadAhead = 3;
  static const int maxAutoDownloadAhead = 50;

  /// 倍速范围
  static const double minSpeed = 0.5;
  static const double maxSpeed = 4.0;
  static const double speedStep = 0.1;

  /// 进度保存节流间隔
  static const Duration progressSaveInterval = Duration(seconds: 5);

  /// 下载进度 UI 刷新节流间隔
  static const Duration downloadEmitInterval = Duration(milliseconds: 600);

  /// 默认下载存储上限（MB）
  static const int defaultDownloadMaxStorageMB = 2048;
}
