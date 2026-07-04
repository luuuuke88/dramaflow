// 剧本模块：契约照抄 ToonFlow /api/script/*（getScrptApi/addScript/batchAddScript/
// updateScript/delScript/extractAssets/pollScriptAssets/getAiRegex/exportScript）。
// extractState：0=提取中 1=成功 -1=失败 2=待提取。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' show Row;

import 'engine.dart';
import 'errors.dart';
import 'events.dart' show stripThink;
import 'queue.dart';
import 'util.dart' show extractJson;

class ScriptRow {
  final int id;
  final int projectId;
  final String? name;
  final String? content;
  final int? extractState;
  final String? errorReason;
  final int? createTime;
  final List<({int id, String name})> relatedAssets;

  const ScriptRow({
    required this.id,
    required this.projectId,
    required this.name,
    required this.content,
    required this.extractState,
    required this.errorReason,
    required this.createTime,
    required this.relatedAssets,
  });
}

/// resultTool 参数 schema（照抄 ToonFlow extractAssets 的工具契约）。
const scriptAssetsToolSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'newAssets': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'desc': {'type': 'string'},
          'prompt': {'type': 'string'},
          'type': {
            'type': 'string',
            'enum': ['role', 'tool', 'scene'],
          },
          'scriptIds': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        },
        'required': ['name', 'type'],
      },
    },
    'existingAssetRefs': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'scriptIds': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        },
        'required': ['name'],
      },
    },
  },
  'required': ['newAssets', 'existingAssetRefs'],
};

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

extension ScriptsApi on Engine {
  void installScriptPipeline() {
    taskRunners['script_generation'] = _runScriptGeneration;
    taskRunners['asset_extraction'] = _runAssetExtraction;
    queue.registerRecover('script_generation', (_) {});
    queue.registerRecover('asset_extraction', _recoverAssetExtraction);
  }

  List<ScriptRow> scripts(int projectId, {String? search}) {
    final where = StringBuffer('projectId=?');
    final args = <Object?>[projectId];
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND name LIKE ?');
      args.add('%${search.trim()}%');
    }
    final rows =
        db.select('SELECT * FROM o_script WHERE $where ORDER BY id', args);
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final links = db.select(
      'SELECT sa.scriptId scriptId, a.id id, a.name name '
      'FROM o_scriptAssets sa JOIN o_assets a ON a.id=sa.assetId '
      'WHERE sa.scriptId IN (${_ph(ids)}) ORDER BY a.id',
      ids,
    );
    final byScript = <int, List<({int id, String name})>>{};
    for (final link in links) {
      byScript
          .putIfAbsent(link['scriptId'] as int, () => [])
          .add((id: link['id'] as int, name: (link['name'] as String?) ?? ''));
    }
    return rows.map((r) => _scriptRow(r, byScript)).toList();
  }

  ScriptRow _scriptRow(
    Row r,
    Map<int, List<({int id, String name})>> byScript,
  ) =>
      ScriptRow(
        id: r['id'] as int,
        projectId: (r['projectId'] as int?) ?? 0,
        name: r['name'] as String?,
        content: r['content'] as String?,
        extractState: r['extractState'] as int?,
        errorReason: r['errorReason'] as String?,
        createTime: r['createTime'] as int?,
        relatedAssets: byScript[r['id'] as int] ?? const [],
      );

  int addScript({
    required int projectId,
    required String name,
    required String content,
    List<int> assets = const [],
  }) {
    db.execute(
      'INSERT INTO o_script (name,content,projectId,createTime) VALUES (?,?,?,?)',
      [name, content, projectId, DateTime.now().millisecondsSinceEpoch],
    );
    final id = db.lastInsertRowId;
    for (final assetId in assets) {
      db.execute(
        'INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [id, assetId],
      );
    }
    return id;
  }

  List<int> batchAddScripts(
    int projectId,
    List<({String scriptName, String scriptData})> items,
  ) =>
      [
        for (final item in items)
          addScript(
            projectId: projectId,
            name: item.scriptName,
            content: item.scriptData,
          ),
      ];

  /// 从已提取事件生成剧本：目标事件一次入队，runner 通过 script_gen 阶段生成
  /// episodes JSON 并写入 o_script。对应 ToonFlow 剧本页「单个/批量从事件生成」。
  int generateScriptsFromEvents(int projectId, List<int> eventIds) {
    if (eventIds.isEmpty) return 0;
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'script_generation',
      describe: '从事件生成剧本',
      relatedObjects: {
        'kind': 'event',
        'ids': eventIds,
      },
    );
  }

  void updateScript(int id,
      {String? name, String? content, List<int>? assets}) {
    final sets = <String>[];
    final args = <Object?>[];
    if (name != null) {
      sets.add('name=?');
      args.add(name);
    }
    if (content != null) {
      sets.add('content=?');
      args.add(content);
    }
    if (sets.isNotEmpty) {
      args.add(id);
      db.execute('UPDATE o_script SET ${sets.join(',')} WHERE id=?', args);
    }
    if (assets != null) {
      db.execute('DELETE FROM o_scriptAssets WHERE scriptId=?', [id]);
      for (final assetId in assets) {
        db.execute(
          'INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
          [id, assetId],
        );
      }
    }
  }

  Future<void> _runScriptGeneration(TasksRow task, CancelToken token) async {
    final projectId = task.projectId ?? 0;
    final ids = (task.relatedObjectsJson['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (ids.isEmpty) return;
    final rows = db.select(
      '''
SELECT e.id id,e.name name,e.detail detail,
       GROUP_CONCAT(n.chapterIndex) chapterIndexes
FROM o_event e
JOIN o_eventChapter ec ON ec.eventId=e.id
JOIN o_novel n ON n.id=ec.novelId
WHERE n.projectId=? AND e.id IN (${_ph(ids)})
GROUP BY e.id
ORDER BY MIN(n.chapterIndex), e.id
''',
      [projectId, ...ids],
    );
    if (rows.isEmpty) {
      throw const EngineException(errNoChapters, {'reason': 'no_events'});
    }

    final system = await getPrompt('script_gen_system');
    final eventText = rows.map((row) {
      final chapters = ((row['chapterIndexes'] as String?) ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .join('、');
      return '事件ID: ${row['id']}\n'
          '事件名: ${row['name'] ?? ''}\n'
          '来源章节: $chapters\n'
          '事件详情: ${row['detail'] ?? ''}';
    }).join('\n\n---\n\n');
    final user = '请根据以下已提取事件，批量改编为短剧剧本。'
        '每个事件通常对应一集；如多个事件更适合合并，也可以合并但不要遗漏关键冲突。'
        '输出必须遵循系统提示词的 episodes JSON 结构。\n\n$eventText';
    final res = await gateway.generateText(
      system,
      user,
      stage: 'script_gen',
      cancelToken: token,
    );
    if (token.isCancelled) throw const EngineException(errCanceled);
    final parsed = extractJson(stripThink(res.content));
    final episodes =
        parsed is Map ? (parsed['episodes'] as List? ?? const []) : const [];
    if (episodes.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': 'empty_episodes'});
    }

    var created = 0;
    for (final raw in episodes.whereType<Map>()) {
      final episode = Map<String, dynamic>.from(raw);
      final title = (episode['title'] ?? '').toString().trim();
      final content = _formatGeneratedEpisode(episode);
      if (content.trim().isEmpty) continue;
      addScript(
        projectId: projectId,
        name: title.isEmpty ? '剧本${created + 1}' : title,
        content: content,
      );
      created++;
    }
    if (created == 0) {
      throw const EngineException(errLlmFormat, {'reason': 'empty_scripts'});
    }
  }

  String _formatGeneratedEpisode(Map<String, dynamic> episode) {
    final title = (episode['title'] ?? '').toString().trim();
    final synopsis = (episode['synopsis'] ?? '').toString().trim();
    final out = StringBuffer();
    if (title.isNotEmpty) out.writeln('# $title');
    if (synopsis.isNotEmpty) {
      if (out.isNotEmpty) out.writeln();
      out.writeln('梗概：$synopsis');
    }
    final scenes = (episode['scenes'] as List? ?? const []).whereType<Map>();
    var index = 0;
    for (final raw in scenes) {
      index++;
      final scene = Map<String, dynamic>.from(raw);
      final location = (scene['location'] ?? '').toString().trim();
      final timeOfDay = (scene['timeOfDay'] ?? '').toString().trim();
      final action = (scene['action'] ?? '').toString().trim();
      if (out.isNotEmpty) out.writeln();
      final suffix = [
        if (location.isNotEmpty) location,
        if (timeOfDay.isNotEmpty) timeOfDay,
      ].join('｜');
      out.writeln(suffix.isEmpty ? '## 场景 $index' : '## 场景 $index｜$suffix');
      if (action.isNotEmpty) out.writeln(action);
      final dialogues =
          (scene['dialogues'] as List? ?? const []).whereType<Map>();
      for (final lineRaw in dialogues) {
        final line = Map<String, dynamic>.from(lineRaw);
        final speaker = (line['speaker'] ?? '').toString().trim();
        final text = (line['line'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        out.writeln(speaker.isEmpty ? text : '$speaker：$text');
      }
    }
    return out.toString().trim();
  }

  /// 级联删除照抄 delScript：agentWorkData/assets2Storyboard/scriptAssets/
  /// storyboard（含首帧图文件）/videoTrack/video（含视频文件）→ o_script。
  void deleteScripts(List<int> ids) {
    if (ids.isEmpty) return;
    final ph = _ph(ids);
    db.execute('DELETE FROM o_agentWorkData WHERE episodesId IN ($ph)', ids);
    db.execute(
      'DELETE FROM o_assets2Storyboard WHERE storyboardId IN '
      '(SELECT id FROM o_storyboard WHERE scriptId IN ($ph))',
      ids,
    );
    db.execute('DELETE FROM o_scriptAssets WHERE scriptId IN ($ph)', ids);
    for (final row in db.select(
      'SELECT filePath FROM o_storyboard WHERE scriptId IN ($ph) '
      'AND filePath IS NOT NULL',
      ids,
    )) {
      final file = File(media.absPath(row['filePath'] as String));
      if (file.existsSync()) file.deleteSync();
    }
    db.execute('DELETE FROM o_storyboard WHERE scriptId IN ($ph)', ids);
    // 视频文件与 o_video/o_videoTrack 行一并清理（此前只删 o_video 行，
    // 泄漏了磁盘上的 .mp4 与整张 o_videoTrack 表，与 deleteProject 不一致）。
    for (final row in db.select(
      'SELECT filePath FROM o_video WHERE scriptId IN ($ph) '
      'AND filePath IS NOT NULL',
      ids,
    )) {
      final file = File(media.absPath(row['filePath'] as String));
      if (file.existsSync()) file.deleteSync();
    }
    db.execute('DELETE FROM o_video WHERE scriptId IN ($ph)', ids);
    db.execute('DELETE FROM o_videoTrack WHERE scriptId IN ($ph)', ids);
    db.execute('DELETE FROM o_timelineClip WHERE scriptId IN ($ph)', ids);
    db.execute('DELETE FROM o_script WHERE id IN ($ph)', ids);
  }

  /// 提取资产：目标剧本置 2（待提取）→ 入队 asset_extraction。
  int extractAssets(List<int> scriptIds, int projectId, {int? groupSize}) {
    if (scriptIds.isEmpty) return 0;
    // 分组大小对齐 ToonFlow assetsBatchGenereateSize（未显式指定时取其他设置值）。
    final g =
        (groupSize ?? config.intOf('assetsBatchGenereateSize')).clamp(1, 16);
    db.execute(
      'UPDATE o_script SET extractState=2, errorReason=NULL '
      'WHERE id IN (${_ph(scriptIds)})',
      scriptIds,
    );
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'asset_extraction',
      relatedObjects: {
        'kind': 'script',
        'ids': scriptIds,
        'groupSize': g,
      },
    );
  }

  Future<void> _runAssetExtraction(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final projectId = task.projectId ?? 0;
    final ids = (related['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final groupSize =
        ((related['groupSize'] as num?)?.toInt() ?? 5).clamp(1, 20);
    final system = await getPrompt('scriptAssetExtraction');

    var successGroups = 0;
    EngineException? firstFailure;
    for (var i = 0; i < ids.length; i += groupSize) {
      if (token.isCancelled) throw const EngineException(errCanceled);
      final group = ids.sublist(i, min(i + groupSize, ids.length));
      final rows = db.select(
        'SELECT id,name,content FROM o_script WHERE id IN (${_ph(group)})',
        group,
      );
      if (rows.isEmpty) continue;
      db.execute(
        'UPDATE o_script SET extractState=0 WHERE id IN (${_ph(group)})',
        group,
      );
      try {
        final existing = db
            .select(
              "SELECT name FROM o_assets WHERE projectId=? AND type IN ('role','tool','scene')",
              [projectId],
            )
            .map((r) => (r['name'] as String?) ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        // 分隔拼接格式逐字照抄 extractAssets.ts
        final scriptsContent = rows
            .map((r) =>
                '===== 【剧本ID: ${r['id']}】${r['name'] ?? ''} =====\n${r['content'] ?? ''}')
            .join('\n\n');
        final user = '当前已有资产列表：${existing.join('、')}\n\n'
            '请根据以下${rows.length}集剧本提取对应的剧本资产（角色、场景、道具）:\n'
            '$scriptsContent';
        final result = await gateway.generateToolJson(
          system,
          user,
          stage: 'asset_extract',
          toolName: 'resultTool',
          schema: scriptAssetsToolSchema,
          cancelToken: token,
        );
        _persistGroupResult(projectId, group, result);
        db.execute(
          'UPDATE o_script SET extractState=1, errorReason=NULL '
          'WHERE id IN (${_ph(group)})',
          group,
        );
        successGroups++;
      } catch (e) {
        if (token.isCancelled) throw const EngineException(errCanceled);
        final ex = e is EngineException
            ? e
            : (e is DioException
                ? EngineException(errNetwork, {'message': e.message})
                : EngineException(errLlmFormat, {'message': '$e'}));
        firstFailure ??= ex;
        db.execute(
          'UPDATE o_script SET extractState=-1, errorReason=? '
          'WHERE id IN (${_ph(group)})',
          [ex.toReasonJson(), ...group],
        );
      }
    }
    if (successGroups == 0 && firstFailure != null) {
      throw firstFailure;
    }
  }

  /// persistGroupResult 语义照抄：去重新增资产 → 重查映射 → 组内 scriptAssets
  /// 全删重插（去重 key = scriptId_assetId）。
  void _persistGroupResult(
    int projectId,
    List<int> groupScriptIds,
    Map<String, dynamic> result,
  ) {
    final newAssets =
        (result['newAssets'] as List? ?? const []).whereType<Map>().toList();
    final existingRefs = (result['existingAssetRefs'] as List? ?? const [])
        .whereType<Map>()
        .toList();

    final existingNames = db
        .select('SELECT name FROM o_assets WHERE projectId=?', [projectId])
        .map((r) => (r['name'] as String?) ?? '')
        .toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final asset in newAssets) {
      final name = (asset['name'] ?? '').toString();
      final type = (asset['type'] ?? '').toString();
      if (name.isEmpty || existingNames.contains(name)) continue;
      if (!const {'role', 'tool', 'scene'}.contains(type)) continue;
      db.execute(
        'INSERT INTO o_assets (name,type,describe,prompt,projectId,startTime) '
        'VALUES (?,?,?,?,?,?)',
        [
          name,
          type,
          (asset['desc'] ?? '').toString(),
          (asset['prompt'] ?? '').toString(),
          projectId,
          now,
        ],
      );
      existingNames.add(name);
    }

    final idByName = <String, int>{
      for (final r in db.select(
        'SELECT id,name FROM o_assets WHERE projectId=?',
        [projectId],
      ))
        if (r['name'] != null) r['name'] as String: r['id'] as int,
    };

    final links = <String, ({int scriptId, int assetId})>{};
    void addLinks(Map raw) {
      final name = (raw['name'] ?? '').toString();
      final assetId = idByName[name];
      if (assetId == null) return;
      final scriptIds = (raw['scriptIds'] as List? ?? const [])
          .map((e) => (e as num).toInt())
          .where(groupScriptIds.contains)
          .toList();
      // LLM 未标 scriptIds 时挂到组内全部剧本（宽松兜底）
      for (final sid in scriptIds.isEmpty ? groupScriptIds : scriptIds) {
        links['${sid}_$assetId'] = (scriptId: sid, assetId: assetId);
      }
    }

    newAssets.forEach(addLinks);
    existingRefs.forEach(addLinks);

    db.execute(
      'DELETE FROM o_scriptAssets WHERE scriptId IN (${_ph(groupScriptIds)})',
      groupScriptIds,
    );
    for (final link in links.values) {
      db.execute(
        'INSERT INTO o_scriptAssets (scriptId,assetId) VALUES (?,?)',
        [link.scriptId, link.assetId],
      );
    }
  }

  void _recoverAssetExtraction(TasksRow task) {
    final ids = (task.relatedObjectsJson['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (ids.isEmpty) return;
    db.execute(
      'UPDATE o_script SET extractState=-1, errorReason=? '
      'WHERE id IN (${_ph(ids)}) AND extractState IN (0,2)',
      [const EngineException(errAppRestart).toReasonJson(), ...ids],
    );
  }

  /// pollScriptAssets 语义（extractState 非进行中的行），供工具/E2E。
  List<({int id, int? extractState, String? errorReason})> scriptExtractState(
    List<int> ids,
  ) {
    if (ids.isEmpty) return const [];
    return db
        .select(
          'SELECT id,extractState,errorReason FROM o_script '
          'WHERE id IN (${_ph(ids)}) AND extractState NOT IN (0,2)',
          ids,
        )
        .map((r) => (
              id: r['id'] as int,
              extractState: r['extractState'] as int?,
              errorReason: r['errorReason'] as String?,
            ))
        .toList();
  }

  /// getAiRegex 语义：前 2000 字交 LLM 产分集正则（原样返回，不带围栏）。
  Future<String> aiEpisodeRegex(String content) async {
    final head = content.substring(0, min(2000, content.length));
    final res = await gateway.generateText(
      '你是正则表达式专家。根据用户给出的剧本文本，输出一个 JavaScript 风格的正则表达式，'
      '用于按集切分：第 1 个捕获组为集号（阿拉伯或中文数字），第 2 个捕获组为该集标题。'
      '只输出正则本身（形如 /pattern/g），不要解释、不要代码块。',
      head,
      stage: 'script_gen',
    );
    return stripThink(res.content)
        .replaceAll(RegExp(r'^```[a-z]*\s*|\s*```$'), '')
        .trim();
  }

  /// 导出剧本 zip：每剧本一个 `{name}.txt`。
  List<int> exportScripts(List<int> ids) {
    if (ids.isEmpty) return const [];
    final rows = db.select(
      'SELECT name,content FROM o_script WHERE id IN (${_ph(ids)}) ORDER BY id',
      ids,
    );
    final archive = Archive();
    var i = 0;
    final used = <String>{};
    for (final row in rows) {
      i++;
      var base = ((row['name'] as String?) ?? '').trim();
      if (base.isEmpty) base = '剧本$i';
      base = base.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      var fileName = '$base.txt';
      var n = 1;
      while (!used.add(fileName)) {
        fileName = '$base(${n++}).txt';
      }
      final bytes = utf8.encode((row['content'] as String?) ?? '');
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
    }
    return ZipEncoder().encode(archive);
  }
}

/// 资产选择器数据源（P2 素材库前的最小只读查询）。
extension ScriptAssetOptions on Engine {
  List<({int id, String name, String type})> assetOptions(int projectId) => db
      .select(
        "SELECT id,name,type FROM o_assets WHERE projectId=? "
        "AND type IN ('role','tool','scene') ORDER BY id",
        [projectId],
      )
      .map((r) => (
            id: r['id'] as int,
            name: (r['name'] as String?) ?? '',
            type: (r['type'] as String?) ?? '',
          ))
      .toList();
}
