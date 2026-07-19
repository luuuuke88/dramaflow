// 全局画风库的数据兼容界面：列表与新增/编辑器均通过 ArtStyleApi（o_artStyle）工作。
// ToonFlow 1.1.8 的活跃项目流程使用视觉/导演手册而非本库；当前没有生产入口，
// 仅保留此界面和测试以维护已有本地画风数据，不能把它当作项目画风选择器。
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/art_style.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

/// 打开画风库管理器。返回 true 表示库有变更（供调用方刷新）。
Future<bool?> showArtStyleLibrary(BuildContext context, WidgetRef ref) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: context.l10n.artStyleLibraryTitle,
    desktopWidthFactor: 0.6,
    builder: (c) => _ArtStyleLibraryBody(ref: ref),
  );
}

class _ArtStyleLibraryBody extends StatefulWidget {
  final WidgetRef ref;
  const _ArtStyleLibraryBody({required this.ref});

  @override
  State<_ArtStyleLibraryBody> createState() => _ArtStyleLibraryBodyState();
}

class _ArtStyleLibraryBodyState extends State<_ArtStyleLibraryBody> {
  bool _dirty = false;
  List<ArtStyleRow> _styles = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _styles = widget.ref.read(engineProvider).artStyles());
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor({ArtStyleRow? existing}) async {
    final saved = await showArtStyleEditor(context, widget.ref, existing: existing);
    if (saved == true) {
      _dirty = true;
      _reload();
    }
  }

  Future<void> _delete(ArtStyleRow style) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.artStyleDeleteHeader),
        content: Text(l10n.artStyleDeleteBody(style.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.ref.read(engineProvider).deleteArtStyle(style.id);
    _dirty = true;
    _toast(l10n.artStyleDeleted);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(children: [
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.artStyleAddTitle),
          ),
        ]),
      ),
      Flexible(
        child: SizedBox(
          height: 380,
          child: _styles.isEmpty
              ? Center(
                  child: Text(l10n.artStyleEmpty,
                      style: TextStyle(color: df.textTertiary)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final style in _styles)
                      _ArtStyleCard(
                        style: style,
                        absPath: (rel) =>
                            widget.ref.read(engineProvider).mediaAbsPath(rel),
                        onEdit: () => _openEditor(existing: style),
                        onDelete: () => _delete(style),
                      ),
                  ]),
                ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_dirty),
            child: Text(l10n.artStyleClose),
          ),
        ]),
      ),
    ]);
  }
}

class _ArtStyleCard extends StatefulWidget {
  final ArtStyleRow style;
  final String Function(String rel) absPath;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ArtStyleCard(
      {required this.style,
      required this.absPath,
      required this.onEdit,
      required this.onDelete});

  @override
  State<_ArtStyleCard> createState() => _ArtStyleCardState();
}

class _ArtStyleCardState extends State<_ArtStyleCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final rel = widget.style.fileUrl;
    // 与 AppShell 的移动断点保持一致：700-839dp 的平板仍走移动壳，
    // 触控没有 hover，操作必须常显。
    final compact = MediaQuery.sizeOf(context).width < 840;
    final showActions = _hover || compact;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Container(
              width: 140,
              height: 100,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: df.surfaceMuted,
                border: Border.all(color: df.stroke),
              ),
              child: rel == null || rel.isEmpty
                  ? Icon(Icons.palette_outlined, color: df.textTertiary)
                  : Image.file(
                      File(widget.absPath(rel)),
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Icon(
                          Icons.broken_image_outlined,
                          color: df.textTertiary),
                    ),
            ),
            if (showActions) ...[
              Positioned(
                top: 4,
                left: 4,
                child: _MiniIcon(
                    icon: Icons.edit_outlined, onTap: widget.onEdit),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: _MiniIcon(
                    icon: Icons.delete_outline, onTap: widget.onDelete),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Text(widget.style.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(widget.style.prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: df.textSecondary)),
        ]),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 画风新增/编辑编辑器。
Future<bool?> showArtStyleEditor(BuildContext context, WidgetRef ref,
    {ArtStyleRow? existing}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: existing == null
        ? context.l10n.artStyleAddTitle
        : context.l10n.artStyleEditTitle,
    desktopWidthFactor: 0.44,
    builder: (c) => _ArtStyleEditor(existing: existing, ref: ref),
  );
}

class _ArtStyleEditor extends StatefulWidget {
  final ArtStyleRow? existing;
  final WidgetRef ref;
  const _ArtStyleEditor({required this.existing, required this.ref});

  @override
  State<_ArtStyleEditor> createState() => _ArtStyleEditorState();
}

class _ArtStyleEditorState extends State<_ArtStyleEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _prompt =
      TextEditingController(text: widget.existing?.prompt ?? '');
  String? _newBase64;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickCover() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: 'image', extensions: ['png', 'jpg', 'jpeg', 'webp'])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _newBase64 = base64Encode(bytes));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.artStyleNameRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      final engine = widget.ref.read(engineProvider);
      if (widget.existing == null) {
        engine.addArtStyle(
          name: _name.text,
          prompt: _prompt.text,
          base64Image: _newBase64,
        );
        _toast(l10n.artStyleAddSuccess);
      } else {
        engine.editArtStyle(
          widget.existing!.id,
          name: _name.text,
          prompt: _prompt.text,
          base64Image: _newBase64,
        );
        _toast(l10n.artStyleEditSuccess);
      }
      if (mounted) Navigator.of(context).pop(true);
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
    final existingRel = widget.existing?.fileUrl;
    Widget cover;
    if (_newBase64 != null) {
      cover = Image.memory(base64Decode(_newBase64!), fit: BoxFit.cover);
    } else if (existingRel != null && existingRel.isNotEmpty) {
      cover = Image.file(
        File(widget.ref.read(engineProvider).mediaAbsPath(existingRel)),
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) =>
            Icon(Icons.add_photo_alternate_outlined, color: df.textTertiary),
      );
    } else {
      cover = Icon(Icons.add_photo_alternate_outlined, color: df.textTertiary);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.artStyleCover,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickCover,
              child: Container(
                width: 120,
                height: 96,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: df.stroke, width: 1.4),
                  borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                  color: df.surfaceMuted,
                ),
                child: cover,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: l10n.artStyleName,
                  hintText: l10n.artStyleNamePh),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _prompt,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                  labelText: l10n.artStylePrompt,
                  hintText: l10n.artStylePromptPh,
                  alignLabelWithHint: true),
            ),
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
            onPressed: _saving ? null : _save,
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
