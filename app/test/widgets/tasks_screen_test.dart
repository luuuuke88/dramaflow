import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/tasks_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-tasksui-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    projectId = engine.addProject(projectType: 'novel', name: '任务筛选项目');
    // 三条不同 taskClass / state 的历史任务
    void task(
      String taskClass,
      String state,
      String describe, {
      int? targetProjectId,
      String? reason,
      String? relatedObjects,
    }) {
      db.execute(
        'INSERT INTO o_tasks '
        '(taskClass,state,projectId,describe,reason,relatedObjects,startTime) '
        'VALUES (?,?,?,?,?,?,?)',
        [
          taskClass,
          state,
          targetProjectId ?? projectId,
          describe,
          reason,
          relatedObjects,
          1700000000000,
        ],
      );
    }

    // 全部用非活动状态（success/failed/canceled），避免落入顶部"进行中"区段，
    // 使断言只针对历史区段的筛选结果。
    task('event_generation', 'success', '事件生成完成');
    task(
      'asset_extraction',
      'failed',
      '素材提取失败',
      reason: '{"errKey":"errModelMissing","errParams":{}}',
      relatedObjects: '{"scriptIds":[7,8]}',
    );
    task('event_generation', 'canceled', '事件生成已取消');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: const TasksScreen(),
        ),
      );

  // 任务中心挂着队列轮询定时器，pumpAndSettle 永不收敛；用固定次数的 pump 驱动。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('历史任务全部展示且带类型+状态筛选下拉', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('事件生成'), findsWidgets);
    expect(find.text('素材提取'), findsWidgets);
    // 两个筛选下拉（任务类型 / 状态）都出现
    expect(find.textContaining('任务类型:'), findsWidgets);
    expect(find.textContaining('状态:'), findsWidgets);
  });

  testWidgets('历史默认跨项目展示，并可翻到下一页', (tester) async {
    final secondProjectId =
        engine.addProject(projectType: 'novel', name: '第二项目');
    for (var index = 0; index < 12; index++) {
      db.execute(
        'INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) '
        'VALUES (?,?,?,?,?)',
        [
          'event_generation',
          'success',
          secondProjectId,
          '第二项目任务 ${index + 1}',
          1700000010000 + index,
        ],
      );
    }

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.byKey(const ValueKey('task-project-filter')), findsOneWidget);
    expect(find.textContaining('第二项目任务 12'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-page-next')), findsOneWidget);
    expect(find.text('共 15 条'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('task-page-next')))
          .onPressed,
      isNotNull,
    );

    final scrollable = find.byType(Scrollable).first;
    final scrollState = tester.state<ScrollableState>(scrollable);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await settle(tester);
    expect(scrollState.position.pixels, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('task-page-next')));
    await settle(tester);

    expect(find.textContaining('第二项目任务 12'), findsNothing);
    expect(find.textContaining('第二项目任务 2'), findsOneWidget);
    expect(find.textContaining('任务筛选项目'), findsWidgets);
  });

  testWidgets('任务中心本地化展示全部流水线任务类型', (tester) async {
    final classes = {
      'asset_prompt_polish': '素材提示词润色',
      'director_plan_generation': '导演规划生成',
      'storyboard_table_generation': '分镜表生成',
      'asset_image_generation': '素材生图',
      'storyboard_generate': '分镜生成',
      'storyboard_image_generation': '首帧图生成',
      'video_prompt_generation': '视频提示词生成',
      'video_generation': '视频生成',
      'audio_bind': '配音匹配',
    };
    var startTime = 1700000000100;
    for (final entry in classes.entries) {
      db.execute(
        'INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) '
        'VALUES (?,?,?,?,?)',
        [entry.key, 'success', projectId, entry.value, startTime++],
      );
    }

    await tester.pumpWidget(app());
    await settle(tester);

    for (final entry in classes.entries) {
      expect(find.text(entry.value), findsWidgets);
      expect(find.text(entry.key), findsNothing);
    }
  });

  testWidgets('刷新会重新读取跨项目历史任务', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    db.execute(
      'INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) '
      'VALUES (?,?,?,?,?)',
      [
        'event_generation',
        'success',
        projectId,
        '刷新后读取的任务',
        1700000020000,
      ],
    );
    expect(find.textContaining('刷新后读取的任务'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task-history-refresh')));
    await settle(tester);

    expect(find.textContaining('刷新后读取的任务'), findsOneWidget);
  });

  testWidgets('按状态筛选：仅失败时只剩素材提取行', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    // 打开状态下拉，选择"失败"
    await tester.tap(find.textContaining('状态: 全部').last);
    await settle(tester);
    await tester.tap(find.textContaining('状态: 失败').last);
    await settle(tester);

    expect(find.text('素材提取'), findsOneWidget);
    expect(find.text('事件生成'), findsNothing);
  });

  testWidgets('按任务类型筛选并调整每页数量', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('task-class-filter')));
    await settle(tester);
    await tester.tap(find.textContaining('任务类型: 事件生成').last);
    await settle(tester);

    expect(find.text('事件生成'), findsWidgets);
    expect(find.text('素材提取'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task-page-size')));
    await settle(tester);
    await tester.tap(find.text('25').last);
    await settle(tester);

    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('task-page-size')),
          )
          .value,
      25,
    );
  });

  testWidgets('点击任务行打开只读详情弹窗', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('素材提取').first);
    await settle(tester);

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('素材提取失败'), findsWidgets);
  });

  testWidgets('移动端任务中心：项目筛选和详情弹窗可用', (tester) async {
    final secondProjectId =
        engine.addProject(projectType: 'novel', name: '第二项目');
    db.execute(
      'UPDATE o_project SET createTime=0 WHERE id=?',
      [secondProjectId],
    );
    db.execute(
      'INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) '
      'VALUES (?,?,?,?,?)',
      [
        'storyboard_generate',
        'failed',
        secondProjectId,
        '第二项目分镜失败',
        1700000000000,
      ],
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('素材提取'), findsOneWidget);
    expect(find.textContaining('第二项目分镜失败'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-project-filter')));
    await settle(tester);
    await tester.tap(find.textContaining('第二项目').last);
    await settle(tester);

    expect(find.textContaining('第二项目分镜失败'), findsOneWidget);
    expect(find.text('素材提取'), findsNothing);
    expect(find.text('storyboard_generate'), findsNothing);

    await tester.tap(find.text('分镜生成').first);
    await settle(tester);

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('第二项目分镜失败'), findsWidgets);
  });

  testWidgets('移动端任务中心：分页控件可达且能翻页', (tester) async {
    final secondProjectId =
        engine.addProject(projectType: 'novel', name: '移动分页项目');
    for (var index = 0; index < 12; index++) {
      db.execute(
        'INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) '
        'VALUES (?,?,?,?,?)',
        [
          'event_generation',
          'success',
          secondProjectId,
          '移动分页任务 ${index + 1}',
          1700000030000 + index,
        ],
      );
    }

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.textContaining('移动分页任务 12'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('task-page-next')));
    await settle(tester);

    expect(find.textContaining('移动分页任务 12'), findsNothing);
    expect(find.textContaining('移动分页任务 2'), findsOneWidget);
  });

  testWidgets('移动端任务中心：失败任务可重试，待处理任务可取消', (tester) async {
    db.execute(
      "INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) "
      "VALUES ('event_generation','pending',?,?,?)",
      [projectId, '等待取消的事件生成', 1700000000001],
    );
    final pendingId = db.lastInsertRowId;

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.byTooltip('重试').first);
    await settle(tester);

    final attempts = db.select(
      "SELECT state, reason FROM o_tasks WHERE describe='素材提取失败' ORDER BY id",
    );
    expect(attempts, hasLength(2));
    expect(attempts.first['state'], 'failed');
    expect(attempts.first['reason'], isNotNull);
    expect(attempts.last['state'], 'pending');
    expect(attempts.last['reason'], isNull);
    expect(find.text('已重新排队'), findsOneWidget);
    expect(find.textContaining('第 2 次'), findsWidgets);
    expect(find.byTooltip('重试'), findsNothing,
        reason: '已有后续 attempt 的失败行不能重复重试');

    await tester.pump(const Duration(seconds: 3));
    final pendingTile = find.ancestor(
      of: find.textContaining('等待取消的事件生成').first,
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(
      of: pendingTile,
      matching: find.byTooltip('取消任务'),
    ));
    await settle(tester);

    final canceled = db.select(
      'SELECT state, reason FROM o_tasks WHERE id=?',
      [pendingId],
    ).single;
    expect(canceled['state'], 'failed');
    expect(canceled['reason'] as String, contains('errCanceled'));
  });
}
