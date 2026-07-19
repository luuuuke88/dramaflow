import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../engine/audio_bind.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/asset_image_preview.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/df_status_tag.dart';
import '../../widgets/df_tag_chip.dart';
import '../../widgets/policy_confirm.dart';
import '../project/model_select.dart';

class CornerScapeScreen extends ConsumerStatefulWidget {
  final int projectId;

  const CornerScapeScreen({super.key, required this.projectId});

  @override
  ConsumerState<CornerScapeScreen> createState() => _CornerScapeScreenState();
}

class _CornerScapeScreenState extends ConsumerState<CornerScapeScreen> {
  final Set<int> _selected = {};
  final Set<String> _types = {};
  final TextEditingController _otherPrompt = TextEditingController();
  String? _selectedModel;
  String _resolution = '1K';
  bool _modelLoaded = false;
  bool _polishing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_modelLoaded) return;
    _modelLoaded = true;
    ref.read(engineProvider).getProject(widget.projectId).then((project) {
      if (mounted && _selectedModel == null) {
        setState(() => _selectedModel = project.imageModel);
      }
    });
  }

  @override
  void dispose() {
    _otherPrompt.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<CornerScapeAsset> _visible(List<CornerScapeAsset> assets) {
    if (_types.isEmpty) return assets;
    return assets.where((item) => _types.contains(item.asset.type)).toList();
  }

  List<int> _selectedVisible(List<CornerScapeAsset> visible) {
    final visibleIds = visible.map((item) => item.asset.id).toSet();
    return _selected.where(visibleIds.contains).toList();
  }

  void _toggleType(String type, List<CornerScapeAsset> assets) {
    setState(() {
      if (!_types.add(type)) _types.remove(type);
      final visibleIds = _visible(assets).map((item) => item.asset.id).toSet();
      _selected.removeWhere((id) => !visibleIds.contains(id));
    });
  }

  void _selectWhere(
    List<CornerScapeAsset> visible,
    bool Function(CornerScapeAsset item) predicate,
  ) {
    setState(() {
      _selected
        ..clear()
        ..addAll(
          visible.where(predicate).map((item) => item.asset.id),
        );
    });
  }

  void _invertSelection(List<CornerScapeAsset> visible) {
    setState(() {
      final visibleIds = visible.map((item) => item.asset.id).toSet();
      final inverted = visibleIds.difference(_selected);
      _selected
        ..removeWhere(visibleIds.contains)
        ..addAll(inverted);
    });
  }

  Future<void> _generatePrompts(List<CornerScapeAsset> visible) async {
    final ids = _selectedVisible(visible);
    final l10n = context.l10n;
    if (ids.isEmpty) {
      _toast(l10n.cornerScapeSelectAtLeastOneAsset);
      return;
    }
    final engine = ref.read(engineProvider);
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'asset_prompt_polish',
      description: l10n.cornerScapeGeneratePrompts,
      units: ids.length,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _polishing = true);
    final supplement = _otherPrompt.text.trim();
    try {
      for (final id in ids) {
        final prompt = await engine.polishAssetPrompt(id);
        if (supplement.isNotEmpty) {
          engine.updateAsset(id, prompt: '$prompt\n$supplement');
        }
      }
      if (mounted) _toast(l10n.cornerScapePromptDone);
    } catch (error) {
      if (mounted) {
        _toast('${l10n.cornerScapePromptFailed}: '
            '${localizeError(context, error)}');
      }
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  Future<void> _matchAudio(List<CornerScapeAsset> visible) async {
    final ids = _selectedVisible(visible);
    final l10n = context.l10n;
    if (ids.isEmpty) {
      _toast(l10n.cornerScapeSelectAtLeastOneAsset);
      return;
    }
    final engine = ref.read(engineProvider);
    if (engine.audioPool(widget.projectId).isEmpty) {
      _toast(l10n.cornerScapeNoAudioPool);
      return;
    }
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'audio_bind',
      description: l10n.cornerScapeMatchAudio,
      units: ids.length,
    )) {
      return;
    }
    if (!mounted) return;
    engine.batchBindAudio(widget.projectId, ids);
    setState(_selected.clear);
    _toast(l10n.cornerScapeAudioMatchStarted);
  }

  Future<void> _startBatch(List<CornerScapeAsset> visible) async {
    final ids = _selectedVisible(visible);
    final l10n = context.l10n;
    if (ids.isEmpty) {
      _toast(l10n.cornerScapeSelectAtLeastOneAsset);
      return;
    }
    final byId = {for (final item in visible) item.asset.id: item};
    if (ids.any((id) => (byId[id]?.asset.prompt ?? '').trim().isEmpty)) {
      _toast(l10n.cornerScapeMissingPrompts);
      return;
    }
    final engine = ref.read(engineProvider);
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'asset_image_generation',
      description: l10n.cornerScapeStartBatch,
      units: ids.length,
    )) {
      return;
    }
    if (!mounted) return;
    final models = await ref.read(modelOptionsProvider('image').future);
    if (!mounted) return;
    final model = _selectedModel;
    if (model == null || !models.any((option) => option.value == model)) {
      _toast(l10n.assetsGenPickModel);
      return;
    }
    engine.generateAssetImages(
      widget.projectId,
      [
        for (final id in ids) (assetsId: id, refImageBase64: null),
      ],
      model: model,
      resolution: _resolution,
    );
    setState(_selected.clear);
    _toast(l10n.cornerScapeImageGenerationStarted);
  }

  void _showBatchPreview(List<CornerScapeAsset> visible) {
    final engine = ref.read(engineProvider);
    final selectedIds = _selectedVisible(visible).toSet();
    var paths = visible
        .where(
          (item) =>
              selectedIds.contains(item.asset.id) &&
              item.asset.filePath?.isNotEmpty == true,
        )
        .map((item) => engine.mediaAbsPath(item.asset.filePath!))
        .toList();
    if (paths.isEmpty) {
      paths = visible
          .where((item) => item.asset.filePath?.isNotEmpty == true)
          .map((item) => engine.mediaAbsPath(item.asset.filePath!))
          .toList();
    }
    if (paths.isEmpty) {
      _toast(context.l10n.cornerScapeNoPreviewImages);
      return;
    }
    showDFAdaptiveDialog<void>(
      context,
      title: context.l10n.cornerScapePreviewTitle,
      desktopWidthFactor: .68,
      builder: (context) => SizedBox(
        height: 560,
        child: GridView.builder(
          padding: const EdgeInsets.all(DFTokens.s16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 190,
            crossAxisSpacing: DFTokens.s12,
            mainAxisSpacing: DFTokens.s12,
          ),
          itemCount: paths.length,
          itemBuilder: (context, index) {
            final path = paths[index];
            return InkWell(
              onTap: () => showAssetImagePreview(context, absPath: path),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                child: ColoredBox(
                  color: context.df.surfaceMuted,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: context.df.textTertiary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jobsGenerationProvider);
    final engine = ref.watch(engineProvider);
    final assets = engine.cornerScapeAssets(widget.projectId);
    final assetIds = assets.map((item) => item.asset.id).toSet();
    _selected.removeWhere((id) => !assetIds.contains(id));
    final visible = _visible(assets);
    final audioByAsset = {
      for (final binding in engine.assetAudioBindings(widget.projectId))
        binding.assetId: binding.audioName,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        final settingsPanel = _settingsPanel(assets, visible);
        final cardGrid = _cardGrid(assets, visible, audioByAsset);
        if (compact) {
          final panelHeight = (constraints.maxHeight * .56).clamp(360.0, 560.0);
          return Column(
            children: [
              SizedBox(height: panelHeight, child: settingsPanel),
              Expanded(child: cardGrid),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 328, child: settingsPanel),
            Expanded(child: cardGrid),
          ],
        );
      },
    );
  }

  Widget _settingsPanel(
    List<CornerScapeAsset> assets,
    List<CornerScapeAsset> visible,
  ) {
    final l10n = context.l10n;
    final df = context.df;
    final selectedCount = _selectedVisible(visible).length;
    List<CornerScapeAsset> currentVisible() => _visible(assets);

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: DFTokens.s8),
          child: Text(
            text,
            style: DFTokens.caption12.copyWith(
              color: df.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    Widget quickAction({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) =>
        OutlinedButton.icon(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: DFTokens.s8),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(label),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: df.surface,
        border: Border(right: BorderSide(color: df.stroke)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DFTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.cornerScapeBatchSettings,
                    style: DFTokens.title20w700.copyWith(color: df.textPrimary),
                  ),
                ),
                DFTagChip(
                  label: visible.length.toString(),
                  tone: DFTagTone.primary,
                ),
              ],
            ),
            const SizedBox(height: DFTokens.s20),
            sectionLabel(l10n.cornerScapeQuickActions),
            Wrap(
              spacing: DFTokens.s8,
              runSpacing: DFTokens.s8,
              children: [
                quickAction(
                  icon: Icons.done_all_rounded,
                  label: l10n.cornerScapeSelectAll,
                  onPressed: () => _selectWhere(currentVisible(), (_) => true),
                ),
                quickAction(
                  icon: Icons.notes_rounded,
                  label: l10n.cornerScapeSelectPromptEmpty,
                  onPressed: () => _selectWhere(
                    currentVisible(),
                    (item) => (item.asset.prompt ?? '').trim().isEmpty,
                  ),
                ),
                quickAction(
                  icon: Icons.image_not_supported_outlined,
                  label: l10n.cornerScapeSelectUngenerated,
                  onPressed: () => _selectWhere(
                    currentVisible(),
                    (item) => item.asset.imageState?.isNotEmpty != true,
                  ),
                ),
                quickAction(
                  icon: Icons.check_circle_outline_rounded,
                  label: l10n.cornerScapeSelectCompleted,
                  onPressed: () => _selectWhere(
                    currentVisible(),
                    (item) => item.asset.imageState == stateDone,
                  ),
                ),
                quickAction(
                  icon: Icons.error_outline_rounded,
                  label: l10n.cornerScapeSelectFailed,
                  onPressed: () => _selectWhere(
                    currentVisible(),
                    (item) => item.asset.imageState == stateFailed,
                  ),
                ),
                quickAction(
                  icon: Icons.swap_horiz_rounded,
                  label: l10n.cornerScapeInvertSelection,
                  onPressed: () => _invertSelection(currentVisible()),
                ),
                quickAction(
                  icon: Icons.clear_rounded,
                  label: l10n.cornerScapeClearSelection,
                  onPressed: () => setState(_selected.clear),
                ),
                quickAction(
                  icon: Icons.grid_view_rounded,
                  label: l10n.cornerScapeBatchPreview,
                  onPressed: () => _showBatchPreview(currentVisible()),
                ),
              ],
            ),
            const SizedBox(height: DFTokens.s20),
            sectionLabel(l10n.cornerScapeAssetType),
            Wrap(
              spacing: DFTokens.s8,
              runSpacing: DFTokens.s8,
              children: [
                FilterChip(
                  label: Text(l10n.cornerScapeFilterRole),
                  selected: _types.contains('role'),
                  onSelected: (_) => _toggleType('role', assets),
                ),
                FilterChip(
                  label: Text(l10n.cornerScapeFilterScene),
                  selected: _types.contains('scene'),
                  onSelected: (_) => _toggleType('scene', assets),
                ),
                FilterChip(
                  label: Text(l10n.cornerScapeFilterTool),
                  selected: _types.contains('tool'),
                  onSelected: (_) => _toggleType('tool', assets),
                ),
              ],
            ),
            const SizedBox(height: DFTokens.s20),
            sectionLabel(l10n.cornerScapeImageModel),
            ModelSelect(
              kind: 'image',
              value: _selectedModel,
              hint: l10n.assetsGenPickModel,
              onChanged: (option) =>
                  setState(() => _selectedModel = option?.value),
            ),
            const SizedBox(height: DFTokens.s16),
            sectionLabel(l10n.cornerScapeResolution),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '1K', label: Text('1K')),
                ButtonSegment(value: '2K', label: Text('2K')),
                ButtonSegment(value: '4K', label: Text('4K')),
              ],
              selected: {_resolution},
              onSelectionChanged: (values) =>
                  setState(() => _resolution = values.single),
            ),
            const SizedBox(height: DFTokens.s16),
            TextField(
              controller: _otherPrompt,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.cornerScapeOtherPrompt,
                hintText: l10n.cornerScapeOtherPromptHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: DFTokens.s16),
            Align(
              alignment: Alignment.centerLeft,
              child: DFTagChip(
                label: l10n.assetsBatchSelected(selectedCount.toString()),
                tone: DFTagTone.primary,
              ),
            ),
            const SizedBox(height: DFTokens.s12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _polishing
                        ? null
                        : () => _generatePrompts(currentVisible()),
                    icon: _polishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 17),
                    label: Text(l10n.cornerScapeGeneratePrompts),
                  ),
                ),
                const SizedBox(width: DFTokens.s8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _matchAudio(currentVisible()),
                    icon: const Icon(Icons.graphic_eq_rounded, size: 17),
                    label: Text(l10n.cornerScapeMatchAudio),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DFTokens.s8),
            FilledButton.icon(
              onPressed: () => _startBatch(currentVisible()),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(l10n.cornerScapeStartBatch),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardGrid(
    List<CornerScapeAsset> all,
    List<CornerScapeAsset> visible,
    Map<int, String?> audioByAsset,
  ) {
    final l10n = context.l10n;
    if (all.isEmpty) {
      return Center(child: DFEmpty(text: l10n.cornerScapeNoAssets));
    }
    if (visible.isEmpty) {
      return Center(child: DFEmpty(text: l10n.cornerScapeNoVisibleAssets));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(DFTokens.s16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 304,
        crossAxisSpacing: DFTokens.s16,
        mainAxisSpacing: DFTokens.s16,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final item = visible[index];
        return _assetCard(item, audioByAsset[item.asset.id]);
      },
    );
  }

  Widget _assetCard(CornerScapeAsset item, String? audioName) {
    final l10n = context.l10n;
    final df = context.df;
    final asset = item.asset;
    final selectedImage = _selectedImage(item);
    final generating = asset.imageState == stateGenerating;
    final done = asset.imageState == stateDone;
    final failed = asset.imageState == stateFailed;
    final selected = _selected.contains(asset.id);
    final filePath = asset.filePath;

    final status = generating
        ? DFStatusTag(
            kind: DFStatusKind.processing,
            text: l10n.cornerScapeGenerating,
          )
        : failed
            ? Tooltip(
                message: selectedImage?.errorReason ?? '',
                child: DFStatusTag(
                  kind: DFStatusKind.failed,
                  text: l10n.cornerScapeGenerationFailed,
                ),
              )
            : done
                ? DFStatusTag(
                    kind: DFStatusKind.success,
                    text: l10n.cornerScapeGenerationDone,
                  )
                : DFStatusTag(
                    kind: DFStatusKind.pending,
                    text: l10n.cornerScapeWaitingGeneration,
                  );

    return Material(
      color: df.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        side: BorderSide(color: selected ? df.primary : df.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('cornerscape-card-${asset.id}'),
        onTap: generating ? null : () => _openAssetDetail(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: df.surfaceMuted,
                    child: _cardPreview(
                      item,
                      status: status,
                      filePath: filePath,
                    ),
                  ),
                  if (done)
                    Positioned(
                      right: DFTokens.s8,
                      bottom: DFTokens.s8,
                      child: status,
                    ),
                  Positioned(
                    left: DFTokens.s8,
                    top: DFTokens.s8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: df.surface.withValues(alpha: .9),
                        borderRadius:
                            BorderRadius.circular(DFTokens.radiusControl),
                      ),
                      child: Checkbox(
                        key: Key('cornerscape-select-${asset.id}'),
                        value: selected,
                        visualDensity: VisualDensity.compact,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(asset.id);
                          } else {
                            _selected.remove(asset.id);
                          }
                        }),
                      ),
                    ),
                  ),
                  if (generating)
                    Positioned(
                      right: DFTokens.s8,
                      top: DFTokens.s8,
                      child: IconButton(
                        key: Key('cornerscape-cancel-${asset.id}'),
                        tooltip: l10n.cornerScapeCancelGeneration,
                        onPressed: () {},
                        style: IconButton.styleFrom(
                          backgroundColor: df.surface.withValues(alpha: .92),
                          foregroundColor: df.danger,
                        ),
                        icon: const Icon(Icons.stop_circle_outlined, size: 20),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DFTokens.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DFTokens.body14.copyWith(
                        color: df.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: DFTokens.s8),
                    Wrap(
                      spacing: DFTokens.s4,
                      runSpacing: DFTokens.s4,
                      children: [
                        Tooltip(
                          message: _typeLabel(asset.type),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: df.surfaceMuted,
                              borderRadius: BorderRadius.circular(
                                DFTokens.radiusControl,
                              ),
                              border: Border.all(color: df.stroke),
                            ),
                            child: Icon(
                              _typeIcon(asset.type),
                              size: 15,
                              color: df.textSecondary,
                            ),
                          ),
                        ),
                        DFTagChip(
                          label: (asset.prompt ?? '').trim().isEmpty
                              ? l10n.cornerScapePromptMissing
                              : l10n.cornerScapePromptReady,
                          tone: (asset.prompt ?? '').trim().isEmpty
                              ? DFTagTone.danger
                              : DFTagTone.success,
                        ),
                        if (audioName?.isNotEmpty == true)
                          DFTagChip(
                            label: audioName!,
                            tone: DFTagTone.primary,
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      asset.describe?.trim().isNotEmpty == true
                          ? asset.describe!
                          : asset.prompt ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DFTokens.caption12.copyWith(
                        color: df.textSecondary,
                      ),
                    ),
                    if (selectedImage?.model?.isNotEmpty == true ||
                        selectedImage?.resolution?.isNotEmpty == true) ...[
                      const SizedBox(height: DFTokens.s4),
                      Text(
                        [
                          if (selectedImage?.model?.isNotEmpty == true)
                            selectedImage!.model!,
                          if (selectedImage?.resolution?.isNotEmpty == true)
                            selectedImage!.resolution!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DFTokens.caption12.copyWith(
                          color: df.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardPreview(
    CornerScapeAsset item, {
    required Widget status,
    required String? filePath,
  }) {
    final df = context.df;
    if (item.asset.imageState == stateDone && filePath?.isNotEmpty == true) {
      return Image.file(
        File(ref.read(engineProvider).mediaAbsPath(filePath!)),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: df.textTertiary,
            size: 36,
          ),
        ),
      );
    }
    return Center(child: status);
  }

  AssetImageRow? _selectedImage(CornerScapeAsset item) {
    for (final image in item.images) {
      if (image.selected) return image;
    }
    return item.images.isEmpty ? null : item.images.last;
  }

  void _openAssetDetail(CornerScapeAsset item) {
    final l10n = context.l10n;
    final df = context.df;
    final asset = item.asset;
    final filePath = asset.filePath;
    final status = switch (asset.imageState) {
      stateDone => DFStatusTag(
          kind: DFStatusKind.success,
          text: l10n.cornerScapeGenerationDone,
        ),
      stateFailed => DFStatusTag(
          kind: DFStatusKind.failed,
          text: l10n.cornerScapeGenerationFailed,
        ),
      _ => DFStatusTag(
          kind: DFStatusKind.pending,
          text: l10n.cornerScapeWaitingGeneration,
        ),
    };

    showDFAdaptiveDialog<void>(
      context,
      title: asset.name ?? '',
      desktopWidthFactor: .42,
      builder: (dialogContext) => SizedBox(
        key: Key('cornerscape-detail-${asset.id}'),
        height: 520,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DFTokens.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                  child: ColoredBox(
                    color: df.surfaceMuted,
                    child: filePath?.isNotEmpty == true
                        ? InkWell(
                            key: Key(
                              'cornerscape-detail-preview-${asset.id}',
                            ),
                            onTap: () => showAssetImagePreview(
                              dialogContext,
                              absPath: ref
                                  .read(engineProvider)
                                  .mediaAbsPath(filePath),
                            ),
                            child: Image.file(
                              File(
                                ref
                                    .read(engineProvider)
                                    .mediaAbsPath(filePath!),
                              ),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image_outlined,
                                color: df.textTertiary,
                                size: 40,
                              ),
                            ),
                          )
                        : Center(child: status),
                  ),
                ),
              ),
              const SizedBox(height: DFTokens.s12),
              Row(
                children: [
                  Tooltip(
                    message: _typeLabel(asset.type),
                    child: Icon(
                      _typeIcon(asset.type),
                      size: 18,
                      color: df.textSecondary,
                    ),
                  ),
                  const SizedBox(width: DFTokens.s8),
                  status,
                ],
              ),
              if (asset.describe?.trim().isNotEmpty == true) ...[
                const SizedBox(height: DFTokens.s12),
                Text(
                  asset.describe!,
                  style: DFTokens.body14.copyWith(color: df.textSecondary),
                ),
              ],
              const SizedBox(height: DFTokens.s16),
              Text(
                l10n.assetsColPrompt,
                style: DFTokens.caption12.copyWith(
                  color: df.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: DFTokens.s4),
              SelectableText(
                (asset.prompt ?? '').trim().isEmpty
                    ? l10n.cornerScapePromptMissing
                    : asset.prompt!,
                style: DFTokens.body14.copyWith(color: df.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    final l10n = context.l10n;
    return switch (type) {
      'role' => l10n.cornerScapeFilterRole,
      'scene' => l10n.cornerScapeFilterScene,
      'tool' => l10n.cornerScapeFilterTool,
      _ => type,
    };
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'role' => Icons.person_outline_rounded,
      'scene' => Icons.landscape_outlined,
      'tool' => Icons.construction_outlined,
      _ => Icons.category_outlined,
    };
  }
}
