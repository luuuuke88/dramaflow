import 'dart:convert';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../engine/errors.dart';
import '../engine/queue.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/df_empty.dart';

const _kAllFilter = '__all__';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  int? _selectedProjectId;
  String _classFilter = _kAllFilter;
  String _stateFilter = _kAllFilter;
  int _pageSize = 10;
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final allJobsAsync = ref.watch(allJobsProvider);
    final activeJobs = ref.watch(activeJobsProvider);

    final projects = projectsAsync.value ?? const [];
    final allJobs = allJobsAsync.value ?? const <TasksRow>[];

    // 去重派生筛选大类
    final classes = <String>{
      for (final task in allJobs)
        if (task.taskClass.isNotEmpty) task.taskClass,
    }.toList()
      ..sort();

    // 状态分类
    final states = <String>[
      'processing',
      'success',
      'failed',
      'pending',
      'canceled'
    ];

    // 多维筛选过滤
    final filteredJobs = [
      for (final task in allJobs)
        if ((_selectedProjectId == null ||
                task.projectId == _selectedProjectId) &&
            (_classFilter == _kAllFilter || task.taskClass == _classFilter) &&
            (_stateFilter == _kAllFilter || task.state == _stateFilter))
          task,
    ];

    // 分页计算
    final totalCount = filteredJobs.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 9999);
    final safePage = _currentPage.clamp(1, totalPages);
    final startIndex = (safePage - 1) * _pageSize;
    final pageJobs = filteredJobs.skip(startIndex).take(_pageSize).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 页面 Header 区域
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.taskCenterTitle,
                          style: DFTokens.pageTitle26w800,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: activeJobs.isNotEmpty
                                ? df.primary.withValues(alpha: 0.12)
                                : df.surfaceMuted,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            activeJobs.isNotEmpty
                                ? '${activeJobs.length} 个任务运行中'
                                : '暂无运行中任务',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: activeJobs.isNotEmpty
                                  ? df.primary
                                  : df.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.taskCenterSubtitle,
                      style: TextStyle(fontSize: 14, color: df.textSecondary),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  ref.read(activeJobsProvider.notifier).poke();
                  ref.invalidate(projectsProvider);
                  ref.invalidate(allJobsProvider);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.commonRefresh),
                style: ButtonStyle(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. 顶部多维筛选控制卡片 (Filter Bar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: df.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: df.stroke.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 筛选 1: 项目名称
                _buildFilterItem(
                  context,
                  label: '项目名称',
                  child: DropdownButton<int?>(
                    value: _selectedProjectId,
                    isDense: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: df.textTertiary, size: 18),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('全部项目'),
                      ),
                      for (final p in projects)
                        DropdownMenuItem<int?>(
                          value: p.id,
                          child: Text(p.name ?? '#${p.id}'),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedProjectId = v;
                      _currentPage = 1;
                    }),
                  ),
                ),
                const SizedBox(width: 24),
                // 筛选 2: 任务大类
                _buildFilterItem(
                  context,
                  label: '任务大类',
                  child: DropdownButton<String>(
                    value: classes.contains(_classFilter)
                        ? _classFilter
                        : _kAllFilter,
                    isDense: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: df.textTertiary, size: 18),
                    items: [
                      const DropdownMenuItem<String>(
                        value: _kAllFilter,
                        child: Text('全部大类'),
                      ),
                      for (final cls in classes)
                        DropdownMenuItem<String>(
                          value: cls,
                          child: Text(_taskClassLabel(l10n, cls)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _classFilter = v;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 24),
                // 筛选 3: 状态
                _buildFilterItem(
                  context,
                  label: '任务状态',
                  child: DropdownButton<String>(
                    value: _stateFilter,
                    isDense: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: df.textTertiary, size: 18),
                    items: [
                      const DropdownMenuItem<String>(
                        value: _kAllFilter,
                        child: Text('全部状态'),
                      ),
                      for (final st in states)
                        DropdownMenuItem<String>(
                          value: st,
                          child: Text(_taskStateLabel(l10n, st)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _stateFilter = v;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
                const Spacer(),
                if (_selectedProjectId != null ||
                    _classFilter != _kAllFilter ||
                    _stateFilter != _kAllFilter)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _selectedProjectId = null;
                      _classFilter = _kAllFilter;
                      _stateFilter = _kAllFilter;
                      _currentPage = 1;
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: const Text('重置筛选'),
                    style: TextButton.styleFrom(
                      foregroundColor: df.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. 旗舰级数据表格卡片 (Pro Table)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: df.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: df.stroke.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 表头 (Table Header)
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: df.surfaceMuted.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: df.stroke.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text('任务大类',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: df.textSecondary)),
                        ),
                        SizedBox(
                          width: 140,
                          child: Text('关联对象',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: df.textSecondary)),
                        ),
                        SizedBox(
                          width: 180,
                          child: Text('模型名称',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: df.textSecondary)),
                        ),
                        Expanded(
                          child: Text('描述',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: df.textSecondary)),
                        ),
                        SizedBox(
                          width: 160,
                          child: Text('失败原因',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: df.textSecondary)),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text('状态',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: df.textSecondary)),
                        ),
                        SizedBox(
                          width: 120,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text('时间 / 操作',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: df.textSecondary)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 表格内容区 (Table Content Rows)
                  Expanded(
                    child: allJobsAsync.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : pageJobs.isEmpty
                            ? _buildEmptyTable(context)
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: pageJobs.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: df.stroke.withValues(alpha: 0.3),
                                ),
                                itemBuilder: (context, index) {
                                  final task = pageJobs[index];
                                  return _TaskTableRow(
                                    task: task,
                                    projects: projects,
                                    isEven: index.isEven,
                                  );
                                },
                              ),
                  ),

                  // 4. 底部分页控制栏 (Pagination Bar)
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: df.stroke.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '共 $totalCount 条数据',
                          style: TextStyle(
                            fontSize: 13,
                            color: df.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        // 每页条数
                        DropdownButton<int>(
                          value: _pageSize,
                          isDense: true,
                          underline: const SizedBox(),
                          icon: Icon(Icons.keyboard_arrow_down_rounded,
                              color: df.textTertiary, size: 16),
                          items: const [
                            DropdownMenuItem(value: 10, child: Text('10 条/页')),
                            DropdownMenuItem(value: 20, child: Text('20 条/页')),
                            DropdownMenuItem(value: 50, child: Text('50 条/页')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _pageSize = v;
                                _currentPage = 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 20),
                        // 页码翻页器
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded,
                                  size: 18),
                              onPressed: safePage > 1
                                  ? () =>
                                      setState(() => _currentPage = safePage - 1)
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            for (int p = 1;
                                p <= totalPages && p <= 5;
                                p++) ...[
                              InkWell(
                                onTap: () => setState(() => _currentPage = p),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: p == safePage
                                        ? df.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$p',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: p == safePage
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: p == safePage
                                          ? Colors.white
                                          : df.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded,
                                  size: 18),
                              onPressed: safePage < totalPages
                                  ? () =>
                                      setState(() => _currentPage = safePage + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterItem(BuildContext context,
      {required String label, required Widget child}) {
    final df = context.df;
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: df.textSecondary,
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildEmptyTable(BuildContext context) {
    return const DFEmpty(
      text: '暂无符合条件的任务记录',
      description: '生成剧本、图片、视频等操作产生的任务会显示在这里，可以按项目、类型、状态筛选查看',
    );
  }
}

class _TaskTableRow extends ConsumerWidget {
  final TasksRow task;
  final List<ProjectRow> projects;
  final bool isEven;

  const _TaskTableRow({
    required this.task,
    required this.projects,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    final l10n = AppLocalizations.of(context);
    final reason = _reasonText(l10n, task.reason);
    final modelName = task.model ?? _taskModelName(task);
    final projectName = _taskProjectName(task, projects);

    return InkWell(
      onTap: () => _showTaskDetail(context, task, reason),
      hoverColor: df.primary.withValues(alpha: 0.04),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: isEven ? df.surface : df.surfaceMuted.withValues(alpha: 0.3),
        child: Row(
          children: [
            // 1. 任务大类
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  Icon(_taskIcon(task.taskClass),
                      size: 17, color: df.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _taskClassLabel(l10n, task.taskClass),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: df.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 2. 关联对象
            SizedBox(
              width: 140,
              child: Text(
                projectName,
                style: TextStyle(fontSize: 13, color: df.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 3. 模型
            SizedBox(
              width: 180,
              child: Text(
                modelName,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: df.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 4. 描述
            Expanded(
              child: Text(
                task.describe ?? '-',
                style: TextStyle(fontSize: 13, color: df.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 5. 失败原因
            SizedBox(
              width: 160,
              child: Text(
                reason ?? '-',
                style: TextStyle(
                  fontSize: 12,
                  color: reason != null ? df.danger : df.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 6. 状态
            SizedBox(
              width: 120,
              child: StatusChip(task.state, dense: true, errorTooltip: reason),
            ),
            // 7. 时间 / 操作
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.startTime != null
                          ? _formatTime(task.startTime!)
                          : '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: df.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (task.state == 'pending' || task.state == 'processing')
                      IconButton(
                        iconSize: 16,
                        tooltip: l10n.taskCancelTooltip,
                        icon: Icon(Icons.close_rounded, color: df.danger),
                        onPressed: () => runAction(context, ref, () async {
                          await ref.read(engineProvider).cancelJob(task.id);
                          ref.invalidate(allJobsProvider);
                        }, successMessage: l10n.taskCanceledMessage),
                      ),
                    if (task.state == 'failed' &&
                        task.supersededByTaskId == null)
                      IconButton(
                        iconSize: 16,
                        tooltip: l10n.commonRetry,
                        icon: Icon(Icons.refresh_rounded, color: df.primary),
                        onPressed: () => runAction(context, ref, () async {
                          await ref.read(engineProvider).retryJob(task.id);
                          ref.invalidate(allJobsProvider);
                        }, successMessage: l10n.taskRetryQueued),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _taskModelName(TasksRow task) {
    try {
      final related = task.relatedObjectsJson;
      if (related.containsKey('model')) return related['model']!.toString();
      if (related.containsKey('model_id'))
        return related['model_id']!.toString();
      if (related.containsKey('provider_model')) {
        return related['provider_model']!.toString();
      }
    } catch (_) {}
    return '-';
  }

  String _taskProjectName(TasksRow task, List<ProjectRow> projects) {
    if (task.projectId == null) return '全局任务';
    for (final p in projects) {
      if (p.id == task.projectId) return p.name ?? '#${p.id}';
    }
    return '#${task.projectId}';
  }
}

String _taskClassLabel(AppLocalizations l10n, String taskClass) =>
    switch (taskClass) {
      'event_generation' => l10n.taskClassEventGeneration,
      'script_generation' => l10n.taskClassScriptGeneration,
      'director_plan_generation' => l10n.taskClassDirectorPlanGeneration,
      'storyboard_table_generation' => l10n.taskClassStoryboardTableGeneration,
      'asset_extraction' => l10n.taskClassAssetExtraction,
      'asset_prompt_polish' => l10n.taskClassAssetPromptPolish,
      'asset_image_generation' => l10n.taskClassAssetImageGeneration,
      'storyboard_generate' => l10n.taskClassStoryboardGenerate,
      'storyboard_image_generation' => l10n.taskClassStoryboardImageGeneration,
      'video_generation' => l10n.taskClassVideoGeneration,
      'audio_bind' => l10n.taskClassAudioBind,
      _ => taskClass.isEmpty ? l10n.taskClassGeneric : taskClass,
    };

IconData _taskIcon(String taskClass) => switch (taskClass) {
      'event_generation' => Icons.auto_awesome_motion_outlined,
      'script_generation' => Icons.article_outlined,
      'director_plan_generation' => Icons.assignment_outlined,
      'storyboard_table_generation' => Icons.table_rows_outlined,
      'asset_extraction' => Icons.category_outlined,
      'asset_prompt_polish' => Icons.auto_fix_high_outlined,
      'asset_image_generation' => Icons.image_outlined,
      'storyboard_generate' => Icons.view_list_outlined,
      'storyboard_image_generation' => Icons.photo_library_outlined,
      'video_generation' => Icons.movie_creation_outlined,
      'audio_bind' => Icons.record_voice_over_outlined,
      _ => Icons.bolt_outlined,
    };

String _taskStateLabel(AppLocalizations l10n, String state) => switch (state) {
      'pending' => l10n.taskStatePending,
      'processing' => l10n.taskStateProcessing,
      'success' => l10n.taskStateSuccess,
      'failed' => l10n.taskStateFailed,
      'canceled' => l10n.taskStateCanceled,
      _ => state,
    };

Future<void> _showTaskDetail(
    BuildContext context, TasksRow task, String? reason) {
  final l10n = AppLocalizations.of(context);
  String related = '';
  try {
    final map = task.relatedObjectsJson;
    if (map.isNotEmpty) {
      related = const JsonEncoder.withIndent('  ').convert(map);
    }
  } catch (_) {
    related = task.relatedObjects ?? '';
  }
  final rows = <(String, String?)>[
    (l10n.taskDetailClass, _taskClassLabel(l10n, task.taskClass)),
    (l10n.taskDetailState, _taskStateLabel(l10n, task.state)),
    (l10n.taskDetailDescribe, task.describe),
    (l10n.taskDetailModel, task.model),
    (l10n.taskDetailRelated, related.isEmpty ? null : related),
    (l10n.taskDetailReason, reason),
    (
      l10n.taskDetailTiming,
      task.startTime == null ? null : _formatTime(task.startTime!),
    ),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.taskDetailTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value) in rows)
                _TaskDetailRow(
                    label: label, value: value ?? l10n.taskDetailNone),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.commonConfirm),
        ),
      ],
    ),
  );
}

class _TaskDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _TaskDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: context.df.textLo, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: context.df.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _reasonText(AppLocalizations l10n, String? reasonJson) {
  final reason = EngineException.fromReasonJson(reasonJson);
  if (reason == null) return null;
  return switch (reason.errKey) {
    errProviderMissing => l10n.errProviderMissing,
    errModelMissing => l10n.errModelMissing,
    errNetwork => l10n.errNetwork,
    errLlmFormat => l10n.errLlmFormat,
    errCanceled => l10n.errCanceled,
    errAppRestart => l10n.errAppRestart,
    errFileTooLarge => l10n.errFileTooLarge,
    errFileType => l10n.errFileType,
    errRegexInvalid => l10n.errRegexInvalid,
    errNoChapters => l10n.errNoChapters,
    errPlatformComposer => l10n.errPlatformComposer,
    _ => reason.errKey,
  };
}

String _formatTime(int ms) {
  final time = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
