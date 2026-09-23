import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bookshelf_providers.dart';
import '../providers/player_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/player/player_backdrop.dart';
import '../widgets/player/player_cover_stage.dart';
import '../widgets/player/player_seek_bar.dart';
import '../widgets/player/player_transport.dart';
import '../widgets/player_sheets.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/skip_config_sheet.dart';

/// 全屏播放器 — 封面舞台 / 下拉关闭 / Hero / 细粒度刷新
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  double _dragY = 0;
  AnimationController? _bounce;

  @override
  void dispose() {
    _bounce?.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final dy = d.primaryDelta ?? 0;
    if (dy == 0) return;
    setState(() => _dragY = (_dragY + dy).clamp(0.0, 420.0));
  }

  Future<void> _snapDragBack() async {
    final start = _dragY;
    if (start <= 0) return;
    _bounce?.dispose();
    final anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _bounce = anim;
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    void tick() {
      if (!mounted) return;
      setState(() => _dragY = start * (1 - curved.value));
    }

    anim.addListener(tick);
    try {
      await anim.forward();
    } finally {
      anim.removeListener(tick);
      if (identical(_bounce, anim)) {
        anim.dispose();
        _bounce = null;
      }
      if (mounted) setState(() => _dragY = 0);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragY > 110 || v > 900) {
      Navigator.of(context).maybePop();
      return;
    }
    _snapDragBack();
  }

  @override
  Widget build(BuildContext context) {
    final bookId = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.id),
    );
    final loading = ref.watch(
      playerControllerProvider.select((p) => p.loading),
    );
    final chapterCount = ref.watch(
      playerControllerProvider.select((p) => p.chapters.length),
    );

    if (bookId == null) {
      return _PlayerShell(
        dragY: 0,
        child: _EmptyOrBoot(loading: loading),
      );
    }

    if (loading && chapterCount == 0) {
      return _PlayerShell(
        dragY: _dragY,
        child: _PreparingBody(
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
        ),
      );
    }

    final t = (_dragY / 320).clamp(0.0, 1.0);
    return _PlayerShell(
      dragY: _dragY,
      scale: 1.0 - 0.06 * t,
      borderRadius: 18.0 * t,
      opacity: 1.0 - 0.35 * t,
      child: _PlayerBody(
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
      ),
    );
  }
}

class _PlayerShell extends StatelessWidget {
  final double dragY;
  final double scale;
  final double borderRadius;
  final double opacity;
  final Widget child;

  const _PlayerShell({
    required this.dragY,
    required this.child,
    this.scale = 1,
    this.borderRadius = 0,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, dragY),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(borderRadius),
              ),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyOrBoot extends StatelessWidget {
  final bool loading;

  const _EmptyOrBoot({required this.loading});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ProtoEmpty(
                    icon: Icons.music_off_outlined,
                    title: '暂无播放',
                    subtitle: '从书架或搜书页选一本书开始',
                    action: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PreparingBody extends ConsumerWidget {
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  const _PreparingBody({
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(
      playerControllerProvider.select((p) => p.currentBook),
    )!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        PlayerBackdrop(coverUrl: book.coverUrl),
        SafeArea(
          child: Column(
            children: [
              _TopBar(
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BookCover(
                          url: book.coverUrl,
                          width: 160,
                          height: 160,
                          radius: 80,
                          softShadow: true,
                          fadeIn: Duration.zero,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          book.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: BrandColors.of(context).accent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '正在准备播放…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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

class _PlayerBody extends ConsumerWidget {
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  const _PlayerBody({
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverUrl = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.coverUrl),
    );
    final bookTitle = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.title),
    )!;
    final bookAuthor = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.author),
    );
    final chapterTitle = ref.watch(
      playerControllerProvider.select((p) => p.currentChapter?.title),
    );
    final chapterId = ref.watch(
      playerControllerProvider.select((p) => p.currentChapter?.id),
    );
    final loadError = ref.watch(
      playerControllerProvider.select((p) => p.loadError),
    );
    final playbackError = ref.watch(
      playerControllerProvider.select((p) => p.playbackError),
    );
    final player = ref.read(playerControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 独立层 + 隔离重绘：播停/进度不再牵动模糊背景
        const RepaintBoundary(child: _StableBackdrop()),
        SafeArea(
          child: Column(
            children: [
              _TopBar(
                onMore: () => _showMore(context, ref),
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availH = constraints.maxHeight;
                    final availW = constraints.maxWidth - 48;
                    // 矮屏 / 有错误条时收紧封面，避免底部溢出
                    final maxCoverH = (availH * 0.55).clamp(100.0, 260.0);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                      child: Column(
                        children: [
                          const Spacer(flex: 1),
                          PlayerCoverStage(
                            coverUrl: coverUrl,
                            maxWidth: availW,
                            maxHeight: maxCoverH,
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, anim) {
                              final offset = Tween<Offset>(
                                begin: const Offset(0, 0.12),
                                end: Offset.zero,
                              ).animate(anim);
                              return FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: offset,
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              chapterTitle ?? '加载中…',
                              key: ValueKey(chapterId ?? 'none'),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              bookTitle,
                              if (bookAuthor != null &&
                                  bookAuthor.trim().isNotEmpty)
                                bookAuthor.trim(),
                            ].join(' · '),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(flex: 2),
                        ],
                      ),
                    );
                  },
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: (loadError != null || playbackError != null)
                    ? _PlaybackErrorBanner(
                        message: loadError ?? playbackError!,
                        onRetry:
                            playbackError != null ? player.retryPlayback : null,
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
              PlayerSecondaryBar(
                onChapters: () => PlayerChapterSheet.show(context, player),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: PlayerSeekBar(),
              ),
              const SizedBox(height: 2),
              const PlayerTransport(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  void _showMore(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerControllerProvider);
    PlayerMoreSheet.show(
      context,
      player: player,
      onSpeed: () => PlayerSpeedSheet.show(context, player),
      onSleep: () => PlayerSleepSheet.show(context, player),
      onSkip: () => _showSkip(context, ref),
      onClosePlaylist: () {
        Navigator.of(context).maybePop().whenComplete(() {
          player.clearSession();
        });
      },
    );
  }

  Future<void> _showSkip(BuildContext context, WidgetRef ref) async {
    final player = ref.read(playerControllerProvider);
    final result = await SkipConfigSheet.show(
      context,
      intro: player.currentBook?.skipIntro,
      outro: player.currentBook?.skipOutro,
      title: '片头 / 片尾跳过',
    );
    if (result == null) return;
    await player.updateSkipForCurrentBook(result.$1, result.$2);
  }
}

/// 仅订阅封面 URL，进度/播停通知不会重建模糊背景
class _StableBackdrop extends ConsumerWidget {
  const _StableBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverUrl = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.coverUrl),
    );
    return PlayerBackdrop(coverUrl: coverUrl);
  }
}

/// 紧凑错误条：友好文案 + 限高，避免 Dio 长栈把底部撑爆
class _PlaybackErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _PlaybackErrorBanner({
    required this.message,
    this.onRetry,
  });

  static String _friendly(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('timeout') || m.contains('timed out')) {
      return '网络超时，请检查网络后重试';
    }
    if (m.contains('socket') ||
        m.contains('connection') ||
        m.contains('network')) {
      return '网络异常，请稍后重试';
    }
    if (m.contains('404') || m.contains('not found')) {
      return '音频地址失效，请重试获取';
    }
    // 去掉 DioException 包装，截断过长原文
    var s = raw
        .replaceFirst(RegExp(r'^播放失败:\s*'), '')
        .replaceFirst(RegExp(r'^DioException\s*\[[^\]]*\]:\s*'), '')
        .trim();
    if (s.length > 48) s = '${s.substring(0, 48)}…';
    return s.isEmpty ? '播放失败，请重试' : s;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _friendly(message),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.error, fontSize: 13, height: 1.3),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: const Text('重新获取并播放'),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final VoidCallback? onMore;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  const _TopBar({
    this.onMore,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bookId = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.id),
    );
    final inShelf = ref.watch(
      bookshelfControllerProvider.select(
        (s) => bookId != null && s.books.any((b) => b.id == bookId),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 拖拽指示条居中
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                ),
                const Spacer(),
                if (onMore != null) ...[
                  IconButton(
                    tooltip: inShelf ? '已在书架' : '加入书架',
                    onPressed: () => _toggleShelf(context, ref),
                    icon: Icon(
                      inShelf
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(Icons.more_horiz_rounded, size: 22),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleShelf(BuildContext context, WidgetRef ref) async {
    final player = ref.read(playerControllerProvider);
    final book = player.currentBook;
    if (book == null) return;
    final shelf = ref.read(bookshelfControllerProvider);
    final inShelf = shelf.books.any((b) => b.id == book.id);
    if (inShelf) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('移出书架'),
          content: Text(
            '将《${book.title}》移出书架？\n'
            '不会停止播放；书架进度记录会清除。',
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
      if (ok != true) return;
      await shelf.remove(book.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已移出书架')),
        );
      }
    } else {
      await shelf.addOrUpdate(book);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入书架')),
        );
      }
    }
  }
}
