import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/download_task.dart';
import '../providers/app_providers.dart';
import '../providers/download_providers.dart';
import '../providers/player_providers.dart';
import '../providers/settings_providers.dart';
import '../theme/app_theme.dart';
import '../utils/audio_utils.dart';
import '../widgets/book_cover.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/sheet_chrome.dart';

enum _DlFilter { all, active, fail, done }

/// 下载一级页 — 按书分组卡片，对齐原型
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _usedBytes = -1;
  _DlFilter _filter = _DlFilter.all;
  final Map<String, String?> _covers = {};
  final Set<String> _offShelf = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(downloadServiceProvider).load();
      await _refreshUsed();
      await _loadMeta();
    });
  }

  Future<void> _refreshUsed() async {
    final used = await ref.read(downloadServiceProvider).usedBytes();
    if (mounted) setState(() => _usedBytes = used);
  }

  Future<void> _loadMeta() async {
    final groups = ref.read(downloadServiceProvider).bookGroups();
    final repo = ref.read(bookRepositoryProvider);
    for (final g in groups) {
      if (_covers.containsKey(g.bookId)) continue;
      final book = await repo.get(g.bookId);
      _covers[g.bookId] = book?.coverUrl;
      if (book == null) {
        _offShelf.add(g.bookId);
      } else {
        _offShelf.remove(g.bookId);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final service = ref.read(downloadServiceProvider);
    if (service.tasks.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => AppSheetScaffold(
        eyebrow: 'DOWNLOADS',
        title: '清空全部下载？',
        subtitle: '将删除全部任务与本地音频文件，不可恢复。',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认清空'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await service.deleteAll();
      await _refreshUsed();
    }
  }

  bool _matchFilter(DownloadBookGroup g) {
    switch (_filter) {
      case _DlFilter.all:
        return true;
      case _DlFilter.active:
        return g.hasActive || g.paused > 0;
      case _DlFilter.fail:
        return g.hasFailed;
      case _DlFilter.done:
        return g.done > 0 && !g.hasActive && !g.hasFailed && g.paused == 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(downloadServiceProvider);
    final settings = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final groups = service.bookGroups();
    // 元数据滞后一拍时补载
    if (groups.any((g) => !_covers.containsKey(g.bookId))) {
      Future.microtask(_loadMeta);
    }
    final filtered = groups.where(_matchFilter).toList();
    final activeBooks =
        groups.where((g) => g.hasActive || g.paused > 0).length;
    final failBooks = groups.where((g) => g.hasFailed).length;
    final hasMini =
        ref.watch(playerControllerProvider.select((p) => p.hasSession));
    final bottom = protoBottomPad(context, hasMini: hasMini);
    final maxBytes = settings.maxStorageMB * 1024 * 1024;
    final used = _usedBytes < 0 ? 0 : _usedBytes;
    final ratio = maxBytes > 0 ? (used / maxBytes).clamp(0.0, 1.0) : 0.0;

    // 任务完成后刷新占用空间
    ref.listen(downloadServiceProvider, (prev, next) {
      _refreshUsed();
    });

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: ProtoPageTitle(
            '下载',
            actions: [
              if (service.tasks.any((t) => t.isActive))
                TextButton(
                  onPressed: () {
                    service.pauseAll();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已暂停全部进行中任务')),
                    );
                  },
                  child: Text(
                    '全部暂停',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (service.tasks.isNotEmpty)
                TextButton(
                  onPressed: _confirmClearAll,
                  child: Text(
                    '清空',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: service.tasks.isEmpty
              ? ProtoEmpty(
                  icon: Icons.cloud_download_outlined,
                  title: '暂无下载任务',
                  subtitle: '在书籍详情中可逐章或全部下载',
                  action: FilledButton(
                    onPressed: () => context.go('/search'),
                    child: const Text('去搜书'),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                  children: [
                    ProtoCard(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('已用空间',
                                  style: theme.textTheme.bodyMedium),
                              const Spacer(),
                              Text(
                                '${AudioUtils.formatBytes(used)} / ${settings.maxStorageMB >= 1024 && settings.maxStorageMB % 1024 == 0 ? '${settings.maxStorageMB ~/ 1024} GB' : '${settings.maxStorageMB} MB'}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 6,
                              backgroundColor: scheme.outlineVariant,
                              color: brand.accent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '达上限将拦截新下载 · 随任务实时刷新',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ProtoChip(
                              label: '全部',
                              selected: _filter == _DlFilter.all,
                              onTap: () =>
                                  setState(() => _filter = _DlFilter.all),
                            ),
                            const SizedBox(width: 8),
                            ProtoChip(
                              label: activeBooks > 0
                                  ? '进行中 $activeBooks'
                                  : '进行中',
                              selected: _filter == _DlFilter.active,
                              onTap: () =>
                                  setState(() => _filter = _DlFilter.active),
                            ),
                            const SizedBox(width: 8),
                            ProtoChip(
                              label:
                                  failBooks > 0 ? '失败 $failBooks' : '失败',
                              selected: _filter == _DlFilter.fail,
                              onTap: () =>
                                  setState(() => _filter = _DlFilter.fail),
                            ),
                            const SizedBox(width: 8),
                            ProtoChip(
                              label: '已完成',
                              selected: _filter == _DlFilter.done,
                              onTap: () =>
                                  setState(() => _filter = _DlFilter.done),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text(
                            '该筛选下暂无书籍',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final g in filtered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ProtoCard(
                            padding: const EdgeInsets.all(12),
                            onTap: () => context.push(
                              '/download-book/${Uri.encodeComponent(g.bookId)}',
                            ),
                            child: Row(
                              children: [
                                BookCover(
                                  url: _covers[g.bookId],
                                  width: 40,
                                  height: 56,
                                  radius: 8,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        g.bookTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${g.done} / ${g.total} 章 · ${AudioUtils.formatBytes(g.bytes)}'
                                        '${g.paused > 0 && g.active == 0 && !g.hasFailed ? ' · 已暂停' : ''}'
                                        '${_offShelf.contains(g.bookId) && g.active == 0 && g.failed == 0 && g.paused == 0 ? ' · 不在书架' : ''}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (g.hasActive || g.hasFailed) ...[
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              if (g.active > 0)
                                                TextSpan(
                                                  text: '${g.active} 下载中',
                                                  style: TextStyle(
                                                    color: brand.accent,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              if (g.active > 0 &&
                                                  g.failed > 0)
                                                TextSpan(
                                                  text: ' · ',
                                                  style: TextStyle(
                                                    color: scheme
                                                        .onSurfaceVariant,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              if (g.failed > 0)
                                                TextSpan(
                                                  text: '${g.failed} 失败',
                                                  style: TextStyle(
                                                    color: scheme.error,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: g.progressRatio,
                                          minHeight: 4,
                                          backgroundColor:
                                              scheme.outlineVariant,
                                          color: brand.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
        ),
      ],
    );
  }
}
