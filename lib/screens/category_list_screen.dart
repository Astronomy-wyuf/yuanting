import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book_source.dart';
import '../models/browse_list_args.dart';
import '../models/search_record.dart';
import '../providers/app_providers.dart';
import '../providers/player_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/source_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/proto_widgets.dart';

/// 书单浏览页 — 分类 / 榜单更多 / 新书更多（分页 + 下滑加载）
class CategoryListScreen extends ConsumerStatefulWidget {
  final BrowseListArgs args;

  const CategoryListScreen({super.key, required this.args});

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  static const _sorts = ['综合', '完结'];

  final _scroll = ScrollController();
  int _sortIndex = 0;
  int _page = 1;
  List<SearchRecord> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _opening = false;
  bool _supportsPage = true;

  BrowseListArgs get args => widget.args;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(() => _reload(reset: true));
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore || _loading) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 320) return;
    _loadMore();
  }

  BookSource? _activeSource() {
    final sources = ref.read(sourcesControllerProvider);
    final preferred = ref.read(settingsControllerProvider).preferredSourceId;
    final enabled = sources.enabledSources;
    if (enabled.isEmpty) return null;
    for (final s in enabled) {
      if (s.id == preferred) return s;
    }
    return enabled.first;
  }

  String get _query {
    final base = args.query.trim();
    if (base.isEmpty) return base;
    switch (_sorts[_sortIndex]) {
      case '完结':
        return '$base 完结';
      default:
        return base;
    }
  }

  bool _sourceSupportsPage(BookSource source) {
    final search = (source.rule['search'] as Map?)?.cast<String, dynamic>();
    final url = search?['url'] as String? ?? '';
    return url.contains('{{page}}');
  }

  List<SearchRecord> _filter(List<SearchRecord> raw) {
    if (!args.matchCategory) return raw;
    final name = args.title.trim();
    if (name.isEmpty) return raw;
    // 严格匹配分类字段：无分类不放行；不做「标题包含分类」的反向 contains，避免误收
    return raw.where((r) {
      final c = r.category?.trim();
      if (c == null || c.isEmpty) return false;
      return c == name || c.contains(name);
    }).toList();
  }

  Future<void> _reload({required bool reset}) async {
    final source = _activeSource();
    if (source == null) {
      setState(() {
        _items = [];
        _loading = false;
        _hasMore = false;
        _error = '请先启用一个书源';
      });
      return;
    }
    if (args.query.trim().isEmpty) {
      setState(() {
        _items = [];
        _loading = false;
        _hasMore = false;
        _error = '缺少关键词';
      });
      return;
    }

    _supportsPage = _sourceSupportsPage(source);
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }

    try {
      final raw = await ref
          .read(sourceEngineProvider)
          .search(source, _query, page: 1);
      var list = _filter(raw);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _page = 1;
        _hasMore = _supportsPage && raw.isNotEmpty;
        if (list.isEmpty) _error = '暂无内容';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !_supportsPage) return;
    final source = _activeSource();
    if (source == null) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final raw = await ref
          .read(sourceEngineProvider)
          .search(source, _query, page: next);
      final prevIds = {
        for (final r in _items) '${r.sourceId}::${r.sourceBookId}',
      };
      final fresh = _filter(raw)
          .where((r) => !prevIds.contains('${r.sourceId}::${r.sourceBookId}'))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...fresh];
        _page = next;
        _hasMore = raw.isNotEmpty && fresh.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _openDetail(SearchRecord record) async {
    if (_opening) return;
    _opening = true;
    try {
      final sources = ref.read(sourcesControllerProvider).sources;
      BookSource? source;
      for (final s in sources) {
        if (s.id == record.sourceId) source = s;
      }
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('书源不存在或已删除')),
        );
        return;
      }
      final book =
          await ref.read(sourceEngineProvider).getDetail(source, record);
      if (!mounted) return;
      context.push('/book-detail', extra: book);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);
    final scheme = theme.colorScheme;
    final hasMini =
        ref.watch(playerControllerProvider.select((p) => p.hasSession));
    final bottom = protoBottomPad(context, hasMini: hasMini);
    final showSort = args.matchCategory;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 28),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        args.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            if (showSort)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _sorts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final on = i == _sortIndex;
                    return ChoiceChip(
                      label: Text(_sorts[i]),
                      selected: on,
                      showCheckmark: false,
                      selectedColor: brand.accent,
                      labelStyle: theme.textTheme.bodySmall?.copyWith(
                        color: on ? Colors.white : scheme.onSurface,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                      side: BorderSide(
                        color: on ? brand.accent : scheme.outlineVariant,
                      ),
                      onSelected: (_) {
                        if (_sortIndex == i) return;
                        setState(() => _sortIndex = i);
                        _reload(reset: true);
                      },
                    );
                  },
                ),
              ),
            if (showSort) const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _items.isEmpty
                      ? ProtoEmpty(
                          icon: Icons.inbox_outlined,
                          title: _error!,
                          action: FilledButton.tonal(
                            onPressed: () => _reload(reset: true),
                            child: const Text('重试'),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _reload(reset: true),
                          child: ListView.separated(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
                            itemCount: _items.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i == _items.length) {
                                if (_loadingMore) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                if (!_hasMore && _items.isNotEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Center(
                                      child: Text(
                                        '没有更多了',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox(height: 8);
                              }
                              final r = _items[i];
                              return ProtoCard(
                                padding: const EdgeInsets.all(10),
                                onTap: () => _openDetail(r),
                                child: Row(
                                  children: [
                                    BookCover(
                                      url: r.coverUrl,
                                      width: 52,
                                      height: 70,
                                      radius: 6,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w500),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              if (r.authorLine != null)
                                                r.authorLine!,
                                              if (r.narratorLine != null)
                                                '播 ${r.narratorLine!}',
                                            ].join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          if (r.chapterCount != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '${r.chapterCount} 集',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
