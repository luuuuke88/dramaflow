import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/queue.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(
  double width, {
  String initial = '/',
  EdgeInsets viewPadding = EdgeInsets.zero,
  ProviderContainer? container,
}) {
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
  final child = MediaQuery(
    data: MediaQueryData(size: Size(width, 800), padding: viewPadding),
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      locale: const Locale('zh'),
      theme: buildTheme(Brightness.light),
      routerConfig: router,
    ),
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: child);
  }
  return ProviderScope(
    overrides: [
      activeJobsProvider.overrideWith(ActiveJobsStub.new),
    ],
    child: child,
  );
}

ProviderContainer _container() => ProviderContainer(
      overrides: [
        activeJobsProvider.overrideWith(ActiveJobsStub.new),
      ],
    );

class ActiveJobsStub extends ActiveJobsNotifier {
  @override
  List<TasksRow> build() => const [];
}

const _scriptProject = ProjectRow(
  id: 7,
  artStyle: null,
  createTime: null,
  directorManual: null,
  imageModel: 'image:demo',
  imageQuality: '1K',
  intro: '测试项目',
  mode: 'text',
  name: '剧本项目',
  projectType: 'script',
  type: '现代',
  userId: 1,
  videoModel: 'volcengine:demo',
  videoRatio: '16:9',
);

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

  testWidgets('移动壳：无 AppBar 的顶级标签页需避让状态栏/灵动岛（真机截图曾发现标题被遮挡）',
      (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 模拟 iPhone 灵动岛机型的顶部安全区（真实设备约 59px）。
    await tester.pumpWidget(_app(380, viewPadding: const EdgeInsets.only(top: 59)));
    await tester.pumpAndSettle();

    final homeTop = tester.getTopLeft(find.text('home')).dy;
    expect(homeTop, greaterThanOrEqualTo(59),
        reason: '首页（无 AppBar 的顶级 Tab）内容顶部必须让开状态栏/灵动岛安全区');
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

  testWidgets('剧本项目隐藏小说专属菜单，保留其余制作分区', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = _container();
    addTearDown(container.dispose);
    container.read(currentProjectProvider.notifier).select(_scriptProject);
    await tester.pumpWidget(_app(1200, container: container));
    await tester.pumpAndSettle();

    expect(find.text('剧本项目'), findsOneWidget);
    expect(find.text('小说原文'), findsNothing);
    expect(find.text('剧本Agent'), findsNothing);
    for (final label in ['剧本管理', '塑角造景', '视频生产', '资产中心']) {
      expect(find.text(label), findsOneWidget, reason: '$label 应保留给剧本项目');
    }
  });
}
