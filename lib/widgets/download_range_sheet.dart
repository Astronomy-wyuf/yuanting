import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../models/download_task.dart';
import '../providers/download_providers.dart';
import '../providers/settings_providers.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import 'sheet_chrome.dart';

enum DownloadRangeKind { current, ahead, rest, all }

/// 详情页 · 下载范围 + 自动后续 N 章（与设置共用）
class DownloadRangeSheet extends ConsumerStatefulWidget {
  final Book book;
  final List<Chapter> chapters;
  final int currentIndex;

  const DownloadRangeSheet({
    super.key,
    required this.book,
    required this.chapters,
    required this.currentIndex,
  });

  static Future<void> show(
    BuildContext context, {
    required Book book,
    required List<Chapter> chapters,
    required int currentIndex,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DownloadRangeSheet(
        book: book,
        chapters: chapters,
        currentIndex: currentIndex.clamp(0, chapters.isEmpty ? 0 : chapters.length - 1),
      ),
    );
  }

  @override
  ConsumerState<DownloadRangeSheet> createState() => _DownloadRangeSheetState();
}

class _DownloadRangeSheetState extends ConsumerState<DownloadRangeSheet> {
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    _custom = TextEditingController();
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  bool _isDoneOrQueued(DownloadTask? t) {
    if (t == null) return false;
    return t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.pending ||
        t.status == DownloadStatus.downloading;
  }

  int _pendingCount(Iterable<Chapter> list) {
    final svc = ref.read(downloadServiceProvider);
    var n = 0;
    for (final ch in list) {
      if (!_isDoneOrQueued(svc.taskForChapter(ch.id))) n++;
    }
    return n;
  }

  List<Chapter> _chaptersFor(DownloadRangeKind kind) {
    final chs = widget.chapters;
    if (chs.isEmpty) return const [];
    final i = widget.currentIndex.clamp(0, chs.length - 1);
    final ahead = ref.read(settingsControllerProvider).autoDownloadAhead;
    switch (kind) {
      case DownloadRangeKind.current:
        return [chs[i]];
      case DownloadRangeKind.ahead:
        if (ahead <= 0) return const [];
        final end = (i + 1 + ahead).clamp(0, chs.length);
        return chs.sublist(i + 1, end);
      case DownloadRangeKind.rest:
        return chs.sublist(i);
      case DownloadRangeKind.all:
        return List<Chapter>.from(chs);
    }
  }

  Future<void> _setAhead(int n, {bool keepOpen = true}) async {
    await ref.read(settingsControllerProvider).setAutoDownloadAhead(n);
    if (!mounted) return;
    setState(() {});
    final msg = n == 0 ? '已关闭自动下载' : '播放时向后补齐 $n 章';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (!keepOpen) Navigator.pop(context);
  }

  Future<void> _queue(DownloadRangeKind kind) async {
    final settings = ref.read(settingsControllerProvider);
    if (kind == DownloadRangeKind.ahead && settings.autoDownloadAhead == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自动下载已关闭，请先设置后续章数')),
      );
      return;
    }
    final targets = _chaptersFor(kind);
    final svc = ref.read(downloadServiceProvider);
    final result = await svc.startMany(widget.book, targets);
    if (!mounted) return;
    Navigator.pop(context);

    String msg;
    if (result.error != null && result.added == 0) {
      msg = result.error!;
    } else {
      msg = switch (kind) {
        DownloadRangeKind.current => result.added == 0
            ? '当前章已在下载，未重复加入'
            : '已加入当前章',
        DownloadRangeKind.ahead =>
          '已加入后续 ${settings.autoDownloadAhead} 章（跳过已完成）',
        DownloadRangeKind.rest => '已从当前章排队到结尾（跳过已完成）',
        DownloadRangeKind.all => '已加入全部未下载章节',
      };
      if (result.error != null) {
        msg = '$msg · ${result.error}';
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            if (context.mounted) context.go('/downloads');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsControllerProvider);
    final n = settings.autoDownloadAhead;
    final chs = widget.chapters;
    final i = widget.currentIndex.clamp(0, chs.isEmpty ? 0 : chs.length - 1);
    final curNo = chs.isEmpty ? 0 : i + 1;
    final total = chs.length;
    final done = () {
      final svc = ref.watch(downloadServiceProvider);
      return chs.where((c) {
        final t = svc.taskForChapter(c.id);
        return t?.status == DownloadStatus.completed;
      }).length;
    }();

    final curQueued = chs.isEmpty
        ? false
        : _isDoneOrQueued(
            ref.watch(downloadServiceProvider).taskForChapter(chs[i].id));
    final restPending = _pendingCount(_chaptersFor(DownloadRangeKind.rest));

    return AppSheetScaffold(
      eyebrow: 'DOWNLOAD',
      title: '下载《${widget.book.title}》',
      subtitle: '从第 $curNo 章起算 · 已完成或已在队列的会跳过',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RangeBtn(
            title: '当前章',
            subtitle: curQueued
                ? '第 $curNo 章 · 已在下载，将跳过'
                : '第 $curNo 章',
            primary: false,
            onTap: () => _queue(DownloadRangeKind.current),
          ),
          const SizedBox(height: 8),
          _RangeBtn(
            title: n == 0 ? '后续章（先打开自动下载）' : '后续 $n 章',
            subtitle: n == 0
                ? '请先在下方设置章数'
                : '第 ${curNo + 1} 章起 · 跳过已完成',
            primary: true,
            onTap: () => _queue(DownloadRangeKind.ahead),
          ),
          const SizedBox(height: 8),
          _RangeBtn(
            title: '从当前章到结尾',
            subtitle: '第 $curNo–$total 章 · 未完成约 $restPending 章',
            primary: false,
            onTap: () => _queue(DownloadRangeKind.rest),
          ),
          const SizedBox(height: 8),
          _RangeBtn(
            title: '全部未下载',
            subtitle: '整本 $total 章 · 跳过已完成 $done 章',
            primary: false,
            onTap: () => _queue(DownloadRangeKind.all),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('自动下载后续',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                n == 0 ? '已关闭' : '当前 $n 章',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '只在播放时补齐窗口，暂停或停播不再开新任务。与「后续 N 章」共用。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          AppSheetOptionGrid(
            crossAxisCount: 5,
            childAspectRatio: 1.6,
            children: [
              for (final p in const [0, 1, 3, 5])
                AppSheetChoice(
                  label: p == 0 ? '关' : '$p',
                  selected: n == p,
                  onTap: () => _setAhead(p),
                ),
              AppSheetChoice(
                label: '自定义',
                selected: ![0, 1, 3, 5].contains(n),
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '0 关闭，最多 50',
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    final v = int.tryParse(_custom.text.trim());
                    if (v != null) _setAhead(v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {
                  final v = int.tryParse(_custom.text.trim());
                  if (v != null) {
                    _setAhead(
                      v.clamp(0, AppConstants.maxAutoDownloadAhead),
                    );
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeBtn extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _RangeBtn({
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    return Material(
      color: primary ? brand.accent : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.85)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
