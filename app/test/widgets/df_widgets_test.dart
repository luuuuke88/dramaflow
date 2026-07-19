import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/theme/tokens.dart';
import 'package:dramaflow/src/widgets/df_adaptive_dialog.dart';
import 'package:dramaflow/src/widgets/df_canvas.dart';
import 'package:dramaflow/src/widgets/df_data_table.dart';
import 'package:dramaflow/src/widgets/df_status_tag.dart';
import 'package:flutter/material.dart';
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
