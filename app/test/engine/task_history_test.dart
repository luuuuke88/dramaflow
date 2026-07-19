import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/queue.dart';
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
  late int firstProjectId;
  late int secondProjectId;
  late List<int> insertedIds;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-task-history-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    firstProjectId = engine.addProject(projectType: 'drama', name: '第一项目');
    secondProjectId = engine.addProject(projectType: 'drama', name: '第二项目');
    insertedIds = [];
    for (var index = 0; index < 27; index++) {
      final projectId = index.isEven ? firstProjectId : secondProjectId;
      final taskClass =
          index % 3 == 0 ? 'event_generation' : 'asset_extraction';
      final state = index % 4 == 0 ? 'failed' : 'success';
      db.execute(
        'INSERT INTO o_tasks (projectId,state,taskClass,describe,startTime) '
        'VALUES (?,?,?,?,?)',
        [projectId, state, taskClass, '任务 ${index + 1}', 1700000000000 + index],
      );
      insertedIds.add(db.lastInsertRowId);
    }
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('跨项目历史按最新排序分页，并返回项目名称和总数', () async {
    final page = await engine.taskHistory(TaskHistoryQuery(page: 2, limit: 10));

    expect(page.total, 27);
    expect(page.totalPages, 3);
    expect(page.hasPrevious, isTrue);
    expect(page.hasNext, isTrue);
    expect(page.items.map((task) => task.id),
        insertedIds.reversed.skip(10).take(10));
    expect(
      page.items.map((task) => task.projectName).toSet(),
      {'第一项目', '第二项目'},
    );
  });

  test('历史查询在数据库中按项目、类型和状态筛选', () async {
    final page = await engine.taskHistory(
      TaskHistoryQuery(
        projectId: firstProjectId,
        taskClass: 'event_generation',
        state: 'failed',
        limit: 50,
      ),
    );

    expect(page.items, isNotEmpty);
    expect(
        page.items.every((task) => task.projectId == firstProjectId), isTrue);
    expect(page.items.every((task) => task.taskClass == 'event_generation'),
        isTrue);
    expect(page.items.every((task) => task.state == 'failed'), isTrue);
    expect(await engine.taskHistoryClasses(), [
      'asset_extraction',
      'event_generation',
    ]);
  });
}
