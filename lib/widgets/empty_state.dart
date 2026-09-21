import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 空状态：大号衬线标题 + 朱砂短线，而非圆形图标气泡
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: scheme.secondary),
            const SizedBox(height: 18),
            Container(
              width: 36,
              height: 3,
              color: scheme.secondary,
            ),
            const SizedBox(height: 18),
            Text(title, style: theme.textTheme.displaySmall),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 28),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 页面顶部品牌眉题
class BrandMasthead extends StatelessWidget {
  final String pageTitle;
  final String? eyebrow;
  final List<Widget>? actions;

  const BrandMasthead({
    super.key,
    required this.pageTitle,
    this.eyebrow,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (eyebrow ?? AppTheme.brandName).toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(pageTitle, style: theme.textTheme.displaySmall),
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// 纸纹背景：斜向淡色块，打破单色平面
class PaperAtmosphere extends StatelessWidget {
  final Widget child;

  const PaperAtmosphere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        AppColors.night,
                        AppColors.nightLift,
                        const Color(0xFF121815),
                      ]
                    : [
                        AppColors.paper,
                        scheme.surfaceContainerLowest,
                        AppColors.paperDeep,
                      ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondary.withValues(alpha: isDark ? 0.08 : 0.07),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -90,
          child: IgnorePointer(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.forest.withValues(alpha: isDark ? 0.12 : 0.06),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
