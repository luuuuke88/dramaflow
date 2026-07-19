// 通用无限画布（照抄 @vue-flow/core 行为，Flutter 自绘方案，见
// docs/reference/p3-production-canvas-brief.md §1/§6）：
// InteractiveViewer 负责平移缩放，节点用 Positioned+Stack，边用 CustomPainter
// 画三次贝塞尔曲线。节点位置由调用方管理；提供 onDragUpdate 时，顶部 36px 拖拽区
// 会把屏幕位移换算为场景位移。调用方可将位置保留在当前会话，但不需要落库。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../util/l10n_ext.dart';

class DFCanvasNode {
  final String id;
  final Offset position;
  final Size size;
  final Widget child;
  final ValueChanged<Offset>? onDragUpdate;
  final double dragHandleHeight;
  const DFCanvasNode({
    required this.id,
    required this.position,
    required this.size,
    required this.child,
    this.onDragUpdate,
    this.dragHandleHeight = 36,
  });
}

class DFCanvasEdge {
  final String sourceId;
  final String targetId;
  const DFCanvasEdge({required this.sourceId, required this.targetId});
}

/// 无限画布：平移缩放 0.1–10（对齐 VueFlow 限制）。平移、缩放和惯性由
/// InteractiveViewer 提供；节点拖拽走顶部拖拽区，避免和画布平移冲突。
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
  int? _dragPointer;
  Offset? _lastDragPosition;
  Matrix4? _transformBeforeDrag;

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

  void _startNodeDrag(PointerDownEvent event) {
    setState(() {
      _dragPointer = event.pointer;
      _lastDragPosition = event.position;
      _transformBeforeDrag = Matrix4.copy(_controller.value);
    });
  }

  void _updateNodeDrag(DFCanvasNode node, PointerMoveEvent event) {
    if (_dragPointer != event.pointer || _lastDragPosition == null) return;
    final delta = event.position - _lastDragPosition!;
    _lastDragPosition = event.position;
    // InteractiveViewer may have accepted the first pan update before the
    // title handle disables its gestures. Keep the viewport anchored so a
    // node drag never turns into a simultaneous canvas pan.
    if (_transformBeforeDrag != null) {
      _controller.value = Matrix4.copy(_transformBeforeDrag!);
    }
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale > 0) node.onDragUpdate!(delta / scale);
  }

  void _endNodeDrag(PointerEvent event) {
    if (_dragPointer != event.pointer) return;
    if (_transformBeforeDrag != null) {
      _controller.value = Matrix4.copy(_transformBeforeDrag!);
    }
    setState(() {
      _dragPointer = null;
      _lastDragPosition = null;
      _transformBeforeDrag = null;
    });
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
            panEnabled: _dragPointer == null,
            scaleEnabled: _dragPointer == null,
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
                    child: RepaintBoundary(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          node.child,
                          if (node.onDragUpdate != null)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: node.dragHandleHeight,
                              child: Semantics(
                                label: context.l10n.canvasDragNode(node.id),
                                child: Listener(
                                  key: ValueKey('df-canvas-drag-${node.id}'),
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: _startNodeDrag,
                                  onPointerMove: (event) =>
                                      _updateNodeDrag(node, event),
                                  onPointerUp: _endNodeDrag,
                                  onPointerCancel: _endNodeDrag,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
