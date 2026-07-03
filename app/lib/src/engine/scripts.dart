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
    taskRunners['asset_extraction'] = _runAssetExtraction;
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

  void updateScript(int id, {String? name, String? content, List<int>? assets}) {
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

  /// 级联删除照抄 delScript：agentWorkData/assets2Storyboard/scriptAssets/
  /// storyboard（含首帧图文件）/video → o_script。
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
    db.execute('DELETE FROM o_video WHERE scriptId IN ($ph)', ids);
    db.execute('DELETE FROM o_script WHERE id IN ($ph)', ids);
  }

  /// 提取资产：目标剧本置 2（待提取）→ 入队 asset_extraction。
  int extractAssets(List<int> scriptIds, int projectId, {int groupSize = 5}) {
    if (scriptIds.isEmpty) return 0;
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
        'groupSize': groupSize,
      },
    );
  }

  Future<void> _runAssetExtraction(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final projectId = task.projectId ?? 0;
    final ids = (related['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final groupSize = ((related['groupSize'] as num?)?.toInt() ?? 5).clamp(1, 20);
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
    final newAssets = (result['newAssets'] as List? ?? const [])
        .whereType<Map>()
        .toList();
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
