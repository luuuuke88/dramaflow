import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/image_flow.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/production/image_flow_editor.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Gateway implements ProviderGateway {
  int imageCalls = 0;

  @override
  Future<String> generateImage(String prompt, String projectId,
      {required String stage,
      CancelToken? cancelToken,
      List<String> referenceAbsPaths = const [],
      String? editInstruction,
      String? ratio,
      String? quality,
      String? modelOverride}) async {
    imageCalls++;
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
  Widget host({int? flowId}) {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1400, 1000)),
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
                    onApply: (_, __) {},
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
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    // 从引擎回读最新 flow，校验 generated 节点 data。
    final flows = engine.db
        .select('SELECT id FROM o_imageFlow ORDER BY id DESC LIMIT 1');
    expect(flows, isNotEmpty, reason: '保存应写入 o_imageFlow');
    final flowId = flows.first['id'] as int;
    final data = engine.getImageFlow(flowId);
    final gen = data.nodes.firstWhere((n) => n.type == 'generated');
    expect(gen.data['ratio'], '9:16');
    expect(gen.data['quality'], '4K');
    expect(gen.data['model'], modelValue);
  });
}
