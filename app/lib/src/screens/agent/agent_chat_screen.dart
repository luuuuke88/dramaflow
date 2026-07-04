// 剧本 Agent 对话页（照抄 scriptAgent 页交互形态，见 P5 参照与 spec §4 决策）：
// 消息列表 + 输入框 + 手动/自动模式切换 + 清空记忆 + 内置能力说明。
// 每次工具调用都是已有真实流水线动作，全部经 o_tasks 队列（任务中心可查可重试），
// 不做多层子代理编排与向量 RAG 记忆——这是 spec 明确的简化范围，非缺陷。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dramaflow/l10n/app_localizations.dart';
import '../../api/models.dart';
import '../../engine/agent.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/common.dart';
import '../../widgets/df_adaptive_dialog.dart';

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
    final confirmed = await showDFAdaptiveDialog<bool>(
      context,
      title: l10n.agentChatConfirmClearTitle,
      desktopWidthFactor: .36,
      builder: (c) => const _AgentClearMemoryConfirmBody(),
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
    showDFAdaptiveDialog<void>(
      context,
      title: l10n.agentChatSkillsInfo,
      desktopWidthFactor: .38,
      builder: (_) => const _AgentSkillsInfoBody(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final messages = ref.watch(engineProvider).agentMessages(widget.projectId);
    final memories =
        ref.watch(engineProvider).agentLongTermMemories(widget.projectId);

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
            _AgentSkillsPane(
              skills: ref.watch(engineProvider).agentSkills(),
              onUpdated: () => setState(() {}),
            ),
            _AgentMemoryPane(
              projectId: widget.projectId,
              messages: messages,
              memories: memories,
              onClear: _clearMemory,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentDeployPane extends ConsumerStatefulWidget {
  final bool autoMode;
  final ValueChanged<bool> onChanged;
  const _AgentDeployPane({required this.autoMode, required this.onChanged});

  @override
  ConsumerState<_AgentDeployPane> createState() => _AgentDeployPaneState();
}

class _AgentDeployPaneState extends ConsumerState<_AgentDeployPane> {
  int _revision = 0;

  Future<List<_AgentModelOption>> _loadModelOptions() async {
    final engine = ref.read(engineProvider);
    final providers = await engine.listProviders();
    final options = <_AgentModelOption>[];
    for (final provider in providers.where((item) => item.enabled)) {
      final models = await engine.listProviderModels(provider.id);
      for (final model
          in models.where((item) => item.enabled && item.kind == 'text')) {
        options.add(_AgentModelOption(provider: provider, model: model));
      }
    }
    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final deployments = ref.watch(engineProvider).agentDeployments();
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
          value: widget.autoMode,
          onChanged: widget.onChanged,
          title: Text(widget.autoMode
              ? l10n.agentChatAutoMode
              : l10n.agentChatManualMode),
          subtitle: Text(l10n.agentDeployModeSaved,
              style: TextStyle(fontSize: 12, color: df.textTertiary)),
          secondary: const Icon(Icons.account_tree_outlined),
        ),
        const SizedBox(height: 18),
        Text(l10n.agentDeployStagesTitle,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: df.textPrimary)),
        const SizedBox(height: 8),
        Text(l10n.agentDeployStagesHint,
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
        const SizedBox(height: 12),
        FutureBuilder<List<_AgentModelOption>>(
          key: ValueKey(_revision),
          future: _loadModelOptions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final options = snapshot.data ?? const <_AgentModelOption>[];
            return Column(
              children: [
                for (final deployment in deployments)
                  _AgentDeployRow(
                    key: ValueKey('agent-deploy-row-${deployment.key}'),
                    deployment: deployment,
                    options: options,
                    onSaved: () => setState(() => _revision++),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AgentModelOption {
  final ProviderInfo provider;
  final ProviderModelInfo model;
  const _AgentModelOption({required this.provider, required this.model});

  String get value => '${provider.id}:${model.modelId}';
  String get label =>
      '${provider.name} · ${model.label.isEmpty ? model.modelId : model.label}';
}

class _AgentDeployRow extends ConsumerStatefulWidget {
  final AgentDeployment deployment;
  final List<_AgentModelOption> options;
  final VoidCallback onSaved;
  const _AgentDeployRow({
    super.key,
    required this.deployment,
    required this.options,
    required this.onSaved,
  });

  @override
  ConsumerState<_AgentDeployRow> createState() => _AgentDeployRowState();
}

class _AgentDeployRowState extends ConsumerState<_AgentDeployRow> {
  late bool _enabled;
  late String? _modelValue;
  late final TextEditingController _maxTokens;
  late final TextEditingController _temperature;

  @override
  void initState() {
    super.initState();
    _syncFromDeployment();
    _maxTokens = TextEditingController(
        text: widget.deployment.maxOutputTokens.toString());
    _temperature =
        TextEditingController(text: widget.deployment.temperature.toString());
  }

  @override
  void didUpdateWidget(covariant _AgentDeployRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deployment.key != widget.deployment.key ||
        oldWidget.deployment.modelName != widget.deployment.modelName ||
        oldWidget.deployment.vendorId != widget.deployment.vendorId ||
        oldWidget.deployment.disabled != widget.deployment.disabled) {
      _syncFromDeployment();
      _maxTokens.text = widget.deployment.maxOutputTokens.toString();
      _temperature.text = widget.deployment.temperature.toString();
    }
  }

  @override
  void dispose() {
    _maxTokens.dispose();
    _temperature.dispose();
    super.dispose();
  }

  void _syncFromDeployment() {
    _enabled = !widget.deployment.disabled;
    final value = widget.deployment.vendorId.isEmpty ||
            widget.deployment.modelName.isEmpty
        ? null
        : '${widget.deployment.vendorId}:${widget.deployment.modelName}';
    final optionValues = widget.options.map((option) => option.value).toSet();
    _modelValue = value != null && optionValues.contains(value) ? value : null;
  }

  String _stageTitle(AppLocalizations l10n, String key) => switch (key) {
        'script_gen' => l10n.stageScriptGenTitle,
        'event_extract' => l10n.stageEventExtractTitle,
        'asset_extract' => l10n.stageAssetExtractTitle,
        'storyboard_gen' => l10n.stageStoryboardGenTitle,
        'video_prompt_gen' => l10n.stageVideoPromptGenTitle,
        _ => key,
      };

  Future<void> _save() async {
    final selected = _modelValue;
    if (selected == null) return;
    final sep = selected.indexOf(':');
    if (sep <= 0 || sep == selected.length - 1) return;
    ref.read(engineProvider).updateAgentDeployment(
          widget.deployment.key,
          vendorId: selected.substring(0, sep),
          modelName: selected.substring(sep + 1),
          maxOutputTokens: int.tryParse(_maxTokens.text.trim()),
          temperature: int.tryParse(_temperature.text.trim()),
          disabled: !_enabled,
        );
    widget.onSaved();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.agentDeploySaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: df.surface,
        border: Border.all(color: df.stroke),
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final title = Row(children: [
            Expanded(
              child: Text(
                _stageTitle(l10n, widget.deployment.key),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Switch(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ]);
          final model = DropdownButtonFormField<String>(
            key: ValueKey('agent-deploy-model-${widget.deployment.key}'),
            initialValue: _modelValue,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.agentDeployModel),
            items: [
              for (final option in widget.options)
                DropdownMenuItem(
                    value: option.value, child: Text(option.label)),
            ],
            onChanged: (value) => setState(() => _modelValue = value),
          );
          final maxTokens = TextField(
            key: ValueKey('agent-deploy-max-tokens-${widget.deployment.key}'),
            controller: _maxTokens,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.agentDeployMaxTokens),
          );
          final temperature = TextField(
            key: ValueKey('agent-deploy-temperature-${widget.deployment.key}'),
            controller: _temperature,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.agentDeployTemperature),
          );
          final save = FilledButton.icon(
            key: ValueKey('agent-deploy-save-${widget.deployment.key}'),
            onPressed: _modelValue == null ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(l10n.commonSave),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 8),
                model,
                const SizedBox(height: 8),
                maxTokens,
                const SizedBox(height: 8),
                temperature,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: save),
              ],
            );
          }
          return Column(
            children: [
              title,
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 4, child: model),
                const SizedBox(width: 10),
                Expanded(child: maxTokens),
                const SizedBox(width: 10),
                Expanded(child: temperature),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: save,
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _AgentSkillsPane extends ConsumerWidget {
  final List<AgentSkill> skills;
  final VoidCallback onUpdated;
  const _AgentSkillsPane({required this.skills, required this.onUpdated});

  Future<void> _editSkill(
      BuildContext context, WidgetRef ref, AgentSkill skill) {
    if (skill.type == 'custom-js-agent') {
      return _openCustomSkillDialog(context, ref, skill: skill);
    }
    return showDFAdaptiveDialog<void>(
      context,
      title: context.l10n.agentSkillEditTitle,
      desktopWidthFactor: .42,
      builder: (_) => _AgentSkillDialog(
        skill: skill,
        onSave: (description, enabled) {
          ref.read(engineProvider).updateAgentSkill(
                skill.id,
                description: description,
                enabled: enabled,
              );
          onUpdated();
        },
      ),
    );
  }

  Future<void> _openCustomSkillDialog(
    BuildContext context,
    WidgetRef ref, {
    AgentSkill? skill,
  }) async {
    final l10n = context.l10n;
    final draft = await showDFAdaptiveDialog<_CustomSkillDraft>(
      context,
      title: skill == null
          ? l10n.agentCustomSkillCreateTitle
          : l10n.agentCustomSkillEditTitle,
      desktopWidthFactor: .5,
      builder: (_) => _AgentCustomSkillDialog(skill: skill),
    );
    if (draft == null || !context.mounted) return;
    await runAction(
      context,
      ref,
      () async {
        ref.read(engineProvider).saveCustomAgentSkill(
              id: draft.id,
              name: draft.name,
              description: draft.description,
              script: draft.script,
              schema: draft.schema,
              enabled: draft.enabled,
            );
        onUpdated();
      },
      successMessage: l10n.agentCustomSkillSaved,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: skills.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(l10n.agentSkillsBuiltinTitle,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: df.textPrimary)),
                ),
                FilledButton.icon(
                  key: const ValueKey('agent-custom-skill-add'),
                  onPressed: () => _openCustomSkillDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.agentCustomSkillAdd),
                ),
              ]),
              const SizedBox(height: 6),
              Text(l10n.agentSkillsEditableHint,
                  style: TextStyle(fontSize: 12, color: df.textSecondary)),
            ],
          );
        }
        final skill = skills[index - 1];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: skill.enabled ? df.surface : df.surfaceMuted,
            border: Border.all(color: df.stroke),
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                skill.enabled
                    ? Icons.bolt_outlined
                    : Icons.power_settings_new_outlined,
                size: 16,
                color: skill.enabled ? df.primary : df.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(skill.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  if (skill.type == 'custom-js-agent') ...[
                    const SizedBox(width: 8),
                    Text(
                      l10n.agentCustomSkillTag,
                      style: TextStyle(fontSize: 11, color: df.primary),
                    ),
                  ],
                ]),
              ),
              Text(
                skill.enabled
                    ? l10n.agentSkillEnabledTag
                    : l10n.agentSkillDisabledTag,
                style: TextStyle(fontSize: 11, color: df.textTertiary),
              ),
              IconButton(
                key: ValueKey('agent-skill-edit-${skill.id}'),
                tooltip: l10n.commonEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editSkill(context, ref, skill),
              ),
            ]),
            const SizedBox(height: 6),
            Text(skill.description,
                style: TextStyle(fontSize: 12, color: df.textSecondary)),
          ]),
        );
      },
    );
  }
}

class _CustomSkillDraft {
  final String id;
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  final String script;
  final bool enabled;

  const _CustomSkillDraft({
    required this.id,
    required this.name,
    required this.description,
    required this.schema,
    required this.script,
    required this.enabled,
  });
}

class _AgentCustomSkillDialog extends StatefulWidget {
  final AgentSkill? skill;
  const _AgentCustomSkillDialog({this.skill});

  @override
  State<_AgentCustomSkillDialog> createState() =>
      _AgentCustomSkillDialogState();
}

class _AgentCustomSkillDialogState extends State<_AgentCustomSkillDialog> {
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _schema = TextEditingController();
  final TextEditingController _script = TextEditingController();
  bool _enabled = true;
  String? _schemaError;

  @override
  void initState() {
    super.initState();
    final skill = widget.skill;
    if (skill != null) {
      _id.text = skill.id;
      _name.text = skill.name;
      _description.text = skill.description;
      _schema.text = skill.schema.isEmpty ? '{}' : jsonEncode(skill.schema);
      _script.text = skill.script;
      _enabled = skill.enabled;
    } else {
      _schema.text = '{"type":"object","properties":{}}';
      _script.text = r'return JSON.stringify(args);';
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _description.dispose();
    _schema.dispose();
    _script.dispose();
    super.dispose();
  }

  void _save() {
    final id = _id.text.trim();
    final script = _script.text.trim();
    if (id.isEmpty || script.isEmpty) return;
    final decoded = _decodeSchema();
    if (decoded == null) return;
    Navigator.pop(
      context,
      _CustomSkillDraft(
        id: id,
        name: _name.text.trim(),
        description: _description.text.trim(),
        schema: decoded,
        script: script,
        enabled: _enabled,
      ),
    );
  }

  Map<String, dynamic>? _decodeSchema() {
    try {
      final decoded =
          jsonDecode(_schema.text.trim().isEmpty ? '{}' : _schema.text.trim());
      if (decoded is Map) {
        setState(() => _schemaError = null);
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    setState(() => _schemaError = context.l10n.agentCustomSkillInvalidSchema);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.skill != null;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('agent-custom-skill-id-field'),
                    controller: _id,
                    readOnly: editing,
                    decoration: InputDecoration(
                      labelText: l10n.agentCustomSkillId,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('agent-custom-skill-name-field'),
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: l10n.agentCustomSkillName,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('agent-custom-skill-description-field'),
                    controller: _description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l10n.agentSkillDescription,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('agent-custom-skill-schema-field'),
                    controller: _schema,
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: l10n.agentCustomSkillSchema,
                      alignLabelWithHint: true,
                      errorText: _schemaError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('agent-custom-skill-script-field'),
                    controller: _script,
                    minLines: 4,
                    maxLines: 8,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: l10n.agentCustomSkillScript,
                      helperText: l10n.agentCustomSkillScriptHint,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                    title: Text(l10n.agentSkillEnabled),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentSkillDialog extends StatefulWidget {
  final AgentSkill skill;
  final void Function(String description, bool enabled) onSave;
  const _AgentSkillDialog({required this.skill, required this.onSave});

  @override
  State<_AgentSkillDialog> createState() => _AgentSkillDialogState();
}

class _AgentSkillDialogState extends State<_AgentSkillDialog> {
  late final TextEditingController _description;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: widget.skill.description);
    _enabled = widget.skill.enabled;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.skill.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('agent-skill-description-field'),
                    controller: _description,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: l10n.agentSkillDescription,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('agent-skill-enabled-switch'),
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                    title: Text(l10n.agentSkillEnabled),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  widget.onSave(_description.text.trim(), _enabled);
                  Navigator.pop(context);
                },
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentMemoryPane extends ConsumerWidget {
  final int projectId;
  final List<AgentMessage> messages;
  final List<AgentMemoryRecord> memories;
  final VoidCallback onClear;
  final VoidCallback onChanged;
  const _AgentMemoryPane({
    required this.projectId,
    required this.messages,
    required this.memories,
    required this.onClear,
    required this.onChanged,
  });

  Future<void> _addMemory(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final draft = await showDFAdaptiveDialog<_MemoryDraft>(
      context,
      title: l10n.agentMemoryCreateTitle,
      desktopWidthFactor: .42,
      builder: (_) => const _AgentMemoryDialog(),
    );
    if (draft == null || !context.mounted) return;
    await runAction(
      context,
      ref,
      () async {
        ref.read(engineProvider).saveAgentMemory(
              projectId,
              name: draft.name,
              content: draft.content,
            );
        onChanged();
      },
      successMessage: l10n.agentMemorySaved,
    );
  }

  Future<void> _editMemory(
    BuildContext context,
    WidgetRef ref,
    AgentMemoryRecord memory,
  ) async {
    final l10n = context.l10n;
    final draft = await showDFAdaptiveDialog<_MemoryDraft>(
      context,
      title: l10n.agentMemoryEditTitle,
      desktopWidthFactor: .42,
      builder: (_) => _AgentMemoryDialog(memory: memory),
    );
    if (draft == null || !context.mounted) return;
    await runAction(
      context,
      ref,
      () async {
        ref.read(engineProvider).saveAgentMemory(
              projectId,
              id: memory.id,
              name: draft.name,
              content: draft.content,
            );
        onChanged();
      },
      successMessage: l10n.agentMemoryUpdated,
    );
  }

  Future<void> _deleteMemory(
    BuildContext context,
    WidgetRef ref,
    AgentMemoryRecord memory,
  ) async {
    final l10n = context.l10n;
    await runAction(
      context,
      ref,
      () async {
        ref.read(engineProvider).deleteAgentMemory(projectId, memory.id);
        onChanged();
      },
      successMessage: l10n.agentMemoryDeleted,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AgentRagLimitCard(onChanged: onChanged),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Text(l10n.agentLongTermMemoryCount(memories.length),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: df.textPrimary)),
          ),
          FilledButton.icon(
            onPressed: () => _addMemory(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.agentMemoryAdd),
          ),
        ]),
        const SizedBox(height: 10),
        if (memories.isEmpty)
          Text(l10n.agentLongTermMemoryEmpty,
              style: TextStyle(fontSize: 12, color: df.textTertiary))
        else
          for (final memory in memories)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: df.surface,
                border: Border.all(color: df.stroke),
                borderRadius: BorderRadius.circular(DFTokens.radiusCard),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(memory.name,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: df.textPrimary)),
                        const SizedBox(height: 4),
                        Text(memory.content,
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('agent-memory-edit-${memory.id}'),
                    tooltip: l10n.commonEdit,
                    onPressed: () => _editMemory(context, ref, memory),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    key: ValueKey('agent-memory-delete-${memory.id}'),
                    tooltip: l10n.commonDelete,
                    onPressed: () => _deleteMemory(context, ref, memory),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 20),
        Divider(color: df.stroke),
        const SizedBox(height: 12),
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

class _AgentRagLimitCard extends ConsumerStatefulWidget {
  final VoidCallback onChanged;
  const _AgentRagLimitCard({required this.onChanged});

  @override
  ConsumerState<_AgentRagLimitCard> createState() => _AgentRagLimitCardState();
}

class _AgentRagLimitCardState extends ConsumerState<_AgentRagLimitCard> {
  late final TextEditingController _limitCtrl;

  @override
  void initState() {
    super.initState();
    _limitCtrl = TextEditingController(
      text: ref.read(engineProvider).agentRagLimit().toString(),
    );
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final value = int.tryParse(_limitCtrl.text.trim());
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agentRagLimitInvalid)),
      );
      return;
    }
    await runAction(
      context,
      ref,
      () async {
        ref.read(engineProvider).setAgentRagLimit(value);
        _limitCtrl.text = ref.read(engineProvider).agentRagLimit().toString();
        widget.onChanged();
      },
      successMessage: l10n.agentRagLimitSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: df.surface,
        border: Border.all(color: df.stroke),
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.agentRagLimitTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: df.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.agentRagLimitHelp,
            style: TextStyle(fontSize: 12, color: df.textTertiary),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: TextField(
                  key: const ValueKey('agent-rag-limit-field'),
                  controller: _limitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '0-50',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const ValueKey('agent-rag-limit-save'),
                onPressed: _save,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryDraft {
  final String name;
  final String content;
  const _MemoryDraft({required this.name, required this.content});
}

class _AgentMemoryDialog extends StatefulWidget {
  final AgentMemoryRecord? memory;
  const _AgentMemoryDialog({this.memory});

  @override
  State<_AgentMemoryDialog> createState() => _AgentMemoryDialogState();
}

class _AgentMemoryDialogState extends State<_AgentMemoryDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _content = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _name.text = widget.memory?.name ?? '';
    _content.text = widget.memory?.content ?? '';
  }

  void _save() {
    final content = _content.text.trim();
    if (content.isEmpty) return;
    Navigator.pop(
      context,
      _MemoryDraft(name: _name.text.trim(), content: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('agent-memory-name-field'),
                    controller: _name,
                    decoration:
                        InputDecoration(labelText: l10n.agentMemoryName),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('agent-memory-content-field'),
                    controller: _content,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: l10n.agentMemoryContent,
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
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
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonConfirm),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentClearMemoryConfirmBody extends StatelessWidget {
  const _AgentClearMemoryConfirmBody();

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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: context.df.danger),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.commonDelete),
              ),
            ],
          ),
        ],
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
