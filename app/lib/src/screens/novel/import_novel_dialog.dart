// 导入原文对话框（照抄 importNovel.vue 分步流程）：
// 第一步＝上传(.txt/.docx≤10MB)或粘贴 + 实时解析章节数 + 字数警示；
// 第二步＝章节选择表 + 已勾选字数 + 保存原文并分析事件（保存后自动触发事件生成）；
// 第三步＝完成提示（事件生成中）。
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/errors.dart';
import '../../engine/novel.dart';
import '../../engine/novel_parse.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_data_table.dart';

const _maxFileBytes = 10 * 1024 * 1024;

Future<bool?> showImportNovelDialog(BuildContext context, WidgetRef ref,
    {required int projectId}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.novelImportTitle,
    desktopWidthFactor: 0.56,
    builder: (c) => _ImportNovelBody(projectId: projectId, ref: ref),
  );
}

class _ImportNovelBody extends StatefulWidget {
  final int projectId;
  final WidgetRef ref;
  const _ImportNovelBody({required this.projectId, required this.ref});

  @override
  State<_ImportNovelBody> createState() => _ImportNovelBodyState();
}

class _ImportNovelBodyState extends State<_ImportNovelBody> {
  int _step = 0;
  final TextEditingController _content = TextEditingController();
  List<ChapterItem> _parsed = const [];
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _reparse() {
    try {
      // 使用用户自定义章节正则（其他设置 chapterReg；空则用内置默认）。
      final chapterReg =
          widget.ref.read(engineProvider).config.str('chapterReg');
      _parsed =
          flattenParsedNovel(parseNovel(_content.text, chapterReg: chapterReg));
    } catch (_) {
      _parsed = const [];
    }
    setState(() {});
  }

  Future<void> _pickFile() async {
    final l10n = context.l10n;
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'novel', extensions: ['txt', 'docx'])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxFileBytes) {
      _toast(l10n.novelImportMsgFileTooLarge);
      return;
    }
    try {
      final name = file.name.toLowerCase();
      if (name.endsWith('.docx')) {
        _content.text = extractDocxText(bytes);
      } else if (name.endsWith('.txt')) {
        _content.text = utf8.decode(bytes, allowMalformed: true);
      } else {
        _toast(l10n.novelImportMsgUnsupportedType);
        return;
      }
      _reparse();
    } on EngineException catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } catch (_) {
      if (mounted) _toast(l10n.novelImportMsgParseFailed);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final rows = [
      for (final item in _parsed)
        if (_selected.contains('${item.index}_${item.chapter}')) item,
    ];
    if (rows.isEmpty) {
      _toast(l10n.novelImportMsgSelectChapters);
      return;
    }
    setState(() => _saving = true);
    try {
      widget.ref.read(engineProvider).addNovels(widget.projectId, rows);
      _toast(l10n.novelImportMsgSaveSuccess);
      setState(() => _step = 2);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _step1() {
    final l10n = context.l10n;
    final df = context.df;
    final chars = _content.text.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: _pickFile,
        child: Container(
          height: 108,
          decoration: BoxDecoration(
            border: Border.all(color: df.stroke, width: 1.4),
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            color: df.surfaceMuted,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.upload_file_outlined, size: 32, color: df.primary),
            const SizedBox(height: 6),
            Text(l10n.novelImportDragUpload,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 2),
            Text(l10n.novelImportUploadHint,
                style: TextStyle(fontSize: 11, color: df.textTertiary)),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Divider(color: df.stroke)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(l10n.novelImportOr,
                style: TextStyle(fontSize: 12, color: df.textTertiary)),
          ),
          Expanded(child: Divider(color: df.stroke)),
        ]),
      ),
      Text(l10n.novelImportPasteLabel,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: _content,
        minLines: 10,
        maxLines: 10,
        onChanged: (_) => _reparse(),
        decoration: InputDecoration(hintText: l10n.novelImportPastePlaceholder),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Text('$chars ${l10n.novelImportChars}',
            style: TextStyle(
                fontSize: 12,
                color:
                    chars > 0 && chars < 100 ? df.warning : df.textTertiary)),
        if (chars > 0 && chars < 100) ...[
          const SizedBox(width: 6),
          Text(l10n.novelImportTooShort,
              style: TextStyle(fontSize: 12, color: df.warning)),
        ],
        const Spacer(),
        Text(l10n.novelImportParsedChapters('${_parsed.length}'),
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
      ]),
    ]);
  }

  Widget _step2() {
    final l10n = context.l10n;
    final df = context.df;
    final selectedChars = _parsed
        .where((c) => _selected.contains('${c.index}_${c.chapter}'))
        .fold<int>(0, (sum, c) => sum + c.chapterData.length);
    return Column(children: [
      Expanded(
        child: DFDataTable(
          columns: [
            DFDataColumn(label: l10n.novelImportColChapter),
            DFDataColumn(label: l10n.novelImportColReel),
            DFDataColumn(label: l10n.novelImportColChapterName),
            DFDataColumn(label: l10n.novelImportColChapterData),
          ],
          selectable: true,
          selectedIds: _selected,
          onSelectionChanged: (ids) => setState(() => _selected
            ..clear()
            ..addAll(ids)),
          rows: [
            for (final c in _parsed)
              DFDataRow(
                id: '${c.index}_${c.chapter}',
                cells: [
                  Text('${c.index}'),
                  Text(c.reel, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(c.chapter, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    c.chapterData.length > 60
                        ? c.chapterData.substring(0, 60)
                        : c.chapterData,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
          ],
          mobileCardBuilder: (c, row) {
            final item =
                _parsed.firstWhere((x) => '${x.index}_${x.chapter}' == row.id);
            return ListTile(
              title: Text('${item.index} · ${item.chapter}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.reel, style: const TextStyle(fontSize: 12)),
                  if (item.chapterData.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.chapterData,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: df.textTertiary),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(l10n.novelImportSelectedInfo('$selectedChars'),
              style: TextStyle(fontSize: 12, color: df.textSecondary)),
        ),
      ),
    ]);
  }

  Widget _step3() {
    final l10n = context.l10n;
    final df = context.df;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.check_circle_outline, size: 48, color: df.success),
      const SizedBox(height: 12),
      Text(l10n.novelImportMsgSaveSuccess,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(l10n.novelEventGeneratingHint,
          style: TextStyle(fontSize: 13, color: df.textSecondary)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stepTitles = [
      '${l10n.novelImportStep1}：${l10n.novelImportText}',
      '${l10n.novelImportStep2}：${l10n.novelImportMsgSelectFile}',
      '${l10n.novelImportStep3}：${l10n.novelImportEventAnalysis}',
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Row(children: [
              Expanded(
                child: Text(stepTitles[_step],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.df.primary,
                    )),
              ),
              const SizedBox(width: 8),
              Text('${_step + 1}/${stepTitles.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.df.textTertiary,
                    fontFeatures: DFTokens.tabularFigures,
                  )),
            ]);
          }

          return Row(children: [
            for (final (i, t) in stepTitles.indexed) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.chevron_right,
                      size: 16, color: context.df.textTertiary),
                ),
              Text(t,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _step == i ? FontWeight.w700 : FontWeight.w400,
                    color: _step == i
                        ? context.df.primary
                        : context.df.textTertiary,
                  )),
            ],
          ]);
        }),
      ),
      Flexible(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 420,
            child: switch (_step) {
              0 => SingleChildScrollView(child: _step1()),
              1 => _step2(),
              _ => _step3(),
            },
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_step == 1)
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: Text(l10n.novelImportPrevStep),
            ),
          const SizedBox(width: 8),
          if (_step == 0)
            FilledButton(
              onPressed: _parsed.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _step = 1;
                        _selected
                          ..clear()
                          ..addAll([
                            for (final c in _parsed) '${c.index}_${c.chapter}'
                          ]);
                      });
                    },
              child: Text(l10n.novelImportNextStep),
            )
          else if (_step == 1)
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.novelImportSaveAndAnalyze),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonConfirm),
            ),
        ]),
      ),
    ]);
  }
}
