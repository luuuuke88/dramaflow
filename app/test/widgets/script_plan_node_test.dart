import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/production_dependencies.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/screens/production/script_plan_node.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('# 自动生成导演规划\n雪夜开场');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-scriptplan-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    engine.saveVisualManual(
      name: '视觉',
      pack: 'visual',
      data: const {'director_planning_style': '视觉规划'},
    );
    engine.saveDirectorManual(
      name: '导演',
      pack: 'director',
      data: const {'director_planning_narrative': '叙事规划'},
    );
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
      ['director_plan', 'director_plan', '规划系统词'],
    );
    engine.installScriptPlanPipeline();
    engine.queue.start();
    projectId = engine.addProject(
      projectType: 'novel',
      name: '规划测试',
      artStyle: 'visual',
      directorManual: 'director',
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 桌面宽度，让 showDFAdaptiveDialog 走对话框而非全屏页，便于就地断言。
  Widget app() {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1200, 900)),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 260,
              child: ScriptPlanNode(projectId: projectId),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('无规划时显示空态与撰写按钮', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('剧本规划'), findsOneWidget); // 节点标题
    expect(find.text('还没有剧本规划，点此撰写整体思路、节奏与要点。'), findsOneWidget);
    expect(find.text('撰写规划'), findsOneWidget);
  });

  testWidgets('已有规划时预览已存 Markdown 文本', (tester) async {
    engine.saveScriptPlan(projectId, '# 主线\n少年逆袭夺回家产');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('少年逆袭夺回家产'), findsOneWidget);
    expect(find.text('还没有剧本规划，点此撰写整体思路、节奏与要点。'), findsNothing);
  });

  testWidgets('已有规划过期时显示重新生成提示', (tester) async {
    engine.saveScriptPlan(projectId, '# 原导演规划');
    engine.setProductionDependencyState(
      projectId: projectId,
      scriptId: 0,
      key: directorPlanStateKey,
      sourceHash: 'old',
      stale: true,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('script-plan-stale')), findsOneWidget);
    expect(find.text('上游内容已变化，需要重新生成'), findsOneWidget);
  });

  testWidgets('打开编辑器、写入并保存后落库且刷新预览', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 打开编辑对话框。
    await tester.tap(find.text('撰写规划'));
    await tester.pumpAndSettle();
    expect(find.text('编辑剧本规划'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '## 分集节奏\n共 12 集，每集一个钩子');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 持久化断言：engine 读回。
    expect(engine.scriptPlan(projectId), '## 分集节奏\n共 12 集，每集一个钩子');
    expect(find.text('剧本规划已保存'), findsOneWidget);
    // 预览刷新断言。
    expect(find.textContaining('每集一个钩子'), findsOneWidget);
  });

  testWidgets('编辑器取消不落库', (tester) async {
    engine.saveScriptPlan(projectId, '原始内容');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '被丢弃的改动');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(engine.scriptPlan(projectId), '原始内容');
  });

  testWidgets('导演规划生成按钮入队并随任务代次刷新预览', (tester) async {
    engine.addScript(projectId: projectId, name: '第一集', content: '雪夜开场');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final generate = find.byKey(const Key('script-plan-generate'));
    expect(generate, findsOneWidget);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(await engine.projectJobs(projectId), isEmpty);

    await tester.tap(generate);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        final tasks = await engine.projectJobs(projectId);
        if (tasks.isNotEmpty && tasks.single.state == 'success') return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    final tasks = await engine.projectJobs(projectId);
    expect(tasks.single.taskClass, 'director_plan_generation');
    expect(tasks.single.state, 'success');
    expect(engine.scriptPlan(projectId), contains('自动生成导演规划'));
    expect(find.textContaining('自动生成导演规划'), findsOneWidget);
  });
}
