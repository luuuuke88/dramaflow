import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db_admin.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/screens/settings_screen.dart';
import 'package:dramaflow/src/state/canvas_wheel_mode.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CandidatesGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<String>> listRemoteModelIds(String providerId) async =>
      ['deepseek-v4-flash', 'deepseek-v4-pro', 'brand-new-model'];
}

class _RecordingHttpGateway extends HttpProviderGateway {
  final calls = <String>[];

  _RecordingHttpGateway(super.db, super.config, super.media);

  @override
  Future<int> testTextModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    calls.add('text:${model.modelId}');
    return 11;
  }

  @override
  Future<int> testImageModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    calls.add('image:${model.modelId}');
    return 22;
  }

  @override
  Future<int> testVideoModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    calls.add('video:${model.modelId}');
    return 33;
  }
}

class _FailingFileSelector extends FileSelectorPlatform {
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    throw StateError('save panel unavailable');
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    throw StateError('open panel unavailable');
  }
}

void main() {
  late Directory dir;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-settingsui-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
    );
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: Consumer(
          builder: (context, ref, _) {
            return MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [
                Locale('zh'),
                Locale('en'),
                Locale('ja')
              ],
              locale: ref.watch(localeProvider) ?? const Locale('zh'),
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: ref.watch(themeModeProvider),
              home: const SettingsScreen(),
            );
          },
        ),
      );

  testWidgets('移动端设置页：外观语言、供应商与提示词入口可用', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(engine.config.str('themeMode'), 'dark');

    await _selectSection(tester, '供应商');
    await tester.tap(find.text('添加供应商').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-custom')), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preset-card-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Local Gateway');
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://127.0.0.1:8787/v1',
    );
    await tester.enterText(find.byType(TextField).at(2), 'local');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final provider = (await engine.listProviders()).single;
    expect(provider.name, 'Local Gateway');
    expect(provider.baseUrl, 'http://127.0.0.1:8787/v1');

    await _selectSection(tester, '提示词');
    await tester.tap(find.text('事件提取'));
    await tester.pumpAndSettle();
    expect(find.text('编辑提示词 · 事件提取'), findsOneWidget);
    expect(find.text('提示词内容'), findsOneWidget);
    Navigator.of(tester.element(find.text('编辑提示词 · 事件提取'))).pop();
    await tester.pumpAndSettle();

    await _selectSection(tester, '外观');
    await tester.ensureVisible(find.text('日本語'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(engine.config.str('app.locale'), 'ja');
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('移动端外观：主题色和字号持久化，非法 HEX 不改变当前设置', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-theme-color-E34D59')));
    await tester.pumpAndSettle();
    expect(engine.config.themePrimaryColor, '#E34D59');

    await tester.enterText(
      find.byKey(const Key('settings-theme-color-custom')),
      '#2BA471',
    );
    await tester.tap(find.byKey(const Key('settings-theme-color-apply')));
    await tester.pumpAndSettle();
    expect(engine.config.themePrimaryColor, '#2BA471');

    await tester.tap(find.byKey(const Key('settings-theme-font-22')));
    await tester.pumpAndSettle();
    expect(engine.config.themeFontSize, 22);

    await tester.enterText(
      find.byKey(const Key('settings-theme-color-custom')),
      '#FFF',
    );
    await tester.tap(find.byKey(const Key('settings-theme-color-apply')));
    await tester.pumpAndSettle();
    expect(engine.config.themePrimaryColor, '#2BA471');
    expect(find.text('请输入 #RRGGBB 格式的颜色'), findsOneWidget);
  });

  testWidgets('移动端自定义供应商表单默认遮蔽 API Key', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.text('添加供应商').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-custom')), 300);
    await tester.tap(find.byKey(const Key('preset-card-custom')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
      isTrue,
    );
  });

  testWidgets('Anthropic 供应商在列表和编辑页都显示原生协议', (tester) async {
    await engine.createProvider(
      name: 'Claude Primary',
      protocol: 'anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      apiKey: 'sk-ant-test',
    );
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    expect(find.text('Anthropic 原生'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑').first);
    await tester.pumpAndSettle();
    expect(find.text('Anthropic 原生'), findsWidgets);
  });

  testWidgets('桌面端提示词库：新建、绑定、编辑和解绑模型模板', (tester) async {
    final provider = await engine.createProvider(
      name: 'Volcengine',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'doubao-seedance-2-0-mini-260615',
        'label': 'Seedance Mini',
        'kind': 'video',
        'enabled': true,
      },
    ]);

    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '提示词');
    expect(find.text('Volcengine'), findsOneWidget);
    final targetKey = ValueKey(
      'model-prompt-target-${provider.id}:doubao-seedance-2-0-mini-260615',
    );
    await tester.scrollUntilVisible(find.byKey(targetKey), 320);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(targetKey));
    await tester.pumpAndSettle();
    expect(find.text('模型提示词模板'), findsOneWidget);

    await tester.tap(find.byKey(const Key('model-prompt-template-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-prompt-template-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('model-prompt-template-name')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('model-prompt-template-name')),
      'Seedance 多参',
    );
    await tester.enterText(
      find.byKey(const Key('model-prompt-template-content')),
      '初版模板正文',
    );
    await tester.tap(find.byKey(const Key('model-prompt-template-save')));
    await tester.pumpAndSettle();

    final templatePath = 'video/Seedance 多参.md';
    await tester.tap(
      find.byKey(ValueKey('model-prompt-bind-$templatePath')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('model-prompt-unbind-$templatePath')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey('model-prompt-edit-$templatePath')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('model-prompt-template-content')),
      '更新后的模板正文',
    );
    await tester.tap(find.byKey(const Key('model-prompt-template-save')));
    await tester.pumpAndSettle();
    expect(
      (await engine.listModelPromptTemplates(kind: 'video')).single.prompt,
      '更新后的模板正文',
    );

    await tester.tap(
      find.byKey(ValueKey('model-prompt-delete-$templatePath')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('删除“Seedance 多参”后，将解绑 1 个模型。此操作不可撤销。'),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('model-prompt-unbind-$templatePath')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('model-prompt-bind-$templatePath')),
        findsOneWidget);
  });

  testWidgets('移动端提示词库：可选择既有模板并编辑且无溢出', (tester) async {
    final provider = await engine.createProvider(
      name: 'Volcengine',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'seedance-mobile',
        'label': 'Seedance Mobile',
        'kind': 'video',
        'enabled': true,
      },
    ]);
    final template = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '移动端已有模板',
      prompt: '旧正文',
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '提示词');
    await tester.drag(
      find.byKey(const Key('settings-section-scroll')),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    final target = find
        .byKey(ValueKey('model-prompt-target-${provider.id}:seedance-mobile'))
        .hitTestable();
    expect(target, findsOneWidget);
    await tester.tap(
      target,
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(ValueKey('model-prompt-bind-${template.path}')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('model-prompt-unbind-${template.path}')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(ValueKey('model-prompt-edit-${template.path}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('model-prompt-template-content')),
      '移动端新正文',
    );
    await tester.tap(find.byKey(const Key('model-prompt-template-save')));
    await tester.pumpAndSettle();
    expect(
      (await engine.listModelPromptTemplates(kind: 'video')).single.prompt,
      '移动端新正文',
    );
  });

  testWidgets('移动端设置页：模型管理、模型绑定与数据库信息可用', (tester) async {
    final provider = await engine.createProvider(
      name: 'Local Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();
    expect(find.text('模型管理 · Local Gateway'), findsOneWidget);

    await tester.tap(find.byKey(const Key('model-editor-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'local-text');
    await tester.enterText(find.byType(TextField).at(1), '本地文本模型');
    await tester.tap(find.byKey(const Key('model-editor-save')));
    await tester.pumpAndSettle();

    final models = await engine.listProviderModels(provider.id);
    expect(models.single.modelId, 'local-text');
    expect(models.single.kind, 'text');

    await _selectSection(tester, '模型绑定');
    expect(find.text('Agent 视觉理解'), findsNothing);
    await _chooseFirstDropdown(tester, 'Local Gateway · 本地文本模型');
    expect(
      (await engine.getBindings())['script_gen'],
      '${provider.id}:local-text',
    );

    await _selectSection(tester, '存储与引擎');
    await tester.tap(find.text('数据库信息'));
    await tester.pumpAndSettle();
    expect(find.text('数据库信息'), findsWidgets);
    expect(find.text('o_project'), findsOneWidget);
  });

  testWidgets('移动端设置页显示导演规划和分镜表阶段', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '模型绑定');
    expect(find.text('director_plan'), findsOneWidget);
    expect(find.text('storyboard_table'), findsOneWidget);

    await _selectSection(tester, '提示词');
    expect(find.text('director_plan'), findsOneWidget);
    expect(find.text('storyboard_table'), findsOneWidget);
  });

  testWidgets('移动端设置页：视频模型能力可编辑并保留未知能力键', (tester) async {
    final provider = await engine.createProvider(
      name: 'Volcengine',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'seedance-custom',
        'label': 'Seedance Custom',
        'kind': 'video',
        'enabled': true,
        'capabilities': {
          'providerSpecific': {'region': 'cn-north-1'},
          'video': {
            'providerSpecific': {'nativeAudioCodec': 'aac'},
            'modes': ['first_frame'],
            'references': {'image': 1, 'video': 0, 'audio': 0},
            'durations': [4],
            'resolutions': ['720p'],
            'ratios': ['16:9'],
            'audio': 'none',
            'promptTemplates': {
              'first_frame': 'video/legacy-first-frame.md',
            },
          },
        },
      },
    ]);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();

    final capabilityEditor =
        find.byKey(const ValueKey('video-capability-seedance-custom'));
    expect(capabilityEditor, findsOneWidget);
    await tester.ensureVisible(capabilityEditor);
    await tester.tap(capabilityEditor);
    await tester.pumpAndSettle();

    expect(find.text('视频能力'), findsOneWidget);
    expect(find.text('first_frame'), findsOneWidget);
    expect(find.text('multi_reference'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(
        'video-capability-mode-multi_reference-seedance-custom')));
    await tester.enterText(
      find.byKey(
          const ValueKey('video-capability-reference-image-seedance-custom')),
      ' 3 ',
    );
    await tester.enterText(
      find.byKey(
          const ValueKey('video-capability-reference-video-seedance-custom')),
      ' 2 ',
    );
    await tester.enterText(
      find.byKey(
          const ValueKey('video-capability-reference-audio-seedance-custom')),
      ' 1 ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('video-capability-durations-seedance-custom')),
      '4, 6, 4',
    );
    await tester.enterText(
      find.byKey(
          const ValueKey('video-capability-resolutions-seedance-custom')),
      '720p, 480p, 720p',
    );
    await tester.enterText(
      find.byKey(const ValueKey('video-capability-ratios-seedance-custom')),
      '16:9, 9:16, 16:9',
    );
    await tester.tap(
      find.byKey(
        const ValueKey('video-capability-audio-seedance-custom'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('可选音频').last);
    await tester.enterText(
      find.byKey(const ValueKey(
          'video-capability-template-multi_reference-seedance-custom')),
      ' video/seedance2-multi.md ',
    );

    await tester.tap(find.byKey(const Key('model-editor-save')));
    await tester.pumpAndSettle();

    final model = (await engine.listProviderModels(provider.id)).single;
    expect(model.capabilities['providerSpecific'], {'region': 'cn-north-1'});
    expect(model.capabilities['video'], {
      'providerSpecific': {'nativeAudioCodec': 'aac'},
      'modes': ['first_frame', 'multi_reference'],
      'references': {'image': 3, 'video': 2, 'audio': 1},
      'durations': [4, 6],
      'resolutions': ['720p', '480p'],
      'ratios': ['16:9', '9:16'],
      'audio': 'optional',
      'promptTemplates': {
        'first_frame': 'video/legacy-first-frame.md',
        'multi_reference': 'video/seedance2-multi.md',
      },
    });
  });

  testWidgets('移动端设置页：拒绝不完整或非法的视频能力配置', (tester) async {
    final provider = await engine.createProvider(
      name: 'Volcengine',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'seedance-validated',
        'label': 'Seedance Validated',
        'kind': 'video',
        'enabled': true,
        'capabilities': {
          'video': {
            'modes': ['first_frame'],
            'references': {'image': 1, 'video': 0, 'audio': 0},
            'durations': [4],
            'resolutions': ['720p'],
            'ratios': ['16:9'],
            'audio': 'none',
            'promptTemplates': {},
          },
        },
      },
    ]);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('video-capability-seedance-validated')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('video-capability-mode-first_frame-seedance-validated'),
    ));
    await tester.tap(find.byKey(const Key('model-editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('视频模型至少需要一种生成模式'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('video-capability-mode-first_frame-seedance-validated'),
    ));
    await tester.enterText(
      find.byKey(
        const ValueKey('video-capability-reference-image-seedance-validated'),
      ),
      '-1',
    );
    await tester.tap(find.byKey(const Key('model-editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('视频参考数量不能为负数'), findsOneWidget);
  });

  testWidgets('移动端设置页：编辑供应商配置并刷新卡片', (tester) async {
    await engine.createProvider(
      name: 'Old Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'old-key',
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('编辑').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑供应商'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'AZT Gateway');
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://127.0.0.1:8787/v1',
    );
    await tester.enterText(find.byType(TextField).at(2), 'local');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final provider = (await engine.listProviders()).single;
    expect(provider.name, 'AZT Gateway');
    expect(provider.baseUrl, 'http://127.0.0.1:8787/v1');
    expect(provider.hasCredential, isTrue);
    expect(find.text('AZT Gateway'), findsOneWidget);
    expect(find.text('Old Gateway'), findsNothing);
  });

  testWidgets('移动端设置页编辑 ima2 时打开双端点专属表单', (tester) async {
    await engine.createProviderFromPreset(presetId: 'ima2', apiKey: 'dummy');

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('编辑').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preset-input-chatBaseUrl')), findsOneWidget);
    expect(find.byKey(const Key('preset-input-imageBaseUrl')), findsOneWidget);
    expect(find.byKey(const Key('preset-form-baseurl')), findsNothing);
  });

  testWidgets('移动端设置页：付费连通测试先确认，视频保持人工验收', (tester) async {
    engine.dispose();
    final db = openEngineDb(':memory:');
    final media = MediaStore(p.join(dir.path, 'media'));
    final config = EngineConfig(db, isMobile: true);
    final gateway = _RecordingHttpGateway(db, config, media);
    engine = Engine(
      db: db,
      media: media,
      gateway: gateway,
      config: config,
    );
    final imageProvider = await engine.createProvider(
      name: 'A Image Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(imageProvider.id, const [
      {
        'modelId': 'local-text',
        'label': '本地文本',
        'kind': 'text',
        'enabled': true,
      },
      {
        'modelId': 'local-image',
        'label': '本地图像',
        'kind': 'image',
        'enabled': true,
      },
    ]);
    final videoProvider = await engine.createProvider(
      name: 'B Volcengine',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'sk-test',
    );
    await engine.saveProviderModels(videoProvider.id, const [
      {
        'modelId': 'local-video',
        'label': '本地视频',
        'kind': 'video',
        'enabled': true,
      },
    ]);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    final imageCard = find.byKey(const ValueKey('a-image-gateway:0'));
    await tester.ensureVisible(imageCard);
    await tester.tap(find.descendant(
      of: imageCard,
      matching: find.byTooltip('测试连通'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('测试连通 · A Image Gateway'), findsOneWidget);

    await _chooseFirstDropdown(tester, '图片 · 本地图像');
    await tester.tap(find.text('测试').last);
    await tester.pumpAndSettle();

    expect(gateway.calls, isEmpty);
    expect(find.byKey(const Key('provider-test-paid-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('provider-test-paid-confirm')));
    await tester.pumpAndSettle();

    final videoCard = find.byKey(const ValueKey('b-volcengine:0'));
    await tester.ensureVisible(videoCard);
    await tester.tap(find.descendant(
      of: videoCard,
      matching: find.byTooltip('测试连通'),
    ));
    await tester.pumpAndSettle();

    expect(gateway.calls, ['image:local-image']);
  });

  testWidgets('移动端设置页：清空数据确认只清内容保留配置', (tester) async {
    await engine.createProvider(
      name: 'Keep Provider',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    engine.addProject(projectType: 'novel', name: '待清理项目');

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(engine.projects(), isNotEmpty);

    await _selectSection(tester, '存储与引擎');
    await tester.tap(find.text('清空数据'));
    await tester.pumpAndSettle();
    expect(find.text('清空所有数据'), findsOneWidget);

    await tester.tap(find.text('清空数据').last);
    await tester.pumpAndSettle();

    expect(engine.projects(), isEmpty);
    expect((await engine.listProviders()).single.name, 'Keep Provider');
  });

  testWidgets('移动端设置页：配置导入导出面板错误可见', (tester) async {
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _FailingFileSelector();
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '存储与引擎');
    await tester.tap(find.text('导出配置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法打开保存面板'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入配置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法打开文件'), findsOneWidget);
  });

  testWidgets('移动端设置页：打开数据目录失败时显示错误', (tester) async {
    debugOpenDataFolderOverride = (path) async {
      expect(path, engine.dataDirPath());
      throw StateError('folder opener unavailable');
    };
    addTearDown(() => debugOpenDataFolderOverride = null);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '存储与引擎');
    await tester.tap(find.text('打开数据目录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('无法打开数据目录'), findsOneWidget);
    expect(find.textContaining('folder opener unavailable'), findsOneWidget);
  });

  testWidgets('移动端设置页：关于区展示应用与内嵌引擎信息', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '关于');

    expect(find.text('关于 DramaFlow'), findsOneWidget);
    expect(find.text('应用名称'), findsOneWidget);
    expect(find.text('DramaFlow'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('引擎版本'), findsOneWidget);
    expect(find.text(Engine.version), findsOneWidget);
    expect(
      find.text('DramaFlow 是本机运行的 AI 短剧创作工作台，数据与媒体全部保存在本机。'),
      findsOneWidget,
    );
  });

  testWidgets('移动端设置页：花钱/破坏确认开关可读写配置', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '其他设置');

    expect(engine.config.str('policy.confirmMoney'), '1');
    expect(engine.config.str('policy.confirmDestructive'), '1');

    await tester.drag(
      find.byKey(const Key('settings-section-scroll')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('花钱操作需确认'));
    await tester.pumpAndSettle();
    expect(engine.config.str('policy.confirmMoney'), '0');

    await tester.tap(find.text('破坏性操作需确认（含 auto 模式）'));
    await tester.pumpAndSettle();
    expect(engine.config.str('policy.confirmDestructive'), '0');

    await tester.tap(find.text('花钱操作需确认'));
    await tester.pumpAndSettle();
    expect(engine.config.str('policy.confirmMoney'), '1');
  });

  testWidgets('其他设置：画布滚轮模式仅本次会话生效', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectSection(tester, '其他设置');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    final beforeConfig = jsonEncode(engine.config.getAll());
    expect(container.read(canvasWheelModeProvider), CanvasWheelMode.zoom);
    expect(find.byKey(const Key('settings-canvas-wheel-zoom')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-canvas-wheel-scroll')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('settings-section-scroll')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-canvas-wheel-scroll')));
    await tester.pump();

    expect(container.read(canvasWheelModeProvider), CanvasWheelMode.scroll);
    expect(jsonEncode(engine.config.getAll()), beforeConfig);
  });

  testWidgets('390dp 其他设置：画布滚轮模式两个选项均可操作', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectSection(tester, '其他设置');

    final zoom = find.byKey(const Key('settings-canvas-wheel-zoom'));
    final scroll = find.byKey(const Key('settings-canvas-wheel-scroll'));
    expect(zoom, findsOneWidget);
    expect(scroll, findsOneWidget);
    const viewport = Rect.fromLTWH(0, 0, 390, 760);
    expect(tester.getRect(zoom).overlaps(viewport), isTrue);
    expect(tester.getRect(scroll).overlaps(viewport), isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await tester.tap(scroll);
    await tester.pump();
    expect(container.read(canvasWheelModeProvider), CanvasWheelMode.scroll);

    await tester.tap(zoom);
    await tester.pump();
    expect(container.read(canvasWheelModeProvider), CanvasWheelMode.zoom);
  });

  testWidgets('390dp 其他设置保存请求超时与画布拖动性能开关', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectSection(tester, '其他设置');

    final timeout = find.byKey(const Key('settings-request-timeout'));
    final interactionSwitch =
        find.byKey(const Key('settings-canvas-interaction-switch'));
    expect(timeout, findsOneWidget);
    expect(interactionSwitch, findsOneWidget);
    const viewport = Rect.fromLTWH(0, 0, 390, 760);
    expect(tester.getRect(timeout).overlaps(viewport), isTrue);
    expect(tester.getRect(interactionSwitch).overlaps(viewport), isTrue);

    await tester.enterText(timeout, '42');
    await tester.tap(interactionSwitch);
    final save = find.byIcon(Icons.save_outlined);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(engine.config.requestTimeout, const Duration(seconds: 42));
    expect(engine.config.str('production.interacting'), '0');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectSection(tester, '其他设置');

    final reloadedTimeout = tester
        .widget<TextField>(find.byKey(const Key('settings-request-timeout')));
    expect(reloadedTimeout.controller!.text, '42');
    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('settings-canvas-interaction-switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('其他设置拒绝小于十秒的请求超时', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _selectSection(tester, '其他设置');

    await tester.enterText(
        find.byKey(const Key('settings-request-timeout')), '9');
    final save = find.byIcon(Icons.save_outlined);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(engine.config.requestTimeout, const Duration(seconds: 600));
    expect(find.textContaining('至少为 10 秒'), findsOneWidget);
  });

  testWidgets('模型管理：从 API 拉取候选，未分类必须定 kind 才能加入，且默认禁用', (tester) async {
    // 换成能应答 /models 的 fake gateway（沿用本文件 setUp 的 db/media 构造方式）
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _CandidatesGateway(),
      config: EngineConfig(db, isMobile: true),
    );
    // deepseek 预设当前模型清单为 deepseek-v4-flash / deepseek-v4-pro
    // （deepseek-chat 已随预设目录更新下线，2026-07-19 复核见 provider_presets.dart）。
    await engine.createProviderFromPreset(
        presetId: 'deepseek',
        apiKey: 'k',
        selectedModelIds: ['deepseek-v4-flash']);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('model-editor-fetch-models')));
    await tester.pumpAndSettle();

    // deepseek-v4-flash 已在清单 → 候选剩 deepseek-v4-pro（目录已知，应自动
    // 归类）与 brand-new-model（目录未收录，未分类）。
    expect(
        find.byKey(const Key('candidate-row-brand-new-model')), findsOneWidget);
    expect(
        find.byKey(const Key('candidate-row-deepseek-v4-pro')), findsOneWidget);
    expect(
        find.byKey(const Key('candidate-row-deepseek-v4-flash')), findsNothing);
    expect(find.text('未分类'), findsOneWidget); // 仅 brand-new-model 未分类

    // Task 1 目录已知模型（deepseek-v4-pro）：kind 应自动预填为 text，
    // 不是留空（spec §5 第 5 条），且勾选它无需手动选类型即可通过校验。
    final preFilledKind = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('candidate-kind-deepseek-v4-pro')));
    expect(preFilledKind.value, 'text', reason: 'Task 1 目录已知模型应自动填充 kind，而非留空');
    await tester.tap(find.byKey(const Key('candidate-check-deepseek-v4-pro')));
    await tester.pump();

    // 不定 kind 勾选加入 → 行内报错，不关弹层
    await tester.tap(find.byKey(const Key('candidate-check-brand-new-model')));
    await tester.pump();
    await tester.tap(find.text('加入清单'));
    await tester.pump();
    expect(find.text('请先为勾选的模型选择类型'), findsOneWidget);

    // 定 kind = 图片 → 加入成功
    await tester.tap(find.byKey(const Key('candidate-kind-brand-new-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入清单'));
    await tester.pumpAndSettle();
    // 新草稿同时预填模型 ID 与显示名称，两个输入框都应保留远端 ID。
    expect(find.text('brand-new-model'), findsNWidgets(2));

    // 保存后落库：新模型默认禁用；已知目录模型 kind 正确落地；原模型不受影响
    await tester.tap(find.byKey(const Key('model-editor-save')));
    await tester.pumpAndSettle();
    final models = await engine.listProviderModels('deepseek');
    final byId = {for (final m in models) m.modelId: m};
    expect(byId['brand-new-model']!.kind, 'image');
    expect(byId['brand-new-model']!.enabled, isFalse,
        reason: '拉取候选默认禁用（spec §5 第 5 条）');
    expect(byId['deepseek-v4-pro']!.kind, 'text',
        reason: '目录已知模型的自动预填 kind 应随保存正确落库');
    expect(byId['deepseek-v4-pro']!.enabled, isFalse,
        reason: '拉取候选默认禁用（spec §5 第 5 条），即便 kind 是自动预填的');
    expect(byId['deepseek-v4-flash']!.enabled, isTrue, reason: '已有条目不受影响');
  });
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  await tester.dragUntilVisible(
    find.text(label),
    find.byType(SegmentedButton).first,
    const Offset(-160, 0),
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _chooseFirstDropdown(
  WidgetTester tester,
  String optionLabel,
) async {
  await tester.tap(find
      .byWidgetPredicate((widget) => widget is DropdownButtonFormField)
      .first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}
