import 'package:flutter/material.dart';

import 'sheet_chrome.dart';

/// 统一片头/片尾跳过配置底栏
class SkipConfigSheet extends StatefulWidget {
  final int? intro;
  final int? outro;
  final String title;
  final String? subtitle;
  final bool allowNull;

  const SkipConfigSheet({
    super.key,
    required this.intro,
    required this.outro,
    this.title = '片头 / 片尾跳过',
    this.subtitle,
    this.allowNull = true,
  });

  static Future<(int?, int?)?> show(
    BuildContext context, {
    required int? intro,
    required int? outro,
    String title = '片头 / 片尾跳过',
    String? subtitle,
    bool allowNull = true,
  }) {
    return showModalBottomSheet<(int?, int?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SkipConfigSheet(
        intro: intro,
        outro: outro,
        title: title,
        subtitle: subtitle,
        allowNull: allowNull,
      ),
    );
  }

  @override
  State<SkipConfigSheet> createState() => _SkipConfigSheetState();
}

class _SkipConfigSheetState extends State<SkipConfigSheet> {
  late double _intro;
  late double _outro;
  late bool _useDefault;

  @override
  void initState() {
    super.initState();
    _useDefault =
        widget.allowNull && widget.intro == null && widget.outro == null;
    _intro = (widget.intro ?? 0).toDouble().clamp(0, 120);
    _outro = (widget.outro ?? 0).toDouble().clamp(0, 120);
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetScaffold(
      eyebrow: 'SKIP',
      title: widget.title,
      subtitle: widget.subtitle ??
          (widget.allowNull
              ? '优先级：本书 > 书源 > 全局'
              : '三级优先级最低层 · 未单独设置时生效'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.allowNull)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('跟随上级默认'),
              subtitle: const Text('关闭后单独设置秒数'),
              value: _useDefault,
              onChanged: (v) => setState(() => _useDefault = v),
            ),
          IgnorePointer(
            ignoring: _useDefault,
            child: Opacity(
              opacity: _useDefault ? 0.4 : 1,
              child: Column(
                children: [
                  _slider('片头', _intro, (v) => setState(() => _intro = v)),
                  _slider('片尾', _outro, (v) => setState(() => _outro = v)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (_useDefault) {
                Navigator.pop(context, (null, null));
              } else {
                Navigator.pop(context, (_intro.round(), _outro.round()));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text('${value.round()} 秒'),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 120,
          divisions: 24,
          label: '${value.round()}s',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
