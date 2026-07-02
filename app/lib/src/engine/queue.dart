import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'db.dart';
import 'util.dart';
import 'pipeline/runners.dart' show JobRow;

/// 任务队列（移植 server/src/queue.ts + M0 生命周期约定）。
/// - 车道串行：text=1 / image=1 / video=1（azt/OAuth 路径脆弱，宁慢勿炸）
/// - start() 幂等：全局唯一 worker loop，热重载不叠加
/// - 冷启动恢复：running→failed('应用重启，任务中断') + 实体三处复位
/// - 取消：queued→canceled+实体按产物恢复；running→CancelToken 中断→canceled
/// - events：任意状态迁移广播（UI watch 源）；onJobFinished：M3.5 导演循环钩子
class JobQueue {
  final Database db;
  final Future<String> Function(JobRow job, CancelToken token) run;
  final Duration tick;

  Timer? _timer;
  bool _started = false;
  final _runningByLane = {'text': 0, 'image': 0, 'video': 0};
  final _cancelTokens = <String, CancelToken>{};
  final _events = StreamController<void>.broadcast();

  void Function(String jobId, String kind, String state)? onJobFinished;

  static const laneOf = {
    'script_gen': 'text',
    'asset_extract': 'text',
    'storyboard_gen': 'text',
    'asset_image': 'image',
    'shot_image': 'image',
    'shot_video': 'video',
    'compose': 'video',
  };
  static const laneCap = {'text': 1, 'image': 1, 'video': 1};

  JobQueue(this.db,
      {required this.run, this.tick = const Duration(milliseconds: 500)});

  Stream<void> get events => _events.stream;

  void notifyChanged() => _events.add(null);

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(tick, (_) => _tick());
  }

  /// 仅冷启动调用（resume 不调用——后台冻结期间任务可能仍在收尾）
  void recoverOnColdStart() {
    final n = db
        .select("SELECT COUNT(*) n FROM jobs WHERE state='running'")
        .first['n'] as int;
    db.execute(
        "UPDATE jobs SET state='failed', error='应用重启，任务中断', finishedAt=? WHERE state='running'",
        [nowIso()]);
    db.execute(
        "UPDATE assets SET status='failed', error='应用重启，任务中断' WHERE status='running'");
    db.execute(
        "UPDATE shots SET imageStatus='failed', imageError='应用重启，任务中断' WHERE imageStatus='running'");
    db.execute(
        "UPDATE shots SET videoStatus='failed', videoError='应用重启，任务中断' WHERE videoStatus='running'");
    db.execute(
        "UPDATE episodes SET composeStatus='failed', composeError='应用重启，任务中断' WHERE composeStatus='running'");
    if (n > 0) _events.add(null);
  }

  String enqueue({
    required String projectId,
    required String kind,
    String targetId = '',
    String targetLabel = '',
    Map<String, dynamic> payload = const {},
    int attempt = 1,
  }) {
    final id = newId();
    db.execute(
        "INSERT INTO jobs (id, projectId, kind, targetId, targetLabel, state, attempt, payload, createdAt) VALUES (?,?,?,?,?,'queued',?,?,?)",
        [
          id,
          projectId,
          kind,
          targetId,
          targetLabel,
          attempt,
          jsonEncode(payload),
          nowIso()
        ]);
    _events.add(null);
    return id;
  }

  bool hasActiveJob(String kind, String targetId) => db.select(
      "SELECT id FROM jobs WHERE kind=? AND targetId=? AND state IN ('queued','running') LIMIT 1",
      [kind, targetId]).isNotEmpty;

  void cancel(String jobId) {
    final rows = db.select(
        'SELECT id, kind, targetId, state FROM jobs WHERE id=?', [jobId]);
    if (rows.isEmpty) throw EngineException('任务不存在');
    final j = rows.first;
    final state = j['state'] as String;
    if (state == 'queued') {
      db.execute(
          "UPDATE jobs SET state='canceled', finishedAt=? WHERE id=? AND state='queued'",
          [nowIso(), jobId]);
      _restoreEntity(j['kind'] as String, j['targetId'] as String);
      _events.add(null);
      onJobFinished?.call(jobId, j['kind'] as String, 'canceled');
      return;
    }
    if (state == 'running') {
      _cancelTokens[jobId]?.cancel('用户取消');
      return; // 终态由 _execute 的 catch 写入
    }
    throw EngineException('只有排队中或运行中的任务可以取消');
  }

  /// 取消后的实体状态恢复：已有产物→done，否则回初始态（v0.1 cancel 语义）
  void _restoreEntity(String kind, String targetId) {
    switch (kind) {
      case 'asset_image':
        db.execute(
            "UPDATE assets SET status = CASE WHEN imagePath IS NOT NULL THEN 'done' ELSE 'draft' END, error=NULL WHERE id=?",
            [targetId]);
      case 'shot_image':
        db.execute(
            "UPDATE shots SET imageStatus = CASE WHEN imagePath IS NOT NULL THEN 'done' ELSE 'none' END, imageError=NULL WHERE id=?",
            [targetId]);
      case 'shot_video':
        db.execute(
            "UPDATE shots SET videoStatus = CASE WHEN videoPath IS NOT NULL THEN 'done' ELSE 'none' END, videoError=NULL WHERE id=?",
            [targetId]);
      case 'compose':
        db.execute(
            "UPDATE episodes SET composeStatus = CASE WHEN composedPath IS NOT NULL THEN 'done' ELSE 'none' END, composeError=NULL WHERE id=?",
            [targetId]);
    }
  }

  void _tick() {
    for (final lane in laneCap.keys) {
      while ((_runningByLane[lane] ?? 0) < laneCap[lane]!) {
        final job = _claim(lane);
        if (job == null) break;
        unawaited(_execute(job, lane));
      }
    }
  }

  JobRow? _claim(String lane) {
    final kinds = laneOf.entries
        .where((e) => e.value == lane)
        .map((e) => "'${e.key}'")
        .join(',');
    final rows = db.select(
        "SELECT id, projectId, kind, targetId, payload FROM jobs WHERE state='queued' AND kind IN ($kinds) ORDER BY createdAt ASC LIMIT 1");
    if (rows.isEmpty) return null;
    final r = rows.first;
    db.execute("UPDATE jobs SET state='running', startedAt=? WHERE id=?",
        [nowIso(), r['id']]);
    _events.add(null);
    return JobRow(r['id'] as String, r['projectId'] as String,
        r['kind'] as String, r['targetId'] as String, r['payload'] as String);
  }

  Future<void> _execute(JobRow job, String lane) async {
    _runningByLane[lane] = (_runningByLane[lane] ?? 0) + 1;
    final token = CancelToken();
    _cancelTokens[job.id] = token;
    var finalState = 'failed';
    try {
      final result = await run(job, token);
      db.execute(
          "UPDATE jobs SET state='done', result=?, finishedAt=? WHERE id=? AND state='running'",
          [result, nowIso(), job.id]);
      finalState = 'done';
    } catch (e) {
      if (token.isCancelled) {
        db.execute(
            "UPDATE jobs SET state='canceled', finishedAt=? WHERE id=? AND state='running'",
            [nowIso(), job.id]);
        _restoreEntity(job.kind, job.targetId); // 覆盖 runner catch 写的 failed
        finalState = 'canceled';
      } else {
        final msg = errMessage(e);
        db.execute(
            "UPDATE jobs SET state='failed', error=?, finishedAt=? WHERE id=? AND state='running'",
            [
              msg.length > 2000 ? msg.substring(0, 2000) : msg,
              nowIso(),
              job.id
            ]);
        finalState = 'failed';
      }
    } finally {
      _runningByLane[lane] = (_runningByLane[lane] ?? 1) - 1;
      _cancelTokens.remove(job.id);
      _events.add(null);
      onJobFinished?.call(job.id, job.kind, finalState);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _events.close();
  }
}
