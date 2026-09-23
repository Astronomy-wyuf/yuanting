import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../providers/bookshelf_providers.dart';
import '../providers/player_providers.dart';
import '../widgets/book_cover.dart';
import '../widgets/proto_widgets.dart';

/// 书架 — 对齐原型：标题栏 + 三列封面网格，无顶部续听横幅
class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(bookshelfControllerProvider).load());
  }

  int? _chapterIndex(Book book) {
    final id = book.lastPlayChapterId;
    if (id == null) return null;
    final prefix = '${book.id}::';
    if (!id.startsWith(prefix)) return null;
    return int.tryParse(id.substring(prefix.length));
  }

  String _progressText(Book book) {
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

  @override
  Widget build(BuildContext context) {
    final shelf = ref.watch(bookshelfControllerProvider);
    final hasMini = ref.watch(
      playerControllerProvider.select((p) => p.hasSession),
    );
    final bottom = protoBottomPad(context, hasMini: hasMini);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: ProtoPageTitle(
            '书架',
            actions: [
              IconButton(
                tooltip: '按最近收听排序',
                onPressed: () async {
                  await ref
                      .read(bookshelfControllerProvider)
                      .load(byLastPlay: true);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已按最近收听排序')),
                  );
                },
                icon: Icon(
                  Icons.swap_vert,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(bookshelfControllerProvider).load(),
            child: shelf.loading && shelf.books.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : shelf.books.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.55,
                            child: ProtoEmpty(
                              icon: Icons.bookmark_border,
                              title: '书架空空如也',
                              subtitle: '去搜书，发现下一本好故事',
                              action: FilledButton(
                                onPressed: () => context.go('/search'),
                                child: const Text('去搜书'),
                              ),
                            ),
                          ),
                        ],
                      )
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.55,
                        ),
                        itemCount: shelf.books.length + 1,
                        itemBuilder: (context, i) {
                          if (i == shelf.books.length) {
                            return _AddTile(
                              onTap: () => context.go('/search'),
                            );
                          }
                          final book = shelf.books[i];
                          return _ShelfTile(
                            book: book,
                            progress: _progressText(book),
                            onOpen: () =>
                                context.push('/book-detail', extra: book),
                            onRemove: () => _confirmRemove(book),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

class _ShelfTile extends StatelessWidget {
  final Book book;
  final String progress;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _ShelfTile({
    required this.book,
    required this.progress,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      onLongPress: onRemove,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => BookCover(
                url: book.coverUrl,
                width: c.maxWidth,
                height: c.maxHeight,
                radius: 8,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          Text(progress, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
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
                  child: Icon(Icons.add, size: 28, color: scheme.onSurfaceVariant),
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
