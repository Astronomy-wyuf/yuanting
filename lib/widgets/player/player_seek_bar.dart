import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/audio_utils.dart';

/// 进度条：仅订阅 position/duration，避免整页随进度重建
class PlayerSeekBar extends ConsumerStatefulWidget {
  const PlayerSeekBar({super.key});

  @override
  ConsumerState<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends ConsumerState<PlayerSeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(
      playerControllerProvider.select((p) => p.position),
    );
    final duration = ref.watch(
      playerControllerProvider.select((p) => p.duration),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);

    final hasDuration = duration > Duration.zero;
    final maxMs = hasDuration ? duration.inMilliseconds.toDouble() : 1.0;
    final posMs = hasDuration
        ? position.inMilliseconds.clamp(0, maxMs.round()).toDouble()
        : 0.0;
    final displayMs = _dragMs ?? posMs;
    final displayPos = Duration(milliseconds: displayMs.round());

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: brand.accent,
            inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.7),
            thumbColor: brand.accent,
            disabledActiveTrackColor: scheme.outlineVariant,
            disabledInactiveTrackColor: scheme.outlineVariant,
          ),
          child: Slider(
            value: displayMs.clamp(0, maxMs),
            max: maxMs,
            onChanged:
                hasDuration ? (v) => setState(() => _dragMs = v) : null,
            onChangeEnd: hasDuration
                ? (v) {
                    setState(() => _dragMs = null);
                    ref
                        .read(playerControllerProvider)
                        .seek(Duration(milliseconds: v.round()));
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AudioUtils.formatDuration(displayPos),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                hasDuration
                    ? AudioUtils.formatDuration(duration)
                    : '--:--',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
