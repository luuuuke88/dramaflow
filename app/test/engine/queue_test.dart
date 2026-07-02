// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/queue.dart';

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('waitFor 超时');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  late Database db;
  late JobQueue q;

  String jobState(String id) =>
      db.select('SELECT state FROM jobs WHERE id=?', [id]).first['state']
          as String;

  setUp(() {
    db = openEngineDb(':memory:');
    db.execute(
        "INSERT INTO projects (id,name,createdAt,updatedAt) VALUES ('p1','t','x','x')");
  });
  tearDown(() {
    q.dispose();
    db.close();
  });

  test('enqueue→done + onJobFinished 一次', () async {
    final finished = <String>[];
    q = JobQueue(db,
        run: (job, token) async => 'ok',
        tick: const Duration(milliseconds: 10));
    q.onJobFinished = (id, kind, state) => finished.add('$kind:$state');
    q.start();
    final id = q.enqueue(projectId: 'p1', kind: 'script_gen', targetId: 'p1');
    await waitFor(() => jobState(id) == 'done');
    expect(finished, ['script_gen:done']);
  });

  test('车道串行：image 并发峰值为 1', () async {
    var current = 0, peak = 0;
    q = JobQueue(db, run: (job, token) async {
      current++;
      if (current > peak) peak = current;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      current--;
      return 'ok';
    }, tick: const Duration(milliseconds: 10));
    q.start();
    final a = q.enqueue(projectId: 'p1', kind: 'asset_image', targetId: 'a1');
    final b = q.enqueue(projectId: 'p1', kind: 'shot_image', targetId: 's1');
    await waitFor(() => jobState(a) == 'done' && jobState(b) == 'done');
    expect(peak, 1);
  });

  test('幂等 start：三次 start 执行次数不重复', () async {
    var runs = 0;
    q = JobQueue(db, run: (job, token) async {
      runs++;
      return 'ok';
    }, tick: const Duration(milliseconds: 10));
    q.start();
    q.start();
    q.start();
    final id = q.enqueue(projectId: 'p1', kind: 'script_gen', targetId: 'p1');
    await waitFor(() => jobState(id) == 'done');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 1);
  });

  test('冷启动恢复：running→failed + 实体复位', () async {
    db.execute(
        "INSERT INTO jobs (id,projectId,kind,state,createdAt) VALUES ('jr','p1','asset_image','running','x')");
    db.execute(
        "INSERT INTO assets (id,projectId,kind,name,status,createdAt) VALUES ('ar','p1','character','x','running','x')");
    q = JobQueue(db, run: (j, t) async => 'ok');
    q.recoverOnColdStart();
    expect(jobState('jr'), 'failed');
    expect(
        db.select('SELECT error FROM jobs').first['error'], contains('应用重启'));
    expect(db.select('SELECT status FROM assets').first['status'], 'failed');
  });

  test('cancel queued：有产物的镜头恢复为 done', () async {
    db.execute(
        "INSERT INTO episodes (id,projectId,idx,createdAt) VALUES ('e1','p1',1,'x')");
    db.execute(
        "INSERT INTO shots (id,episodeId,projectId,idx,imagePath,imageStatus,createdAt) VALUES ('s1','e1','p1',1,'p1/img_old.png','queued','x')");
    q = JobQueue(db, run: (j, t) async => 'ok'); // 不 start，保持 queued
    final id = q.enqueue(projectId: 'p1', kind: 'shot_image', targetId: 's1');
    q.cancel(id);
    expect(jobState(id), 'canceled');
    expect(db.select('SELECT imageStatus FROM shots').first['imageStatus'],
        'done');
  });

  test('cancel running：token 中断 → canceled 而非 failed', () async {
    q = JobQueue(db, run: (job, token) async {
      await token.whenCancel; // 挂起直到取消
      throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/x'), reason: 'user');
    }, tick: const Duration(milliseconds: 10));
    q.start();
    final id = q.enqueue(projectId: 'p1', kind: 'asset_image', targetId: 'a1');
    await waitFor(() => jobState(id) == 'running');
    q.cancel(id);
    await waitFor(() => jobState(id) == 'canceled');
    expect(jobState(id), 'canceled');
  });

  test('events 广播状态迁移', () async {
    q = JobQueue(db,
        run: (j, t) async => 'ok', tick: const Duration(milliseconds: 10));
    var count = 0;
    final sub = q.events.listen((_) => count++);
    q.start();
    final id = q.enqueue(projectId: 'p1', kind: 'script_gen', targetId: 'p1');
    await waitFor(() => jobState(id) == 'done');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(count, greaterThanOrEqualTo(2)); // enqueue + claim/finish
    await sub.cancel();
  });
}
