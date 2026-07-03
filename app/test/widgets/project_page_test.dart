import 'dart:io';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/screens/project/project_list_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-projpage-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
          path: '/',
          builder: (c, s) => const Scaffold(body: ProjectListScreen())),
      GoRoute(
          path: '/p/:pid/novel', builder: (c, s) => const Text('novel-page')),
    ]);
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    );
  }

  testWidgets('空态：提示与新建按钮', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('暂无项目'), findsOneWidget);
    expect(find.text('新建项目'), findsNWidgets(2)); // 头部+空态
  });

  testWidgets('项目卡片渲染与点击跳转', (tester) async {
    engine.addProject(
        projectType: 'novel', name: '剑出寒山', intro: '少年得剑', artStyle: '国风水墨');
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('剑出寒山'), findsOneWidget);
    expect(find.text('基于小说原文'), findsOneWidget);
    expect(find.text('国风水墨'), findsOneWidget);

    await tester.tap(find.text('剑出寒山'));
    await tester.pumpAndSettle();
    expect(find.text('novel-page'), findsOneWidget);
  });

  testWidgets('新建对话框：名称必填校验', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('项目类型'), findsOneWidget);
    expect(find.text('视觉手册'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBar, '请输入项目名称'), findsOneWidget);
  });

  testWidgets('移动端新建向导：完整项目设置保存到本地库', (tester) async {
    final provider = await engine.createProvider(
      name: 'Demo Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'img-demo',
        'label': '图像模型',
        'kind': 'image',
        'enabled': true,
      },
      {
        'modelId': 'video-demo',
        'label': '视频模型',
        'kind': 'video',
        'enabled': true,
        'capabilities': {
          'modes': ['fast', 'quality'],
        },
      },
    ]);
    engine.saveVisualManual(
      name: '国风视觉',
      data: const {'README': 'ink visual'},
    );
    engine.saveDirectorManual(
      name: '悬疑导演',
      data: const {'README': 'suspense director'},
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('项目类型'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '移动端短剧');
    await tester.enterText(find.byType(TextField).at(1), '玄幻');
    await tester.enterText(find.byType(TextField).at(2), '少年入山修行');
    await _chooseDropdown(tester, '请选择图片模型', 'Demo Provider · 图像模型');
    await _chooseDropdown(tester, '1K', '4K');
    await _chooseDropdown(tester, '请选择视频模型', 'Demo Provider · 视频模型');
    await _chooseDropdown(tester, '请选择模式', 'fast');
    await _chooseDropdown(tester, '16:9', '9:16');

    await tester.scrollUntilVisible(
      find.text('国风视觉'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('国风视觉'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('悬疑导演'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('悬疑导演'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    final project = engine.projects().single;
    expect(project.name, '移动端短剧');
    expect(project.type, '玄幻');
    expect(project.intro, '少年入山修行');
    expect(project.artStyle, '国风视觉');
    expect(project.directorManual, '悬疑导演');
    expect(project.imageModel, 'demo-provider:img-demo');
    expect(project.imageQuality, '4K');
    expect(project.videoModel, 'demo-provider:video-demo');
    expect(project.mode, 'fast');
    expect(project.videoRatio, '9:16');
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
  await tester.tap(field.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}
