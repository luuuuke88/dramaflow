// 制作画布右侧 Agent 对话面板（照抄 ToonFlow rightChatBox：把剧本 Agent 对话
// 以右侧滑出面板/移动端全屏对话的形态嵌进制作画布，与独立的 Agent 页共用同一套
// 消息气泡 + 输入框 + 手动/自动模式切换 + 清空记忆交互，且共用同一份底层数据
// （engine.agentMessages/sendAgentMessage/clearAgentMemory，project 级）。
// 这里不复用 agent_chat_screen.dart 的私有 State（那是整页 Scaffold 形态，含 AppBar），
// 面板形态需要自带头部与紧凑布局，因此自成一个可复用 widget，逻辑与其保持一致。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/agent.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';

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
      await ref
          .read(engineProvider)
          .sendAgentMessage(widget.projectId, text, autoMode: _autoMode);
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
    ref.read(engineProvider).clearAgentMemory(widget.projectId);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.agentChatMemoryCleared)));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final messages = ref.watch(engineProvider).agentMessages(widget.projectId);

    return Column(children: [
      _PanelHeader(
        title: l10n.canvasChatTitle,
        autoMode: _autoMode,
        onModeChanged: (v) => setState(() => _autoMode = v),
        onClear: _clearMemory,
        onClose: widget.onClose,
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            if (messages.isEmpty) _WelcomeBubble(text: l10n.agentChatWelcome),
            for (final m in messages) _MessageBubble(message: m),
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
  final AgentMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final isUser = message.role == agentRoleUser;
    final isTool = message.role == agentRoleTool;

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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        child: Text(
          message.content,
          style: TextStyle(
              fontSize: 13, color: isUser ? Colors.white : df.textPrimary),
        ),
      ),
    );
  }
}
