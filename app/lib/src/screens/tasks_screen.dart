import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
      appBar: AppBar(
        backgroundColor: _lightAppBarBackground(context),
        bottom: _lightAppBarBottom(context),
        title: const Text('任务中心'),
      ),
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
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: _JobTableSection(
                  title: '进行中',
                  trailing: active.isEmpty ? null : '${active.length} 个任务',
                  jobs: active,
                  active: true,
                  emptyText: '当前没有进行中的任务',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ..._historySlivers(context, ref, projectsAsync, effectiveId),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _historySlivers(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Project>> projectsAsync,
    String? effectiveId,
  ) {
    final historyPicker = _ProjectPicker(
      projects: projectsAsync.value ?? const <Project>[],
      effectiveId: effectiveId,
    );
    if (projectsAsync.isLoading && !projectsAsync.hasValue) {
      return [
        SliverToBoxAdapter(
          child: _JobTableSection(
            title: '历史',
            accessory: historyPicker,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: CircularProgressIndicator(color: context.df.primary),
              ),
            ),
          ),
        ),
      ];
    }
    if (projectsAsync.hasError && !projectsAsync.hasValue) {
      return [
        SliverToBoxAdapter(
          child: _JobTableSection(
            title: '历史',
            accessory: historyPicker,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorCard(
                message: projectsAsync.error.toString(),
                onRetry: () => ref.invalidate(projectsProvider),
              ),
            ),
          ),
        ),
      ];
    }
    if (effectiveId == null) {
      return [
        SliverToBoxAdapter(
          child: _JobTableSection(
            title: '历史',
            body: const EmptyHint(
              icon: Icons.folder_off_outlined,
              title: '暂无项目',
              subtitle: '创建项目并发起生成后，这里会显示任务历史',
            ),
          ),
        ),
      ];
    }

    final jobsAsync = ref.watch(projectJobsProvider(effectiveId));
    if (jobsAsync.isLoading && !jobsAsync.hasValue) {
      return [
        SliverToBoxAdapter(
          child: _JobTableSection(
            title: '历史',
            accessory: historyPicker,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: CircularProgressIndicator(color: context.df.primary),
              ),
            ),
          ),
        ),
      ];
    }
    if (jobsAsync.hasError && !jobsAsync.hasValue) {
      return [
        SliverToBoxAdapter(
          child: _JobTableSection(
            title: '历史',
            accessory: historyPicker,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorCard(
                message: jobsAsync.error.toString(),
                onRetry: () => ref.invalidate(projectJobsProvider(effectiveId)),
              ),
            ),
          ),
        ),
      ];
    }
    final jobs = (jobsAsync.value ?? const <Job>[]).take(50).toList();
    return [
      SliverToBoxAdapter(
        child: _JobTableSection(
          title: '历史',
          accessory: historyPicker,
          trailing: jobs.isEmpty ? null : '最近 ${jobs.length} 条',
          jobs: jobs,
          emptyText: '该项目暂无历史任务',
        ),
      ),
    ];
  }
}

const _statusColumnWidth = 96.0;
const _typeColumnWidth = 132.0;
const _durationColumnWidth = 84.0;
const _finishedColumnWidth = 104.0;
const _actionColumnWidth = 76.0;
const _tableMinWidth = 760.0;

/// 历史区项目选择器。
class _ProjectPicker extends ConsumerWidget {
  final List<Project> projects;
  final String? effectiveId;

  const _ProjectPicker({required this.projects, required this.effectiveId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (projects.isEmpty) return const SizedBox.shrink();
    return DropdownMenu<String>(
      key: ValueKey('history-project-$effectiveId'),
      initialSelection: effectiveId,
      width: 220,
      requestFocusOnTap: false,
      leadingIcon:
          Icon(Icons.movie_outlined, size: 18, color: context.df.textLo),
      textStyle: TextStyle(fontSize: 13, color: context.df.textHi),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: context.df.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: context.df.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: context.df.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: context.df.primary, width: 1.5),
        ),
      ),
      dropdownMenuEntries: [
        for (final p in projects) DropdownMenuEntry(value: p.id, label: p.name),
      ],
      onSelected: (v) {
        if (v != null) {
          ref.read(_selectedProjectProvider.notifier).state = v;
        }
      },
    );
  }
}

class _JobTableSection extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? accessory;
  final List<Job> jobs;
  final bool active;
  final String emptyText;
  final Widget? body;

  const _JobTableSection({
    required this.title,
    this.trailing,
    this.accessory,
    this.jobs = const [],
    this.active = false,
    this.emptyText = '暂无任务',
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    trailing!,
                    style: TextStyle(color: context.df.textLo, fontSize: 12),
                  ),
                ],
                if (accessory != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: accessory!,
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
          const Divider(height: 1),
          if (body != null)
            body!
          else if (jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
              child: Text(
                emptyText,
                style: TextStyle(color: context.df.textLo, fontSize: 13),
              ),
            )
          else
            _JobTable(jobs: jobs, active: active),
        ],
      ),
    );
  }
}

class _JobTable extends StatelessWidget {
  final List<Job> jobs;
  final bool active;

  const _JobTable({required this.jobs, required this.active});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, _tableMinWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                const _JobTableHeader(),
                for (final (i, job) in jobs.indexed)
                  _JobTableRow(
                    job: job,
                    active: active,
                    isLast: i == jobs.length - 1,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JobTableHeader extends StatelessWidget {
  const _JobTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.df.bg,
        border: Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: const [
          _HeaderCell('状态', width: _statusColumnWidth),
          _HeaderCell('类型', width: _typeColumnWidth),
          Expanded(child: _HeaderCell('目标')),
          _HeaderCell('耗时', width: _durationColumnWidth),
          _HeaderCell('完成时间', width: _finishedColumnWidth),
          _HeaderCell('操作', width: _actionColumnWidth, alignRight: true),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final double? width;
  final bool alignRight;

  const _HeaderCell(this.label, {this.width, this.alignRight = false});

  @override
  Widget build(BuildContext context) {
    final child = Text(
      label,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: context.df.textLo,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
    if (width == null) return child;
    return SizedBox(width: width, child: child);
  }
}

class _JobTableRow extends ConsumerWidget {
  final Job job;
  final bool active;
  final bool isLast;

  const _JobTableRow({
    required this.job,
    required this.active,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active && job.state == 'failed') {
      return _FailedJobTableRow(job: job, isLast: isLast);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: _JobRowContent(
        job: job,
        action: active && job.state == 'queued'
            ? IconButton(
                tooltip: '取消任务',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.df.textLo,
                ),
                onPressed: () => runAction(context, ref, () async {
                  await ref.read(engineProvider).cancelJob(job.id);
                  ref.invalidate(projectJobsProvider(job.projectId));
                }, successMessage: '任务已取消'),
              )
            : const _ActionPlaceholder(),
      ),
    );
  }
}

class _FailedJobTableRow extends ConsumerStatefulWidget {
  final Job job;
  final bool isLast;

  const _FailedJobTableRow({required this.job, required this.isLast});

  @override
  ConsumerState<_FailedJobTableRow> createState() => _FailedJobTableRowState();
}

class _FailedJobTableRowState extends ConsumerState<_FailedJobTableRow> {
  bool _expanded = false;

  Future<void> _retry() => runAction(context, ref, () async {
        await ref.read(engineProvider).retryJob(widget.job.id);
        ref.invalidate(projectJobsProvider(widget.job.projectId));
      }, successMessage: '已重新排队');

  @override
  Widget build(BuildContext context) {
    final error =
        (widget.job.error?.isNotEmpty ?? false) ? widget.job.error! : '未知错误';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: context.df.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: _JobRowContent(
              job: widget.job,
              action: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '重试',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.refresh_rounded,
                        size: 17, color: context.df.red),
                    onPressed: _retry,
                  ),
                  IconButton(
                    tooltip: _expanded ? '收起原因' : '查看原因',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: context.df.textLo,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                242,
                0,
                14,
                12,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.df.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: context.df.red.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      error,
                      style: TextStyle(
                        color: context.df.red,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('重试'),
                        onPressed: _retry,
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
}

class _JobRowContent extends StatelessWidget {
  final Job job;
  final Widget action;

  const _JobRowContent({required this.job, required this.action});

  @override
  Widget build(BuildContext context) {
    final duration = _fmtDuration(job.durationMs);
    final finished = job.finishedAt == null ? '—' : _hms(job.finishedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: _statusColumnWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                job.state,
                dense: true,
                errorTooltip: job.error,
              ),
            ),
          ),
          SizedBox(
            width: _typeColumnWidth,
            child: Row(
              children: [
                Icon(_kindIcon(job.kind), size: 16, color: context.df.textLo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _kindLabel(job.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.df.textHi,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              job.targetLabel.isEmpty ? '—' : job.targetLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.df.textMid, fontSize: 12.5),
            ),
          ),
          _ValueCell(duration.isEmpty ? '—' : duration,
              width: _durationColumnWidth),
          _ValueCell(finished, width: _finishedColumnWidth),
          SizedBox(
            width: _actionColumnWidth,
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String value;
  final double width;

  const _ValueCell(this.value, {required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.df.textLo, fontSize: 12),
      ),
    );
  }
}

class _ActionPlaceholder extends StatelessWidget {
  const _ActionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Text(
      '—',
      style: TextStyle(color: context.df.textLo, fontSize: 12),
    );
  }
}
