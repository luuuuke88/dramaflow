import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

Color? _lightAppBarBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? context.df.surface
        : null;

PreferredSizeWidget? _lightAppBarBottom(BuildContext context) {
  if (Theme.of(context).brightness != Brightness.light) return null;
  return PreferredSize(
    preferredSize: const Size.fromHeight(1),
    child: Container(height: 1, color: context.df.stroke),
  );
}

/// 单集剧本页：梗概 + 场次卡片（只读），可发起分镜生成 / 跳转分镜列表。
class EpisodeScreen extends ConsumerWidget {
  final String projectId;
  final String episodeId;

  const EpisodeScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
  });

  Future<void> _copyScenesJson(BuildContext context, Episode episode) async {
    final json = jsonEncode(episode.scenes.map((s) => s.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('场次 JSON 已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _generateStoryboard(
      BuildContext context, WidgetRef ref, int? shotCountMaybe) async {
    // shotsProvider 尚未加载完成时数量不可信（会误判为 0 而跳过覆盖确认），
    // 此时直接向后端拿权威数量
    var shotCount = shotCountMaybe;
    if (shotCount == null) {
      try {
        shotCount =
            (await ref.read(engineProvider).listShots(episodeId)).length;
      } on Exception {
        shotCount = 0;
      }
      if (!context.mounted) return;
    }
    if (shotCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重新生成分镜？'),
          content: const Text('重新生成将覆盖现有分镜，已生成的镜头图不会保留关联。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重新生成'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await runAction(context, ref, () async {
      await ref.read(engineProvider).generateStoryboard(episodeId);
    }, successMessage: '分镜生成任务已提交');
    if (!context.mounted) return;
    ref.invalidate(shotsProvider(episodeId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodeAsync = ref.watch(episodeProvider(episodeId));
    final episode = episodeAsync.value;
    final int? shotCountMaybe =
        ref.watch(shotsProvider(episodeId)).value?.length;
    final shotCount = shotCountMaybe ?? 0;
    final storyboardRunning = ref
        .watch(activeJobsProvider)
        .any((j) => j.kind == 'storyboard_gen' && j.targetId == episodeId);
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _lightAppBarBackground(context),
        bottom: _lightAppBarBottom(context),
        leading: IconButton(
          tooltip: '返回项目',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/projects/$projectId'),
        ),
        title: Text(
          episode == null ? '剧集' : '第${episode.idx}集 · ${episode.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '复制场次 JSON',
            icon: const Icon(Icons.copy_all_rounded, size: 20),
            onPressed: episode == null
                ? null
                : () => _copyScenesJson(context, episode),
          ),
          const SizedBox(width: 4),
          if (narrow)
            IconButton.outlined(
              tooltip: '生成分镜',
              icon: const Icon(Icons.auto_awesome_motion_rounded, size: 20),
              onPressed: storyboardRunning
                  ? null
                  : () => _generateStoryboard(context, ref, shotCountMaybe),
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome_motion_rounded, size: 18),
              label: Text(storyboardRunning ? '生成中…' : '生成分镜'),
              onPressed: storyboardRunning
                  ? null
                  : () => _generateStoryboard(context, ref, shotCountMaybe),
            ),
          const SizedBox(width: 8),
          if (narrow)
            IconButton.filled(
              tooltip: '查看分镜',
              icon: Badge(
                isLabelVisible: shotCount > 0,
                label: Text('$shotCount'),
                backgroundColor: onPrimary,
                textColor: context.df.primary,
                child: const Icon(Icons.grid_view_rounded, size: 20),
              ),
              onPressed: () =>
                  context.go('/projects/$projectId/episodes/$episodeId/shots'),
            )
          else
            FilledButton.icon(
              icon: Badge(
                isLabelVisible: shotCount > 0,
                label: Text('$shotCount'),
                backgroundColor: onPrimary,
                textColor: context.df.primary,
                child: const Icon(Icons.grid_view_rounded, size: 18),
              ),
              label: const Text('查看分镜'),
              onPressed: () =>
                  context.go('/projects/$projectId/episodes/$episodeId/shots'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (storyboardRunning) const _StoryboardBanner(),
          Expanded(
            child: AsyncView<Episode>(
              value: episodeAsync,
              onRetry: () => ref.invalidate(episodeProvider(episodeId)),
              builder: (ep) {
                if (ep.scenes.isEmpty && ep.synopsis.isEmpty) {
                  return const EmptyHint(
                    icon: Icons.theaters_outlined,
                    title: '本集还没有剧本内容',
                    subtitle: '请先在流水线页生成剧本，或稍后刷新查看',
                  );
                }
                return PageContainer(
                  maxWidth: 960,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: ep.scenes.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _SynopsisCard(synopsis: ep.synopsis),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SceneCard(idx: i, scene: ep.scenes[i - 1]),
                      );
                    },
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

/// 分镜生成中的顶部提示条。
class _StoryboardBanner extends StatelessWidget {
  const _StoryboardBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.df.primary.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            minHeight: 2,
            color: context.df.primary,
            backgroundColor: Colors.transparent,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.autorenew_rounded,
                    size: 15, color: context.df.primary),
                const SizedBox(width: 8),
                Text(
                  '分镜生成中…',
                  style: TextStyle(
                    color: context.df.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本集梗概卡片。
class _SynopsisCard extends StatelessWidget {
  final String synopsis;

  const _SynopsisCard({required this.synopsis});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes_rounded, size: 16, color: context.df.primary),
                const SizedBox(width: 6),
                Text(
                  '本集梗概',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.df.textMid,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              synopsis.isEmpty ? '（暂无梗概）' : synopsis,
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个场次卡片：序号 + 地点 + 时间 chip + 动作描述 + 对白。
class _SceneCard extends StatelessWidget {
  final int idx;
  final Scene scene;

  const _SceneCard({required this.idx, required this.scene});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.df.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: context.df.primary.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '第 $idx 场',
                    style: TextStyle(
                      color: context.df.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    scene.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (scene.timeOfDay.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.df.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: context.df.blue.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      scene.timeOfDay,
                      style: TextStyle(
                        color: context.df.blue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (scene.action.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                scene.action,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.6),
              ),
            ],
            if (scene.dialogues.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.df.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.df.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, d) in scene.dialogues.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.speaker,
                              style: TextStyle(
                                color: context.df.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                d.line,
                                style: TextStyle(
                                  color: context.df.textHi,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
