import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:dramaflow/src/screens/production/production_screen.dart';
import 'package:dramaflow/src/state/canvas_wheel_mode.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/df_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../tool/e2e_local_smoke.dart' as smoke;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiSmokeComposer implements VideoComposer {
  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    File(outputAbsPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1]);
  }

  @override
  Future<void> compose(
      List<ComposeSegment> segments, String outputAbsPath) async {
    File(outputAbsPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
          [for (final segment in segments) segment.hasAudio ? 2 : 1]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => 9.0;
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
      composer: _UiSmokeComposer(),
    );
    // 本文件断言的是「生成分镜」等按钮触发任务入队的业务逻辑，不是确认闸弹窗本身
    // （闸本身已由 policy_confirm_test.dart 覆盖）；关闸避免每个用例都要多点一次确认。
    engine.config.update({'policy.confirmMoney': '0'});
    // 大多数画布行为用例不关心首次教学；引导专项用例会显式恢复未完成状态。
    engine.config.update({'production.guide.completed': '1'});
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
        builder: (c, s) =>
            Scaffold(body: ProductionScreen(projectId: projectId)),
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

  testWidgets('桌面制作页首次显示四步引导，完成后重进不再出现', (tester) async {
    engine.config.update({'production.guide.completed': '0'});
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('production-guide')), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const Key('production-guide-next')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('production-guide-finish')));
    await tester.pumpAndSettle();

    expect(engine.config.str('production.guide.completed'), '1');
    expect(find.byKey(const Key('production-guide')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('production-guide')), findsNothing);
  });

  testWidgets('390dp 制作页引导完成后仍可访问节点标签页', (tester) async {
    engine.config.update({'production.guide.completed': '0'});
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('production-guide-compact')), findsOneWidget);
    await tester.tap(find.byKey(const Key('production-guide-skip')));
    await tester.pumpAndSettle();

    expect(engine.config.str('production.guide.completed'), '1');
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('剧本'), findsWidgets);
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

  testWidgets('桌面画布：会话滚轮模式立即传给主 DFCanvas', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: '正文内容');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductionScreen)),
    );
    expect(tester.widget<DFCanvas>(find.byType(DFCanvas)).wheelMode,
        CanvasWheelMode.zoom);

    container
        .read(canvasWheelModeProvider.notifier)
        .setMode(CanvasWheelMode.scroll);
    await tester.pump();

    expect(tester.widget<DFCanvas>(find.byType(DFCanvas)).wheelMode,
        CanvasWheelMode.scroll);
  });

  testWidgets('桌面画布读取持久化的拖动性能开关', (tester) async {
    engine.config.update({'production.interacting': '0'});
    engine.addScript(projectId: projectId, name: '第一集', content: '正文内容');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DFCanvas>(find.byType(DFCanvas))
          .interactionReductionEnabled,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    engine.config.update({'production.interacting': '1'});
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DFCanvas>(find.byType(DFCanvas))
          .interactionReductionEnabled,
      isTrue,
    );
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
    expect(find.textContaining('我是制作 Agent'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
  });

  testWidgets('桌面画布：刷新会重建当前视图并反馈结果', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    final before = const ValueKey('production-canvas-0');
    final after = const ValueKey('production-canvas-1');
    expect(find.byKey(before), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('production-refresh')));
    await tester.pump();

    expect(find.byKey(before), findsNothing);
    expect(find.byKey(after), findsOneWidget);
    expect(find.text('画布已刷新'), findsOneWidget);
  });

  testWidgets('桌面画布：节点可从标题栏拖动并能自动布局复位', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    engine.addScript(projectId: projectId, name: '第二集', content: 'y');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    final dragHandle = find.byKey(const ValueKey('df-canvas-drag-script'));
    final before = tester.getTopLeft(dragHandle);
    await tester.drag(dragHandle, const Offset(120, 0));
    await tester.pump();
    final moved = tester.getTopLeft(dragHandle);
    expect(moved.dx, greaterThan(before.dx + 40));

    await tester.tap(find.text('第二集'));
    await tester.pump();
    expect(tester.getTopLeft(dragHandle).dx, closeTo(moved.dx, 0.1));

    await tester.tap(find.byKey(const ValueKey('production-auto-layout')));
    await tester.pump();
    final reset = tester.getTopLeft(dragHandle);
    expect(reset.dx, closeTo(before.dx, 0.1));
  });

  testWidgets('桌面资产节点按原始与衍生层级展示，衍生项进入图片编辑器', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final originalId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final derivedId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪-雨夜',
      describe: '战损造型',
      prompt: '雨夜战损造型',
      parentAssetsId: originalId,
    );
    engine.saveAssetImage(
      assetsId: originalId,
      projectId: projectId,
      base64Image: 'AQID',
      type: 'role',
    );
    engine.saveAssetImage(
      assetsId: derivedId,
      projectId: projectId,
      base64Image: 'BAUG',
      type: 'role',
    );
    engine.updateScript(scriptId, assets: [originalId]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('production-asset-parent-$originalId')),
        findsOneWidget);
    expect(find.text('原始资产'), findsOneWidget);
    expect(
        find.byKey(ValueKey('production-derived-$derivedId')), findsOneWidget);
    expect(find.text('衍生资产'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('production-derived-$derivedId')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '图片生成'), findsOneWidget);

    final generatedTitle = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('图片生成'),
    );
    await tester.tap(generatedTitle.last, warnIfMissed: false);
    await tester.pumpAndSettle();
    final apply = find.byKey(const ValueKey('image-flow-apply-g1'));
    expect(apply, findsOneWidget);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull,
        reason: '原版会把已有衍生图作为结果节点，进入编辑器后可直接采用');
  });

  testWidgets('桌面资产节点删除衍生项须确认且仅移除该子项', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final originalId = engine.addAsset(
        projectId: projectId, type: 'role', name: '谢危', describe: 'x');
    final derivedId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '谢危-朝服',
      describe: '礼服版本',
      parentAssetsId: originalId,
    );
    engine.updateScript(scriptId, assets: [originalId]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(ValueKey('production-derived-delete-$derivedId')));
    await tester.pumpAndSettle();
    expect(find.text('删除该衍生资产后无法恢复。'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('production-derived-delete-confirm')));
    await tester.pumpAndSettle();

    expect(engine.assetsByIds([originalId]).single.sonAssets, isEmpty);
    expect(find.text('谢危-朝服'), findsNothing);
  });

  testWidgets('桌面资产节点删除生成中的衍生项需要生成中专属提示（Bug 2 回归）', (tester) async {
    // 对照 _thumbnail 已经对 imageState == stateGenerating 显示转圈，
    // 删除入口此前无任何区别地直接弹通用确认——这里验证生成中态会换成
    // 明确提示会中断生成的专属文案，而不是和普通删除共用同一句话。
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final originalId = engine.addAsset(
        projectId: projectId, type: 'role', name: '沈知微', describe: 'x');
    final derivedId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '沈知微-夜行',
      describe: '生成中版本',
      parentAssetsId: originalId,
    );
    engine.db.execute(
      'INSERT INTO o_image (assetsId,state,type) VALUES (?,?,?)',
      [derivedId, stateGenerating, 'role'],
    );
    engine.db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [engine.db.lastInsertRowId, derivedId]);
    engine.updateScript(scriptId, assets: [originalId]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 生成中缩略图含不确定态 CircularProgressIndicator，会一直调度新帧，
    // 此处不能用 pumpAndSettle（永远不会 settle），改用有界 pump（对齐本文件
    // corner_scape 系测试处理常驻动画时的既有写法）。
    await tester.pumpWidget(app(1400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // 缩略图与 _thumbnail 一致显示生成中转圈。
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester
        .tap(find.byKey(ValueKey('production-derived-delete-$derivedId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const ValueKey('production-derived-delete-generating-warn')),
      findsOneWidget,
    );
    expect(find.text('该衍生资产正在生成图片，删除将中断本次生成且无法恢复，确定要删除吗？'),
        findsOneWidget);
    // 不能和普通（非生成中）删除共用同一句无区别的文案。
    expect(find.text('删除该衍生资产后无法恢复。'), findsNothing);

    // 明确二次确认后仍然允许删除（不是硬性拦截，只是要求用户看清后果）。
    await tester.tap(find.byKey(ValueKey('production-derived-delete-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(engine.assetsByIds([originalId]).single.sonAssets, isEmpty);
    expect(find.text('沈知微-夜行'), findsNothing);
  });

  testWidgets('桌面资产节点为失败的衍生图显示失败态与原因提示', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final originalId = engine.addAsset(
        projectId: projectId, type: 'role', name: '姜梨', describe: 'x');
    final derivedId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '姜梨-雪夜',
      describe: '失败版本',
      parentAssetsId: originalId,
    );
    engine.db.execute(
      'INSERT INTO o_image (assetsId,state,errorReason,type) VALUES (?,?,?,?)',
      [derivedId, stateFailed, '{"key":"errNetwork","params":{}}', 'role'],
    );
    engine.db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [engine.db.lastInsertRowId, derivedId]);
    engine.updateScript(scriptId, assets: [originalId]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.text('生成失败'), findsOneWidget);
    expect(find.byTooltip('网络请求失败'), findsOneWidget);
  });

  testWidgets('390dp 资产节点保留原始与衍生资产层级且没有布局异常', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final originalId = engine.addAsset(
        projectId: projectId, type: 'role', name: '沈璃', describe: 'x');
    final derivedId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '沈璃-战甲',
      describe: '披甲版本',
      parentAssetsId: originalId,
    );
    engine.updateScript(scriptId, assets: [originalId]);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, '资产'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('production-asset-parent-$originalId')),
        findsOneWidget);
    expect(
        find.byKey(ValueKey('production-derived-$derivedId')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('移动端：节点检查器底部抽屉可切换到指定节点', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final assetId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.updateScript(scriptId, assets: [assetId]);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('节点检查器'));
    await tester.pumpAndSettle();
    expect(find.text('当前节点'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('mobile-node-inspector-assets')));
    await tester.pumpAndSettle();
    expect(find.text('林朝雪'), findsOneWidget);
  });

  testWidgets('桌面端离线主链：制作页工作台入口可打开并完成合成', (tester) async {
    final seed = smoke.seedOfflinePipeline(engine);
    projectId = seed.projectId;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('打开工作台'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-tab-generate')));
    await tester.pumpAndSettle();
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    expect(find.text('镜头配音'), findsWidgets);

    await tester.tap(find.text('合成本集'));
    await tester.pumpAndSettle();
    expect(find.text('合成成功'), findsOneWidget);
  });

  testWidgets('移动端离线主链：制作页 Tab 可进入工作台并打开同一条链路', (tester) async {
    final seed = smoke.seedOfflinePipeline(engine);
    projectId = seed.projectId;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(TabBar), const Offset(-280, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '工作台'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.text('打开工作台'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-tab-generate')));
    await tester.pumpAndSettle();
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    expect(find.byTooltip('合成本集'), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-compose-compact')),
        findsOneWidget);
  });

  testWidgets('移动端离线主链：工作台可直接合成本集', (tester) async {
    final seed = smoke.seedOfflinePipeline(engine);
    projectId = seed.projectId;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(TabBar), const Offset(-280, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '工作台'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开工作台'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-tab-generate')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workbench-compose-compact')));
    await tester.pumpAndSettle();

    expect(find.text('合成成功'), findsOneWidget);
    final clips = engine.getAssets(projectId, type: 'clip').data;
    expect(clips, hasLength(1));
    expect(clips.single.filePath, contains('episode_'));
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
    expect(find.widgetWithText(AppBar, '制作 Agent'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
  });

  testWidgets('点击「生成分镜」触发任务入队', (tester) async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    engine.saveScriptPlan(projectId, '测试导演规划');
    engine.saveStoryboardTable(projectId, scriptId, '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 测试镜头 | 推近 | 3 |
''');
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

  testWidgets('剧本节点支持 Markdown 编辑工具并渲染预览', (tester) async {
    final scriptId = engine.addScript(
        projectId: projectId, name: '第一集', content: '# 开场\n**雪夜**');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    expect(find.text('开场'), findsOneWidget);
    expect(find.textContaining('**雪夜**'), findsNothing);

    await tester.tap(find.byTooltip('编辑').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('加粗'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '请输入剧本正文'), '正文');
    await tester.tap(find.byTooltip('加粗'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).firstWhere((s) => s.id == scriptId);
    expect(row.content, contains('**重点**'));
  });

  testWidgets('分镜表节点可编辑：撰写 Markdown 经 saveStoryboardTable 持久化', (tester) async {
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

  testWidgets('分镜表生成按钮入队并显示过期状态', (tester) async {
    engine.config.update({'policy.confirmMoney': '1'});
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '雪夜');
    engine.saveScriptPlan(projectId, '导演规划');
    engine.saveStoryboardTable(projectId, scriptId, '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 雪夜山门 | 推近 | 3 |
''');
    engine.updateScript(scriptId, content: '雪夜山门改稿');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    final generate = find.byKey(Key('storyboard-table-generate-$scriptId'));
    expect(generate, findsOneWidget);
    expect(find.byKey(Key('storyboard-table-stale-$scriptId')), findsOneWidget);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(await engine.projectJobs(projectId), isEmpty);

    await tester.tap(generate);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pump();
    final tasks = await engine.projectJobs(projectId);
    expect(tasks.map((task) => task.taskClass),
        contains('storyboard_table_generation'));
  });
}
