// 分镜模块：契约照抄 ToonFlow /api/production/storyboard/*
// （详见 docs/reference/p3-production-canvas-brief.md §2）。
// 状态枚举为 DB 中文字符串（逐字）：未生成/生成中/已完成/生成失败。
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' show Row;

import 'engine.dart';
import 'errors.dart';
import 'image_flow_cleanup.dart';
import 'production_dependencies.dart';
import 'prompt_resolver.dart';
import 'queue.dart';
import 'script_plan.dart';
import 'storyboard_table.dart';
import 'video_track.dart' show VideoTrackApi;

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

class StoryboardTableShot {
  final String prompt;
  final String videoDesc;
  final String duration;
  final String track;
  final List<String> assetNames;
  final bool shouldGenerateImage;

  const StoryboardTableShot({
    required this.prompt,
    required this.videoDesc,
    required this.duration,
    required this.track,
    required this.assetNames,
    required this.shouldGenerateImage,
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
        'required': ['prompt', 'videoDesc'],
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

List<String> _splitMarkdownRow(String line) {
  final cells = <String>[];
  final cell = StringBuffer();
  final text = line.trim();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == r'\' && i + 1 < text.length && text[i + 1] == '|') {
      cell.write('|');
      i++;
    } else if (char == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(char);
    }
  }
  cells.add(cell.toString().trim());
  if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
  if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
  return cells;
}

String _normalizedTableHeader(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

bool _isMarkdownSeparator(List<String> cells) =>
    cells.isNotEmpty &&
    cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell));

Never _storyboardTableError(String reason) => throw EngineException(
      errLlmFormat,
      {'reason': 'storyboard_table:$reason'},
    );

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
    final flowIds = imageFlowIdsForStoryboards(db, ids);
    final trackIds = ids.length == 1
        ? db
            .select(
              'SELECT trackId FROM o_storyboard WHERE id IN ($ph) '
              'AND trackId IS NOT NULL',
              ids,
            )
            .map((row) => row['trackId'] as int)
            .toSet()
            .toList()
        : const <int>[];
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
    clearUnreferencedImageFlows(db, flowIds);
    // 对齐 ToonFlow removeFrame：单镜删除后，若其轨道已空则一并移除。
    // 批量删除保持 batchDelete 的原始语义，不主动删除空轨。
    for (final trackId in trackIds) {
      final hasStoryboard = db.select(
        'SELECT id FROM o_storyboard WHERE trackId=? LIMIT 1',
        [trackId],
      );
      if (hasStoryboard.isEmpty) deleteVideoTrack(trackId);
    }
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

  List<StoryboardTableShot> parseStoryboardTable(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    List<String>? headers;
    var separatorIndex = -1;
    for (var i = 0; i + 1 < lines.length; i++) {
      if (!lines[i].contains('|') || !lines[i + 1].contains('|')) continue;
      final candidateHeaders = _splitMarkdownRow(lines[i]);
      final separator = _splitMarkdownRow(lines[i + 1]);
      if (!_isMarkdownSeparator(separator) ||
          candidateHeaders.length != separator.length) {
        continue;
      }
      final normalized = candidateHeaders.map(_normalizedTableHeader).toList();
      if (normalized.contains('画面提示词') || normalized.contains('prompt')) {
        headers = normalized;
        separatorIndex = i + 1;
        break;
      }
    }
    if (headers == null) _storyboardTableError('missing_table');

    int column(Set<String> aliases) {
      for (var i = 0; i < headers!.length; i++) {
        if (aliases.contains(headers[i])) return i;
      }
      return -1;
    }

    final promptColumn = column({'画面提示词', 'prompt'});
    final videoDescColumn = column({'画面描述', 'videodesc'});
    final durationColumn = column({'时长', 'duration'});
    final trackColumn = column({'分轨', 'track'});
    final assetsColumn = column({'资产', 'assetnames'});
    final imageColumn = column({'生成首帧', 'shouldgenerateimage'});
    if (promptColumn < 0 || videoDescColumn < 0 || durationColumn < 0) {
      _storyboardTableError('missing_required_columns');
    }

    final shots = <StoryboardTableShot>[];
    for (var i = separatorIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || !line.contains('|')) break;
      final cells = _splitMarkdownRow(line);
      if (cells.length != headers.length) {
        _storyboardTableError('row_${i + 1}_column_count');
      }
      final prompt = cells[promptColumn].trim();
      final videoDesc = cells[videoDescColumn].trim();
      final duration = cells[durationColumn].trim();
      if (prompt.isEmpty || videoDesc.isEmpty || duration.isEmpty) {
        _storyboardTableError('row_${i + 1}_required_value');
      }
      // 宽松解析：LLM（尤其非默认调优模型）对该列的自然语言表达差异较大，
      // 严格枚举曾在真实生成中导致整张表因单个单元格解析失败而报废。
      // 无法识别的取值降级为默认需要生成（与该列整体缺失时的默认行为一致），
      // 不再让单个模糊单元格拖垮整张分镜表。
      var shouldGenerateImage = true;
      if (imageColumn >= 0) {
        final raw = cells[imageColumn].trim().toLowerCase();
        // 仅否定取值（及留空）判否；其余一律判需要生成——包括无法识别的
        // 自然语言变体。已知限制：精确 token 匹配，含否定词的整句、全角
        // 拉丁或零宽字符污染的取值会落入默认 true（测试有对应锁定用例）。
        const falseValues = {'否', 'false', '0', 'no', 'n', '不需要', '✗', '×'};
        shouldGenerateImage = raw.isNotEmpty && !falseValues.contains(raw);
      }
      final assetNames = assetsColumn < 0
          ? const <String>[]
          : cells[assetsColumn]
              .split(RegExp('[,，]'))
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList();
      shots.add(StoryboardTableShot(
        prompt: prompt,
        videoDesc: videoDesc,
        duration: duration,
        track: trackColumn < 0 ? '' : cells[trackColumn].trim(),
        assetNames: List.unmodifiable(assetNames),
        shouldGenerateImage: shouldGenerateImage,
      ));
    }
    if (shots.isEmpty) _storyboardTableError('empty_rows');
    return List.unmodifiable(shots);
  }

  int generateStoryboards(
    int projectId,
    int scriptId, {
    bool replaceExisting = false,
  }) {
    final script = db.select(
      'SELECT content FROM o_script WHERE id=? AND projectId=? LIMIT 1',
      [scriptId, projectId],
    ).firstOrNull;
    final plan = scriptPlan(projectId);
    final table = storyboardTable(projectId, scriptId);
    if (script == null || plan.trim().isEmpty || table.trim().isEmpty) return 0;
    if (!replaceExisting &&
        db.select('SELECT id FROM o_storyboard WHERE scriptId=? LIMIT 1',
            [scriptId]).isNotEmpty) {
      return 0;
    }
    final content = script['content'] as String? ?? '';
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'storyboard_generate',
      describe: '分镜生成',
      relatedObjects: {
        'kind': 'script',
        'scriptId': scriptId,
        'replaceExisting': replaceExisting,
        'scriptHash': promptContentHash(content),
        'planHash': promptContentHash(plan),
        'tableHash': promptContentHash(table),
        'assetsHash': scriptAssetsHash(projectId, scriptId),
      },
    );
  }

  void _assertStoryboardSourcesCurrent(
    int projectId,
    int scriptId,
    Map<String, dynamic> related,
  ) {
    final script = db.select(
      'SELECT content FROM o_script WHERE id=? AND projectId=? LIMIT 1',
      [scriptId, projectId],
    ).firstOrNull;
    if (script == null) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:staleScript'},
      );
    }
    final content = script['content'] as String? ?? '';
    final plan = scriptPlan(projectId);
    final table = storyboardTable(projectId, scriptId);
    if ((related['scriptHash'] ?? '').toString() !=
        promptContentHash(content)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:staleScript'},
      );
    }
    if ((related['planHash'] ?? '').toString() != promptContentHash(plan)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:stalePlan'},
      );
    }
    if ((related['tableHash'] ?? '').toString() != promptContentHash(table)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:staleTable'},
      );
    }
    if ((related['assetsHash'] ?? '').toString() !=
        scriptAssetsHash(projectId, scriptId)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:staleAssets'},
      );
    }
  }

  String _storyboardOutputHash(int scriptId) {
    String material(
      String label,
      String sql,
      List<String> columns,
    ) {
      final rows = db.select(sql, [scriptId]);
      return rows.map((row) {
        final values = [for (final column in columns) row[column] ?? ''];
        return '$label\u0000${values.join('\u0000')}';
      }).join('\n');
    }

    return promptContentHash([
      material(
        'storyboard',
        'SELECT id,"index",prompt,videoDesc,duration,filePath,'
            'shouldGenerateImage,track,trackId,audioAssetId,audioText,audioPath,'
            'audioState,state FROM o_storyboard WHERE scriptId=? ORDER BY id',
        const [
          'id',
          'index',
          'prompt',
          'videoDesc',
          'duration',
          'filePath',
          'shouldGenerateImage',
          'track',
          'trackId',
          'audioAssetId',
          'audioText',
          'audioPath',
          'audioState',
          'state',
        ],
      ),
      material(
        'assetLink',
        'SELECT ats.storyboardId,ats.assetId FROM o_assets2Storyboard ats '
            'JOIN o_storyboard s ON s.id=ats.storyboardId '
            'WHERE s.scriptId=? ORDER BY ats.storyboardId,ats.assetId',
        const ['storyboardId', 'assetId'],
      ),
      material(
        'videoTrack',
        'SELECT id,prompt,duration,transition,filterPreset,selectVideoId,videoId,'
            'state,videoRequest FROM o_videoTrack WHERE scriptId=? ORDER BY id',
        const [
          'id',
          'prompt',
          'duration',
          'transition',
          'filterPreset',
          'selectVideoId',
          'videoId',
          'state',
          'videoRequest',
        ],
      ),
      material(
        'video',
        'SELECT id,videoTrackId,filePath,state,modelBinding,requestFingerprint,'
            'upstreamTaskId,upstreamState FROM o_video '
            'WHERE scriptId=? ORDER BY id',
        const [
          'id',
          'videoTrackId',
          'filePath',
          'state',
          'modelBinding',
          'requestFingerprint',
          'upstreamTaskId',
          'upstreamState',
        ],
      ),
      material(
        'timeline',
        'SELECT id,assetId,filePath,lane,startMs,durationMs,name,opacity '
            'FROM o_timelineClip WHERE scriptId=? ORDER BY id',
        const [
          'id',
          'assetId',
          'filePath',
          'lane',
          'startMs',
          'durationMs',
          'name',
          'opacity',
        ],
      ),
    ].join('\n'));
  }

  Future<void> _runStoryboardGenerate(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final scriptId = ((related['scriptId'] as num?) ?? 0).toInt();
    final replaceExisting = related['replaceExisting'] == true;
    final projectId = task.projectId ?? 0;
    final script = db.select(
      'SELECT content FROM o_script WHERE id=? AND projectId=? LIMIT 1',
      [scriptId, projectId],
    ).firstOrNull;
    if (script == null) {
      throw EngineException(errPromptMissing, {'type': 'script'});
    }
    final content = script['content'] as String? ?? '';
    final plan = scriptPlan(projectId);
    final table = storyboardTable(projectId, scriptId);
    if (plan.trim().isEmpty || table.trim().isEmpty) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:dependencies'},
      );
    }
    _assertStoryboardSourcesCurrent(projectId, scriptId, related);
    final tableShots = parseStoryboardTable(table);
    if (!replaceExisting &&
        db.select('SELECT id FROM o_storyboard WHERE scriptId=? LIMIT 1',
            [scriptId]).isNotEmpty) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:existing'},
      );
    }
    final existingOutputHash =
        replaceExisting ? _storyboardOutputHash(scriptId) : '';
    final assets = db.select(
      "SELECT a.id,a.type,a.name,a.describe FROM o_scriptAssets sa "
      "JOIN o_assets a ON a.id=sa.assetId "
      "WHERE sa.scriptId=? AND a.projectId=? "
      "AND a.type IN ('role','tool','scene') ORDER BY a.id",
      [scriptId, projectId],
    );
    final nameToId = {
      for (final a in assets)
        if ((a['name'] as String? ?? '').trim().isNotEmpty)
          (a['name'] as String).trim(): a['id'] as int,
    };
    final assetsText = assets.map((row) {
      final name = (row['name'] as String? ?? '').trim();
      final type = (row['type'] as String? ?? '').trim();
      final describe = (row['describe'] as String? ?? '').trim();
      return '$name（$type）：$describe';
    }).join('\n');
    final resolution = resolvePrompt(
      projectId: projectId,
      basePromptKey: 'storyboard_gen',
      visualSection: 'director_storyboard',
      modelStage: 'storyboard_gen',
      modelPromptPath: 'text/storyboard_gen.md',
      requireModelPrompt: false,
    );
    final user = '导演规划：\n$plan\n\n'
        '分镜表：\n$table\n\n'
        '当前剧本：\n$content\n\n'
        '候选资产：\n${assetsText.isEmpty ? '（无）' : assetsText}\n\n'
        '请严格按分镜表的行数和顺序输出，保持每行的时长、分轨和资产意图，'
        '只润色画面提示词和画面描述。';
    recordTaskPromptSources(
      task.id,
      resolution,
      requests: [
        PromptRequestTrace(
          targetType: 'script',
          targetId: scriptId,
          sources: List.unmodifiable([
            ...resolution.sources,
            PromptSource(
              id: 'data:directorPlan:$projectId',
              kind: 'data',
              version: promptContentHash(plan),
              content: plan,
            ),
            PromptSource(
              id: 'data:storyboardTable:$scriptId',
              kind: 'data',
              version: promptContentHash(table),
              content: table,
            ),
            PromptSource(
              id: 'data:script:$scriptId',
              kind: 'data',
              version: promptContentHash(content),
              content: content,
            ),
            PromptSource(
              id: 'data:scriptAssets:$scriptId',
              kind: 'data',
              version: scriptAssetsHash(projectId, scriptId),
              content: assetsText,
            ),
          ]),
        ),
      ],
    );
    final result = await gateway.generateToolJson(
      resolution.system,
      user,
      stage: 'storyboard_gen',
      toolName: 'resultTool',
      schema: storyboardListToolSchema,
      cancelToken: token,
    );
    if (token.isCancelled) throw const EngineException(errCanceled);
    _assertStoryboardSourcesCurrent(projectId, scriptId, related);
    if (replaceExisting &&
        existingOutputHash != _storyboardOutputHash(scriptId)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:staleExisting'},
      );
    }
    if (!replaceExisting &&
        db.select('SELECT id FROM o_storyboard WHERE scriptId=? LIMIT 1',
            [scriptId]).isNotEmpty) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboard:existing'},
      );
    }
    final rawShots = result['shots'];
    if (rawShots is! List ||
        rawShots.isEmpty ||
        rawShots.length != tableShots.length) {
      throw const EngineException(
        errLlmFormat,
        {'reason': 'storyboard_shots:count'},
      );
    }
    final generated = <({String prompt, String videoDesc})>[];
    for (var i = 0; i < rawShots.length; i++) {
      final raw = rawShots[i];
      if (raw is! Map) {
        throw EngineException(
          errLlmFormat,
          {'reason': 'storyboard_shots:row_${i + 1}'},
        );
      }
      final prompt = (raw['prompt'] ?? '').toString().trim();
      final videoDesc = (raw['videoDesc'] ?? '').toString().trim();
      if (prompt.isEmpty || videoDesc.isEmpty) {
        throw EngineException(
          errLlmFormat,
          {'reason': 'storyboard_shots:row_${i + 1}_required'},
        );
      }
      generated.add((prompt: prompt, videoDesc: videoDesc));
    }

    final oldMediaPaths = <String>{};
    final oldStoryboardIds = <int>[];
    final oldFlowIds = <int>[];
    if (replaceExisting) {
      oldStoryboardIds.addAll(db.select(
          'SELECT id FROM o_storyboard WHERE scriptId=?',
          [scriptId]).map((row) => row['id'] as int));
      oldFlowIds.addAll(imageFlowIdsForStoryboards(db, oldStoryboardIds));
      for (final row in db.select(
        'SELECT filePath FROM o_storyboard WHERE scriptId=? '
        'AND filePath IS NOT NULL',
        [scriptId],
      )) {
        final path = (row['filePath'] as String? ?? '').trim();
        if (path.isNotEmpty) oldMediaPaths.add(path);
      }
      for (final row in db.select(
        'SELECT filePath FROM o_video WHERE scriptId=? AND filePath IS NOT NULL',
        [scriptId],
      )) {
        final path = (row['filePath'] as String? ?? '').trim();
        if (path.isNotEmpty) oldMediaPaths.add(path);
      }
    }

    db.execute('SAVEPOINT replace_storyboards');
    try {
      if (replaceExisting) {
        db.execute(
          'DELETE FROM o_assets2Storyboard WHERE storyboardId IN '
          '(SELECT id FROM o_storyboard WHERE scriptId=?)',
          [scriptId],
        );
        db.execute('DELETE FROM o_storyboard WHERE scriptId=?', [scriptId]);
        clearUnreferencedImageFlows(db, oldFlowIds);
        db.execute('DELETE FROM o_video WHERE scriptId=?', [scriptId]);
        db.execute('DELETE FROM o_videoTrack WHERE scriptId=?', [scriptId]);
        db.execute('DELETE FROM o_timelineClip WHERE scriptId=?', [scriptId]);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < tableShots.length; i++) {
        final tableShot = tableShots[i];
        final generatedShot = generated[i];
        db.execute(
          'INSERT INTO o_storyboard '
          '(projectId,scriptId,"index",prompt,videoDesc,duration,state,'
          'shouldGenerateImage,track,createTime) VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            projectId,
            scriptId,
            i + 1,
            generatedShot.prompt,
            generatedShot.videoDesc,
            tableShot.duration,
            sbNotGenerated,
            tableShot.shouldGenerateImage ? 1 : 0,
            tableShot.track,
            now,
          ],
        );
        final storyboardId = db.lastInsertRowId;
        final assetIds = <int>{
          for (final name in tableShot.assetNames)
            if (nameToId[name] != null) nameToId[name]!,
        };
        for (final assetId in assetIds) {
          db.execute(
            'INSERT INTO o_assets2Storyboard (assetId,storyboardId) '
            'VALUES (?,?)',
            [assetId, storyboardId],
          );
        }
      }
      db.execute('RELEASE SAVEPOINT replace_storyboards');
    } catch (_) {
      db.execute('ROLLBACK TO SAVEPOINT replace_storyboards');
      db.execute('RELEASE SAVEPOINT replace_storyboards');
      rethrow;
    }

    for (final path in oldMediaPaths) {
      try {
        final stillReferencedByAsset = db.select(
          'SELECT id FROM o_image WHERE filePath=? LIMIT 1',
          [path],
        ).isNotEmpty;
        if (stillReferencedByAsset) continue;
        final file = File(media.absPath(path));
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Database replacement is already committed; orphan cleanup can retry later.
      }
    }
    setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptId,
      key: structuredStoryboardStateKey,
      sourceHash: promptContentHash(table),
      stale: false,
    );
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
