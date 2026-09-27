import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/app_providers.dart';
import 'providers/player_providers.dart';
import 'services/audio_player_service.dart';
import 'services/audiobook_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 后台播放 / 通知栏 / 锁屏：自定义 Handler，始终提供上一集 / 下一集
  AudioPlayerService? audioService;
  try {
    await AudioService.init(
      builder: () {
        final service = AudioPlayerService();
        audioService = service;
        return AudiobookAudioHandler(service);
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.yuanting.player.channel',
        androidNotificationChannelName: '源听播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // 听书常用 ±30 秒（通知栏快退 / 快进）
        rewindInterval: Duration(seconds: 30),
        fastForwardInterval: Duration(seconds: 30),
      ),
    );
  } catch (e, st) {
    // 后台音频初始化失败时仍进入 UI，避免整应用白屏
    debugPrint('AudioService.init failed: $e\n$st');
  }
  audioService ??= AudioPlayerService();

  // 全局配置
  final prefs = await SharedPreferences.getInstance();

  // Android 13+ 通知权限（用于播放通知栏控制；拒绝不影响播放，仅无通知）
  if (Platform.isAndroid) {
    try {
      await Permission.notification.request();
    } catch (_) {
      // 部分低版本设备无该权限项，忽略
    }
  }

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioPlayerServiceProvider.overrideWithValue(audioService!),
    ],
    child: const AudiobookApp(),
  ));
}
