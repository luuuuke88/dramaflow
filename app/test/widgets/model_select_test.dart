import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/project/model_select.dart';
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
    dir = Directory.systemTemp.createTempSync('dramaflow-model-select-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({ValueChanged<ModelOption?>? onChanged}) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: ModelSelect(
              kind: 'image',
              value: null,
              hint: '选择模型',
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      );

  Future<void> addImageModel({
    required String providerName,
    required String modelId,
  }) async {
    final provider = await engine.createProvider(
      name: providerName,
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'test-key',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': modelId,
        'label': modelId,
        'kind': 'image',
        'enabled': true,
        'capabilities': <String, dynamic>{},
      },
    ]);
  }

  testWidgets('列出全部启用供应商的对应类型模型，选中后回传选项', (tester) async {
    await addImageModel(providerName: 'ima2', modelId: 'gpt-image-2');
    await addImageModel(providerName: '火山引擎', modelId: 'doubao-seedream');

    ModelOption? picked;
    await tester.pumpWidget(app(onChanged: (option) => picked = option));
    await tester.pumpAndSettle();

    expect(find.text('选择模型'), findsOneWidget);

    await tester.tap(find.text('选择模型'));
    await tester.pumpAndSettle();

    // DFSelect 弹层把「供应商 · 模型」拆成 供应商角标 + 模型名两段展示
    expect(find.text('ima2'), findsOneWidget);
    expect(find.text('gpt-image-2'), findsOneWidget);
    expect(find.text('火山引擎'), findsOneWidget);
    expect(find.text('doubao-seedream'), findsOneWidget);

    await tester.tap(find.text('doubao-seedream'));
    await tester.pumpAndSettle();
    expect(picked?.label, '火山引擎 · doubao-seedream');
  });

  testWidgets('禁用的模型不会出现在选项里', (tester) async {
    final provider = await engine.createProvider(
      name: 'ima2',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'test-key',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'gpt-image-2',
        'label': 'gpt-image-2',
        'kind': 'image',
        'enabled': true,
        'capabilities': <String, dynamic>{},
      },
      {
        'modelId': 'gpt-image-off',
        'label': 'gpt-image-off',
        'kind': 'image',
        'enabled': false,
        'capabilities': <String, dynamic>{},
      },
    ]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择模型'));
    await tester.pumpAndSettle();

    expect(find.text('gpt-image-2'), findsOneWidget);
    expect(find.textContaining('gpt-image-off'), findsNothing);
  });

  testWidgets('无可用模型时展示占位提示且不崩溃', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('选择模型'), findsOneWidget);
    await tester.tap(find.text('选择模型'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
