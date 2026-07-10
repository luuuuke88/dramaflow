import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/production_dependencies.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  String Function(String system, String user, String stage)? textHandler;
  var textCalls = 0;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    textCalls++;
    return TextResult(textHandler!(system, user, stage));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late _Gateway gateway;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-plan-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    engine.saveVisualManual(
      name: 'Ink',
      pack: 'ink_pack',
      data: const {'director_planning_style': 'VISUAL PLAN'},
    );
    engine.saveDirectorManual(
      name: 'Pace',
      pack: 'pace_pack',
      data: const {'director_planning_narrative': 'DIRECTOR PLAN'},
    );
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
      ['director_plan', 'director_plan', 'BASE PLAN'],
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '规划测试',
      artStyle: 'ink_pack',
      directorManual: 'pace_pack',
    );
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('剧本规划：初始为空串', () {
    expect(engine.scriptPlan(projectId), '');
  });

  test('剧本规划：写入后可读回，二次写入为更新而非新增', () {
    engine.saveScriptPlan(projectId, '# 第一幕\n\n少年下山。');
    expect(engine.scriptPlan(projectId), '# 第一幕\n\n少年下山。');

    engine.saveScriptPlan(projectId, '# 第一幕（修订）\n\n少年雪夜下山。');
    expect(engine.scriptPlan(projectId), '# 第一幕（修订）\n\n少年雪夜下山。');

    final rows = db.select(
      "SELECT id FROM o_agentWorkData WHERE projectId=? AND key='scriptPlan'",
      [projectId],
    );
    expect(rows, hasLength(1), reason: '二次写入应为 upsert，仅一行');
  });

  test('剧本规划与 Agent 对话（同表不同 key）互不干扰', () {
    engine.saveScriptPlan(projectId, '规划内容');
    db.execute(
      "INSERT INTO o_agentWorkData (projectId,key,data) VALUES (?,'agentChat','[]')",
      [projectId],
    );
    expect(engine.scriptPlan(projectId), '规划内容');
  });

  test('保存导演规划使所有分镜表和结构分镜过期', () {
    final scriptA =
        engine.addScript(projectId: projectId, name: '第一集', content: '山门雪夜');
    final scriptB =
        engine.addScript(projectId: projectId, name: '第二集', content: '玉佩示警');
    engine.saveStoryboardTable(projectId, scriptA, 'A 表');
    engine.saveStoryboardTable(projectId, scriptB, 'B 表');
    engine.setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptA,
      key: structuredStoryboardStateKey,
      sourceHash: 'a',
      stale: false,
    );
    engine.setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptB,
      key: structuredStoryboardStateKey,
      sourceHash: 'b',
      stale: false,
    );

    engine.saveScriptPlan(projectId, '# 新导演规划');

    expect(
      engine
          .productionDependencyState(projectId, storyboardTableStateKey,
              scriptId: scriptA)
          .stale,
      isTrue,
    );
    expect(
      engine
          .productionDependencyState(projectId, storyboardTableStateKey,
              scriptId: scriptB)
          .stale,
      isTrue,
    );
    expect(
      engine
          .productionDependencyState(projectId, structuredStoryboardStateKey,
              scriptId: scriptA)
          .stale,
      isTrue,
    );
    expect(
      engine
          .productionDependencyState(projectId, structuredStoryboardStateKey,
              scriptId: scriptB)
          .stale,
      isTrue,
    );
  });

  test('无剧本时不提交导演规划任务', () {
    expect(engine.generateDirectorPlan(projectId), 0);
    expect(db.select('SELECT id FROM o_tasks'), isEmpty);
  });

  test('导演规划生成记录来源并写入项目 Markdown', () async {
    engine.addScript(projectId: projectId, name: '第一集', content: '林朝雪雪夜拔剑');
    gateway.textHandler = (system, user, stage) {
      expect(stage, 'director_plan');
      expect(system, 'BASE PLAN\n\nVISUAL PLAN\n\nDIRECTOR PLAN');
      expect(user, contains('第一集'));
      expect(user, contains('林朝雪雪夜拔剑'));
      return '<think>分析</think># 导演规划\n\n## 节奏\n快切推进';
    };
    engine.installScriptPlanPipeline();
    engine.queue.start();

    final taskId = engine.generateDirectorPlan(projectId);
    await _waitTask(db, taskId);

    expect(engine.scriptPlan(projectId), '# 导演规划\n\n## 节奏\n快切推进');
    final related = Map<String, dynamic>.from(jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [taskId]).single['relatedObjects'] as String) as Map);
    expect(related['scriptsHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(related['promptSources'], isNotEmpty);
    expect(related['promptRequests'], hasLength(1));
    expect(jsonEncode(related), isNot(contains('林朝雪雪夜拔剑')));
  });

  test('手册缺失时在模型调用前失败', () async {
    engine.addScript(projectId: projectId, name: '第一集', content: '初稿');
    engine.installScriptPlanPipeline();

    engine.deleteVisualManual('ink_pack');
    engine.queue.start();
    final missingManualTask = engine.generateDirectorPlan(projectId);
    await _waitTask(db, missingManualTask, expected: 'failed');
    expect(gateway.textCalls, 0);
  });

  test('排队后剧本变化时在模型调用前失败', () async {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '初稿');
    engine.installScriptPlanPipeline();

    final staleTask = engine.generateDirectorPlan(projectId);
    engine.updateScript(scriptId, content: '修订稿');
    engine.queue.start();
    await _waitTask(db, staleTask, expected: 'failed');
    expect(gateway.textCalls, 0);
    final reason = db.select('SELECT reason FROM o_tasks WHERE id=?',
        [staleTask]).single['reason'] as String;
    expect(EngineException.fromReasonJson(reason)?.errKey, errPromptMissing);
  });
}

Future<void> _waitTask(Database db, int taskId,
    {String expected = 'success'}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    final state = db.select(
            'SELECT state FROM o_tasks WHERE id=?', [taskId]).single['state']
        as String;
    if (state == 'success' || state == 'failed') {
      expect(state, expected);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('task $taskId timed out');
}
