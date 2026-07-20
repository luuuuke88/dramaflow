import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/image_flow.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/screens/production/image_flow_editor.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 最小合法 PNG（1x1），供素材/分镜选图缩略图渲染。
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

class _Gateway implements ProviderGateway {
  int imageCalls = 0;
  String? lastEditInstruction;
  List<String> lastReferenceAbsPaths = const [];
  String? lastMaskAbsPath;

  @override
  Future<String> generateImage(String prompt, String projectId,
      {required String stage,
      CancelToken? cancelToken,
      List<String> referenceAbsPaths = const [],
      String? editInstruction,
      String? maskAbsPath,
      String? ratio,
      String? quality,
      String? modelOverride}) async {
    imageCalls++;
    lastEditInstruction = editInstruction;
    lastReferenceAbsPaths = referenceAbsPaths;
    lastMaskAbsPath = maskAbsPath;
    return 'p/gen.png';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;

  // 装一个 enabled 图片模型，供模型选择器填充。
  Future<String> installImageModel() async {
    final provider = await engine.createProvider(
      name: 'TestVendor',
      protocol: 'openai_compatible',
      baseUrl: 'https://api.test/v1',
      apiKey: 'sk-test',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'seedream-x',
        'label': 'Seedream X',
        'kind': 'image',
        'enabled': true,
        'capabilities': <String, dynamic>{},
      },
    ]);
    return '${provider.id}:seedream-x';
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-flow-editor-');
    final db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    projectId = engine.addProject(projectType: 'novel', name: '编辑器控件测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 通过一个按钮触发 showImageFlowEditor（需要 WidgetRef + BuildContext）。
  Widget host({
    int? flowId,
    int? scriptId,
    List<String> seedRefs = const [],
    Size size = const Size(1400, 1000),
    void Function(String rel, int flowId)? onApply,
  }) {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Consumer(builder: (context, ref, _) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showImageFlowEditor(
                    context,
                    ref,
                    projectId: projectId,
                    flowId: flowId,
                    scriptId: scriptId,
                    seedReferenceRelPaths: seedRefs,
                    onApply: onApply ?? (_, __) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // 生成节点默认未选中（折叠）；点击节点标题展开参数面板。
  Future<void> expandGeneratedNode(WidgetTester tester) async {
    // AppBar 与节点内均有「图片生成」，节点标题是最后一个（画布层在下、AppBar 在上，
    // 但 find 返回按 widget 树顺序）——取节点内的标题（Icons.auto_fix_high 同行）。
    final nodeTitle = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('图片生成'),
    );
    await tester.tap(nodeTitle.last, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  // 三个 DropdownButtonFormField 顺序：模型(0)、画幅(1)、清晰度(2)。
  Finder modelDrop() => find.byType(DropdownButtonFormField<String>).at(0);
  Finder ratioDrop() => find.byType(DropdownButtonFormField<String>).at(1);
  Finder qualityDrop() => find.byType(DropdownButtonFormField<String>).at(2);

  testWidgets('展开生成节点面板：渲染画幅/清晰度/模型三个控件', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await installImageModel();
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    // 三个下拉控件均已渲染。
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    // 画幅默认 16:9（项目无 videoRatio → 回退），清晰度默认空显示 hint「质量」。
    expect(find.text('16:9'), findsWidgets);
    expect(find.text('质量'), findsOneWidget);
    // 模型选择器已选中项目默认模型为空 → 显示 hint「模型」。
    expect(find.text('模型'), findsOneWidget);
  });

  testWidgets('三项未齐时生成按钮禁用；补齐后启用并可生成', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await installImageModel();
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    // 输入 prompt（默认项目无 model/quality，ratio 回退 16:9）。
    await tester.enterText(find.byType(TextField).first, '少年拔剑');
    await tester.pumpAndSettle();

    // 此时 model + quality 仍空 → 生成按钮禁用。
    final genBtn = find.widgetWithText(OutlinedButton, '生成');
    expect(genBtn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(genBtn).onPressed, isNull,
        reason: 'model/quality 未选，生成应禁用');

    // 选模型。
    await tester.tap(modelDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('TestVendor · Seedream X').last);
    await tester.pumpAndSettle();

    // 选质量 2K。
    await tester.tap(qualityDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('2K').last);
    await tester.pumpAndSettle();

    // 现在三项齐全，生成按钮启用。
    expect(tester.widget<OutlinedButton>(genBtn).onPressed, isNotNull,
        reason: '三项齐全，生成应启用');

    await tester.tap(genBtn);
    await tester.pumpAndSettle();
    expect(gateway.imageCalls, 1);
  });

  testWidgets('选择画幅/清晰度/模型后保存，持久化到节点 data', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modelValue = await installImageModel();
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    // 选模型。
    await tester.tap(modelDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('TestVendor · Seedream X').last);
    await tester.pumpAndSettle();

    // 选画幅 9:16。
    await tester.tap(ratioDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:16').last);
    await tester.pumpAndSettle();

    // 选清晰度 4K。
    await tester.tap(qualityDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('4K').last);
    await tester.pumpAndSettle();

    // 点保存（AppBar 保存图标）。
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    // 从引擎回读最新 flow，校验 generated 节点 data。
    final flows =
        engine.db.select('SELECT id FROM o_imageFlow ORDER BY id DESC LIMIT 1');
    expect(flows, isNotEmpty, reason: '保存应写入 o_imageFlow');
    final flowId = flows.first['id'] as int;
    final data = engine.getImageFlow(flowId);
    final gen = data.nodes.firstWhere((n) => n.type == 'generated');
    expect(gen.data['ratio'], '9:16');
    expect(gen.data['quality'], '4K');
    expect(gen.data['model'], modelValue);
  });

  testWidgets('图片流生成节点拖动后保存新的画布位置', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flowId = engine.saveImageFlow([
      const ImageFlowNode(
        id: 'g0',
        type: 'generated',
        x: 80,
        y: 100,
        data: {'prompt': '御剑少年', 'ratio': '16:9'},
      ),
    ], const []);

    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 生成节点的图片区不是表单控件；拖动它应移动节点而不是平移整个画布。
    await tester.drag(
      find.byIcon(Icons.image_not_supported_outlined),
      const Offset(60, 30),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final saved = engine.getImageFlow(flowId);
    final generated = saved.nodes.singleWhere((node) => node.id == 'g0');
    expect(generated.x, closeTo(140, 0.1));
    expect(generated.y, closeTo(130, 0.1));
  });

  testWidgets('移动端图片流生成节点拖动后保存新的画布位置', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flowId = engine.saveImageFlow([
      const ImageFlowNode(
        id: 'g0',
        type: 'generated',
        x: 40,
        y: 80,
        data: {'prompt': '雨中持剑', 'ratio': '9:16'},
      ),
    ], const []);

    await tester.pumpWidget(
      host(flowId: flowId, size: const Size(390, 900)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final imagePlaceholder = find.byIcon(Icons.image_not_supported_outlined);
    expect(imagePlaceholder.hitTestable(), findsOneWidget);
    await tester.drag(imagePlaceholder, const Offset(30, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final saved = engine.getImageFlow(flowId);
    final generated = saved.nodes.singleWhere((node) => node.id == 'g0');
    expect(generated.x, closeTo(70, 0.1));
    expect(generated.y, closeTo(100, 0.1));
  });

  testWidgets('图片流生成节点的参数区拖动不会移动节点', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flowId = engine.saveImageFlow([
      const ImageFlowNode(
        id: 'g0',
        type: 'generated',
        x: 80,
        y: 100,
        data: {'prompt': '剑光划过雨幕', 'ratio': '16:9'},
      ),
    ], const []);

    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    final prompt = find.byType(TextField).first;
    await tester.drag(prompt, const Offset(50, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final saved = engine.getImageFlow(flowId);
    final generated = saved.nodes.singleWhere((node) => node.id == 'g0');
    expect(generated.x, closeTo(80, 0.1));
    expect(generated.y, closeTo(100, 0.1));
  });

  // upload 节点内包裹图片区、可触发选图的 InkWell（onTap→选图来源表）。
  Finder uploadImageTap() => find.ancestor(
        of: find.byType(Image),
        matching: find.byType(InkWell),
      );

  // 造一个 upload 节点（其 imageRel 指向真实文件，缩略图正常渲染）。
  String seedUploadRel() => engine.saveFlowUploadImage(projectId, _pngBytes);

  testWidgets('上传节点选图弹出三来源：本地/素材库/分镜', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(seedRefs: [seedUploadRel()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 点击 upload 节点缩略图区域触发来源选择表。
    await tester.tap(uploadImageTap().first);
    await tester.pumpAndSettle();
    expect(find.text('本地文件'), findsOneWidget);
    expect(find.text('从素材库选择'), findsOneWidget);
    expect(find.text('从分镜选择'), findsOneWidget);
  });

  testWidgets('从素材库选择：挑一张已生成资产图设为参考', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 造一个有已选中图片的角色资产。
    final assetId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final rel = engine.media.saveImage(_pngBytes, '$projectId');
    engine.attachAssetImage(assetId, rel);

    await tester.pumpWidget(host(seedRefs: [seedUploadRel()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(uploadImageTap().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从素材库选择'));
    await tester.pumpAndSettle();

    // 选图对话框列出资产名，点击选择。
    expect(find.text('选择参考图'), findsWidgets);
    expect(find.text('林朝雪'), findsOneWidget);
    await tester.tap(find.text('林朝雪'));
    await tester.pumpAndSettle();
    // 对话框关闭（不再有资产名）。
    expect(find.text('林朝雪'), findsNothing);
  });

  testWidgets('上传节点可直接采用已有参考图并保存当前流程', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sourceRel = seedUploadRel();
    String? appliedRel;
    int? appliedFlowId;
    await tester.pumpWidget(host(
      seedRefs: [sourceRel],
      onApply: (rel, flowId) {
        appliedRel = rel;
        appliedFlowId = flowId;
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-apply-u0')));
    await tester.pumpAndSettle();

    expect(appliedRel, sourceRel);
    expect(appliedFlowId, isNotNull);
    expect(engine.getImageFlow(appliedFlowId!).nodes, isNotEmpty);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('移动端 390px：上传节点可直接采用参考图', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sourceRel = seedUploadRel();
    String? appliedRel;
    await tester.pumpWidget(host(
      size: const Size(390, 900),
      seedRefs: [sourceRel],
      onApply: (rel, _) => appliedRel = rel,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final apply = find.byKey(const Key('image-flow-apply-u0'));
    expect(apply.hitTestable(), findsOneWidget);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(appliedRel, sourceRel);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('生成节点可从素材库直接设为结果后采用', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final assetId = engine.addAsset(
        projectId: projectId, type: 'role', name: '直接采用图', describe: 'x');
    final assetRel = engine.media.saveImage(_pngBytes, '$projectId');
    engine.attachAssetImage(assetId, assetRel);
    String? appliedRel;
    await tester.pumpWidget(host(
      seedRefs: [seedUploadRel()],
      onApply: (rel, _) => appliedRel = rel,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-seed-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从素材库选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接采用图'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);
    await tester.tap(find.byKey(const Key('image-flow-apply-g1')));
    await tester.pumpAndSettle();

    expect(appliedRel, assetRel);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('移动端 390px：生成节点首屏可操作，素材参考与生成参数可保存', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modelValue = await installImageModel();
    final assetId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    final assetRel = engine.media.saveImage(_pngBytes, '$projectId');
    engine.attachAssetImage(assetId, assetRel);

    await tester.pumpWidget(
        host(size: const Size(390, 900), seedRefs: [seedUploadRel()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final generatedTitle = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('图片生成'),
    );
    final generatedTitleRect = tester.getRect(generatedTitle.last);
    expect(generatedTitleRect.right, lessThanOrEqualTo(390),
        reason: '紧凑视图需要先把生成节点缩放到可视区域内');
    expect(generatedTitle.hitTestable(), findsOneWidget,
        reason: '390px 宽度下生成节点应在首屏可点击，不能只停留在画布右侧视野外');

    await tester.tap(uploadImageTap().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从素材库选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('林朝雪'));
    await tester.pumpAndSettle();

    await tester.tap(generatedTitle.hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '雪地御剑回眸');
    await tester.pumpAndSettle();

    await tester.tap(modelDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('TestVendor · Seedream X').last);
    await tester.pumpAndSettle();

    await tester.tap(ratioDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:16').last);
    await tester.pumpAndSettle();

    await tester.tap(qualityDrop());
    await tester.pumpAndSettle();
    await tester.tap(find.text('2K').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final rows =
        engine.db.select('SELECT id FROM o_imageFlow ORDER BY id DESC LIMIT 1');
    expect(rows, isNotEmpty);
    final data = engine.getImageFlow(rows.first['id'] as int);
    final upload = data.nodes.firstWhere((n) => n.type == 'upload');
    final generated = data.nodes.firstWhere((n) => n.type == 'generated');
    expect(upload.data['image'], assetRel);
    expect(generated.data['references'], [
      {'image': assetRel}
    ]);
    expect(generated.data['prompt'], '雪地御剑回眸');
    expect(generated.data['model'], modelValue);
    expect(generated.data['ratio'], '9:16');
    expect(generated.data['quality'], '2K');
  });

  testWidgets('从分镜选择：无 scriptId 时提示无图片', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(seedRefs: [seedUploadRel()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(uploadImageTap().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从分镜选择'));
    await tester.pumpAndSettle();
    expect(find.text('分镜暂无已生成首帧图'), findsOneWidget);
  });

  testWidgets('从分镜选择：列出本剧集已生成首帧图', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine.installStoryboardPipeline();
    final scriptId =
        engine.addScript(projectId: projectId, name: '第一集', content: 'x');
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'p');
    final rel = engine.media.saveImage(_pngBytes, '$projectId');
    engine.setStoryboardImage(sbId, rel);

    await tester
        .pumpWidget(host(scriptId: scriptId, seedRefs: [seedUploadRel()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(uploadImageTap().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从分镜选择'));
    await tester.pumpAndSettle();
    // 首帧图以镜头序号 S01 标注。
    expect(find.text('S01'), findsOneWidget);
  });

  testWidgets('连线中点 × 手柄可删除单条连线', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // seedRefs 会造 1 个 upload + 1 个 generated + 1 条连线。
    await tester.pumpWidget(host(seedRefs: [seedUploadRel()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 删除连线的 × 手柄（Tooltip「删除该连线」）。
    final delDot = find.byTooltip('删除该连线');
    expect(delDot, findsOneWidget);
    await tester.tap(delDot);
    await tester.pumpAndSettle();

    // 连线被删后 × 手柄消失，并弹出提示。
    expect(find.byTooltip('删除该连线'), findsNothing);
    expect(find.text('已删除连线'), findsOneWidget);
  });

  testWidgets('生成节点可作为参考源连接到下一个生成节点', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final generatedRel = engine.media.saveImage(_pngBytes, '$projectId');
    final flowId = engine.saveImageFlow([
      ImageFlowNode(
        id: 'g1',
        type: 'generated',
        x: 400,
        y: 40,
        data: {'generatedImage': generatedRel},
      ),
      const ImageFlowNode(
        id: 'g2',
        type: 'generated',
        x: 400,
        y: 300,
        data: {},
      ),
    ], const []);
    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-source-g1')));
    await tester.tap(find.byKey(const Key('image-flow-target-g2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final data = engine.getImageFlow(flowId);
    expect(
      data.edges.any((edge) => edge.source == 'g1' && edge.target == 'g2'),
      isTrue,
    );
    final secondGenerated = data.nodes.firstWhere((node) => node.id == 'g2');
    expect(secondGenerated.data['references'], [
      {'image': generatedRel}
    ]);
  });

  testWidgets('图片流拒绝与既有边方向相反的重复连线', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(seedRefs: const ['p/source.png']));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '生成节点'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-source-g1')));
    await tester.tap(find.byKey(const Key('image-flow-target-g2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-source-g2')));
    await tester.tap(find.byKey(const Key('image-flow-target-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final flowId = engine.db
        .select('SELECT id FROM o_imageFlow ORDER BY id DESC LIMIT 1')
        .single['id'] as int;
    final generatedEdges = engine
        .getImageFlow(flowId)
        .edges
        .where((edge) =>
            (edge.source == 'g1' && edge.target == 'g2') ||
            (edge.source == 'g2' && edge.target == 'g1'))
        .toList();
    expect(generatedEdges, hasLength(1));
    expect(
      generatedEdges.single,
      isA<ImageFlowEdge>()
          .having((edge) => edge.source, 'source', 'g1')
          .having((edge) => edge.target, 'target', 'g2'),
    );
  });

  testWidgets('移动端 390px：生成节点可作为下一节点的参考源', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        host(size: const Size(390, 900), seedRefs: const ['p/source.png']));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-add-generated')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-flow-source-g1')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const Key('image-flow-target-g2')).hitTestable(),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('image-flow-source-g1')));
    await tester.tap(find.byKey(const Key('image-flow-target-g2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final flowId = engine.db
        .select('SELECT id FROM o_imageFlow ORDER BY id DESC LIMIT 1')
        .single['id'] as int;
    expect(
      engine
          .getImageFlow(flowId)
          .edges
          .any((edge) => edge.source == 'g1' && edge.target == 'g2'),
      isTrue,
    );
  });

  testWidgets('图片流自动布局按连线重排为从左到右的层级', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flowId = engine.saveImageFlow(const [
      ImageFlowNode(id: 'g1', type: 'generated', x: 800, y: 500, data: {}),
      ImageFlowNode(id: 'g2', type: 'generated', x: 40, y: 40, data: {}),
    ], const [
      ImageFlowEdge(id: 'e1', source: 'g1', target: 'g2'),
    ]);
    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-auto-layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final data = engine.getImageFlow(flowId);
    final first = data.nodes.firstWhere((node) => node.id == 'g1');
    final second = data.nodes.firstWhere((node) => node.id == 'g2');
    expect(first.x, lessThan(second.x));
    expect(
      find.byKey(const Key('image-flow-target-g2')).hitTestable(),
      findsOneWidget,
      reason: '重新布局后目标节点必须仍适配在当前视口内',
    );
  });

  testWidgets('移动端 390px：自动布局入口可用并保存 LR 层级', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flowId = engine.saveImageFlow(const [
      ImageFlowNode(id: 'g1', type: 'generated', x: 800, y: 500, data: {}),
      ImageFlowNode(id: 'g2', type: 'generated', x: 40, y: 40, data: {}),
    ], const [
      ImageFlowEdge(id: 'e1', source: 'g1', target: 'g2'),
    ]);
    await tester.pumpWidget(host(flowId: flowId, size: const Size(390, 900)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final layoutButton = find.byKey(const Key('image-flow-auto-layout'));
    expect(layoutButton.hitTestable(), findsOneWidget);
    await tester.tap(layoutButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-flow-save')));
    await tester.pumpAndSettle();

    final data = engine.getImageFlow(flowId);
    final first = data.nodes.firstWhere((node) => node.id == 'g1');
    final second = data.nodes.firstWhere((node) => node.id == 'g2');
    expect(first.x, lessThan(second.x));
    expect(find.byKey(const Key('image-flow-target-g2')).hitTestable(),
        findsOneWidget);
  });

  testWidgets('关闭已有图片流时确认并保存当前节点结构', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flowId = engine.saveImageFlow(const [
      ImageFlowNode(id: 'g1', type: 'generated', x: 400, y: 40, data: {}),
    ], const []);
    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '生成节点'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const Key('image-flow-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(engine.getImageFlow(flowId).nodes, hasLength(2));
  });

  testWidgets('移动端 390px：关闭新图片流确认后不创建空记录', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        host(size: const Size(390, 900), seedRefs: const ['p/source.png']));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('image-flow-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(engine.db.select('SELECT id FROM o_imageFlow'), isEmpty);
  });

  testWidgets('已生成节点可重绘：当前结果作为参考图并传递修改意见', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await installImageModel();
    final generatedRel = engine.media.saveImage(_pngBytes, '$projectId');
    final flowId = engine.saveImageFlow([
      ImageFlowNode(
        id: 'g0',
        type: 'generated',
        x: 40,
        y: 40,
        data: {
          'prompt': '白衣少年',
          'generatedImage': generatedRel,
          'model': null,
          'ratio': '16:9',
          'quality': '2K',
        },
      ),
    ], const []);

    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, '重绘'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '把衣服改成红色');
    await tester.tap(find.widgetWithText(FilledButton, '重绘'));
    await tester.pumpAndSettle();

    expect(gateway.imageCalls, 1);
    expect(gateway.lastEditInstruction, '把衣服改成红色');
    expect(gateway.lastReferenceAbsPaths, [
      engine.mediaAbsPath(generatedRel),
    ]);
  });

  testWidgets('已生成节点可局部重绘：画笔 mask 随图片编辑请求传递', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await installImageModel();
    final generatedRel = engine.media.saveImage(_pngBytes, '$projectId');
    final flowId = engine.saveImageFlow([
      ImageFlowNode(
        id: 'g0',
        type: 'generated',
        x: 40,
        y: 40,
        data: {
          'prompt': '白衣少年',
          'generatedImage': generatedRel,
          'model': null,
          'ratio': '16:9',
          'quality': '2K',
        },
      ),
    ], const []);

    await tester.pumpWidget(host(flowId: flowId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, '局部重绘'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '只重绘袖口');
    await tester.drag(
        find.byKey(const Key('mask-paint-area')), const Offset(48, 0));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '局部重绘'));
    await tester.tap(find.widgetWithText(FilledButton, '局部重绘'));
    await tester.pumpAndSettle();

    expect(gateway.imageCalls, 1);
    expect(gateway.lastEditInstruction, '只重绘袖口');
    expect(gateway.lastReferenceAbsPaths, [
      engine.mediaAbsPath(generatedRel),
    ]);
    expect(gateway.lastMaskAbsPath, isNotNull);
    expect(File(gateway.lastMaskAbsPath!).existsSync(), isTrue);
  });

  testWidgets('移动端 390px：已生成节点可局部重绘并传递 mask', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await installImageModel();
    final generatedRel = engine.media.saveImage(_pngBytes, '$projectId');
    final flowId = engine.saveImageFlow([
      ImageFlowNode(
        id: 'g0',
        type: 'generated',
        x: 40,
        y: 40,
        data: {
          'prompt': '青衣少女',
          'generatedImage': generatedRel,
          'model': null,
          'ratio': '9:16',
          'quality': '1K',
        },
      ),
    ], const []);

    await tester.pumpWidget(host(flowId: flowId, size: const Size(390, 900)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expandGeneratedNode(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, '局部重绘'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '只重绘发簪');
    await tester.drag(
        find.byKey(const Key('mask-paint-area')), const Offset(32, 0));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '局部重绘'));
    await tester.tap(find.widgetWithText(FilledButton, '局部重绘'));
    await tester.pumpAndSettle();

    expect(gateway.imageCalls, 1);
    expect(gateway.lastEditInstruction, '只重绘发簪');
    expect(gateway.lastReferenceAbsPaths, [
      engine.mediaAbsPath(generatedRel),
    ]);
    expect(gateway.lastMaskAbsPath, isNotNull);
    expect(File(gateway.lastMaskAbsPath!).existsSync(), isTrue);
  });
}
