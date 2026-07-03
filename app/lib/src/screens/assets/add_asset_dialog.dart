// 新增/编辑资产对话框（照抄 addAssets.vue）：名称*/描述*/备注/提示词（clip 隐藏）。
// clip 新增支持真实文件上传（照抄 uploadClip.ts）：选文件后落盘+建 o_image 行。
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../engine/assets.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<bool?> showAddAssetDialog(BuildContext context, WidgetRef ref,
    {required int projectId, required String type, AssetRow? existing}) {
  final l10n = context.l10n;
  return showDFAdaptiveDialog<bool>(
    context,
    title: existing == null ? l10n.assetsAddPrefix : l10n.assetsEdit,
    desktopWidthFactor: 0.44,
    builder: (c) => _AddAssetBody(
        projectId: projectId, type: type, existing: existing, ref: ref),
  );
}

class _AddAssetBody extends StatefulWidget {
  final int projectId;
  final String type;
  final AssetRow? existing;
  final WidgetRef ref;
  const _AddAssetBody(
      {required this.projectId,
      required this.type,
      required this.existing,
      required this.ref});

  @override
  State<_AddAssetBody> createState() => _AddAssetBodyState();
}

class _AddAssetBodyState extends State<_AddAssetBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _describe =
      TextEditingController(text: widget.existing?.describe ?? '');
  late final TextEditingController _remark =
      TextEditingController(text: widget.existing?.remark ?? '');
  late final TextEditingController _prompt =
      TextEditingController(text: widget.existing?.prompt ?? '');
  bool _saving = false;

  // clip 新增：选中的真实文件（可选，无文件则退回仅记录元数据）。
  List<int>? _clipBytes;
  String? _clipFileName;

  bool get _isNewClip => widget.type == 'clip' && widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    _describe.dispose();
    _remark.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickClip() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'media', extensions: [
        'png', 'jpg', 'jpeg', 'webp', 'gif',
        'mp3', 'wav', 'm4a', 'aac',
        'mp4', 'webm', 'mov',
      ])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _clipBytes = bytes;
      _clipFileName = file.name;
      if (_name.text.trim().isEmpty) {
        _name.text = p.basenameWithoutExtension(file.name);
      }
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    // clip 上传了真实文件：走 uploadClip（不要求描述）。
    if (_isNewClip && _clipBytes != null) {
      setState(() => _saving = true);
      try {
        final engine = widget.ref.read(engineProvider);
        final ext = _clipFileName == null
            ? 'bin'
            : p.extension(_clipFileName!).replaceFirst('.', '').toLowerCase();
        engine.uploadClip(
          projectId: widget.projectId,
          name: _name.text.trim().isEmpty
              ? (_clipFileName ?? '')
              : _name.text.trim(),
          bytes: _clipBytes!,
          ext: ext.isEmpty ? 'bin' : ext,
        );
        _toast(l10n.clipUploadSuccess);
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) _toast(localizeError(context, e));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    if (_name.text.trim().isEmpty) {
      _toast(l10n.assetsAddNameRequired);
      return;
    }
    // clip 仅记录元数据时无需描述（照抄 addAssets.vue：clip 隐藏描述必填）。
    if (widget.type != 'clip' && _describe.text.trim().isEmpty) {
      _toast(l10n.assetsAddDescribeRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      final engine = widget.ref.read(engineProvider);
      if (widget.existing == null) {
        engine.addAsset(
          projectId: widget.projectId,
          type: widget.type,
          name: _name.text.trim(),
          describe: _describe.text,
          remark: _remark.text,
          prompt: widget.type == 'clip' ? null : _prompt.text,
        );
        _toast(l10n.assetsAddAddSuccess);
      } else {
        engine.updateAsset(
          widget.existing!.id,
          name: _name.text.trim(),
          describe: _describe.text,
          remark: _remark.text,
          prompt: widget.type == 'clip' ? null : _prompt.text,
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

  Widget _clipPicker() {
    final l10n = context.l10n;
    final df = context.df;
    final ext = _clipFileName == null
        ? ''
        : p.extension(_clipFileName!).replaceFirst('.', '').toLowerCase();
    final isImage = const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext);
    return InkWell(
      onTap: _pickClip,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke, width: 1.4),
          borderRadius: BorderRadius.circular(8),
          color: df.surfaceMuted,
        ),
        child: Row(children: [
          if (isImage && _clipBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                Uint8List.fromList(_clipBytes!),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          else
            Icon(
                _clipBytes == null
                    ? Icons.upload_file_outlined
                    : Icons.insert_drive_file_outlined,
                color: df.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _clipFileName ?? l10n.clipNoFile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: _clipFileName == null
                      ? df.textTertiary
                      : df.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _pickClip,
            child: Text(l10n.clipPickFile,
                style: const TextStyle(fontSize: 12)),
          ),
        ]),
      ),
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
            if (_isNewClip) ...[
              _clipPicker(),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: l10n.assetsAddName,
                  hintText: l10n.assetsAddNamePh),
            ),
            if (widget.type != 'clip') ...[
              const SizedBox(height: 14),
              TextField(
                controller: _describe,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                    labelText: l10n.assetsAddDescribe,
                    hintText: l10n.assetsAddDescribePh,
                    alignLabelWithHint: true),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _remark,
              decoration: InputDecoration(
                  labelText: l10n.assetsAddRemark,
                  hintText: l10n.assetsAddRemarkPh),
            ),
            if (widget.type != 'clip') ...[
              const SizedBox(height: 14),
              TextField(
                controller: _prompt,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                    labelText: l10n.assetsAddPrompt,
                    hintText: l10n.assetsAddPromptPh,
                    alignLabelWithHint: true),
              ),
            ],
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
