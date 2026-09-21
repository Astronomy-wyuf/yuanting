import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../utils/sm4.dart';

/// 书源声明式加解密错误（可诊断）
class SourceCryptoException implements Exception {
  final String code;
  final String message;
  SourceCryptoException(this.code, this.message);

  @override
  String toString() => message;
}

/// 按书源声明执行标准算法。密钥、前缀、编码都来自规则。
class SourceCrypto {
  SourceCrypto._();

  /// algorithm → (密钥字节数, nonce 字节数, 种类)
  static const _catalog = <String, (int, int, String)>{
    'aes-128-gcm': (16, 12, 'gcm'),
    'aes-256-gcm': (32, 12, 'gcm'),
    'aes-128-cbc': (16, 16, 'cbc'),
    'aes-256-cbc': (32, 16, 'cbc'),
    'chacha20-poly1305': (32, 12, 'chacha'),
    'xchacha20-poly1305': (32, 24, 'xchacha'),
    'sm4-ecb': (16, 0, 'sm4'),
  };

  static const prefixes = {'none', 'nonce', 'version+nonce'};

  static Set<String> get algorithms => _catalog.keys.toSet();

  static void validatePipeline(Map<String, dynamic>? pipe, {required String path}) {
    if (pipe == null) return;
    final algo = pipe['algorithm'] as String?;
    final spec = algo == null ? null : _catalog[algo];
    if (spec == null) {
      throw SourceCryptoException(
        'bad_algorithm',
        '不支持的算法「$algo」（$path）；允许: ${algorithms.join(", ")}',
      );
    }
    final key = pipe['key'] as String?;
    if (key == null || key.isEmpty) {
      throw SourceCryptoException('bad_key', '缺少密钥（$path）');
    }
    final prefix = pipe['prefix'] as String?;
    if (prefix != null && !prefixes.contains(prefix)) {
      throw SourceCryptoException(
        'bad_prefix',
        '不支持的 prefix「$prefix」（$path）；允许: ${prefixes.join(", ")}',
      );
    }
  }

  static Uint8List decodeKey(Map<String, dynamic> pipe) {
    final key = pipe['key'] as String;
    final enc = ((pipe['keyEncoding'] as String?) ?? 'hex').toLowerCase();
    return _decodeOuter(key, enc);
  }

  static Future<String> encrypt(
    String plaintext,
    Map<String, dynamic> pipe,
  ) async {
    validatePipeline(pipe, path: 'requestCrypto');
    final spec = _resolve(pipe);
    final keyBytes = decodeKey(pipe);
    _checkKey(keyBytes, spec);
    final nonce = _nonceForEncrypt(pipe, spec);
    final body = await _encryptBody(
      spec,
      keyBytes,
      nonce,
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    final version = (pipe['versionByte'] as num?)?.toInt() ?? 1;
    final packed = _pack(spec, version, nonce, body);
    final encoding = ((pipe['encoding'] as String?) ?? 'hex').toLowerCase();
    return _encodeOuter(packed, encoding);
  }

  static Future<String> decrypt(
    String ciphertextOuter,
    Map<String, dynamic> pipe,
  ) async {
    validatePipeline(pipe, path: 'responseParse.decrypt');
    try {
      final spec = _resolve(pipe);
      final keyBytes = decodeKey(pipe);
      _checkKey(keyBytes, spec);
      final encoding = ((pipe['encoding'] as String?) ?? 'hex').toLowerCase();
      final packed = _decodeOuter(ciphertextOuter, encoding);
      final parts = _unpack(spec, packed);
      var body = parts.body;
      final reverseOn = (pipe['reverseCiphertextOnVersion'] as num?)?.toInt();
      if (reverseOn != null && parts.version == reverseOn) {
        body = Uint8List.fromList(body.reversed.toList());
      }
      final nonce = spec.nonceLen == 0
          ? Uint8List(0)
          : (parts.nonce.isNotEmpty ? parts.nonce : _fixedNonce(pipe, spec));
      final clear = await _decryptBody(spec, keyBytes, nonce, body);
      return utf8.decode(clear);
    } on SourceCryptoException {
      rethrow;
    } catch (e) {
      throw SourceCryptoException(
        'protocol_changed',
        '解密失败，请检查书源中的算法、密钥与密文格式（$e）',
      );
    }
  }

  static _Spec _resolve(Map<String, dynamic> pipe) {
    final algo = pipe['algorithm'] as String;
    final row = _catalog[algo]!;
    final nonceLen = row.$2;
    final prefix =
        ((pipe['prefix'] as String?) ?? (nonceLen == 0 ? 'none' : 'nonce'))
            .toLowerCase();
    return _Spec(
      algorithm: algo,
      kind: row.$3,
      keyLen: row.$1,
      nonceLen: nonceLen,
      includeNonce: prefix != 'none',
      versionPrefix: prefix == 'version+nonce',
    );
  }

  static void _checkKey(Uint8List key, _Spec spec) {
    if (key.length != spec.keyLen) {
      throw SourceCryptoException(
        'bad_key',
        '${spec.algorithm} 需要 ${spec.keyLen} 字节密钥',
      );
    }
  }

  static Uint8List _nonceForEncrypt(Map<String, dynamic> pipe, _Spec spec) {
    if (spec.nonceLen == 0) return Uint8List(0);
    final fixed = pipe['iv'] ?? pipe['nonce'];
    if (fixed is String && fixed.isNotEmpty && fixed.toLowerCase() != 'random') {
      final bytes = _decodeOuter(
        fixed,
        ((pipe['ivEncoding'] as String?) ??
                pipe['keyEncoding'] as String? ??
                'hex')
            .toLowerCase(),
      );
      if (bytes.length != spec.nonceLen) {
        throw SourceCryptoException(
          'bad_prefix',
          'iv 长度应为 ${spec.nonceLen} 字节',
        );
      }
      return bytes;
    }
    return _randomBytes(spec.nonceLen);
  }

  static Uint8List _fixedNonce(Map<String, dynamic> pipe, _Spec spec) {
    final fixed = pipe['iv'] ?? pipe['nonce'];
    if (fixed is! String || fixed.isEmpty || fixed.toLowerCase() == 'random') {
      throw SourceCryptoException('bad_prefix', '密文未包含 iv，请在规则中声明 iv');
    }
    return _decodeOuter(
      fixed,
      ((pipe['ivEncoding'] as String?) ?? pipe['keyEncoding'] as String? ?? 'hex')
          .toLowerCase(),
    );
  }

  static Future<Uint8List> _encryptBody(
    _Spec spec,
    Uint8List key,
    Uint8List nonce,
    Uint8List plain,
  ) async {
    switch (spec.kind) {
      case 'gcm':
        final algo =
            spec.keyLen == 16 ? AesGcm.with128bits() : AesGcm.with256bits();
        final box = await algo.encrypt(
          plain,
          secretKey: SecretKey(key),
          nonce: nonce,
        );
        return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
      case 'cbc':
        final algo = spec.keyLen == 16
            ? AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
            : AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
        final box = await algo.encrypt(
          plain,
          secretKey: SecretKey(key),
          nonce: nonce,
        );
        return Uint8List.fromList(box.cipherText);
      case 'chacha':
        final box = await Chacha20.poly1305Aead().encrypt(
          plain,
          secretKey: SecretKey(key),
          nonce: nonce,
        );
        return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
      case 'xchacha':
        final box = await Xchacha20.poly1305Aead().encrypt(
          plain,
          secretKey: SecretKey(key),
          nonce: nonce,
        );
        return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
      case 'sm4':
        return sm4EcbEncrypt(key, plain);
      default:
        throw SourceCryptoException('bad_algorithm', '不支持的算法 ${spec.algorithm}');
    }
  }

  static Future<List<int>> _decryptBody(
    _Spec spec,
    Uint8List key,
    Uint8List nonce,
    Uint8List body,
  ) async {
    switch (spec.kind) {
      case 'gcm':
      case 'chacha':
      case 'xchacha':
        if (body.length < 16) {
          throw SourceCryptoException('bad_prefix', '密文过短');
        }
        final mac = body.sublist(body.length - 16);
        final cipherText = body.sublist(0, body.length - 16);
        final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
        final Cipher algo;
        if (spec.kind == 'gcm') {
          algo =
              spec.keyLen == 16 ? AesGcm.with128bits() : AesGcm.with256bits();
        } else if (spec.kind == 'chacha') {
          algo = Chacha20.poly1305Aead();
        } else {
          algo = Xchacha20.poly1305Aead();
        }
        return algo.decrypt(box, secretKey: SecretKey(key));
      case 'cbc':
        final algo = spec.keyLen == 16
            ? AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
            : AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
        return algo.decrypt(
          SecretBox(body, nonce: nonce, mac: Mac.empty),
          secretKey: SecretKey(key),
        );
      case 'sm4':
        return sm4EcbDecrypt(key, body);
      default:
        throw SourceCryptoException('bad_algorithm', '不支持的算法 ${spec.algorithm}');
    }
  }

  static Uint8List _pack(
    _Spec spec,
    int version,
    Uint8List nonce,
    Uint8List body,
  ) {
    final out = BytesBuilder();
    if (spec.versionPrefix) out.addByte(version & 0xff);
    if (spec.includeNonce) out.add(nonce);
    out.add(body);
    return out.toBytes();
  }

  static ({int version, Uint8List nonce, Uint8List body}) _unpack(
    _Spec spec,
    Uint8List packed,
  ) {
    var offset = 0;
    var version = 0;
    if (spec.versionPrefix) {
      if (packed.isEmpty) {
        throw SourceCryptoException('bad_prefix', '空密文');
      }
      version = packed[0];
      offset = 1;
    }
    var nonce = Uint8List(0);
    if (spec.includeNonce) {
      if (packed.length < offset + spec.nonceLen) {
        throw SourceCryptoException('bad_prefix', '密文长度不足');
      }
      nonce = Uint8List.fromList(packed.sublist(offset, offset + spec.nonceLen));
      offset += spec.nonceLen;
    }
    return (
      version: version,
      nonce: nonce,
      body: Uint8List.fromList(packed.sublist(offset)),
    );
  }

  static String _encodeOuter(Uint8List bytes, String encoding) {
    switch (encoding) {
      case 'hex':
        return _hexEncode(bytes);
      case 'base64':
        return base64Encode(bytes);
      case 'raw':
        return utf8.decode(bytes, allowMalformed: true);
      default:
        throw SourceCryptoException('bad_encoding', '未知 encoding: $encoding');
    }
  }

  static Uint8List _decodeOuter(String s, String encoding) {
    switch (encoding) {
      case 'hex':
        return _hexDecode(s.trim());
      case 'base64':
        return Uint8List.fromList(base64Decode(s.trim()));
      case 'utf8':
      case 'raw':
        return Uint8List.fromList(utf8.encode(s));
      default:
        throw SourceCryptoException('bad_encoding', '未知 encoding: $encoding');
    }
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static String _hexEncode(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexDecode(String hex) {
    var s = hex.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.length.isOdd) {
      throw SourceCryptoException('bad_key', 'hex 长度必须为偶数');
    }
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

class _Spec {
  final String algorithm;
  final String kind;
  final int keyLen;
  final int nonceLen;
  final bool includeNonce;
  final bool versionPrefix;

  const _Spec({
    required this.algorithm,
    required this.kind,
    required this.keyLen,
    required this.nonceLen,
    required this.includeNonce,
    required this.versionPrefix,
  });
}
