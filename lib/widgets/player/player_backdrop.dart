import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 播放页氛围底：封面虚化 + 品牌色渐变（无重依赖取色）
class PlayerBackdrop extends StatelessWidget {
  final String? coverUrl;
  final Animation<double>? fade;

  const PlayerBackdrop({
    super.key,
    this.coverUrl,
    this.fade,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = BrandColors.of(context);
    final url = coverUrl?.trim();

    Widget layer = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        if (url != null && url.isNotEmpty)
          Opacity(
            opacity: 0.42,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Transform.scale(
                scale: 1.18,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  placeholder: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                brand.accentSoft.withValues(alpha: 0.55),
                scheme.surface.withValues(alpha: 0.72),
                scheme.surface,
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.7),
              radius: 1.15,
              colors: [
                brand.cover1.withValues(alpha: 0.55),
                scheme.surface.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );

    if (fade != null) {
      layer = FadeTransition(opacity: fade!, child: layer);
    }
    return layer;
  }
}
