import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../providers/bookshelf_providers.dart';
import '../providers/player_providers.dart';
import '../widgets/book_cover.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/source_guide_card.dart';

/// 书架 — 标题栏 + 分组筛选 + 排序/搜索 + 三列封面网格（含更新红点）
class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen> {
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  bool _checkingUpdates = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(bookshelfControllerProvider).load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int? _chapterIndex(Book book) {
    final id = book.lastPlayChapterId;
    if (id == null) return null;
    final prefix = '${book.id}::';
    if (!id.startsWith(prefix)) return null;
    return int.tryParse(id.substring(prefix.length));
  }

  String _progressText(Book book) {
    if (book.playState == Book.stateFinished) return '听完';
    if (book.lastPlayChapterId == null) return '未开始';
    final idx = _chapterIndex(book);
    final total = book.totalChapters;
    final chapterText = idx != null
        ? (total != null && total > 0 ? '${idx + 1}/$total' : '第${idx + 1}章')
        : '有进度';
    final time = book.lastPlayTime;
    if (time == null) return chapterText;
    return '$chapterText · ${_rel(time)}';
  }

  String _rel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes}分钟前';
    if (d.inDays < 1) return '${d.inHours}小时前';
    if (d.inDays == 1) return '昨天';
    if (d.inDays < 7) return '${d.inDays}天前';
    return '一周前';
  }

  Future<void> _confirmRemove(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出书架'),
        content: Text(
          '将《${book.title}》移出书架？\n'
          '不会停止当前播放；书架进度记录会清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // 不 clearSession：移出书架 ≠ 停止收听
    await ref.read(bookshelfControllerProvider).remove(book.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移出《${book.title}》')),
    );
  }

  Future<void> _showBookActions(Book book) async {
    final shelf = ref.read(bookshelfControllerProvider);
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('标记为未听'),
              onTap: () => Navigator.pop(sheetCtx, Book.stateUnlistened),
            ),
            ListTile(
              leading: const Icon(Icons.headphones_rounded),
              title: const Text('标记为在听'),
              onTap: () => Navigator.pop(sheetCtx, Book.stateListening),
            ),
            ListTile(
              leading: const Icon(Icons.done_all_rounded),
              title: const Text('标记为听完'),
              onTap: () => Navigator.pop(sheetCtx, Book.stateFinished),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.bookmark_remove_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text('移出书架',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(sheetCtx, -1),
            ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    if (value == -1) {
      await _confirmRemove(book);
      return;
    }
    await shelf.setPlayState(book.id, value);
  }

  Future<void> _runUpdateCheck() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    try {
      final checker = ref.read(shelfUpdateCheckerProvider);
      final updated = await checker.checkAll();
      await ref.read(bookshelfControllerProvider).load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(updated > 0 ? '$updated 本书有新章节' : '暂无新章节'),
        duration: const Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  void _pickSort() {
    final shelf = ref.read(bookshelfControllerProvider);
    showModalBottomSheet<ShelfSort>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in ShelfSort.values)
              ListTile(
                leading: Icon(shelf.sort == s
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(_sortLabel(s)),
                onTap: () => Navigator.pop(sheetCtx, s),
              ),
          ],
        ),
      ),
    ).then((s) {
      if (s is ShelfSort) {
        setState(() => shelf.sort = s);
      }
    });
  }

  String _sortLabel(ShelfSort s) {
    switch (s) {
      case ShelfSort.recentUpdated:
        return '最近更新';
      case ShelfSort.recentPlayed:
        return '最近收听';
      case ShelfSort.byTitle:
        return '书名';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelf = ref.watch(bookshelfControllerProvider);
    final hasMini = ref.watch(
      playerControllerProvider.select((p) => p.hasSession),
    );
    final bottom = protoBottomPad(context, hasMini: hasMini);
    final visible = shelf.visibleBooks;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: ProtoPageTitle(
            '书架',
            actions: [
              IconButton(
                tooltip: '搜索书架',
                onPressed: () {
                  setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _searchCtrl.clear();
                      shelf.query = '';
                    }
                  });
                },
                icon: Icon(
                  _searching ? Icons.search_off : Icons.search,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: '检查章节更新',
                onPressed: _checkingUpdates ? null : _runUpdateCheck,
                icon: _checkingUpdates
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.new_releases_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
              ),
              IconButton(
                tooltip: '排序',
                onPressed: _pickSort,
                icon: Icon(
                  Icons.swap_vert,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // 分组筛选行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              for (final g in ShelfGroup.values) ...[
                _GroupChip(
                  label: g.label,
                  selected: shelf.group == g,
                  onTap: () => setState(() => shelf.group = g),
                ),
                if (g != ShelfGroup.finished) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索书名 / 作者',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: shelf.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => shelf.query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => shelf.query = v),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _runUpdateCheck,
            child: shelf.loading && shelf.books.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SourceGuideCard(),
                      if (visible.isEmpty)
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.5,
                          child: shelf.books.isEmpty
                              ? ProtoEmpty(
                                  icon: Icons.bookmark_border,
                                  title: '书架空空如也',
                                  subtitle: '去搜书，发现下一本好故事',
                                  action: FilledButton(
                                    onPressed: () => context.go('/search'),
                                    child: const Text('去搜书'),
                                  ),
                                )
                              : const ProtoEmpty(
                                  icon: Icons.filter_alt_off_outlined,
                                  title: '该筛选下暂无书籍',
                                  subtitle: '换个分组或关键词试试',
                                ),
                        )
                      else
                        GridView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.55,
                          ),
                          itemCount: visible.length + 1,
                          itemBuilder: (context, i) {
                            if (i == visible.length) {
                              return _AddTile(
                                onTap: () => context.go('/search'),
                              );
                            }
                            final book = visible[i];
                            return _ShelfTile(
                              book: book,
                              progress: _progressText(book),
                              hasUpdate: book.newChapters > 0,
                              onOpen: () async {
                                // 打开详情即清除该书红点
                                if (book.newChapters > 0) {
                                  await ref
                                      .read(bookshelfControllerProvider)
                                      .clearNewChapters(book.id);
                                }
                                if (!context.mounted) return;
                                await context.push('/book-detail',
                                    extra: book);
                              },
                              onActions: () => _showBookActions(book),
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// 分组筛选 chip
class _GroupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color:
              selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
    );
  }
}

class _ShelfTile extends StatelessWidget {
  final Book book;
  final String progress;
  final bool hasUpdate;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  const _ShelfTile({
    required this.book,
    required this.progress,
    required this.hasUpdate,
    required this.onOpen,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      onLongPress: onActions,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                clipBehavior: Clip.none,
                children: [
                  BookCover(
                    url: book.coverUrl,
                    width: c.maxWidth,
                    height: c.maxHeight,
                    radius: 8,
                  ),
                  if (hasUpdate)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '+${book.newChapters}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onError,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (book.playState == Book.stateFinished)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '听完',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          Text(progress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Container(
                width: c.maxWidth,
                height: c.maxHeight,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      Icon(Icons.add, size: 28, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '去搜书',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          Text('添加更多', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
