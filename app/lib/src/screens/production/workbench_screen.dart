// 工作台（照抄 production/components/workbench 语义，见 P4 参照 §3）：
// 顺序镜头列表（顺序由分镜 index 决定，支持拖拽重排并回写 index）+
// 每镜视频候选网格（生成/挑选/删除，同 P2/P3 多版本模式）+ 顶部"合成本集"。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../engine/assets.dart';
import '../../engine/audio_bind.dart';
import '../../engine/compose_episode.dart';
import '../../engine/engine.dart';
import '../../engine/storyboard.dart';
import '../../engine/storyboard_audio.dart';
import '../../engine/timeline_clip.dart';
import '../../engine/video_track.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_empty.dart';
import '../../widgets/policy_confirm.dart';
import '../../widgets/common.dart';

/// media_kit 一次性初始化。放懒调用（工作台/配音页首次进入时），避免侵入未持有的
/// main.dart；MediaKit.ensureInitialized 幂等，可多次调用。
bool _mediaKitReady = false;
void ensureMediaKit() {
  if (_mediaKitReady) return;
  MediaKit.ensureInitialized();
  _mediaKitReady = true;
}

void _showWorkbenchSnackBar(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// 播放候选视频（tap-to-play 弹窗，media_kit）。相对路径经 engine.mediaAbsPath 解析。
Future<void> showVideoPlayerDialog(
  BuildContext context, {
  required String absPath,
}) {
  final mobile = MediaQuery.sizeOf(context).width < 840;
  if (mobile) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (c) {
          final l10n = c.l10n;
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(l10n.workbenchPlayVideo),
            ),
            body: SafeArea(
              child: _VideoPlayerSurface(
                absPath: absPath,
                expand: true,
              ),
            ),
          );
        },
      ),
    );
  }

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (c) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(DFTokens.s24),
      child: _VideoPlayerSurface(
        absPath: absPath,
        showCloseButton: true,
      ),
    ),
  );
}

class _VideoPlayerSurface extends StatefulWidget {
  final String absPath;
  final bool expand;
  final bool showCloseButton;

  const _VideoPlayerSurface({
    required this.absPath,
    this.expand = false,
    this.showCloseButton = false,
  });

  @override
  State<_VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<_VideoPlayerSurface> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<String>? _errorSub;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    try {
      if (!File(widget.absPath).existsSync()) {
        _errored = true;
        return;
      }
      ensureMediaKit();
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      _errorSub = player.stream.error.listen((_) {
        if (mounted) setState(() => _errored = true);
      });
      player.open(Media(widget.absPath));
    } catch (_) {
      _errored = true;
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = _controller;
    final player = AspectRatio(
      aspectRatio: 16 / 9,
      child: _errored || controller == null
          ? Center(
              child: Text(l10n.workbenchVideoLoadFailed,
                  style: const TextStyle(color: Colors.white70)))
          : Video(controller: controller),
    );
    return Stack(
      key: const ValueKey('workbench-video-player-screen'),
      children: [
        widget.expand ? Center(child: player) : player,
        if (widget.showCloseButton)
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: l10n.commonConfirm,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
      ],
    );
  }
}

Future<void> showWorkbench(BuildContext context, WidgetRef ref,
    {required int projectId, required int scriptId}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => _WorkbenchPage(projectId: projectId, scriptId: scriptId),
    ),
  );
}

class _WorkbenchPage extends ConsumerStatefulWidget {
  final int projectId;
  final int scriptId;
  const _WorkbenchPage({required this.projectId, required this.scriptId});

  @override
  ConsumerState<_WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<_WorkbenchPage> {
  bool _composing = false;
  bool _batchPrompting = false;
  final Set<int> _checkedShotIds = {};
  final Set<int> _knownShotIds = {};

  Future<void> _compose() async {
    final l10n = context.l10n;
    setState(() => _composing = true);
    try {
      final result = await ref
          .read(engineProvider)
          .composeEpisode(widget.projectId, widget.scriptId);
      if (!mounted) return;
      showDFAdaptiveDialog<void>(
        context,
        title: l10n.workbenchComposeSuccess,
        desktopWidthFactor: .42,
        builder: (c) => _ComposeResultBody(result: result),
      );
    } catch (e) {
      if (mounted) _showWorkbenchSnackBar(context, localizeError(context, e));
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  void _syncCheckedShots(List<StoryboardRow> shots) {
    final currentIds = {for (final shot in shots) shot.id};
    _checkedShotIds.removeWhere((id) => !currentIds.contains(id));
    _knownShotIds.removeWhere((id) => !currentIds.contains(id));
    for (final id in currentIds) {
      if (_knownShotIds.add(id)) {
        _checkedShotIds.add(id);
      }
    }
  }

  void _toggleShotSelection(int shotId, bool selected) {
    setState(() {
      if (selected) {
        _checkedShotIds.add(shotId);
      } else {
        _checkedShotIds.remove(shotId);
      }
    });
  }

  Future<void> _generateChecked(List<StoryboardRow> shots) async {
    final selected = [
      for (final shot in shots)
        if (_checkedShotIds.contains(shot.id)) shot,
    ];
    if (selected.isEmpty) return;
    final engine = ref.read(engineProvider);
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'video_generation',
      description: context.l10n.workbenchGenerateAll,
      units: selected.length,
    )) {
      return;
    }
    if (!mounted) return;
    try {
      engine.batchGenerateVideos(
          widget.projectId, selected.map((s) => s.id).toList());
      _showWorkbenchSnackBar(context, context.l10n.workbenchGenerateVideo);
    } catch (error) {
      _showWorkbenchSnackBar(context, localizeError(context, error));
    }
  }

  Future<void> _generateCheckedPrompts(List<StoryboardRow> shots) async {
    final selected = [
      for (final shot in shots)
        if (_checkedShotIds.contains(shot.id)) shot,
    ];
    if (selected.isEmpty || _batchPrompting) return;
    setState(() => _batchPrompting = true);
    try {
      final engine = ref.read(engineProvider);
      for (final shot in selected) {
        await engine.generateVideoPrompt(shot.id);
      }
      if (mounted) {
        setState(() {});
        _showWorkbenchSnackBar(context, context.l10n.workbenchGeneratePrompt);
      }
    } catch (e) {
      if (mounted) _showWorkbenchSnackBar(context, localizeError(context, e));
    } finally {
      if (mounted) setState(() => _batchPrompting = false);
    }
  }

  Future<void> _clearCheckedTracks(List<StoryboardRow> shots) async {
    final selected = [
      for (final shot in shots)
        if (_checkedShotIds.contains(shot.id) && shot.trackId != null) shot,
    ];
    if (selected.isEmpty) return;
    final l10n = context.l10n;
    final ok = await showDFAdaptiveDialog<bool>(
      context,
      title: l10n.workbenchClearSelectedTracks,
      desktopWidthFactor: .36,
      builder: (c) => _ConfirmActionBody(
        message: l10n.workbenchClearSelectedTracksConfirm,
        confirmLabel: l10n.workbenchClearTracksAction,
        onCancel: () => Navigator.pop(c, false),
        onConfirm: () => Navigator.pop(c, true),
      ),
    );
    if (ok != true || !mounted) return;
    final engine = ref.read(engineProvider);
    for (final shot in selected) {
      final trackId = shot.trackId;
      if (trackId != null) engine.deleteVideoTrack(trackId);
    }
    setState(() {});
    _showWorkbenchSnackBar(context, l10n.workbenchClearSelectedTracksDone);
  }

  void _reorderShots(List<StoryboardRow> shots, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final targetIndex = newIndex.clamp(0, shots.length - 1);
    final ids = [for (final shot in shots) shot.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(targetIndex, moved);
    ref.read(engineProvider).reorderStoryboards(widget.scriptId, ids);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compactActions = MediaQuery.sizeOf(context).width < 620;
    ref.watch(jobsGenerationProvider);
    final shots = ref.watch(engineProvider).storyboards(widget.scriptId);
    _syncCheckedShots(shots);
    final missing = ref
        .watch(engineProvider)
        .orderedSelectedVideoPaths(widget.scriptId)
        .where((p) => p == null || p.isEmpty)
        .length;
    final toolbarTextButtonStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    );
    final toolbarFilledButtonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workbenchTitle),
        actions: [
          if (shots.isNotEmpty && compactActions)
            PopupMenuButton<_WorkbenchBatchAction>(
              enabled: _checkedShotIds.isNotEmpty && !_batchPrompting,
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) {
                switch (action) {
                  case _WorkbenchBatchAction.prompts:
                    _generateCheckedPrompts(shots);
                    break;
                  case _WorkbenchBatchAction.videos:
                    _generateChecked(shots);
                    break;
                  case _WorkbenchBatchAction.clearTracks:
                    _clearCheckedTracks(shots);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _WorkbenchBatchAction.prompts,
                  child: Text(l10n.workbenchGenerateAllPrompts),
                ),
                PopupMenuItem(
                  value: _WorkbenchBatchAction.videos,
                  child: Text(l10n.workbenchGenerateAll),
                ),
                PopupMenuItem(
                  value: _WorkbenchBatchAction.clearTracks,
                  child: Text(l10n.workbenchClearSelectedTracks),
                ),
              ],
            ),
          if (shots.isNotEmpty && !compactActions)
            TextButton.icon(
              style: toolbarTextButtonStyle,
              onPressed: _checkedShotIds.isEmpty || _batchPrompting
                  ? null
                  : () => _generateCheckedPrompts(shots),
              icon: _batchPrompting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.workbenchGenerateAllPrompts),
            ),
          if (shots.isNotEmpty && !compactActions)
            TextButton.icon(
              style: toolbarTextButtonStyle,
              onPressed: _checkedShotIds.isEmpty
                  ? null
                  : () => _generateChecked(shots),
              icon: const Icon(Icons.movie_creation_outlined),
              label: Text(l10n.workbenchGenerateAll),
            ),
          if (shots.isNotEmpty && !compactActions)
            TextButton.icon(
              style: toolbarTextButtonStyle,
              onPressed: _checkedShotIds.isEmpty
                  ? null
                  : () => _clearCheckedTracks(shots),
              icon: const Icon(Icons.layers_clear_outlined),
              label: Text(l10n.workbenchClearSelectedTracks),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: toolbarFilledButtonStyle,
              onPressed: _composing || shots.isEmpty ? null : _compose,
              icon: _composing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.movie_filter_outlined, size: 18),
              label: Text(_composing
                  ? l10n.workbenchComposing
                  : missing > 0
                      ? '${l10n.workbenchCompose} (${l10n.workbenchComposeMissing(('$missing'))})'
                      : l10n.workbenchCompose),
            ),
          ),
        ],
      ),
      body: shots.isEmpty
          ? Center(child: DFEmpty(text: l10n.workbenchNoShots))
          : Column(
              children: [
                _TimelineOverview(projectId: widget.projectId, shots: shots),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) =>
                        _reorderShots(shots, oldIndex, newIndex),
                    itemCount: shots.length,
                    itemBuilder: (c, i) {
                      final shot = shots[i];
                      return Padding(
                        key: ValueKey('workbench-shot-item-${shot.id}'),
                        padding: EdgeInsets.only(
                            bottom: i == shots.length - 1 ? 0 : 12),
                        child: _ShotRow(
                          projectId: widget.projectId,
                          shot: shot,
                          index: i,
                          selected: _checkedShotIds.contains(shot.id),
                          onSelected: (value) =>
                              _toggleShotSelection(shot.id, value),
                          dragHandle: ReorderableDragStartListener(
                            key:
                                ValueKey('workbench-reorder-handle-${shot.id}'),
                            index: i,
                            child: Tooltip(
                              message: l10n.workbenchReorderShot,
                              child: Icon(Icons.drag_indicator_rounded,
                                  color: context.df.textTertiary),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

enum _WorkbenchBatchAction { prompts, videos, clearTracks }

class _ConfirmActionBody extends StatelessWidget {
  final String message;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _ConfirmActionBody({
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: DFTokens.body14.copyWith(color: df.textSecondary),
          ),
          const SizedBox(height: DFTokens.s20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DFTokens.s8,
            runSpacing: DFTokens.s8,
            children: [
              TextButton(
                onPressed: onCancel,
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: onConfirm,
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposeResultBody extends StatelessWidget {
  final ComposeResult result;

  const _ComposeResultBody({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${l10n.workbenchOutputPath}: ${result.outputRelPath}',
            style: DFTokens.body14.copyWith(color: df.textSecondary),
          ),
          if (result.clipAssetId != null) ...[
            const SizedBox(height: DFTokens.s8),
            Text(
              l10n.workbenchSavedToAssets(result.clipAssetId!),
              style: DFTokens.body14.copyWith(color: df.textSecondary),
            ),
          ],
          if (result.durationSec != null) ...[
            const SizedBox(height: DFTokens.s8),
            Text(
              '${l10n.workbenchDuration}: ${result.durationSec!.toStringAsFixed(1)}s',
              style: DFTokens.body14.copyWith(color: df.textSecondary),
            ),
          ],
          const SizedBox(height: DFTokens.s20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonConfirm),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineOverview extends ConsumerStatefulWidget {
  final int projectId;
  final List<StoryboardRow> shots;

  const _TimelineOverview({required this.projectId, required this.shots});

  @override
  ConsumerState<_TimelineOverview> createState() => _TimelineOverviewState();
}

class _TimelineClipPlacement {
  final int lane;
  final int startMs;
  final int durationMs;

  const _TimelineClipPlacement({
    required this.lane,
    required this.startMs,
    required this.durationMs,
  });
}

class _TimelineOverviewState extends ConsumerState<_TimelineOverview> {
  static const double _dragPixelsPerTimeStep = 12;
  static const int _dragTimeStepMs = 100;
  static const double _dragPixelsPerLaneStep = 36;
  static const double _timelineTrackStartX = 92;
  static const int _defaultClipDurationMs = 1000;
  static const int _minClipDurationMs = 100;
  static const int _snapThresholdMs = 100;

  final _timelineDropZoneKey = GlobalKey();
  final _selectedClipIds = <int>{};
  int? _snapPlayheadMs;

  void _updateSnapPlayhead(String value) {
    final parsed = int.tryParse(value.trim());
    setState(() {
      _snapPlayheadMs = parsed != null && parsed >= 0 ? parsed : null;
    });
  }

  void _toggleClipSelection(int clipId, bool selected) {
    setState(() {
      if (selected) {
        _selectedClipIds.add(clipId);
      } else {
        _selectedClipIds.remove(clipId);
      }
    });
  }

  void _splitSelectedClipsAtPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty || playheadMs == null) return;
    final engine = ref.read(engineProvider);
    final newIds = engine.splitTimelineClipsAt(
      clipIds: _selectedClipIds.toList(),
      playheadMs: playheadMs,
    );
    setState(() {
      _selectedClipIds.addAll(newIds);
    });
  }

  void _duplicateSelectedClipLayers() {
    if (_selectedClipIds.isEmpty) return;
    final engine = ref.read(engineProvider);
    final duplicateIds =
        engine.duplicateTimelineClips(_selectedClipIds.toList());
    setState(() {
      _selectedClipIds
        ..clear()
        ..addAll(duplicateIds);
    });
  }

  void _copySelectedClipLayersToPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty || playheadMs == null) return;
    final engine = ref.read(engineProvider);
    final duplicateIds =
        engine.duplicateTimelineClips(_selectedClipIds.toList());
    if (duplicateIds.isEmpty) return;
    final duplicateRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => duplicateIds.contains(clip.id))
        .toList();
    if (duplicateRows.isEmpty) return;
    final duplicateStart = duplicateRows
        .map((clip) => clip.startMs)
        .reduce((a, b) => a < b ? a : b);
    engine.moveTimelineClips(
      clipIds: duplicateIds,
      deltaStartMs: playheadMs - duplicateStart,
    );
    setState(() {
      _selectedClipIds
        ..clear()
        ..addAll(duplicateIds);
    });
  }

  void _alignSelectedClipLayersToPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty ||
        playheadMs == null ||
        widget.shots.isEmpty) {
      return;
    }
    _alignSelectedClipLayers((_) => playheadMs);
  }

  void _alignSelectedClipLayerEndsToPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty ||
        playheadMs == null ||
        widget.shots.isEmpty) {
      return;
    }
    _alignSelectedClipLayers((clip) {
      final duration = clip.durationMs ?? _defaultClipDurationMs;
      final nextStart = playheadMs - duration;
      return nextStart < 0 ? 0 : nextStart;
    });
  }

  void _alignSelectedClipLayerCentersToPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty ||
        playheadMs == null ||
        widget.shots.isEmpty) {
      return;
    }
    _alignSelectedClipLayers((clip) {
      final duration = clip.durationMs ?? _defaultClipDurationMs;
      final nextStart = playheadMs - duration ~/ 2;
      return nextStart < 0 ? 0 : nextStart;
    });
  }

  void _alignSelectedClipLayers(int Function(TimelineClipRow clip) startFor) {
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final selectedIds = selectedRows.map((clip) => clip.id).toSet();
    final placements = <_TimelineClipPlacement>[];
    for (final clip in selectedRows) {
      final duration = clip.durationMs ?? _defaultClipDurationMs;
      final resolvedStart = _avoidTimelineClipOverlapForward(
        engine: engine,
        clip: clip,
        lane: clip.lane,
        startMs: startFor(clip),
        durationMs: duration,
        ignoredClipIds: selectedIds,
        placed: placements,
      );
      engine.updateTimelineClip(
        clipId: clip.id,
        lane: clip.lane,
        startMs: resolvedStart,
        durationMs: clip.durationMs,
      );
      placements.add(_TimelineClipPlacement(
        lane: clip.lane,
        startMs: resolvedStart,
        durationMs: duration,
      ));
    }
    setState(() {});
  }

  void _rippleDuplicateSelectedClipLayers() {
    if (_selectedClipIds.isEmpty) return;
    final engine = ref.read(engineProvider);
    final duplicateIds =
        engine.duplicateTimelineClipsRipple(_selectedClipIds.toList());
    setState(() {
      _selectedClipIds
        ..clear()
        ..addAll(duplicateIds);
    });
  }

  Future<void> _moveSelectedClipLayers() async {
    if (_selectedClipIds.isEmpty || widget.shots.isEmpty) return;
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final defaultStartMs = selectedRows
        .map((clip) => clip.startMs)
        .reduce((a, b) => a < b ? a : b);
    final nextStartMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineMoveTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipStartDialog(
        defaultStartMs: defaultStartMs,
        inputKey: const ValueKey('workbench-timeline-move-start-input'),
        confirmKey: const ValueKey('workbench-timeline-move-confirm'),
      ),
    );
    if (nextStartMs == null || !mounted) return;
    engine.moveTimelineClips(
      clipIds: _selectedClipIds.toList(),
      deltaStartMs: nextStartMs - defaultStartMs,
    );
    setState(() {});
  }

  Future<void> _laneSelectedClipLayers() async {
    if (_selectedClipIds.isEmpty || widget.shots.isEmpty) return;
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final defaultLane =
        selectedRows.map((clip) => clip.lane).reduce((a, b) => a < b ? a : b);
    final nextLane = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineLaneTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipLaneDialog(
        defaultLane: defaultLane,
        inputKey: const ValueKey('workbench-timeline-lane-input'),
        confirmKey: const ValueKey('workbench-timeline-lane-confirm'),
      ),
    );
    if (nextLane == null || !mounted) return;
    engine.moveTimelineClips(
      clipIds: _selectedClipIds.toList(),
      deltaStartMs: 0,
      deltaLane: nextLane - defaultLane,
    );
    setState(() {});
  }

  Future<void> _rippleMoveSelectedClipLayers() async {
    if (_selectedClipIds.isEmpty || widget.shots.isEmpty) return;
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final defaultStartMs = selectedRows
        .map((clip) => clip.startMs)
        .reduce((a, b) => a < b ? a : b);
    final nextStartMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineRippleMoveTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipStartDialog(
        defaultStartMs: defaultStartMs,
        inputKey: const ValueKey('workbench-timeline-ripple-move-start-input'),
        confirmKey: const ValueKey('workbench-timeline-ripple-move-confirm'),
      ),
    );
    if (nextStartMs == null || !mounted) return;
    engine.moveTimelineClipsRipple(
      clipIds: _selectedClipIds.toList(),
      startMs: nextStartMs,
    );
    setState(() {});
  }

  Future<void> _trimSelectedClipLayersEnd() async {
    if (_selectedClipIds.isEmpty || widget.shots.isEmpty) return;
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final defaultDurationMs =
        selectedRows.first.durationMs ?? _defaultClipDurationMs;
    final nextDurationMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineTrimTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipDurationDialog(
        defaultDurationMs: defaultDurationMs,
        inputKey: const ValueKey('workbench-timeline-trim-duration-input'),
        confirmKey: const ValueKey('workbench-timeline-trim-confirm'),
      ),
    );
    if (nextDurationMs == null || !mounted) return;
    engine.resizeTimelineClipsEnd(
      clipIds: _selectedClipIds.toList(),
      durationMs: nextDurationMs,
    );
    setState(() {});
  }

  void _trimSelectedClipLayersEndToPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty ||
        playheadMs == null ||
        widget.shots.isEmpty) {
      return;
    }
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final selectedIds = selectedRows.map((clip) => clip.id).toSet();
    for (final clip in selectedRows) {
      final rawDuration = playheadMs - clip.startMs;
      final targetDuration =
          rawDuration < _minClipDurationMs ? _minClipDurationMs : rawDuration;
      final resolvedDuration = _avoidTimelineClipEndOverlap(
        engine: engine,
        clip: clip,
        durationMs: targetDuration,
        ignoredClipIds: selectedIds,
      );
      engine.updateTimelineClip(
        clipId: clip.id,
        lane: clip.lane,
        startMs: clip.startMs,
        durationMs: resolvedDuration,
      );
    }
    setState(() {});
  }

  void _trimSelectedClipLayersStartToPlayhead() {
    final playheadMs = _snapPlayheadMs;
    if (_selectedClipIds.isEmpty ||
        playheadMs == null ||
        widget.shots.isEmpty) {
      return;
    }
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final selectedIds = selectedRows.map((clip) => clip.id).toSet();
    for (final clip in selectedRows) {
      final duration = clip.durationMs ?? _defaultClipDurationMs;
      final clipEnd = clip.startMs + duration;
      var targetStart = playheadMs;
      final maxStart = clipEnd - _minClipDurationMs;
      if (targetStart > maxStart) targetStart = maxStart;
      if (targetStart < 0) targetStart = 0;
      targetStart = _avoidTimelineClipStartOverlap(
        engine: engine,
        clip: clip,
        startMs: targetStart,
        endMs: clipEnd,
        ignoredClipIds: selectedIds,
      );
      final nextDuration = clipEnd - targetStart;
      engine.updateTimelineClip(
        clipId: clip.id,
        lane: clip.lane,
        startMs: targetStart,
        durationMs: nextDuration < _minClipDurationMs
            ? _minClipDurationMs
            : nextDuration,
      );
    }
    setState(() {});
  }

  Future<void> _rippleTrimSelectedClipLayersEnd() async {
    if (_selectedClipIds.isEmpty || widget.shots.isEmpty) return;
    final engine = ref.read(engineProvider);
    final selectedRows = engine
        .timelineClips(widget.shots.first.scriptId)
        .where((clip) => _selectedClipIds.contains(clip.id))
        .toList();
    if (selectedRows.isEmpty) return;
    final defaultDurationMs =
        selectedRows.first.durationMs ?? _defaultClipDurationMs;
    final nextDurationMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineRippleTrimTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipDurationDialog(
        defaultDurationMs: defaultDurationMs,
        inputKey:
            const ValueKey('workbench-timeline-ripple-trim-duration-input'),
        confirmKey: const ValueKey('workbench-timeline-ripple-trim-confirm'),
      ),
    );
    if (nextDurationMs == null || !mounted) return;
    engine.resizeTimelineClipsEndRipple(
      clipIds: _selectedClipIds.toList(),
      durationMs: nextDurationMs,
    );
    setState(() {});
  }

  void _deleteSelectedClipLayers() {
    if (_selectedClipIds.isEmpty) return;
    final engine = ref.read(engineProvider);
    engine.deleteTimelineClips(_selectedClipIds.toList());
    setState(_selectedClipIds.clear);
  }

  void _rippleDeleteSelectedClipLayers() {
    if (_selectedClipIds.isEmpty) return;
    final engine = ref.read(engineProvider);
    engine.deleteTimelineClipsRipple(_selectedClipIds.toList());
    setState(_selectedClipIds.clear);
  }

  Future<void> _addClipLayer() async {
    final l10n = context.l10n;
    final engine = ref.read(engineProvider);
    final clips =
        engine.getAssets(widget.projectId, type: 'clip', limit: 100).data;
    try {
      final draft = await showDFAdaptiveDialog<_TimelineClipDraft>(
        context,
        title: l10n.workbenchTimelineAddClipTitle,
        desktopWidthFactor: 0.42,
        builder: (c) => _AddTimelineClipDialog(clips: clips),
      );
      if (draft == null || !mounted) return;
      if (draft.autoLane) {
        engine.addTimelineClipFromAssetAutoLane(
          projectId: widget.projectId,
          scriptId: widget.shots.first.scriptId,
          clipAssetId: draft.asset.id,
          lane: draft.lane,
          startMs: draft.startMs,
          durationMs: draft.durationMs,
        );
      } else if (draft.rippleInsert) {
        engine.addTimelineClipFromAssetRipple(
          projectId: widget.projectId,
          scriptId: widget.shots.first.scriptId,
          clipAssetId: draft.asset.id,
          lane: draft.lane,
          startMs: draft.startMs,
          durationMs: draft.durationMs,
        );
      } else {
        engine.addTimelineClipFromAsset(
          projectId: widget.projectId,
          scriptId: widget.shots.first.scriptId,
          clipAssetId: draft.asset.id,
          lane: draft.lane,
          startMs: draft.startMs,
          durationMs: draft.durationMs,
        );
      }
      setState(() {});
      _showWorkbenchSnackBar(context, l10n.workbenchTimelineClipAdded);
    } catch (e) {
      if (!mounted) return;
      _showWorkbenchSnackBar(context, localizeError(context, e));
    }
  }

  Future<void> _openTimelineMediaLibrary() async {
    final engine = ref.read(engineProvider);
    final clips =
        engine.getAssets(widget.projectId, type: 'clip', limit: 100).data;
    try {
      final asset = await showDFAdaptiveDialog<AssetRow>(
        context,
        title: context.l10n.workbenchTimelineMediaLibraryTitle,
        desktopWidthFactor: 0.46,
        builder: (c) => _TimelineMediaLibraryDialog(clips: clips),
      );
      if (asset == null || !mounted) return;
      _addTimelineClipAsset(asset, startMs: _snapPlayheadMs ?? 0);
    } catch (e) {
      if (!mounted) return;
      _showWorkbenchSnackBar(context, localizeError(context, e));
    }
  }

  void _addTimelineClipAssetFromDrop(AssetRow asset, Offset globalDropOffset) {
    final engine = ref.read(engineProvider);
    final scriptId = widget.shots.first.scriptId;
    final rawStartMs = _timelineDropStartMs(globalDropOffset);
    final startMs = rawStartMs == null
        ? _snapPlayheadMs ?? 0
        : _snapNewTimelineClipStart(
            engine: engine,
            scriptId: scriptId,
            startMs: rawStartMs,
          );
    _addTimelineClipAsset(asset, startMs: startMs);
  }

  int? _timelineDropStartMs(Offset globalDropOffset) {
    final context = _timelineDropZoneKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final local = renderObject.globalToLocal(globalDropOffset);
    final trackX = local.dx - _timelineTrackStartX;
    final timeSteps = (trackX / _dragPixelsPerTimeStep).round();
    return (timeSteps < 0 ? 0 : timeSteps) * _dragTimeStepMs;
  }

  int _snapNewTimelineClipStart({
    required Engine engine,
    required int scriptId,
    required int startMs,
  }) {
    final anchors =
        _timelineDropSnapAnchors(engine: engine, scriptId: scriptId);
    final snappedStart = _snapValue(
      startMs,
      anchors,
    );
    if (snappedStart != startMs) {
      return snappedStart < 0 ? 0 : snappedStart;
    }
    final snappedEnd = _snapValue(startMs + _defaultClipDurationMs, anchors);
    final nextStart = snappedEnd == startMs + _defaultClipDurationMs
        ? startMs
        : snappedEnd - _defaultClipDurationMs;
    return nextStart < 0 ? 0 : nextStart;
  }

  List<int> _timelineDropSnapAnchors({
    required Engine engine,
    required int scriptId,
  }) {
    final anchors = <int>{0};
    final playheadMs = _snapPlayheadMs;
    if (playheadMs != null) anchors.add(playheadMs);
    var cursorMs = 0;
    for (final shot in widget.shots.where((s) => s.scriptId == scriptId)) {
      final track = shot.trackId != null ? engine.track(shot.trackId!) : null;
      anchors.add(cursorMs);
      cursorMs += _timelineSeconds(shot, track) * 1000;
      anchors.add(cursorMs);
    }
    for (final clip in engine.timelineClips(scriptId)) {
      final duration = clip.durationMs ?? _defaultClipDurationMs;
      anchors
        ..add(clip.startMs)
        ..add(clip.startMs + duration);
    }
    return anchors.toList();
  }

  void _addTimelineClipAsset(AssetRow asset, {required int startMs}) {
    final l10n = context.l10n;
    try {
      ref.read(engineProvider).addTimelineClipFromAssetAutoLane(
            projectId: widget.projectId,
            scriptId: widget.shots.first.scriptId,
            clipAssetId: asset.id,
            lane: 1,
            startMs: startMs,
          );
      setState(() {});
      _showWorkbenchSnackBar(context, l10n.workbenchTimelineClipAdded);
    } catch (e) {
      if (!mounted) return;
      _showWorkbenchSnackBar(context, localizeError(context, e));
    }
  }

  void _moveClipLayer(TimelineClipRow clip, Offset dragDelta) {
    final timeSteps = (dragDelta.dx / _dragPixelsPerTimeStep).round();
    final laneSteps = (dragDelta.dy / _dragPixelsPerLaneStep).round();
    if (timeSteps == 0 && laneSteps == 0) return;
    final engine = ref.read(engineProvider);
    final timelineSnapshot = engine.timelineClips(clip.scriptId);
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    final rawDeltaStartMs = timeSteps * _dragTimeStepMs;
    final rawStart = clip.startMs + rawDeltaStartMs;
    if (_selectedClipIds.length > 1 && _selectedClipIds.contains(clip.id)) {
      final resolvedDeltaStartMs = timeSteps == 0
          ? 0
          : _snapTimelineClipGroupDelta(
              engine: engine,
              clip: clip,
              selectedClipIds: _selectedClipIds,
              deltaStartMs: rawDeltaStartMs,
              timelineClips: timelineSnapshot,
            );
      engine.moveTimelineClips(
        clipIds: _selectedClipIds.toList(),
        deltaStartMs: resolvedDeltaStartMs,
        deltaLane: laneSteps,
      );
      setState(() {});
      return;
    }
    final nextStart = timeSteps == 0
        ? clip.startMs
        : _snapClipStart(
            engine: engine,
            clip: clip,
            startMs: rawStart,
            durationMs: duration,
            timelineClips: timelineSnapshot,
          );
    final nextLane = clip.lane + laneSteps;
    final resolvedLane = laneSteps == 0
        ? nextLane
        : _autoTimelineClipLane(
            engine: engine,
            clip: clip,
            preferredLane: nextLane,
            startMs: nextStart,
            durationMs: duration,
            timelineClips: timelineSnapshot,
          );
    final resolvedStart = laneSteps == 0
        ? _avoidTimelineClipOverlap(
            engine: engine,
            clip: clip,
            lane: resolvedLane,
            startMs: nextStart,
            durationMs: duration,
            timelineClips: timelineSnapshot,
          )
        : nextStart;
    engine.updateTimelineClip(
      clipId: clip.id,
      lane: resolvedLane,
      startMs: resolvedStart,
      durationMs: clip.durationMs,
    );
    setState(() {});
  }

  int _snapTimelineClipGroupDelta({
    required Engine engine,
    required TimelineClipRow clip,
    required Set<int> selectedClipIds,
    required int deltaStartMs,
    List<TimelineClipRow>? timelineClips,
  }) {
    final clips = timelineClips ?? engine.timelineClips(clip.scriptId);
    final selectedRows =
        clips.where((row) => selectedClipIds.contains(row.id)).toList();
    if (selectedRows.length < 2) return deltaStartMs;
    final groupStart =
        selectedRows.map((row) => row.startMs).reduce((a, b) => a < b ? a : b);
    final groupEnd = selectedRows.map((row) {
      final duration = row.durationMs ?? _defaultClipDurationMs;
      return row.startMs + duration;
    }).reduce((a, b) => a > b ? a : b);
    final anchors = _timelineSnapAnchors(
      engine: engine,
      clip: clip,
      excludeClipIds: selectedClipIds,
      timelineClips: clips,
    );
    final rawGroupStart = groupStart + deltaStartMs;
    final snappedGroupStart = _snapValue(rawGroupStart, anchors);
    if (snappedGroupStart != rawGroupStart) {
      return snappedGroupStart - groupStart;
    }
    final rawGroupEnd = groupEnd + deltaStartMs;
    final snappedGroupEnd = _snapValue(rawGroupEnd, anchors);
    if (snappedGroupEnd != rawGroupEnd) {
      return snappedGroupEnd - groupEnd;
    }
    return deltaStartMs;
  }

  void _resizeClipLayerEnd(TimelineClipRow clip, Offset dragDelta) {
    final timeSteps = (dragDelta.dx / _dragPixelsPerTimeStep).round();
    if (timeSteps == 0) return;
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    final rawDuration = duration + timeSteps * _dragTimeStepMs;
    final engine = ref.read(engineProvider);
    final timelineSnapshot = engine.timelineClips(clip.scriptId);
    final rawEnd = clip.startMs +
        (rawDuration < _minClipDurationMs ? _minClipDurationMs : rawDuration);
    final snappedEnd = _snapValue(
      rawEnd,
      _timelineSnapAnchors(
        engine: engine,
        clip: clip,
        timelineClips: timelineSnapshot,
      ),
    );
    final snappedDuration = snappedEnd - clip.startMs;
    final nextDuration = snappedDuration < _minClipDurationMs
        ? _minClipDurationMs
        : snappedDuration;
    final resolvedDuration = _avoidTimelineClipEndOverlap(
      engine: engine,
      clip: clip,
      durationMs: nextDuration,
      timelineClips: timelineSnapshot,
    );
    engine.updateTimelineClip(
      clipId: clip.id,
      lane: clip.lane,
      startMs: clip.startMs,
      durationMs: resolvedDuration,
    );
    setState(() {});
  }

  void _trimClipLayerStart(TimelineClipRow clip, Offset dragDelta) {
    final timeSteps = (dragDelta.dx / _dragPixelsPerTimeStep).round();
    if (timeSteps == 0) return;
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    var deltaMs = timeSteps * _dragTimeStepMs;
    if (deltaMs > duration - _minClipDurationMs) {
      deltaMs = duration - _minClipDurationMs;
    }
    final nextStart = clip.startMs + deltaMs;
    final engine = ref.read(engineProvider);
    final timelineSnapshot = engine.timelineClips(clip.scriptId);
    var normalizedStart = nextStart < 0 ? 0 : nextStart;
    normalizedStart = _snapValue(
      normalizedStart,
      _timelineSnapAnchors(
        engine: engine,
        clip: clip,
        timelineClips: timelineSnapshot,
      ),
    );
    final maxStart = clip.startMs + duration - _minClipDurationMs;
    if (normalizedStart > maxStart) normalizedStart = maxStart;
    if (normalizedStart < 0) normalizedStart = 0;
    normalizedStart = _avoidTimelineClipStartOverlap(
      engine: engine,
      clip: clip,
      startMs: normalizedStart,
      endMs: clip.startMs + duration,
      timelineClips: timelineSnapshot,
    );
    final appliedDelta = normalizedStart - clip.startMs;
    final nextDuration = duration - appliedDelta;
    engine.updateTimelineClip(
      clipId: clip.id,
      lane: clip.lane,
      startMs: normalizedStart,
      durationMs:
          nextDuration < _minClipDurationMs ? _minClipDurationMs : nextDuration,
    );
    setState(() {});
  }

  int _snapClipStart({
    required Engine engine,
    required TimelineClipRow clip,
    required int startMs,
    required int durationMs,
    List<TimelineClipRow>? timelineClips,
  }) {
    final anchors = _timelineSnapAnchors(
      engine: engine,
      clip: clip,
      timelineClips: timelineClips,
    );
    final snappedStart = _snapValue(startMs, anchors);
    if (snappedStart != startMs) return snappedStart < 0 ? 0 : snappedStart;
    final snappedEnd = _snapValue(startMs + durationMs, anchors);
    final nextStart =
        snappedEnd == startMs + durationMs ? startMs : snappedEnd - durationMs;
    return nextStart < 0 ? 0 : nextStart;
  }

  int _avoidTimelineClipOverlap({
    required Engine engine,
    required TimelineClipRow clip,
    required int lane,
    required int startMs,
    required int durationMs,
    List<TimelineClipRow>? timelineClips,
  }) {
    final targetLane = lane < 1 ? 1 : lane;
    var candidate = startMs < 0 ? 0 : startMs;
    final clips = timelineClips ?? engine.timelineClips(clip.scriptId);
    final others = clips
        .where((other) => other.id != clip.id && other.lane == targetLane)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    var changed = true;
    var guard = 0;
    while (changed && guard < others.length + 1) {
      changed = false;
      guard += 1;
      for (final other in others) {
        final otherDuration = other.durationMs ?? _defaultClipDurationMs;
        final otherEnd = other.startMs + otherDuration;
        final candidateEnd = candidate + durationMs;
        final overlaps = candidate < otherEnd && candidateEnd > other.startMs;
        if (!overlaps) continue;
        candidate =
            candidate < other.startMs ? other.startMs - durationMs : otherEnd;
        if (candidate < 0) candidate = 0;
        changed = true;
        break;
      }
    }
    return candidate;
  }

  int _avoidTimelineClipOverlapForward({
    required Engine engine,
    required TimelineClipRow clip,
    required int lane,
    required int startMs,
    required int durationMs,
    Set<int> ignoredClipIds = const {},
    List<_TimelineClipPlacement> placed = const [],
  }) {
    final targetLane = lane < 1 ? 1 : lane;
    var candidate = startMs < 0 ? 0 : startMs;
    final intervals = <_TimelineClipPlacement>[
      for (final other in engine.timelineClips(clip.scriptId))
        if (other.id != clip.id &&
            other.lane == targetLane &&
            !ignoredClipIds.contains(other.id))
          _TimelineClipPlacement(
            lane: targetLane,
            startMs: other.startMs,
            durationMs: other.durationMs ?? _defaultClipDurationMs,
          ),
      for (final item in placed)
        if (item.lane == targetLane) item,
    ]..sort((a, b) {
        final byStart = a.startMs.compareTo(b.startMs);
        return byStart != 0 ? byStart : a.durationMs.compareTo(b.durationMs);
      });
    var changed = true;
    var guard = 0;
    while (changed && guard < intervals.length + 1) {
      changed = false;
      guard += 1;
      for (final interval in intervals) {
        final intervalEnd = interval.startMs + interval.durationMs;
        final candidateEnd = candidate + durationMs;
        final overlaps =
            candidate < intervalEnd && candidateEnd > interval.startMs;
        if (!overlaps) continue;
        candidate = intervalEnd;
        changed = true;
        break;
      }
    }
    return candidate;
  }

  int _autoTimelineClipLane({
    required Engine engine,
    required TimelineClipRow clip,
    required int preferredLane,
    required int startMs,
    required int durationMs,
    List<TimelineClipRow>? timelineClips,
  }) {
    final targetStart = startMs < 0 ? 0 : startMs;
    final targetEnd = targetStart + durationMs;
    var lane = preferredLane < 1 ? 1 : preferredLane;
    final clips = timelineClips ?? engine.timelineClips(clip.scriptId);
    final maxLane = clips.fold<int>(lane, (max, row) {
      return row.lane > max ? row.lane : max;
    });
    while (lane <= maxLane + 1) {
      final hasOverlap = clips.any((other) {
        if (other.id == clip.id || other.lane != lane) return false;
        final otherDuration = other.durationMs ?? _defaultClipDurationMs;
        final otherEnd = other.startMs + otherDuration;
        return targetStart < otherEnd && targetEnd > other.startMs;
      });
      if (!hasOverlap) return lane;
      lane += 1;
    }
    return lane;
  }

  int _avoidTimelineClipEndOverlap({
    required Engine engine,
    required TimelineClipRow clip,
    required int durationMs,
    Set<int> ignoredClipIds = const {},
    List<TimelineClipRow>? timelineClips,
  }) {
    var resolvedDuration = durationMs;
    final clipStart = clip.startMs;
    final clips = timelineClips ?? engine.timelineClips(clip.scriptId);
    for (final other in clips) {
      if (other.id == clip.id ||
          ignoredClipIds.contains(other.id) ||
          other.lane != clip.lane) {
        continue;
      }
      if (other.startMs <= clipStart) continue;
      final clipEnd = clipStart + resolvedDuration;
      if (clipEnd > other.startMs) {
        resolvedDuration = other.startMs - clipStart;
      }
    }
    return resolvedDuration < _minClipDurationMs
        ? _minClipDurationMs
        : resolvedDuration;
  }

  int _avoidTimelineClipStartOverlap({
    required Engine engine,
    required TimelineClipRow clip,
    required int startMs,
    required int endMs,
    Set<int> ignoredClipIds = const {},
    List<TimelineClipRow>? timelineClips,
  }) {
    var resolvedStart = startMs;
    final clips = timelineClips ?? engine.timelineClips(clip.scriptId);
    for (final other in clips) {
      if (other.id == clip.id ||
          ignoredClipIds.contains(other.id) ||
          other.lane != clip.lane) {
        continue;
      }
      final otherDuration = other.durationMs ?? _defaultClipDurationMs;
      final otherEnd = other.startMs + otherDuration;
      if (otherEnd <= resolvedStart || other.startMs >= endMs) continue;
      if (otherEnd > resolvedStart) resolvedStart = otherEnd;
    }
    final maxStart = endMs - _minClipDurationMs;
    if (resolvedStart > maxStart) return maxStart;
    return resolvedStart < 0 ? 0 : resolvedStart;
  }

  List<int> _timelineSnapAnchors({
    required Engine engine,
    required TimelineClipRow clip,
    Set<int> excludeClipIds = const <int>{},
    List<TimelineClipRow>? timelineClips,
  }) {
    final anchors = <int>{0};
    final excludedIds = {...excludeClipIds, clip.id};
    final playheadMs = _snapPlayheadMs;
    if (playheadMs != null) anchors.add(playheadMs);
    var cursorMs = 0;
    for (final shot in widget.shots.where((s) => s.scriptId == clip.scriptId)) {
      final track = shot.trackId != null ? engine.track(shot.trackId!) : null;
      anchors.add(cursorMs);
      cursorMs += _timelineSeconds(shot, track) * 1000;
      anchors.add(cursorMs);
    }
    final clips = timelineClips ?? engine.timelineClips(clip.scriptId);
    for (final other in clips) {
      if (excludedIds.contains(other.id)) continue;
      final duration = other.durationMs ?? _defaultClipDurationMs;
      anchors
        ..add(other.startMs)
        ..add(other.startMs + duration);
    }
    return anchors.toList();
  }

  int _snapValue(int value, Iterable<int> anchors) {
    var snapped = value;
    var bestDistance = _snapThresholdMs + 1;
    for (final anchor in anchors) {
      final distance = (value - anchor).abs();
      if (distance <= _snapThresholdMs && distance < bestDistance) {
        snapped = anchor;
        bestDistance = distance;
      }
    }
    return snapped;
  }

  void _splitClipLayer(TimelineClipRow clip) {
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    if (duration <= _minClipDurationMs * 2) return;
    final engine = ref.read(engineProvider);
    engine.splitTimelineClip(
      clipId: clip.id,
      offsetMs: duration ~/ 2,
    );
    setState(() {});
  }

  void _duplicateClipLayer(TimelineClipRow clip) {
    final engine = ref.read(engineProvider);
    engine.duplicateTimelineClip(clip.id);
    setState(() {});
  }

  void _rippleDuplicateClipLayer(TimelineClipRow clip) {
    final engine = ref.read(engineProvider);
    engine.duplicateTimelineClipRipple(clip.id);
    setState(() {});
  }

  Future<void> _rippleMoveClipLayer(TimelineClipRow clip) async {
    final nextStartMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineRippleMoveTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipStartDialog(
        defaultStartMs: clip.startMs,
        inputKey: const ValueKey('workbench-timeline-ripple-move-start-input'),
        confirmKey: const ValueKey('workbench-timeline-ripple-move-confirm'),
      ),
    );
    if (nextStartMs == null || !mounted) return;
    final engine = ref.read(engineProvider);
    engine.moveTimelineClipRipple(clipId: clip.id, startMs: nextStartMs);
    setState(() {});
  }

  Future<void> _splitClipLayerAtPlayhead(TimelineClipRow clip) async {
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    if (duration <= _minClipDurationMs * 2) return;
    final playheadMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineSplitAtTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _SplitTimelineClipDialog(
        defaultPlayheadMs: clip.startMs + duration ~/ 2,
      ),
    );
    if (playheadMs == null || !mounted) return;
    final engine = ref.read(engineProvider);
    engine.splitTimelineClip(
      clipId: clip.id,
      offsetMs: playheadMs - clip.startMs,
    );
    setState(() {});
  }

  Future<void> _rippleTrimClipLayerEnd(TimelineClipRow clip) async {
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    final nextDurationMs = await showDFAdaptiveDialog<int>(
      context,
      title: context.l10n.workbenchTimelineRippleTrimTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TimelineClipDurationDialog(
        defaultDurationMs: duration,
        inputKey:
            const ValueKey('workbench-timeline-ripple-trim-duration-input'),
        confirmKey: const ValueKey('workbench-timeline-ripple-trim-confirm'),
      ),
    );
    if (nextDurationMs == null || !mounted) return;
    final engine = ref.read(engineProvider);
    engine.resizeTimelineClipEndRipple(
      clipId: clip.id,
      durationMs: nextDurationMs,
    );
    setState(() {});
  }

  Future<void> _editClipLayer(TimelineClipRow clip) async {
    final draft = await showDFAdaptiveDialog<_TimelineClipPropertyDraft>(
      context,
      title: context.l10n.workbenchTimelineEditClipTitle,
      desktopWidthFactor: 0.42,
      builder: (c) => _EditTimelineClipDialog(clip: clip),
    );
    if (draft == null || !mounted) return;
    final duration = draft.durationMs ?? _defaultClipDurationMs;
    final engine = ref.read(engineProvider);
    final resolvedStart = _avoidTimelineClipOverlap(
      engine: engine,
      clip: clip,
      lane: draft.lane,
      startMs: draft.startMs,
      durationMs: duration,
    );
    engine.updateTimelineClip(
      clipId: clip.id,
      lane: draft.lane,
      startMs: resolvedStart,
      durationMs: draft.durationMs,
      opacity: draft.opacity,
    );
    setState(() {});
  }

  void _deleteClipLayer(TimelineClipRow clip) {
    final engine = ref.read(engineProvider);
    engine.deleteTimelineClip(clip.id);
    setState(() {
      _selectedClipIds.remove(clip.id);
    });
  }

  void _rippleDeleteClipLayer(TimelineClipRow clip) {
    final engine = ref.read(engineProvider);
    engine.deleteTimelineClipRipple(clip.id);
    setState(() {
      _selectedClipIds.remove(clip.id);
    });
  }

  List<Widget> _timelineOverlayClipWidgets({
    required Engine engine,
    required List<TimelineClipRow> clips,
  }) {
    final widgets = <Widget>[];
    var cursorPx = 0.0;
    for (final clip in clips) {
      final desiredLeft =
          clip.startMs * _dragPixelsPerTimeStep / _dragTimeStepMs;
      final gap = desiredLeft - cursorPx;
      if (gap > 0) {
        widgets.add(SizedBox(width: gap));
      }
      final groupSelected =
          _selectedClipIds.length > 1 && _selectedClipIds.contains(clip.id);
      widgets.add(
        _TimelineAssetClip(
          clip: clip,
          selected: _selectedClipIds.contains(clip.id),
          snapAnchors: _timelineSnapAnchors(
            engine: engine,
            clip: clip,
            excludeClipIds: groupSelected ? _selectedClipIds : const <int>{},
          ),
          snapPreviewOffsetsMs: _timelineClipSnapPreviewOffsets(
            engine: engine,
            clip: clip,
            selectedClipIds: _selectedClipIds,
          ),
          dragPixelsPerTimeStep: _dragPixelsPerTimeStep,
          dragTimeStepMs: _dragTimeStepMs,
          snapThresholdMs: _snapThresholdMs,
          onSelectedChanged: (selected) =>
              _toggleClipSelection(clip.id, selected),
          onDragCommit: (delta) => _moveClipLayer(clip, delta),
          onTrimStartCommit: (delta) => _trimClipLayerStart(clip, delta),
          onTrimEndCommit: (delta) => _resizeClipLayerEnd(clip, delta),
          onSplit: () => _splitClipLayer(clip),
          onDuplicate: () => _duplicateClipLayer(clip),
          onRippleDuplicate: () => _rippleDuplicateClipLayer(clip),
          onRippleMove: () => _rippleMoveClipLayer(clip),
          onSplitAt: () => _splitClipLayerAtPlayhead(clip),
          onRippleTrimEnd: () => _rippleTrimClipLayerEnd(clip),
          onEdit: () => _editClipLayer(clip),
          onDelete: () => _deleteClipLayer(clip),
          onRippleDelete: () => _rippleDeleteClipLayer(clip),
        ),
      );
      final clipRight = desiredLeft + _timelineAssetClipWidth(clip) + 8;
      if (clipRight > cursorPx) cursorPx = clipRight;
    }
    return widgets;
  }

  List<int> _timelineClipSnapPreviewOffsets({
    required Engine engine,
    required TimelineClipRow clip,
    required Set<int> selectedClipIds,
  }) {
    final duration = clip.durationMs ?? _defaultClipDurationMs;
    final offsets = <int>[0, duration];
    if (selectedClipIds.length < 2 || !selectedClipIds.contains(clip.id)) {
      return offsets;
    }
    final selectedRows = engine
        .timelineClips(clip.scriptId)
        .where((row) => selectedClipIds.contains(row.id))
        .toList();
    if (selectedRows.length < 2) return offsets;
    final groupStart =
        selectedRows.map((row) => row.startMs).reduce((a, b) => a < b ? a : b);
    final groupEnd = selectedRows.map((row) {
      final rowDuration = row.durationMs ?? _defaultClipDurationMs;
      return row.startMs + rowDuration;
    }).reduce((a, b) => a > b ? a : b);
    for (final offset in [groupStart - clip.startMs, groupEnd - clip.startMs]) {
      if (!offsets.contains(offset)) offsets.add(offset);
    }
    return offsets;
  }

  List<Widget> _timelineOverlayLaneWidgets({
    required Engine engine,
    required List<TimelineClipRow> clips,
    required String label,
  }) {
    final byLane = <int, List<TimelineClipRow>>{};
    for (final clip in clips) {
      (byLane[clip.lane] ??= <TimelineClipRow>[]).add(clip);
    }
    final laneIds = byLane.keys.toList()..sort();
    final rows = <Widget>[];
    for (var i = 0; i < laneIds.length; i++) {
      final lane = laneIds[i];
      final laneClips = byLane[lane]!
        ..sort((a, b) {
          final byStart = a.startMs.compareTo(b.startMs);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        _TimelineLane(
          label: i == 0 ? label : '$label L$lane',
          icon: Icons.layers_outlined,
          children: _timelineOverlayClipWidgets(
            engine: engine,
            clips: laneClips,
          ),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final engine = ref.watch(engineProvider);
    final audioNames = {
      for (final audio in engine.audioPool(widget.projectId))
        audio.id: audio.name,
    };
    final clips = widget.shots.isEmpty
        ? <TimelineClipRow>[]
        : engine.timelineClips(widget.shots.first.scriptId);
    final liveClipIds = clips.map((clip) => clip.id).toSet();
    _selectedClipIds.removeWhere((id) => !liveClipIds.contains(id));
    final selectedClipCount = _selectedClipIds.length;
    final compactBatchButtonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final mediaClips = engine
        .getAssets(widget.projectId, type: 'clip', limit: 100)
        .data
        .where((clip) => clip.filePath?.isNotEmpty == true)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, constraints) {
          final title = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.view_timeline_outlined, size: 18, color: df.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.workbenchTimelineOverview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: df.textHi,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ]);
          final controls = [
            SizedBox(
              width: 132,
              child: TextField(
                key: const ValueKey('workbench-timeline-playhead-input'),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.workbenchTimelineSplitAtMs,
                ),
                keyboardType: TextInputType.number,
                onChanged: _updateSnapPlayhead,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('workbench-timeline-media'),
              onPressed:
                  widget.shots.isEmpty ? null : _openTimelineMediaLibrary,
              icon: const Icon(Icons.video_library_outlined, size: 16),
              label: Text(l10n.workbenchTimelineMediaLibrary),
            ),
            TextButton.icon(
              onPressed: widget.shots.isEmpty ? null : _addClipLayer,
              icon: const Icon(Icons.add_to_photos_outlined, size: 16),
              label: Text(l10n.workbenchTimelineAddClip),
            ),
          ];
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: controls),
              ],
            );
          }
          return Row(children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            ...[
              for (var i = 0; i < controls.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                controls[i],
              ],
            ],
          ]);
        }),
        const SizedBox(height: 10),
        if (mediaClips.isNotEmpty) ...[
          _TimelineMediaBin(clips: mediaClips),
          const SizedBox(height: 10),
        ],
        if (clips.isNotEmpty) ...[
          TextButtonTheme(
            data: TextButtonThemeData(style: compactBatchButtonStyle),
            child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.workbenchTimelineSelectedClips(selectedClipCount),
                    style: TextStyle(
                      color: df.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('workbench-timeline-split-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _splitSelectedClipsAtPlayhead,
                    icon: const Icon(Icons.call_split_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineSplitSelected),
                  ),
                  TextButton.icon(
                    key:
                        const ValueKey('workbench-timeline-duplicate-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _duplicateSelectedClipLayers,
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineDuplicateSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-copy-to-playhead-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _copySelectedClipLayersToPlayhead,
                    icon: const Icon(Icons.content_paste_go_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineCopyToPlayheadSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-align-to-playhead-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _alignSelectedClipLayersToPlayhead,
                    icon: const Icon(Icons.vertical_align_center, size: 16),
                    label: Text(l10n.workbenchTimelineAlignToPlayheadSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-align-end-to-playhead-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _alignSelectedClipLayerEndsToPlayhead,
                    icon: const Icon(Icons.vertical_align_bottom, size: 16),
                    label:
                        Text(l10n.workbenchTimelineAlignEndToPlayheadSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-align-center-to-playhead-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _alignSelectedClipLayerCentersToPlayhead,
                    icon: const Icon(Icons.center_focus_strong_outlined,
                        size: 16),
                    label: Text(
                        l10n.workbenchTimelineAlignCenterToPlayheadSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-ripple-duplicate-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _rippleDuplicateSelectedClipLayers,
                    icon: const Icon(Icons.playlist_add_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineRippleDuplicateSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey('workbench-timeline-move-selected'),
                    onPressed:
                        selectedClipCount == 0 ? null : _moveSelectedClipLayers,
                    icon: const Icon(Icons.swap_horiz_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineMoveSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey('workbench-timeline-lane-selected'),
                    onPressed:
                        selectedClipCount == 0 ? null : _laneSelectedClipLayers,
                    icon: const Icon(Icons.layers_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineLaneSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-ripple-move-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _rippleMoveSelectedClipLayers,
                    icon: const Icon(Icons.open_with_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineRippleMoveSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey('workbench-timeline-trim-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _trimSelectedClipLayersEnd,
                    icon: const Icon(Icons.content_cut_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineTrimSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-trim-to-playhead-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _trimSelectedClipLayersEndToPlayhead,
                    icon: const Icon(Icons.vertical_align_bottom, size: 16),
                    label: Text(l10n.workbenchTimelineTrimToPlayheadSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-trim-start-to-playhead-selected'),
                    onPressed: selectedClipCount == 0 || _snapPlayheadMs == null
                        ? null
                        : _trimSelectedClipLayersStartToPlayhead,
                    icon: const Icon(Icons.vertical_align_top, size: 16),
                    label:
                        Text(l10n.workbenchTimelineTrimStartToPlayheadSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-ripple-trim-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _rippleTrimSelectedClipLayersEnd,
                    icon: const Icon(Icons.compress_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineRippleTrimSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey('workbench-timeline-delete-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _deleteSelectedClipLayers,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(l10n.workbenchTimelineDeleteSelected),
                  ),
                  TextButton.icon(
                    key: const ValueKey(
                        'workbench-timeline-ripple-delete-selected'),
                    onPressed: selectedClipCount == 0
                        ? null
                        : _rippleDeleteSelectedClipLayers,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: Text(l10n.workbenchTimelineRippleDeleteSelected),
                  ),
                ]),
          ),
          const SizedBox(height: 10),
        ],
        DragTarget<AssetRow>(
          onWillAcceptWithDetails: (details) {
            return widget.shots.isNotEmpty &&
                details.data.filePath?.isNotEmpty == true;
          },
          onAcceptWithDetails: (details) {
            _addTimelineClipAssetFromDrop(details.data, details.offset);
          },
          builder: (context, candidateData, rejectedData) {
            final active = candidateData.isNotEmpty;
            return Container(
              key: const ValueKey('workbench-timeline-drop-zone'),
              child: AnimatedContainer(
                key: _timelineDropZoneKey,
                duration: DFTokens.fast120,
                padding: active ? const EdgeInsets.all(6) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                  border: active
                      ? Border.all(color: df.primary, width: 1.5)
                      : Border.all(color: Colors.transparent),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TimelineLane(
                          label: l10n.workbenchTimelineVideoTrack,
                          icon: Icons.movie_outlined,
                          children: [
                            for (var i = 0; i < widget.shots.length; i++)
                              _TimelineClip(
                                key: ValueKey(
                                    'workbench-timeline-video-${widget.shots[i].id}'),
                                index: i,
                                shot: widget.shots[i],
                                track: widget.shots[i].trackId != null
                                    ? engine.track(widget.shots[i].trackId!)
                                    : null,
                                kind: _TimelineClipKind.video,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _TimelineLane(
                          label: l10n.workbenchTimelineAudioTrack,
                          icon: Icons.graphic_eq_outlined,
                          children: [
                            for (var i = 0; i < widget.shots.length; i++)
                              _TimelineClip(
                                key: ValueKey(
                                    'workbench-timeline-audio-${widget.shots[i].id}'),
                                index: i,
                                shot: widget.shots[i],
                                track: widget.shots[i].trackId != null
                                    ? engine.track(widget.shots[i].trackId!)
                                    : null,
                                kind: _TimelineClipKind.audio,
                                audioName: widget.shots[i].audioAssetId != null
                                    ? audioNames[widget.shots[i].audioAssetId]
                                    : null,
                              ),
                          ],
                        ),
                        if (clips.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ..._timelineOverlayLaneWidgets(
                            engine: engine,
                            clips: clips,
                            label: l10n.workbenchTimelineOverlayTrack,
                          ),
                        ],
                      ]),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _TimelineMediaBin extends StatelessWidget {
  final List<AssetRow> clips;

  const _TimelineMediaBin({required this.clips});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 84,
        child: Row(children: [
          Icon(Icons.perm_media_outlined, size: 14, color: df.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.workbenchTimelineMediaBin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: df.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final clip in clips) ...[
              Draggable<AssetRow>(
                data: clip,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Material(
                  color: Colors.transparent,
                  child: _TimelineMediaChip(clip: clip, elevated: true),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.45,
                  child: _TimelineMediaChip(clip: clip),
                ),
                child: _TimelineMediaChip(
                  key: ValueKey('workbench-timeline-media-drag-${clip.id}'),
                  clip: clip,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      ),
    ]);
  }
}

class _TimelineMediaChip extends StatelessWidget {
  final AssetRow clip;
  final bool elevated;

  const _TimelineMediaChip({
    super.key,
    required this.clip,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: df.primarySubtle,
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
        border: Border.all(color: df.primary.withValues(alpha: 0.35)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.video_library_outlined, size: 14, color: df.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.l10n.workbenchTimelineDraggableClipName(clip.name ?? ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: df.textHi,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ]),
    );
  }
}

class _TimelineMediaLibraryDialog extends StatelessWidget {
  final List<AssetRow> clips;

  const _TimelineMediaLibraryDialog({required this.clips});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 840;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: clips.isEmpty
                ? Center(child: DFEmpty(text: l10n.workbenchNoClipAssets))
                : ListView.separated(
                    itemCount: clips.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final row = clips[i];
                      final enabled = row.filePath?.isNotEmpty == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.video_library_outlined),
                        title: Text(row.name ?? ''),
                        subtitle: Text(
                          row.filePath ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: FilledButton(
                          key: ValueKey(
                            'workbench-timeline-media-add-${row.id}',
                          ),
                          onPressed: enabled
                              ? () => Navigator.of(context).pop(row)
                              : null,
                          child: Text(l10n.workbenchTimelineAddAtPlayhead),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: DFTokens.s16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
          ),
        ],
      ),
    );

    if (compact) return content;
    return SizedBox(
      height: clips.length <= 3 ? 280 : 520,
      child: content,
    );
  }
}

class _TimelineClipDraft {
  final AssetRow asset;
  final int lane;
  final int startMs;
  final int? durationMs;
  final bool rippleInsert;
  final bool autoLane;

  const _TimelineClipDraft({
    required this.asset,
    required this.lane,
    required this.startMs,
    required this.durationMs,
    required this.rippleInsert,
    required this.autoLane,
  });
}

class _TimelineClipPropertyDraft {
  final int lane;
  final int startMs;
  final int? durationMs;
  final double opacity;

  const _TimelineClipPropertyDraft({
    required this.lane,
    required this.startMs,
    required this.durationMs,
    required this.opacity,
  });
}

class _AddTimelineClipDialog extends StatefulWidget {
  final List<AssetRow> clips;

  const _AddTimelineClipDialog({required this.clips});

  @override
  State<_AddTimelineClipDialog> createState() => _AddTimelineClipDialogState();
}

class _AddTimelineClipDialogState extends State<_AddTimelineClipDialog> {
  late final TextEditingController _laneCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _durationCtrl;
  AssetRow? _selected;

  @override
  void initState() {
    super.initState();
    _laneCtrl = TextEditingController(text: '1');
    _startCtrl = TextEditingController(text: '0');
    _durationCtrl = TextEditingController();
    _selected = widget.clips.where((clip) => clip.filePath != null).firstOrNull;
  }

  @override
  void dispose() {
    _laneCtrl.dispose();
    _startCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  _TimelineClipDraft? _draft({
    required bool rippleInsert,
    required bool autoLane,
  }) {
    final selected = _selected;
    if (selected == null) return null;
    return _TimelineClipDraft(
      asset: selected,
      lane: int.tryParse(_laneCtrl.text.trim()) ?? 1,
      startMs: int.tryParse(_startCtrl.text.trim()) ?? 0,
      durationMs: int.tryParse(_durationCtrl.text.trim()),
      rippleInsert: rippleInsert,
      autoLane: autoLane,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 480;
    final fields = [
      TextField(
        controller: _laneCtrl,
        decoration: InputDecoration(labelText: l10n.workbenchTimelineLayer),
        keyboardType: TextInputType.number,
      ),
      TextField(
        controller: _startCtrl,
        decoration: InputDecoration(labelText: l10n.workbenchTimelineStartMs),
        keyboardType: TextInputType.number,
      ),
      TextField(
        controller: _durationCtrl,
        decoration:
            InputDecoration(labelText: l10n.workbenchTimelineDurationMs),
        keyboardType: TextInputType.number,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.clips.isEmpty)
            DFEmpty(text: l10n.workbenchNoClipAssets)
          else
            SizedBox(
              height: compact ? 220 : 160,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.clips.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final row = widget.clips[i];
                  final enabled = row.filePath?.isNotEmpty == true;
                  return ListTile(
                    leading: const Icon(Icons.video_library_outlined),
                    title: Text(row.name ?? ''),
                    subtitle: Text(row.filePath ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: _selected?.id == row.id,
                    enabled: enabled,
                    onTap:
                        enabled ? () => setState(() => _selected = row) : null,
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          if (compact)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  fields[i],
                ],
              ],
            )
          else
            Row(children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: fields[i]),
              ],
            ]),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          _draft(rippleInsert: false, autoLane: false),
                        ),
                child: Text(l10n.workbenchTimelineAdd),
              ),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          _draft(rippleInsert: false, autoLane: true),
                        ),
                child: Text(l10n.workbenchTimelineAutoLayerAdd),
              ),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          _draft(rippleInsert: true, autoLane: false),
                        ),
                child: Text(l10n.workbenchTimelineRippleInsert),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditTimelineClipDialog extends StatefulWidget {
  final TimelineClipRow clip;

  const _EditTimelineClipDialog({required this.clip});

  @override
  State<_EditTimelineClipDialog> createState() =>
      _EditTimelineClipDialogState();
}

class _EditTimelineClipDialogState extends State<_EditTimelineClipDialog> {
  late final TextEditingController _laneCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _opacityCtrl;

  @override
  void initState() {
    super.initState();
    _laneCtrl = TextEditingController(text: widget.clip.lane.toString());
    _startCtrl = TextEditingController(text: widget.clip.startMs.toString());
    _durationCtrl = TextEditingController(
      text: widget.clip.durationMs?.toString() ?? '',
    );
    _opacityCtrl = TextEditingController(
      text: (widget.clip.opacity * 100).round().toString(),
    );
  }

  @override
  void dispose() {
    _laneCtrl.dispose();
    _startCtrl.dispose();
    _durationCtrl.dispose();
    _opacityCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final opacityPercent =
        (double.tryParse(_opacityCtrl.text.trim()) ?? widget.clip.opacity * 100)
            .clamp(0, 100)
            .toDouble();
    Navigator.of(context).pop(_TimelineClipPropertyDraft(
      lane: int.tryParse(_laneCtrl.text.trim()) ?? widget.clip.lane,
      startMs: int.tryParse(_startCtrl.text.trim()) ?? widget.clip.startMs,
      durationMs: int.tryParse(_durationCtrl.text.trim()),
      opacity: opacityPercent / 100,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 480;
    final fields = [
      TextField(
        key: const ValueKey('workbench-timeline-edit-lane-input'),
        controller: _laneCtrl,
        decoration: InputDecoration(labelText: l10n.workbenchTimelineLayer),
        keyboardType: TextInputType.number,
      ),
      TextField(
        key: const ValueKey('workbench-timeline-edit-start-input'),
        controller: _startCtrl,
        decoration: InputDecoration(labelText: l10n.workbenchTimelineStartMs),
        keyboardType: TextInputType.number,
      ),
      TextField(
        key: const ValueKey('workbench-timeline-edit-duration-input'),
        controller: _durationCtrl,
        decoration:
            InputDecoration(labelText: l10n.workbenchTimelineDurationMs),
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _submit(),
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  fields[i],
                ],
              ],
            )
          else
            Row(children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: fields[i]),
              ],
            ]),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('workbench-timeline-edit-opacity-input'),
            controller: _opacityCtrl,
            decoration:
                InputDecoration(labelText: l10n.workbenchTimelineOpacity),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('workbench-timeline-edit-confirm'),
                onPressed: _submit,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineLane extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Widget> children;

  const _TimelineLane({
    required this.label,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 84,
        child: Row(children: [
          Icon(icon, size: 14, color: df.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: df.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Row(children: children),
    ]);
  }
}

class _SplitTimelineClipDialog extends StatefulWidget {
  final int defaultPlayheadMs;

  const _SplitTimelineClipDialog({
    required this.defaultPlayheadMs,
  });

  @override
  State<_SplitTimelineClipDialog> createState() =>
      _SplitTimelineClipDialogState();
}

class _SplitTimelineClipDialogState extends State<_SplitTimelineClipDialog> {
  late final TextEditingController _playheadCtrl;

  @override
  void initState() {
    super.initState();
    _playheadCtrl =
        TextEditingController(text: widget.defaultPlayheadMs.toString());
  }

  @override
  void dispose() {
    _playheadCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_playheadCtrl.text.trim());
    if (value == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('workbench-timeline-split-playhead-input'),
            controller: _playheadCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.workbenchTimelineSplitAtMs,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: DFTokens.s20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DFTokens.s8,
            runSpacing: DFTokens.s8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const ValueKey('workbench-timeline-split-confirm'),
                onPressed: _submit,
                child: Text(l10n.workbenchTimelineSplit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineClipDurationDialog extends StatefulWidget {
  final int defaultDurationMs;
  final Key inputKey;
  final Key confirmKey;

  const _TimelineClipDurationDialog({
    required this.defaultDurationMs,
    required this.inputKey,
    required this.confirmKey,
  });

  @override
  State<_TimelineClipDurationDialog> createState() =>
      _TimelineClipDurationDialogState();
}

class _TimelineClipDurationDialogState
    extends State<_TimelineClipDurationDialog> {
  late final TextEditingController _durationCtrl;

  @override
  void initState() {
    super.initState();
    _durationCtrl =
        TextEditingController(text: widget.defaultDurationMs.toString());
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_durationCtrl.text.trim());
    if (value == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: widget.inputKey,
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.workbenchTimelineDurationMs,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: DFTokens.s20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DFTokens.s8,
            runSpacing: DFTokens.s8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: widget.confirmKey,
                onPressed: _submit,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineClipStartDialog extends StatefulWidget {
  final int defaultStartMs;
  final Key inputKey;
  final Key confirmKey;

  const _TimelineClipStartDialog({
    required this.defaultStartMs,
    required this.inputKey,
    required this.confirmKey,
  });

  @override
  State<_TimelineClipStartDialog> createState() =>
      _TimelineClipStartDialogState();
}

class _TimelineClipStartDialogState extends State<_TimelineClipStartDialog> {
  late final TextEditingController _startCtrl;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: widget.defaultStartMs.toString());
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_startCtrl.text.trim());
    if (value == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: widget.inputKey,
            controller: _startCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.workbenchTimelineStartMs,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: DFTokens.s20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DFTokens.s8,
            runSpacing: DFTokens.s8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: widget.confirmKey,
                onPressed: _submit,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineClipLaneDialog extends StatefulWidget {
  final int defaultLane;
  final Key inputKey;
  final Key confirmKey;

  const _TimelineClipLaneDialog({
    required this.defaultLane,
    required this.inputKey,
    required this.confirmKey,
  });

  @override
  State<_TimelineClipLaneDialog> createState() =>
      _TimelineClipLaneDialogState();
}

class _TimelineClipLaneDialogState extends State<_TimelineClipLaneDialog> {
  late final TextEditingController _laneCtrl;

  @override
  void initState() {
    super.initState();
    _laneCtrl = TextEditingController(text: widget.defaultLane.toString());
  }

  @override
  void dispose() {
    _laneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_laneCtrl.text.trim());
    if (value == null) return;
    Navigator.of(context).pop(value < 1 ? 1 : value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: widget.inputKey,
            controller: _laneCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.workbenchTimelineLane,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: DFTokens.s20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DFTokens.s8,
            runSpacing: DFTokens.s8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: widget.confirmKey,
                onPressed: _submit,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _TimelineClipKind { video, audio }

enum _TimelineClipAction {
  split,
  duplicate,
  rippleDuplicate,
  rippleMove,
  splitAt,
  rippleTrimEnd,
  edit,
  delete,
  rippleDelete,
}

class _TimelineClip extends StatelessWidget {
  final int index;
  final StoryboardRow shot;
  final VideoTrackRow? track;
  final _TimelineClipKind kind;
  final String? audioName;

  const _TimelineClip({
    super.key,
    required this.index,
    required this.shot,
    required this.track,
    required this.kind,
    this.audioName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final seconds = _timelineSeconds(shot, track);
    final width = (72 + seconds * 7).clamp(96, 184).toDouble();
    final hasVideo = track?.selectVideoId != null;
    final hasAudio = audioName?.isNotEmpty == true;
    final isVideo = kind == _TimelineClipKind.video;
    final active = isVideo ? hasVideo : hasAudio;
    final label = isVideo
        ? (hasVideo ? l10n.workbenchSelected : l10n.workbenchTimelineUnselected)
        : (audioName ?? l10n.workbenchTimelineNoAudio);

    return Container(
      width: width,
      height: isVideo ? 48 : 36,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? df.primarySubtle : df.surfaceMuted,
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
        border: Border.all(color: active ? df.primary : df.stroke),
      ),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? df.primary.withValues(alpha: 0.14)
                : df.stroke.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          ),
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: active ? df.primary : df.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? df.textHi : df.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isVideo) ...[
              const SizedBox(height: 2),
              Text(
                l10n.workbenchDurationSeconds(seconds),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: df.textTertiary, fontSize: 10),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _TimelineAssetClip extends StatefulWidget {
  final TimelineClipRow clip;
  final bool selected;
  final List<int> snapAnchors;
  final List<int> snapPreviewOffsetsMs;
  final double dragPixelsPerTimeStep;
  final int dragTimeStepMs;
  final int snapThresholdMs;
  final ValueChanged<bool> onSelectedChanged;
  final ValueChanged<Offset> onDragCommit;
  final ValueChanged<Offset> onTrimStartCommit;
  final ValueChanged<Offset> onTrimEndCommit;
  final VoidCallback onSplit;
  final VoidCallback onDuplicate;
  final VoidCallback onRippleDuplicate;
  final VoidCallback onRippleMove;
  final VoidCallback onSplitAt;
  final VoidCallback onRippleTrimEnd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRippleDelete;

  const _TimelineAssetClip({
    required this.clip,
    required this.selected,
    required this.snapAnchors,
    required this.snapPreviewOffsetsMs,
    required this.dragPixelsPerTimeStep,
    required this.dragTimeStepMs,
    required this.snapThresholdMs,
    required this.onSelectedChanged,
    required this.onDragCommit,
    required this.onTrimStartCommit,
    required this.onTrimEndCommit,
    required this.onSplit,
    required this.onDuplicate,
    required this.onRippleDuplicate,
    required this.onRippleMove,
    required this.onSplitAt,
    required this.onRippleTrimEnd,
    required this.onEdit,
    required this.onDelete,
    required this.onRippleDelete,
  });

  @override
  State<_TimelineAssetClip> createState() => _TimelineAssetClipState();
}

double _timelineAssetClipWidth(TimelineClipRow clip) {
  final durationSec = ((clip.durationMs ?? 1000) / 1000).ceil();
  return (96 + durationSec * 7).clamp(160, 220).toDouble();
}

class _TimelineAssetClipState extends State<_TimelineAssetClip> {
  Offset _dragDelta = Offset.zero;
  Alignment? _snapGuideAlignment;

  @override
  void didUpdateWidget(covariant _TimelineAssetClip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.startMs != widget.clip.startMs ||
        oldWidget.clip.lane != widget.clip.lane ||
        oldWidget.clip.durationMs != widget.clip.durationMs) {
      _dragDelta = Offset.zero;
      _snapGuideAlignment = null;
    }
  }

  void _resetDrag() {
    setState(() {
      _dragDelta = Offset.zero;
      _snapGuideAlignment = null;
    });
  }

  void _accumulateDrag(DragUpdateDetails details) {
    setState(() {
      _dragDelta += details.delta;
      _snapGuideAlignment = _activeSnapGuideAlignment();
    });
  }

  void _commitDrag(ValueChanged<Offset> commit) {
    final delta = _dragDelta;
    _clearDragPreview();
    commit(delta);
  }

  void _hideSnapGuide() {
    if (!mounted || _snapGuideAlignment == null) return;
    setState(() {
      _snapGuideAlignment = null;
    });
  }

  void _hideSnapGuideAfterPointerUp() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _hideSnapGuide());
  }

  void _clearDragPreview() {
    if (!mounted) return;
    setState(() {
      _dragDelta = Offset.zero;
      _snapGuideAlignment = null;
    });
  }

  Alignment? _activeSnapGuideAlignment() {
    final timeSteps = (_dragDelta.dx / widget.dragPixelsPerTimeStep).round();
    if (timeSteps == 0) return null;
    final duration = widget.clip.durationMs ?? 1000;
    final candidateStart =
        widget.clip.startMs + timeSteps * widget.dragTimeStepMs;
    for (final offset in widget.snapPreviewOffsetsMs) {
      if (_hasNearbySnapAnchor(candidateStart + offset)) {
        return _snapGuideAlignmentForOffset(offset, duration);
      }
    }
    return null;
  }

  Alignment _snapGuideAlignmentForOffset(int offsetMs, int durationMs) {
    if (offsetMs <= 0) return Alignment.centerLeft;
    if (offsetMs >= durationMs) return Alignment.centerRight;
    return offsetMs <= durationMs / 2
        ? Alignment.centerLeft
        : Alignment.centerRight;
  }

  bool _hasNearbySnapAnchor(int value) {
    for (final anchor in widget.snapAnchors) {
      final distance = (value - anchor).abs();
      if (distance <= widget.snapThresholdMs) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final clip = widget.clip;
    final width = _timelineAssetClipWidth(clip);
    final opacityPercent = (clip.opacity * 100).round();
    final opacitySuffix = opacityPercent >= 100 ? '' : ' · $opacityPercent%';

    return Container(
      width: width,
      height: 48,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: df.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
        border: Border.all(color: df.success.withValues(alpha: 0.65)),
      ),
      child: SizedBox.expand(
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Row(children: [
              Icon(Icons.layers_outlined, size: 16, color: df.success),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clip.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: df.textHi,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'L${clip.lane} · ${clip.startMs}ms'
                        '${clip.durationMs != null ? ' · ${clip.durationMs}ms' : ''}'
                        '$opacitySuffix',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: df.textTertiary, fontSize: 10),
                      ),
                    ]),
              ),
            ]),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: 0,
            child: Listener(
              onPointerUp: (_) => _hideSnapGuideAfterPointerUp(),
              onPointerCancel: (_) => _clearDragPreview(),
              child: GestureDetector(
                key: ValueKey('workbench-timeline-clip-${clip.id}'),
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => _resetDrag(),
                onPanUpdate: _accumulateDrag,
                onPanEnd: (_) => _commitDrag(widget.onDragCommit),
                onPanCancel: _clearDragPreview,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (_snapGuideAlignment != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: _snapGuideAlignment!,
                  child: Container(
                    key: ValueKey('workbench-timeline-snap-guide-${clip.id}'),
                    width: 2,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: df.primary,
                      borderRadius: BorderRadius.circular(DFTokens.radiusChip),
                      boxShadow: [
                        BoxShadow(
                          color: df.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          _TimelineResizeHandle(
            handleKey:
                ValueKey('workbench-timeline-clip-resize-start-${clip.id}'),
            alignment: Alignment.centerLeft,
            color: df.success,
            onDragStart: _resetDrag,
            onDragUpdate: _accumulateDrag,
            onDragEnd: () => _commitDrag(widget.onTrimStartCommit),
          ),
          _TimelineResizeHandle(
            handleKey:
                ValueKey('workbench-timeline-clip-resize-end-${clip.id}'),
            alignment: Alignment.centerRight,
            color: df.success,
            onDragStart: _resetDrag,
            onDragUpdate: _accumulateDrag,
            onDragEnd: () => _commitDrag(widget.onTrimEndCommit),
          ),
          Positioned(
            left: 18,
            top: 6,
            child: SizedBox(
              width: 24,
              height: 24,
              child: InkWell(
                key: ValueKey('workbench-timeline-clip-select-${clip.id}'),
                borderRadius: BorderRadius.circular(DFTokens.radiusChip),
                onTap: () => widget.onSelectedChanged(!widget.selected),
                child: Icon(
                  widget.selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: widget.selected ? df.primary : df.textTertiary,
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 0,
            child: SizedBox(
              width: 28,
              height: 24,
              child: PopupMenuButton<_TimelineClipAction>(
                key: ValueKey('workbench-timeline-clip-menu-${clip.id}'),
                padding: EdgeInsets.zero,
                tooltip: context.l10n.workbenchTimelineClipActions,
                icon:
                    Icon(Icons.more_horiz_rounded, size: 16, color: df.success),
                onSelected: (action) {
                  switch (action) {
                    case _TimelineClipAction.split:
                      widget.onSplit();
                      break;
                    case _TimelineClipAction.duplicate:
                      widget.onDuplicate();
                      break;
                    case _TimelineClipAction.rippleDuplicate:
                      widget.onRippleDuplicate();
                      break;
                    case _TimelineClipAction.rippleMove:
                      widget.onRippleMove();
                      break;
                    case _TimelineClipAction.splitAt:
                      widget.onSplitAt();
                      break;
                    case _TimelineClipAction.rippleTrimEnd:
                      widget.onRippleTrimEnd();
                      break;
                    case _TimelineClipAction.edit:
                      widget.onEdit();
                      break;
                    case _TimelineClipAction.delete:
                      widget.onDelete();
                      break;
                    case _TimelineClipAction.rippleDelete:
                      widget.onRippleDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: ValueKey('workbench-timeline-clip-split-${clip.id}'),
                    value: _TimelineClipAction.split,
                    child: Text(context.l10n.workbenchTimelineSplitMidpoint),
                  ),
                  PopupMenuItem(
                    key: ValueKey(
                        'workbench-timeline-clip-duplicate-${clip.id}'),
                    value: _TimelineClipAction.duplicate,
                    child: Text(context.l10n.workbenchTimelineDuplicate),
                  ),
                  PopupMenuItem(
                    key: ValueKey(
                        'workbench-timeline-clip-ripple-duplicate-${clip.id}'),
                    value: _TimelineClipAction.rippleDuplicate,
                    child: Text(context.l10n.workbenchTimelineRippleDuplicate),
                  ),
                  PopupMenuItem(
                    key: ValueKey(
                        'workbench-timeline-clip-ripple-move-${clip.id}'),
                    value: _TimelineClipAction.rippleMove,
                    child: Text(context.l10n.workbenchTimelineRippleMove),
                  ),
                  PopupMenuItem(
                    key:
                        ValueKey('workbench-timeline-clip-split-at-${clip.id}'),
                    value: _TimelineClipAction.splitAt,
                    child: Text(context.l10n.workbenchTimelineSplitAt),
                  ),
                  PopupMenuItem(
                    key: ValueKey(
                        'workbench-timeline-clip-ripple-trim-end-${clip.id}'),
                    value: _TimelineClipAction.rippleTrimEnd,
                    child: Text(context.l10n.workbenchTimelineRippleTrimEnd),
                  ),
                  PopupMenuItem(
                    key: ValueKey('workbench-timeline-clip-edit-${clip.id}'),
                    value: _TimelineClipAction.edit,
                    child: Text(context.l10n.workbenchTimelineEditClip),
                  ),
                  PopupMenuItem(
                    key: ValueKey('workbench-timeline-clip-delete-${clip.id}'),
                    value: _TimelineClipAction.delete,
                    child: Text(context.l10n.workbenchTimelineDelete),
                  ),
                  PopupMenuItem(
                    key: ValueKey(
                        'workbench-timeline-clip-ripple-delete-${clip.id}'),
                    value: _TimelineClipAction.rippleDelete,
                    child: Text(context.l10n.workbenchTimelineRippleDelete),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TimelineResizeHandle extends StatelessWidget {
  final Key handleKey;
  final Alignment alignment;
  final Color color;
  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  const _TimelineResizeHandle({
    required this.handleKey,
    required this.alignment,
    required this.color,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: handleKey,
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart(),
            onPanUpdate: onDragUpdate,
            onPanEnd: (_) => onDragEnd(),
            onPanCancel: onDragEnd,
            child: SizedBox(
              width: 14,
              height: double.infinity,
              child: Center(
                child: Container(
                  width: 2,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int _timelineSeconds(StoryboardRow shot, VideoTrackRow? track) {
  final fromTrack = track?.duration;
  if (fromTrack != null && fromTrack > 0) return fromTrack;
  final fromShot = int.tryParse((shot.duration ?? '').trim());
  if (fromShot != null && fromShot > 0) return fromShot;
  return 4;
}

class _ShotRow extends ConsumerStatefulWidget {
  final int projectId;
  final StoryboardRow shot;
  final int index;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Widget dragHandle;
  const _ShotRow({
    required this.projectId,
    required this.shot,
    required this.index,
    required this.selected,
    required this.onSelected,
    required this.dragHandle,
  });

  @override
  ConsumerState<_ShotRow> createState() => _ShotRowState();
}

class _ShotRowState extends ConsumerState<_ShotRow> {
  bool _generatingPrompt = false;
  // 懒建/编辑后回填的 trackId：widget.shot 是父级快照，其 trackId 在本次编辑后可能仍为
  // null（父未重建）。本地缓存保证时长/提示词编辑立即在本行可见。
  int? _localTrackId;
  int? _localAudioAssetId;

  int? get _effectiveTrackId => widget.shot.trackId ?? _localTrackId;
  int? get _effectiveAudioAssetId =>
      _localAudioAssetId ?? widget.shot.audioAssetId;

  Future<void> _generatePrompt() async {
    setState(() => _generatingPrompt = true);
    try {
      final engine = ref.read(engineProvider);
      await engine.generateVideoPrompt(widget.shot.id);
      _localTrackId = engine.ensureTrackForStoryboard(widget.shot.id);
    } catch (e) {
      if (mounted) _showWorkbenchSnackBar(context, localizeError(context, e));
    } finally {
      if (mounted) setState(() => _generatingPrompt = false);
    }
  }

  Future<void> _generateOne() async {
    final engine = ref.read(engineProvider);
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'video_generation',
      description: context.l10n.workbenchGenerateVideo,
    )) {
      return;
    }
    if (!mounted) return;
    engine.batchGenerateVideos(widget.projectId, [widget.shot.id]);
    _showWorkbenchSnackBar(context, context.l10n.workbenchGenerateVideo);
  }

  Future<void> _pickClip() async {
    final l10n = context.l10n;
    final engine = ref.read(engineProvider);
    final clips =
        engine.getAssets(widget.projectId, type: 'clip', limit: 100).data;
    final clip = await showDFAdaptiveDialog<AssetRow>(
      context,
      title: l10n.workbenchPickClipTitle,
      desktopWidthFactor: 0.42,
      builder: (c) => _PickClipAssetList(clips: clips),
    );
    if (clip == null || !mounted) return;
    try {
      final trackId = engine.ensureTrackForStoryboard(widget.shot.id);
      engine.attachClipToTrack(trackId, clip.id);
      setState(() => _localTrackId = trackId);
    } catch (e) {
      if (mounted) _showWorkbenchSnackBar(context, localizeError(context, e));
    }
  }

  void _bindAudio(int value) {
    final audioAssetId = value == 0 ? null : value;
    ref.read(engineProvider).bindStoryboardAudio(
          storyboardId: widget.shot.id,
          audioAssetId: audioAssetId,
        );
    setState(() => _localAudioAssetId = audioAssetId);
  }

  void _updateTransition(String value) {
    final engine = ref.read(engineProvider);
    final trackId = engine.ensureTrackForStoryboard(widget.shot.id);
    engine.updateVideoTransition(trackId, value);
    setState(() => _localTrackId = trackId);
  }

  void _updateFilter(String value) {
    final engine = ref.read(engineProvider);
    final trackId = engine.ensureTrackForStoryboard(widget.shot.id);
    engine.updateVideoFilter(trackId, value);
    setState(() => _localTrackId = trackId);
  }

  /// 手动编辑运镜提示词（懒建轨道后写入 o_videoTrack.prompt）。
  Future<void> _editPrompt(String current) async {
    final l10n = context.l10n;
    final saved = await showDFAdaptiveDialog<String>(
      context,
      title: l10n.workbenchEditPromptTitle,
      desktopWidthFactor: 0.42,
      builder: (c) => _TextEditDialog(
        initial: current,
        hint: l10n.workbenchPromptFieldHint,
        multiline: true,
      ),
    );
    if (saved == null || !mounted) return;
    final engine = ref.read(engineProvider);
    final trackId = engine.ensureTrackForStoryboard(widget.shot.id);
    engine.updateVideoPrompt(trackId, saved.trim());
    setState(() => _localTrackId = trackId);
  }

  /// 编辑本镜时长（秒）。保存时空/非正值清空为未设置；取消不改动。
  Future<void> _editDuration(int? current) async {
    final l10n = context.l10n;
    final saved = await showDFAdaptiveDialog<String>(
      context,
      title: l10n.workbenchEditDurationTitle,
      desktopWidthFactor: 0.36,
      builder: (c) => _TextEditDialog(
        initial: current != null ? '$current' : '',
        label: l10n.workbenchDurationFieldLabel,
        numeric: true,
      ),
    );
    if (saved == null || !mounted) return; // 取消：不改动
    final engine = ref.read(engineProvider);
    final trackId = engine.ensureTrackForStoryboard(widget.shot.id);
    engine.updateVideoDuration(trackId, int.tryParse(saved.trim()));
    setState(() => _localTrackId = trackId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final engine = ref.watch(engineProvider);
    final trackId = _effectiveTrackId;
    final track = trackId != null ? engine.track(trackId) : null;
    final audioPool = engine.audioPool(widget.projectId);
    final selectedAudioId = _effectiveAudioAssetId;
    final audioValue = audioPool.any((audio) => audio.id == selectedAudioId)
        ? selectedAudioId!
        : 0;
    final transitionOptions = [
      _NleOption('', l10n.workbenchTransitionNone),
      _NleOption('fade', l10n.workbenchTransitionFade),
      _NleOption('dissolve', l10n.workbenchTransitionDissolve),
      _NleOption('whip_pan', l10n.workbenchTransitionWhipPan),
    ];
    final filterOptions = [
      _NleOption('', l10n.workbenchFilterNone),
      _NleOption('cinematic', l10n.workbenchFilterCinematic),
      _NleOption('warm', l10n.workbenchFilterWarm),
      _NleOption('cool', l10n.workbenchFilterCool),
      _NleOption('vintage', l10n.workbenchFilterVintage),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.stroke),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 60,
          height: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Checkbox(
                key: ValueKey('workbench-shot-check-${widget.shot.id}'),
                value: widget.selected,
                onChanged: (value) => widget.onSelected(value ?? false),
              ),
              widget.dragHandle,
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 100,
          height: 100,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: df.surfaceMuted,
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
          ),
          child: widget.shot.filePath != null
              ? Image.file(File(engine.mediaAbsPath(widget.shot.filePath!)),
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) =>
                      Icon(Icons.broken_image_outlined, color: df.textTertiary))
              : Icon(Icons.image_not_supported_outlined,
                  color: df.textTertiary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('S${widget.index + 1}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              // 本镜时长（可编辑）：优先展示视频轨时长，否则「未设置」。
              _DurationPill(
                seconds: track?.duration,
                onTap: () => _editDuration(track?.duration),
              ),
            ]),
            const SizedBox(height: 4),
            // 运镜提示词：可点击编辑（此前只读）。空时显示占位。
            InkWell(
              onTap: () =>
                  _editPrompt(track?.prompt ?? widget.shot.videoDesc ?? ''),
              borderRadius: BorderRadius.circular(DFTokens.radiusControl),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        (track?.prompt?.isNotEmpty == true)
                            ? track!.prompt!
                            : (widget.shot.videoDesc?.isNotEmpty == true
                                ? widget.shot.videoDesc!
                                : l10n.workbenchPromptEmpty),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: df.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 14, color: df.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _NleOptionChip(
                icon: Icons.blur_on_outlined,
                value: track?.transition ?? '',
                options: transitionOptions,
                onSelected: _updateTransition,
              ),
              _NleOptionChip(
                icon: Icons.tune_outlined,
                value: track?.filter ?? '',
                options: filterOptions,
                onSelected: _updateFilter,
              ),
            ]),
            const SizedBox(height: 8),
            if (audioPool.isNotEmpty || selectedAudioId != null) ...[
              _ShotAudioPicker(
                value: audioValue,
                options: audioPool,
                onChanged: _bindAudio,
              ),
              const SizedBox(height: 8),
            ],
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _generatingPrompt ? null : _generatePrompt,
                icon: _generatingPrompt
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 14),
                label: Text(l10n.workbenchGeneratePrompt,
                    style: const TextStyle(fontSize: 12)),
              ),
              FilledButton.icon(
                onPressed: _generateOne,
                icon: const Icon(Icons.videocam_outlined, size: 14),
                label: Text(l10n.workbenchGenerateVideo,
                    style: const TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                onPressed: _pickClip,
                icon: const Icon(Icons.video_library_outlined, size: 14),
                label: Text(l10n.workbenchPickClip,
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
            if (track != null && track.candidates.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in track.candidates)
                  _VideoCandidateChip(
                    trackId: track.id,
                    video: v,
                    selected: v.id == track.selectVideoId,
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _PickClipAssetList extends StatelessWidget {
  final List<AssetRow> clips;

  const _PickClipAssetList({required this.clips});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (clips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DFTokens.s20),
        child: DFEmpty(text: l10n.workbenchNoClipAssets),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: DFTokens.s8),
      itemCount: clips.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final row = clips[i];
        final enabled = row.filePath?.isNotEmpty == true;
        return ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: Text(row.name ?? ''),
          subtitle: Text(
            row.filePath ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          enabled: enabled,
          onTap: enabled ? () => Navigator.pop(context, row) : null,
        );
      },
    );
  }
}

class _ShotAudioPicker extends StatelessWidget {
  final int value;
  final List<({int id, String name})> options;
  final ValueChanged<int> onChanged;

  const _ShotAudioPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return Row(children: [
      Icon(Icons.graphic_eq_outlined, size: 14, color: df.textTertiary),
      const SizedBox(width: 6),
      Text(
        l10n.workbenchShotAudioLabel,
        style: TextStyle(fontSize: 12, color: df.textSecondary),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: df.surfaceMuted,
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            border: Border.all(color: df.stroke),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isDense: true,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(l10n.workbenchShotAudioNone),
                ),
                for (final audio in options)
                  DropdownMenuItem(
                    value: audio.id,
                    child: Text(audio.name),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ),
    ]);
  }
}

class _NleOption {
  final String value;
  final String label;
  const _NleOption(this.value, this.label);
}

class _NleOptionChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final List<_NleOption> options;
  final ValueChanged<String> onSelected;

  const _NleOptionChip({
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    return PopupMenuButton<String>(
      tooltip: selected.label,
      initialValue: selected.value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.value,
            child: Text(option.label),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          border: Border.all(color: df.stroke),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: df.textTertiary),
          const SizedBox(width: 5),
          Text(
            selected.label,
            style: TextStyle(fontSize: 11, color: df.textSecondary),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down_rounded, size: 16, color: df.textTertiary),
        ]),
      ),
    );
  }
}

/// 通用文本编辑表单（自持 TextEditingController，在自身 dispose 里释放，避免
/// 在外层 await 后同步 dispose 导致退场动画期间控制器被误用的崩溃）。返回 trim 前的
/// 原文（保存）或 null（取消）。
class _TextEditDialog extends StatefulWidget {
  final String initial;
  final String? hint;
  final String? label;
  final bool multiline;
  final bool numeric;
  const _TextEditDialog({
    required this.initial,
    this.hint,
    this.label,
    this.multiline = false,
    this.numeric = false,
  });

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DFTokens.s20,
        DFTokens.s16,
        DFTokens.s20,
        DFTokens.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('workbench-text-edit-input'),
            controller: _controller,
            autofocus: true,
            maxLines: widget.multiline ? 5 : 1,
            minLines: widget.multiline ? 3 : 1,
            keyboardType: widget.numeric ? TextInputType.number : null,
            decoration: InputDecoration(
              hintText: widget.hint,
              labelText: widget.label,
            ),
          ),
          const SizedBox(height: DFTokens.s20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: DFTokens.s8,
            runSpacing: DFTokens.s8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _controller.text),
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 本镜时长小药丸（点击编辑）。
class _DurationPill extends StatelessWidget {
  final int? seconds;
  final VoidCallback onTap;
  const _DurationPill({required this.seconds, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DFTokens.radiusChip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          border: Border.all(color: df.stroke),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined, size: 12, color: df.textTertiary),
          const SizedBox(width: 4),
          Text(
            seconds != null
                ? l10n.workbenchDurationSeconds(seconds!)
                : l10n.workbenchDurationUnset,
            style: TextStyle(fontSize: 11, color: df.textSecondary),
          ),
        ]),
      ),
    );
  }
}

class _VideoCandidateChip extends ConsumerWidget {
  final int trackId;
  final VideoRow video;
  final bool selected;
  const _VideoCandidateChip(
      {required this.trackId, required this.video, required this.selected});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDFAdaptiveDialog<bool>(
      context,
      title: l10n.workbenchDeleteCandidate,
      desktopWidthFactor: .36,
      builder: (c) => _ConfirmActionBody(
        message: l10n.workbenchDeleteCandidateConfirm,
        confirmLabel: l10n.commonDelete,
        onCancel: () => Navigator.pop(c, false),
        onConfirm: () => Navigator.pop(c, true),
      ),
    );
    if (ok == true) ref.read(engineProvider).deleteVideo(video.id);
  }

  void _saveToAssets(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    try {
      final clipAssetId = ref.read(engineProvider).saveVideoCandidateAsClip(
            video.id,
            name: l10n.workbenchCandidateClipName(video.id),
          );
      _showWorkbenchSnackBar(context, l10n.workbenchSavedToAssets(clipAssetId));
    } catch (e) {
      _showWorkbenchSnackBar(context, localizeError(context, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    final compact = MediaQuery.sizeOf(context).width < 480;
    Widget label;
    switch (video.state) {
      case vtGenerating:
        label = const StatusChip('running', dense: true);
        break;
      case vtFailed:
        label = StatusChip(
          'failed',
          dense: true,
          errorTooltip: localizeReason(l10n, video.errorReason),
        );
        break;
      default:
        label = Text(
            selected ? l10n.workbenchSelected : l10n.workbenchSelectCandidate,
            style: const TextStyle(fontSize: 11));
    }
    final canPlay =
        video.state == vtDone && (video.filePath?.isNotEmpty ?? false);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      decoration: BoxDecoration(
        color: selected ? df.primarySubtle : df.surfaceMuted,
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
        border: Border.all(color: selected ? df.primary : df.stroke),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // 播放（tap-to-play 弹窗）
        if (canPlay)
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: l10n.workbenchPlayVideo,
            icon: Icon(Icons.play_circle_outline, size: 18, color: df.primary),
            onPressed: () => showVideoPlayerDialog(
              context,
              absPath: ref.read(engineProvider).mediaAbsPath(video.filePath!),
            ),
          ),
        if (canPlay)
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: l10n.workbenchSaveCandidateToAssets,
            icon: Icon(Icons.library_add_outlined, size: 17, color: df.primary),
            onPressed: () => _saveToAssets(context, ref),
          ),
        // 选为正片（窄屏用图标避免候选 chip 横向溢出）。
        if (compact)
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: selected
                ? l10n.workbenchSelected
                : l10n.workbenchSelectCandidate,
            icon: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: selected ? df.primary : df.textTertiary,
            ),
            onPressed: video.state == vtDone
                ? () => ref.read(engineProvider).selectVideo(trackId, video.id)
                : null,
          )
        else
          InkWell(
            onTap: video.state == vtDone
                ? () => ref.read(engineProvider).selectVideo(trackId, video.id)
                : null,
            borderRadius: BorderRadius.circular(DFTokens.radiusChip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: label,
            ),
          ),
        // 显式删除按钮（此前只有隐藏的 onLongPress）
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          tooltip: l10n.workbenchDeleteCandidate,
          icon: Icon(Icons.delete_outline, size: 16, color: df.textTertiary),
          onPressed: () => _confirmDelete(context, ref),
        ),
      ]),
    );
  }
}
