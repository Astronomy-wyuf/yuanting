import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/search_captcha.dart';
import '../providers/search_providers.dart';
import '../theme/app_theme.dart';

/// 搜索验证码过渡页（BottomSheet）
Future<void> showSearchCaptchaSheet({
  required BuildContext context,
  required AudiobookSearchController controller,
  required SourceSearchState state,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _SearchCaptchaSheet(controller: controller, stateId: state.source.id),
      );
    },
  );
}

class _SearchCaptchaSheet extends StatefulWidget {
  final AudiobookSearchController controller;
  final String stateId;

  const _SearchCaptchaSheet({
    required this.controller,
    required this.stateId,
  });

  @override
  State<_SearchCaptchaSheet> createState() => _SearchCaptchaSheetState();
}

class _SearchCaptchaSheetState extends State<_SearchCaptchaSheet> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;

  SourceSearchState? get _state => widget.controller.bySource[widget.stateId];

  SearchCaptchaChallenge? get _challenge => _state?.captcha;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCtrl() {
    if (!mounted) return;
    final s = _state;
    if (s == null) {
      Navigator.of(context).maybePop();
      return;
    }
    if (s.status == SourceSearchStatus.done) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.submitCaptcha(widget.stateId, code);
      if (!mounted) return;
      if (_state?.status == SourceSearchStatus.needsCaptcha) {
        _code.clear();
        await widget.controller.refreshCaptcha(widget.stateId);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = BrandColors.of(context);
    final state = _state;
    final challenge = _challenge;
    if (state == null || challenge == null) {
      return const SizedBox(height: 120, child: Center(child: Text('验证已结束')));
    }

    final bytes = challenge.imageBytes;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${state.source.name} · 安全验证',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '该站搜索需要验证码。输入下方字符后继续（会话 Cookie 会保留一段时间）。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: bytes == null || bytes.isEmpty
                        ? Text(
                            '加载中…',
                            style: theme.textTheme.bodySmall,
                          )
                        : Image.memory(
                            bytes,
                            height: 40,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: '换一张',
                  onPressed: _submitting
                      ? null
                      : () => widget.controller.refreshCaptcha(widget.stateId),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: InputDecoration(
                labelText: '验证码',
                hintText: '不区分大小写',
                border: const OutlineInputBorder(),
                errorText: state.error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: brand.accent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('提交并搜索'),
            ),
          ],
        ),
      ),
    );
  }
}
