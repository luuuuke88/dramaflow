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
    void task(String taskClass, String state, String describe) {
      db.execute(
        'INSERT INTO o_tasks (taskClass,state,projectId,describe,startTime) '
        'VALUES (?,?,?,?,?)',
        [taskClass, state, projectId, describe, 1700000000000],
      );
    }

    // 全部用非活动状态（success/failed/canceled），避免落入顶部"进行中"区段，
    // 使断言只针对历史区段的筛选结果。
    task('event_generation', 'success', '事件生成完成');
    task('asset_extraction', 'failed', '素材提取失败');
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

  testWidgets('点击任务行打开只读详情弹窗', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('素材提取').first);
    await settle(tester);

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('素材提取失败'), findsWidgets);
  });
}
