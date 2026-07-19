// 批量添加剧本对话框（照抄 batchAddScript.vue 两步）：
// 第一步＝分集正则（支持 /pattern/flags，实时校验）+ AI解析正则 + 上传/粘贴；
// 第二步＝选择表 + 已选字数 + 保存（batchAddScripts）。
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/errors.dart';
import '../../engine/novel_parse.dart';
import '../../engine/scripts.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_data_table.dart';

const _maxFileBytes = 10 * 1024 * 1024;

Future<bool?> showBatchAddDialog(BuildContext context, WidgetRef ref,
    {required int projectId}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.scriptBatchAdd,
    desktopWidthFactor: 0.56,
    builder: (c) => _BatchAddBody(projectId: projectId, ref: ref),
  );
}

class _BatchAddBody extends StatefulWidget {
  final int projectId;
  final WidgetRef ref;
  const _BatchAddBody({required this.projectId, required this.ref});

  @override
  State<_BatchAddBody> createState() => _BatchAddBodyState();
}

class _BatchAddBodyState extends State<_BatchAddBody> {
  int _step = 0;
  final TextEditingController _regex = TextEditingController();
  final TextEditingController _content = TextEditingController();
  String? _regexError;
  bool _aiLoading = false;
  bool _saving = false;
  List<({String id, int index, String scriptName, String scriptData})> _parsed =
      const [];
  final Set<String> _selected = {};

  int get _episodeLimit =>
      widget.ref.read(engineProvider).config.intOf('scriptEpisodeLength');

  /// 已勾选且超出单集字数上限的分集（对齐 ToonFlow：任一超限则禁用保存）。
  List<({String id, int index, String scriptName, String scriptData})>
      get _overLimit => [
            for (final s in _parsed)
              if (_selected.contains(s.id) &&
                  s.scriptData.length > _episodeLimit)
                s,
          ];

  @override
  void dispose() {
    _regex.dispose();
    _content.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _validateRegex() {
    final raw = _regex.text.trim();
    if (raw.isEmpty) {
      setState(() => _regexError = null);
      return;
    }
    try {
      final m = RegExp(r'^/(.*)/([igmuy]*)$').firstMatch(raw);
      RegExp(m != null ? m.group(1)! : raw);
      setState(() => _regexError = null);
    } catch (_) {
      setState(() => _regexError = context.l10n.errRegexInvalid);
    }
  }

  void _reparse() {
    // 剧本批量导入与 ToonFlow parseScript.ts 一致，默认按“第 X 集”拆分。
    try {
      final episodes = parseScript(
        _content.text,
        episodeReg: _regex.text.trim().isEmpty ? null : _regex.text.trim(),
      );
      _parsed = [
        for (final item in episodes)
          (
            id: '${item.index}',
            index: item.index,
            scriptName: item.chapter,
            scriptData: item.text,
          ),
      ];
    } catch (_) {
      _parsed = const [];
    }
    setState(() {});
  }

  Future<void> _aiRegex() async {
    if (_content.text.trim().isEmpty) {
      _toast(context.l10n.scriptAddMsgEnterContent);
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final regex =
          await widget.ref.read(engineProvider).aiEpisodeRegex(_content.text);
      _regex.text = regex;
      _validateRegex();
      _reparse();
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _pickFile() async {
    final l10n = context.l10n;
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'script', extensions: ['txt', 'docx'])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxFileBytes) {
      if (mounted) _toast(l10n.scriptAddMsgFileTooLarge);
      return;
    }
    try {
      final name = file.name.toLowerCase();
      if (name.endsWith('.docx')) {
        _content.text = extractDocxText(bytes);
      } else if (name.endsWith('.txt')) {
        _content.text = utf8.decode(bytes, allowMalformed: true);
      } else {
        if (mounted) _toast(l10n.scriptAddMsgUnsupportedType);
        return;
      }
      _reparse();
    } on EngineException catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } catch (_) {
      if (mounted) _toast(l10n.scriptAddMsgParseFailed);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final rows = [
      for (final item in _parsed)
        if (_selected.contains(item.id))
          (scriptName: item.scriptName, scriptData: item.scriptData),
    ];
    if (rows.isEmpty) {
      _toast(l10n.novelImportMsgSelectChapters);
      return;
    }
    if (_overLimit.isNotEmpty) {
      _toast(l10n.scriptBatchAddMsgOverLimit('$_episodeLimit'));
      return;
    }
    setState(() => _saving = true);
    try {
      widget.ref.read(engineProvider).batchAddScripts(widget.projectId, rows);
      _toast(l10n.scriptAddMsgAddSuccess);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _step1() {
    final l10n = context.l10n;
    final df = context.df;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _regex,
            onChanged: (_) {
              _validateRegex();
              _reparse();
            },
            decoration: InputDecoration(
              hintText: l10n.scriptImportEpisodeRegexPh,
              errorText: _regexError,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _aiLoading ? null : _aiRegex,
          child: _aiLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.scriptImportGetAiRegex),
        ),
      ]),
      const SizedBox(height: 12),
      InkWell(
        onTap: _pickFile,
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            border: Border.all(color: df.stroke, width: 1.4),
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            color: df.surfaceMuted,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.upload_file_outlined, size: 26, color: df.primary),
            const SizedBox(height: 4),
            Text(l10n.scriptAddDragUpload,
                style: const TextStyle(fontSize: 12)),
            Text(l10n.scriptAddUploadHint,
                style: TextStyle(fontSize: 10, color: df.textTertiary)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _content,
        minLines: 9,
        maxLines: 9,
        onChanged: (_) => _reparse(),
        decoration: InputDecoration(
          hintText: l10n.novelImportPastePlaceholder,
        ),
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerRight,
        child: Text(l10n.novelImportParsedChapters('${_parsed.length}'),
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
      ),
    ]);
  }

  Widget _step2() {
    final l10n = context.l10n;
    final df = context.df;
    final selectedChars = _parsed
        .where((s) => _selected.contains(s.id))
        .fold<int>(0, (sum, s) => sum + s.scriptData.length);
    final limit = _episodeLimit;
    final overLimit = _overLimit;
    return Column(children: [
      Expanded(
        child: DFDataTable(
          columns: [
            DFDataColumn(label: l10n.novelColId),
            DFDataColumn(label: l10n.scriptAddScriptName),
            DFDataColumn(label: l10n.scriptAddScriptContent),
          ],
          selectable: true,
          selectedIds: _selected,
          onSelectionChanged: (ids) => setState(() => _selected
            ..clear()
            ..addAll(ids)),
          rows: [
            for (final s in _parsed)
              DFDataRow(
                id: s.id,
                cells: [
                  Text('${s.index}'),
                  Text(s.scriptName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(children: [
                    Expanded(
                      child: Text(
                        s.scriptData.length > 60
                            ? s.scriptData.substring(0, 60)
                            : s.scriptData,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '${s.scriptData.length}/$limit',
                      style: TextStyle(
                        fontSize: 11,
                        color: s.scriptData.length > limit
                            ? df.danger
                            : df.textTertiary,
                      ),
                    ),
                  ]),
                ],
              ),
          ],
          mobileCardBuilder: (c, row) {
            final s = _parsed.firstWhere((x) => x.id == row.id);
            return ListTile(
              title: Text(
                  s.scriptName.isEmpty
                      ? l10n.scriptBatchEpisodeFallback('${s.index}')
                      : s.scriptName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(
                s.scriptData.length > 40
                    ? s.scriptData.substring(0, 40)
                    : s.scriptData,
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          if (overLimit.isNotEmpty)
            Expanded(
              child: Text(
                l10n.scriptBatchAddMsgOverLimit('$limit'),
                style: TextStyle(fontSize: 12, color: df.danger),
              ),
            )
          else
            const Spacer(),
          Text(l10n.novelImportSelectedInfo('$selectedChars'),
              style: TextStyle(fontSize: 12, color: df.textSecondary)),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 430),
            child:
                _step == 0 ? SingleChildScrollView(child: _step1()) : _step2(),
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
              onPressed: _parsed.isEmpty || _regexError != null
                  ? null
                  : () => setState(() {
                        _step = 1;
                        _selected.clear();
                      }),
              child: Text(l10n.novelImportNextStep),
            )
          else
            FilledButton(
              onPressed: _saving || _overLimit.isNotEmpty ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.commonSave),
            ),
        ]),
      ),
    ]);
  }
}
