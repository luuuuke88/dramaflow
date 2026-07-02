import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../api/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

/// 历史区当前选中的项目 id（null = 默认第一个项目）。
final _selectedProjectProvider = StateProvider<String?>((ref) => null);

const _kindLabels = <String, String>{
  'script_gen': '剧本生成',
  'asset_extract': '素材提取',
  'storyboard_gen': '分镜生成',
  'asset_image': '素材图',
  'shot_image': '镜头图',
  'shot_video': '视频生成',
};

String _kindLabel(String kind) => _kindLabels[kind] ?? kind;

IconData _kindIcon(String kind) => switch (kind) {
      'script_gen' => Icons.edit_note_rounded,
      'asset_extract' => Icons.style_outlined,
      'storyboard_gen' => Icons.movie_filter_outlined,
      'asset_image' => Icons.brush_outlined,
      'shot_image' => Icons.image_outlined,
      'shot_video' => Icons.videocam_outlined,
      _ => Icons.bolt_rounded,
    };

/// ISO8601 → 本地时间 HH:mm:ss
String _hms(String? iso) {
  if (iso == null || iso.isEmpty) return '--:--:--';
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '--:--:--';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 毫秒时长 → '12.3s' / '2m05s'
String _fmtDuration(int? ms) {
  if (ms == null) return '';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final m = ms ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  return '${m}m${s.toString().padLeft(2, '0')}s';
}

/// 全局任务中心：进行中（实时轮询）+ 按项目查看历史。
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeJobsProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final selectedId = ref.watch(_selectedProjectProvider);

    // 有效选中项目：优先用户选择，否则第一个项目
    final projects = projectsAsync.value ?? const <Project>[];
    final String? effectiveId;
    if (projects.isEmpty) {
      effectiveId = null;
    } else if (selectedId != null && projects.any((p) => p.id == selectedId)) {
      effectiveId = selectedId;
    } else {
      effectiveId = projects.first.id;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('任务中心')),
      body: RefreshIndicator(
        color: DF.amber,
        onRefresh: () async {
          ref.read(activeJobsProvider.notifier).poke();
          ref.invalidate(projectsProvider);
          if (effectiveId != null) {
            ref.invalidate(projectJobsProvider(effectiveId));
          }
        },
        child: PageContainer(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: '进行中',
                  trailing: active.isEmpty ? null : '${active.length} 个任务',
                ),
              ),
              if (active.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('当前没有进行中的任务',
                        style: TextStyle(color: DF.textLo, fontSize: 13)),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: active.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ActiveJobCard(job: active[i]),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: _HistoryHeader(
                  projects: projects,
                  effectiveId: effectiveId,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ..._historySlivers(ref, projectsAsync, effectiveId),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _historySlivers(
    WidgetRef ref,
    AsyncValue<List<Project>> projectsAsync,
    String? effectiveId,
  ) {
    if (projectsAsync.isLoading && !projectsAsync.hasValue) {
      return const [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: DF.amber),
            ),
          ),
        ),
      ];
    }
    if (projectsAsync.hasError && !projectsAsync.hasValue) {
      return [
        SliverToBoxAdapter(
          child: ErrorCard(
            message: projectsAsync.error.toString(),
            onRetry: () => ref.invalidate(projectsProvider),
          ),
        ),
      ];
    }
    if (effectiveId == null) {
      return const [
        SliverToBoxAdapter(
          child: EmptyHint(
            icon: Icons.folder_off_outlined,
            title: '暂无项目',
            subtitle: '创建项目并发起生成后，这里会显示任务历史',
          ),
        ),
      ];
    }

    final jobsAsync = ref.watch(projectJobsProvider(effectiveId));
    if (jobsAsync.isLoading && !jobsAsync.hasValue) {
      return const [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: DF.amber),
            ),
          ),
        ),
      ];
    }
    if (jobsAsync.hasError && !jobsAsync.hasValue) {
      return [
        SliverToBoxAdapter(
          child: ErrorCard(
            message: jobsAsync.error.toString(),
            onRetry: () => ref.invalidate(projectJobsProvider(effectiveId)),
          ),
        ),
      ];
    }
    final jobs = (jobsAsync.value ?? const <Job>[]).take(50).toList();
    if (jobs.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('该项目暂无历史任务',
                style: TextStyle(color: DF.textLo, fontSize: 13)),
          ),
        ),
      ];
    }
    return [
      SliverList.builder(
        itemCount: jobs.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HistoryTile(job: jobs[i]),
        ),
      ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Text(trailing!,
                style: const TextStyle(color: DF.textLo, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// 历史区标题 + 项目选择器。
class _HistoryHeader extends ConsumerWidget {
  final List<Project> projects;
  final String? effectiveId;

  const _HistoryHeader({required this.projects, required this.effectiveId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Text('历史', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (projects.isNotEmpty)
          DropdownMenu<String>(
            key: ValueKey('history-project-$effectiveId'),
            initialSelection: effectiveId,
            width: 220,
            requestFocusOnTap: false,
            leadingIcon:
                const Icon(Icons.movie_outlined, size: 18, color: DF.textLo),
            textStyle: const TextStyle(fontSize: 13, color: DF.textHi),
            inputDecorationTheme: const InputDecorationTheme(
              isDense: true,
              filled: true,
              fillColor: DF.bg,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: DF.stroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: DF.stroke),
              ),
            ),
            dropdownMenuEntries: [
              for (final p in projects)
                DropdownMenuEntry(value: p.id, label: p.name),
            ],
            onSelected: (v) {
              if (v != null) {
                ref.read(_selectedProjectProvider.notifier).state = v;
              }
            },
          ),
      ],
    );
  }
}

/// 进行中的任务卡片：图标 + 类型/目标 + 状态 + 排队可取消。
class _ActiveJobCard extends ConsumerWidget {
  final Job job;

  const _ActiveJobCard({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: DF.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DF.stroke),
              ),
              child: Icon(_kindIcon(job.kind), size: 19, color: DF.textMid),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_kindLabel(job.kind)} · ${job.targetLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '创建于 ${_hms(job.createdAt)}'
                    '${job.attempt > 1 ? ' · 第 ${job.attempt} 次尝试' : ''}',
                    style: const TextStyle(color: DF.textLo, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(job.state, dense: true),
            if (job.state == 'queued')
              IconButton(
                tooltip: '取消任务',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: DF.textLo),
                onPressed: () => runAction(context, ref, () async {
                  await ref.read(engineProvider).cancelJob(job.id);
                  ref.invalidate(projectJobsProvider(job.projectId));
                }, successMessage: '任务已取消'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 历史任务行：失败可展开看完整错误并重试；完成显示结果摘要。
class _HistoryTile extends ConsumerWidget {
  final Job job;

  const _HistoryTile({required this.job});

  String get _meta {
    final parts = <String>[
      if (job.durationMs != null) _fmtDuration(job.durationMs),
      if (job.finishedAt != null) '完成于 ${_hms(job.finishedAt)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (job.state == 'failed') return _failedTile(context, ref);

    final result = job.result ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleRow(),
            if (job.state == 'done' && result.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                result,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: DF.textLo, fontSize: 12, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _titleRow() {
    return Row(
      children: [
        StatusChip(job.state, dense: true, errorTooltip: job.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${_kindLabel(job.kind)} · ${job.targetLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Text(_meta, style: const TextStyle(color: DF.textLo, fontSize: 11.5)),
      ],
    );
  }

  Widget _failedTile(BuildContext context, WidgetRef ref) {
    final error = (job.error?.isNotEmpty ?? false) ? job.error! : '未知错误';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: DF.textMid,
          collapsedIconColor: DF.textLo,
          title: _titleRow(),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DF.red, fontSize: 12),
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DF.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DF.red.withValues(alpha: 0.35)),
              ),
              child: SelectableText(
                error,
                style:
                    const TextStyle(color: DF.red, fontSize: 12.5, height: 1.6),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试'),
                onPressed: () => runAction(context, ref, () async {
                  await ref.read(engineProvider).retryJob(job.id);
                  ref.invalidate(projectJobsProvider(job.projectId));
                }, successMessage: '已重新排队'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
