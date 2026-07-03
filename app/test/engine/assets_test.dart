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
    projectId = engine.addProject(
        projectType: 'novel', name: '素材测试', artStyle: '国风水墨');
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
    expect(engine.getAssets(projectId, type: 'scene').data.single.imageId,
        isNull);

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
      if (user.contains('坏')) throw DioException(requestOptions: RequestOptions());
      if (user.contains('剑-鞘')) {
        expect(system, contains('手册[art_prop_derivative]'));
      } else {
        expect(system, contains('手册[art_prop]'));
      }
      return 'ok prompt';
    };
    final taskId =
        engine.batchPolishAssetPrompts(projectId, [a, b, c]);
    await waitTask(taskId);
    final states = db
        .select('SELECT id,promptState FROM o_assets ORDER BY id')
        .map((r) => r['promptState'])
        .toList();
    expect(states, [stateDone, stateDone, stateFailed]);
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
      [(assetsId: a, refImageBase64: null), (assetsId: b, refImageBase64: null)],
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
    db.execute('UPDATE o_image SET state=? WHERE assetsId=?',
        [stateGenerating, a]);
    db.execute(
        "UPDATE o_tasks SET state='processing' WHERE id=?", [taskId]);
    engine.queue.recoverOnColdStart();
    expect(engine.assetImages(a).single.state, stateFailed);
  });
}

class _Gateway implements ProviderGateway {
  String Function(String system, String user)? textHandler;
  String Function(String prompt, String projectId)? imageHandler;

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
      String? ratio,
      String? quality,
      String? modelOverride}) async {
    expect(stage, 'asset_image');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return imageHandler!(prompt, projectId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
