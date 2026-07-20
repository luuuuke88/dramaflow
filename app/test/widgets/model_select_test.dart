import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/api/models.dart';
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

  Widget app() => ProviderScope(
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
              onChanged: (_) {},
            ),
          ),
        ),
      );

  Future<ProviderInfo> addImageModel({
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
    return provider;
  }

  testWidgets('groups image models beneath their provider headers',
      (tester) async {
    final ima2 = await addImageModel(
      providerName: 'ima2',
      modelId: 'gpt-image-2',
    );
    final volcengine = await addImageModel(
      providerName: '火山引擎',
      modelId: 'doubao-seedream',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-select-field-image')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('model-select-provider-${ima2.id}')), findsOneWidget);
    expect(find.byKey(Key('model-select-provider-${volcengine.id}')),
        findsOneWidget);
    expect(find.text('图片'), findsNWidgets(2));
  });

  testWidgets('refreshes the available models when the menu opens',
      (tester) async {
    await addImageModel(
      providerName: 'ima2',
      modelId: 'gpt-image-2',
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final addedAfterBuild = await addImageModel(
      providerName: '火山引擎',
      modelId: 'doubao-seedream',
    );
    await tester.tap(find.byKey(const Key('model-select-field-image')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('model-select-provider-${addedAfterBuild.id}')),
      findsOneWidget,
    );
  });

  testWidgets('does not offer a model disabled after the selector loaded',
      (tester) async {
    final provider = await addImageModel(
      providerName: 'ima2',
      modelId: 'gpt-image-2',
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await engine.updateProvider(provider.id, enabled: false);
    await tester.tap(find.byKey(const Key('model-select-field-image')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(Key('model-select-provider-${provider.id}')), findsNothing);
  });
}
