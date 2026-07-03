// 关联资产选择器（多选已有 role/tool/scene 资产）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/scripts.dart';
import '../../state/providers.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<List<int>?> showAssetPicker(BuildContext context, WidgetRef ref,
    {required int projectId, required List<int> initial}) {
  final options = ref.read(engineProvider).assetOptions(projectId);
  return showDFAdaptiveDialog<List<int>>(
    context,
    title: context.l10n.scriptAddMsgSelectAssetsTitle,
    desktopWidthFactor: 0.4,
    builder: (c) => _AssetPickerBody(options: options, initial: initial),
  );
}

class _AssetPickerBody extends StatefulWidget {
  final List<({int id, String name, String type})> options;
  final List<int> initial;
  const _AssetPickerBody({required this.options, required this.initial});

  @override
  State<_AssetPickerBody> createState() => _AssetPickerBodyState();
}

class _AssetPickerBodyState extends State<_AssetPickerBody> {
  late final Set<int> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SizedBox(
          height: 360,
          child: widget.options.isEmpty
              ? Center(child: Text(l10n.scriptAddNoAssets))
              : ListView(children: [
                  for (final option in widget.options)
                    CheckboxListTile(
                      dense: true,
                      value: _selected.contains(option.id),
                      title: Text(option.name),
                      subtitle:
                          Text(option.type, style: const TextStyle(fontSize: 11)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(option.id);
                        } else {
                          _selected.remove(option.id);
                        }
                      }),
                    ),
                ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel)),
          const SizedBox(width: 8),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_selected.toList()),
              child: Text(l10n.commonConfirm)),
        ]),
      ),
    ]);
  }
}
