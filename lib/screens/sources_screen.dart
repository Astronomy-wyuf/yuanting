import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/book_source.dart';
import '../providers/source_providers.dart';
import '../utils/clipboard_text.dart';
import '../utils/text_file_codec.dart';
import '../theme/app_theme.dart';
import '../widgets/proto_widgets.dart';

/// 书源管理：列表、启用/禁用、编辑、删除、导入（粘贴 / 文件 / 网络）
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sourcesControllerProvider).load());
  }

  Future<void> _importFromPaste() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _JsonEditorPage(
          title: '粘贴书源 JSON',
          confirmLabel: '导入',
          hint: '点「从剪贴板粘入」。长 JSON 只读显示，避免输入法把内容截成约 2048 字。',
        ),
      ),
    );
    if (text == null || !mounted) return;
    final result =
        await ref.read(sourcesControllerProvider).importFromText(text);
    if (!mounted) return;
    _showImportResult(result);
  }

  Future<void> _importFromFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      List<int>? bytes = file.bytes;
      if ((bytes == null || bytes.isEmpty) &&
          file.path != null &&
          file.path!.isNotEmpty) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        await _showCopyableError(
          '读取文件失败',
          '无法读取所选文件（path=${file.path}，bytes=${file.bytes?.length}）。\n'
          '请改用「粘贴导入」，或把文件放到 Download 后再选。',
        );
        return;
      }
      final text = decodeTextFileBytes(bytes);
      if (text.trim().isEmpty) {
        await _showCopyableError('文件内容为空', '解码后文本为空。请另存为 UTF-8 的 .json 再试。');
        return;
      }
      final result =
          await ref.read(sourcesControllerProvider).importFromText(text);
      if (!mounted) return;
      _showImportResult(result);
    } on PlatformException catch (e) {
      await _showCopyableError(
        '选择文件失败',
        'code=${e.code}\nmessage=${e.message}\ndetails=${e.details}',
      );
    } catch (e, st) {
      await _showCopyableError('读取文件失败', '$e\n\n$st');
    }
  }

  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('网络导入'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'https://example.com/source.json',
              labelText: '书源 JSON 链接',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (url == null || url.isEmpty || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在下载书源…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    SourceImportResult result;
    try {
      result = await ref.read(sourcesControllerProvider).importFromUrl(url);
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    _showImportResult(result);
  }

  void _showImportResult(SourceImportResult result) {
    if (result.success || result.okCount > 0) {
      _toast('成功导入 ${result.okCount} 个书源'
          '${result.errors.isNotEmpty ? '，${result.errors.length} 个失败' : ''}');
      if (result.errors.isNotEmpty) {
        _showCopyableError('部分导入失败', result.errors.join('\n'));
      }
    } else {
      _showCopyableError(
        '导入失败',
        result.errors.isNotEmpty ? result.errors.join('\n') : '未知错误',
      );
    }
  }

  Future<void> _showCopyableError(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(message),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('错误信息已复制')),
              );
            },
            child: const Text('复制错误信息'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BookSource source) async {
    final initial =
        const JsonEncoder.withIndent('  ').convert(source.rule);
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _JsonEditorPage(
          title: '编辑：${source.name}',
          confirmLabel: '保存',
          initialText: initial,
          hint: '点「从剪贴板粘入」替换全文。较长内容只读显示，避免输入法截断。',
        ),
      ),
    );
    if (text == null || !mounted) return;
    final errors = await ref
        .read(sourcesControllerProvider)
        .updateRule(source, text);
    if (!mounted) return;
    if (errors.isEmpty) {
      _toast('书源已更新');
    } else {
      await _showCopyableError('保存失败', errors.join('\n'));
    }
  }

  Future<void> _delete(BookSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书源'),
        content: Text(
            '确定删除书源「${source.name}」？已收藏书籍的章节缓存与进度将保留，但重新抓取章节将失败。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(sourcesControllerProvider).delete(source);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showImportSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴 JSON'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromPaste();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('从文件导入'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('网络导入'),
              subtitle: const Text('从 URL 下载书源 JSON'),
              onTap: () {
                Navigator.pop(ctx);
                _importFromUrl();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left, size: 28),
                  ),
                  Expanded(
                    child: Text(
                      '书源管理',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _showImportSheet,
                    icon: Icon(Icons.add, color: scheme.secondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sources.loading && sources.sources.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : sources.sources.isEmpty
                      ? ProtoEmpty(
                          icon: Icons.cell_tower,
                          title: '还没有书源',
                          subtitle: '可粘贴 JSON、从文件或网络导入',
                          action: FilledButton(
                            onPressed: _showImportSheet,
                            child: const Text('导入书源'),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          children: [
                            for (final s in sources.sources) ...[
                              _tile(theme, s),
                              const SizedBox(height: 12),
                            ],
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                              child: Text(
                                '支持粘贴、文件与网络导入合法书源 JSON。规则含搜索 / 详情 / 章节 / 音频解析四段流水线。',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ThemeData theme, BookSource source) {
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: source.enabled ? 1 : 0.7,
      child: ProtoCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: source.enabled
                        ? BrandColors.of(context).accentSoft
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cell_tower,
                    size: 18,
                    color: source.enabled
                        ? BrandColors.of(context).accent
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              source.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.enabled
                            ? '${source.url} · json 规则'
                            : '已禁用 · 不参与聚合搜索',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: source.enabled,
                  onChanged: (_) =>
                      ref.read(sourcesControllerProvider).toggle(source),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _edit(source),
                    child: const Text('编辑'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _delete(source),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 超过这个长度就不要再交给 Android 输入法。
/// 不少系统会把输入框内容回写成约 2048 字，并覆盖掉刚粘入的全文。
const _kImeSafeLength = 1000;

/// 全屏 JSON 编辑。长文本不进入输入法，避免被回写成约 2048 字。
class _JsonEditorPage extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String? initialText;
  final String hint;

  const _JsonEditorPage({
    required this.title,
    required this.confirmLabel,
    this.initialText,
    required this.hint,
  });

  @override
  State<_JsonEditorPage> createState() => _JsonEditorPageState();
}

class _JsonEditorPageState extends State<_JsonEditorPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// 真正要导入/保存的全文。长文本时不放进 TextField。
  String _body = '';
  bool _locked = false;
  int _chars = 0;
  String? _warn;

  @override
  void initState() {
    super.initState();
    _body = widget.initialText ?? '';
    _locked = _body.length > _kImeSafeLength;
    _controller = TextEditingController(text: _locked ? '' : _body);
    _focusNode = FocusNode();
    _chars = _body.length;
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (_locked) return;
    final t = _controller.text;
    // 输入法把刚写入的长文本回写成前缀时，丢掉这次回写，保留全文。
    if (_body.length > t.length &&
        _body.length > _kImeSafeLength &&
        t.isNotEmpty &&
        _body.startsWith(t)) {
      _focusNode.unfocus();
      setState(() => _locked = true);
      return;
    }
    _body = t;
    if (t.length != _chars) setState(() => _chars = t.length);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final text = await readClipboardText();
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板为空')),
      );
      return;
    }
    _applyText(text);
  }

  void _applyText(String text) {
    _focusNode.unfocus();
    final lock = text.length > _kImeSafeLength;
    setState(() {
      _body = text;
      _locked = lock;
      _chars = text.length;
      _warn = text.length == 2048
          ? '剪贴板里恰好 2048 字，复制时可能已被系统截断。请改用文件导入。'
          : null;
    });
    if (!lock) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已粘入 ${text.length} 个字符')),
    );
  }

  void _submit() {
    final text = _locked ? _body : _controller.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容为空')),
      );
      return;
    }
    Navigator.pop(context, text);
  }

  static const _mono = TextStyle(
    fontSize: 13,
    fontFamily: 'monospace',
    height: 1.35,
  );

  Widget _lockedPreview(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _body.isEmpty ? '{ "site": { ... }, ... }' : _body,
            style: _mono.copyWith(
              color: _body.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _editorField() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      expands: true,
      maxLines: null,
      minLines: null,
      maxLength: null,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: _mono,
      contextMenuBuilder: (context, editableTextState) {
        final items = editableTextState.contextMenuButtonItems
            .where((i) => i.type != ContextMenuButtonType.paste)
            .toList();
        items.add(
          ContextMenuButtonItem(
            label: '粘贴全部',
            onPressed: () {
              ContextMenuController.removeAny();
              _pasteFromClipboard();
            },
          ),
        );
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
      decoration: const InputDecoration(
        filled: true,
        border: OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(12),
        hintText: '{ "site": { ... }, ... }',
        counterText: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteFromClipboard,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _pasteFromClipboard,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: _pasteFromClipboard,
              child: const Text('从剪贴板粘入'),
            ),
            FilledButton(
              onPressed: _submit,
              child: Text(widget.confirmLabel),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前 $_chars 字符（无上限）',
                  style: theme.textTheme.labelMedium,
                ),
                if (_warn != null) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        _warn!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (_locked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '全文已保留，可直接导入。此处不进入输入法，避免被截成约 2048 字。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(
                  child: _locked ? _lockedPreview(theme) : _editorField(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
