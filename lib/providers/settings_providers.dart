import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'app_providers.dart';

/// 应用设置控制器
class SettingsController extends ChangeNotifier {
  final AppSettingsService service;

  SettingsController(this.service);

  ThemeMode get themeMode {
    switch (service.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  AppSkin get skin => AppSkin.parse(service.skin);

  /// 浅色槽：纸感 / 日间
  ThemeData get lightTheme => AppTheme.forSkin(
        skin == AppSkin.paper ? AppSkin.paper : AppSkin.day,
      );

  /// 深色槽：墨青 / 夜间
  ThemeData get darkTheme => AppTheme.forSkin(
        skin == AppSkin.ink ? AppSkin.ink : AppSkin.night,
      );

  double get defaultRate => service.defaultPlaybackRate;
  int get defaultSkipIntro => service.defaultSkipIntro;
  int get defaultSkipOutro => service.defaultSkipOutro;
  int get maxStorageMB => service.downloadMaxStorageMB;
  bool get wifiOnlyDownload => service.wifiOnlyDownload;
  int get autoDownloadAhead => service.autoDownloadAhead;
  String? get preferredSourceId => service.preferredSourceId;

  String get autoDownloadAheadLabel =>
      autoDownloadAhead == 0 ? '关闭' : '$autoDownloadAhead 章';

  Future<void> setThemeMode(String mode) async {
    await service.setThemeMode(mode);
    if (mode == 'dark' && !skin.isDark) {
      await service.setSkin(AppSkin.night.name);
    } else if (mode == 'light' && skin.isDark) {
      await service.setSkin(AppSkin.day.name);
    }
    notifyListeners();
  }

  /// 选皮肤立即生效（对齐原型 setSkin）
  Future<void> setSkin(AppSkin next) async {
    await service.setSkin(next.name);
    await service.setThemeMode(next.isDark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setDefaultRate(double value) async {
    await service.setDefaultPlaybackRate(value);
    notifyListeners();
  }

  Future<void> setDefaultSkipIntro(int value) async {
    await service.setDefaultSkipIntro(value);
    notifyListeners();
  }

  Future<void> setDefaultSkipOutro(int value) async {
    await service.setDefaultSkipOutro(value);
    notifyListeners();
  }

  Future<void> setMaxStorageMB(int value) async {
    await service.setDownloadMaxStorageMB(value);
    notifyListeners();
  }

  Future<void> setWifiOnlyDownload(bool value) async {
    await service.setWifiOnlyDownload(value);
    notifyListeners();
  }

  Future<void> setAutoDownloadAhead(int value) async {
    await service.setAutoDownloadAhead(value);
    notifyListeners();
  }

  Future<void> setPreferredSourceId(String? id) async {
    await service.setPreferredSourceId(id);
    notifyListeners();
  }
}

final settingsControllerProvider =
    ChangeNotifierProvider<SettingsController>((ref) {
  return SettingsController(ref.watch(settingsServiceProvider));
});
