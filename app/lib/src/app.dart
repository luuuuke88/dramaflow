import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/projects_screen.dart';
import 'screens/project_screen.dart';
import 'screens/novel_screen.dart';
import 'screens/episode_screen.dart';
import 'screens/assets_screen.dart';
import 'screens/shots_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/settings_screen.dart';
import 'state/providers.dart';
import 'theme/theme.dart';
import 'widgets/shell.dart';

/// Web 端从浏览器地址深链启动（刷新/分享链接保持位置）；桌面/移动端从首页启动。
String _initialLocation() {
  if (kIsWeb) {
    final path = Uri.base.path;
    if (path.isNotEmpty && path != '/') return path;
  }
  return '/';
}

final _router = GoRouter(
  initialLocation: _initialLocation(),
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const ProjectsScreen()),
        GoRoute(path: '/tasks', builder: (c, s) => const TasksScreen()),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        GoRoute(
          path: '/projects/:pid',
          builder: (c, s) => ProjectScreen(projectId: s.pathParameters['pid']!),
        ),
        GoRoute(
          path: '/projects/:pid/novel',
          builder: (c, s) => NovelScreen(projectId: s.pathParameters['pid']!),
        ),
        GoRoute(
          path: '/projects/:pid/assets',
          builder: (c, s) => AssetsScreen(projectId: s.pathParameters['pid']!),
        ),
        GoRoute(
          path: '/projects/:pid/episodes/:eid',
          builder: (c, s) => EpisodeScreen(
            projectId: s.pathParameters['pid']!,
            episodeId: s.pathParameters['eid']!,
          ),
        ),
        GoRoute(
          path: '/projects/:pid/episodes/:eid/shots',
          builder: (c, s) => ShotsScreen(
            projectId: s.pathParameters['pid']!,
            episodeId: s.pathParameters['eid']!,
          ),
        ),
      ],
    ),
  ],
);

class DramaFlowApp extends ConsumerWidget {
  const DramaFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'DramaFlow',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
        Locale('ja'),
      ],
      locale: locale,
      themeMode: themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: _router,
    );
  }
}
