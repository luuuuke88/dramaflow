import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/screens/production/production_guide.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required bool compact,
  required List<GlobalKey> targets,
  required VoidCallback onComplete,
  bool withAppBar = false,
  Offset targetOffset = Offset.zero,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
    locale: const Locale('zh'),
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      appBar: withAppBar ? AppBar(title: const Text('画布')) : null,
      body: Stack(
        children: [
          for (var index = 0; index < targets.length; index++)
            Positioned(
              key: targets[index],
              left: targetOffset.dx + 32.0 + index * 96,
              top: targetOffset.dy + 48.0 + index * 48,
              width: 72,
              height: 36,
              child: const SizedBox.expand(),
            ),
          ProductionGuideOverlay(
            compact: compact,
            targets: targets,
            onComplete: onComplete,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('桌面引导按四步推进并在完成时仅回调一次', (tester) async {
    var completed = 0;
    final targets = List.generate(4, (_) => GlobalKey());

    await tester.pumpWidget(_host(
      compact: false,
      targets: targets,
      onComplete: () => completed++,
    ));
    await tester.pump();

    expect(find.byKey(const Key('production-guide')), findsOneWidget);
    expect(
        find.byKey(const Key('production-guide-desktop-card')), findsOneWidget);
    expect(find.byKey(const Key('production-guide-highlight')), findsOneWidget);
    expect(find.text('第 1 / 4 步'), findsOneWidget);

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const Key('production-guide-next')));
      await tester.pump();
    }

    expect(find.text('第 4 / 4 步'), findsOneWidget);
    await tester.tap(find.byKey(const Key('production-guide-finish')));
    await tester.pump();

    expect(completed, 1);
    expect(find.byKey(const Key('production-guide')), findsNothing);
  });

  testWidgets('390dp 引导使用全屏步骤面板且跳过时仅回调一次', (tester) async {
    var completed = 0;
    final targets = List.generate(4, (_) => GlobalKey());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      compact: true,
      targets: targets,
      onComplete: () => completed++,
    ));
    await tester.pump();

    expect(find.byKey(const Key('production-guide-compact')), findsOneWidget);
    expect(
        find.byKey(const Key('production-guide-desktop-card')), findsNothing);
    expect(find.text('切换剧集'), findsOneWidget);

    await tester.tap(find.byKey(const Key('production-guide-skip')));
    await tester.pump();

    expect(completed, 1);
    expect(find.byKey(const Key('production-guide')), findsNothing);
  });

  testWidgets('紧凑引导在小高度下可滚动并仍可完成', (tester) async {
    var completed = 0;
    final targets = List.generate(4, (_) => GlobalKey());
    tester.view.physicalSize = const Size(390, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      compact: true,
      targets: targets,
      onComplete: () => completed++,
    ));
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('production-guide-skip')),
      120,
    );
    await tester.tap(find.byKey(const Key('production-guide-skip')));
    await tester.pump();

    expect(completed, 1);
  });

  testWidgets('由紧凑模式切到桌面后会重新测量并显示目标高亮', (tester) async {
    final targets = List.generate(4, (_) => GlobalKey());

    await tester.pumpWidget(_host(
      compact: true,
      targets: targets,
      onComplete: () {},
    ));
    await tester.pump();
    expect(find.byKey(const Key('production-guide-highlight')), findsNothing);

    await tester.pumpWidget(_host(
      compact: false,
      targets: targets,
      onComplete: () {},
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('production-guide-highlight')), findsOneWidget);
  });

  testWidgets('桌面高亮按引导层局部坐标定位目标', (tester) async {
    final targets = List.generate(4, (_) => GlobalKey());

    await tester.pumpWidget(_host(
      compact: false,
      targets: targets,
      withAppBar: true,
      onComplete: () {},
    ));
    await tester.pump();

    final targetTopLeft = tester.getTopLeft(find.byKey(targets.first));
    final highlightTopLeft = tester.getTopLeft(
      find.byKey(const Key('production-guide-highlight')),
    );
    expect(highlightTopLeft.dx, closeTo(targetTopLeft.dx - 6, 0.1));
    expect(highlightTopLeft.dy, closeTo(targetTopLeft.dy - 6, 0.1));
  });
}
