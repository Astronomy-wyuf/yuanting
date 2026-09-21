import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';

import '../utils/json_path.dart';
import '../utils/sm4.dart';

/// 解析 auth.cookie：把声明的变量写入上下文，并按 valueTemplate 生成 cookieValue。
class SourceAuthBootstrap {
  SourceAuthBootstrap._();

  static const defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

  /// 向 [context] 注入 userAgent；配置了 auth.cookie 时再注入变量与 cookieValue。
  static void apply(Map<String, dynamic>? auth, Map<String, dynamic> context) {
    context.putIfAbsent('userAgent', () => defaultUserAgent);
    if (auth == null) return;

    final cookie = (auth['cookie'] as Map?)?.cast<String, dynamic>();
    if (cookie == null) return;

    final vars = (cookie['variables'] as Map?)?.cast<String, dynamic>() ?? {};
    final local = <String, dynamic>{...context};

    // 先解析普通变量，再解析依赖它们的加密变量
    for (final e in vars.entries) {
      if (_isCipherVar(e.value)) continue;
      local[e.key] = _resolveVar(e.value, local);
    }
    for (final e in vars.entries) {
      if (!_isCipherVar(e.value)) continue;
      local[e.key] = _resolveVar(e.value, local);
    }
    for (final key in vars.keys) {
      if (local.containsKey(key)) context[key] = local[key];
    }

    final template = (cookie['valueTemplate'] as String?)?.trim() ?? '';
    if (template.isEmpty) return;
    context['cookieValue'] = renderTemplate(template, local);
  }

  static bool _isCipherVar(dynamic spec) {
    if (spec is! Map) return false;
    final algo = (spec['algorithm'] as String?)?.toLowerCase() ?? '';
    return algo.startsWith('sm4');
  }

  static String _resolveVar(dynamic spec, Map<String, dynamic> ctx) {
    if (spec is String) return renderTemplate(spec, ctx);
    if (spec is! Map) return stringifyValue(spec);
    final map = spec.cast<String, dynamic>();

    final algo = (map['algorithm'] as String?)?.toLowerCase();
    if (algo == 'sm4-ecb-pkcs7' || algo == 'sm4-ecb') {
      return _sm4Encrypt(map, ctx);
    }

    final source = (map['source'] as String?)?.toLowerCase();
    if (source == 'date') {
      final format = (map['format'] as String?) ?? 'yyyyMMdd';
      final raw = DateFormat(format).format(DateTime.now());
      final transform = map['transform'] as String?;
      if (transform == 'parseIntRadix36') {
        return int.parse(raw).toRadixString(36);
      }
      return raw;
    }

    return '';
  }

  static String _sm4Encrypt(Map<String, dynamic> map, Map<String, dynamic> ctx) {
    final keySpec = map['key'];
    final keyBytes = _resolveKey(keySpec, ctx);
    final plain = renderTemplate(map['plaintext'] as String? ?? '', ctx);
    final encoding = ((map['encoding'] as String?) ?? 'base64').toLowerCase();
    final out = sm4EcbEncrypt(keyBytes, Uint8List.fromList(utf8.encode(plain)));
    switch (encoding) {
      case 'hex':
        return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      case 'base64':
      default:
        return base64Encode(out);
    }
  }

  static Uint8List _resolveKey(dynamic keySpec, Map<String, dynamic> ctx) {
    if (keySpec is String) {
      final s = renderTemplate(keySpec, ctx);
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(s) && s.length % 2 == 0) {
        return _hex(s);
      }
      return Uint8List.fromList(utf8.encode(s));
    }
    if (keySpec is! Map) {
      throw StateError('auth.cookie key 配置无效');
    }
    final map = keySpec.cast<String, dynamic>();
    final kdf = (map['kdf'] as String?)?.toLowerCase();
    if (kdf == 'sha256') {
      final input = renderTemplate(map['input'] as String? ?? '', ctx);
      final digest = sha256.convert(utf8.encode(input));
      var hex = digest.toString(); // already hex
      final take = (map['takeHexChars'] as num?)?.toInt() ?? 32;
      if (take > 0 && take < hex.length) hex = hex.substring(0, take);
      return _hex(hex);
    }
    throw StateError('不支持的 key.kdf: $kdf');
  }

  static Uint8List _hex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
