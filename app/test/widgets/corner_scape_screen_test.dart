import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
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
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _imageModel = 'test-image:corner-image';
const _imageModelLabel = '测试图片 · Corner Image';

void main() {
  late Directory dir;
  late Engine engine;
  late int projectId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-cornerscape-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    engine.config.update({'policy.confirmMoney': '0'});
    engine.installAudioBindPipeline();
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
    projectId = engine.addProject(projectType: 'novel', name: '塑角造景测试');
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
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_imageModelLabel).last);
    await tester.pump();
  }

  Future<void> confirmBatchImageGeneration(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, '开始批量生成'));
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
      findsOneWidget,
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
