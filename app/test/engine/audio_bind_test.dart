import 'dart:convert';
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
      final state = db.select(
              'SELECT state FROM o_tasks WHERE id=?', [taskId]).first['state']
          as String;
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
    final rows =
        db.select('SELECT COUNT(*) n FROM o_assetsRole2Audio').first['n'];
    expect(rows, 1, reason: '覆盖写入，不残留旧绑定');
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, audioB);

    engine.bindRoleAudio(roleId, null);
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, isNull);
  });

  test('场景和道具可以复用原有关联表绑定音频，角色兼容 API 不回归', () {
    final scene = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门', describe: '雪夜');
    final tool = engine.addAsset(
        projectId: projectId, type: 'tool', name: '灵剑', describe: '长剑');
    final role = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: '');

    engine.bindAssetAudio(scene, audio);
    engine.bindAssetAudio(tool, audio);
    engine.bindRoleAudio(role, audio);

    expect(engine.assetAudioBindings(projectId).map((row) => row.assetId),
        containsAll([scene, tool, role]));
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, audio);
  });

  test('通用绑定只接受项目内父角色/场景/道具和父音频', () {
    final scene = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门', describe: '雪夜');
    final tool = engine.addAsset(
        projectId: projectId, type: 'tool', name: '灵剑', describe: '长剑');
    final sceneChild = engine.addAsset(
        projectId: projectId,
        type: 'scene',
        name: '山门子项',
        describe: '子项',
        parentAssetsId: scene);
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: '');
    final audioChild = engine.addAsset(
        projectId: projectId,
        type: 'audio',
        name: '低音男声子项',
        describe: '',
        parentAssetsId: audio);
    final otherProject = engine.addProject(projectType: 'novel', name: '其他项目');
    final foreignTarget = engine.addAsset(
        projectId: otherProject, type: 'role', name: '越权角色', describe: '');
    final foreignAudio = engine.addAsset(
        projectId: otherProject, type: 'audio', name: '越权音频', describe: '');

    engine.bindAssetAudio(scene, audio);
    engine.bindAssetAudio(tool, audio);
    engine.bindAssetAudio(foreignTarget, foreignAudio);
    db.execute(
        'INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)',
        [audio, sceneChild]);
    db.execute(
        'INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)',
        [audio, audio]);
    expect(_linkedAudio(db, scene), audio);
    expect(_linkedAudio(db, tool), audio);
    expect(_linkedAudio(db, foreignTarget), foreignAudio);

    engine.bindAssetAudio(scene, foreignAudio);
    expect(_linkedAudio(db, scene), audio, reason: '跨项目 audio 不得清空已有绑定');
    engine.bindAssetAudio(scene, audioChild);
    expect(_linkedAudio(db, scene), audio, reason: 'audio 子资产不得覆盖已有绑定');

    engine.bindAssetAudio(sceneChild, audio);
    expect(_linkedAudio(db, sceneChild), audio,
        reason: 'child target 不得创建或破坏绑定');
    engine.bindAssetAudio(audio, audio);
    expect(_linkedAudio(db, audio), audio, reason: 'audio target 不得创建或破坏绑定');
    engine.bindAssetAudio(foreignTarget, audio);
    expect(_linkedAudio(db, foreignTarget), foreignAudio,
        reason: '跨项目 target 不得破坏既有绑定');

    engine.bindAssetAudio(scene, null);
    engine.bindAssetAudio(tool, null);
    expect(_linkCount(db, scene), 0);
    expect(_linkCount(db, tool), 0);
  });

  test('角色包装 API 继承通用绑定的 target 和 audio 校验', () {
    final role = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final roleChild = engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林朝雪子项',
        describe: '',
        parentAssetsId: role);
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '清亮女声', describe: '');
    final audioChild = engine.addAsset(
        projectId: projectId,
        type: 'audio',
        name: '清亮女声子项',
        describe: '',
        parentAssetsId: audio);
    final otherProject = engine.addProject(projectType: 'novel', name: '其他项目');
    final foreignRole = engine.addAsset(
        projectId: otherProject, type: 'role', name: '越权角色', describe: '');
    final foreignAudio = engine.addAsset(
        projectId: otherProject, type: 'audio', name: '越权音频', describe: '');

    engine.bindRoleAudio(role, audio);
    engine.bindRoleAudio(foreignRole, foreignAudio);
    db.execute(
        'INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)',
        [audio, roleChild]);
    db.execute(
        'INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)',
        [audio, audio]);
    expect(_linkedAudio(db, role), audio);
    expect(_linkedAudio(db, foreignRole), foreignAudio);

    engine.bindRoleAudio(role, foreignAudio);
    expect(_linkedAudio(db, role), audio, reason: '跨项目 audio 不得清空角色已有绑定');
    engine.bindRoleAudio(role, audioChild);
    expect(_linkedAudio(db, role), audio, reason: 'audio 子资产不得覆盖角色已有绑定');
    engine.bindRoleAudio(roleChild, audio);
    expect(_linkedAudio(db, roleChild), audio,
        reason: 'child role target 不得创建或破坏绑定');
    engine.bindRoleAudio(audio, audio);
    expect(_linkedAudio(db, audio), audio, reason: 'audio target 不得创建或破坏角色绑定');
    engine.bindRoleAudio(foreignRole, audio);
    expect(_linkedAudio(db, foreignRole), foreignAudio,
        reason: '跨项目 role target 不得破坏既有绑定');

    engine.bindRoleAudio(role, null);
    expect(_linkCount(db, role), 0);
  });

  test('通用查询只列项目内 role/scene/tool 父资产', () {
    final role = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final scene = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门', describe: '雪夜');
    final tool = engine.addAsset(
        projectId: projectId, type: 'tool', name: '灵剑', describe: '长剑');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '音频', describe: '');
    engine.addAsset(
        projectId: projectId,
        type: 'scene',
        name: '山门子项',
        describe: '',
        parentAssetsId: scene);
    final otherProject = engine.addProject(projectType: 'novel', name: '其他项目');
    engine.addAsset(
        projectId: otherProject, type: 'role', name: '越权角色', describe: '');

    expect(engine.assetAudioBindings(projectId).map((row) => row.assetId),
        unorderedEquals([role, scene, tool]));
    expect(
        engine.assetAudioBindings(projectId, types: {'scene'}).single.assetId,
        scene);
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
    expect(
        bindings.firstWhere((b) => b.roleId == role1).audioAssetId, audioYoung);
    expect(
        bindings.firstWhere((b) => b.roleId == role2).audioAssetId, audioOld);
  });

  test('批量音频匹配为选中资产呈现开始、完成状态', () async {
    final role = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final scene = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门', describe: '雪夜');
    final ignoredAudio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '候选音频', describe: '');

    gateway.toolResult = (_) => {
          'matches': [
            {'assetId': role, 'audioAssetId': ignoredAudio},
          ],
        };
    final taskId =
        engine.batchBindAudio(projectId, [role, scene, ignoredAudio]);

    expect(_audioBindState(db, role), stateGenerating);
    expect(_audioBindState(db, scene), stateGenerating);
    expect(_audioBindState(db, ignoredAudio), isNull, reason: '音频池本身不是可匹配目标');

    await waitTask(taskId);
    expect(_audioBindState(db, role), stateDone);
    expect(_audioBindState(db, scene), stateDone,
        reason: '原版每个资产的匹配调用结束后都会进入终态');
  });

  test('批量音频匹配失败和冷启动恢复会终结资产匹配状态', () async {
    final role = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final taskId = engine.batchBindAudio(projectId, [role]);
    expect(_audioBindState(db, role), stateGenerating);

    await waitTask(taskId, expectState: 'failed');
    expect(_audioBindState(db, role), stateFailed);

    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: '');
    gateway.toolResult = (_) => {
          'matches': [
            {'assetId': role, 'audioAssetId': audio},
          ],
        };
    final interruptedTaskId = engine.batchBindAudio(projectId, [role]);
    expect(_audioBindState(db, role), stateGenerating);
    db.execute(
      "UPDATE o_tasks SET state='processing' WHERE id=?",
      [interruptedTaskId],
    );

    engine.queue.recoverOnColdStart();

    expect(
      db.select('SELECT state FROM o_tasks WHERE id=?',
          [interruptedTaskId]).single['state'],
      'failed',
    );
    expect(_audioBindState(db, role), stateFailed);
  });

  test('批量 LLM 使用新 assetIds 绑定场景和道具，提示包含资产类型', () async {
    final scene = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门', describe: '雪夜');
    final tool = engine.addAsset(
        projectId: projectId, type: 'tool', name: '灵剑', describe: '长剑');
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: '');

    gateway.toolResult = (user) {
      expect(user, contains('资产ID:$scene'));
      expect(user, contains('名称:山门'));
      expect(user, contains('描述:雪夜'));
      expect(user, contains('类型:scene'));
      expect(user, contains('资产ID:$tool'));
      expect(user, contains('类型:tool'));
      expect(user, isNot(contains('待匹配角色')));
      return {
        'matches': [
          {'assetId': scene, 'audioAssetId': audio},
          {'assetId': tool, 'audioAssetId': audio},
        ],
      };
    };
    final taskId = engine.batchBindAudio(projectId, [scene, tool]);
    final related = jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [taskId]).single['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['assetIds'], [scene, tool]);
    expect(related.containsKey('roleIds'), isFalse);
    await waitTask(taskId);

    final bindings = engine.assetAudioBindings(projectId);
    expect(bindings.firstWhere((b) => b.assetId == scene).audioAssetId, audio);
    expect(bindings.firstWhere((b) => b.assetId == tool).audioAssetId, audio);
    final matchItem = ((gateway.lastSchema!['properties'] as Map)['matches']
        as Map)['items'] as Map;
    expect((matchItem['properties'] as Map).containsKey('assetId'), isTrue);
    expect(matchItem['required'], contains('assetId'));
  });

  test('旧 roleIds payload 和 roleId 工具结果仍可恢复执行', () async {
    final role = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '剑客');
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: '');
    gateway.toolResult = (_) => {
          'matches': [
            {'roleId': role, 'audioAssetId': audio},
          ],
        };
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,describe,relatedObjects,startTime) "
      "VALUES (?,'pending','audio_bind','配音绑定',?,?)",
      [
        projectId,
        jsonEncode({
          'kind': 'role',
          'roleIds': [role]
        }),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final taskId = db.lastInsertRowId;

    await waitTask(taskId);
    expect(engine.roleAudioBindings(projectId).single.audioAssetId, audio);
  });

  test('无候选音频池时抛 errPromptMissing', () async {
    final role1 = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final taskId = engine.batchBindAudio(projectId, [role1]);
    await waitTask(taskId, expectState: 'failed');
    final reason = db.select(
            'SELECT reason FROM o_tasks WHERE id=?', [taskId]).first['reason']
        as String;
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

  test('LLM 返回越权 asset/audio id 时不写绑定', () async {
    final scene = engine.addAsset(
        projectId: projectId, type: 'scene', name: '山门', describe: 'x');
    final unselectedTool = engine.addAsset(
        projectId: projectId, type: 'tool', name: '灵剑', describe: 'x');
    final localAudio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '音A', describe: 'x');
    final otherProject = engine.addProject(projectType: 'novel', name: '其他项目');
    final foreignAudio = engine.addAsset(
        projectId: otherProject, type: 'audio', name: '越权音频', describe: 'x');
    gateway.toolResult = (_) => {
          'matches': [
            {'assetId': unselectedTool, 'audioAssetId': localAudio},
            {'assetId': scene, 'audioAssetId': foreignAudio},
          ],
        };
    final taskId = engine.batchBindAudio(projectId, [scene]);
    await waitTask(taskId);
    expect(
        engine
            .assetAudioBindings(projectId)
            .firstWhere((b) => b.assetId == scene)
            .audioAssetId,
        isNull);
    expect(
        engine
            .assetAudioBindings(projectId)
            .firstWhere((b) => b.assetId == unselectedTool)
            .audioAssetId,
        isNull);
  });
}

class _Gateway implements ProviderGateway {
  Map<String, dynamic> Function(String user)? toolResult;
  Map<String, dynamic>? lastSchema;

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
      {required String stage,
      required String toolName,
      required Map<String, dynamic> schema,
      CancelToken? cancelToken}) async {
    expect(stage, 'asset_extract');
    expect(toolName, 'resultTool');
    lastSchema = schema;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return toolResult!(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _linkCount(Database db, int assetId) => db.select(
    'SELECT COUNT(*) n FROM o_assetsRole2Audio WHERE assetsRoleId=?',
    [assetId]).single['n'] as int;

int? _linkedAudio(Database db, int assetId) => db.select(
    'SELECT assetsAudioId FROM o_assetsRole2Audio WHERE assetsRoleId=?',
    [assetId]).firstOrNull?['assetsAudioId'] as int?;

String? _audioBindState(Database db, int assetId) => db.select(
    'SELECT audioBindState FROM o_assets WHERE id=?',
    [assetId]).single['audioBindState'] as String?;
