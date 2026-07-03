import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/screens/production/production_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-production-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    engine.installStoryboardPipeline();
    projectId = engine.addProject(projectType: 'novel', name: '画布测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app(double width) {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(
            body: ProductionScreen(projectId: projectId)),
      ),
      GoRoute(
          path: '/p/:pid/script', builder: (c, s) => const Text('script-page')),
    ]);
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
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

  testWidgets('无剧本时显示空态并可跳转剧本管理', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();

    expect(find.text('暂无剧本，请先在「剧本管理」创建'), findsOneWidget);
    await tester.tap(find.text('去创建剧本'));
    await tester.pumpAndSettle();
    expect(find.text('script-page'), findsOneWidget);
  });

  testWidgets('桌面画布：渲染 6 节点标题+剧集选择器', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: '正文内容');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.text('第一集'), findsOneWidget); // 剧集选择 chip
    expect(find.textContaining('剧本'), findsWidgets);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('分镜表'), findsOneWidget);
    expect(find.text('分镜'), findsWidgets); // 节点标题 + 内部工具栏文案
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('生成分镜'), findsOneWidget); // 分镜为空时的按钮
  });

  testWidgets('移动端：Tab 切换代替画布', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('点击「生成分镜」触发任务入队', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成分镜'));
    await tester.pump();
    final tasks = await engine.projectJobs(projectId);
    expect(tasks.any((t) => t.taskClass == 'storyboard_generate'), isTrue);
  });
}
