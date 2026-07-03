import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/novel/novel_screen.dart';
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
        GoRoute(path: '/', builder: (c, s) => const ProjectListScreen()),
        GoRoute(path: '/tasks', builder: (c, s) => const TasksScreen()),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        // 项目内分区（对应 ToonFlow /novel /scriptAgent /script /cornerScape /production /assets）
        GoRoute(
            path: '/p/:pid/novel',
            builder: (c, s) =>
                NovelScreen(projectId: int.parse(s.pathParameters['pid']!))),
        GoRoute(
            path: '/p/:pid/script',
            builder: (c, s) =>
                ScriptScreen(projectId: int.parse(s.pathParameters['pid']!))),
        GoRoute(
            path: '/p/:pid/scriptAgent',
            builder: (c, s) => const ComingSoonScreen(batch: 'P5')),
        GoRoute(
            path: '/p/:pid/cornerScape',
            builder: (c, s) => const ComingSoonScreen(batch: 'P4')),
        GoRoute(
            path: '/p/:pid/production',
            builder: (c, s) => const ComingSoonScreen(batch: 'P3')),
        GoRoute(
            path: '/p/:pid/assets',
            builder: (c, s) => const ComingSoonScreen(batch: 'P2')),
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
