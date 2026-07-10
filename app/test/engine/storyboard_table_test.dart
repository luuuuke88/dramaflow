import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
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
  late int scriptA;
  late int scriptB;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-sbtable-');
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
      data: const {'director_storyboard_table_style': 'TABLE VISUAL'},
    );
    engine.saveDirectorManual(
      name: 'Pace',
      pack: 'pace_pack',
      data: const {'director_storyboard_table_narrative': 'TABLE DIRECTOR'},
    );
    db.execute(
      'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
      ['storyboard_table', 'storyboard_table', 'BASE TABLE'],
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '分镜表测试',
      artStyle: 'ink_pack',
      directorManual: 'pace_pack',
    );
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '白衣少女剑客',
    );
    scriptA = engine.addScript(
      projectId: projectId,
      name: '第一集',
      content: '# 第一集\n林朝雪雪夜拔剑',
      assets: [assetId],
    );
    scriptB = engine.addScript(projectId: projectId, name: '第二集', content: 'b');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('未写入时返回空串', () {
    expect(engine.storyboardTable(projectId, scriptA), '');
  });

  test('保存/回读/更新（剧集级 upsert）', () {
    engine.saveStoryboardTable(projectId, scriptA, '# 分镜\nS01 开场');
    expect(engine.storyboardTable(projectId, scriptA), '# 分镜\nS01 开场');

    // 更新同一剧集（应为 update 而非新增行）。
    engine.saveStoryboardTable(projectId, scriptA, '# 分镜\nS01 改写');
    expect(engine.storyboardTable(projectId, scriptA), '# 分镜\nS01 改写');
    final rows = engine.db.select(
      "SELECT COUNT(*) n FROM o_agentWorkData WHERE key='storyboardTable' AND episodesId=?",
      [scriptA],
    );
    expect(rows.first['n'], 1, reason: '同剧集重复保存应 upsert，不新增行');
  });

  test('不同剧集互不干扰', () {
    engine.saveStoryboardTable(projectId, scriptA, 'A 表');
    engine.saveStoryboardTable(projectId, scriptB, 'B 表');
    expect(engine.storyboardTable(projectId, scriptA), 'A 表');
    expect(engine.storyboardTable(projectId, scriptB), 'B 表');
  });

  test('保存分镜表仅使同剧集结构分镜过期', () {
    engine.setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptA,
      key: structuredStoryboardStateKey,
      sourceHash: 'old-a',
      stale: false,
    );
    engine.setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptB,
      key: structuredStoryboardStateKey,
      sourceHash: 'old-b',
      stale: false,
    );

    engine.saveStoryboardTable(projectId, scriptA, 'A 表');

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
      isFalse,
    );
  });

  test('无导演规划时不提交分镜表任务', () {
    expect(engine.generateStoryboardTable(projectId, scriptA), 0);
    expect(db.select('SELECT id FROM o_tasks'), isEmpty);
  });

  test('分镜表生成记录来源并写入剧集 Markdown', () async {
    engine.saveScriptPlan(projectId, '# 导演规划\n强调快节奏推进');
    const table = '''| 镜头 | 画面提示词 | 画面描述 | 时长 | 分轨 | 资产 | 生成首帧 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 雪夜山门 | 缓慢推进 | 5 | 主线 | 林朝雪 | 是 |''';
    gateway.textHandler = (system, user, stage) {
      expect(stage, 'storyboard_table');
      expect(system, 'BASE TABLE\n\nTABLE VISUAL\n\nTABLE DIRECTOR');
      expect(user, contains('# 导演规划'));
      expect(user, contains('# 第一集'));
      expect(user, contains('林朝雪（role）'));
      return table;
    };
    engine.installStoryboardTablePipeline();
    engine.queue.start();

    final taskId = engine.generateStoryboardTable(projectId, scriptA);
    await _waitTask(db, taskId);

    expect(engine.storyboardTable(projectId, scriptA), table);
    expect(
      engine
          .productionDependencyState(projectId, structuredStoryboardStateKey,
              scriptId: scriptA)
          .stale,
      isTrue,
    );
    final related = Map<String, dynamic>.from(jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [taskId]).single['relatedObjects'] as String) as Map);
    expect(related['scriptHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(related['planHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(related['assetsHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(related['promptSources'], isNotEmpty);
    expect(related['promptRequests'], hasLength(1));
    expect(jsonEncode(related), isNot(contains('林朝雪雪夜拔剑')));
    expect(jsonEncode(related), isNot(contains('强调快节奏推进')));
  });

  test('分镜表手册缺失时在模型调用前失败', () async {
    engine.saveScriptPlan(projectId, '# 导演规划');
    engine.installStoryboardTablePipeline();
    engine.deleteDirectorManual('pace_pack');
    engine.queue.start();

    final taskId = engine.generateStoryboardTable(projectId, scriptA);
    await _waitTask(db, taskId, expected: 'failed');
    expect(gateway.textCalls, 0);
  });

  test('排队后导演规划、剧本或资产变化时在模型调用前失败', () async {
    engine.saveScriptPlan(projectId, '# 初始导演规划');
    engine.installStoryboardTablePipeline();

    final taskForPlan = engine.generateStoryboardTable(projectId, scriptA);
    engine.saveScriptPlan(projectId, '# 改后导演规划');
    final taskForScript = engine.generateStoryboardTable(projectId, scriptA);
    engine.updateScript(scriptA, content: '改后剧本');
    final taskForAssets = engine.generateStoryboardTable(projectId, scriptA);
    final nextAsset = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '雪夜山门',
    );
    engine.updateScript(scriptA, assets: [nextAsset]);
    engine.queue.start();

    for (final taskId in [taskForPlan, taskForScript, taskForAssets]) {
      await _waitTask(db, taskId, expected: 'failed');
    }
    expect(gateway.textCalls, 0);
    final reasons = db
        .select('SELECT reason FROM o_tasks ORDER BY id')
        .map((row) => EngineException.fromReasonJson(row['reason'] as String))
        .toList();
    expect(reasons, everyElement(isA<EngineException>()));
    expect(reasons.map((reason) => reason!.errKey),
        everyElement(errPromptMissing));
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
