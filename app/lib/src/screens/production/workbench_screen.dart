// 工作台（照抄 production/components/workbench 语义，见 P4 参照 §3）：
// 只读镜头列表（顺序已由分镜 index 决定，不做拖拽重排/剪辑特效——见执行边界）+
// 每镜视频候选网格（生成/挑选/删除，同 P2/P3 多版本模式）+ 顶部"合成本集"。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../engine/compose_episode.dart';
import '../../engine/storyboard.dart';
import '../../engine/video_track.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';

/// media_kit 一次性初始化。放懒调用（工作台/配音页首次进入时），避免侵入未持有的
/// main.dart；MediaKit.ensureInitialized 幂等，可多次调用。
bool _mediaKitReady = false;
void ensureMediaKit() {
  if (_mediaKitReady) return;
  MediaKit.ensureInitialized();
  _mediaKitReady = true;
}

/// 播放候选视频（tap-to-play 弹窗，media_kit）。相对路径经 engine.mediaAbsPath 解析。
Future<void> showVideoPlayerDialog(
  BuildContext context, {
  required String absPath,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (c) => _VideoPlayerDialog(absPath: absPath),
  );
}

class _VideoPlayerDialog extends StatefulWidget {
  final String absPath;
  const _VideoPlayerDialog({required this.absPath});

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late final Player _player;
  late final VideoController _controller;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    ensureMediaKit();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((_) {
      if (mounted) setState(() => _errored = true);
    });
    if (File(widget.absPath).existsSync()) {
      _player.open(Media(widget.absPath));
    } else {
      _errored = true;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(DFTokens.s24),
      child: Stack(children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _errored
              ? Center(
                  child: Text(l10n.workbenchVideoLoadFailed,
                      style: const TextStyle(color: Colors.white70)))
              : Video(controller: _controller),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            tooltip: l10n.commonConfirm,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ]),
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
  // 懒建/编辑后回填的 trackId：widget.shot 是父级快照，其 trackId 在本次编辑后可能仍为
  // null（父未重建）。本地缓存保证时长/提示词编辑立即在本行可见。
  int? _localTrackId;

  int? get _effectiveTrackId => widget.shot.trackId ?? _localTrackId;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _generatePrompt() async {
    setState(() => _generatingPrompt = true);
    try {
      final engine = ref.read(engineProvider);
      await engine.generateVideoPrompt(widget.shot.id);
      _localTrackId = engine.ensureTrackForStoryboard(widget.shot.id);
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

  /// 手动编辑运镜提示词（懒建轨道后写入 o_videoTrack.prompt）。
  Future<void> _editPrompt(String current) async {
    final l10n = context.l10n;
    final saved = await showDialog<String>(
      context: context,
      builder: (c) => _TextEditDialog(
        title: l10n.workbenchEditPromptTitle,
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
    final saved = await showDialog<String>(
      context: context,
      builder: (c) => _TextEditDialog(
        title: l10n.workbenchEditDurationTitle,
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
                        style:
                            TextStyle(fontSize: 12, color: df.textSecondary),
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

/// 通用文本编辑弹窗（自持 TextEditingController，在自身 dispose 里释放，避免
/// 在外层 await 后同步 dispose 导致退场动画期间控制器被误用的崩溃）。返回 trim 前的
/// 原文（保存）或 null（取消）。
class _TextEditDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String? hint;
  final String? label;
  final bool multiline;
  final bool numeric;
  const _TextEditDialog({
    required this.title,
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
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
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
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(l10n.commonSave)),
      ],
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.workbenchDeleteCandidate),
        content: Text(l10n.workbenchDeleteCandidateConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (ok == true) ref.read(engineProvider).deleteVideo(video.id);
  }

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
    final canPlay = video.state == vtDone &&
        (video.filePath?.isNotEmpty ?? false);
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
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: l10n.workbenchPlayVideo,
            icon: Icon(Icons.play_circle_outline, size: 18, color: df.primary),
            onPressed: () => showVideoPlayerDialog(
              context,
              absPath:
                  ref.read(engineProvider).mediaAbsPath(video.filePath!),
            ),
          ),
        // 选为正片（原 InkWell 语义保留）
        InkWell(
          onTap: video.state == vtDone
              ? () => ref.read(engineProvider).selectVideo(trackId, video.id)
              : null,
          borderRadius: BorderRadius.circular(DFTokens.radiusChip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: label,
          ),
        ),
        // 显式删除按钮（此前只有隐藏的 onLongPress）
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          tooltip: l10n.workbenchDeleteCandidate,
          icon: Icon(Icons.delete_outline, size: 16, color: df.textTertiary),
          onPressed: () => _confirmDelete(context, ref),
        ),
      ]),
    );
  }
}
