// 编辑剧本对话框（照抄 editScript.vue）：名称(≤10)/内容(20行)+计数/关联资产。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scripts.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_tag_chip.dart';
import 'asset_picker.dart';

Future<bool?> showEditScriptDialog(BuildContext context, WidgetRef ref,
    {required int projectId, required ScriptRow row}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.scriptEditTitle,
    desktopWidthFactor: 0.6,
    builder: (c) => _EditScriptBody(projectId: projectId, row: row, ref: ref),
  );
}

class _EditScriptBody extends StatefulWidget {
  final int projectId;
  final ScriptRow row;
  final WidgetRef ref;
  const _EditScriptBody(
      {required this.projectId, required this.row, required this.ref});

  @override
  State<_EditScriptBody> createState() => _EditScriptBodyState();
}

class _EditScriptBodyState extends State<_EditScriptBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.row.name ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.row.content ?? '');
  late List<int> _assets =
      widget.row.relatedAssets.map((a) => a.id).toList();
  late List<({int id, String name, String type})> _assetOptions;
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

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.scriptEditScriptNamePh);
      return;
    }
    setState(() => _saving = true);
    try {
      widget.ref.read(engineProvider).updateScript(
            widget.row.id,
            name: _name.text.trim(),
            content: _content.text,
            assets: _assets,
          );
      _toast(l10n.scriptEditMsgUpdateSuccess);
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
    final episodeLimit =
        widget.ref.read(engineProvider).config.intOf('scriptEpisodeLength');
    final overLimit = _content.text.length > episodeLimit;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: l10n.scriptEditScriptName,
                hintText: l10n.scriptEditScriptNamePh,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _content,
              minLines: 16,
              maxLines: 16,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.scriptEditScriptContent,
                hintText: l10n.scriptEditScriptContentPh,
                alignLabelWithHint: true,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_content.text.length}/$episodeLimit',
                  style: TextStyle(
                      fontSize: 11,
                      color: overLimit ? df.danger : df.textTertiary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(l10n.scriptEditRelatedAssets,
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
                label: Text(l10n.scriptEditSelectAssets,
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ]),
            const SizedBox(height: 8),
            if (_assets.isEmpty)
              Text(l10n.scriptEditNoAssets,
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
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving || overLimit ? null : _save,
            child: Text(l10n.commonSave),
          ),
        ]),
      ),
    ]);
  }
}
