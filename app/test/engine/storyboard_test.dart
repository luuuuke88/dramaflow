import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
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
      "('storyboard_gen','storyboard_gen','分镜系统提示词',NULL)",
    );
    engine.installStoryboardPipeline();
    engine.queue.start();
    projectId = engine.addProject(
        projectType: 'novel', name: '分镜测试', videoRatio: '16:9');
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
      final state = db
          .select('SELECT state FROM o_tasks WHERE id=?', [taskId])
          .first['state'] as String;
      if (state == 'success' || state == 'failed') {
        expect(state, expectState);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('任务超时');
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

  test('剧本生成分镜：tool-calling 落库+资产名映射为 id', () async {
    db.execute(
        "INSERT INTO o_assets (name,type,projectId) VALUES ('林朝雪','role',?)",
        [projectId]);
    final assetId = db.lastInsertRowId;
    gateway.toolResult = (user) {
      expect(user, contains('林朝雪拔剑'));
      return {
        'shots': [
          {
            'prompt': '少年白衣拔剑，逆光',
            'videoDesc': '慢镜推近',
            'duration': '3',
            'track': '主线',
            'assetNames': ['林朝雪'],
          },
          {'prompt': '剑光一闪', 'duration': '2'},
        ],
      };
    };
    final taskId = engine.generateStoryboards(projectId, scriptId);
    await waitTask(taskId);
    final rows = engine.storyboards(scriptId);
    expect(rows, hasLength(2));
    expect(rows[0].prompt, '少年白衣拔剑，逆光');
    expect(rows[0].assetIds, [assetId]);
    expect(rows[0].track, '主线');
    expect(rows[1].assetIds, isEmpty);
  });

  test('生成分镜失败：空 shots 抛 errLlmFormat', () async {
    gateway.toolResult = (_) => {'shots': []};
    final taskId = engine.generateStoryboards(projectId, scriptId);
    await waitTask(taskId, expectState: 'failed');
    final reason = db
        .select('SELECT reason FROM o_tasks WHERE id=?', [taskId])
        .first['reason'] as String;
    expect(EngineException.fromReasonJson(reason)?.errKey, errLlmFormat);
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
    final taskId =
        engine.batchGenerateStoryboardImages(projectId, [s1, s2]);
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
    db.execute('UPDATE o_storyboard SET shouldGenerateImage=0 WHERE id=?', [skip]);
    gateway.imageHandler = (p, i, r) => 'x/img.png';

    final skipped =
        engine.batchGenerateStoryboardImages(projectId, [skip]);
    expect(skipped, 0, reason: '无可生成目标，不入队');

    final forced = engine.batchGenerateStoryboardImages(
        projectId, [skip], compulsory: true);
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
  String Function(String prompt, String projectId, String? refPath)?
      imageHandler;

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
      {required String stage,
      required String toolName,
      required Map<String, dynamic> schema,
      CancelToken? cancelToken}) async {
    expect(stage, 'storyboard_gen');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return toolResult!(user);
  }

  @override
  Future<String> generateImage(String prompt, String projectId,
      {required String stage,
      CancelToken? cancelToken,
      String? refImageAbsPath,
      String? editInstruction}) async {
    expect(stage, 'shot_image');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return imageHandler!(prompt, projectId, refImageAbsPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
