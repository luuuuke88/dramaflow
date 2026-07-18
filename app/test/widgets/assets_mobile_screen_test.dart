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

  testWidgets('移动端素材库：整页 10 条素材可通过滚动全部触达，无 RenderFlex 溢出', (tester) async {
    // A real phone viewport (iPhone SE-class), shorter than the 390x900 used
    // by the other test above — the taller size leaves enough room that a
    // full page of 10 cards can fit without ever needing to scroll, which is
    // exactly why this bug slipped through before.
    tester.view.physicalSize = const Size(390, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (var i = 1; i <= 10; i++) {
      engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: 'Asset${i.toString().padLeft(2, '0')}',
        describe: 'd$i',
      );
    }

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The first row is reachable without scrolling.
    expect(find.text('Asset01').hitTestable(), findsOneWidget);

    // The last row of the full default page (limit = 10) is not yet
    // reachable: it's below the fold of the phone-sized viewport.
    expect(find.text('Asset10').hitTestable(), findsNothing);

    // Scrolling must reveal it — with no RenderFlex overflow or other
    // exceptions along the way.
    await tester.dragUntilVisible(
      find.text('Asset10'),
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asset10').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动壳平板宽度下素材工具栏不溢出', (tester) async {
    tester.view.physicalSize = const Size(800, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 空态和工具栏都会提供“新增角色”，本用例关心的是平板宽度下
    // 页面正常渲染且无溢出，而非这两个入口的数量。
    expect(find.text('新增角色'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('资产图片缩略图可打开独立预览层', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '可预览角色',
      describe: '用于验证缩略图预览入口',
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'role',
      prompt: '测试图',
      base64Image:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAF/gL+6fD6nwAAAABJRU5ErkJggg==',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('asset-media-preview')), findsOneWidget);
  });

  testWidgets('素材视频以播放缩略图呈现，而非当作图片解码', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    engine.uploadClip(
      projectId: projectId,
      name: '片段.mp4',
      bytes: const [0, 1, 2, 3],
      ext: 'mp4',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectTab(tester, '素材');

    final play = find.byIcon(Icons.play_circle_outline);
    expect(play, findsOneWidget);
  });

  testWidgets('音频预览显示当前音频名称', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    engine.addAudioAssets(
      projectId: projectId,
      name: '清冷女声',
      sex: '女',
      describe: '低沉',
      items: const [
        (
          base64: 'AQID',
          ext: 'mp3',
          prompt: '试听台词',
          name: '试听样例',
          describe: '平静',
          existingImageId: null,
        ),
      ],
    );
    final child =
        engine.getAssets(projectId, type: 'audio').data.single.sonAssets.single;
    final childId = child.id;
    File(engine.mediaAbsPath(child.filePath!)).deleteSync();

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectTab(tester, '音频');
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(find.text('试听样例'), findsOneWidget);
    final audioPreview = find.byKey(ValueKey('asset-media-trigger-$childId'));
    expect(audioPreview, findsOneWidget);
    await tester.tap(audioPreview);
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('asset-media-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.text('试听样例')),
      findsOneWidget,
      reason: 'ToonFlow 音频预览需明确当前正在试听的音频名称',
    );
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
