// 节点式图片编辑器持久化+生成（照抄 ToonFlow /production/editImage/*，
// 详见 docs/reference/p3-production-canvas-brief.md §3）。
// o_imageFlow.flowData = JSON {"nodes":[...],"edges":[...]}（剥离 VueFlow 内部字段，
// 仅保留 id/type/position/data，逐字照抄 cleanNodes/cleanEdges 语义）。
//
// generateFlowImage 把全部连线参考图作为参考列表传给图模型（对齐 ToonFlow 多参考语义）。
// 本操作是交互式同步调用（用户点击等待），不入队列（与 ToonFlow 该端点同为同步语义，
// 不产生 o_tasks 行）。
import 'dart:convert';
import 'dart:typed_data';

import 'engine.dart';

class ImageFlowNode {
  final String id;
  final String type; // upload | generated
  final double x;
  final double y;
  final Map<String, dynamic> data;
  const ImageFlowNode(
      {required this.id,
      required this.type,
      required this.x,
      required this.y,
      required this.data});

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'position': {'x': x, 'y': y}, 'data': data};

  factory ImageFlowNode.fromJson(Map<String, dynamic> j) => ImageFlowNode(
        id: j['id'] as String,
        type: j['type'] as String,
        x: ((j['position']?['x']) as num?)?.toDouble() ?? 0,
        y: ((j['position']?['y']) as num?)?.toDouble() ?? 0,
        data: Map<String, dynamic>.from(j['data'] as Map? ?? {}),
      );
}

class ImageFlowEdge {
  final String id;
  final String source;
  final String target;
  const ImageFlowEdge(
      {required this.id, required this.source, required this.target});

  Map<String, dynamic> toJson() =>
      {'id': id, 'source': source, 'target': target, 'type': 'removeLine'};

  factory ImageFlowEdge.fromJson(Map<String, dynamic> j) => ImageFlowEdge(
        id: j['id'] as String,
        source: j['source'] as String,
        target: j['target'] as String,
      );
}

class ImageFlowData {
  final int? flowId;
  final List<ImageFlowNode> nodes;
  final List<ImageFlowEdge> edges;
  const ImageFlowData({this.flowId, required this.nodes, required this.edges});
}

extension ImageFlowApi on Engine {
  /// 编辑器上传节点选图：落盘为普通媒体文件，返回相对路径。
  String saveFlowUploadImage(int projectId, Uint8List bytes) =>
      media.saveImage(bytes, '$projectId');


  ImageFlowData getImageFlow(int? flowId) {
    if (flowId == null) return const ImageFlowData(nodes: [], edges: []);
    final row = db
        .select('SELECT flowData FROM o_imageFlow WHERE id=?', [flowId])
        .firstOrNull;
    if (row == null) return const ImageFlowData(nodes: [], edges: []);
    try {
      final decoded = jsonDecode(row['flowData'] as String) as Map;
      return ImageFlowData(
        flowId: flowId,
        nodes: (decoded['nodes'] as List? ?? const [])
            .map((n) => ImageFlowNode.fromJson(Map<String, dynamic>.from(n)))
            .toList(),
        edges: (decoded['edges'] as List? ?? const [])
            .map((e) => ImageFlowEdge.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } catch (_) {
      return ImageFlowData(flowId: flowId, nodes: const [], edges: const []);
    }
  }

  /// 保存（新建）或更新画布图，返回 flowId。
  int saveImageFlow(
    List<ImageFlowNode> nodes,
    List<ImageFlowEdge> edges, {
    int? existingFlowId,
  }) {
    final json = jsonEncode({
      'nodes': [for (final n in nodes) n.toJson()],
      'edges': [for (final e in edges) e.toJson()],
    });
    if (existingFlowId != null) {
      db.execute('UPDATE o_imageFlow SET flowData=? WHERE id=?',
          [json, existingFlowId]);
      return existingFlowId;
    }
    db.execute('INSERT INTO o_imageFlow (flowData) VALUES (?)', [json]);
    return db.lastInsertRowId;
  }

  /// 生成节点出图：把 **全部** 连线参考图作为参考列表传给图模型
  /// （对齐 ToonFlow generatedNode 的多参考语义，此前只取首张）。
  /// 同步直调网关，不入队列（对齐 ToonFlow 该端点同步语义）。
  /// model/ratio/quality 对齐 ToonFlow generatedNode 三个必选参数：现真正生效——
  /// model 覆写阶段绑定图模型，ratio→尺寸、quality→清晰度传入图模型。
  Future<String> generateFlowImage({
    required int projectId,
    required String prompt,
    List<String> referenceAbsPaths = const [],
    String? model,
    String? ratio,
    String? quality,
  }) {
    return gateway.generateImage(
      prompt,
      '$projectId',
      stage: 'asset_image',
      referenceAbsPaths: referenceAbsPaths,
      ratio: ratio,
      quality: quality,
      modelOverride: model,
    );
  }
}
