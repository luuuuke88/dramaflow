import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-audiobind-');
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
      "('audio_bind','audio_bind','配音匹配系统词',NULL)",
    );
    engine.installAudioBindPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: '配音测试');
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

  test('roleAudioBindings 未绑定时 audioAssetId 为空', () {
    engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final bindings = engine.roleAudioBindings(projectId);
    expect(bindings.single.roleName, '林朝雪');
    expect(bindings.single.audioAssetId, isNull);
  });

  test('手动绑定/解绑：覆盖写入，一角色一音频', () {
    final roleId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final audioA = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: 'x');
    final audioB = engine.addAsset(
        projectId: projectId, type: 'audio', name: '清亮男声', describe: 'x');

    engine.bindRoleAudio(roleId, audioA);
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, audioA);

    engine.bindRoleAudio(roleId, audioB);
    final rows = db.select('SELECT COUNT(*) n FROM o_assetsRole2Audio').first['n'];
    expect(rows, 1, reason: '覆盖写入，不残留旧绑定');
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, audioB);

    engine.bindRoleAudio(roleId, null);
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, isNull);
  });

  test('批量 LLM 匹配：tool-calling 结果写入绑定表', () async {
    final role1 = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '冷峻少年');
    final role2 = engine.addAsset(
        projectId: projectId, type: 'role', name: '沈青崖', describe: '威严长者');
    final audioYoung = engine.addAsset(
        projectId: projectId, type: 'audio', name: '清亮少年音', describe: 'x');
    final audioOld = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低沉长者音', describe: 'x');

    gateway.toolResult = (user) {
      expect(user, contains('林朝雪'));
      expect(user, contains('清亮少年音'));
      return {
        'matches': [
          {'roleId': role1, 'audioAssetId': audioYoung},
          {'roleId': role2, 'audioAssetId': audioOld},
        ],
      };
    };
    final taskId = engine.batchBindAudio(projectId, [role1, role2]);
    await waitTask(taskId);

    final bindings = engine.roleAudioBindings(projectId);
    expect(bindings.firstWhere((b) => b.roleId == role1).audioAssetId,
        audioYoung);
    expect(bindings.firstWhere((b) => b.roleId == role2).audioAssetId, audioOld);
  });

  test('无候选音频池时抛 errPromptMissing', () async {
    final role1 = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final taskId = engine.batchBindAudio(projectId, [role1]);
    await waitTask(taskId, expectState: 'failed');
    final reason = db
        .select('SELECT reason FROM o_tasks WHERE id=?', [taskId])
        .first['reason'] as String;
    expect(EngineException.fromReasonJson(reason)?.errKey, errPromptMissing);
  });

  test('audioAssetAbsPath 解析父/子资产文件；无文件返回 null', () {
    final mediaRoot = p.join(dir.path, 'media');
    // 父资产（audioPool / 绑定关系里用到的就是这个 id）
    final parent = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: 'x');
    // 无文件时返回 null
    expect(engine.audioAssetAbsPath(parent), isNull);

    // 文件挂在子资产上（对齐 assets.dart _writeAudioItems 落盘方式）
    final childId = engine.addAsset(
        projectId: projectId,
        type: 'audio',
        name: '低音男声-1',
        describe: 'x',
        parentAssetsId: parent);
    const rel = 'aud/voice.mp3';
    final f = File(p.join(mediaRoot, rel))..parent.createSync(recursive: true);
    f.writeAsBytesSync([1, 2, 3]);
    db.execute(
        "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'audio','已完成')",
        [childId, rel]);
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [db.lastInsertRowId, childId]);

    final abs = engine.audioAssetAbsPath(parent);
    expect(abs, isNotNull);
    expect(File(abs!).existsSync(), isTrue);
    expect(abs, endsWith('voice.mp3'));
  });

  test('LLM 返回越权/无效 id 时安全忽略', () async {
    final role1 = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '音A', describe: 'x');
    gateway.toolResult = (_) => {
          'matches': [
            {'roleId': 9999, 'audioAssetId': 9999}, // 无效角色/音频 id
          ],
        };
    final taskId = engine.batchBindAudio(projectId, [role1]);
    await waitTask(taskId);
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, isNull);
  });
}

class _Gateway implements ProviderGateway {
  Map<String, dynamic> Function(String user)? toolResult;

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
      {required String stage,
      required String toolName,
      required Map<String, dynamic> schema,
      CancelToken? cancelToken}) async {
    expect(stage, 'asset_extract');
    expect(toolName, 'resultTool');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return toolResult!(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
