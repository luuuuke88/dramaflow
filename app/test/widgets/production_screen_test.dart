import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
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
    expect(find.text('剧本规划'), findsOneWidget); // 真实规划节点标题
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('分镜表'), findsOneWidget);
    expect(find.text('分镜'), findsWidgets); // 节点标题 + 内部工具栏文案
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('生成分镜'), findsOneWidget); // 分镜为空时的按钮
    // scriptPlan 已落地为真实节点，不再有占位文案。
    expect(find.textContaining('批次交付'), findsNothing);
    expect(find.text('还没有剧本规划，点此撰写整体思路、节奏与要点。'), findsOneWidget);
  });

  testWidgets('桌面画布：Agent 对话入口可打开右侧面板', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agent 对话'));
    await tester.pumpAndSettle();
    // 面板打开后出现欢迎语与发送按钮。
    expect(find.textContaining('我是剧本 Agent'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
  });

  testWidgets('点击资产节点卡片打开节点式图片编辑器', (tester) async {
    final scriptId = engine.addScript(
        projectId: projectId, name: '第一集', content: 'x');
    final assetId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.updateScript(scriptId, assets: [assetId]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('林朝雪'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '图片生成'), findsOneWidget);
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
    expect(find.widgetWithText(Tab, '剧本规划'), findsOneWidget); // 规划 Tab
  });

  testWidgets('移动端：Agent 入口打开全屏对话', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '剧本 Agent'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
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

  testWidgets('剧本节点可编辑：改名+改正文经 updateScript 持久化', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '旧正文');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    // 点击剧本节点头部的编辑按钮（工具提示「编辑」）。
    await tester.tap(find.byTooltip('编辑').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑剧本'), findsWidgets); // 对话框标题

    // 改名称与正文。
    await tester.enterText(find.widgetWithText(TextField, '请输入剧本名称'), '改后集名');
    await tester.enterText(find.widgetWithText(TextField, '请输入剧本正文'), '新正文内容');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).firstWhere((s) => s.id == scriptId);
    expect(row.name, '改后集名');
    expect(row.content, '新正文内容');
  });

  testWidgets('分镜表节点可编辑：撰写 Markdown 经 saveStoryboardTable 持久化',
      (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    // 空态展示「撰写分镜表」按钮；点击打开编辑器。
    expect(find.text('撰写分镜表'), findsOneWidget);
    await tester.tap(find.text('撰写分镜表'));
    await tester.pumpAndSettle();
    expect(find.text('编辑分镜表'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, '# 分镜表\nS01 开场雪景');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(engine.storyboardTable(projectId, scriptId), '# 分镜表\nS01 开场雪景');
    // 保存后节点预览应显示已写入的 Markdown。
    expect(find.textContaining('S01 开场雪景'), findsWidgets);
  });
}
