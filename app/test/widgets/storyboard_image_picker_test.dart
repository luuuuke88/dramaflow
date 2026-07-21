import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/production/storyboard_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;

  const candidates = [
    StoryboardImageCandidate(id: 1, label: 'A', prompt: '', localPath: 'a.png'),
    StoryboardImageCandidate(id: 2, label: 'B', prompt: '', localPath: 'b.png'),
    StoryboardImageCandidate(id: 3, label: 'C', prompt: '', localPath: 'c.png'),
    StoryboardImageCandidate(id: 4, label: 'D', prompt: '', localPath: 'd.png'),
  ];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-storyboard-picker-');
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

  Widget app(ValueSetter<List<StoryboardImageCandidate>?> onResult) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                onResult(await showStoryboardImagePicker(
                  context,
                  engine: engine,
                  candidates: candidates,
                  emptyText: 'empty',
                  multiple: true,
                ));
              },
              child: const Text('open'),
            );
          }),
        ),
      );

  testWidgets('确认按钮按勾选先后顺序返回候选，而不是候选列表的原始顺序', (tester) async {
    List<StoryboardImageCandidate>? result;
    await tester.pumpWidget(app((value) => result = value));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 候选列表原始顺序是 A(1),B(2),C(3),D(4)；按 D -> A -> C 的顺序勾选。
    await tester
        .tap(find.byKey(const ValueKey('storyboard-image-picker-item-4')));
    await tester
        .tap(find.byKey(const ValueKey('storyboard-image-picker-item-1')));
    await tester
        .tap(find.byKey(const ValueKey('storyboard-image-picker-item-3')));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const ValueKey('storyboard-image-picker-confirm')));
    await tester.pumpAndSettle();

    expect(result?.map((c) => c.id).toList(), [4, 1, 3]);
  });
}
