import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/screens/first_run_guide.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required VoidCallback onComplete,
  required ValueChanged<String> onOpenSettings,
  ValueChanged<String>? onLocaleChanged,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      locale: const Locale('zh'),
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: FirstRunGuide(
          onComplete: onComplete,
          onOpenSettings: onOpenSettings,
          onLocaleChanged: onLocaleChanged,
        ),
      ),
    );

void main() {
  testWidgets('首次引导按模型配置、模型绑定和完成顺序推进', (tester) async {
    var completed = 0;
    final openedSections = <String>[];
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      onComplete: () => completed++,
      onOpenSettings: openedSections.add,
    ));

    expect(find.text('欢迎使用 DramaFlow'), findsOneWidget);
    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();

    expect(find.text('配置模型服务'), findsOneWidget);
    await tester.tap(find.text('打开模型设置'));
    expect(openedSections, ['providers']);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('配置创作模型'), findsOneWidget);
    await tester.tap(find.text('打开模型绑定'));
    expect(openedSections, ['providers', 'bindings']);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('开始创作'), findsOneWidget);
    await tester.tap(find.text('完成'));
    expect(completed, 1);
  });

  testWidgets('任何步骤都可跳过，桌面布局仍保留开始设置入口', (tester) async {
    var completed = 0;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      onComplete: () => completed++,
      onOpenSettings: (_) {},
    ));

    expect(find.text('开始设置'), findsOneWidget);
    await tester.tap(find.text('跳过设置'));

    expect(completed, 1);
  });

  testWidgets('欢迎页可以切换应用语言', (tester) async {
    String? selectedLocale;
    await tester.pumpWidget(_host(
      onComplete: () {},
      onOpenSettings: (_) {},
      onLocaleChanged: (languageCode) => selectedLocale = languageCode,
    ));

    await tester.tap(find.byKey(const Key('onboarding-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-language-en')));

    expect(selectedLocale, 'en');
  });
}
