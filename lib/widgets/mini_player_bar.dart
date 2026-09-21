import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/player_providers.dart';
import '../providers/source_providers.dart';
import '../theme/app_theme.dart';
import 'book_cover.dart';

/// 迷你播放条 — 悬浮圆角卡片，贴在 Dock 上方
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  static const _radius = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    if (!player.hasSession) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final book = player.currentBook!;
    final chapter = player.currentChapter;
    final progress = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final speedLabel =
        '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 0 : 1)}x';

    final sources = ref.watch(sourcesControllerProvider).sources;
    String sourceName = '播放中';
    for (final s in sources) {
      if (s.id == book.sourceId) {
        sourceName = s.name;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: () => context.push('/player'),
          child: SizedBox(
            height: 56,
            child: Stack(
              children: [
                // 进度条贴顶，左右内缩避开圆角，避免「比圆角还长」
                Positioned(
                  left: _radius * 0.55,
                  right: _radius * 0.55,
                  top: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: scheme.outlineVariant.withValues(alpha: 0.45),
                      color: brand.accent,
                    ),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: BookCover(
                        url: book.coverUrl,
                        width: 40,
                        height: 40,
                        radius: 6,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chapter != null
                                  ? '${chapter.title} · ${book.title}'
                                  : book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              player.playbackError != null
                                  ? player.playbackError!
                                  : '$speedLabel · $sourceName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: player.playbackError != null
                                    ? scheme.error
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 24,
                        color: brand.accent,
                      ),
                      tooltip: player.playbackError != null ? '重试播放' : null,
                      onPressed: player.togglePlay,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: () => player.clearSession(),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
