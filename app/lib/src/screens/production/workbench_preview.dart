import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

Future<void> writeWorkbenchPreviewZip(Uint8List bytes, String path) {
  return fs.XFile.fromData(
    bytes,
    mimeType: 'application/zip',
    name: '分镜压缩包.zip',
  ).saveTo(path);
}

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

  const WorkbenchQuickPreviewPage({
    super.key,
    required this.projectId,
    required this.scriptId,
  });

  @override
  ConsumerState<WorkbenchQuickPreviewPage> createState() =>
      _WorkbenchQuickPreviewPageState();
}

class _WorkbenchQuickPreviewPageState
    extends ConsumerState<WorkbenchQuickPreviewPage> {
  late final List<_PreviewShot> _shots;
  late final PreviewTimelineController _timeline;
  final Set<int> _selectedShotIds = {};
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(engineProvider);
    final rows = engine.storyboards(widget.scriptId);
    final assetIds = <int>{for (final row in rows) ...row.assetIds};
    final assets = {
      for (final asset in engine.assetsByIds(assetIds.toList())) asset.id: asset,
    };
    _shots = [
      for (final row in rows) _PreviewShot.fromRow(row, engine, assets),
    ];
    _timeline = PreviewTimelineController([
      for (final shot in _shots) shot.duration,
    ]);
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _timeline.tick(const Duration(milliseconds: 50));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _timeline.dispose();
    super.dispose();
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
    final l10n = context.l10n;
    if (_selectedShotIds.isEmpty) {
      _toast(l10n.storyboardExportNoImages);
      return;
    }
    try {
      final export = ref
          .read(engineProvider)
          .exportStoryboardImages(widget.scriptId, _selectedShotIds);
      if (export.fileCount == 0) {
        _toast(l10n.storyboardExportNoImages);
        return;
      }
      final location = await fs.getSaveLocation(
        suggestedName: '分镜压缩包.zip',
        acceptedTypeGroups: const [
          fs.XTypeGroup(label: 'zip', extensions: ['zip']),
        ],
      );
      if (location == null) return;
      await writeWorkbenchPreviewZip(export.bytes, location.path);
      if (mounted) _toast(l10n.workbenchPreviewExported(export.fileCount));
    } catch (error) {
      if (mounted) _toast(localizeError(context, error));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: const ValueKey('workbench-preview-page'),
      appBar: AppBar(title: Text(l10n.workbenchQuickPreview)),
      body: _shots.isEmpty
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
            ),
    );
  }

  Widget _buildStage(BuildContext context) {
    final shot = _shots[_timeline.currentIndex];
    final df = context.df;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: df.surfaceMuted,
              borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DFTokens.radiusControl),
              child: shot.imageAbsPath == null
                  ? _PreviewEmptyImage(text: context.l10n.workbenchPreviewNoImage)
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
              onPressed: _timeline.currentIndex == 0 ? null : _timeline.previous,
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
            Text(_formatTime(_timeline.totalElapsed), style: DFTokens.caption12),
            Expanded(
              child: Slider(
                value: _timeline.totalElapsed.inMilliseconds.toDouble(),
                max: math.max(1, _timeline.totalDuration.inMilliseconds)
                    .toDouble(),
                onChangeStart: (_) => _timeline.pause(),
                onChanged: (value) => _timeline
                    .seek(Duration(milliseconds: value.round())),
              ),
            ),
            Text(_formatTime(_timeline.totalDuration), style: DFTokens.caption12),
          ],
        ),
        _buildSegments(context),
      ],
    );
  }

  Widget _buildSegments(BuildContext context) {
    final df = context.df;
    return Row(
      children: [
        for (final entry in _shots.indexed)
          Expanded(
            flex: math.max(1, entry.$2.duration.inMilliseconds),
            child: Semantics(
              button: true,
              label: '${context.l10n.workbenchQuickPreview} ${entry.$1 + 1}',
              child: InkWell(
                onTap: () => _timeline.jumpTo(entry.$1),
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
              child: Text(l10n.workbenchPreviewSeconds(
                  _formatSeconds(shot.duration))),
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
                            avatar: asset.imageAbsPath == null
                                ? null
                                : CircleAvatar(
                                    backgroundImage: FileImage(
                                        File(asset.imageAbsPath!)),
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
              child: Text(_displayOr(
                  shot.prompt, l10n.workbenchPreviewNoDescription)),
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
              onPressed: _exportSelected,
              icon: const Icon(Icons.download_outlined),
              label: Text(context.l10n.workbenchPreviewExportSelected),
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
                            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
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
                            key: ValueKey('workbench-preview-selected-${shot.id}'),
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
  return engine.mediaAbsPath(relPath);
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
