import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book_source.dart';
import '../models/browse_list_args.dart';
import '../providers/settings_providers.dart';
import '../providers/source_providers.dart';
import '../utils/discover_source_config.dart';
import '../widgets/proto_widgets.dart';

/// 全部分类 — 按当前书源配置展示；无分类能力时提示空状态
class CategoryAllScreen extends ConsumerWidget {
  const CategoryAllScreen({super.key});

  void _open(BuildContext context, String name) {
    context.push('/category', extra: BrowseListArgs.category(name));
  }

  BookSource? _activeSource(WidgetRef ref) {
    final sources = ref.watch(sourcesControllerProvider);
    final preferred = ref.watch(settingsControllerProvider).preferredSourceId;
    final enabled = sources.enabledSources;
    if (enabled.isEmpty) return null;
    for (final s in enabled) {
      if (s.id == preferred) return s;
    }
    return enabled.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final source = _activeSource(ref);
    final config = DiscoverSourceConfig.resolve(source);
    final sourceName = source?.name ?? '未启用书源';

    Widget section(String title, List<String> names) {
      if (names.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
            child: Text(
              title,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in names)
                ProtoChip(
                  label: name,
                  onTap: () => _open(context, name),
                ),
            ],
          ),
        ],
      );
    }

    final bodyChildren = <Widget>[
      Text(
        '当前书源 · $sourceName',
        style: theme.textTheme.bodySmall,
      ),
    ];

    if (!config.hasCategories) {
      bodyChildren.add(
        const Padding(
          padding: EdgeInsets.only(top: 48),
          child: ProtoEmpty(
            icon: Icons.category_outlined,
            title: '当前书源暂无分类',
          ),
        ),
      );
    } else if (config.categoryGroups.isNotEmpty) {
      for (final g in config.categoryGroups) {
        bodyChildren.add(section(g.$1, g.$2));
      }
    } else {
      bodyChildren.add(section('分类', config.featuredCategories));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 28),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        '全部分类',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: bodyChildren,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
