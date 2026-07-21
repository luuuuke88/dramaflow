// 可复用的项目资产选择器：支持类型筛选、父子资产、搜索、分页和单/多选。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

const _scriptAssetTypes = {'role', 'tool', 'scene'};

/// 打开项目资产选择器。
///
/// 默认筛选剧本可关联的角色、道具和场景；其他页面可传入自己的 [types]
/// 与 [multiple]，避免再次复制一份选择器逻辑。
Future<List<int>?> showAssetPicker(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  required List<int> initial,
  Set<String> types = _scriptAssetTypes,
  bool multiple = true,
  String? title,
}) {
  final options = ref.read(engineProvider).assetSelectionItems(
        projectId,
        types: types,
      );
  return showDFAdaptiveDialog<List<int>>(
    context,
    title: title ?? context.l10n.scriptAddMsgSelectAssetsTitle,
    desktopWidthFactor: .5,
    builder: (_) => _AssetPickerBody(
      options: options,
      initial: initial,
      multiple: multiple,
    ),
  );
}

class _AssetPickerBody extends StatefulWidget {
  final List<AssetRow> options;
  final List<int> initial;
  final bool multiple;

  const _AssetPickerBody({
    required this.options,
    required this.initial,
    required this.multiple,
  });

  @override
  State<_AssetPickerBody> createState() => _AssetPickerBodyState();
}

class _AssetPickerBodyState extends State<_AssetPickerBody> {
  static const _pageSize = 10;

  late final Set<int> _selected = {...widget.initial};
  var _query = '';
  var _page = 0;

  List<AssetRow> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options.where((asset) {
      return [asset.name, asset.describe, asset.prompt]
          .whereType<String>()
          .any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = _filtered;
    final pageCount = (items.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, pageCount - 1);
    final visible = items.skip(page * _pageSize).take(_pageSize).toList();

    return SizedBox(
      height: 520,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(DFTokens.s16),
          child: TextField(
            key: const ValueKey('asset-picker-search'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_outlined),
              hintText: l10n.commonSearch,
            ),
            onChanged: (value) => setState(() {
              _query = value;
              _page = 0;
            }),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(l10n.scriptAddNoAssets))
              : _assetList(visible),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DFTokens.s16,
            8,
            DFTokens.s16,
            DFTokens.s16,
          ),
          child: Row(children: [
            IconButton(
              key: const ValueKey('asset-picker-previous'),
              tooltip: l10n.assetPickerPreviousPage,
              onPressed:
                  page == 0 ? null : () => setState(() => _page = page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text('${page + 1} / $pageCount'),
            IconButton(
              key: const ValueKey('asset-picker-next'),
              tooltip: l10n.assetPickerNextPage,
              onPressed: page + 1 >= pageCount
                  ? null
                  : () => setState(() => _page = page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('asset-picker-confirm'),
              onPressed: () => Navigator.of(context).pop([
                for (final asset in widget.options)
                  if (_selected.contains(asset.id)) asset.id,
              ]),
              child: Text(l10n.commonConfirm),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _assetList(List<AssetRow> visible) {
    final list = ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final asset = visible[index];
        final selected = _selected.contains(asset.id);
        final subtitle = [
          _typeLabel(context, asset.type),
          if (asset.assetsId != null) context.l10n.productionAssetDerived,
          if ((asset.describe ?? '').isNotEmpty) asset.describe!,
        ].join(' · ');
        return ListTile(
          key: ValueKey('asset-picker-item-${asset.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: DFTokens.s16,
          ),
          leading: asset.assetsId == null
              ? const Icon(Icons.category_outlined)
              : const Icon(Icons.subdirectory_arrow_right_outlined),
          title: Text(asset.name ?? ''),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.multiple
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => _toggle(asset.id),
                )
              : Radio<int>(value: asset.id),
          onTap: () => _toggle(asset.id),
        );
      },
    );
    if (widget.multiple) return list;
    return RadioGroup<int>(
      groupValue: _selected.firstOrNull,
      onChanged: (id) {
        if (id != null) _toggle(id);
      },
      child: list,
    );
  }

  void _toggle(int id) => setState(() {
        if (widget.multiple) {
          if (!_selected.add(id)) _selected.remove(id);
        } else {
          _selected
            ..clear()
            ..add(id);
        }
      });
}

String _typeLabel(BuildContext context, String type) => switch (type) {
      'role' => context.l10n.assetPickerTypeRole,
      'tool' => context.l10n.assetPickerTypeTool,
      'scene' => context.l10n.assetPickerTypeScene,
      'clip' => context.l10n.assetPickerTypeClip,
      'audio' => context.l10n.assetPickerTypeAudio,
      _ => type,
    };
