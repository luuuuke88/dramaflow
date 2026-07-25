import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

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
import '../../widgets/df_toast.dart';
import '../../widgets/local_media_preview.dart';
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
  final Map<int, Future<void>> _detailPolishOperations = {};
  final ValueNotifier<int> _detailPolishRevision = ValueNotifier(0);
  final TextEditingController _otherPrompt = TextEditingController();
  String? _selectedModel;
  String _resolution = '1K';
  bool _modelLoaded = false;
  bool _polishing = false;
  bool _probing = false;
  bool _nextStepBannerDismissed = false;

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
    _detailPolishRevision.dispose();
    _otherPrompt.dispose();
    super.dispose();
  }
  bool _isMobileSettingsExpanded = true;

  void _toast(String message) {
    showDFToast(context, message);
  }

  List<CornerScapeAsset> _visible(List<CornerScapeAsset> assets) {
    if (_types.isEmpty) return assets;
    return assets.where((item) => _types.contains(item.asset.type)).toList();
  }

  List<int> _selectedVisible(List<CornerScapeAsset> visible) {
    final visibleIds = visible.map((item) => item.asset.id).toSet();
    return _selected.where(visibleIds.contains).toList();
  }

  /// 当前该干的是第几步：蓝色主按钮跟着它走，永远等于「现在该点这个」。
  ///
  /// 判断对象是已勾选的资产；一个都没勾时看当前可见的全部，这样空手进来
  /// 也有正确的指引。缺提示词 → 1；提示词齐了但图没出全 → 2。
  ///
  /// 图出完之后返回 0（没有任何一步是蓝的）：第 3 步配音是**可选**的，
  /// 视频生产那边「有音频就用、没有就跳过」。把它标成蓝色主按钮等于催用户
  /// 去做一件本来可做可不做的事，出口改由「去视频生产」提示条给出。
  int _activeStep(List<CornerScapeAsset> visible) {
    final selectedIds = _selectedVisible(visible).toSet();
    final targets = selectedIds.isEmpty
        ? visible
        : visible.where((item) => selectedIds.contains(item.asset.id));
    if (targets.isEmpty) return 1;
    if (targets.any((item) => (item.asset.prompt ?? '').trim().isEmpty)) {
      return 1;
    }
    if (targets.any((item) => item.asset.imageState != stateDone)) return 2;
    return 0;
  }

  Future<bool> _isCurrentImageCandidate(String selectedModel) async {
    final engine = ref.read(engineProvider);
    final providers = await engine.listProviders();
    for (final provider in providers) {
      if (!provider.enabled) continue;
      final models = await engine.listProviderModels(provider.id);
      if (models.any(
        (model) =>
            model.enabled &&
            model.kind == 'image' &&
            '${provider.id}:${model.modelId}' == selectedModel,
      )) {
        return true;
      }
    }
    return false;
  }

  /// 出图前的连通预检：连得上返回 true 放行；连不上弹窗说明并返回 false。
  /// 只拦「地址根本连不上」，鉴权/额度之类仍旧交给真实任务去报。
  Future<bool> _ensureModelReachable(String selectedModel) async {
    final engine = ref.read(engineProvider);
    final parts = selectedModel.split(':');
    if (parts.length < 2) return true;
    final providerId = parts.first;
    final modelId = parts.sublist(1).join(':');
    setState(() => _probing = true);
    try {
      await engine.probeModelReachable(providerId, modelId);
      return true;
    } catch (_) {
      if (!mounted) return false;
      final goSettings = await showDFAdaptiveDialog<bool>(
        context,
        title: context.l10n.cornerScapeModelUnreachableTitle,
        desktopWidthFactor: .36,
        builder: (c) => _ModelUnreachableBody(
          message: c.l10n
              .cornerScapeModelUnreachableBody('$providerId · $modelId'),
        ),
      );
      if (goSettings == true && mounted) context.go('/settings');
      return false;
    } finally {
      if (mounted) setState(() => _probing = false);
    }
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
      engine.batchPolishAssetPrompts(
        widget.projectId,
        ids,
        otherTextPrompt: supplement,
      );
      setState(_selected.clear);
      if (mounted) _toast(l10n.assetsBatchPromptDone);
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
    ref.read(jobsGenerationProvider.notifier).bump();
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
    final model = _selectedModel;
    if (model == null) {
      _toast(l10n.assetsGenPickModel);
      return;
    }
    final currentModel = await _isCurrentImageCandidate(model);
    if (!mounted) return;
    if (!currentModel) {
      _toast(l10n.assetsGenPickModel);
      return;
    }
    // 先探一下模型连不连得上：连不上就当场说清楚，别糟蹋一整批任务。
    if (!await _ensureModelReachable(model)) return;
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

  Future<void> _cancelAssetGeneration(int assetId) async {
    final engine = ref.read(engineProvider);
    final taskId = engine.cornerScapeImageTaskId(assetId);
    if (taskId == null) return;
    if (!await confirmPolicyAction(
      context,
      engine.config,
      destructiveKey: 'cancel_generation',
      description: context.l10n.cornerScapeCancelGeneration,
    )) {
      return;
    }
    if (!mounted) return;
    final currentTaskId = engine.cornerScapeImageTaskId(assetId);
    if (currentTaskId != taskId) {
      ref.read(jobsGenerationProvider.notifier).bump();
      setState(() {});
      _toast(context.l10n.cornerScapeNoCancelableGeneration);
      return;
    }
    try {
      await engine.cancelJob(taskId);
    } catch (error) {
      if (mounted) _toast(localizeError(context, error));
    } finally {
      ref.read(jobsGenerationProvider.notifier).bump();
      if (mounted) setState(() {});
    }
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

  /// 步骤按钮：左边一个圆形序号，右边是按钮本体，撑满剩余宽度。
  ///
  /// [active] 为真时这一步是「现在该点的」——序号点亮成实心，按钮用蓝色实底；
  /// 其余步骤序号是淡底，按钮只描边。同一时刻页面上只有一处蓝色。
  Widget _stepButton({
    required int step,
    required bool active,
    required VoidCallback? onPressed,
    required Widget icon,
    required String label,
    bool optional = false,
  }) {
    final df = context.df;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? df.primary : df.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$step',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : df.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 44,
            child: active
                ? FilledButton.icon(
                    onPressed: onPressed,
                    icon: icon,
                    label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: icon,
                    // 可选步骤在名字后面挂一个「可选」小字，明说它可做可不做，
                    // 免得序号让人以为不做就走不下去。
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 14)),
                        if (optional) ...[
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.cornerScapeStepOptional,
                            style: TextStyle(
                              fontSize: 11,
                              color: df.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: df.stroke.withValues(alpha: 0.6)),
                      foregroundColor: df.textSecondary,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget? _nextStepBanner(List<CornerScapeAsset> assets,
      Map<int, String?> audioByAsset) {
    if (_nextStepBannerDismissed) return null;
    if (assets.isEmpty) return null;
    // 出口只看图出完没有。配音是可选项（视频生产那边「有音频才用，没有就跳过」），
    // 之前把它当成前置条件，跳过配音的人就永远等不到这条提示。
    final allImagesDone =
        assets.every((item) => item.asset.imageState == stateDone);
    if (!allImagesDone) return null;

    final l10n = context.l10n;
    final df = context.df;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: df.primarySubtle,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(Icons.auto_awesome_rounded, size: 20, color: df.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.cornerScapeNextStepBannerText,
            style: DFTokens.body14.copyWith(color: df.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () => context.go('/p/${widget.projectId}/production'),
          child: Text(l10n.cornerScapeNextStepBannerButton),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: () => setState(() => _nextStepBannerDismissed = true),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 订阅队列终态，确保页面独立挂载时也会刷新资产级匹配状态。
    ref.watch(activeJobsProvider);
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
    final banner = _nextStepBanner(assets, audioByAsset);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        if (compact) {
          return CustomScrollView(
            key: const Key('cornerscape-scroll'),
            slivers: [
              if (banner != null) SliverToBoxAdapter(child: banner),
              SliverToBoxAdapter(
                child: _settingsPanel(
                  assets,
                  visible,
                  compact: true,
                ),
              ),
              _compactCardSliver(assets, visible, audioByAsset),
            ],
          );
        }
        final settingsPanel = _settingsPanel(assets, visible);
        final cardGrid = _cardGrid(assets, visible, audioByAsset);
        return Column(
          children: [
            if (banner != null) banner,
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 328, child: settingsPanel),
                  Expanded(child: cardGrid),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _settingsPanel(
    List<CornerScapeAsset> assets,
    List<CornerScapeAsset> visible, {
    bool compact = false,
  }) {
    final l10n = context.l10n;
    final df = context.df;
    final selectedCount = _selectedVisible(visible).length;
    final activeStep = _activeStep(visible);
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
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: df.surfaceMuted.withValues(alpha: 0.5),
            foregroundColor: df.textPrimary,
            elevation: 0,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        );

    final content = Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: compact
                ? () {
                    setState(() {
                      _isMobileSettingsExpanded = !_isMobileSettingsExpanded;
                    });
                  }
                : null,
            child: Row(
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
                if (compact) ...[
                  const SizedBox(width: 12),
                  Icon(
                    _isMobileSettingsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: df.textSecondary,
                  ),
                ],
              ],
            ),
          ),
          AnimatedCrossFade(
            crossFadeState: compact && !_isMobileSettingsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: DFTokens.fast120,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: compact ? DFTokens.s16 : DFTokens.s24),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide.none,
                      backgroundColor: df.surfaceMuted.withValues(alpha: 0.5),
                      selectedColor: df.primary.withValues(alpha: 0.12),
                      checkmarkColor: df.primary,
                      labelStyle: TextStyle(
                        color: _types.contains('role') ? df.primary : df.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    FilterChip(
                      label: Text(l10n.cornerScapeFilterScene),
                      selected: _types.contains('scene'),
                      onSelected: (_) => _toggleType('scene', assets),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide.none,
                      backgroundColor: df.surfaceMuted.withValues(alpha: 0.5),
                      selectedColor: df.primary.withValues(alpha: 0.12),
                      checkmarkColor: df.primary,
                      labelStyle: TextStyle(
                        color: _types.contains('scene') ? df.primary : df.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    FilterChip(
                      label: Text(l10n.cornerScapeFilterTool),
                      selected: _types.contains('tool'),
                      onSelected: (_) => _toggleType('tool', assets),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide.none,
                      backgroundColor: df.surfaceMuted.withValues(alpha: 0.5),
                      selectedColor: df.primary.withValues(alpha: 0.12),
                      checkmarkColor: df.primary,
                      labelStyle: TextStyle(
                        color: _types.contains('tool') ? df.primary : df.textPrimary,
                        fontSize: 12,
                      ),
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
                // 三步按真实干活顺序竖排：先出提示词，再出图，最后配音频。
                // 蓝色主按钮跟着 _activeStep 走，永远落在「现在该点的那一步」上。
                _stepButton(
                  step: 1,
                  active: activeStep == 1,
                  onPressed:
                      _polishing ? null : () => _generatePrompts(currentVisible()),
                  icon: _polishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded, size: 17),
                  label: l10n.cornerScapeGeneratePrompts,
                ),
                const SizedBox(height: DFTokens.s8),
                _stepButton(
                  step: 2,
                  active: activeStep == 2,
                  onPressed: _probing ? null : () => _startBatch(currentVisible()),
                  icon: _probing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_outlined, size: 18),
                  label: l10n.cornerScapeStartBatch,
                ),
                const SizedBox(height: DFTokens.s8),
                _stepButton(
                  step: 3,
                  active: false,
                  optional: true,
                  onPressed: () => _matchAudio(currentVisible()),
                  icon: const Icon(Icons.graphic_eq_rounded, size: 17),
                  label: l10n.cornerScapeMatchAudio,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (compact) {
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: df.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: content,
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(child: content),
      ),
    );
  }

  Widget _compactCardSliver(
    List<CornerScapeAsset> all,
    List<CornerScapeAsset> visible,
    Map<int, String?> audioByAsset,
  ) {
    final l10n = context.l10n;
    if (all.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: Center(child: DFEmpty(text: l10n.cornerScapeNoAssets)),
        ),
      );
    }
    if (visible.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: Center(
            child: DFEmpty(text: l10n.cornerScapeNoVisibleAssets),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(DFTokens.s16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 1,
          mainAxisExtent: 304,
          mainAxisSpacing: DFTokens.s16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = visible[index];
            return _assetCard(item, audioByAsset[item.asset.id], visible);
          },
          childCount: visible.length,
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
        return _assetCard(item, audioByAsset[item.asset.id], visible);
      },
    );
  }

  Widget _assetCard(CornerScapeAsset item, String? audioName, List<CornerScapeAsset> visible) {
    final l10n = context.l10n;
    final df = context.df;
    final asset = item.asset;
    final selectedImage = _selectedImage(item);
    final generating = asset.imageState == stateGenerating;
    final done = asset.imageState == stateDone;
    final failed = asset.imageState == stateFailed;
    final audioMatching = asset.audioBindState == stateGenerating;
    final audioMatchFailed = asset.audioBindState == stateFailed;
    final selected = _selected.contains(asset.id);
    final filePath = asset.filePath;
    final activeTaskId =
        ref.read(engineProvider).cornerScapeImageTaskId(asset.id);

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
                  GestureDetector(
                    onTap: () {
                      if (!done || filePath == null || filePath.isEmpty) return;
                      final validAssets = visible
                          .where((a) =>
                              a.asset.imageState == stateDone &&
                              _selectedImage(a)?.filePath?.isNotEmpty == true)
                          .toList();
                      if (validAssets.isEmpty) return;
                      
                      final paths = validAssets
                          .map((a) => ref.read(engineProvider).mediaAbsPath(_selectedImage(a)!.filePath!))
                          .toList();
                      
                      final clickedPath = ref.read(engineProvider).mediaAbsPath(filePath);
                      final initialIndex = paths.indexOf(clickedPath).clamp(0, paths.length - 1);
                      
                      showAssetGalleryPreview(
                        context,
                        paths: paths,
                        initialIndex: initialIndex,
                      );
                    },
                    child: ColoredBox(
                      color: df.surfaceMuted,
                      child: _cardPreview(
                        item,
                        status: audioMatching
                            ? DFStatusTag(
                                kind: DFStatusKind.processing,
                                text: l10n.cornerScapeAudioMatching,
                              )
                            : status,
                        filePath: filePath,
                        forceStatus: audioMatching,
                      ),
                    ),
                  ),
                  if (done) ...[
                    Positioned(
                      right: DFTokens.s8,
                      bottom: DFTokens.s8,
                      child: status,
                    ),
                    Positioned(
                      right: DFTokens.s8,
                      top: DFTokens.s8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
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
                  if (activeTaskId != null)
                    Positioned(
                      right: DFTokens.s8,
                      top: DFTokens.s8,
                      child: IconButton(
                        key: Key('cornerscape-cancel-${asset.id}'),
                        tooltip: l10n.cornerScapeCancelGeneration,
                        onPressed: () => _cancelAssetGeneration(asset.id),
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
                        if (audioMatchFailed)
                          KeyedSubtree(
                            key: Key('cornerscape-audio-state-${asset.id}'),
                            child: DFTagChip(
                              label: l10n.cornerScapeAudioMatchFailed,
                              tone: DFTagTone.danger,
                            ),
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
    required bool forceStatus,
  }) {
    final df = context.df;
    if (!forceStatus &&
        item.asset.imageState == stateDone &&
        filePath?.isNotEmpty == true) {
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

  bool _isDetailPolishing(int assetId) =>
      _detailPolishOperations.containsKey(assetId);

  Future<void> _polishDetailAsset(int assetId) {
    final existing = _detailPolishOperations[assetId];
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = ref
        .read(engineProvider)
        .polishAssetPrompt(assetId)
        .then<void>((_) {})
        .whenComplete(() {
      if (identical(_detailPolishOperations[assetId], operation)) {
        _detailPolishOperations.remove(assetId);
      }
      if (mounted) {
        _detailPolishRevision.value++;
        setState(() {});
      }
    });
    _detailPolishOperations[assetId] = operation;
    _detailPolishRevision.value++;
    return operation;
  }

  void _openAssetDetail(CornerScapeAsset item) {
    final asset = item.asset;
    final selectedImage = _selectedImage(item);
    showDFAdaptiveDialog<void>(
      context,
      title: '${asset.name ?? ''} · ${_typeLabel(asset.type)}',
      desktopWidthFactor: .5,
      builder: (dialogContext) => _AssetDetailBody(
        key: Key('cornerscape-detail-${asset.id}'),
        projectId: widget.projectId,
        asset: asset,
        images: item.images,
        initialModel: _selectedModel,
        initialResolution: selectedImage?.resolution?.isNotEmpty == true
            ? selectedImage!.resolution!
            : _resolution,
        validateModel: _isCurrentImageCandidate,
        polishRevision: _detailPolishRevision,
        isPolishing: _isDetailPolishing,
        polishPrompt: _polishDetailAsset,
        onChanged: () {
          if (mounted) setState(() {});
        },
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

class _AssetDetailBody extends ConsumerStatefulWidget {
  final int projectId;
  final AssetRow asset;
  final List<AssetImageRow> images;
  final String? initialModel;
  final String initialResolution;
  final Future<bool> Function(String model) validateModel;
  final ValueListenable<int> polishRevision;
  final bool Function(int assetId) isPolishing;
  final Future<void> Function(int assetId) polishPrompt;
  final VoidCallback onChanged;

  const _AssetDetailBody({
    super.key,
    required this.projectId,
    required this.asset,
    required this.images,
    required this.initialModel,
    required this.initialResolution,
    required this.validateModel,
    required this.polishRevision,
    required this.isPolishing,
    required this.polishPrompt,
    required this.onChanged,
  });

  @override
  ConsumerState<_AssetDetailBody> createState() => _AssetDetailBodyState();
}

class _AssetDetailBodyState extends ConsumerState<_AssetDetailBody> {
  late final TextEditingController _prompt =
      TextEditingController(text: widget.asset.prompt ?? '');
  late final FocusNode _promptFocus = FocusNode()
    ..addListener(_savePromptOnBlur);
  late int? _selectedImageId = widget.asset.imageId;
  late String? _model = widget.initialModel;
  late String _resolution = widget.initialResolution;
  late bool _polishing = widget.isPolishing(widget.asset.id);
  int? _audioAssetId;
  bool _promptDirty = false;

  @override
  void initState() {
    super.initState();
    widget.polishRevision.addListener(_handlePolishStateChanged);
    final bindings =
        ref.read(engineProvider).assetAudioBindings(widget.projectId);
    for (final binding in bindings) {
      if (binding.assetId == widget.asset.id) {
        _audioAssetId = binding.audioAssetId;
        break;
      }
    }
  }

  @override
  void dispose() {
    widget.polishRevision.removeListener(_handlePolishStateChanged);
    if (_promptDirty && !widget.isPolishing(widget.asset.id)) {
      ref.read(engineProvider).updateAsset(
            widget.asset.id,
            prompt: _prompt.text,
          );
    }
    _promptFocus
      ..removeListener(_savePromptOnBlur)
      ..dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _handlePolishStateChanged() {
    final polishing = widget.isPolishing(widget.asset.id);
    if (polishing == _polishing || !mounted) return;
    setState(() {
      _polishing = polishing;
      _promptDirty = false;
      if (!polishing) {
        final assets = ref.read(engineProvider).assetsByIds([widget.asset.id]);
        if (assets.isNotEmpty) {
          _prompt.text = assets.single.prompt ?? '';
        }
      }
    });
  }

  void _toast(String message) {
    showDFToast(context, message);
  }

  void _savePromptOnBlur() {
    if (_promptFocus.hasFocus || !_promptDirty || _polishing) return;
    ref.read(engineProvider).updateAsset(
          widget.asset.id,
          prompt: _prompt.text,
        );
    _promptDirty = false;
    widget.onChanged();
  }

  AssetImageRow? get _selectedImage {
    for (final image in widget.images) {
      if (image.id == _selectedImageId) return image;
    }
    return null;
  }

  Future<void> _selectHistory(AssetImageRow image) async {
    if (image.state != stateDone) return;
    ref.read(engineProvider).saveAssetImage(
          assetsId: widget.asset.id,
          projectId: widget.projectId,
          imageId: image.id,
          prompt: _prompt.text,
          type: widget.asset.type,
        );
    if (!mounted) return;
    setState(() {
      _selectedImageId = image.id;
      if (image.resolution?.isNotEmpty == true) {
        _resolution = image.resolution!;
      }
    });
    widget.onChanged();
  }

  Future<void> _polishPrompt() async {
    if (_polishing) return;
    if (_prompt.text.trim().isEmpty) {
      _toast(context.l10n.assetsGenFillPrompt);
      return;
    }
    final engine = ref.read(engineProvider);
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'asset_prompt_polish',
      description: context.l10n.assetsGenSmartGenerate,
    )) {
      return;
    }
    if (!mounted || _polishing) return;
    if (_prompt.text.trim().isEmpty) {
      _toast(context.l10n.assetsGenFillPrompt);
      return;
    }
    final assetId = widget.asset.id;
    try {
      await widget.polishPrompt(assetId);
    } catch (error) {
      if (mounted) _toast(localizeError(context, error));
    }
  }

  Future<void> _regenerate() async {
    if (_polishing) return;
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
      description: l10n.directorPlanRegenerate,
    )) {
      return;
    }
    if (!mounted || _polishing) return;
    final selectedModel = _model;
    if (selectedModel == null) {
      _toast(l10n.assetsGenPickModel);
      return;
    }
    if (!await widget.validateModel(selectedModel)) {
      if (mounted) _toast(l10n.assetsGenPickModel);
      return;
    }
    if (!mounted || _polishing) return;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      _toast(l10n.assetsGenFillPrompt);
      return;
    }
    engine.updateAsset(widget.asset.id, prompt: prompt);
    engine.generateAssetImages(
      widget.projectId,
      [(assetsId: widget.asset.id, refImageBase64: null)],
      model: selectedModel,
      resolution: _resolution,
    );
    ref.read(jobsGenerationProvider.notifier).bump();
    widget.onChanged();
    if (mounted) Navigator.of(context).pop();
  }

  void _bindAudio(int? audioAssetId) {
    try {
      ref.read(engineProvider).bindAssetAudio(
            widget.asset.id,
            audioAssetId,
          );
      setState(() => _audioAssetId = audioAssetId);
      widget.onChanged();
    } catch (error) {
      _toast(localizeError(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final selectedImage = _selectedImage;
    final selectedAbsPath = selectedImage?.filePath?.isNotEmpty == true
        ? ref.read(engineProvider).mediaAbsPath(selectedImage!.filePath!)
        : null;
    final audioPool = ref.read(engineProvider).audioPool(widget.projectId);
    final bodyHeight =
        (MediaQuery.sizeOf(context).height * .72).clamp(480.0, 680.0);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: DFTokens.s4),
          child: Text(
            text,
            style: DFTokens.caption12.copyWith(
              color: df.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    return SizedBox(
      height: bodyHeight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DFTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                child: ColoredBox(
                  color: df.surfaceMuted,
                  child: selectedAbsPath == null
                      ? Center(
                          child: DFStatusTag(
                            kind: selectedImage?.state == stateFailed
                                ? DFStatusKind.failed
                                : DFStatusKind.pending,
                            text: selectedImage?.state == stateFailed
                                ? l10n.cornerScapeGenerationFailed
                                : l10n.cornerScapeWaitingGeneration,
                          ),
                        )
                      : InkWell(
                          key: Key(
                            'cornerscape-detail-current-image-'
                            '${selectedImage!.id}',
                          ),
                          onTap: () => showAssetImagePreview(
                            context,
                            absPath: selectedAbsPath,
                          ),
                          child: Image.file(
                            File(selectedAbsPath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.broken_image_outlined,
                              color: df.textTertiary,
                              size: 40,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            if (widget.asset.describe?.trim().isNotEmpty == true) ...[
              const SizedBox(height: DFTokens.s12),
              Text(
                widget.asset.describe!,
                style: DFTokens.body14.copyWith(color: df.textSecondary),
              ),
            ],
            const SizedBox(height: DFTokens.s16),
            label(l10n.taskHistoryTitle),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: DFTokens.s8),
                itemBuilder: (context, index) {
                  final image = widget.images[index];
                  final selected = image.id == _selectedImageId;
                  final absPath = image.filePath?.isNotEmpty == true
                      ? ref.read(engineProvider).mediaAbsPath(image.filePath!)
                      : null;
                  return InkWell(
                    key: Key('cornerscape-history-image-${image.id}'),
                    onTap: image.state == stateDone
                        ? () => _selectHistory(image)
                        : null,
                    child: Container(
                      width: 100,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: df.surfaceMuted,
                        borderRadius:
                            BorderRadius.circular(DFTokens.radiusControl),
                        border: Border.all(
                          color: selected ? df.primary : df.stroke,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: absPath == null
                          ? Icon(
                              Icons.image_not_supported_outlined,
                              color: df.textTertiary,
                            )
                          : Image.file(
                              File(absPath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image_outlined,
                                color: df.textTertiary,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: DFTokens.s16),
            label(l10n.assetsColPrompt),
            TextField(
              key: Key('cornerscape-prompt-${widget.asset.id}'),
              controller: _prompt,
              focusNode: _promptFocus,
              enabled: !_polishing,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => _promptDirty = true,
              decoration: InputDecoration(
                hintText: l10n.assetsAddPromptPh,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: DFTokens.s16),
            label(l10n.cornerScapeImageModel),
            KeyedSubtree(
              key: Key('cornerscape-model-${widget.asset.id}'),
              child: ModelSelect(
                kind: 'image',
                value: _model,
                hint: l10n.assetsGenPickModel,
                onChanged: (option) => setState(() => _model = option?.value),
              ),
            ),
            const SizedBox(height: DFTokens.s16),
            label(l10n.cornerScapeResolution),
            KeyedSubtree(
              key: Key('cornerscape-resolution-${widget.asset.id}'),
              child: SegmentedButton<String>(
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
            ),
            const SizedBox(height: DFTokens.s16),
            label(l10n.workbenchCompositionAudio),
            Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: Key('cornerscape-audio-${widget.asset.id}'),
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey(
                        'cornerscape-audio-value-${widget.asset.id}-'
                        '$_audioAssetId',
                      ),
                      initialValue: _audioAssetId,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(l10n.cornerScapeUnbind),
                        ),
                        for (final audio in audioPool)
                          DropdownMenuItem<int?>(
                            value: audio.id,
                            child: Text(
                              audio.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _bindAudio,
                    ),
                  ),
                ),
                const SizedBox(width: DFTokens.s8),
                _AuditionButton(
                  key: Key('cornerscape-audition-${widget.asset.id}'),
                  audioAssetId: _audioAssetId,
                  audioPath: _audioAssetId == null
                      ? null
                      : ref
                          .read(engineProvider)
                          .audioAssetAbsPath(_audioAssetId!),
                ),
              ],
            ),
            const SizedBox(height: DFTokens.s20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('cornerscape-polish-${widget.asset.id}'),
                    onPressed: _polishing ? null : _polishPrompt,
                    icon: _polishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: Text(l10n.assetsGenSmartGenerate),
                  ),
                ),
                const SizedBox(width: DFTokens.s8),
                Expanded(
                  child: FilledButton.icon(
                    key: Key('cornerscape-regenerate-${widget.asset.id}'),
                    onPressed: _polishing ? null : _regenerate,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.directorPlanRegenerate),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditionButton extends ConsumerStatefulWidget {
  final int? audioAssetId;
  final String? audioPath;

  const _AuditionButton({
    super.key,
    required this.audioAssetId,
    required this.audioPath,
  });

  @override
  ConsumerState<_AuditionButton> createState() => _AuditionButtonState();
}

class _AuditionButtonState extends ConsumerState<_AuditionButton> {
  Player? _player;
  StreamSubscription<bool>? _completedSubscription;
  int _playbackGeneration = 0;
  int? _openingGeneration;
  bool _stopping = false;
  bool _playing = false;

  bool get _opening => _openingGeneration != null;

  @override
  void didUpdateWidget(covariant _AuditionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioAssetId != widget.audioAssetId ||
        oldWidget.audioPath != widget.audioPath) {
      unawaited(_stopAndReset());
    }
  }

  @override
  void dispose() {
    _playbackGeneration++;
    final subscription = _completedSubscription;
    _completedSubscription = null;
    final player = _player;
    _player = null;
    unawaited(subscription?.cancel() ?? Future.value());
    if (player != null) unawaited(_disposePlayer(player));
    super.dispose();
  }

  Future<void> _disposePlayer(Player player) async {
    try {
      await player.stop();
    } catch (_) {
      // The player may already be stopping after a binding change.
    }
    try {
      await player.dispose();
    } catch (_) {
      // Disposal is best-effort while the detail route is closing.
    }
  }

  void _toast(String message) {
    showDFToast(context, message);
  }

  Future<void> _stopAndReset() async {
    final generation = ++_playbackGeneration;
    final subscription = _completedSubscription;
    _completedSubscription = null;
    final player = _player;
    if (subscription == null && player == null && !_opening && !_playing) {
      return;
    }
    if (mounted) {
      setState(() {
        _stopping = true;
        _playing = false;
      });
    } else {
      _stopping = true;
      _playing = false;
    }
    try {
      await subscription?.cancel();
      await player?.stop();
    } catch (_) {
      // Playback can already be stopped or disposed while the detail closes.
    } finally {
      if (generation == _playbackGeneration) {
        _stopping = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _toggle() async {
    final l10n = context.l10n;
    if (_opening || _stopping) return;
    if (_playing) {
      await _stopAndReset();
      return;
    }
    final audioAssetId = widget.audioAssetId;
    final absPath = widget.audioPath;
    if (absPath == null || !File(absPath).existsSync()) {
      _toast(l10n.cornerScapeAudioMissing);
      return;
    }
    final generation = ++_playbackGeneration;
    setState(() => _openingGeneration = generation);
    try {
      ensureLocalMediaKit();
      final player = _player ??= Player();
      final previousSubscription = _completedSubscription;
      _completedSubscription = null;
      await previousSubscription?.cancel();
      if (!mounted || generation != _playbackGeneration) return;
      _completedSubscription = player.stream.completed.listen((completed) {
        if (completed &&
            mounted &&
            generation == _playbackGeneration &&
            identical(_player, player) &&
            widget.audioAssetId == audioAssetId &&
            widget.audioPath == absPath) {
          setState(() => _playing = false);
        }
      });
      await player.open(Media(absPath));
      if (!mounted) return;
      if (generation != _playbackGeneration ||
          widget.audioAssetId != audioAssetId ||
          widget.audioPath != absPath) {
        try {
          await player.stop();
        } catch (_) {
          // A newer stop or disposal already invalidated this open.
        }
        return;
      }
      setState(() => _playing = !player.state.completed);
    } catch (_) {
      if (!mounted || generation != _playbackGeneration) return;
      setState(() => _playing = false);
      _toast(l10n.cornerScapeAuditionFailed);
    } finally {
      if (_openingGeneration == generation) {
        _openingGeneration = null;
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _opening || _stopping;
    final enabled = widget.audioAssetId != null && !busy;
    return IconButton(
      tooltip:
          _playing ? l10n.cornerScapeStopAudition : l10n.cornerScapeAudition,
      onPressed: enabled ? _toggle : null,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            ),
    );
  }
}

/// 「模型连不上」弹窗正文：说明原因，并给出「去设置」的去处。
class _ModelUnreachableBody extends StatelessWidget {
  final String message;
  const _ModelUnreachableBody({required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wifi_off_rounded, size: 20, color: df.danger),
              const SizedBox(width: DFTokens.s8),
              Expanded(
                child: Text(
                  message,
                  style: DFTokens.body14.copyWith(color: df.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonGotIt),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.modelSelectGoSettings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
