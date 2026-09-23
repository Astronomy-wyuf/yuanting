import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 直角封面 + 纸质渐变占位（杂志裁切感）
class BookCover extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;
  final IconData placeholderIcon;
  final bool softShadow;

  /// 迷你条 ↔ 全屏播放页共享转场
  final Object? heroTag;

  /// 网络图淡入；播放页/迷你条用 0 避免重建闪白
  final Duration fadeIn;

  const BookCover({
    super.key,
    this.url,
    this.width = 56,
    this.height = 78,
    this.radius = 0,
    this.placeholderIcon = Icons.menu_book_outlined,
    this.softShadow = false,
    this.heroTag,
    this.fadeIn = const Duration(milliseconds: 180),
  });

  static Object playerHeroTag(String bookId) => 'player-cover-$bookId';

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            brand.cover1,
            brand.cover2,
            brand.cover3,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Icon(
        placeholderIcon,
        color: Colors.white.withValues(alpha: 0.85),
        size: width * 0.32,
      ),
    );

    Widget child;
    final imageUrl = url?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      child = placeholder;
    } else {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            if (_imageReferer(imageUrl) case final ref?) 'Referer': ref,
          },
          fadeInDuration: fadeIn,
          fadeOutDuration: Duration.zero,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        ),
      );
    }

    if (softShadow) {
      child = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: child,
      );
    }

    if (heroTag == null) return child;
    return Hero(
      tag: heroTag!,
      createRectTween: (begin, end) =>
          MaterialRectArcTween(begin: begin, end: end),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }

  /// 部分 CDN（如 guoguo）强制站点 Referer，否则封面 403。
  static String? _imageReferer(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('guoguo.org.cn') || lower.contains('huantingwang.com')) {
      return 'https://huantingwang.com/';
    }
    try {
      final u = Uri.parse(url);
      if (u.hasScheme && u.host.isNotEmpty) {
        return '${u.scheme}://${u.host}/';
      }
    } catch (_) {}
    return null;
  }
}
