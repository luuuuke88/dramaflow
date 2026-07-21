import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/assets.dart';
import 'package:dramaflow/src/engine/audio_bind.dart';
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

  test('新建独立视频轨不绑定分镜，并保留创建时长', () {
    final storyboardId =
        engine.addStoryboard(projectId: projectId, scriptId: scriptId);

    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );

    final track = engine.track(trackId)!;
    expect(track.projectId, projectId);
    expect(track.scriptId, scriptId);
    expect(track.duration, 5);
    expect(track.state, vtNotGenerated);
    expect(
        engine
            .storyboards(scriptId)
            .singleWhere((s) => s.id == storyboardId)
            .trackId,
        isNull,
        reason: '独立轨不能被伪装成分镜轨');
  });

  test('独立视频轨列表按创建顺序显示，且不混入分镜轨', () {
    final storyboardId =
        engine.addStoryboard(projectId: projectId, scriptId: scriptId);
    final storyboardTrackId = engine.ensureTrackForStoryboard(storyboardId);
    final first = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    final second = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 10,
    );

    expect(
      engine
          .standaloneVideoTracks(projectId, scriptId)
          .map((track) => track.id),
      [first, second],
    );
    expect(
      engine
          .standaloneVideoTracks(projectId, scriptId)
          .any((track) => track.id == storyboardTrackId),
      isFalse,
    );
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

  test('独立视频轨可用已保存参数构建纯文本请求而不伪造分镜', () {
    configureVideoModel(modelId: 'test-video');
    db.execute(
      "UPDATE o_vendorConfig SET models=? WHERE id='volcengine'",
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
      ],
    );
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    engine.updateVideoPrompt(trackId, '山巅人物御剑穿云');
    engine.updateVideoRequest(
      trackId,
      VideoRequestDraft(
        version: 1,
        mode: VideoMode.text,
        references: const [],
        duration: 5,
        resolution: '720p',
        ratio: '16:9',
        generateAudio: false,
      ),
    );

    final request = engine.buildVideoRequestForTrack(
      projectId: projectId,
      trackId: trackId,
    );

    expect(request.storyboardId, isNull);
    expect(request.prompt, '山巅人物御剑穿云');
    expect(request.mode, VideoMode.text);
    expect(request.references, isEmpty);
  });

  test('独立视频轨可直接入同一视频队列而不绑定分镜', () {
    configureVideoModel(modelId: 'test-video');
    db.execute(
      "UPDATE o_vendorConfig SET models=? WHERE id='volcengine'",
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
      ],
    );
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    engine.updateVideoPrompt(trackId, '剑客穿过云海');
    engine.updateVideoRequest(
      trackId,
      VideoRequestDraft(
        version: 1,
        mode: VideoMode.text,
        references: const [],
        duration: 5,
        resolution: '720p',
        ratio: '16:9',
        generateAudio: false,
      ),
    );

    final taskId = engine.batchGenerateVideoTracks(projectId, [trackId]);

    final candidate = engine.track(trackId)!.candidates.single;
    expect(taskId, greaterThan(0));
    expect(candidate.videoTrackId, trackId);
    expect(candidate.state, vtGenerating);
    expect(
      db.select('SELECT scriptId FROM o_video WHERE id=?',
          [candidate.id]).single['scriptId'],
      scriptId,
    );
  });

  test('独立视频轨可从项目素材库选择参考而不带入分镜首帧', () {
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '不应自动成为独立轨参考的分镜',
    );
    writeMedia('p/storyboard-only.png');
    db.execute(
      "UPDATE o_storyboard SET filePath='p/storyboard-only.png' WHERE id=?",
      [storyboardId],
    );
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '独立轨角色参考',
      describe: '',
    );
    writeMedia('p/standalone-reference.png');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'image','已完成')",
      [assetId, 'p/standalone-reference.png'],
    );
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [db.lastInsertRowId, assetId]);

    final candidates =
        engine.videoReferenceCandidatesForTrack(projectId, trackId);

    expect(
      candidates.map((candidate) => candidate.localPath),
      contains('p/standalone-reference.png'),
    );
    expect(
      candidates.map((candidate) => candidate.localPath),
      isNot(contains('p/storyboard-only.png')),
    );
  });

  test('videoReferenceCandidates 优先当前镜头素材并保留项目素材候选', () {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '参考素材');
    writeMedia('p/candidate-first.png');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/candidate-first.png' WHERE id=?",
        [sbId]);
    final assetId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '角色参考',
      describe: '',
    );
    writeMedia('p/candidate-role.png');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'image','已完成')",
      [assetId, 'p/candidate-role.png'],
    );
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [db.lastInsertRowId, assetId]);
    db.execute(
      'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
      [assetId, sbId],
    );
    final unrelatedAssetId = engine.addAsset(
      projectId: projectId,
      type: 'scene',
      name: '不相关场景',
      describe: '',
    );
    writeMedia('p/candidate-unrelated.png');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'image','已完成')",
      [unrelatedAssetId, 'p/candidate-unrelated.png'],
    );
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
        [db.lastInsertRowId, unrelatedAssetId]);

    final candidates = engine.videoReferenceCandidates(projectId, sbId);

    final paths = candidates.map((candidate) => candidate.localPath).toList();
    expect(
      paths,
      containsAll([
        'p/candidate-first.png',
        'p/candidate-role.png',
        'p/candidate-unrelated.png',
      ]),
    );
    expect(
      paths.indexOf('p/candidate-role.png'),
      lessThan(paths.indexOf('p/candidate-unrelated.png')),
      reason: '当前镜头关联资产应比项目其余素材优先展示',
    );
    expect(candidates.every((candidate) => candidate.localPath.startsWith('/')),
        isFalse);
  });

  test('videoReferenceCandidates 暴露关联资产已绑定的本地音频参考', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '角色有绑定配音的镜头',
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
      describe: '清冷',
      items: [
        (
          base64: base64Encode([1, 2, 3, 4]),
          ext: 'mp3',
          prompt: '角色台词样本',
          name: '林朝雪音色样本',
          describe: '',
          existingImageId: null,
        ),
      ],
    );
    engine.bindAssetAudio(roleId, audioId);
    engine.addAudioAssets(
      projectId: projectId,
      name: '不相关音色',
      sex: '男',
      describe: '',
      items: [
        (
          base64: base64Encode([5, 6, 7]),
          ext: 'mp3',
          prompt: '不相关',
          name: '不相关样本',
          describe: '',
          existingImageId: null,
        ),
      ],
    );

    final candidates = engine.videoReferenceCandidates(projectId, storyboardId);
    final audio = candidates.firstWhere(
      (candidate) =>
          candidate.source.sourceType == 'audio' &&
          candidate.source.sourceId == audioId,
    );

    expect(audio.source.sourceId, audioId);
    expect(audio.source.mediaType, 'audio');
    expect(audio.source.role, 'reference_audio');
    expect(audio.label, '林朝雪音色');
    expect(audio.localPath, startsWith('$projectId/'));
    expect(audio.localPath, endsWith('.mp3'));
  });

  test('videoReferenceCandidates 子资产候选可继承父级角色绑定的配音', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '角色有换装子资产的镜头',
    );
    final roleId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '有换装的角色',
      describe: '',
    );
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: '角色音色',
      sex: '女',
      describe: '',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '样本',
          name: '样本',
          describe: '',
          existingImageId: null,
        ),
      ],
    );
    engine.bindAssetAudio(roleId, audioId);

    final childId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '换装子资产',
      describe: '',
      parentAssetsId: roleId,
    );
    writeMedia('p/child-outfit.png');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'image','已完成')",
      [childId, 'p/child-outfit.png'],
    );
    db.execute(
      'UPDATE o_assets SET imageId=? WHERE id=?',
      [db.lastInsertRowId, childId],
    );

    final candidates =
        engine.videoReferenceCandidates(projectId, storyboardId);
    final childCandidate = candidates.firstWhere(
      (candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == childId,
    );

    expect(
      childCandidate.boundAudioSourceIds,
      contains(audioId),
      reason: '子资产作为候选时应继承父级角色绑定的配音，而不是查出空列表',
    );
  });

  test('videoReferenceCandidates 也列出项目中未关联当前分镜的可用素材', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '允许从项目素材库选参考的镜头',
    );
    final roleId = engine.uploadClip(
      projectId: projectId,
      type: 'role',
      name: '项目角色参考',
      bytes: [1, 2, 3],
      ext: 'png',
    );
    final clipId = engine.uploadClip(
      projectId: projectId,
      type: 'clip',
      name: '项目片段参考',
      bytes: [4, 5, 6],
      ext: 'mp4',
    );
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: '项目音色参考',
      sex: '女',
      describe: '',
      items: [
        (
          base64: base64Encode([7, 8, 9]),
          ext: 'mp3',
          prompt: '台词样本',
          name: '项目音色样本',
          describe: '',
          existingImageId: null,
        ),
      ],
    );

    final candidates = engine.videoReferenceCandidates(projectId, storyboardId);

    expect(
      candidates.any((candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == roleId &&
          candidate.source.mediaType == 'image'),
      isTrue,
    );
    expect(
      candidates.any((candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == clipId &&
          candidate.source.mediaType == 'video'),
      isTrue,
    );
    expect(
      candidates.any((candidate) =>
          candidate.source.sourceType == 'audio' &&
          candidate.source.sourceId == audioId &&
          candidate.source.mediaType == 'audio'),
      isTrue,
    );
  });

  test('videoReferenceCandidates 配音候选按父资产聚合，不为每条录音样本重复', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '配音资产有多条录音样本的镜头',
    );
    final audioId = engine.addAudioAssets(
      projectId: projectId,
      name: '多样本音色',
      sex: '女',
      describe: '',
      items: [
        (
          base64: base64Encode([1, 2, 3]),
          ext: 'mp3',
          prompt: '样本一',
          name: '样本一',
          describe: '',
          existingImageId: null,
        ),
        (
          base64: base64Encode([4, 5, 6]),
          ext: 'mp3',
          prompt: '样本二',
          name: '样本二',
          describe: '',
          existingImageId: null,
        ),
        (
          base64: base64Encode([7, 8, 9]),
          ext: 'mp3',
          prompt: '样本三',
          name: '样本三',
          describe: '',
          existingImageId: null,
        ),
      ],
    );

    final candidates =
        engine.videoReferenceCandidates(projectId, storyboardId);
    final audioCandidates = candidates
        .where((candidate) => candidate.source.mediaType == 'audio')
        .toList();

    expect(
      audioCandidates,
      hasLength(1),
      reason: '父资产与每条录音子样本不应各自拆成独立候选，同一音色只应出现一次',
    );
    expect(audioCandidates.single.source.sourceId, audioId);
    expect(audioCandidates.single.source.sourceType, 'audio');
  });

  test('videoReferenceCandidates 按片段扩展名分类并保留可选子资产', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '图片片段、视频片段和子资产都可作为参考',
    );
    final imageClipId = engine.uploadClip(
      projectId: projectId,
      name: '图片片段',
      bytes: [1, 2, 3],
      ext: 'png',
    );
    final videoClipId = engine.uploadClip(
      projectId: projectId,
      name: '视频片段',
      bytes: [4, 5, 6],
      ext: 'mp4',
    );
    final parentId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '角色父资产',
      describe: '',
    );
    final childId = engine.addAsset(
      projectId: projectId,
      type: 'role',
      name: '角色子资产',
      describe: '',
      parentAssetsId: parentId,
    );
    writeMedia('p/child-reference.png');
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'image','已完成')",
      [childId, 'p/child-reference.png'],
    );
    db.execute(
      'UPDATE o_assets SET imageId=? WHERE id=?',
      [db.lastInsertRowId, childId],
    );

    final candidates = engine.videoReferenceCandidates(projectId, storyboardId);

    expect(
      candidates.any((candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == imageClipId &&
          candidate.source.mediaType == 'image'),
      isTrue,
    );
    expect(
      candidates.any((candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == videoClipId &&
          candidate.source.mediaType == 'video'),
      isTrue,
    );
    expect(
      candidates.any((candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == childId &&
          candidate.source.mediaType == 'image'),
      isTrue,
    );
  });

  test('videoReferenceCandidates 音频扩展名的素材库片段归类为 reference_audio 角色', () {
    final storyboardId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '项目素材库里混入音频片段的镜头',
    );
    final audioClipId = engine.uploadClip(
      projectId: projectId,
      type: 'clip',
      name: '素材库音频片段',
      bytes: [1, 2, 3],
      ext: 'mp3',
    );

    final candidates =
        engine.videoReferenceCandidates(projectId, storyboardId);
    final clipCandidate = candidates.firstWhere(
      (candidate) =>
          candidate.source.sourceType == 'asset' &&
          candidate.source.sourceId == audioClipId,
    );

    expect(clipCandidate.source.mediaType, 'audio');
    expect(
      clipCandidate.source.role,
      'reference_audio',
      reason: 'mediaType 为 audio 的素材库候选必须归为 reference_audio，'
          '不能被二元表达式误判成 reference_image',
    );
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

  test('retry accepted running candidate only polls its existing upstream task',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '继续轮询');
    writeMedia('p/retry-running-frame.png');
    writeMedia('p/retry-running.mp4');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/retry-running-frame.png' WHERE id=?",
        [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: sbId,
      trackId: trackId,
    );
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState,modelBinding,requestFingerprint,upstreamTaskId,upstreamState) "
      "VALUES (?,?,?,?, 'accepted', ?, ?, 'upstream-running', 'running')",
      [
        projectId,
        scriptId,
        trackId,
        vtFailed,
        request.modelBinding,
        request.fingerprint(),
      ],
    );
    final videoId = db.lastInsertRowId;
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_generation',?,?)",
      [
        projectId,
        const EngineException(errNetwork).toReasonJson(),
        jsonEncode({
          'trackIds': [trackId],
          'videoIds': [videoId],
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;
    gateway.pollHandler = (upstreamTaskId, _, modelBinding) {
      expect(upstreamTaskId, 'upstream-running');
      expect(modelBinding, request.modelBinding);
      return const VideoPollResult(
        upstreamState: 'succeeded',
        localVideoPath: 'p/retry-running.mp4',
      );
    };

    final retryId = await engine.retryJob(failedTaskId);
    await waitTask(retryId);

    expect(gateway.submitCount, 0);
    expect(gateway.pollCount, 1);
    final retry = db.select('SELECT relatedObjects FROM o_tasks WHERE id=?',
        [retryId]).single['relatedObjects'] as String;
    expect(jsonDecode(retry), containsPair('videoIds', [videoId]));
  });

  test('retry terminal failed candidate creates a new paid submission',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '重新提交');
    writeMedia('p/retry-terminal-frame.png');
    writeMedia('p/retry-terminal.mp4');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/retry-terminal-frame.png' WHERE id=?",
        [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: sbId,
      trackId: trackId,
    );
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState,modelBinding,requestFingerprint,upstreamTaskId,upstreamState) "
      "VALUES (?,?,?,?, 'accepted', ?, ?, 'upstream-failed', 'failed')",
      [
        projectId,
        scriptId,
        trackId,
        vtFailed,
        request.modelBinding,
        request.fingerprint(),
      ],
    );
    final oldVideoId = db.lastInsertRowId;
    engine.selectVideo(trackId, oldVideoId);
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_generation',?,?)",
      [
        projectId,
        const EngineException(errNetwork).toReasonJson(),
        jsonEncode({
          'trackIds': [trackId],
          'videoIds': [oldVideoId],
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;
    gateway.submitHandler = (received) {
      expect(received.fingerprint(), request.fingerprint());
      return const VideoSubmission('upstream-retry');
    };
    gateway.pollHandler = (upstreamTaskId, _, __) {
      expect(upstreamTaskId, 'upstream-retry');
      return const VideoPollResult(
        upstreamState: 'succeeded',
        localVideoPath: 'p/retry-terminal.mp4',
      );
    };

    final retryId = await engine.retryJob(failedTaskId);
    final retry = jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [retryId]).single['relatedObjects'] as String) as Map;
    final retryVideoId = (retry['videoIds'] as List).single as int;
    expect(retryVideoId, isNot(oldVideoId));
    await waitTask(retryId);

    expect(gateway.submitCount, 1);
    expect(gateway.pollCount, 1);
    final old = db.select('SELECT state,upstreamTaskId FROM o_video WHERE id=?',
        [oldVideoId]).single;
    expect(old['state'], vtFailed);
    expect(old['upstreamTaskId'], 'upstream-failed');
    expect(engine.track(trackId)!.selectVideoId, retryVideoId);
  });

  test('retry terminal failed standalone candidate does not require a storyboard',
      () async {
    configureVideoModel();
    db.execute(
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
                'ratios': ['16:9', '9:16'],
                'audio': 'none',
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    writeMedia('p/retry-standalone.mp4');
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    engine.updateVideoPrompt(trackId, '独立轨重试镜头');
    final request = engine.buildVideoRequestForTrack(
      projectId: projectId,
      trackId: trackId,
    );
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState,modelBinding,requestFingerprint,upstreamTaskId,upstreamState) "
      "VALUES (?,?,?,?, 'accepted', ?, ?, 'upstream-failed', 'failed')",
      [
        projectId,
        scriptId,
        trackId,
        vtFailed,
        request.modelBinding,
        request.fingerprint(),
      ],
    );
    final oldVideoId = db.lastInsertRowId;
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_generation',?,?)",
      [
        projectId,
        const EngineException(errNetwork).toReasonJson(),
        jsonEncode({
          'trackIds': [trackId],
          'videoIds': [oldVideoId],
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;
    gateway.submitHandler = (received) {
      expect(received.storyboardId, isNull);
      expect(received.prompt, '独立轨重试镜头');
      return const VideoSubmission('upstream-standalone-retry');
    };
    gateway.pollHandler = (upstreamTaskId, _, __) {
      expect(upstreamTaskId, 'upstream-standalone-retry');
      return const VideoPollResult(
        upstreamState: 'succeeded',
        localVideoPath: 'p/retry-standalone.mp4',
      );
    };

    final retryId = await engine.retryJob(failedTaskId);
    await waitTask(retryId);

    expect(gateway.submitCount, 1);
    expect(gateway.pollCount, 1);
    expect(engine.track(trackId)!.state, vtDone);
  });

  test('retry prepared candidate rebuilds a corrected current request',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '修正参数后重试');
    writeMedia('p/retry-prepared-frame.png');
    writeMedia('p/retry-prepared.mp4');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/retry-prepared-frame.png' WHERE id=?",
        [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState,modelBinding,requestFingerprint) "
      "VALUES (?,?,?,?, 'prepared', 'volcengine:old-model', 'stale-request')",
      [projectId, scriptId, trackId, vtFailed],
    );
    final oldVideoId = db.lastInsertRowId;
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_generation',?,?)",
      [
        projectId,
        const EngineException(errLlmFormat).toReasonJson(),
        jsonEncode({
          'trackIds': [trackId],
          'videoIds': [oldVideoId],
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;
    final current = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: sbId,
      trackId: trackId,
    );
    gateway.submitHandler = (received) {
      expect(received.fingerprint(), current.fingerprint());
      return const VideoSubmission('upstream-prepared-retry');
    };
    gateway.pollHandler = (_, __, ___) => const VideoPollResult(
          upstreamState: 'succeeded',
          localVideoPath: 'p/retry-prepared.mp4',
        );

    final retryId = await engine.retryJob(failedTaskId);
    final retry = jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [retryId]).single['relatedObjects'] as String) as Map;
    final retryVideoId = (retry['videoIds'] as List).single as int;
    expect(retryVideoId, isNot(oldVideoId));
    await waitTask(retryId);

    expect(gateway.submitCount, 1);
    final rebuilt = db.select(
        'SELECT modelBinding,requestFingerprint FROM o_video WHERE id=?',
        [retryVideoId]).single;
    expect(rebuilt['modelBinding'], current.modelBinding);
    expect(rebuilt['requestFingerprint'], current.fingerprint());
  });

  test('legacy retry without video ids uses only the latest failed candidate',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '旧任务重试');
    writeMedia('p/retry-legacy-frame.png');
    writeMedia('p/retry-legacy.mp4');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/retry-legacy-frame.png' WHERE id=?",
        [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    final request = engine.buildVideoRequest(
      projectId: projectId,
      storyboardId: sbId,
      trackId: trackId,
    );
    for (final upstreamTaskId in ['upstream-old', 'upstream-latest']) {
      db.execute(
        "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState,modelBinding,requestFingerprint,upstreamTaskId,upstreamState) "
        "VALUES (?,?,?,?, 'accepted', ?, ?, ?, 'failed')",
        [
          projectId,
          scriptId,
          trackId,
          vtFailed,
          request.modelBinding,
          request.fingerprint(),
          upstreamTaskId,
        ],
      );
    }
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_generation',?,?)",
      [
        projectId,
        const EngineException(errNetwork).toReasonJson(),
        jsonEncode({
          'trackIds': [trackId]
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;
    gateway.submitHandler = (_) => const VideoSubmission('upstream-legacy');
    gateway.pollHandler = (_, __, ___) => const VideoPollResult(
          upstreamState: 'succeeded',
          localVideoPath: 'p/retry-legacy.mp4',
        );

    final retryId = await engine.retryJob(failedTaskId);
    final retry = jsonDecode(db.select(
        'SELECT relatedObjects FROM o_tasks WHERE id=?',
        [retryId]).single['relatedObjects'] as String) as Map;
    expect(retry['videoIds'], hasLength(1));
    await waitTask(retryId);

    expect(gateway.submitCount, 1);
    expect(gateway.pollCount, 1);
  });

  test('retry uncertain submission is refused before another paid request',
      () async {
    configureVideoModel();
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '不确定提交');
    writeMedia('p/retry-uncertain-frame.png');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/retry-uncertain-frame.png' WHERE id=?",
        [sbId]);
    final trackId = engine.ensureTrackForStoryboard(sbId);
    db.execute(
      "INSERT INTO o_video (projectId,scriptId,videoTrackId,state,submissionState) "
      "VALUES (?,?,?,?, 'uncertain')",
      [projectId, scriptId, trackId, vtFailed],
    );
    final videoId = db.lastInsertRowId;
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_generation',?,?)",
      [
        projectId,
        const EngineException(errNetwork).toReasonJson(),
        jsonEncode({
          'trackIds': [trackId],
          'videoIds': [videoId],
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;

    await expectLater(
      engine.retryJob(failedTaskId),
      throwsA(isA<EngineException>().having(
        (error) => error.errParams['reason'],
        'reason',
        'videoSubmissionUncertain',
      )),
    );

    expect(gateway.submitCount, 0);
    expect(db.select('SELECT id FROM o_tasks'), hasLength(1));
    expect(db.select('SELECT id FROM o_video'), hasLength(1));
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

  test('generateVideoPrompt 模型库显式绑定优先于能力模式模板', () async {
    db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'id': 'volcengine:test-video',
            'providerId': 'volcengine',
            'modelId': 'test-video',
            'label': 'Test Video',
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
                  'first_frame': 'video/fixed-mode.md',
                },
              },
            },
          },
        ]),
        'volcengine',
      ],
    );
    final explicit = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '用户显式绑定',
      prompt: '模型库显式视频模板',
    );
    await engine.bindModelPromptTemplate(
      'volcengine',
      'test-video',
      explicit.path,
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'volcengine',
        'test-video',
        'fixed-mode.md',
        'video/fixed-mode.md',
        '固定能力模式视频模板',
      ],
    );
    final sbId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '用户模板优先级测试',
    );

    String? seenSystem;
    gateway.textHandler = (system, user) {
      seenSystem = system;
      return 'local prompt only';
    };

    await engine.generateVideoPrompt(sbId);

    expect(
      seenSystem,
      '运镜提示词系统词\n\n视频视觉手册\n\n模型库显式视频模板',
    );
    expect(seenSystem, isNot(contains('固定能力模式视频模板')));
    expect(gateway.submitCount, 0);
    expect(gateway.pollCount, 0);
  });

  test('generateVideoPrompt 项目视频模型覆盖阶段默认并解析其显式模板', () async {
    db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          for (final modelId in ['stage-video', 'project-video'])
            {
              'id': 'volcengine:$modelId',
              'providerId': 'volcengine',
              'modelId': modelId,
              'label': modelId,
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
        'volcengine',
      ],
    );
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:stage-video')",
    );
    engine.editProject(
      projectId,
      videoModel: 'volcengine:project-video',
      videoRatio: '9:16',
    );
    final stageTemplate = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '阶段默认模板',
      prompt: 'STAGE VIDEO TEMPLATE',
    );
    final projectTemplate = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '项目覆盖模板',
      prompt: 'PROJECT VIDEO TEMPLATE',
    );
    await engine.bindModelPromptTemplate(
      'volcengine',
      'stage-video',
      stageTemplate.path,
    );
    await engine.bindModelPromptTemplate(
      'volcengine',
      'project-video',
      projectTemplate.path,
    );
    final sbId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '项目模型优先级测试',
    );

    String? seenSystem;
    gateway.textHandler = (system, user) {
      seenSystem = system;
      return 'project model prompt';
    };

    await engine.generateVideoPrompt(sbId);

    expect(seenSystem, contains('PROJECT VIDEO TEMPLATE'));
    expect(seenSystem, isNot(contains('STAGE VIDEO TEMPLATE')));
    expect(gateway.submitCount, 0);
    expect(gateway.pollCount, 0);
  });

  test('generateVideoPrompt 项目视频模型覆盖阶段默认并解析其旧版回退模板', () async {
    db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          for (final modelId in ['stage-legacy', 'project-legacy'])
            {
              'id': 'volcengine:$modelId',
              'providerId': 'volcengine',
              'modelId': modelId,
              'label': modelId,
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
        'volcengine',
      ],
    );
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','volcengine:stage-legacy')",
    );
    engine.editProject(
      projectId,
      videoModel: 'volcengine:project-legacy',
      videoRatio: '9:16',
    );
    for (final entry in const {
      'stage-legacy': 'STAGE LEGACY TEMPLATE',
      'project-legacy': 'PROJECT LEGACY TEMPLATE',
    }.entries) {
      db.execute(
        'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
        'VALUES (?,?,?,?,?)',
        [
          'volcengine',
          entry.key,
          'video_prompt_gen',
          'video_prompt_gen',
          entry.value,
        ],
      );
    }
    final sbId = engine.addStoryboard(
      projectId: projectId,
      scriptId: scriptId,
      prompt: '项目旧版模板优先级测试',
    );

    String? seenSystem;
    gateway.textHandler = (system, user) {
      seenSystem = system;
      return 'project legacy prompt';
    };

    await engine.generateVideoPrompt(sbId);

    expect(seenSystem, contains('PROJECT LEGACY TEMPLATE'));
    expect(seenSystem, isNot(contains('STAGE LEGACY TEMPLATE')));
    final trackId = engine.storyboards(scriptId).single.trackId!;
    final provenanceRaw = db.select(
      'SELECT promptProvenance FROM o_videoTrack WHERE id=?',
      [trackId],
    ).single['promptProvenance'] as String;
    final provenance = jsonDecode(provenanceRaw) as Map<String, dynamic>;
    final sources = (provenance['promptSources'] as List)
        .map((source) => Map<String, dynamic>.from(source as Map))
        .toList();
    expect(
        sources.map((source) => source['id']),
        contains(
          'model:volcengine:project-legacy:video_prompt_gen',
        ));
    expect(
        sources.map((source) => source['id']),
        isNot(contains(
          'model:volcengine:stage-legacy:video_prompt_gen',
        )));
    expect(gateway.submitCount, 0);
    expect(gateway.pollCount, 0);
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

  test('批量运镜提示词立即入队并保持视频生成状态不变', () {
    final first = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头一');
    final second = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '镜头二');

    final taskId = engine.batchGenerateVideoPrompts(projectId, [first, second]);

    final tracks = engine.storyboards(scriptId);
    final trackIds = [
      tracks.singleWhere((shot) => shot.id == first).trackId!,
      tracks.singleWhere((shot) => shot.id == second).trackId!,
    ];
    expect(taskId, greaterThan(0));
    expect(
      db.select('SELECT taskClass FROM o_tasks WHERE id=?', [taskId]).single[
          'taskClass'],
      'video_prompt_generation',
    );
    for (final trackId in trackIds) {
      final row = db.select(
          'SELECT state,promptState,promptErrorReason FROM o_videoTrack WHERE id=?',
          [trackId]).single;
      expect(row['state'], vtNotGenerated);
      expect(row['promptState'], '生成中');
      expect(row['promptErrorReason'], isNull);
    }
  });

  test('批量运镜提示词逐轨落成功或失败而不覆盖视频状态', () async {
    final good = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '成功镜头');
    final bad = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '失败镜头');
    gateway.textHandler = (_, user) {
      if (user.contains('失败镜头')) throw const EngineException(errNetwork);
      return 'dolly in';
    };

    final taskId = engine.batchGenerateVideoPrompts(projectId, [good, bad]);
    await waitTask(taskId);

    final goodTrackId = engine
        .storyboards(scriptId)
        .singleWhere((shot) => shot.id == good)
        .trackId!;
    final badTrackId = engine
        .storyboards(scriptId)
        .singleWhere((shot) => shot.id == bad)
        .trackId!;
    final goodTrack = engine.track(goodTrackId)!;
    final badTrack = engine.track(badTrackId)!;
    expect(goodTrack.prompt, 'dolly in');
    expect(goodTrack.promptState, videoPromptDone);
    expect(goodTrack.promptErrorReason, isNull);
    expect(goodTrack.promptTaskId, isNull);
    expect(goodTrack.state, vtNotGenerated);
    expect(badTrack.promptState, videoPromptFailed);
    expect(
      EngineException.fromReasonJson(badTrack.promptErrorReason)?.errKey,
      errNetwork,
    );
    expect(badTrack.promptTaskId, isNull);
    expect(badTrack.state, vtNotGenerated);
  });

  test('取消批量运镜提示词会关闭仍在生成的提示词状态', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '待取消镜头');
    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);

    await engine.cancelJob(taskId);

    final trackId = engine.storyboards(scriptId).single.trackId!;
    final track = engine.track(trackId)!;
    expect(track.promptState, videoPromptFailed);
    expect(
      EngineException.fromReasonJson(track.promptErrorReason)?.errKey,
      errCanceled,
    );
    expect(track.promptTaskId, isNull);
    expect(track.state, vtNotGenerated);
  });

  test('已取消的运镜提示词不能被迟到回包覆写', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '迟到回包镜头');
    final started = Completer<void>();
    final response = Completer<String>();
    gateway.textHandler = (_, __) {
      started.complete();
      return response.future;
    };

    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);
    await started.future;
    await engine.cancelJob(taskId);
    response.complete('不应写入的提示词');
    await waitTask(taskId, expectState: 'failed');

    final trackId = engine.storyboards(scriptId).single.trackId!;
    final track = engine.track(trackId)!;
    expect(track.prompt, isNull);
    expect(track.promptState, videoPromptFailed);
    expect(
      EngineException.fromReasonJson(track.promptErrorReason)?.errKey,
      errCanceled,
    );
  });

  test('用户编辑提示词后批量任务的迟到回包不能覆盖编辑', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '手动编辑优先');
    final started = Completer<void>();
    final response = Completer<String>();
    gateway.textHandler = (_, __) {
      started.complete();
      return response.future;
    };

    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);
    await started.future;
    final trackId = engine.storyboards(scriptId).single.trackId!;
    engine.updateVideoPrompt(trackId, '用户手动编辑');
    response.complete('不应覆盖用户编辑的旧回包');
    await waitTask(taskId, expectState: 'failed');

    final track = engine.track(trackId)!;
    expect(track.prompt, '用户手动编辑');
    expect(track.promptState, videoPromptDone);
    expect(track.promptErrorReason, isNull);
    expect(track.promptTaskId, isNull);
  });

  test('单镜提示词请求会取代正在运行的批量请求', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '单镜请求优先');
    final started = Completer<void>();
    final oldResponse = Completer<String>();
    var calls = 0;
    gateway.textHandler = (_, __) {
      calls++;
      if (calls == 1) {
        started.complete();
        return oldResponse.future;
      }
      return '单镜的新提示词';
    };

    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);
    await started.future;
    expect(await engine.generateVideoPrompt(storyboardId), '单镜的新提示词');
    oldResponse.complete('旧批量回包');
    await waitTask(taskId, expectState: 'failed');

    final track = engine.track(engine.storyboards(scriptId).single.trackId!)!;
    expect(track.prompt, '单镜的新提示词');
    expect(track.promptState, videoPromptDone);
    expect(track.promptTaskId, isNull);
  });

  test('单镜提示词正在生成时拒绝把同一轨道加入批量任务', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '单镜先开始');
    final started = Completer<void>();
    final response = Completer<String>();
    gateway.textHandler = (_, __) {
      started.complete();
      return response.future;
    };

    final single = engine.generateVideoPrompt(storyboardId);
    await started.future;
    expect(
      () => engine.batchGenerateVideoPrompts(projectId, [storyboardId]),
      throwsA(
        isA<EngineException>().having(
          (error) => error.errKey,
          'errKey',
          errTaskActive,
        ),
      ),
    );
    response.complete('单镜完成');
    expect(await single, '单镜完成');

    final track = engine.track(engine.storyboards(scriptId).single.trackId!)!;
    expect(track.prompt, '单镜完成');
    expect(track.promptState, videoPromptDone);
    expect(track.promptTaskId, isNull);
    expect(
      db
          .select(
              "SELECT id FROM o_tasks WHERE taskClass='video_prompt_generation'")
          .length,
      0,
    );
  });

  test('同一轨道已有活跃提示词任务时拒绝重复入队', () {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '禁止重复收费');
    engine.batchGenerateVideoPrompts(projectId, [storyboardId]);

    expect(
      () => engine.batchGenerateVideoPrompts(projectId, [storyboardId]),
      throwsA(
        isA<EngineException>().having(
          (error) => error.errKey,
          'errKey',
          errTaskActive,
        ),
      ),
    );
    expect(
      db
          .select(
              "SELECT id FROM o_tasks WHERE taskClass='video_prompt_generation'")
          .length,
      1,
    );
  });

  test('重试失败的批量运镜提示词任务会重新取得轨道归属', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '重试运镜提示词');
    final trackId = engine.ensureTrackForStoryboard(storyboardId);
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass,reason,relatedObjects) "
      "VALUES (?,'failed','video_prompt_generation',?,?)",
      [
        projectId,
        const EngineException(errNetwork).toReasonJson(),
        jsonEncode({
          'kind': 'videoTrack',
          'storyboardIds': [storyboardId],
          'trackIds': [trackId],
          'concurrentCount': 1,
        }),
      ],
    );
    final failedTaskId = db.lastInsertRowId;
    db.execute(
      'UPDATE o_videoTrack SET promptState=?,promptErrorReason=?,promptTaskId=NULL '
      'WHERE id=?',
      [
        videoPromptFailed,
        const EngineException(errNetwork).toReasonJson(),
        trackId,
      ],
    );
    gateway.textHandler = (_, __) => '重试后的提示词';

    final retryId = await engine.retryJob(failedTaskId);

    final queued = engine.track(trackId)!;
    expect(queued.promptState, videoPromptGenerating);
    expect(queued.promptTaskId, retryId);
    await waitTask(retryId);
    final completed = engine.track(trackId)!;
    expect(completed.prompt, '重试后的提示词');
    expect(completed.promptState, videoPromptDone);
    expect(completed.promptTaskId, isNull);
  });

  test('冷启动恢复会清理单镜遗留的提示词所有权', () {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '单镜重启恢复');
    final trackId = engine.ensureTrackForStoryboard(storyboardId);
    db.execute(
      'UPDATE o_videoTrack SET promptState=?,promptErrorReason=NULL,promptTaskId=? '
      'WHERE id=?',
      [videoPromptGenerating, -1, trackId],
    );

    engine.recoverOrphanedManualVideoPrompts();

    final track = engine.track(trackId)!;
    expect(track.promptState, videoPromptFailed);
    expect(
      EngineException.fromReasonJson(track.promptErrorReason)?.errKey,
      errAppRestart,
    );
    expect(track.promptTaskId, isNull);
  });

  test('单镜提示词失败会清理自身所有权', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '单镜失败解锁');
    gateway.textHandler = (_, __) => throw const EngineException(errNetwork);

    await expectLater(
      engine.generateVideoPrompt(storyboardId),
      throwsA(isA<EngineException>()),
    );

    final trackId = engine.storyboards(scriptId).single.trackId!;
    final track = engine.track(trackId)!;
    expect(track.promptState, videoPromptFailed);
    expect(
      EngineException.fromReasonJson(track.promptErrorReason)?.errKey,
      errNetwork,
    );
    expect(track.promptTaskId, isNull);
    expect(engine.batchGenerateVideoPrompts(projectId, [storyboardId]),
        greaterThan(0));
  });

  test('批量提示词的任务插入和轨道归属更新在同一事务内', () {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '事务原子性');
    final trackId = engine.ensureTrackForStoryboard(storyboardId);
    db.execute('''
CREATE TRIGGER reject_prompt_task_owner
BEFORE UPDATE OF promptTaskId ON o_videoTrack
WHEN NEW.promptTaskId IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'test rollback');
END;
''');

    expect(
      () => engine.batchGenerateVideoPrompts(projectId, [storyboardId]),
      throwsA(isA<SqliteException>()),
    );

    expect(
      db
          .select(
              "SELECT id FROM o_tasks WHERE taskClass='video_prompt_generation'")
          .length,
      0,
    );
    expect(engine.track(trackId)!.promptTaskId, isNull);
  });

  test('清空轨道会使尚未执行的提示词任务失效且不重建轨道', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '清空中的镜头');
    var calls = 0;
    gateway.textHandler = (_, __) {
      calls++;
      return '不应请求';
    };
    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);
    final trackId = engine.storyboards(scriptId).single.trackId!;

    engine.deleteVideoTrack(trackId);
    await waitTask(taskId, expectState: 'failed');

    expect(calls, 0);
    expect(engine.storyboards(scriptId).single.trackId, isNull);
    expect(engine.track(trackId), isNull);
  });

  test('清空正在等待回包的轨道不会被旧任务复活', () async {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '回包途中清空');
    final started = Completer<void>();
    final response = Completer<String>();
    gateway.textHandler = (_, __) {
      started.complete();
      return response.future;
    };
    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);
    await started.future;
    final trackId = engine.storyboards(scriptId).single.trackId!;

    engine.deleteVideoTrack(trackId);
    response.complete('旧任务不能复活轨道');
    await waitTask(taskId, expectState: 'failed');

    expect(engine.storyboards(scriptId).single.trackId, isNull);
    expect(engine.track(trackId), isNull);
    expect(db.select('SELECT id FROM o_videoTrack'), isEmpty);
  });

  test('冷启动恢复会终结遗留的运镜提示词生成状态', () {
    final storyboardId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: '重启恢复镜头');
    final taskId = engine.batchGenerateVideoPrompts(projectId, [storyboardId]);
    final trackId = engine.storyboards(scriptId).single.trackId!;
    db.execute("UPDATE o_tasks SET state='processing' WHERE id=?", [taskId]);

    engine.queue.recoverOnColdStart();

    expect(
      db.select(
          'SELECT state FROM o_tasks WHERE id=?', [taskId]).single['state'],
      'failed',
    );
    final track = engine.track(trackId)!;
    expect(track.promptState, videoPromptFailed);
    expect(
      EngineException.fromReasonJson(track.promptErrorReason)?.errKey,
      errAppRestart,
    );
    expect(track.promptTaskId, isNull);
    expect(track.state, vtNotGenerated);
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

  test('生成任务处理前轨道被删除，不能被静默判定为成功', () async {
    final sbId = engine.addStoryboard(
        projectId: projectId, scriptId: scriptId, prompt: 'x');
    db.execute(
        "UPDATE o_storyboard SET filePath='p/frame.png' WHERE id=?", [sbId]);
    writeMedia('p/frame.png');
    final trackId = engine.ensureTrackForStoryboard(sbId);

    final taskId = engine.batchGenerateVideos(projectId, [sbId]);
    // 队列 tick 有 10ms 延迟；本行与上一行之间没有任何 await，保证在 worker
    // 处理这条候选之前同步删除轨道，复现"生成中被删除 → worker 发现候选行
    // 已不存在只 continue（既不计入 success 也不计入 firstFailure）→
    // success==0 且 firstFailure==null → 函数正常返回 → 任务被静默判定
    // 为完成"。
    engine.deleteVideoTrack(trackId);

    await waitTask(taskId, expectState: 'failed');

    final reason = db
        .select('SELECT reason FROM o_tasks WHERE id=?', [taskId])
        .single['reason'] as String?;
    expect(
      EngineException.fromReasonJson(reason)?.errKey,
      errVideoTargetDeleted,
    );
    expect(gateway.submitCount, 0,
        reason: '目标在 worker 处理前已被删除，不应该真的去调用上游生成');
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

  test('exportVideoCandidatesToFile 只打包选中的已完成本地候选', () async {
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    const readyRel = 'p/export-ready.mp4';
    const missingRel = 'p/export-missing.mp4';
    File(engine.mediaAbsPath(readyRel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, readyRel, vtDone],
    );
    final readyId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, missingRel, vtDone],
    );
    final missingId = db.lastInsertRowId;
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, 'p/running.mp4', vtGenerating],
    );
    final runningId = db.lastInsertRowId;

    final target = p.join(dir.path, 'candidate-videos.zip');
    expect(
        engine.videoCandidateExportFileCount({readyId, missingId, runningId}),
        1);
    final count = await engine.exportVideoCandidatesToFile(
      {readyId, missingId, runningId},
      target,
    );

    expect(count, 1);
    final archive = ZipDecoder().decodeBytes(File(target).readAsBytesSync());
    expect(archive.files, hasLength(1));
    expect(archive.files.single.name, '候选视频$readyId.mp4');
    expect(archive.files.single.content, [1, 2, 3, 4]);
  });

  test('候选视频导出拒绝媒体目录外的路径，单文件导出也不创建目标', () async {
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    final outside = File(p.join(dir.path, 'outside', 'secret.mp4'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9, 9, 9]);
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, outside.path, vtDone],
    );
    final unsafeId = db.lastInsertRowId;

    final zipTarget = p.join(dir.path, 'unsafe-candidates.zip');
    final fileTarget = p.join(dir.path, 'unsafe-candidate.mp4');
    expect(engine.videoCandidateExportFileCount({unsafeId}), 0);
    expect(await engine.exportVideoCandidatesToFile({unsafeId}, zipTarget), 0);
    expect(File(zipTarget).existsSync(), isFalse);
    expect(
        await engine.exportVideoCandidateToFile(unsafeId, fileTarget), isFalse);
    expect(File(fileTarget).existsSync(), isFalse);
  });

  test('exportVideoCandidateToFile 将已完成候选复制到用户选择的位置', () async {
    final trackId = engine.createStandaloneVideoTrack(
      projectId: projectId,
      scriptId: scriptId,
      duration: 5,
    );
    const rel = 'p/export-single.mp4';
    File(engine.mediaAbsPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([8, 6, 7, 5]);
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state) '
      'VALUES (?,?,?,?,?)',
      [projectId, scriptId, trackId, rel, vtDone],
    );
    final videoId = db.lastInsertRowId;

    final target = p.join(dir.path, 'exports', 'candidate.mp4');
    expect(await engine.exportVideoCandidateToFile(videoId, target), isTrue);
    expect(File(target).readAsBytesSync(), [8, 6, 7, 5]);
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
  FutureOr<String> Function(String system, String user)? textHandler;
  String Function(String prompt, String referencePath, String projectId)?
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
    return TextResult(await textHandler!(system, user));
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
