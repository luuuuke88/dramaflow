// 精简助手页：默认只承载工作流对话；保留的管理能力收进高级面板。
// 被砍功能（custom JS 执行、监督 Agent、RAG 设置）不再从 UI 暴露。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assistant_chat.dart';
import '../../engine/assistant_deploy.dart';
import '../../engine/assistant_skills.dart';
import '../../engine/errors.dart';
import '../../engine/project_notes.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/policy_confirm.dart';

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
  String _family = assistantFamilyScript;

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

  void _setAutoMode(bool value) {
    setState(() => _autoMode = value);
    ref.read(engineProvider).setAssistantAutoMode(value);
  }

  void _setFamily(String family) {
    if (_family == family) return;
    setState(() => _family = family);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: DFTokens.standard200,
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    _scrollToBottom();
    final family = _family;
    try {
      await ref.read(engineProvider).sendAssistantMessage(
            widget.projectId,
            text,
            family: family,
            autoMode: _autoMode,
          );
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _quickSend(String prompt) async {
    if (_sending) return;
    _input.text = prompt;
    await _send();
  }

  Future<void> _clearChat() async {
    final l10n = context.l10n;
    final confirmed = await showDFAdaptiveDialog<bool>(
      context,
      title: l10n.agentChatConfirmClearTitle,
      desktopWidthFactor: .36,
      builder: (_) => const _ClearChatConfirmBody(),
    );
    if (confirmed != true) return;
    ref
        .read(engineProvider)
        .clearAssistantChat(widget.projectId, family: _family);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.agentChatMemoryCleared)),
    );
    setState(() {});
  }

  Future<void> _confirmPending(bool approve) async {
    await ref.read(engineProvider).confirmPendingAssistantAction(
          widget.projectId,
          family: _family,
          approve: approve,
        );
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _showSkillsInfo() {
    final l10n = context.l10n;
    showDFAdaptiveDialog<void>(
      context,
      title: l10n.agentChatSkillsInfo,
      desktopWidthFactor: .38,
      builder: (_) => const _AgentSkillsInfoBody(),
    );
  }

  void _openAdvanced() {
    final l10n = context.l10n;
    showDFAdaptiveDialog<void>(
      context,
      title: l10n.agentChatAdvancedTitle,
      desktopWidthFactor: .56,
      builder: (_) => _AssistantAdvancedPanel(projectId: widget.projectId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final messages = ref.watch(engineProvider).assistantMessages(
          widget.projectId,
          family: _family,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(_family == assistantFamilyScript
            ? l10n.agentDeployGroupScriptAgent
            : l10n.agentDeployGroupProductionAgent),
        actions: [
          IconButton(
            key: const ValueKey('assistant-advanced-button'),
            tooltip: l10n.agentChatAdvanced,
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openAdvanced,
          ),
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
                  _autoMode ? l10n.agentChatAutoMode : l10n.agentChatManualMode,
                  style: const TextStyle(fontSize: 12),
                ),
                Switch(value: _autoMode, onChanged: _setAutoMode),
              ]),
            ),
          ),
          IconButton(
            tooltip: l10n.agentChatClearMemory,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearChat,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              key: const ValueKey('assistant-family-switch'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: assistantFamilyScript,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(
                    l10n.agentDeployGroupScriptAgent,
                    key: const ValueKey('assistant-family-script'),
                  ),
                ),
                ButtonSegment(
                  value: assistantFamilyProduction,
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: Text(
                    l10n.agentDeployGroupProductionAgent,
                    key: const ValueKey('assistant-family-production'),
                  ),
                ),
              ],
              selected: {_family},
              onSelectionChanged: (selection) {
                _setFamily(selection.single);
              },
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (messages.isEmpty)
                _WelcomeBubble(
                  text: _family == assistantFamilyScript
                      ? l10n.agentChatWelcome
                      : l10n.canvasChatWelcome,
                ),
              for (final message in messages)
                _AssistantMessageBubble(
                  message: message,
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.agentChatThinking,
                      style: TextStyle(
                        fontSize: 12,
                        color: df.textTertiary,
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: df.surface,
            border: Border(top: BorderSide(color: df.stroke)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ActionChip(
                        avatar: Icon(Icons.query_stats_rounded,
                            size: 16, color: df.textSecondary),
                        label: Text(l10n.agentChatQuickStatus),
                        onPressed: _sending
                            ? null
                            : () => _quickSend('现在进度如何'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Container(
                          width: 1,
                          height: 16,
                          color: df.stroke,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          l10n.agentChatQuickOrderLabel,
                          style:
                              TextStyle(fontSize: 11, color: df.textTertiary),
                        ),
                      ),
                      for (final entry in [
                        (l10n.agentChatQuickScript, '帮我从事件生成剧本'),
                        (l10n.agentChatQuickAssets, '帮我提取剧本里的资产'),
                        (l10n.agentChatQuickStoryboard, '帮我生成分镜'),
                        (l10n.agentChatQuickShotImage, '帮我生成首帧图'),
                        (l10n.agentChatQuickVideo, '帮我生成视频'),
                        (l10n.agentChatQuickAudio, '帮我绑定配音'),
                        (l10n.agentChatQuickCompose, '帮我合成这一集'),
                      ].indexed)
                        Row(children: [
                          if (entry.$1 > 0)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: df.textTertiary),
                            ),
                          ActionChip(
                            avatar: CircleAvatar(
                              radius: 9,
                              backgroundColor: df.primarySubtle,
                              child: Text(
                                '${entry.$1 + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: df.primary,
                                ),
                              ),
                            ),
                            label: Text(entry.$2.$1),
                            onPressed: _sending
                                ? null
                                : () => _quickSend(entry.$2.$2),
                          ),
                        ]),
                    ],
                  ),
                ),
                Row(children: [
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
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _AssistantAdvancedPanel extends StatelessWidget {
  final int projectId;

  const _AssistantAdvancedPanel({required this.projectId});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 720,
      height: 560,
      child: DefaultTabController(
        length: 3,
        child: Column(children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.agentTabDeploy),
              Tab(text: l10n.agentTabSkills),
              Tab(text: l10n.agentTabMemory),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              const _AssistantDeployPane(),
              const _AssistantSkillsPane(),
              _ProjectNotesPane(projectId: projectId),
            ]),
          ),
        ]),
      ),
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
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  final AssistantMessage message;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _AssistantMessageBubble({
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
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: df.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            border: Border.all(color: df.warning.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.privacy_tip_outlined, size: 16, color: df.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.agentChatConfirmNeeded(message.toolName ?? ''),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: df.textPrimary,
                    ),
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
            ],
          ),
        ),
      );
    }

    if (isTool) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: df.primarySubtle,
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            border: Border.all(color: df.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.bolt, size: 14, color: df.primary),
                const SizedBox(width: 4),
                Text(
                  l10n.agentChatToolExecuted(message.toolName ?? ''),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: df.primary,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(message.content, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: isUser ? df.primary : df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        ),
        child: Text(
          _assistantDisplayText(context, message.content),
          style: TextStyle(
            fontSize: 13,
            color: isUser ? Colors.white : df.textPrimary,
          ),
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

class _ClearChatConfirmBody extends StatelessWidget {
  const _ClearChatConfirmBody();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.agentChatConfirmClearBody),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonDelete),
            ),
          ]),
        ],
      ),
    );
  }
}

class _AgentSkillsInfoBody extends StatelessWidget {
  const _AgentSkillsInfoBody();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.agentChatSkillsBody),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonConfirm),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantDeployPane extends ConsumerWidget {
  const _AssistantDeployPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider);
    final deployments = engine.assistantDeployments();
    final l10n = context.l10n;
    final df = context.df;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.agentDeployStagesTitle,
            style: DFTokens.section16w600.copyWith(color: df.textPrimary)),
        const SizedBox(height: 6),
        Text(l10n.agentDeployStagesHint,
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
        const SizedBox(height: 12),
        for (final deployment in deployments)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(deployment.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deployment.key),
                  Text(
                    deployment.vendorId.isEmpty || deployment.modelName.isEmpty
                        ? l10n.errModelMissing
                        : '${deployment.vendorId}:${deployment.modelName}',
                  ),
                ],
              ),
              trailing: IconButton(
                key: ValueKey('assistant-deploy-edit-${deployment.key}'),
                tooltip: l10n.commonEdit,
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => _editDeployment(context, ref, deployment),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editDeployment(
    BuildContext context,
    WidgetRef ref,
    AssistantDeployment deployment,
  ) async {
    final changed = await showDFAdaptiveDialog<bool>(
      context,
      title: '${context.l10n.agentDeployModel} - ${deployment.key}',
      desktopWidthFactor: .42,
      builder: (_) => _DeployEditBody(deployment: deployment),
    );
    if (changed == true) {
      ref.invalidate(engineProvider);
    }
  }
}

class _DeployEditBody extends ConsumerStatefulWidget {
  final AssistantDeployment deployment;
  const _DeployEditBody({required this.deployment});

  @override
  ConsumerState<_DeployEditBody> createState() => _DeployEditBodyState();
}

class _DeployEditBodyState extends ConsumerState<_DeployEditBody> {
  late final TextEditingController _vendor =
      TextEditingController(text: widget.deployment.vendorId);
  late final TextEditingController _model =
      TextEditingController(text: widget.deployment.modelName);
  late final TextEditingController _maxTokens =
      TextEditingController(text: '${widget.deployment.maxOutputTokens}');
  late final TextEditingController _temperature =
      TextEditingController(text: '${widget.deployment.temperature}');
  late bool _disabled = widget.deployment.disabled;

  @override
  void dispose() {
    _vendor.dispose();
    _model.dispose();
    _maxTokens.dispose();
    _temperature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('assistant-deploy-vendor'),
            controller: _vendor,
            decoration: const InputDecoration(labelText: 'Vendor ID'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('assistant-deploy-model'),
            controller: _model,
            decoration: InputDecoration(labelText: l10n.agentDeployModel),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _maxTokens,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l10n.agentDeployMaxTokens),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _temperature,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l10n.agentDeployTemperature),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disabled'),
            value: _disabled,
            onChanged: (value) => setState(() => _disabled = value),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                try {
                  ref.read(engineProvider).updateAssistantDeployment(
                        widget.deployment.key,
                        vendorId: _vendor.text.trim(),
                        modelName: _model.text.trim(),
                        maxOutputTokens:
                            int.tryParse(_maxTokens.text.trim()) ?? 8000,
                        temperature:
                            int.tryParse(_temperature.text.trim()) ?? 70,
                        disabled: _disabled,
                      );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.agentDeploySaved)),
                  );
                  Navigator.pop(context, true);
                } on EngineException catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizeError(context, e)),
                      backgroundColor: context.df.danger,
                    ),
                  );
                }
              },
              child: Text(l10n.commonSave),
            ),
          ]),
        ],
      ),
    );
  }
}

class _AssistantSkillsPane extends ConsumerWidget {
  const _AssistantSkillsPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider);
    final skills = [...engine.assistantSkills()]..sort((a, b) {
        final aMarkdown = a.type == markdownAssistantSkillType;
        final bMarkdown = b.type == markdownAssistantSkillType;
        if (aMarkdown != bMarkdown) return aMarkdown ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    final l10n = context.l10n;
    final df = context.df;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.agentSkillsBuiltinTitle,
            style: DFTokens.section16w600.copyWith(color: df.textPrimary)),
        const SizedBox(height: 6),
        Text(l10n.agentSkillsEditableHint,
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
        const SizedBox(height: 12),
        for (final skill in skills)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(skill.name),
              subtitle: Text(
                skill.description.isEmpty ? skill.id : skill.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              leading: Icon(
                skill.type == markdownAssistantSkillType
                    ? Icons.article_outlined
                    : Icons.build_circle_outlined,
              ),
              trailing: Switch(
                key: ValueKey('assistant-skill-toggle-${skill.id}'),
                value: skill.enabled,
                onChanged: (value) {
                  engine.updateAssistantSkill(skill.id, enabled: value);
                  ref.invalidate(engineProvider);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectNotesPane extends ConsumerStatefulWidget {
  final int projectId;
  const _ProjectNotesPane({required this.projectId});

  @override
  ConsumerState<_ProjectNotesPane> createState() => _ProjectNotesPaneState();
}

class _ProjectNotesPaneState extends ConsumerState<_ProjectNotesPane> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _editNote([ProjectNote? note]) async {
    final saved = await showDFAdaptiveDialog<bool>(
      context,
      title: note == null
          ? context.l10n.agentMemoryCreateTitle
          : context.l10n.agentMemoryEditTitle,
      desktopWidthFactor: .42,
      builder: (_) => _ProjectNoteEditBody(
        projectId: widget.projectId,
        note: note,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _deleteNote(ProjectNote note) async {
    final engine = ref.read(engineProvider);
    final ok = await confirmPolicyAction(
      context,
      engine.config,
      destructiveKey: 'note_delete',
      description: context.l10n.agentMemoryDeleted,
    );
    if (!ok) return;
    engine.deleteProjectNote(widget.projectId, note.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.agentMemoryDeleted)),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineProvider);
    final l10n = context.l10n;
    final df = context.df;
    final notes = _query.trim().isEmpty
        ? engine.projectNotes(widget.projectId)
        : engine.searchProjectNotes(widget.projectId, _query);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              l10n.agentMemoryCount(notes.length),
              style: DFTokens.section16w600.copyWith(color: df.textPrimary),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _editNote(),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.agentMemoryAdd),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('project-note-search'),
              controller: _search,
              decoration: InputDecoration(
                hintText: l10n.commonSearch,
                isDense: true,
              ),
              onSubmitted: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const ValueKey('project-note-search-button'),
            tooltip: l10n.commonSearch,
            onPressed: () => setState(() => _query = _search.text),
            icon: const Icon(Icons.search_rounded),
          ),
        ]),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          Text(l10n.agentMemoryEmpty, style: TextStyle(color: df.textSecondary))
        else
          for (final note in notes)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title:
                    Text(note.name.isEmpty ? l10n.agentMemoryName : note.name),
                subtitle: Text(note.content),
                onTap: () => _editNote(note),
                trailing: IconButton(
                  key: const ValueKey('project-note-delete'),
                  tooltip: l10n.commonDelete,
                  icon: Icon(Icons.delete_outline_rounded, color: df.danger),
                  onPressed: () => _deleteNote(note),
                ),
              ),
            ),
      ],
    );
  }
}

class _ProjectNoteEditBody extends ConsumerStatefulWidget {
  final int projectId;
  final ProjectNote? note;
  const _ProjectNoteEditBody({required this.projectId, this.note});

  @override
  ConsumerState<_ProjectNoteEditBody> createState() =>
      _ProjectNoteEditBodyState();
}

class _ProjectNoteEditBodyState extends ConsumerState<_ProjectNoteEditBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.note?.name ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.note?.content ?? '');

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('project-note-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.agentMemoryName),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('project-note-content'),
            controller: _content,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(labelText: l10n.agentMemoryContent),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                ref.read(engineProvider).saveProjectNote(
                      widget.projectId,
                      id: widget.note?.id,
                      name: _name.text.trim(),
                      content: _content.text.trim(),
                    );
                Navigator.pop(context, true);
              },
              child: Text(l10n.commonSave),
            ),
          ]),
        ],
      ),
    );
  }
}
