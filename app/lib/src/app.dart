import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/agent/agent_chat_screen.dart';
import 'screens/assets/assets_screen.dart';
import 'screens/cornerscape/corner_scape_screen.dart';
import 'screens/novel/novel_screen.dart';
import 'screens/production/production_screen.dart';
import 'screens/project/project_list_screen.dart';
import 'screens/script/script_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tasks_screen.dart';
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
        GoRoute(
          path: '/',
          pageBuilder: (c, s) =>
              const NoTransitionPage<void>(child: ProjectListScreen()),
        ),
        GoRoute(
          path: '/tasks',
          pageBuilder: (c, s) =>
              const NoTransitionPage<void>(child: TasksScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (c, s) =>
              const NoTransitionPage<void>(child: SettingsScreen()),
        ),
        // 项目内分区（对应 ToonFlow /novel /scriptAgent /script /cornerScape /production /assets）
        GoRoute(
          path: '/p/:pid/novel',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child: NovelScreen(projectId: int.parse(s.pathParameters['pid']!)),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: '/p/:pid/script',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child: ScriptScreen(projectId: int.parse(s.pathParameters['pid']!)),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: '/p/:pid/scriptAgent',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child: AgentChatScreen(
                projectId: int.parse(s.pathParameters['pid']!)),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: '/p/:pid/cornerScape',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child: CornerScapeScreen(
                projectId: int.parse(s.pathParameters['pid']!)),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: '/p/:pid/production',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child: ProductionScreen(
                projectId: int.parse(s.pathParameters['pid']!)),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: '/p/:pid/assets',
          pageBuilder: (c, s) => CustomTransitionPage<void>(
            key: s.pageKey,
            child:
                AssetsScreen(projectId: int.parse(s.pathParameters['pid']!)),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child,
              );
            },
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
