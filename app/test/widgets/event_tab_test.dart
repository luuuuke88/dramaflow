// EventTab 移动端适配回归测试：
// (a) 窄屏工具栏不因 Row 溢出而抛出 RenderFlex 异常；
// (b) 移动端卡片补回单条删除操作（此前只能批量选中删除）。
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/novel/event_tab.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    return const TextResult('');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-event-tab-ui-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    // 不调用 installNovelEventPipeline / 设置 onNovelsAdded，
    // 避免 addNovels 触发真实事件生成任务；测试直接向 o_event/o_eventChapter 落表，
    // 复刻 _replaceChapterEvent 的落表语义（照抄 events_test.dart 的做法）。
    projectId = engine.addProject(projectType: 'novel', name: '事件页测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 造一条事件：先建一章，再手工落 o_event/o_eventChapter（同 _replaceChapterEvent 语义）。
  int seedEvent(String name, String detail) {
    final novelId = engine.addNovels(projectId, [
      ChapterItem(index: 1, reel: '正文卷', chapter: '章1', chapterData: '内容1'),
    ]).single;
    db.execute(
      'INSERT INTO o_event (name,detail,createTime) VALUES (?,?,?)',
      [name, detail, DateTime.now().millisecondsSinceEpoch],
    );
    final eventId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_eventChapter (eventId,novelId) VALUES (?,?)',
      [eventId, novelId],
    );
    return eventId;
  }

  Widget app([double width = 390]) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 760)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: EventTab(projectId: projectId)),
          ),
        ),
      );

  testWidgets('窄屏（390px）下事件页工具栏不溢出', (tester) async {
    seedEvent('危机降临', '| 危机降临 | 角 | 事 | 强 | 高 | 50秒 | 转折 |');
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Bug 1 回归断言：窄屏下工具栏（2 个 FilledButton + 搜索框）不应触发
    // RenderFlex 溢出等布局异常。
    expect(tester.takeException(), isNull);
    expect(find.text('重新生成事件'), findsOneWidget);
    expect(find.text('批量删除'), findsOneWidget);
  });

  testWidgets('窄屏下事件卡片可单条删除（不再仅支持批量删除）', (tester) async {
    seedEvent('危机降临', '| 危机降临 | 角 | 事 | 强 | 高 | 50秒 | 转折 |');
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(db.select('SELECT COUNT(*) n FROM o_event').first['n'], 1);
    expect(find.text('危机降临'), findsOneWidget);

    // Bug 2 回归断言：移动卡片上存在独立的删除入口（trailing IconButton），
    // 点击后走确认弹窗，确认后单条删除成功——无需先进入批量选中模式。
    final deleteButton = find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('删除事件'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(db.select('SELECT COUNT(*) n FROM o_event').first['n'], 0);
    expect(find.text('危机降临'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动壳平板宽度下事件工具栏不溢出', (tester) async {
    seedEvent('平板事件', '平板宽度下的工具栏回归测试');
    tester.view.physicalSize = const Size(800, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(800));
    await tester.pumpAndSettle();

    expect(find.text('重新生成事件'), findsOneWidget);
    expect(find.text('批量删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
