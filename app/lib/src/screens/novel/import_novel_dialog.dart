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
  String? _uploadedFileName;
  bool _programmaticChange = false;

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
      _programmaticChange = true;
      if (name.endsWith('.docx')) {
        _content.text = extractDocxText(bytes);
      } else if (name.endsWith('.txt')) {
        _content.text = utf8.decode(bytes, allowMalformed: true);
      } else {
        _programmaticChange = false;
        _toast(l10n.novelImportMsgUnsupportedType);
        return;
      }
      _programmaticChange = false;
      setState(() => _uploadedFileName = file.name);
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 136,
          decoration: BoxDecoration(
            border: Border.all(
                color: df.primary.withValues(alpha: 0.35), width: 1.5),
            borderRadius: BorderRadius.circular(16),
            color: df.surface.withValues(alpha: 0.65),
            boxShadow: [
              BoxShadow(
                color: df.primary.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_uploadedFileName != null ? df.success : df.primary)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _uploadedFileName != null
                    ? Icons.check_circle_rounded
                    : Icons.cloud_upload_rounded,
                size: 26,
                color: _uploadedFileName != null ? df.success : df.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _uploadedFileName != null
                  ? l10n.novelImportUploaded(_uploadedFileName!)
                  : l10n.novelImportDragUpload,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _uploadedFileName != null
                  ? l10n.novelImportReUploadHint
                  : l10n.novelImportUploadHint,
              style: TextStyle(fontSize: 12, color: df.textTertiary),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Divider(color: df.stroke.withValues(alpha: 0.5))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: df.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l10n.novelImportOr,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: df.textTertiary),
              ),
            ),
          ),
          Expanded(child: Divider(color: df.stroke.withValues(alpha: 0.5))),
        ]),
      ),
      Text(
        l10n.novelImportPasteLabel,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _content,
        minLines: 8,
        maxLines: 8,
        onChanged: (_) {
          if (!_programmaticChange && _uploadedFileName != null) {
            setState(() => _uploadedFileName = null);
          }
          _reparse();
        },
        style: const TextStyle(fontSize: 13, height: 1.5),
        decoration: InputDecoration(
          hintText: l10n.novelImportPastePlaceholder,
          fillColor: df.surface.withValues(alpha: 0.7),
          filled: true,
          contentPadding: const EdgeInsets.all(16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: df.stroke.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: df.stroke.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: df.primary, width: 1.5),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                '$chars ${l10n.novelImportChars}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: chars > 0 && chars < 100
                        ? df.warning
                        : df.textTertiary),
              ),
              if (chars > 0 && chars < 100)
                Text(l10n.novelImportTooShort,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: df.warning)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: df.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            l10n.novelImportParsedChapters('${_parsed.length}'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: df.primary),
          ),
        ),
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
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${item.index} · ${item.chapter}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.reel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
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
    final df = context.df;
    final stepTitles = [
      '${l10n.novelImportStep1}：${l10n.novelImportText}',
      '${l10n.novelImportStep2}：${l10n.novelImportMsgSelectFile}',
      '${l10n.novelImportStep3}：${l10n.novelImportEventAnalysis}',
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 12),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Row(children: [
              Expanded(
                child: Text(stepTitles[_step],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: df.primary,
                    )),
              ),
              const SizedBox(width: 8),
              Text('${_step + 1}/${stepTitles.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: df.textTertiary,
                    fontFeatures: DFTokens.tabularFigures,
                  )),
            ]);
          }

          return Row(children: [
            for (final (i, t) in stepTitles.indexed) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: df.textTertiary.withValues(alpha: 0.6)),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _step == i
                      ? df.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _step == i
                        ? df.primary.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  t,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _step == i ? FontWeight.w700 : FontWeight.w500,
                    color: _step == i ? df.primary : df.textTertiary,
                  ),
                ),
              ),
            ],
          ]);
        }),
      ),
      Flexible(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SizedBox(
            height: 440,
            child: switch (_step) {
              0 => SingleChildScrollView(child: _step1()),
              1 => _step2(),
              _ => _step3(),
            },
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_step == 1)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => setState(() => _step = 0),
              child: Text(l10n.novelImportPrevStep),
            ),
          const SizedBox(width: 10),
          if (_step == 0)
            FilledButton(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
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
              child: Text(l10n.novelImportNextStep,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          else if (_step == 1)
            FilledButton(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.novelImportSaveAndAnalyze,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonConfirm,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    ]);
  }
}
