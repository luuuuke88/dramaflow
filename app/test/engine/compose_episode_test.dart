import 'dart:io';
import 'dart:convert';

import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
import 'package:dramaflow/src/engine/compose.dart';
import 'package:dramaflow/src/engine/compose_episode.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/storyboard_audio.dart';
import 'package:dramaflow/src/engine/timeline_clip.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 回归测试：Engine 构造函数曾接受 composer 参数但从未存成字段（T3 重写遗留 bug，
/// 2026-07-03 修复）。此处锁定 engine.composer 确实是传入的实例。
class _FakeComposer implements VideoComposer {
  final List<List<String>> concatCalls = [];
  final List<List<ComposeSegment>> composeCalls = [];
  double? probedDuration = 4.0;

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
  Future<double?> probeDurationSec(String inputAbsPath) async => probedDuration;
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _FakeComposer composer;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-compose-');
    db = openEngineDb(':memory:');
    composer = _FakeComposer();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      composer: composer,
    );
    projectId = engine.addProject(projectType: 'novel', name: '合成测试');
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('回归：Engine.composer 字段确实持有构造时传入的合成器（曾被静默丢弃）', () {
    expect(identical(engine.composer, composer), isTrue);
  });

  test('未传 composer 时默认回落 UnsupportedComposer（不为 null）', () {
    final other = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media2')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
    expect(other.composer, isA<UnsupportedComposer>());
  });

  test('orderedSelectedVideoPaths 按分镜序号返回选中视频（未选中为 null）', () {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final sb2 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    final videoId = db.lastInsertRowId;
    engine.selectVideo(track1, videoId);
    engine.ensureTrackForStoryboard(sb2); // 未生成任何候选

    final paths = engine.orderedSelectedVideoPaths(scriptId);
    expect(paths, ['p/vid_1.mp4', null]);
  });

  test('orderedSelectedVideoPaths 和 composeEpisode 跟随分镜重排后的 index 顺序',
      () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final sb2 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    final track2 = engine.ensureTrackForStoryboard(sb2);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track2, 'p/vid_2.mp4', vtDone]);
    engine.selectVideo(track2, db.lastInsertRowId);

    engine.reorderStoryboards(scriptId, [sb2, sb1]);

    expect(engine.orderedSelectedVideoPaths(scriptId), [
      'p/vid_2.mp4',
      'p/vid_1.mp4',
    ]);

    await engine.composeEpisode(projectId, scriptId);
    expect(composer.concatCalls.single.map((p) => p.split('/').last), [
      'vid_2.mp4',
      'vid_1.mp4',
    ]);
  });

  test('composeEpisode：全部已选时拼接成功并返回时长', () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);

    final result = await engine.composeEpisode(projectId, scriptId);
    expect(result.segmentCount, 1);
    expect(result.durationSec, 4.0);
    expect(composer.concatCalls.single.single, contains('vid_1.mp4'));
    expect(composer.composeCalls, isEmpty);
    expect(
        File(engine.mediaAbsPath(result.outputRelPath)).existsSync(), isTrue);
  });

  test('composeEpisode：导出成片后登记为 clip 素材，便于重启后管理', () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);

    final result = await engine.composeEpisode(projectId, scriptId);

    expect(result.clipAssetId, isNotNull);
    final clips = engine.getAssets(projectId, type: 'clip').data;
    expect(clips, hasLength(1));
    final clip = clips.single;
    expect(clip.id, result.clipAssetId);
    expect(clip.name, contains('一'));
    expect(clip.filePath, result.outputRelPath);
    expect(clip.imageState, stateDone);
  });

  test('composeEpisode：存在分镜配音时传递视频+音频时间线给 composer', () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: 'alloy',
      sex: '男',
      describe: '沉稳',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '少侠，该醒了。',
          name: 'alloy-1',
          describe: '平静',
          existingImageId: null,
        ),
      ],
    );
    engine.bindStoryboardAudio(
        storyboardId: sb1, audioAssetId: audioId, audioText: '少侠，该醒了。');

    final result = await engine.composeEpisode(projectId, scriptId);

    expect(result.segmentCount, 1);
    expect(composer.concatCalls, isEmpty);
    final segment = composer.composeCalls.single.single;
    expect(segment.videoAbsPath, engine.mediaAbsPath('p/vid_1.mp4'));
    expect(segment.audioAbsPath, engine.audioAssetAbsPath(audioId));
  });

  test('composeEpisode：存在转场或滤镜时走 compose 以保留 NLE 元数据', () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);
    engine.updateVideoTransition(track1, 'fade');
    engine.updateVideoFilter(track1, 'cinematic');

    await engine.composeEpisode(projectId, scriptId);

    expect(composer.concatCalls, isEmpty, reason: 'concat 只有路径列表，会丢失转场/滤镜元数据');
    final segment = composer.composeCalls.single.single;
    expect(segment.transition, 'fade');
    expect(segment.filter, 'cinematic');
  });

  test('orderedComposeSegments 传递每镜转场与滤镜元数据', () {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);

    engine.updateVideoTransition(track1, 'fade');
    engine.updateVideoFilter(track1, 'cinematic');

    final segment = engine.orderedComposeSegments(scriptId).single!;
    expect(segment.transition, 'fade');
    expect(segment.filter, 'cinematic');
  });

  test('composeEpisode：额外素材 clip 作为多层时间线段参与合成', () async {
    final sb1 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final sb2 = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final track1 = engine.ensureTrackForStoryboard(sb1);
    final track2 = engine.ensureTrackForStoryboard(sb2);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track1, 'p/vid_1.mp4', vtDone]);
    engine.selectVideo(track1, db.lastInsertRowId);
    db.execute(
        "INSERT INTO o_video (videoTrackId,filePath,state) VALUES (?,?,?)",
        [track2, 'p/vid_2.mp4', vtDone]);
    engine.selectVideo(track2, db.lastInsertRowId);
    engine.updateVideoDuration(track1, 3);
    engine.updateVideoDuration(track2, 5);

    const overlayRel = 'p/overlay.mp4';
    File(engine.mediaAbsPath(overlayRel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 9, 9]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '法阵叠加',
      relPath: overlayRel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 1,
      startMs: 1500,
      durationMs: 1200,
    );
    engine.updateTimelineClip(
      clipId: clipId,
      lane: 1,
      startMs: 1500,
      durationMs: 1200,
      opacity: 0.42,
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips.single.id, clipId);
    expect(clips.single.lane, 1);
    expect(clips.single.startMs, 1500);
    expect(clips.single.durationMs, 1200);
    expect(clips.single.opacity, 0.42);
    expect(clips.single.filePath, overlayRel);

    final segments = engine.orderedComposeSegments(scriptId);
    expect(segments, hasLength(3));
    expect(segments[0]!.timelineKind, 'storyboard');
    expect(segments[0]!.lane, 0);
    expect(segments[0]!.startMs, 0);
    expect(segments[0]!.durationMs, 3000);
    expect(segments[1]!.timelineKind, 'clip');
    expect(segments[1]!.lane, 1);
    expect(segments[1]!.startMs, 1500);
    expect(segments[1]!.durationMs, 1200);
    expect(segments[1]!.opacity, 0.42);
    expect(segments[1]!.videoAbsPath, engine.mediaAbsPath(overlayRel));
    expect(segments[2]!.timelineKind, 'storyboard');
    expect(segments[2]!.startMs, 3000);
    expect(segments[2]!.durationMs, 5000);

    final result = await engine.composeEpisode(projectId, scriptId);

    expect(result.segmentCount, 3);
    expect(composer.concatCalls, isEmpty);
    final composed = composer.composeCalls.single;
    expect(composed[1].timelineKind, 'clip');
    expect(composed[1].lane, 1);
    expect(composed[1].startMs, 1500);
    expect(composed[1].durationMs, 1200);
    expect(composed[1].opacity, 0.42);
  });

  test('timelineClip：可更新时间线位置并夹住非法值', () {
    const overlayRel = 'p/overlay-edit.mp4';
    File(engine.mediaAbsPath(overlayRel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '云雾遮罩',
      relPath: overlayRel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    engine.updateTimelineClip(
      clipId: clipId,
      lane: -3,
      startMs: -200,
      durationMs: -1,
    );

    final clip = engine.timelineClips(scriptId).single;
    expect(clip.id, clipId);
    expect(clip.lane, 1);
    expect(clip.startMs, 0);
    expect(clip.durationMs, isNull);

    engine.updateTimelineClip(
      clipId: clipId,
      lane: 4,
      startMs: 2300,
      durationMs: 900,
    );

    final updated = engine.timelineClips(scriptId).single;
    expect(updated.lane, 4);
    expect(updated.startMs, 2300);
    expect(updated.durationMs, 900);
  });

  test('timelineClip：可按偏移量分割成连续素材段', () {
    const overlayRel = 'p/overlay-split.mp4';
    File(engine.mediaAbsPath(overlayRel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 6]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '分割遮罩',
      relPath: overlayRel,
    );
    final clipId = engine.addTimelineClipFromAsset(
      projectId: projectId,
      scriptId: scriptId,
      clipAssetId: clipAssetId,
      lane: 2,
      startMs: 1500,
      durationMs: 1200,
    );

    final splitId = engine.splitTimelineClip(
      clipId: clipId,
      offsetMs: 500,
    );

    final clips = engine.timelineClips(scriptId);
    expect(clips, hasLength(2));
    expect(clips[0].id, clipId);
    expect(clips[0].lane, 2);
    expect(clips[0].startMs, 1500);
    expect(clips[0].durationMs, 500);
    expect(clips[0].filePath, overlayRel);
    expect(clips[1].id, splitId);
    expect(clips[1].assetId, clipAssetId);
    expect(clips[1].name, '分割遮罩');
    expect(clips[1].lane, 2);
    expect(clips[1].startMs, 2000);
    expect(clips[1].durationMs, 700);
    expect(clips[1].filePath, overlayRel);
  });

  test('composeEpisode：存在未选中分镜时抛 errPromptMissing 且不拼接', () async {
    engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    expect(
      () => engine.composeEpisode(projectId, scriptId),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errPromptMissing)),
    );
    expect(composer.concatCalls, isEmpty);
  });

  test('composeEpisode：无任何分镜时抛 errNoChapters', () async {
    final emptyScriptId =
        engine.addScript(projectId: projectId, name: '空', content: 'x');
    expect(
      () => engine.composeEpisode(projectId, emptyScriptId),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errNoChapters)),
    );
  });
}
