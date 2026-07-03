import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/image_flow.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  String Function(String prompt, String? refPath)? imageHandler;

  @override
  Future<String> generateImage(String prompt, String projectId,
      {required String stage,
      CancelToken? cancelToken,
      String? refImageAbsPath,
      String? editInstruction}) async {
    expect(stage, 'asset_image');
    return imageHandler!(prompt, refImageAbsPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-imageflow-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '编辑器测试');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('图节点往返：save→get 保留节点/边/位置/数据', () {
    final nodes = [
      const ImageFlowNode(id: 'u1', type: 'upload', x: 0, y: 0, data: {'image': 'p/a.png'}),
      const ImageFlowNode(id: 'g1', type: 'generated', x: 400, y: 0, data: {
        'prompt': '水墨少年',
        'references': [{'image': 'p/a.png'}],
      }),
    ];
    final edges = [
      const ImageFlowEdge(id: 'e1', source: 'u1', target: 'g1'),
    ];
    final flowId = engine.saveImageFlow(nodes, edges);
    final loaded = engine.getImageFlow(flowId);
    expect(loaded.nodes, hasLength(2));
    expect(loaded.nodes.last.data['prompt'], '水墨少年');
    expect(loaded.edges.single.source, 'u1');
    expect(loaded.edges.single.target, 'g1');

    // 更新覆盖
    final updatedId = engine.saveImageFlow(nodes, const [], existingFlowId: flowId);
    expect(updatedId, flowId);
    expect(engine.getImageFlow(flowId).edges, isEmpty);
  });

  test('getImageFlow(null) 与查无行均返回空图', () {
    expect(engine.getImageFlow(null).nodes, isEmpty);
    expect(engine.getImageFlow(999).nodes, isEmpty);
  });

  test('generateFlowImage 取首张参考图，同步直调网关不入队列', () async {
    gateway.imageHandler = (prompt, refPath) {
      expect(prompt, '少年拔剑');
      expect(refPath, 'ref/first.png');
      return 'p/generated.png';
    };
    final rel = await engine.generateFlowImage(
      projectId: projectId,
      prompt: '少年拔剑',
      referenceAbsPaths: ['ref/first.png', 'ref/second.png'],
    );
    expect(rel, 'p/generated.png');
    expect(db.select('SELECT COUNT(*) n FROM o_tasks').first['n'], 0,
        reason: '同步语义，不落任务表');
  });

  test('attachAssetImage 落新图片版本并选中+可选回填 flowId', () {
    final assetId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.attachAssetImage(assetId, 'p/img_flow.png', flowId: 7);
    final row = engine.getAssets(projectId, type: 'role').data.single;
    expect(row.filePath, 'p/img_flow.png');
    expect(row.flowId, 7, reason: 'AssetRow 模型直接暴露 flowId');
  });

  test('setStoryboardImage 直接写入分镜结果', () {
    final scriptId =
        engine.addScript(projectId: projectId, name: '一', content: 'x');
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    engine.setStoryboardImage(sbId, 'p/img_sb.png', flowId: 3);
    final row = engine.storyboards(scriptId).single;
    expect(row.filePath, 'p/img_sb.png');
    expect(row.state, sbDone);
    expect(row.flowId, 3, reason: 'StoryboardRow 模型直接暴露 flowId');
  });
}
