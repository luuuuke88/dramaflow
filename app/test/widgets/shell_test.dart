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

  testWidgets('全部 6 个项目分区均已交付，无占位批次徽标残留', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(1200));
    await tester.pumpAndSettle();

    for (final label in ['小说原文', '剧本Agent', '剧本管理', '塑角造景', '视频生产', '资产中心']) {
      expect(find.text(label), findsOneWidget, reason: '$label 分区应可见');
    }
    for (final batch in ['P2', 'P3', 'P4', 'P5']) {
      expect(find.text(batch), findsNothing, reason: '不应再有 $batch 占位徽标');
    }
  });
}
