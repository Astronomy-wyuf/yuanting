import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _clipboardChannel = MethodChannel('audiobook_player/clipboard');

/// 读取剪贴板纯文本。Android 走原生通道，尽量避开 Flutter/IME 粘贴截断。
Future<String?> readClipboardText() async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      final text = await _clipboardChannel.invokeMethod<String>('getText');
      if (text != null && text.isNotEmpty) return text;
    } catch (_) {
      // fall through
    }
  }
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return data?.text;
}
