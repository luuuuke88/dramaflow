import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
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
      final state = db.select(
              'SELECT state FROM o_tasks WHERE id=?', [taskId]).first['state']
          as String;
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

  test('generateVideoPrompt 用户消息带上关联资产名称与时长做增强', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '少年拔剑');
    final roleId = engine.addAsset(
        projectId: projectId, type: 'role', name: '林朝雪', describe: '');
    final propId = engine.addAsset(
        projectId: projectId, type: 'prop', name: '青霜剑', describe: '');
    db.execute(
        'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?),(?,?)',
        [roleId, sbId, propId, sbId]);
    db.execute("UPDATE o_storyboard SET duration='5' WHERE id=?", [sbId]);

    String? seenUser;
    gateway.textHandler = (system, user) {
      seenUser = user;
      return 'pan';
    };
    await engine.generateVideoPrompt(sbId);
    expect(seenUser, contains('少年拔剑'));
    expect(seenUser, contains('林朝雪'));
    expect(seenUser, contains('青霜剑'));
    expect(seenUser, contains('镜头时长'));
    expect(seenUser, contains('5'));
  });

  test('generateVideoPrompt 优先使用目标视频模型的专属提示词模板', () async {
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:doubao-seedance-2-0-mini-260615')",
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'volcengine',
        'doubao-seedance-2-0-mini-260615',
        'video_prompt_gen',
        'video/seedance2Multi-parameterMode.md',
        'Seedance 2.0 Mini 专属视频提示词模板',
      ],
    );
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '少年御剑飞起');

    String? seenSystem;
    gateway.textHandler = (system, user) {
      seenSystem = system;
      return 'dolly up';
    };

    await engine.generateVideoPrompt(sbId);

    expect(seenSystem, 'Seedance 2.0 Mini 专属视频提示词模板');
  });

  test('updateVideoPrompt 手动覆盖运镜提示词', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.updateVideoPrompt(trackId, '缓慢推近特写');
    expect(engine.track(trackId)!.prompt, '缓慢推近特写');
  });

  test('updateVideoDuration 写入/清空本镜时长；非正值清空', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.updateVideoDuration(trackId, 6);
    expect(engine.track(trackId)!.duration, 6);
    engine.updateVideoDuration(trackId, 0);
    expect(engine.track(trackId)!.duration, isNull, reason: '非正值视为清空');
    engine.updateVideoDuration(trackId, 8);
    engine.updateVideoDuration(trackId, null);
    expect(engine.track(trackId)!.duration, isNull);
  });

  test('updateVideoTransition/updateVideoFilter 写入/清空每镜 NLE 参数', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);

    engine.updateVideoTransition(trackId, 'fade');
    engine.updateVideoFilter(trackId, 'cinematic');
    var track = engine.track(trackId)!;
    expect(track.transition, 'fade');
    expect(track.filter, 'cinematic');

    engine.updateVideoTransition(trackId, '');
    engine.updateVideoFilter(trackId, null);
    track = engine.track(trackId)!;
    expect(track.transition, isNull, reason: '空字符串视为清空');
    expect(track.filter, isNull);
  });

  test('generateVideoPrompt 增强时长优先取视频轨（用户编辑更权威）', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute("UPDATE o_storyboard SET duration='3' WHERE id=?", [sbId]);
    engine.updateVideoDuration(trackId, 9);
    String? seenUser;
    gateway.textHandler = (system, user) {
      seenUser = user;
      return 'pan';
    };
    await engine.generateVideoPrompt(sbId);
    expect(seenUser, contains('9'), reason: '视频轨时长优先于分镜时长文本');
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
    final taskId = engine.batchGenerateVideos(projectId, [withImage, noImage]);
    await waitTask(taskId);

    final okTrackId = engine
        .storyboards(scriptId)
        .firstWhere((r) => r.id == withImage)
        .trackId!;
    final okTrack = engine.track(okTrackId)!;
    expect(okTrack.state, vtDone);
    expect(okTrack.candidates.single.filePath, 'p/vid_out.mp4');
    expect(okTrack.selectVideoId, okTrack.candidates.single.id,
        reason: '首个候选自动选中');

    final badTrackId = engine
        .storyboards(scriptId)
        .firstWhere((r) => r.id == noImage)
        .trackId!;
    final badTrack = engine.track(badTrackId)!;
    expect(badTrack.state, vtFailed);
    expect(EngineException.fromReasonJson(badTrack.reason)?.errKey,
        errPromptMissing);
  });

  test('selectVideo 手动切换选中候选；deleteVideo 清空被删的选中引用并删除磁盘文件', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    final mediaRoot = p.join(dir.path, 'media');
    var callCount = 0;
    gateway.videoHandler = (prompt, firstFrame, pid) {
      callCount++;
      final rel = 'p/vid_$callCount.mp4';
      // 写真实文件，验证 deleteVideo 会连磁盘一起清。
      final f = File(p.join(mediaRoot, rel))
        ..parent.createSync(recursive: true);
      f.writeAsBytesSync([0, 1, 2, 3]);
      return rel;
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

    final secondFile = File(p.join(mediaRoot, 'p/vid_2.mp4'));
    expect(secondFile.existsSync(), isTrue, reason: '前置：候选文件已落盘');
    engine.deleteVideo(secondVideoId);
    expect(engine.track(trackId)!.candidates, hasLength(1));
    expect(engine.track(trackId)!.selectVideoId, isNull,
        reason: '删除的正是当前选中候选，需清空引用');
    expect(secondFile.existsSync(), isFalse,
        reason: 'deleteVideo 需删除磁盘文件，不能泄漏');
  });

  test('attachClipToTrack 从素材库 clip 创建候选并保护源素材文件', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    const rel = 'p/library_clip.mp4';
    final clipFile = File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    final clipAssetId = engine.registerClipAsset(
      projectId: projectId,
      name: '素材镜头A',
      relPath: rel,
    );

    final videoId = engine.attachClipToTrack(trackId, clipAssetId);

    final track = engine.track(trackId)!;
    expect(track.state, vtDone);
    expect(track.selectVideoId, videoId);
    expect(track.candidates, hasLength(1));
    expect(track.candidates.single.filePath, rel);
    expect(track.candidates.single.state, vtDone);
    expect(clipFile.existsSync(), isTrue, reason: '从素材库复用 clip 时不能移动或删除原素材文件');

    engine.deleteVideo(videoId);
    expect(engine.track(trackId)!.candidates, isEmpty);
    expect(clipFile.existsSync(), isTrue, reason: '删除候选不能误删素材库里的 clip 源文件');
  });

  test('saveVideoCandidateAsClip 将工作台候选保存为 clip 素材并保护源文件', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    const rel = 'p/generated_candidate.mp4';
    final videoFile = File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 7, 8]);
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, rel, vtDone],
    );
    final videoId = db.lastInsertRowId;

    final clipAssetId = engine.saveVideoCandidateAsClip(videoId, name: '可复用镜头');

    final clips = engine.getAssets(projectId, type: 'clip').data;
    expect(clips, hasLength(1));
    expect(clips.single.id, clipAssetId);
    expect(clips.single.name, '可复用镜头');
    expect(clips.single.filePath, rel);
    expect(videoFile.existsSync(), isTrue);

    engine.deleteVideo(videoId);
    expect(videoFile.existsSync(), isTrue,
        reason: '候选保存进素材库后，删除候选不能删除已入库 clip 文件');
  });

  test('deleteScripts 级联清除 o_videoTrack 行与视频磁盘文件（此前泄漏）', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    final mediaRoot = p.join(dir.path, 'media');
    gateway.videoHandler = (prompt, firstFrame, pid) {
      final rel = 'p/vid_del.mp4';
      final f = File(p.join(mediaRoot, rel))
        ..parent.createSync(recursive: true);
      f.writeAsBytesSync([9, 9, 9]);
      return rel;
    };
    final taskId = engine.batchGenerateVideos(projectId, [sbId]);
    await waitTask(taskId);
    final trackId = engine.storyboards(scriptId).single.trackId!;
    final vidFile = File(p.join(mediaRoot, 'p/vid_del.mp4'));
    expect(vidFile.existsSync(), isTrue);
    expect(db.select('SELECT id FROM o_videoTrack WHERE id=?', [trackId]),
        isNotEmpty);

    engine.deleteScripts([scriptId]);

    expect(
        db.select('SELECT id FROM o_videoTrack WHERE scriptId=?', [scriptId]),
        isEmpty,
        reason: 'o_videoTrack 行必须随剧本级联删除');
    expect(db.select('SELECT id FROM o_video WHERE scriptId=?', [scriptId]),
        isEmpty);
    expect(vidFile.existsSync(), isFalse, reason: '视频磁盘文件必须一并清除');
  });

  test('冷启动恢复：processing 任务判失败且滞留轨道/视频置 生成失败', () {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute(
        'UPDATE o_videoTrack SET state=? WHERE id=?', [vtGenerating, trackId]);
    db.execute("INSERT INTO o_video (videoTrackId,state) VALUES (?,?)",
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
