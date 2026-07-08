import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/novel/novel_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  String Function(String system, String user, String stage)? textHandler;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    return TextResult(textHandler?.call(system, user, stage) ?? '');
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
    dir = Directory.systemTemp.createTempSync('dramaflow-novel-ui-');
    db = openEngineDb(':memory:');
    _seedPrompts(db);
    gateway = _NoopGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    // 本文件断言的是按钮入队任务的业务逻辑，不是确认闸弹窗本身
    // （闸本身已由 policy_confirm_test.dart 覆盖）；关闸避免每个用例都要多点一次确认。
    engine.config.update({'policy.confirmMoney': '0'});
    // 注册事件任务执行器但不设置 onNovelsAdded，避免 addNovels 自动触发事件生成，
    // 从而可以精确断言「生成选中章节事件」按钮入队的任务。
    projectId = engine.addProject(projectType: 'novel', name: '章节测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<int> seed(int n) => engine.addNovels(projectId, [
        for (var i = 1; i <= n; i++)
          ChapterItem(
            index: i,
            reel: '正文卷',
            chapter: '章$i',
            chapterData: '内容$i',
          ),
      ]);

  Widget app(double width) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: NovelScreen(projectId: projectId)),
          ),
        ),
      );

  testWidgets('勾选章节后「生成事件」按钮为选中章节入队 event_generation 任务', (tester) async {
    final ids = seed(3);
    // 先把三章都标记为已完成，便于断言仅选中章节被重置为「生成中」。
    db.execute('UPDATE o_novel SET eventState=1');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    // 未勾选时按钮禁用，无任务入队。
    final genButton = find.widgetWithText(FilledButton, '生成事件');
    expect(genButton, findsOneWidget);
    expect(tester.widget<FilledButton>(genButton).onPressed, isNull);

    // 勾选前两章（复选框列的第 0 个是全选，行复选框依次跟随）。
    final checkboxes = find.byType(Checkbox);
    await tester.tap(checkboxes.at(1));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();

    expect(db.select("SELECT COUNT(*) n FROM o_tasks").first['n'], 0);

    await tester.tap(find.widgetWithText(FilledButton, '生成事件 (2)'));
    await tester.pump();

    final tasks = db.select(
        "SELECT relatedObjects FROM o_tasks WHERE taskClass='event_generation'");
    expect(tasks, hasLength(1), reason: '仅入队一条事件生成任务');
    final related = tasks.first['relatedObjects'] as String;
    // 仅为选中的前两章入队，第三章不在内。
    expect(related, contains('${ids[0]}'));
    expect(related, contains('${ids[1]}'));
    expect(related, isNot(contains('${ids[2]}')));

    // 仅选中章节被重置为「生成中」（eventState=0），未选中章节保持完成（1）。
    final states =
        engine.novels(projectId).data.map((r) => (r.id, r.eventState)).toList();
    expect(states.firstWhere((e) => e.$1 == ids[0]).$2, 0);
    expect(states.firstWhere((e) => e.$1 == ids[1]).$2, 0);
    expect(states.firstWhere((e) => e.$1 == ids[2]).$2, 1);
  });

  testWidgets('移动端小说页：导入两章并自动入队事件生成任务', (tester) async {
    engine.onNovelsAdded = (pid, ids) => engine.generateEvents(pid, ids);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '导入原文').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byType(TextField).last,
      '第1章 雪夜\n黑衣人来到山门，掌门取出一枚焦黑玉佩。\n'
      '第2章 入山\n少年穿过石阶，看见云海中亮起剑光。',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存原文并分析事件'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final rows = engine.novels(projectId).data;
    expect(rows.map((r) => r.chapter), ['雪夜', '入山']);
    final tasks = db.select(
        "SELECT relatedObjects FROM o_tasks WHERE taskClass='event_generation'");
    expect(tasks, hasLength(1));
    expect(find.textContaining('雪夜'), findsOneWidget);
    expect(find.textContaining('入山'), findsOneWidget);
  });

  testWidgets('移动端小说页：选中章节可打开事件分析并展示分析结果', (tester) async {
    final ids = seed(2);
    db.execute(
      'UPDATE o_novel SET eventState=1, event=CASE id '
      'WHEN ? THEN ? WHEN ? THEN ? END WHERE id IN (?,?)',
      [
        ids[0],
        '危机降临|黑衣人压境，掌门示警',
        ids[1],
        '少年入山|少年进入山门，云海剑光出现',
        ids[0],
        ids[1],
      ],
    );
    final seeded = engine.novels(projectId).data;
    expect(seeded.map((r) => r.event), [
      '危机降临|黑衣人压境，掌门示警',
      '少年入山|少年进入山门，云海剑光出现',
    ]);
    var seenSystem = '';
    var seenUser = '';
    var seenStage = '';
    gateway.textHandler = (system, user, stage) {
      seenSystem = system;
      seenUser = user;
      seenStage = stage;
      return '[{"chapterIndex":1,"analysis":"危机强，适合保留为开场钩子"},'
          '{"chapterIndex":2,"analysis":"视觉信息明确，可衔接主角入门"}]';
    };

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.textContaining('章1').first);
    await tester.pump();
    await tester.tap(find.textContaining('章2').first);
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '事件分析 (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final startButton = find.widgetWithText(FilledButton, '开始分析');
    expect(startButton, findsOneWidget);
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '开始分析'), findsNothing);
    expect(seenStage, 'event_extract');
    expect(seenSystem, contains('短剧改编分析助手'));
    expect(seenUser, contains('危机降临'));
    expect(seenUser, contains('少年入山'));
    expect(find.textContaining('第1章'), findsOneWidget);
    expect(find.text('危机强，适合保留为开场钩子'), findsOneWidget);
    expect(find.text('视觉信息明确，可衔接主角入门'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _seedPrompts(Database db) {
  for (final entry in {
    'eventExtraction': '事件提取系统提示词',
    'eventAnalysis': '你是短剧改编分析助手。',
  }.entries) {
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
      [entry.key, entry.key, entry.value],
    );
  }
}
