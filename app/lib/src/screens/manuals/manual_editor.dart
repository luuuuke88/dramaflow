// 手册编辑器（照抄视觉/导演手册对话框）：名称、稳定目录 ID、封面多图上传 + 多 Tab MD 输入。
// 校验照抄：名称必填 / 封面必传 / 全 tab 非空；目录 ID 仅可在新建时设置。
// 补充：支持从 .docx/.md 文件导入正文填充当前标签。
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../engine/manuals.dart';
import '../../engine/novel_parse.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';

/// kind: 'visual' | 'director'
Future<bool?> showManualEditor(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  ManualPack? existing,
}) {
  final isVisual = kind == 'visual';
  final l10n = context.l10n;
  final title = isVisual
      ? (existing == null
          ? l10n.projectDialogNewVisualManualTitle
          : l10n.projectDialogEditVisualManualTitle)
      : (existing == null
          ? l10n.projectDialogNewDirecorManualTitle
          : l10n.projectDialogEditingDirectorManual);
  return showDFAdaptiveDialog<bool>(
    context,
    title: title,
    desktopWidthFactor: 0.9,
    builder: (c) => _ManualEditor(kind: kind, existing: existing, ref: ref),
  );
}

class _ManualEditor extends StatefulWidget {
  final String kind;
  final ManualPack? existing;
  final WidgetRef ref;
  const _ManualEditor(
      {required this.kind, required this.existing, required this.ref});

  @override
  State<_ManualEditor> createState() => _ManualEditorState();
}

class _ManualEditorState extends State<_ManualEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _pack = TextEditingController(
    text: widget.existing?.pack ?? '',
  );
  late final List<String> _keys =
      widget.kind == 'visual' ? visualManualKeys : directorManualKeys;
  late final Map<String, TextEditingController> _tabs = {
    for (final k in _keys)
      k: TextEditingController(text: widget.existing?.data[k] ?? ''),
  };
  final List<String> _keepImages = [];
  final List<({String name, String base64})> _newImages = [];
  bool _saving = false;
  bool _packManuallyEdited = false;

  bool get _isVisual => widget.kind == 'visual';

  @override
  void initState() {
    super.initState();
    _keepImages.addAll(widget.existing?.images ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    for (final c in _tabs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await openFiles(acceptedTypeGroups: [
      const XTypeGroup(label: 'images', extensions: ['png', 'jpg', 'jpeg', 'webp'])
    ]);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      setState(() => _newImages.add((name: f.name, base64: base64Encode(bytes))));
    }
  }

  void _toast(String msg, {bool warning = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 从 .docx / .md / .txt 导入正文，填充当前标签内容。
  Future<void> _importInto(String key) async {
    final l10n = context.l10n;
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'doc', extensions: ['docx', 'md', 'markdown', 'txt'])
    ]);
    if (file == null) return;
    try {
      final ext = p.extension(file.name).replaceFirst('.', '').toLowerCase();
      final String text;
      if (ext == 'docx') {
        text = extractDocxText(await file.readAsBytes());
      } else {
        text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      }
      _tabs[key]!.text = text;
      if (mounted) {
        setState(() {});
        _toast(l10n.manualImportSuccess, warning: false);
      }
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(_isVisual
          ? l10n.projectMsgEnterVisualManualName
          : l10n.projectDialogDirectorManualNamePh);
      return;
    }
    if (_keepImages.isEmpty && _newImages.isEmpty) {
      _toast(l10n.projectMsgEnterVisualManualImage);
      return;
    }
    for (final k in _keys) {
      if (_tabs[k]!.text.trim().isEmpty) {
        _toast(l10n.projectMsgEnterVisualManualTabData);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final engine = widget.ref.read(engineProvider);
      final data = {for (final k in _keys) k: _tabs[k]!.text};
      if (_isVisual) {
        engine.saveVisualManual(
          name: _name.text,
          pack: _pack.text,
          overwriteExisting: widget.existing != null,
          keepImages: _keepImages,
          imageBytesBase64: [for (final img in _newImages) img.base64],
          data: data,
        );
      } else {
        engine.saveDirectorManual(
          name: _name.text,
          pack: _pack.text,
          overwriteExisting: widget.existing != null,
          keepImages: _keepImages,
          imageBytesBase64: [for (final img in _newImages) img.base64],
          data: data,
        );
      }
      if (mounted) {
        _toast(
            _isVisual
                ? (widget.existing == null
                    ? l10n.projectMsgVisualManualAdded
                    : l10n.projectMsgVisualManualUpdated)
                : (widget.existing == null
                    ? l10n.projectMsgDirectorManualAdded
                    : l10n.projectMsgDirectorManualUpdated),
            warning: false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _tabLabel(String key) {
    final l10n = context.l10n;
    switch (key) {
      case 'README':
        return l10n.manualTabReadme;
      case 'prefix':
        return l10n.manualTabPrefix;
      case 'art_character':
        return l10n.manualTabCharacter;
      case 'art_character_derivative':
        return l10n.manualTabCharacterDerivative;
      case 'art_prop':
        return l10n.manualTabProp;
      case 'art_prop_derivative':
        return l10n.manualTabPropDerivative;
      case 'art_scene':
        return l10n.manualTabScene;
      case 'art_scene_derivative':
        return l10n.manualTabSceneDerivative;
      case 'director_storyboard':
        return l10n.manualTabStoryboard;
      case 'art_storyboard_video':
        return l10n.manualTabStoryboardVideo;
      case 'director_planning_style':
        return l10n.manualTabDirectorPlanning;
      case 'director_storyboard_table_style':
        return l10n.manualTabStoryboardTable;
      case 'director_planning_narrative':
        return l10n.manualTabNarrativePlanning;
      case 'director_storyboard_table_narrative':
        return l10n.manualTabNarrativeTable;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = context.l10n;
    return DefaultTabController(
      length: _keys.length,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _name,
                onChanged: (value) {
                  if (widget.existing == null && !_packManuallyEdited) {
                    _pack.text = sanitizePackName(value);
                  }
                },
                decoration: InputDecoration(
                  labelText: _isVisual
                      ? l10n.projectDialogVisualManualName
                      : l10n.projectDialogDirectorManualName,
                  hintText: _isVisual
                      ? l10n.projectDialogVisualManualNamePh
                      : l10n.projectDialogDirectorManualNamePh,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('manual-pack-id-input'),
                controller: _pack,
                enabled: widget.existing == null,
                onChanged: (_) => _packManuallyEdited = true,
                decoration: InputDecoration(
                  labelText: l10n.manualDirectoryId,
                  hintText: l10n.manualDirectoryIdHint,
                  helperText: widget.existing == null
                      ? l10n.manualDirectoryIdCreateHint
                      : l10n.manualDirectoryIdLockedHint,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _isVisual
                    ? l10n.projectDialogVisualManualCover
                    : l10n.projectDialogDirectorManualCover,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final path in _keepImages)
                  _CoverThumb(
                    child: Image.file(File(path), fit: BoxFit.cover),
                    onRemove: () => setState(() => _keepImages.remove(path)),
                  ),
                for (final img in _newImages)
                  _CoverThumb(
                    child: Image.memory(base64Decode(img.base64),
                        fit: BoxFit.cover),
                    onRemove: () => setState(() => _newImages.remove(img)),
                  ),
                InkWell(
                  onTap: _pickImages,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: df.stroke, width: 1.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: df.textTertiary),
                          Text(l10n.projectDialogUploadCover,
                              style: TextStyle(
                                  fontSize: 10, color: df.textTertiary)),
                        ]),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final k in _keys) Tab(text: _tabLabel(k))],
              ),
              SizedBox(
                height: 280,
                child: TabBarView(children: [
                  for (final k in _keys)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _importInto(k),
                              icon: const Icon(Icons.upload_file_outlined,
                                  size: 16),
                              label: Text(l10n.manualImportFile,
                                  style: const TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: TextField(
                              controller: _tabs[k],
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                  fontSize: 13, fontFamily: 'monospace'),
                              decoration: InputDecoration(
                                hintText: l10n.projectDialogPromptPlaceholder,
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ]),
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
      ]),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  const _CoverThumb({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        width: 80,
        height: 80,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: child,
      ),
      Positioned(
        top: 2,
        right: 2,
        child: InkWell(
          onTap: onRemove,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 12, color: Colors.white),
          ),
        ),
      ),
    ]);
  }
}
