import 'dart:convert';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../engine/errors.dart';
import '../engine/queue.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

const _kAllFilter = '__all__';
const _kAllProjectId = -1;

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(activeJobsProvider.notifier).poke();
    ref.read(jobsGenerationProvider.notifier).bump();
    ref.invalidate(projectsProvider);
    ref.invalidate(taskHistoryClassesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeJobsProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.taskCenterTitle),
        actions: [
          IconButton(
            key: const ValueKey('task-history-refresh'),
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: context.df.primary,
        onRefresh: () => _refresh(ref),
        child: PageContainer(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              _TaskSection(
                title: l10n.taskActiveTitle,
                tasks: active,
                emptyText: l10n.taskActiveEmpty,
              ),
              const SizedBox(height: 16),
              _HistorySection(projectsAsync: projectsAsync),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySection extends ConsumerStatefulWidget {
  final AsyncValue<List<ProjectRow>> projectsAsync;

  const _HistorySection({required this.projectsAsync});

  @override
  ConsumerState<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends ConsumerState<_HistorySection> {
  int? _selectedProjectId;
  String _classFilter = _kAllFilter;
  String _stateFilter = _kAllFilter;
  int _page = 1;
  int _limit = 10;

  void _resetPage(VoidCallback update) {
    setState(() {
      update();
      _page = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = widget.projectsAsync;
    final projects = projectsAsync.value ?? const [];
    final l10n = AppLocalizations.of(context);
    final effectiveProjectId = _selectedProjectId != null &&
            projects.any((project) => project.id == _selectedProjectId)
        ? _selectedProjectId
        : null;
    final query = TaskHistoryQuery(
      projectId: effectiveProjectId,
      taskClass: _classFilter == _kAllFilter ? null : _classFilter,
      state: _stateFilter == _kAllFilter ? null : _stateFilter,
      page: _page,
      limit: _limit,
    );
    final tasksAsync = ref.watch(taskHistoryProvider(query));
    final classesAsync = ref.watch(taskHistoryClassesProvider);
    final projectPicker = DropdownButton<int>(
      key: const ValueKey('task-project-filter'),
      isExpanded: true,
      value: effectiveProjectId ?? _kAllProjectId,
      items: [
        DropdownMenuItem<int>(
          value: _kAllProjectId,
          child: _FilterLabel(
            '${l10n.taskFilterProject}: ${l10n.taskAllProjects}',
          ),
        ),
        for (final project in projects)
          DropdownMenuItem<int>(
            value: project.id,
            child: _FilterLabel(
              '${l10n.taskFilterProject}: '
              '${project.name ?? '#${project.id}'}',
            ),
          ),
      ],
      onChanged: (id) {
        if (id != null) {
          _resetPage(() {
            _selectedProjectId = id == _kAllProjectId ? null : id;
          });
        }
      },
    );

    if (tasksAsync.isLoading && !tasksAsync.hasValue) {
      return _TaskSection(
          title: l10n.taskHistoryTitle,
          trailing: projectPicker,
          body: const _CenteredLoader());
    }
    if (tasksAsync.hasError && !tasksAsync.hasValue) {
      return _TaskSection(
        title: l10n.taskHistoryTitle,
        trailing: projectPicker,
        body: ErrorCard(
          message: tasksAsync.error.toString(),
          onRetry: () => ref.invalidate(taskHistoryProvider(query)),
        ),
      );
    }

    final page = tasksAsync.value!;
    final classes = <String>{
      ...?classesAsync.value,
      if (_classFilter != _kAllFilter) _classFilter,
    }.toList()
      ..sort();
    const states = ['pending', 'processing', 'success', 'failed', 'canceled'];

    return _TaskSection(
      title: l10n.taskHistoryTitle,
      trailing: projectPicker,
      filters: _TaskFilters(
        classes: classes,
        states: states,
        classValue: _classFilter,
        stateValue: _stateFilter,
        onClassChanged: (v) => _resetPage(() => _classFilter = v),
        onStateChanged: (v) => _resetPage(() => _stateFilter = v),
      ),
      tasks: page.items,
      emptyText: query.projectId == null && page.total == 0
          ? l10n.taskHistoryEmpty
          : l10n.taskFilterEmpty,
      footer: _TaskHistoryFooter(
        page: page,
        onLimitChanged: (limit) => _resetPage(() => _limit = limit),
        onPageChanged: (targetPage) => setState(() => _page = targetPage),
      ),
    );
  }
}

class _TaskHistoryFooter extends StatelessWidget {
  final TaskHistoryPage page;
  final ValueChanged<int> onLimitChanged;
  final ValueChanged<int> onPageChanged;

  const _TaskHistoryFooter({
    required this.page,
    required this.onLimitChanged,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.taskPageSize),
          DropdownButton<int>(
            key: const ValueKey('task-page-size'),
            value: page.query.limit,
            items: const [10, 25, 50]
                .map((limit) => DropdownMenuItem(
                      value: limit,
                      child: Text('$limit'),
                    ))
                .toList(),
            onChanged: (limit) {
              if (limit != null) onLimitChanged(limit);
            },
          ),
          Text('${page.query.page} / ${page.totalPages}'),
          Text(l10n.dataTableTotal(page.total)),
          IconButton(
            key: const ValueKey('task-page-previous'),
            tooltip: l10n.dataTablePrevPage,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: page.hasPrevious
                ? () => onPageChanged(page.query.page - 1)
                : null,
          ),
          IconButton(
            key: const ValueKey('task-page-next'),
            tooltip: l10n.dataTableNextPage,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed:
                page.hasNext ? () => onPageChanged(page.query.page + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _TaskFilters extends StatelessWidget {
  final List<String> classes;
  final List<String> states;
  final String classValue;
  final String stateValue;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onStateChanged;

  const _TaskFilters({
    required this.classes,
    required this.states,
    required this.classValue,
    required this.stateValue,
    required this.onClassChanged,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth < 560;
        final filterWidth = compactWidth ? constraints.maxWidth : 260.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              SizedBox(
                width: filterWidth,
                child: DropdownButton<String>(
                  key: const ValueKey('task-class-filter'),
                  isExpanded: true,
                  value: classValue,
                  hint: Text(l10n.taskFilterClass),
                  items: [
                    DropdownMenuItem(
                      value: _kAllFilter,
                      child: _FilterLabel(
                        '${l10n.taskFilterClass}: ${l10n.taskFilterAll}',
                      ),
                    ),
                    for (final cls in classes)
                      DropdownMenuItem(
                        value: cls,
                        child: _FilterLabel(
                          '${l10n.taskFilterClass}: ${_taskClassLabel(l10n, cls)}',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onClassChanged(v);
                  },
                ),
              ),
              SizedBox(
                width: filterWidth,
                child: DropdownButton<String>(
                  key: const ValueKey('task-state-filter'),
                  isExpanded: true,
                  value: stateValue,
                  hint: Text(l10n.taskFilterState),
                  items: [
                    DropdownMenuItem(
                      value: _kAllFilter,
                      child: _FilterLabel(
                        '${l10n.taskFilterState}: ${l10n.taskFilterAll}',
                      ),
                    ),
                    for (final state in states)
                      DropdownMenuItem(
                        value: state,
                        child: _FilterLabel(
                          '${l10n.taskFilterState}: ${_taskStateLabel(l10n, state)}',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onStateChanged(v);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String text;

  const _FilterLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _TaskSection extends StatelessWidget {
  final String title;
  final List<TasksRow> tasks;
  final String emptyText;
  final Widget? trailing;
  final Widget? body;
  final Widget? filters;
  final Widget? footer;

  const _TaskSection({
    required this.title,
    this.tasks = const [],
    this.emptyText = '',
    this.trailing,
    this.body,
    this.filters,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedEmptyText =
        emptyText.isEmpty ? AppLocalizations.of(context).taskEmpty : emptyText;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final titleWidget = Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                );
                if (trailing == null) return titleWidget;
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleWidget,
                      const SizedBox(height: 8),
                      trailing!
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: titleWidget),
                    const SizedBox(width: 16),
                    SizedBox(width: 240, child: trailing!),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (filters != null) filters!,
            if (body != null)
              body!
            else if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  resolvedEmptyText,
                  style: TextStyle(color: context.df.textLo),
                ),
              )
            else
              for (final task in tasks) _TaskTile(task: task),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  final TasksRow task;

  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reason = _reasonText(l10n, task.reason);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _showTaskDetail(context, task, reason),
      leading: Icon(_taskIcon(task.taskClass), color: context.df.textLo),
      title: Text(_taskClassLabel(l10n, task.taskClass)),
      subtitle: Text([
        if (task.describe?.isNotEmpty == true) task.describe!,
        if (task.attempt > 1) l10n.taskAttemptLabel(task.attempt),
        if (task.projectName?.isNotEmpty == true)
          task.projectName!
        else if (task.projectId != null)
          l10n.taskProjectLabel(task.projectId!),
        if (task.startTime != null) _formatTime(task.startTime!),
        if (reason != null) reason,
      ].join(' · ')),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusChip(task.state, dense: true, errorTooltip: reason),
          if (task.state == 'pending' || task.state == 'processing')
            IconButton(
              tooltip: l10n.taskCancelTooltip,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => runAction(context, ref, () async {
                await ref.read(engineProvider).cancelJob(task.id);
                ref.read(jobsGenerationProvider.notifier).bump();
              }, successMessage: l10n.taskCanceledMessage),
            ),
          if (task.state == 'failed' && task.supersededByTaskId == null)
            IconButton(
              tooltip: l10n.commonRetry,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => runAction(context, ref, () async {
                await ref.read(engineProvider).retryJob(task.id);
                ref.read(jobsGenerationProvider.notifier).bump();
              }, successMessage: l10n.taskRetryQueued),
            ),
        ],
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    );
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
