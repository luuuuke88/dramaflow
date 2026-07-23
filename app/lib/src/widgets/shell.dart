// ToonFlow 工作台壳 1:1 移植（Toonflow-web src/pages/workbench/index.vue）：
// 桌面 ≥840：左侧细图标栏（Logo/我的项目/任务中心 + 底部反馈·设置·GitHub）
import 'dart:async';
import 'dart:ui';
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

/// 玻璃质感胶囊（侧栏/移动端底部导航共用）的渐变底色：不用 BackdropFilter 真实模糊
/// （会跟路由/弹窗动画冲突导致渲染错乱，见 _SideBar 里的说明），改用左上到右下的
/// 双色渐变 + 顶部高光边，模拟玻璃的光影层次，纯色调也不至于显得单薄。
LinearGradient glassGradient(DFColors df, bool isDark) {
  final base = Color.alphaBlend(
    df.primary.withValues(alpha: isDark ? 0.16 : 0.08),
    df.surface,
  );
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      base.withValues(alpha: isDark ? 0.90 : 0.90),
      base.withValues(alpha: isDark ? 0.72 : 0.68),
    ],
  );
}

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
        // 悬浮磨砂玻璃胶囊侧栏，与窗口边缘留白
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: _SideBar(path: path),
        ),
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
    final activeCount = ref.watch(activeJobsProvider).length;

    final isProject = path == '/' || path.startsWith('/p/');
    final isTasks = path.startsWith('/tasks');
    final isSettings = path.startsWith('/settings');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 胶囊形状：圆角 = 宽度一半，顶部/底部自然收成半圆。
    // 玻璃底色在 surface 基础上混入一点主色，再拉高不透明度：纯灰玻璃在素色背景下
    // 太浅，几乎看不出形状；混色+提高不透明度后，不管背景亮暗都能看清胶囊轮廓。
    // 注：不用 BackdropFilter 做真实模糊——它跟路由切换/弹窗动画同时触发时会导致
    // 渲染树错乱（页面跳转卡顿、弹窗消失），这里改成纯色调不透明度模拟玻璃质感，
    // 牺牲一点"透"的效果换稳定。
    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C24).withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(38),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
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
      height: 86,
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(children: [
        // 左上角当前项目名（纯展示，不可点击）
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            project?.name ?? context.l10n.shellSelectProject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: project == null ? df.textTertiary : df.textPrimary,
            ),
          ),
        ),
        const Spacer(),
        // 右上角项目功能 Segmented 选项卡（大气舒展布局）
        if (visibleMenus.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: df.surfaceMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? df.surface
                : (_hover ? df.surfaceMuted : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
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
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
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

    return Scaffold(
      extendBody: true,
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _MobileFloatingNavBar(
            selectedIndex: _tabIndex,
            activeCount: activeCount,
            onSelect: (i) => context.go(const ['/', '/tasks', '/settings'][i]),
          ),
        ),
      ),
    );
  }
}

/// 移动端底部导航：跟桌面侧栏同一套磨砂玻璃胶囊语言（圆角=高度一半、同样的玻璃底色）。
class _MobileFloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final int activeCount;
  final ValueChanged<int> onSelect;
  const _MobileFloatingNavBar({
    required this.selectedIndex,
    required this.activeCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const height = 64.0;

    final items = [
      (Icons.grid_view_outlined, Icons.grid_view_rounded, l10n.menuMyProject),
      (Icons.view_stream_outlined, Icons.view_stream_rounded, l10n.menuTaskCenter),
      (Icons.settings_outlined, Icons.settings_rounded, l10n.menuSettings),
    ];

    // 跟桌面侧栏一样：不用 BackdropFilter，用渐变+高光边模拟玻璃质感，避免跟
    // 路由切换动画冲突导致渲染错乱。
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: glassGradient(df, isDark),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _MobileNavItem(
                outlineIcon: items[i].$1,
                filledIcon: items[i].$2,
                label: items[i].$3,
                selected: i == selectedIndex,
                badgeCount: i == 1 ? activeCount : 0,
                onTap: () => onSelect(i),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;
  const _MobileNavItem({
    required this.outlineIcon,
    required this.filledIcon,
    required this.label,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final color = selected ? df.primary : df.textSecondary;

    final icon = Badge(
      isLabelVisible: badgeCount > 0,
      label: Text('$badgeCount'),
      backgroundColor: df.accent,
      child: Icon(selected ? filledIcon : outlineIcon, size: 22, color: color),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ),
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

/// 品牌 Logo："开口播放环"：圆角方块上一个缺口圆环，缺口处嵌播放三角。
/// 纯代码矢量绘制，只用主色/辅色/容器底色三种颜色，小尺寸下依然清晰。
class DFLogo extends StatelessWidget {
  const DFLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _DFLogoPainter(
          primary: df.primary,
          accent: df.accent,
          background: df.surface,
        ),
      ),
    );
  }
}

class _DFLogoPainter extends CustomPainter {
  final Color primary;
  final Color accent;
  final Color background;
  const _DFLogoPainter({
    required this.primary,
    required this.accent,
    required this.background,
  });

  static final _badge = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 3, 34, 34), const Radius.circular(10));
  static const _ringCenter = Offset(17.5, 20);
  static const _ringRadius = 11.0;

  // 挖开圆环右侧缺口的“橡皮擦”三角（与主体同色，视觉上抹掉右半圈）。
  static final _wedge = Path()
    ..moveTo(19, 7)
    ..lineTo(33, 20)
    ..lineTo(19, 33)
    ..close();

  // 缺口处的播放三角。
  static final _triangle = Path()
    ..moveTo(20.5, 14.5)
    ..lineTo(29, 20)
    ..lineTo(20.5, 25.5)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(_badge, Paint()..color = primary);
    canvas.drawCircle(
      _ringCenter,
      _ringRadius,
      Paint()
        ..color = background
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawPath(_wedge, Paint()..color = primary);
    canvas.drawPath(_triangle, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _DFLogoPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.accent != accent ||
      oldDelegate.background != background;
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
