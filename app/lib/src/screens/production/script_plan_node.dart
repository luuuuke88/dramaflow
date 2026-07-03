// 剧本规划节点（照抄 ToonFlow production/node/scriptPlan.vue：制作画布上的
// Markdown 文档节点，展示已存规划预览，点击打开编辑对话框改写并持久化）。
// 数据经 engine.scriptPlan(load) / engine.saveScriptPlan(save)，project 级，
// 存 o_agentWorkData(key='scriptPlan')。Markdown 以纯文本源码编辑（与 ToonFlow
// 存储形态一致），预览区渲染为轻量样式的纯文本。
// engine 是可变单例、无监听机制，故本节点自持 state：保存后 setState 重读预览。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/script_plan.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

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
    final markdown = ref.read(engineProvider).scriptPlan(widget.projectId);
    final hasPlan = markdown.trim().isNotEmpty;

    return _NodeFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _NodeHeader(
          title: l10n.productionNodeScriptPlanTitle,
          onEdit: () => _openEditor(markdown),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _openEditor(markdown),
            child: hasPlan
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Text(
                        markdown,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  )
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notes_outlined,
                          color: df.textTertiary, size: 22),
                      const SizedBox(height: 8),
                      Text(l10n.scriptPlanEmpty,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: df.textTertiary)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _openEditor(markdown),
                        icon: const Icon(Icons.edit_note, size: 16),
                        label: Text(l10n.scriptPlanWrite,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
          ),
        ),
      ]),
    );
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
    ref
        .read(engineProvider)
        .saveScriptPlan(widget.projectId, _controller.text);
    if (!mounted) return;
    final l10n = context.l10n;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.scriptPlanSaved)));
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

class _NodeFrame extends StatelessWidget {
  final Widget child;
  const _NodeFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.stroke),
        boxShadow: DFTokens.cardRest,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _NodeHeader extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  const _NodeHeader({required this.title, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      color: df.textPrimary,
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: df.surface)),
        ),
        IconButton(
          tooltip: context.l10n.commonEdit,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(Icons.edit_outlined, size: 15, color: df.surface),
          onPressed: onEdit,
        ),
      ]),
    );
  }
}
