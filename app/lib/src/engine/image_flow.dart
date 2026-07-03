// 节点式图片编辑器持久化+生成（照抄 ToonFlow /production/editImage/*，
// 详见 docs/reference/p3-production-canvas-brief.md §3）。
// o_imageFlow.flowData = JSON {"nodes":[...],"edges":[...]}（剥离 VueFlow 内部字段，
// 仅保留 id/type/position/data，逐字照抄 cleanNodes/cleanEdges 语义）。
//
// 已知偏差（文档化）：ToonFlow generateFlowImage 支持任意数量连线参考图；本引擎的
// ProviderGateway.generateImage 签名仅支持单张参考图（与 P1/P2 一致的既有能力边界），
// 故本模块取连线参考图的第一张作为编辑基准图，其余参考图仍在画布可见/可连线，
// 但不参与本次生成——不是无声阉割，此限制体现在 UI 提示文案中。
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

  /// 生成节点出图：取连线参考图首张为编辑基准（见文件头偏差说明）。
  /// 同步直调网关，不入队列（对齐 ToonFlow 该端点同步语义）。
  Future<String> generateFlowImage({
    required int projectId,
    required String prompt,
    List<String> referenceAbsPaths = const [],
  }) {
    return gateway.generateImage(
      prompt,
      '$projectId',
      stage: 'asset_image',
      refImageAbsPath: referenceAbsPaths.isEmpty ? null : referenceAbsPaths.first,
    );
  }
}
