import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/search_record.dart';
import '../providers/player_providers.dart';
import '../providers/search_providers.dart';
import '../providers/source_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/search_captcha_sheet.dart';

/// 搜书 — 多源左右分栏（左源名 / 右当前源列表）；单源隐藏左栏
class SearchScreen extends ConsumerStatefulWidget {
  final String? initialKeyword;

  const SearchScreen({super.key, this.initialKeyword});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  bool _opening = false;
  bool _focused = false;
  bool _loadingMore = false;
  /// 多源时当前选中的书源；无效时回落到第一个
  String? _sourceFilter;

  static const _tips = ['玄幻奇幻', '武侠小说', '相声小品', '历史军事'];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
    _scroll.addListener(_onScroll);
    Future.microtask(() {
      ref.read(sourcesControllerProvider).load();
      ref.read(searchControllerProvider).refreshHistory();
      final kw = widget.initialKeyword?.trim();
      if (kw != null && kw.isNotEmpty) {
        _search(kw);
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 320) return;
    _tryLoadMore();
  }

  String? _selectedId(
    AudiobookSearchController search,
    List<SourceSearchState> states,
  ) {
    if (states.isEmpty) return null;
    final id = _sourceFilter;
    if (id != null && search.bySource.containsKey(id)) return id;
    return states.first.source.id;
  }

  SourceSearchState? _selectedState(AudiobookSearchController search) {
    final states = search.bySource.values.toList();
    final id = _selectedId(search, states);
    if (id == null) return null;
    return search.bySource[id];
  }

  bool _selectedHasMore(AudiobookSearchController search) {
    final state = _selectedState(search);
    if (state == null) return false;
    return state.hasMore &&
        (state.status == SourceSearchStatus.done ||
            state.status == SourceSearchStatus.loadingMore);
  }

  void _selectSource(String id) {
    if (_sourceFilter == id) return;
    setState(() => _sourceFilter = id);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _tryLoadMore() async {
    final search = ref.read(searchControllerProvider);
    final id = _selectedId(search, search.bySource.values.toList());
    if (_loadingMore || search.query.isEmpty || id == null) return;
    if (!_selectedHasMore(search)) return;
    _loadingMore = true;
    try {
      await search.loadMore(id);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    _controller.text = keyword.trim();
    setState(() => _sourceFilter = null);
    final search = ref.read(searchControllerProvider);
    await search.search(keyword);
    if (!mounted) return;
    final first = search.bySource.values.isEmpty
        ? null
        : search.bySource.values.first;
    if (first != null &&
        first.status == SourceSearchStatus.needsCaptcha &&
        first.captcha != null) {
      await showSearchCaptchaSheet(
        context: context,
        controller: search,
        state: first,
      );
      return;
    }
    if (search.totalResults == 0 && !search.isSearching) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有找到结果，换个词试试')),
      );
    }
  }

  Future<void> _openDetail(SearchRecord record) async {
    if (_opening) return;
    _opening = true;
    try {
      final exists = ref
          .read(sourcesControllerProvider)
          .sources
          .any((s) => s.id == record.sourceId);
      if (!exists) {
        _toast('书源不存在或已删除');
        return;
      }
      if (!mounted) return;
      // 先跳转，详情页后台补全 meta / 章节，避免等 getDetail
      context.push('/book-detail', extra: record.toBook());
    } finally {
      _opening = false;
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final states = search.bySource.values.toList();
    final selectedId = _selectedId(search, states);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final showIdle = search.query.isEmpty && states.isEmpty;
    final hasMini =
        ref.watch(playerControllerProvider.select((p) => p.hasSession));
    final bottom = protoBottomPad(context, hasMini: hasMini);

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '搜书',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _focused
                              ? [
                                  BoxShadow(
                                    color: brand.accentSoft,
                                    blurRadius: 0,
                                    spreadRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '书名 / 作者 / 关键词',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            filled: true,
                            fillColor: scheme.surfaceContainerLow,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: scheme.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: scheme.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: brand.accent,
                                width: 1.5,
                              ),
                            ),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _controller.clear();
                                      ref
                                          .read(searchControllerProvider)
                                          .clear();
                                      setState(() {});
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _search(_controller.text),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('搜索'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: showIdle
              ? _idle(search, bottom)
              : selectedId == null
                  ? _loading()
                  : _results(search, states, selectedId, bottom),
        ),
      ],
    );
  }

  Widget _results(
    AudiobookSearchController search,
    List<SourceSearchState> states,
    String selectedId,
    double bottom,
  ) {
    final selected = search.bySource[selectedId];
    if (selected == null) return _loading();
    final pane = _sourcePane(search, selected, bottom);
    if (states.length < 2) return pane;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sourceRail(states, selectedId, bottom),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: scheme.outlineVariant,
        ),
        Expanded(child: pane),
      ],
    );
  }

  Widget _sourceRail(
    List<SourceSearchState> states,
    String selectedId,
    double bottom,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    return SizedBox(
      width: 84,
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: bottom),
        itemCount: states.length,
        itemBuilder: (context, index) {
          final s = states[index];
          final selected = s.source.id == selectedId;
          final loading = s.status == SourceSearchStatus.loading ||
              s.status == SourceSearchStatus.loadingMore;
          final err = s.status == SourceSearchStatus.error;
          final captcha = s.status == SourceSearchStatus.needsCaptcha;
          return Material(
            color: selected ? brand.accentSoft : Colors.transparent,
            child: InkWell(
              onTap: () => _selectSource(s.source.id),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(6, 12, 8, 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: selected ? brand.accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _railName(s.source.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.25,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: err
                            ? scheme.error
                            : selected
                                ? brand.accent
                                : scheme.onSurface,
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: brand.accent,
                        ),
                      ),
                    ] else if (captcha) ...[
                      const SizedBox(height: 4),
                      Icon(Icons.shield_outlined,
                          size: 14, color: brand.accent),
                    ] else if (err) ...[
                      const SizedBox(height: 4),
                      Icon(Icons.error_outline, size: 14, color: scheme.error),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 左栏只留站名，去掉括号里的域名，避免挤占列表。
  String _railName(String name) {
    final cut = name.split(RegExp(r'\s*[(（]')).first.trim();
    return cut.isEmpty ? name : cut;
  }

  Widget _sourcePane(
    AudiobookSearchController search,
    SourceSearchState state,
    double bottom,
  ) {
    final list = state.results;
    final initialLoading =
        state.status == SourceSearchStatus.loading && list.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.status == SourceSearchStatus.error)
          _errorBar(search, state),
        if (state.status == SourceSearchStatus.needsCaptcha &&
            state.captcha != null)
          _captchaBar(search, state),
        Expanded(
          child: initialLoading ? _loading() : _resultList(list, state, bottom),
        ),
      ],
    );
  }

  Widget _errorBar(AudiobookSearchController search, SourceSearchState state) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.error ?? '搜索失败',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ),
          TextButton(
            onPressed: () => search.retrySource(state.source.id),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _captchaBar(
    AudiobookSearchController search,
    SourceSearchState state,
  ) {
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: brand.accentSoft,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showSearchCaptchaSheet(
            context: context,
            controller: search,
            state: state,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: brand.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '需要验证码才能搜索',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: brand.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '去验证',
                  style: theme.textTheme.bodySmall?.copyWith(color: brand.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultList(
    List<SearchRecord> flat,
    SourceSearchState state,
    double bottom,
  ) {
    final theme = Theme.of(context);
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(12, 0, 16, bottom),
      itemCount: flat.length + 1,
      itemBuilder: (context, index) {
        if (index == flat.length) return _footer(state, flat);
        final r = flat[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _openDetail(r),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(
                  url: r.coverUrl,
                  width: 52,
                  height: 70,
                  radius: 6,
                  placeholderIcon: Icons.menu_book_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.subtitleLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (r.chapterCount != null) ...[
                        const SizedBox(height: 4),
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
          ),
        );
      },
    );
  }

  Widget _footer(SourceSearchState state, List<SearchRecord> flat) {
    final theme = Theme.of(context);
    final mute = theme.colorScheme.onSurfaceVariant;
    if (state.status == SourceSearchStatus.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (flat.isEmpty) {
      if (state.status == SourceSearchStatus.needsCaptcha ||
          state.status == SourceSearchStatus.error) {
        return const SizedBox(height: 8);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('暂无结果', style: theme.textTheme.bodySmall),
        ),
      );
    }
    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton(
            onPressed: _tryLoadMore,
            child: const Text('加载更多'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text('没有更多了', style: TextStyle(color: mute, fontSize: 12)),
      ),
    );
  }

  Widget _loading() {
    final mute = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 8),
            Text('正在搜索…', style: TextStyle(color: mute, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 4; i++) ...[
          Container(
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _idle(AudiobookSearchController search, double bottom) {
    final theme = Theme.of(context);
    final mute = theme.colorScheme.onSurfaceVariant;
    final history = search.history.isEmpty
        ? const ['三体', '诡秘之主', '广播剧']
        : search.history;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      children: [
        Row(
          children: [
            Text('搜索历史',
                style: theme.textTheme.bodySmall?.copyWith(color: mute)),
            const Spacer(),
            if (search.history.isNotEmpty)
              IconButton(
                tooltip: '清空',
                icon: Icon(Icons.delete_outline, size: 18, color: mute),
                onPressed: search.clearHistory,
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in history.take(12))
              ProtoChip(label: h, onTap: () => _search(h)),
          ],
        ),
        const SizedBox(height: 20),
        Text('试试这些', style: theme.textTheme.bodySmall?.copyWith(color: mute)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tip in _tips)
              ProtoChip(label: tip, onTap: () => _search(tip)),
          ],
        ),
      ],
    );
  }
}
