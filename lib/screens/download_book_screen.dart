import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../models/download_task.dart';
import '../providers/app_providers.dart';
import '../providers/download_providers.dart';
import '../providers/player_providers.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import '../utils/audio_utils.dart';
import '../widgets/proto_widgets.dart';

enum _ChFilter { all, active, fail, done }

/// 下载二级页 — 单本书章节任务
class DownloadBookScreen extends ConsumerStatefulWidget {
  final String bookId;

  const DownloadBookScreen({super.key, required this.bookId});

  @override
  ConsumerState<DownloadBookScreen> createState() => _DownloadBookScreenState();
}

class _DownloadBookScreenState extends ConsumerState<DownloadBookScreen> {
  _ChFilter _filter = _ChFilter.all;
  Book? _book;
  bool _metaLoaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadBook);
  }

  Future<void> _loadBook() async {
    final book = await ref.read(bookRepositoryProvider).get(widget.bookId);
    if (mounted) {
      setState(() {
        _book = book;
        _metaLoaded = true;
      });
    }
  }

  bool _match(DownloadTask t) {
    switch (_filter) {
      case _ChFilter.all:
        return true;
      case _ChFilter.active:
        return t.isActive || t.status == DownloadStatus.paused;
      case _ChFilter.fail:
        return t.status == DownloadStatus.failed;
      case _ChFilter.done:
        return t.status == DownloadStatus.completed;
    }
  }

  Future<void> _headerAction(List<DownloadTask> tasks) async {
    final svc = ref.read(downloadServiceProvider);
    if (_book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书籍不在书架，请从搜书重新打开')),
      );
      return;
    }
    final hasActive = tasks.any((t) => t.isActive);
    if (hasActive) {
      svc.pauseBook(widget.bookId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已暂停本书下载')),
      );
      return;
    }
    final msg = await svc.resumeBook(widget.bookId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? '已继续本书下载')),
    );
  }

  Future<void> _play(DownloadTask task) async {
    final repo = ref.read(bookRepositoryProvider);
    final book = _book ?? await repo.get(task.bookId);
    if (book == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('《${task.bookTitle}》不在书架，无法播放')),
      );
      return;
    }
    final chapters = await repo.getChapters(book.id);
    final idx = chapters.indexWhere((c) => c.id == task.chapterId);
    if (idx < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到章节，请先打开详情刷新目录')),
      );
      return;
    }
    final player = ref.read(playerControllerProvider);
    await player.playBook(book, startIndex: idx);
    if (!mounted) return;
    if (player.loadError != null || player.currentBook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(player.loadError ?? '起播失败')),
      );
      return;
    }
    await context.push('/player');
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(downloadServiceProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final tasks = service.tasksForBook(widget.bookId);
    final title =
        tasks.isNotEmpty ? tasks.first.bookTitle : (_book?.title ?? '下载');
    final group = DownloadBookGroup(
      bookId: widget.bookId,
      bookTitle: title,
      tasks: tasks,
    );
    final filtered = tasks.where(_match).toList();
    final hasActive = group.hasActive;
    final allPaused = group.paused > 0 && !hasActive;
    final offShelf = _metaLoaded && _book == null;

    String actionLabel;
    if (offShelf) {
      actionLabel = '加入书架';
    } else if (hasActive) {
      actionLabel = '暂停';
    } else if (allPaused || group.hasFailed) {
      actionLabel = '继续';
    } else {
      actionLabel = '暂停';
    }

    final bannerParts = <InlineSpan>[
      TextSpan(
        text:
            '${group.done} / ${group.total} 章 · ${AudioUtils.formatBytes(group.bytes)}',
        style: theme.textTheme.bodyMedium,
      ),
    ];
    if (group.active > 0) {
      bannerParts.add(TextSpan(
        text: ' · ${group.active} 下载中',
        style: theme.textTheme.bodyMedium?.copyWith(color: brand.accent),
      ));
    }
    if (group.failed > 0) {
      bannerParts.add(TextSpan(
        text: ' · ${group.failed} 失败',
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
      ));
    }
    if (allPaused) {
      bannerParts.add(TextSpan(
        text: ' · 已暂停',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ));
    }
    if (offShelf) {
      bannerParts.add(TextSpan(
        text: ' · 不在书架。加入后可从详情续听。',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: tasks.isEmpty
                        ? null
                        : () => _headerAction(tasks),
                    child: Text(
                      actionLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: brand.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (tasks.isEmpty)
              const Expanded(
                child: ProtoEmpty(
                  icon: Icons.cloud_download_outlined,
                  title: '本书暂无下载任务',
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    ProtoCard(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Text.rich(TextSpan(children: bannerParts)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final e in [
                              (_ChFilter.all, '全部'),
                              (_ChFilter.active, '进行中'),
                              (_ChFilter.fail, '失败'),
                              (_ChFilter.done, '已完成'),
                            ]) ...[
                              ProtoChip(
                                label: e.$2,
                                selected: _filter == e.$1,
                                onTap: () =>
                                    setState(() => _filter = e.$1),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                    ProtoCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                color: scheme.outlineVariant,
                              ),
                            _chapterRow(theme, service, filtered[i]),
                          ],
                        ],
                      ),
                    ),
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
    DownloadService service,
    DownloadTask task,
  ) {
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    String sub;
    Color? subColor;
    switch (task.status) {
      case DownloadStatus.pending:
        sub = '等待中';
      case DownloadStatus.downloading:
        sub =
            '下载中 ${task.progress}% · ${AudioUtils.formatBytes(task.downloadedBytes)}';
        subColor = brand.accent;
      case DownloadStatus.paused:
        sub = task.progress > 0 ? '已暂停 · ${task.progress}%' : '已暂停';
      case DownloadStatus.completed:
        sub =
            '已完成 · ${AudioUtils.formatBytes(task.totalBytes ?? task.downloadedBytes)} · 可离线播';
      case DownloadStatus.failed:
        sub = '失败 · ${task.error ?? '网络中断'}';
        subColor = scheme.error;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subColor ?? scheme.onSurfaceVariant,
                  ),
                ),
                if (task.status == DownloadStatus.downloading ||
                    (task.status == DownloadStatus.paused &&
                        task.progress > 0)) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (task.progress / 100).clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: scheme.outlineVariant,
                      color: brand.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (task.status == DownloadStatus.completed)
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 22),
              onPressed: () => _play(task),
            ),
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.pending)
            IconButton(
              icon: const Icon(Icons.pause, size: 20),
              onPressed: () => service.pause(task.id),
            ),
          if (task.status == DownloadStatus.paused)
            IconButton(
              icon: Icon(Icons.play_arrow, size: 22, color: brand.accent),
              onPressed: () async {
                final msg = await service.resume(task.id);
                if (msg != null && mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          if (task.status == DownloadStatus.failed)
            IconButton(
              icon: Icon(Icons.refresh, size: 20, color: brand.accent),
              onPressed: () async {
                final msg = await service.resume(task.id);
                if (msg != null && mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          if (task.status == DownloadStatus.completed)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                await service.delete(task.id);
                if (mounted &&
                    ref
                        .read(downloadServiceProvider)
                        .tasksForBook(widget.bookId)
                        .isEmpty) {
                  context.pop();
                }
              },
            ),
        ],
      ),
    );
  }
}
