// 编辑章节对话框（照抄 editNodel.vue）：章节名称/事件内容/章节内容(15行)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/novel.dart';
import '../../state/providers.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

Future<bool?> showEditNovelDialog(BuildContext context, WidgetRef ref,
    {required NovelRow row}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.novelEditDialogTitle,
    desktopWidthFactor: 0.5,
    builder: (c) => _EditNovelBody(row: row, ref: ref),
  );
}

class _EditNovelBody extends StatefulWidget {
  final NovelRow row;
  final WidgetRef ref;
  const _EditNovelBody({required this.row, required this.ref});

  @override
  State<_EditNovelBody> createState() => _EditNovelBodyState();
}

class _EditNovelBodyState extends State<_EditNovelBody> {
  late final TextEditingController _chapter =
      TextEditingController(text: widget.row.chapter ?? '');
  late final TextEditingController _event =
      TextEditingController(text: widget.row.event ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.row.chapterData ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _chapter.dispose();
    _event.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      widget.ref.read(engineProvider).updateNovel(
            widget.row.id,
            chapter: _chapter.text,
            event: _event.text,
            chapterData: _content.text,
          );
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.novelEditDialogMsgUpdateSuccess)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(localizeError(context, e))));
      }
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
              controller: _chapter,
              decoration: InputDecoration(
                labelText: l10n.novelEditDialogChapterName,
                hintText: l10n.novelEditDialogChapterNamePh,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _event,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.novelEditDialogEventContent,
                hintText: l10n.novelEditDialogEventContentPh,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _content,
              minLines: 15,
              maxLines: 15,
              decoration: InputDecoration(
                labelText: l10n.novelEditDialogChapterContent,
                hintText: l10n.novelEditDialogChapterContentPh,
                alignLabelWithHint: true,
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
            child: Text(l10n.novelEditDialogCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.novelEditDialogSave),
          ),
        ]),
      ),
    ]);
  }
}
