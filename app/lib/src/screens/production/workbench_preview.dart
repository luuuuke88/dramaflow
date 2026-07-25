import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/assets.dart';
import '../../engine/engine.dart';
import '../../engine/storyboard.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import 'workbench_preview_controller.dart';
import '../../widgets/df_toast.dart';

Future<void> showWorkbenchQuickPreview(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  required int scriptId,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => WorkbenchQuickPreviewPage(
        projectId: projectId,
        scriptId: scriptId,
      ),
    ),
  );
}

class WorkbenchQuickPreviewPage extends ConsumerStatefulWidget {
  final int projectId;
  final int scriptId;
  final bool embedded;
  final String videoRatio;

  const WorkbenchQuickPreviewPage({
    super.key,
    required this.projectId,
    required this.scriptId,
    this.embedded = false,
    this.videoRatio = '16:9',
  });

  @override
  ConsumerState<WorkbenchQuickPreviewPage> createState() =>
      _WorkbenchQuickPreviewPageState();
}

class _WorkbenchQuickPreviewPageState
    extends ConsumerState<WorkbenchQuickPreviewPage>
    with WidgetsBindingObserver {
  late final List<_PreviewShot> _shots;
  late final PreviewTimelineController _timeline;
  final Set<int> _selectedShotIds = {};
  final Stopwatch _playClock = Stopwatch();
  Timer? _ticker;
  var _isExporting = false;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(engineProvider);
    final rows = engine.storyboards(widget.scriptId);
    final assetIds = <int>{for (final row in rows) ...row.assetIds};
    final assets = {
      for (final asset in engine.assetsByIds(assetIds.toList()))
        asset.id: asset,
    };
    _shots = [
      for (final row in rows) _PreviewShot.fromRow(row, engine, assets),
    ];
    _timeline = PreviewTimelineController([
      for (final shot in _shots) shot.duration,
    ]);
    _timeline.addListener(_syncPlaybackTicker);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeline.removeListener(_syncPlaybackTicker);
    _ticker?.cancel();
    _playClock.stop();
    _timeline.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _timeline.pause();
  }

  void _syncPlaybackTicker() {
    if (_timeline.isPlaying) {
      if (!_playClock.isRunning) {
        _playClock
          ..reset()
          ..start();
      }
      _ticker ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
        final elapsed = _playClock.elapsed;
        _playClock
          ..reset()
          ..start();
        _timeline.tick(elapsed);
      });
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    _playClock
      ..stop()
      ..reset();
  }

  void _toggleSelected(int shotId, bool selected) {
    setState(() {
      if (selected) {
        _selectedShotIds.add(shotId);
      } else {
        _selectedShotIds.remove(shotId);
      }
    });
  }

  void _toggleAllSelected(bool selected) {
    setState(() {
      if (selected) {
        _selectedShotIds.addAll(_shots.map((shot) => shot.id));
      } else {
        _selectedShotIds.clear();
      }
    });
  }

  Future<void> _exportSelected() async {
    if (_isExporting) return;
    final l10n = context.l10n;
    final fileName = l10n.workbenchPreviewZipFileName;
    if (_selectedShotIds.isEmpty) {
      _toast(l10n.storyboardExportNoImages);
      return;
    }
    try {
      final engine = ref.read(engineProvider);
      final selectedIds = Set<int>.of(_selectedShotIds);
      if (engine.storyboardImageExportFileCount(widget.scriptId, selectedIds) ==
          0) {
        _toast(l10n.storyboardExportNoImages);
        return;
      }
      final location = await fs.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          fs.XTypeGroup(label: 'zip', extensions: ['zip']),
        ],
      );
      if (location == null) return;
      setState(() => _isExporting = true);
      final count = await engine.exportStoryboardImagesToFile(
        widget.scriptId,
        selectedIds,
        location.path,
      );
      if (!mounted) return;
      if (count == 0) {
        _toast(l10n.storyboardExportNoImages);
      } else {
        _toast(l10n.workbenchPreviewExported(count));
      }
    } catch (error) {
      if (mounted) _toast(localizeError(context, error));
    } finally {
      if (mounted && _isExporting) setState(() => _isExporting = false);
    }
  }

  void _toast(String message) {
    showDFToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = _shots.isEmpty
        ? Center(child: Text(l10n.workbenchNoShots))
        : AnimatedBuilder(
            animation: _timeline,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final stage = _buildStage(context);
                final details = _buildDetails(context);
                final compact = constraints.maxWidth < 840;
                return SingleChildScrollView(
                  key: const ValueKey('workbench-preview-scroll'),
                  padding: const EdgeInsets.all(DFTokens.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (compact) ...[
                        stage,
                        const SizedBox(height: DFTokens.s16),
                        details,
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: stage),
                            const SizedBox(width: DFTokens.s20),
                            Expanded(flex: 3, child: details),
                          ],
                        ),
                      const SizedBox(height: DFTokens.s20),
                      _buildShotControls(context),
                    ],
                  ),
                );
              },
            ),
          );
    if (widget.embedded) {
      return KeyedSubtree(
        key: const ValueKey('workbench-preview-embedded'),
        child: body,
      );
    }
    return Scaffold(
      key: const ValueKey('workbench-preview-page'),
      appBar: AppBar(title: Text(l10n.workbenchQuickPreview)),
      body: body,
    );
  }

  Widget _buildStage(BuildContext context) {
    final shot = _shots[_timeline.currentIndex];
    final df = context.df;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          key: ValueKey('workbench-preview-stage-${widget.videoRatio}'),
          aspectRatio: _aspectRatioFor(widget.videoRatio),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: df.surfaceMuted,
              borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DFTokens.radiusControl),
              child: shot.imageAbsPath == null
                  ? _PreviewEmptyImage(
                      text: context.l10n.workbenchPreviewNoImage)
                  : Image.file(
                      File(shot.imageAbsPath!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _PreviewEmptyImage(
                        text: context.l10n.workbenchPreviewNoImage,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: DFTokens.s12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('workbench-preview-previous'),
              tooltip: context.l10n.workbenchPreviewPrevious,
              onPressed:
                  _timeline.currentIndex == 0 ? null : _timeline.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('workbench-preview-play'),
              onPressed: _timeline.togglePlay,
              icon: Icon(_timeline.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              label: Text(_timeline.isPlaying
                  ? context.l10n.workbenchPreviewPause
                  : context.l10n.workbenchPreviewPlay),
            ),
            IconButton(
              key: const ValueKey('workbench-preview-next'),
              tooltip: context.l10n.workbenchPreviewNext,
              onPressed: _timeline.currentIndex >= _shots.length - 1
                  ? null
                  : _timeline.next,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        Row(
          children: [
            Text(_formatTime(_timeline.totalElapsed),
                style: DFTokens.caption12),
            Expanded(
              child: Slider(
                value: _timeline.totalElapsed.inMilliseconds.toDouble(),
                max: math
                    .max(1, _timeline.totalDuration.inMilliseconds)
                    .toDouble(),
                onChangeStart: (_) => _timeline.pause(),
                onChanged: (value) =>
                    _timeline.seek(Duration(milliseconds: value.round())),
              ),
            ),
            Text(_formatTime(_timeline.totalDuration),
                style: DFTokens.caption12),
          ],
        ),
        _buildSegments(context),
      ],
    );
  }

  double _aspectRatioFor(String ratio) => switch (ratio.trim()) {
        '1:1' => 1,
        '9:16' => 9 / 16,
        _ => 16 / 9,
      };

  Widget _buildSegments(BuildContext context) {
    final df = context.df;
    return Row(
      children: [
        for (final entry in _shots.indexed)
          Expanded(
            flex: math.max(1, entry.$2.duration.inMilliseconds),
            child: SizedBox(
              key: ValueKey('workbench-preview-segment-${entry.$2.id}'),
              height: 48,
              child: Semantics(
                button: true,
                selected: entry.$1 == _timeline.currentIndex,
                label: '${context.l10n.workbenchQuickPreview} ${entry.$1 + 1}',
                child: InkWell(
                  onTap: () => _timeline.jumpTo(entry.$1),
                  child: Center(
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(
                        right: entry.$1 == _shots.length - 1 ? 0 : 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: entry.$1 < _timeline.currentIndex
                            ? df.primary
                            : entry.$1 == _timeline.currentIndex
                                ? df.primary.withValues(alpha: .55)
                                : df.stroke,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context) {
    final shot = _shots[_timeline.currentIndex];
    final l10n = context.l10n;
    final df = context.df;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: df.surfaceMuted,
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DFTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewDetailSection(
              title: l10n.workbenchPreviewStoryboardDescription,
              child: Text(
                '【${_timeline.currentIndex + 1}】${_displayOr(shot.videoDesc, l10n.workbenchPreviewNoDescription)}',
              ),
            ),
            _PreviewDetailSection(
              title: l10n.workbenchPreviewDuration,
              child: Text(
                  l10n.workbenchPreviewSeconds(_formatSeconds(shot.duration))),
            ),
            _PreviewDetailSection(
              title: l10n.workbenchPreviewRelatedAssets,
              child: shot.assets.isEmpty
                  ? Text(l10n.workbenchPreviewNoAssets)
                  : Wrap(
                      spacing: DFTokens.s8,
                      runSpacing: DFTokens.s8,
                      children: [
                        for (final asset in shot.assets)
                          Chip(
                            avatar: _PreviewAssetAvatar(
                              imageAbsPath: asset.imageAbsPath,
                            ),
                            label: Text(
                              '${asset.name}（${_assetTypeLabel(context, asset.type)}）',
                            ),
                          ),
                      ],
                    ),
            ),
            _PreviewDetailSection(
              title: l10n.workbenchPreviewImagePrompt,
              child: Text(
                  _displayOr(shot.prompt, l10n.workbenchPreviewNoDescription)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShotControls(BuildContext context) {
    final allSelected = _selectedShotIds.length == _shots.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: allSelected,
              onChanged: (value) => _toggleAllSelected(value ?? false),
            ),
            Expanded(child: Text(context.l10n.workbenchPreviewSelectAll)),
            FilledButton.tonalIcon(
              key: const ValueKey('workbench-preview-export'),
              onPressed: _isExporting ? null : _exportSelected,
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_isExporting
                  ? context.l10n.workbenchPreviewExporting
                  : context.l10n.workbenchPreviewExportSelected),
            ),
          ],
        ),
        const SizedBox(height: DFTokens.s8),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _shots.length,
            separatorBuilder: (_, __) => const SizedBox(width: DFTokens.s8),
            itemBuilder: (context, index) {
              final shot = _shots[index];
              final active = index == _timeline.currentIndex;
              final selected = _selectedShotIds.contains(shot.id);
              return SizedBox(
                width: 132,
                child: Material(
                  color: active
                      ? context.df.primary.withValues(alpha: .10)
                      : context.df.surfaceMuted,
                  borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                  child: InkWell(
                    key: ValueKey('workbench-preview-thumbnail-${shot.id}'),
                    borderRadius: BorderRadius.circular(DFTokens.radiusControl),
                    onTap: () => _timeline.jumpTo(index),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(DFTokens.radiusControl),
                            child: shot.imageAbsPath == null
                                ? const Icon(Icons.image_not_supported_outlined)
                                : Image.file(
                                    File(shot.imageAbsPath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('#${index + 1}'),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Checkbox(
                            key: ValueKey(
                                'workbench-preview-selected-${shot.id}'),
                            value: selected,
                            onChanged: (value) =>
                                _toggleSelected(shot.id, value ?? false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PreviewShot {
  final int id;
  final Duration duration;
  final String? imageAbsPath;
  final String? videoDesc;
  final String? prompt;
  final List<_PreviewAsset> assets;

  const _PreviewShot({
    required this.id,
    required this.duration,
    required this.imageAbsPath,
    required this.videoDesc,
    required this.prompt,
    required this.assets,
  });

  factory _PreviewShot.fromRow(
    StoryboardRow row,
    Engine engine,
    Map<int, AssetRow> assets,
  ) =>
      _PreviewShot(
        id: row.id,
        duration: _durationFromText(row.duration),
        imageAbsPath: _absoluteMediaPath(engine, row.filePath),
        videoDesc: row.videoDesc,
        prompt: row.prompt,
        assets: [
          for (final id in row.assetIds)
            if (assets[id] case final asset?)
              _PreviewAsset(
                name: asset.name?.trim().isNotEmpty == true
                    ? asset.name!.trim()
                    : '—',
                type: asset.type,
                imageAbsPath: _absoluteMediaPath(engine, asset.filePath),
              ),
        ],
      );
}

class _PreviewAsset {
  final String name;
  final String type;
  final String? imageAbsPath;

  const _PreviewAsset({
    required this.name,
    required this.type,
    required this.imageAbsPath,
  });
}

class _PreviewAssetAvatar extends StatelessWidget {
  final String? imageAbsPath;

  const _PreviewAssetAvatar({required this.imageAbsPath});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        child: imageAbsPath == null
            ? const Icon(Icons.image_not_supported_outlined)
            : ClipOval(
                child: Image.file(
                  File(imageAbsPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_not_supported_outlined),
                ),
              ),
      );
}

class _PreviewDetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _PreviewDetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: DFTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: DFTokens.body14.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: DFTokens.s4),
            child,
          ],
        ),
      );
}

class _PreviewEmptyImage extends StatelessWidget {
  final String text;

  const _PreviewEmptyImage({required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined, size: 48),
            const SizedBox(height: DFTokens.s8),
            Text(text),
          ],
        ),
      );
}

Duration _durationFromText(String? raw) {
  final seconds = double.tryParse(raw?.trim() ?? '');
  if (seconds == null || !seconds.isFinite || seconds <= 0) {
    return const Duration(seconds: 3);
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

String? _absoluteMediaPath(Engine engine, String? relPath) {
  if (relPath == null || relPath.trim().isEmpty) return null;
  return engine.media.existingFilePath(relPath);
}

String _formatTime(Duration value) {
  final seconds = value.inSeconds;
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _formatSeconds(Duration value) {
  final milliseconds = value.inMilliseconds;
  if (milliseconds % 1000 == 0) return '${milliseconds ~/ 1000}';
  return (milliseconds / 1000).toStringAsFixed(1);
}

String _displayOr(String? value, String fallback) =>
    value?.trim().isNotEmpty == true ? value!.trim() : fallback;

String _assetTypeLabel(BuildContext context, String type) => switch (type) {
      'role' => context.l10n.assetsTabRole,
      'scene' => context.l10n.assetsTabScene,
      'tool' => context.l10n.assetsTabTool,
      _ => type,
    };
