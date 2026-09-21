import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 底栏弹窗公共外壳：eyebrow + 标题 + 可选副文案
class AppSheetScaffold extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;

  const AppSheetScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: brand.accent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(title, style: theme.textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 等分选项网格
class AppSheetOptionGrid extends StatelessWidget {
  final List<Widget> children;
  final int crossAxisCount;
  final double? childAspectRatio;

  const AppSheetOptionGrid({
    super.key,
    required this.children,
    this.crossAxisCount = 4,
    this.childAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: childAspectRatio ??
          (crossAxisCount == 2 ? 2.6 : 2.1),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

/// 可选中的选项块
class AppSheetChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AppSheetChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? brand.accent : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? Colors.white : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

/// 全宽可选列表行（存储上限等）
class AppSheetSelectRow extends StatelessWidget {
  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  const AppSheetSelectRow({
    super.key,
    required this.label,
    this.trailing,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? brand.accentSoft : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? brand.accent : scheme.onSurface,
                      ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 18, color: brand.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
