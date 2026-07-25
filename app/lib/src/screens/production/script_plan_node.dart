// 剧本规划节点（照抄 ToonFlow production/node/scriptPlan.vue：制作画布上的
// Markdown 文档节点，展示已存规划预览，点击打开编辑对话框改写并持久化）。
// 数据经 engine.scriptPlan(load) / engine.saveScriptPlan(save)，project 级，
// 存 o_agentWorkData(key='scriptPlan')。Markdown 以纯文本源码编辑（与 ToonFlow
// 存储形态一致），预览区渲染为轻量样式的纯文本。
// engine 是可变单例、无监听机制，故本节点自持 state：保存后 setState 重读预览。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/production_dependencies.dart';
import '../../engine/script_plan.dart';
import '../../engine/scripts.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/policy_confirm.dart';
import 'production_node_card.dart';
import '../../widgets/df_canvas.dart';
import '../../widgets/df_toast.dart';

/// 剧本规划节点卡片。桌面（画布节点）与移动端（Tab 内容）共用同一实现。
class ScriptPlanNode extends ConsumerStatefulWidget {
  final int projectId;
  const ScriptPlanNode({super.key, required this.projectId});

  @override
  ConsumerState<ScriptPlanNode> createState() => _ScriptPlanNodeState();
}

class _ScriptPlanNodeState extends ConsumerState<ScriptPlanNode> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final engine = ref.read(engineProvider);
    final markdown = engine.scriptPlan(widget.projectId);
    final hasPlan = markdown.trim().isNotEmpty;
    final canGenerate = engine.scripts(widget.projectId).isNotEmpty;
    final stale = hasPlan &&
        engine
            .productionDependencyState(
              widget.projectId,
              directorPlanStateKey,
            )
            .stale;

    return ProductionNodeCard(
      stage: ProductionStage.scriptPlan,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProductionNodeHeader(
          stage: ProductionStage.scriptPlan,
          // 铅笔就是「撰写/编辑」这一个动作，提示文字写具体，
          // 免得空状态里没了正文按钮就找不到入口。
          editTooltip: l10n.scriptPlanWrite,
          title: l10n.productionNodeScriptPlanTitle,
          onEdit: () => _openEditor(markdown),
          // 空状态中间已经有一个更醒目的「生成」，标题栏这个只在有内容时
          // 出现，那时它的语义是「重新生成」，不再重复。
          action: !hasPlan
              ? null
              : Tooltip(
                  message: l10n.directorPlanGenerateTooltip,
                  child: FilledButton.icon(
                    key: const Key('script-plan-generate'),
                    onPressed: canGenerate ? _generatePlan : null,
                    icon: const Icon(Icons.auto_awesome, size: 13),
                    label: Text(
                      hasPlan
                          ? l10n.directorPlanRegenerate
                          : l10n.directorPlanGenerate,
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
        ),
        if (stale)
          Container(
            key: const Key('script-plan-stale'),
            width: double.infinity,
            color: df.warning.withValues(alpha: .12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              l10n.productionNeedsRegeneration,
              style: TextStyle(fontSize: 11, color: df.warning),
            ),
          ),
        Expanded(
          child: InkWell(
            onTap: () => _openEditor(markdown),
            child: hasPlan
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: DFCanvasScrollRegion(
                      child: SingleChildScrollView(
                        child: Text(
                          markdown,
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ),
                    ))
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notes_outlined,
                          color: df.textTertiary, size: 22),
                      const SizedBox(height: 8),
                      Text(l10n.scriptPlanEmpty,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: df.textTertiary)),
                      const SizedBox(height: 12),
                      // 空状态里「让 AI 生成」才是主动作，放中间当主按钮；
                      // 手写降为次要。原先反过来：生成缩在标题栏角落，
                      // 中间的大蓝按钮却是手写。
                      FilledButton.icon(
                        key: const Key('script-plan-generate-empty'),
                        onPressed: canGenerate ? _generatePlan : null,
                        icon: const Icon(Icons.auto_awesome, size: 15),
                        label: Text(l10n.directorPlanGenerate,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _generatePlan() async {
    final engine = ref.read(engineProvider);
    final allowed = await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'director_plan_generation',
      description: context.l10n.directorPlanGenerateDescription,
    );
    if (!allowed || !mounted) return;
    final taskId = engine.generateDirectorPlan(widget.projectId);
    if (taskId == 0) return;
    ref.read(activeJobsProvider.notifier).poke();
    showDFToast(context, context.l10n.directorPlanGenerating);
  }

  Future<void> _openEditor(String current) async {
    final saved = await showDFAdaptiveDialog<bool>(
      context,
      title: context.l10n.scriptPlanEditTitle,
      builder: (dialogContext) => _ScriptPlanEditor(
        projectId: widget.projectId,
        initial: current,
      ),
    );
    // 保存后重读预览（engine 无响应式，需手动 rebuild）。
    if (saved == true && mounted) setState(() {});
  }
}

class _ScriptPlanEditor extends ConsumerStatefulWidget {
  final int projectId;
  final String initial;
  const _ScriptPlanEditor({
    required this.projectId,
    required this.initial,
  });

  @override
  ConsumerState<_ScriptPlanEditor> createState() => _ScriptPlanEditorState();
}

class _ScriptPlanEditorState extends ConsumerState<_ScriptPlanEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(engineProvider).saveScriptPlan(widget.projectId, _controller.text);
    if (!mounted) return;
    final l10n = context.l10n;
    Navigator.of(context).pop(true);
    showDFToast(context, l10n.scriptPlanSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: TextField(
            controller: _controller,
            minLines: 8,
            maxLines: 20,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: l10n.scriptPlanEditHint,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: DFTokens.s12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: DFTokens.s8),
          FilledButton(
            onPressed: _save,
            child: Text(l10n.commonSave),
          ),
        ]),
      ]),
    );
  }
}
