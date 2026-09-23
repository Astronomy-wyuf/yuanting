import 'dart:convert';

/// HTTP 头（尤其 Location）里的非 ASCII 常被按 Latin-1 误读成乱码。
/// 若看起来像 UTF-8 字节被当成 Latin-1，则还原为正确 Unicode。
String fixHttpHeaderEncoding(String value) {
  if (value.isEmpty) return value;
  // 已是正常中文则不必动
  if (!_looksLikeMojibake(value)) return value;
  try {
    final fixed = utf8.decode(latin1.encode(value), allowMalformed: false);
    if (fixed.isNotEmpty) return fixed;
  } catch (_) {}
  return value;
}

/// 解析并修正重定向 Location（相对路径按 [currentUrl] 补全）。
Uri resolveRedirectLocation(String currentUrl, String location) {
  final fixed = fixHttpHeaderEncoding(location.trim());
  return Uri.parse(currentUrl).resolve(fixed);
}

bool _looksLikeMojibake(String s) {
  // 典型：UTF-8 中文被 Latin-1 解读后出现 Ã、å、é、ç 等 + 高位 Latin-1
  var weird = 0;
  for (final r in s.runes) {
    if (r >= 0x80 && r <= 0xff) weird++;
    // 已含正常 CJK 则更像本来就是 Unicode
    if (r >= 0x4e00 && r <= 0x9fff) return false;
  }
  return weird >= 2;
}
