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
import '../utils/discover_source_config.dart';
import '../widgets/book_cover.dart';
import '../widgets/proto_widgets.dart';

/// 发现 — 按当前书源能力展示模块；无数据/无配置的区块自动隐藏
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  List<SearchRecord> _hot = [];
  List<SearchRecord> _rank = [];
  List<SearchRecord> _news = [];
  bool _loading = false;
  bool _hotRefreshing = false;
  String? _error;
  bool _opening = false;
  int _hotPoolIndex = 0;
  int _hotPage = 1;
  DiscoverSourceConfig _config = const DiscoverSourceConfig();

  void _openCategory(String name) {
    context.push('/category', extra: BrowseListArgs.category(name));
  }

  void _openBrowse(BrowseListArgs args) {
    context.push('/category', extra: args);
  }

  void _openAllCategories() => context.push('/category-all');

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

  Future<void> _reload() async {
    await ref.read(sourcesControllerProvider).load();
    final source = _activeSource();
    final config = DiscoverSourceConfig.resolve(source);
    if (source == null) {
      setState(() {
        _config = config;
        _hot = [];
        _rank = [];
        _news = [];
        _error = '请先启用一个书源';
        _loading = false;
      });
      return;
    }

    setState(() {
      _config = config;
      _loading = true;
      _error = null;
      _hotPoolIndex = 0;
      _hotPage = 1;
      _hot = [];
      _rank = [];
      _news = [];
    });

    final engine = ref.read(sourceEngineProvider);
    try {
      Future<List<SearchRecord>> safeSearch(String q) async {
        try {
          return await engine.search(source, q, page: 1);
        } catch (_) {
          return const [];
        }
      }

      final futures = <Future<List<SearchRecord>>>[];
      final kinds = <String>[];
      if (config.hasHot) {
        futures.add(safeSearch(config.hotQueries.first));
        kinds.add('hot');
      }
      if (config.hasRank) {
        futures.add(safeSearch(config.rankQuery!));
        kinds.add('rank');
      }
      if (config.hasNews) {
        futures.add(safeSearch(config.newsQuery!));
        kinds.add('news');
      }

      final results = futures.isEmpty
          ? <List<SearchRecord>>[]
          : await Future.wait(futures);

      List<SearchRecord> hot = [];
      List<SearchRecord> rank = [];
      List<SearchRecord> news = [];
      for (var i = 0; i < kinds.length; i++) {
        final list = results[i];
        switch (kinds[i]) {
          case 'hot':
            hot = list.take(8).toList();
          case 'rank':
            rank = list.take(6).toList();
          case 'news':
            news = list.take(6).toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _hot = hot;
        _rank = rank;
        _news = news;
        _loading = false;
        final noModules = !config.hasCategories &&
            hot.isEmpty &&
            rank.isEmpty &&
            news.isEmpty;
        if (noModules) {
          _error = '当前书源暂无发现内容，可去搜书';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _shuffleHot() async {
    if (_hotRefreshing || !_config.hasHot) return;
    final source = _activeSource();
    if (source == null) return;
    final queries = _config.hotQueries;
    setState(() => _hotRefreshing = true);
    _hotPoolIndex = (_hotPoolIndex + 1) % queries.length;
    if (_hotPoolIndex == 0) _hotPage += 1;
    try {
      var list = await ref.read(sourceEngineProvider).search(
            source,
            queries[_hotPoolIndex],
            page: _hotPage,
          );
      if (list.isEmpty && _hotPage > 1) {
        _hotPage = 1;
        list = await ref.read(sourceEngineProvider).search(
              source,
              queries[_hotPoolIndex],
              page: 1,
            );
      }
      if (!mounted) return;
      setState(() {
        _hot = list.take(8).toList();
        _hotRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _hotRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('换一批失败: $e')),
      );
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
          SnackBar(content: Text('打开详情失败: $e')),
        );
      }
    } finally {
      _opening = false;
    }
  }

  void _pickSource() {
    final ctrl = ref.read(sourcesControllerProvider);
    final settings = ref.read(settingsControllerProvider);
    final preferred = settings.preferredSourceId;
    final all = ctrl.sources;
    final sheetWidth = MediaQuery.sizeOf(context).width;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(minWidth: sheetWidth, maxWidth: sheetWidth),
      builder: (ctx) {
        final brand = BrandColors.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('选择书源', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                  ),
                  child: all.isEmpty
                      ? Text(
                          '暂无书源',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: all.length,
                          itemBuilder: (_, i) {
                            final s = all[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(s.name),
                              subtitle: Text(
                                s.enabled ? '已启用' : '已禁用',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                              trailing: preferred == s.id ||
                                      (preferred == null &&
                                          ctrl.enabledSources.isNotEmpty &&
                                          ctrl.enabledSources.first.id == s.id)
                                  ? Icon(Icons.check, color: brand.accent)
                                  : null,
                              onTap: () async {
                                if (!s.enabled) await ctrl.toggle(s);
                                await settings.setPreferredSourceId(s.id);
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _reload();
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/sources');
                  },
                  child: const Text('管理书源'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final enabled = ref.watch(sourcesControllerProvider).enabledSources;
    final preferredId = ref.watch(
      settingsControllerProvider.select((s) => s.preferredSourceId),
    );
    String sourceName = '未启用书源';
    if (enabled.isNotEmpty) {
      final match = enabled.where((s) => s.id == preferredId);
      final active = match.isNotEmpty ? match.first : enabled.first;
      sourceName = active.name;
    }

    // 切换书源后按新源能力重载，并隐藏无关模块
    ref.listen(
      settingsControllerProvider.select((s) => s.preferredSourceId),
      (prev, next) {
        if (prev != next) _reload();
      },
    );

    final hasMini =
        ref.watch(playerControllerProvider.select((p) => p.hasSession));
    final bottom = protoBottomPad(context, hasMini: hasMini);

    final showCategories = _config.hasCategories;
    final showHot = _config.hasHot && _hot.isNotEmpty;
    final showRank = _config.hasRank && _rank.isNotEmpty;
    final showNews = _config.hasNews && _news.isNotEmpty;
    final anyContent = showHot || showRank || showNews;
    final showGlobalLoading = _loading && !anyContent && !showCategories;
    final showEmpty =
        !_loading && _error != null && !anyContent && !showCategories;

    // 有分类时加载中：在分类下方给一点反馈
    final showInlineLoading = _loading && showCategories && !anyContent;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: ProtoPageTitle(
            '发现',
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: brand.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _pickSource,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 168),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cell_tower,
                                size: 14, color: brand.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                sourceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: brand.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_drop_down,
                                size: 18, color: brand.accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: bottom),
              children: [
                if (showCategories) ...[
                  _secHead(theme, '分类', '全部', _openAllCategories),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0;
                              i < _config.featuredCategories.length;
                              i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            ProtoChip(
                              label: _config.featuredCategories[i],
                              onTap: () => _openCategory(
                                _config.featuredCategories[i],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (showGlobalLoading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (showInlineLoading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (showEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: ProtoEmpty(
                      icon: Icons.cloud_off,
                      title: _error!,
                      action: FilledButton.tonal(
                        onPressed: _reload,
                        child: const Text('重试'),
                      ),
                    ),
                  )
                else ...[
                  if (showHot) ...[
                    _secHead(
                      theme,
                      _config.hotTitle,
                      '换一批',
                      _shuffleHot,
                      accentAction: false,
                    ),
                    SizedBox(
                      height: 210,
                      child: _hotRefreshing
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _hot.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) {
                                final r = _hot[i];
                                return _HotBook(
                                  record: r,
                                  onTap: () => _openDetail(r),
                                );
                              },
                            ),
                    ),
                  ],
                  if (showRank) ...[
                    _secHead(
                      theme,
                      _config.rankTitle,
                      '更多',
                      () => _openBrowse(
                        BrowseListArgs(
                          title: _config.rankTitle,
                          query: _config.rankQuery!,
                          matchCategory: false,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ProtoCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < _rank.length; i++) ...[
                              if (i > 0)
                                Divider(
                                    height: 1, color: scheme.outlineVariant),
                              _RankRow(
                                index: i + 1,
                                record: _rank[i],
                                onTap: () => _openDetail(_rank[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (showNews) ...[
                    _secHead(
                      theme,
                      _config.newsTitle,
                      '更多',
                      () => _openBrowse(
                        BrowseListArgs(
                          title: _config.newsTitle,
                          query: _config.newsQuery!,
                          matchCategory: false,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _news.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 78,
                        ),
                        itemBuilder: (_, i) {
                          final r = _news[i];
                          return ProtoCard(
                            padding: const EdgeInsets.all(8),
                            onTap: () => _openDetail(r),
                            child: Row(
                              children: [
                                BookCover(
                                  url: r.coverUrl,
                                  width: 40,
                                  height: 54,
                                  radius: 6,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        r.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        r.subtitleLine,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          height: 1.2,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (r.chapterCount != null)
                                        Text(
                                          '${r.chapterCount} 集',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            height: 1.2,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _secHead(
    ThemeData theme,
    String title,
    String action,
    VoidCallback onAction, {
    bool accentAction = true,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
      child: Row(
        children: [
          Text(title,
              style:
                  theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          const Spacer(),
          TextButton(
            onPressed: onAction,
            child: Text(
              action,
              style: theme.textTheme.bodySmall?.copyWith(
                color: accentAction
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotBook extends StatelessWidget {
  final SearchRecord record;
  final VoidCallback onTap;
  const _HotBook({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mute = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 11,
      height: 1.2,
    );
    return SizedBox(
      width: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              url: record.coverUrl,
              width: 96,
              height: 128,
              radius: 8,
            ),
            const SizedBox(height: 6),
            Text(
              record.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500, height: 1.2),
            ),
            if (record.authorLine != null)
              Text(
                record.authorLine!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mute,
              ),
            if (record.narratorLine != null)
              Text(
                '播 ${record.narratorLine!}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mute,
              ),
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int index;
  final SearchRecord record;
  final VoidCallback onTap;

  const _RankRow({
    required this.index,
    required this.record,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = BrandColors.of(context).accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '$index',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: index <= 2
                      ? accent
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            BookCover(
              url: record.coverUrl,
              width: 40,
              height: 54,
              radius: 8,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (record.authorLine != null || record.narratorLine != null)
                    Text(
                      [
                        if (record.authorLine != null) record.authorLine!,
                        if (record.narratorLine != null)
                          '播 ${record.narratorLine!}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (record.chapterCount != null)
              Text(
                '${record.chapterCount} 集',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
