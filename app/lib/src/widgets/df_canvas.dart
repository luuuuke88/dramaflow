// 通用无限画布（照抄 @vue-flow/core 行为，Flutter 自绘方案，见
// docs/reference/p3-production-canvas-brief.md §1/§6）：
// 背景手势层负责平移缩放，节点用 Positioned+Stack，边用 CustomPainter 画三次贝塞尔
// 曲线。节点位置由调用方管理；提供 onDragUpdate 时，顶部 36px 拖拽区会把屏幕位移
// 换算为场景位移。背景与节点是命中测试的同级层，保证卡片内的输入控件不被画布抢手势。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// material.dart re-exports rendering.dart with a `show` clause that (as of
// this Flutter version) omits the trackpad PointerPanZoom*EventListener
// typedefs even though the Listener widget itself already exposes
// onPointerPanZoomStart/Update/End — import the full barrel directly so
// _CanvasNodeDragHandlers can name those typedefs explicitly.
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../state/canvas_wheel_mode.dart';
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

/// 只在 Space + 鼠标主键下抢占手势，普通卡片输入不会加入画布的手势竞技场。
class _SpacePanGestureRecognizer extends OneSequenceGestureRecognizer {
  bool Function(PointerDownEvent event)? shouldStart;
  PointerDownEventListener? onStart;
  void Function(PointerMoveEvent event)? onUpdate;
  void Function(PointerEvent event)? onEnd;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && (shouldStart?.call(event) ?? false);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    onStart?.call(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event case PointerMoveEvent moveEvent) onUpdate?.call(moveEvent);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      onEnd?.call(event);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'spaceCanvasPan';
}

/// 仅在第二个触点落下后接受手势，避免单指节点拖拽变成画布平移。
class _TwoFingerCanvasScaleRecognizer extends OneSequenceGestureRecognizer {
  final Map<int, Offset> _positions = {};
  List<int>? _pair;
  Map<int, Offset>? _initialPositions;
  bool _active = false;

  void Function(Offset focalPoint)? onStart;
  void Function(Offset focalPoint, double scale)? onUpdate;
  VoidCallback? onEnd;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && event.kind == PointerDeviceKind.touch;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _positions[event.pointer] = event.localPosition;
    if (_active || _positions.length < 2) return;

    _pair = _positions.keys.take(2).toList(growable: false);
    _initialPositions = {
      for (final pointer in _pair!) pointer: _positions[pointer]!,
    };
    _active = true;
    onStart?.call(_focalPoint(_initialPositions!));
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _positions.containsKey(event.pointer)) {
      if (!_active) {
        _positions.remove(event.pointer);
        resolvePointer(event.pointer, GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
      _positions[event.pointer] = event.localPosition;
      _emitUpdate();
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      final endsActivePair = _active && _pair!.contains(event.pointer);
      _positions.remove(event.pointer);
      if (endsActivePair) _finish();
      if (!_active) resolvePointer(event.pointer, GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  void _emitUpdate() {
    final pair = _pair;
    final initial = _initialPositions;
    if (!_active || pair == null || initial == null) return;
    final first = _positions[pair[0]];
    final second = _positions[pair[1]];
    if (first == null || second == null) return;
    final initialDistance = (initial[pair[0]]! - initial[pair[1]]!).distance;
    if (initialDistance == 0) return;
    onUpdate?.call(
        (first + second) / 2, (first - second).distance / initialDistance);
  }

  Offset _focalPoint(Map<int, Offset> positions) {
    final pair = _pair!;
    return (positions[pair[0]]! + positions[pair[1]]!) / 2;
  }

  void _finish() {
    if (_active) onEnd?.call();
    _active = false;
    _pair = null;
    _initialPositions = null;
  }

  @override
  void rejectGesture(int pointer) {
    _positions.remove(pointer);
    if (_pair?.contains(pointer) ?? false) _finish();
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _finish();
    _positions.clear();
  }

  @override
  String get debugDescription => 'twoFingerCanvasScale';
}

/// Marks a region inside a [DFCanvasNode] as an intentional pointer surface.
///
/// The default moves its node. [movesNode] false keeps both the viewport and
/// node position fixed for interactions inside an editable card region.
class DFCanvasDragRegion extends StatelessWidget {
  final Widget child;
  final bool movesNode;

  const DFCanvasDragRegion({
    super.key,
    required this.child,
    this.movesNode = true,
  });

  @override
  Widget build(BuildContext context) {
    final handlers = _DFCanvasNodeDragScope.maybeOf(context);
    if (handlers == null || !movesNode) return child;
    return Listener(
      onPointerDown: handlers.startNodeDrag,
      onPointerMove: handlers.updateNodeDrag,
      onPointerUp: handlers.endNodeDrag,
      onPointerCancel: handlers.cancelNodeDrag,
      onPointerSignal: handlers.handleViewportPointerSignal,
      onPointerPanZoomStart: handlers.handleViewportPanZoomStart,
      onPointerPanZoomUpdate: handlers.handleViewportPanZoomUpdate,
      onPointerPanZoomEnd: handlers.handleViewportPanZoomEnd,
      child: child,
    );
  }
}

/// 将普通节点卡片上的滚轮信号交还给画布，而不改变节点的拖拽区域。
class DFCanvasViewportSignalRegion extends StatelessWidget {
  final Widget child;

  const DFCanvasViewportSignalRegion({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final handlers = _DFCanvasNodeDragScope.maybeOf(context);
    if (handlers == null) return child;
    return Listener(
      onPointerSignal: handlers.handleViewportPointerSignal,
      onPointerPanZoomStart: handlers.handleViewportPanZoomStart,
      onPointerPanZoomUpdate: handlers.handleViewportPanZoomUpdate,
      onPointerPanZoomEnd: handlers.handleViewportPanZoomEnd,
      child: child,
    );
  }
}

class _CanvasNodeDragHandlers {
  final PointerDownEventListener startNodeDrag;
  final PointerMoveEventListener updateNodeDrag;
  final PointerUpEventListener endNodeDrag;
  final PointerCancelEventListener cancelNodeDrag;
  final void Function(PointerSignalEvent event) handleViewportPointerSignal;
  final PointerPanZoomStartEventListener handleViewportPanZoomStart;
  final PointerPanZoomUpdateEventListener handleViewportPanZoomUpdate;
  final PointerPanZoomEndEventListener handleViewportPanZoomEnd;

  const _CanvasNodeDragHandlers({
    required this.startNodeDrag,
    required this.updateNodeDrag,
    required this.endNodeDrag,
    required this.cancelNodeDrag,
    required this.handleViewportPointerSignal,
    required this.handleViewportPanZoomStart,
    required this.handleViewportPanZoomUpdate,
    required this.handleViewportPanZoomEnd,
  });
}

class _DFCanvasNodeDragScope extends InheritedWidget {
  final _CanvasNodeDragHandlers? handlers;

  const _DFCanvasNodeDragScope({
    required this.handlers,
    required super.child,
  });

  static _CanvasNodeDragHandlers? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DFCanvasNodeDragScope>()
      ?.handlers;

  @override
  bool updateShouldNotify(_DFCanvasNodeDragScope oldWidget) =>
      handlers != oldWidget.handlers;
}

/// 画布视口控制器。
///
/// 保留 [TransformationController] 的缩放和平移 API，并额外提供由 [DFCanvas]
/// 在挂载期间注册的 [fitView]。未挂载时调用是安全的空操作。
class DFCanvasController extends TransformationController {
  VoidCallback? _fitView;

  void fitView() => _fitView?.call();

  void _attachFitView(VoidCallback callback) => _fitView = callback;

  void _detachFitView(VoidCallback callback) {
    if (_fitView == callback) _fitView = null;
  }
}

/// 无限画布：平移缩放 0.1–10（对齐 VueFlow 限制）。背景手势与节点内容分层，
/// 所以节点拖拽、文本编辑和画布平移不会进入同一个手势竞技场。
class DFCanvas extends StatefulWidget {
  final List<DFCanvasNode> nodes;
  final List<DFCanvasEdge> edges;
  final TransformationController? controller;
  final bool fitOnInit;
  final CanvasWheelMode wheelMode;
  final bool interactionReductionEnabled;

  const DFCanvas({
    super.key,
    required this.nodes,
    this.edges = const [],
    this.controller,
    this.fitOnInit = true,
    this.wheelMode = CanvasWheelMode.zoom,
    this.interactionReductionEnabled = false,
  });

  @override
  State<DFCanvas> createState() => _DFCanvasState();
}

class _DFCanvasState extends State<DFCanvas> {
  late TransformationController _controller;
  late bool _ownsController;
  bool _fitted = false;
  int? _dragPointer;
  int? _pendingNodeDragPointer;
  Offset? _lastDragPosition;
  int? _spacePanPointer;
  Offset? _spacePanOrigin;
  Matrix4? _transformBeforeSpacePan;
  Matrix4? _transformBeforeViewportGesture;
  Offset? _viewportGestureOrigin;
  bool _twoFingerPinchActive = false;
  Timer? _interactionRecovery;
  bool _isInteracting = false;
  int? _nodePanZoomPointer;
  Offset? _nodePanZoomStartPosition;
  Object? _handledPanZoomUpdateId;

  @override
  void initState() {
    super.initState();
    _setController(widget.controller);
    if (widget.fitOnInit && widget.nodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitView());
    }
  }

  @override
  void dispose() {
    _interactionRecovery?.cancel();
    _releaseController();
    super.dispose();
  }

  void _setController(TransformationController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? TransformationController();
    _controller.addListener(_handleTransformChanged);
    if (_controller case final DFCanvasController canvasController) {
      canvasController._attachFitView(_fitView);
    }
  }

  void _releaseController() {
    if (_controller case final DFCanvasController canvasController) {
      canvasController._detachFitView(_fitView);
    }
    _controller.removeListener(_handleTransformChanged);
    if (_ownsController) _controller.dispose();
  }

  void _handleTransformChanged() {
    if (mounted) setState(() {});
  }

  void _beginInteraction() {
    if (!widget.interactionReductionEnabled) return;
    _interactionRecovery?.cancel();
    if (_isInteracting) return;
    setState(() => _isInteracting = true);
  }

  void _endInteractionAfterDelay() {
    if (!widget.interactionReductionEnabled || !_isInteracting) return;
    _interactionRecovery?.cancel();
    _interactionRecovery = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _isInteracting = false);
    });
  }

  void _clearInteractionReduction() {
    _interactionRecovery?.cancel();
    _interactionRecovery = null;
    if (_isInteracting) setState(() => _isInteracting = false);
  }

  void _startNodeDrag(PointerDownEvent event) {
    if ((event.kind == PointerDeviceKind.mouse &&
            event.buttons != kPrimaryMouseButton) ||
        _dragPointer != null ||
        _pendingNodeDragPointer != null ||
        _spacePanPointer != null ||
        _twoFingerPinchActive ||
        (event.kind == PointerDeviceKind.mouse &&
            HardwareKeyboard.instance
                .isLogicalKeyPressed(LogicalKeyboardKey.space))) {
      return;
    }
    _pendingNodeDragPointer = event.pointer;
    _lastDragPosition = event.position;
  }

  void _updateNodeDrag(DFCanvasNode node, PointerMoveEvent event) {
    if (_twoFingerPinchActive) return;
    if (_dragPointer == null) {
      if (_pendingNodeDragPointer != event.pointer) return;
      if (_spacePanPointer != null ||
          (event.kind == PointerDeviceKind.mouse &&
              HardwareKeyboard.instance
                  .isLogicalKeyPressed(LogicalKeyboardKey.space))) {
        _pendingNodeDragPointer = null;
        _lastDragPosition = null;
        return;
      }
      _dragPointer = event.pointer;
      _pendingNodeDragPointer = null;
      _beginInteraction();
    }
    if (_dragPointer != event.pointer || _lastDragPosition == null) return;
    final delta = event.position - _lastDragPosition!;
    _lastDragPosition = event.position;
    // Matrix4 的 Z 轴固定为 1；getMaxScaleOnAxis 在缩小视图时会误取该轴。
    // 画布不允许旋转，取两个平面轴即可得到真实的画布缩放。
    final storage = _controller.value.storage;
    final scale = math.max(storage[0].abs(), storage[5].abs());
    if (scale > 0) node.onDragUpdate!(delta / scale);
  }

  void _endNodeDrag(PointerEvent event) {
    final wasDragging = _dragPointer == event.pointer;
    if (_dragPointer == event.pointer) {
      _dragPointer = null;
      _lastDragPosition = null;
    }
    if (wasDragging) _endInteractionAfterDelay();
    if (_pendingNodeDragPointer == event.pointer) {
      _pendingNodeDragPointer = null;
      _lastDragPosition = null;
    }
  }

  void _startSpacePan(PointerDownEvent event) {
    if (!_shouldStartSpacePan(event)) {
      return;
    }
    _spacePanPointer = event.pointer;
    _spacePanOrigin = event.position;
    _transformBeforeSpacePan = Matrix4.copy(_controller.value);
  }

  bool _shouldStartSpacePan(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.mouse &&
      event.buttons == kPrimaryMouseButton &&
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  void _updateSpacePan(PointerMoveEvent event) {
    if (_spacePanPointer != event.pointer ||
        _spacePanOrigin == null ||
        _transformBeforeSpacePan == null) {
      return;
    }
    _beginInteraction();
    final delta = event.position - _spacePanOrigin!;
    final transform = Matrix4.copy(_transformBeforeSpacePan!);
    transform.storage[12] += delta.dx;
    transform.storage[13] += delta.dy;
    _controller.value = transform;
  }

  void _endSpacePan(PointerEvent event) {
    if (_spacePanPointer != event.pointer) return;
    _spacePanPointer = null;
    _spacePanOrigin = null;
    _transformBeforeSpacePan = null;
    _endInteractionAfterDelay();
  }

  double _canvasScale(Matrix4 transform) =>
      math.max(transform.storage[0].abs(), transform.storage[5].abs());

  void _startViewportTransform(Offset focalPoint) {
    _transformBeforeViewportGesture = Matrix4.copy(_controller.value);
    _viewportGestureOrigin = focalPoint;
  }

  void _updateViewportTransform(Offset focalPoint, double gestureScale) {
    final initial = _transformBeforeViewportGesture;
    final origin = _viewportGestureOrigin;
    if (initial == null || origin == null || _spacePanPointer != null) return;

    final initialScale = _canvasScale(initial);
    if (initialScale <= 0) return;
    if (gestureScale != 1 || focalPoint != origin) _beginInteraction();
    final targetScale =
        (initialScale * gestureScale).clamp(0.1, 10.0).toDouble();
    final factor = targetScale / initialScale;
    final transform = Matrix4.copy(initial);
    transform.storage[0] = initial.storage[0] * factor;
    transform.storage[5] = initial.storage[5] * factor;
    transform.storage[12] =
        focalPoint.dx - (origin.dx - initial.storage[12]) * factor;
    transform.storage[13] =
        focalPoint.dy - (origin.dy - initial.storage[13]) * factor;
    _controller.value = transform;
  }

  void _startViewportGesture(ScaleStartDetails details) {
    if (_spacePanPointer != null ||
        _twoFingerPinchActive ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.space)) {
      return;
    }
    _startViewportTransform(details.localFocalPoint);
  }

  void _updateViewportGesture(ScaleUpdateDetails details) {
    _updateViewportTransform(details.localFocalPoint, details.scale);
  }

  void _endViewportGesture(ScaleEndDetails details) {
    _transformBeforeViewportGesture = null;
    _viewportGestureOrigin = null;
    _endInteractionAfterDelay();
  }

  void _startTwoFingerViewportGesture(Offset focalPoint) {
    _dragPointer = null;
    _pendingNodeDragPointer = null;
    _lastDragPosition = null;
    _twoFingerPinchActive = true;
    _startViewportTransform(focalPoint);
  }

  void _updateTwoFingerViewportGesture(Offset focalPoint, double scale) {
    _updateViewportTransform(focalPoint, scale);
  }

  void _endTwoFingerViewportGesture() {
    _twoFingerPinchActive = false;
    _transformBeforeViewportGesture = null;
    _viewportGestureOrigin = null;
    _endInteractionAfterDelay();
  }

  Offset _localPositionOf(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(globalPosition) ?? globalPosition;
  }

  Offset _viewportPositionOf(PointerEvent event) =>
      _localPositionOf(event.position);

  /// 触控板双指手势(PointerPanZoomStart/Update/End)是独立于 PointerSignalEvent
  /// 的事件族，走正常指针路由而不是信号派发，背景层 Positioned.fill 上的
  /// ScaleGestureRecognizer(约构建方法里 698 行前后)已经能正确处理它——但只有
  /// 手势起点落在空白画布时才轮得到它:节点卡片的可见内容(Text/Image 等)
  /// hitTestSelf 恒为 true，命中测试会在 Stack 同级的节点内容分支处停下，
  /// 背景层这个兄弟分支根本收不到事件。这里复用"滚轮事件已经从节点层转发给
  /// 背景层处理函数"的同一思路(见 _registerBackgroundPointerSignal 的调用方:
  /// 标题拖拽条、DFCanvasDragRegion、DFCanvasViewportSignalRegion)，让这些
  /// 已经位于节点不透明内容之上的 Listener 也转发 PanZoom 事件，驱动同一套
  /// _startViewportTransform/_updateViewportTransform 画布变换逻辑。
  ///
  /// 同一次命中测试路径上可能有多个转发 Listener 同时收到同一个事件(和 Bug 1
  /// 滚轮重复触发同一根因)，但 PointerSignalResolver 只认 PointerSignalEvent。
  /// 这里手动做等价的去重:起点用 pointer 互斥(先到先得，见
  /// _handleNodePanZoomStart)；更新用 event.original 识别"这是不是同一个物理
  /// 事件的重复派发"(写法参考 SDK pointer_signal_resolver.dart 里的
  /// _isSameEvent)，避免同一帧被处理两次。
  void _handleNodePanZoomStart(PointerPanZoomStartEvent event) {
    if (_nodePanZoomPointer != null ||
        _spacePanPointer != null ||
        _twoFingerPinchActive) {
      return;
    }
    _nodePanZoomPointer = event.pointer;
    _nodePanZoomStartPosition = event.position;
    _startViewportTransform(_viewportPositionOf(event));
  }

  void _handleNodePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final start = _nodePanZoomStartPosition;
    if (_nodePanZoomPointer != event.pointer || start == null) return;
    final eventId = event.original ?? event;
    if (identical(_handledPanZoomUpdateId, eventId)) return;
    _handledPanZoomUpdateId = eventId;
    // Bug 3: 和背景层 ScaleGestureRecognizer 上设置的 trackpadScrollCausesScale
    // 读取同一个 widget.wheelMode，两条路径(起点在空白画布 vs 起点在节点上)
    // 对触控板手势的解读必须一致。causesScale 为 true 时公式抄自 SDK
    // scale.dart 的 _PointerPanZoomData:焦点固定在手势起点，pan 量按
    // kDefaultTrackpadScrollToScaleFactor 换算成指数缩放；为 false 时保持原来
    // 的纯平移语义(焦点 = 起点 + 累计 pan，scale 恒为手势自身的 event.scale)。
    final causesScale = widget.wheelMode == CanvasWheelMode.zoom;
    final focalGlobal = causesScale ? start : start + event.pan;
    final gestureScale = causesScale
        ? event.scale *
            math.exp(event.pan.dx * kDefaultTrackpadScrollToScaleFactor.dx +
                event.pan.dy * kDefaultTrackpadScrollToScaleFactor.dy)
        : event.scale;
    _updateViewportTransform(_localPositionOf(focalGlobal), gestureScale);
  }

  void _handleNodePanZoomEnd(PointerPanZoomEndEvent event) {
    if (_nodePanZoomPointer != event.pointer) return;
    _nodePanZoomPointer = null;
    _nodePanZoomStartPosition = null;
    _handledPanZoomUpdateId = null;
    _endViewportGesture(ScaleEndDetails());
  }

  /// 三个转发点(背景层自身、标题拖拽条、卡片内的 DFCanvasDragRegion /
  /// DFCanvasViewportSignalRegion)在同一次命中测试里可能同时出现在事件路径上
  /// ——标题条用 HitTestBehavior.translucent，即使它自己没吸收命中也仍会被计入
  /// 路径，卡片内容随后可能各自再命中一次。PointerSignalEvent 的派发会把信号
  /// 送达路径上的每一个 Listener，不会像手势竞技场那样只有一个胜者，所以必须
  /// 显式登记到 PointerSignalResolver 去重，让同一个滚轮事件只被处理一次——
  /// 这正是 Flutter 自己的 Scrollable 组件(见 SDK scrollable.dart 里的
  /// _receivedPointerSignal/_handlePointerScroll)在嵌套滚动场景下使用的标准
  /// 写法，也让画布和卡片内嵌套的 ListView/Scrollable 互斥。
  void _registerBackgroundPointerSignal(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver
        .register(event, _handleBackgroundPointerSignal);
  }

  void _handleBackgroundPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _spacePanPointer != null) return;
    final transform = Matrix4.copy(_controller.value);
    if (widget.wheelMode == CanvasWheelMode.scroll) {
      if (event.scrollDelta == Offset.zero) return;
      _beginInteraction();
      transform.storage[12] -= event.scrollDelta.dx;
      transform.storage[13] -= event.scrollDelta.dy;
      _controller.value = transform;
      _endInteractionAfterDelay();
      return;
    }
    if (event.scrollDelta.dy == 0) return;
    final scale = _canvasScale(transform);
    if (scale <= 0) return;
    _beginInteraction();
    final targetScale =
        (scale * math.exp(-event.scrollDelta.dy / 200)).clamp(0.1, 10.0);
    final factor = targetScale / scale;
    transform.storage[0] *= factor;
    transform.storage[5] *= factor;
    final focalPoint = _viewportPositionOf(event);
    transform.storage[12] =
        focalPoint.dx - (focalPoint.dx - transform.storage[12]) * factor;
    transform.storage[13] =
        focalPoint.dy - (focalPoint.dy - transform.storage[13]) * factor;
    _controller.value = transform;
    _endInteractionAfterDelay();
  }

  @override
  void didUpdateWidget(covariant DFCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _releaseController();
      _setController(widget.controller);
    }
    if (oldWidget.interactionReductionEnabled &&
        !widget.interactionReductionEnabled) {
      _clearInteractionReduction();
    }
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
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _SpacePanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_SpacePanGestureRecognizer>(
          _SpacePanGestureRecognizer.new,
          (recognizer) {
            recognizer.shouldStart = _shouldStartSpacePan;
            recognizer.onStart = _startSpacePan;
            recognizer.onUpdate = _updateSpacePan;
            recognizer.onEnd = _endSpacePan;
          },
        ),
        _TwoFingerCanvasScaleRecognizer: GestureRecognizerFactoryWithHandlers<
            _TwoFingerCanvasScaleRecognizer>(
          _TwoFingerCanvasScaleRecognizer.new,
          (recognizer) {
            recognizer.onStart = _startTwoFingerViewportGesture;
            recognizer.onUpdate = _updateTwoFingerViewportGesture;
            recognizer.onEnd = _endTwoFingerViewportGesture;
          },
        ),
      },
      child: ClipRect(
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
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerSignal: _registerBackgroundPointerSignal,
                    child: RawGestureDetector(
                      key: const ValueKey('df-canvas-background'),
                      behavior: HitTestBehavior.opaque,
                      gestures: {
                        ScaleGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                ScaleGestureRecognizer>(
                          () => ScaleGestureRecognizer(
                            allowedButtonsFilter: (buttons) =>
                                buttons == kPrimaryButton,
                          ),
                          (recognizer) {
                            recognizer.onStart = _startViewportGesture;
                            recognizer.onUpdate = _updateViewportGesture;
                            recognizer.onEnd = _endViewportGesture;
                            // Bug 3: 触控板双指默认被 ScaleGestureRecognizer 当成
                            // 平移(trackpadScrollCausesScale 默认 false)，从不
                            // 查询画布自己的 wheelMode 设置。这里让它和现有
                            // PointerScrollEvent 分支(_handleBackgroundPointerSignal
                            // 里 widget.wheelMode == CanvasWheelMode.scroll 的判断)
                            // 保持同一套读取方式，缩放模式下让触控板双指也走缩放。
                            recognizer.trackpadScrollCausesScale =
                                widget.wheelMode == CanvasWheelMode.zoom;
                          },
                        ),
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 12000,
                  maxWidth: 12000,
                  minHeight: 8000,
                  maxHeight: 8000,
                  child: Transform(
                    alignment: Alignment.topLeft,
                    transform: _controller.value,
                    child: SizedBox(
                      width: 12000,
                      height: 8000,
                      child: Stack(children: [
                        RepaintBoundary(
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: const Size(12000, 8000),
                              painter: _GridPainter(
                                  color: df.stroke.withValues(alpha: 0.4)),
                            ),
                          ),
                        ),
                        if (visibleEdges.isNotEmpty)
                          RepaintBoundary(
                            child: IgnorePointer(
                              child: CustomPaint(
                                size: const Size(12000, 8000),
                                painter: _EdgePainter(
                                  edges: visibleEdges,
                                  nodes: nodesById,
                                ),
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
                                  _DFCanvasNodeDragScope(
                                    handlers: node.onDragUpdate == null
                                        ? null
                                        : _CanvasNodeDragHandlers(
                                            startNodeDrag: _startNodeDrag,
                                            updateNodeDrag: (event) =>
                                                _updateNodeDrag(node, event),
                                            endNodeDrag: _endNodeDrag,
                                            cancelNodeDrag: _endNodeDrag,
                                            handleViewportPointerSignal:
                                                _registerBackgroundPointerSignal,
                                            handleViewportPanZoomStart:
                                                _handleNodePanZoomStart,
                                            handleViewportPanZoomUpdate:
                                                _handleNodePanZoomUpdate,
                                            handleViewportPanZoomEnd:
                                                _handleNodePanZoomEnd,
                                          ),
                                    child: _isInteracting &&
                                            widget.interactionReductionEnabled
                                        ? TickerMode(
                                            enabled: false,
                                            child: IgnorePointer(
                                                child: node.child),
                                          )
                                        : node.child,
                                  ),
                                  if (node.onDragUpdate != null)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      height: node.dragHandleHeight,
                                      child: Semantics(
                                        label: context.l10n
                                            .canvasDragNode(node.id),
                                        child: Listener(
                                          key: ValueKey(
                                              'df-canvas-drag-${node.id}'),
                                          behavior: HitTestBehavior.translucent,
                                          onPointerDown: _startNodeDrag,
                                          onPointerMove: (event) =>
                                              _updateNodeDrag(node, event),
                                          onPointerUp: _endNodeDrag,
                                          onPointerCancel: _endNodeDrag,
                                          onPointerSignal:
                                              _registerBackgroundPointerSignal,
                                          onPointerPanZoomStart:
                                              _handleNodePanZoomStart,
                                          onPointerPanZoomUpdate:
                                              _handleNodePanZoomUpdate,
                                          onPointerPanZoomEnd:
                                              _handleNodePanZoomEnd,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
