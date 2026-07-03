// 新增剧本对话框（照抄 addScript.vue）：名称/上传文件/内容+字数计数/关联资产。
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
import '../../widgets/df_tag_chip.dart';
import 'asset_picker.dart';

const _maxFileBytes = 10 * 1024 * 1024;
const _defaultEpisodeLength = 2000;

Future<bool?> showAddScriptDialog(BuildContext context, WidgetRef ref,
    {required int projectId}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.scriptAddTitle,
    desktopWidthFactor: 0.6,
    builder: (c) => _AddScriptBody(projectId: projectId, ref: ref),
  );
}

class _AddScriptBody extends StatefulWidget {
  final int projectId;
  final WidgetRef ref;
  const _AddScriptBody({required this.projectId, required this.ref});

  @override
  State<_AddScriptBody> createState() => _AddScriptBodyState();
}

class _AddScriptBodyState extends State<_AddScriptBody> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _content = TextEditingController();
  List<int> _assets = [];
  List<({int id, String name, String type})> _assetOptions = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _assetOptions =
        widget.ref.read(engineProvider).assetOptions(widget.projectId);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFile() async {
    final l10n = context.l10n;
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'script', extensions: ['txt', 'docx'])
    ]);
    if (file == null || !mounted) return;
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
      setState(() {});
    } on EngineException catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } catch (_) {
      if (mounted) _toast(l10n.scriptAddMsgParseFailed);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.scriptAddMsgEnterName);
      return;
    }
    if (_content.text.trim().isEmpty) {
      _toast(l10n.scriptAddMsgEnterContent);
      return;
    }
    setState(() => _saving = true);
    try {
      widget.ref.read(engineProvider).addScript(
            projectId: widget.projectId,
            name: _name.text.trim(),
            content: _content.text,
            assets: _assets,
          );
      _toast(l10n.scriptAddMsgAddSuccess);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final overLimit = _content.text.length > _defaultEpisodeLength;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.scriptAddScriptName,
                hintText: l10n.scriptAddScriptNamePh,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickFile,
              child: Container(
                height: 84,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: df.stroke, width: 1.4),
                  borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                  color: df.surfaceMuted,
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file_outlined,
                          size: 26, color: df.primary),
                      const SizedBox(height: 4),
                      Text(l10n.scriptAddDragUpload,
                          style: const TextStyle(fontSize: 12)),
                      Text(l10n.scriptAddUploadHint,
                          style: TextStyle(
                              fontSize: 10, color: df.textTertiary)),
                    ]),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _content,
              minLines: 10,
              maxLines: 10,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.scriptAddScriptContent,
                hintText: l10n.scriptAddScriptContentPh,
                alignLabelWithHint: true,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_content.text.length}/$_defaultEpisodeLength',
                  style: TextStyle(
                      fontSize: 11,
                      color: overLimit ? df.danger : df.textTertiary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(l10n.scriptAddRelatedAssets,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showAssetPicker(context, widget.ref,
                      projectId: widget.projectId, initial: _assets);
                  if (picked != null) setState(() => _assets = picked);
                },
                icon: const Icon(Icons.add, size: 14),
                label: Text(l10n.scriptAddSelectAssets,
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ]),
            const SizedBox(height: 8),
            if (_assets.isEmpty)
              Text(l10n.scriptAddNoAssets,
                  style: TextStyle(fontSize: 12, color: df.textTertiary))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final id in _assets)
                  DFTagChip(
                    label: _assetOptions
                        .where((o) => o.id == id)
                        .map((o) => o.name)
                        .firstOrNull ??
                        '$id',
                    onClose: () => setState(() => _assets.remove(id)),
                  ),
              ]),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.scriptAddCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving || overLimit ? null : _save,
            child: Text(l10n.scriptAddConfirm),
          ),
        ]),
      ),
    ]);
  }
}
