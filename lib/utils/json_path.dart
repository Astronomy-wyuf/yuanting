/// 简易 JSONPath 实现，支持书源规则中使用的路径语法：
/// - `$.response.docs` ：从根对象取值
/// - `$.creator` / `$.creator[0]` ：数组下标
/// - `$.chapters[*]` / `$.chapters[]` ：取整个数组（与 `$.chapters` 等价）
/// - `$.a.b.c` ：嵌套对象
/// 路径必须以 `$.` 开头；找不到时返回 null。
dynamic readJsonPath(dynamic root, String path) {
  if (!path.startsWith(r'$')) return null;
  var expr = path.substring(1); // 去掉 $
  if (expr.startsWith('.')) expr = expr.substring(1);
  if (expr.isEmpty) return root;

  dynamic current = root;
  for (final seg in expr.split('.')) {
    if (current == null) return null;
    var name = seg;
    var index = -1;
    var takeAll = false;
    // [*] / [] 表示取整个数组；[n] 取下标
    final starMatch = RegExp(r'^(.*)\[\*]$').firstMatch(seg);
    final idxMatch = RegExp(r'^(.*)\[(\d*)]$').firstMatch(seg);
    if (starMatch != null) {
      name = starMatch.group(1) ?? '';
      takeAll = true;
    } else if (idxMatch != null) {
      name = idxMatch.group(1) ?? '';
      final i = idxMatch.group(2);
      if (i == null || i.isEmpty) {
        takeAll = true;
      } else {
        index = int.tryParse(i) ?? -1;
      }
    }
    if (name.isNotEmpty) {
      if (current is Map) {
        if (!current.containsKey(name)) return null;
        current = current[name];
      } else {
        return null;
      }
    }
    if (takeAll) {
      // 已定位到数组本身，继续后续路径段
      continue;
    }
    if (index >= 0) {
      if (current is List && index < current.length) {
        current = current[index];
      } else {
        return null;
      }
    }
  }
  return current;
}

/// 将任意值转为字符串（用于模板渲染与规则字段取值）
String stringifyValue(dynamic v) {
  if (v == null) return '';
  if (v is List) return v.map((e) => e.toString()).join(', ');
  return v.toString();
}

/// 模板渲染：将 `{{keyword}}`、`{{page}}`、`{{$.a.b}}` 替换为上下文值。
/// - 普通键：直接查 context 映射表（如 keyword / page / bookId）
/// - `$.x.y` 路径：在 context 上执行 JSONPath 取值
/// 未匹配到的占位符替换为空字符串。
String renderTemplate(String template, Map<String, dynamic> context) {
  return template.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (m) {
    final expr = (m.group(1) ?? '').trim();
    if (expr.isEmpty) return '';
    if (expr.startsWith(r'$')) {
      return stringifyValue(readJsonPath(context, expr));
    }
    return stringifyValue(context[expr]);
  });
}
