import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_providers.dart';
import '../../services/audio_player_service.dart';
import '../../theme/app_theme.dart';
import '../player_sheets.dart';

/// 主控：±秒 / 上下一集 / 播停（带动画）
class PlayerTransport extends ConsumerWidget {
  const PlayerTransport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(
      playerControllerProvider.select((p) => p.isPlaying),
    );
    final buffering = ref.watch(
      playerControllerProvider.select((p) => p.isBuffering),
    );
    final hasPrev = ref.watch(
      playerControllerProvider.select((p) => p.hasPrevious),
    );
    final hasNext = ref.watch(
      playerControllerProvider.select((p) => p.hasNext),
    );
    final brand = BrandColors.of(context);
    final player = ref.read(playerControllerProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IconBtn(
          icon: Icons.replay_10_rounded,
          size: 28,
          onTap: () => player.seek(
            player.position - const Duration(seconds: 10),
          ),
        ),
        const SizedBox(width: 8),
        _IconBtn(
          icon: Icons.skip_previous_rounded,
          size: 36,
          onTap: hasPrev ? player.previous : null,
        ),
        const SizedBox(width: 12),
        _PlayButton(
          playing: isPlaying,
          buffering: buffering,
          color: brand.accent,
          onTap: player.togglePlay,
        ),
        const SizedBox(width: 12),
        _IconBtn(
          icon: Icons.skip_next_rounded,
          size: 36,
          onTap: hasNext ? player.next : null,
        ),
        const SizedBox(width: 8),
        _IconBtn(
          icon: Icons.forward_30_rounded,
          size: 28,
          onTap: () => player.seek(
            player.position + const Duration(seconds: 30),
          ),
        ),
      ],
    );
  }
}

/// 次要操作：倍速 · 章节 · 睡眠（标题与进度之间，三等分更舒展）
class PlayerSecondaryBar extends ConsumerWidget {
  final VoidCallback onChapters;

  const PlayerSecondaryBar({super.key, required this.onChapters});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playerControllerProvider.select((p) => p.speed));
    final sleepOn = ref.watch(
      playerControllerProvider.select(
        (p) => p.sleepTimer.mode != SleepTimerMode.off,
      ),
    );
    final player = ref.read(playerControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final brand = BrandColors.of(context);
    final speedLabel =
        '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 1)}x';

    Widget cell({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) {
      final color = active ? brand.accent : scheme.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          cell(
            icon: Icons.speed_rounded,
            label: speedLabel,
            onTap: () => PlayerSpeedSheet.show(context, player),
          ),
          cell(
            icon: Icons.queue_music_rounded,
            label: '章节',
            onTap: onChapters,
          ),
          cell(
            icon: sleepOn ? Icons.bedtime_rounded : Icons.bedtime_outlined,
            label: '睡眠',
            active: sleepOn,
            onTap: () => PlayerSleepSheet.show(context, player),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final bool buffering;
  final Color color;
  final VoidCallback onTap;

  const _PlayButton({
    required this.playing,
    required this.buffering,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 不用 AnimatedSwitcher：播停/缓冲切换的缩放淡入会被当成整页闪
    final Widget icon;
    if (buffering && !playing) {
      icon = const SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: Colors.white,
        ),
      );
    } else {
      icon = Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: playing ? 34 : 38,
        color: Colors.white,
      );
    }

    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.35),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  const _IconBtn({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      color: enabled
          ? scheme.onSurface
          : scheme.onSurface.withValues(alpha: 0.28),
      icon: Icon(icon),
    );
  }
}
