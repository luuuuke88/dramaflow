import 'dart:ui' show PointerDeviceKind;

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/state/canvas_wheel_mode.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/theme/tokens.dart';
import 'package:dramaflow/src/widgets/df_adaptive_dialog.dart';
import 'package:dramaflow/src/widgets/df_canvas.dart';
import 'package:dramaflow/src/widgets/df_data_table.dart';
import 'package:dramaflow/src/widgets/df_status_tag.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setLogicalSize(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget themed(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      theme: buildTheme(Brightness.light),
      home: child,
    );
  }

  test('canvas wheel mode is session-only and starts at zoom', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(canvasWheelModeProvider), CanvasWheelMode.zoom);
    container
        .read(canvasWheelModeProvider.notifier)
        .setMode(CanvasWheelMode.scroll);
    expect(container.read(canvasWheelModeProvider), CanvasWheelMode.scroll);
  });

  testWidgets('DFDataTable renders desktop table at 900px', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    var mobileBuilds = 0;

    await tester.pumpWidget(themed(DFDataTable(
      columns: const [DFDataColumn(label: '名称')],
      rows: const [
        DFDataRow(id: 'row-1', cells: [Text('第一行')]),
      ],
      mobileCardBuilder: (context, row) {
        mobileBuilds += 1;
        return Text('mobile ${row.id}');
      },
    )));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('第一行'), findsOneWidget);
    expect(mobileBuilds, 0);
  });

  testWidgets('DFDataTable renders mobile cards at 380px', (tester) async {
    await setLogicalSize(tester, const Size(380, 600));
    var mobileBuilds = 0;

    await tester.pumpWidget(themed(DFDataTable(
      columns: const [DFDataColumn(label: '名称')],
      rows: const [
        DFDataRow(id: 'row-1', cells: [Text('第一行')]),
      ],
      mobileCardBuilder: (context, row) {
        mobileBuilds += 1;
        return Text('mobile ${row.id}');
      },
    )));

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('mobile row-1'), findsOneWidget);
    expect(mobileBuilds, 1);
  });

  testWidgets('DFStatusTag processing contains progress indicator',
      (tester) async {
    await tester.pumpWidget(themed(
      const Center(child: DFStatusTag(kind: DFStatusKind.processing)),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('showDFAdaptiveDialog uses desktop Dialog at 900px',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));

    await tester.pumpWidget(themed(Builder(builder: (context) {
      return TextButton(
        onPressed: () => showDFAdaptiveDialog<void>(
          context,
          title: '标题',
          builder: (_) => const Text('内容'),
        ),
        child: const Text('打开'),
      );
    })));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('showDFAdaptiveDialog uses fullscreen Scaffold at 380px',
      (tester) async {
    await setLogicalSize(tester, const Size(380, 600));

    await tester.pumpWidget(themed(Builder(builder: (context) {
      return TextButton(
        onPressed: () => showDFAdaptiveDialog<void>(
          context,
          title: '标题',
          builder: (_) => const Text('内容'),
        ),
        child: const Text('打开'),
      );
    })));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
  });

  test('DFColors light primary matches design token', () {
    expect(DFColors.light().primary, const Color(0xFF414CB2));
  });

  testWidgets('DFCanvas culls offscreen nodes in a 1000-node canvas',
      (tester) async {
    await setLogicalSize(tester, const Size(1200, 900));
    final controller = TransformationController();
    final built = <int>[];
    final nodes = List.generate(1000, (i) {
      final col = i % 40;
      final row = i ~/ 40;
      return DFCanvasNode(
        id: 'n$i',
        position: Offset(col * 260.0, row * 160.0),
        size: const Size(160, 80),
        child: Builder(builder: (context) {
          built.add(i);
          return Text('N$i');
        }),
      );
    });
    final edges = [
      for (var i = 0; i < 999; i++)
        DFCanvasEdge(sourceId: 'n$i', targetId: 'n${i + 1}'),
    ];

    await tester.pumpWidget(themed(SizedBox(
      width: 1200,
      height: 900,
      child: DFCanvas(
        nodes: nodes,
        edges: edges,
        controller: controller,
        fitOnInit: false,
      ),
    )));

    expect(find.text('N0'), findsOneWidget);
    expect(find.text('N999'), findsNothing);
    expect(built.length, lessThan(120));

    controller.value = Matrix4.identity()
      ..translateByDouble(-10000, -3700, 0, 1);
    await tester.pump();

    expect(find.text('N999'), findsOneWidget);
    expect(find.text('N0'), findsNothing);
  });

  testWidgets('DFCanvas 桌面空白区鼠标拖拽会平移画布', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = (Matrix4.identity()
        ..setEntry(0, 3, 12)
        ..setEntry(1, 3, 15));

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: const [],
      ),
    )));

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('df-canvas-background'))),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(40, 20));
    await drag.up();
    await tester.pump();

    expect(controller.value.storage[12], closeTo(52, 0.1));
    expect(controller.value.storage[13], closeTo(35, 0.1));
  });

  testWidgets('DFCanvas 空白区鼠标右键拖拽不平移画布', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = (Matrix4.identity()
        ..setEntry(0, 3, 12)
        ..setEntry(1, 3, 15));

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: const [],
      ),
    )));

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('df-canvas-background'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await drag.moveBy(const Offset(40, 20));
    await drag.up();
    await tester.pump();

    expect(controller.value.storage[12], closeTo(12, 0.1));
    expect(controller.value.storage[13], closeTo(15, 0.1));
  });

  testWidgets('DFCanvas 移动端双指缩放保持识别起点的场景坐标', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: const [],
      ),
    )));

    final first = await tester.startGesture(const Offset(300, 250), pointer: 1);
    final second =
        await tester.startGesture(const Offset(400, 250), pointer: 2);
    await first.moveTo(const Offset(250, 250));
    await second.moveTo(const Offset(450, 250));
    await second.up();
    await first.up();
    await tester.pump();

    expect(controller.value.storage[0], closeTo(2, 0.1));
    expect(controller.value.storage[5], closeTo(2, 0.1));
    // 统一的双指识别器在第二个触点落下时以 350,250 建立缩放原点，场景点仍须
    // 跟随最终焦点，而不是被固定在原来的屏幕坐标。
    expect(controller.toScene(const Offset(350, 250)).dx, closeTo(350, 0.1));
    expect(controller.toScene(const Offset(350, 250)).dy, closeTo(250, 0.1));
  });

  testWidgets('DFCanvas 双指从节点上开始时缩放画布而非拖动节点', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();
    final nodeDeltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'pinch-node',
            position: const Offset(180, 160),
            size: const Size(360, 180),
            onDragUpdate: nodeDeltas.add,
            child: const DFCanvasDragRegion(
              child: ColoredBox(
                key: ValueKey('canvas-pinch-node'),
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    )));

    final first = await tester.startGesture(const Offset(300, 240), pointer: 1);
    final second =
        await tester.startGesture(const Offset(400, 240), pointer: 2);
    await first.moveTo(const Offset(250, 240));
    await second.moveTo(const Offset(450, 240));
    await second.up();
    await first.up();
    await tester.pump();

    expect(controller.value.storage[0], closeTo(2, 0.1));
    expect(controller.value.storage[5], closeTo(2, 0.1));
    expect(nodeDeltas, isEmpty);
  });

  testWidgets('DFCanvas 鼠标滚轮缩放保持鼠标焦点', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: const [],
      ),
    )));

    const focalPoint = Offset(450, 300);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(focalPoint);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();

    expect(controller.value.storage[0], closeTo(0.6065, 0.001));
    expect(controller.value.storage[5], closeTo(0.6065, 0.001));
    expect(controller.toScene(focalPoint).dx, closeTo(focalPoint.dx, 0.1));
    expect(controller.toScene(focalPoint).dy, closeTo(focalPoint.dy, 0.1));
  });

  testWidgets('DFCanvas 可拖拽卡片区域的鼠标滚轮同样缩放画布', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'scroll-card',
            position: Offset(180, 160),
            size: Size(240, 120),
            onDragUpdate: (_) {},
            child: DFCanvasDragRegion(
              child: ColoredBox(
                key: ValueKey('canvas-scroll-card'),
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    )));

    final card = find.byKey(const ValueKey('canvas-scroll-card'));
    expect(card.hitTestable(), findsOneWidget);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(card));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();

    expect(controller.value.storage[0], closeTo(0.6065, 0.001));
  });

  testWidgets('DFCanvas 节点内容区域的鼠标滚轮同样缩放画布', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'signal-card',
            position: const Offset(180, 160),
            size: const Size(240, 120),
            onDragUpdate: (_) {},
            child: const DFCanvasViewportSignalRegion(
              child: ColoredBox(
                key: ValueKey('canvas-signal-card'),
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    )));

    final card = find.byKey(const ValueKey('canvas-signal-card'));
    expect(card.hitTestable(), findsOneWidget);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(card));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();

    expect(controller.value.storage[0], closeTo(0.6065, 0.001));
  });

  testWidgets('DFCanvas 变换后节点内容滚轮缩放仍保持真实鼠标焦点', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = (Matrix4.diagonal3Values(2, 2, 1)
        ..setEntry(0, 3, 20)
        ..setEntry(1, 3, 30));

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'transformed-signal-card',
            position: const Offset(80, 80),
            size: const Size(240, 120),
            onDragUpdate: (_) {},
            child: const DFCanvasViewportSignalRegion(
              child: ColoredBox(
                key: ValueKey('canvas-transformed-signal-card'),
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    )));

    final card = find.byKey(const ValueKey('canvas-transformed-signal-card'));
    final cursor = tester.getCenter(card);
    final scenePointBefore = controller.toScene(cursor);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();

    final scenePointAfter = controller.toScene(cursor);
    expect(scenePointAfter.dx, closeTo(scenePointBefore.dx, 0.1));
    expect(scenePointAfter.dy, closeTo(scenePointBefore.dy, 0.1));
  });

  // Bug 4 修复:flutter_test 的 TestPointer.scroll() 无论构造时传入什么
  // PointerDeviceKind,产出的都是 PointerScrollEvent(鼠标滚轮语义)——SDK
  // test_pointer.dart 原文是 "scroll wheel scroll, not finger-drag scroll"。
  // 用 PointerDeviceKind.trackpad 调它只是给滚轮事件贴了个 trackpad 标签，并
  // 没有真正走触控板的 PointerPanZoomStart/Update/End 事件流，测不到 Bug 2/3
  // 描述的真实触控板路径。下面两个测试改用 panZoomStart/panZoomUpdate(pan:
  // ...)/panZoomEnd()——SDK 同一份源码明确要求用这组 API 模拟真实触控板输入，
  // 对 trackpad kind 的指针调用 .down()/.scroll() 会直接触发断言失败。
  testWidgets(
      'DFCanvas zoom mode lets trackpad scrolling zoom around its focal point',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: const [],
      ),
    )));

    const focalPoint = Offset(450, 300);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(focalPoint));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(focalPoint, pan: const Offset(0, 100)));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    expect(controller.value.storage[0], closeTo(0.6065, 0.001));
    expect(controller.value.storage[5], closeTo(0.6065, 0.001));
    expect(controller.toScene(focalPoint).dx, closeTo(focalPoint.dx, 0.1));
    expect(controller.toScene(focalPoint).dy, closeTo(focalPoint.dy, 0.1));
  });

  testWidgets('DFCanvas scroll mode pans mouse and trackpad signals',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        wheelMode: CanvasWheelMode.scroll,
        nodes: const [],
      ),
    )));

    final mouse = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(const Offset(450, 300));
    await tester.sendEventToBinding(mouse.scroll(const Offset(20, 100)));
    await tester.pump();

    expect(controller.value.storage[0], 1);
    expect(controller.value.storage[5], 1);
    expect(controller.value.storage[12], closeTo(-20, 0.1));
    expect(controller.value.storage[13], closeTo(-100, 0.1));

    // 触控板双指平移的 pan 语义和鼠标滚轮的 scrollDelta 方向相反(内容跟随
    // 手指移动，而不是像滚轮那样朝滚动方向的反方向滚)，所以这里 pan 取值和
    // 上面鼠标部分的 scrollDelta 符号相反，但产生的最终矩阵断言保持不变，
    // 验证的是同一个"scroll 模式下触控板也走平移而不是缩放"的行为。
    final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(
        trackpad.panZoomStart(const Offset(450, 300)));
    await tester.sendEventToBinding(trackpad.panZoomUpdate(
      const Offset(450, 300),
      pan: const Offset(12, -18),
    ));
    await tester.sendEventToBinding(trackpad.panZoomEnd());
    await tester.pump();

    expect(controller.value.storage[0], closeTo(1, 0.001));
    expect(controller.value.storage[5], closeTo(1, 0.001));
    expect(controller.value.storage[12], closeTo(-8, 0.1));
    expect(controller.value.storage[13], closeTo(-118, 0.1));
  });

  testWidgets(
      'DFCanvas 滚轮滚过节点标题栏与卡片主体产生相同的单次缩放量(Bug 1 回归)',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();
    const nodePosition = Offset(180, 160);
    const nodeSize = Size(240, 120);

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'title-overlap',
            position: nodePosition,
            size: nodeSize,
            onDragUpdate: (_) {},
            // 完整卡片(含自身约 30px 标题 Text)整体包在 DFCanvasDragRegion
            // 里，和 DFCanvas 自动加的 36px 标题拖拽条在屏幕上重叠——这正是
            // Bug 1 的真实触发形状:同一次命中测试路径里会有两个 Listener
            // 都收到同一个滚轮信号。
            child: DFCanvasDragRegion(
              child: ColoredBox(
                key: const ValueKey('title-overlap-card'),
                color: Colors.blue,
                child: Column(children: [
                  const SizedBox(
                    height: 30,
                    child: Center(
                      child:
                          Text('节点标题', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  Expanded(child: Container()),
                ]),
              ),
            ),
          ),
        ],
      ),
    )));

    final titleStripPoint = Offset(
        nodePosition.dx + nodeSize.width / 2, nodePosition.dy + 15);
    final titlePointer = TestPointer(1, PointerDeviceKind.mouse);
    titlePointer.hover(titleStripPoint);
    await tester.sendEventToBinding(titlePointer.scroll(const Offset(0, 100)));
    await tester.pump();
    final titleScale = controller.value.storage[0];

    controller.value = Matrix4.identity();
    await tester.pump();

    final bodyPoint =
        tester.getCenter(find.byKey(const ValueKey('title-overlap-card')));
    final bodyPointer = TestPointer(2, PointerDeviceKind.mouse);
    bodyPointer.hover(bodyPoint);
    await tester.sendEventToBinding(bodyPointer.scroll(const Offset(0, 100)));
    await tester.pump();
    final bodyScale = controller.value.storage[0];

    // 双重触发时观察到的是 exp(-1) ≈ 0.3679(两次 exp(-0.5) 叠乘)；
    // 单次正确触发应为 exp(-0.5) ≈ 0.6065，且标题栏和卡片主体应完全一致。
    expect(titleScale, closeTo(0.6065, 0.001));
    expect(bodyScale, closeTo(0.6065, 0.001));
    expect(titleScale, closeTo(bodyScale, 0.0001));
  });

  testWidgets(
      'DFCanvas 触控板双指手势从卡片文字内容上方开始时画布同样响应(Bug 2 回归)',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'trackpad-text-card',
            position: const Offset(180, 160),
            size: const Size(240, 120),
            onDragUpdate: (_) {},
            child: const DFCanvasViewportSignalRegion(
              child: ColoredBox(
                color: Colors.blue,
                child: Center(
                  child: Text(
                    '卡片正文内容',
                    key: ValueKey('trackpad-text-card-label'),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    )));

    final textFinder = find.byKey(const ValueKey('trackpad-text-card-label'));
    expect(textFinder.hitTestable(), findsOneWidget);
    final start = tester.getCenter(textFinder);

    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(start));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(start, pan: const Offset(-30, -20)));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    // 起点落在 RenderParagraph(Text)可见内容正上方；修复前背景层的
    // ScaleGestureRecognizer 命中测试不到，矩阵会纹丝不动等于单位矩阵。
    expect(controller.value, isNot(Matrix4.identity()));
  });

  testWidgets('DFCanvas wheelMode 决定节点上方触控板手势是缩放还是平移(Bug 3 回归)',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));

    Future<TransformationController> pumpAndPan(CanvasWheelMode mode) async {
      final controller = TransformationController();
      await tester.pumpWidget(themed(SizedBox(
        width: 900,
        height: 600,
        child: DFCanvas(
          controller: controller,
          fitOnInit: false,
          wheelMode: mode,
          nodes: [
            DFCanvasNode(
              id: 'wheel-mode-card',
              position: const Offset(180, 160),
              size: const Size(240, 120),
              onDragUpdate: (_) {},
              child: const DFCanvasViewportSignalRegion(
                child: ColoredBox(
                  key: ValueKey('wheel-mode-card-body'),
                  color: Colors.blue,
                  child: Text('内容'),
                ),
              ),
            ),
          ],
        ),
      )));

      final start =
          tester.getCenter(find.byKey(const ValueKey('wheel-mode-card-body')));
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(start));
      await tester
          .sendEventToBinding(pointer.panZoomUpdate(start, pan: const Offset(0, 60)));
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();
      return controller;
    }

    final zoomController = await pumpAndPan(CanvasWheelMode.zoom);
    expect(zoomController.value.storage[0], isNot(closeTo(1, 0.001)));

    final scrollController = await pumpAndPan(CanvasWheelMode.scroll);
    expect(scrollController.value.storage[0], closeTo(1, 0.001));
    expect(scrollController.value.storage[13], closeTo(60, 0.1));
  });

  testWidgets('DFCanvas title handle moves a node in scene coordinates',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = Matrix4.diagonal3Values(2, 2, 1);
    final deltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'movable',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ],
      ),
    )));

    await tester.drag(
      find.byKey(const ValueKey('df-canvas-drag-movable')),
      const Offset(40, 20),
    );

    final total = deltas.fold(Offset.zero, (sum, delta) => sum + delta);
    expect(total.dx, closeTo(20, 0.1));
    expect(total.dy, closeTo(10, 0.1));
  });

  testWidgets('DFCanvas interaction reduction blocks content for 150ms',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final deltas = <Offset>[];
    var taps = 0;

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        fitOnInit: false,
        interactionReductionEnabled: true,
        nodes: [
          DFCanvasNode(
            id: 'reduced-content',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: GestureDetector(
              key: const Key('reduced-node-content'),
              onTap: () => taps++,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ],
      ),
    )));

    await tester.drag(
      find.byKey(const ValueKey('df-canvas-drag-reduced-content')),
      const Offset(40, 20),
    );
    await tester.pump();

    expect(deltas, isNotEmpty);
    await tester.tap(
      find.byKey(const Key('reduced-node-content')),
      warnIfMissed: false,
    );
    expect(taps, 0);

    await tester.pump(const Duration(milliseconds: 149));
    await tester.tap(
      find.byKey(const Key('reduced-node-content')),
      warnIfMissed: false,
    );
    expect(taps, 0);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(const Key('reduced-node-content')));
    expect(taps, 1);
  });

  testWidgets('DFCanvas default keeps non-production content tappable',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    var taps = 0;

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'normal-content',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: (_) {},
            child: GestureDetector(
              key: const Key('normal-node-content'),
              onTap: () => taps++,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ],
      ),
    )));

    await tester.drag(
      find.byKey(const ValueKey('df-canvas-drag-normal-content')),
      const Offset(40, 20),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('normal-node-content')));

    expect(taps, 1);
  });

  testWidgets('DFCanvas title handle keeps scene delta at zoom below one',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = Matrix4.diagonal3Values(0.5, 0.5, 1);
    final deltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'zoomed-out',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ],
      ),
    )));

    await tester.drag(
      find.byKey(const ValueKey('df-canvas-drag-zoomed-out')),
      const Offset(40, 20),
    );

    final total = deltas.fold(Offset.zero, (sum, delta) => sum + delta);
    expect(total.dx, closeTo(80, 0.1));
    expect(total.dy, closeTo(40, 0.1));
  });

  testWidgets('DFCanvas 空格拖节点标题栏在放大视图中只平移画布', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = (Matrix4.diagonal3Values(2, 2, 1)
        ..setEntry(0, 3, 30)
        ..setEntry(1, 3, 40));
    final deltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'space-pan-zoomed-in',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ],
      ),
    )));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final zoomedInDrag = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('df-canvas-drag-space-pan-zoomed-in')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await zoomedInDrag.moveBy(const Offset(40, 20));
    await zoomedInDrag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(deltas, isEmpty);
    expect(controller.value.storage[0], closeTo(2, 0.01));
    expect(controller.value.storage[5], closeTo(2, 0.01));
    expect(controller.value.storage[12], closeTo(70, 0.1));
    expect(controller.value.storage[13], closeTo(60, 0.1));
  });

  testWidgets('DFCanvas 空格拖节点标题栏在缩小视图中仍按屏幕像素平移', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = (Matrix4.diagonal3Values(0.5, 0.5, 1)
        ..setEntry(0, 3, 30)
        ..setEntry(1, 3, 40));
    final deltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'space-pan-zoomed-out',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ],
      ),
    )));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final zoomedOutDrag = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('df-canvas-drag-space-pan-zoomed-out')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await zoomedOutDrag.moveBy(const Offset(40, 20));
    await zoomedOutDrag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(deltas, isEmpty);
    expect(controller.value.storage[0], closeTo(0.5, 0.01));
    expect(controller.value.storage[5], closeTo(0.5, 0.01));
    expect(controller.value.storage[12], closeTo(70, 0.1));
    expect(controller.value.storage[13], closeTo(60, 0.1));
  });

  testWidgets('DFCanvas 空格拖拽会夺取图片节点内的平移手势', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = Matrix4.diagonal3Values(2, 2, 1);
    final canvasDeltas = <Offset>[];
    final imageNodeDeltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'image-node-space-pan',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: canvasDeltas.add,
            child: DFCanvasDragRegion(
              child: GestureDetector(
                key: const Key('nested-image-node-pan'),
                onPanUpdate: (details) => imageNodeDeltas.add(details.delta),
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ],
      ),
    )));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('nested-image-node-pan'))),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(40, 20));
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(canvasDeltas, isEmpty);
    expect(imageNodeDeltas, isEmpty);
    expect(controller.value.storage[12], closeTo(40, 0.1));
    expect(controller.value.storage[13], closeTo(20, 0.1));
  });

  testWidgets('DFCanvasDragRegion 从卡片拖动节点且保留点击', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController();
    final nodeDeltas = <Offset>[];
    var taps = 0;

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'image-node-normal-pan',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: nodeDeltas.add,
            child: DFCanvasDragRegion(
              child: GestureDetector(
                key: const Key('nested-image-node-normal-pan'),
                onTap: () => taps++,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ],
      ),
    )));

    await tester.drag(
      find.byKey(const Key('nested-image-node-normal-pan')),
      const Offset(40, 20),
    );

    final total = nodeDeltas.fold(Offset.zero, (sum, delta) => sum + delta);
    expect(total.dx, closeTo(40, 0.1));
    expect(total.dy, closeTo(20, 0.1));
    expect(controller.value.storage[12], closeTo(0, 0.1));
    expect(controller.value.storage[13], closeTo(0, 0.1));

    await tester.tap(find.byKey(const Key('nested-image-node-normal-pan')));
    expect(taps, 1);
  });

  testWidgets('DFCanvas 节点拖动忽略鼠标右键', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final deltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'primary-drag-only',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ],
      ),
    )));

    final drag = await tester.startGesture(
      tester.getCenter(
          find.byKey(const ValueKey('df-canvas-drag-primary-drag-only'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await drag.moveBy(const Offset(40, 20));
    await drag.up();

    expect(deltas, isEmpty);
  });

  testWidgets('DFCanvasDragRegion 参数区不移动节点或画布（含 scroll 模式）', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = (Matrix4.identity()
        ..setEntry(0, 3, 12)
        ..setEntry(1, 3, 15));
    final nodeDeltas = <Offset>[];
    final parameterDeltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        wheelMode: CanvasWheelMode.scroll,
        nodes: [
          DFCanvasNode(
            id: 'image-node-parameters',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: nodeDeltas.add,
            child: DFCanvasDragRegion(
              movesNode: false,
              child: GestureDetector(
                key: const Key('nested-image-node-parameters'),
                onPanUpdate: (details) => parameterDeltas.add(details.delta),
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ],
      ),
    )));

    await tester.drag(
      find.byKey(const Key('nested-image-node-parameters')),
      const Offset(40, 20),
    );

    expect(parameterDeltas, isNotEmpty);
    expect(nodeDeltas, isEmpty);
    expect(controller.value.storage[12], closeTo(12, 0.1));
    expect(controller.value.storage[13], closeTo(15, 0.1));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester
        .getCenter(find.byKey(const Key('nested-image-node-parameters'))));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();

    expect(controller.value.storage[0], closeTo(1, 0.1));
    expect(controller.value.storage[5], closeTo(1, 0.1));
    expect(controller.value.storage[12], closeTo(12, 0.1));
    expect(controller.value.storage[13], closeTo(15, 0.1));
  });

  testWidgets('DFCanvas 触摸拖节点不会被空格桌面快捷键阻断', (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = TransformationController()
      ..value = Matrix4.diagonal3Values(2, 2, 1);
    final deltas = <Offset>[];

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: [
          DFCanvasNode(
            id: 'touch-keeps-dragging',
            position: const Offset(80, 80),
            size: const Size(220, 120),
            onDragUpdate: deltas.add,
            child: const ColoredBox(color: Colors.blue),
          ),
        ],
      ),
    )));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.drag(
      find.byKey(const ValueKey('df-canvas-drag-touch-keeps-dragging')),
      const Offset(40, 20),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    final total = deltas.fold(Offset.zero, (sum, delta) => sum + delta);
    expect(total.dx, closeTo(20, 0.1));
    expect(total.dy, closeTo(10, 0.1));
  });

  testWidgets('DFCanvasController fits all nodes into the current viewport',
      (tester) async {
    await setLogicalSize(tester, const Size(900, 600));
    final controller = DFCanvasController()
      ..value = Matrix4.diagonal3Values(3, 3, 1);

    await tester.pumpWidget(themed(SizedBox(
      width: 900,
      height: 600,
      child: DFCanvas(
        controller: controller,
        fitOnInit: false,
        nodes: const [
          DFCanvasNode(
            id: 'wide',
            position: Offset.zero,
            size: Size(1500, 800),
            child: SizedBox.expand(),
          ),
        ],
      ),
    )));

    expect(tester.getSize(find.byType(DFCanvas)), const Size(900, 600));

    controller.fitView();
    await tester.pump();

    expect(controller.value.storage[0], lessThan(1));
  });
}
