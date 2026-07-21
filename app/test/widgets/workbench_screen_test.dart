import 'dart:io';
import 'dart:convert';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_audio.dart';
import 'package:dramaflow/src/engine/timeline_clip.dart';
import 'package:dramaflow/src/engine/video_request.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:dramaflow/src/screens/production/workbench_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dramaflow/src/widgets/common.dart';
import 'package:dio/dio.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class _NoopGateway implements ProviderGateway {
  int textCalls = 0;
  String Function(int call, String system, String user)? textHandler;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    expect(stage, 'video_prompt_gen');
    final handler = textHandler;
    if (handler == null) {
      throw StateError('unexpected text call');
    }
    textCalls += 1;
    return TextResult(handler(textCalls, system, user));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeComposer implements VideoComposer {
  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    File(outputAbsPath).writeAsBytesSync([0]);
  }

  @override
  Future<void> compose(
      List<ComposeSegment> segments, String outputAbsPath) async {
    File(outputAbsPath).writeAsBytesSync([0]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => 4.0;
}

class _RecordingComposer implements VideoComposer {
  final List<List<String>> concatCalls = [];
  final List<List<ComposeSegment>> composeCalls = [];

  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    concatCalls.add(segmentAbsPaths);
    File(outputAbsPath).writeAsBytesSync([0]);
  }

  @override
  Future<void> compose(
      List<ComposeSegment> segments, String outputAbsPath) async {
    composeCalls.add(segments);
    File(outputAbsPath).writeAsBytesSync([0]);
  }

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async => 4.0;
}

class _PreviewSaveSelector extends FileSelectorPlatform {
  String path;
  int saveCalls = 0;
  List<XTypeGroup>? acceptedTypeGroups;

  _PreviewSaveSelector(this.path);

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saveCalls++;
    this.acceptedTypeGroups = acceptedTypeGroups;
    return FileSaveLocation(path);
  }
}

void main() {
  late Directory dir;
  late Engine engine;
  late _NoopGateway gateway;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-workbench-');
    final db = openEngineDb(':memory:');
    gateway = _NoopGateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      composer: _FakeComposer(),
    );
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) '
      'VALUES (?,?,?,?)',
      [
        'volcengine',
        1,
        '{}',
        jsonEncode([
          {
            'modelId': 'test-video',
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': ['first_frame'],
                'references': {'image': 1},
                'durations': [5],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'none',
              },
            },
          },
        ]),
      ],
    );
    db.execute(
      "INSERT INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:test-video')",
    );
    // 本文件断言的是工作台批量/单条生成视频等业务逻辑，不是确认闸弹窗本身
    // （闸本身已由 policy_confirm_test.dart 覆盖）；关闸避免每个用例都要多点一次确认。
    // 设置写入共享 db（o_setting 表），文件内部分用例会用同一个 db 重建 Engine
    // （见「移动端…」系列用例），该设置随 db 一并继承，无需重复关闸。
    engine.config.update({'policy.confirmMoney': '0'});
    engine.installVideoTrackPipeline();
    engine.saveVisualManual(
      name: '工作台视觉',
      pack: 'workbench_pack',
      data: const {'art_storyboard_video': '工作台视频视觉手册'},
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '工作台测试',
      artStyle: 'workbench_pack',
    );
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app({Locale locale = const Locale('zh')}) {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(
          body: Builder(builder: (innerContext) {
            return Consumer(builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () => showWorkbench(innerContext, ref,
                    projectId: projectId, scriptId: scriptId),
                child: const Text('open'),
              );
            });
          }),
        ),
      ),
    ]);
    return ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        locale: locale,
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    );
  }

  Widget appearanceApp() {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(
          body: Builder(builder: (innerContext) {
            return Consumer(builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () => showWorkbench(innerContext, ref,
                    projectId: projectId, scriptId: scriptId),
                child: const Text('open'),
              );
            });
          }),
        ),
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

  Future<void> tapTimelineClipAction(
    WidgetTester tester, {
    required int clipId,
    required String actionKey,
  }) async {
    final menuFinder =
        find.byKey(ValueKey('workbench-timeline-clip-menu-$clipId'));
    await tester.ensureVisible(menuFinder);
    await tester.pumpAndSettle();
    await tester.tap(menuFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(actionKey)));
    await tester.pumpAndSettle();
  }

  Future<void> tapWorkbenchBatchAction(
    WidgetTester tester,
    String label,
  ) async {
    await tester.tap(find.byKey(const ValueKey('workbench-batch-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    // 批量生成会维持运行态动画，不能在触发后台动作后等待所有动画静止。
    await tester.pump();
  }

  testWidgets('无分镜时显示空态', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('暂无分镜，请先在「制作」的分镜节点生成'), findsOneWidget);
  });

  testWidgets('工作台可创建独立视频轨，窄屏入口仍可操作', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final addTrack =
        find.byKey(const ValueKey('workbench-add-standalone-track'));
    expect(addTrack, findsOneWidget);
    await tester.tap(addTrack);
    await tester.pumpAndSettle();

    final tracks = engine.standaloneVideoTracks(projectId, scriptId);
    expect(tracks, hasLength(1));
    expect(tracks.single.duration, 5);
    expect(
        find.byKey(ValueKey('workbench-standalone-track-${tracks.single.id}')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立视频轨删除需确认且不影响分镜轨', (tester) async {
    final storyboardId =
        engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final storyboardTrackId = engine.ensureTrackForStoryboard(storyboardId);
    final standaloneTrackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        ValueKey('workbench-delete-standalone-track-$standaloneTrackId')));
    await tester.pumpAndSettle();

    expect(find.text('删除此视频轨及其候选视频？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(engine.track(standaloneTrackId), isNull);
    expect(engine.track(storyboardTrackId), isNotNull);
    expect(engine.storyboards(scriptId).single.trackId, storyboardTrackId);
  });

  testWidgets('有分镜时渲染镜头行+合成按钮显示缺口提示', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('S1'), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-compose-compact')),
        findsOneWidget);
  });

  testWidgets('工作台快速预览按时长跳镜并展示本地分镜与关联资产', (tester) async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL3UQAAAABJRU5ErkJggg==';
    engine.db.execute(
      "INSERT INTO o_image (filePath,type,state) VALUES ('assets/hero.png','role','已完成')",
    );
    final imageId = engine.db.lastInsertRowId;
    engine.db.execute(
      "INSERT INTO o_assets (projectId,name,type,imageId) VALUES (?,'林朝雪','role',?)",
      [projectId, imageId],
    );
    final assetId = engine.db.lastInsertRowId;
    final first = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '雪夜山门，月光照剑。',
      videoDesc: '镜头一描述',
      duration: '2',
      assetIds: [assetId],
    );
    final second = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '拔剑后快切近景。',
      videoDesc: '镜头二描述',
      duration: '4',
    );
    for (final rel in ['assets/hero.png', 'shots/one.png', 'shots/two.png']) {
      final file = File(engine.mediaAbsPath(rel));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(base64Decode(png));
    }
    engine.setStoryboardImage(first, 'shots/one.png');
    engine.setStoryboardImage(second, 'shots/two.png');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-quick-preview')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('workbench-preview-page')), findsOneWidget);
    expect(find.textContaining('镜头一描述'), findsOneWidget);
    expect(find.text('林朝雪（角色）'), findsOneWidget);
    expect(find.text('雪夜山门，月光照剑。'), findsOneWidget);
    expect(find.text('00:06'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workbench-preview-next')));
    await tester.pump();
    expect(find.textContaining('镜头二描述'), findsOneWidget);
    expect(find.byKey(ValueKey('workbench-preview-thumbnail-$second')),
        findsOneWidget);
  });

  testWidgets('390dp 工作台快速预览可切换缩略图并访问导出动作', (tester) async {
    final first = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动端第一镜',
      videoDesc: '移动端第一镜描述',
      duration: '3',
    );
    final second = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动端第二镜',
      videoDesc: '移动端第二镜描述',
      duration: '5',
    );
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-quick-preview')));
    await tester.pumpAndSettle();

    final thumbnail =
        find.byKey(ValueKey('workbench-preview-thumbnail-$second'));
    await tester.ensureVisible(thumbnail);
    await tester.tap(thumbnail);
    await tester.pump();
    expect(find.textContaining('移动端第二镜描述'), findsOneWidget);
    final checkbox = find.byKey(ValueKey('workbench-preview-selected-$second'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.drag(
      find.byKey(const ValueKey('workbench-preview-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('workbench-preview-export')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(first, isPositive);
  });

  testWidgets('快速预览缺失关联资产图时保持可用', (tester) async {
    engine.db.execute(
      "INSERT INTO o_image (filePath,type,state) VALUES ('assets/missing.png','role','已完成')",
    );
    final imageId = engine.db.lastInsertRowId;
    engine.db.execute(
      "INSERT INTO o_assets (projectId,name,type,imageId) VALUES (?,'缺图角色','role',?)",
      [projectId, imageId],
    );
    final assetId = engine.db.lastInsertRowId;
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '缺图镜头',
      assetIds: [assetId],
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-quick-preview')));
    await tester.pumpAndSettle();

    expect(find.text('缺图角色（角色）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快速预览时间段保持 48dp 触控命中区', (tester) async {
    final shot = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '可触控时间段',
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-quick-preview')));
    await tester.pumpAndSettle();

    final segment = find.byKey(ValueKey('workbench-preview-segment-$shot'));
    expect(segment, findsOneWidget);
    expect(tester.getRect(segment).height, greaterThanOrEqualTo(48));
  });

  testWidgets('1024dp 英文工作台将批量动作收进紧凑工具栏', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workbench-compose-compact')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工作台快速预览为已选首帧请求 ZIP 保存', (tester) async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL3UQAAAABJRU5ErkJggg==';
    final shot = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '导出镜头',
      duration: '3',
    );
    const rel = 'shots/export.png';
    final source = File(engine.mediaAbsPath(rel));
    source.parent.createSync(recursive: true);
    source.writeAsBytesSync(base64Decode(png));
    engine.setStoryboardImage(shot, rel);
    final output = p.join(dir.path, 'preview.zip');
    final selector = _PreviewSaveSelector(output);
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-quick-preview')));
    await tester.pumpAndSettle();
    final checkbox = find.byKey(ValueKey('workbench-preview-selected-$shot'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    final export = find.byKey(const ValueKey('workbench-preview-export'));
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(selector.saveCalls, 1);
    expect(selector.acceptedTypeGroups?.single.extensions, ['zip']);
  });

  testWidgets('桌面最大外观设置下工作台可选中镜头且主色生效', (tester) async {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '外观极值镜头',
    );
    await engine.setThemePrimaryColor('#2BA471');
    await engine.setThemeFontSize(22);
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appearanceApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final shotContext = tester.element(find.text('S1'));
    expect(Theme.of(shotContext).colorScheme.primary, const Color(0xFF2BA471));
    expect(MediaQuery.textScalerOf(shotContext).scale(16), 22);

    final checkboxKey = ValueKey('workbench-shot-check-$storyboardId');
    expect(tester.widget<Checkbox>(find.byKey(checkboxKey)).value, isTrue);
    await tester.tap(find.byKey(checkboxKey));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byKey(checkboxKey)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工作台显示视频轨和音频轨时间线总览', (tester) async {
    final s1 = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    final s2 = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头二',
      duration: '6',
    );
    final t1 = engine.ensureTrackForStoryboard(s1);
    final t2 = engine.ensureTrackForStoryboard(s2);
    engine.updateVideoDuration(t1, 5);
    engine.db.execute(
      "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
      [t1, 'p/vid_1.mp4', vtDone],
    );
    engine.selectVideo(t1, engine.db.lastInsertRowId);
    engine.db.execute(
      "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
      [t2, 'p/vid_2.mp4', vtDone],
    );
    engine.selectVideo(t2, engine.db.lastInsertRowId);
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: '旁白音色',
      sex: '女',
      describe: '温柔',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '这里绑定到第二镜。',
          name: '旁白音色-样例',
          describe: '轻声',
          existingImageId: null,
        ),
      ],
    );
    engine.bindStoryboardAudio(storyboardId: s2, audioAssetId: audioId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('时间线总览'), findsOneWidget);
    expect(find.text('视频轨'), findsOneWidget);
    expect(find.text('音频轨'), findsOneWidget);
    expect(
        find.byKey(ValueKey('workbench-timeline-video-$s1')), findsOneWidget);
    expect(
        find.byKey(ValueKey('workbench-timeline-video-$s2')), findsOneWidget);
    expect(
        find.byKey(ValueKey('workbench-timeline-audio-$s2')), findsOneWidget);
    expect(find.text('5 秒'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('workbench-timeline-audio-$s2')),
        matching: find.text('旁白音色'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('工作台可从素材库添加多层时间线素材段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const rel = 'p/overlay_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 6]);
    engine.registerClipAsset(
      projectId: projectId,
      name: '法阵叠加',
      relPath: rel,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加素材层'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('法阵叠加'));
    await tester.enterText(find.widgetWithText(TextField, '层级'), '2');
    await tester.enterText(find.widgetWithText(TextField, '起点(ms)'), '1500');
    await tester.enterText(find.widgetWithText(TextField, '时长(ms)'), '1200');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    final clip = engine.timelineClips(scriptId).single;
    expect(clip.name, '法阵叠加');
    expect(clip.filePath, rel);
    expect(clip.lane, 2);
    expect(clip.startMs, 1500);
    expect(clip.durationMs, 1200);
    expect(find.text('素材层'), findsOneWidget);
    expect(find.text('法阵叠加'), findsOneWidget);
    expect(find.byKey(ValueKey('workbench-timeline-clip-${clip.id}')),
        findsOneWidget);
  });

  testWidgets('移动端工作台：添加素材层使用全屏单列表单并可保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '4',
    );
    const rel = 'p/mobile_overlay_add.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([7, 7, 7]);
    engine.registerClipAsset(
      projectId: projectId,
      name: '移动新增素材层',
      relPath: rel,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加素材层'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    final laneTop = tester.getTopLeft(find.widgetWithText(TextField, '层级')).dy;
    final startTop =
        tester.getTopLeft(find.widgetWithText(TextField, '起点(ms)')).dy;
    final durationTop =
        tester.getTopLeft(find.widgetWithText(TextField, '时长(ms)')).dy;
    expect(startTop, greaterThan(laneTop));
    expect(durationTop, greaterThan(startTop));

    await tester.enterText(find.widgetWithText(TextField, '层级'), '2');
    await tester.enterText(find.widgetWithText(TextField, '起点(ms)'), '600');
    await tester.enterText(find.widgetWithText(TextField, '时长(ms)'), '1100');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    final clip = engine.timelineClips(scriptId).single;
    expect(clip.name, '移动新增素材层');
    expect(clip.lane, 2);
    expect(clip.startMs, 600);
    expect(clip.durationMs, 1100);
    expect(find.textContaining('L2 · 600ms · 1100ms'), findsOneWidget);
  });

  testWidgets('工作台添加素材层可自动选择同时间空层', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/auto_layer_a.mp4';
    const relB = 'p/auto_layer_b.mp4';
    const relInsert = 'p/auto_layer_insert.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 1, 9]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 2, 9]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 3, 9]);
    engine.registerClipAsset(
      projectId: projectId,
      name: '自动层素材',
      relPath: relInsert,
    );
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '已有素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '已有素材 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 0,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加素材层'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '层级'), '1');
    await tester.enterText(find.widgetWithText(TextField, '起点(ms)'), '200');
    await tester.enterText(find.widgetWithText(TextField, '时长(ms)'), '500');
    await tester.tap(find.widgetWithText(FilledButton, '自动层级添加'));
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final inserted = clips.singleWhere((clip) => clip.name == '自动层素材');
    expect(inserted.lane, 3);
    expect(inserted.startMs, 200);
    expect(inserted.durationMs, 500);
    expect(find.textContaining('L3 · 200ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台媒体库可按播放头快捷添加素材层并自动找空层', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/media_library_lane_a.mp4';
    const relB = 'p/media_library_lane_b.mp4';
    const relInsert = 'p/media_library_insert.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 5, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 5, 2]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 5, 3]);
    final insertAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '媒体库快捷素材',
      relPath: relInsert,
    );
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '媒体库占用 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '媒体库占用 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 1200,
      durationMs: 1000,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 1200,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1500',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-timeline-media')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-media-add-$insertAssetId')),
    );
    await tester.pumpAndSettle();

    final inserted = engine
        .timelineClips(scriptId)
        .singleWhere((clip) => clip.name == '媒体库快捷素材');
    expect(inserted.lane, 3);
    expect(inserted.startMs, 1500);
    expect(inserted.durationMs, isNull);
    expect(find.textContaining('L3 · 1500ms'), findsOneWidget);
  });

  testWidgets('移动端工作台：媒体库按播放头添加素材层使用全屏列表', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '4',
    );
    const relA = 'p/mobile_media_library_lane_a.mp4';
    const relB = 'p/mobile_media_library_lane_b.mp4';
    const relInsert = 'p/mobile_media_library_insert.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 6, 3]);
    final insertAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '移动媒体库素材',
      relPath: relInsert,
    );
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '移动媒体占用 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '移动媒体占用 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 1000,
      durationMs: 900,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 1000,
      durationMs: 900,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1200',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-timeline-media')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('时间线媒体库'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-media-add-$insertAssetId')),
    );
    await tester.pumpAndSettle();

    final inserted = engine
        .timelineClips(scriptId)
        .singleWhere((clip) => clip.name == '移动媒体库素材');
    expect(inserted.lane, 3);
    expect(inserted.startMs, 1200);
    expect(inserted.durationMs, isNull);
    expect(find.textContaining('L3 · 1200ms'), findsOneWidget);
  });

  testWidgets('工作台可拖放媒体库素材到时间线落点并自动找空层', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/media_drag_lane_a.mp4';
    const relB = 'p/media_drag_lane_b.mp4';
    const relInsert = 'p/media_drag_insert.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 6, 3]);
    final insertAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放素材',
      relPath: relInsert,
    );
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放占用 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放占用 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 2200,
      durationMs: 1000,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 2200,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1300',
    );
    await tester.pumpAndSettle();

    final dragSource =
        find.byKey(ValueKey('workbench-timeline-media-drag-$insertAssetId'));
    final dropTarget =
        find.byKey(const ValueKey('workbench-timeline-drop-zone'));
    expect(dragSource, findsOneWidget);
    expect(dropTarget, findsOneWidget);
    final dropTopLeft = tester.getTopLeft(dropTarget);
    final dropSize = tester.getSize(dropTarget);
    final dropAt2500ms =
        dropTopLeft + Offset(92 + 25 * 12, dropSize.height / 2);
    await tester.dragFrom(
      tester.getCenter(dragSource),
      dropAt2500ms - tester.getCenter(dragSource),
    );
    await tester.pumpAndSettle();

    final inserted = engine
        .timelineClips(scriptId)
        .singleWhere((clip) => clip.name == '拖放素材');
    expect(inserted.lane, 3);
    expect(inserted.startMs, 2500);
    expect(inserted.durationMs, isNull);
    expect(find.textContaining('L3 · 2500ms'), findsOneWidget);
  });

  testWidgets('工作台拖放媒体库素材接近播放头时自动吸附', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/media_drag_snap_lane_a.mp4';
    const relB = 'p/media_drag_snap_lane_b.mp4';
    const relInsert = 'p/media_drag_snap_insert.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 5]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([6, 6, 6]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 6, 4]);
    final insertAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放吸附素材',
      relPath: relInsert,
    );
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放吸附占用 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放吸附占用 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 2200,
      durationMs: 1000,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 2200,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '2600',
    );
    await tester.pumpAndSettle();

    final dragSource =
        find.byKey(ValueKey('workbench-timeline-media-drag-$insertAssetId'));
    final dropTarget =
        find.byKey(const ValueKey('workbench-timeline-drop-zone'));
    expect(dragSource, findsOneWidget);
    expect(dropTarget, findsOneWidget);
    final dropTopLeft = tester.getTopLeft(dropTarget);
    final dropSize = tester.getSize(dropTarget);
    final dropNear2600ms =
        dropTopLeft + Offset(92 + 25 * 12, dropSize.height / 2);
    await tester.dragFrom(
      tester.getCenter(dragSource),
      dropNear2600ms - tester.getCenter(dragSource),
    );
    await tester.pumpAndSettle();

    final inserted = engine
        .timelineClips(scriptId)
        .singleWhere((clip) => clip.name == '拖放吸附素材');
    expect(inserted.lane, 3);
    expect(inserted.startMs, 2600);
    expect(inserted.durationMs, isNull);
    expect(find.textContaining('L3 · 2600ms'), findsOneWidget);
  });

  testWidgets('工作台拖放媒体库素材尾部接近锚点时自动吸附', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/media_drag_end_snap_lane_a.mp4';
    const relB = 'p/media_drag_end_snap_lane_b.mp4';
    const relInsert = 'p/media_drag_end_snap_insert.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([8, 6, 8]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 6, 9]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([7, 6, 7]);
    final insertAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放尾部吸附素材',
      relPath: relInsert,
    );
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放尾部吸附占用 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '拖放尾部吸附占用 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 2200,
      durationMs: 1000,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 2200,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '3500',
    );
    await tester.pumpAndSettle();

    final dragSource =
        find.byKey(ValueKey('workbench-timeline-media-drag-$insertAssetId'));
    final dropTarget =
        find.byKey(const ValueKey('workbench-timeline-drop-zone'));
    expect(dragSource, findsOneWidget);
    expect(dropTarget, findsOneWidget);
    final dropTopLeft = tester.getTopLeft(dropTarget);
    final dropSize = tester.getSize(dropTarget);
    final dropNear3500msEnd =
        dropTopLeft + Offset(92 + 25.5 * 12, dropSize.height / 2);
    await tester.dragFrom(
      tester.getCenter(dragSource),
      dropNear3500msEnd - tester.getCenter(dragSource),
    );
    await tester.pumpAndSettle();

    final inserted = engine
        .timelineClips(scriptId)
        .singleWhere((clip) => clip.name == '拖放尾部吸附素材');
    expect(inserted.lane, 3);
    expect(inserted.startMs, 2500);
    expect(inserted.durationMs, isNull);
    expect(find.textContaining('L3 · 2500ms'), findsOneWidget);
  });

  testWidgets('工作台可波纹插入素材层并后移同轨后续片段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relExisting = 'p/ripple_insert_existing.mp4';
    const relOtherLane = 'p/ripple_insert_other_lane.mp4';
    const relInsert = 'p/ripple_insert_new.mp4';
    File(engine.mediaAbsPath(relExisting))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 7, 1]);
    File(engine.mediaAbsPath(relOtherLane))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 7, 2]);
    File(engine.mediaAbsPath(relInsert))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 7, 3]);
    engine.registerClipAsset(
      projectId: projectId,
      name: '插入素材',
      relPath: relInsert,
    );
    final existingAsset = engine.registerClipAsset(
      projectId: projectId,
      name: '后续素材',
      relPath: relExisting,
    );
    final otherLaneAsset = engine.registerClipAsset(
      projectId: projectId,
      name: '异轨素材',
      relPath: relOtherLane,
    );
    final existingClipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: existingAsset,
      lane: 1,
      startMs: 1000,
      durationMs: 600,
    );
    final otherLaneClipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: otherLaneAsset,
      lane: 2,
      startMs: 1000,
      durationMs: 600,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加素材层'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '层级'), '1');
    await tester.enterText(find.widgetWithText(TextField, '起点(ms)'), '700');
    await tester.enterText(find.widgetWithText(TextField, '时长(ms)'), '400');
    await tester.tap(find.widgetWithText(FilledButton, '波纹插入'));
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final inserted = clips.singleWhere((clip) => clip.name == '插入素材');
    expect(inserted.startMs, 700);
    expect(inserted.durationMs, 400);
    final shifted = clips.singleWhere((clip) => clip.id == existingClipId);
    expect(shifted.startMs, 1400);
    expect(shifted.durationMs, 600);
    final otherLane = clips.singleWhere((clip) => clip.id == otherLaneClipId);
    expect(otherLane.startMs, 1000);
    expect(otherLane.durationMs, 600);
    expect(find.textContaining('L1 · 700ms · 400ms'), findsOneWidget);
    expect(find.textContaining('L1 · 1400ms · 600ms'), findsOneWidget);
  });

  testWidgets('工作台可拖拽素材层调整时间线位置', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const rel = 'p/drag_overlay_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([7, 8, 9]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '拖动素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipId'));
    expect(clipFinder, findsOneWidget);
    await tester.drag(clipFinder, const Offset(48, 40));
    await tester.pumpAndSettle();

    final updated = engine.timelineClips(scriptId).single;
    expect(updated.lane, 3);
    expect(updated.startMs, 1900);
    expect(updated.durationMs, 1200);
    expect(find.textContaining('L3 · 1900ms'), findsOneWidget);
  });

  testWidgets('工作台素材层按时间起点拉开可视间距', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/visual_gap_overlay_a.mp4';
    const relB = 'p/visual_gap_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '视觉间距 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '视觉间距 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 3000,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final firstLeft = tester.getTopLeft(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdA')),
    );
    final secondLeft = tester.getTopLeft(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdB')),
    );
    expect(secondLeft.dx - firstLeft.dx, greaterThanOrEqualTo(350));
  });

  testWidgets('工作台素材层按 lane 分成可视多轨且同起点对齐', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/visual_lane_overlay_a.mp4';
    const relB = 'p/visual_lane_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 5, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 5, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '视觉轨道 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '视觉轨道 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 0,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final firstLeft = tester.getTopLeft(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdA')),
    );
    final secondLeft = tester.getTopLeft(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdB')),
    );
    expect((secondLeft.dx - firstLeft.dx).abs(), lessThanOrEqualTo(4));
    expect(secondLeft.dy - firstLeft.dy, greaterThanOrEqualTo(50));
  });

  testWidgets('工作台可拖拽素材层边缘裁剪时长', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const rel = 'p/trim_overlay_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 2, 1]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '裁剪素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final endHandle =
        find.byKey(ValueKey('workbench-timeline-clip-resize-end-$clipId'));
    expect(endHandle, findsOneWidget);
    await tester.drag(endHandle, const Offset(36, 0));
    await tester.pumpAndSettle();

    var updated = engine.timelineClips(scriptId).single;
    expect(updated.startMs, 1500);
    expect(updated.durationMs, 1500);
    expect(find.textContaining('1500ms · 1500ms'), findsOneWidget);

    final startHandle =
        find.byKey(ValueKey('workbench-timeline-clip-resize-start-$clipId'));
    expect(startHandle, findsOneWidget);
    await tester.drag(startHandle, const Offset(24, 0));
    await tester.pumpAndSettle();

    updated = engine.timelineClips(scriptId).single;
    expect(updated.startMs, 1700);
    expect(updated.durationMs, 1300);
    expect(find.textContaining('1700ms · 1300ms'), findsOneWidget);
  });

  testWidgets('工作台裁剪素材层边缘时避免同轨重叠冲突', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/trim_overlap_guard_a.mp4';
    const relB = 'p/trim_overlap_guard_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '裁剪冲突 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '裁剪冲突 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1600,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final endHandleA =
        find.byKey(ValueKey('workbench-timeline-clip-resize-end-$clipIdA'));
    expect(endHandleA, findsOneWidget);
    await tester.drag(endHandleA, const Offset(96, 0));
    await tester.pumpAndSettle();

    var clips = engine.timelineClips(scriptId);
    var first = clips.singleWhere((c) => c.id == clipIdA);
    expect(first.startMs, 0);
    expect(first.durationMs, 1600);

    final startHandleB =
        find.byKey(ValueKey('workbench-timeline-clip-resize-start-$clipIdB'));
    expect(startHandleB, findsOneWidget);
    await tester.drag(startHandleB, const Offset(-96, 0));
    await tester.pumpAndSettle();

    clips = engine.timelineClips(scriptId);
    final second = clips.singleWhere((c) => c.id == clipIdB);
    expect(second.startMs, 1600);
    expect(second.durationMs, 800);
    expect(find.textContaining('1600ms · 800ms'), findsOneWidget);
  });

  testWidgets('工作台可分割素材层为连续片段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const rel = 'p/split_overlay_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([8, 6, 4]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '分割素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipId,
      actionKey: 'workbench-timeline-clip-split-$clipId',
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(2));
    expect(clips[0].id, clipId);
    expect(clips[0].startMs, 1500);
    expect(clips[0].durationMs, 600);
    expect(clips[1].startMs, 2100);
    expect(clips[1].durationMs, 600);
    expect(find.textContaining('2100ms · 600ms'), findsOneWidget);
  });

  testWidgets('工作台可按播放头切分素材层', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const rel = 'p/playhead_split_overlay_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 7]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '播放头分割素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipId,
      actionKey: 'workbench-timeline-clip-split-at-$clipId',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-split-playhead-input')),
      '2200',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-split-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(2));
    expect(clips[0].id, clipId);
    expect(clips[0].startMs, 1500);
    expect(clips[0].durationMs, 700);
    expect(clips[1].startMs, 2200);
    expect(clips[1].durationMs, 500);
    expect(find.textContaining('2200ms · 500ms'), findsOneWidget);
  });

  testWidgets('移动端工作台：按播放头切分素材层使用全屏表单并保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '4',
    );
    const rel = 'p/mobile_playhead_split_overlay_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 8]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '移动播放头分割素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipId,
      actionKey: 'workbench-timeline-clip-split-at-$clipId',
    );

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('按播放头切分素材层'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-split-playhead-input')),
      '2200',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-split-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(2));
    expect(clips[0].id, clipId);
    expect(clips[0].startMs, 1500);
    expect(clips[0].durationMs, 700);
    expect(clips[1].startMs, 2200);
    expect(clips[1].durationMs, 500);
    expect(find.textContaining('2200ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并按播放头批量切分', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/batch_split_overlay_a.mp4';
    const relB = 'p/batch_split_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 7, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 7, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '批量分割 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '批量分割 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 200,
      durationMs: 1000,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '700',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-split-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(4));
    expect(clips.singleWhere((c) => c.id == clipIdA).durationMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdB).durationMs, 500);
    expect(clips.where((c) => c.startMs == 700), hasLength(2));
    expect(find.textContaining('700ms · 300ms'), findsOneWidget);
    expect(find.textContaining('700ms · 500ms'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-delete-selected')),
    );
    await tester.pumpAndSettle();

    expect(engine.timelineClips(scriptId), isEmpty,
        reason: '批量切分后新尾段也应保留选中状态，后续批量操作才不会漏掉');
  });

  testWidgets('工作台可选中多个素材层并按播放头批量裁剪尾部', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/batch_trim_to_playhead_overlay_a.mp4';
    const relB = 'p/batch_trim_to_playhead_overlay_b.mp4';
    const relC = 'p/batch_trim_to_playhead_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 9, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '裁到播放头 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '裁到播放头 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '裁到播放头 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 900,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 200,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '800',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-trim-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final trimmedA = clips.singleWhere((c) => c.id == clipIdA);
    final trimmedB = clips.singleWhere((c) => c.id == clipIdB);
    final untouchedC = clips.singleWhere((c) => c.id == clipIdC);
    expect(trimmedA.startMs, 100);
    expect(trimmedA.durationMs, 700);
    expect(trimmedB.startMs, 300);
    expect(trimmedB.durationMs, 500);
    expect(untouchedC.startMs, 200);
    expect(untouchedC.durationMs, 400);
    expect(find.textContaining('100ms · 700ms'), findsOneWidget);
    expect(find.textContaining('300ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台按播放头裁剪相邻选中素材层时不互相钳制', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/batch_trim_adjacent_a.mp4';
    const relB = 'p/batch_trim_adjacent_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 11, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 11, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '相邻裁剪 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '相邻裁剪 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 500,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '800',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-trim-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).durationMs, 800);
    expect(clips.singleWhere((c) => c.id == clipIdB).durationMs, 300);
  });

  testWidgets('工作台可选中多个素材层并按播放头批量裁剪头部', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/batch_trim_start_to_playhead_overlay_a.mp4';
    const relB = 'p/batch_trim_start_to_playhead_overlay_b.mp4';
    const relC = 'p/batch_trim_start_to_playhead_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 10, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 10, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 10, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '裁头到播放头 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '裁头到播放头 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '裁头到播放头 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 900,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 200,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '800',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-trim-start-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final trimmedA = clips.singleWhere((c) => c.id == clipIdA);
    final trimmedB = clips.singleWhere((c) => c.id == clipIdB);
    final untouchedC = clips.singleWhere((c) => c.id == clipIdC);
    expect(trimmedA.startMs, 800);
    expect(trimmedA.durationMs, 300);
    expect(trimmedB.startMs, 800);
    expect(trimmedB.durationMs, 400);
    expect(untouchedC.startMs, 200);
    expect(untouchedC.durationMs, 400);
    expect(find.textContaining('800ms · 300ms'), findsOneWidget);
    expect(find.textContaining('800ms · 400ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量删除', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/batch_delete_overlay_a.mp4';
    const relB = 'p/batch_delete_overlay_b.mp4';
    const relC = 'p/batch_delete_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 8, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '批量删除 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '保留 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '批量删除 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 0,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 0,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdC')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-delete-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(1));
    expect(clips.single.id, clipIdB);
    expect(
        find.byKey(ValueKey('workbench-timeline-clip-$clipIdA')), findsNothing);
    expect(find.byKey(ValueKey('workbench-timeline-clip-$clipIdB')),
        findsOneWidget);
    expect(
        find.byKey(ValueKey('workbench-timeline-clip-$clipIdC')), findsNothing);
  });

  testWidgets('工作台可选中多个素材层并批量波纹删除', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/batch_ripple_delete_overlay_a.mp4';
    const relB = 'p/batch_ripple_delete_overlay_b.mp4';
    const relC = 'p/batch_ripple_delete_overlay_c.mp4';
    const relD = 'p/batch_ripple_delete_overlay_d.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 4, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 4, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 4, 3]);
    File(engine.mediaAbsPath(relD))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 4, 4]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹删 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹删 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 C',
      relPath: relC,
    );
    final clipAssetD = engine.registerClipAsset(
      projectId: projectId,
      name: '其他轨 D',
      relPath: relD,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 700,
      durationMs: 300,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 1200,
      durationMs: 400,
    );
    final clipIdD = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetD,
      lane: 2,
      startMs: 1200,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-delete-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.map((c) => c.id), isNot(contains(clipIdA)));
    expect(clips.map((c) => c.id), isNot(contains(clipIdB)));
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 400);
    expect(clips.singleWhere((c) => c.id == clipIdD).startMs, 1200);
    expect(find.textContaining('400ms · 400ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量复制成相对时间一致的新组', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_duplicate_overlay_a.mp4';
    const relB = 'p/batch_duplicate_overlay_b.mp4';
    const relC = 'p/batch_duplicate_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 6, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '批量复制 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '批量复制 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '占位 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 200,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 900,
      durationMs: 400,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 1300,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-duplicate-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(5));
    expect(
      clips.where((c) => c.assetId == clipAssetA && c.startMs == 1600),
      hasLength(1),
    );
    expect(
      clips.where((c) => c.assetId == clipAssetB && c.startMs == 2300),
      hasLength(1),
    );
    expect(find.textContaining('1600ms · 500ms'), findsOneWidget);
    expect(find.textContaining('2300ms · 400ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并复制到播放头', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_copy_playhead_overlay_a.mp4';
    const relB = 'p/batch_copy_playhead_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 7, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 7, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '复制播放头 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '复制播放头 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1200',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-copy-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(4));
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 100);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 300);
    final copiedA = clips.singleWhere(
      (c) => c.id != clipIdA && c.assetId == clipAssetA,
    );
    final copiedB = clips.singleWhere(
      (c) => c.id != clipIdB && c.assetId == clipAssetB,
    );
    expect(copiedA.startMs, 1200);
    expect(copiedB.startMs, 1400);
    expect(find.textContaining('1200ms · 400ms'), findsOneWidget);
    expect(find.textContaining('1400ms · 500ms'), findsOneWidget);
    expect(find.byKey(ValueKey('workbench-timeline-clip-${copiedA.id}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('workbench-timeline-clip-${copiedB.id}')),
        findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并对齐到播放头', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_align_playhead_overlay_a.mp4';
    const relB = 'p/batch_align_playhead_overlay_b.mp4';
    const relC = 'p/batch_align_playhead_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 8, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '对齐播放头 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '对齐播放头 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '对齐播放头 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1200',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-align-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final alignedA = clips.singleWhere((c) => c.id == clipIdA);
    final alignedB = clips.singleWhere((c) => c.id == clipIdB);
    final untouchedC = clips.singleWhere((c) => c.id == clipIdC);
    expect(alignedA.startMs, 1200);
    expect(alignedA.lane, 1);
    expect(alignedA.durationMs, 400);
    expect(alignedB.startMs, 1200);
    expect(alignedB.lane, 2);
    expect(alignedB.durationMs, 500);
    expect(untouchedC.startMs, 900);
    expect(untouchedC.lane, 3);
    expect(untouchedC.durationMs, 300);
    expect(find.textContaining('1200ms · 400ms'), findsOneWidget);
    expect(find.textContaining('1200ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台批量对齐到播放头遇到同轨未选素材时后移避让', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_align_avoid_overlay_a.mp4';
    const relB = 'p/batch_align_avoid_overlay_b.mp4';
    const relC = 'p/batch_align_avoid_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 4]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 5]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 8, 6]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '对齐避让 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '对齐避让 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '同轨阻挡 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 1200,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1000',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-align-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final alignedA = clips.singleWhere((c) => c.id == clipIdA);
    final alignedB = clips.singleWhere((c) => c.id == clipIdB);
    final blockerC = clips.singleWhere((c) => c.id == clipIdC);
    expect(alignedA.startMs, 1500);
    expect(alignedA.lane, 1);
    expect(alignedA.durationMs, 400);
    expect(alignedB.startMs, 1000);
    expect(alignedB.lane, 2);
    expect(alignedB.durationMs, 500);
    expect(blockerC.startMs, 1200);
    expect(blockerC.lane, 1);
    expect(blockerC.durationMs, 300);
    expect(find.textContaining('1500ms · 400ms'), findsOneWidget);
    expect(find.textContaining('1000ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并将尾部对齐到播放头', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_align_end_playhead_overlay_a.mp4';
    const relB = 'p/batch_align_end_playhead_overlay_b.mp4';
    const relC = 'p/batch_align_end_playhead_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 11, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 11, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 11, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '尾部对齐播放头 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '尾部对齐播放头 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '尾部对齐播放头 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1200',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-align-end-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final alignedA = clips.singleWhere((c) => c.id == clipIdA);
    final alignedB = clips.singleWhere((c) => c.id == clipIdB);
    final untouchedC = clips.singleWhere((c) => c.id == clipIdC);
    expect(alignedA.startMs, 800);
    expect(alignedA.lane, 1);
    expect(alignedA.durationMs, 400);
    expect(alignedB.startMs, 700);
    expect(alignedB.lane, 2);
    expect(alignedB.durationMs, 500);
    expect(untouchedC.startMs, 900);
    expect(untouchedC.lane, 3);
    expect(untouchedC.durationMs, 300);
    expect(find.textContaining('800ms · 400ms'), findsOneWidget);
    expect(find.textContaining('700ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并将中心对齐到播放头', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_align_center_playhead_overlay_a.mp4';
    const relB = 'p/batch_align_center_playhead_overlay_b.mp4';
    const relC = 'p/batch_align_center_playhead_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 12, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 12, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 12, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '中心对齐播放头 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '中心对齐播放头 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '中心对齐播放头 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '1200',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey(
          'workbench-timeline-align-center-to-playhead-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final alignedA = clips.singleWhere((c) => c.id == clipIdA);
    final alignedB = clips.singleWhere((c) => c.id == clipIdB);
    final untouchedC = clips.singleWhere((c) => c.id == clipIdC);
    expect(alignedA.startMs, 1000);
    expect(alignedA.lane, 1);
    expect(alignedA.durationMs, 400);
    expect(alignedB.startMs, 950);
    expect(alignedB.lane, 2);
    expect(alignedB.durationMs, 500);
    expect(untouchedC.startMs, 900);
    expect(untouchedC.lane, 3);
    expect(untouchedC.durationMs, 300);
    expect(find.textContaining('1000ms · 400ms'), findsOneWidget);
    expect(find.textContaining('950ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量波纹复制', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_ripple_duplicate_overlay_a.mp4';
    const relB = 'p/batch_ripple_duplicate_overlay_b.mp4';
    const relC = 'p/batch_ripple_duplicate_overlay_c.mp4';
    const relD = 'p/batch_ripple_duplicate_overlay_d.mp4';
    const relE = 'p/batch_ripple_duplicate_overlay_e.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 5, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 5, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 5, 3]);
    File(engine.mediaAbsPath(relD))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 4]);
    File(engine.mediaAbsPath(relE))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 5, 5]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹复制 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹复制 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 C',
      relPath: relC,
    );
    final clipAssetD = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 D',
      relPath: relD,
    );
    final clipAssetE = engine.registerClipAsset(
      projectId: projectId,
      name: '其他轨 E',
      relPath: relE,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdD = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetD,
      lane: 2,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdE = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetE,
      lane: 3,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
          const ValueKey('workbench-timeline-ripple-duplicate-selected')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(7));
    expect(
      clips.where((c) => c.assetId == clipAssetA && c.startMs == 800),
      hasLength(1),
    );
    expect(
      clips.where((c) => c.assetId == clipAssetB && c.startMs == 1000),
      hasLength(1),
    );
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1600);
    expect(clips.singleWhere((c) => c.id == clipIdD).startMs, 1600);
    expect(clips.singleWhere((c) => c.id == clipIdE).startMs, 900);
    expect(find.textContaining('800ms · 400ms'), findsOneWidget);
    expect(find.textContaining('1000ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量波纹移动', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_ripple_move_overlay_a.mp4';
    const relB = 'p/batch_ripple_move_overlay_b.mp4';
    const relC = 'p/batch_ripple_move_overlay_c.mp4';
    const relD = 'p/batch_ripple_move_overlay_d.mp4';
    const relE = 'p/batch_ripple_move_overlay_e.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 6, 3]);
    File(engine.mediaAbsPath(relD))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 6, 4]);
    File(engine.mediaAbsPath(relE))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 5]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹移动 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹移动 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 C',
      relPath: relC,
    );
    final clipAssetD = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 D',
      relPath: relD,
    );
    final clipAssetE = engine.registerClipAsset(
      projectId: projectId,
      name: '其他轨 E',
      relPath: relE,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdD = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetD,
      lane: 2,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdE = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetE,
      lane: 3,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-move-selected')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-ripple-move-start-input')),
      '500',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-move-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 500);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1300);
    expect(clips.singleWhere((c) => c.id == clipIdD).startMs, 1300);
    expect(clips.singleWhere((c) => c.id == clipIdE).startMs, 900);
    expect(find.textContaining('500ms · 400ms'), findsOneWidget);
    expect(find.textContaining('700ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量移动到指定起点', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_move_overlay_a.mp4';
    const relB = 'p/batch_move_overlay_b.mp4';
    const relC = 'p/batch_move_overlay_c.mp4';
    const relD = 'p/batch_move_overlay_d.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 9, 3]);
    File(engine.mediaAbsPath(relD))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 9, 4]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '批量移动 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '批量移动 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 C',
      relPath: relC,
    );
    final clipAssetD = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 D',
      relPath: relD,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 1400,
      durationMs: 300,
    );
    final clipIdD = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetD,
      lane: 2,
      startMs: 1400,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-move-selected')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-move-start-input')),
      '500',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-move-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 500);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1400);
    expect(clips.singleWhere((c) => c.id == clipIdD).startMs, 1400);
    expect(find.textContaining('500ms · 400ms'), findsOneWidget);
    expect(find.textContaining('700ms · 500ms'), findsOneWidget);
  });

  testWidgets('移动端工作台：批量移动起点使用全屏表单并保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '5',
    );
    const relA = 'p/mobile_batch_move_overlay_a.mp4';
    const relB = 'p/mobile_batch_move_overlay_b.mp4';
    const relC = 'p/mobile_batch_move_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 8, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '移动批量起点 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '移动批量起点 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '移动后续 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 1400,
      durationMs: 300,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-move-selected')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('移动素材层'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-move-start-input')),
      '500',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-move-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 500);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1400);
    expect(find.textContaining('500ms · 400ms'), findsOneWidget);
    expect(find.textContaining('700ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量移动到指定轨道', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_lane_overlay_a.mp4';
    const relB = 'p/batch_lane_overlay_b.mp4';
    const relC = 'p/batch_lane_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 0, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 0, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 0, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '批量轨道 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '批量轨道 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '保留轨道 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 5,
      startMs: 1200,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-lane-selected')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-lane-input')),
      '3',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-lane-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).lane, 3);
    expect(clips.singleWhere((c) => c.id == clipIdB).lane, 4);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 100);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 300);
    expect(clips.singleWhere((c) => c.id == clipIdC).lane, 5);
    expect(find.textContaining('L3 · 100ms'), findsOneWidget);
    expect(find.textContaining('L4 · 300ms'), findsOneWidget);
  });

  testWidgets('移动端工作台：批量改轨使用全屏表单并保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '5',
    );
    const relA = 'p/mobile_batch_lane_overlay_a.mp4';
    const relB = 'p/mobile_batch_lane_overlay_b.mp4';
    const relC = 'p/mobile_batch_lane_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 3, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 3, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 3, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '移动批量轨道 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '移动批量轨道 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '移动保留轨道 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 5,
      startMs: 1200,
      durationMs: 300,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-lane-selected')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('移动素材层轨道'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-lane-input')),
      '3',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-lane-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).lane, 3);
    expect(clips.singleWhere((c) => c.id == clipIdB).lane, 4);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 100);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 300);
    expect(clips.singleWhere((c) => c.id == clipIdC).lane, 5);
    expect(find.textContaining('L3 · 100ms'), findsOneWidget);
    expect(find.textContaining('L4 · 300ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量波纹裁剪尾部', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_ripple_trim_overlay_a.mp4';
    const relB = 'p/batch_ripple_trim_overlay_b.mp4';
    const relC = 'p/batch_ripple_trim_overlay_c.mp4';
    const relD = 'p/batch_ripple_trim_overlay_d.mp4';
    const relE = 'p/batch_ripple_trim_overlay_e.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 7, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 7, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 7, 3]);
    File(engine.mediaAbsPath(relD))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 7, 4]);
    File(engine.mediaAbsPath(relE))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 7, 5]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹裁剪 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹裁剪 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 C',
      relPath: relC,
    );
    final clipAssetD = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 D',
      relPath: relD,
    );
    final clipAssetE = engine.registerClipAsset(
      projectId: projectId,
      name: '其他轨 E',
      relPath: relE,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdD = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetD,
      lane: 2,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdE = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetE,
      lane: 3,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-trim-selected')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
          const ValueKey('workbench-timeline-ripple-trim-duration-input')),
      '700',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-trim-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).durationMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdB).durationMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1200);
    expect(clips.singleWhere((c) => c.id == clipIdD).startMs, 1100);
    expect(clips.singleWhere((c) => c.id == clipIdE).startMs, 900);
    expect(find.textContaining('100ms · 700ms'), findsOneWidget);
    expect(find.textContaining('300ms · 700ms'), findsOneWidget);
  });

  testWidgets('工作台可选中多个素材层并批量裁剪尾部且不波纹移动和重叠', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/batch_trim_overlay_a.mp4';
    const relB = 'p/batch_trim_overlay_b.mp4';
    const relC = 'p/batch_trim_overlay_c.mp4';
    const relD = 'p/batch_trim_overlay_d.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 8, 3]);
    File(engine.mediaAbsPath(relD))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 8, 4]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '批量裁剪 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '批量裁剪 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 C',
      relPath: relC,
    );
    final clipAssetD = engine.registerClipAsset(
      projectId: projectId,
      name: '后续 D',
      relPath: relD,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 900,
      durationMs: 300,
    );
    final clipIdD = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetD,
      lane: 2,
      startMs: 900,
      durationMs: 300,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-trim-selected')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-trim-duration-input')),
      '700',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-trim-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).durationMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdB).durationMs, 600);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 900);
    expect(clips.singleWhere((c) => c.id == clipIdD).startMs, 900);
    expect(find.textContaining('100ms · 700ms'), findsOneWidget);
    expect(find.textContaining('300ms · 600ms'), findsOneWidget);
  });

  testWidgets('移动端工作台：批量裁剪尾部使用全屏表单并保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '5',
    );
    const relA = 'p/mobile_batch_trim_overlay_a.mp4';
    const relB = 'p/mobile_batch_trim_overlay_b.mp4';
    const relC = 'p/mobile_batch_trim_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 4, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 4, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 4, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '移动批量裁剪 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '移动批量裁剪 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '移动裁剪后续 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 100,
      durationMs: 400,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 300,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 900,
      durationMs: 300,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-trim-selected')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('裁剪素材层尾部'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-trim-duration-input')),
      '700',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-trim-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).durationMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdB).durationMs, 700);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 900);
    expect(find.textContaining('100ms · 700ms'), findsOneWidget);
    expect(find.textContaining('300ms · 700ms'), findsOneWidget);
  });

  testWidgets('工作台选中多个素材层后拖动其中一个会整组平移', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/group_move_overlay_a.mp4';
    const relB = 'p/group_move_overlay_b.mp4';
    const relC = 'p/group_move_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 9, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '组移动 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '组移动 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '未选 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 200,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 900,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 3,
      startMs: 900,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdA')),
      const Offset(48, 0),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 600);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 1300);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 900);
  });

  testWidgets('工作台多选拖拽时整组左边缘接近锚点会整体吸附', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/group_snap_left_overlay_a.mp4';
    const relB = 'p/group_snap_left_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '组吸附 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '组吸附 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 120,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 900,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdB')),
      const Offset(-12, 0),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 0);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 780);
    expect(find.textContaining('L1 · 0ms · 500ms'), findsOneWidget);
    expect(find.textContaining('L2 · 780ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台多选拖拽时整组边界接近锚点会显示参考线', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/group_snap_guide_left_overlay_a.mp4';
    const relB = 'p/group_snap_guide_left_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 3]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 4]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '组参考线 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '组参考线 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 120,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 900,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipIdB'));
    final guideFinder =
        find.byKey(ValueKey('workbench-timeline-snap-guide-$clipIdB'));
    expect(clipFinder, findsOneWidget);
    expect(guideFinder, findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(clipFinder));
    await gesture.moveBy(const Offset(-12, 0));
    await tester.pump();

    expect(guideFinder, findsOneWidget);

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('工作台多选拖拽遇到同轨未选素材时整组后移避让', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/group_move_avoid_overlay_a.mp4';
    const relB = 'p/group_move_avoid_overlay_b.mp4';
    const relC = 'p/group_move_avoid_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 9, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '组避让 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '组避让 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '阻挡 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 200,
      durationMs: 500,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 900,
      durationMs: 500,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 1,
      startMs: 800,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-timeline-clip-select-$clipIdB')),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(ValueKey('workbench-timeline-clip-$clipIdA')),
      const Offset(48, 0),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 1200);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 1900);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 800);
    expect(find.textContaining('1200ms · 500ms'), findsOneWidget);
    expect(find.textContaining('1900ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可从时间线删除素材层且保留源素材', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/delete_overlay_a.mp4';
    const relB = 'p/delete_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 1, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 2, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '删除素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '保留素材 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1200,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdA,
      actionKey: 'workbench-timeline-clip-delete-$clipIdA',
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(1));
    expect(clips.single.id, clipIdB);
    expect(
        find.byKey(ValueKey('workbench-timeline-clip-$clipIdA')), findsNothing);
    expect(find.byKey(ValueKey('workbench-timeline-clip-$clipIdB')),
        findsOneWidget);
    expect(File(engine.mediaAbsPath(relA)).existsSync(), isTrue);
  });

  testWidgets('工作台可波纹删除素材层并前移同轨后续片段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/ripple_delete_a.mp4';
    const relB = 'p/ripple_delete_b.mp4';
    const relC = 'p/ripple_delete_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 3, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 4, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 5, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹删除 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹删除 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹删除 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1400,
      durationMs: 700,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 2,
      startMs: 1400,
      durationMs: 700,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdA,
      actionKey: 'workbench-timeline-clip-ripple-delete-$clipIdA',
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips.map((c) => c.id), isNot(contains(clipIdA)));
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.startMs, 400);
    expect(shifted.durationMs, 700);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.startMs, 1400);
    expect(otherLane.durationMs, 700);
    expect(find.textContaining('L1 · 400ms · 700ms'), findsOneWidget);
  });

  testWidgets('工作台可波纹裁剪素材层尾部并移动同轨后续片段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const relA = 'p/ripple_trim_a.mp4';
    const relB = 'p/ripple_trim_b.mp4';
    const relC = 'p/ripple_trim_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 6, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 6, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 6, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹裁剪 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹裁剪 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹裁剪 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1400,
      durationMs: 700,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 2,
      startMs: 1400,
      durationMs: 700,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdA,
      actionKey: 'workbench-timeline-clip-ripple-trim-end-$clipIdA',
    );

    await tester.enterText(
      find.byKey(
          const ValueKey('workbench-timeline-ripple-trim-duration-input')),
      '600',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-trim-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final trimmed = clips.singleWhere((c) => c.id == clipIdA);
    expect(trimmed.durationMs, 600);
    final shifted = clips.singleWhere((c) => c.id == clipIdB);
    expect(shifted.startMs, 1000);
    expect(shifted.durationMs, 700);
    final otherLane = clips.singleWhere((c) => c.id == clipIdC);
    expect(otherLane.startMs, 1400);
    expect(otherLane.durationMs, 700);
    expect(find.textContaining('L1 · 0ms · 600ms'), findsOneWidget);
    expect(find.textContaining('L1 · 1000ms · 700ms'), findsOneWidget);
  });

  testWidgets('工作台拖拽素材层接近相邻边缘时自动吸附', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/snap_overlay_a.mp4';
    const relB = 'p/snap_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 3, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '吸附素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '吸附素材 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1500,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipIdB'));
    expect(clipFinder, findsOneWidget);
    await tester.drag(clipFinder, const Offset(-48, 0));
    await tester.pumpAndSettle();

    final moved = engine.timelineClips(scriptId).last;
    expect(moved.id, clipIdB);
    expect(moved.startMs, 1000);
    expect(moved.durationMs, 800);
    expect(find.textContaining('1000ms · 800ms'), findsOneWidget);
  });

  testWidgets('工作台拖拽素材层接近吸附点时显示参考线', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/snap_guide_a.mp4';
    const relB = 'p/snap_guide_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '参考线素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '参考线素材 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1500,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipIdB'));
    final guideFinder =
        find.byKey(ValueKey('workbench-timeline-snap-guide-$clipIdB'));
    expect(clipFinder, findsOneWidget);
    expect(guideFinder, findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(clipFinder));
    await gesture.moveBy(const Offset(-48, 0));
    await tester.pump();

    expect(guideFinder, findsOneWidget);

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('工作台拖拽素材层接近播放头时自动吸附', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '5',
    );
    const rel = 'p/playhead_snap_overlay.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 2, 0]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '播放头吸附素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 1,
      startMs: 1500,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-playhead-input')),
      '2200',
    );
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipId'));
    expect(clipFinder, findsOneWidget);
    await tester.drag(clipFinder, const Offset(72, 0));
    await tester.pumpAndSettle();

    final moved = engine.timelineClips(scriptId).single;
    expect(moved.startMs, 2200);
    expect(moved.durationMs, 500);
    expect(find.textContaining('2200ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台拖拽素材层时避免同轨重叠冲突', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/overlap_guard_a.mp4';
    const relB = 'p/overlap_guard_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 7, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '冲突保护 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '冲突保护 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1600,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipIdB'));
    expect(clipFinder, findsOneWidget);
    await tester.drag(clipFinder, const Offset(-96, 0));
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(2));
    final moved = clips.singleWhere((c) => c.id == clipIdB);
    expect(moved.lane, 1);
    expect(moved.startMs, 1000);
    expect(moved.durationMs, 800);
    expect(find.textContaining('1000ms · 800ms'), findsOneWidget);
  });

  testWidgets('工作台拖拽素材层到被占用层时自动下探空层', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/drag_auto_lane_a.mp4';
    const relB = 'p/drag_auto_lane_b.mp4';
    const relC = 'p/drag_auto_lane_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 4, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 4, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 4, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '占用层 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '占用层 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '待移动层 C',
      relPath: relC,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 4,
      startMs: 200,
      durationMs: 500,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipIdC'));
    expect(clipFinder, findsOneWidget);
    await tester.drag(clipFinder, const Offset(0, -108));
    await tester.pumpAndSettle();

    final moved = engine.timelineClips(scriptId).singleWhere(
          (clip) => clip.id == clipIdC,
        );
    expect(moved.lane, 3);
    expect(moved.startMs, 200);
    expect(moved.durationMs, 500);
    expect(find.textContaining('L3 · 200ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可编辑素材层属性并避让同轨重叠', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/property_edit_a.mp4';
    const relB = 'p/property_edit_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '属性素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '属性素材 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 2,
      startMs: 1800,
      durationMs: 700,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdB,
      actionKey: 'workbench-timeline-clip-edit-$clipIdB',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-edit-lane-input')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-edit-start-input')),
      '400',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-edit-duration-input')),
      '500',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-edit-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final edited = clips.singleWhere((c) => c.id == clipIdB);
    expect(edited.lane, 1);
    expect(edited.startMs, 1000);
    expect(edited.durationMs, 500);
    expect(find.textContaining('L1 · 1000ms · 500ms'), findsOneWidget);
  });

  testWidgets('工作台可编辑素材层透明度并显示百分比', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const rel = 'p/property_opacity_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 10, 1]);
    final clipAsset = engine.registerClipAsset(
      projectId: projectId,
      name: '透明度素材',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAsset,
      lane: 2,
      startMs: 700,
      durationMs: 900,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipId,
      actionKey: 'workbench-timeline-clip-edit-$clipId',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-edit-opacity-input')),
      '60',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-edit-confirm')),
    );
    await tester.pumpAndSettle();

    final opacity = engine.db.select(
      'SELECT opacity FROM o_timelineClip WHERE id=?',
      [clipId],
    ).single['opacity'] as double?;
    expect(opacity, 0.6);
    expect(find.textContaining('60%'), findsOneWidget);
  });

  testWidgets('工作台可复制素材层到同轨后方并避让冲突', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/duplicate_overlay_a.mp4';
    const relB = 'p/duplicate_overlay_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 9, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 9, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '复制素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '阻挡素材 B',
      relPath: relB,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 500,
      durationMs: 600,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1200,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdA,
      actionKey: 'workbench-timeline-clip-duplicate-$clipIdA',
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(3));
    final duplicate = clips.singleWhere(
      (c) => c.id != clipIdA && c.assetId == clipAssetA,
    );
    expect(duplicate.lane, 1);
    expect(duplicate.startMs, 1600);
    expect(duplicate.durationMs, 600);
    expect(find.textContaining('L1 · 1600ms · 600ms'), findsOneWidget);
  });

  testWidgets('工作台可波纹复制素材层并后移同轨后续片段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/ripple_duplicate_overlay_a.mp4';
    const relB = 'p/ripple_duplicate_overlay_b.mp4';
    const relC = 'p/ripple_duplicate_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 8, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 8, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 8, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹复制素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹复制后续 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹复制其他轨 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 500,
      durationMs: 600,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1200,
      durationMs: 400,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 2,
      startMs: 1200,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdA,
      actionKey: 'workbench-timeline-clip-ripple-duplicate-$clipIdA',
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(4));
    expect(clips.singleWhere((c) => c.id == clipIdA).startMs, 500);
    final duplicate = clips.singleWhere(
      (c) => c.id != clipIdA && c.assetId == clipAssetA,
    );
    expect(duplicate.lane, 1);
    expect(duplicate.startMs, 1100);
    expect(duplicate.durationMs, 600);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 1800);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1200);
    expect(find.textContaining('L1 · 1100ms · 600ms'), findsOneWidget);
    expect(find.textContaining('L1 · 1800ms · 400ms'), findsOneWidget);
  });

  testWidgets('工作台可波纹移动素材层并移动同轨后续片段', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/ripple_move_overlay_a.mp4';
    const relB = 'p/ripple_move_overlay_b.mp4';
    const relC = 'p/ripple_move_overlay_c.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 7, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 7, 2]);
    File(engine.mediaAbsPath(relC))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3, 7, 3]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹移动素材 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹移动后续 B',
      relPath: relB,
    );
    final clipAssetC = engine.registerClipAsset(
      projectId: projectId,
      name: '波纹移动其他轨 C',
      relPath: relC,
    );
    final clipIdA = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 500,
      durationMs: 600,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1400,
      durationMs: 400,
    );
    final clipIdC = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetC,
      lane: 2,
      startMs: 1400,
      durationMs: 400,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipIdA,
      actionKey: 'workbench-timeline-clip-ripple-move-$clipIdA',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-ripple-move-start-input')),
      '900',
    );
    await tester.tap(
      find.byKey(const ValueKey('workbench-timeline-ripple-move-confirm')),
    );
    await tester.pumpAndSettle();

    final clips = engine.timelineClips(scriptId);
    final moved = clips.singleWhere((c) => c.id == clipIdA);
    expect(moved.startMs, 900);
    expect(moved.durationMs, 600);
    expect(clips.singleWhere((c) => c.id == clipIdB).startMs, 1800);
    expect(clips.singleWhere((c) => c.id == clipIdC).startMs, 1400);
    expect(find.textContaining('L1 · 900ms · 600ms'), findsOneWidget);
    expect(find.textContaining('L1 · 1800ms · 400ms'), findsOneWidget);
  });

  testWidgets('工作台仅上下拖拽素材层时不改变时间点', (tester) async {
    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
      duration: '4',
    );
    const relA = 'p/lane_snap_guard_a.mp4';
    const relB = 'p/lane_snap_guard_b.mp4';
    File(engine.mediaAbsPath(relA))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 4, 1]);
    File(engine.mediaAbsPath(relB))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2, 5, 2]);
    final clipAssetA = engine.registerClipAsset(
      projectId: projectId,
      name: '换轨保护 A',
      relPath: relA,
    );
    final clipAssetB = engine.registerClipAsset(
      projectId: projectId,
      name: '换轨保护 B',
      relPath: relB,
    );
    engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetA,
      lane: 1,
      startMs: 0,
      durationMs: 1000,
    );
    final clipIdB = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetB,
      lane: 1,
      startMs: 1050,
      durationMs: 800,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final clipFinder = find.byKey(ValueKey('workbench-timeline-clip-$clipIdB'));
    expect(clipFinder, findsOneWidget);
    await tester.drag(clipFinder, const Offset(0, 40));
    await tester.pumpAndSettle();

    final moved = engine.timelineClips(scriptId).last;
    expect(moved.id, clipIdB);
    expect(moved.lane, 2);
    expect(moved.startMs, 1050);
    expect(moved.durationMs, 800);
  });

  testWidgets('移动端工作台：素材层编辑使用全屏单列表单并可保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
      duration: '4',
    );
    const rel = 'p/mobile_overlay_edit.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([6, 6, 6]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '移动素材层',
      relPath: rel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 1,
      startMs: 0,
      durationMs: 900,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tapTimelineClipAction(
      tester,
      clipId: clipId,
      actionKey: 'workbench-timeline-clip-edit-$clipId',
    );

    expect(find.byType(AlertDialog), findsNothing);
    final laneTop = tester
        .getTopLeft(
            find.byKey(const ValueKey('workbench-timeline-edit-lane-input')))
        .dy;
    final startTop = tester
        .getTopLeft(
            find.byKey(const ValueKey('workbench-timeline-edit-start-input')))
        .dy;
    final durationTop = tester
        .getTopLeft(find
            .byKey(const ValueKey('workbench-timeline-edit-duration-input')))
        .dy;
    expect(startTop, greaterThan(laneTop));
    expect(durationTop, greaterThan(startTop));

    await tester.enterText(
      find.byKey(const ValueKey('workbench-timeline-edit-opacity-input')),
      '65',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final row = engine.db.select(
        'SELECT opacity FROM o_timelineClip WHERE id=?', [clipId]).single;
    expect(row['opacity'] as double, closeTo(0.65, 0.001));
    expect(find.textContaining('65%'), findsOneWidget);
  });

  testWidgets('工作台批量生成只作用于已勾选镜头轨道', (tester) async {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');
    final frame = File(engine.mediaAbsPath('p/s2.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    expect(frame.existsSync(), isTrue);
    engine.db.execute(
        "UPDATE o_storyboard SET filePath='p/s2.png' WHERE id=?", [s2]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('workbench-shot-check-$s1')));
    await tester.pumpAndSettle();
    await tapWorkbenchBatchAction(tester, '全部生成视频');

    final task = engine.db
        .select(
          "SELECT relatedObjects FROM o_tasks WHERE taskClass='video_generation'",
        )
        .single;
    final related =
        jsonDecode(task['relatedObjects'] as String) as Map<String, dynamic>;
    final trackIds =
        (related['trackIds'] as List).map((e) => (e as num).toInt()).toList();
    expect(trackIds, [
      engine.storyboards(scriptId).singleWhere((s) => s.id == s2).trackId,
    ]);
  });

  testWidgets('工作台批量运镜提示词立即入队并显示每轨生成状态', (tester) async {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');
    engine.db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)",
      ['video_prompt_gen', 'video_prompt_gen', '运镜系统词'],
    );
    gateway.textHandler = (call, system, user) => '批量运镜提示词 #$call';

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('workbench-shot-check-$s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workbench-batch-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部生成运镜提示词'));
    // 生成任务保持运行态时，状态芯片有意播放无限动画；这里只需推进一帧，
    // 断言后台任务已入队而非等待它结束。
    await tester.pump();

    final shot1 = engine.storyboards(scriptId).singleWhere((s) => s.id == s1);
    final shot2 = engine.storyboards(scriptId).singleWhere((s) => s.id == s2);
    expect(shot1.trackId, isNull);
    final track = engine.track(shot2.trackId!)!;
    expect(
      engine.db
          .select(
              "SELECT taskClass FROM o_tasks WHERE taskClass='video_prompt_generation'")
          .single['taskClass'],
      'video_prompt_generation',
    );
    expect(track.promptState, videoPromptGenerating);
    expect(
      find.byKey(ValueKey('workbench-prompt-status-${track.id}')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(ValueKey('workbench-shot-check-$s2')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('工作台响应后台提示词的完成和失败终态', (tester) async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '状态刷新镜头');
    final trackId = engine.ensureTrackForStoryboard(storyboardId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    engine.db.execute(
      'UPDATE o_videoTrack SET promptState=?,promptErrorReason=NULL WHERE id=?',
      [videoPromptDone, trackId],
    );
    engine.queue.notifyChanged();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatusChip>(
              find.byKey(ValueKey('workbench-prompt-status-$trackId')))
          .status,
      'success',
    );

    engine.db.execute(
      'UPDATE o_videoTrack SET promptState=?,promptErrorReason=? WHERE id=?',
      [
        videoPromptFailed,
        const EngineException(errNetwork).toReasonJson(),
        trackId,
      ],
    );
    engine.queue.notifyChanged();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatusChip>(
              find.byKey(ValueKey('workbench-prompt-status-$trackId')))
          .status,
      'failed',
    );
    expect(find.byTooltip('网络请求失败'), findsOneWidget);
  });

  testWidgets('移动端工作台按模型能力保存单镜视频参数', (tester) async {
    engine.db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'modelId': 'test-video',
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': [
                  'text',
                  'first_frame',
                  'first_last_frame',
                  'multi_reference',
                ],
                'references': {'image': 3, 'video': 1, 'audio': 1},
                'durations': [4, 5],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'optional',
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '镜头一',
    );
    final image = File(engine.mediaAbsPath('p/first.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    expect(image.existsSync(), isTrue);
    engine.db.execute(
      "UPDATE o_storyboard SET filePath='p/first.png' WHERE id=?",
      [storyboardId],
    );
    final trackId = engine.ensureTrackForStoryboard(storyboardId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('workbench-video-params-$storyboardId')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-request-mode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-request-mode')));
    await tester.pumpAndSettle();
    expect(find.text('first_last_frame'), findsOneWidget);
    expect(find.text('multi_reference'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video-request-provider-audio')),
      findsOneWidget,
    );

    await tester.tap(find.text('multi_reference').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('video-request-reference-storyboard-$storyboardId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video-request-save')));
    await tester.pumpAndSettle();

    final draft = engine.videoRequestForTrack(trackId);
    expect(draft.mode, VideoMode.multiReference);
    expect(draft.references, hasLength(1));
    expect(draft.references.single.role, 'reference_image');
    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: storyboardId,
      trackId: trackId,
    );
    expect(request.mode, VideoMode.multiReference);
    expect(request.references.single.role, 'reference_image');
  });

  testWidgets('视频参数弹窗可选择分镜关联角色的绑定音频参考', (tester) async {
    engine.db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'modelId': 'test-video',
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': ['multi_reference'],
                'references': {'image': 2, 'video': 0, 'audio': 1},
                'durations': [5],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'none',
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '带角色音色参考的镜头',
    );
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '林朝雪',
      describe: '',
    );
    engine.db.execute(
      'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
      [roleId, storyboardId],
    );
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: '林朝雪音色',
      sex: '女',
      describe: '',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '台词样本',
          name: '样本',
          describe: '',
          existingImageId: null,
        ),
      ],
    );
    engine.bindAssetAudio(roleId, audioId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(ValueKey('workbench-video-params-$storyboardId')));
    await tester.pumpAndSettle();

    final audioReference =
        find.byKey(ValueKey('video-request-reference-audio-$audioId'));
    expect(audioReference, findsOneWidget);
    await tester.tap(audioReference);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video-request-save')));
    await tester.pumpAndSettle();

    final trackId = engine
        .storyboards(scriptId)
        .singleWhere((storyboard) => storyboard.id == storyboardId)
        .trackId!;
    final draft = engine.videoRequestForTrack(trackId);
    expect(draft.references, hasLength(1));
    expect(draft.references.single.sourceType, 'audio');
    expect(draft.references.single.sourceId, audioId);
    expect(draft.references.single.role, 'reference_audio');
    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: storyboardId,
      trackId: trackId,
    );
    expect(request.references.single.mediaType, 'audio');
    expect(request.references.single.role, 'reference_audio');
  });

  testWidgets('桌面工作台为纯文生模型隐藏参考素材和供应商音频', (tester) async {
    engine.db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'modelId': 'test-video',
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': ['text'],
                'references': {'image': 0, 'video': 0, 'audio': 0},
                'durations': [5],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'none',
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '文本镜头',
    );

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-video-params-$storyboardId')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-request-mode')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('video-request-provider-audio')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('video-request-reference-storyboard-$storyboardId')),
      findsNothing,
    );
  });

  testWidgets('取消视频参数不创建视频轨', (tester) async {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '不应落库的参数预览',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-video-params-$storyboardId')),
    );
    await tester.pumpAndSettle();

    expect(
      engine.db.select('SELECT trackId FROM o_storyboard WHERE id=?',
          [storyboardId]).single['trackId'],
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      engine.db.select('SELECT trackId FROM o_storyboard WHERE id=?',
          [storyboardId]).single['trackId'],
      isNull,
    );
    expect(
      engine.db
          .select('SELECT COUNT(*) count FROM o_videoTrack')
          .single['count'],
      0,
    );
  });

  testWidgets('工作台锁定供应商要求生成的音频', (tester) async {
    engine.db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'modelId': 'test-video',
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': ['first_frame'],
                'references': {'image': 1, 'video': 0, 'audio': 0},
                'durations': [5],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'required',
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '首帧镜头',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-video-params-$storyboardId')),
    );
    await tester.pumpAndSettle();

    final providerAudio = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('video-request-provider-audio')),
    );
    expect(providerAudio.value, isTrue);
    expect(providerAudio.onChanged, isNull);
  });

  testWidgets('工作台首尾帧模式要求尾帧并保存为正确引用角色', (tester) async {
    engine.db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'modelId': 'test-video',
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': ['first_last_frame'],
                'references': {'image': 2, 'video': 0, 'audio': 0},
                'durations': [5],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'none',
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '首尾帧镜头',
    );
    final firstFrame = File(engine.mediaAbsPath('p/first-last-start.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    expect(firstFrame.existsSync(), isTrue);
    engine.db.execute(
      "UPDATE o_storyboard SET filePath='p/first-last-start.png' WHERE id=?",
      [storyboardId],
    );
    final lastFrameAsset = engine.uploadClip(
      projectId: projectId,
      name: '尾帧',
      bytes: [3, 2, 1],
      type: 'role',
      ext: 'png',
    );
    engine.db.execute(
      'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
      [lastFrameAsset, storyboardId],
    );
    final trackId = engine.ensureTrackForStoryboard(storyboardId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workbench-video-params-$storyboardId')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-request-save')), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('video-request-reference-asset-$lastFrameAsset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video-request-save')));
    await tester.pumpAndSettle();

    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: storyboardId,
      trackId: trackId,
    );
    expect(request.mode, VideoMode.firstLastFrame);
    expect(request.references.map((reference) => reference.role),
        ['first_frame', 'last_frame']);
  });

  testWidgets('点击生成运镜提示词按钮不崩溃且写入轨道', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 无提示词种子时 getPrompt 抛错，验证走 toast 而非崩溃
    await tester.tap(find.text('生成运镜提示词'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(engine.storyboards(scriptId).single.id, sbId);
  });

  testWidgets('全部已选视频时可成功合成并弹出结果', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [trackId, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(trackId, engine.db.lastInsertRowId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workbench-compose-compact')));
    await tester.pumpAndSettle();

    expect(find.text('合成成功'), findsOneWidget);
    expect(find.textContaining('已保存到素材库'), findsOneWidget);
  });

  testWidgets('移动端工作台：合成成功结果使用全屏表单并展示导出信息', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '移动合成');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.db.execute(
      'INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)',
      [trackId, 'p/mobile_compose.mp4', vtDone],
    );
    engine.selectVideo(trackId, engine.db.lastInsertRowId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workbench-compose-compact')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('合成成功'), findsOneWidget);
    expect(find.textContaining('输出路径'), findsOneWidget);
    expect(find.textContaining('已保存到素材库'), findsOneWidget);
  });

  testWidgets('可从素材库选择 clip 作为本镜候选并自动选为正片', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    const rel = 'p/library_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    engine.registerClipAsset(
      projectId: projectId,
      name: '素材镜头A',
      relPath: rel,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('素材库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('素材镜头A'));
    await tester.pumpAndSettle();

    final trackId = engine.storyboards(scriptId).single.trackId!;
    final track = engine.track(trackId)!;
    expect(engine.storyboards(scriptId).single.id, sbId);
    expect(track.candidates.single.filePath, rel);
    expect(track.selectVideoId, track.candidates.single.id);
    expect(find.text('已选'), findsOneWidget);
  });

  testWidgets('移动端工作台：素材库选择候选使用全屏列表并自动选为正片', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '移动镜头');
    const rel = 'p/mobile_library_clip.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 3, 2, 1]);
    engine.registerClipAsset(
      projectId: projectId,
      name: '移动素材镜头A',
      relPath: rel,
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('素材库'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('选择素材视频'), findsOneWidget);

    await tester.tap(find.text('移动素材镜头A'));
    await tester.pumpAndSettle();

    final trackId = engine.storyboards(scriptId).single.trackId!;
    final track = engine.track(trackId)!;
    expect(engine.storyboards(scriptId).single.id, sbId);
    expect(track.candidates.single.filePath, rel);
    expect(track.selectVideoId, track.candidates.single.id);
    expect(find.byTooltip('已选'), findsOneWidget);
  });

  testWidgets('移动端工作台：候选视频播放使用全屏预览', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '移动候选播放');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.db.execute(
      'INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)',
      [trackId, 'p/mobile_preview_missing.mp4', vtDone],
    );
    final videoId = engine.db.lastInsertRowId;
    engine.selectVideo(trackId, videoId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('workbench-video-player-screen')),
        findsOneWidget);
    expect(find.text('视频加载失败'), findsOneWidget);
  });

  testWidgets('候选视频可保存到素材库 clip 供后续复用', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    const rel = 'p/candidate_for_library.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 8, 7]);
    engine.db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, rel, vtDone],
    );
    final videoId = engine.db.lastInsertRowId;
    engine.selectVideo(trackId, videoId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('保存到素材库'));
    await tester.pumpAndSettle();

    final clips = engine.getAssets(projectId, type: 'clip').data;
    expect(engine.storyboards(scriptId).single.id, sbId);
    expect(clips, hasLength(1));
    expect(clips.single.filePath, rel);
    expect(find.textContaining('已保存到素材库'), findsWidgets);
  });

  testWidgets('候选视频可另存为本地 MP4，勾选镜头后导出所选正片 ZIP', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '导出候选');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    const firstRel = 'p/export_candidate_1.mp4';
    const secondRel = 'p/export_candidate_2.mp4';
    for (final (rel, bytes) in [
      (firstRel, <int>[1, 2, 3]),
      (secondRel, <int>[4, 5, 6]),
    ]) {
      File(engine.mediaAbsPath(rel))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      engine.db.execute(
        'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
        'VALUES (?,?,?,?,?)',
        [projectId, scriptId, trackId, rel, vtDone],
      );
    }
    final candidates = engine.track(trackId)!.candidates;
    final firstId = candidates.first.id;
    engine.selectVideo(trackId, firstId);
    final output = p.join(dir.path, 'candidate-export.mp4');
    final selector = _PreviewSaveSelector(output);
    final originalSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = selector;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(ValueKey('workbench-candidate-download-$firstId')));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(File(output).readAsBytesSync(), [1, 2, 3]);
    expect(selector.acceptedTypeGroups?.single.extensions, ['mp4']);

    final archive = p.join(dir.path, 'candidate-export.zip');
    selector.path = archive;
    await tester.tap(find.byKey(const ValueKey('workbench-batch-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载已选视频'));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(File(archive).existsSync(), isTrue);
    expect(selector.acceptedTypeGroups?.single.extensions, ['zip']);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(ValueKey('workbench-shot-check-$sbId')),
          )
          .value,
      isFalse,
      reason: '对齐 ToonFlow：批量下载完成后清空镜头勾选',
    );
  });

  testWidgets('候选删除按钮：可见删除图标 + 二次确认后调用 deleteVideo', (tester) async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [trackId, 'p/vid_1.mp4', vtDone]);
    final videoId = engine.db.lastInsertRowId;
    engine.selectVideo(trackId, videoId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 可见删除图标（此前只有隐藏 onLongPress）
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    // 弹出确认，取消不删
    expect(find.text('确定删除该候选视频？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(engine.track(trackId)!.candidates, hasLength(1));

    // 再次删除并确认
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(engine.track(trackId)!.candidates, isEmpty);
  });

  testWidgets('移动端工作台：候选删除确认使用全屏表单并删除候选', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '移动候选');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.db.execute(
      'INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)',
      [trackId, 'p/mobile_candidate_delete.mp4', vtDone],
    );
    final videoId = engine.db.lastInsertRowId;
    engine.selectVideo(trackId, videoId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('删除候选'), findsWidgets);
    expect(find.text('确定删除该候选视频？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(engine.track(trackId)!.candidates, isEmpty);
  });

  testWidgets('工作台可清空已勾选视频轨道但保留分镜', (tester) async {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');
    final t1 = engine.ensureTrackForStoryboard(s1);
    final t2 = engine.ensureTrackForStoryboard(s2);
    const rel1 = 'p/clear_track_1.mp4';
    File(engine.mediaAbsPath(rel1))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 1, 1]);
    engine.db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, t1, rel1, vtDone],
    );
    final v1 = engine.db.lastInsertRowId;
    engine.selectVideo(t1, v1);
    engine.db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, t2, 'p/clear_track_2.mp4', vtDone],
    );
    engine.selectVideo(t2, engine.db.lastInsertRowId);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('workbench-shot-check-$s2')));
    await tester.pumpAndSettle();
    await tapWorkbenchBatchAction(tester, '清空已选轨道');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    final shots = engine.storyboards(scriptId);
    expect(shots, hasLength(2));
    expect(shots.singleWhere((s) => s.id == s1).trackId, isNull);
    expect(shots.singleWhere((s) => s.id == s2).trackId, t2);
    expect(engine.track(t1), isNull);
    expect(engine.track(t2), isNotNull);
    expect(File(engine.mediaAbsPath(rel1)).existsSync(), isFalse);
  });

  testWidgets('移动端工作台：清空已选轨道确认使用全屏表单并保留分镜', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '移动镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '移动镜头二');
    final t1 = engine.ensureTrackForStoryboard(s1);
    final t2 = engine.ensureTrackForStoryboard(s2);
    const rel1 = 'p/mobile_clear_track_1.mp4';
    File(engine.mediaAbsPath(rel1))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    engine.db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, t1, rel1, vtDone],
    );
    engine.selectVideo(t1, engine.db.lastInsertRowId);
    engine.db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, t2, 'p/mobile_clear_track_2.mp4', vtDone],
    );
    engine.selectVideo(t2, engine.db.lastInsertRowId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('workbench-shot-check-$s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空已选轨道'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('清空已选轨道'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    final shots = engine.storyboards(scriptId);
    expect(shots, hasLength(2));
    expect(shots.singleWhere((s) => s.id == s1).trackId, isNull);
    expect(shots.singleWhere((s) => s.id == s2).trackId, t2);
    expect(engine.track(t1), isNull);
    expect(engine.track(t2), isNotNull);
    expect(File(engine.mediaAbsPath(rel1)).existsSync(), isFalse);
  });

  testWidgets('本镜时长可编辑：点药丸输入秒数写入视频轨', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 初始未设置
    expect(find.text('未设置'), findsOneWidget);
    await tester.tap(find.text('未设置'));
    await tester.pumpAndSettle();
    expect(find.text('编辑本镜时长'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('workbench-text-edit-input')),
      '7',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final trackId = engine.storyboards(scriptId).single.trackId!;
    expect(engine.track(trackId)!.duration, 7);
    expect(find.text('7 秒'), findsOneWidget);
  });

  testWidgets('移动端工作台：本镜时长编辑使用全屏表单并保存', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: _FakeComposer(),
    );
    engine.installVideoTrackPipeline();

    engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '移动镜头',
    );

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('未设置'), findsOneWidget);
    await tester.tap(find.text('未设置'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('编辑本镜时长'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workbench-text-edit-input')),
      '7',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final trackId = engine.storyboards(scriptId).single.trackId!;
    expect(engine.track(trackId)!.duration, 7);
    expect(find.text('7 秒'), findsOneWidget);
  });

  testWidgets('每镜转场和滤镜可编辑并写入视频轨', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('无转场'), findsOneWidget);
    expect(find.text('无滤镜'), findsOneWidget);

    await tester.tap(find.text('无转场'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('淡入淡出').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('无滤镜'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('电影感').last);
    await tester.pumpAndSettle();

    final trackId = engine.storyboards(scriptId).single.trackId!;
    final track = engine.track(trackId)!;
    expect(track.transition, 'fade');
    expect(track.filter, 'cinematic');
    expect(find.text('淡入淡出'), findsOneWidget);
    expect(find.text('电影感'), findsOneWidget);
  });

  testWidgets('运镜提示词可手动编辑：点击文字弹出编辑框并写入轨道', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // videoDesc 为空时显示占位，可点
    await tester.tap(find.text('暂无运镜提示词，点击生成或编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑运镜提示词'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('workbench-text-edit-input')),
      '缓慢推近特写',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final trackId = engine.storyboards(scriptId).single.trackId!;
    expect(engine.track(trackId)!.prompt, '缓慢推近特写');
    expect(find.text('缓慢推近特写'), findsOneWidget);
  });

  testWidgets('分镜行可选择镜头配音并写入 storyboard audioAssetId', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: '少年声',
      sex: '男',
      describe: '清亮',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '师兄，该出发了。',
          name: '少年声-样例',
          describe: '平静',
          existingImageId: null,
        ),
      ],
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('镜头配音'), findsOneWidget);
    await tester.tap(find.text('无配音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('少年声').last);
    await tester.pumpAndSettle();

    expect(engine.storyboards(scriptId).single.audioAssetId, audioId);
    expect(find.text('少年声'), findsOneWidget);
  });

  testWidgets('工作台镜头可拖拽重排并持久化到分镜顺序', (tester) async {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(engine.storyboards(scriptId).map((r) => r.id), [s1, s2]);
    expect(find.byTooltip('拖拽调整顺序'), findsNWidgets(2));

    await tester.drag(
      find.byKey(ValueKey('workbench-reorder-handle-$s2')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    expect(engine.storyboards(scriptId).map((r) => r.id), [s2, s1]);
    expect(engine.storyboards(scriptId).map((r) => r.index), [1, 2]);
  });

  testWidgets('移动端工作台：390px 下可重排镜头且合成顺序跟随', (tester) async {
    final db = engine.db;
    final media = engine.media;
    engine.dispose();
    final composer = _RecordingComposer();
    engine = Engine(
      db: db,
      media: media,
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: true),
      composer: composer,
    );
    engine.installVideoTrackPipeline();

    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');
    final t1 = engine.ensureTrackForStoryboard(s1);
    final t2 = engine.ensureTrackForStoryboard(s2);
    engine.db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [t1, 'p/mobile_1.mp4', vtDone]);
    engine.selectVideo(t1, engine.db.lastInsertRowId);
    engine.db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [t2, 'p/mobile_2.mp4', vtDone]);
    engine.selectVideo(t2, engine.db.lastInsertRowId);

    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(ValueKey('workbench-reorder-handle-$s2')),
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();

    expect(engine.storyboards(scriptId).map((r) => r.id), [s2, s1]);

    await tester.tap(find.byKey(const ValueKey('workbench-compose-compact')));
    await tester.pumpAndSettle();

    expect(composer.concatCalls.single.map((p) => p.split('/').last), [
      'mobile_2.mp4',
      'mobile_1.mp4',
    ]);
  });
}
