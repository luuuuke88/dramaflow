import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/screens/production/storyboard_canvas_node.dart';
import 'package:dramaflow/src/screens/production/storyboard_gallery.dart';
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
    scriptId = engine.addScript(projectId: projectId, name: '第一集', content: 'x');
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

  testWidgets('「预览全部」打开整屏画廊，页数等于分镜总数（含占位）', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 2 张有图 + 1 张未生成 = 3 页。
    seedShot(withImage: true);
    seedShot(withImage: true);
    seedShot(withImage: false);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('预览全部'), findsOneWidget);
    await tester.tap(find.text('预览全部'));
    await tester.pumpAndSettle();

    // 画廊为一个 PageView，页数 = 全部分镜数（3）。
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.childrenDelegate.estimatedChildCount, 3);
    // 首页计数标签显示 S01（1/3）。
    expect(find.textContaining('S01'), findsWidgets);
    expect(find.textContaining('1/3'), findsOneWidget);
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

  testWidgets('StoryboardPreviewItem 占位页不崩溃（absPath 为 null）', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showStoryboardGallery(
                  context,
                  items: const [
                    StoryboardPreviewItem(shotNumber: 1, absPath: null),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('S01 尚未生成首帧图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
