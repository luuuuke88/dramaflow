// 批量生成对话框（照抄 batchGeneration.vue）：mode 1=提示词 / 2=图片。
// 工具栏（已选/全选/清空/搜索/两生成钮）+ 表（预览/名称/提示词行内可编辑）+ 保存已选。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_data_table.dart';
import '../../widgets/df_search_field.dart';
import '../../widgets/df_status_tag.dart';

Future<bool?> showBatchGenerationDialog(BuildContext context, WidgetRef ref,
    {required int projectId, required String type, required int mode}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.assetsBatchHeader,
    desktopWidthFactor: 0.72,
    builder: (c) => _BatchGenerationBody(
        projectId: projectId, type: type, mode: mode, ref: ref),
  );
}

class _BatchGenerationBody extends ConsumerStatefulWidget {
  final int projectId;
  final String type;
  final int mode;
  final WidgetRef ref;
  const _BatchGenerationBody(
      {required this.projectId,
      required this.type,
      required this.mode,
      required this.ref});

  @override
  ConsumerState<_BatchGenerationBody> createState() =>
      _BatchGenerationBodyState();
}

class _BatchGenerationBodyState extends ConsumerState<_BatchGenerationBody> {
  int _page = 1;
  static const _limit = 10;
  String _search = '';
  final Set<String> _selected = {};
  final Map<int, TextEditingController> _promptEdits = {};

  @override
  void dispose() {
    for (final c in _promptEdits.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  TextEditingController _promptCtl(AssetRow row) =>
      _promptEdits.putIfAbsent(row.id, () {
        final c = TextEditingController(text: row.prompt ?? '');
        return c;
      });

  void _savePromptEdits() {
    final engine = ref.read(engineProvider);
    for (final entry in _promptEdits.entries) {
      engine.updateAsset(entry.key, prompt: entry.value.text);
    }
  }

  void _batchPrompt() {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.assetsSelectAtLeastOne);
      return;
    }
    _savePromptEdits();
    ref.read(engineProvider).batchPolishAssetPrompts(
        widget.projectId, _selected.map(int.parse).toList());
    _toast(l10n.assetsBatchPromptDone);
  }

  void _batchImage() {
    final l10n = context.l10n;
    if (_selected.isEmpty) {
      _toast(l10n.assetsSelectAtLeastOne);
      return;
    }
    _savePromptEdits();
    final engine = ref.read(engineProvider);
    final page = engine.batchGenerationData(widget.projectId,
        type: widget.type, page: 1, limit: 10000);
    final byId = {for (final a in page.data) a.id: a};
    final targets = <int>[];
    for (final idStr in _selected) {
      final id = int.parse(idStr);
      final prompt = _promptEdits[id]?.text ?? byId[id]?.prompt ?? '';
      if (prompt.trim().isNotEmpty) targets.add(id);
    }
    if (targets.isEmpty) {
      _toast(l10n.assetsBatchMissingPrompts);
      return;
    }
    engine.generateAssetImages(
      widget.projectId,
      [for (final id in targets) (assetsId: id, refImageBase64: null)],
      concurrentCount: 1,
    );
    _toast(l10n.assetsBatchImageDone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final engine = ref.watch(engineProvider);
    final result = engine.batchGenerationData(widget.projectId,
        type: widget.type,
        page: _page,
        limit: _limit,
        search: _search.isEmpty ? null : _search);

    Widget preview(AssetRow row) {
      if (row.imageState == stateGenerating) {
        return const SizedBox(
            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (row.filePath == null || row.filePath!.isEmpty) {
        return Icon(Icons.image_not_supported_outlined,
            size: 20, color: df.textTertiary);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(engine.mediaAbsPath(row.filePath!)),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              Icon(Icons.broken_image_outlined, color: df.textTertiary),
        ),
      );
    }

    Widget promptCell(AssetRow row) {
      if (row.promptState == stateGenerating) {
        return DFStatusTag(
            kind: DFStatusKind.processing, text: l10n.assetsGenerating);
      }
      final ctl = _promptCtl(row);
      if (row.promptState == stateDone &&
          ctl.text != (row.prompt ?? '') &&
          !ctl.value.selection.isValid) {
        // 引擎已回填新提示词且用户未在编辑 → 同步
        ctl.text = row.prompt ?? '';
      }
      return TextField(
        controller: ctl,
        maxLines: 2,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: l10n.assetsBatchInputPh,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(children: [
          Text(l10n.assetsBatchSelected('${_selected.length}'),
              style: TextStyle(fontSize: 12, color: df.textSecondary)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() => _selected
              ..clear()
              ..addAll(result.data.map((a) => '${a.id}'))),
            child: Text(l10n.assetsBatchSelectAll,
                style: const TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => setState(() => _selected.clear()),
            child: Text(l10n.assetsBatchClearSelection,
                style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          DFSearchField(
            hint: l10n.assetsSearchPlaceholder,
            width: 180,
            onSearch: (q) => setState(() {
              _search = q;
              _page = 1;
            }),
          ),
          const SizedBox(width: 8),
          if (widget.mode == 1)
            FilledButton.icon(
              onPressed: _batchPrompt,
              icon: const Icon(Icons.translate_outlined, size: 16),
              label: Text(l10n.assetsGeneratePrompt,
                  style: const TextStyle(fontSize: 12)),
            )
          else
            FilledButton.icon(
              onPressed: _batchImage,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: Text(l10n.assetsGenerateImage,
                  style: const TextStyle(fontSize: 12)),
            ),
        ]),
      ),
      Flexible(
        child: SizedBox(
          height: 430,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DFDataTable(
              columns: [
                DFDataColumn(label: l10n.assetsBatchColPreviewImg),
                DFDataColumn(label: l10n.assetsColName),
                DFDataColumn(label: l10n.assetsColPrompt),
              ],
              selectable: true,
              selectedIds: _selected,
              onSelectionChanged: (ids) => setState(() => _selected
                ..clear()
                ..addAll(ids)),
              pagination: DFPagination(
                  page: _page, pageSize: _limit, total: result.total),
              onPageChange: (p) => setState(() => _page = p),
              rows: [
                for (final row in result.data)
                  DFDataRow(
                    id: '${row.id}',
                    cells: [
                      preview(row),
                      Text(row.name ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      promptCell(row),
                    ],
                  ),
              ],
              mobileCardBuilder: (c, dfRow) {
                final row =
                    result.data.firstWhere((a) => '${a.id}' == dfRow.id);
                return ListTile(
                  leading: preview(row),
                  title: Text(row.name ?? ''),
                  subtitle: promptCell(row),
                );
              },
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.assetsCancelBtn),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () {
                    _savePromptEdits();
                    _toast(l10n.assetsBatchSaveSuccess);
                    Navigator.of(context).pop(true);
                  },
            child: Text(l10n.assetsBatchSaveSelected('${_selected.length}')),
          ),
        ]),
      ),
    ]);
  }
}
