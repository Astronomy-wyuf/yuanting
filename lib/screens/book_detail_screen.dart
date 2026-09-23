import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import '../models/download_task.dart';
import '../models/search_record.dart';
import '../providers/app_providers.dart';
import '../providers/bookshelf_providers.dart';
import '../providers/download_providers.dart';
import '../providers/player_providers.dart';
import '../theme/app_theme.dart';
import '../utils/audio_utils.dart';
import '../widgets/book_cover.dart';
import '../widgets/download_range_sheet.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/skip_config_sheet.dart';

/// 书籍详情 — 对齐原型：顶栏返回 / 封面横排 / 继续收听+收藏+下载 / 章节列表
class BookDetailScreen extends ConsumerStatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  late Book _book;
  BookSource? _source;
  List<Chapter> _chapters = [];
  bool _loading = true;
  String? _error;
  bool _inShelf = false;
  bool _starting = false;

  bool get _canResume => _book.lastPlayChapterId != null;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    Future.microtask(_init);
  }

  Future<void> _init() async {
    await _checkShelf();
    // 列表进详情时 meta 可能不全；与章节并行补全，不挡目录
    unawaited(_enrichDetailMeta());
    await _loadChapters();
  }

  /// 后台拉取详情简介等；失败静默保留列表字段。
  Future<void> _enrichDetailMeta() async {
    try {
      final source = await ref.read(sourceRepositoryProvider).get(_book.sourceId);
      if (source == null) return;
      final detail = source.rule['detail'];
      final url = detail is Map ? (detail['url'] as String?)?.trim() : null;
      if (url == null || url.isEmpty) return;

      final record = SearchRecord(
        sourceId: _book.sourceId,
        sourceName: source.name,
        sourceBookId: _book.sourceBookId,
        title: _book.title,
        author: _book.author,
        coverUrl: _book.coverUrl,
        detailUrl: _book.detailUrl,
      );
      final detailed =
          await ref.read(sourceEngineProvider).getDetail(source, record);
      if (!mounted) return;
      setState(() {
        _book = _book.copyWith(
          title: detailed.title,
          author: detailed.author ?? _book.author,
          coverUrl: detailed.coverUrl ?? _book.coverUrl,
          description: detailed.description ?? _book.description,
          detailUrl: detailed.detailUrl.isNotEmpty
              ? detailed.detailUrl
              : _book.detailUrl,
        );
      });
      if (_inShelf) {
        unawaited(
          ref.read(bookshelfControllerProvider).addOrUpdate(_book),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkShelf() async {
    final repo = ref.read(bookRepositoryProvider);
    final existing = await repo.get(_book.id);
    if (existing != null) {
      _inShelf = true;
      _book = existing.copyWith(
        title: _book.title,
        author: _book.author ?? existing.author,
        coverUrl: _book.coverUrl ?? existing.coverUrl,
        description: _book.description ?? existing.description,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadChapters({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(bookRepositoryProvider);
      final sourceRepo = ref.read(sourceRepositoryProvider);
      _source = await sourceRepo.get(_book.sourceId);
      var chs = forceRefresh ? <Chapter>[] : await repo.getChapters(_book.id);
      if (chs.isEmpty) {
        if (_source == null) {
          throw Exception('书源不存在或已被删除，无法获取章节列表');
        }
        final engine = ref.read(sourceEngineProvider);
        chs = await engine.getChapters(_source!, _book);
        // 仅在拉取成功后写库，避免刷新失败把已有缓存清空
        await repo.saveChapters(_book.id, chs);
        _book = _book.copyWith(totalChapters: chs.length);
        if (_inShelf) {
          await ref.read(bookshelfControllerProvider).addOrUpdate(_book);
        }
      }
      _chapters = chs;
      if (chs.isNotEmpty && _book.totalChapters == null) {
        _book = _book.copyWith(totalChapters: chs.length);
        if (_inShelf) {
          await ref.read(bookshelfControllerProvider).addOrUpdate(_book);
        }
      }
      _loading = false;
    } catch (e) {
      _loading = false;
      _error = e.toString().replaceFirst('Exception: ', '');
      // 强制刷新失败时保留旧章节列表
      if (forceRefresh && _chapters.isEmpty) {
        final cached =
            await ref.read(bookRepositoryProvider).getChapters(_book.id);
        if (cached.isNotEmpty) _chapters = cached;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleShelf() async {
    final shelf = ref.read(bookshelfControllerProvider);
    if (_inShelf) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('移出书架'),
          content: Text(
            '将《${_book.title}》移出书架？\n'
            '不会停止播放；书架进度记录会清除，章节缓存仍保留便于再播。',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移出')),
          ],
        ),
      );
      if (ok != true) return;
      await shelf.remove(_book.id);
      setState(() => _inShelf = false);
    } else {
      await shelf.addOrUpdate(_book);
      setState(() => _inShelf = true);
    }
  }

  Future<void> _afterStartPlay(PlayerController player) async {
    if (!mounted) return;
    if (player.loadError != null || player.currentBook == null) {
      final err = player.loadError ?? '起播失败';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    // 播放不自动加书架；收藏由用户显式点「书架」
  }

  Future<void> _ensurePlayerRoute() async {
    if (!mounted) return;
    final loc = GoRouterState.of(context).uri.path;
    if (loc == '/player') return;
    await context.push('/player');
  }

  /// 会话已认领（currentBook 已设）即可进播放页；章节/音频在播放页缓冲。
  Future<void> _waitSessionReady(PlayerController player, String bookId) async {
    bool ready() =>
        player.loadError != null || player.currentBook?.id == bookId;
    if (ready()) return;

    final done = Completer<void>();
    void listener() {
      if (ready() && !done.isCompleted) done.complete();
    }

    player.addListener(listener);
    try {
      listener();
      await done.future.timeout(const Duration(seconds: 8));
    } finally {
      player.removeListener(listener);
    }
  }

  /// 点播放即进播放页；章节目录优先用本页已加载列表，音频在播放页缓冲。
  Future<void> _play({int startIndex = 0}) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final player = ref.read(playerControllerProvider);
      final book = _inShelf
          ? _book
          : _book.copyWith(addedAt: DateTime.now(), updatedAt: DateTime.now());
      final known = _chapters.isNotEmpty ? _chapters : null;
      final playFuture = player.playBook(
        book,
        startIndex: startIndex,
        knownChapters: known,
      );
      try {
        await _waitSessionReady(player, book.id);
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载超时，请重试')),
        );
        return;
      }
      if (!mounted) return;
      if (player.loadError != null || player.currentBook == null) {
        await _afterStartPlay(player);
        await playFuture;
        return;
      }
      await _ensurePlayerRoute();
      await _afterStartPlay(player);
      // 起播/落盘继续后台进行
      unawaited(playFuture);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _continuePlay() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final player = ref.read(playerControllerProvider);
      // 已有本会话且音频已就绪 → 直接进播放页
      if (player.hasSession &&
          player.currentBook?.id == _book.id &&
          player.player.audioSource != null) {
        await _ensurePlayerRoute();
        return;
      }
      // 刷新书架记录，拿到最新 lastPlayChapterId
      final fresh = await ref.read(bookRepositoryProvider).get(_book.id);
      if (fresh != null && mounted) {
        setState(() {
          _book = fresh;
          _inShelf = true;
        });
      }
      final target = fresh ?? _book;
      final known = _chapters.isNotEmpty ? _chapters : null;
      final playFuture =
          player.continueBook(target, knownChapters: known);
      try {
        await _waitSessionReady(player, target.id);
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载超时，请重试')),
        );
        return;
      }
      if (!mounted) return;
      if (player.loadError != null || player.currentBook == null) {
        await _afterStartPlay(player);
        await playFuture;
        return;
      }
      await _ensurePlayerRoute();
      await _afterStartPlay(player);
      unawaited(playFuture);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _download(Chapter chapter) async {
    final service = ref.read(downloadServiceProvider);
    // 地址解析交给 DownloadService.urlResolver，避免 UI 阻塞
    final msg = await service.start(_book, chapter);
    if (msg.isNotEmpty) _toast(msg);
  }

  int _downloadAnchorIndex() {
    final player = ref.read(playerControllerProvider);
    if (player.currentBook?.id == _book.id && player.chapters.isNotEmpty) {
      return player.currentIndex.clamp(0, _chapters.length - 1);
    }
    if (_book.lastPlayChapterId != null) {
      final idx =
          _chapters.indexWhere((c) => c.id == _book.lastPlayChapterId);
      if (idx >= 0) return idx;
    }
    return 0;
  }

  Future<void> _openDownloadRange() async {
    if (_chapters.isEmpty) return;
    await DownloadRangeSheet.show(
      context,
      book: _book,
      chapters: _chapters,
      currentIndex: _downloadAnchorIndex(),
    );
  }

  Future<void> _showSkipSheet() async {
    final result = await SkipConfigSheet.show(
      context,
      intro: _book.skipIntro,
      outro: _book.skipOutro,
      title: '片头 / 片尾跳过（仅本书）',
    );
    if (result == null) return;
    final updated = _book.copyWith(skipIntro: result.$1, skipOutro: result.$2);
    setState(() => _book = updated);
    final repo = ref.read(bookRepositoryProvider);
    final existing = await repo.get(updated.id);
    if (existing != null) {
      await repo.upsert(existing.copyWith(
        skipIntro: updated.skipIntro,
        skipOutro: updated.skipOutro,
        updatedAt: DateTime.now(),
      ));
    }
    final player = ref.read(playerControllerProvider);
    if (player.currentBook?.id == updated.id) {
      await player.updateSkipForCurrentBook(result.$1, result.$2);
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _refreshMeta() async {
    await _loadChapters(forceRefresh: true);
    if (!mounted) return;
    if (_error != null) {
      _toast('刷新失败：$_error');
    } else {
      _toast('信息已刷新');
    }
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新章节'),
              onTap: () {
                Navigator.pop(ctx);
                _refreshMeta();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: const Text('片头片尾'),
              onTap: () {
                Navigator.pop(ctx);
                _showSkipSheet();
              },
            ),
            ListTile(
              leading: Icon(_inShelf ? Icons.bookmark_remove : Icons.bookmark_add),
              title: Text(_inShelf ? '移出书架' : '加入书架'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleShelf();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadServiceProvider);
    final player = ref.watch(playerControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentChapterId =
        player.currentBook?.id == _book.id ? player.currentChapter?.id : null;
    final sourceLabel = _source?.name ?? _book.sourceId;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left, size: 28),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _refreshMeta,
                    icon: const Icon(Icons.refresh, size: 22),
                  ),
                  IconButton(
                    tooltip: '更多',
                    onPressed: _showMore,
                    icon: const Icon(Icons.more_horiz, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BookCover(
                                url: _book.coverUrl,
                                width: 112,
                                height: 144,
                                radius: 8,
                                softShadow: true,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _book.title,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 17,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${_book.author ?? '佚名'} · $sourceLabel',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (_book.description != null &&
                                          _book.description!.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _book.description!,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _chapters.isEmpty || _starting
                                      ? null
                                      : _continuePlay,
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        BrandColors.of(context).accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: _starting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.play_arrow, size: 20),
                                  label: Text(
                                    _starting
                                        ? '准备中…'
                                        : (_canResume ? '继续收听' : '开始播放'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _IconBtn(
                                icon: _inShelf
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                color: _inShelf ? scheme.secondary : null,
                                onTap: _toggleShelf,
                              ),
                              const SizedBox(width: 8),
                              _IconBtn(
                                icon: Icons.download_outlined,
                                onTap:
                                    _chapters.isEmpty ? null : _openDownloadRange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  if (_loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && _chapters.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ProtoEmpty(
                        icon: Icons.cloud_off,
                        title: _error!,
                        action: FilledButton.tonal(
                          onPressed: _loadChapters,
                          child: const Text('重试'),
                        ),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Text(
                              '章节 · ${_chapters.length}',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _showSkipSheet,
                              child: Text(
                                '片头片尾',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final ch = _chapters[i];
                            return _chapterRow(
                              theme,
                              ch,
                              downloads.taskForChapter(ch.id),
                              isCurrent: currentChapterId == ch.id,
                            );
                          },
                          childCount: _chapters.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chapterRow(
    ThemeData theme,
    Chapter chapter,
    DownloadTask? task, {
    required bool isCurrent,
  }) {
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    return InkWell(
      onTap: _starting ? null : () => _play(startIndex: chapter.index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? brand.accentSoft : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${chapter.index + 1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isCurrent ? brand.accent : scheme.onSurfaceVariant,
                  fontWeight: isCurrent ? FontWeight.w600 : null,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                      color: isCurrent ? brand.accent : null,
                    ),
                  ),
                  if (chapter.duration != null && chapter.duration! > 0)
                    Text(
                      AudioUtils.formatSeconds(chapter.duration!.toDouble()),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            _dlIcon(task, chapter),
          ],
        ),
      ),
    );
  }

  Widget _dlIcon(DownloadTask? task, Chapter chapter) {
    if (task == null) {
      return IconButton(
        icon: const Icon(Icons.download_outlined, size: 20),
        onPressed: () => _download(chapter),
      );
    }
    switch (task.status) {
      case DownloadStatus.completed:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.download_done, size: 20, color: AppColors.forest),
        );
      case DownloadStatus.downloading:
      case DownloadStatus.pending:
        return Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: task.progress > 0 ? task.progress / 100 : null,
              strokeWidth: 2,
            ),
          ),
        );
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () async {
            final msg =
                await ref.read(downloadServiceProvider).resume(task.id);
            if (msg != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg)),
              );
            }
          },
        );
    }
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const _IconBtn({required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 48,
          child: Icon(icon, size: 22, color: color ?? scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
