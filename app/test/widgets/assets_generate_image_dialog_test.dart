import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/assets/assets_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:dramaflow/src/widgets/df_toast.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAF/gL+6fD6nwAAAABJRU5ErkJggg==';

class _Gateway implements ProviderGateway {
  late String Function(String rel) absPath;
  final List<String> textStages = [];
  final List<String> imagePrompts = [];
  final List<List<String>> imageReferences = [];
  final List<String?> imageModels = [];
  final List<String?> imageQualities = [];

  @override
  Future<TextResult> generateText(
    String system,
    String user, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    textStages.add(stage);
    expectSync(user, contains('林逸'));
    return const TextResult('月下白衣剑修，冷色国风插画');
  }

  @override
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    List<String> referenceAbsPaths = const [],
    String? editInstruction,
    String? maskAbsPath,
    String? ratio,
    String? quality,
    String? modelOverride,
  }) async {
    imagePrompts.add(prompt);
    expectSync(stage, 'asset_image');
    expectSync(prompt, contains('月下白衣剑修'));
    imageReferences.add(referenceAbsPaths);
    imageModels.add(modelOverride);
    imageQualities.add(quality);
    const rel = 'generated/asset.png';
    final file = File(absPath(rel));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(base64Decode(_pngBase64));
    return rel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageFileSelector extends FileSelectorPlatform {
  final List<XFile> files;
  int openFileCalls = 0;
  final List<List<XTypeGroup>?> acceptedTypeGroupCalls = [];

  _ImageFileSelector(this.files);

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async =>
      null;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openFileCalls++;
    acceptedTypeGroupCalls.add(acceptedTypeGroups);
    if (openFileCalls > files.length) {
      throw StateError('no queued test image');
    }
    return files[openFileCalls - 1];
  }
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;
  late int assetId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-asset-image-dialog-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 5),
    );
    gateway.absPath = engine.mediaAbsPath;
    engine.installAssetPipeline();
    engine.config.update({'policy.confirmMoney': '0'});
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('asset_prompt_polish','asset_prompt_polish','',NULL)",
    );
    engine.saveVisualManual(
      name: '国风水墨',
      data: {for (final key in visualManualKeys) key: '测试画风[$key]'},
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '资产弹窗测试',
      artStyle: '国风水墨',
    );
    assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林逸',
      describe: '少年剑修',
      prompt: '初始提示词',
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      base64Image: _pngBase64,
      prompt: '初始提示词',
      type: 'role',
    );
  });

  tearDown(() {
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({double width = 1400, double height = 900}) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light),
            home: Consumer(
              builder: (context, ref, _) {
                // AppShell 常驻监听它；测试直挂页面时也必须接上同一刷新桥。
                ref.watch(activeJobsProvider);
                return Scaffold(body: AssetsScreen(projectId: projectId));
              },
            ),
          ),
        ),
      );

  testWidgets('桌面端资产生图弹窗：润色、选模型分辨率、候选选中并保存', (tester) async {
    // 必须在 widget test 的 fake-async zone 内启动，后续 tester.pump 才会驱动队列 tick。
    engine.queue.start();
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _ImageFileSelector([
      XFile.fromData(base64Decode(_pngBase64), path: 'reference.png'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final provider = await engine.createProvider(
      name: '测试供应商',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'image-test',
        'label': '图像测试',
        'kind': 'image',
        'enabled': true,
      },
    ]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(DropTarget)),
      findsOneWidget,
      reason: '原版参考图区域支持桌面文件拖入，Flutter 对话框也必须暴露投放目标',
    );
    await tester.tap(find.descendant(
      of: dialog,
      matching: find.byIcon(Icons.add_photo_alternate_outlined),
    ));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, '智能生成'));
    await tester.pumpAndSettle();
    expect(gateway.textStages, ['asset_extract']);
    expect(_promptField(tester, dialog).controller!.text, '月下白衣剑修，冷色国风插画');

    await _chooseDropdown(tester, '请选择模型', '测试供应商 · 图像测试');
    await tester.tap(find.text('2K'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '生成'));
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      db.select(
          "SELECT id FROM o_tasks WHERE taskClass='asset_image_generation'"),
      isNotEmpty,
      reason: '点击生成必须先将图片任务入队',
    );
    await _pumpUntil(
      tester,
      () => engine.assetImages(assetId).last.state == stateDone,
    );
    // 任务已落库，后续只核验候选选择与保存；先停掉 fake-async 周期队列。
    engine.queue.dispose();
    await tester.pump();

    expect(gateway.imagePrompts.single, contains('月下白衣剑修'));
    expect(gateway.imageModels, ['${provider.id}:image-test']);
    expect(gateway.imageQualities, ['2K']);
    expect(gateway.imageReferences.single, hasLength(1));
    final generated = engine.assetImages(assetId);
    expect(generated, hasLength(2));
    expect(generated.last.state, stateDone);
    expect(engine.getAssets(projectId, type: 'role').data.single.imageId,
        generated.last.id);

    final generatedPath = engine.mediaAbsPath(generated.last.filePath!);
    final generatedImage = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is FileImage &&
            (widget.image as FileImage).file.path == generatedPath,
      ),
    );
    expect(generatedImage, findsOneWidget);
    expect(
      find.descendant(
        of: find
            .ancestor(
              of: generatedImage,
              matching: find.byType(GestureDetector),
            )
            .first,
        matching: find.byKey(const Key('asset-image-candidate-preview')),
      ),
      findsOneWidget,
      reason: '候选图应提供独立预览入口，不能挤占点击选中语义',
    );
    await tester.tap(find
        .ancestor(
          of: generatedImage,
          matching: find.byType(GestureDetector),
        )
        .first);
    await tester.pump();
    await tester.tap(find.descendant(
        of: dialog, matching: find.widgetWithText(FilledButton, '确定')));
    await tester.pumpAndSettle();

    final asset = engine.getAssets(projectId, type: 'role').data.single;
    expect(asset.prompt, '月下白衣剑修，冷色国风插画');
    expect(asset.imageId, generated.last.id);
  });

  testWidgets('移动端资产生图以全屏表单呈现，模型、候选和确认操作均可达',
      (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final provider = await engine.createProvider(
      name: '移动图像供应商',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'mobile-image-test',
        'label': '移动图像测试',
        'kind': 'image',
        'enabled': true,
      },
    ]);

    await tester.pumpWidget(app(width: 390, height: 780));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '生成'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing,
        reason: '窄屏必须打开可返回的全屏表单，而非挤压桌面对话框');
    expect(find.text('生成图片 · 林逸'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);

    await _chooseDropdown(tester, '请选择模型', '移动图像供应商 · 移动图像测试');
    await tester.dragUntilVisible(
      find.text('生成结果'),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -240),
    );
    expect(find.text('生成结果').hitTestable(), findsOneWidget,
        reason: '移动端不能因左侧表单变成长列而让候选网格不可达');
    expect(
      find.widgetWithText(FilledButton, '确定').hitTestable(),
      findsOneWidget,
      reason: '确认动作应固定在全屏表单底部，滚动后仍可操作',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未选择图片模型时，生成按钮不会创建任务', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '生成'));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(dfToastKey),
        matching: find.text('请选择模型'),
      ),
      findsOneWidget,
      reason: 'ToonFlow 原版在提交生图前要求选择模型，不能把空模型任务交给队列',
    );
    expect(
      db.select(
          "SELECT id FROM o_tasks WHERE taskClass='asset_image_generation'"),
      isEmpty,
    );
  });

  testWidgets('参考图选择器接受 ToonFlow image/* 范围的常见图片格式', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _ImageFileSelector([
      XFile.fromData(base64Decode(_pngBase64), path: 'reference.png'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    await tester.tap(find.descendant(
      of: dialog,
      matching: find.byIcon(Icons.add_photo_alternate_outlined),
    ));
    await tester.pumpAndSettle();

    final typeGroup = selector.acceptedTypeGroupCalls.single!.single;
    expect(typeGroup.mimeTypes, contains('image/*'));
    expect(typeGroup.webWildCards, contains('image/*'));
    expect(typeGroup.uniformTypeIdentifiers, contains('public.image'));
    expect(
      typeGroup.extensions,
      containsAll(<String>[
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'bmp',
        'tif',
        'tiff',
        'heic',
        'heif',
        'avif',
        'svg',
      ]),
      reason: 'Windows/Linux 文件对话框只依赖扩展名，不能因补充 image/* 而缩小支持面',
    );
  });

  testWidgets('参考图拖入接受 image MIME，即使文件扩展名不在本地白名单', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();

    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            base64Decode(_pngBase64),
            name: 'camera-export.unknown',
            mimeType: 'image/png',
            path: '/tmp/camera-export.unknown',
          ),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
      reason: 'ToonFlow 的 image/* 接受语义不能因未知扩展名而丢弃系统已识别的图片',
    );
  });

  testWidgets('删除候选图片必须确认，取消后保留图片', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog).first;
    await tester.tap(
      find.descendant(of: dialog, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pumpAndSettle();

    final confirmDialog = find.byType(AlertDialog);
    expect(confirmDialog, findsOneWidget);
    expect(
      find.descendant(of: confirmDialog, matching: find.text('确认删除')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(
      of: confirmDialog,
      matching: find.widgetWithText(TextButton, '取消'),
    ));
    await tester.pumpAndSettle();

    expect(engine.assetImages(assetId), hasLength(1));
  });

  testWidgets('上传自定义图片后，必须点选候选图才能保存', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    final selector = _ImageFileSelector([
      XFile.fromData(base64Decode(_pngBase64), path: 'custom.png'),
    ]);
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog).first;
    final confirm = find.descendant(
      of: dialog,
      matching: find.widgetWithText(FilledButton, '确定'),
    );

    await tester
        .tap(find.descendant(of: dialog, matching: find.byIcon(Icons.add)));
    await tester.pumpAndSettle();
    expect(selector.openFileCalls, 1);
    expect(
      tester.widget<FilledButton>(confirm).onPressed,
      isNull,
      reason: '原版在 selectedImageIndex 为空时禁用确定，上传本身不能视为选择',
    );

    final customCandidate = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect(customCandidate, findsOneWidget);
    await tester.tap(find
        .ancestor(
          of: customCandidate,
          matching: find.byType(GestureDetector),
        )
        .first);
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(engine.assetImages(assetId), hasLength(2));
  });
}

TextField _promptField(WidgetTester tester, Finder dialog) =>
    tester.widget<TextField>(
      find.descendant(of: dialog, matching: find.byType(TextField)),
    );

Future<void> _chooseDropdown(
  WidgetTester tester,
  String closedLabel,
  String optionLabel,
) async {
  final field = find.ancestor(
    of: find.text(closedLabel),
    matching: find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String>,
    ),
  );
  final modelField = find.ancestor(
    of: find.text(closedLabel),
    matching: find.byType(InkWell),
  );
  await tester.tap(field.evaluate().isNotEmpty ? field : modelField.first);
  await tester.pumpAndSettle();
  // DFSelect 弹层把「供应商 · 模型」拆成角标+模型名两段：整段找不到时点模型名。
  var option = find.text(optionLabel);
  if (option.evaluate().isEmpty && optionLabel.contains(' · ')) {
    option = find.text(optionLabel.split(' · ').last);
  }
  await tester.tap(option.last);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (done()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for fake image generation');
}
