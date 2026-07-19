import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/screens/provider_preset_gallery.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
    {required Set<String> existing,
    required void Function(String?) onResult}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
    locale: const Locale('zh'),
    theme: buildTheme(Brightness.light),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open-gallery'),
            onPressed: () async {
              onResult(await showProviderPresetGallery(context,
                  existingProviderIds: existing));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Finder _inCard(String presetId, String text) => find.descendant(
    of: find.byKey(Key('preset-card-$presetId')), matching: find.text(text));

void main() {
  testWidgets('手机宽度：卡片、原生 Anthropic 未验证角标、选中回传', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(_host(existing: {}, onResult: (v) => picked = v));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();

    // openai 未过验收 → 未验证；非兼容模式 → 无兼容模式角标
    expect(_inCard('openai', '未验证'), findsOneWidget);
    expect(_inCard('openai', '兼容模式'), findsNothing);
    // Anthropic 已有原生协议，尚未做真实 Key 验收，因此仅显示未验证。
    expect(_inCard('anthropic', '未验证'), findsOneWidget);
    expect(_inCard('anthropic', '兼容模式'), findsNothing);

    await tester.tap(find.byKey(const Key('preset-card-openai')));
    await tester.pumpAndSettle();
    expect(picked, 'openai');
  });

  testWidgets('桌面宽度：已添加优先于未验证；azt 已验不显示未验证', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester
          .pumpWidget(_host(existing: {'volcengine'}, onResult: (_) {}));
      await tester.tap(find.byKey(const Key('open-gallery')));
      await tester.pumpAndSettle();

      expect(_inCard('volcengine', '已添加'), findsOneWidget);
      expect(_inCard('volcengine', '未验证'), findsNothing,
          reason: '已添加态优先，不再叠未验证');
      await tester.scrollUntilVisible(
          find.byKey(const Key('preset-card-azt')), 300);
      expect(_inCard('azt', '未验证'), findsNothing,
          reason: 'azt acceptanceVerified=true');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('移动平台不提供仅桌面可用的 azt 预设', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(_host(existing: const {}, onResult: (_) {}));
      await tester.tap(find.byKey(const Key('open-gallery')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('preset-card-azt')), findsNothing,
          reason: '127.0.0.1 的本地 OAuth 代理不属于 iOS/Android 可用供应商');
      expect(find.byKey(const Key('preset-card-volcengine')), findsOneWidget);
      expect(find.byKey(const Key('preset-card-custom')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('自定义卡返回 custom', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(_host(existing: {}, onResult: (v) => picked = v));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-custom')), 300);
    await tester.tap(find.byKey(const Key('preset-card-custom')));
    await tester.pumpAndSettle();
    expect(picked, 'custom');
  });
}
