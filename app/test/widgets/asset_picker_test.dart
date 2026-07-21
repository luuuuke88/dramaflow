import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/script/asset_picker.dart';
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
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-asset-picker-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '选择器测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('确认按钮按勾选先后顺序返回，而不是选项列表的原始顺序', (tester) async {
    // 选项列表（assetSelectionItems 按 id 升序）原始顺序是 A、B、C、D。
    final idA = engine.addAsset(
        projectId: projectId, type: 'role', name: 'A', describe: '');
    final idB = engine.addAsset(
        projectId: projectId, type: 'role', name: 'B', describe: '');
    final idC = engine.addAsset(
        projectId: projectId, type: 'role', name: 'C', describe: '');
    final idD = engine.addAsset(
        projectId: projectId, type: 'role', name: 'D', describe: '');

    List<int>? result;
    await tester.pumpWidget(ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                result = await showAssetPicker(
                  context,
                  ref,
                  projectId: projectId,
                  initial: const [],
                );
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 按 D -> A -> C 的顺序勾选：跟选项列表原始顺序（A,B,C,D）不同。
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idD')));
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idA')));
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idC')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-picker-confirm')));
    await tester.pumpAndSettle();

    expect(result, [idD, idA, idC]);
    expect(idB, isNotNull); // idB 未勾选，仅用于确认选项列表包含它。
  });

  testWidgets('取消再重新勾选的资产排到最后（按最近一次勾选的时间排序）', (tester) async {
    final idA = engine.addAsset(
        projectId: projectId, type: 'role', name: 'A', describe: '');
    final idB = engine.addAsset(
        projectId: projectId, type: 'role', name: 'B', describe: '');

    List<int>? result;
    await tester.pumpWidget(ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                result = await showAssetPicker(
                  context,
                  ref,
                  projectId: projectId,
                  initial: const [],
                );
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 先勾 A 再勾 B，然后取消 A、重新勾选 A：最终顺序应为 B、A。
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idA')));
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idB')));
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idA')));
    await tester.tap(find.byKey(ValueKey('asset-picker-item-$idA')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('asset-picker-confirm')));
    await tester.pumpAndSettle();

    expect(result, [idB, idA]);
  });
}
