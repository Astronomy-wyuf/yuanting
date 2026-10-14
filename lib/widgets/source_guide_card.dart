import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/settings_providers.dart';
import '../providers/source_providers.dart';
import '../theme/app_theme.dart';
import 'proto_widgets.dart';

/// 首次启动且无启用书源时的导入引导卡片。
///
/// 点「立即导入」或「稍后再说」都会标记 [AppSettingsService.setFirstLaunchDone]，
/// 之后不再出现；已有启用书源时也会静默补标记。
class SourceGuideCard extends ConsumerWidget {
  const SourceGuideCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final sources = ref.watch(sourcesControllerProvider);
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);

    if (sources.loading) return const SizedBox.shrink();
    if (sources.enabledSources.isNotEmpty) {
      // 首启标记是历史遗留死键（可能已有书源但未标记）→ 静默补标记
      if (settings.isFirstLaunch) {
        Future.microtask(() => settings.setFirstLaunchDone());
      }
      return const SizedBox.shrink();
    }
    if (!settings.isFirstLaunch) return const SizedBox.shrink();

    return ProtoCard(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: brand.accentSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.library_music_rounded,
                    size: 22, color: brand.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '先导入一个书源',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '源听通过书源聚合有声内容。粘贴书源 JSON、选择文件或输入链接导入，'
            '之后即可搜索、浏览与收听。',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await settings.setFirstLaunchDone();
                  if (context.mounted) context.push('/sources');
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('立即导入'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => settings.setFirstLaunchDone(),
                child: const Text('稍后再说'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
