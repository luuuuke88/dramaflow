import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/provider_preset_form.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Engine engine;

  setUp(() {
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore('/tmp/df-preset-form-test-media'),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() => engine.dispose());

  Widget host() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                key: const Key('open-form'),
                onPressed: () =>
                    showProviderPresetForm(context, ref, presetId: 'deepseek'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('预填正确：BaseURL/模型清单来自目录，Key 框遮蔽可切换', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-form')));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-baseurl')))
            .controller!
            .text,
        'https://api.deepseek.com/v1');
    // 目录当前真值（provider_presets.dart 独立复核后）：deepseek-v4-flash /
    // deepseek-v4-pro（不是早前的 deepseek-chat/deepseek-reasoner，那两个
    // 已定于 2026-07-24 停用）。
    expect(find.text('deepseek-v4-flash'), findsOneWidget);
    expect(find.text('deepseek-v4-pro'), findsOneWidget);

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-apikey')))
            .obscureText,
        isTrue);
    await tester.tap(find.byKey(const Key('preset-form-apikey-toggle')));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-apikey')))
            .obscureText,
        isFalse);
  });

  testWidgets('保存：改名+改 BaseURL+取消一个模型，全部真实落库', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-form')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('preset-form-name')), '我的 DeepSeek');
    await tester.enterText(find.byKey(const Key('preset-form-baseurl')),
        'https://proxy.example.com/v1');
    await tester.enterText(
        find.byKey(const Key('preset-form-apikey')), 'sk-test');
    await tester.tap(find.byKey(const Key('preset-model-deepseek-v4-pro')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('preset-form-save')));
    await tester.pumpAndSettle();

    final provider = (await engine.listProviders()).single;
    expect(provider.name, '我的 DeepSeek', reason: '可编辑名称必须真实生效（评审 P1-3）');
    expect(provider.baseUrl, 'https://proxy.example.com/v1');
    final models = await engine.listProviderModels('deepseek');
    expect(models.map((m) => m.modelId).toList(), ['deepseek-v4-flash']);
  });

  testWidgets('保存失败（供应商已存在）：展示本地化文案，不泄漏原始异常（评审 round 2）',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 复用 Task 2 已在引擎层验证过的 errProviderExists 场景：预先真实创建一次
    // 同 presetId 的供应商，制造表单在“重复创建竞争”下会遇到的真实异常
    // （不是伪造/mock 出来的），再让表单对同一 presetId 保存去触发它。
    await engine.createProviderFromPreset(
      presetId: 'deepseek',
      apiKey: '',
      selectedModelIds: const ['deepseek-v4-flash'],
    );

    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-form')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('preset-form-save')));
    await tester.pumpAndSettle();

    // 必须是 Task 4 添加的本地化文案（app_zh.arb: presetProviderExists），
    // 而不是 EngineException.toString() 产出的原始
    // `errProviderExists {providerId: deepseek}`。
    expect(find.text('该供应商已添加，请直接编辑'), findsOneWidget);
    expect(find.textContaining('errProviderExists'), findsNothing);
    expect(find.textContaining('providerId'), findsNothing);
  });
}
