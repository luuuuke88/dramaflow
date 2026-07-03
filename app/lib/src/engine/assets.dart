// 素材模块：契约照抄 ToonFlow /api/assets/* 与 /api/assetsGenerate/*
// （详见 docs/reference/p2-assets-brief.md）。
// 状态枚举为 DB 中文字符串（逐字）：promptState/state ∈ 生成中/已完成/生成失败。
// 偏差（已记录）：taskClass 统一英文 asset_prompt_polish / asset_image_generation，
// describe 存中文标签；生图 aspectRatio 用项目 videoRatio（ToonFlow 写死 16:9）。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' show Row;

import 'engine.dart';
import 'errors.dart';
import 'manuals.dart';
import 'queue.dart';

const stateGenerating = '生成中';
const stateDone = '已完成';
const stateFailed = '生成失败';

class AssetImageRow {
  final int id;
  final String? filePath;
  final String? state;
  final String? errorReason;
  final String? model;
  final String? resolution;
  final bool selected;
  const AssetImageRow({
    required this.id,
    required this.filePath,
    required this.state,
    required this.errorReason,
    required this.model,
    required this.resolution,
    required this.selected,
  });
}

class AssetRow {
  final int id;
  final int projectId;
  final String? name;
  final String? describe;
  final String? remark;
  final String? prompt;
  final String type;
  final int? assetsId; // 父资产 id（子资产非空）
  final int? imageId;
  final int? startTime;
  final String? promptState;
  final String? promptErrorReason;
  final String? filePath; // 选中图（o_image via imageId）
  final String? imageState;
  final List<AssetRow> sonAssets;

  const AssetRow({
    required this.id,
    required this.projectId,
    required this.name,
    required this.describe,
    required this.remark,
    required this.prompt,
    required this.type,
    required this.assetsId,
    required this.imageId,
    required this.startTime,
    required this.promptState,
    required this.promptErrorReason,
    required this.filePath,
    required this.imageState,
    this.sonAssets = const [],
  });

  /// audio：describe = "性别|描述"
  String get sex => (describe ?? '').split('|').first;
  String get audioDescribe {
    final parts = (describe ?? '').split('|');
    return parts.length > 1 ? parts.sublist(1).join('|') : '';
  }
}

class _TypeConfig {
  final String label;
  final String nameLabel;
  final String promptTitle;
  final String promptEnd;
  final String dir;
  final String manualKey;
  final String manualKeyDerivative;
  const _TypeConfig(this.label, this.nameLabel, this.promptTitle,
      this.promptEnd, this.dir, this.manualKey, this.manualKeyDerivative);
}

const _typeConfigs = {
  'role': _TypeConfig('角色', '角色', '角色标准四视图', '人物角色四视图', 'role',
      'art_character', 'art_character_derivative'),
  'scene': _TypeConfig(
      '场景', '场景', '标准场景图', '标准场景图', 'scene', 'art_scene', 'art_scene_derivative'),
  'tool': _TypeConfig(
      '道具', '道具', '标准道具图', '标准道具图', 'props', 'art_prop', 'art_prop_derivative'),
};

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

extension AssetsApi on Engine {
  void installAssetPipeline() {
    taskRunners['asset_prompt_polish'] = _runPromptPolish;
    taskRunners['asset_image_generation'] = _runImageGeneration;
    queue.registerRecover('asset_prompt_polish', _recoverPromptPolish);
    queue.registerRecover('asset_image_generation', _recoverImageGeneration);
  }

  // ───────── 查询 ─────────

  AssetRow _assetFromRow(Row r, {List<AssetRow> sons = const []}) => AssetRow(
        id: r['id'] as int,
        projectId: (r['projectId'] as int?) ?? 0,
        name: r['name'] as String?,
        describe: r['describe'] as String?,
        remark: r['remark'] as String?,
        prompt: r['prompt'] as String?,
        type: (r['type'] as String?) ?? '',
        assetsId: r['assetsId'] as int?,
        imageId: r['imageId'] as int?,
        startTime: r['startTime'] as int?,
        promptState: r['promptState'] as String?,
        promptErrorReason: r['promptErrorReason'] as String?,
        filePath: r['filePath'] as String?,
        imageState: r['imageState'] as String?,
        sonAssets: sons,
      );

  static const _assetSelect = '''
SELECT a.*, i.filePath filePath, i.state imageState
FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId
''';

  ({List<AssetRow> data, int total}) getAssets(
    int projectId, {
    required String type,
    int page = 1,
    int limit = 10,
    String? search,
  }) {
    final where = StringBuffer('a.projectId=? AND a.type=? AND a.assetsId IS NULL');
    final args = <Object?>[projectId, type];
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND a.name LIKE ?');
      args.add('%${search.trim()}%');
    }
    final total = db
        .select(
          'SELECT COUNT(*) n FROM o_assets a WHERE $where',
          args,
        )
        .first['n'] as int;
    final parents = db.select(
      '$_assetSelect WHERE $where ORDER BY a.id LIMIT ? OFFSET ?',
      [...args, limit, (page - 1) * limit],
    );
    if (parents.isEmpty) return (data: const <AssetRow>[], total: total);
    final parentIds = parents.map((r) => r['id'] as int).toList();
    final children = db.select(
      '$_assetSelect WHERE a.assetsId IN (${_ph(parentIds)}) ORDER BY a.id',
      parentIds,
    );
    final sonsByParent = <int, List<AssetRow>>{};
    for (final c in children) {
      sonsByParent
          .putIfAbsent(c['assetsId'] as int, () => [])
          .add(_assetFromRow(c));
    }
    return (
      data: [
        for (final r in parents)
          _assetFromRow(r, sons: sonsByParent[r['id'] as int] ?? const []),
      ],
      total: total,
    );
  }

  /// 批量生成对话框数据源（batchGenerationData 语义：仅父资产平铺）。
  ({List<AssetRow> data, int total}) batchGenerationData(
    int projectId, {
    required String type,
    int page = 1,
    int limit = 10,
    String? search,
  }) =>
      getAssets(projectId,
          type: type, page: page, limit: limit, search: search);

  /// 按 id 批量取资产（跨类型），供制作画布资产节点展示关联资产缩略图。
  List<AssetRow> assetsByIds(List<int> ids) {
    if (ids.isEmpty) return const [];
    final rows = db.select(
      '$_assetSelect WHERE a.id IN (${_ph(ids)})',
      ids,
    );
    return [for (final r in rows) _assetFromRow(r)];
  }

  List<AssetImageRow> assetImages(int assetsId) {
    final selectedId = db
        .select('SELECT imageId FROM o_assets WHERE id=?', [assetsId])
        .firstOrNull?['imageId'] as int?;
    return db
        .select(
          'SELECT * FROM o_image WHERE assetsId=? ORDER BY id',
          [assetsId],
        )
        .map((r) => AssetImageRow(
              id: r['id'] as int,
              filePath: r['filePath'] as String?,
              state: r['state'] as String?,
              errorReason: r['errorReason'] as String?,
              model: r['model'] as String?,
              resolution: r['resolution'] as String?,
              selected: r['id'] == selectedId,
            ))
        .toList();
  }

  // ───────── CRUD ─────────

  int addAsset({
    required int projectId,
    required String type,
    required String name,
    required String describe,
    String? remark,
    String? prompt,
    int? parentAssetsId,
  }) {
    db.execute(
      'INSERT INTO o_assets (name,describe,type,projectId,remark,prompt,assetsId,startTime) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        name,
        describe,
        type,
        projectId,
        remark,
        prompt,
        parentAssetsId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return db.lastInsertRowId;
  }

  void updateAsset(int id,
      {String? name, String? describe, String? remark, String? prompt}) {
    final sets = <String>[];
    final args = <Object?>[];
    void set(String col, Object? v) {
      if (v == null) return;
      sets.add('$col=?');
      args.add(v);
    }

    set('name', name);
    set('describe', describe);
    set('remark', remark);
    set('prompt', prompt);
    if (sets.isEmpty) return;
    args.add(id);
    db.execute('UPDATE o_assets SET ${sets.join(',')} WHERE id=?', args);
  }

  /// saveAssets 语义：base64→落盘+插已完成图+选中；imageId→仅选中。
  void saveAssetImage({
    required int assetsId,
    required int projectId,
    String? base64Image,
    int? imageId,
    String? prompt,
    required String type,
  }) {
    int? finalImageId = imageId;
    if (base64Image != null && base64Image.isNotEmpty) {
      final raw = base64Image.contains(',')
          ? base64Image.substring(base64Image.indexOf(',') + 1)
          : base64Image;
      final rel = media.saveImage(base64Decode(raw), '$projectId');
      db.execute(
        "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,?,?)",
        [assetsId, rel, type, stateDone],
      );
      finalImageId = db.lastInsertRowId;
    }
    final sets = <String>[];
    final args = <Object?>[];
    if (prompt != null) {
      sets.add('prompt=?');
      args.add(prompt);
    }
    if (finalImageId != null) {
      sets.add('imageId=?');
      args.add(finalImageId);
    }
    if (sets.isEmpty) return;
    args.add(assetsId);
    db.execute('UPDATE o_assets SET ${sets.join(',')} WHERE id=?', args);
  }

  /// 图片编辑器"保存"应用到资产：登记已落盘的 rel 路径为新图片版本并选中。
  void attachAssetImage(int assetsId, String rel, {int? flowId}) {
    final type = db
            .select('SELECT type FROM o_assets WHERE id=?', [assetsId])
            .firstOrNull?['type'] as String? ??
        'role';
    db.execute(
      "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,?,?)",
      [assetsId, rel, type, stateDone],
    );
    final imageId = db.lastInsertRowId;
    db.execute(
      'UPDATE o_assets SET imageId=?${flowId != null ? ',flowId=?' : ''} WHERE id=?',
      flowId != null ? [imageId, flowId, assetsId] : [imageId, assetsId],
    );
  }

  void deleteAssetImage(int imageId) {
    final rows =
        db.select('SELECT filePath FROM o_image WHERE id=?', [imageId]);
    db.execute('UPDATE o_assets SET imageId=NULL WHERE imageId=?', [imageId]);
    db.execute('DELETE FROM o_image WHERE id=?', [imageId]);
    final rel = rows.firstOrNull?['filePath'] as String?;
    if (rel != null && rel.isNotEmpty) {
      final f = File(media.absPath(rel));
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// 级联删除：含子资产与全部图片版本文件。
  void deleteAssets(List<int> ids) {
    if (ids.isEmpty) return;
    final all = <int>{...ids};
    for (final r in db.select(
      'SELECT id FROM o_assets WHERE assetsId IN (${_ph(ids)})',
      ids,
    )) {
      all.add(r['id'] as int);
    }
    final allList = all.toList();
    for (final r in db.select(
      'SELECT filePath FROM o_image WHERE assetsId IN (${_ph(allList)}) '
      'AND filePath IS NOT NULL',
      allList,
    )) {
      final f = File(media.absPath(r['filePath'] as String));
      if (f.existsSync()) f.deleteSync();
    }
    db.execute(
        'DELETE FROM o_image WHERE assetsId IN (${_ph(allList)})', allList);
    db.execute(
        'DELETE FROM o_scriptAssets WHERE assetId IN (${_ph(allList)})',
        allList);
    db.execute('DELETE FROM o_assets WHERE id IN (${_ph(allList)})', allList);
  }

  // ───────── 音频资产 ─────────

  /// addAudioAssets 语义：父(type=audio, describe="性别|描述") + 子条目（prompt=音频文本）。
  int addAudioAssets({
    required int projectId,
    required String name,
    required String sex,
    required String describe,
    required List<({String? base64, String? ext, String prompt, String name, String describe, int? existingImageId})>
        items,
  }) {
    final parentId = addAsset(
      projectId: projectId,
      type: 'audio',
      name: name,
      describe: '$sex|$describe',
    );
    _writeAudioItems(projectId, parentId, items);
    return parentId;
  }

  void updateAudioAssets({
    required int parentId,
    required int projectId,
    required String name,
    required String sex,
    required String describe,
    required List<({String? base64, String? ext, String prompt, String name, String describe, int? existingImageId})>
        items,
  }) {
    updateAsset(parentId, name: name, describe: '$sex|$describe');
    // 子条目全删重建（保留 existingImageId 引用的音频文件）
    final keepImageIds = items
        .map((i) => i.existingImageId)
        .whereType<int>()
        .toList();
    final oldChildren = db
        .select('SELECT id FROM o_assets WHERE assetsId=?', [parentId])
        .map((r) => r['id'] as int)
        .toList();
    if (oldChildren.isNotEmpty) {
      for (final r in db.select(
        'SELECT id,filePath FROM o_image WHERE assetsId IN (${_ph(oldChildren)})',
        oldChildren,
      )) {
        if (keepImageIds.contains(r['id'])) continue;
        final rel = r['filePath'] as String?;
        if (rel != null) {
          final f = File(media.absPath(rel));
          if (f.existsSync()) f.deleteSync();
        }
        db.execute('DELETE FROM o_image WHERE id=?', [r['id']]);
      }
      db.execute(
          'DELETE FROM o_assets WHERE id IN (${_ph(oldChildren)})', oldChildren);
    }
    _writeAudioItems(projectId, parentId, items);
  }

  void _writeAudioItems(
    int projectId,
    int parentId,
    List<({String? base64, String? ext, String prompt, String name, String describe, int? existingImageId})>
        items,
  ) {
    for (final item in items) {
      final childId = addAsset(
        projectId: projectId,
        type: 'audio',
        name: item.name,
        describe: item.describe,
        prompt: item.prompt,
        parentAssetsId: parentId,
      );
      db.execute('UPDATE o_assets SET prompt=? WHERE id=?',
          [item.prompt, childId]);
      int? imageId = item.existingImageId;
      if (item.base64 != null && item.base64!.isNotEmpty) {
        final raw = item.base64!.contains(',')
            ? item.base64!.substring(item.base64!.indexOf(',') + 1)
            : item.base64!;
        final ext = item.ext ?? 'mp3';
        final rel = '$projectId/assets_audio_${childId}_'
            '${DateTime.now().millisecondsSinceEpoch}.$ext';
        final f = File(media.absPath(rel));
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(base64Decode(raw));
        db.execute(
          "INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,'audio',?)",
          [childId, rel, stateDone],
        );
        imageId = db.lastInsertRowId;
      } else if (imageId != null) {
        db.execute(
            'UPDATE o_image SET assetsId=? WHERE id=?', [childId, imageId]);
      }
      if (imageId != null) {
        db.execute(
            'UPDATE o_assets SET imageId=? WHERE id=?', [imageId, childId]);
      }
    }
  }

  // ───────── 提示词润色 ─────────

  ({String system, String user}) _polishMessages(
      int projectId, String type, String name, String describe,
      {required bool isDerivative, String? otherTextPrompt}) {
    final cfg = _typeConfigs[type];
    if (cfg == null) {
      throw EngineException(errTaskUnsupported, {'type': type});
    }
    final artStyle = db
        .select('SELECT artStyle FROM o_project WHERE id=?', [projectId])
        .firstOrNull?['artStyle'] as String?;
    var system = '';
    if (artStyle != null && artStyle.isNotEmpty) {
      final pack = visualManuals()
          .where((p) => p.name == artStyle)
          .firstOrNull;
      system = pack?.data[
              isDerivative ? cfg.manualKeyDerivative : cfg.manualKey] ??
          '';
    }
    if (otherTextPrompt != null && otherTextPrompt.isNotEmpty) {
      system = '$system\n$otherTextPrompt';
    }
    // user 模板逐字照抄 polishAssetsPrompt.ts
    final user = '**基础参数：**\n'
        '**${cfg.nameLabel}设定：**\n'
        '- ${cfg.nameLabel}名称:$name,\n'
        '- ${cfg.nameLabel}描述:$describe,';
    return (system: system, user: user);
  }

  /// 单资产润色（对话框"智能生成"，同步等待返回）。
  Future<String> polishAssetPrompt(int assetsId) async {
    final row = db
        .select('SELECT * FROM o_assets WHERE id=?', [assetsId])
        .firstOrNull;
    if (row == null) {
      throw const EngineException(errPromptMissing, {'type': 'asset'});
    }
    db.execute(
        'UPDATE o_assets SET promptState=? WHERE id=?', [stateGenerating, assetsId]);
    try {
      final msgs = _polishMessages(
        (row['projectId'] as int?) ?? 0,
        (row['type'] as String?) ?? '',
        (row['name'] as String?) ?? '',
        (row['describe'] as String?) ?? '',
        isDerivative: row['assetsId'] != null,
      );
      final res = await gateway.generateText(msgs.system, msgs.user,
          stage: 'asset_extract');
      final prompt = res.content.trim();
      db.execute(
        'UPDATE o_assets SET prompt=?, promptState=?, promptErrorReason=NULL WHERE id=?',
        [prompt, stateDone, assetsId],
      );
      return prompt;
    } catch (e) {
      final ex = e is EngineException
          ? e
          : EngineException(errNetwork, {'message': '$e'});
      db.execute(
        'UPDATE o_assets SET promptState=?, promptErrorReason=? WHERE id=?',
        [stateFailed, ex.toReasonJson(), assetsId],
      );
      rethrow;
    }
  }

  /// 批量润色（队列任务，text lane）。
  int batchPolishAssetPrompts(int projectId, List<int> assetIds,
      {int concurrentCount = 5, String? otherTextPrompt}) {
    if (assetIds.isEmpty) return 0;
    db.execute(
      'UPDATE o_assets SET promptState=? WHERE id IN (${_ph(assetIds)})',
      [stateGenerating, ...assetIds],
    );
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'asset_prompt_polish',
      describe: '提示词批量润色',
      relatedObjects: {
        'kind': 'asset',
        'ids': assetIds,
        'concurrentCount': concurrentCount,
        if (otherTextPrompt != null) 'otherTextPrompt': otherTextPrompt,
      },
    );
  }

  Future<void> _runPromptPolish(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final ids = (related['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 5).clamp(1, 16);
    final other = related['otherTextPrompt'] as String?;
    var success = 0;
    EngineException? firstFailure;
    var cursor = 0;

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= ids.length) return;
        final id = ids[i];
        final row =
            db.select('SELECT * FROM o_assets WHERE id=?', [id]).firstOrNull;
        if (row == null) continue;
        try {
          final msgs = _polishMessages(
            (row['projectId'] as int?) ?? 0,
            (row['type'] as String?) ?? '',
            (row['name'] as String?) ?? '',
            (row['describe'] as String?) ?? '',
            isDerivative: row['assetsId'] != null,
            otherTextPrompt: other,
          );
          final res = await gateway.generateText(msgs.system, msgs.user,
              stage: 'asset_extract', cancelToken: token);
          db.execute(
            'UPDATE o_assets SET prompt=?, promptState=?, promptErrorReason=NULL WHERE id=?',
            [res.content.trim(), stateDone, id],
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
            'UPDATE o_assets SET promptState=?, promptErrorReason=? WHERE id=?',
            [stateFailed, ex.toReasonJson(), id],
          );
        }
      }
    }

    await Future.wait(
        [for (var w = 0; w < min(concurrent, ids.length); w++) worker()]);
    if (token.isCancelled) throw const EngineException(errCanceled);
    if (success == 0 && firstFailure != null) throw firstFailure!;
  }

  void _recoverPromptPolish(TasksRow task) {
    final ids = (task.relatedObjectsJson['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    if (ids.isEmpty) return;
    db.execute(
      'UPDATE o_assets SET promptState=?, promptErrorReason=? '
      'WHERE id IN (${_ph(ids)}) AND promptState=?',
      [
        stateFailed,
        const EngineException(errAppRestart).toReasonJson(),
        ...ids,
        stateGenerating,
      ],
    );
  }

  // ───────── 生图 ─────────

  String _imageUserPrompt(
      String type, String? artStyle, String name, String prompt) {
    final cfg = _typeConfigs[type]!;
    // 模板逐字照抄 generateAssets.ts
    return '请根据以下参数生成${cfg.promptTitle}：\n\n'
        '**基础参数：**\n'
        '- 画风风格: ${artStyle ?? ''}\n\n'
        '**${cfg.label}设定：**\n'
        '- 名称:$name,\n'
        '- 提示词:$prompt,\n\n'
        '请严格按照系统规范生成${cfg.promptEnd}。';
  }

  /// 生图（单个=1 项、批量=N 项，统一队列任务，image lane）。
  /// 预插 o_image(生成中) 并把 imageId 选中到资产（照抄语义），返回任务 id。
  int generateAssetImages(
    int projectId,
    List<({int assetsId, String? refImageBase64})> items, {
    String? resolution,
    int concurrentCount = 1,
  }) {
    if (items.isEmpty) return 0;
    final payload = <Map<String, Object?>>[];
    for (final item in items) {
      final row = db
          .select('SELECT type FROM o_assets WHERE id=?', [item.assetsId])
          .firstOrNull;
      if (row == null) continue;
      db.execute(
        'INSERT INTO o_image (assetsId,type,state,resolution) VALUES (?,?,?,?)',
        [item.assetsId, row['type'], stateGenerating, resolution],
      );
      final imageId = db.lastInsertRowId;
      db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
          [imageId, item.assetsId]);
      payload.add({
        'assetsId': item.assetsId,
        'imageId': imageId,
        if (item.refImageBase64 != null) 'refImageBase64': item.refImageBase64,
      });
    }
    if (payload.isEmpty) return 0;
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'asset_image_generation',
      describe: '资产图生成',
      relatedObjects: {
        'kind': 'asset',
        'items': payload,
        'ids': [for (final p in payload) p['assetsId']],
        'concurrentCount': concurrentCount,
      },
    );
  }

  Future<void> _runImageGeneration(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final items = (related['items'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 1).clamp(1, 8);
    final projectId = task.projectId ?? 0;
    final artStyle = db
        .select('SELECT artStyle FROM o_project WHERE id=?', [projectId])
        .firstOrNull?['artStyle'] as String?;

    var success = 0;
    EngineException? firstFailure;
    var cursor = 0;

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= items.length) return;
        final item = items[i];
        final assetsId = ((item['assetsId'] as num?) ?? 0).toInt();
        final imageId = ((item['imageId'] as num?) ?? 0).toInt();
        final row = db
            .select('SELECT * FROM o_assets WHERE id=?', [assetsId])
            .firstOrNull;
        if (row == null) continue;
        String? refPath;
        try {
          final b64 = item['refImageBase64'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            final raw = b64.contains(',')
                ? b64.substring(b64.indexOf(',') + 1)
                : b64;
            final tmp = File(
                '${Directory.systemTemp.path}/df_ref_$imageId.png');
            tmp.writeAsBytesSync(base64Decode(raw));
            refPath = tmp.path;
          }
          final user = _imageUserPrompt(
            (row['type'] as String?) ?? '',
            artStyle,
            (row['name'] as String?) ?? '',
            (row['prompt'] as String?) ?? '',
          );
          final rel = await gateway.generateImage(
            user,
            '$projectId',
            stage: 'asset_image',
            cancelToken: token,
            refImageAbsPath: refPath,
          );
          db.execute(
            'UPDATE o_image SET state=?, filePath=?, errorReason=NULL WHERE id=?',
            [stateDone, rel, imageId],
          );
          db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
              [imageId, assetsId]);
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
            'UPDATE o_image SET state=?, errorReason=? WHERE id=?',
            [stateFailed, ex.toReasonJson(), imageId],
          );
        } finally {
          if (refPath != null) {
            final f = File(refPath);
            if (f.existsSync()) f.deleteSync();
          }
        }
      }
    }

    await Future.wait(
        [for (var w = 0; w < min(concurrent, items.length); w++) worker()]);
    if (token.isCancelled) throw const EngineException(errCanceled);
    if (success == 0 && firstFailure != null) throw firstFailure!;
  }

  void _recoverImageGeneration(TasksRow task) {
    final items = (task.relatedObjectsJson['items'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    for (final item in items) {
      final imageId = ((item['imageId'] as num?) ?? 0).toInt();
      db.execute(
        'UPDATE o_image SET state=?, errorReason=? WHERE id=? AND state=?',
        [
          stateFailed,
          const EngineException(errAppRestart).toReasonJson(),
          imageId,
          stateGenerating,
        ],
      );
    }
  }
}
