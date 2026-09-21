import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'json_path.dart';
import 'nuxt_payload.dart';

/// 通用书源解析器：按 ParserConfig 解析 JSON / HTML / RSS / XML / DIRECT / NUXT 响应。
///
/// ParserConfig 结构：
/// ```json
/// {
///   "type": "json | html | rss | xml | direct | nuxt",
///   "listSelector": "CSS 选择器 或 $.json.path 或 searchResults.list",
///   "fields": { "title": "$.title | .book-name @text | a @href | p @text##作者：(.+)" },
///   "listFilter": { "field": "$.format", "equals": ["MP3"] },
///   "stripExtension": true
/// }
/// ```
class RuleParser {
  RuleParser._();

  /// 解析响应体，返回字段映射列表。
  /// [context] 为外层上下文（如 bookId / keyword），用于字段模板渲染。
  static List<Map<String, String>> parse(
    String body,
    Map<String, dynamic> parser, {
    Map<String, dynamic> context = const {},
  }) {
    final type = (parser['type'] as String?)?.toLowerCase() ?? 'html';
    switch (type) {
      case 'json':
        return _parseJson(body, parser, context);
      case 'nuxt':
        return _parseNuxt(body, parser, context);
      case 'html':
      case 'rss':
      case 'xml':
        return _parseHtml(body, parser, context);
      case 'direct':
        return _parseDirect(parser, context);
      default:
        throw SourceRuleException('不支持的解析类型: $type');
    }
  }

  /// Nuxt SSR：从 `__NUXT_DATA__` 解析列表。
  /// listSelector 形如 `searchResults.list`（先定位含 searchResults 的节点，再取 .list）。
  static List<Map<String, String>> _parseNuxt(
    String body,
    Map<String, dynamic> parser,
    Map<String, dynamic> context,
  ) {
    final data = NuxtPayload.extractArray(body);
    if (data == null) {
      throw SourceRuleException('页面中未找到 __NUXT_DATA__');
    }
    final listSelector = (parser['listSelector'] as String?)?.trim() ?? '';
    if (listSelector.isEmpty) {
      throw SourceRuleException('nuxt 解析缺少 listSelector');
    }
    // 支持 searchResults.list 或 $.searchResults.list
    var path = listSelector;
    if (path.startsWith(r'$.')) path = path.substring(2);
    if (path.startsWith(r'$')) path = path.substring(1);
    if (path.startsWith('.')) path = path.substring(1);
    final parts = path.split('.');
    final rootKey = parts.first;
    final rest = parts.length > 1 ? parts.sublist(1).join('.') : '';
    final rawList = NuxtPayload.findList(data, rootKey: rootKey, itemPath: rest);
    if (rawList == null) {
      throw SourceRuleException('nuxt listSelector 未命中: $listSelector');
    }
    if (rawList is! List) {
      throw SourceRuleException('nuxt listSelector 结果不是数组: $listSelector');
    }
    return _mapJsonItems(rawList, parser, context);
  }

  /// JSON 类型：listSelector 为 JSONPath（如 `$.response.docs`），
  /// fields 值为相对当前条目的 JSONPath（如 `$.title`）。
  static List<Map<String, String>> _parseJson(
    String body,
    Map<String, dynamic> parser,
    Map<String, dynamic> context,
  ) {
    final dynamic root;
    try {
      root = jsonDecode(body);
    } catch (e) {
      throw SourceRuleException('JSON 解析失败: $e');
    }
    final listSelector = parser['listSelector'] as String?;
    if (listSelector == null || listSelector.isEmpty) {
      throw SourceRuleException('JSON 解析缺少 listSelector');
    }
    final rawList = readJsonPath(root, listSelector);
    if (rawList == null) throw SourceRuleException('listSelector 未命中: $listSelector');
    if (rawList is! List) throw SourceRuleException('listSelector 结果不是数组: $listSelector');
    return _mapJsonItems(rawList, parser, context);
  }

  static List<Map<String, String>> _mapJsonItems(
    List rawList,
    Map<String, dynamic> parser,
    Map<String, dynamic> context,
  ) {
    final items = _applyListFilter(rawList, parser);
    final fields =
        (parser['fields'] as Map<String, dynamic>?)?.cast<String, dynamic>() ??
            {};
    final stripExt = parser['stripExtension'] == true;

    final result = <Map<String, String>>[];
    for (final item in items) {
      final merged = <String, dynamic>{...context, ..._toJsonDynamic(item)};
      final values = <String, String>{};
      for (final entry in fields.entries) {
        final rule = entry.value.toString();
        String value;
        if (rule.contains('{{')) {
          value = renderTemplate(rule, merged);
        } else if (rule.startsWith(r'$')) {
          value = stringifyValue(readJsonPath(item, rule));
        } else {
          // 允许简写字段名 id / title
          value = stringifyValue(
            item is Map ? (item[rule] ?? readJsonPath(item, '\$.$rule')) : null,
          );
        }
        if (stripExt && entry.key == 'title') {
          value = _stripExtension(value);
        }
        values[entry.key] = value;
      }
      result.add(values);
    }
    return result;
  }

  /// HTML / RSS / XML 类型：listSelector 为 CSS 选择器，
  /// fields 值格式为 `CSS选择器 @属性`（@text/@html/@href/@src/@任意属性名）。
  static List<Map<String, String>> _parseHtml(
    String body,
    Map<String, dynamic> parser,
    Map<String, dynamic> context,
  ) {
    final listSelector = parser['listSelector'] as String?;
    if (listSelector == null || listSelector.isEmpty) {
      throw SourceRuleException('HTML 解析缺少 listSelector');
    }
    final doc = html_parser.parse(body);
    final elements = doc.querySelectorAll(listSelector);
    final fields = (parser['fields'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {};
    final stripExt = parser['stripExtension'] == true;

    final result = <Map<String, String>>[];
    for (final el in elements) {
      final values = <String, String>{};
      for (final entry in fields.entries) {
        final rule = entry.value;
        String value;
        if (rule.contains('{{')) {
          // 纯模板字段（引用外层上下文）
          value = renderTemplate(rule, context);
        } else {
          value = _readHtmlField(el, rule);
        }
        if (stripExt && entry.key == 'title') {
          value = _stripExtension(value);
        }
        values[entry.key] = value;
      }
      result.add(values);
    }
    return result;
  }

  /// direct 类型：字段直接取自上下文（如章节列表已包含 audioUrl）。
  static List<Map<String, String>> _parseDirect(
    Map<String, dynamic> parser,
    Map<String, dynamic> context,
  ) {
    final fields = (parser['fields'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {};
    final values = <String, String>{};
    for (final entry in fields.entries) {
      var value = stringifyValue(context[entry.value]);
      values[entry.key] = value;
    }
    if (values.isEmpty) {
      // 无 fields 定义时，直接输出上下文中的字符串键
      context.forEach((k, v) {
        if (v is String || v is num) values[k] = stringifyValue(v);
      });
    }
    return [values];
  }

  /// 字段语法：`CSS @attr`，可选尾缀 `##regex`（有捕获组时取 group1）。
  /// 例：`div.info h4 + p + p @text##作者：(.+)`
  static String _readHtmlField(dynamic element, String rule) {
    var fieldRule = rule;
    String? regex;
    final hash = rule.indexOf('##');
    if (hash >= 0) {
      fieldRule = rule.substring(0, hash).trim();
      regex = rule.substring(hash + 2).trim();
    }

    var selector = '';
    var attr = 'text';
    final idx = fieldRule.lastIndexOf('@');
    if (idx >= 0) {
      selector = fieldRule.substring(0, idx).trim();
      attr = fieldRule.substring(idx + 1).trim();
    } else {
      selector = fieldRule.trim();
    }
    dynamic target = element;
    if (selector.isNotEmpty) {
      target = (element as dynamic).querySelector(selector);
    }
    if (target == null) return '';
    String value;
    switch (attr) {
      case 'text':
        value = (target as dynamic).text?.trim() ?? '';
        break;
      case 'html':
      case 'innerHtml':
        value = ((target as dynamic).innerHtml ?? '').trim();
        break;
      default:
        final v = (target as dynamic).attributes?[attr];
        value = (v ?? '').trim();
    }
    if (regex == null || regex.isEmpty || value.isEmpty) return value;
    final m = RegExp(regex).firstMatch(value);
    if (m == null) return value;
    if (m.groupCount >= 1) return (m.group(1) ?? value).trim();
    return (m.group(0) ?? value).trim();
  }

  /// 列表过滤：{"field": "$.format", "equals": ["MP3", "VBR MP3"]}
  /// equals 比较不区分大小写。
  static List<dynamic> _applyListFilter(List list, Map<String, dynamic> parser) {
    final filter = parser['listFilter'] as Map<String, dynamic>?;
    if (filter == null) return list;
    final field = filter['field'] as String?;
    if (field == null) return list;
    final equals = (filter['equals'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    final contains = (filter['contains'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    return list.where((item) {
      final value = stringifyValue(readJsonPath(item, field)).toLowerCase();
      if (equals != null && equals.isNotEmpty) {
        return equals.contains(value);
      }
      if (contains != null && contains.isNotEmpty) {
        return contains.any((c) => value.contains(c));
      }
      return true;
    }).toList();
  }

  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 5) return name.substring(0, dot);
    return name;
  }

  static Map<String, dynamic> _toJsonDynamic(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return item.map((k, v) => MapEntry(k.toString(), v));
    return {};
  }
}

/// 书源规则异常
class SourceRuleException implements Exception {
  final String message;
  SourceRuleException(this.message);
  @override
  String toString() => message;
}
