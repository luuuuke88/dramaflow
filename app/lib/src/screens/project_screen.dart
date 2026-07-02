import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 项目主页：显式流水线枢纽（小说 → 剧本 → 素材 → 分镜/镜头图 → 视频）。
class ProjectScreen extends ConsumerWidget {
  final String projectId;

  const ProjectScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectProvider(projectId));
    final episodes =
        ref.watch(episodesProvider(projectId)).value ?? const [];
    final activeJobs = ref
        .watch(activeJobsProvider)
        .where((j) => j.projectId == projectId)
        .toList();
    final recentJobs =
        ref.watch(projectJobsProvider(projectId)).value ?? const <Job>[];
    final project = projectAsync.value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回项目列表',
          onPressed: () => context.go('/'),
        ),
        title: project == null
            ? const Text('项目')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (project.artStyle.isNotEmpty)
                    Text(
                      project.artStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: DF.textLo,
                      ),
                    ),
                ],
              ),
        actions: [
          if (project != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: () => _showEditDialog(context, ref, project),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            ),
        ],
      ),
      body: PageContainer(
        maxWidth: 900,
        child: AsyncView<Project>(
          value: projectAsync,
          onRetry: () => ref.invalidate(projectProvider(projectId)),
          builder: (p) =>
              _pipeline(context, ref, p, episodes, activeJobs, recentJobs),
        ),
      ),
    );
  }

  // ---------- 流水线主体 ----------

  Widget _pipeline(
    BuildContext context,
    WidgetRef ref,
    Project p,
    List<EpisodeSummary> episodes,
    List<Job> activeJobs,
    List<Job> recentJobs,
  ) {
    final s = p.stats;

    final novelDone = s.hasNovel;
    final scriptState = _deriveStage(
      activeJobs: activeJobs,
      recentJobs: recentJobs,
      kinds: const {'script_gen'},
      done: s.episodes > 0,
    );
    final assetState = _deriveStage(
      activeJobs: activeJobs,
      recentJobs: recentJobs,
      kinds: const {'asset_extract', 'asset_image'},
      done: s.assets > 0 && s.assetsDone == s.assets,
    );
    final shotImageState = _deriveStage(
      activeJobs: activeJobs,
      recentJobs: recentJobs,
      kinds: const {'storyboard_gen', 'shot_image'},
      done: s.shots > 0 && s.shotsImageDone == s.shots,
    );
    final videoState = _deriveStage(
      activeJobs: activeJobs,
      recentJobs: recentJobs,
      kinds: const {'shot_video'},
      done: s.shots > 0 && s.shotsVideoDone == s.shots,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        // 1. 小说
        _StageCard(
          index: 1,
          title: '小说',
          status: novelDone ? 'done' : 'none',
          completed: novelDone,
          subtitle: novelDone ? '已导入' : '未导入，先把原著小说粘贴进来',
          actions: [
            OutlinedButton.icon(
              onPressed: () => context.go('/projects/$projectId/novel'),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('打开'),
            ),
          ],
        ),
        // 2. 剧本
        _StageCard(
          index: 2,
          title: '剧本',
          status: scriptState.status,
          completed: s.episodes > 0,
          failedJob: scriptState.failedJob,
          onRetry: (job) => _retryJob(context, ref, job),
          subtitle: !s.hasNovel
              ? '请先在「小说」阶段导入小说，才能生成剧本'
              : (s.episodes > 0 ? '已生成 ${s.episodes} 集' : '将小说改编为分集短剧剧本'),
          actions: [
            FilledButton.icon(
              onPressed: s.hasNovel
                  ? () => _showGenerateScriptDialog(context, ref)
                  : null,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('生成剧本'),
            ),
          ],
          extra: episodes.isEmpty
              ? null
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in episodes)
                      ActionChip(
                        avatar: const Icon(Icons.description_outlined,
                            size: 16, color: DF.textMid),
                        label: Text(
                          '第${e.idx}集 ${e.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 12, color: DF.textHi),
                        ),
                        backgroundColor: DF.surface,
                        side: const BorderSide(color: DF.stroke),
                        onPressed: () => context
                            .go('/projects/$projectId/episodes/${e.id}'),
                      ),
                  ],
                ),
        ),
        // 3. 素材
        _StageCard(
          index: 3,
          title: '素材',
          status: assetState.status,
          completed: s.assets > 0 && s.assetsDone == s.assets,
          failedJob: assetState.failedJob,
          onRetry: (job) => _retryJob(context, ref, job),
          subtitle: s.episodes == 0
              ? '请先生成剧本，再从剧本中提取角色与场景素材'
              : '${s.assetsDone}/${s.assets} 完成',
          actions: [
            FilledButton.icon(
              onPressed: s.episodes == 0
                  ? null
                  : () => runAction(
                        context,
                        ref,
                        () async {
                          await ref.read(apiProvider).extractAssets(projectId);
                        },
                        successMessage: '素材提取任务已提交',
                      ),
              icon: const Icon(Icons.category_outlined, size: 18),
              label: const Text('提取素材'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/projects/$projectId/assets'),
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('打开素材库'),
            ),
          ],
        ),
        // 4. 分镜与镜头图
        _StageCard(
          index: 4,
          title: '分镜与镜头图',
          status: shotImageState.status,
          completed: s.shots > 0 && s.shotsImageDone == s.shots,
          failedJob: shotImageState.failedJob,
          onRetry: (job) => _retryJob(context, ref, job),
          subtitle: '镜头图 ${s.shotsImageDone}/${s.shots} 完成 · 进入某一集生成分镜',
        ),
        // 5. 视频
        _StageCard(
          index: 5,
          title: '视频',
          status: videoState.status,
          completed: s.shots > 0 && s.shotsVideoDone == s.shots,
          failedJob: videoState.failedJob,
          onRetry: (job) => _retryJob(context, ref, job),
          subtitle:
              '${s.shotsVideoDone}/${s.shots} 完成 · 在分镜页逐镜生成视频（首次使用请先在设置中确认视频配置）',
          isLast: true,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => context.go('/tasks'),
            icon: const Icon(Icons.bolt_outlined, size: 18),
            label: const Text('查看全部任务'),
          ),
        ),
      ],
    );
  }

  // ---------- 阶段状态推导 ----------

  /// 优先级：活跃任务(running > queued) > 该类最近一次任务失败 > 计数完成 > 无。
  _StageState _deriveStage({
    required List<Job> activeJobs,
    required List<Job> recentJobs,
    required Set<String> kinds,
    required bool done,
  }) {
    Job? queued;
    for (final j in activeJobs) {
      if (!kinds.contains(j.kind)) continue;
      if (j.state == 'running') return const _StageState('running');
      queued ??= j;
    }
    if (queued != null) return const _StageState('queued');

    // recentJobs 按时间倒序：取该类最近一次任务，若失败则整段标红。
    for (final j in recentJobs) {
      if (kinds.contains(j.kind)) {
        if (j.state == 'failed') return _StageState('failed', failedJob: j);
        break;
      }
    }
    return done ? const _StageState('done') : const _StageState('none');
  }

  // ---------- 动作 ----------

  Future<void> _retryJob(BuildContext context, WidgetRef ref, Job job) =>
      runAction(
        context,
        ref,
        () async {
          await ref.read(apiProvider).retryJob(job.id);
        },
        successMessage: '已重新排队',
      );

  Future<void> _showGenerateScriptDialog(
      BuildContext context, WidgetRef ref) async {
    var count = 3;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('生成剧本'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('将小说改编为分集短剧剧本，选择集数：',
                    style: TextStyle(color: DF.textMid)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: count.toDouble(),
                        min: 1,
                        max: 12,
                        divisions: 11,
                        activeColor: DF.amber,
                        label: '$count 集',
                        onChanged: (v) => setState(() => count = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '$count 集',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: DF.amber),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('已有剧本会被覆盖，生成过程约需数分钟。',
                    style: TextStyle(fontSize: 12, color: DF.textLo)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开始生成'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await runAction(
      context,
      ref,
      () async {
        await ref
            .read(apiProvider)
            .generateScript(projectId, episodeCount: count);
      },
      successMessage: '剧本生成任务已提交（$count 集）',
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, WidgetRef ref, Project project) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: project.name);
    final styleCtrl = TextEditingController(text: project.artStyle);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑项目'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '项目名称'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入项目名称' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: styleCtrl,
                  decoration: const InputDecoration(
                    labelText: '画风',
                    hintText: '如：国风动漫，厚涂插画风。可留空',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final name = nameCtrl.text.trim();
    final artStyle = styleCtrl.text.trim();
    await runAction(
      context,
      ref,
      () async {
        await ref
            .read(apiProvider)
            .updateProject(projectId, name: name, artStyle: artStyle);
      },
      successMessage: '项目已更新',
    );
    ref.invalidate(projectProvider(projectId));
    ref.invalidate(projectsProvider);
  }
}

/// 阶段推导结果。
class _StageState {
  final String status; // none | queued | running | done | failed
  final Job? failedJob;

  const _StageState(this.status, {this.failedJob});
}

/// 单个阶段卡片：左侧序号徽标 + 竖向连接线，右侧内容卡。
class _StageCard extends StatelessWidget {
  final int index;
  final String title;
  final String status;
  final bool completed;
  final String subtitle;
  final Job? failedJob;
  final void Function(Job job)? onRetry;
  final List<Widget> actions;
  final Widget? extra;
  final bool isLast;

  const _StageCard({
    required this.index,
    required this.title,
    required this.status,
    required this.completed,
    required this.subtitle,
    this.failedJob,
    this.onRetry,
    this.actions = const [],
    this.extra,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：序号徽标 + 连接线
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: completed ? DF.amber : DF.card,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: completed ? DF.amber : DF.stroke, width: 1.5),
                  ),
                  child: completed
                      ? const Icon(Icons.check_rounded,
                          size: 18, color: Color(0xFF1A1200))
                      : Text(
                          '$index',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DF.textMid,
                          ),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: completed ? DF.amberDim : DF.stroke,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 右侧：内容卡
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 10),
                          StatusChip(
                            status,
                            errorTooltip: failedJob?.error,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: DF.textMid, height: 1.5),
                      ),
                      if (failedJob != null &&
                          (failedJob!.error ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 16, color: DF.red),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                failedJob!.error!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: DF.red, height: 1.4),
                              ),
                            ),
                            if (onRetry != null) ...[
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: DF.red,
                                  side: BorderSide(
                                      color: DF.red.withValues(alpha: 0.5)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => onRetry!(failedJob!),
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('重试',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(spacing: 10, runSpacing: 10, children: actions),
                      ],
                      if (extra != null) ...[
                        const SizedBox(height: 14),
                        extra!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
