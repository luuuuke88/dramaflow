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
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:dramaflow/src/screens/production/workbench_screen.dart';
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
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-workbench-');
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
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
    await tester.enterText(find.byType(TextField), '7');
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
    await tester.enterText(find.byType(TextField), '缓慢推近特写');
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
