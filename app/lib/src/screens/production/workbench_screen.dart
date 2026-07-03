// 工作台（照抄 production/components/workbench 语义，见 P4 参照 §3）：
// 只读镜头列表（顺序已由分镜 index 决定，不做拖拽重排/剪辑特效——见执行边界）+
// 每镜视频候选网格（生成/挑选/删除，同 P2/P3 多版本模式）+ 顶部"合成本集"。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/compose_episode.dart';
import '../../engine/storyboard.dart';
import '../../engine/video_track.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';

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

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _compose() async {
    final l10n = context.l10n;
    setState(() => _composing = true);
    try {
      final result = await ref
          .read(engineProvider)
          .composeEpisode(widget.projectId, widget.scriptId);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.workbenchComposeSuccess),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${l10n.workbenchOutputPath}: ${result.outputRelPath}'),
            if (result.durationSec != null)
              Text('${l10n.workbenchDuration}: ${result.durationSec!.toStringAsFixed(1)}s'),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: Text(l10n.commonConfirm)),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  void _generateAll(List<StoryboardRow> shots) {
    final engine = ref.read(engineProvider);
    engine.batchGenerateVideos(widget.projectId, shots.map((s) => s.id).toList());
    _toast(context.l10n.workbenchGenerateVideo);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(jobsGenerationProvider);
    final shots = ref.watch(engineProvider).storyboards(widget.scriptId);
    final missing = ref
        .watch(engineProvider)
        .orderedSelectedVideoPaths(widget.scriptId)
        .where((p) => p == null || p.isEmpty)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workbenchTitle),
        actions: [
          if (shots.isNotEmpty)
            TextButton.icon(
              onPressed: () => _generateAll(shots),
              icon: const Icon(Icons.movie_creation_outlined),
              label: Text(l10n.workbenchGenerateAll),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
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
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: shots.length,
              separatorBuilder: (c, i) => const SizedBox(height: 12),
              itemBuilder: (c, i) => _ShotRow(
                  projectId: widget.projectId, shot: shots[i], index: i),
            ),
    );
  }
}

class _ShotRow extends ConsumerStatefulWidget {
  final int projectId;
  final StoryboardRow shot;
  final int index;
  const _ShotRow(
      {required this.projectId, required this.shot, required this.index});

  @override
  ConsumerState<_ShotRow> createState() => _ShotRowState();
}

class _ShotRowState extends ConsumerState<_ShotRow> {
  bool _generatingPrompt = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _generatePrompt() async {
    setState(() => _generatingPrompt = true);
    try {
      await ref.read(engineProvider).generateVideoPrompt(widget.shot.id);
    } catch (e) {
      if (mounted) _toast(localizeError(context, e));
    } finally {
      if (mounted) setState(() => _generatingPrompt = false);
    }
  }

  void _generateOne() {
    ref
        .read(engineProvider)
        .batchGenerateVideos(widget.projectId, [widget.shot.id]);
    _toast(context.l10n.workbenchGenerateVideo);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final engine = ref.watch(engineProvider);
    final trackId = widget.shot.trackId;
    final track = trackId != null ? engine.track(trackId) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.stroke),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              : Icon(Icons.image_not_supported_outlined, color: df.textTertiary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('S${widget.index + 1}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(track?.prompt ?? widget.shot.videoDesc ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: df.textSecondary)),
            const SizedBox(height: 8),
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

class _VideoCandidateChip extends ConsumerWidget {
  final int trackId;
  final VideoRow video;
  final bool selected;
  const _VideoCandidateChip(
      {required this.trackId, required this.video, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    Widget label;
    switch (video.state) {
      case vtGenerating:
        label = Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          const SizedBox(width: 6),
          Text(l10n.assetsGenerating, style: const TextStyle(fontSize: 11)),
        ]);
        break;
      case vtFailed:
        label = Tooltip(
          message: localizeReason(l10n, video.errorReason) ?? '',
          child: Text(l10n.scriptStateFailed,
              style: TextStyle(fontSize: 11, color: df.danger)),
        );
        break;
      default:
        label = Text(selected ? l10n.workbenchSelected : l10n.workbenchSelectCandidate,
            style: const TextStyle(fontSize: 11));
    }
    return InkWell(
      onTap: video.state == vtDone
          ? () => ref.read(engineProvider).selectVideo(trackId, video.id)
          : null,
      onLongPress: () => ref.read(engineProvider).deleteVideo(video.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? df.primarySubtle : df.surfaceMuted,
          borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          border: Border.all(color: selected ? df.primary : df.stroke),
        ),
        child: label,
      ),
    );
  }
}
