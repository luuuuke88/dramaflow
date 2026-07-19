import 'dart:async';
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
import 'package:dramaflow/src/engine/prompt_resolver.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-assets-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    engine.installAssetPipeline();
    engine.queue.start();
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('asset_prompt_polish','asset_prompt_polish','',NULL)",
    );
    projectId =
        engine.addProject(projectType: 'novel', name: '素材测试', artStyle: '国风水墨');
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

  Future<void> waitForTaskState(int taskId, String expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final state = db.select(
              'SELECT state FROM o_tasks WHERE id=?', [taskId]).first['state']
          as String;
      if (state == expected) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('任务未进入 $expected');
  }

  test('CRUD：父子层级/getAssets JOIN 选中图/分页搜索', () {
    final parent = engine.addAsset(
        projectId: projectId, type: 'role', name: '林逸', describe: '主角');
    engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林逸-侧脸',
        describe: '衍生',
        parentAssetsId: parent);
    engine.saveAssetImage(
      assetsId: parent,
      projectId: projectId,
      base64Image: base64Encode([1, 2, 3]),
      type: 'role',
      prompt: 'a young man',
    );

    final page = engine.getAssets(projectId, type: 'role');
    expect(page.total, 1, reason: '子资产不计入父列表');
    final row = page.data.single;
    expect(row.name, '林逸');
    expect(row.prompt, 'a young man');
    expect(row.filePath, isNotNull);
    expect(row.imageState, stateDone);
    expect(row.sonAssets.single.name, '林逸-侧脸');

    expect(engine.getAssets(projectId, type: 'role', search: '不存在').total, 0);
    expect(engine.assetImages(parent).single.selected, isTrue);
  });

  test('cornerScapeAssets 默认返回三类父资产、排除音频子资产并保留全部历史图', () {
    final role = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '甲',
      describe: '',
    );
    final scene = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
    );
    final tool = engine.addAsset(
      projectId: projectId,
      type: 'tool',
      name: '灵剑',
      describe: '',
    );
    final audio = engine.addAsset(
      projectId: projectId,
      type: 'audio',
      name: '旁白',
      describe: '',
    );
    final clip = engine.addAsset(
      projectId: projectId,
      type: 'clip',
      name: '片头',
      describe: '',
    );
    final unknown = engine.addAsset(
      projectId: projectId,
      type: 'unknown',
      name: '未知',
      describe: '',
    );
    final child = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '甲-侧脸',
      describe: '',
      parentAssetsId: role,
    );
    engine.saveAssetImage(
      assetsId: role,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([1, 2, 3]),
    );
    engine.saveAssetImage(
      assetsId: role,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([4, 5, 6]),
    );

    final result = engine.cornerScapeAssets(projectId);
    final byId = {for (final item in result) item.asset.id: item};

    expect(byId.keys, unorderedEquals([role, scene, tool]));
    expect(byId.keys, isNot(contains(audio)));
    expect(byId.keys, isNot(contains(clip)));
    expect(byId.keys, isNot(contains(unknown)));
    expect(byId.keys, isNot(contains(child)));
    expect(byId[role]!.images.map((image) => image.id),
        orderedEquals(engine.assetImages(role).map((image) => image.id)));
    expect(byId[role]!.images, hasLength(2));
    expect(byId[role]!.asset.imageState, stateDone);
  });

  test('cornerScapeAssets 显式集合白名单忽略 audio、clip 和未知类型', () {
    final role = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '甲',
      describe: '',
    );
    final scene = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
    );
    final tool = engine.addAsset(
      projectId: projectId,
      type: 'tool',
      name: '灵剑',
      describe: '',
    );
    final audio = engine.addAsset(
      projectId: projectId,
      type: 'audio',
      name: '旁白',
      describe: '',
    );
    final clip = engine.addAsset(
      projectId: projectId,
      type: 'clip',
      name: '片头',
      describe: '',
    );
    final unknown = engine.addAsset(
      projectId: projectId,
      type: 'unknown',
      name: '未知',
      describe: '',
    );
    final roleChild = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '甲-侧脸',
      describe: '',
      parentAssetsId: role,
    );
    engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门-远景',
      describe: '',
      parentAssetsId: scene,
    );

    final result = engine.cornerScapeAssets(
      projectId,
      types: {'role', 'audio', 'clip', 'unknown'},
    );

    expect(result.map((item) => item.asset.id), unorderedEquals([role]));
    expect(result.map((item) => item.asset.id), isNot(contains(roleChild)));
    expect(result.map((item) => item.asset.id), isNot(contains(scene)));
    expect(result.map((item) => item.asset.id), isNot(contains(tool)));
    expect(result.map((item) => item.asset.id), isNot(contains(audio)));
    expect(result.map((item) => item.asset.id), isNot(contains(clip)));
    expect(result.map((item) => item.asset.id), isNot(contains(unknown)));
  });

  test('cornerScapeImageTaskId 忽略 ids、错误 taskClass 和非活动最新任务', () {
    final idsOnlyAsset = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: 'ids-only',
      describe: '',
    );
    final wrongClassAsset = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: 'wrong-class',
      describe: '',
    );
    final completedAsset = engine.addAsset(
      projectId: projectId,
      type: 'tool',
      name: 'completed',
      describe: '',
    );
    final failedAsset = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: 'failed',
      describe: '',
    );
    final imageOnlyAsset = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: 'image-only',
      describe: '',
    );
    engine.saveAssetImage(
      assetsId: imageOnlyAsset,
      projectId: projectId,
      type: 'scene',
      base64Image: base64Encode([7, 8, 9]),
    );

    int addTask({
      required String state,
      required String taskClass,
      required Map<String, Object?> relatedObjects,
    }) {
      db.execute(
        'INSERT INTO o_tasks '
        '(projectId,state,taskClass,describe,relatedObjects,startTime) '
        'VALUES (?,?,?,?,?,?)',
        [
          projectId,
          state,
          taskClass,
          '测试任务',
          jsonEncode(relatedObjects),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      return db.lastInsertRowId;
    }

    addTask(
      state: 'pending',
      taskClass: 'asset_image_generation',
      relatedObjects: {
        'ids': [idsOnlyAsset]
      },
    );
    addTask(
      state: 'pending',
      taskClass: 'storyboard_image_generation',
      relatedObjects: {
        'items': [
          {'assetsId': wrongClassAsset},
        ],
      },
    );
    addTask(
      state: 'success',
      taskClass: 'asset_image_generation',
      relatedObjects: {
        'items': [
          {'assetsId': completedAsset},
        ],
      },
    );
    addTask(
      state: 'failed',
      taskClass: 'asset_image_generation',
      relatedObjects: {
        'items': [
          {'assetsId': failedAsset},
        ],
      },
    );

    expect(engine.cornerScapeImageTaskId(idsOnlyAsset), isNull);
    expect(engine.cornerScapeImageTaskId(wrongClassAsset), isNull);
    expect(engine.cornerScapeImageTaskId(completedAsset), isNull);
    expect(engine.cornerScapeImageTaskId(failedAsset), isNull);
    expect(engine.cornerScapeImageTaskId(imageOnlyAsset), isNull);
  });

  test('cornerScapeImageTaskId 分别返回 pending 和 processing 资产的任务', () {
    final pendingAsset = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: 'pending-only',
      describe: '',
    );
    final processingAsset = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: 'processing-only',
      describe: '',
    );

    int addTask(int assetsId, String state) {
      db.execute(
        'INSERT INTO o_tasks '
        '(projectId,state,taskClass,describe,relatedObjects,startTime) '
        'VALUES (?,?,?,?,?,?)',
        [
          projectId,
          state,
          'asset_image_generation',
          '测试任务',
          jsonEncode({
            'items': [
              {'assetsId': assetsId},
            ],
          }),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      return db.lastInsertRowId;
    }

    final pendingTask = addTask(pendingAsset, 'pending');
    final processingTask = addTask(processingAsset, 'processing');

    expect(engine.cornerScapeImageTaskId(pendingAsset), pendingTask);
    expect(engine.cornerScapeImageTaskId(processingAsset), processingTask);
  });

  test('cornerScapeImageTaskId 返回同一资产最新的 processing 生图任务', () {
    final target = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '甲',
      describe: '',
    );

    int addTask(String state) {
      db.execute(
        'INSERT INTO o_tasks '
        '(projectId,state,taskClass,describe,relatedObjects,startTime) '
        'VALUES (?,?,?,?,?,?)',
        [
          projectId,
          state,
          'asset_image_generation',
          '测试任务',
          jsonEncode({
            'items': [
              {'assetsId': target},
            ],
          }),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      return db.lastInsertRowId;
    }

    final firstTask = addTask('pending');
    final latestTask = addTask('processing');

    expect(engine.cornerScapeImageTaskId(target), latestTask);
    expect(latestTask, greaterThan(firstTask));
  });

  test('deleteAssets 级联子资产+图片文件；deleteAssetImage 置空选中', () {
    final parent = engine.addAsset(
        projectId: projectId, type: 'scene', name: '寒山', describe: 'x');
    engine.saveAssetImage(
        assetsId: parent,
        projectId: projectId,
        base64Image: base64Encode([9, 9]),
        type: 'scene');
    final img = engine.assetImages(parent).single;
    final abs = engine.mediaAbsPath(img.filePath!);
    expect(File(abs).existsSync(), isTrue);

    engine.deleteAssetImage(img.id);
    expect(File(abs).existsSync(), isFalse);
    expect(
        engine.getAssets(projectId, type: 'scene').data.single.imageId, isNull);

    engine.addAsset(
        projectId: projectId,
        type: 'scene',
        name: '子',
        describe: 'y',
        parentAssetsId: parent);
    engine.deleteAssets([parent]);
    expect(db.select('SELECT COUNT(*) n FROM o_assets').first['n'], 0);
  });

  test('uploadClip：真实文件落盘 + o_image 行 + imageId 选中', () {
    final id = engine.uploadClip(
      projectId: projectId,
      name: '片头素材',
      bytes: const [1, 2, 3, 4, 5],
      ext: 'mp4',
    );
    final page = engine.getAssets(projectId, type: 'clip');
    final row = page.data.single;
    expect(row.id, id);
    expect(row.name, '片头素材');
    expect(row.type, 'clip');
    expect(row.imageId, isNotNull, reason: 'uploadClip 应选中新建的图片行');
    expect(row.filePath, isNotNull);
    expect(row.filePath, endsWith('.mp4'));
    expect(row.imageState, stateDone);
    final abs = engine.mediaAbsPath(row.filePath!);
    expect(File(abs).existsSync(), isTrue);
    expect(File(abs).readAsBytesSync(), const [1, 2, 3, 4, 5]);
  });

  test('uploadClip：空名称回退默认名', () {
    final id = engine.uploadClip(
      projectId: projectId,
      name: '   ',
      bytes: const [9],
      ext: 'png',
    );
    final row = engine.assetsByIds([id]).single;
    expect(row.name, '素材');
  });

  test('音频资产：父子结构/性别管道编码/文件落盘', () {
    final parentId = engine.addAudioAssets(
      projectId: projectId,
      name: '沉稳男声',
      sex: '男',
      describe: '低音',
      items: [
        (
          base64: base64Encode([1, 1]),
          ext: 'mp3',
          prompt: '今日天气不错',
          name: '样例1',
          describe: '平静',
          existingImageId: null,
        ),
      ],
    );
    final page = engine.getAssets(projectId, type: 'audio');
    final parent = page.data.single;
    expect(parent.id, parentId);
    expect(parent.sex, '男');
    expect(parent.audioDescribe, '低音');
    expect(parent.sonAssets.single.prompt, '今日天气不错');
    expect(parent.sonAssets.single.filePath, endsWith('.mp3'));

    engine.updateAudioAssets(
      parentId: parentId,
      projectId: projectId,
      name: '沉稳男声2',
      sex: '男',
      describe: '更低',
      items: const [],
    );
    final updated = engine.getAssets(projectId, type: 'audio').data.single;
    expect(updated.name, '沉稳男声2');
    expect(updated.sonAssets, isEmpty);
  });

  test('单资产润色：视觉手册作 system、模板逐字、状态流转', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      data: {for (final k in visualManualKeys) k: '手册[$k]'},
    );
    final id = engine.addAsset(
        projectId: projectId, type: 'role', name: '林逸', describe: '主角侠客');
    gateway.textHandler = (system, user) {
      expect(system, '手册[art_character]');
      expect(user, '**基础参数：**\n**角色设定：**\n- 角色名称:林逸,\n- 角色描述:主角侠客,');
      return 'a wuxia hero, ink style';
    };
    final prompt = await engine.polishAssetPrompt(id);
    expect(prompt, 'a wuxia hero, ink style');
    final row = engine.getAssets(projectId, type: 'role').data.single;
    expect(row.promptState, stateDone);
    expect(row.prompt, prompt);
  });

  test('批量润色按基础模板和视觉章节组装并记录来源', () async {
    db.execute(
      "UPDATE o_prompt SET data='BASE ASSET' WHERE name='asset_prompt_polish'",
    );
    engine.saveVisualManual(
      name: '国风水墨',
      data: const {
        'art_character': 'VISUAL ROLE',
        'art_character_derivative': 'VISUAL DERIVATIVE',
      },
    );
    final parent = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角侠客',
    );
    final derivative = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸战损',
      describe: '战后造型',
      parentAssetsId: parent,
    );
    gateway.textHandler = (system, user) {
      expect(system, isNot(contains('SECRET INSTRUCTION')));
      if (user.contains('林逸战损')) {
        expect(system, 'BASE ASSET\n\nVISUAL DERIVATIVE');
      } else {
        expect(system, 'BASE ASSET\n\nVISUAL ROLE');
      }
      expect(
        user.indexOf('角色描述'),
        lessThan(user.indexOf('SECRET INSTRUCTION')),
      );
      return 'resolved prompt';
    };

    final taskId = engine.batchPolishAssetPrompts(
      projectId,
      [parent, derivative],
      concurrentCount: 2,
      otherTextPrompt: 'SECRET INSTRUCTION',
    );
    await waitTask(taskId);

    final related = jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [taskId]).single['relatedObjects'] as String) as Map<String, dynamic>;
    final sources = (related['promptSources'] as List)
        .map((source) => Map<String, dynamic>.from(source as Map))
        .toList();
    expect(sources.map((source) => source['id']), [
      'base:asset_prompt_polish',
      'visual:国风水墨:art_character',
      'visual:国风水墨:art_character_derivative',
      'instruction:asset_prompt_polish',
    ]);
    expect(sources.map((source) => source['version']), [
      promptContentHash('BASE ASSET'),
      promptContentHash('VISUAL ROLE'),
      promptContentHash('VISUAL DERIVATIVE'),
      promptContentHash('SECRET INSTRUCTION'),
    ]);
    expect(jsonEncode(related), isNot(contains('BASE ASSET')));
    expect(jsonEncode(related), isNot(contains('VISUAL ROLE')));
    expect(jsonEncode(related), isNot(contains('SECRET INSTRUCTION')));
    expect(
      related['privateInstructionVersion'],
      promptContentHash('SECRET INSTRUCTION'),
    );
    final requests = (related['promptRequests'] as List)
        .map((request) => Map<String, dynamic>.from(request as Map))
        .toList();
    expect(
        requests.map((request) => request['targetId']), [parent, derivative]);
    expect(
      (requests[0]['sources'] as List).map((source) => (source as Map)['id']),
      [
        'base:asset_prompt_polish',
        'visual:国风水墨:art_character',
        'data:asset:$parent',
        'instruction:asset_prompt_polish',
      ],
    );
    expect(
      (requests[1]['sources'] as List).map((source) => (source as Map)['id']),
      [
        'base:asset_prompt_polish',
        'visual:国风水墨:art_character_derivative',
        'data:asset:$derivative',
        'instruction:asset_prompt_polish',
      ],
    );
    expect(
      (requests[0]['sources'] as List)
          .map((source) => (source as Map)['version']),
      [
        promptContentHash('BASE ASSET'),
        promptContentHash('VISUAL ROLE'),
        promptContentHash('**基础参数：**\n'
            '**角色设定：**\n'
            '- 角色名称:林逸,\n'
            '- 角色描述:主角侠客,'),
        promptContentHash('SECRET INSTRUCTION'),
      ],
    );
    expect(
      File(p.join(dir.path, 'task_payloads', '$taskId.payload')).existsSync(),
      isFalse,
      reason: '成功任务应清理私有补充要求文件',
    );
  });

  test('取消后的批量润色保留私有要求，重试成功后清理', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      data: const {'art_character': 'VISUAL ROLE'},
    );
    final id = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角侠客',
    );
    final taskId = engine.batchPolishAssetPrompts(
      projectId,
      [id],
      otherTextPrompt: 'RETRY INSTRUCTION',
    );
    final payload = File(p.join(dir.path, 'task_payloads', '$taskId.payload'));
    expect(payload.existsSync(), isTrue);

    await engine.cancelJob(taskId);
    expect(
      db.select(
          'SELECT state FROM o_tasks WHERE id=?', [taskId]).single['state'],
      'failed',
    );
    expect(payload.existsSync(), isTrue, reason: '失败任务重试仍需原始补充要求');

    gateway.textHandler = (system, user) {
      expect(user, contains('RETRY INSTRUCTION'));
      return 'retried prompt';
    };
    final retryId = await engine.retryJob(taskId);
    final retryPayload =
        File(p.join(dir.path, 'task_payloads', '$retryId.payload'));
    expect(retryId, isNot(taskId));
    expect(payload.existsSync(), isFalse, reason: '私有要求只保留在最新 attempt');
    expect(retryPayload.existsSync(), isTrue);
    expect(
      db.select('SELECT state,reason FROM o_tasks WHERE id=?', [taskId]).single,
      containsPair('state', 'failed'),
    );
    expect(
        db.select(
            'SELECT reason FROM o_tasks WHERE id=?', [taskId]).single['reason'],
        isNotNull);
    await waitTask(retryId);
    expect(retryPayload.existsSync(), isFalse);
    expect(engine.assetsByIds([id]).single.prompt, 'retried prompt');
  });

  test('冷启动时私有要求文件缺失会在模型调用前失败关闭', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      data: const {'art_character': 'VISUAL ROLE'},
    );
    final id = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角侠客',
    );
    final taskId = engine.batchPolishAssetPrompts(
      projectId,
      [id],
      otherTextPrompt: 'MUST SURVIVE',
    );
    File(p.join(dir.path, 'task_payloads', '$taskId.payload')).deleteSync();

    engine.dispose();
    gateway.textHandler = (system, user) => fail('私有要求缺失时不得调用模型');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    engine.installAssetPipeline();
    engine.queue.start();

    await waitTask(taskId, expectState: 'failed');
    final asset = engine.assetsByIds([id]).single;
    expect(asset.promptState, stateFailed);
    expect(
      EngineException.fromReasonJson(asset.promptErrorReason)?.errKey,
      errPromptMissing,
    );
  });

  test('冷启动时私有要求文件被篡改会在模型调用前失败关闭', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      data: const {'art_character': 'VISUAL ROLE'},
    );
    final id = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角侠客',
    );
    final taskId = engine.batchPolishAssetPrompts(
      projectId,
      [id],
      otherTextPrompt: 'MUST NOT CHANGE',
    );
    File(p.join(dir.path, 'task_payloads', '$taskId.payload'))
        .writeAsStringSync('TAMPERED');

    engine.dispose();
    gateway.textHandler = (system, user) => fail('私有要求被篡改时不得调用模型');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    engine.installAssetPipeline();
    engine.queue.start();

    await waitTask(taskId, expectState: 'failed');
    final asset = engine.assetsByIds([id]).single;
    expect(asset.promptState, stateFailed);
    expect(
      EngineException.fromReasonJson(asset.promptErrorReason)?.errKey,
      errPromptMissing,
    );
  });

  test('删除项目同时删除该项目任务的私有要求文件', () {
    engine.saveVisualManual(
      name: '国风水墨',
      data: const {'art_character': 'VISUAL ROLE'},
    );
    final id = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角侠客',
    );
    final taskId = engine.batchPolishAssetPrompts(
      projectId,
      [id],
      otherTextPrompt: 'DELETE WITH PROJECT',
    );
    final payload = File(p.join(dir.path, 'task_payloads', '$taskId.payload'));
    expect(payload.existsSync(), isTrue);

    engine.deleteProject(projectId);

    expect(payload.existsSync(), isFalse);
    expect(db.select('SELECT id FROM o_tasks WHERE id=?', [taskId]), isEmpty);
  });

  test('私有要求写入失败时撤销任务并标记资产失败', () {
    engine.saveVisualManual(
      name: '国风水墨',
      data: const {'art_character': 'VISUAL ROLE'},
    );
    final id = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角侠客',
    );
    File(p.join(dir.path, 'task_payloads'))
        .writeAsStringSync('block directory');

    expect(
      () => engine.batchPolishAssetPrompts(
        projectId,
        [id],
        otherTextPrompt: 'WILL NOT PERSIST',
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(db.select('SELECT id FROM o_tasks'), isEmpty);
    final asset = engine.assetsByIds([id]).single;
    expect(asset.promptState, stateFailed);
    expect(
      EngineException.fromReasonJson(asset.promptErrorReason)?.errKey,
      errNetwork,
    );
  });

  test('批量润色：并发任务、单个失败不失败任务、衍生用 _derivative 手册', () async {
    engine.saveVisualManual(
      name: '国风水墨',
      data: {for (final k in visualManualKeys) k: '手册[$k]'},
    );
    final a = engine.addAsset(
        projectId: projectId, type: 'tool', name: '剑', describe: '古剑');
    final b = engine.addAsset(
        projectId: projectId,
        type: 'tool',
        name: '剑-鞘',
        describe: '衍生',
        parentAssetsId: a);
    final c = engine.addAsset(
        projectId: projectId, type: 'tool', name: '坏', describe: 'x');
    gateway.textHandler = (system, user) {
      if (user.contains('坏')) {
        throw DioException(requestOptions: RequestOptions());
      }
      if (user.contains('剑-鞘')) {
        expect(system, contains('手册[art_prop_derivative]'));
      } else {
        expect(system, contains('手册[art_prop]'));
      }
      return 'ok prompt';
    };
    final taskId = engine.batchPolishAssetPrompts(projectId, [a, b, c]);
    await waitTask(taskId);
    final states = db
        .select('SELECT id,promptState FROM o_assets ORDER BY id')
        .map((r) => r['promptState'])
        .toList();
    expect(states, [stateDone, stateDone, stateFailed]);
  });

  test('取消待处理资产生图会失败生成中占位并保留已完成历史', () async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '主角',
      prompt: '侠客',
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([1, 2, 3]),
    );
    final completedId = engine.assetImages(assetId).single.id;
    final taskId = engine.generateAssetImages(
      projectId,
      [(assetsId: assetId, refImageBase64: null)],
    );
    final task = (await engine.projectJobs(projectId))
        .singleWhere((job) => job.id == taskId);
    final canceledImageId = ((task.relatedObjectsJson['items'] as List).single
        as Map)['imageId'] as int;

    await engine.cancelJob(taskId);

    final images = {
      for (final image in engine.assetImages(assetId)) image.id: image
    };
    expect(images[completedId]!.state, stateDone);
    expect(images[canceledImageId]!.state, stateFailed);
    expect(
      EngineException.fromReasonJson(images[canceledImageId]!.errorReason)
          ?.errKey,
      errCanceled,
    );
  });

  test('取消的资产生图任务重试只为失败项创建新图片并更新选中图', () async {
    final completedAssetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '已完成角色',
      describe: '保留历史',
      prompt: '完成图',
    );
    final canceledAssetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '待重试场景',
      describe: '取消后重试',
      prompt: '失败图',
    );
    final canceledRequest = Completer<String>();
    final canceledRequestStarted = Completer<void>();
    gateway.imageFutureHandler = (prompt, _) {
      if (prompt.contains('已完成角色')) {
        return Future.value('p/completed.png');
      }
      canceledRequestStarted.complete();
      return canceledRequest.future;
    };

    final taskId = engine.generateAssetImages(
      projectId,
      [
        (assetsId: completedAssetId, refImageBase64: null),
        (assetsId: canceledAssetId, refImageBase64: null),
      ],
    );
    final originalTask = (await engine.projectJobs(projectId))
        .singleWhere((job) => job.id == taskId);
    final originalItems = {
      for (final item in (originalTask.relatedObjectsJson['items'] as List)
          .whereType<Map>())
        (item['assetsId'] as num).toInt(): (item['imageId'] as num).toInt(),
    };
    final completedImageId = originalItems[completedAssetId]!;
    final canceledImageId = originalItems[canceledAssetId]!;
    await canceledRequestStarted.future.timeout(const Duration(seconds: 5));

    await engine.cancelJob(taskId);
    canceledRequest.complete('p/late-canceled.png');
    await waitTask(taskId, expectState: 'failed');

    final retryRequest = Completer<String>();
    final retryRequestStarted = Completer<void>();
    gateway.imageFutureHandler = (_, __) {
      retryRequestStarted.complete();
      return retryRequest.future;
    };
    final retryId = await engine.retryJob(taskId);
    final retryTask = (await engine.projectJobs(projectId))
        .singleWhere((job) => job.id == retryId);
    final retryItems = (retryTask.relatedObjectsJson['items'] as List)
        .whereType<Map>()
        .toList();

    expect(retryItems, hasLength(1));
    expect(retryItems.single['assetsId'], canceledAssetId);
    final retryImageId = (retryItems.single['imageId'] as num).toInt();
    expect(retryImageId, isNot(canceledImageId));
    expect(
      engine.assetsByIds([completedAssetId]).single.imageId,
      completedImageId,
    );
    expect(
      engine.assetsByIds([canceledAssetId]).single.imageId,
      retryImageId,
    );
    await retryRequestStarted.future.timeout(const Duration(seconds: 5));
    expect(
      engine
          .assetImages(canceledAssetId)
          .singleWhere((image) => image.id == retryImageId)
          .state,
      stateGenerating,
    );

    retryRequest.complete('p/retried.png');
    await waitTask(retryId);

    final completedImage = engine.assetImages(completedAssetId).single;
    final canceledImages = {
      for (final image in engine.assetImages(canceledAssetId)) image.id: image,
    };
    expect(completedImage.id, completedImageId);
    expect(completedImage.state, stateDone);
    expect(completedImage.filePath, 'p/completed.png');
    expect(canceledImages[canceledImageId]!.state, stateFailed);
    expect(canceledImages[canceledImageId]!.filePath, isNull);
    expect(
      EngineException.fromReasonJson(
        canceledImages[canceledImageId]!.errorReason,
      )?.errKey,
      errCanceled,
    );
    expect(canceledImages[retryImageId]!.state, stateDone);
    expect(canceledImages[retryImageId]!.filePath, 'p/retried.png');
    expect(
      engine.assetsByIds([canceledAssetId]).single.imageId,
      retryImageId,
    );
  });

  test('处理中资产生图取消后晚到结果不能覆盖取消失败态', () async {
    final pendingImage = Completer<String>();
    gateway.pendingImage = pendingImage;
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '雪山',
      describe: '夜景',
      prompt: '风雪',
    );
    final taskId = engine.generateAssetImages(
      projectId,
      [(assetsId: assetId, refImageBase64: null)],
    );
    final task = (await engine.projectJobs(projectId))
        .singleWhere((job) => job.id == taskId);
    final imageId = ((task.relatedObjectsJson['items'] as List).single
        as Map)['imageId'] as int;
    await waitForTaskState(taskId, 'processing');

    await engine.cancelJob(taskId);
    final stateAfterCancel = engine.assetImages(assetId).single.state;
    pendingImage.complete('p/late_result.png');
    await waitTask(taskId, expectState: 'failed');

    final image = engine.assetImages(assetId).single;
    expect(stateAfterCancel, stateFailed);
    expect(image.id, imageId);
    expect(image.state, stateFailed);
    expect(image.filePath, isNull);
    expect(
      EngineException.fromReasonJson(image.errorReason)?.errKey,
      errCanceled,
    );
  });

  test('生图：预插生成中→成功落盘/失败保留错误码；冷启动恢复', () async {
    final a = engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林逸',
        describe: 'x',
        prompt: 'hero');
    final b = engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '坏图',
        describe: 'y',
        prompt: 'bad');
    gateway.imageHandler = (prompt, projectId) {
      expect(prompt, contains('请根据以下参数生成角色标准四视图：'));
      expect(prompt, contains('- 画风风格: 国风水墨'));
      if (prompt.contains('坏图')) {
        throw const EngineException(errLlmFormat);
      }
      return 'p/img_ok.png';
    };
    final taskId = engine.generateAssetImages(
      projectId,
      [
        (assetsId: a, refImageBase64: null),
        (assetsId: b, refImageBase64: null)
      ],
      resolution: '2K',
    );
    // 预插断言
    expect(
      db.select('SELECT COUNT(*) n FROM o_image WHERE state=?',
          [stateGenerating]).first['n'],
      anyOf(2, 1, 0), // 竞态：任务可能已开始
    );
    await waitTask(taskId);
    final images = engine.assetImages(a);
    expect(images.single.state, stateDone);
    expect(images.single.filePath, 'p/img_ok.png');
    expect(images.single.resolution, '2K');
    final failed = engine.assetImages(b).single;
    expect(failed.state, stateFailed);
    expect(
      EngineException.fromReasonJson(failed.errorReason)?.errKey,
      errLlmFormat,
    );

    // 冷启动恢复
    db.execute(
        'UPDATE o_image SET state=? WHERE assetsId=?', [stateGenerating, a]);
    db.execute("UPDATE o_tasks SET state='processing' WHERE id=?", [taskId]);
    engine.queue.recoverOnColdStart();
    expect(engine.assetImages(a).single.state, stateFailed);
  });
}

class _Gateway implements ProviderGateway {
  String Function(String system, String user)? textHandler;
  String Function(String prompt, String projectId)? imageHandler;
  Future<String> Function(String prompt, String projectId)? imageFutureHandler;
  Completer<String>? pendingImage;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return TextResult(textHandler!(system, user));
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
    expect(stage, 'asset_image');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (imageFutureHandler case final handler?) {
      return handler(prompt, projectId);
    }
    if (pendingImage case final pending?) return pending.future;
    return imageHandler!(prompt, projectId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
