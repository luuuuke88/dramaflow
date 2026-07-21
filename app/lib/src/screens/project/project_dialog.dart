// 项目新建/编辑对话框（照抄 projectDialog.vue 双栏结构）：
// 左栏＝项目类型/名称/小说类型/图片模型+画质/视频模型+模式/影片比例/简介；
// 右栏＝视觉手册画廊（选中→artStyle）+ 导演手册画廊（选中→directorManual）。
// 校验照抄：名称必填。移动端 <840 全屏单列。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../engine/manuals.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_select.dart';
import '../manuals/manual_editor.dart';
import '../manuals/manual_gallery.dart';
import 'model_select.dart';

Future<bool?> showProjectDialog(BuildContext context, {ProjectRow? existing}) {
  final l10n = context.l10n;
  return showDFAdaptiveDialog<bool>(
    context,
    title: existing == null
        ? l10n.projectDialogAddTitle
        : l10n.projectDialogEditTitle,
    desktopWidthFactor: 0.72,
    builder: (c) => _ProjectDialogBody(existing: existing),
  );
}

class _ProjectDialogBody extends ConsumerStatefulWidget {
  final ProjectRow? existing;
  const _ProjectDialogBody({required this.existing});

  @override
  ConsumerState<_ProjectDialogBody> createState() => _ProjectDialogBodyState();
}

class _ProjectDialogBodyState extends ConsumerState<_ProjectDialogBody> {
  late String _projectType = widget.existing?.projectType ?? 'novel';
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _novelType =
      TextEditingController(text: widget.existing?.type ?? '');
  late final TextEditingController _intro =
      TextEditingController(text: widget.existing?.intro ?? '');
  late String? _imageModel = widget.existing?.imageModel;
  late String? _imageQuality = widget.existing?.imageQuality ?? '1K';
  late String? _videoModel = widget.existing?.videoModel;
  late String? _mode = widget.existing?.mode;
  late String? _videoRatio = widget.existing?.videoRatio ?? '16:9';
  late String? _artStyle = widget.existing?.artStyle;
  late String? _directorManual = widget.existing?.directorManual;
  List<String> _videoModes = const [];
  bool _saving = false;

  List<ManualPack> _visuals = const [];
  List<ManualPack> _directors = const [];

  @override
  void initState() {
    super.initState();
    _name.addListener(_onFormChanged);
    _reloadManuals();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateExistingVideoModes();
    });
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _isValid =>
      _name.text.trim().isNotEmpty &&
      _artStyle != null &&
      _artStyle!.isNotEmpty &&
      _directorManual != null &&
      _directorManual!.isNotEmpty;

  Future<void> _hydrateExistingVideoModes() async {
    final selected = _videoModel;
    if (selected == null || selected.isEmpty) return;
    final options = await ref.read(modelOptionsProvider('video').future);
    if (!mounted) return;
    final option = options.where((item) => item.value == selected).firstOrNull;
    if (option == null) return;
    setState(() => _setVideoModes(option));
  }

  void _setVideoModes(ModelOption? option) {
    final rawVideo = option?.capabilities['video'];
    final modes =
        rawVideo is Map ? rawVideo['modes'] : option?.capabilities['modes'];
    _videoModes =
        modes is List ? modes.map((item) => '$item').toList() : const [];
    if (!_videoModes.contains(_mode)) _mode = null;
  }

  void _reloadManuals() {
    final engine = ref.read(engineProvider);
    setState(() {
      _visuals = engine.visualManuals();
      _directors = engine.directorManuals();
    });
  }

  @override
  void dispose() {
    _name.removeListener(_onFormChanged);
    _name.dispose();
    _novelType.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      _toast(l10n.projectMsgEnterProjectName);
      return;
    }
    if (_artStyle == null || _artStyle!.isEmpty) {
      _toast(l10n.projectMsgEnterArtStyle);
      return;
    }
    if (_directorManual == null || _directorManual!.isEmpty) {
      _toast(l10n.projectMsgDirectorManual);
      return;
    }
    setState(() => _saving = true);
    try {
      final engine = ref.read(engineProvider);
      if (widget.existing == null) {
        engine.addProject(
          projectType: _projectType,
          name: _name.text.trim(),
          intro: _intro.text,
          type: _novelType.text,
          artStyle: _artStyle,
          directorManual: _directorManual,
          videoRatio: _videoRatio,
          imageModel: _imageModel,
          videoModel: _videoModel,
          imageQuality: _imageQuality,
          mode: _mode,
        );
        _toast(l10n.projectMsgAddSuccess);
      } else {
        engine.editProject(
          widget.existing!.id,
          projectType: _projectType,
          name: _name.text.trim(),
          intro: _intro.text,
          type: _novelType.text,
          artStyle: _artStyle,
          directorManual: _directorManual,
          videoRatio: _videoRatio,
          imageModel: _imageModel,
          videoModel: _videoModel,
          imageQuality: _imageQuality,
          mode: _mode,
        );
        ref.read(currentProjectProvider.notifier).refresh();
        _toast(l10n.projectMsgEditSuccess);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        _toast(localizeError(context, e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteManual(String kind, ManualPack pack) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(kind == 'visual'
            ? l10n.projectMsgDeleteVisualManualHeader
            : l10n.projectMsgDeleteDirectorManualHeader),
        content: Text(kind == 'visual'
            ? l10n.projectMsgDeleteVisualManualBody(pack.name)
            : l10n.projectMsgDeleteDirectorManualBody(pack.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.projectMsgDeleteVisualManualCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.projectMsgDeleteVisualManualConfirm)),
        ],
      ),
    );
    if (confirmed != true) return;
    final engine = ref.read(engineProvider);
    if (kind == 'visual') {
      engine.deleteVisualManual(pack.pack);
      if (_artStyle == pack.pack) _artStyle = null;
    } else {
      engine.deleteDirectorManual(pack.pack);
      if (_directorManual == pack.pack) _directorManual = null;
    }
    _toast(l10n.projectMsgVisualManualDeleted);
    _reloadManuals();
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final df = context.df;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: df.surfaceMuted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: df.stroke.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: df.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: df.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _leftForm() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          context,
          title: l10n.projectDialogProjectType,
          icon: Icons.edit_note_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(l10n.projectDialogProjectType),
              DFSelect<String>(
                value: _projectType,
                hint: l10n.projectDialogSelectType,
                items: [
                  DFSelectItem(
                      value: 'novel', label: l10n.projectDialogBasedOnNovel),
                  DFSelectItem(
                      value: 'script', label: l10n.projectDialogBasedOnScript),
                ],
                onChanged: (v) => setState(() => _projectType = v ?? 'novel'),
              ),
              _label(l10n.projectDialogProjectName),
              TextField(
                controller: _name,
                decoration:
                    InputDecoration(hintText: l10n.projectDialogProjectNamePh),
              ),
              _label(l10n.projectDialogNovelType),
              TextField(
                controller: _novelType,
                decoration:
                    InputDecoration(hintText: l10n.projectDialogNovelTypePh),
              ),
            ],
          ),
        ),
        _buildSectionCard(
          context,
          title: l10n.projectDialogModelData,
          icon: Icons.tune_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(l10n.projectDialogModelData),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: ModelSelect(
                    kind: 'image',
                    value: _imageModel,
                    hint: l10n.projectMsgEnterImageModel,
                    onChanged: (o) => setState(() => _imageModel = o?.value),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 1,
                  child: DFSelect<String>(
                    value: _imageQuality,
                    items: const [
                      DFSelectItem(value: '1K', label: '1K'),
                      DFSelectItem(value: '2K', label: '2K'),
                      DFSelectItem(value: '4K', label: '4K'),
                    ],
                    onChanged: (v) => setState(() => _imageQuality = v),
                  ),
                ),
              ]),
              _label(l10n.projectDialogVideoModelData),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: ModelSelect(
                    kind: 'video',
                    value: _videoModel,
                    hint: l10n.projectMsgEnterVideoModel,
                    onChanged: (o) => setState(() {
                      _videoModel = o?.value;
                      _setVideoModes(o);
                    }),
                  ),
                ),
                if (_videoModes.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 1,
                    child: DFSelect<String>(
                      value: _mode,
                      hint: l10n.projectMsgSelectMode,
                      items: [
                        for (final m in _videoModes)
                          DFSelectItem(value: m, label: m),
                      ],
                      onChanged: (v) => setState(() => _mode = v),
                    ),
                  ),
                ],
              ]),
              _label(l10n.projectDialogVideoRatio),
              DFSelect<String>(
                value: _videoRatio,
                items: const [
                  DFSelectItem(value: '16:9', label: '16:9'),
                  DFSelectItem(value: '9:16', label: '9:16'),
                ],
                onChanged: (v) => setState(() => _videoRatio = v),
              ),
              _label(l10n.projectDialogNovelIntro),
              TextField(
                controller: _intro,
                minLines: 3,
                maxLines: 5,
                decoration:
                    InputDecoration(hintText: l10n.projectDialogNovelIntroPh),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rightManuals() {
    final l10n = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ManualGallery(
        title: l10n.projectDialogVisualManual,
        addLabel: l10n.projectDialogNewVisualManual,
        packs: _visuals,
        selectedPackId: _artStyle,
        onSelect: (p) => setState(() => _artStyle = p?.pack),
        onCreate: () async {
          final saved = await showManualEditor(context, ref, kind: 'visual');
          if (saved == true) _reloadManuals();
        },
        onEdit: (p) async {
          final saved =
              await showManualEditor(context, ref, kind: 'visual', existing: p);
          if (saved == true) _reloadManuals();
        },
        onDelete: (p) => _deleteManual('visual', p),
      ),
      const SizedBox(height: 14),
      ManualGallery(
        title: l10n.projectDialogDirectorManual,
        addLabel: l10n.projectDialogAddDirectorManual,
        packs: _directors,
        selectedPackId: _directorManual,
        onSelect: (p) => setState(() => _directorManual = p?.pack),
        onCreate: () async {
          final saved = await showManualEditor(context, ref, kind: 'director');
          if (saved == true) _reloadManuals();
        },
        onEdit: (p) async {
          final saved = await showManualEditor(context, ref,
              kind: 'director', existing: p);
          if (saved == true) _reloadManuals();
        },
        onDelete: (p) => _deleteManual('director', p),
      ),
    ]);
  }

  Widget _label(String text) {
    final df = context.df;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: df.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: LayoutBuilder(builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 700;
            if (!twoCol) {
              return Column(children: [
                _leftForm(),
                const SizedBox(height: 20),
                _rightManuals(),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _leftForm()),
              const SizedBox(width: 24),
              Expanded(child: _rightManuals()),
            ]);
          }),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: df.stroke)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.projectDialogCancel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 16),
            style: FilledButton.styleFrom(
              backgroundColor: _isValid
                  ? df.primary
                  : df.primary.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
            ),
            onPressed: _saving ? null : _save,
            label: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.existing == null
                    ? l10n.projectDialogOk
                    : l10n.projectDialogSave),
          ),
        ]),
      ),
    ]);
  }
}
