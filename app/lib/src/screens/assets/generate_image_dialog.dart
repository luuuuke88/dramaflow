// 生成图片对话框（照抄 generateImage.vue，左 40% 表单 / 右 60% 结果版本网格）。
// 左：参考图（可选）/提示词+智能生成/模型/分辨率/生成；
// 右：图片版本（生成中/失败/完成三态、选中黑框、删除、自定义上传）+ 确定保存选中。
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/desktop_drop_file.dart';
import '../../widgets/asset_image_preview.dart';
import '../../widgets/policy_confirm.dart';
import '../project/model_select.dart';

const _imageFileExtensions = <String>[
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'bmp',
  'tif',
  'tiff',
  'heic',
  'heif',
  'avif',
  'svg',
];

const _imageTypeGroup = XTypeGroup(
  label: 'image',
  extensions: _imageFileExtensions,
  mimeTypes: <String>['image/*'],
  uniformTypeIdentifiers: <String>['public.image'],
  webWildCards: <String>['image/*'],
);

Future<bool?> showGenerateImageDialog(BuildContext context, WidgetRef ref,
    {required int projectId, required AssetRow asset}) {
  return showDFAdaptiveDialog<bool>(
    context,
    title: '${context.l10n.assetsGenHeader} · ${asset.name ?? ''}',
    desktopWidthFactor: 0.78,
    builder: (c) =>
        _GenerateImageBody(projectId: projectId, asset: asset, ref: ref),
  );
}

class _GenerateImageBody extends ConsumerStatefulWidget {
  final int projectId;
  final AssetRow asset;
  final WidgetRef ref;
  const _GenerateImageBody(
      {required this.projectId, required this.asset, required this.ref});

  @override
  ConsumerState<_GenerateImageBody> createState() => _GenerateImageBodyState();
}

class _GenerateImageBodyState extends ConsumerState<_GenerateImageBody> {
  late final TextEditingController _prompt =
      TextEditingController(text: widget.asset.prompt ?? '');
  String? _refBase64;
  String? _model;
  String _resolution = '1K';
  bool _polishing = false;
  bool _draggingReference = false;
  int? _selectedImageId;
  String? _uploadBase64;
  bool _customUploadSelected = false;

  @override
  void initState() {
    super.initState();
    _selectedImageId = widget.asset.imageId;
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickRef() async {
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file == null) return;
    await _setReferenceBytes(await file.readAsBytes());
  }

  Future<void> _setReferenceBytes(List<int> bytes) async {
    if (bytes.isEmpty) return;
    if (mounted) setState(() => _refBase64 = base64Encode(bytes));
  }

  Future<void> _dropReference(DropDoneDetails detail) async {
    final file = detail.files.where((file) {
      if (file.mimeType?.startsWith('image/') ?? false) return true;
      final extension = droppedFileName(file).split('.').last.toLowerCase();
      return _imageFileExtensions.contains(extension);
    }).firstOrNull;
    if (file == null) {
      _toast(context.l10n.assetsGenUploadRef);
      return;
    }
    try {
      await _setReferenceBytes(await readDroppedFileBytes(file));
    } catch (_) {
      if (mounted) _toast(context.l10n.assetsGenUploadRef);
    }
  }

  bool get _desktopDropEnabled =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Widget _referencePicker() {
    final df = context.df;
    final picker = InkWell(
      onTap: _pickRef,
      child: Container(
        width: 96,
        height: 96,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(
            color: _draggingReference ? df.primary : df.stroke,
            width: _draggingReference ? 2 : 1.4,
          ),
          borderRadius: BorderRadius.circular(DFTokens.radiusControl),
          color: df.surfaceMuted,
        ),
        child: _refBase64 == null
            ? Icon(Icons.add_photo_alternate_outlined, color: df.textTertiary)
            : Image.memory(
                base64Decode(_refBase64!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  color: df.textTertiary,
                ),
              ),
      ),
    );
    if (!_desktopDropEnabled) return picker;
    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingReference = true),
      onDragExited: (_) => setState(() => _draggingReference = false),
      onDragDone: (detail) async {
        if (mounted) setState(() => _draggingReference = false);
        await _dropReference(detail);
      },
      child: picker,
    );
  }

  Future<void> _polish() async {
    setState(() => _polishing = true);
    try {
      final prompt =
          await ref.read(engineProvider).polishAssetPrompt(widget.asset.id);
      _prompt.text = prompt;
      if (mounted) _toast(context.l10n.assetsGenPromptSuccess);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  Future<void> _generate() async {
    final l10n = context.l10n;
    if (_prompt.text.trim().isEmpty) {
      _toast(l10n.assetsGenFillPrompt);
      return;
    }
    if (_model == null) {
      _toast(l10n.assetsGenPickModel);
      return;
    }
    final engine = ref.read(engineProvider);
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'asset_image_generation',
      description: l10n.assetsGenGenerateBtn,
    )) {
      return;
    }
    if (!mounted) return;
    // 先保存提示词，再入队生图
    engine.updateAsset(widget.asset.id, prompt: _prompt.text);
    engine.generateAssetImages(
      widget.projectId,
      [(assetsId: widget.asset.id, refImageBase64: _refBase64)],
      resolution: _resolution,
      model: _model,
    );
    _toast(l10n.assetsGenAssetGenSuccess);
  }

  Future<void> _uploadCustom() async {
    final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _uploadBase64 = base64Encode(bytes);
      _selectedImageId = null;
      _customUploadSelected = false;
    });
  }

  Future<void> _deleteCandidate(AssetImageRow image) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.assetsConfirmDeleteHeader),
        content: Text(l10n.assetsGenConfirmDeleteImage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.assetsCancelBtn),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.df.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.assetsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(engineProvider).deleteAssetImage(image.id);
    setState(() {
      if (_selectedImageId == image.id) _selectedImageId = null;
    });
  }

  void _confirm() {
    final l10n = context.l10n;
    final customImageSelected = _customUploadSelected && _uploadBase64 != null;
    if (_selectedImageId == null && !customImageSelected) {
      _toast(l10n.assetsGenConfirmSelect);
      return;
    }
    ref.read(engineProvider).saveAssetImage(
          assetsId: widget.asset.id,
          projectId: widget.projectId,
          base64Image: customImageSelected ? _uploadBase64 : null,
          imageId: _selectedImageId,
          prompt: _prompt.text,
          type: widget.asset.type,
        );
    _toast(l10n.assetsGenImageSaved);
    Navigator.of(context).pop(true);
  }

  Widget _leftPanel() {
    final l10n = context.l10n;
    final df = context.df;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(l10n.assetsGenUploadRef,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: df.surfaceMuted,
            borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          ),
          child: Text(l10n.assetsGenOptional,
              style: TextStyle(fontSize: 10, color: df.textTertiary)),
        ),
      ]),
      const SizedBox(height: 8),
      _referencePicker(),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: Text(l10n.assetsGenPromptLabel,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        OutlinedButton.icon(
          onPressed: _polishing ? null : _polish,
          icon: _polishing
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 14),
          label: Text(l10n.assetsGenSmartGenerate,
              style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: _prompt,
        minLines: 8,
        maxLines: 8,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(hintText: l10n.assetsAddPromptPh),
      ),
      const SizedBox(height: 14),
      Text(l10n.assetsGenSelectModel,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      ModelSelect(
        kind: 'image',
        value: _model,
        hint: l10n.assetsGenPickModel,
        onChanged: (o) => setState(() => _model = o?.value),
      ),
      const SizedBox(height: 14),
      Text(l10n.assetsGenSelectResolution,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: '1K', label: Text('1K')),
          ButtonSegment(value: '2K', label: Text('2K')),
          ButtonSegment(value: '4K', label: Text('4K')),
        ],
        selected: {_resolution},
        onSelectionChanged: (s) => setState(() => _resolution = s.single),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.bolt, size: 18),
          label: Text(l10n.assetsGenGenerateBtn),
        ),
      ),
    ]);
  }

  Widget _imageCell(AssetImageRow img) {
    final df = context.df;
    final l10n = context.l10n;
    final selected = img.id == _selectedImageId;
    Widget inner;
    if (img.state == stateGenerating) {
      inner = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(height: 6),
        Text(l10n.assetsGenGeneratingLabel,
            style: TextStyle(fontSize: 11, color: df.textTertiary)),
      ]);
    } else if (img.state == stateFailed) {
      inner = Tooltip(
        message: localizeReason(l10n, img.errorReason) ?? '',
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.close, color: df.danger),
          Text(l10n.assetsGenGenFailed,
              style: TextStyle(fontSize: 11, color: df.danger)),
        ]),
      );
    } else if (img.filePath != null) {
      final abs = ref.read(engineProvider).mediaAbsPath(img.filePath!);
      inner = Image.file(File(abs),
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              Icon(Icons.broken_image_outlined, color: df.textTertiary));
    } else {
      inner = const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: img.state == stateDone
          ? () => setState(() {
                _selectedImageId = img.id;
                _customUploadSelected = false;
              })
          : null,
      child: Stack(children: [
        Container(
          width: 148,
          height: 148,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              width: 2,
              color: selected ? df.textPrimary : df.stroke,
            ),
            color: df.surfaceMuted,
          ),
          child: SizedBox.expand(child: inner),
        ),
        if (selected)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration:
                  BoxDecoration(color: df.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 12, color: Colors.white),
            ),
          ),
        if (img.state == stateDone && img.filePath != null)
          Positioned(
            top: 2,
            left: 2,
            child: IconButton(
              key: const Key('asset-image-candidate-preview'),
              tooltip: l10n.assetsColPreview,
              visualDensity: VisualDensity.compact,
              onPressed: () => showAssetImagePreview(
                context,
                absPath: ref.read(engineProvider).mediaAbsPath(img.filePath!),
              ),
              icon: const Icon(Icons.zoom_in_outlined,
                  size: 18, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
        if (img.state != stateGenerating)
          Positioned(
            bottom: 6,
            right: 6,
            child: InkWell(
              onTap: () => _deleteCandidate(img),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.delete_outline,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _rightPanel() {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final images = ref.watch(engineProvider).assetImages(widget.asset.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(l10n.assetsGenResultTitle,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: df.primarySubtle,
            borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          ),
          child: Text(l10n.assetsGenGeneratedCount('${images.length}'),
              style: TextStyle(fontSize: 11, color: df.primary)),
        ),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: SingleChildScrollView(
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final img in images) _imageCell(img),
            if (_uploadBase64 != null)
              GestureDetector(
                onTap: () => setState(() {
                  _selectedImageId = null;
                  _customUploadSelected = true;
                }),
                child: Stack(children: [
                  Container(
                    width: 148,
                    height: 148,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        width: 2,
                        color:
                            _customUploadSelected ? df.textPrimary : df.stroke,
                      ),
                    ),
                    child: Image.memory(base64Decode(_uploadBase64!),
                        fit: BoxFit.cover),
                  ),
                  if (_customUploadSelected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: df.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 12, color: Colors.white),
                      ),
                    ),
                ]),
              ),
            InkWell(
              onTap: _uploadCustom,
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  border: Border.all(color: df.stroke, width: 1.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add, color: df.textTertiary, size: 28),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canConfirm = _selectedImageId != null ||
        (_customUploadSelected && _uploadBase64 != null);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: LayoutBuilder(builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 700;
            final left = _leftPanel();
            final right = SizedBox(height: 420, child: _rightPanel());
            if (!twoCol) {
              return SingleChildScrollView(
                child:
                    Column(children: [left, const SizedBox(height: 16), right]),
              );
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: SingleChildScrollView(child: left)),
              const SizedBox(width: 20),
              Expanded(flex: 3, child: right),
            ]);
          }),
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
            onPressed: canConfirm ? _confirm : null,
            child: Text(l10n.commonConfirm),
          ),
        ]),
      ),
    ]);
  }
}
