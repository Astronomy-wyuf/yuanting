import '../models/book_source.dart';

/// 从书源规则解析发现页能力；无 `discover` 配置则用通用关键词试探，空结果再隐藏。
class DiscoverSourceConfig {
  final List<String> featuredCategories;
  final List<(String group, List<String> names)> categoryGroups;
  final List<String> hotQueries;
  final String? rankQuery;
  final String? newsQuery;
  final String hotTitle;
  final String rankTitle;
  final String newsTitle;

  const DiscoverSourceConfig({
    this.featuredCategories = const [],
    this.categoryGroups = const [],
    this.hotQueries = const [],
    this.rankQuery,
    this.newsQuery,
    this.hotTitle = '热门推荐',
    this.rankTitle = '本周榜单',
    this.newsTitle = '新书速递',
  });

  bool get hasCategories =>
      featuredCategories.isNotEmpty || categoryGroups.isNotEmpty;

  bool get hasHot => hotQueries.isNotEmpty;

  bool get hasRank => rankQuery != null && rankQuery!.trim().isNotEmpty;

  bool get hasNews => newsQuery != null && newsQuery!.trim().isNotEmpty;

  List<String> get allCategoryNames {
    if (categoryGroups.isNotEmpty) {
      return [
        for (final g in categoryGroups) ...g.$2,
      ];
    }
    return featuredCategories;
  }

  static DiscoverSourceConfig resolve(BookSource? source) {
    if (source == null) return const DiscoverSourceConfig();

    final raw = source.rule['discover'];
    if (raw is Map) {
      return _fromRule(raw.cast<String, dynamic>());
    }

    // 书源未声明 discover：仅尝试通用搜索区块（空结果再隐藏）
    return const DiscoverSourceConfig(
      hotQueries: ['热门', '完结', '连载'],
      rankQuery: '热门',
      newsQuery: '最新',
    );
  }

  static DiscoverSourceConfig _fromRule(Map<String, dynamic> d) {
    List<String> strList(dynamic v) {
      if (v is! List) return const [];
      return [
        for (final e in v)
          if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
      ];
    }

    final featured = strList(d['categories']);
    final groups = <(String, List<String>)>[];
    final rawGroups = d['categoryGroups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is! Map) continue;
        final name = g['name']?.toString() ?? '';
        final items = strList(g['items']);
        if (name.isEmpty || items.isEmpty) continue;
        groups.add((name, items));
      }
    }

    final hot = d['hot'];
    List<String> hotQueries = const [];
    var hotTitle = '热门推荐';
    if (hot is Map) {
      hotTitle = hot['title']?.toString() ?? hotTitle;
      hotQueries = strList(hot['queries'] ?? hot['query']);
      if (hotQueries.isEmpty && hot['query'] is String) {
        hotQueries = [hot['query'].toString()];
      }
    } else if (hot is List) {
      hotQueries = strList(hot);
    }

    String? sectionQuery(String key, String fallbackTitle) {
      final s = d[key];
      if (s == null) return null;
      if (s is String) return s.trim().isEmpty ? null : s.trim();
      if (s is Map) {
        final q = s['query']?.toString().trim() ?? '';
        return q.isEmpty ? null : q;
      }
      if (s is bool && !s) return null;
      return null;
    }

    String sectionTitle(String key, String fallback) {
      final s = d[key];
      if (s is Map && s['title'] != null) return s['title'].toString();
      return fallback;
    }

    final rankQuery = sectionQuery('rank', '本周榜单');
    final newsQuery = sectionQuery('news', '新书速递');

    // 显式 false 关闭
    final rankOff = d['rank'] == false;
    final newsOff = d['news'] == false;
    final hotOff = d['hot'] == false;

    var featuredOut = featured;
    if (featuredOut.isEmpty && groups.isNotEmpty) {
      featuredOut = [
        for (final g in groups) ...g.$2,
      ].take(8).toList();
    }

    return DiscoverSourceConfig(
      featuredCategories: featuredOut,
      categoryGroups: groups,
      hotQueries: hotOff ? const [] : hotQueries,
      rankQuery: rankOff ? null : rankQuery,
      newsQuery: newsOff ? null : newsQuery,
      hotTitle: hotTitle,
      rankTitle: sectionTitle('rank', '本周榜单'),
      newsTitle: sectionTitle('news', '新书速递'),
    );
  }
}
