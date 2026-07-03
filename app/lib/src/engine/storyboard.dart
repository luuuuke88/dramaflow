// 分镜模块：契约照抄 ToonFlow /api/production/storyboard/*
// （详见 docs/reference/p3-production-canvas-brief.md §2）。
// 状态枚举为 DB 中文字符串（逐字）：未生成/生成中/已完成/生成失败。
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' show Row;

import 'engine.dart';
import 'errors.dart';
import 'queue.dart';

const sbNotGenerated = '未生成';
const sbGenerating = '生成中';
const sbDone = '已完成';
const sbFailed = '生成失败';

class StoryboardRow {
  final int id;
  final int projectId;
  final int scriptId;
  final int index;
  final String? duration;
  final String? prompt;
  final String? videoDesc;
  final String? filePath;
  final int? audioAssetId;
  final String? audioText;
  final String? audioPath;
  final String? audioState;
  final String? audioError;
  final String? state;
  final String? reason;
  final int shouldGenerateImage;
  final String? track;
  final int? trackId;
  final int? flowId;
  final List<int> assetIds;

  const StoryboardRow({
    required this.id,
    required this.projectId,
    required this.scriptId,
    required this.index,
    required this.duration,
    required this.prompt,
    required this.videoDesc,
    required this.filePath,
    required this.audioAssetId,
    required this.audioText,
    required this.audioPath,
    required this.audioState,
    required this.audioError,
    required this.state,
    required this.reason,
    required this.shouldGenerateImage,
    required this.track,
    required this.trackId,
    required this.flowId,
    required this.assetIds,
  });
}

/// resultTool schema：剧本 → 分镜列表（照抄 batchAddStoryboardInfo 语义）。
const storyboardListToolSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'shots': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'prompt': {'type': 'string'},
          'videoDesc': {'type': 'string'},
          'duration': {'type': 'string'},
          'track': {'type': 'string'},
          'assetNames': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['prompt'],
      },
    },
  },
  'required': ['shots'],
};

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

bool _sameOrder(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

extension StoryboardApi on Engine {
  void installStoryboardPipeline() {
    taskRunners['storyboard_generate'] = _runStoryboardGenerate;
    taskRunners['storyboard_image_generation'] = _runStoryboardImage;
    queue.registerRecover('storyboard_generate', _recoverStoryboardGenerate);
    queue.registerRecover(
        'storyboard_image_generation', _recoverStoryboardImage);
  }

  StoryboardRow _fromRow(Row r, List<int> assetIds) => StoryboardRow(
        id: r['id'] as int,
        projectId: (r['projectId'] as int?) ?? 0,
        scriptId: (r['scriptId'] as int?) ?? 0,
        index: (r['index'] as int?) ?? 0,
        duration: r['duration'] as String?,
        prompt: r['prompt'] as String?,
        videoDesc: r['videoDesc'] as String?,
        filePath: r['filePath'] as String?,
        audioAssetId: r['audioAssetId'] as int?,
        audioText: r['audioText'] as String?,
        audioPath: r['audioPath'] as String?,
        audioState: r['audioState'] as String?,
        audioError: r['audioError'] as String?,
        state: r['state'] as String?,
        reason: r['reason'] as String?,
        shouldGenerateImage: (r['shouldGenerateImage'] as int?) ?? 1,
        track: r['track'] as String?,
        trackId: r['trackId'] as int?,
        flowId: r['flowId'] as int?,
        assetIds: assetIds,
      );

  /// 有序返回已生成首帧图的分镜（1 基镜头序号 + 图片绝对路径），用于整屏预览/批量导出。
  /// 未生成图片的分镜不返回；序号按当前分镜顺序（`index` 升序）连续编号。
  List<({int shotNumber, String absPath})> storyboardImagePaths(int scriptId) {
    final rows = storyboards(scriptId);
    final out = <({int shotNumber, String absPath})>[];
    for (final (i, r) in rows.indexed) {
      final rel = r.filePath;
      if (rel == null || rel.isEmpty) continue;
      out.add((shotNumber: i + 1, absPath: media.absPath(rel)));
    }
    return out;
  }

  List<StoryboardRow> storyboards(int scriptId) {
    final rows = db.select(
      'SELECT * FROM o_storyboard WHERE scriptId=? ORDER BY "index" ASC',
      [scriptId],
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final links = db.select(
      'SELECT storyboardId,assetId FROM o_assets2Storyboard '
      'WHERE storyboardId IN (${_ph(ids)})',
      ids,
    );
    final byStoryboard = <int, List<int>>{};
    for (final l in links) {
      byStoryboard
          .putIfAbsent(l['storyboardId'] as int, () => [])
          .add(l['assetId'] as int);
    }
    return [
      for (final r in rows)
        _fromRow(r, byStoryboard[r['id'] as int] ?? const []),
    ];
  }

  /// 插入单个分镜（照抄 addStoryboard；index 未传时追加到末尾）。
  int addStoryboard({
    required int projectId,
    required int scriptId,
    String prompt = '',
    String? videoDesc,
    String? duration,
    int? insertAfterIndex,
    List<int> assetIds = const [],
  }) {
    final maxIndex = (db.select(
            'SELECT MAX("index") m FROM o_storyboard WHERE scriptId=?',
            [scriptId]).first['m'] as int?) ??
        0;
    final index =
        insertAfterIndex == null ? maxIndex + 1 : insertAfterIndex + 1;
    if (insertAfterIndex != null) {
      db.execute(
        'UPDATE o_storyboard SET "index"="index"+1 '
        'WHERE scriptId=? AND "index">?',
        [scriptId, insertAfterIndex],
      );
    }
    db.execute(
      'INSERT INTO o_storyboard '
      '(projectId,scriptId,"index",prompt,videoDesc,duration,state,'
      'shouldGenerateImage,createTime) VALUES (?,?,?,?,?,?,?,1,?)',
      [
        projectId,
        scriptId,
        index,
        prompt,
        videoDesc,
        duration,
        sbNotGenerated,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final id = db.lastInsertRowId;
    for (final assetId in assetIds) {
      db.execute(
        'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
        [assetId, id],
      );
    }
    return id;
  }

  /// 图片编辑器"保存"应用到分镜：直接写入生成结果（不经批量生图队列）。
  void setStoryboardImage(int id, String rel, {int? flowId}) {
    db.execute(
      'UPDATE o_storyboard SET filePath=?, state=?, reason=NULL'
      '${flowId != null ? ', flowId=?' : ''} WHERE id=?',
      flowId != null ? [rel, sbDone, flowId, id] : [rel, sbDone, id],
    );
  }

  void editStoryboard(int id,
      {String? prompt, String? videoDesc, String? duration}) {
    final sets = <String>[];
    final args = <Object?>[];
    void set(String col, Object? v) {
      if (v == null) return;
      sets.add('$col=?');
      args.add(v);
    }

    set('prompt', prompt);
    set('videoDesc', videoDesc);
    set('duration', duration);
    if (sets.isEmpty) return;
    args.add(id);
    db.execute('UPDATE o_storyboard SET ${sets.join(',')} WHERE id=?', args);
  }

  /// 按给定 id 顺序重排同一剧本的分镜，并重写为连续 1 基 index。
  ///
  /// 这是工作台拖拽排序的唯一写入口：调用方必须传入当前 script 下的完整 id 列表，
  /// 避免部分列表或跨剧本 id 把合成顺序写坏。
  void reorderStoryboards(int scriptId, List<int> orderedIds) {
    final currentIds = db
        .select(
          'SELECT id FROM o_storyboard WHERE scriptId=? ORDER BY "index" ASC',
          [scriptId],
        )
        .map((r) => r['id'] as int)
        .toList();
    if (currentIds.length != orderedIds.length ||
        currentIds.toSet().length != orderedIds.toSet().length ||
        !currentIds.toSet().containsAll(orderedIds)) {
      throw const EngineException(
          errPromptMissing, {'type': 'storyboardOrder'});
    }
    if (_sameOrder(currentIds, orderedIds)) return;

    db.execute('SAVEPOINT reorder_storyboards');
    try {
      for (final (i, id) in orderedIds.indexed) {
        db.execute(
          'UPDATE o_storyboard SET "index"=? WHERE id=? AND scriptId=?',
          [i + 1, id, scriptId],
        );
      }
      db.execute('RELEASE SAVEPOINT reorder_storyboards');
    } catch (_) {
      db.execute('ROLLBACK TO SAVEPOINT reorder_storyboards');
      db.execute('RELEASE SAVEPOINT reorder_storyboards');
      rethrow;
    }
  }

  /// 批量删除：清关联+清图片文件+重排剩余 index。
  void deleteStoryboards(List<int> ids) {
    if (ids.isEmpty) return;
    final ph = _ph(ids);
    final scriptIds = db
        .select(
            'SELECT DISTINCT scriptId FROM o_storyboard WHERE id IN ($ph)', ids)
        .map((r) => r['scriptId'] as int)
        .toList();
    for (final row in db.select(
      'SELECT filePath FROM o_storyboard WHERE id IN ($ph) AND filePath IS NOT NULL',
      ids,
    )) {
      final f = File(media.absPath(row['filePath'] as String));
      if (f.existsSync()) f.deleteSync();
    }
    db.execute(
        'DELETE FROM o_assets2Storyboard WHERE storyboardId IN ($ph)', ids);
    db.execute('DELETE FROM o_storyboard WHERE id IN ($ph)', ids);
    for (final scriptId in scriptIds) {
      final remaining = db.select(
        'SELECT id FROM o_storyboard WHERE scriptId=? ORDER BY "index" ASC',
        [scriptId],
      );
      var i = 1;
      for (final r in remaining) {
        db.execute(
            'UPDATE o_storyboard SET "index"=? WHERE id=?', [i++, r['id']]);
      }
    }
  }

  // ───────── 剧本 → 分镜生成（LLM tool-calling） ─────────

  int generateStoryboards(int projectId, int scriptId) {
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'storyboard_generate',
      describe: '分镜生成',
      relatedObjects: {'kind': 'script', 'scriptId': scriptId},
    );
  }

  Future<void> _runStoryboardGenerate(TasksRow task, CancelToken token) async {
    final scriptId =
        ((task.relatedObjectsJson['scriptId'] as num?) ?? 0).toInt();
    final script =
        db.select('SELECT * FROM o_script WHERE id=?', [scriptId]).firstOrNull;
    if (script == null) {
      throw EngineException(errPromptMissing, {'type': 'script'});
    }
    final projectId = (script['projectId'] as int?) ?? task.projectId ?? 0;
    final assets = db.select(
      'SELECT id,name FROM o_assets WHERE projectId=? '
      "AND type IN ('role','tool','scene')",
      [projectId],
    );
    final nameToId = {
      for (final a in assets)
        if (a['name'] != null) a['name'] as String: a['id'] as int,
    };
    final system = await getPrompt('storyboard_gen');
    final user = '请根据以下剧本内容生成分镜列表（每个分镜包含画面提示词、'
        '运镜/画面描述、预估时长秒数、涉及的资产名称）：\n${script['content'] ?? ''}';
    final result = await gateway.generateToolJson(
      system,
      user,
      stage: 'storyboard_gen',
      toolName: 'resultTool',
      schema: storyboardListToolSchema,
      cancelToken: token,
    );
    final shots = (result['shots'] as List? ?? const []).whereType<Map>();
    if (shots.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': 'empty shots'});
    }
    var index = 0;
    for (final shot in shots) {
      index++;
      final assetNames = (shot['assetNames'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      final assetIds = [
        for (final name in assetNames)
          if (nameToId[name] != null) nameToId[name]!,
      ];
      db.execute(
        'INSERT INTO o_storyboard '
        '(projectId,scriptId,"index",prompt,videoDesc,duration,state,'
        'shouldGenerateImage,track,createTime) VALUES (?,?,?,?,?,?,?,1,?,?)',
        [
          projectId,
          scriptId,
          index,
          (shot['prompt'] ?? '').toString(),
          (shot['videoDesc'] ?? '').toString(),
          (shot['duration'] ?? '').toString(),
          sbNotGenerated,
          (shot['track'] ?? '').toString(),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      final id = db.lastInsertRowId;
      for (final assetId in assetIds) {
        db.execute(
          'INSERT INTO o_assets2Storyboard (assetId,storyboardId) VALUES (?,?)',
          [assetId, id],
        );
      }
    }
  }

  void _recoverStoryboardGenerate(TasksRow task) {
    // 生成中途中断：已落库的分镜行本身状态未受影响（生成过程仅在最后一次性写入），
    // 无需额外补偿；仅任务本身标记失败，供用户重试。
  }

  // ───────── 首帧图批量生成 ─────────

  int batchGenerateStoryboardImages(
    int projectId,
    List<int> storyboardIds, {
    bool compulsory = false,
    int concurrentCount = 5,
  }) {
    if (storyboardIds.isEmpty) return 0;
    final targets = compulsory
        ? storyboardIds
        : db
            .select(
              'SELECT id FROM o_storyboard WHERE id IN (${_ph(storyboardIds)}) '
              'AND shouldGenerateImage!=0',
              storyboardIds,
            )
            .map((r) => r['id'] as int)
            .toList();
    if (targets.isEmpty) return 0;
    db.execute(
      'UPDATE o_storyboard SET state=? WHERE id IN (${_ph(targets)})',
      [sbGenerating, ...targets],
    );
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'storyboard_image_generation',
      describe: '分镜首帧图生成',
      relatedObjects: {
        'kind': 'storyboard',
        'ids': targets,
        'concurrentCount': concurrentCount,
      },
    );
  }

  Future<void> _runStoryboardImage(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final ids = (related['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 5).clamp(1, 16);
    final projectId = task.projectId ?? 0;

    var success = 0;
    EngineException? firstFailure;
    var cursor = 0;

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= ids.length) return;
        final id = ids[i];
        final row = db
            .select('SELECT * FROM o_storyboard WHERE id=?', [id]).firstOrNull;
        if (row == null) continue;
        try {
          final assetIds = db
              .select(
                  'SELECT assetId FROM o_assets2Storyboard WHERE storyboardId=? '
                  'ORDER BY rowid',
                  [id])
              .map((r) => r['assetId'] as int)
              .toList();
          // 对齐 ToonFlow batchGenerateImage：把 **全部** 关联资产的首图按顺序
          // 作为参考列表传给图模型（此前只取 assetIds.first，丢失了角色+场景+道具
          // 的多参考信息，导致多资产分镜生成偏离）。
          final refPaths = <String>[];
          for (final assetId in assetIds) {
            final assetImage = db.select(
              'SELECT i.filePath filePath FROM o_assets a '
              'JOIN o_image i ON i.id=a.imageId WHERE a.id=?',
              [assetId],
            ).firstOrNull;
            final rel = assetImage?['filePath'] as String?;
            if (rel != null && rel.isNotEmpty) {
              refPaths.add(media.absPath(rel));
            }
          }
          final rel = await gateway.generateImage(
            (row['prompt'] as String?) ?? '',
            '$projectId',
            stage: 'shot_image',
            cancelToken: token,
            referenceAbsPaths: refPaths,
          );
          db.execute(
            'UPDATE o_storyboard SET state=?, filePath=?, reason=NULL WHERE id=?',
            [sbDone, rel, id],
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
          db.execute(
            'UPDATE o_storyboard SET state=?, reason=? WHERE id=?',
            [sbFailed, ex.toReasonJson(), id],
          );
        }
      }
    }

    await Future.wait(
        [for (var w = 0; w < min(concurrent, ids.length); w++) worker()]);
    if (token.isCancelled) throw const EngineException(errCanceled);
    if (success == 0 && firstFailure != null) throw firstFailure!;
  }

  void _recoverStoryboardImage(TasksRow task) {
    final ids = (task.relatedObjectsJson['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (ids.isEmpty) return;
    db.execute(
      'UPDATE o_storyboard SET state=?, reason=? '
      'WHERE id IN (${_ph(ids)}) AND state=?',
      [
        sbFailed,
        const EngineException(errAppRestart).toReasonJson(),
        ...ids,
        sbGenerating,
      ],
    );
  }
}
