import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/assets/batch_generation_dialog.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _Gateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('x');

  @override
  Future<String> generateImage(String prompt, String projectId,
          {required String stage,
          CancelToken? cancelToken,
          List<String> referenceAbsPaths = const [],
          String? editInstruction,
          String? maskAbsPath,
          String? ratio,
          String? quality,
          String? modelOverride}) async =>
      'p/img.png';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-batchdlg-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _Gateway(),
      config: EngineConfig(db, isMobile: false),
    );
    // 本文件断言的是批量生成任务落库时携带的参数，不是确认闸弹窗本身
    // （闸本身已由 policy_confirm_test.dart 覆盖）；关闸避免每个用例都要多点一次确认。
    engine.config.update({'policy.confirmMoney': '0'});
    projectId =
        engine.addProject(projectType: 'novel', name: '批量测试', artStyle: '国风');
    // 两个带提示词的角色资产（生图要求 prompt 非空）
    engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林逸',
        describe: 'x',
        prompt: 'hero');
    engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '白容',
        describe: 'y',
        prompt: 'heroine');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({int mode = 2}) => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              return Center(
                child: ElevatedButton(
                  onPressed: () => showBatchGenerationDialog(context, ref,
                      projectId: projectId, type: 'role', mode: mode),
                  child: const Text('open'),
                ),
              );
            }),
          ),
        ),
      );

  testWidgets('图片模式：渲染模型/分辨率/并发控件，并把参数带入任务', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 控件存在：模型/分辨率/并发/补充提示词只在 prompt 模式出现
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('分辨率'), findsOneWidget);
    expect(find.text('并发数'), findsOneWidget);
    expect(find.text('2K'), findsOneWidget);

    // 选 2K 分辨率
    await tester.tap(find.text('2K'));
    await tester.pumpAndSettle();

    // 并发数改为 3
    await tester.enterText(find.widgetWithText(TextField, '1-8'), '3');
    await tester.pump();

    // 全选并生成图片
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '生成图片'));
    await tester.pumpAndSettle();

    // 断言：入队了 asset_image_generation 任务，relatedObjects 带 resolution/concurrentCount
    final row = db
        .select(
            "SELECT relatedObjects FROM o_tasks WHERE taskClass='asset_image_generation' ORDER BY id DESC LIMIT 1")
        .single;
    final related =
        jsonDecode(row['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['resolution'], '2K');
    expect(related['concurrentCount'], 3);
    expect((related['items'] as List).length, 2);
  });

  testWidgets('移动端提示词模式：补充提示词和并发参数带入任务', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(mode: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('补充提示词'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, '追加到润色系统提示词（可选）'), '统一国风赛璐璐');
    await tester.enterText(find.widgetWithText(TextField, '1-8'), '4');
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '生成提示词'));
    await tester.pumpAndSettle();

    final row = db
        .select(
            "SELECT id,relatedObjects FROM o_tasks WHERE taskClass='asset_prompt_polish' ORDER BY id DESC LIMIT 1")
        .single;
    final related =
        jsonDecode(row['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['concurrentCount'], 4);
    expect(related, isNot(contains('otherTextPrompt')));
    expect(row['relatedObjects'] as String, isNot(contains('统一国风赛璐璐')));
    expect(
      File(p.join(dir.path, 'task_payloads', '${row['id']}.payload'))
          .readAsStringSync(),
      '统一国风赛璐璐',
    );
    expect(related['ids'], hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端图片模式：模型/分辨率/并发参数带入任务', (tester) async {
    final provider = await engine.createProvider(
      name: 'Mobile Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'img-test',
        'label': '图片模型',
        'kind': 'image',
        'enabled': true,
      },
    ]);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _chooseDropdown(tester, '使用阶段默认', 'Mobile Provider · 图片模型');
    await tester.tap(find.text('4K'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '1-8'), '5');
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '生成图片'));
    await tester.pumpAndSettle();

    final row = db
        .select(
            "SELECT relatedObjects FROM o_tasks WHERE taskClass='asset_image_generation' ORDER BY id DESC LIMIT 1")
        .single;
    final related =
        jsonDecode(row['relatedObjects'] as String) as Map<String, dynamic>;
    expect(related['model'], '${provider.id}:img-test');
    expect(related['resolution'], '4K');
    expect(related['concurrentCount'], 5);
    expect((related['items'] as List), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端卡片：资产名过长时标题省略号截断而非溢出', (tester) async {
    const longName = '林逸的超长测试角色名称用于验证省略号截断效果不会溢出布局';
    expect(longName.length, greaterThanOrEqualTo(15));
    engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: longName,
        describe: 'x',
        prompt: 'long');

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final titleFinder = find.descendant(
      of: find.byType(ListTile),
      matching: find.text(longName),
    );
    expect(titleFinder, findsOneWidget);
    final titleText = tester.widget<Text>(titleFinder);
    expect(titleText.maxLines, 1);
    expect(titleText.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端真实机型高度：表格区域可滚动，不再因固定 430 高度而溢出', (tester) async {
    // setUp 已有 2 个资产（林逸/白容），再补 8 个凑满一页 10 条，
    // 复现"控件+选择栏+操作栏+表格"总内容远超 iPhone SE 可用高度的场景。
    for (var i = 0; i < 8; i++) {
      engine.addAsset(
          projectId: projectId,
          type: 'role',
          name: '批量角色$i',
          describe: 'x',
          prompt: 'p$i');
    }
    const lastRowName = '批量角色7';

    // iPhone SE 可用 body 高度（约 480-500px），远小于其余用例使用的 900。
    tester.view.physicalSize = const Size(390, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 关键回归点：修复前，430px 固定高度 + 不可滚动内层列表会在此处抛出
    // RenderFlex/overflow 异常。
    expect(tester.takeException(), isNull);

    // 末行在树中已构建（shrinkWrap 撑满内容），但初始处于可视区域之外。
    final lastRow = find.text(lastRowName);
    expect(lastRow, findsOneWidget);
    final offscreenCenter = tester.getCenter(lastRow);
    expect(offscreenCenter.dy, greaterThan(tester.view.physicalSize.height));

    // 表格区域可真正滚动到该行。
    await tester.dragUntilVisible(
      lastRow,
      find.byKey(const Key('batch-table-scroll')),
      const Offset(0, -80),
    );
    expect(find.text(lastRowName), findsOneWidget);
    final visibleCenter = tester.getCenter(find.text(lastRowName));
    expect(visibleCenter.dy, lessThan(tester.view.physicalSize.height));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  String closedLabel,
  String optionLabel,
) async {
  await tester.ensureVisible(find.text(closedLabel).first);
  final field = find.ancestor(
    of: find.text(closedLabel).first,
    matching: find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String>,
    ),
  );
  final modelField = find.ancestor(
    of: find.text(closedLabel).first,
    matching: find.byType(InkWell),
  );
  await tester.tap(field.evaluate().isNotEmpty ? field.first : modelField.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}
