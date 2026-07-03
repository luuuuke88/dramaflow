import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/theme/tokens.dart';
import 'package:dramaflow/src/widgets/df_adaptive_dialog.dart';
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
    return MaterialApp(theme: buildTheme(Brightness.light), home: child);
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
}
