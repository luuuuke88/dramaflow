import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/video_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;
  late _Gateway gateway;
  late int projectId;
  late int scriptId;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-video-');
    db = openEngineDb(':memory:');
    gateway = _Gateway();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
      queueTick: const Duration(milliseconds: 10),
    );
    db.execute(
      "INSERT INTO o_prompt (name,type,data,useData) VALUES "
      "('video_prompt_gen','video_prompt_gen','运镜提示词系统词',NULL)",
    );
    engine.installVideoTrackPipeline();
    engine.queue.start();
    projectId = engine.addProject(projectType: 'novel', name: '视频测试');
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> waitTask(int taskId, {String expectState = 'success'}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final state = db
          .select('SELECT state FROM o_tasks WHERE id=?', [taskId])
          .first['state'] as String;
      if (state == 'success' || state == 'failed') {
        expect(state, expectState);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('任务超时');
  }

  test('ensureTrackForStoryboard 懒建轨道并回填 storyboard.trackId', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    final again = engine.ensureTrackForStoryboard(sbId);
    expect(again, trackId, reason: '幂等，不重复建轨道');
    final row = engine.storyboards(scriptId).single;
    expect(row.trackId, trackId);
    expect(engine.track(trackId)!.state, vtNotGenerated);
  });

  test('generateVideoPrompt 同步生成并写入轨道', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '少年拔剑');
    gateway.textHandler = (system, user) {
      expect(user, contains('少年拔剑'));
      return '<think>x</think>slow pan across snowy mountain, hero draws sword';
    };
    final text = await engine.generateVideoPrompt(sbId);
    expect(text, 'slow pan across snowy mountain, hero draws sword');
    final trackId = engine.storyboards(scriptId).single.trackId!;
    expect(engine.track(trackId)!.prompt, text);
  });

  test('批量生成：无首帧图直接失败；有首帧图成功且首个候选自动选中', () async {
    final withImage = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute("UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?",
        [withImage]);
    final noImage = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'y');

    gateway.videoHandler = (prompt, firstFrame, pid) {
      expect(firstFrame, contains('frame.png'));
      return 'p/vid_out.mp4';
    };
    final taskId =
        engine.batchGenerateVideos(projectId, [withImage, noImage]);
    await waitTask(taskId);

    final okTrackId = engine.storyboards(scriptId)
        .firstWhere((r) => r.id == withImage)
        .trackId!;
    final okTrack = engine.track(okTrackId)!;
    expect(okTrack.state, vtDone);
    expect(okTrack.candidates.single.filePath, 'p/vid_out.mp4');
    expect(okTrack.selectVideoId, okTrack.candidates.single.id,
        reason: '首个候选自动选中');

    final badTrackId = engine.storyboards(scriptId)
        .firstWhere((r) => r.id == noImage)
        .trackId!;
    final badTrack = engine.track(badTrackId)!;
    expect(badTrack.state, vtFailed);
    expect(EngineException.fromReasonJson(badTrack.reason)?.errKey,
        errPromptMissing);
  });

  test('selectVideo 手动切换选中候选；deleteVideo 清空被删的选中引用', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute("UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    var callCount = 0;
    gateway.videoHandler = (prompt, firstFrame, pid) {
      callCount++;
      return 'p/vid_$callCount.mp4';
    };
    final taskId = engine.batchGenerateVideos(projectId, [sbId]);
    await waitTask(taskId);
    final trackId = engine.storyboards(scriptId).single.trackId!;
    final firstVideoId = engine.track(trackId)!.candidates.single.id;

    // 手动再生成一条候选
    final taskId2 = engine.batchGenerateVideos(projectId, [sbId]);
    await waitTask(taskId2);
    final candidates = engine.track(trackId)!.candidates;
    expect(candidates, hasLength(2));
    expect(engine.track(trackId)!.selectVideoId, firstVideoId,
        reason: '已有选中时第二条不覆盖');

    final secondVideoId = candidates.last.id;
    engine.selectVideo(trackId, secondVideoId);
    expect(engine.track(trackId)!.selectVideoId, secondVideoId);

    engine.deleteVideo(secondVideoId);
    expect(engine.track(trackId)!.candidates, hasLength(1));
    expect(engine.track(trackId)!.selectVideoId, isNull,
        reason: '删除的正是当前选中候选，需清空引用');
  });

  test('冷启动恢复：processing 任务判失败且滞留轨道/视频置 生成失败', () {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute("UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute('UPDATE o_videoTrack SET state=? WHERE id=?', [vtGenerating, trackId]);
    db.execute(
        "INSERT INTO o_video (videoTrackId,state) VALUES (?,?)",
        [trackId, vtGenerating]);
    engine.batchGenerateVideos(projectId, [sbId]);
    db.execute("UPDATE o_tasks SET state='processing'");
    engine.queue.recoverOnColdStart();

    final track = engine.track(trackId)!;
    expect(track.state, vtFailed);
    expect(track.candidates.every((v) => v.state == vtFailed), isTrue);
  });
}

class _Gateway implements ProviderGateway {
  String Function(String system, String user)? textHandler;
  String Function(String prompt, String firstFrameAbsPath, String projectId)?
      videoHandler;

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    expect(stage, 'video_prompt_gen');
    return TextResult(textHandler!(system, user));
  }

  @override
  Future<String> generateVideo(
      String prompt, String firstFrameAbsPath, String projectId,
      {required String stage, CancelToken? cancelToken}) async {
    expect(stage, 'shot_video');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return videoHandler!(prompt, firstFrameAbsPath, projectId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
