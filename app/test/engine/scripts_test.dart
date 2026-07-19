import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/production_dependencies.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _ToolGateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-scripts-');
    db = openEngineDb(':memory:');
    gateway = _ToolGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('scriptAssetExtraction','scriptAssetExtraction','提取系统词',NULL),"
      "('scriptGen','script_gen_system','剧本生成系统词',NULL)",
    );
    engine.installScriptPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: '剧本测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> waitTask(int taskId, {String expectState = 'success'}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final state = db.select(
              'SELECT state FROM o_tasks WHERE id=?', [taskId]).first['state']
          as String;
      if (state == 'success' || state == 'failed') {
        expect(state, expectState);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('任务 $taskId 超时未完成');
  }

  test('剧本 CRUD 与关联资产读取', () {
    db.execute(
        "INSERT INTO o_assets (name,type,projectId) VALUES ('林逸','role',?)",
        [projectId]);
    final assetId = db.lastInsertRowId;
    final id = engine.addScript(
      projectId: projectId,
      name: '第一集',
      content: '内容',
      assets: [assetId],
    );
    var rows = engine.scripts(projectId);
    expect(rows.single.relatedAssets.single.name, '林逸');

    engine.updateScript(id, name: '改名', assets: []);
    rows = engine.scripts(projectId, search: '改');
    expect(rows.single.name, '改名');
    expect(rows.single.relatedAssets, isEmpty);

    engine.batchAddScripts(projectId, [
      (scriptName: '第二集', scriptData: 'B'),
      (scriptName: '第三集', scriptData: 'C'),
    ]);
    expect(engine.scripts(projectId), hasLength(3));

    engine.deleteScripts([id]);
    expect(engine.scripts(projectId), hasLength(2));
  });

  test('删除剧本会清理其分镜的图片编辑流程', () {
    final scriptId =
        engine.addScript(projectId: projectId, name: '待删除', content: 'x');
    db.execute(
      'INSERT INTO o_storyboard (projectId,scriptId,"index",prompt) '
      'VALUES (?,?,?,?)',
      [projectId, scriptId, 1, '镜头'],
    );
    final storyboardId = db.lastInsertRowId;
    db.execute("INSERT INTO o_imageFlow (flowData) VALUES ('{}')");
    final flowId = db.lastInsertRowId;
    db.execute(
        'UPDATE o_storyboard SET flowId=? WHERE id=?', [flowId, storyboardId]);

    engine.deleteScripts([scriptId]);

    expect(
        db.select('SELECT id FROM o_imageFlow WHERE id=?', [flowId]), isEmpty,
        reason: '剧本级联删除分镜时必须同步删除图片编辑流程');
  });

  test('更新剧本名称或内容会使本集下游过期', () {
    final scriptA =
        engine.addScript(projectId: projectId, name: '第一集', content: '旧内容');
    final scriptB =
        engine.addScript(projectId: projectId, name: '第二集', content: '第二集');
    engine.saveStoryboardTable(projectId, scriptA, 'A 表');
    engine.saveStoryboardTable(projectId, scriptB, 'B 表');
    for (final scriptId in [scriptA, scriptB]) {
      engine.setProductionDependencyState(
        projectId: projectId,
        scriptId: scriptId,
        key: storyboardTableStateKey,
        sourceHash: 'table-$scriptId',
        stale: false,
      );
      engine.setProductionDependencyState(
        projectId: projectId,
        scriptId: scriptId,
        key: structuredStoryboardStateKey,
        sourceHash: 'shots-$scriptId',
        stale: false,
      );
    }

    engine.updateScript(scriptA, name: '第一集（修订）');

    expect(
      engine
          .productionDependencyState(projectId, storyboardTableStateKey,
              scriptId: scriptA)
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
          .productionDependencyState(projectId, storyboardTableStateKey,
              scriptId: scriptB)
          .stale,
      isFalse,
    );
  });

  test('新增、修改或删除剧本会使导演规划过期', () {
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: '旧内容');
    engine.saveScriptPlan(projectId, '规划 v1');

    engine.updateScript(scriptId, content: '新内容');
    expect(
      engine.productionDependencyState(projectId, directorPlanStateKey).stale,
      isTrue,
    );

    engine.saveScriptPlan(projectId, '规划 v2');
    final second =
        engine.addScript(projectId: projectId, name: '第二集', content: '续集');
    expect(
      engine.productionDependencyState(projectId, directorPlanStateKey).stale,
      isTrue,
    );

    engine.saveScriptPlan(projectId, '规划 v3');
    engine.deleteScripts([second]);
    expect(
      engine.productionDependencyState(projectId, directorPlanStateKey).stale,
      isTrue,
    );
  });

  test('提取资产：tool JSON 落库、已有资产去重、组内链接重建', () async {
    db.execute(
        "INSERT INTO o_assets (name,type,projectId) VALUES ('林逸','role',?)",
        [projectId]);
    final s1 = engine.addScript(projectId: projectId, name: '一', content: 'A');
    final s2 = engine.addScript(projectId: projectId, name: '二', content: 'B');
    for (final scriptId in [s1, s2]) {
      engine.setProductionDependencyState(
        projectId: projectId,
        scriptId: scriptId,
        key: storyboardTableStateKey,
        sourceHash: 'table-$scriptId',
        stale: false,
      );
    }

    gateway.result = (user) {
      expect(user, contains('===== 【剧本ID: $s1】一 ====='));
      expect(user, contains('当前已有资产列表：林逸'));
      return {
        'newAssets': [
          {
            'name': '林逸', // 与已有重名 → 不新增
            'desc': 'x',
            'type': 'role',
            'scriptIds': [s1],
          },
          {
            'name': '寒山剑',
            'desc': '古剑',
            'prompt': 'ancient sword',
            'type': 'tool',
            'scriptIds': [s1, s2],
          },
        ],
        'existingAssetRefs': [
          {
            'name': '林逸',
            'scriptIds': [s2],
          },
        ],
      };
    };

    final taskId = engine.extractAssets([s1, s2], projectId);
    expect(
      engine.scripts(projectId).map((s) => s.extractState),
      everyElement(anyOf(0, 2)),
      reason: '入队后为待提取/提取中',
    );
    await waitTask(taskId);

    final assets = db.select(
        'SELECT name,type FROM o_assets WHERE projectId=? ORDER BY id',
        [projectId]);
    expect(assets, hasLength(2), reason: '重名不重复插入');
    expect(assets.last['name'], '寒山剑');

    final rows = engine.scripts(projectId);
    expect(rows.map((s) => s.extractState), everyElement(1));
    expect(rows.first.relatedAssets.map((a) => a.name).toSet(), {'林逸', '寒山剑'});
    expect(rows.last.relatedAssets.map((a) => a.name).toSet(), {'林逸', '寒山剑'});
    expect(
      engine
          .productionDependencyState(projectId, storyboardTableStateKey,
              scriptId: s1)
          .stale,
      isTrue,
    );
    expect(
      engine
          .productionDependencyState(projectId, storyboardTableStateKey,
              scriptId: s2)
          .stale,
      isTrue,
    );
  });

  test('提取失败：extractState=-1 且 errorReason 为错误码 JSON', () async {
    final s1 = engine.addScript(projectId: projectId, name: '一', content: 'A');
    gateway.result = (_) => throw const EngineException(errLlmFormat);
    final taskId = engine.extractAssets([s1], projectId);
    await waitTask(taskId, expectState: 'failed');
    final row = engine.scripts(projectId).single;
    expect(row.extractState, -1);
    expect(
      EngineException.fromReasonJson(row.errorReason)?.errKey,
      errLlmFormat,
    );
  });

  test('冷启动恢复：滞留 0/2 状态置 -1 errAppRestart', () {
    final s1 = engine.addScript(projectId: projectId, name: '一', content: 'A');
    engine.extractAssets([s1], projectId);
    db.execute("UPDATE o_tasks SET state='processing'");
    engine.queue.recoverOnColdStart();
    final row = engine.scripts(projectId).single;
    expect(row.extractState, -1);
    expect(
      EngineException.fromReasonJson(row.errorReason)?.errKey,
      errAppRestart,
    );
  });

  test('导出 zip 可解出同名 txt（重名去重）', () {
    engine.addScript(projectId: projectId, name: '一', content: '甲');
    engine.addScript(projectId: projectId, name: '一', content: '乙');
    final ids = engine.scripts(projectId).map((s) => s.id).toList();
    final bytes = engine.exportScripts(ids);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.files.map((f) => f.name).toSet(), {'一.txt', '一(1).txt'});
    expect(
      utf8.decode(archive.files.first.content as List<int>),
      '甲',
    );
  });

  test('aiEpisodeRegex 剥离围栏返回正则', () async {
    gateway.text = '```\n/第(\\d+)集\\s*(.*)/g\n```';
    final regex = await engine.aiEpisodeRegex('第1集 开端\n正文' * 300);
    expect(regex, r'/第(\d+)集\s*(.*)/g');
  });

  test('从事件批量生成剧本：script_gen 任务落库多集剧本', () async {
    db.execute(
      "INSERT INTO o_novel (projectId,chapterIndex,reel,chapter,chapterData,eventState,event) "
      "VALUES (?,1,'正文卷','雪夜','山门雪夜',1,'事件一'),"
      "(?,2,'正文卷','焦玉','玉佩坠地',1,'事件二')",
      [projectId, projectId],
    );
    final novel1 =
        db.select('SELECT id FROM o_novel ORDER BY id').first['id'] as int;
    final novel2 =
        db.select('SELECT id FROM o_novel ORDER BY id').last['id'] as int;
    db.execute(
      "INSERT INTO o_event (name,detail,createTime) VALUES "
      "('雪夜破门','| 第1章 雪夜 | 林朝雪 | 黑衣人破门 | 强 | 高 | 50秒 | 冲突 |',1),"
      "('焦玉示警','| 第2章 焦玉 | 林朝雪 | 焦黑玉佩示警 | 强 | 高 | 45秒 | 悬疑 |',2)",
    );
    final event1 =
        db.select('SELECT id FROM o_event ORDER BY id').first['id'] as int;
    final event2 =
        db.select('SELECT id FROM o_event ORDER BY id').last['id'] as int;
    db.execute(
      'INSERT INTO o_eventChapter (eventId,novelId) VALUES (?,?),(?,?)',
      [event1, novel1, event2, novel2],
    );

    gateway.textResult = (system, user, stage) {
      expect(system, '剧本生成系统词');
      expect(stage, 'script_gen');
      expect(user, contains('雪夜破门'));
      expect(user, contains('焦黑玉佩示警'));
      return '<think>规划</think>{"episodes":[{"title":"雪夜破门","synopsis":"黑衣人破门","scenes":[{"location":"山门","timeOfDay":"夜","action":"黑衣人撞开山门","dialogues":[{"speaker":"林朝雪","line":"谁敢闯山门？"}]}]},{"title":"焦玉示警","synopsis":"玉佩示警","scenes":[{"location":"祠堂","timeOfDay":"夜","action":"焦黑玉佩亮起红光","dialogues":[]}]}]}';
    };

    final taskId =
        engine.generateScriptsFromEvents(projectId, [event1, event2]);
    await waitTask(taskId);

    final scripts = engine.scripts(projectId);
    expect(scripts.map((s) => s.name), ['雪夜破门', '焦玉示警']);
    expect(scripts.first.content, contains('黑衣人撞开山门'));
    expect(scripts.first.content, contains('林朝雪：谁敢闯山门？'));
    expect(scripts.last.content, contains('焦黑玉佩亮起红光'));
  });
}

class _ToolGateway implements ProviderGateway {
  Map<String, dynamic> Function(String user)? result;
  String text = '';
  String Function(String system, String user, String stage)? textResult;

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
      {required String stage,
      required String toolName,
      required Map<String, dynamic> schema,
      CancelToken? cancelToken}) async {
    expect(stage, 'asset_extract');
    expect(toolName, 'resultTool');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return result!(user);
  }

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    final fn = textResult;
    if (fn != null) return TextResult(fn(system, user, stage));
    return TextResult(text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
