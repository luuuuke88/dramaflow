// ToonFlow 工作台壳 1:1 移植（Toonflow-web src/pages/workbench/index.vue）：
// 桌面 ≥840：左侧细图标栏（Logo/我的项目/任务中心 + 底部反馈·设置·GitHub）
//           + 顶栏 50px（项目名 | 项目内菜单右对齐）+ 圆角内容区。
// 移动 <840：底部导航（项目/任务/设置），项目内子页由顶部横向 Tab 承接。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/engine.dart';
import '../screens/project/project_dialog.dart';
import '../state/providers.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/l10n_ext.dart';

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
    final inProject = path.startsWith('/p/');

    return Scaffold(
      backgroundColor: df.bg,
      body: Row(children: [
        // 满版大气侧边栏（全高连贯布局，无零碎内缩外边距框）
        _SideBar(path: path),
        // 主内容画布（通透满版无缩进）
        Expanded(
          child: Column(children: [
            // 仅在点进具体项目（/p/:pid/...）时展示顶栏
            if (inProject) _TopBar(path: path, project: project),
            Expanded(
              child: Container(
                width: double.infinity,
                color: df.bg,
                child: child,
              ),
            ),
          ]),
        ),
      ]),
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

    final isProject = path == '/' || path.startsWith('/p/');
    final isTasks = path.startsWith('/tasks');
    final isSettings = path.startsWith('/settings');

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: df.surface,
        border: Border(
          right: BorderSide(
            color: df.stroke.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(children: [
        const DFLogo(),
        const SizedBox(height: 24),
        // 核心导航区
        _SideIcon(
          tooltip: context.l10n.menuMyProject,
          icon: Icons.grid_view_rounded,
          selected: isProject,
          onTap: () => context.go('/'),
        ),
        _SideIcon(
          tooltip: context.l10n.menuTaskCenter,
          icon: Icons.view_stream_rounded,
          selected: isTasks,
          badgeCount: activeCount,
          onTap: () => context.go('/tasks'),
        ),
        const Spacer(),
        // 下方系统操作区：【设置】与【反馈】
        _SideIcon(
          tooltip: context.l10n.menuSettings,
          icon: Icons.settings_rounded,
          selected: isSettings,
          onTap: () => context.go('/settings'),
        ),
        _SideIcon(
          tooltip: context.l10n.menuFeedbackQuestions,
          icon: Icons.help_outline_rounded,
          onTap: () => launchUrl(Uri.parse(_feedbackUrl)),
        ),
      ]),
    );
  }
}

class _SideIcon extends StatefulWidget {
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
  State<_SideIcon> createState() => _SideIconState();
}

class _SideIconState extends State<_SideIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final isSelected = widget.selected;

    final targetColor = isSelected
        ? df.primary
        : (_hover ? df.primary.withValues(alpha: 0.85) : df.textSecondary);

    final iconWidget = Badge(
      isLabelVisible: widget.badgeCount > 0,
      label: Text('${widget.badgeCount}'),
      backgroundColor: df.accent,
      child: AnimatedScale(
        scale: _hover ? 1.12 : (isSelected ? 1.05 : 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Icon(
          widget.icon,
          size: 21,
          color: targetColor,
        ),
      ),
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  iconWidget,
                  if (isSelected)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 3.5,
                        height: 16,
                        decoration: BoxDecoration(
                          color: df.primary,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
    final visibleMenus = _visibleProjectMenus(project);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: df.surface,
        border: Border(
          bottom: BorderSide(
            color: df.stroke.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(children: [
        // 左上角当前项目 Switcher Pill（大气大号按键）
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: df.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: df.stroke.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                project != null
                    ? Icons.movie_creation_outlined
                    : Icons.auto_awesome_mosaic_outlined,
                size: 18,
                color: project != null ? df.primary : df.textTertiary,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  project?.name ?? context.l10n.shellSelectProject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: project == null ? df.textTertiary : df.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: df.textSecondary,
              ),
            ],
          ),
        ),
        const Spacer(),
        // 右上角项目功能 Segmented 选项卡（大气舒展布局）
        if (visibleMenus.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: df.surfaceMuted.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: df.stroke.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final menu in visibleMenus) ...[
                  if (menu.path == 'assets')
                    Container(
                      width: 1,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: df.stroke.withValues(alpha: 0.5),
                    ),
                  _TopMenuButton(menu: menu, path: path, project: project),
                ],
              ],
            ),
          ),
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

  void _handleTap(BuildContext context, WidgetRef ref) async {
    if (project != null) {
      context.go('/p/${project!.id}/${menu.path}');
      return;
    }
    final projects = ref.read(engineProvider).projects();
    if (projects.isNotEmpty) {
      final target = projects.first;
      ref.read(currentProjectProvider.notifier).select(target);
      if (context.mounted) context.go('/p/${target.id}/${menu.path}');
    } else {
      final created = await showProjectDialog(context);
      if (created == true && context.mounted) {
        final newProjects = ref.read(engineProvider).projects();
        if (newProjects.isNotEmpty) {
          final target = newProjects.first;
          ref.read(currentProjectProvider.notifier).select(target);
          if (context.mounted) context.go('/p/${target.id}/${menu.path}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuFullPath = project != null ? '/p/${project!.id}/${menu.path}' : '';
    final selected = project != null &&
        (path == menuFullPath || path.startsWith('$menuFullPath/'));
    return _NavPill(
      selected: selected,
      label: menu.label(context),
      icon: menu.icon,
      onTap: () => _handleTap(context, ref),
    );
  }
}

/// 纯视觉 hover 药丸按钮，不持有任何路由 context
class _NavPill extends StatefulWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NavPill({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_NavPill> createState() => _NavPillState();
}

class _NavPillState extends State<_NavPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final isSelected = widget.selected;
    final Color fg = isSelected
        ? df.primary
        : (_hover ? df.primary : df.textSecondary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? df.surface
                : (_hover ? df.surfaceMuted : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected
                  ? df.stroke.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

/// 品牌 Logo："层叠分镜"：三张错位旋转的圆角卡片代表小说→分镜→成片的流水线，
/// 最前一张卡片上嵌入播放三角。纯代码绘制，跟随主题 primary/accent 自动换色。
class DFLogo extends StatelessWidget {
  const DFLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _DFLogoPainter(primary: df.primary, accent: df.accent),
      ),
    );
  }
}

class _DFLogoPainter extends CustomPainter {
  final Color primary;
  final Color accent;
  const _DFLogoPainter({required this.primary, required this.accent});

  static const _squareRect = Rect.fromLTWH(9, 9, 22, 22);
  static final _rrect =
      RRect.fromRectAndRadius(_squareRect, const Radius.circular(6.5));
  static final _triangle = Path()
    ..moveTo(17.3, 14.6)
    ..lineTo(26, 20)
    ..lineTo(17.3, 25.4)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    void withRotation(double degrees, void Function() draw) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(degrees * math.pi / 180);
      canvas.translate(-center.dx, -center.dy);
      draw();
      canvas.restore();
    }

    withRotation(-14, () => canvas.drawRRect(
        _rrect, Paint()..color = primary.withValues(alpha: 0.28)));
    withRotation(7, () => canvas.drawRRect(
        _rrect, Paint()..color = primary.withValues(alpha: 0.55)));
    withRotation(-2, () {
      canvas.drawRRect(_rrect, Paint()..color = primary);
      canvas.drawPath(_triangle, Paint()..color = accent);
    });
  }

  @override
  bool shouldRepaint(covariant _DFLogoPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.accent != accent;
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
