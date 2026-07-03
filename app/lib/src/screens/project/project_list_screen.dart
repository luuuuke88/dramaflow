// 项目列表页（照抄 views/project/index.vue）：标题区+新建按钮、3 列卡片网格
// （<1100 两列、<700 单列），卡片=名称+类型圆角签+画风签+简介两行+时间+悬停编辑/删除。
// 点击卡片=选中项目并按类型跳转（novel→/novel，script→/script）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../engine/engine.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';
import 'project_dialog.dart';

final projectsTickProvider = StateProvider<int>((_) => 0);
final projectsProvider = Provider.autoDispose<List<ProjectRow>>((ref) {
  ref.watch(projectsTickProvider);
  return ref.watch(engineProvider).projects();
});
final projectStatsProvider =
    Provider.autoDispose<Map<int, ProjectStats>>((ref) {
  ref.watch(projectsTickProvider);
  return ref.watch(engineProvider).projectStats();
});

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  void _openProject(BuildContext context, WidgetRef ref, ProjectRow project) {
    ref.read(currentProjectProvider.notifier).select(project);
    final section = project.projectType == 'script' ? 'script' : 'novel';
    context.go('/p/${project.id}/$section');
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, ProjectRow project) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.projectMsgDeleteHeader),
        content: Text(l10n.projectMsgDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.projectMsgDeleteCancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.projectMsgDeleteConfirm)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      ref.read(engineProvider).deleteProject(project.id);
      if (ref.read(currentProjectProvider)?.id == project.id) {
        ref.read(currentProjectProvider.notifier).select(null);
      }
      ref.read(projectsTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.projectMsgDeleteSuccess)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(localizeError(context, e))));
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref,
      {ProjectRow? existing}) async {
    final saved = await showProjectDialog(context, existing: existing);
    if (saved == true) {
      ref.read(projectsTickProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    final projects = ref.watch(projectsProvider);
    final stats = ref.watch(projectStatsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.projectTitle,
                  style:
                      DFTokens.display24w700.copyWith(color: df.textPrimary)),
              const SizedBox(height: 4),
              Text(l10n.projectSubtitle,
                  style: TextStyle(fontSize: 13, color: df.textSecondary)),
            ]),
          ),
          FilledButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.projectNewProject),
          ),
        ]),
        const SizedBox(height: 24),
        Expanded(
          child: projects.isEmpty
              ? Center(
                  child: DFEmpty(
                    text: l10n.projectEmpty,
                    action: FilledButton.icon(
                      onPressed: () => _edit(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.projectNewProject),
                    ),
                  ),
                )
              : LayoutBuilder(builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 1100
                      ? 3
                      : constraints.maxWidth >= 700
                          ? 2
                          : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisExtent: 208,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: projects.length,
                    itemBuilder: (c, i) => _ProjectCard(
                      project: projects[i],
                      stats: stats[projects[i].id] ?? const ProjectStats(),
                      onOpen: () => _openProject(context, ref, projects[i]),
                      onEdit: () => _edit(context, ref, existing: projects[i]),
                      onDelete: () => _delete(context, ref, projects[i]),
                    ),
                  );
                }),
        ),
      ]),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  final ProjectRow project;
  final ProjectStats stats;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProjectCard(
      {required this.project,
      required this.stats,
      required this.onOpen,
      required this.onEdit,
      required this.onDelete});

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = context.l10n;
    final p = widget.project;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final showActions = _hover || compact;
    final typeLabel = p.projectType == 'script'
        ? l10n.projectDialogBasedOnScript
        : l10n.projectDialogBasedOnNovel;
    final created = p.createTime == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(DateTime.fromMillisecondsSinceEpoch(p.createTime!));

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: DFTokens.fast120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: df.surface,
            borderRadius: BorderRadius.circular(DFTokens.radiusCard),
            border: Border.all(color: _hover ? df.strokeStrong : df.stroke),
            boxShadow: _hover ? DFTokens.cardHover : DFTokens.cardRest,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  p.name ?? l10n.projectUntitled,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              _RoundTag(text: typeLabel, color: df.primary),
            ]),
            const SizedBox(height: 8),
            if ((p.artStyle ?? '').isNotEmpty)
              _RoundTag(text: p.artStyle!, color: df.accent),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                p.intro ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: df.textSecondary),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _StatTag(text: l10n.projectStatChapters(widget.stats.chapters)),
                _StatTag(text: l10n.projectStatScripts(widget.stats.scripts)),
                _StatTag(text: l10n.projectStatAssets(widget.stats.assets)),
                _StatTag(
                    text:
                        l10n.projectStatStoryboards(widget.stats.storyboards)),
              ],
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(created,
                    style: TextStyle(fontSize: 11, color: df.textTertiary)),
              ),
              if (showActions) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.commonEdit,
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: df.textSecondary),
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.commonDelete,
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: df.textSecondary),
                  onPressed: widget.onDelete,
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StatTag extends StatelessWidget {
  final String text;

  const _StatTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: df.surfaceMuted,
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: df.textTertiary),
      ),
    );
  }
}

class _RoundTag extends StatelessWidget {
  final String text;
  final Color color;
  const _RoundTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
      ),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
