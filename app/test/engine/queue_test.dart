// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/queue.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Future<void> waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('waitFor 超时');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  late Database db;
  JobQueue? q;

  String taskState(int id) =>
      db.select('SELECT state FROM o_tasks WHERE id=?', [id]).first['state']
          as String;

  String? taskReason(int id) =>
      db.select('SELECT reason FROM o_tasks WHERE id=?', [id]).first['reason']
          as String?;

  setUp(() {
    db = openEngineDb(':memory:');
    db.execute(
      "INSERT INTO o_project (id,name,projectType) VALUES (1,'t','drama')",
    );
  });

  tearDown(() {
    q?.dispose();
    db.close();
  });

  test('enqueue 写入 o_tasks pending 与 relatedObjects JSON', () {
    q = JobQueue(db, run: (task, token) async {});
    final id = q!.enqueue(
      projectId: 1,
      taskClass: 'event_generation',
      describe: '生成事件',
      model: 'p:m',
      relatedObjects: {
        'kind': 'novel',
        'ids': [1, 2],
      },
    );

    final row = TasksRow.fromRow(
      db.select('SELECT * FROM o_tasks WHERE id=?', [id]).first,
    );
    expect(row.state, 'pending');
    expect(row.taskClass, 'event_generation');
    expect(row.describe, '生成事件');
    expect(row.model, 'p:m');
    expect(row.relatedObjectsJson['kind'], 'novel');
    expect(row.relatedObjectsJson['ids'], [1, 2]);
  });

  test('start 执行成功写入 success + onTaskFinished 一次', () async {
    final finished = <String>[];
    q = JobQueue(
      db,
      run: (task, token) async {},
      tick: const Duration(milliseconds: 10),
    );
    q!.onTaskFinished =
        (id, taskClass, state) => finished.add('$taskClass:$state');
    q!.start();
    final id = q!.enqueue(projectId: 1, taskClass: 'event_generation');

    await waitFor(() => taskState(id) == 'success');
    expect(finished, ['event_generation:success']);
  });

  test('text 车道串行：event_generation 与 asset_extraction 峰值为 1', () async {
    var current = 0;
    var peak = 0;
    q = JobQueue(db, run: (task, token) async {
      current++;
      if (current > peak) peak = current;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      current--;
    }, tick: const Duration(milliseconds: 10));
    q!.start();
    final a = q!.enqueue(projectId: 1, taskClass: 'event_generation');
    final b = q!.enqueue(projectId: 1, taskClass: 'asset_extraction');

    await waitFor(() => taskState(a) == 'success' && taskState(b) == 'success');
    expect(peak, 1);
  });

  test('start 幂等：多次 start 不重复执行任务', () async {
    var runs = 0;
    q = JobQueue(db, run: (task, token) async {
      runs++;
    }, tick: const Duration(milliseconds: 10));
    q!
      ..start()
      ..start()
      ..start();
    final id = q!.enqueue(projectId: 1, taskClass: 'event_generation');

    await waitFor(() => taskState(id) == 'success');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(runs, 1);
  });

  test('recoverOnColdStart 将 processing 标记 failed(errAppRestart) 并调用 recover',
      () {
    db.execute(
      "INSERT INTO o_tasks (id,projectId,state,taskClass) VALUES (9,1,'processing','event_generation')",
    );
    final recovered = <int>[];
    q = JobQueue(db, run: (task, token) async {});
    q!.registerRecover('event_generation', (task) => recovered.add(task.id));

    q!.recoverOnColdStart();

    expect(taskState(9), 'failed');
    expect(
        EngineException.fromReasonJson(taskReason(9))!.errKey, errAppRestart);
    expect(recovered, [9]);
  });

  test('cancel pending 写入 failed(errCanceled)', () {
    q = JobQueue(db, run: (task, token) async {});
    final id = q!.enqueue(projectId: 1, taskClass: 'event_generation');

    q!.cancel(id);

    expect(taskState(id), 'failed');
    expect(EngineException.fromReasonJson(taskReason(id))!.errKey, errCanceled);
  });

  test('cancel processing 通过 token 终止为 failed(errCanceled)', () async {
    q = JobQueue(db, run: (task, token) async {
      await token.whenCancel;
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: '/x'),
        reason: 'user',
      );
    }, tick: const Duration(milliseconds: 10));
    q!.start();
    final id = q!.enqueue(projectId: 1, taskClass: 'event_generation');
    await waitFor(() => taskState(id) == 'processing');

    q!.cancel(id);

    await waitFor(() => taskState(id) == 'failed');
    expect(EngineException.fromReasonJson(taskReason(id))!.errKey, errCanceled);
  });

  test('runner EngineException 写入 reason JSON', () async {
    q = JobQueue(db, run: (task, token) async {
      throw const EngineException(
          errModelMissing, {'stage': 'event_generation'});
    }, tick: const Duration(milliseconds: 10));
    q!.start();
    final id = q!.enqueue(projectId: 1, taskClass: 'event_generation');

    await waitFor(() => taskState(id) == 'failed');
    final reason = EngineException.fromReasonJson(taskReason(id));
    expect(reason!.errKey, errModelMissing);
    expect(reason.errParams['stage'], 'event_generation');
  });

  test('hasActiveTask 支持 taskClass 与 projectId 过滤', () {
    q = JobQueue(db, run: (task, token) async {});
    q!.enqueue(projectId: 1, taskClass: 'event_generation');
    db.execute(
      "INSERT INTO o_project (id,name,projectType) VALUES (2,'other','drama')",
    );

    expect(q!.hasActiveTask('event_generation'), isTrue);
    expect(q!.hasActiveTask('event_generation', projectId: 1), isTrue);
    expect(q!.hasActiveTask('event_generation', projectId: 2), isFalse);
    expect(q!.hasActiveTask('asset_extraction'), isFalse);
  });

  test('events 广播 enqueue/claim/finish', () async {
    q = JobQueue(
      db,
      run: (task, token) async {},
      tick: const Duration(milliseconds: 10),
    );
    var count = 0;
    final sub = q!.events.listen((_) => count++);
    q!.start();
    final id = q!.enqueue(projectId: 1, taskClass: 'event_generation');

    await waitFor(() => taskState(id) == 'success');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();
    expect(count, greaterThanOrEqualTo(3));
  });
}
