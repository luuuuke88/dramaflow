import 'dart:io';
import 'dart:ui';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/art_style.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/novel.dart';
import 'package:dramaflow/src/engine/novel_parse.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
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
      GoRoute(
        path: '/settings',
        builder: (c, s) => const Text('settings-provider-page'),
      ),
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

  Widget appearanceApp() {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
          path: '/',
          builder: (c, s) => const Scaffold(body: ProjectListScreen())),
      GoRoute(
          path: '/p/:pid/novel', builder: (c, s) => const Text('novel-page')),
      GoRoute(
        path: '/settings',
        builder: (c, s) => const Text('settings-provider-page'),
      ),
    ]);
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: Consumer(
        builder: (context, ref, _) {
          final primaryColor = ref.watch(themePrimaryColorProvider);
          final fontSize = ref.watch(themeFontSizeProvider);
          return MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            locale: const Locale('zh'),
            theme: buildTheme(Brightness.light, primaryColor: primaryColor),
            darkTheme: buildTheme(Brightness.dark, primaryColor: primaryColor),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(fontSize / 16),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
            routerConfig: router,
          );
        },
      ),
    );
  }

  Future<
      ({
        String artStyle,
        String directorManual,
        String imageModel,
        String videoModel
      })> seedEditableProjectInputs() async {
    final imageProvider = await engine.createProvider(
      name: 'Edit Image Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(imageProvider.id, const [
      {
        'modelId': 'edit-image',
        'label': '编辑图片模型',
        'kind': 'image',
        'enabled': true,
      },
    ]);
    final videoProvider = await engine.createProvider(
      name: 'Edit Video Provider',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'test-key',
    );
    await engine.saveProviderModels(videoProvider.id, const [
      {
        'modelId': 'edit-video',
        'label': '编辑视频模型',
        'kind': 'video',
        'enabled': true,
        'capabilities': {
          'modes': ['first_frame'],
        },
      },
    ]);
    engine.saveVisualManual(
      name: '编辑视觉',
      pack: 'edit_visual',
      data: const {'README': 'visual'},
    );
    engine.saveDirectorManual(
      name: '编辑导演',
      pack: 'edit_director',
      data: const {'README': 'director'},
    );
    return (
      artStyle: 'edit_visual',
      directorManual: 'edit_director',
      imageModel: '${imageProvider.id}:edit-image',
      videoModel: '${videoProvider.id}:edit-video',
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
    final inputs = await seedEditableProjectInputs();
    engine.addProject(
      projectType: 'novel',
      name: '剑出寒山',
      intro: '少年得剑',
      artStyle: '国风水墨',
      imageModel: inputs.imageModel,
      videoModel: inputs.videoModel,
    );
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

  testWidgets('模型绑定失效的项目进入前提示并打开编辑', (tester) async {
    engine.addProject(
      projectType: 'novel',
      name: '待修复配置',
      imageModel: 'missing-image-provider:image-model',
      videoModel: 'missing-video-provider:video-model',
    );
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('待修复配置'));
    await tester.pumpAndSettle();

    expect(find.text('novel-page'), findsNothing);
    expect(find.text('编辑项目'), findsOneWidget);
    expect(
      find.widgetWithText(
        SnackBar,
        '视频模型或图片模型供应商未启用或无模型供应商，请先配置',
      ),
      findsOneWidget,
    );
  });

  testWidgets('移动端失效模型也不能绕过项目入口保护', (tester) async {
    engine.addProject(
      projectType: 'novel',
      name: '移动端待修复配置',
      imageModel: 'missing-image-provider:image-model',
      videoModel: 'missing-video-provider:video-model',
    );
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('移动端待修复配置'));
    await tester.pumpAndSettle();

    expect(find.text('novel-page'), findsNothing);
    expect(find.text('编辑项目'), findsOneWidget);
  });

  testWidgets('桌面项目卡片：hover 后可编辑和删除', (tester) async {
    final inputs = await seedEditableProjectInputs();
    final projectId = engine.addProject(
      projectType: 'novel',
      name: '桌面项目',
      intro: '旧简介',
      type: '玄幻',
      artStyle: inputs.artStyle,
      directorManual: inputs.directorManual,
      videoRatio: '16:9',
      imageModel: inputs.imageModel,
      videoModel: inputs.videoModel,
      imageQuality: '1K',
      mode: 'first_frame',
    );
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('桌面项目')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('编辑'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '桌面项目改名');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final edited = await engine.getProject(projectId);
    expect(edited.name, '桌面项目改名');

    await mouse.moveTo(tester.getCenter(find.text('桌面项目改名')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(engine.projects(), isEmpty);
    expect(find.text('暂无项目'), findsOneWidget);
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

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-intake-validation-error')),
        findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const Key('project-intake-validation-error')))
          .data,
      '请输入项目名称',
    );
  });

  testWidgets('新建对话框：名称后按原版顺序拦住缺少题材', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '待校验项目');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-intake-validation-error')),
        findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const Key('project-intake-validation-error')))
          .data,
      '请输入小说类型',
    );
    expect(engine.projects(), isEmpty);
    expect(find.text('项目类型'), findsOneWidget, reason: '校验失败必须留在项目向导，而不是静默关闭');
  });

  testWidgets('项目对话框的手册画廊可打开视觉手册编辑器', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '新建视觉手册'));
    await tester.pumpAndSettle();

    expect(find.text('新建视觉手册'), findsNWidgets(2), reason: '画廊按钮与全屏/对话框标题各显示一次');
    expect(find.text('视觉手册封面'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget,
        reason: '画廊入口必须打开同一套可保存的手册编辑器');
  });

  testWidgets('移动端项目对话框可编辑并删除已有视觉手册', (tester) async {
    engine.saveVisualManual(
      name: '待维护视觉手册',
      pack: 'maintenance_visual',
      data: {for (final key in visualManualKeys) key: '$key 内容'},
    );
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('待维护视觉手册'),
      260,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑视觉手册'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '待维护视觉手册',
      reason: '画廊编辑必须把已有手册传给同一编辑器，而非打开空白新建表单',
    );

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除视觉手册'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(engine.visualManuals(), isEmpty);
    expect(find.text('待维护视觉手册'), findsNothing);
  });

  testWidgets('390dp 最大外观设置下可打开新建项目且主色生效', (tester) async {
    await engine.setThemePrimaryColor('#2BA471');
    await engine.setThemeFontSize(22);
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appearanceApp());
    await tester.pumpAndSettle();

    final projectContext = tester.element(find.byType(ProjectListScreen));
    expect(
        Theme.of(projectContext).colorScheme.primary, const Color(0xFF2BA471));
    expect(MediaQuery.textScalerOf(projectContext).scale(16), 22);
    expect(
      FilledButtonTheme.of(projectContext)
          .style!
          .backgroundColor!
          .resolve(const {}),
      const Color(0xFF2BA471),
    );

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('项目类型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端新建向导：完整项目设置保存到本地库', (tester) async {
    final previousHitTestWarningPolicy =
        WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal =
        previousHitTestWarningPolicy);

    final imageProvider = await engine.createProvider(
      name: 'Demo Image Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(imageProvider.id, [
      {
        'modelId': 'img-demo',
        'label': '图像模型',
        'kind': 'image',
        'enabled': true,
      },
    ]);
    final videoProvider = await engine.createProvider(
      name: 'Demo Video Provider',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'test-key',
    );
    await engine.saveProviderModels(videoProvider.id, [
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
      pack: 'ink_pack',
      data: const {'README': 'ink visual'},
    );
    engine.saveDirectorManual(
      name: '悬疑导演',
      pack: 'fast_cut',
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
    await _chooseDropdown(tester, '请选择图片模型', 'Demo Image Provider · 图像模型');
    await _chooseDropdown(tester, '1K', '4K');
    await _chooseDropdown(tester, '请选择视频模型', 'Demo Video Provider · 视频模型');
    await _chooseDropdown(tester, '请选择模式', 'fast');
    await _chooseDropdown(tester, '16:9', '9:16');

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-intake-validation-error')),
        findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const Key('project-intake-validation-error')))
          .data,
      '请选择项目视觉手册',
    );
    expect(engine.projects(), isEmpty);

    await tester.scrollUntilVisible(
      find.text('国风视觉'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(_manualCard('国风视觉'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-intake-validation-error')),
        findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const Key('project-intake-validation-error')))
          .data,
      '请选择项目导演手册',
    );
    expect(engine.projects(), isEmpty);
    await tester.scrollUntilVisible(
      find.text('悬疑导演'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(_manualCard('悬疑导演'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    final project = engine.projects().single;
    expect(project.name, '移动端短剧');
    expect(project.type, '玄幻');
    expect(project.intro, '少年入山修行');
    expect(project.artStyle, 'ink_pack');
    expect(project.directorManual, 'fast_cut');
    expect(project.imageModel, 'demo-image-provider:img-demo');
    expect(project.imageQuality, '4K');
    expect(project.videoModel, 'demo-video-provider:video-demo');
    expect(project.mode, 'fast');
    expect(project.videoRatio, '9:16');
  });

  testWidgets('移动端无可用模型时可从项目向导直达供应商设置', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-select-configure-image')));
    await tester.pumpAndSettle();

    expect(find.text('settings-provider-page'), findsOneWidget);
    expect(find.text('项目类型'), findsNothing);
  });

  testWidgets('桌面端无可用模型时也可从项目向导直达供应商设置', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-select-configure-video')));
    await tester.pumpAndSettle();

    expect(find.text('settings-provider-page'), findsOneWidget);
    expect(find.text('项目类型'), findsNothing);
  });

  testWidgets('移动端新建向导不再暴露重复画风库入口', (tester) async {
    engine.saveVisualManual(
      name: '国风赛璐璐',
      pack: 'anime_ink',
      data: const {'README': 'anime ink style'},
    );
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目').first);
    await tester.pumpAndSettle();
    expect(find.text('管理画风库'), findsNothing);
    expect(find.text('国风赛璐璐'), findsOneWidget);
    expect(engine.artStyles(), isEmpty);
  });

  testWidgets('移动端项目卡片：无需 hover 也能编辑和删除', (tester) async {
    final inputs = await seedEditableProjectInputs();
    final projectId = engine.addProject(
      projectType: 'novel',
      name: '移动端项目',
      intro: '旧简介',
      type: '玄幻',
      artStyle: inputs.artStyle,
      directorManual: inputs.directorManual,
      videoRatio: '16:9',
      imageModel: inputs.imageModel,
      videoModel: inputs.videoModel,
      imageQuality: '1K',
      mode: 'first_frame',
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byTooltip('编辑'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '移动端项目改名');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final edited = await engine.getProject(projectId);
    expect(edited.name, '移动端项目改名');
    expect(find.text('移动端项目改名'), findsOneWidget);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(engine.projects(), isEmpty);
    expect(find.text('暂无项目'), findsOneWidget);
  });

  testWidgets('移动壳平板宽度下项目卡片仍显示编辑和删除', (tester) async {
    engine.addProject(
      projectType: 'novel',
      name: '平板项目',
      intro: '平板触控操作',
      artStyle: '国风水墨',
    );
    tester.view.physicalSize = const Size(800, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byTooltip('编辑'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
  });

  testWidgets('项目卡片展示本地统计数量', (tester) async {
    final projectId = engine.addProject(
      projectType: 'novel',
      name: '统计项目',
      intro: '带数据',
      artStyle: '赛博',
    );
    engine.addNovels(projectId, [
      const ChapterItem(
        index: 1,
        reel: '正文卷',
        chapter: '第一章',
        chapterData: '入山',
      ),
      const ChapterItem(
        index: 2,
        reel: '正文卷',
        chapter: '第二章',
        chapterData: '试炼',
      ),
    ]);
    final scriptId =
        engine.addScript(projectId: projectId, name: '第1集', content: '剧本');
    final roleId = engine.addAsset(
      projectId: projectId,
      name: '李禾',
      type: 'role',
      describe: '少年',
      prompt: '少年',
    );
    engine.addAsset(
      projectId: projectId,
      name: '山门',
      type: 'scene',
      describe: '山门',
      prompt: '石阶',
    );
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      videoDesc: '少年走向山门',
      prompt: '山门远景',
      duration: '3',
      assetIds: [roleId],
    );

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('章节 2'), findsOneWidget);
    expect(find.text('剧本 1'), findsOneWidget);
    expect(find.text('素材 2'), findsOneWidget);
    expect(find.text('分镜 1'), findsOneWidget);
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

Finder _manualCard(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byType(GestureDetector),
    );
