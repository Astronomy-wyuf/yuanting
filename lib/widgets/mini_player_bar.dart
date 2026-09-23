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
    final hasSession = ref.watch(
      playerControllerProvider.select((p) => p.hasSession),
    );
    if (!hasSession) return const SizedBox.shrink();

    final coverUrl = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.coverUrl),
    );
    final title = ref.watch(
      playerControllerProvider.select((p) => p.currentBook?.title),
    )!;
    final chapterTitle = ref.watch(
      playerControllerProvider.select((p) => p.currentChapter?.title),
    );
    final sourceId = ref.watch(
      playerControllerProvider.select((p) => p.currentBook!.sourceId),
    );
    final isPlaying = ref.watch(
      playerControllerProvider.select((p) => p.isPlaying),
    );
    final playbackError = ref.watch(
      playerControllerProvider.select((p) => p.playbackError),
    );
    final speed = ref.watch(
      playerControllerProvider.select((p) => p.speed),
    );
    final progress = ref.watch(
      playerControllerProvider.select((p) {
        final d = p.duration.inMilliseconds;
        if (d <= 0) return 0.0;
        return (p.position.inMilliseconds / d).clamp(0.0, 1.0);
      }),
    );

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);
    final speedLabel =
        '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 1)}x';

    final sources = ref.watch(sourcesControllerProvider).sources;
    String sourceName = '播放中';
    for (final s in sources) {
      if (s.id == sourceId) {
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
                Positioned(
                  left: _radius * 0.55,
                  right: _radius * 0.55,
                  top: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor:
                          scheme.outlineVariant.withValues(alpha: 0.45),
                      color: brand.accent,
                    ),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    // 不用 Hero：全屏播放页打开时迷你条仍在树内，双 Hero 同 tag 会闪
                    BookCover(
                      url: coverUrl,
                      width: 40,
                      height: 40,
                      radius: 6,
                      fadeIn: Duration.zero,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chapterTitle != null
                                  ? '$chapterTitle · $title'
                                  : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              playbackError ?? '$speedLabel · $sourceName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: playbackError != null
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
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 24,
                        color: brand.accent,
                      ),
                      tooltip: playbackError != null ? '重试播放' : null,
                      onPressed: () =>
                          ref.read(playerControllerProvider).togglePlay(),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          ref.read(playerControllerProvider).clearSession(),
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
