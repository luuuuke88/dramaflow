import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/df_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(void Function(BuildContext) onReady) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => onReady(context),
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      );

  testWidgets('提示条从顶部出现，而不是底部', (tester) async {
    await tester.pumpWidget(host((c) => showDFToast(c, '已保存')));
    await tester.tap(find.text('触发'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final toast = tester.getRect(find.byKey(dfToastKey));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(toast.center.dy, lessThan(screen.height / 2),
        reason: '提示必须显示在上半屏——全应用统一从顶部出现');
  });

  testWidgets('同一时刻只保留一条提示，新的顶掉旧的', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(host((c) => ctx = c));
    await tester.tap(find.text('触发'));
    await tester.pump();

    showDFToast(ctx, '第一条');
    await tester.pump();
    showDFToast(ctx, '第二条');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第一条'), findsNothing, reason: '旧提示应被顶掉，不能堆叠');
    expect(find.text('第二条'), findsOneWidget);
  });

  testWidgets('提示条不拦截点击，被它盖住的东西照样能点', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: Padding(
              // 正好落在提示条（top: 60）覆盖的位置
              padding: const EdgeInsets.only(top: 70),
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('被盖住的按钮'),
              ),
            ),
          ),
        ),
      ),
    ));

    showDFToast(
        tester.element(find.text('被盖住的按钮')), '一条挡在上面的很长很长的提示文案');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(dfToastKey), findsOneWidget);

    await tester.tap(find.text('被盖住的按钮'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 1,
        reason: '顶部提示压在正文上方，若拦截手势会让用户点不动被盖住的内容');
  });

  testWidgets('窄屏上长文案换行，不把提示条撑出屏幕', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host((c) => showDFToast(
        c, '这是一条相当长的提示文案，用来验证窄屏上不会把提示条撑出屏幕之外导致溢出报错')));
    await tester.tap(find.text('触发'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(dfToastKey)).width,
        lessThanOrEqualTo(390));
  });
}
