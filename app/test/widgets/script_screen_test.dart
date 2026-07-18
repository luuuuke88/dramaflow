import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/screens/script/script_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  String Function(String system, String user, String stage)? textResult;

  @override
  Future<TextResult> generateText(
    String system,
    String user, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final fn = textResult;
    if (fn != null) return TextResult(fn(system, user, stage));
    return const TextResult('');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _NoopGateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-script-ui-');
    db = openEngineDb(':memory:');
    gateway = _NoopGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    // 本文件断言的是「事件生成剧本」入队/落库的业务逻辑，不是确认闸弹窗本身
    // （闸本身已由 policy_confirm_test.dart 覆盖）；关闸避免每个用例都要多点一次确认。
    engine.config.update({'policy.confirmMoney': '0'});
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('scriptGen','script_gen_system','剧本生成系统词',NULL)",
    );
    engine.installScriptPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: '剧本移动端测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app(double width) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: ScriptScreen(projectId: projectId)),
          ),
        ),
      );

  testWidgets('移动端剧本页：批量添加两集并落库', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('批量添加'));
    await tester.pumpAndSettle();
    expect(find.text('批量添加'), findsWidgets);

    await tester.enterText(
      find.byType(TextField).last,
      '第1章 雪夜\n黑衣人来到山门。\n第2章 焦玉\n焦黑玉佩落在雪中。',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final scripts = engine.scripts(projectId);
    expect(scripts.map((s) => s.name), ['雪夜', '焦玉']);
    expect(find.text('雪夜'), findsOneWidget);
    expect(find.text('焦玉'), findsOneWidget);
  });

  testWidgets('移动端剧本页：从事件选择并生成剧本', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    db.execute(
      "INSERT INTO o_novel (projectId,chapterIndex,reel,chapter,chapterData,eventState,event) "
      "VALUES (?,1,'正文卷','雪夜','山门雪夜',1,'事件一')",
      [projectId],
    );
    final novelId = db.select('SELECT id FROM o_novel').first['id'] as int;
    db.execute(
      "INSERT INTO o_event (name,detail,createTime) VALUES "
      "('雪夜破门','| 第1章 雪夜 | 林朝雪 | 黑衣人破门 | 强 | 高 | 50秒 | 冲突 |',1)",
    );
    final eventId = db.select('SELECT id FROM o_event').first['id'] as int;
    db.execute(
      'INSERT INTO o_eventChapter (eventId,novelId) VALUES (?,?)',
      [eventId, novelId],
    );
    gateway.textResult = (system, user, stage) {
      expect(system, '剧本生成系统词');
      expect(stage, 'script_gen');
      expect(user, contains('雪夜破门'));
      return '{"episodes":[{"title":"雪夜破门","synopsis":"黑衣人破门","scenes":[{"location":"山门","timeOfDay":"夜","action":"黑衣人撞开山门","dialogues":[{"speaker":"林朝雪","line":"谁敢闯山门？"}]}]}]}';
    };

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('事件生成剧本'));
    await tester.pumpAndSettle();
    expect(find.text('选择事件生成剧本'), findsOneWidget);
    expect(find.text('雪夜破门'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    final generateButton = find.widgetWithText(FilledButton, '生成剧本');
    expect(tester.widget<FilledButton>(generateButton).onPressed, isNotNull);
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        if (engine.scripts(projectId).isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    final scripts = engine.scripts(projectId);
    final taskRows =
        db.select('SELECT taskClass,state,reason FROM o_tasks ORDER BY id');
    expect(scripts.map((s) => s.name), ['雪夜破门'], reason: 'tasks=$taskRows');
    expect(scripts.single.content, contains('林朝雪：谁敢闯山门？'));
    expect(find.text('雪夜破门'), findsOneWidget);
  });

  testWidgets('移动端剧本页：编辑已有剧本并落库刷新', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '旧名', content: '旧内容');

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.text('旧名'));
    await tester.pumpAndSettle();
    expect(find.text('剧本详情'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新名');
    await tester.enterText(find.byType(TextField).last, '新内容第一场');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).single;
    expect(row.name, '新名');
    expect(row.content, '新内容第一场');
    expect(find.text('新名'), findsOneWidget);
    expect(find.text('旧名'), findsNothing);
  });

  testWidgets('移动端剧本页：编辑器支持 Markdown 格式工具和预览', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '旧名', content: '旧内容');

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();

    await tester.tap(find.text('旧名'));
    await tester.pumpAndSettle();
    expect(find.text('剧本详情'), findsOneWidget);
    expect(find.byTooltip('加粗'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '新内容第一场');
    await tester.tap(find.byTooltip('加粗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('重点'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).single;
    expect(row.content, contains('**重点**'));
  });

  testWidgets('桌面剧本页：编辑器支持 Markdown 格式工具和预览', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '第一集', content: '# 开场');

    await tester.pumpWidget(app(1200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第一集'));
    await tester.pumpAndSettle();
    expect(find.text('剧本详情'), findsOneWidget);
    expect(find.byTooltip('标题'), findsOneWidget);
    expect(find.byTooltip('台词'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '正文');
    await tester.tap(find.byTooltip('台词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('角色：台词'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.scripts(projectId).single;
    expect(row.content, contains('> 角色：台词'));
  });

  testWidgets('移动端剧本页：卡片宽度不超出视口，删除按钮无需悬停即可点击',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '待删本', content: '内容');

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Bug 1：卡片曾经硬编码 width:400，在 <400px 的手机视口上必然溢出。
    final cardSize = tester.getSize(find.byType(AnimatedContainer).first);
    expect(cardSize.width, lessThanOrEqualTo(390),
        reason: '卡片宽度不应超过 390pt 视口');

    // Bug 2：删除按钮曾经只在 MouseRegion hover 时显示，触屏端不可达。
    // 手机宽度下不做任何 hover 动作，直接确认其常显且可点。
    final deleteOpacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(deleteOpacity.opacity, 1.0, reason: '窄屏下删除按钮应无需悬停即可见');

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确认删除'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(engine.scripts(projectId).map((s) => s.name), ['待删本']);
  });

  testWidgets('移动壳平板宽度下剧本删除按钮仍无需 hover', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.addScript(projectId: projectId, name: '平板待删本', content: '内容');

    await tester.pumpWidget(app(800));
    await tester.pumpAndSettle();

    final deleteOpacity =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(deleteOpacity.opacity, 1.0);
  });
}
