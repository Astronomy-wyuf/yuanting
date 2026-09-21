import 'dart:convert';
import 'dart:typed_data';

/// 解码本地文本/JSON 文件字节：兼容 UTF-8、带 BOM，以及 Windows 记事本常见的 UTF-16。
String decodeTextFileBytes(List<int> raw) {
  final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  if (bytes.isEmpty) return '';

  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }

  // UTF-16 LE BOM（Windows「新建文本文档」常见）
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, littleEndian: true, skipBom: true);
  }

  // UTF-16 BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, littleEndian: false, skipBom: true);
  }

  // 无 BOM 的 UTF-16 LE 启发式：偶数长度且大量 0x00 出现在奇数下标
  if (bytes.length >= 4 &&
      bytes.length.isEven &&
      _looksLikeUtf16Le(bytes)) {
    return _decodeUtf16(bytes, littleEndian: true, skipBom: false);
  }

  return utf8.decode(bytes);
}

bool _looksLikeUtf16Le(Uint8List bytes) {
  var nulOnOdd = 0;
  final sample = bytes.length < 64 ? bytes.length : 64;
  for (var i = 1; i < sample; i += 2) {
    if (bytes[i] == 0) nulOnOdd++;
  }
  return nulOnOdd >= (sample ~/ 4);
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  required bool skipBom,
}) {
  var i = skipBom ? 2 : 0;
  final codes = <int>[];
  while (i + 1 < bytes.length) {
    final unit = littleEndian
        ? (bytes[i] | (bytes[i + 1] << 8))
        : ((bytes[i] << 8) | bytes[i + 1]);
    i += 2;
    // 简易代理对处理
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < bytes.length) {
      final low = littleEndian
          ? (bytes[i] | (bytes[i + 1] << 8))
          : ((bytes[i] << 8) | bytes[i + 1]);
      i += 2;
      if (low >= 0xDC00 && low <= 0xDFFF) {
        codes.add(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
        continue;
      }
    }
    codes.add(unit);
  }
  return String.fromCharCodes(codes);
}
