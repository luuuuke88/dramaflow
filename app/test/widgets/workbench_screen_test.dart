import 'dart:io';
import 'dart:convert';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_audio.dart';
import 'package:dramaflow/src/engine/timeline_clip.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:dramaflow/src/screens/production/workbench_screen.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:dio/dio.dart';
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
    engine.installVideoTrackPipeline();
    projectId = engine.addProject(projectType: 'novel', name: '工作台测试');
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app() {
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
        locale: const Locale('zh'),
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    );
  }

  Future<void> tapTimelineClipAction(
    WidgetTester tester, {
    required int clipId,
    required String actionKey,
  }) async {
    await tester
        .tap(find.byKey(ValueKey('workbench-timeline-clip-menu-$clipId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(actionKey)));
    await tester.pumpAndSettle();
  }

  testWidgets('无分镜时显示空态', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('暂无分镜，请先在「制作」的分镜节点生成'), findsOneWidget);
  });

  testWidgets('有分镜时渲染镜头行+合成按钮显示缺口提示', (tester) async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId, prompt: 'x');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('S1'), findsOneWidget);
    expect(find.textContaining('合成本集'), findsOneWidget);
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

  testWidgets('工作台批量生成只作用于已勾选镜头轨道', (tester) async {
    final s1 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final s2 = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('workbench-shot-check-$s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部生成视频'));
    await tester.pumpAndSettle();

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

  testWidgets('工作台批量运镜提示词只写入已勾选镜头轨道', (tester) async {
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
    await tester.tap(find.text('全部生成运镜提示词'));
    await tester.pumpAndSettle();

    final shot1 = engine.storyboards(scriptId).singleWhere((s) => s.id == s1);
    final shot2 = engine.storyboards(scriptId).singleWhere((s) => s.id == s2);
    expect(shot1.trackId, isNull);
    expect(engine.track(shot2.trackId!)!.prompt, '批量运镜提示词 #1');
    expect(gateway.textCalls, 1);
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

    await tester.tap(find.textContaining('合成本集'));
    await tester.pumpAndSettle();

    expect(find.text('合成成功'), findsOneWidget);
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
    await tester.tap(find.text('清空已选轨道'));
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

    await tester.tap(find.textContaining('合成本集'));
    await tester.pumpAndSettle();

    expect(composer.concatCalls.single.map((p) => p.split('/').last), [
      'mobile_2.mp4',
      'mobile_1.mp4',
    ]);
  });
}
