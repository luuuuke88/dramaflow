// 剧本 Agent 对话页（照抄 scriptAgent 页交互形态，见 P5 参照与 spec §4 决策）：
// 消息列表 + 输入框 + 手动/自动模式切换 + 清空记忆 + 内置能力说明。
// 每次工具调用都是已有真实流水线动作，全部经 o_tasks 队列（任务中心可查可重试），
// 不做多层子代理编排与向量 RAG 记忆——这是 spec 明确的简化范围，非缺陷。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/agent.dart';
import '../../engine/providers/openai_text.dart' show AgentToolDef;
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
  void initState() {
    super.initState();
    // auto/manual 模式持久化：从引擎载入上次选择（默认 manual）。
    _autoMode = ref.read(engineProvider).agentUseMode();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setAutoMode(bool value) {
    setState(() => _autoMode = value);
    ref.read(engineProvider).setAgentUseMode(value);
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
        content: SizedBox(width: 420, child: Text(l10n.agentChatSkillsBody)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l10n.commonConfirm)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final messages = ref.watch(engineProvider).agentMessages(widget.projectId);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.agentChatTitle),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.agentTabChat),
              Tab(text: l10n.agentTabDeploy),
              Tab(text: l10n.agentTabSkills),
              Tab(text: l10n.agentTabMemory),
            ],
          ),
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
                    onChanged: _setAutoMode,
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
        body: TabBarView(
          children: [
            Column(children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (messages.isEmpty)
                      _WelcomeBubble(text: l10n.agentChatWelcome),
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
                              style: TextStyle(
                                  fontSize: 12, color: df.textTertiary)),
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
            _AgentDeployPane(autoMode: _autoMode, onChanged: _setAutoMode),
            _AgentSkillsPane(tools: ref.watch(engineProvider).agentTools),
            _AgentMemoryPane(messages: messages, onClear: _clearMemory),
          ],
        ),
      ),
    );
  }
}

class _AgentDeployPane extends StatelessWidget {
  final bool autoMode;
  final ValueChanged<bool> onChanged;
  const _AgentDeployPane({required this.autoMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.agentDeployExecutionMode,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: df.textPrimary)),
        const SizedBox(height: 8),
        Text(l10n.agentChatModeHint,
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const ValueKey('agent-deploy-mode-switch'),
          value: autoMode,
          onChanged: onChanged,
          title: Text(
              autoMode ? l10n.agentChatAutoMode : l10n.agentChatManualMode),
          subtitle: Text(l10n.agentDeployModeSaved,
              style: TextStyle(fontSize: 12, color: df.textTertiary)),
          secondary: const Icon(Icons.account_tree_outlined),
        ),
      ],
    );
  }
}

class _AgentSkillsPane extends StatelessWidget {
  final List<AgentToolDef> tools;
  const _AgentSkillsPane({required this.tools});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tools.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.agentSkillsBuiltinTitle,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: df.textPrimary)),
              const SizedBox(height: 6),
              Text(l10n.agentChatSkillsBody,
                  style: TextStyle(fontSize: 12, color: df.textSecondary)),
            ],
          );
        }
        final tool = tools[index - 1];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: df.surface,
            border: Border.all(color: df.stroke),
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bolt_outlined, size: 16, color: df.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tool.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(tool.description,
                style: TextStyle(fontSize: 12, color: df.textSecondary)),
          ]),
        );
      },
    );
  }
}

class _AgentMemoryPane extends StatelessWidget {
  final List<AgentMessage> messages;
  final VoidCallback onClear;
  const _AgentMemoryPane({required this.messages, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child: Text(l10n.agentMemoryCount(messages.length),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: df.textPrimary)),
          ),
          FilledButton.tonalIcon(
            onPressed: messages.isEmpty ? null : onClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(l10n.agentChatClearMemory),
          ),
        ]),
        const SizedBox(height: 10),
        if (messages.isEmpty)
          Text(l10n.agentMemoryEmpty,
              style: TextStyle(fontSize: 12, color: df.textTertiary))
        else
          for (final message in messages)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: df.surface,
                border: Border.all(color: df.stroke),
                borderRadius: BorderRadius.circular(DFTokens.radiusCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.role,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: df.textTertiary)),
                  const SizedBox(height: 4),
                  Text(message.content, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
      ],
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
        child: Text(
          message.content,
          style: TextStyle(
              fontSize: 13, color: isUser ? Colors.white : df.textPrimary),
        ),
      ),
    );
  }
}
