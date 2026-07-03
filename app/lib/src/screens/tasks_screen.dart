import 'dart:convert';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../engine/engine.dart';
import '../engine/errors.dart';
import '../engine/queue.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/shell.dart';

final _selectedProjectProvider = StateProvider<int?>((ref) => null);

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeJobsProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final selectedId = ref.watch(_selectedProjectProvider);
    final l10n = AppLocalizations.of(context);
    final projects = projectsAsync.value ?? const [];
    final effectiveId = selectedId != null &&
            projects.any((project) => project.id == selectedId)
        ? selectedId
        : (projects.isEmpty ? null : projects.first.id);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskCenterTitle)),
      body: RefreshIndicator(
        color: context.df.primary,
        onRefresh: () async {
          ref.read(activeJobsProvider.notifier).poke();
          ref.invalidate(projectsProvider);
          if (effectiveId != null) {
            ref.invalidate(projectJobsProvider(effectiveId));
          }
        },
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
              _HistorySection(
                projectsAsync: projectsAsync,
                effectiveId: effectiveId,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 任务筛选（审计补齐）：任务类型 + 状态。客户端筛选，任务类型选项从当前行去重派生。
const _kAllFilter = '__all__';

class _HistorySection extends ConsumerStatefulWidget {
  final AsyncValue<List<ProjectRow>> projectsAsync;
  final int? effectiveId;

  const _HistorySection({
    required this.projectsAsync,
    required this.effectiveId,
  });

  @override
  ConsumerState<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends ConsumerState<_HistorySection> {
  String _classFilter = _kAllFilter;
  String _stateFilter = _kAllFilter;

  @override
  Widget build(BuildContext context) {
    final projectsAsync = widget.projectsAsync;
    final effectiveId = widget.effectiveId;
    final projects = projectsAsync.value ?? const [];
    final l10n = AppLocalizations.of(context);
    if (projectsAsync.isLoading && !projectsAsync.hasValue) {
      return _TaskSection(title: l10n.taskHistoryTitle, body: const _CenteredLoader());
    }
    if (projectsAsync.hasError && !projectsAsync.hasValue) {
      return _TaskSection(
        title: l10n.taskHistoryTitle,
        body: ErrorCard(
          message: projectsAsync.error.toString(),
          onRetry: () => ref.invalidate(projectsProvider),
        ),
      );
    }
    if (effectiveId == null) {
      return _TaskSection(
        title: l10n.taskHistoryTitle,
        emptyText: l10n.taskNoProjects,
      );
    }

    final tasksAsync = ref.watch(projectJobsProvider(effectiveId));
    final projectPicker = DropdownButton<int>(
      value: effectiveId,
      items: [
        for (final project in projects)
          DropdownMenuItem<int>(
            value: project.id,
            child: Text(project.name ?? '#${project.id}'),
          ),
      ],
      onChanged: (id) {
        if (id != null) {
          ref.read(_selectedProjectProvider.notifier).state = id;
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
          onRetry: () => ref.invalidate(projectJobsProvider(effectiveId)),
        ),
      );
    }

    final allTasks = tasksAsync.value ?? const <TasksRow>[];
    final classes = <String>{
      for (final task in allTasks)
        if (task.taskClass.isNotEmpty) task.taskClass,
    }.toList()
      ..sort();
    final states = <String>{
      for (final task in allTasks) task.state,
    }.toList()
      ..sort();
    // 当前筛选值已不在选项列表中时（如切换项目后），回退到"全部"。
    final classValue =
        classes.contains(_classFilter) ? _classFilter : _kAllFilter;
    final stateValue =
        states.contains(_stateFilter) ? _stateFilter : _kAllFilter;
    final filtered = [
      for (final task in allTasks)
        if ((classValue == _kAllFilter || task.taskClass == classValue) &&
            (stateValue == _kAllFilter || task.state == stateValue))
          task,
    ];

    return _TaskSection(
      title: l10n.taskHistoryTitle,
      trailing: projectPicker,
      filters: allTasks.isEmpty
          ? null
          : _TaskFilters(
              classes: classes,
              states: states,
              classValue: classValue,
              stateValue: stateValue,
              onClassChanged: (v) => setState(() => _classFilter = v),
              onStateChanged: (v) => setState(() => _stateFilter = v),
            ),
      tasks: filtered,
      emptyText: allTasks.isEmpty ? l10n.taskHistoryEmpty : l10n.taskFilterEmpty,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          DropdownButton<String>(
            value: classValue,
            hint: Text(l10n.taskFilterClass),
            items: [
              DropdownMenuItem(
                value: _kAllFilter,
                child: Text('${l10n.taskFilterClass}: ${l10n.taskFilterAll}'),
              ),
              for (final cls in classes)
                DropdownMenuItem(
                  value: cls,
                  child: Text('${l10n.taskFilterClass}: ${_taskClassLabel(l10n, cls)}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) onClassChanged(v);
            },
          ),
          DropdownButton<String>(
            value: stateValue,
            hint: Text(l10n.taskFilterState),
            items: [
              DropdownMenuItem(
                value: _kAllFilter,
                child: Text('${l10n.taskFilterState}: ${l10n.taskFilterAll}'),
              ),
              for (final state in states)
                DropdownMenuItem(
                  value: state,
                  child:
                      Text('${l10n.taskFilterState}: ${_taskStateLabel(l10n, state)}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) onStateChanged(v);
            },
          ),
        ],
      ),
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

  const _TaskSection({
    required this.title,
    this.tasks = const [],
    this.emptyText = '',
    this.trailing,
    this.body,
    this.filters,
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
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
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
        if (task.projectId != null) l10n.taskProjectLabel(task.projectId!),
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
                if (task.projectId != null) {
                  ref.invalidate(projectJobsProvider(task.projectId!));
                }
              }, successMessage: l10n.taskCanceledMessage),
            ),
          if (task.state == 'failed')
            IconButton(
              tooltip: l10n.commonRetry,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => runAction(context, ref, () async {
                await ref.read(engineProvider).retryJob(task.id);
                if (task.projectId != null) {
                  ref.invalidate(projectJobsProvider(task.projectId!));
                }
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

String _taskClassLabel(AppLocalizations l10n, String taskClass) => switch (taskClass) {
      'event_generation' => l10n.taskClassEventGeneration,
      'asset_extraction' => l10n.taskClassAssetExtraction,
      _ => taskClass.isEmpty ? l10n.taskClassGeneric : taskClass,
    };

IconData _taskIcon(String taskClass) => switch (taskClass) {
      'event_generation' => Icons.auto_awesome_motion_outlined,
      'asset_extraction' => Icons.category_outlined,
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
    if (map.isNotEmpty) related = const JsonEncoder.withIndent('  ').convert(map);
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
                _TaskDetailRow(label: label, value: value ?? l10n.taskDetailNone),
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
    _ => reason.errKey,
  };
}

String _formatTime(int ms) {
  final time = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
