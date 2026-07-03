// 剧本管理页（照抄 views/script/index.vue）：
// 工具栏【搜索+搜索钮｜新增剧本｜批量添加 ‖ 全选↔取消全选｜导出+数｜提取资产+数｜删除+数】
// + 400px 卡片流（名称+复选/内容一行/资产 tag/提取四态/悬停删除），点卡开编辑。
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scripts.dart';
import '../../engine/events.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_search_field.dart';
import '../../widgets/df_status_tag.dart';
import '../../widgets/df_tag_chip.dart';
import 'add_script_dialog.dart';
import 'batch_add_dialog.dart';
import 'edit_script_dialog.dart';

class ScriptScreen extends ConsumerStatefulWidget {
  final int projectId;
  const ScriptScreen({super.key, required this.projectId});

  @override
  ConsumerState<ScriptScreen> createState() => _ScriptScreenState();
}

class _ScriptScreenState extends ConsumerState<ScriptScreen> {
  String _search = '';
  final Set<int> _selected = {};

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _batchDelete(List<ScriptRow> all) async {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.scriptMsgSelectDelScript);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.scriptMsgBatchDeleteHeader),
        content: Text(l10n.scriptMsgBatchDeleteBody('${_selected.length}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.scriptMsgCancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.scriptMsgDeleteConfirm)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).deleteScripts(_selected.toList());
    setState(() => _selected.clear());
    _toast(l10n.scriptMsgBatchDeleteSuccess);
  }

  Future<void> _export() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.scriptMsgSelectExport);
      return;
    }
    try {
      final bytes = ref.read(engineProvider).exportScripts(_selected.toList());
      final location = await fs
          .getSaveLocation(suggestedName: 'scripts.zip', acceptedTypeGroups: [
        const fs.XTypeGroup(label: 'zip', extensions: ['zip'])
      ]);
      if (location == null) return;
      final file = fs.XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: 'application/zip',
        name: 'scripts.zip',
      );
      await file.saveTo(location.path);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    }
  }

  void _extract() {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.scriptMsgSelectDelScript);
      return;
    }
    ref
        .read(engineProvider)
        .extractAssets(_selected.toList(), widget.projectId);
    _toast(l10n.scriptMsgExtracting);
  }

  Future<void> _generateFromEvents() async {
    final l10n = context.l10n;
    final picked = await showDFAdaptiveDialog<List<int>>(
      context,
      title: l10n.scriptGenerateFromEventsTitle,
      desktopWidthFactor: 0.56,
      builder: (_) => _EventScriptPicker(projectId: widget.projectId, ref: ref),
    );
    if (!mounted || picked == null) return;
    if (picked.isEmpty) {
      _toast(l10n.scriptGenerateFromEventsSelectHint);
      return;
    }
    ref
        .read(engineProvider)
        .generateScriptsFromEvents(widget.projectId, picked);
    _toast(l10n.scriptGenerateFromEventsSubmitted);
  }

  Widget _stateArea(ScriptRow row) {
    final l10n = context.l10n;
    switch (row.extractState) {
      case 0:
        return DFStatusTag(
            kind: DFStatusKind.processing, text: l10n.scriptStateExtracting);
      case 2:
        return DFStatusTag(
            kind: DFStatusKind.pending, text: l10n.scriptStateWaiting);
      case -1:
        return Tooltip(
          message: localizeReason(l10n, row.errorReason) ?? '',
          child: DFStatusTag(
              kind: DFStatusKind.failed, text: l10n.scriptStateFailed),
        );
      default:
        if (row.relatedAssets.isEmpty) return const SizedBox.shrink();
        return Wrap(spacing: 6, runSpacing: 6, children: [
          for (final asset in row.relatedAssets.take(6))
            DFTagChip(label: asset.name),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(activeJobsProvider);
    ref.watch(jobsGenerationProvider);
    final scripts = ref
        .watch(engineProvider)
        .scripts(widget.projectId, search: _search.isEmpty ? null : _search);
    final allSelected =
        scripts.isNotEmpty && _selected.length == scripts.length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          Future<void> openAdd() async {
            final saved = await showAddScriptDialog(context, ref,
                projectId: widget.projectId);
            if (saved == true) setState(() {});
          }

          Future<void> openBatchAdd() async {
            final saved = await showBatchAddDialog(context, ref,
                projectId: widget.projectId);
            if (saved == true) setState(() {});
          }

          final primaryActions = <Widget>[
            FilledButton.icon(
              onPressed: openAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.scriptAddScript),
            ),
            FilledButton.icon(
              onPressed: openBatchAdd,
              icon: const Icon(Icons.library_add_outlined, size: 18),
              label: Text(l10n.scriptBatchAdd),
            ),
            OutlinedButton.icon(
              onPressed: _generateFromEvents,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(l10n.scriptGenerateFromEvents),
            ),
          ];
          final batchActions = scripts.isEmpty
              ? <Widget>[]
              : <Widget>[
                  OutlinedButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(scripts.map((s) => s.id));
                      }
                    }),
                    child: Text(allSelected
                        ? l10n.scriptCancelSelectAll
                        : l10n.scriptSelectAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: _export,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(_selected.isEmpty
                        ? l10n.scriptExportScript
                        : '${l10n.scriptExportScript} (${_selected.length})'),
                  ),
                  FilledButton.icon(
                    onPressed: _extract,
                    icon: const Icon(Icons.category_outlined, size: 18),
                    label: Text(_selected.isEmpty
                        ? l10n.scriptExtractAssets
                        : '${l10n.scriptExtractAssets} (${_selected.length})'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _batchDelete(scripts),
                    style: FilledButton.styleFrom(backgroundColor: df.danger),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(_selected.isEmpty
                        ? l10n.commonDelete
                        : '${l10n.commonDelete} (${_selected.length})'),
                  ),
                ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DFSearchField(
                  hint: l10n.scriptSearchPlaceholder,
                  width: constraints.maxWidth,
                  onSearch: (q) => setState(() => _search = q),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [...primaryActions, ...batchActions],
                ),
              ],
            );
          }

          return Row(children: [
            DFSearchField(
              hint: l10n.scriptSearchPlaceholder,
              width: 240,
              onSearch: (q) => setState(() => _search = q),
            ),
            const SizedBox(width: 10),
            ...primaryActions
                .expand((button) => [button, const SizedBox(width: 8)]),
            const Spacer(),
            ...batchActions
                .expand((button) => [button, const SizedBox(width: 8)]),
          ]);
        }),
      ),
      Expanded(
        child: scripts.isEmpty
            ? Center(
                child: DFEmpty(
                  text: l10n.scriptAddNoAssets,
                  action: FilledButton.icon(
                    onPressed: () async {
                      final saved = await showAddScriptDialog(context, ref,
                          projectId: widget.projectId);
                      if (saved == true) setState(() {});
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.scriptAddScript),
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Wrap(spacing: 16, runSpacing: 16, children: [
                  for (final row in scripts)
                    _ScriptCard(
                      row: row,
                      selected: _selected.contains(row.id),
                      onToggleSelect: (v) => setState(() {
                        if (v == true) {
                          _selected.add(row.id);
                        } else {
                          _selected.remove(row.id);
                        }
                      }),
                      onOpen: () async {
                        final saved = await showEditScriptDialog(context, ref,
                            projectId: widget.projectId, row: row);
                        if (saved == true) setState(() {});
                      },
                      onDelete: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(l10n.scriptMsgDeleteHeader),
                            content: Text(l10n.scriptMsgDeleteBody),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: Text(l10n.scriptMsgCancel)),
                              FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: df.danger),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: Text(l10n.scriptMsgDeleteConfirm)),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          ref.read(engineProvider).deleteScripts([row.id]);
                          setState(() => _selected.remove(row.id));
                          _toast(l10n.scriptMsgDeleteSuccess);
                        }
                      },
                      stateArea: _stateArea(row),
                    ),
                ]),
              ),
      ),
    ]);
  }
}

class _EventScriptPicker extends StatefulWidget {
  final int projectId;
  final WidgetRef ref;
  const _EventScriptPicker({required this.projectId, required this.ref});

  @override
  State<_EventScriptPicker> createState() => _EventScriptPickerState();
}

class _EventScriptPickerState extends State<_EventScriptPicker> {
  late final List<EventRow> _events =
      widget.ref.read(engineProvider).events(widget.projectId, limit: 999).list;
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: _events.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(l10n.scriptGenerateFromEventsEmpty,
                      style: TextStyle(fontSize: 13, color: df.textTertiary)),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                itemCount: _events.length,
                separatorBuilder: (_, __) => Divider(color: df.stroke),
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return CheckboxListTile(
                    value: _selected.contains(event.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(event.id);
                      } else {
                        _selected.remove(event.id);
                      }
                    }),
                    title: Text(event.name ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(event.detail ?? '',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: Text(l10n.scriptGenerateFromEventsConfirm),
          ),
        ]),
      ),
    ]);
  }
}

class _ScriptCard extends StatefulWidget {
  final ScriptRow row;
  final bool selected;
  final ValueChanged<bool?> onToggleSelect;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final Widget stateArea;
  const _ScriptCard(
      {required this.row,
      required this.selected,
      required this.onToggleSelect,
      required this.onOpen,
      required this.onDelete,
      required this.stateArea});

  @override
  State<_ScriptCard> createState() => _ScriptCardState();
}

class _ScriptCardState extends State<_ScriptCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final row = widget.row;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: DFTokens.fast120,
          width: 400,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: df.surface,
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            border: Border.all(
                color: widget.selected
                    ? df.primary
                    : (_hover ? df.strokeStrong : df.stroke)),
            boxShadow: _hover ? DFTokens.cardHover : DFTokens.cardRest,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(row.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Checkbox(
                  value: widget.selected, onChanged: widget.onToggleSelect),
            ]),
            const SizedBox(height: 4),
            Text(row.content ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: df.textSecondary)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: widget.stateArea),
              AnimatedOpacity(
                duration: DFTokens.fast120,
                opacity: _hover ? 1 : 0,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.l10n.commonDelete,
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: df.textSecondary),
                  onPressed: widget.onDelete,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
