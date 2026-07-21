import 'dart:io';

import 'package:flutter/material.dart';

import '../../engine/engine.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

class StoryboardImageCandidate {
  final int id;
  final String label;
  final String prompt;
  final String localPath;

  const StoryboardImageCandidate({
    required this.id,
    required this.label,
    required this.prompt,
    required this.localPath,
  });
}

Future<List<StoryboardImageCandidate>?> showStoryboardImagePicker(
  BuildContext context, {
  required Engine engine,
  required List<StoryboardImageCandidate> candidates,
  required String emptyText,
  bool multiple = false,
}) =>
    showDFAdaptiveDialog<List<StoryboardImageCandidate>>(
      context,
      title: context.l10n.imageEditorPickImageTitle,
      desktopWidthFactor: .8,
      builder: (_) => _StoryboardImagePicker(
        engine: engine,
        candidates: candidates,
        emptyText: emptyText,
        multiple: multiple,
      ),
    );

class _StoryboardImagePicker extends StatefulWidget {
  final Engine engine;
  final List<StoryboardImageCandidate> candidates;
  final String emptyText;
  final bool multiple;

  const _StoryboardImagePicker({
    required this.engine,
    required this.candidates,
    required this.emptyText,
    required this.multiple,
  });

  @override
  State<_StoryboardImagePicker> createState() => _StoryboardImagePickerState();
}

class _StoryboardImagePickerState extends State<_StoryboardImagePicker> {
  static const _pageSize = 10;
  final _selected = <int>{};
  var _query = '';
  var _page = 0;

  List<StoryboardImageCandidate> get _filtered =>
      widget.candidates.where((item) {
        final q = _query.trim().toLowerCase();
        return q.isEmpty ||
            item.label.toLowerCase().contains(q) ||
            item.prompt.toLowerCase().contains(q);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pageCount = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, pageCount - 1);
    final visible = filtered.skip(page * _pageSize).take(_pageSize).toList();
    if (widget.candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DFTokens.s24),
        child: Center(child: Text(widget.emptyText)),
      );
    }
    return SizedBox(
      height: 520,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(DFTokens.s16),
          child: TextField(
            key: const ValueKey('storyboard-image-picker-search'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_outlined),
              hintText: context.l10n.commonSearch,
            ),
            onChanged: (value) => setState(() {
              _query = value;
              _page = 0;
            }),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(widget.emptyText))
              : RadioGroup<int>(
                  groupValue: _selected.firstOrNull,
                  onChanged: (id) {
                    if (!widget.multiple && id != null) _toggle(id);
                  },
                  child: ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final item = visible[index];
                      final selected = _selected.contains(item.id);
                      return ListTile(
                        key:
                            ValueKey('storyboard-image-picker-item-${item.id}'),
                        leading: SizedBox(
                          width: 56,
                          height: 40,
                          child: Image.file(
                            File(widget.engine.mediaAbsPath(item.localPath)),
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stackTrace) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        title: Text(item.label),
                        subtitle: Text(item.prompt,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: widget.multiple
                            ? Checkbox(
                                value: selected,
                                onChanged: (_) => _toggle(item.id))
                            : Radio<int>(value: item.id),
                        onTap: () => _toggle(item.id),
                      );
                    },
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              DFTokens.s16, 8, DFTokens.s16, DFTokens.s16),
          child: Row(children: [
            IconButton(
              key: const ValueKey('storyboard-image-picker-previous'),
              onPressed:
                  page == 0 ? null : () => setState(() => _page = page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text('${page + 1} / $pageCount'),
            IconButton(
              key: const ValueKey('storyboard-image-picker-next'),
              onPressed: page + 1 >= pageCount
                  ? null
                  : () => setState(() => _page = page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            const Spacer(),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.commonCancel)),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('storyboard-image-picker-confirm'),
              // `_selected` 是按勾选先后顺序迭代的 LinkedHashSet；用 id 查表
              // 换回候选对象，而不是按 widget.candidates 固定顺序枚举再过滤，
              // 否则确认后的返回顺序会丢失用户的实际勾选顺序。
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final byId = {
                        for (final item in widget.candidates) item.id: item,
                      };
                      Navigator.of(context).pop([
                        for (final id in _selected) byId[id]!,
                      ]);
                    },
              child: Text(context.l10n.commonConfirm),
            ),
          ]),
        ),
      ]),
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
