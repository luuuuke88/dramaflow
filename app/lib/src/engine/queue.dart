import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';

import 'errors.dart';

class TasksRow {
  final int id;
  final int? projectId;
  final String? projectName;
  final String state;
  final String? reason;
  final String? relatedObjects;
  final String taskClass;
  final int? startTime;
  final String? model;
  final String? describe;

  const TasksRow({
    required this.id,
    required this.projectId,
    this.projectName,
    required this.state,
    required this.reason,
    required this.relatedObjects,
    required this.taskClass,
    required this.startTime,
    required this.model,
    required this.describe,
  });

  factory TasksRow.fromRow(Row row) => TasksRow(
        id: row['id'] as int,
        projectId: row['projectId'] as int?,
        projectName: row['projectName'] as String?,
        state: row['state'] as String? ?? 'pending',
        reason: row['reason'] as String?,
        relatedObjects: row['relatedObjects'] as String?,
        taskClass: row['taskClass'] as String? ?? '',
        startTime: row['startTime'] as int?,
        model: row['model'] as String?,
        describe: row['describe'] as String?,
      );

  Map<String, dynamic> get relatedObjectsJson {
    final raw = relatedObjects;
    if (raw == null || raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  }

  Map<String, dynamic> get retryJson {
    final value = relatedObjectsJson['_retry'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  int get attempt {
    final value = (retryJson['attempt'] as num?)?.toInt() ?? 1;
    return value < 1 ? 1 : value;
  }

  int? get previousAttemptId => (retryJson['previousTaskId'] as num?)?.toInt();

  int? get supersededByTaskId =>
      (retryJson['supersededByTaskId'] as num?)?.toInt();

  EngineException? get engineReason => EngineException.fromReasonJson(reason);
}

class TaskHistoryQuery {
  final int? projectId;
  final String? taskClass;
  final String? state;
  final int page;
  final int limit;

  factory TaskHistoryQuery({
    int? projectId,
    String? taskClass,
    String? state,
    int page = 1,
    int limit = 10,
  }) =>
      TaskHistoryQuery._(
        projectId: projectId,
        taskClass: _optionalValue(taskClass),
        state: _optionalValue(state),
        page: page < 1 ? 1 : page,
        limit: limit < 1 ? 1 : limit,
      );

  const TaskHistoryQuery._({
    required this.projectId,
    required this.taskClass,
    required this.state,
    required this.page,
    required this.limit,
  });

  int get offset => (page - 1) * limit;

  static String? _optionalValue(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  @override
  bool operator ==(Object other) =>
      other is TaskHistoryQuery &&
      other.projectId == projectId &&
      other.taskClass == taskClass &&
      other.state == state &&
      other.page == page &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(projectId, taskClass, state, page, limit);
}

class TaskHistoryPage {
  final List<TasksRow> items;
  final int total;
  final TaskHistoryQuery query;

  const TaskHistoryPage({
    required this.items,
    required this.total,
    required this.query,
  });

  int get totalPages =>
      total == 0 ? 1 : (total + query.limit - 1) ~/ query.limit;

  bool get hasPrevious => query.page > 1;

  bool get hasNext => query.page < totalPages;
}

typedef TaskRunner = Future<void> Function(TasksRow task, CancelToken token);
typedef TaskRecover = void Function(TasksRow task);

enum ColdStartDisposition { fail, resume }

typedef TaskColdStartResumer = ColdStartDisposition Function(TasksRow task);

class JobQueue {
  final Database db;
  final TaskRunner run;
  final Duration tick;

  Timer? _timer;
  bool _started = false;
  final _runningByLane = {'text': 0, 'image': 0, 'video': 0};
  final _cancelTokens = <int, CancelToken>{};
  final _recover = <String, TaskRecover>{};
  final _coldStartResumers = <String, TaskColdStartResumer>{};
  final _events = StreamController<void>.broadcast();

  void Function(int taskId, String taskClass, String state)? onTaskFinished;

  static const laneOf = {
    'event_generation': 'text',
    'script_generation': 'text',
    'asset_extraction': 'text',
    'asset_prompt_polish': 'text',
    'director_plan_generation': 'text',
    'storyboard_table_generation': 'text',
    'asset_image_generation': 'image',
    'storyboard_generate': 'text',
    'storyboard_image_generation': 'image',
    'video_generation': 'video',
    'audio_bind': 'text',
  };
  static const laneCap = {'text': 1, 'image': 1, 'video': 1};

  JobQueue(
    this.db, {
    required this.run,
    this.tick = const Duration(milliseconds: 500),
  });

  Stream<void> get events => _events.stream;

  void notifyChanged() => _events.add(null);

  void registerRecover(String taskClass, TaskRecover fn) {
    _recover[taskClass] = fn;
  }

  void registerColdStartResumer(String taskClass, TaskColdStartResumer fn) {
    _coldStartResumers[taskClass] = fn;
  }

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(tick, (_) => _tick());
  }

  void recoverOnColdStart() {
    final rows = db
        .select("SELECT * FROM o_tasks WHERE state='processing'")
        .map(TasksRow.fromRow)
        .toList();
    if (rows.isEmpty) return;
    final resumableIds = <int>[];
    for (final task in rows) {
      if (_coldStartResumers[task.taskClass]?.call(task) ==
          ColdStartDisposition.resume) {
        resumableIds.add(task.id);
      }
    }
    if (resumableIds.isNotEmpty) {
      db.execute(
        "UPDATE o_tasks SET state='pending', reason=NULL WHERE id IN (${_placeholders(resumableIds)})",
        resumableIds,
      );
    }
    final failedRows = rows
        .where((task) => !resumableIds.contains(task.id))
        .toList(growable: false);
    if (failedRows.isEmpty) {
      _events.add(null);
      return;
    }
    final reason = const EngineException(errAppRestart).toReasonJson();
    db.execute(
      "UPDATE o_tasks SET state='failed', reason=? WHERE state='processing' "
      'AND id IN (${_placeholders(failedRows.map((task) => task.id).toList())})',
      [reason, ...failedRows.map((task) => task.id)],
    );
    for (final task in failedRows) {
      _recover[task.taskClass]?.call(task);
    }
    _events.add(null);
  }

  int enqueue({
    required int projectId,
    required String taskClass,
    String? describe,
    String? model,
    Map<String, Object?> relatedObjects = const {},
  }) {
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,describe,model,relatedObjects,startTime) VALUES (?,'pending',?,?,?,?,?)",
      [
        projectId,
        taskClass,
        describe,
        model,
        jsonEncode(relatedObjects),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final id = db.lastInsertRowId;
    _events.add(null);
    return id;
  }

  bool hasActiveTask(String taskClass, {int? projectId}) {
    final params = <Object?>[taskClass];
    var sql =
        "SELECT id FROM o_tasks WHERE taskClass=? AND state IN ('pending','processing')";
    if (projectId != null) {
      sql += ' AND projectId=?';
      params.add(projectId);
    }
    sql += ' LIMIT 1';
    return db.select(sql, params).isNotEmpty;
  }

  void cancel(int taskId) {
    final rows = db.select('SELECT * FROM o_tasks WHERE id=?', [taskId]);
    if (rows.isEmpty) {
      throw const EngineException(errCanceled, {'reason': '任务不存在'});
    }
    final task = TasksRow.fromRow(rows.first);
    if (task.state == 'pending') {
      _fail(task, const EngineException(errCanceled));
      onTaskFinished?.call(task.id, task.taskClass, 'failed');
      return;
    }
    if (task.state == 'processing') {
      _cancelTokens[taskId]?.cancel(errCanceled);
      return;
    }
    throw const EngineException(errCanceled, {'reason': '任务已结束'});
  }

  void _tick() {
    for (final lane in laneCap.keys) {
      while ((_runningByLane[lane] ?? 0) < laneCap[lane]!) {
        final task = _claim(lane);
        if (task == null) break;
        unawaited(_execute(task, lane));
      }
    }
  }

  TasksRow? _claim(String lane) {
    final classes = laneOf.entries
        .where((entry) => entry.value == lane)
        .map((entry) => "'${entry.key}'")
        .join(',');
    if (classes.isEmpty) return null;
    final rows = db.select(
      "SELECT * FROM o_tasks WHERE state='pending' AND taskClass IN ($classes) ORDER BY id ASC LIMIT 1",
    );
    if (rows.isEmpty) return null;
    final id = rows.first['id'] as int;
    db.execute(
      "UPDATE o_tasks SET state='processing', reason=NULL WHERE id=? AND state='pending'",
      [id],
    );
    _events.add(null);
    return TasksRow.fromRow(
      db.select('SELECT * FROM o_tasks WHERE id=?', [id]).first,
    );
  }

  Future<void> _execute(TasksRow task, String lane) async {
    _runningByLane[lane] = (_runningByLane[lane] ?? 0) + 1;
    final token = CancelToken();
    _cancelTokens[task.id] = token;
    var finalState = 'failed';
    try {
      await run(task, token);
      // run() 正常返回，但取消可能在其同步收尾阶段（最后一次 await 之后）才被请求；
      // 若不检查会把已请求取消的任务错标为 success。
      if (token.isCancelled) {
        _fail(task, const EngineException(errCanceled));
      } else {
        db.execute(
          "UPDATE o_tasks SET state='success', reason=NULL WHERE id=? AND state='processing'",
          [task.id],
        );
        finalState = 'success';
      }
    } catch (e) {
      if (token.isCancelled) {
        _fail(task, const EngineException(errCanceled));
      } else if (e is EngineException) {
        _fail(task, e);
      } else if (e is DioException) {
        _fail(task, EngineException(errNetwork, {'message': e.message}));
      } else {
        _fail(task, EngineException(errLlmFormat, {'message': e.toString()}));
      }
    } finally {
      _runningByLane[lane] = (_runningByLane[lane] ?? 1) - 1;
      _cancelTokens.remove(task.id);
      _events.add(null);
      onTaskFinished?.call(task.id, task.taskClass, finalState);
    }
  }

  void _fail(TasksRow task, EngineException reason) {
    db.execute(
      "UPDATE o_tasks SET state='failed', reason=? WHERE id=? AND state IN ('pending','processing')",
      [reason.toReasonJson(), task.id],
    );
    _events.add(null);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _events.close();
  }
}

String _placeholders(List<int> ids) => List.filled(ids.length, '?').join(',');
