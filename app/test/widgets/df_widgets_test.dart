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
    pointer.hover(focalPoint);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
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

    final trackpad = TestPointer(2, PointerDeviceKind.trackpad)
      ..hover(const Offset(450, 300));
    await tester.sendEventToBinding(trackpad.scroll(const Offset(-12, 18)));
    await tester.pump();

    expect(controller.value.storage[0], 1);
    expect(controller.value.storage[5], 1);
    expect(controller.value.storage[12], closeTo(-8, 0.1));
    expect(controller.value.storage[13], closeTo(-118, 0.1));
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
