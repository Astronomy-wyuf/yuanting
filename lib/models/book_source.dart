import 'dart:convert';

/// 书源：一条完整的书源规则 JSON + 启用状态等元信息。
/// 规则 JSON 结构见根目录「书源规则.md」。
class BookSource {
  final String id;
  final String name;
  final String url;
  final int version;
  final String? author;
  final String? description;
  final Map<String, dynamic> rule;
  final bool enabled;
  final DateTime importedAt;

  const BookSource({
    required this.id,
    required this.name,
    required this.url,
    this.version = 1,
    this.author,
    this.description,
    required this.rule,
    this.enabled = true,
    required this.importedAt,
  });

  BookSource copyWith({
    String? id,
    String? name,
    String? url,
    int? version,
    String? author,
    String? description,
    Map<String, dynamic>? rule,
    bool? enabled,
    DateTime? importedAt,
  }) {
    return BookSource(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      rule: rule ?? this.rule,
      enabled: enabled ?? this.enabled,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  /// 从书源规则 JSON（导入格式）构建 BookSource
  factory BookSource.fromRuleJson(Map<String, dynamic> raw, {String? id}) {
    final site = (raw['site'] as Map?)?.cast<String, dynamic>() ?? {};
    return BookSource(
      id: id ?? 'src_${DateTime.now().microsecondsSinceEpoch}',
      name: (site['name'] as String?) ?? '未命名书源',
      url: (site['url'] as String?) ?? '',
      version: (site['version'] as num?)?.toInt() ?? 1,
      author: site['author'] as String?,
      description: site['description'] as String?,
      rule: raw,
      enabled: true,
      importedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'version': version,
        'author': author,
        'description': description,
        'rule_json': jsonEncode(rule),
        'enabled': enabled ? 1 : 0,
        'imported_at': importedAt.millisecondsSinceEpoch,
      };

  factory BookSource.fromMap(Map<String, dynamic> map) => BookSource(
        id: map['id'] as String,
        name: map['name'] as String,
        url: map['url'] as String? ?? '',
        version: (map['version'] as num?)?.toInt() ?? 1,
        author: map['author'] as String?,
        description: map['description'] as String?,
        rule: _decodeRule(map['rule_json'] as String? ?? '{}'),
        enabled: (map['enabled'] as num? ?? 1) == 1,
        importedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['imported_at'] as num?)?.toInt() ?? 0),
      );

  /// 导出为书源规则 JSON（可再次导入的格式）
  Map<String, dynamic> toRuleJson() => rule;

  static Map<String, dynamic> _decodeRule(String s) {
    try {
      final d = jsonDecode(s);
      if (d is Map<String, dynamic>) return d;
      return {};
    } catch (_) {
      return {};
    }
  }
}
