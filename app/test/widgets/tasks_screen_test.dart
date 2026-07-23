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
          home: const Scaffold(body: TasksScreen()),
        ),
      );

  // 任务中心挂着队列轮询定时器，pumpAndSettle 永不收敛；用固定次数的 pump 驱动。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('历史任务全部展示且带类型+状态筛选下拉', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('事件生成'), findsWidgets);
    expect(find.text('素材提取'), findsWidgets);
    // 筛选卡片上的三个下拉（项目/大类/状态）都有标签与触发框
    expect(find.text('任务大类'), findsWidgets);
    expect(find.text('任务状态'), findsWidgets);
    expect(find.text('全部大类'), findsOneWidget);
    expect(find.text('全部状态'), findsOneWidget);
  });

  testWidgets('任务中心本地化展示全部流水线任务类型', (tester) async {
    final classes = {
      'asset_prompt_polish': '素材提示词润色',
      'director_plan_generation': '导演规划生成',
      'storyboard_table_generation': '分镜表生成',
      'asset_image_generation': '素材生图',
      'storyboard_generate': '分镜生成',
      'storyboard_image_generation': '首帧图生成',
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

    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);

    for (final entry in classes.entries) {
      expect(find.text(entry.value), findsWidgets,
          reason: '${entry.key} 应显示为本地化名称 ${entry.value}');
      expect(find.text(entry.key), findsNothing);
    }
  });

  testWidgets('按状态筛选：仅失败时只剩素材提取行', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);

    // 打开状态下拉，选择"失败"
    await tester.tap(find.text('全部状态'));
    await settle(tester);
    await tester.tap(find.text('失败').last);
    await settle(tester);

    expect(find.text('素材提取'), findsOneWidget);
    expect(find.text('事件生成'), findsNothing);
  });

  testWidgets('点击任务行打开只读详情弹窗', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

    // 默认跨项目展示：两个项目的任务都可见
    expect(find.text('素材提取'), findsOneWidget);
    expect(find.textContaining('第二项目分镜失败'), findsOneWidget);

    await tester.tap(find.text('全部项目'));
    await settle(tester);
    await tester.tap(find.text('第二项目').last);
    await settle(tester);

    expect(find.textContaining('第二项目分镜失败'), findsOneWidget);
    expect(find.text('素材提取'), findsNothing);
    expect(find.text('storyboard_generate'), findsNothing);

    await tester.tap(find.text('分镜生成').first);
    await settle(tester);

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('第二项目分镜失败'), findsWidgets);
  });

  testWidgets('移动端任务中心：失败任务可重试，待处理任务可取消', (tester) async {
    // 用一个队列不认识的任务类型：重试动作会唤醒队列，若这里用真实类型，
    // 队列会抢在点"取消"之前把它执行掉（失败），断言就测不到取消链路了。
    db.execute(
      "INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) "
      "VALUES ('debug_hold','pending',?,?,?)",
      [projectId, '等待取消的事件生成', 1700000000001],
    );
    final pendingId = db.lastInsertRowId;

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await settle(tester);

    // 失败卡片上的"重试"按钮
    await tester.ensureVisible(find.text('重试').first);
    await settle(tester);
    await tester.tap(find.text('重试').first);
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
    expect(find.text('重试'), findsNothing,
        reason: '已有后续 attempt 的失败行不能重复重试');

    // 等待中的卡片上的"取消任务"按钮：重试产生的新任务也带取消按钮，
    // 必须锁定到"等待取消的事件生成"这张卡片内的那一个。
    await tester.pump(const Duration(seconds: 3));
    final pendingCard = find.ancestor(
      of: find.textContaining('等待取消的事件生成').first,
      matching: find.byType(InkWell),
    );
    final cancelButton = find.descendant(
      of: pendingCard,
      matching: find.text('取消任务'),
    );
    await tester.ensureVisible(cancelButton);
    await settle(tester);
    await tester.tap(cancelButton);
    await settle(tester);

    // 现在的引擎把"取消等待中的任务"记为 失败+已取消原因，而不是独立的
    // canceled 状态（界面上按原因显示为已取消）。
    final canceled = db.select(
      'SELECT state, reason FROM o_tasks WHERE id=?',
      [pendingId],
    ).single;
    expect(canceled['state'], 'failed');
    expect(canceled['reason'] as String, contains('errCanceled'));
  });
}
