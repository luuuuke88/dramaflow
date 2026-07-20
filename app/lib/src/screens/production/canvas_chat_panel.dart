// 制作画布右侧助手面板：固定 production 入口，底层使用 v0.4 assistant_chat。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assistant_chat.dart';
import '../../engine/errors.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/external_link_text.dart';

/// 画布内嵌的 Agent 对话面板。可作为桌面右侧滑出面板的内容，也可作为移动端
/// 全屏对话页的 body。头部提供关闭、模式切换、清空记忆入口。
class CanvasChatPanel extends ConsumerStatefulWidget {
  final int projectId;

  /// 头部关闭按钮回调；为 null 时不显示关闭按钮（例如放进 Scaffold 的 body）。
  final VoidCallback? onClose;

  const CanvasChatPanel({super.key, required this.projectId, this.onClose});

  @override
  ConsumerState<CanvasChatPanel> createState() => _CanvasChatPanelState();
}

class _CanvasChatPanelState extends ConsumerState<CanvasChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _autoMode = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _autoMode = ref.read(engineProvider).assistantAutoMode();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: DFTokens.standard200, curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    _scrollToBottom();
    try {
      await ref.read(engineProvider).sendAssistantMessage(
            widget.projectId,
            text,
            autoMode: _autoMode,
            family: assistantFamilyProduction,
          );
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _clearMemory() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.agentChatConfirmClearTitle),
        content: Text(l10n.agentChatConfirmClearBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).clearAssistantChat(widget.projectId,
        family: assistantFamilyProduction);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.agentChatMemoryCleared)));
      setState(() {});
    }
  }

  Future<void> _confirmPending(bool approve) async {
    await ref.read(engineProvider).confirmPendingAssistantAction(
          widget.projectId,
          family: assistantFamilyProduction,
          approve: approve,
        );
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final messages = ref
        .watch(engineProvider)
        .assistantMessages(widget.projectId, family: assistantFamilyProduction);

    return Column(children: [
      _PanelHeader(
        title: l10n.canvasChatTitle,
        autoMode: _autoMode,
        onModeChanged: (v) {
          setState(() => _autoMode = v);
          ref.read(engineProvider).setAssistantAutoMode(v);
        },
        onClear: _clearMemory,
        onClose: widget.onClose,
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            if (messages.isEmpty) _WelcomeBubble(text: l10n.canvasChatWelcome),
            for (final m in messages)
              _MessageBubble(
                message: m,
                onApprove: () => _confirmPending(true),
                onReject: () => _confirmPending(false),
              ),
            if (_sending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(l10n.agentChatThinking,
                      style: TextStyle(fontSize: 12, color: df.textTertiary)),
                ]),
              ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: df.surface,
          border: Border(top: BorderSide(color: df.stroke)),
        ),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: l10n.agentChatInputPlaceholder,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: Text(l10n.agentChatSend),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final bool autoMode;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onClear;
  final VoidCallback? onClose;

  const _PanelHeader({
    required this.title,
    required this.autoMode,
    required this.onModeChanged,
    required this.onClear,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: df.surface,
        border: Border(bottom: BorderSide(color: df.stroke)),
      ),
      child: Row(children: [
        Icon(Icons.smart_toy_outlined, size: 18, color: df.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: DFTokens.section16w600.copyWith(color: df.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        Tooltip(
          message: l10n.agentChatModeHint,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(autoMode ? l10n.agentChatAutoMode : l10n.agentChatManualMode,
                style: TextStyle(fontSize: 12, color: df.textSecondary)),
            Switch(value: autoMode, onChanged: onModeChanged),
          ]),
        ),
        IconButton(
          tooltip: l10n.agentChatClearMemory,
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: onClear,
        ),
        if (onClose != null)
          IconButton(
            tooltip: l10n.canvasChatClose,
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
      ]),
    );
  }
}

class _WelcomeBubble extends StatelessWidget {
  final String text;
  const _WelcomeBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AssistantMessage message;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _MessageBubble({
    required this.message,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final isUser = message.role == assistantRoleUser;
    final isTool = message.role == assistantRoleTool;
    final isConfirm = message.role == assistantRoleConfirm;

    if (isConfirm) {
      final pending = message.confirmStatus == 'pending';
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: df.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            border: Border.all(color: df.warning.withValues(alpha: 0.5)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.privacy_tip_outlined, size: 16, color: df.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.agentChatConfirmNeeded(message.toolName ?? ''),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: df.textPrimary),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              pending
                  ? l10n.agentChatConfirmActionBody
                  : message.confirmStatus == 'approved'
                      ? l10n.agentChatConfirmApproved
                      : l10n.agentChatConfirmRejected,
              style: TextStyle(fontSize: 12, color: df.textSecondary),
            ),
            if (pending) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  key: const ValueKey('assistant-confirm-reject'),
                  onPressed: onReject,
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('assistant-confirm-approve'),
                  onPressed: onApprove,
                  child: Text(l10n.commonConfirm),
                ),
              ]),
            ],
          ]),
        ),
      );
    }

    if (isTool) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: df.primarySubtle,
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            border: Border.all(color: df.primary.withValues(alpha: 0.3)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bolt, size: 14, color: df.primary),
              const SizedBox(width: 4),
              Text(l10n.agentChatToolExecuted(message.toolName ?? ''),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: df.primary)),
            ]),
            const SizedBox(height: 4),
            Text(message.content, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: isUser ? df.primary : df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        ),
        child: ExternalLinkText(
          text: _assistantDisplayText(context, message.content),
          style: TextStyle(
              fontSize: 13, color: isUser ? Colors.white : df.textPrimary),
        ),
      ),
    );
  }
}

String _assistantDisplayText(BuildContext context, String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      final errKey = decoded['errKey'];
      if (errKey is String && errKey.isNotEmpty) {
        final params = decoded['params'];
        return localizeErrKey(
          context.l10n,
          EngineException(
            errKey,
            params is Map ? Map<String, Object?>.from(params) : const {},
          ),
        );
      }
      if (decoded['infoKey'] == 'assistantMoneyNotice') {
        return context.l10n
            .agentChatMoneyAutoNotice('${decoded['tool'] ?? ''}');
      }
    }
  } catch (_) {
    // 普通文本直接展示。
  }
  return content;
}
