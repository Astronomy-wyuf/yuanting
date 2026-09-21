import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bookshelf_providers.dart';
import '../providers/player_providers.dart';
import '../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../utils/audio_utils.dart';
import '../widgets/book_cover.dart';
import '../widgets/player_sheets.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/skip_config_sheet.dart';

/// 全屏播放器 — 对齐原型：下拉关闭 / 大封面 / 章节·书架·跳过 / 主控条
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (player.currentBook == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                ),
              ),
              const Expanded(
                child: ProtoEmpty(
                  icon: Icons.music_off_outlined,
                  title: '暂无播放',
                  subtitle: '从书架或搜书页选一本书开始',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final book = player.currentBook!;
    final chapter = player.currentChapter;
    final brand = BrandColors.of(context);
    final shelf = ref.watch(bookshelfControllerProvider);
    final inShelf = shelf.books.any((b) => b.id == book.id);
    final speedLabel =
        '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 0 : 1)}x';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: scheme.surface),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.55),
                  radius: 1.05,
                  colors: [
                    brand.cover1.withValues(alpha: 0.85),
                    brand.accentSoft.withValues(alpha: 0.45),
                    scheme.surface.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                      ),
                      Expanded(
                        child: Text(
                          '正在播放',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showMore(context, player),
                        icon: const Icon(Icons.more_horiz, size: 22),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 标题+工具大约占 110；封面按剩余高度缩放，绝不撑破
                      final availH = constraints.maxHeight;
                      final availW = constraints.maxWidth - 48;
                      final maxCoverH = (availH * 0.58).clamp(80.0, 260.0);
                      var coverW = availW.clamp(80.0, 200.0);
                      var coverH = coverW * 4 / 3;
                      if (coverH > maxCoverH) {
                        coverH = maxCoverH;
                        coverW = coverH * 3 / 4;
                      }
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: SizedBox(
                          height: availH,
                          child: Column(
                            children: [
                              const Spacer(flex: 2),
                              BookCover(
                                url: book.coverUrl,
                                width: coverW,
                                height: coverH,
                                radius: 12,
                                softShadow: coverH > 140,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                chapter?.title ?? '加载中…',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${book.title}${book.author != null ? ' · ${book.author}' : ''}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _SideTool(
                                    icon: Icons.list,
                                    label: '章节',
                                    onTap: () =>
                                        PlayerChapterSheet.show(context, player),
                                  ),
                                  const SizedBox(width: 24),
                                  _SideTool(
                                    icon: inShelf
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    label: inShelf ? '已收藏' : '书架',
                                    onTap: () =>
                                        _toggleShelf(context, ref, player),
                                  ),
                                  const SizedBox(width: 24),
                                  _SideTool(
                                    icon: Icons.content_cut,
                                    label: '跳过',
                                    onTap: () => _showSkip(context, player),
                                  ),
                                ],
                              ),
                              const Spacer(flex: 3),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (player.loadError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      player.loadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  )
                else if (player.playbackError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          player.playbackError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: player.retryPlayback,
                          child: const Text('重新获取并播放'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: _SeekBar(player: player),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 360,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _Ctrl(
                            label: speedLabel,
                            onTap: () => PlayerSpeedSheet.show(context, player),
                          ),
                          _Ctrl(
                            icon: Icons.replay_10,
                            onTap: () => player.seek(
                              player.position - const Duration(seconds: 10),
                            ),
                          ),
                          _Ctrl(
                            icon: Icons.skip_previous,
                            onTap: player.hasPrevious ? player.previous : null,
                          ),
                          Material(
                            color: brand.accent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: player.togglePlay,
                              child: SizedBox(
                                width: 64,
                                height: 64,
                                child: Center(
                                  child: player.isPlaying
                                      ? (player.isBuffering
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.pause,
                                              size: 28, color: Colors.white))
                                      : const Icon(Icons.play_arrow,
                                          size: 32, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                          _Ctrl(
                            icon: Icons.skip_next,
                            onTap: player.hasNext ? player.next : null,
                          ),
                          _Ctrl(
                            icon: Icons.forward_30,
                            onTap: () => player.seek(
                              player.position + const Duration(seconds: 30),
                            ),
                          ),
                          _Ctrl(
                            icon: Icons.bedtime_outlined,
                            onTap: () => PlayerSleepSheet.show(context, player),
                            active: player.sleepTimer.mode != SleepTimerMode.off,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (player.loading)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleShelf(
    BuildContext context,
    WidgetRef ref,
    PlayerController player,
  ) async {
    final book = player.currentBook;
    if (book == null) return;
    final shelf = ref.read(bookshelfControllerProvider);
    final inShelf = shelf.books.any((b) => b.id == book.id);
    if (inShelf) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('移出书架'),
          content: Text('将《${book.title}》移出书架？收听进度将一并删除。'),
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

  void _showMore(BuildContext context, PlayerController player) {
    PlayerMoreSheet.show(
      context,
      player: player,
      onSpeed: () => PlayerSpeedSheet.show(context, player),
      onSleep: () => PlayerSleepSheet.show(context, player),
      onSkip: () => _showSkip(context, player),
      onClosePlaylist: () {
        player.clearSession();
        Navigator.of(context).maybePop();
      },
    );
  }

  Future<void> _showSkip(
      BuildContext context, PlayerController player) async {
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

class _SeekBar extends StatefulWidget {
  final PlayerController player;

  const _SeekBar({required this.player});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final hasDuration = player.duration > Duration.zero;
    final maxMs =
        hasDuration ? player.duration.inMilliseconds.toDouble() : 1.0;
    final posMs = hasDuration
        ? player.position.inMilliseconds.clamp(0, maxMs.round()).toDouble()
        : 0.0;
    final displayMs = _dragMs ?? posMs;
    final displayPos = Duration(milliseconds: displayMs.round());
    final displayDur =
        hasDuration ? player.duration : Duration.zero;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: brand.accent,
            inactiveTrackColor: scheme.outlineVariant,
            thumbColor: brand.accent,
            disabledActiveTrackColor: scheme.outlineVariant,
            disabledInactiveTrackColor: scheme.outlineVariant,
          ),
          child: Slider(
            value: displayMs.clamp(0, maxMs),
            max: maxMs,
            onChanged: hasDuration
                ? (v) => setState(() => _dragMs = v)
                : null,
            onChangeEnd: hasDuration
                ? (v) {
                    setState(() => _dragMs = null);
                    player.seek(Duration(milliseconds: v.round()));
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AudioUtils.formatDuration(displayPos),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                hasDuration
                    ? AudioUtils.formatDuration(displayDur)
                    : '--:--',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SideTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SideTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mute = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            Icon(icon, size: 20, color: mute),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Ctrl extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final bool active;

  const _Ctrl({
    this.icon,
    this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color = !enabled
        ? scheme.onSurface.withValues(alpha: 0.28)
        : active
            ? scheme.secondary
            : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22, color: color)
              : Text(
                  label ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
        ),
      ),
    );
  }
}
