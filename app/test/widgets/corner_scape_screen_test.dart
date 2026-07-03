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
    engine.installAudioBindPipeline();
    projectId = engine.addProject(projectType: 'novel', name: '配音测试');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: CornerScapeScreen(projectId: projectId)),
      ),
    );
  }

  testWidgets('无角色资产时显示空态', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('暂无角色资产，请先在「资产中心」创建角色'), findsOneWidget);
  });

  testWidgets('有角色时渲染列表+未绑定提示；无音频池时显示警示', (tester) async {
    engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('林朝雪'), findsOneWidget);
    expect(find.text('暂无音频素材，请先在「资产中心」上传音频'), findsWidgets);
  });

  testWidgets('手动绑定音频下拉可选并调用引擎', (tester) async {
    engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('低音男声').last);
    await tester.pumpAndSettle();

    expect(engine.roleAudioBindings(projectId).single.audioName, '低音男声');
  });

  testWidgets('勾选角色后点击 AI 自动匹配触发批量任务', (tester) async {
    engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('AI 自动匹配'));
    await tester.pump();

    final tasks = await engine.projectJobs(projectId);
    expect(tasks.any((t) => t.taskClass == 'audio_bind'), isTrue);
  });

  testWidgets('状态筛选「未绑定」只展示未绑定角色', (tester) async {
    final bound = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'role', name: '沈砚之', describe: 'x');
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: 'x');
    engine.bindRoleAudio(bound, audio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 初始「全部」两角色都在。
    expect(find.text('林朝雪'), findsOneWidget);
    expect(find.text('沈砚之'), findsOneWidget);

    // 切到「未绑定」：只剩未绑定的沈砚之。
    await tester.tap(find.text('未绑定'));
    await tester.pumpAndSettle();
    expect(find.text('林朝雪'), findsNothing);
    expect(find.text('沈砚之'), findsOneWidget);

    // 切到「已绑定」：只剩已绑定的林朝雪。
    await tester.tap(find.text('已绑定'));
    await tester.pumpAndSettle();
    expect(find.text('林朝雪'), findsOneWidget);
    expect(find.text('沈砚之'), findsNothing);
  });

  testWidgets('搜索按角色名称过滤列表', (tester) async {
    engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'role', name: '沈砚之', describe: 'x');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '林');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('林朝雪'), findsOneWidget);
    expect(find.text('沈砚之'), findsNothing);
  });

  testWidgets('全选未绑定把可见未绑定角色加入 AI 匹配选择', (tester) async {
    final bound = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'role', name: '沈砚之', describe: 'x');
    engine.addAsset(
        projectId: projectId, type: 'role', name: '苏晚', describe: 'x');
    final audio = engine.addAsset(
        projectId: projectId, type: 'audio', name: '低音男声', describe: 'x');
    engine.bindRoleAudio(bound, audio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 三角色一绑定两未绑定：点「全选未绑定」应选中 2 个。
    await tester.tap(find.text('全选未绑定'));
    await tester.pumpAndSettle();

    // AI 自动匹配按钮标签带上选择计数 (2)。
    expect(find.textContaining('(2)'), findsOneWidget);

    // 触发批量匹配，任务的 roleIds 恰为两个未绑定角色。
    await tester.tap(find.textContaining('AI 自动匹配'));
    await tester.pump();

    final tasks = await engine.projectJobs(projectId);
    final task = tasks.firstWhere((t) => t.taskClass == 'audio_bind');
    final roleIds = (task.relatedObjectsJson['roleIds'] as List)
        .map((e) => (e as num).toInt())
        .toSet();
    expect(roleIds, hasLength(2));
    expect(roleIds.contains(bound), isFalse);
  });
}
