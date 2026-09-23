import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/download_providers.dart';
import '../theme/app_theme.dart';

/// 底部 Tab — 实色底栏（避免 BackdropFilter 滚动掉帧）
class AppDock extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const AppDock({
    super.key,
    required this.index,
    required this.onChanged,
  });

  static const _items = [
    (Icons.menu_book_outlined, Icons.menu_book, '书架'),
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.search, Icons.search, '搜书'),
    (Icons.download_outlined, Icons.download, '下载'),
    (Icons.settings_outlined, Icons.settings, '设置'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final brand = BrandColors.of(context);
    final activeDl = ref.watch(
      downloadServiceProvider.select((s) => s.activeCount),
    );

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom > 0
            ? MediaQuery.paddingOf(context).bottom
            : 6,
        top: 4,
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _DockItem(
                  icon: index == i ? _items[i].$2 : _items[i].$1,
                  label: _items[i].$3,
                  selected: index == i,
                  badge: i == 3 && activeDl > 0
                      ? (activeDl > 99 ? '99+' : '$activeDl')
                      : null,
                  badgeColor: brand.accent,
                  onTap: () => onChanged(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.secondary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20, color: color),
              if (badge != null)
                Positioned(
                  right: -10,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeColor ?? scheme.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    child: Text(
                      badge!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 10,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}
