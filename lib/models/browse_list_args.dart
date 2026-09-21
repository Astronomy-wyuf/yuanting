/// 发现 / 分类 / 榜单「更多」共用的书单浏览参数
class BrowseListArgs {
  /// 顶栏标题（如「玄幻奇幻」「本周榜单」）
  final String title;

  /// 实际搜索关键词
  final String query;

  /// 是否优先按 category 字段过滤（分类入口为 true；榜单/新书为 false）
  final bool matchCategory;

  const BrowseListArgs({
    required this.title,
    required this.query,
    this.matchCategory = false,
  });

  factory BrowseListArgs.category(String name) => BrowseListArgs(
        title: name,
        query: name,
        matchCategory: true,
      );

  factory BrowseListArgs.fromExtra(Object? extra) {
    if (extra is BrowseListArgs) return extra;
    if (extra is String && extra.trim().isNotEmpty) {
      return BrowseListArgs.category(extra.trim());
    }
    return const BrowseListArgs(title: '书单', query: '');
  }
}
