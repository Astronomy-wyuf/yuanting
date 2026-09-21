import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/settings_providers.dart';
import '../utils/constants.dart';
import 'sheet_chrome.dart';

String _fmtSpeed(double r) =>
    r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

/// 设置 · 默认倍速
class DefaultSpeedSheet extends StatefulWidget {
  final SettingsController settings;

  const DefaultSpeedSheet({super.key, required this.settings});

  static const speeds = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0,
  ];

  static Future<void> show(BuildContext context, SettingsController settings) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DefaultSpeedSheet(settings: settings),
    );
  }

  @override
  State<DefaultSpeedSheet> createState() => _DefaultSpeedSheetState();
}

class _DefaultSpeedSheetState extends State<DefaultSpeedSheet> {
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    _custom = TextEditingController(
      text: _fmtSpeed(widget.settings.defaultRate),
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _apply(double speed) async {
    final v = speed.clamp(AppConstants.minSpeed, AppConstants.maxSpeed);
    await widget.settings.setDefaultRate(v);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _applyCustom() async {
    final raw = _custom.text.trim().replaceAll(RegExp(r'[xX]'), '');
    final v = double.tryParse(raw);
    if (v == null) return;
    await _apply(v);
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.settings.defaultRate;
    return AppSheetScaffold(
      eyebrow: 'PLAYBACK',
      title: '默认倍速',
      subtitle:
          '新会话起播使用 · 播放页改速会回写 · 范围 ${AppConstants.minSpeed}–${AppConstants.maxSpeed}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetOptionGrid(
            children: [
              for (final s in DefaultSpeedSheet.speeds)
                AppSheetChoice(
                  label: '${_fmtSpeed(s)}x',
                  selected: (rate - s).abs() < 0.01,
                  onTap: () => _apply(s),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '自定义 0.5–4.0',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyCustom(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _applyCustom,
                child: const Text('应用'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置 · 下载存储上限
class StorageLimitSheet extends StatelessWidget {
  final SettingsController settings;
  final List<int> options;

  const StorageLimitSheet({
    super.key,
    required this.settings,
    this.options = const [512, 1024, 2048, 4096, 8192],
  });

  static Future<void> show(
    BuildContext context,
    SettingsController settings, {
    List<int> options = const [512, 1024, 2048, 4096, 8192],
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StorageLimitSheet(settings: settings, options: options),
    );
  }

  String _label(int mb) {
    if (mb >= 1024 && mb % 1024 == 0) {
      return '${mb ~/ 1024} GB';
    }
    return '$mb MB';
  }

  String _detail(int mb) => '$mb MB';

  @override
  Widget build(BuildContext context) {
    final current = settings.maxStorageMB;
    return AppSheetScaffold(
      eyebrow: 'STORAGE',
      title: '下载存储上限',
      subtitle: '达到上限后需清理已下载内容才能继续下载',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            AppSheetSelectRow(
              label: _label(options[i]),
              trailing: options[i] >= 1024 ? _detail(options[i]) : null,
              selected: current == options[i],
              onTap: () async {
                await settings.setMaxStorageMB(options[i]);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 设置 / 下载弹层共用 · 自动下载后续 N 章
class AutoAheadSheet extends StatefulWidget {
  final SettingsController settings;
  final bool popOnSelect;

  const AutoAheadSheet({
    super.key,
    required this.settings,
    this.popOnSelect = true,
  });

  static const presets = [0, 1, 3, 5];

  static Future<void> show(
    BuildContext context,
    SettingsController settings, {
    bool popOnSelect = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AutoAheadSheet(
        settings: settings,
        popOnSelect: popOnSelect,
      ),
    );
  }

  @override
  State<AutoAheadSheet> createState() => _AutoAheadSheetState();
}

class _AutoAheadSheetState extends State<AutoAheadSheet> {
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    _custom = TextEditingController();
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _apply(int n) async {
    await widget.settings.setAutoDownloadAhead(n);
    if (!mounted) return;
    setState(() {});
    if (widget.popOnSelect) Navigator.pop(context);
    final msg = n == 0 ? '已关闭自动下载' : '播放时向后补齐 $n 章';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _applyCustom() async {
    final n = int.tryParse(_custom.text.trim());
    if (n == null) return;
    await _apply(n);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.settings.autoDownloadAhead;
    final isCustom = !AutoAheadSheet.presets.contains(n);
    return AppSheetScaffold(
      eyebrow: 'PLAYBACK',
      title: '自动下载后续',
      subtitle: '播放时让当前章之后始终有 N 章在本地或队列中。'
          '听到新章只补窗口边缘，不重复整段重下。',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetOptionGrid(
            crossAxisCount: 5,
            childAspectRatio: 1.6,
            children: [
              for (final p in AutoAheadSheet.presets)
                AppSheetChoice(
                  label: p == 0 ? '关' : '$p',
                  selected: n == p,
                  onTap: () => _apply(p),
                ),
              AppSheetChoice(
                label: '自定义',
                selected: isCustom,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '0 关闭，最多 50',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyCustom(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _applyCustom,
                child: const Text('确定'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
