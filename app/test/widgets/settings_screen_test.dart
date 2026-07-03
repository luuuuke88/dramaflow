import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/settings_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-settingsui-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: Consumer(
          builder: (context, ref, _) {
            return MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [
                Locale('zh'),
                Locale('en'),
                Locale('ja')
              ],
              locale: ref.watch(localeProvider) ?? const Locale('zh'),
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: ref.watch(themeModeProvider),
              home: const SettingsScreen(),
            );
          },
        ),
      );

  testWidgets('移动端设置页：外观语言、供应商与提示词入口可用', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(engine.config.str('themeMode'), 'dark');

    await _selectSection(tester, '供应商');
    await tester.tap(find.text('添加供应商').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Local Gateway');
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://127.0.0.1:8787/v1',
    );
    await tester.enterText(find.byType(TextField).at(2), 'local');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final provider = (await engine.listProviders()).single;
    expect(provider.name, 'Local Gateway');
    expect(provider.baseUrl, 'http://127.0.0.1:8787/v1');

    await _selectSection(tester, '提示词');
    await tester.tap(find.text('事件提取'));
    await tester.pumpAndSettle();
    expect(find.text('编辑提示词 · 事件提取'), findsOneWidget);
    expect(find.text('提示词内容'), findsOneWidget);
    Navigator.of(tester.element(find.text('编辑提示词 · 事件提取'))).pop();
    await tester.pumpAndSettle();

    await _selectSection(tester, '外观');
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(engine.config.str('app.locale'), 'ja');
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('移动端设置页：模型管理、模型绑定与数据库信息可用', (tester) async {
    final provider = await engine.createProvider(
      name: 'Local Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();
    expect(find.text('模型管理 · Local Gateway'), findsOneWidget);

    await tester.tap(find.text('添加模型').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'local-text');
    await tester.enterText(find.byType(TextField).at(1), '本地文本模型');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final models = await engine.listProviderModels(provider.id);
    expect(models.single.modelId, 'local-text');
    expect(models.single.kind, 'text');

    await _selectSection(tester, '模型绑定');
    await _chooseFirstDropdown(tester, 'Local Gateway · 本地文本模型');
    expect(
      (await engine.getBindings())['script_gen'],
      '${provider.id}:local-text',
    );

    await _selectSection(tester, '存储与引擎');
    await tester.tap(find.text('数据库信息'));
    await tester.pumpAndSettle();
    expect(find.text('数据库信息'), findsWidgets);
    expect(find.text('o_project'), findsOneWidget);
  });

  testWidgets('移动端设置页：编辑供应商配置并刷新卡片', (tester) async {
    await engine.createProvider(
      name: 'Old Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'old-key',
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('编辑').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑供应商'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'AZT Gateway');
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://127.0.0.1:8787/v1',
    );
    await tester.enterText(find.byType(TextField).at(2), 'local');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final provider = (await engine.listProviders()).single;
    expect(provider.name, 'AZT Gateway');
    expect(provider.baseUrl, 'http://127.0.0.1:8787/v1');
    expect(provider.apiKey, 'local');
    expect(find.text('AZT Gateway'), findsOneWidget);
    expect(find.text('Old Gateway'), findsNothing);
  });

  testWidgets('移动端设置页：清空数据确认只清内容保留配置', (tester) async {
    await engine.createProvider(
      name: 'Keep Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    engine.addProject(projectType: 'novel', name: '待清理项目');

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(engine.projects(), isNotEmpty);

    await _selectSection(tester, '存储与引擎');
    await tester.tap(find.text('清空数据'));
    await tester.pumpAndSettle();
    expect(find.text('清空所有数据'), findsOneWidget);

    await tester.tap(find.text('清空数据').last);
    await tester.pumpAndSettle();

    expect(engine.projects(), isEmpty);
    expect((await engine.listProviders()).single.name, 'Keep Provider');
  });
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  await tester.dragUntilVisible(
    find.text(label),
    find.byType(SegmentedButton).first,
    const Offset(-160, 0),
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _chooseFirstDropdown(
  WidgetTester tester,
  String optionLabel,
) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}
