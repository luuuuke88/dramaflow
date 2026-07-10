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
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(engine.config.str('app.locale'), 'ja');
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('移动端设置页：可编辑模型专属提示词模板', (tester) async {
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
    engine.db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        provider.id,
        'doubao-seedance-2-0-mini-260615',
        'video_prompt_gen',
        'video/seedance2Multi-parameterMode.md',
        '旧 Seedance 模板',
      ],
    );

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '提示词');
    expect(find.text('模型专属模板'), findsOneWidget);
    expect(find.textContaining('Volcengine · Seedance Mini'), findsOneWidget);

    await tester
        .ensureVisible(find.textContaining('Volcengine · Seedance Mini'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Volcengine · Seedance Mini'));
    await tester.pumpAndSettle();
    expect(find.textContaining('编辑提示词 · Volcengine · Seedance Mini'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '新 Seedance 模板');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final prompt = engine.db.select(
        'SELECT prompt FROM o_modelPrompt WHERE vendorId=?',
        [provider.id]).single['prompt'];
    expect(prompt, '新 Seedance 模板');
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

    await tester.tap(find.text('添加模型').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'local-text');
    await tester.enterText(find.byType(TextField).at(1), '本地文本模型');
    await tester.tap(find.text('保存'));
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

    await tester.tap(find.text('保存'));
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
    await tester.tap(find.text('保存'));
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
    await tester.tap(find.text('保存'));
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

  testWidgets('移动端设置页：分模态连通测试可选择图片和视频模型', (tester) async {
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
    final provider = await engine.createProvider(
      name: 'Local Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: 'local',
    );
    await engine.saveProviderModels(provider.id, const [
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
    await tester.tap(find.byTooltip('测试连通').first);
    await tester.pumpAndSettle();
    expect(find.text('测试连通 · Local Gateway'), findsOneWidget);

    await _chooseFirstDropdown(tester, '图片 · 本地图像');
    await tester.tap(find.text('测试').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('测试连通').first);
    await tester.pumpAndSettle();
    await _chooseFirstDropdown(tester, '视频 · 本地视频');
    await tester.tap(find.text('测试').last);
    await tester.pumpAndSettle();

    expect(gateway.calls, [
      'image:local-image',
      'video:local-video',
    ]);
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
