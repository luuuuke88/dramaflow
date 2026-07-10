import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/volcengine_video.dart';
import 'package:dramaflow/src/engine/scripts.dart';
import 'package:dramaflow/src/engine/storyboard.dart';
import 'package:dramaflow/src/engine/video_request.dart';
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

  void configureVideoModel({
    String modelId = 'test-video',
    bool selectProject = true,
  }) {
    db.execute(
      'INSERT OR REPLACE INTO o_vendorConfig (id,enable,inputValues,models) '
      'VALUES (?,?,?,?)',
      [
        'volcengine',
        1,
        '{}',
        jsonEncode([
          {
            'modelId': modelId,
            'kind': 'video',
            'enabled': true,
            'capabilities': {
              'video': {
                'modes': ['first_frame', 'first_last_frame'],
                'references': {'image': 2, 'video': 0, 'audio': 0},
                'durations': [5],
                'resolutions': ['720p'],
                'ratios': ['16:9', '9:16'],
                'audio': 'none',
              },
            },
          },
        ]),
      ],
    );
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:$modelId')",
    );
    if (selectProject) {
      engine.editProject(
        projectId,
        videoModel: 'volcengine:$modelId',
        videoRatio: '9:16',
      );
    }
  }

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
    engine.saveVisualManual(
      name: '视频视觉',
      pack: 'video_pack',
      data: const {'art_storyboard_video': '视频视觉手册'},
    );
    projectId = engine.addProject(
      projectType: 'novel',
      name: '视频测试',
      artStyle: 'video_pack',
    );
    scriptId = engine.addScript(projectId: projectId, name: '一', content: 'x');
    configureVideoModel(selectProject: false);
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

  Future<void> waitUntil(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('等待条件超时');
  }

  void writeMedia(String rel) {
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
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
      expect(system, '运镜提示词系统词\n\n视频视觉手册');
      expect(user, contains('少年拔剑'));
      return '<think>x</think>slow pan across snowy mountain, hero draws sword';
    };
    final text = await engine.generateVideoPrompt(sbId);
    expect(text, 'slow pan across snowy mountain, hero draws sword');
    final trackId = engine.storyboards(scriptId).single.trackId!;
    expect(engine.track(trackId)!.prompt, text);
  });

  test('buildVideoRequest uses project model and persisted reference sources',
      () {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '少年御剑');
    writeMedia('p/first.png');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/first.png' WHERE id=?", [sbId]);
    final lastAssetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '山巅',
      describe: '',
    );
    writeMedia('p/last.png');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'image','已完成')",
      [lastAssetId, 'p/last.png'],
    );
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [db.lastInsertRowId, lastAssetId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.updateVideoRequest(
      trackId,
      VideoRequestDraft(
        version: 1,
        mode: VideoMode.firstLastFrame,
        references: [
          VideoReferenceSource(
            sourceType: 'storyboard',
            sourceId: sbId,
            mediaType: 'image',
            role: 'first_frame',
          ),
          VideoReferenceSource(
            sourceType: 'asset',
            sourceId: lastAssetId,
            mediaType: 'image',
            role: 'last_frame',
          ),
        ],
        duration: 5,
        resolution: '720p',
        ratio: '9:16',
        generateAudio: false,
      ),
    );

    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: sbId,
      trackId: trackId,
    );

    expect(request.modelBinding, 'volcengine:test-video');
    expect(request.mode, VideoMode.firstLastFrame);
    expect(request.ratio, '9:16');
    expect(request.references.map((reference) => reference.role),
        ['first_frame', 'last_frame']);
    expect(request.references.map((reference) => reference.localPath),
        ['p/first.png', 'p/last.png']);
  });

  test('batchGenerateVideos rejects unsupported controls before enqueue', () {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '不能提交');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.updateVideoRequest(
      trackId,
      VideoRequestDraft(
        version: 1,
        mode: VideoMode.text,
        references: const [],
        duration: 5,
        resolution: '720p',
        ratio: '9:16',
        generateAudio: false,
      ),
    );

    expect(
      () => engine.batchGenerateVideos(projectId, [sbId]),
      throwsA(isA<EngineException>()
          .having((error) => error.errKey, 'errKey', errModelMissing)),
    );
    expect(db.select('SELECT id FROM o_tasks'), isEmpty);
    expect(db.select('SELECT id FROM o_video'), isEmpty);
    expect(engine.track(trackId)!.state, vtNotGenerated);
  });

  test('video pipeline persists accepted upstream identity before first poll',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '安全提交');
    writeMedia('p/frame.png');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    writeMedia('p/accepted.mp4');
    final pollGate = Completer<VideoPollResult>();
    gateway.submitHandler = (request) {
      expect(request.modelBinding, 'volcengine:test-video');
      return const VideoSubmission('upstream-accepted');
    };
    gateway.pollHandler = (upstreamTaskId, projectId, modelBinding) {
      expect(upstreamTaskId, 'upstream-accepted');
      expect(modelBinding, 'volcengine:test-video');
      return pollGate.future;
    };

    final taskId = engine.batchGenerateVideos(projectId, [sbId]);
    await waitUntil(() => gateway.pollCount == 1);

    final candidate = db
        .select(
          'SELECT state,submissionState,upstreamTaskId,modelBinding,requestFingerprint '
          'FROM o_video',
        )
        .single;
    expect(candidate['state'], vtGenerating);
    expect(candidate['submissionState'], 'accepted');
    expect(candidate['upstreamTaskId'], 'upstream-accepted');
    expect(candidate['modelBinding'], 'volcengine:test-video');
    expect(candidate['requestFingerprint'], isNotEmpty);
    expect(gateway.submitCount, 1);

    pollGate.complete(const VideoPollResult(
      upstreamState: 'succeeded',
      localVideoPath: 'p/accepted.mp4',
    ));
    await waitTask(taskId);
    expect(engine.track(engine.storyboards(scriptId).single.trackId!)!.state,
        vtDone);
  });

  test('cold restart polls accepted candidate without a second submission',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '恢复轮询');
    writeMedia('p/recovery-frame.png');
    writeMedia('p/recovered.mp4');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/recovery-frame.png' WHERE id=?",
        [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute(
        'UPDATE o_videoTrack SET state=? WHERE id=?', [vtGenerating, trackId]);
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState,modelBinding,requestFingerprint,upstreamTaskId,upstreamState) "
      "VALUES (?,?,?,?, 'accepted', ?, ?, 'upstream-recovery', 'running')",
      [
        projectId,
        scriptId,
        trackId,
        vtGenerating,
        'volcengine:test-video',
        'fingerprint',
      ],
    );
    final videoId = db.lastInsertRowId;
    gateway.pollHandler = (upstreamTaskId, projectId, modelBinding) {
      expect(upstreamTaskId, 'upstream-recovery');
      expect(modelBinding, 'volcengine:test-video');
      return const VideoPollResult(
        upstreamState: 'succeeded',
        localVideoPath: 'p/recovered.mp4',
      );
    };
    final taskId = engine.queue.enqueue(
      projectId: projectId,
      taskClass: 'video_generation',
      relatedObjects: {
        'kind': 'videoTrack',
        'trackIds': [trackId],
        'videoIds': [videoId],
      },
    );
    db.execute("UPDATE o_tasks SET state='processing' WHERE id=?", [taskId]);

    engine.queue.recoverOnColdStart();
    await waitTask(taskId);

    expect(gateway.submitCount, 0);
    expect(gateway.pollCount, 1);
    final candidate = db.select(
        'SELECT state,submissionState,upstreamTaskId FROM o_video WHERE id=?',
        [videoId]).single;
    expect(candidate['state'], vtDone);
    expect(candidate['submissionState'], 'accepted');
    expect(candidate['upstreamTaskId'], 'upstream-recovery');
  });

  test('canceling an accepted video also cancels the upstream task', () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '取消远端');
    writeMedia('p/cancel-frame.png');
    writeMedia('p/cancel-race.mp4');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/cancel-frame.png' WHERE id=?",
        [sbId]);
    final pollGate = Completer<VideoPollResult>();
    gateway.submitHandler = (_) => const VideoSubmission('upstream-cancel');
    gateway.pollHandler = (_, __, ___) => pollGate.future;

    final taskId = engine.batchGenerateVideos(projectId, [sbId]);
    await waitUntil(() => gateway.pollCount == 1);
    await engine.cancelJob(taskId);
    pollGate.complete(const VideoPollResult(
      upstreamState: 'succeeded',
      localVideoPath: 'p/cancel-race.mp4',
    ));
    await waitTask(taskId, expectState: 'failed');

    expect(gateway.cancelledUpstreamIds, ['upstream-cancel']);
    final candidate = db.select(
        'SELECT state,errorReason FROM o_video WHERE upstreamTaskId=?',
        ['upstream-cancel']).single;
    expect(candidate['state'], vtFailed);
    expect(
        EngineException.fromReasonJson(candidate['errorReason'] as String?)
            ?.errKey,
        errCanceled);
    expect(engine.track(engine.storyboards(scriptId).single.trackId!)!.state,
        vtFailed);
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
      'INSERT OR REPLACE INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'volcengine',
        1,
        '{}',
        jsonEncode([
          {
            'modelId': 'doubao-seedance-2-0-mini-260615',
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
                'promptTemplates': {
                  'first_frame': 'video/seedance2Multi-parameterMode.md',
                },
              },
            },
          },
        ]),
      ],
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

    expect(
      seenSystem,
      '运镜提示词系统词\n\n视频视觉手册\n\nSeedance 2.0 Mini 专属视频提示词模板',
    );
    final trackId = engine.storyboards(scriptId).single.trackId!;
    final provenanceRaw = db.select(
        'SELECT promptProvenance FROM o_videoTrack WHERE id=?',
        [trackId]).single['promptProvenance'] as String;
    final provenance = jsonDecode(provenanceRaw) as Map<String, dynamic>;
    final sources = (provenance['promptSources'] as List)
        .map((source) => Map<String, dynamic>.from(source as Map))
        .toList();
    expect(sources.map((source) => source['id']), [
      'base:video_prompt_gen',
      'visual:video_pack:art_storyboard_video',
      'model:volcengine:doubao-seedance-2-0-mini-260615:video/seedance2Multi-parameterMode.md',
    ]);
    expect(sources, everyElement(isNot(contains('content'))));
  });

  test('generateVideoPrompt 为旧版模型提示词保存实际来源', () async {
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','legacy:video')",
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'legacy',
        'video',
        'video_prompt_gen',
        'video_prompt_gen',
        '旧版模型视频提示词模板',
      ],
    );
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '旧版模型镜头');

    String? seenSystem;
    gateway.textHandler = (system, user) {
      seenSystem = system;
      return 'slow pan';
    };

    await engine.generateVideoPrompt(sbId);

    expect(seenSystem, '旧版模型视频提示词模板\n\n视频视觉手册');
    final trackId = engine.storyboards(scriptId).single.trackId!;
    final provenanceRaw = db.select(
        'SELECT promptProvenance FROM o_videoTrack WHERE id=?',
        [trackId]).single['promptProvenance'] as String;
    final provenance = jsonDecode(provenanceRaw) as Map<String, dynamic>;
    final sources = (provenance['promptSources'] as List)
        .map((source) => Map<String, dynamic>.from(source as Map))
        .toList();
    expect(sources.map((source) => source['id']), [
      'model:legacy:video:video_prompt_gen',
      'visual:video_pack:art_storyboard_video',
    ]);
    expect(sources, everyElement(isNot(contains('content'))));
  });

  test('updateVideoPrompt 手动覆盖运镜提示词', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    engine.updateVideoPrompt(trackId, '缓慢推近特写');
    expect(engine.track(trackId)!.prompt, '缓慢推近特写');
  });

  test('video request JSON round-trips without changing storyboard audio', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute(
      "UPDATE o_storyboard SET audioAssetId=77,audioPath='audio/voice.m4a',audioState='已完成',audioText='台词' WHERE id=?",
      [sbId],
    );
    final normalized = engine.videoRequestForTrack(trackId);
    expect(normalized.mode, VideoMode.firstFrame);
    expect(normalized.references.single.sourceId, sbId);
    expect(
        db.select('SELECT videoRequest FROM o_videoTrack WHERE id=?',
            [trackId]).single['videoRequest'],
        isNull,
        reason: '读取旧行只归一化，不在未保存时写回');
    final request = VideoRequestDraft(
      version: 1,
      mode: VideoMode.firstFrame,
      references: [
        VideoReferenceSource(
          sourceType: 'storyboard',
          sourceId: sbId,
          mediaType: 'image',
          role: 'first_frame',
        ),
      ],
      duration: 5,
      resolution: '720p',
      ratio: '16:9',
      generateAudio: true,
    );

    engine.updateVideoRequest(trackId, request);

    final restored = engine.videoRequestForTrack(trackId);
    expect(restored.toJson(), request.toJson());
    final stored = jsonDecode(db.select(
        'SELECT videoRequest FROM o_videoTrack WHERE id=?',
        [trackId]).single['videoRequest'] as String) as Map<String, dynamic>;
    expect(stored['generateAudio'], isTrue);
    final storyboard = db.select(
        'SELECT audioAssetId,audioPath,audioState,audioText FROM o_storyboard WHERE id=?',
        [sbId]).single;
    expect(storyboard['audioAssetId'], 77);
    expect(storyboard['audioPath'], 'audio/voice.m4a');
    expect(storyboard['audioState'], '已完成');
    expect(storyboard['audioText'], '台词');
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

  test('批量生成：合法首帧成功且首个候选自动选中', () async {
    final withImage = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute("UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?",
        [withImage]);
    writeMedia('p/frame.png');

    gateway.videoHandler = (prompt, firstFrame, pid) {
      expect(firstFrame, contains('frame.png'));
      return 'p/vid_out.mp4';
    };
    final taskId = engine.batchGenerateVideos(projectId, [withImage]);
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
  });

  test('selectVideo 手动切换选中候选；deleteVideo 清空被删的选中引用并删除磁盘文件', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    writeMedia('p/frame.png');
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

  test('deleteVideoTrack 清空分镜轨道并删除候选视频文件', () {
    final sbId = engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    const rel = 'p/track_del.mp4';
    final videoFile = File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([7, 7, 7]);
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, rel, vtDone],
    );
    final videoId = db.lastInsertRowId;
    engine.selectVideo(trackId, videoId);

    engine.deleteVideoTrack(trackId);

    final shot = engine.storyboards(scriptId).singleWhere((s) => s.id == sbId);
    expect(shot.trackId, isNull);
    expect(engine.track(trackId), isNull);
    expect(db.select('SELECT id FROM o_video WHERE id=?', [videoId]), isEmpty);
    expect(videoFile.existsSync(), isFalse);
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
    writeMedia('p/frame.png');
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
    db.execute(
      'INSERT INTO o_timelineClip (projectId,scriptId,filePath,lane,startMs) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, 'p/overlay.mp4', 1, 500],
    );

    engine.deleteScripts([scriptId]);

    expect(
        db.select('SELECT id FROM o_videoTrack WHERE scriptId=?', [scriptId]),
        isEmpty,
        reason: 'o_videoTrack 行必须随剧本级联删除');
    expect(db.select('SELECT id FROM o_video WHERE scriptId=?', [scriptId]),
        isEmpty);
    expect(
        db.select('SELECT id FROM o_timelineClip WHERE scriptId=?', [scriptId]),
        isEmpty,
        reason: '时间线素材层必须随剧本删除');
    expect(vidFile.existsSync(), isFalse, reason: '视频磁盘文件必须一并清除');
  });

  test('冷启动恢复：processing 任务判失败且滞留轨道/视频置 生成失败', () {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    writeMedia('p/frame.png');
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

  test('冷启动恢复：仅已接受且有上游任务 ID 的视频任务回到 pending', () {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute(
        'UPDATE o_videoTrack SET state=? WHERE id=?', [vtGenerating, trackId]);
    db.execute(
      "INSERT INTO o_video (videoTrackId,state,submissionState,upstreamTaskId) VALUES (?,?,'accepted','upstream-1')",
      [trackId, vtGenerating],
    );
    db.execute(
      "INSERT INTO o_video (videoTrackId,state,submissionState) VALUES (?,?,'prepared')",
      [trackId, vtGenerating],
    );
    final taskId = engine.queue.enqueue(
      projectId: projectId,
      taskClass: 'video_generation',
      relatedObjects: {
        'trackIds': [trackId],
      },
    );
    db.execute("UPDATE o_tasks SET state='processing' WHERE id=?", [taskId]);

    engine.queue.recoverOnColdStart();

    expect(
        db.select(
            'SELECT state FROM o_tasks WHERE id=?', [taskId]).single['state'],
        'pending');
    final candidates = db.select(
        'SELECT submissionState,state,errorReason FROM o_video WHERE videoTrackId=? ORDER BY id',
        [trackId]);
    expect(candidates.first['state'], vtGenerating);
    expect(candidates.last['state'], vtFailed);
    expect(
        EngineException.fromReasonJson(
                candidates.last['errorReason'] as String?)
            ?.errKey,
        errAppRestart);
    expect(engine.track(trackId)!.state, vtGenerating);
  });
}

class _Gateway implements ProviderGateway {
  String Function(String system, String user)? textHandler;
  String Function(String prompt, String firstFrameAbsPath, String projectId)?
      videoHandler;
  VideoSubmission Function(VideoGenerationRequest request)? submitHandler;
  FutureOr<VideoPollResult> Function(
    String upstreamTaskId,
    String projectId,
    String? modelBinding,
  )? pollHandler;
  final submittedRequests = <VideoGenerationRequest>[];
  final generatedPaths = <String, String>{};
  final cancelledUpstreamIds = <String>[];
  var submitCount = 0;
  var pollCount = 0;

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
  Future<VideoSubmission> submitVideo(
    VideoGenerationRequest request, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    expect(stage, 'shot_video');
    submitCount++;
    submittedRequests.add(request);
    if (submitHandler != null) return submitHandler!(request);
    final taskId = 'fake-$submitCount';
    generatedPaths[taskId] = videoHandler!(
      request.prompt,
      request.references.first.localPath,
      '$request.projectId',
    );
    return VideoSubmission(taskId);
  }

  @override
  Future<VideoPollResult> pollVideo(
    String upstreamTaskId,
    String projectId, {
    required String stage,
    required String? modelOverride,
    CancelToken? cancelToken,
  }) async {
    expect(stage, 'shot_video');
    pollCount++;
    if (pollHandler != null) {
      return pollHandler!(upstreamTaskId, projectId, modelOverride);
    }
    return VideoPollResult(
      upstreamState: 'succeeded',
      localVideoPath: generatedPaths[upstreamTaskId],
    );
  }

  @override
  Future<void> cancelVideo(
    String upstreamTaskId, {
    required String stage,
    required String? modelOverride,
  }) async {
    expect(stage, 'shot_video');
    cancelledUpstreamIds.add(upstreamTaskId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
