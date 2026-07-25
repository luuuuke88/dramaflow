import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/cornerscape/corner_scape_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  int textCalls = 0;
  Completer<TextResult>? pendingText;

  @override
  Future<TextResult> generateText(
    String system,
    String user, {
    required String stage,
    dynamic cancelToken,
  }) async {
    textCalls++;
    final pending = pendingText;
    if (pending != null) return pending.future;
    return const TextResult('润色后的雪山剑客');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _imageModel = 'test-image:corner-image';
const _imageModelLabel = '测试图片 · Corner Image';

void main() {
  late Directory dir;
  late Engine engine;
  late _NoopGateway gateway;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-cornerscape-');
    final db = openEngineDb(':memory:');
    gateway = _NoopGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    engine.config.update({'policy.confirmMoney': '0'});
    engine.installAudioBindPipeline();
    engine.db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('asset_prompt_polish','asset_prompt_polish','本地测试提示词',NULL)",
    );
    engine.saveVisualManual(
      name: '测试画风',
      data: {for (final key in visualManualKeys) key: '本地手册[$key]'},
    );
    engine.db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'test-image',
        1,
        jsonEncode({'name': '测试图片', 'protocol': 'openai_compatible'}),
        jsonEncode([
          {
            'id': _imageModel,
            'providerId': 'test-image',
            'modelId': 'corner-image',
            'label': 'Corner Image',
            'kind': 'image',
            'capabilities': {},
            'enabled': true,
          },
        ]),
      ],
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '塑角造景测试',
      artStyle: '测试画风',
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({double width = 1400}) {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: CornerScapeScreen(projectId: projectId)),
        ),
      ),
    );
  }

  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(width: 1400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> selectImageModel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('model-select-field-image')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_imageModelLabel.split(' · ').last).last);
    await tester.pump();
  }

  Future<void> confirmBatchImageGeneration(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, '生成图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pump();
  }

  void setImageState(int assetId, String state) {
    engine.db.execute(
      'INSERT INTO o_image (assetsId,type,state) VALUES (?,?,?)',
      [assetId, 'role', state],
    );
    final imageId = engine.db.lastInsertRowId;
    engine.db.execute(
      'UPDATE o_assets SET imageId=? WHERE id=?',
      [imageId, assetId],
    );
  }

  bool isSelected(WidgetTester tester, int assetId) {
    final checkbox = tester.widget<Checkbox>(
      find.byKey(Key('cornerscape-select-$assetId')),
    );
    return checkbox.value ?? false;
  }

  testWidgets(
    '390dp 塑角造景可筛选资产、选择卡片、打开详情并发起批量生成',
    (tester) async {
      tester.view.physicalSize = const Size(390, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final role = engine.addAsset(
        projectId: projectId,
        type: 'role',
        name: '林朝雪',
        describe: '',
        prompt: '剑客',
      );
      final scene = engine.addAsset(
        projectId: projectId,
        type: 'scene',
        name: '山门雪夜',
        describe: '',
        prompt: '雪夜',
      );
      final tool = engine.addAsset(
        projectId: projectId,
        type: 'tool',
        name: '灵剑',
        describe: '',
        prompt: '长剑',
      );
      engine.config.update({'policy.confirmMoney': '1'});

      await tester.pumpWidget(app(width: 390));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final scroll = find.byKey(const Key('cornerscape-scroll'));
      expect(scroll, findsOneWidget);
      await tester.dragUntilVisible(
        find.text('场景'),
        scroll,
        const Offset(0, -80),
      );
      await tester.tap(find.text('场景'));
      await tester.pump();
      expect(find.byKey(Key('cornerscape-card-$role')), findsNothing);
      expect(find.byKey(Key('cornerscape-card-$tool')), findsNothing);
      expect(find.byKey(Key('cornerscape-card-$scene')), findsOneWidget);

      await tester.ensureVisible(find.text('选择未生成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择未生成'));
      await tester.pump();
      expect(find.text('已选 1 项'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('model-select-field-image')),
      );
      await tester.pumpAndSettle();
      await selectImageModel(tester);

      final sceneCard = find.byKey(Key('cornerscape-card-$scene'));
      await tester.dragUntilVisible(
        sceneCard,
        scroll,
        const Offset(0, -100),
      );
      expect(isSelected(tester, scene), isTrue);
      expect(tester.getSize(sceneCard).width, greaterThanOrEqualTo(350));
      expect(tester.getSize(sceneCard).width, lessThanOrEqualTo(390));
      await tester.tap(sceneCard);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('cornerscape-detail-$scene')),
        findsOneWidget,
      );

      final regenerate = find.byKey(Key('cornerscape-regenerate-$scene'));
      await tester.ensureVisible(regenerate);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(regenerate).onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('关闭').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('cornerscape-detail-$scene')),
        findsNothing,
      );

      final batchButton = find.widgetWithText(FilledButton, '生成图片');
      await tester.ensureVisible(batchButton);
      await tester.pumpAndSettle();
      await tester.tap(batchButton);
      await tester.pumpAndSettle();
      expect(find.text('花费确认'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pump();

      final imageJobs = (await engine.projectJobs(projectId))
          .where((job) => job.taskClass == 'asset_image_generation')
          .toList();
      expect(imageJobs, hasLength(1));
      expect(imageJobs.single.relatedObjectsJson['ids'], [scene]);
      expect(imageJobs.single.relatedObjectsJson['model'], _imageModel);
      expect(imageJobs.single.relatedObjectsJson['resolution'], '1K');
      expect(gateway.textCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('桌面塑角造景按类型筛选未生成资产并以模型和分辨率发起批量图片任务', (tester) async {
    final role = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '剑客',
    );
    engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
      prompt: '雪夜',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.text('角色'));
    await tester.tap(find.text('选择未生成'));
    await selectImageModel(tester);
    await tester.tap(find.text('2K'));
    await confirmBatchImageGeneration(tester);

    final tasks = await engine.projectJobs(projectId);
    final task = tasks.singleWhere(
      (job) => job.taskClass == 'asset_image_generation',
    );
    expect(task.relatedObjectsJson['ids'], [role]);
    expect(task.relatedObjectsJson['model'], _imageModel);
    expect(task.relatedObjectsJson['resolution'], '2K');
  });

  testWidgets('三步按钮的蓝色主按钮跟着当前该干的那一步走', (tester) async {
    // 缺提示词 → 第 1 步是主按钮。
    final blank = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '无提示词',
      describe: '',
    );
    await pumpDesktop(tester);
    expect(find.widgetWithText(FilledButton, '生成提示词'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '生成图片'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'AI 匹配音频'), findsOneWidget);

    // 提示词齐了但图还没出 → 主按钮移到第 2 步。
    engine.db.execute('UPDATE o_assets SET prompt=? WHERE id=?', ['剑客', blank]);
    await pumpDesktop(tester);
    expect(find.widgetWithText(OutlinedButton, '生成提示词'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '生成图片'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'AI 匹配音频'), findsOneWidget);

    // 图也出完了 → 主按钮移到第 3 步。
    setImageState(blank, stateDone);
    await pumpDesktop(tester);
    expect(find.widgetWithText(OutlinedButton, '生成提示词'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '生成图片'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'AI 匹配音频'), findsOneWidget);
  });

  testWidgets('未选择图片模型时确认批量生成不会创建图片任务', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '无模型角色',
      describe: '',
      prompt: '剑客',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-select-$assetId')));
    await confirmBatchImageGeneration(tester);

    expect(
      (await engine.projectJobs(projectId))
          .where((job) => job.taskClass == 'asset_image_generation'),
      isEmpty,
    );
  });

  testWidgets('项目保存的失效图片模型经确认也不会创建图片任务', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '失效模型角色',
      describe: '',
      prompt: '剑客',
    );
    engine.editProject(projectId, imageModel: 'removed:image-model');
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-select-$assetId')));
    await confirmBatchImageGeneration(tester);

    expect(
      (await engine.projectJobs(projectId))
          .where((job) => job.taskClass == 'asset_image_generation'),
      isEmpty,
    );
  });

  testWidgets('确认图片生成期间候选模型被移除时不会创建图片任务', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '确认期间移除模型的角色',
      describe: '',
      prompt: '剑客',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-select-$assetId')));
    await selectImageModel(tester);
    await tester.tap(find.widgetWithText(FilledButton, '生成图片'));
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);

    await engine.saveProviderModels('test-image', []);

    await tester.tap(find.text('确定'));
    await tester.pump();

    expect(
      (await engine.projectJobs(projectId))
          .where((job) => job.taskClass == 'asset_image_generation'),
      isEmpty,
    );
  });

  testWidgets('类型筛选会裁剪选择且音频匹配只提交当前可见选择', (tester) async {
    final role = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '剑客',
    );
    final scene = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '雪夜',
    );
    engine.addAsset(
      projectId: projectId,
      type: 'audio',
      name: '清冷女声',
      describe: '',
    );

    await pumpDesktop(tester);
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(isSelected(tester, role), isTrue);
    expect(isSelected(tester, scene), isTrue);

    await tester.tap(find.text('角色'));
    await tester.pump();
    expect(find.byKey(Key('cornerscape-card-$scene')), findsNothing);
    expect(isSelected(tester, role), isTrue);
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.text('AI 匹配音频'));
    await tester.pump();

    final tasks = await engine.projectJobs(projectId);
    final task = tasks.singleWhere((job) => job.taskClass == 'audio_bind');
    expect(task.relatedObjectsJson['assetIds'], [role]);
    expect(
      engine.db.select('SELECT audioBindState FROM o_assets WHERE id=?',
          [role]).single['audioBindState'],
      stateGenerating,
    );
  });

  testWidgets('快捷选择按提示词和图片状态选择并支持反选与清空', (tester) async {
    final empty = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '空白角色',
      describe: '',
      prompt: '',
    );
    final generating = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '生成角色',
      describe: '',
      prompt: '生成中',
    );
    final failed = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '失败角色',
      describe: '',
      prompt: '失败',
    );
    final done = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '完成角色',
      describe: '',
      prompt: '完成',
    );
    setImageState(generating, stateGenerating);
    setImageState(failed, stateFailed);
    engine.saveAssetImage(
      assetsId: done,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([1, 2, 3]),
    );

    await pumpDesktop(tester);

    await tester.tap(find.text('提示词为空'));
    await tester.pump();
    expect(isSelected(tester, empty), isTrue);
    expect(isSelected(tester, generating), isFalse);

    await tester.tap(find.text('选择未生成'));
    await tester.pump();
    expect(isSelected(tester, empty), isTrue);
    expect(isSelected(tester, failed), isFalse);

    await tester.tap(find.text('选择已完成'));
    await tester.pump();
    expect(isSelected(tester, done), isTrue);
    expect(isSelected(tester, empty), isFalse);

    await tester.tap(find.text('选择失败'));
    await tester.pump();
    expect(isSelected(tester, failed), isTrue);
    expect(isSelected(tester, done), isFalse);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 4 项'), findsOneWidget);

    await tester.tap(find.text('反选'));
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);
  });

  testWidgets('批量提示词命令只入队一次并隔离补充要求', (tester) async {
    final role = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '剑客',
    );
    final scene = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '雪夜',
    );

    await pumpDesktop(tester);
    await tester.tap(find.text('全选'));
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '补充提示词',
      ),
      '统一冷色调',
    );
    // 步骤按钮的外观随「当前该干哪一步」在实底/描边间切换，这里只按文案定位。
    await tester.tap(find.text('生成提示词'));
    await tester.pump();

    expect(find.text('提示词批量生成已提交'), findsOneWidget);
    expect(find.text('提示词生成完成'), findsNothing);
    final tasks = (await engine.projectJobs(projectId))
        .where((job) => job.taskClass == 'asset_prompt_polish')
        .toList();
    expect(tasks, hasLength(1));
    expect(tasks.single.relatedObjectsJson['ids'], [role, scene]);
    expect(
      tasks.single.relatedObjectsJson['privateInstructionVersion'],
      isNotNull,
    );
    expect(engine.readTaskPrivatePayload(tasks.single.id), '统一冷色调');
    expect(engine.assetsByIds([role, scene]).map((asset) => asset.promptState),
        everyElement(stateGenerating));
    expect(gateway.textCalls, 0);
  });

  testWidgets('桌面批量预览只展示已选资产的生成图', (tester) async {
    final selected = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '剑客',
    );
    final unselected = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
      prompt: '雪夜',
    );
    engine.saveAssetImage(
      assetsId: selected,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([1, 2, 3]),
    );
    engine.saveAssetImage(
      assetsId: unselected,
      projectId: projectId,
      type: 'scene',
      base64Image: base64Encode([4, 5, 6]),
    );

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-select-$selected')));
    await tester.tap(find.text('批量预览'));
    await tester.pumpAndSettle();

    expect(find.text('资产图片预览'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(gateway.textCalls, 0);
  });

  testWidgets('资产卡固定高度并呈现空白生成中失败完成四种状态', (tester) async {
    final empty = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '空白角色',
      describe: '',
    );
    final generating = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '生成角色',
      describe: '',
    );
    final failed = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '失败角色',
      describe: '',
    );
    final done = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '完成角色',
      describe: '',
    );
    setImageState(generating, stateGenerating);
    setImageState(failed, stateFailed);
    engine.saveAssetImage(
      assetsId: done,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([4, 5, 6]),
    );

    await pumpDesktop(tester);

    expect(find.text('等待生成'), findsOneWidget);
    expect(find.text('生成中'), findsOneWidget);
    expect(find.text('生成失败'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(
      find.byKey(Key('cornerscape-cancel-$generating')),
      findsNothing,
    );
    expect(find.byKey(Key('cornerscape-cancel-$empty')), findsNothing);

    final heights = [empty, generating, failed, done]
        .map(
          (id) =>
              tester.getSize(find.byKey(Key('cornerscape-card-$id'))).height,
        )
        .toSet();
    expect(heights, hasLength(1));

    await tester.tap(find.byKey(Key('cornerscape-card-$generating')));
    await tester.pump();
    expect(
      find.byKey(Key('cornerscape-detail-$generating')),
      findsNothing,
    );

    await tester.tap(find.byKey(Key('cornerscape-card-$done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(Key('cornerscape-detail-$done')), findsOneWidget);
  });

  testWidgets('390dp 卡片会呈现音频匹配中和失败状态，且失败资产仍可打开', (tester) async {
    tester.view.physicalSize = const Size(390, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final matching = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '匹配中的角色',
      describe: '剑客',
    );
    final failed = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '匹配失败的场景',
      describe: '雪夜',
    );
    engine.db.execute(
      'UPDATE o_assets SET audioBindState=? WHERE id IN (?,?)',
      [stateGenerating, matching, failed],
    );

    await tester.pumpWidget(app(width: 390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final scroll = find.byKey(const Key('cornerscape-scroll'));
    await tester.dragUntilVisible(
      find.byKey(Key('cornerscape-card-$matching')),
      scroll,
      const Offset(0, -100),
    );
    expect(find.text('音频匹配中'), findsOneWidget);
    engine.db.execute(
      'UPDATE o_assets SET audioBindState=? WHERE id=?',
      [stateFailed, failed],
    );
    await tester.pumpWidget(app(width: 390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.dragUntilVisible(
      find.byKey(Key('cornerscape-card-$failed')),
      scroll,
      const Offset(0, -100),
    );

    expect(find.text('音频匹配失败'), findsOneWidget);
    await tester.tap(find.byKey(Key('cornerscape-card-$failed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(Key('cornerscape-detail-$failed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面独立挂载时会随音频任务终态刷新卡片', (tester) async {
    final role = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '异步失败角色',
      describe: '剑客',
    );
    engine.addAsset(
      projectId: projectId,
      type: 'audio',
      name: '候选音色',
      describe: '',
    );
    engine.queue.start();

    try {
      await pumpDesktop(tester);
      await tester.tap(find.byKey(Key('cornerscape-select-$role')));
      await tester.tap(find.text('AI 匹配音频'));
      await tester.pump();
      expect(find.text('音频匹配中'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('音频匹配失败'), findsOneWidget,
          reason: '不应依赖外层 Shell 的任务徽标订阅才能刷新卡片');
    } finally {
      engine.queue.dispose();
    }
  });

  testWidgets('选择历史图会只更新当前图且历史数量不变，取消拒绝时任务保持等待，确认后标记为已取消', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '剑客',
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([1, 2, 3]),
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([4, 5, 6]),
    );
    final imageRows = engine.db.select(
      'SELECT id FROM o_image WHERE assetsId=? ORDER BY id ASC',
      [assetId],
    );
    final historyId = imageRows.first['id'] as int;
    final currentId = imageRows.last['id'] as int;

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('cornerscape-history-image-$historyId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('cornerscape-history-image-$currentId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('cornerscape-detail-current-image-$currentId')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(Key('cornerscape-history-image-$historyId')),
    );
    await tester.pump();

    expect(engine.assetsByIds([assetId]).single.imageId, historyId);
    expect(
      engine.db
          .select('SELECT id FROM o_image WHERE assetsId=?', [assetId]).length,
      imageRows.length,
    );
    expect(
      find.byKey(Key('cornerscape-detail-current-image-$historyId')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('关闭').first);
    await tester.pumpAndSettle();
    engine.config.update({'policy.confirmDestructive': '1'});
    final taskId = engine.generateAssetImages(
      projectId,
      [(assetsId: assetId, refImageBase64: null)],
    );
    tester.container().read(jobsGenerationProvider.notifier).bump();
    await tester.pump();

    await tester.tap(find.byKey(Key('cornerscape-cancel-$assetId')));
    await tester.pump();
    expect(find.text('危险操作确认'), findsOneWidget);
    final jobsGenerationBeforeCancel =
        tester.container().read(jobsGenerationProvider);
    expect(
      (await engine.projectJobs(projectId))
          .singleWhere((job) => job.id == taskId)
          .state,
      'pending',
    );

    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(
      (await engine.projectJobs(projectId))
          .singleWhere((job) => job.id == taskId)
          .state,
      'pending',
    );
    expect(find.byKey(Key('cornerscape-cancel-$assetId')), findsOneWidget);

    await tester.tap(find.byKey(Key('cornerscape-cancel-$assetId')));
    await tester.pump();
    expect(find.text('危险操作确认'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pump();

    final canceled = (await engine.projectJobs(projectId))
        .singleWhere((job) => job.id == taskId);
    expect(canceled.state, 'failed');
    expect(
      EngineException.fromReasonJson(
        engine.db.select(
          'SELECT reason FROM o_tasks WHERE id=?',
          [taskId],
        ).single['reason'] as String,
      )!
          .errKey,
      errCanceled,
    );
    expect(
      tester.container().read(jobsGenerationProvider),
      greaterThan(jobsGenerationBeforeCancel),
    );
    expect(
      find.byKey(Key('cornerscape-cancel-$assetId')),
      findsNothing,
    );
  });

  testWidgets('取消确认只针对打开确认框时捕获的任务', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '剑客',
    );
    engine.config.update({'policy.confirmDestructive': '1'});
    final originalTaskId = engine.generateAssetImages(
      projectId,
      [(assetsId: assetId, refImageBase64: null)],
    );

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-cancel-$assetId')));
    await tester.pump();
    expect(find.text('危险操作确认'), findsOneWidget);

    await engine.cancelJob(originalTaskId);
    final replacementTaskId = engine.generateAssetImages(
      projectId,
      [(assetsId: assetId, refImageBase64: null)],
    );

    await tester.tap(find.text('确定'));
    await tester.pump();

    final jobs = await engine.projectJobs(projectId);
    expect(
      jobs.singleWhere((job) => job.id == originalTaskId).state,
      'failed',
    );
    expect(
      jobs.singleWhere((job) => job.id == replacementTaskId).state,
      'pending',
    );
    expect(find.text('当前没有可取消的生成'), findsOneWidget);
  });

  testWidgets('详情分辨率默认使用当前选中图片的分辨率', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
      prompt: '雪夜',
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'scene',
      base64Image: base64Encode([1, 2, 3]),
    );
    engine.db.execute(
      'UPDATE o_image SET resolution=? WHERE assetsId=?',
      ['2K', assetId],
    );

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final resolution = tester.widget<SegmentedButton<String>>(
      find.descendant(
        of: find.byKey(Key('cornerscape-resolution-$assetId')),
        matching: find.byType(SegmentedButton<String>),
      ),
    );
    expect(resolution.selected, {'2K'});
  });

  testWidgets('切换有分辨率的历史图会更新详情重新生成默认值', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'tool',
      name: '灵剑',
      describe: '',
      prompt: '长剑',
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'tool',
      base64Image: base64Encode([1, 2, 3]),
    );
    engine.saveAssetImage(
      assetsId: assetId,
      projectId: projectId,
      type: 'tool',
      base64Image: base64Encode([4, 5, 6]),
    );
    final images = engine.assetImages(assetId);
    final historyId = images.first.id;
    engine.db.execute(
      'UPDATE o_image SET resolution=? WHERE id=?',
      ['4K', historyId],
    );
    engine.db.execute(
      'UPDATE o_image SET resolution=? WHERE id=?',
      ['1K', images.last.id],
    );

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('cornerscape-history-image-$historyId')));
    await tester.pump();

    final resolution = tester.widget<SegmentedButton<String>>(
      find.descendant(
        of: find.byKey(Key('cornerscape-resolution-$assetId')),
        matching: find.byType(SegmentedButton<String>),
      ),
    );
    expect(resolution.selected, {'4K'});
  });

  testWidgets('失败的当前图片在详情显示失败而不是等待生成', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '失败角色',
      describe: '',
      prompt: '剑客',
    );
    setImageState(assetId, stateFailed);

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final detail = find.byKey(Key('cornerscape-detail-$assetId'));
    expect(
      find.descendant(of: detail, matching: find.text('生成失败')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('等待生成')),
      findsNothing,
    );
  });

  testWidgets('详情提示词失焦持久化且 AI 润色调用单资产接口', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '旧提示词',
    );

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();
    expect(find.text('林朝雪 · 角色'), findsOneWidget);

    final promptField = find.byKey(Key('cornerscape-prompt-$assetId'));
    await tester.enterText(promptField, '失焦后保存的提示词');
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
    expect(
      engine.assetsByIds([assetId]).single.prompt,
      '失焦后保存的提示词',
    );

    final polishButton = find.byKey(Key('cornerscape-polish-$assetId'));
    await tester.ensureVisible(polishButton);
    await tester.pump();
    await tester.tap(polishButton);
    await tester.pumpAndSettle();

    expect(gateway.textCalls, 1);
    expect(engine.assetsByIds([assetId]).single.prompt, '润色后的雪山剑客');
    expect(
      tester.widget<TextField>(promptField).controller!.text,
      '润色后的雪山剑客',
    );
  });

  testWidgets('详情空白提示词不会调用 AI 润色', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '   ',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final polishButton = find.byKey(Key('cornerscape-polish-$assetId'));
    await tester.ensureVisible(polishButton);
    await tester.tap(polishButton);
    await tester.pumpAndSettle();

    expect(find.text('花费确认'), findsNothing);
    expect(gateway.textCalls, 0);
    expect(engine.assetsByIds([assetId]).single.prompt, '   ');
  });

  testWidgets('详情 AI 润色在花费确认取消后不调用也不修改提示词', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '原提示词',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final polishButton = find.byKey(Key('cornerscape-polish-$assetId'));
    await tester.ensureVisible(polishButton);
    await tester.tap(polishButton);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(gateway.textCalls, 0);
    expect(engine.assetsByIds([assetId]).single.prompt, '原提示词');
    expect(
      tester
          .widget<TextField>(find.byKey(Key('cornerscape-prompt-$assetId')))
          .controller!
          .text,
      '原提示词',
    );
  });

  testWidgets('详情 AI 润色在花费确认后调用并更新提示词', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '原提示词',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final polishButton = find.byKey(Key('cornerscape-polish-$assetId'));
    await tester.ensureVisible(polishButton);
    await tester.tap(polishButton);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(gateway.textCalls, 1);
    expect(engine.assetsByIds([assetId]).single.prompt, '润色后的雪山剑客');
  });

  testWidgets('详情 AI 润色确认后锁定提示词直到结果写入', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '原提示词',
    );
    final pending = Completer<TextResult>();
    gateway.pendingText = pending;
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final promptField = find.byKey(Key('cornerscape-prompt-$assetId'));
    final polishButton = find.byKey(Key('cornerscape-polish-$assetId'));
    await tester.ensureVisible(polishButton);
    await tester.tap(polishButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pump();

    expect(gateway.textCalls, 1);
    expect(tester.widget<TextField>(promptField).enabled, isFalse);

    await tester.tap(promptField);
    await tester.enterText(promptField, '不应覆盖原提示词');
    await tester.pump();
    expect(
      tester.widget<TextField>(promptField).controller!.text,
      '原提示词',
    );

    pending.complete(const TextResult('润色后的雪山剑客'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(promptField).enabled, isTrue);
    expect(
      tester.widget<TextField>(promptField).controller!.text,
      '润色后的雪山剑客',
    );
    expect(engine.assetsByIds([assetId]).single.prompt, '润色后的雪山剑客');
  });

  testWidgets('详情 AI 润色关闭重开后保持锁定且旧控制器不会覆盖结果', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
      prompt: '原提示词',
    );
    final pending = Completer<TextResult>();
    gateway.pendingText = pending;
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final promptField = find.byKey(Key('cornerscape-prompt-$assetId'));
    await tester.enterText(promptField, '待润色草稿');
    final polishButton = find.byKey(Key('cornerscape-polish-$assetId'));
    await tester.ensureVisible(polishButton);
    await tester.tap(polishButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pump();

    expect(gateway.textCalls, 1);
    expect(tester.widget<TextField>(promptField).enabled, isFalse);
    expect(tester.widget<OutlinedButton>(polishButton).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(Key('cornerscape-regenerate-$assetId')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('关闭').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final reopenedPrompt = find.byKey(Key('cornerscape-prompt-$assetId'));
    final reopenedPolish = find.byKey(Key('cornerscape-polish-$assetId'));
    final reopenedRegenerate =
        find.byKey(Key('cornerscape-regenerate-$assetId'));
    await tester.ensureVisible(reopenedPolish);
    await tester.pump();

    expect(tester.widget<TextField>(reopenedPrompt).enabled, isFalse);
    expect(tester.widget<OutlinedButton>(reopenedPolish).onPressed, isNull);
    expect(tester.widget<FilledButton>(reopenedRegenerate).onPressed, isNull);

    pending.complete(const TextResult('润色后的雪山剑客'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(reopenedPrompt).enabled, isTrue);
    expect(
      tester.widget<TextField>(reopenedPrompt).controller!.text,
      '润色后的雪山剑客',
    );
    expect(tester.widget<OutlinedButton>(reopenedPolish).onPressed, isNotNull);
    expect(
      tester.widget<FilledButton>(reopenedRegenerate).onPressed,
      isNotNull,
    );
    expect(engine.assetsByIds([assetId]).single.prompt, '润色后的雪山剑客');
  });

  testWidgets('场景和道具详情共用音频选择试听并可解绑', (tester) async {
    final sceneId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '雪山',
      describe: '',
      prompt: '雪夜',
    );
    final toolId = engine.addAsset(
      projectId: projectId,
      type: 'tool',
      name: '长剑',
      describe: '',
      prompt: '寒光',
    );
    final audioId = engine.addAsset(
      projectId: projectId,
      type: 'audio',
      name: '风雪声',
      describe: '',
    );

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$sceneId')));
    await tester.pumpAndSettle();
    expect(find.text('雪山 · 场景'), findsOneWidget);

    final sceneAudio = find.byKey(Key('cornerscape-audio-$sceneId'));
    await tester.ensureVisible(sceneAudio);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: sceneAudio,
        matching: find.byType(DropdownButtonFormField<int?>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('风雪声').last);
    await tester.pump();
    expect(
      engine
          .assetAudioBindings(projectId)
          .singleWhere((binding) => binding.assetId == sceneId)
          .audioAssetId,
      audioId,
    );

    await tester.tap(
      find.byKey(Key('cornerscape-audition-$sceneId')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('音频文件缺失'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: sceneAudio,
        matching: find.byType(DropdownButtonFormField<int?>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('解除绑定').last);
    await tester.pump();
    expect(
      engine
          .assetAudioBindings(projectId)
          .singleWhere((binding) => binding.assetId == sceneId)
          .audioAssetId,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(Key('cornerscape-audition-$sceneId')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('关闭').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('cornerscape-card-$toolId')));
    await tester.pumpAndSettle();
    expect(find.text('长剑 · 道具'), findsOneWidget);

    final toolAudio = find.byKey(Key('cornerscape-audio-$toolId'));
    await tester.ensureVisible(toolAudio);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: toolAudio,
        matching: find.byType(DropdownButtonFormField<int?>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('风雪声').last);
    await tester.pump();
    expect(
      engine
          .assetAudioBindings(projectId)
          .singleWhere((binding) => binding.assetId == toolId)
          .audioAssetId,
      audioId,
    );
  });

  testWidgets('详情重新生成只提交当前资产提示词模型和分辨率', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
      prompt: '旧雪夜',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final modelField = find.byKey(Key('cornerscape-model-$assetId'));
    await tester.ensureVisible(modelField);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: modelField,
        matching: find.byKey(const Key('model-select-field-image')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_imageModelLabel.split(' · ').last).last);
    await tester.pump();

    final resolution = find.byKey(Key('cornerscape-resolution-$assetId'));
    await tester.ensureVisible(resolution);
    await tester.pump();
    await tester.tap(
      find.descendant(of: resolution, matching: find.text('2K')),
    );
    await tester.enterText(
      find.byKey(Key('cornerscape-prompt-$assetId')),
      '当前雪夜提示词',
    );

    final regenerateButton = find.byKey(Key('cornerscape-regenerate-$assetId'));
    await tester.ensureVisible(regenerateButton);
    await tester.pump();
    await tester.tap(regenerateButton);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pump();

    final task = (await engine.projectJobs(projectId)).singleWhere(
      (job) => job.taskClass == 'asset_image_generation',
    );
    expect(task.relatedObjectsJson['ids'], [assetId]);
    expect(task.relatedObjectsJson['model'], _imageModel);
    expect(task.relatedObjectsJson['resolution'], '2K');
    expect(engine.assetsByIds([assetId]).single.prompt, '当前雪夜提示词');
  });

  testWidgets('详情重新生成确认后读取最新提示词而非确认前快照', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山门',
      describe: '',
      prompt: '旧雪夜',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final modelField = find.byKey(Key('cornerscape-model-$assetId'));
    await tester.ensureVisible(modelField);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: modelField,
        matching: find.byKey(const Key('model-select-field-image')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_imageModelLabel.split(' · ').last).last);
    await tester.pump();

    final promptField = find.byKey(Key('cornerscape-prompt-$assetId'));
    await tester.enterText(promptField, '确认前提示词');
    final promptController = tester.widget<TextField>(promptField).controller!;
    final regenerateButton = find.byKey(Key('cornerscape-regenerate-$assetId'));
    await tester.ensureVisible(regenerateButton);
    await tester.pump();
    await tester.tap(regenerateButton);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);

    promptController.text = '确认后的最新提示词';
    await tester.tap(find.text('确定'));
    await tester.pump();

    final task = (await engine.projectJobs(projectId)).singleWhere(
      (job) => job.taskClass == 'asset_image_generation',
    );
    expect(task.relatedObjectsJson['ids'], [assetId]);
    expect(
      engine.assetsByIds([assetId]).single.prompt,
      '确认后的最新提示词',
    );
  });

  testWidgets('详情重新生成确认期间模型失效不会创建任务', (tester) async {
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'tool',
      name: '长剑',
      describe: '',
      prompt: '寒光',
    );
    engine.config.update({'policy.confirmMoney': '1'});

    await pumpDesktop(tester);
    await tester.tap(find.byKey(Key('cornerscape-card-$assetId')));
    await tester.pumpAndSettle();

    final modelField = find.byKey(Key('cornerscape-model-$assetId'));
    await tester.ensureVisible(modelField);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: modelField,
        matching: find.byKey(const Key('model-select-field-image')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_imageModelLabel.split(' · ').last).last);
    await tester.pump();

    final regenerateButton = find.byKey(Key('cornerscape-regenerate-$assetId'));
    await tester.ensureVisible(regenerateButton);
    await tester.pump();
    await tester.tap(regenerateButton);
    await tester.pumpAndSettle();
    expect(find.text('花费确认'), findsOneWidget);

    await engine.saveProviderModels('test-image', []);
    await tester.tap(find.text('确定'));
    await tester.pump();

    expect(
      (await engine.projectJobs(projectId))
          .where((job) => job.taskClass == 'asset_image_generation'),
      isEmpty,
    );
  });

  testWidgets('桌面完成卡显示两行描述和模型分辨率时不溢出且保持等高', (tester) async {
    final completed = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '长描述完成角色',
      describe: '这是用于验证完成卡文本区域的两行描述，在预览保持固定高度时仍需完整占用自己的空间。',
      prompt: '剑客',
    );
    final waiting = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '等高对照场景',
      describe: '对照卡片',
      prompt: '雪夜',
    );
    engine.saveAssetImage(
      assetsId: completed,
      projectId: projectId,
      type: 'role',
      base64Image: base64Encode([4, 5, 6]),
    );
    engine.db.execute(
      'UPDATE o_image SET model=?, resolution=? WHERE assetsId=?',
      ['azt:gpt-image-2', '2K', completed],
    );

    await pumpDesktop(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('这是用于验证完成卡文本区域的两行描述'),
      findsOneWidget,
    );
    final heights = [completed, waiting]
        .map(
          (id) =>
              tester.getSize(find.byKey(Key('cornerscape-card-$id'))).height,
        )
        .toSet();
    expect(heights, hasLength(1));
  });
}
