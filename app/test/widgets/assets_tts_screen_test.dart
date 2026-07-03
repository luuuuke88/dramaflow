import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/assets/assets_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Gateway implements ProviderGateway {
  late String Function(String rel) absPath;

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) async {
    expect(stage, 'tts');
    expect(text, '吾辈修士，何惧一战。');
    expect(voice, 'alloy');
    final rel = '$projectId/tts_ui.mp3';
    File(absPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([8, 8, 8]);
    return rel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-assets-tts-');
    final db = openEngineDb(':memory:');
    final gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    gateway.absPath = engine.mediaAbsPath;
    projectId = engine.addProject(projectType: 'novel', name: '配音 UI 测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({double width = 1400}) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: AssetsScreen(projectId: projectId)),
          ),
        ),
      );

  testWidgets('音频 tab 可用文本配音创建可试听音频资产', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('文本配音'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tts-audio-name')), 'alloy');
    await tester.enterText(find.byKey(const Key('tts-audio-sex')), '男');
    await tester.enterText(find.byKey(const Key('tts-audio-describe')), '低音示例');
    await tester.enterText(
        find.byKey(const Key('tts-audio-text')), '吾辈修士，何惧一战。');
    await tester.enterText(find.byKey(const Key('tts-audio-voice')), 'alloy');
    await tester.tap(find.widgetWithText(FilledButton, '生成配音'));
    await tester.pumpAndSettle();

    expect(engine.audioPool(projectId).single.name, 'alloy');
    final audioId = engine.audioPool(projectId).single.id;
    expect(engine.audioAssetAbsPath(audioId), isNotNull);
    expect(
        File(engine.audioAssetAbsPath(audioId)!).readAsBytesSync(), [8, 8, 8]);
  });

  testWidgets('移动端音频 tab：文本配音创建音频资产', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('文本配音'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('tts-audio-name')), 'alloy');
    await tester.enterText(find.byKey(const Key('tts-audio-sex')), '男');
    await tester.enterText(find.byKey(const Key('tts-audio-describe')), '低音示例');
    await tester.enterText(
        find.byKey(const Key('tts-audio-text')), '吾辈修士，何惧一战。');
    await tester.enterText(find.byKey(const Key('tts-audio-voice')), 'alloy');
    await tester.tap(find.widgetWithText(FilledButton, '生成配音'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(engine.audioPool(projectId).single.name, 'alloy');
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('alloy')),
      findsOneWidget,
    );
  });
}
