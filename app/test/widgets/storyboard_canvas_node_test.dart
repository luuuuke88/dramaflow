import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/script_plan.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_table.dart';
import 'package:dramaflow/src/screens/production/storyboard_canvas_node.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SaveContactSheetSelector extends FileSelectorPlatform {
  final String path;
  int saveCalls = 0;
  List<XTypeGroup>? acceptedTypeGroups;
  String? suggestedName;

  _SaveContactSheetSelector(this.path);

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saveCalls++;
    this.acceptedTypeGroups = acceptedTypeGroups;
    suggestedName = options.suggestedName;
    return FileSaveLocation(path);
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      null;
}

/// 最小合法 PNG（1x1 透明），供 Image.file 与批量导出复制使用。
final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-storyboard-node-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    engine.installStoryboardPipeline();
    projectId = engine.addProject(projectType: 'novel', name: '画布测试');
    scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 新增分镜；[withImage] 为真时写入真实 PNG 并置为已完成。
  int seedShot({required bool withImage}) {
    final id = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'p');
    if (withImage) {
      final rel = engine.media.saveImage(_pngBytes, '$projectId');
      engine.setStoryboardImage(id, rel);
    }
    return id;
  }

  Widget app({double width = 1200}) {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 900,
              child: StoryboardCanvasNode(
                  projectId: projectId, scriptId: scriptId),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('「预览全部」合成有效首帧为单张五列网格预览', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 2 张有图 + 1 张未生成：原版过滤无图，只预览两张有效图。
    seedShot(withImage: true);
    seedShot(withImage: true);
    seedShot(withImage: false);
    final imagePaths = engine.storyboardImagePaths(scriptId);
    expect(imagePaths, hasLength(2));
    expect(
      imagePaths
          .every((image) => File(image.absPath).readAsBytesSync().isNotEmpty),
      isTrue,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('预览全部'), findsOneWidget);
    await tester.tap(find.text('预览全部'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('storyboard-contact-sheet-preview')),
        findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, .1);
    expect(viewer.maxScale, 10);
    expect(
      find.descendant(
        of: find.byKey(const Key('storyboard-contact-sheet-preview')),
        matching: find.byIcon(Icons.download_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('「导出全部」按钮存在；无图片时提示且不打开系统面板', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 仅有未生成图片的分镜。
    seedShot(withImage: false);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('导出全部'), findsOneWidget);
    await tester.tap(find.text('导出全部'));
    await tester.pump();
    // 无可导出图片：出现本地化提示 SnackBar（未触及平台文件面板）。
    expect(find.text('还没有可导出的首帧图'), findsOneWidget);
  });

  testWidgets('「导出全部」通过保存面板写出一张可解码 PNG 网格', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seedShot(withImage: true);
    seedShot(withImage: true);
    final output = p.join(dir.path, 'storyboard-preview.png');
    final originalPlatform = FileSelectorPlatform.instance;
    final selector = _SaveContactSheetSelector(output);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('导出全部'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(selector.saveCalls, 1);
    expect(selector.acceptedTypeGroups!.single.extensions, ['png']);
    expect(
      selector.suggestedName,
      matches(r'^storyboardImagePreview-\d+\.png$'),
    );
    expect(File(output).existsSync(), isTrue);
    expect(img.decodePng(File(output).readAsBytesSync()), isNotNull);
  });

  testWidgets('390dp 移动壳同样可打开单张联系表预览', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seedShot(withImage: true);

    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览全部'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storyboard-contact-sheet-preview')),
        findsOneWidget);
  });

  testWidgets('390dp 预览内下载同样写出单张 PNG 联系表', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seedShot(withImage: true);
    final output = p.join(dir.path, 'mobile-contact-sheet.png');
    final originalPlatform = FileSelectorPlatform.instance;
    final selector = _SaveContactSheetSelector(output);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    await tester.pumpWidget(app(width: 390));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览全部'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('storyboard-contact-sheet-preview')),
          matching: find.byIcon(Icons.download_outlined),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(selector.saveCalls, 1);
    expect(File(output).existsSync(), isTrue);
    expect(img.decodePng(File(output).readAsBytesSync()), isNotNull);
  });

  test('storyboardImagePaths 仅返回已生成图片，按镜头顺序编号', () {
    seedShot(withImage: false); // 镜头 1：无图
    seedShot(withImage: true); // 镜头 2：有图
    seedShot(withImage: true); // 镜头 3：有图

    final images = engine.storyboardImagePaths(scriptId);
    expect(images.length, 2);
    expect(images[0].shotNumber, 2);
    expect(images[1].shotNumber, 3);
    for (final img in images) {
      expect(File(img.absPath).existsSync(), isTrue);
    }
  });

  testWidgets('行菜单「在前面插入分镜」把新镜头排到目标之前', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头1');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头2');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 长按第二个分镜格（displayIndex=1）打开行菜单。
    await tester.longPress(find.textContaining('S02'));
    await tester.pumpAndSettle();
    expect(find.text('在前面插入分镜'), findsOneWidget);

    await tester.tap(find.text('在前面插入分镜'));
    await tester.pumpAndSettle();

    // 新镜头应排在 s2 之前：顺序 s1, 新, s2。
    final rows = engine.storyboards(scriptId);
    expect(rows.length, 3);
    expect(rows.first.id, s1);
    expect(rows.last.id, s2);
    expect(rows.map((r) => r.index), [1, 2, 3]);
  });

  testWidgets('重新生成分镜依次经过破坏确认和费用确认', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.saveScriptPlan(projectId, '导演规划');
    engine.saveStoryboardTable(projectId, scriptId, '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 雪夜山门 | 推近 | 3 |
''');
    seedShot(withImage: false);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final generate = find.byKey(Key('storyboard-generate-$scriptId'));
    expect(generate, findsOneWidget);
    expect(find.byKey(Key('storyboard-stale-$scriptId')), findsOneWidget);

    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('危险操作确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(await engine.projectJobs(projectId), isEmpty);

    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('危险操作确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(await engine.projectJobs(projectId), isEmpty);

    await tester.tap(generate);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pump();
    final tasks = await engine.projectJobs(projectId);
    expect(tasks, hasLength(1));
    expect(tasks.single.taskClass, 'storyboard_generate');
    expect(tasks.single.relatedObjectsJson['replaceExisting'], isTrue);
  });

  testWidgets('只有分镜表但没有导演规划时生成按钮禁用', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.saveStoryboardTable(projectId, scriptId, '''
| 画面提示词 | 画面描述 | 时长 |
| --- | --- | --- |
| 雪夜山门 | 推近 | 3 |
''');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(Key('storyboard-generate-$scriptId')),
    );
    expect(button.onPressed, isNull);
    expect(await engine.projectJobs(projectId), isEmpty);
  });
}
