// 新增/编辑资产对话框（照抄 addAssets.vue）：名称*/描述*/备注/提示词（clip 隐藏）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../state/providers.dart';
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

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.assetsAddNameRequired);
      return;
    }
    if (_describe.text.trim().isEmpty) {
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
                  labelText: l10n.assetsAddName,
                  hintText: l10n.assetsAddNamePh),
            ),
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
