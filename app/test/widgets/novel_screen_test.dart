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

  testWidgets('勾选章节后「事件分析」按钮为选中章节入队 event_generation 任务', (tester) async {
    final ids = seed(3);
    // 先把三章都标记为已完成，便于断言仅选中章节被重置为「生成中」。
    db.execute('UPDATE o_novel SET eventState=1');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(1400));
    await tester.pumpAndSettle();

    // 未勾选时按钮禁用，无任务入队。
    final genButton = find.widgetWithText(OutlinedButton, '事件分析');
    expect(genButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(genButton).onPressed, isNull);

    // 勾选前两章（复选框列的第 0 个是全选，行复选框依次跟随）。
    final checkboxes = find.byType(Checkbox);
    await tester.tap(checkboxes.at(1));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();

    expect(db.select("SELECT COUNT(*) n FROM o_tasks").first['n'], 0);

    await tester.tap(find.widgetWithText(OutlinedButton, '事件分析 (2)'));
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

  testWidgets('移动端小说页只保留原版事件分析入口并为选中章节入队', (tester) async {
    final ids = seed(2);
    db.execute('UPDATE o_novel SET eventState=1');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.byType(TabBar), findsNothing,
        reason: '原版小说页没有事件列表 Tab');
    expect(find.text('生成事件'), findsNothing,
        reason: '原版只有「事件分析」这一项批量事件生成入口');

    await tester.tap(find.textContaining('章1').first);
    await tester.pump();
    await tester.tap(find.textContaining('章2').first);
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '事件分析 (2)'));
    await tester.pump();

    final tasks = db.select(
        "SELECT relatedObjects FROM o_tasks WHERE taskClass='event_generation'");
    expect(tasks, hasLength(1));
    final related = tasks.single['relatedObjects'] as String;
    expect(related, contains('${ids[0]}'));
    expect(related, contains('${ids[1]}'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('事件生成中禁用章节的编辑和删除操作', (tester) async {
    seed(1);
    db.execute('UPDATE o_novel SET eventState=0');
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1400));
    // 生成中状态含持续动画，固定推进一帧即可验证操作禁用状态。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final edit = find.widgetWithText(TextButton, '编辑');
    final delete = find.widgetWithText(TextButton, '删除');
    expect(edit, findsOneWidget);
    expect(delete, findsOneWidget);
    expect(tester.widget<TextButton>(edit).onPressed, isNull);
    expect(tester.widget<TextButton>(delete).onPressed, isNull);
  });

  testWidgets('移动端小说页：卡片展示章节内容预览，点击「查看详情」走全屏弹窗而非小弹窗', (tester) async {
    final ids = seed(1);
    final longContent = '风雪压境，' * 30; // 超过 80 字截断阈值
    db.execute(
        'UPDATE o_novel SET chapterData=? WHERE id=?', [longContent, ids[0]]);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    // (a) 手机卡片展示章节内容预览片段（截断后的前缀），而不是完全没有该字段。
    expect(find.textContaining(longContent.substring(0, 20)), findsOneWidget);
    expect(find.text(longContent), findsNothing);

    // (b) 点击「查看详情」应走 showDFAdaptiveDialog 的全屏路径（AppBar+关闭按钮），
    // 而不是旧的小号 AlertDialog。
    expect(find.byType(AppBar), findsNothing);
    await tester.tap(find.text('查看详情').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text(longContent), findsOneWidget);
  });

  testWidgets('桌面端编辑章节会更新名称、事件和正文并刷新列表', (tester) async {
    final id = seed(1).single;
    db.execute('UPDATE o_novel SET eventState=1, event=? WHERE id=?', ['旧事件', id]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(1400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('编辑').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(_fieldWithLabel('章节名称'), '新章节名');
    await tester.enterText(_fieldWithLabel('事件内容'), '新事件');
    await tester.enterText(_fieldWithLabel('章节内容'), '新的章节正文');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final row = engine.novels(projectId).data.single;
    expect(row.chapter, '新章节名');
    expect(row.event, '新事件');
    expect(row.chapterData, '新的章节正文');
    expect(find.text('新章节名'), findsOneWidget);
  });

  testWidgets('移动端编辑章节以全屏表单呈现，取消不会写入修改', (tester) async {
    final id = seed(1).single;
    db.execute('UPDATE o_novel SET eventState=1 WHERE id=?', [id]);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('编辑').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.enterText(_fieldWithLabel('章节名称'), '不应保存的名称');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(engine.novels(projectId).data.single.id, id);
    expect(engine.novels(projectId).data.single.chapter, '章1');
  });

  testWidgets('移动壳平板宽度下小说工具栏不溢出', (tester) async {
    seed(1);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(800));
    // 此用例只验证初始布局。不要等待所有持续动画结束，否则会把与
    // RenderFlex 无关的动画计时器误报成失败。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.widgetWithText(FilledButton, '导入原文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField(label: $label)',
    );

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
