// 新增/编辑音频资产对话框（照抄 addAudioAssets.vue）：
// 音色*/性别/描述 + 动态音频条目（文件上传/音频文本/描述，可增删）。
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<bool?> showAddAudioAssetDialog(BuildContext context, WidgetRef ref,
    {required int projectId, AssetRow? existing}) {
  final l10n = context.l10n;
  return showDFAdaptiveDialog<bool>(
    context,
    title: existing == null
        ? '${l10n.assetsAddPrefix}${l10n.assetsTabAudio}'
        : l10n.assetsEdit,
    desktopWidthFactor: 0.5,
    builder: (c) =>
        _AddAudioBody(projectId: projectId, existing: existing, ref: ref),
  );
}

class _AudioItemDraft {
  final TextEditingController text = TextEditingController();
  final TextEditingController describe = TextEditingController();
  String name = '';
  String? base64;
  String? ext;
  int? existingImageId;
  String? fileName;
}

class _AddAudioBody extends StatefulWidget {
  final int projectId;
  final AssetRow? existing;
  final WidgetRef ref;
  const _AddAudioBody(
      {required this.projectId, required this.existing, required this.ref});

  @override
  State<_AddAudioBody> createState() => _AddAudioBodyState();
}

class _AddAudioBodyState extends State<_AddAudioBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _sex =
      TextEditingController(text: widget.existing?.sex ?? '');
  late final TextEditingController _describe =
      TextEditingController(text: widget.existing?.audioDescribe ?? '');
  final List<_AudioItemDraft> _items = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final son in widget.existing?.sonAssets ?? const <AssetRow>[]) {
      final draft = _AudioItemDraft()
        ..name = son.name ?? ''
        ..existingImageId = son.imageId
        ..fileName = son.filePath?.split('/').last;
      draft.text.text = son.prompt ?? '';
      draft.describe.text = son.describe ?? '';
      _items.add(draft);
    }
    if (_items.isEmpty) _items.add(_AudioItemDraft());
  }

  @override
  void dispose() {
    _name.dispose();
    _sex.dispose();
    _describe.dispose();
    for (final item in _items) {
      item.text.dispose();
      item.describe.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickAudio(_AudioItemDraft item) async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: 'audio', extensions: ['mp3', 'wav', 'm4a', 'flac', 'aiff'])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      item.base64 = base64Encode(bytes);
      item.ext = file.name.split('.').last.toLowerCase();
      item.fileName = file.name;
      item.existingImageId = null;
      if (item.name.isEmpty) item.name = file.name;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.assetsAddAudioNamePh);
      return;
    }
    if (_describe.text.trim().isEmpty) {
      _toast(l10n.assetsAddDescribeRequired);
      return;
    }
    for (final item in _items) {
      if (item.base64 == null && item.existingImageId == null) {
        _toast(l10n.assetsAddPleaseUploadAudio);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final engine = widget.ref.read(engineProvider);
      final payload = [
        for (final item in _items)
          (
            base64: item.base64,
            ext: item.ext,
            prompt: item.text.text,
            name: item.name.isEmpty ? _name.text.trim() : item.name,
            describe: item.describe.text,
            existingImageId: item.existingImageId,
          ),
      ];
      if (widget.existing == null) {
        engine.addAudioAssets(
          projectId: widget.projectId,
          name: _name.text.trim(),
          sex: _sex.text.trim(),
          describe: _describe.text,
          items: payload,
        );
        _toast(l10n.assetsAddAddSuccess);
      } else {
        engine.updateAudioAssets(
          parentId: widget.existing!.id,
          projectId: widget.projectId,
          name: _name.text.trim(),
          sex: _sex.text.trim(),
          describe: _describe.text,
          items: payload,
        );
        _toast(l10n.assetsAddUpdateSuccess);
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _itemCard(_AudioItemDraft item, int index) {
    final l10n = context.l10n;
    final df = context.df;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: df.surfaceMuted,
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
        border: Border.all(color: df.stroke),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickAudio(item),
              icon: const Icon(Icons.audio_file_outlined, size: 16),
              label: Text(
                item.fileName ?? l10n.assetsAddAudioFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.assetsDelete,
            icon: Icon(Icons.remove_circle_outline,
                size: 18, color: df.danger),
            onPressed: _items.length <= 1
                ? null
                : () => setState(() => _items.removeAt(index)),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: item.text,
          decoration: InputDecoration(
              labelText: l10n.assetsAudioText,
              hintText: l10n.assetsAddAudioTextPh,
              isDense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: item.describe,
          decoration: InputDecoration(
              labelText: l10n.assetsColDescribe,
              hintText: l10n.assetsAddAudioDescPh,
              isDense: true),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: l10n.assetsAudioName,
                  hintText: l10n.assetsAddAudioNamePh),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sex,
              decoration: InputDecoration(
                  labelText: l10n.assetsSex, hintText: l10n.assetsAddSexPh),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _describe,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: l10n.assetsColDescribe,
                  hintText: l10n.assetsAddDescribePh,
                  alignLabelWithHint: true),
            ),
            const SizedBox(height: 14),
            for (final (i, item) in _items.indexed) _itemCard(item, i),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _items.add(_AudioItemDraft())),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.assetsAddAudioItem,
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          ]),
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
            onPressed: _saving ? null : _save,
            child: Text(l10n.commonConfirm),
          ),
        ]),
      ),
    ]);
  }
}
