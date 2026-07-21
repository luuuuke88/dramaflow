// 项目新建/编辑对话框（照抄 projectDialog.vue 双栏结构）：
// 左栏＝项目类型/名称/小说类型/图片模型+画质/视频模型+模式/影片比例/简介；
// 右栏＝视觉手册画廊（选中→artStyle）+ 导演手册画廊（选中→directorManual）。
// 校验照抄：名称必填。移动端 <840 全屏单列。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dramaflow/l10n/app_localizations.dart';

import '../../engine/engine.dart';
import '../../engine/manuals.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../manuals/manual_editor.dart';
import '../manuals/manual_gallery.dart';
import 'model_select.dart';

/// ToonFlow 项目向导在保存前按固定顺序提示首个缺失项。
enum ProjectIntakeField {
  name,
  type,
  imageModel,
  videoModel,
  artStyle,
  directorManual,
  videoRatio,
  intro,
  imageQuality,
  mode,
}

ProjectIntakeField? firstMissingProjectIntakeField({
  required String? name,
  required String? type,
  required String? imageModel,
  required String? videoModel,
  required String? artStyle,
  required String? directorManual,
  required String? videoRatio,
  required String? intro,
  required String? imageQuality,
  required String? mode,
}) {
  final values = <(ProjectIntakeField, String?)>[
    (ProjectIntakeField.name, name),
    (ProjectIntakeField.type, type),
    (ProjectIntakeField.imageModel, imageModel),
    (ProjectIntakeField.videoModel, videoModel),
    (ProjectIntakeField.artStyle, artStyle),
    (ProjectIntakeField.directorManual, directorManual),
    (ProjectIntakeField.videoRatio, videoRatio),
    (ProjectIntakeField.intro, intro),
    (ProjectIntakeField.imageQuality, imageQuality),
    (ProjectIntakeField.mode, mode),
  ];
  for (final (field, value) in values) {
    if (value?.trim().isEmpty ?? true) return field;
  }
  return null;
}

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
  String? _validationMessage;

  List<ManualPack> _visuals = const [];
  List<ManualPack> _directors = const [];

  @override
  void initState() {
    super.initState();
    _reloadManuals();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateExistingVideoModes();
    });
  }

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
    _name.dispose();
    _novelType.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openProviderSettings() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/settings?section=providers');
  }

  String _intakeError(
    AppLocalizations l10n,
    ProjectIntakeField field,
  ) =>
      switch (field) {
        ProjectIntakeField.name => l10n.projectMsgEnterProjectName,
        ProjectIntakeField.type => l10n.projectMsgEnterProjectType,
        ProjectIntakeField.imageModel => l10n.projectMsgEnterImageModel,
        ProjectIntakeField.videoModel => l10n.projectMsgEnterVideoModel,
        ProjectIntakeField.artStyle => l10n.projectMsgEnterArtStyle,
        ProjectIntakeField.directorManual => l10n.projectMsgDirectorManual,
        ProjectIntakeField.videoRatio => l10n.projectMsgEnterVideoRatio,
        ProjectIntakeField.intro => l10n.projectMsgEnterProjectIntro,
        ProjectIntakeField.imageQuality => l10n.projectMsgEnterProjectQuality,
        ProjectIntakeField.mode => l10n.projectMsgSelectMode,
      };

  Future<void> _save() async {
    final l10n = context.l10n;
    final missing = firstMissingProjectIntakeField(
      name: _name.text,
      type: _novelType.text,
      imageModel: _imageModel,
      videoModel: _videoModel,
      artStyle: _artStyle,
      directorManual: _directorManual,
      videoRatio: _videoRatio,
      intro: _intro.text,
      imageQuality: _imageQuality,
      mode: _mode,
    );
    if (missing != null) {
      setState(() => _validationMessage = _intakeError(l10n, missing));
      return;
    }
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
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

  Widget _leftForm() {
    final l10n = context.l10n;
    final df = context.df;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(l10n.projectDialogProjectType),
      DropdownButtonFormField<String>(
        initialValue: _projectType,
        isExpanded: true,
        items: [
          DropdownMenuItem(
              value: 'novel', child: Text(l10n.projectDialogBasedOnNovel)),
          DropdownMenuItem(
              value: 'script', child: Text(l10n.projectDialogBasedOnScript)),
        ],
        onChanged: (v) => setState(() => _projectType = v ?? 'novel'),
        hint: Text(l10n.projectDialogSelectType),
      ),
      _label(l10n.projectDialogProjectName),
      TextField(
        controller: _name,
        onChanged: (_) => setState(() => _validationMessage = null),
        decoration: InputDecoration(hintText: l10n.projectDialogProjectNamePh),
      ),
      _label(l10n.projectDialogNovelType),
      TextField(
        controller: _novelType,
        onChanged: (_) => setState(() => _validationMessage = null),
        decoration: InputDecoration(hintText: l10n.projectDialogNovelTypePh),
      ),
      _label(l10n.projectDialogModelData),
      Row(children: [
        Expanded(
          flex: 3,
          child: ModelSelect(
            kind: 'image',
            value: _imageModel,
            hint: l10n.projectMsgEnterImageModel,
            onChanged: (o) => setState(() {
              _imageModel = o?.value;
              _validationMessage = null;
            }),
            onConfigure: _openProviderSettings,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<String>(
            initialValue: _imageQuality,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: '1K', child: Text('1K')),
              DropdownMenuItem(value: '2K', child: Text('2K')),
              DropdownMenuItem(value: '4K', child: Text('4K')),
            ],
            onChanged: (v) => setState(() {
              _imageQuality = v;
              _validationMessage = null;
            }),
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
              _validationMessage = null;
            }),
            onConfigure: _openProviderSettings,
          ),
        ),
        if (_videoModes.isNotEmpty) ...[
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: DropdownButtonFormField<String>(
              initialValue: _mode,
              isExpanded: true,
              hint: Text(l10n.projectMsgSelectMode,
                  style: TextStyle(fontSize: 12, color: df.textTertiary)),
              items: [
                for (final m in _videoModes)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() {
                _mode = v;
                _validationMessage = null;
              }),
            ),
          ),
        ],
      ]),
      _label(l10n.projectDialogVideoRatio),
      DropdownButtonFormField<String>(
        initialValue: _videoRatio,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: '16:9', child: Text('16:9')),
          DropdownMenuItem(value: '9:16', child: Text('9:16')),
        ],
        onChanged: (v) => setState(() {
          _videoRatio = v;
          _validationMessage = null;
        }),
      ),
      _label(l10n.projectDialogNovelIntro),
      TextField(
        controller: _intro,
        minLines: 3,
        maxLines: 6,
        onChanged: (_) => setState(() => _validationMessage = null),
        decoration: InputDecoration(hintText: l10n.projectDialogNovelIntroPh),
      ),
    ]);
  }

  Widget _rightManuals() {
    final l10n = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ManualGallery(
        title: l10n.projectDialogVisualManual,
        addLabel: l10n.projectDialogNewVisualManual,
        packs: _visuals,
        selectedPackId: _artStyle,
        onSelect: (p) => setState(() {
          _artStyle = p?.pack;
          _validationMessage = null;
        }),
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
      const SizedBox(height: 20),
      ManualGallery(
        title: l10n.projectDialogDirectorManual,
        addLabel: l10n.projectDialogAddDirectorManual,
        packs: _directors,
        selectedPackId: _directorManual,
        onSelect: (p) => setState(() {
          _directorManual = p?.pack;
          _validationMessage = null;
        }),
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
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
      if (_validationMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _validationMessage!,
              key: const Key('project-intake-validation-error'),
              style: TextStyle(color: context.df.danger),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.projectDialogCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
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
