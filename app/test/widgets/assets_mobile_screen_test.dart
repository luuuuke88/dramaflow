import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
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

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-assets-mobile-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
    );
    projectId = engine.addProject(projectType: 'novel', name: '移动素材测试');
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
          home: Scaffold(body: AssetsScreen(projectId: projectId)),
        ),
      );

  testWidgets('移动端素材库：角色/道具/场景新增编辑删除与子资产展开', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _addAsset(tester, tab: '角色', name: '林逸', describe: '少年剑修');
    await _editVisibleAsset(tester, newName: '林逸改');
    var role = engine.getAssets(projectId, type: 'role').data.single;
    expect(role.name, '林逸改');

    engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸-侧脸',
      describe: '侧脸参考',
      parentAssetsId: role.id,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('林逸-侧脸'), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(find.text('林逸-侧脸'), findsOneWidget);

    await _selectTab(tester, '道具');
    await _addAsset(tester, tab: '道具', name: '寒铁剑', describe: '泛蓝冷光');
    await _editVisibleAsset(tester, newName: '寒铁剑改');
    expect(engine.getAssets(projectId, type: 'tool').data.single.name, '寒铁剑改');

    await _selectTab(tester, '场景');
    await _addAsset(tester, tab: '场景', name: '太岳山门', describe: '云雾宗门');
    await _editVisibleAsset(tester, newName: '太岳山门改');
    expect(
        engine.getAssets(projectId, type: 'scene').data.single.name, '太岳山门改');

    await _deleteVisibleAsset(tester);
    expect(engine.getAssets(projectId, type: 'scene').total, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

Future<void> _addAsset(
  WidgetTester tester, {
  required String tab,
  required String name,
  required String describe,
}) async {
  await tester.tap(find.text('新增$tab').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), name);
  await tester.enterText(find.byType(TextField).at(1), describe);
  await tester.enterText(find.byType(TextField).at(2), '$name 备注');
  await tester.enterText(find.byType(TextField).at(3), '$name prompt');
  await tester.tap(find.text('确定').last);
  await tester.pumpAndSettle();
  expect(find.text(name), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _editVisibleAsset(
  WidgetTester tester, {
  required String newName,
}) async {
  await tester.tap(find.byIcon(Icons.more_horiz).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('编辑').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), newName);
  await tester.tap(find.text('确定').last);
  await tester.pumpAndSettle();
  expect(find.text(newName), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _deleteVisibleAsset(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_horiz).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('删除').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '删除'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}
