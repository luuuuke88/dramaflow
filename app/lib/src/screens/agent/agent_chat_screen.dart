// 剧本 Agent 对话页（照抄 scriptAgent 页交互形态，见 P5 参照与 spec §4 决策）：
// 消息列表 + 输入框 + 手动/自动模式切换 + 清空记忆 + 内置能力说明。
// 每次工具调用都是已有真实流水线动作，全部经 o_tasks 队列（任务中心可查可重试），
// 不做多层子代理编排与向量 RAG 记忆——这是 spec 明确的简化范围，非缺陷。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/agent.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';

class AgentChatScreen extends ConsumerStatefulWidget {
  final int projectId;
  const AgentChatScreen({super.key, required this.projectId});

  @override
  ConsumerState<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends ConsumerState<AgentChatScreen> {
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

  void _showSkillsInfo() {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.agentChatSkillsInfo),
        content: SizedBox(
            width: 420, child: Text(l10n.agentChatSkillsBody)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: Text(l10n.commonConfirm)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final messages = ref.watch(engineProvider).agentMessages(widget.projectId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.agentChatTitle),
        actions: [
          IconButton(
            tooltip: l10n.agentChatSkillsInfo,
            icon: const Icon(Icons.info_outline),
            onPressed: _showSkillsInfo,
          ),
          Tooltip(
            message: l10n.agentChatModeHint,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Text(
                    _autoMode
                        ? l10n.agentChatAutoMode
                        : l10n.agentChatManualMode,
                    style: const TextStyle(fontSize: 12)),
                Switch(
                  value: _autoMode,
                  onChanged: (v) => setState(() => _autoMode = v),
                ),
              ]),
            ),
          ),
          IconButton(
            tooltip: l10n.agentChatClearMemory,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearMemory,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
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
