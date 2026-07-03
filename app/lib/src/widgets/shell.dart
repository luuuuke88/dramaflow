// ToonFlow 工作台壳 1:1 移植（Toonflow-web src/pages/workbench/index.vue）：
// 桌面 ≥840：左侧细图标栏（Logo/我的项目/任务中心 + 底部反馈·设置·GitHub）
//           + 顶栏 50px（项目名 | 项目内菜单右对齐）+ 圆角内容区。
// 移动 <840：底部导航（项目/任务/设置），项目内子页由顶部横向 Tab 承接。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/engine.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';

const _githubUrl = 'https://github.com/HBAI-Ltd/Toonflow-app';
const _feedbackUrl = 'https://github.com/HBAI-Ltd/Toonflow-app/issues';

/// 项目内菜单定义（顺序照抄 ToonFlow workbench 顶栏）。P1-P5 全部批次已交付，
/// 各分区均为真实功能（无占位）。
class _ProjectMenu {
  final String path; // 相对项目根：novel/scriptAgent/script/cornerScape/production/assets
  final String Function(BuildContext) label;
  final IconData icon;
  final bool novelOnly;
  const _ProjectMenu(this.path, this.label, this.icon,
      {this.novelOnly = false});
}

final _projectMenus = <_ProjectMenu>[
  _ProjectMenu('novel', (c) => c.l10n.menuNovel, Icons.menu_book_outlined,
      novelOnly: true),
  _ProjectMenu(
      'scriptAgent', (c) => c.l10n.menuScriptAgent, Icons.auto_awesome_outlined,
      novelOnly: true),
  _ProjectMenu(
      'script', (c) => c.l10n.menuScriptManage, Icons.description_outlined),
  _ProjectMenu('cornerScape', (c) => c.l10n.menuCornerScape,
      Icons.record_voice_over_outlined),
  _ProjectMenu(
      'production', (c) => c.l10n.menuProduction, Icons.movie_filter_outlined),
  _ProjectMenu(
      'assets', (c) => c.l10n.menuAssetCenter, Icons.inventory_2_outlined),
];

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  int? _projectIdFromPath(String path) {
    final m = RegExp(r'^/p/(\d+)/').firstMatch(path);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final pid = _projectIdFromPath(path);
    if (pid != null) {
      // 深链/刷新回填当前项目
      Future.microtask(
          () => ref.read(currentProjectProvider.notifier).ensure(pid));
    }
    final project = ref.watch(currentProjectProvider);

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      return wide
          ? _DesktopShell(path: path, project: project, child: child)
          : _MobileShell(path: path, project: project, child: child);
    });
  }
}

// ───────────────────────── 桌面壳 ─────────────────────────

class _DesktopShell extends ConsumerWidget {
  final String path;
  final ProjectRow? project;
  final Widget child;
  const _DesktopShell(
      {required this.path, required this.project, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    return Scaffold(
      backgroundColor: df.bg,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          _SideBar(path: path),
          const SizedBox(width: 12),
          Expanded(
            child: Column(children: [
              _TopBar(path: path, project: project),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: df.surface,
                    borderRadius: BorderRadius.circular(DFTokens.radiusShell),
                    border: Border.all(color: df.stroke),
                  ),
                  child: child,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SideBar extends ConsumerWidget {
  final String path;
  const _SideBar({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    final activeCount = ref.watch(activeJobsProvider).length;

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusShell),
        border: Border.all(color: df.stroke),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        const DFLogo(),
        const SizedBox(height: 20),
        _SideIcon(
          tooltip: context.l10n.menuMyProject,
          icon: Icons.folder_outlined,
          selected: path == '/' || path.startsWith('/p/'),
          onTap: () => context.go('/'),
        ),
        _SideIcon(
          tooltip: context.l10n.menuTaskCenter,
          icon: Icons.view_list_outlined,
          selected: path.startsWith('/tasks'),
          badgeCount: activeCount,
          onTap: () => context.go('/tasks'),
        ),
        const Spacer(),
        _SideIcon(
          tooltip: context.l10n.menuFeedbackQuestions,
          icon: Icons.feedback_outlined,
          onTap: () => launchUrl(Uri.parse(_feedbackUrl)),
        ),
        _SideIcon(
          tooltip: context.l10n.menuSettings,
          icon: Icons.settings_outlined,
          selected: path.startsWith('/settings'),
          onTap: () => context.go('/settings'),
        ),
        _SideIcon(
          tooltip: context.l10n.menuJumpGithub,
          icon: Icons.code_rounded,
          onTap: () => launchUrl(Uri.parse(_githubUrl)),
        ),
      ]),
    );
  }
}

class _SideIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final int badgeCount;
  final VoidCallback? onTap;
  const _SideIcon(
      {required this.tooltip,
      required this.icon,
      this.selected = false,
      this.badgeCount = 0,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final iconWidget = Badge(
      isLabelVisible: badgeCount > 0,
      label: Text('$badgeCount'),
      backgroundColor: df.accent,
      child: Icon(icon,
          size: 22, color: selected ? df.primary : df.textSecondary),
    );
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: selected ? df.primarySubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(DFTokens.radiusControl),
          child: InkWell(
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: iconWidget),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final String path;
  final ProjectRow? project;
  const _TopBar({required this.path, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    return SizedBox(
      height: 50,
      child: Row(children: [
        Expanded(
          child: Text(
            project?.name ?? context.l10n.shellSelectProject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: project == null ? df.textTertiary : df.textPrimary,
            ),
          ),
        ),
        for (final menu in _visibleProjectMenus(project)) ...[
          if (menu.path == 'assets')
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: df.stroke,
            ),
          _TopMenuButton(menu: menu, path: path, project: project),
        ],
      ]),
    );
  }
}

/// projectType=script 的项目隐藏 novelOnly 项（照抄 workbench 逻辑）。
List<_ProjectMenu> _visibleProjectMenus(ProjectRow? project) => [
      for (final m in _projectMenus)
        if (!(m.novelOnly && project?.projectType == 'script')) m,
    ];

class _TopMenuButton extends ConsumerWidget {
  final _ProjectMenu menu;
  final String path;
  final ProjectRow? project;
  const _TopMenuButton(
      {required this.menu, required this.path, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    final enabled = project != null;
    final selected =
        project != null && path.startsWith('/p/${project!.id}/${menu.path}');

    final button = Material(
      color: selected ? df.primarySubtle : Colors.transparent,
      borderRadius: BorderRadius.circular(DFTokens.radiusControl),
      child: InkWell(
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
        onTap: enabled
            ? () => context.go('/p/${project!.id}/${menu.path}')
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(menu.icon,
                size: 18,
                color: !enabled
                    ? df.textTertiary
                    : (selected ? df.primary : df.textSecondary)),
            const SizedBox(width: 6),
            Text(
              menu.label(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: !enabled
                    ? df.textTertiary
                    : (selected ? df.primary : df.textPrimary),
              ),
            ),
          ]),
        ),
      ),
    );
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2), child: button);
  }
}

// ───────────────────────── 移动壳 ─────────────────────────

class _MobileShell extends ConsumerWidget {
  final String path;
  final ProjectRow? project;
  final Widget child;
  const _MobileShell(
      {required this.path, required this.project, required this.child});

  int get _tabIndex {
    if (path.startsWith('/tasks')) return 1;
    if (path.startsWith('/settings')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = context.df;
    final activeCount = ref.watch(activeJobsProvider).length;
    final inProject = project != null && path.startsWith('/p/');

    Widget taskIcon(bool active) => Badge(
          isLabelVisible: activeCount > 0,
          label: Text('$activeCount'),
          backgroundColor: df.accent,
          child: Icon(active ? Icons.view_list : Icons.view_list_outlined),
        );

    return Scaffold(
      backgroundColor: df.bg,
      appBar: inProject
          ? AppBar(
              title: Text(project!.name ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              leading: BackButton(onPressed: () => context.go('/')),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: _MobileProjectTabs(path: path, project: project!),
              ),
            )
          : null,
      body: inProject ? child : SafeArea(bottom: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        height: 64,
        onDestinationSelected: (i) =>
            context.go(const ['/', '/tasks', '/settings'][i]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: context.l10n.menuMyProject,
          ),
          NavigationDestination(
            icon: taskIcon(false),
            selectedIcon: taskIcon(true),
            label: context.l10n.menuTaskCenter,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: context.l10n.menuSettings,
          ),
        ],
      ),
    );
  }
}

class _MobileProjectTabs extends StatelessWidget {
  final String path;
  final ProjectRow project;
  const _MobileProjectTabs({required this.path, required this.project});

  @override
  Widget build(BuildContext context) {
    final menus = _visibleProjectMenus(project);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final menu in menus)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: _MobileTabChip(menu: menu, path: path, project: project),
            ),
        ],
      ),
    );
  }
}

class _MobileTabChip extends StatelessWidget {
  final _ProjectMenu menu;
  final String path;
  final ProjectRow project;
  const _MobileTabChip(
      {required this.menu, required this.path, required this.project});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final selected = path.startsWith('/p/${project.id}/${menu.path}');
    return Material(
      color: selected ? df.primarySubtle : df.surfaceMuted,
      borderRadius: BorderRadius.circular(DFTokens.radiusChip),
      child: InkWell(
        borderRadius: BorderRadius.circular(DFTokens.radiusChip),
        onTap: () => context.go('/p/${project.id}/${menu.path}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            menu.label(context),
            style: TextStyle(
              fontSize: 13,
              color: selected ? df.primary : df.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 品牌 Logo（墨青→琥珀渐变）。
class DFLogo extends StatelessWidget {
  const DFLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [df.primary, df.accent],
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(Icons.play_arrow_rounded,
          color: Theme.of(context).colorScheme.onPrimary, size: 24),
    );
  }
}

/// 页面级内容容器：统一最大宽度与内边距，避免超宽屏内容拉满。
class PageContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const PageContainer({super.key, required this.child, this.maxWidth = 1200});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: child,
        ),
      ),
    );
  }
}
