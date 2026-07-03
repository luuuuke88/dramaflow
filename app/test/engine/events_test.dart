import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/events.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _ScriptedGateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-events-');
    db = openEngineDb(':memory:');
    gateway = _ScriptedGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    _seedPrompts(db);
    engine.installNovelEventPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: '事件测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> waitTask(int taskId, {String expectState = 'success'}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final state = db
          .select('SELECT state FROM o_tasks WHERE id=?', [taskId])
          .first['state'] as String;
      if (state == 'success' || state == 'failed') {
        expect(state, expectState);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('任务 $taskId 超时未完成');
  }

  List<ChapterItem> chapters(int n) => [
        for (var i = 1; i <= n; i++)
          ChapterItem(
            index: i,
            reel: '正文卷',
            chapter: '章$i',
            chapterData: '内容$i',
          ),
      ];

  test('导入章节自动触发事件生成：两成功一失败，事件落表', () async {
    gateway.script = (user) {
      if (user.contains('内容2')) throw DioException(requestOptions: RequestOptions());
      final idx = RegExp(r'章节数：(\d+)').firstMatch(user)!.group(1);
      return '<think>推理</think>| 第$idx章 标题$idx | 主角 | 核心事件$idx | 强（推进） | 高 | 50秒 | 转折 |';
    };
    final ids = engine.addNovels(projectId, chapters(3));
    final taskId = db
        .select("SELECT id FROM o_tasks WHERE taskClass='event_generation'")
        .first['id'] as int;
    await waitTask(taskId);

    final rows = engine.novels(projectId).data;
    expect(rows.map((r) => r.eventState), [1, -1, 1]);
    expect(rows.first.event, startsWith('| 第1章'), reason: 'stripThink 生效');
    final failed = rows[1];
    expect(
      EngineException.fromReasonJson(failed.errorReason)?.errKey,
      errNetwork,
    );
    expect(db.select('SELECT COUNT(*) n FROM o_event').first['n'], 2);
    final links = db.select(
      'SELECT novelId FROM o_eventChapter ORDER BY novelId',
    );
    expect(links.map((r) => r['novelId']), [ids[0], ids[2]]);
    // 事件名 = 管道首字段
    expect(
      db.select('SELECT name FROM o_event ORDER BY id').first['name'],
      '第1章 标题1',
    );
  });

  test('重跑同章不产生重复事件行', () async {
    gateway.script = (user) => '| 第1章 A | 角 | 事 | 强 | 高 | 50秒 | 转折 |';
    engine.addNovels(projectId, chapters(1));
    var taskId = db
        .select("SELECT MAX(id) id FROM o_tasks")
        .first['id'] as int;
    await waitTask(taskId);

    final novelId = engine.novels(projectId).data.single.id;
    engine.generateEvents(projectId, [novelId]);
    taskId = db.select('SELECT MAX(id) id FROM o_tasks').first['id'] as int;
    await waitTask(taskId);

    expect(db.select('SELECT COUNT(*) n FROM o_event').first['n'], 1);
    expect(db.select('SELECT COUNT(*) n FROM o_eventChapter').first['n'], 1);
  });

  test('全部失败时任务失败并保留首个错误', () async {
    gateway.script = (_) => throw const EngineException(errProviderMissing);
    engine.addNovels(projectId, chapters(2));
    final taskId = db.select('SELECT MAX(id) id FROM o_tasks').first['id'] as int;
    await waitTask(taskId, expectState: 'failed');
    final reason = db
        .select('SELECT reason FROM o_tasks WHERE id=?', [taskId])
        .first['reason'] as String;
    expect(EngineException.fromReasonJson(reason)?.errKey, errProviderMissing);
  });

  test('冷启动恢复：processing 任务判失败且滞留章置 -1/errAppRestart', () async {
    final ids = engine.addNovels(projectId, chapters(1));
    // 手工伪造中断现场
    db.execute("UPDATE o_tasks SET state='processing'");
    db.execute('UPDATE o_novel SET eventState=0');
    engine.queue.recoverOnColdStart();

    final novel = engine.novels(projectId).data.single;
    expect(novel.eventState, -1);
    expect(
      EngineException.fromReasonJson(novel.errorReason)?.errKey,
      errAppRestart,
    );
    expect(ids, isNotEmpty);
  });

  test('events 分页 JOIN 返回章节号数组', () async {
    gateway.script = (user) {
      final idx = RegExp(r'章节数：(\d+)').firstMatch(user)!.group(1);
      return '| 第$idx章 名$idx | 角 | 事 | 强 | 高 | 50秒 | 转折 |';
    };
    engine.addNovels(projectId, chapters(12));
    final taskId = db.select('SELECT MAX(id) id FROM o_tasks').first['id'] as int;
    await waitTask(taskId);

    final page1 = engine.events(projectId, page: 1, limit: 10);
    expect(page1.total, 12);
    expect(page1.list, hasLength(10));
    expect(page1.list.first.chapters, [1]);

    final hit = engine.events(projectId, search: '名3');
    expect(hit.total, 1);

    engine.deleteEvents([page1.list.first.id]);
    expect(engine.events(projectId).total, 11);
  });

  test('eventAnalysis 汇总章节事件并剥离思维链', () async {
    gateway.script = (user) {
      if (user.contains('内容1')) {
        return '| 第1章 名 | 角 | 事 | 强 | 高 | 50秒 | 转折 |';
      }
      expect(user, contains('第1章'));
      return '<think>x</think>[{"chapterIndex":1,"analysis":"值得保留"}]';
    };
    final ids = engine.addNovels(projectId, chapters(1));
    final taskId = db.select('SELECT MAX(id) id FROM o_tasks').first['id'] as int;
    await waitTask(taskId);

    final analysis = await engine.eventAnalysis(projectId, ids);
    expect(analysis, '[{"chapterIndex":1,"analysis":"值得保留"}]');

    expect(
      () => engine.eventAnalysis(projectId, const []),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errNoChapters)),
    );
  });
}

void _seedPrompts(Database db) {
  for (final entry in {
    'eventExtraction': '事件提取系统提示词',
    'eventAnalysis': '事件分析系统提示词',
  }.entries) {
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
      [entry.key, entry.key, entry.value],
    );
  }
}

class _ScriptedGateway implements ProviderGateway {
  String Function(String user)? script;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    expect(stage, 'event_extract');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return TextResult(script!(user));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
