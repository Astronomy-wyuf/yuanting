import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chapter.dart';
import '../providers/player_providers.dart';
import '../services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import 'sheet_chrome.dart';

/// 播放倍速：预设网格 + 自定义输入
class PlayerSpeedSheet extends StatefulWidget {
  final PlayerController player;

  const PlayerSpeedSheet({super.key, required this.player});

  static const speeds = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0,
  ];

  static Future<void> show(BuildContext context, PlayerController player) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlayerSpeedSheet(player: player),
    );
  }

  @override
  State<PlayerSpeedSheet> createState() => _PlayerSpeedSheetState();
}

class _PlayerSpeedSheetState extends State<PlayerSpeedSheet> {
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    _custom = TextEditingController(
      text: widget.player.speed.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _apply(double speed) async {
    await widget.player.setSpeed(speed);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _applyCustom() async {
    final raw = _custom.text.trim().replaceAll('x', '').replaceAll('X', '');
    final v = double.tryParse(raw);
    if (v == null) return;
    await _apply(v.clamp(AppConstants.minSpeed, AppConstants.maxSpeed));
  }

  @override
  Widget build(BuildContext context) {
    final speed = widget.player.speed;
    return AppSheetScaffold(
      eyebrow: 'SPEED',
      title: '播放倍速',
      subtitle: '当前 ${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 2)}x · 范围 ${AppConstants.minSpeed}–${AppConstants.maxSpeed}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetOptionGrid(
            children: [
              for (final s in PlayerSpeedSheet.speeds)
                AppSheetChoice(
                  label: '${s}x',
                  selected: (speed - s).abs() < 0.01,
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

/// 睡眠定时：预设 + 自定义分钟 / 自定义章节
class PlayerSleepSheet extends StatefulWidget {
  final PlayerController player;

  const PlayerSleepSheet({super.key, required this.player});

  static Future<void> show(BuildContext context, PlayerController player) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlayerSleepSheet(player: player),
    );
  }

  @override
  State<PlayerSleepSheet> createState() => _PlayerSleepSheetState();
}

class _PlayerSleepSheetState extends State<PlayerSleepSheet> {
  final _minutesCtrl = TextEditingController();
  final _chaptersCtrl = TextEditingController();

  @override
  void dispose() {
    _minutesCtrl.dispose();
    _chaptersCtrl.dispose();
    super.dispose();
  }

  void _apply(SleepTimerState state) {
    widget.player.setSleepTimer(state);
    Navigator.pop(context);
  }

  void _applyMinutes() {
    final n = int.tryParse(_minutesCtrl.text.trim());
    if (n == null || n <= 0) return;
    final minutes = n.clamp(1, 24 * 60);
    _apply(SleepTimerState(
      mode: SleepTimerMode.countdown,
      minutes: minutes,
      endAt: DateTime.now().add(Duration(minutes: minutes)),
    ));
  }

  void _applyChapters() {
    final n = int.tryParse(_chaptersCtrl.text.trim());
    if (n == null || n <= 0) return;
    _apply(SleepTimerState(
      mode: SleepTimerMode.afterNChapters,
      chaptersRemaining: n.clamp(1, 999),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final sleep = widget.player.sleepTimer;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = BrandColors.of(context);

    String? status;
    switch (sleep.mode) {
      case SleepTimerMode.off:
        status = null;
      case SleepTimerMode.countdown:
        status = '进行中 · ${sleep.remainingLabel()}';
      case SleepTimerMode.afterChapter:
        status = '进行中 · 播完本集停止';
      case SleepTimerMode.afterNChapters:
        status = '进行中 · 还剩 ${sleep.chaptersRemaining} 集';
    }

    return AppSheetScaffold(
      eyebrow: 'SLEEP',
      title: '睡眠定时',
      subtitle: status ?? '到点自动暂停，不影响进度保存',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: brand.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.bedtime, size: 18, color: brand.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: brand.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _apply(SleepTimerState.off),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text('按时间', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AppSheetOptionGrid(
            crossAxisCount: 2,
            children: [
              for (final m in const [15, 30, 60, 90])
                AppSheetChoice(
                  label: '$m 分钟',
                  selected: sleep.mode == SleepTimerMode.countdown &&
                      sleep.minutes == m,
                  onTap: () => _apply(SleepTimerState(
                    mode: SleepTimerMode.countdown,
                    minutes: m,
                    endAt: DateTime.now().add(Duration(minutes: m)),
                  )),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minutesCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: '自定义分钟',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyMinutes(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _applyMinutes,
                child: const Text('确定'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('按章节', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AppSheetOptionGrid(
            crossAxisCount: 2,
            children: [
              AppSheetChoice(
                label: '播完本集',
                selected: sleep.mode == SleepTimerMode.afterChapter,
                onTap: () => _apply(const SleepTimerState(
                  mode: SleepTimerMode.afterChapter,
                )),
              ),
              for (final n in const [2, 3, 5])
                AppSheetChoice(
                  label: '播完 $n 集',
                  selected: sleep.mode == SleepTimerMode.afterNChapters &&
                      sleep.chaptersRemaining == n,
                  onTap: () => _apply(SleepTimerState(
                    mode: SleepTimerMode.afterNChapters,
                    chaptersRemaining: n,
                  )),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chaptersCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: '播完 X 章',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyChapters(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _applyChapters,
                child: const Text('确定'),
              ),
            ],
          ),
          if (sleep.mode == SleepTimerMode.off) ...[
            const SizedBox(height: 8),
            Text(
              '自定义上限：时间 24 小时 · 章节 999 集',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 章节列表：可搜索标题 / 集数，定位当前章
class PlayerChapterSheet extends StatefulWidget {
  final PlayerController player;

  const PlayerChapterSheet({super.key, required this.player});

  static Future<void> show(BuildContext context, PlayerController player) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlayerChapterSheet(player: player),
    );
  }

  @override
  State<PlayerChapterSheet> createState() => _PlayerChapterSheetState();
}

class _PlayerChapterSheetState extends State<PlayerChapterSheet> {
  String _query = '';
  final _scroll = ScrollController();

  List<({int index, Chapter chapter})> get _filtered {
    final q = _query.trim().toLowerCase();
    final all = widget.player.chapters;
    if (q.isEmpty) {
      return [
        for (var i = 0; i < all.length; i++) (index: i, chapter: all[i]),
      ];
    }
    final out = <({int index, Chapter chapter})>[];
    for (var i = 0; i < all.length; i++) {
      final ch = all[i];
      final no = '${i + 1}';
      if (ch.title.toLowerCase().contains(q) || no.contains(q)) {
        out.add((index: i, chapter: ch));
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_query.isNotEmpty || !_scroll.hasClients) return;
      final i = widget.player.currentIndex;
      if (i <= 0) return;
      final offset = (i * 56.0) - 120;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);
    final scheme = theme.colorScheme;
    final items = _filtered;
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CHAPTERS',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: brand.accent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('章节列表', style: theme.textTheme.headlineSmall),
                  const Spacer(),
                  Text(
                    '${widget.player.chapters.length}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: '搜章节 / 集数',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _query = ''),
                        ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的章节',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: items.length,
                        itemExtent: 56,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final current =
                              item.index == widget.player.currentIndex;
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            leading: SizedBox(
                              width: 28,
                              child: Text(
                                '${item.index + 1}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: current
                                      ? brand.accent
                                      : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(
                              item.chapter.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: current ? brand.accent : null,
                                fontWeight:
                                    current ? FontWeight.w600 : null,
                              ),
                            ),
                            trailing: current
                                ? Icon(Icons.graphic_eq,
                                    size: 18, color: brand.accent)
                                : null,
                            onTap: () {
                              widget.player.playChapter(item.index);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 更多菜单
class PlayerMoreSheet extends StatelessWidget {
  final PlayerController player;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;
  final VoidCallback onSkip;
  final VoidCallback onClosePlaylist;

  const PlayerMoreSheet({
    super.key,
    required this.player,
    required this.onSpeed,
    required this.onSleep,
    required this.onSkip,
    required this.onClosePlaylist,
  });

  static Future<void> show(
    BuildContext context, {
    required PlayerController player,
    required VoidCallback onSpeed,
    required VoidCallback onSleep,
    required VoidCallback onSkip,
    required VoidCallback onClosePlaylist,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => PlayerMoreSheet(
        player: player,
        onSpeed: onSpeed,
        onSleep: onSleep,
        onSkip: onSkip,
        onClosePlaylist: onClosePlaylist,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sleep = player.sleepTimer;
    final sleepLabel = sleep.mode == SleepTimerMode.off
        ? '未开启'
        : sleep.remainingLabel();
    final speedLabel =
        '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 0 : 2)}x';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('倍速'),
              trailing: Text(speedLabel),
              onTap: () {
                Navigator.pop(context);
                onSpeed();
              },
            ),
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('睡眠定时'),
              trailing: Text(sleepLabel),
              onTap: () {
                Navigator.pop(context);
                onSleep();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: const Text('片头片尾'),
              onTap: () {
                Navigator.pop(context);
                onSkip();
              },
            ),
            const Divider(height: 16),
            ListTile(
              leading: Icon(Icons.close,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                '关闭播放列表',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                onClosePlaylist();
              },
            ),
          ],
        ),
      ),
    );
  }
}
