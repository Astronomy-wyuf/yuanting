import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/app_providers.dart';
import 'providers/player_providers.dart';
import 'services/audio_player_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 后台播放 / 通知栏 / 锁屏控制初始化（just_audio_background）
  // androidNotificationOngoing=true 时必须同时 androidStopForegroundOnPause=true，否则断言崩溃白屏
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.yuanting.player.channel',
      androidNotificationChannelName: '源听播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    );
  } catch (e, st) {
    // 后台音频初始化失败时仍进入 UI，避免整应用白屏
    debugPrint('JustAudioBackground.init failed: $e\n$st');
  }

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
      audioPlayerServiceProvider.overrideWithValue(AudioPlayerService()),
    ],
    child: const AudiobookApp(),
  ));
}
