import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 分镜列表：每个镜头一张卡片，图片 + 状态 + 操作。
class ShotsScreen extends ConsumerWidget {
  final String projectId;
  final String episodeId;

  const ShotsScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
  });

  Future<void> _generateAllImages(BuildContext context, WidgetRef ref) async {
    int? queued;
    await runAction(context, ref, () async {
      final ids =
          await ref.read(engineProvider).generateAllShotImages(episodeId);
      queued = ids.length;
    });
    if (queued != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            queued == 0 ? '没有需要生成的镜头图（已完成或进行中的会被跳过）' : '已排队 $queued 个镜头图生成任务'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shotsAsync = ref.watch(shotsProvider(episodeId));
    final episode = ref.watch(episodeProvider(episodeId)).value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回剧集',
          onPressed: () =>
              context.go('/projects/$projectId/episodes/$episodeId'),
        ),
        title: Text(episode == null ? '分镜' : '分镜 · 第${episode.idx}集'),
        actions: [
          FilledButton.icon(
            onPressed: () => _generateAllImages(context, ref),
            icon: const Icon(Icons.burst_mode_rounded, size: 18),
            label: const Text('批量生成镜头图'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: PageContainer(
        child: AsyncView(
          value: shotsAsync,
          onRetry: () => ref.invalidate(shotsProvider(episodeId)),
          builder: (shots) {
            if (shots.isEmpty) {
              return EmptyHint(
                icon: Icons.view_carousel_outlined,
                title: '还没有分镜',
                subtitle: '回到剧集页点击「生成分镜」',
                action: FilledButton.icon(
                  onPressed: () => runAction(context, ref, () async {
                    await ref
                        .read(engineProvider)
                        .generateStoryboard(episodeId);
                  }, successMessage: '分镜生成任务已排队'),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('生成分镜'),
                ),
              );
            }
            return LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 20),
                itemCount: shots.length,
                itemBuilder: (context, i) => Padding(
                  padding:
                      EdgeInsets.only(bottom: i == shots.length - 1 ? 12 : 16),
                  child: _ShotCard(
                    shot: shots[i],
                    episodeId: episodeId,
                    wide: wide,
                  ),
                ),
              );
            });
          },
        ),
      ),
    );
  }
}

/// 单个镜头卡片：宽屏左图右文，窄屏上图下文。
class _ShotCard extends ConsumerWidget {
  final Shot shot;
  final String episodeId;
  final bool wide;

  const _ShotCard({
    required this.shot,
    required this.episodeId,
    required this.wide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = _info(context, ref);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MediaImage(shot.imageUrl, width: 220, height: 220),
                      const SizedBox(height: 10),
                      StatusChip(shot.imageStatus,
                          dense: true, errorTooltip: shot.imageError),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: info),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: MediaImage(shot.imageUrl),
                  ),
                  const SizedBox(height: 14),
                  info,
                ],
              ),
      ),
    );
  }

  Widget _info(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final imageError = shot.imageError;
    final videoError = shot.videoError;
    final imageFailed = shot.imageStatus == 'failed' &&
        imageError != null &&
        imageError.isNotEmpty;
    final videoFailed = shot.videoStatus == 'failed' &&
        videoError != null &&
        videoError.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _idxBadge(context),
            if (shot.camera.isNotEmpty) _cameraChip(context),
            StatusChip(shot.imageStatus,
                dense: true, errorTooltip: shot.imageError),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('视频',
                    style: TextStyle(fontSize: 11, color: context.df.textLo)),
                const SizedBox(width: 4),
                StatusChip(shot.videoStatus,
                    dense: true, errorTooltip: shot.videoError),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(shot.description, style: theme.bodyMedium),
        if (shot.dialogue.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.df.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.df.stroke),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote_rounded,
                    size: 16, color: context.df.textLo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(shot.dialogue,
                      style: theme.bodySmall?.copyWith(height: 1.5)),
                ),
              ],
            ),
          ),
        ],
        if (shot.assetNames.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in shot.assetNames)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.df.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: context.df.stroke),
                  ),
                  child: Text(name,
                      style:
                          TextStyle(fontSize: 11, color: context.df.textMid)),
                ),
            ],
          ),
        ],
        if (imageFailed) ...[
          const SizedBox(height: 8),
          _errorText(context, '图片：$imageError'),
        ],
        if (videoFailed) ...[
          const SizedBox(height: 8),
          _errorText(context, '视频：$videoError'),
        ],
        const SizedBox(height: 12),
        _actions(context, ref),
      ],
    );
  }

  Widget _errorText(BuildContext context, String text) => Tooltip(
        message: text,
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.df.red, height: 1.4)),
      );

  Widget _idxBadge(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: context.df.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: context.df.primary.withValues(alpha: 0.4)),
        ),
        child: Text('镜头 ${shot.idx}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.df.primary)),
      );

  Widget _cameraChip(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.df.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.df.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_outlined, size: 13, color: context.df.textLo),
            const SizedBox(width: 4),
            Text(shot.camera,
                style: TextStyle(fontSize: 11.5, color: context.df.textMid)),
          ],
        ),
      );

  ButtonStyle get _compactOutlined => OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      );

  ButtonStyle get _compactText => TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      );

  Widget _actions(BuildContext context, WidgetRef ref) {
    final imageBusy =
        shot.imageStatus == 'queued' || shot.imageStatus == 'running';
    final videoBusy =
        shot.videoStatus == 'queued' || shot.videoStatus == 'running';
    final imageDone = shot.imageStatus == 'done';
    final imageFailed = shot.imageStatus == 'failed';

    final videoEnabled = imageDone && !videoBusy;
    final videoTooltip =
        !imageDone ? '需要先生成镜头图，完成后才能生成视频' : (videoBusy ? '视频任务进行中' : null);

    Widget videoButton = OutlinedButton.icon(
      onPressed: videoEnabled
          ? () => runAction(context, ref, () async {
                await ref.read(engineProvider).generateShotVideo(shot.id);
              }, successMessage: '视频生成任务已排队')
          : null,
      icon: const Icon(Icons.movie_creation_outlined, size: 16),
      label: Text(shot.videoStatus == 'done' ? '重新生成视频' : '生成视频'),
      style: _compactOutlined,
    );
    if (videoTooltip != null) {
      videoButton = Tooltip(message: videoTooltip, child: videoButton);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: imageBusy
              ? null
              : () => runAction(context, ref, () async {
                    await ref.read(engineProvider).generateShotImage(shot.id);
                  }, successMessage: '镜头图生成任务已排队'),
          icon: Icon(
              imageDone || imageFailed
                  ? Icons.refresh_rounded
                  : Icons.image_outlined,
              size: 16),
          label: Text(imageDone ? '重新生成' : (imageFailed ? '重试' : '生成镜头图')),
          style: _compactOutlined,
        ),
        videoButton,
        TextButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _ShotEditDialog(shot: shot, episodeId: episodeId),
          ),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('编辑'),
          style: _compactText,
        ),
        if (shot.videoUrl != null && shot.videoUrl!.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              final abs = ref.read(engineProvider).mediaAbsPath(shot.videoUrl!);
              await Clipboard.setData(ClipboardData(text: abs));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('视频文件路径已复制'),
                  duration: Duration(seconds: 2),
                ));
              }
            },
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('打开视频'),
            style: _compactText,
          ),
      ],
    );
  }
}

/// 编辑弹窗：描述 / 运镜 / 台词 / 图片提示词 / 视频提示词，只提交改动的字段。
class _ShotEditDialog extends ConsumerStatefulWidget {
  final Shot shot;
  final String episodeId;

  const _ShotEditDialog({required this.shot, required this.episodeId});

  @override
  ConsumerState<_ShotEditDialog> createState() => _ShotEditDialogState();
}

class _ShotEditDialogState extends ConsumerState<_ShotEditDialog> {
  late final _desc = TextEditingController(text: widget.shot.description);
  late final _camera = TextEditingController(text: widget.shot.camera);
  late final _dialogue = TextEditingController(text: widget.shot.dialogue);
  late final _imagePrompt =
      TextEditingController(text: widget.shot.imagePrompt);
  late final _videoPrompt =
      TextEditingController(text: widget.shot.videoPrompt);
  bool _saving = false;

  @override
  void dispose() {
    _desc.dispose();
    _camera.dispose();
    _dialogue.dispose();
    _imagePrompt.dispose();
    _videoPrompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final patch = <String, String>{};
    void addIfChanged(String key, String original, TextEditingController c) {
      final v = c.text.trim();
      if (v != original) patch[key] = v;
    }

    addIfChanged('description', widget.shot.description, _desc);
    addIfChanged('camera', widget.shot.camera, _camera);
    addIfChanged('dialogue', widget.shot.dialogue, _dialogue);
    addIfChanged('imagePrompt', widget.shot.imagePrompt, _imagePrompt);
    addIfChanged('videoPrompt', widget.shot.videoPrompt, _videoPrompt);

    if (patch.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    var ok = false;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).updateShot(widget.shot.id, patch);
      ok = true;
    }, successMessage: '分镜已保存');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ref.invalidate(shotsProvider(widget.episodeId));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑镜头 ${widget.shot.idx}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '画面描述', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _camera,
                decoration: const InputDecoration(labelText: '运镜'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _dialogue,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '台词', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _imagePrompt,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: '图片提示词', alignLabelWithHint: true),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _videoPrompt,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: '视频提示词', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
