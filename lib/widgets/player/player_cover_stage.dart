import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_providers.dart';
import '../book_cover.dart';

/// 封面舞台：圆形大封面 · 点击播停（无呼吸/无 Hero，避免点播放整页闪）
class PlayerCoverStage extends ConsumerWidget {
  final String? coverUrl;
  final double maxWidth;
  final double maxHeight;

  const PlayerCoverStage({
    super.key,
    required this.coverUrl,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final side = [
      maxWidth,
      maxHeight,
      260.0,
    ].reduce((a, b) => a < b ? a : b).clamp(100.0, 260.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(playerControllerProvider).togglePlay(),
      child: BookCover(
        url: coverUrl,
        width: side,
        height: side,
        radius: side / 2,
        softShadow: true,
        fadeIn: Duration.zero,
      ),
    );
  }
}
