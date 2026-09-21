import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

/// 从 Nuxt 3 SSR 页面提取并解析 `__NUXT_DATA__` 扁平引用数组。
class NuxtPayload {
  NuxtPayload._();

  /// 从 HTML 取出 JSON 数组；失败返回 null。
  static List<dynamic>? extractArray(String html) {
    final doc = html_parser.parse(html);
    final el = doc.querySelector('script#__NUXT_DATA__') ??
        doc.querySelector('script[type="application/json"]#__NUXT_DATA__');
    var raw = el?.text.trim() ?? '';
    if (raw.isEmpty) {
      final m = RegExp(
        r'<script[^>]*id="__NUXT_DATA__"[^>]*>([\s\S]*?)</script>',
        caseSensitive: false,
      ).firstMatch(html);
      raw = m?.group(1)?.trim() ?? '';
    }
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  /// 解析扁平 Nuxt payload 中的下标引用。
  static dynamic resolve(List<dynamic> data, dynamic idx, [Set<int>? seen]) {
    final visiting = seen ?? <int>{};
    if (idx is! int) return idx;
    if (idx < 0 || idx >= data.length) return null;
    if (visiting.contains(idx)) return null;
    visiting.add(idx);
    final val = data[idx];
    if (val is String || val is num || val is bool || val == null) return val;
    if (val is List) {
      if (val.isNotEmpty &&
          val.first is String &&
          const {
            'Reactive',
            'ShallowReactive',
            'Ref',
            'ShallowRef',
            'Set',
            'Map',
            'EmptyRef',
          }.contains(val.first)) {
        if (val.length < 2) return null;
        return resolve(data, val[1], visiting);
      }
      return [
        for (final x in val)
          x is int ? resolve(data, x, Set<int>.from(visiting)) : x,
      ];
    }
    if (val is Map) {
      final out = <String, dynamic>{};
      val.forEach((k, v) {
        final key = k is int
            ? resolve(data, k, Set<int>.from(visiting))?.toString() ?? '$k'
            : k.toString();
        out[key] = v is int ? resolve(data, v, Set<int>.from(visiting)) : v;
      });
      return out;
    }
    return val;
  }

  /// 在 payload 中查找包含 [rootKey] 的对象并解析，再按点路径取值。
  /// 例如 rootKey=`searchResults` path=`list` → searchResults.list
  static dynamic findList(
    List<dynamic> data, {
    required String rootKey,
    String itemPath = 'list',
  }) {
    for (var i = 0; i < data.length; i++) {
      final v = data[i];
      if (v is! Map) continue;
      if (!v.containsKey(rootKey)) continue;
      final resolved = resolve(data, i);
      if (resolved is! Map) continue;
      dynamic cur = resolved[rootKey];
      if (itemPath.isEmpty) return cur;
      for (final seg in itemPath.split('.')) {
        if (seg.isEmpty) continue;
        if (cur is Map) {
          cur = cur[seg];
        } else {
          return null;
        }
      }
      return cur;
    }
    return null;
  }
}
