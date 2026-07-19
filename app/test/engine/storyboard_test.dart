import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/production_dependencies.dart';
import 'package:dramaflow/src/engine/prompt_resolver.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-storyboard-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('storyboard_gen','storyboard_gen','分镜系统提示词',NULL),"
      "('director_plan','director_plan','导演规划系统词',NULL),"
      "('storyboard_table','storyboard_table','分镜表系统词',NULL)",
    );
    engine.installStoryboardPipeline();
    engine.installScriptPlanPipeline();
    engine.installStoryboardTablePipeline();
    engine.queue.start();
    engine.saveVisualManual(
      name: '分镜视觉',
      pack: 'storyboard_pack',
      data: const {
        'director_storyboard': '分镜视觉手册',
        'director_planning_style': '导演规划视觉手册',
        'director_storyboard_table_style': '分镜表视觉手册',
      },
    );
    engine.saveDirectorManual(
      name: '导演叙事',
      pack: 'director_pack',
      data: const {
        'director_planning_narrative': '导演规划叙事手册',
        'director_storyboard_table_narrative': '分镜表叙事手册',
      },
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '分镜测试',
      videoRatio: '16:9',
      artStyle: 'storyboard_pack',
      directorManual: 'director_pack',
    );
    scriptId = engine.addScript(
        projectId: projectId, name: '第一集', content: '林朝雪拔剑，白衣如雪。');
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
        final reason = db.select(
            'SELECT reason FROM o_tasks WHERE id=?', [taskId]).first['reason'];
        expect(state, expectState, reason: reason?.toString());
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('任务超时');
  }

  const validTable = '''
# 第一集分镜表

| 镜头 | 画面提示词 | 画面描述 | 时长 | 分轨 | 资产 | 生成首帧 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 雪夜山门\\|剑光 | 慢镜推近 | 3 | 主线 | 林朝雪，山门, 青霜剑 | 是 |
| 2 | 近景剑锋 | 横向跟拍 | 2 | 副线 | 林朝雪 | 否 |
''';

  test('exportStoryboardImagesToFile 仅打包已选且存在的本地首帧', () async {
    final first = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '首张图',
    );
    final missing = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '缺失图',
    );
    final ignored = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '未选图',
    );
    const firstRel = 'images/first.png';
    const missingRel = 'images/missing.jpg';
    const ignoredRel = 'images/ignored.webp';
    File(engine.mediaAbsPath(firstRel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    File(engine.mediaAbsPath(ignoredRel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 8, 7]);
    engine.setStoryboardImage(first, firstRel);
    engine.setStoryboardImage(missing, missingRel);
    engine.setStoryboardImage(ignored, ignoredRel);

    final target = p.join(dir.path, 'first-frames.zip');
    expect(
        engine.storyboardImageExportFileCount(scriptId, {first, missing}), 1);
    final count = await engine.exportStoryboardImagesToFile(
      scriptId,
      {first, missing},
      target,
    );

    expect(count, 1);
    final archive = ZipDecoder().decodeBytes(File(target).readAsBytesSync());
    expect(archive.files, hasLength(1));
    expect(archive.files.single.name, '分镜$first.png');
    expect(archive.files.single.content, [1, 2, 3]);

    final emptyTarget = p.join(dir.path, 'empty.zip');
    final empty = await engine.exportStoryboardImagesToFile(
      scriptId,
      const {},
      emptyTarget,
    );
    expect(empty, 0);
    expect(File(emptyTarget).existsSync(), isFalse);
  });

  test('首帧导出拒绝越出媒体根目录和符号链接的路径', () async {
    final outside = File(p.join(dir.path, 'outside', 'secret.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 9, 9]);
    final traversal = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '越界路径',
    );
    final absolute = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '绝对路径',
    );
    final linked = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '符号链接',
    );
    engine.setStoryboardImage(traversal, '../../outside/secret.png');
    engine.setStoryboardImage(absolute, outside.path);
    final link = Link(engine.mediaAbsPath('shots/outside.png'))
      ..parent.createSync(recursive: true)
      ..createSync(outside.path);
    addTearDown(() {
      if (link.existsSync()) link.deleteSync();
    });
    engine.setStoryboardImage(linked, 'shots/outside.png');

    final selected = {traversal, absolute, linked};
    expect(engine.storyboardImageExportFileCount(scriptId, selected), 0);
    final target = p.join(dir.path, 'unsafe.zip');
    final count =
        await engine.exportStoryboardImagesToFile(scriptId, selected, target);
    expect(count, 0);
    expect(File(target).existsSync(), isFalse);
  });

  void seedDocuments({String table = validTable, String plan = '导演规划 A'}) {
    engine.saveScriptPlan(projectId, plan);
    engine.saveStoryboardTable(projectId, scriptId, table);
  }

  int addLinkedAsset(String name, String type, {String describe = ''}) {
    db.execute(
      'INSERT INTO o_assets (name,type,projectId,describe) VALUES (?,?,?,?)',
      [name, type, projectId, describe],
    );
    final id = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
      [scriptId, id],
    );
    return id;
  }

  test('CRUD：新增/插入排序/编辑/批量删除后重排', () {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头1');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头2');
    var rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.index), [1, 2]);
    expect(rows.map((r) => r.state), [sbNotGenerated, sbNotGenerated]);

    final inserted = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '插入镜头',
      insertAfterIndex: 1,
    );
    rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.id), [s1, inserted, s2]);
    expect(rows.map((r) => r.index), [1, 2, 3]);

    engine.editStoryboard(s1, prompt: '改后镜头1', videoDesc: '推镜');
    expect(engine.storyboards(scriptId).first.prompt, '改后镜头1');

    engine.deleteStoryboards([inserted]);
    rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.id), [s1, s2]);
    expect(rows.map((r) => r.index), [1, 2], reason: '删除后重排剩余序号');
  });

  test('单条删除分镜会清理图片流和已空视频轨', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '待删除镜头',
    );
    db.execute("INSERT INTO o_imageFlow (flowData) VALUES ('{}')");
    final flowId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,?)',
      [projectId, scriptId, '未生成'],
    );
    final trackId = db.lastInsertRowId;
    db.execute(
      'UPDATE o_storyboard SET flowId=?,trackId=? WHERE id=?',
      [flowId, trackId, storyboardId],
    );

    engine.deleteStoryboards([storyboardId]);

    expect(
        db.select('SELECT id FROM o_imageFlow WHERE id=?', [flowId]), isEmpty,
        reason: 'ToonFlow removeFrame 会随分镜删除图片编辑流程');
    expect(
        db.select('SELECT id FROM o_videoTrack WHERE id=?', [trackId]), isEmpty,
        reason: 'ToonFlow removeFrame 会删除只属于该镜头的空轨');
  });

  test('前插语义：insertAfterIndex=目标index-1 使新镜头排到目标之前', () {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头1');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头2');
    var rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.index), [1, 2]);

    // 在第一格（index=1）之前插入 → insertAfterIndex = 1-1 = 0。
    final beforeFirst = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '前插首格',
      insertAfterIndex: rows.first.index - 1,
    );
    rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.id), [beforeFirst, s1, s2], reason: '前插首格应排在最前');
    expect(rows.map((r) => r.index), [1, 2, 3]);

    // 在原第二格（现 index=3 的 s2）之前插入。
    final s2Row = rows.firstWhere((r) => r.id == s2);
    final beforeS2 = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '前插 s2',
      insertAfterIndex: s2Row.index - 1,
    );
    rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.id), [beforeFirst, s1, beforeS2, s2]);
    expect(rows.map((r) => r.index), [1, 2, 3, 4]);
  });

  test('重排分镜：按新 id 顺序重写连续 index 并驱动后续合成顺序', () {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头1');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头2');
    final s3 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头3');

    engine.reorderStoryboards(scriptId, [s3, s1, s2]);

    final rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.id), [s3, s1, s2]);
    expect(rows.map((r) => r.index), [1, 2, 3]);
  });

  test('重排分镜：缺少或混入其他 id 时拒绝写入，保留原顺序', () {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头1');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头2');

    expect(
      () => engine.reorderStoryboards(scriptId, [s2, 999]),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errPromptMissing)),
    );

    final rows = engine.storyboards(scriptId);
    expect(rows.map((r) => r.id), [s1, s2]);
    expect(rows.map((r) => r.index), [1, 2]);
  });

  test('严格解析分镜表：中英表头、转义竖线、资产和布尔值', () {
    final shots = engine.parseStoryboardTable(validTable);
    expect(shots, hasLength(2));
    expect(shots.first.prompt, '雪夜山门|剑光');
    expect(shots.first.assetNames, ['林朝雪', '山门', '青霜剑']);
    expect(shots.first.shouldGenerateImage, isTrue);
    expect(shots.last.shouldGenerateImage, isFalse);

    final english = engine.parseStoryboardTable('''
notes
| prompt | videoDesc | duration | track | assetNames | shouldGenerateImage |
| --- | --- | --- | --- | --- | --- |
| close shot | dolly in | 4 | main | Alice, Gate | true |
''');
    expect(english.single.duration, '4');
    expect(english.single.track, 'main');
    expect(english.single.assetNames, ['Alice', 'Gate']);
    expect(english.single.shouldGenerateImage, isTrue);
  });

  test('严格解析分镜表：缺必填列或空提示词拒绝', () {
    for (final markdown in [
      '| 镜头 | 时长 |\n| --- | --- |\n| 1 | 5 |',
      '| 画面提示词 | 画面描述 | 时长 |\n| --- | --- | --- |\n| | 推近 | 5 |',
    ]) {
      expect(
        () => engine.parseStoryboardTable(markdown),
        throwsA(isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errLlmFormat)
            .having((e) => e.errParams['reason'], 'reason',
                startsWith('storyboard_table:'))),
      );
    }
  });

  test('宽松解析生成首帧列：常见自然语言变体与无法识别时降级为需要生成', () {
    final looseTrue = engine.parseStoryboardTable('''
| 画面提示词 | 画面描述 | 时长 | 生成首帧 |
| --- | --- | --- | --- |
| 提示A | 描述A | 3 | 需要 |
| 提示B | 描述B | 3 | ✓ |
| 提示C | 描述C | 3 | yes |
| 提示D | 描述D | 3 | Y |
''');
    expect(
        looseTrue.map((s) => s.shouldGenerateImage), [true, true, true, true]);

    final looseFalse = engine.parseStoryboardTable('''
| 画面提示词 | 画面描述 | 时长 | 生成首帧 |
| --- | --- | --- | --- |
| 提示A | 描述A | 3 | 不需要 |
| 提示B | 描述B | 3 | ✗ |
| 提示C | 描述C | 3 | no |
| 提示D | 描述D | 3 | N |
''');
    expect(looseFalse.map((s) => s.shouldGenerateImage),
        [false, false, false, false]);

    // 无法识别的取值不应炸掉整张表——降级为默认需要生成（与该列整体缺失时的默认行为一致）。
    final unrecognized = engine.parseStoryboardTable('''
| 画面提示词 | 画面描述 | 时长 | 生成首帧 |
| --- | --- | --- | --- |
| 提示A | 描述A | 3 | 待定 |
''');
    expect(unrecognized.single.shouldGenerateImage, isTrue);

    // 空单元格是“否”：与无法识别取值的默认 true 是刻意的不对称，锁住这条边界。
    final emptyCell = engine.parseStoryboardTable('''
| 画面提示词 | 画面描述 | 时长 | 生成首帧 |
| --- | --- | --- | --- |
| 提示A | 描述A | 3 |  |
''');
    expect(emptyCell.single.shouldGenerateImage, isFalse,
        reason: '生成首帧列留空表示不生成，不应落入无法识别的默认 true 分支');

    // 记录当前行为：全角拉丁与零宽字符污染的取值不会被识别为否，
    // 会走默认 true 分支（trim 不剥 U+200B、全角Ｎ小写后仍是全角ｎ）。
    // 若未来改为归一化/子串匹配，这两条断言应当有意识地翻转。
    final corrupted = engine.parseStoryboardTable('''
| 画面提示词 | 画面描述 | 时长 | 生成首帧 |
| --- | --- | --- | --- |
| 提示A | 描述A | 3 | Ｎ |
| 提示B | 描述B | 3 | 否​ |
''');
    expect(corrupted.map((s) => s.shouldGenerateImage), [true, true],
        reason: '现状：全角/零宽污染的否定取值落入默认 true 分支（已知限制，见 storyboard.dart 注释）');
  });

  test('无规划/分镜表不入队，已有分镜且不替换也不入队', () {
    expect(engine.generateStoryboards(projectId, scriptId), 0);
    engine.saveScriptPlan(projectId, '导演规划 A');
    expect(engine.generateStoryboards(projectId, scriptId), 0);
    engine.saveStoryboardTable(projectId, scriptId, validTable);
    engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '旧镜头');
    expect(engine.generateStoryboards(projectId, scriptId), 0);
  });

  test('分镜表驱动生成：表内元数据权威、仅关联资产、追溯不泄漏原文', () async {
    final roleId = addLinkedAsset('林朝雪', 'role', describe: '白衣剑客');
    final sceneId = addLinkedAsset('山门', 'scene', describe: '雪夜宗门');
    db.execute(
      "INSERT INTO o_assets (name,type,projectId) VALUES ('青霜剑','tool',?)",
      [projectId],
    );
    seedDocuments();
    gateway.toolResult = (_) => {
          'shots': [
            {
              'prompt': '模型润色镜头一',
              'videoDesc': '模型运镜一',
              'duration': '999',
              'track': '错误分轨',
              'assetNames': ['青霜剑'],
            },
            {'prompt': '模型润色镜头二', 'videoDesc': '模型运镜二'},
          ],
        };

    final taskId = engine.generateStoryboards(projectId, scriptId);
    await waitTask(taskId);

    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(2));
    expect(rows.first.prompt, '模型润色镜头一');
    expect(rows.first.videoDesc, '模型运镜一');
    expect(rows.first.duration, '3');
    expect(rows.first.track, '主线');
    expect(rows.first.assetIds, unorderedEquals([roleId, sceneId]));
    expect(rows.first.shouldGenerateImage, 1);
    expect(rows.last.duration, '2');
    expect(rows.last.track, '副线');
    expect(rows.last.shouldGenerateImage, 0);
    expect(gateway.seenSystem, '分镜系统提示词\n\n分镜视觉手册');
    expect(gateway.seenUser!.indexOf('导演规划：'),
        lessThan(gateway.seenUser!.indexOf('分镜表：')));
    expect(gateway.seenUser!.indexOf('分镜表：'),
        lessThan(gateway.seenUser!.indexOf('当前剧本：')));
    expect(gateway.seenUser!.indexOf('当前剧本：'),
        lessThan(gateway.seenUser!.indexOf('候选资产：')));

    final relatedRaw = db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [taskId]).single['relatedObjects'] as String;
    final related = jsonDecode(relatedRaw) as Map<String, dynamic>;
    expect(related.keys,
        containsAll(['scriptHash', 'planHash', 'tableHash', 'assetsHash']));
    expect(relatedRaw, isNot(contains('导演规划 A')));
    expect(relatedRaw, isNot(contains('雪夜山门')));
    expect(relatedRaw, isNot(contains('林朝雪拔剑')));
    final request = (related['promptRequests'] as List).single as Map;
    expect(
        (request['sources'] as List).map((source) => (source as Map)['id']), [
      'base:storyboard_gen',
      'visual:storyboard_pack:director_storyboard',
      'data:directorPlan:$projectId',
      'data:storyboardTable:$scriptId',
      'data:script:$scriptId',
      'data:scriptAssets:$scriptId',
    ]);
    final state = engine.productionDependencyState(
      projectId,
      structuredStoryboardStateKey,
      scriptId: scriptId,
    );
    expect(state.stale, isFalse);
    expect(state.sourceHash, promptContentHash(validTable));
  });

  test('C4 fake provider 全链：剧本到规划、分镜表和结构分镜', () async {
    const apiKey = 'sk-c4-task-json-must-not-leak';
    const scriptSource = '林朝雪拔剑，白衣如雪。';
    const planSource = '# 导演规划\n雪夜开场，三秒建立危机。';
    const tableSource = '''
| 画面提示词 | 画面描述 | 时长 | 分轨 | 资产 | 生成首帧 |
| --- | --- | --- | --- | --- | --- |
| 雪夜山门，林朝雪拔剑 | 慢镜推近 | 3 | 主线 | 林朝雪 | 是 |
''';
    const assetSource = '林朝雪（role）：白衣剑客';
    await engine.credentials.write(providerCredentialRef('azt'), apiKey);
    final assetId = addLinkedAsset('林朝雪', 'role', describe: '白衣剑客');
    gateway.textResult = (system, user, stage) => switch (stage) {
          'director_plan' => planSource,
          'storyboard_table' => tableSource,
          _ => throw StateError('unexpected text stage: $stage'),
        };
    gateway.toolResult = (_) => {
          'shots': [
            {'prompt': '雪夜山门拔剑，冷蓝逆光', 'videoDesc': '慢镜推近'},
          ],
        };

    final planTask = engine.generateDirectorPlan(projectId);
    await waitTask(planTask);
    final tableTask = engine.generateStoryboardTable(projectId, scriptId);
    await waitTask(tableTask);
    final shotsTask = engine.generateStoryboards(
      projectId,
      scriptId,
      replaceExisting: false,
    );
    await waitTask(shotsTask);

    final plan = engine.scriptPlan(projectId);
    expect(plan, contains('导演规划'));
    final table = engine.storyboardTable(projectId, scriptId);
    expect(table, contains('雪夜山门'));
    final shots = engine.storyboards(scriptId);
    expect(shots.single.prompt, contains('冷蓝逆光'));
    expect(shots.single.assetIds, [assetId]);
    expect(
      engine
          .productionDependencyState(
            projectId,
            structuredStoryboardStateKey,
            scriptId: scriptId,
          )
          .sourceHash,
      promptContentHash(table),
    );

    Map<String, dynamic> taskTrace(int taskId) => Map<String, dynamic>.from(
          jsonDecode(db.select('SELECT relatedObjects FROM o_tasks WHERE id=?',
              [taskId]).single['relatedObjects'] as String) as Map,
        );

    final planTrace = taskTrace(planTask);
    final tableTrace = taskTrace(tableTask);
    final shotsTrace = taskTrace(shotsTask);
    expect(planTrace['scriptsHash'], engine.projectScriptsHash(projectId));
    expect(tableTrace,
        containsPair('scriptHash', promptContentHash(scriptSource)));
    expect(tableTrace, containsPair('planHash', promptContentHash(plan)));
    expect(
        tableTrace,
        containsPair(
            'assetsHash', engine.scriptAssetsHash(projectId, scriptId)));
    expect(shotsTrace,
        containsPair('scriptHash', promptContentHash(scriptSource)));
    expect(shotsTrace, containsPair('planHash', promptContentHash(plan)));
    expect(shotsTrace, containsPair('tableHash', promptContentHash(table)));
    expect(
        shotsTrace,
        containsPair(
            'assetsHash', engine.scriptAssetsHash(projectId, scriptId)));

    for (final trace in [planTrace, tableTrace, shotsTrace]) {
      final raw = jsonEncode(trace);
      for (final sensitive in [
        apiKey,
        scriptSource,
        plan,
        table,
        assetSource,
        '分镜系统提示词',
        '导演规划系统词',
        '分镜表系统词',
        '分镜视觉手册',
        '导演规划视觉手册',
        '分镜表视觉手册',
        '导演规划叙事手册',
        '分镜表叙事手册',
      ]) {
        expect(raw, isNot(contains(sensitive)));
      }
    }
  });

  test('生成结果未验证时保留旧数据，验证通过后原子替换并清理媒体', () async {
    seedDocuments(table: '''
| 画面提示词 | 画面描述 | 时长 | 资产 | 生成首帧 |
| --- | --- | --- | --- | --- |
| 雪夜山门 | 慢镜推近 | 3 | 林朝雪 | 是 |
''');
    final assetId = addLinkedAsset('林朝雪', 'role');
    final oldId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '旧镜头',
      assetIds: [assetId],
    );
    const oldImageRel = 'old/frame.png';
    const oldVideoRel = 'old/video.mp4';
    const protectedVideoRel = 'old/saved-clip.mp4';
    for (final rel in [oldImageRel, oldVideoRel, protectedVideoRel]) {
      final file = File(engine.media.absPath(rel));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([1, 2, 3]);
    }
    db.execute(
        'UPDATE o_storyboard SET filePath=? WHERE id=?', [oldImageRel, oldId]);
    db.execute("INSERT INTO o_imageFlow (flowData) VALUES ('{}')");
    final oldFlowId = db.lastInsertRowId;
    db.execute(
        'UPDATE o_storyboard SET flowId=? WHERE id=?', [oldFlowId, oldId]);
    db.execute(
      'INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,?)',
      [projectId, scriptId, '已完成'],
    );
    final trackId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, oldVideoRel, '已完成'],
    );
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, protectedVideoRel, '已完成'],
    );
    db.execute(
      "INSERT INTO o_image (filePath,type,state) VALUES (?,'clip','已完成')",
      [protectedVideoRel],
    );
    db.execute(
      'INSERT INTO o_timelineClip (projectId,scriptId,filePath,lane,startMs) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, oldVideoRel, 0, 0],
    );

    gateway.toolResult = (_) => {'shots': []};
    final failed = engine.generateStoryboards(
      projectId,
      scriptId,
      replaceExisting: true,
    );
    await waitTask(failed, expectState: 'failed');
    expect(engine.storyboards(scriptId).single.id, oldId);
    expect(db.select('SELECT id FROM o_imageFlow WHERE id=?', [oldFlowId]),
        isNotEmpty,
        reason: '替换验证失败时不能提前删除旧分镜的图片流');
    expect(File(engine.media.absPath(oldImageRel)).existsSync(), isTrue);
    expect(File(engine.media.absPath(oldVideoRel)).existsSync(), isTrue);
    expect(
        db.select('SELECT id FROM o_videoTrack WHERE scriptId=?', [scriptId]),
        isNotEmpty);

    gateway.toolResult = (_) => {
          'shots': [
            {'prompt': '新镜头', 'videoDesc': '新运镜'},
          ],
        };
    final succeeded = engine.generateStoryboards(
      projectId,
      scriptId,
      replaceExisting: true,
    );
    await waitTask(succeeded);
    final rows = engine.storyboards(scriptId);
    expect(rows.single.prompt, '新镜头');
    expect(rows.single.id, isNot(oldId));
    expect(rows.single.assetIds, [assetId]);
    expect(File(engine.media.absPath(oldImageRel)).existsSync(), isFalse);
    expect(File(engine.media.absPath(oldVideoRel)).existsSync(), isFalse);
    expect(File(engine.media.absPath(protectedVideoRel)).existsSync(), isTrue,
        reason: '已登记为可复用素材的候选视频不能删文件');
    expect(
        db.select('SELECT id FROM o_videoTrack WHERE scriptId=?', [scriptId]),
        isEmpty);
    expect(db.select('SELECT id FROM o_video WHERE scriptId=?', [scriptId]),
        isEmpty);
    expect(db.select('SELECT id FROM o_imageFlow WHERE id=?', [oldFlowId]),
        isEmpty,
        reason: '原子替换成功后不能遗留旧分镜的图片流');
    expect(
        db.select('SELECT id FROM o_timelineClip WHERE scriptId=?', [scriptId]),
        isEmpty);
  });

  test('事务内新分镜插入失败时完整回滚旧输出且不删文件', () async {
    seedDocuments(table: '''
| 画面提示词 | 画面描述 | 时长 | 资产 |
| --- | --- | --- | --- |
| 雪夜山门 | 慢镜推近 | 3 | 林朝雪 |
''');
    final assetId = addLinkedAsset('林朝雪', 'role');
    final oldId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '事务前旧镜头',
      assetIds: [assetId],
    );
    const imageRel = 'rollback/frame.png';
    const videoRel = 'rollback/video.mp4';
    for (final rel in [imageRel, videoRel]) {
      final file = File(engine.media.absPath(rel));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([4, 5, 6]);
    }
    db.execute(
        'UPDATE o_storyboard SET filePath=? WHERE id=?', [imageRel, oldId]);
    db.execute(
      'INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,?)',
      [projectId, scriptId, '已完成'],
    );
    final trackId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, videoRel, '已完成'],
    );
    db.execute(
      'INSERT INTO o_timelineClip (projectId,scriptId,filePath,lane,startMs) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, videoRel, 0, 0],
    );
    db.execute('''
CREATE TRIGGER fail_storyboard_insert
BEFORE INSERT ON o_storyboard
BEGIN
  SELECT RAISE(ABORT, 'forced storyboard insert failure');
END
''');
    gateway.toolResult = (_) => {
          'shots': [
            {'prompt': '不应落库', 'videoDesc': '不应落库'},
          ],
        };

    final taskId = engine.generateStoryboards(
      projectId,
      scriptId,
      replaceExisting: true,
    );
    await waitTask(taskId, expectState: 'failed');

    final rows = engine.storyboards(scriptId);
    expect(rows.single.id, oldId);
    expect(rows.single.prompt, '事务前旧镜头');
    expect(rows.single.assetIds, [assetId]);
    expect(
        db.select('SELECT id FROM o_videoTrack WHERE scriptId=?', [scriptId]),
        isNotEmpty);
    expect(db.select('SELECT id FROM o_video WHERE scriptId=?', [scriptId]),
        isNotEmpty);
    expect(
        db.select('SELECT id FROM o_timelineClip WHERE scriptId=?', [scriptId]),
        isNotEmpty);
    expect(File(engine.media.absPath(imageRel)).existsSync(), isTrue);
    expect(File(engine.media.absPath(videoRel)).existsSync(), isTrue);
  });

  test('分镜表格式错误在调用供应商前失败', () async {
    seedDocuments(table: '| 镜头 | 时长 |\n| --- | --- |\n| 1 | 5 |');
    gateway.toolResult = (_) => fail('不应调用供应商');
    final taskId = engine.generateStoryboards(projectId, scriptId);
    await waitTask(taskId, expectState: 'failed');
    expect(gateway.toolCalls, 0);
  });

  test('入队后剧本/规划/分镜表/资产变化均在供应商前拒绝', () async {
    Future<void> expectStale(void Function() mutate) async {
      seedDocuments();
      final beforeCalls = gateway.toolCalls;
      final taskId = engine.generateStoryboards(projectId, scriptId);
      mutate();
      await waitTask(taskId, expectState: 'failed');
      expect(gateway.toolCalls, beforeCalls);
    }

    await expectStale(() => db.execute(
        "UPDATE o_script SET content='changed script' WHERE id=?", [scriptId]));
    db.execute(
        "UPDATE o_script SET content='林朝雪拔剑，白衣如雪。' WHERE id=?", [scriptId]);
    await expectStale(() => engine.saveScriptPlan(projectId, '导演规划 B'));
    engine.saveScriptPlan(projectId, '导演规划 A');
    await expectStale(() =>
        engine.saveStoryboardTable(projectId, scriptId, '$validTable\n说明'));
    engine.saveStoryboardTable(projectId, scriptId, validTable);
    await expectStale(() => addLinkedAsset('新道具', 'tool'));
  });

  test('供应商等待期间分镜表变化时拒绝旧响应并保留旧分镜', () async {
    seedDocuments(table: '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 雪夜山门 | 慢镜推近 | 3 |
''');
    final oldId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '旧镜头',
    );
    gateway.toolResult = (_) {
      engine.saveStoryboardTable(projectId, scriptId, '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 已编辑的新镜头 | 横向跟拍 | 4 |
''');
      return {
        'shots': [
          {'prompt': '过期响应', 'videoDesc': '过期运镜'},
        ],
      };
    };

    final taskId = engine.generateStoryboards(
      projectId,
      scriptId,
      replaceExisting: true,
    );
    await waitTask(taskId, expectState: 'failed');
    expect(engine.storyboards(scriptId).single.id, oldId);
    expect(engine.storyboards(scriptId).single.prompt, '旧镜头');
  });

  test('供应商等待期间旧分镜被编辑时不用生成结果覆盖', () async {
    seedDocuments(table: '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 雪夜山门 | 慢镜推近 | 3 |
''');
    final oldId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '旧镜头',
    );
    gateway.toolResult = (_) {
      engine.editStoryboard(oldId, prompt: '用户等待时的手动修改');
      return {
        'shots': [
          {'prompt': '过期响应', 'videoDesc': '过期运镜'},
        ],
      };
    };

    final taskId = engine.generateStoryboards(
      projectId,
      scriptId,
      replaceExisting: true,
    );
    await waitTask(taskId, expectState: 'failed');
    expect(engine.storyboards(scriptId).single.id, oldId);
    expect(engine.storyboards(scriptId).single.prompt, '用户等待时的手动修改');
  });

  test('首帧图批量生成：预置生成中→完成/失败/关联资产参考图', () async {
    db.execute(
        "INSERT INTO o_assets (name,type,projectId,imageId) VALUES ('林朝雪','role',?,1)",
        [projectId]);
    final assetId = db.lastInsertRowId;
    db.execute(
        "INSERT INTO o_image (id,filePath,type,state) VALUES (1,'ref/林.png','role','已完成')");
    final s1 = engine.addStoryboard(
        projectId: projectId,
        scriptId: scriptId,
        prompt: '好镜头',
        assetIds: [assetId]);
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '坏镜头');

    gateway.imageHandler = (prompt, pid, refPath) {
      if (prompt == '好镜头') {
        expect(refPath, isNotNull);
        return 'p/img_good.png';
      }
      throw const EngineException(errLlmFormat);
    };
    final taskId = engine.batchGenerateStoryboardImages(projectId, [s1, s2]);
    await waitTask(taskId);
    final rows = engine.storyboards(scriptId);
    final good = rows.firstWhere((r) => r.id == s1);
    final bad = rows.firstWhere((r) => r.id == s2);
    expect(good.state, sbDone);
    expect(good.filePath, 'p/img_good.png');
    expect(bad.state, sbFailed);
    expect(EngineException.fromReasonJson(bad.reason)?.errKey, errLlmFormat);
  });

  test('shouldGenerateImage=0 的分镜默认跳过批量生成，compulsory=true 时强制', () async {
    final skip = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '跳过镜头');
    db.execute(
        'UPDATE o_storyboard SET shouldGenerateImage=0 WHERE id=?', [skip]);
    gateway.imageHandler = (p, i, r) => 'x/img.png';

    final skipped = engine.batchGenerateStoryboardImages(projectId, [skip]);
    expect(skipped, 0, reason: '无可生成目标，不入队');

    final forced = engine.batchGenerateStoryboardImages(projectId, [skip],
        compulsory: true);
    await waitTask(forced);
    expect(engine.storyboards(scriptId).single.state, sbDone);
  });

  test('冷启动恢复：processing 任务判失败且滞留分镜置 生成失败/errAppRestart', () {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    engine.batchGenerateStoryboardImages(projectId, [s1]);
    db.execute("UPDATE o_tasks SET state='processing'");
    engine.queue.recoverOnColdStart();
    final row = engine.storyboards(scriptId).single;
    expect(row.state, sbFailed);
    expect(EngineException.fromReasonJson(row.reason)?.errKey, errAppRestart);
  });
}

class _Gateway implements ProviderGateway {
  Map<String, dynamic> Function(String user)? toolResult;
  String Function(String system, String user, String stage)? textResult;
  String? seenSystem;
  String? seenUser;
  int toolCalls = 0;
  String Function(String prompt, String projectId, String? refPath)?
      imageHandler;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    return TextResult(textResult!(system, user, stage));
  }

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
      {required String stage,
      required String toolName,
      required Map<String, dynamic> schema,
      CancelToken? cancelToken}) async {
    expect(stage, 'storyboard_gen');
    toolCalls++;
    seenSystem = system;
    seenUser = user;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return toolResult!(user);
  }

  @override
  Future<String> generateImage(String prompt, String projectId,
      {required String stage,
      CancelToken? cancelToken,
      List<String> referenceAbsPaths = const [],
      String? editInstruction,
      String? maskAbsPath,
      String? ratio,
      String? quality,
      String? modelOverride}) async {
    expect(stage, 'shot_image');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return imageHandler!(prompt, projectId,
        referenceAbsPaths.isEmpty ? null : referenceAbsPaths.first);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
