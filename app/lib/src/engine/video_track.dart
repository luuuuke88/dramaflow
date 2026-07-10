// 多轨工作台（视频生成/挑选）：契约照抄 ToonFlow /api/production/workbench/*
// （详见 docs/reference/p4-workbench-brief.md §1/§2）。
// 数据模型澄清：o_videoTrack = 一个分镜的视频槽位（与 o_storyboard.trackId 一一对应，
// 与 P3 分镜=图片槽位同构）；o_video = 该槽位下的候选生成结果；
// selectVideoId = 用户选中的候选（videoId 字段保持同步写入，避免死字段）。
// 状态枚举为 DB 中文字符串（逐字）：未生成/生成中/已完成/生成失败。
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' show Row;

import 'assets.dart';
import 'engine.dart';
import 'errors.dart';
import 'events.dart' show stripThink;
import 'prompt_resolver.dart';
import 'queue.dart';

const vtNotGenerated = '未生成';
const vtGenerating = '生成中';
const vtDone = '已完成';
const vtFailed = '生成失败';

class VideoRow {
  final int id;
  final int videoTrackId;
  final String? filePath;
  final String? state;
  final String? errorReason;
  final int? time;
  const VideoRow({
    required this.id,
    required this.videoTrackId,
    required this.filePath,
    required this.state,
    required this.errorReason,
    required this.time,
  });
}

class VideoTrackRow {
  final int id;
  final int projectId;
  final int scriptId;
  final String? prompt;
  final String? reason;
  final String? state;
  final int? duration;
  final String? transition;
  final String? filter;
  final int? selectVideoId;
  final List<VideoRow> candidates;
  const VideoTrackRow({
    required this.id,
    required this.projectId,
    required this.scriptId,
    required this.prompt,
    required this.reason,
    required this.state,
    required this.duration,
    required this.transition,
    required this.filter,
    required this.selectVideoId,
    required this.candidates,
  });
}

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

extension VideoTrackApi on Engine {
  void installVideoTrackPipeline() {
    taskRunners['video_generation'] = _runVideoGeneration;
    queue.registerRecover('video_generation', _recoverVideoGeneration);
  }

  /// 懒建分镜对应的视频轨（trackId 未建时新建并回填 o_storyboard.trackId）。
  int ensureTrackForStoryboard(int storyboardId) {
    final row = db.select(
        'SELECT trackId,projectId,scriptId FROM o_storyboard WHERE id=?',
        [storyboardId]).firstOrNull;
    if (row == null) {
      throw EngineException(errPromptMissing, {'type': 'storyboard'});
    }
    final existing = row['trackId'] as int?;
    if (existing != null) return existing;
    db.execute(
      'INSERT INTO o_videoTrack (projectId,scriptId,state) VALUES (?,?,?)',
      [row['projectId'], row['scriptId'], vtNotGenerated],
    );
    final trackId = db.lastInsertRowId;
    db.execute('UPDATE o_storyboard SET trackId=? WHERE id=?',
        [trackId, storyboardId]);
    return trackId;
  }

  VideoTrackRow? track(int trackId) {
    final row = db
        .select('SELECT * FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
    if (row == null) return null;
    return _trackFromRow(row);
  }

  VideoTrackRow _trackFromRow(Row row) {
    final candidates = db
        .select('SELECT * FROM o_video WHERE videoTrackId=? ORDER BY id',
            [row['id']])
        .map((r) => VideoRow(
              id: r['id'] as int,
              videoTrackId: (r['videoTrackId'] as int?) ?? 0,
              filePath: r['filePath'] as String?,
              state: r['state'] as String?,
              errorReason: r['errorReason'] as String?,
              time: r['time'] as int?,
            ))
        .toList();
    return VideoTrackRow(
      id: row['id'] as int,
      projectId: (row['projectId'] as int?) ?? 0,
      scriptId: (row['scriptId'] as int?) ?? 0,
      prompt: row['prompt'] as String?,
      reason: row['reason'] as String?,
      state: row['state'] as String?,
      duration: row['duration'] as int?,
      transition: row['transition'] as String?,
      filter: row['filterPreset'] as String?,
      selectVideoId: row['selectVideoId'] as int?,
      candidates: candidates,
    );
  }

  /// 同步生成运镜提示词（text 调用，非队列——与资产提示词润色同步语义一致）。
  /// 用户消息在画面描述/运镜说明之外，附带本分镜关联资产名称与时长做适度增强
  /// （o_assets2Storyboard→o_assets 取名字），让 LLM 知道镜头里有哪些角色/场景/道具、
  /// 该镜多长，产出更贴合的运镜词；不做过度堆料（只带名称，不带长描述与图片）。
  Future<String> generateVideoPrompt(int storyboardId) async {
    final sb = db.select(
        'SELECT projectId,prompt,videoDesc,duration '
        'FROM o_storyboard WHERE id=?',
        [storyboardId]).firstOrNull;
    if (sb == null) {
      throw EngineException(errPromptMissing, {'type': 'storyboard'});
    }
    final trackId = ensureTrackForStoryboard(storyboardId);
    final assetNames = db
        .select(
          'SELECT a.name name FROM o_assets2Storyboard l '
          'JOIN o_assets a ON a.id=l.assetId '
          'WHERE l.storyboardId=? ORDER BY l.rowid',
          [storyboardId],
        )
        .map((r) => (r['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final trackDuration = (db.select(
        'SELECT duration FROM o_videoTrack WHERE id=?',
        [trackId]).firstOrNull?['duration'] as int?);
    // 时长优先取视频轨（用户手动编辑过的更权威），回退分镜时长文本。
    final durationText = trackDuration != null
        ? '$trackDuration'
        : (sb['duration'] as String?) ?? '';
    final resolution = resolvePrompt(
      projectId: (sb['projectId'] as int?) ?? 0,
      basePromptKey: 'video_prompt_gen',
      visualSection: 'art_storyboard_video',
      modelStage: 'shot_video',
    );
    final genericPrompt = await getPrompt('video_prompt_gen');
    final legacyModelPrompt =
        await getPromptForStageModel('video_prompt_gen', 'shot_video');
    final system = legacyModelPrompt == genericPrompt
        ? resolution.system
        : [
            legacyModelPrompt,
            ...resolution.sources
                .where((source) => source.kind != 'base')
                .map((source) => source.content),
          ].where((content) => content.trim().isNotEmpty).join('\n\n');
    final user = StringBuffer()
      ..writeln('画面描述：${sb['prompt'] ?? ''}')
      ..writeln('运镜/动作说明：${sb['videoDesc'] ?? ''}');
    if (assetNames.isNotEmpty) {
      user.writeln('关联资产：${assetNames.join('、')}');
    }
    if (durationText.isNotEmpty) {
      user.writeln('镜头时长（秒）：$durationText');
    }
    final res = await gateway.generateText(system, user.toString().trimRight(),
        stage: 'video_prompt_gen');
    final text = stripThink(res.content);
    db.execute('UPDATE o_videoTrack SET prompt=? WHERE id=?', [text, trackId]);
    return text;
  }

  /// 手动编辑运镜提示词（覆盖写入 o_videoTrack.prompt）。
  void updateVideoPrompt(int trackId, String text) {
    db.execute('UPDATE o_videoTrack SET prompt=? WHERE id=?', [text, trackId]);
  }

  /// 编辑本镜时长（秒；写入 o_videoTrack.duration）。null 或非正值视为清空。
  void updateVideoDuration(int trackId, int? seconds) {
    final v = (seconds != null && seconds > 0) ? seconds : null;
    db.execute('UPDATE o_videoTrack SET duration=? WHERE id=?', [v, trackId]);
  }

  /// 编辑本镜转场预设。null/空字符串清空，具体渲染由 composer 平台实现解释。
  void updateVideoTransition(int trackId, String? transition) {
    db.execute('UPDATE o_videoTrack SET transition=? WHERE id=?',
        [_nleValue(transition), trackId]);
  }

  /// 编辑本镜滤镜预设。null/空字符串清空，具体渲染由 composer 平台实现解释。
  void updateVideoFilter(int trackId, String? filter) {
    db.execute('UPDATE o_videoTrack SET filterPreset=? WHERE id=?',
        [_nleValue(filter), trackId]);
  }

  /// 批量生成（队列任务，video lane，cap=1；任务内并发由 concurrentCount 控制，
  /// 与图片生成同一模式）。
  int batchGenerateVideos(int projectId, List<int> storyboardIds,
      {int concurrentCount = 2}) {
    if (storyboardIds.isEmpty) return 0;
    final trackIds = [
      for (final sbId in storyboardIds) ensureTrackForStoryboard(sbId),
    ];
    db.execute(
      'UPDATE o_videoTrack SET state=? WHERE id IN (${_ph(trackIds)})',
      [vtGenerating, ...trackIds],
    );
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'video_generation',
      describe: '视频生成',
      relatedObjects: {
        'kind': 'videoTrack',
        'trackIds': trackIds,
        'concurrentCount': concurrentCount,
      },
    );
  }

  Future<void> _runVideoGeneration(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final trackIds = (related['trackIds'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 2).clamp(1, 8);
    final projectId = task.projectId ?? 0;

    var success = 0;
    EngineException? firstFailure;
    var cursor = 0;

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= trackIds.length) return;
        final trackId = trackIds[i];
        final trackRow = db.select(
            'SELECT * FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
        if (trackRow == null) continue;
        final storyboard = db.select(
            'SELECT filePath,prompt FROM o_storyboard WHERE trackId=?',
            [trackId]).firstOrNull;
        final firstFrame = storyboard?['filePath'] as String?;
        if (firstFrame == null || firstFrame.isEmpty) {
          final ex = EngineException(errPromptMissing, {'type': 'firstFrame'});
          firstFailure ??= ex;
          db.execute('UPDATE o_videoTrack SET state=?, reason=? WHERE id=?',
              [vtFailed, ex.toReasonJson(), trackId]);
          continue;
        }
        db.execute(
          'INSERT INTO o_video (projectId,scriptId,videoTrackId,state,time) '
          'VALUES (?,?,?,?,?)',
          [
            projectId,
            trackRow['scriptId'],
            trackId,
            vtGenerating,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        final videoId = db.lastInsertRowId;
        try {
          final prompt = (trackRow['prompt'] as String?)?.isNotEmpty == true
              ? trackRow['prompt'] as String
              : (storyboard?['prompt'] as String? ?? '');
          final rel = await gateway.generateVideo(
            prompt,
            media.absPath(firstFrame),
            '$projectId',
            stage: 'shot_video',
            cancelToken: token,
          );
          db.execute(
            'UPDATE o_video SET state=?, filePath=? WHERE id=?',
            [vtDone, rel, videoId],
          );
          // 首个候选自动选中（无选择时，减少摩擦；见 P4 参照 §2）
          final hasSelection = db.select(
                  'SELECT selectVideoId FROM o_videoTrack WHERE id=?',
                  [trackId]).first['selectVideoId'] !=
              null;
          db.execute(
            'UPDATE o_videoTrack SET state=?, reason=NULL'
            '${hasSelection ? '' : ', selectVideoId=?, videoId=?'} WHERE id=?',
            hasSelection
                ? [vtDone, trackId]
                : [vtDone, videoId, videoId, trackId],
          );
          success++;
        } catch (e) {
          if (token.isCancelled) return;
          final ex = e is EngineException
              ? e
              : (e is DioException
                  ? EngineException(errNetwork, {'message': e.message})
                  : EngineException(errLlmFormat, {'message': '$e'}));
          firstFailure ??= ex;
          db.execute('UPDATE o_video SET state=?, errorReason=? WHERE id=?',
              [vtFailed, ex.toReasonJson(), videoId]);
          db.execute('UPDATE o_videoTrack SET state=?, reason=? WHERE id=?',
              [vtFailed, ex.toReasonJson(), trackId]);
        }
      }
    }

    await Future.wait(
        [for (var w = 0; w < min(concurrent, trackIds.length); w++) worker()]);
    if (token.isCancelled) throw const EngineException(errCanceled);
    if (success == 0 && firstFailure != null) throw firstFailure!;
  }

  void _recoverVideoGeneration(TasksRow task) {
    final trackIds = (task.relatedObjectsJson['trackIds'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (trackIds.isEmpty) return;
    final reason = const EngineException(errAppRestart).toReasonJson();
    db.execute(
      'UPDATE o_videoTrack SET state=?, reason=? '
      'WHERE id IN (${_ph(trackIds)}) AND state=?',
      [vtFailed, reason, ...trackIds, vtGenerating],
    );
    db.execute(
      'UPDATE o_video SET state=?, errorReason=? '
      'WHERE videoTrackId IN (${_ph(trackIds)}) AND state=?',
      [vtFailed, reason, ...trackIds, vtGenerating],
    );
  }

  /// 选择候选视频（更新 selectVideoId，videoId 同步写入避免死字段）。
  void selectVideo(int trackId, int videoId) {
    db.execute(
      'UPDATE o_videoTrack SET selectVideoId=?, videoId=? WHERE id=?',
      [videoId, videoId, trackId],
    );
  }

  /// 从素材库 clip 复用一个本地视频作为当前轨道候选，并立即选为正片。
  int attachClipToTrack(int trackId, int clipAssetId) {
    final trackRow = db
        .select('SELECT * FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
    if (trackRow == null) {
      throw EngineException(errPromptMissing, {'type': 'videoTrack'});
    }
    final clipRow = db.select(
      'SELECT a.type type, i.filePath filePath '
      'FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId '
      'WHERE a.id=? AND a.projectId=?',
      [clipAssetId, trackRow['projectId']],
    ).firstOrNull;
    final rel = clipRow?['filePath'] as String?;
    if (clipRow == null ||
        clipRow['type'] != 'clip' ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'clip'});
    }
    db.execute(
      'INSERT INTO o_video (projectId,scriptId,videoTrackId,filePath,state,time) '
      'VALUES (?,?,?,?,?,?)',
      [
        trackRow['projectId'],
        trackRow['scriptId'],
        trackId,
        rel,
        vtDone,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final videoId = db.lastInsertRowId;
    db.execute(
      'UPDATE o_videoTrack SET state=?, reason=NULL, selectVideoId=?, videoId=? '
      'WHERE id=?',
      [vtDone, videoId, videoId, trackId],
    );
    return videoId;
  }

  /// 将某个工作台候选视频登记回素材库 clip，便于其他镜头复用。
  int saveVideoCandidateAsClip(int videoId, {String? name}) {
    final row = db.select(
      'SELECT projectId,filePath FROM o_video WHERE id=? AND state=?',
      [videoId, vtDone],
    ).firstOrNull;
    final rel = row?['filePath'] as String?;
    if (row == null ||
        rel == null ||
        rel.isEmpty ||
        !File(media.absPath(rel)).existsSync()) {
      throw const EngineException(errFileType, {'type': 'video'});
    }
    return registerClipAsset(
      projectId: (row['projectId'] as int?) ?? 0,
      name: name?.trim().isNotEmpty == true ? name!.trim() : '镜头候选 #$videoId',
      relPath: rel,
    );
  }

  void deleteVideo(int videoId) {
    final row = db.select(
        'SELECT videoTrackId,filePath FROM o_video WHERE id=?',
        [videoId]).firstOrNull;
    if (row == null) return;
    // 先删磁盘文件再删行（此前只删行，泄漏了候选视频 .mp4）。
    final rel = row['filePath'] as String?;
    if (rel != null && rel.isNotEmpty) {
      final stillReferencedByAsset = db.select(
          'SELECT id FROM o_image WHERE filePath=? LIMIT 1', [rel]).isNotEmpty;
      if (!stillReferencedByAsset) {
        final file = File(media.absPath(rel));
        if (file.existsSync()) file.deleteSync();
      }
    }
    db.execute(
      'UPDATE o_videoTrack SET selectVideoId=NULL, videoId=NULL '
      'WHERE id=? AND (selectVideoId=? OR videoId=?)',
      [row['videoTrackId'], videoId, videoId],
    );
    db.execute('DELETE FROM o_video WHERE id=?', [videoId]);
  }

  /// 删除整条视频轨：保留分镜行本身，但清空 storyboard.trackId，并删除该轨道
  /// 下所有候选视频。候选文件删除沿用 deleteVideo 的素材库引用保护逻辑。
  void deleteVideoTrack(int trackId) {
    final row = db.select(
        'SELECT id FROM o_videoTrack WHERE id=?', [trackId]).firstOrNull;
    if (row == null) return;
    final videoIds = db
        .select('SELECT id FROM o_video WHERE videoTrackId=? ORDER BY id',
            [trackId])
        .map((r) => r['id'] as int)
        .toList();
    for (final videoId in videoIds) {
      deleteVideo(videoId);
    }
    db.execute(
        'UPDATE o_storyboard SET trackId=NULL WHERE trackId=?', [trackId]);
    db.execute('DELETE FROM o_videoTrack WHERE id=?', [trackId]);
  }
}

String? _nleValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
