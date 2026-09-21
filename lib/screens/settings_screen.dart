import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/player_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/source_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/proto_widgets.dart';
import '../widgets/settings_sheets.dart';
import '../widgets/skip_config_sheet.dart';

/// 设置 — 对齐原型：听众卡 / 皮肤 / 播放 / 存储 / 关于
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _fmt(double r) =>
      r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final sources = ref.watch(sourcesControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasMini =
        ref.watch(playerControllerProvider.select((p) => p.hasSession));
    final bottom = protoBottomPad(context, hasMini: hasMini);
    final enabledCount = sources.enabledSources.length;
    final modeKey = settings.themeMode == ThemeMode.system
        ? 'auto'
        : settings.themeMode == ThemeMode.dark
            ? 'night'
            : 'manual';
    final brand = BrandColors.of(context);
    final skin = settings.skin;

    return Column(
      children: [
        const SafeArea(
          bottom: false,
          child: ProtoPageTitle('设置'),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
            children: [
              ProtoCard(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: brand.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '听',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: brand.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '本地听众',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '无账号 · 数据存于本机',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const ProtoSectionLabel('外观'),
              ProtoCard(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('皮肤',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final item in [
                          (
                            AppSkin.day,
                            const Color(0xFFFAFAF8),
                            true,
                          ),
                          (
                            AppSkin.night,
                            const Color(0xFF111113),
                            false,
                          ),
                          (
                            AppSkin.paper,
                            const Color(0xFFF3EBDD),
                            true,
                          ),
                          (
                            AppSkin.ink,
                            const Color(0xFF0D1524),
                            false,
                          ),
                        ]) ...[
                          _SkinDot(
                            color: item.$2,
                            border: item.$3,
                            selected: skin == item.$1,
                            onTap: () => settings.setSkin(item.$1),
                          ),
                          if (item.$1 != AppSkin.ink) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('跟随系统 / 手动', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    _Seg(
                      options: const ['自动', '手动', '夜间'],
                      selected: modeKey == 'auto'
                          ? 0
                          : modeKey == 'manual'
                              ? 1
                              : 2,
                      onChanged: (i) {
                        if (i == 0) settings.setThemeMode('auto');
                        if (i == 1) {
                          settings.setThemeMode('light');
                          if (settings.skin.isDark) {
                            settings.setSkin(AppSkin.day);
                          }
                        }
                        if (i == 2) settings.setThemeMode('dark');
                      },
                    ),
                  ],
                ),
              ),
              const ProtoSectionLabel('播放'),
              ProtoCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    ProtoRow(
                      title: '默认倍速',
                      subtitle: '播放页改速会回写',
                      trailing: Text(
                        '${_fmt(settings.defaultRate)}x',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      onTap: () => DefaultSpeedSheet.show(context, settings),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    ProtoRow(
                      title: '全局片头片尾',
                      subtitle: '三级优先级最低层',
                      trailing: Text(
                        '${settings.defaultSkipIntro}s / ${settings.defaultSkipOutro}s',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      onTap: () async {
                        final result = await SkipConfigSheet.show(
                          context,
                          intro: settings.defaultSkipIntro,
                          outro: settings.defaultSkipOutro,
                          title: '全局片头片尾',
                          subtitle: '三级优先级最低层 · 未单独设置时生效',
                          allowNull: false,
                        );
                        if (result == null) return;
                        await settings.setDefaultSkipIntro(result.$1 ?? 0);
                        await settings.setDefaultSkipOutro(result.$2 ?? 0);
                      },
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    ProtoRow(
                      title: '自动下载后续',
                      subtitle: '播放时向后补齐，暂停后不再新开',
                      trailing: Text(
                        settings.autoDownloadAheadLabel,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      onTap: () => AutoAheadSheet.show(context, settings),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('仅 Wi‑Fi 下载',
                                    style: theme.textTheme.bodyMedium),
                                Text('避免移动网络偷流量',
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: settings.wifiOnlyDownload,
                            onChanged: settings.setWifiOnlyDownload,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const ProtoSectionLabel('存储与书源'),
              ProtoCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    ProtoRow(
                      title: '下载存储上限',
                      trailing: Text(
                        '${settings.maxStorageMB} MB',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      onTap: () => StorageLimitSheet.show(context, settings),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant),
                    ProtoRow(
                      title: '书源管理',
                      trailing: ProtoBadge('$enabledCount 启用'),
                      onTap: () => context.push('/sources'),
                    ),
                  ],
                ),
              ),
              ProtoCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final v = snap.data?.version ?? '1.0.0';
                    return ProtoRow(
                      title: '关于',
                      trailing: Text(
                        'v$v',
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => context.push('/about'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkinDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final bool border;
  final VoidCallback onTap;

  const _SkinDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.border = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = BrandColors.of(context).accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? accent
                : (border ? const Color(0xFFDDDDDD) : Colors.transparent),
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 16, color: accent)
            : null,
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  const _Seg({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Material(
                color: i == selected
                    ? scheme.surfaceContainerLowest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      options[i],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight:
                                i == selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
