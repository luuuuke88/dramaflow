import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/queue.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(double width, {String initial = '/'}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const Text('home')),
          GoRoute(path: '/tasks', builder: (c, s) => const Text('tasks')),
          GoRoute(path: '/settings', builder: (c, s) => const Text('settings')),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      activeJobsProvider.overrideWith(ActiveJobsStub.new),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
}

class ActiveJobsStub extends ActiveJobsNotifier {
  @override
  List<TasksRow> build() => const [];
}

void main() {
  testWidgets('桌面壳：细侧栏 + 顶栏，未选项目时项目菜单禁用', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(1200));
    await tester.pumpAndSettle();

    expect(find.text('请选择项目'), findsOneWidget);
    expect(find.text('小说原文'), findsOneWidget);
    expect(find.text('剧本管理'), findsOneWidget);
    // 未选项目 → 点击项目菜单不导航（仍在 home）
    await tester.tap(find.text('剧本管理'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('移动壳：底部导航三项', (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(380));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('我的项目'), findsOneWidget);
    expect(find.text('任务中心'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('任务中心'));
    await tester.pumpAndSettle();
    expect(find.text('tasks'), findsOneWidget);
  });

  testWidgets('禁用分区带批次徽标', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(1200));
    await tester.pumpAndSettle();

    expect(find.text('P2'), findsNothing); // 资产中心已随 P2 交付解禁
    expect(find.text('P3'), findsNothing); // 制作已随 P3 交付解禁
    expect(find.text('P4'), findsOneWidget); // 配音
    expect(find.text('P5'), findsOneWidget); // 剧本Agent
  });
}
