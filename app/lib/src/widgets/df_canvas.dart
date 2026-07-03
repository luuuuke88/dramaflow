// 通用无限画布（照抄 @vue-flow/core 行为，Flutter 自绘方案，见
// docs/reference/p3-production-canvas-brief.md §1/§6）：
// InteractiveViewer 负责平移缩放，节点用 Positioned+Stack，边用 CustomPainter
// 画三次贝塞尔曲线。节点位置由调用方在每次数据变化时重新计算并传入（链式布局，
// 不落库——与 ToonFlow 行为一致：main canvas 不持久化坐标，仅 editImage 子画布持久化）。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

class DFCanvasNode {
  final String id;
  final Offset position;
  final Size size;
  final Widget child;
  const DFCanvasNode({
    required this.id,
    required this.position,
    required this.size,
    required this.child,
  });
}

class DFCanvasEdge {
  final String sourceId;
  final String targetId;
  const DFCanvasEdge({required this.sourceId, required this.targetId});
}

/// 无限画布：平移缩放 0.1–10（照抄 VueFlow 限制），空格+拖拽额外支持由
/// InteractiveViewer 原生手势覆盖（触屏双指缩放/单指平移，桌面滚轮缩放+拖拽平移）。
class DFCanvas extends StatefulWidget {
  final List<DFCanvasNode> nodes;
  final List<DFCanvasEdge> edges;
  final TransformationController? controller;
  final bool fitOnInit;

  const DFCanvas({
    super.key,
    required this.nodes,
    this.edges = const [],
    this.controller,
    this.fitOnInit = true,
  });

  @override
  State<DFCanvas> createState() => _DFCanvasState();
}

class _DFCanvasState extends State<DFCanvas> {
  late final TransformationController _controller;
  late final bool _ownsController;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TransformationController();
    _controller.addListener(_handleTransformChanged);
    if (widget.fitOnInit && widget.nodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitView());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTransformChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DFCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitOnInit &&
        !_fitted &&
        widget.nodes.isNotEmpty &&
        oldWidget.nodes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitView());
    }
  }

  void _fitView() {
    if (widget.nodes.isEmpty || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final viewport = box.size;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final n in widget.nodes) {
      minX = math.min(minX, n.position.dx);
      minY = math.min(minY, n.position.dy);
      maxX = math.max(maxX, n.position.dx + n.size.width);
      maxY = math.max(maxY, n.position.dy + n.size.height);
    }
    final contentW = maxX - minX;
    final contentH = maxY - minY;
    if (contentW <= 0 || contentH <= 0) return;
    final scale = math.min(
        (viewport.width - 80) / contentW, (viewport.height - 80) / contentH);
    final clamped = scale.clamp(0.1, 1.0);
    final dx = (viewport.width - contentW * clamped) / 2 - minX * clamped;
    final dy = (viewport.height - contentH * clamped) / 2 - minY * clamped;
    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(clamped, clamped, 1, 1);
    _fitted = true;
  }

  Rect _visibleSceneRect(Size viewport) {
    if (viewport.isEmpty) {
      return const Rect.fromLTWH(0, 0, 12000, 8000);
    }
    final topLeft = _controller.toScene(Offset.zero);
    final bottomRight =
        _controller.toScene(Offset(viewport.width, viewport.height));
    return Rect.fromLTRB(
      math.min(topLeft.dx, bottomRight.dx),
      math.min(topLeft.dy, bottomRight.dy),
      math.max(topLeft.dx, bottomRight.dx),
      math.max(topLeft.dy, bottomRight.dy),
    ).inflate(600);
  }

  bool _nodeIntersects(DFCanvasNode node, Rect sceneRect) {
    final rect = Rect.fromLTWH(
      node.position.dx,
      node.position.dy,
      node.size.width,
      node.size.height,
    );
    return rect.overlaps(sceneRect);
  }

  bool _edgeIntersects(
    DFCanvasEdge edge,
    Rect sceneRect,
    Map<String, DFCanvasNode> nodes,
  ) {
    final source = nodes[edge.sourceId];
    final target = nodes[edge.targetId];
    if (source == null || target == null) return false;
    final start = Offset(
      source.position.dx + source.size.width,
      source.position.dy + source.size.height / 2,
    );
    final end = Offset(
      target.position.dx,
      target.position.dy + target.size.height / 2,
    );
    return Rect.fromPoints(start, end).inflate(160).overlaps(sceneRect);
  }

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          final visibleScene = _visibleSceneRect(viewport);
          final nodesById = {for (final n in widget.nodes) n.id: n};
          final visibleNodes = [
            for (final node in widget.nodes)
              if (_nodeIntersects(node, visibleScene)) node,
          ];
          final visibleEdges = [
            for (final edge in widget.edges)
              if (_edgeIntersects(edge, visibleScene, nodesById)) edge,
          ];
          return InteractiveViewer(
            transformationController: _controller,
            minScale: 0.1,
            maxScale: 10,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(4000),
            child: SizedBox(
              width: 12000,
              height: 8000,
              child: Stack(children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(12000, 8000),
                    painter:
                        _GridPainter(color: df.stroke.withValues(alpha: 0.4)),
                  ),
                ),
                if (visibleEdges.isNotEmpty)
                  RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(12000, 8000),
                      painter: _EdgePainter(
                        edges: visibleEdges,
                        nodes: nodesById,
                      ),
                    ),
                  ),
                for (final node in visibleNodes)
                  Positioned(
                    left: node.position.dx,
                    top: node.position.dy,
                    width: node.size.width,
                    height: node.size.height,
                    child: RepaintBoundary(child: node.child),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 40.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawCircle(Offset(x, 0), 0.8, paint);
    }
    for (var x = 0.0; x < size.width; x += step) {
      for (var y = 0.0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _EdgePainter extends CustomPainter {
  final List<DFCanvasEdge> edges;
  final Map<String, DFCanvasNode> nodes;
  const _EdgePainter({required this.edges, required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final e in edges) {
      final source = nodes[e.sourceId];
      final target = nodes[e.targetId];
      if (source == null || target == null) continue;
      final start = Offset(source.position.dx + source.size.width,
          source.position.dy + source.size.height / 2);
      final end = Offset(
          target.position.dx, target.position.dy + target.size.height / 2);
      final path = Path()..moveTo(start.dx, start.dy);
      final ctrlX = (start.dx + end.dx) / 2;
      path.cubicTo(ctrlX, start.dy, ctrlX, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.edges != edges || oldDelegate.nodes != nodes;
}
