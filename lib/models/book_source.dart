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

  /// 网络导入时的 JSON 地址；空表示本地（粘贴/文件）导入。
  final String? remoteUrl;

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
    this.remoteUrl,
  });

  bool get isRemote => remoteUrl != null && remoteUrl!.trim().isNotEmpty;

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
    Object? remoteUrl = _unset,
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
      remoteUrl: identical(remoteUrl, _unset)
          ? this.remoteUrl
          : remoteUrl as String?,
    );
  }

  static const Object _unset = Object();

  /// 从书源规则 JSON（导入格式）构建 BookSource
  factory BookSource.fromRuleJson(
    Map<String, dynamic> raw, {
    String? id,
    String? remoteUrl,
  }) {
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
      remoteUrl: remoteUrl,
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
        'remote_url': remoteUrl,
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
        remoteUrl: map['remote_url'] as String?,
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
