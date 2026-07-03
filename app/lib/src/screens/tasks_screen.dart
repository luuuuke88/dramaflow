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
    final projects = projectsAsync.value ?? const [];
    final effectiveId = selectedId != null &&
            projects.any((project) => project.id == selectedId)
        ? selectedId
        : (projects.isEmpty ? null : projects.first.id);

    return Scaffold(
      appBar: AppBar(title: const Text('任务中心')),
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
                title: '进行中',
                tasks: active,
                emptyText: '当前没有进行中的任务',
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

class _HistorySection extends ConsumerWidget {
  final AsyncValue<List<ProjectRow>> projectsAsync;
  final int? effectiveId;

  const _HistorySection({
    required this.projectsAsync,
    required this.effectiveId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = projectsAsync.value ?? const [];
    if (projectsAsync.isLoading && !projectsAsync.hasValue) {
      return const _TaskSection(title: '历史', body: _CenteredLoader());
    }
    if (projectsAsync.hasError && !projectsAsync.hasValue) {
      return _TaskSection(
        title: '历史',
        body: ErrorCard(
          message: projectsAsync.error.toString(),
          onRetry: () => ref.invalidate(projectsProvider),
        ),
      );
    }
    if (effectiveId == null) {
      return const _TaskSection(
        title: '历史',
        emptyText: '暂无项目',
      );
    }

    final tasksAsync = ref.watch(projectJobsProvider(effectiveId!));
    final picker = DropdownButton<int>(
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
          title: '历史', trailing: picker, body: const _CenteredLoader());
    }
    if (tasksAsync.hasError && !tasksAsync.hasValue) {
      return _TaskSection(
        title: '历史',
        trailing: picker,
        body: ErrorCard(
          message: tasksAsync.error.toString(),
          onRetry: () => ref.invalidate(projectJobsProvider(effectiveId!)),
        ),
      );
    }
    return _TaskSection(
      title: '历史',
      trailing: picker,
      tasks: tasksAsync.value ?? const [],
      emptyText: '该项目暂无历史任务',
    );
  }
}

class _TaskSection extends StatelessWidget {
  final String title;
  final List<TasksRow> tasks;
  final String emptyText;
  final Widget? trailing;
  final Widget? body;

  const _TaskSection({
    required this.title,
    this.tasks = const [],
    this.emptyText = '暂无任务',
    this.trailing,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
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
            if (body != null)
              body!
            else if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  emptyText,
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
      leading: Icon(_taskIcon(task.taskClass), color: context.df.textLo),
      title: Text(_taskClassLabel(task.taskClass)),
      subtitle: Text([
        if (task.describe?.isNotEmpty == true) task.describe!,
        if (task.projectId != null) '项目 #${task.projectId}',
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
              tooltip: '取消任务',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => runAction(context, ref, () async {
                await ref.read(engineProvider).cancelJob(task.id);
                if (task.projectId != null) {
                  ref.invalidate(projectJobsProvider(task.projectId!));
                }
              }, successMessage: '任务已取消'),
            ),
          if (task.state == 'failed')
            IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => runAction(context, ref, () async {
                await ref.read(engineProvider).retryJob(task.id);
                if (task.projectId != null) {
                  ref.invalidate(projectJobsProvider(task.projectId!));
                }
              }, successMessage: '已重新排队'),
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

String _taskClassLabel(String taskClass) => switch (taskClass) {
      'event_generation' => '事件生成',
      'asset_extraction' => '素材提取',
      _ => taskClass.isEmpty ? '任务' : taskClass,
    };

IconData _taskIcon(String taskClass) => switch (taskClass) {
      'event_generation' => Icons.auto_awesome_motion_outlined,
      'asset_extraction' => Icons.category_outlined,
      _ => Icons.bolt_outlined,
    };

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
