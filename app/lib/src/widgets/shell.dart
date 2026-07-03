import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../state/providers.dart';
import '../theme/theme.dart';

/// 全局响应式外壳：
/// - 宽度 ≥ 840：左侧 NavigationRail（≥1200 展开带文字）
/// - 宽度 < 840：底部 NavigationBar
/// 顶部注入活跃任务指示器。
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (
      path: '/',
      icon: Icons.movie_outlined,
      activeIcon: Icons.movie_rounded,
      label: '项目'
    ),
    (
      path: '/tasks',
      icon: Icons.bolt_outlined,
      activeIcon: Icons.bolt_rounded,
      label: '任务'
    ),
    (
      path: '/settings',
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune_rounded,
      label: '设置'
    ),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    if (loc.startsWith('/tasks')) return 1;
    if (loc.startsWith('/settings')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(activeJobsProvider).length;
    final index = _currentIndex(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    Widget taskIcon(bool active) => Badge(
          isLabelVisible: activeCount > 0,
          label: Text('$activeCount'),
          backgroundColor: context.df.primary,
          textColor: onPrimary,
          child: Icon(active ? Icons.bolt_rounded : Icons.bolt_outlined),
        );

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      final extended = constraints.maxWidth >= 1200;

      if (!wide) {
        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            height: 64,
            onDestinationSelected: (i) => context.go(_tabs[i].path),
            destinations: [
              for (final (i, t) in _tabs.indexed)
                NavigationDestination(
                  icon: i == 1 ? taskIcon(false) : Icon(t.icon),
                  selectedIcon: i == 1 ? taskIcon(true) : Icon(t.activeIcon),
                  label: t.label,
                ),
            ],
          ),
        );
      }

      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              extended: extended,
              minExtendedWidth: 180,
              labelType: extended ? null : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: extended
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Logo(),
                          SizedBox(width: 10),
                          Text('DramaFlow',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  letterSpacing: -0.3)),
                        ],
                      )
                    : const _Logo(),
              ),
              onDestinationSelected: (i) => context.go(_tabs[i].path),
              destinations: [
                for (final (i, t) in _tabs.indexed)
                  NavigationRailDestination(
                    icon: i == 1 ? taskIcon(false) : Icon(t.icon),
                    selectedIcon: i == 1 ? taskIcon(true) : Icon(t.activeIcon),
                    label: Text(t.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    });
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final endColor =
        isLight ? const Color(0xFF1D4ED8) : const Color(0xFFE07A1F);
    final iconColor = Theme.of(context).colorScheme.onPrimary;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.df.primary, endColor],
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(Icons.play_arrow_rounded, color: iconColor, size: 24),
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
