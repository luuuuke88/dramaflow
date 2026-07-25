// 项目列表页（照抄 views/project/index.vue）：标题区+统计角标+搜索+网格/列表视图切换。
// 卡片=名称+类型圆角签+画风签+简介+统计标签+时间+悬停（或触屏常显）编辑/删除。
// 点击卡片=选中项目并按类型跳转（novel→/novel，script→/script）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../engine/engine.dart';
import '../../engine/manuals.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_empty.dart';
import 'project_dialog.dart';
import '../../widgets/df_toast.dart';

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

class ProjectListScreen extends ConsumerStatefulWidget {
  const ProjectListScreen({super.key});

  @override
  ConsumerState<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends ConsumerState<ProjectListScreen> {
  String _searchQuery = '';
  bool _isGridView = true;

  void _openProject(ProjectRow project) {
    ref.read(currentProjectProvider.notifier).select(project);
    final section = project.projectType == 'script' ? 'script' : 'novel';
    context.go('/p/${project.id}/$section');
  }

  Future<void> _delete(ProjectRow project) async {
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
      if (mounted) {
        showDFToast(context, l10n.projectMsgDeleteSuccess);
      }
    } catch (e) {
      if (mounted) {
        showDFToast(context, localizeError(context, e));
      }
    }
  }

  Future<void> _edit({ProjectRow? existing}) async {
    final saved = await showProjectDialog(context, existing: existing);
    if (saved == true) {
      ref.read(projectsTickProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final projects = ref.watch(projectsProvider);
    final stats = ref.watch(projectStatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final visualStyleNames = {
      for (final pack in ref.watch(engineProvider).visualManuals())
        pack.pack: pack.name,
    };

    final filteredProjects = [
      for (final p in projects)
        if (_searchQuery.isEmpty ||
            (p.name?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                false) ||
            (p.intro?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                false))
          p,
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // 与 AppShell 的移动断点保持一致：700-839dp 的平板仍走移动壳，触控没有
      // hover，标题堆叠、搜索/切换控件尺寸也统一按这一断点收紧。
      final compact = constraints.maxWidth < 840;

      final headerInfo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Text(
                l10n.projectTitle,
                style: TextStyle(
                    fontSize: compact ? 28 : 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: df.textPrimary),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: df.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  l10n.projectStatTotalProjects(projects.length),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: df.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.projectSubtitle,
            style:
                TextStyle(fontSize: compact ? 14 : 16, color: df.textSecondary),
          ),
        ],
      );

      final newProjectBtn = FilledButton.icon(
        onPressed: () => _edit(),
        icon: Icon(Icons.add_rounded, size: compact ? 20 : 22),
        label: Text(l10n.projectNewProject,
            style: TextStyle(
                fontSize: compact ? 15 : 16, fontWeight: FontWeight.w700)),
        style: ButtonStyle(
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
                horizontal: compact ? 16 : 32, vertical: compact ? 16 : 20),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );

      final header = compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerInfo,
                const SizedBox(height: 24),
                newProjectBtn,
              ],
            )
          : Row(
              children: [
                Expanded(child: headerInfo),
                newProjectBtn,
              ],
            );

      final searchBar = Container(
        height: compact ? 46 : 56,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C24) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: l10n.projectSearchPlaceholder,
            hintStyle: TextStyle(fontSize: 15, color: df.textTertiary),
            prefixIcon:
                Icon(Icons.search_rounded, size: 20, color: df.textTertiary),
            contentPadding:
                EdgeInsets.symmetric(horizontal: compact ? 16 : 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

      final viewSwitcher = Container(
        height: compact ? 46 : 56,
        padding: EdgeInsets.all(compact ? 4 : 6),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1C24).withValues(alpha: 0.6)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _isGridView = true),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 20, vertical: compact ? 6 : 10),
                decoration: BoxDecoration(
                  color: _isGridView
                      ? (isDark ? const Color(0xFF2C2C34) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: _isGridView
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      size: 18,
                      color: _isGridView ? df.primary : df.textTertiary,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.projectViewGrid,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              _isGridView ? FontWeight.w700 : FontWeight.w500,
                          color: _isGridView ? df.primary : df.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _isGridView = false),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 20, vertical: compact ? 6 : 10),
                decoration: BoxDecoration(
                  color: !_isGridView
                      ? (isDark ? const Color(0xFF2C2C34) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: !_isGridView
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.view_headline_rounded,
                      size: 18,
                      color: !_isGridView ? df.primary : df.textTertiary,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.projectViewList,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              !_isGridView ? FontWeight.w700 : FontWeight.w500,
                          color: !_isGridView ? df.primary : df.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      final controlStrip = Row(
        children: [
          Expanded(child: searchBar),
          SizedBox(width: compact ? 12 : 32),
          viewSwitcher,
        ],
      );

      return Padding(
        // 手机壳（compact）有悬浮底部导航，底部要预留出它的高度。
        padding: EdgeInsets.fromLTRB(compact ? 20 : 40, compact ? 20 : 36,
            compact ? 20 : 40, compact ? 120 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            SizedBox(height: compact ? 24 : 36),
            controlStrip,
            SizedBox(height: compact ? 24 : 36),
            Expanded(
              child: filteredProjects.isEmpty
                  ? Center(
                      child: DFEmpty(
                        text: l10n.projectEmpty,
                        description: l10n.projectEmptySubtitle,
                        action: FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l10n.projectNewProject),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    )
                  : _isGridView
                      ? _buildGridView(
                          context, filteredProjects, stats, visualStyleNames)
                      : _buildListView(
                          context, filteredProjects, stats, visualStyleNames),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildGridView(
      BuildContext context,
      List<ProjectRow> projects,
      Map<int, ProjectStats> stats,
      Map<String, String> visualStyleNames) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth >= 1200
          ? 3
          : constraints.maxWidth >= 720
              ? 2
              : 1;
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisExtent: constraints.maxWidth < 840 ? 164 : 184,
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
        ),
        itemCount: projects.length,
        itemBuilder: (c, i) => _ProjectCard(
          project: projects[i],
          stats: stats[projects[i].id] ?? const ProjectStats(),
          styleLabel: visualStyleNames[projects[i].artStyle],
          onOpen: () => _openProject(projects[i]),
          onEdit: () => _edit(existing: projects[i]),
          onDelete: () => _delete(projects[i]),
        ),
      );
    });
  }

  Widget _buildListView(
      BuildContext context,
      List<ProjectRow> projects,
      Map<int, ProjectStats> stats,
      Map<String, String> visualStyleNames) {
    final df = context.df;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final project = projects[index];
        final pStats = stats[project.id] ?? const ProjectStats();
        final styleLabel = visualStyleNames[project.artStyle];

        return _ProjectListItem(
          project: project,
          stats: pStats,
          styleLabel: styleLabel,
          isDark: isDark,
          df: df,
          onOpen: () => _openProject(project),
          onEdit: () => _edit(existing: project),
          onDelete: () => _delete(project),
        );
      },
    );
  }
}

class _ProjectCard extends StatefulWidget {
  final ProjectRow project;
  final ProjectStats stats;
  final String? styleLabel;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.stats,
    required this.styleLabel,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

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
    // 与 AppShell 的移动断点保持一致：700-839dp 的平板仍走移动壳，
    // 触控没有 hover，编辑/删除操作必须常显。
    final compact = MediaQuery.sizeOf(context).width < 840;
    final showActions = _hover || compact;
    final typeLabel = p.projectType == 'script'
        ? l10n.projectDialogBasedOnScript
        : l10n.projectDialogBasedOnNovel;
    final created = p.createTime == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(p.createTime!));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: DFTokens.fast120,
            padding: EdgeInsets.all(compact ? 14 : 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C24) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _hover
                      ? Colors.black.withValues(alpha: isDark ? 0.4 : 0.08)
                      : Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: _hover ? 32 : 16,
                  offset: _hover ? const Offset(0, 12) : const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name ?? l10n.projectUntitled,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: compact ? 16 : 18,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    _RoundTag(text: typeLabel, color: df.primary),
                  ],
                ),
                SizedBox(height: compact ? 6 : 8),
                Row(
                  children: [
                    if ((p.artStyle ?? '').isNotEmpty) ...[
                      _RoundTag(
                          text: widget.styleLabel ?? p.artStyle!,
                          color: df.accent),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        created,
                        style: TextStyle(fontSize: 11, color: df.textTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    p.intro ?? '',
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: df.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StatTag(
                              text: l10n
                                  .projectStatChapters(widget.stats.chapters)),
                          _StatTag(
                              text: l10n
                                  .projectStatScripts(widget.stats.scripts)),
                          _StatTag(
                              text:
                                  l10n.projectStatAssets(widget.stats.assets)),
                          _StatTag(
                              text: l10n.projectStatStoryboards(
                                  widget.stats.storyboards)),
                        ],
                      ),
                    ),
                    if (showActions) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.commonEdit,
                        icon: Icon(Icons.edit_outlined,
                            size: 18, color: df.textSecondary),
                        onPressed: widget.onEdit,
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.commonDelete,
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: df.textSecondary),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectListItem extends StatelessWidget {
  final ProjectRow project;
  final ProjectStats stats;
  final String? styleLabel;
  final bool isDark;
  final DFColors df;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProjectListItem({
    required this.project,
    required this.stats,
    required this.styleLabel,
    required this.isDark,
    required this.df,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typeLabel = project.projectType == 'script'
        ? l10n.projectDialogBasedOnScript
        : l10n.projectDialogBasedOnNovel;
    final created = project.createTime == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(project.createTime!));

    // 与 AppShell 的移动断点保持一致，跟 _ProjectCard 用同一条线。
    final compact = MediaQuery.sizeOf(context).width < 840;

    final actionsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.commonEdit,
          icon: Icon(Icons.edit_outlined,
              size: compact ? 16 : 18, color: df.textSecondary),
          onPressed: onEdit,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.commonDelete,
          icon: Icon(Icons.delete_outline,
              size: compact ? 16 : 18, color: df.textSecondary),
          onPressed: onDelete,
        ),
      ],
    );

    Widget contentWidget;

    if (compact) {
      // 极简手机端列表项
      contentWidget = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: df.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              project.projectType == 'script'
                  ? Icons.description_outlined
                  : Icons.menu_book_outlined,
              color: df.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        project.name ?? l10n.projectUntitled,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if ((project.artStyle ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _RoundTag(
                          text: styleLabel ?? project.artStyle!,
                          color: df.accent),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  created,
                  style: TextStyle(fontSize: 11, color: df.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          actionsRow,
        ],
      );
    } else {
      // 桌面端完整信息
      final headerInfo = Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: df.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              project.projectType == 'script'
                  ? Icons.description_outlined
                  : Icons.menu_book_outlined,
              color: df.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      project.name ?? l10n.projectUntitled,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    _RoundTag(text: typeLabel, color: df.primary),
                    if ((project.artStyle ?? '').isNotEmpty)
                      _RoundTag(
                          text: styleLabel ?? project.artStyle!,
                          color: df.accent),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  project.intro ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: df.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );

      final statsRow = Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _StatTag(text: l10n.projectStatChapters(stats.chapters)),
          _StatTag(text: l10n.projectStatScripts(stats.scripts)),
          _StatTag(text: l10n.projectStatAssets(stats.assets)),
          _StatTag(text: l10n.projectStatStoryboards(stats.storyboards)),
        ],
      );

      contentWidget = Row(
        children: [
          Expanded(child: headerInfo),
          const SizedBox(width: 20),
          statsRow,
          const SizedBox(width: 20),
          Text(
            created,
            style: TextStyle(fontSize: 12, color: df.textTertiary),
          ),
          const SizedBox(width: 12),
          actionsRow,
        ],
      );
    }

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(compact ? 12 : 14),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 20, vertical: compact ? 10 : 16),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1C24).withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.85),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: contentWidget,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: df.surfaceMuted,
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DFTokens.caption12.copyWith(color: df.textTertiary),
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
