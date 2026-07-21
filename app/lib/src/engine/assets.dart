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
import 'image_flow_cleanup.dart';
import 'manuals.dart';
import 'prompt_resolver.dart';
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
  final String? audioBindState;
  final String? filePath; // 选中图（o_image via imageId）
  final String? imageState;
  final String? imageErrorReason;
  final int? flowId; // 节点式图片编辑器画布（o_imageFlow.id）
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
    required this.audioBindState,
    required this.filePath,
    required this.imageState,
    required this.imageErrorReason,
    required this.flowId,
    this.sonAssets = const [],
  });

  /// audio：describe = "性别|描述"
  String get sex => (describe ?? '').split('|').first;
  String get audioDescribe {
    final parts = (describe ?? '').split('|');
    return parts.length > 1 ? parts.sublist(1).join('|') : '';
  }
}

/// 塑角造景卡片的只读数据，聚合父资产及其全部历史图片。
class CornerScapeAsset {
  final AssetRow asset;
  final List<AssetImageRow> images;

  const CornerScapeAsset({required this.asset, required this.images});
}

const _cornerScapeAssetTypes = {'role', 'scene', 'tool'};
const _clipVideoExtensions = {'mp4', 'webm', 'mov', 'avi', 'mkv'};
const _clipAudioExtensions = {'mp3', 'wav', 'ogg', 'aac', 'flac', 'm4a'};

/// ToonFlow 的素材库按实际文件扩展名区分 clip 是图片、视频还是音频。
/// 这个归类同时供资产筛选和视频请求使用，避免两条调用路径产生不同结论。
String clipMediaTypeForPath(String? localPath) {
  final path = (localPath ?? '').split('?').first;
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (_clipVideoExtensions.contains(extension)) return 'video';
  if (_clipAudioExtensions.contains(extension)) return 'audio';
  return 'image';
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
  'role': _TypeConfig('角色', '角色', '角色标准四视图', '人物角色四视图', 'role', 'art_character',
      'art_character_derivative'),
  'scene': _TypeConfig('场景', '场景', '标准场景图', '标准场景图', 'scene', 'art_scene',
      'art_scene_derivative'),
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
        audioBindState: r['audioBindState']?.toString(),
        filePath: r['filePath'] as String?,
        imageState: r['imageState'] as String?,
        imageErrorReason: r['imageErrorReason'] as String?,
        flowId: r['flowId'] as int?,
        sonAssets: sons,
      );

  static const _assetSelect = '''
SELECT a.*, i.filePath filePath, i.state imageState, i.errorReason imageErrorReason
FROM o_assets a LEFT JOIN o_image i ON i.id=a.imageId
''';

  ({List<AssetRow> data, int total}) getAssets(
    int projectId, {
    required String type,
    int page = 1,
    int limit = 10,
    String? search,
  }) {
    final where =
        StringBuffer('a.projectId=? AND a.type=? AND a.assetsId IS NULL');
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

  /// 通用资产选择器的数据源：按类型平铺父资产及其衍生子资产。
  ///
  /// 既有 [getAssets] 的页面列表只展示父资产；选择器需要允许选中
  /// ToonFlow 中可见的衍生资产，因此在这里保留父子顺序后展开。
  List<AssetRow> assetSelectionItems(
    int projectId, {
    required Set<String> types,
    String? search,
  }) {
    if (types.isEmpty) return const [];

    final result = <AssetRow>[];
    for (final type in types.toList()..sort()) {
      final page = getAssets(
        projectId,
        type: type,
        page: 1,
        // SQLite 的 LIMIT -1 表示不设上限；选择器再在 UI 逐页展示，避免静默漏项。
        limit: -1,
        search: search,
      );
      for (final parent in page.data) {
        result
          ..add(parent)
          ..addAll(parent.sonAssets);
      }
    }
    return result;
  }

  /// 按 id 批量取资产（跨类型），供制作画布资产节点展示关联资产缩略图。
  List<AssetRow> assetsByIds(List<int> ids) {
    if (ids.isEmpty) return const [];
    final parents = db.select(
      '$_assetSelect WHERE a.id IN (${_ph(ids)})',
      ids,
    );
    if (parents.isEmpty) return const [];
    final parentIds = [for (final parent in parents) parent['id'] as int];
    final children = db.select(
      '$_assetSelect WHERE a.assetsId IN (${_ph(parentIds)}) ORDER BY a.id',
      parentIds,
    );
    final childrenByParent = <int, List<AssetRow>>{};
    for (final child in children) {
      childrenByParent
          .putIfAbsent(child['assetsId'] as int, () => [])
          .add(_assetFromRow(child));
    }
    return [
      for (final parent in parents)
        _assetFromRow(
          parent,
          sons: childrenByParent[parent['id'] as int] ?? const [],
        ),
    ];
  }

  List<AssetImageRow> assetImages(int assetsId) {
    final selectedId = db.select('SELECT imageId FROM o_assets WHERE id=?',
        [assetsId]).firstOrNull?['imageId'] as int?;
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

  /// 塑角造景工作台的角色、场景和道具卡片数据。
  ///
  /// 仅复用资产和图片历史查询，不改变选中图片或任何生成状态。
  List<CornerScapeAsset> cornerScapeAssets(
    int projectId, {
    Set<String> types = const {'role', 'scene', 'tool'},
  }) {
    final values = <CornerScapeAsset>[];
    for (final type in types) {
      if (!_cornerScapeAssetTypes.contains(type)) continue;
      final assets =
          getAssets(projectId, type: type, page: 1, limit: 10000).data;
      values.addAll(
        assets.map(
          (asset) => CornerScapeAsset(
            asset: asset,
            images: assetImages(asset.id),
          ),
        ),
      );
    }
    return values;
  }

  /// 当前仍可取消的资产生图任务。
  ///
  /// 任务归属以队列 payload 的 `items[].assetsId` 为唯一依据；图片行即使仍处于
  /// “生成中”也不能反推到某个任务，避免误取消已经结束或不相关的任务。
  int? cornerScapeImageTaskId(int assetsId) {
    final tasks = db
        .select(
          "SELECT * FROM o_tasks WHERE taskClass='asset_image_generation' "
          "AND state IN ('pending','processing') ORDER BY id DESC",
        )
        .map(TasksRow.fromRow);
    for (final task in tasks) {
      final items = task.relatedObjectsJson['items'];
      if (items is! List) continue;
      final matches = items.whereType<Map>().any((item) {
        return (item['assetsId'] as num?)?.toInt() == assetsId;
      });
      if (matches) return task.id;
    }
    return null;
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

  /// 素材文件上传（照抄 uploadClip.ts）：真实图片/音频/视频文件落盘，
  /// 建 o_assets 行 + o_image 行并选中。ext 由调用方按文件名/MIME 提供，
  /// 默认 bin。返回新建的资产 id。
  int uploadClip({
    required int projectId,
    required String name,
    required List<int> bytes,
    String type = 'clip',
    String ext = 'bin',
  }) {
    final assetsId = addAsset(
      projectId: projectId,
      type: type,
      name: name.trim().isEmpty ? '素材' : name.trim(),
      describe: '',
    );
    final rel = '$projectId/assets_clip_${assetsId}_'
        '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final f = File(media.absPath(rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    db.execute(
      'INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,?,?)',
      [assetsId, rel, type, stateDone],
    );
    final imageId = db.lastInsertRowId;
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?', [imageId, assetsId]);
    return assetsId;
  }

  /// 将已经落在媒体目录中的文件登记为素材版本。用于合成导出这类先产出文件、
  /// 后进入素材库管理的路径，避免再次读取/复制大视频。
  int registerClipAsset({
    required int projectId,
    required String name,
    required String relPath,
    String type = 'clip',
  }) {
    final file = File(media.absPath(relPath));
    if (!file.existsSync()) {
      throw EngineException(errFileType, {'reason': 'file missing'});
    }
    final assetsId = addAsset(
      projectId: projectId,
      type: type,
      name: name.trim().isEmpty ? '素材' : name.trim(),
      describe: '',
    );
    db.execute(
      'INSERT INTO o_image (assetsId,filePath,type,state) VALUES (?,?,?,?)',
      [assetsId, relPath, type, stateDone],
    );
    final imageId = db.lastInsertRowId;
    db.execute('UPDATE o_assets SET imageId=? WHERE id=?', [imageId, assetsId]);
    return assetsId;
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
    final type = db.select('SELECT type FROM o_assets WHERE id=?',
            [assetsId]).firstOrNull?['type'] as String? ??
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
    final flowIds = imageFlowIdsForAssets(db, allList);
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
    db.execute('DELETE FROM o_scriptAssets WHERE assetId IN (${_ph(allList)})',
        allList);
    db.execute(
        'DELETE FROM o_assets2Storyboard WHERE assetId IN (${_ph(allList)})',
        allList);
    db.execute('DELETE FROM o_assets WHERE id IN (${_ph(allList)})', allList);
    clearUnreferencedImageFlows(db, flowIds);
  }

  // ───────── 音频资产 ─────────

  /// addAudioAssets 语义：父(type=audio, describe="性别|描述") + 子条目（prompt=音频文本）。
  int addAudioAssets({
    required int projectId,
    required String name,
    required String sex,
    required String describe,
    required List<
            ({
              String? base64,
              String? ext,
              String prompt,
              String name,
              String describe,
              int? existingImageId
            })>
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
    required List<
            ({
              String? base64,
              String? ext,
              String prompt,
              String name,
              String describe,
              int? existingImageId
            })>
        items,
  }) {
    updateAsset(parentId, name: name, describe: '$sex|$describe');
    // 子条目全删重建（保留 existingImageId 引用的音频文件）
    final keepImageIds =
        items.map((i) => i.existingImageId).whereType<int>().toList();
    final oldChildren = db
        .select('SELECT id FROM o_assets WHERE assetsId=?', [parentId])
        .map((r) => r['id'] as int)
        .toList();
    if (oldChildren.isNotEmpty) {
      final flowIds = imageFlowIdsForAssets(db, oldChildren);
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
        'DELETE FROM o_assets2Storyboard WHERE assetId IN (${_ph(oldChildren)})',
        oldChildren,
      );
      db.execute('DELETE FROM o_assets WHERE id IN (${_ph(oldChildren)})',
          oldChildren);
      clearUnreferencedImageFlows(db, flowIds);
    }
    _writeAudioItems(projectId, parentId, items);
  }

  void _writeAudioItems(
    int projectId,
    int parentId,
    List<
            ({
              String? base64,
              String? ext,
              String prompt,
              String name,
              String describe,
              int? existingImageId
            })>
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
      db.execute(
          'UPDATE o_assets SET prompt=? WHERE id=?', [item.prompt, childId]);
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

  ({
    PromptResolution resolution,
    String currentData,
    String system,
    String user,
  }) _polishMessages(int projectId, String type, String name, String describe,
      {required bool isDerivative, String? otherTextPrompt}) {
    final cfg = _typeConfigs[type];
    if (cfg == null) {
      throw EngineException(errTaskUnsupported, {'type': type});
    }
    final resolution = resolvePrompt(
      projectId: projectId,
      basePromptKey: 'asset_prompt_polish',
      visualSection: isDerivative ? cfg.manualKeyDerivative : cfg.manualKey,
    );
    // user 模板逐字照抄 polishAssetsPrompt.ts
    final currentData = '**基础参数：**\n'
        '**${cfg.nameLabel}设定：**\n'
        '- ${cfg.nameLabel}名称:$name,\n'
        '- ${cfg.nameLabel}描述:$describe,';
    var user = currentData;
    if (otherTextPrompt != null && otherTextPrompt.isNotEmpty) {
      user = '$user\n\n**补充要求：**\n$otherTextPrompt';
    }
    return (
      resolution: resolution,
      currentData: currentData,
      system: resolution.system,
      user: user,
    );
  }

  /// 单资产润色（对话框"智能生成"，同步等待返回）。
  Future<String> polishAssetPrompt(int assetsId) async {
    final row =
        db.select('SELECT * FROM o_assets WHERE id=?', [assetsId]).firstOrNull;
    if (row == null) {
      throw const EngineException(errPromptMissing, {'type': 'asset'});
    }
    db.execute('UPDATE o_assets SET promptState=? WHERE id=?',
        [stateGenerating, assetsId]);
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
    final taskId = queue.enqueue(
      projectId: projectId,
      taskClass: 'asset_prompt_polish',
      describe: '提示词批量润色',
      relatedObjects: {
        'kind': 'asset',
        'ids': assetIds,
        'concurrentCount': concurrentCount,
        if (otherTextPrompt != null && otherTextPrompt.isNotEmpty)
          'privateInstructionVersion': promptContentHash(otherTextPrompt),
      },
    );
    if (otherTextPrompt != null && otherTextPrompt.isNotEmpty) {
      try {
        writeTaskPrivatePayload(taskId, otherTextPrompt);
      } catch (e) {
        final reason = EngineException(errNetwork, {'message': '$e'});
        queue.cancel(taskId);
        deleteTaskPrivatePayload(taskId);
        db.execute('DELETE FROM o_tasks WHERE id=?', [taskId]);
        db.execute(
          'UPDATE o_assets SET promptState=?, promptErrorReason=? '
          'WHERE id IN (${_ph(assetIds)})',
          [stateFailed, reason.toReasonJson(), ...assetIds],
        );
        rethrow;
      }
    }
    return taskId;
  }

  Future<void> _runPromptPolish(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final ids = (related['ids'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 5).clamp(1, 16);
    final other = readTaskPrivatePayload(task.id);
    final expectedInstructionVersion =
        related['privateInstructionVersion'] as String?;
    if (expectedInstructionVersion != null &&
        (other == null ||
            promptContentHash(other) != expectedInstructionVersion)) {
      final reason = EngineException(
        errPromptMissing,
        {'type': 'privateInstruction:${task.id}'},
      );
      db.execute(
        'UPDATE o_assets SET promptState=?, promptErrorReason=? '
        'WHERE id IN (${_ph(ids)})',
        [stateFailed, reason.toReasonJson(), ...ids],
      );
      throw reason;
    }
    var success = 0;
    EngineException? firstFailure;
    var cursor = 0;
    final messagesById = <int,
        ({
      PromptResolution resolution,
      String currentData,
      String system,
      String user,
    })>{};

    for (final id in ids) {
      final row =
          db.select('SELECT * FROM o_assets WHERE id=?', [id]).firstOrNull;
      if (row == null) continue;
      try {
        messagesById[id] = _polishMessages(
          (row['projectId'] as int?) ?? 0,
          (row['type'] as String?) ?? '',
          (row['name'] as String?) ?? '',
          (row['describe'] as String?) ?? '',
          isDerivative: row['assetsId'] != null,
          otherTextPrompt: other,
        );
      } catch (e) {
        final ex = e is EngineException
            ? e
            : EngineException(errLlmFormat, {'message': '$e'});
        firstFailure ??= ex;
        db.execute(
          'UPDATE o_assets SET promptState=?, promptErrorReason=? WHERE id=?',
          [stateFailed, ex.toReasonJson(), id],
        );
      }
    }

    final uniqueSources = <String, PromptSource>{};
    for (final id in ids) {
      final messages = messagesById[id];
      if (messages == null) continue;
      for (final source in messages.resolution.sources) {
        uniqueSources.putIfAbsent(
          '${source.id}:${source.version}',
          () => source,
        );
      }
    }
    PromptSource? instructionSource;
    if (other != null && other.isNotEmpty && messagesById.isNotEmpty) {
      instructionSource = PromptSource(
        id: 'instruction:asset_prompt_polish',
        kind: 'instruction',
        version: promptContentHash(other),
        content: other,
      );
      uniqueSources['${instructionSource.id}:${instructionSource.version}'] =
          instructionSource;
    }
    if (uniqueSources.isNotEmpty) {
      final ordered = <PromptSource>[];
      for (final kind in const [
        'base',
        'visual',
        'director',
        'model',
        'instruction',
      ]) {
        ordered.addAll(
          uniqueSources.values.where((source) => source.kind == kind),
        );
      }
      recordTaskPromptSources(
        task.id,
        PromptResolution(system: '', sources: List.unmodifiable(ordered)),
        requests: [
          for (final id in ids)
            if (messagesById[id] case final messages?)
              PromptRequestTrace(
                targetType: 'asset',
                targetId: id,
                sources: List.unmodifiable([
                  ...messages.resolution.sources,
                  PromptSource(
                    id: 'data:asset:$id',
                    kind: 'data',
                    version: promptContentHash(messages.currentData),
                    content: messages.currentData,
                  ),
                  if (instructionSource != null) instructionSource,
                ]),
              ),
        ],
      );
    }

    final runIds = messagesById.keys.toList();

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = cursor++;
        if (i >= runIds.length) return;
        final id = runIds[i];
        final msgs = messagesById[id]!;
        try {
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

    await Future.wait([
      for (var w = 0; w < min(concurrent, runIds.length); w++) worker(),
    ]);
    if (token.isCancelled) throw const EngineException(errCanceled);
    if (success == 0 && firstFailure != null) throw firstFailure!;
    deleteTaskPrivatePayload(task.id);
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

  String _visualPackContext(int projectId) {
    final packId = db.select('SELECT artStyle FROM o_project WHERE id=?',
        [projectId]).firstOrNull?['artStyle'] as String?;
    if (packId == null || packId.isEmpty) return '';
    final pack =
        visualManuals().where((item) => item.pack == packId).firstOrNull;
    // Older Flutter projects stored a visible style string or prompt here.
    // Preserve that context until the project is next edited with a pack ID.
    if (pack == null) return packId;
    final prefix = pack.data['prefix']?.trim() ?? '';
    return prefix.isNotEmpty ? prefix : pack.name;
  }

  String _imageUserPrompt(
      String type, String visualContext, String name, String prompt) {
    final cfg = _typeConfigs[type]!;
    // 模板逐字照抄 generateAssets.ts
    return '请根据以下参数生成${cfg.promptTitle}：\n\n'
        '**基础参数：**\n'
        '- 画风风格: $visualContext\n\n'
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
    String? model,
    int concurrentCount = 1,
  }) {
    if (items.isEmpty) return 0;
    final payload = <Map<String, Object?>>[];
    for (final item in items) {
      final row = db.select(
          'SELECT type FROM o_assets WHERE id=?', [item.assetsId]).firstOrNull;
      if (row == null) continue;
      db.execute(
        'INSERT INTO o_image (assetsId,type,state,resolution) VALUES (?,?,?,?)',
        [item.assetsId, row['type'], stateGenerating, resolution],
      );
      final imageId = db.lastInsertRowId;
      db.execute(
          'UPDATE o_assets SET imageId=? WHERE id=?', [imageId, item.assetsId]);
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
        if (resolution != null) 'resolution': resolution,
        if (model != null) 'model': model,
      },
    );
  }

  /// 制作 Agent 的衍生资产批量出图：先按父/子描述生成衍生提示词，
  /// 再将父资产当前图片作为参考图生成子资产图片。
  ///
  /// 这是 ToonFlow production/assets/batchGenerateAssetsImage 的专用路径，
  /// 不与资产中心的普通批量生图混用。
  int generateDerivedAssetImages(
    int projectId,
    List<int> assetIds, {
    int concurrentCount = 5,
  }) {
    if (assetIds.isEmpty) return 0;
    final project = db.select(
      'SELECT imageModel,imageQuality FROM o_project WHERE id=?',
      [projectId],
    ).firstOrNull;
    if (project == null) return 0;
    final assets = db.select(
      'SELECT id,type FROM o_assets '
      'WHERE projectId=? AND assetsId IS NOT NULL '
      'AND id IN (${_ph(assetIds)})',
      [projectId, ...assetIds],
    );
    if (assets.isEmpty) return 0;

    final resolution = project['imageQuality'] as String?;
    final model = project['imageModel'] as String?;
    final payload = <Map<String, Object?>>[];
    for (final asset in assets) {
      final assetId = asset['id'] as int;
      db.execute(
        'INSERT INTO o_image (assetsId,type,state,resolution,model) '
        'VALUES (?,?,?,?,?)',
        [assetId, asset['type'], stateGenerating, resolution, model],
      );
      final imageId = db.lastInsertRowId;
      db.execute(
          'UPDATE o_assets SET imageId=? WHERE id=?', [imageId, assetId]);
      payload.add({
        'assetsId': assetId,
        'imageId': imageId,
        'derived': true,
      });
    }
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'asset_image_generation',
      describe: '衍生资产图片生成',
      relatedObjects: {
        'kind': 'derivedAsset',
        'items': payload,
        'ids': [for (final item in payload) item['assetsId']],
        'concurrentCount': concurrentCount,
        if (resolution != null && resolution.isNotEmpty)
          'resolution': resolution,
        if (model != null && model.isNotEmpty) 'model': model,
      },
    );
  }

  /// Creates fresh placeholders for unfinished items in a failed image task.
  /// The caller owns the savepoint that also inserts the replacement task.
  Map<String, dynamic> prepareAssetImageRetry(TasksRow task) {
    final projectId = task.projectId;
    if (projectId == null) {
      throw const EngineException(
        errLlmFormat,
        {'reason': '资产图片任务缺少项目'},
      );
    }
    final related = Map<String, dynamic>.from(task.relatedObjectsJson);
    final resolution = related['resolution'] as String?;
    final retryItems = <Map<String, dynamic>>[];
    final items =
        (related['items'] as List? ?? const []).whereType<Map>().toList();

    for (final item in items) {
      final assetsId = (item['assetsId'] as num?)?.toInt();
      if (assetsId == null) continue;
      final asset = db.select(
        'SELECT type FROM o_assets WHERE id=? AND projectId=? LIMIT 1',
        [assetsId, projectId],
      ).firstOrNull;
      if (asset == null) continue;

      final oldImageId = (item['imageId'] as num?)?.toInt();
      final oldState = oldImageId == null
          ? null
          : db.select(
              'SELECT state FROM o_image WHERE id=? AND assetsId=? LIMIT 1',
              [oldImageId, assetsId],
            ).firstOrNull?['state'] as String?;
      if (oldState == stateDone) continue;

      db.execute(
        'INSERT INTO o_image (assetsId,type,state,resolution) VALUES (?,?,?,?)',
        [assetsId, asset['type'], stateGenerating, resolution],
      );
      final imageId = db.lastInsertRowId;
      db.execute(
        'UPDATE o_assets SET imageId=? WHERE id=?',
        [imageId, assetsId],
      );
      retryItems.add(Map<String, dynamic>.from(item)..['imageId'] = imageId);
    }

    if (retryItems.isEmpty) {
      throw const EngineException(
        errLlmFormat,
        {'reason': '没有可重试的资产图片'},
      );
    }
    related['items'] = retryItems;
    related['ids'] = [
      for (final item in retryItems) item['assetsId'],
    ];
    return related;
  }

  Future<void> _runImageGeneration(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final resolution = related['resolution'] as String?;
    final modelOverride = related['model'] as String?;
    final items =
        (related['items'] as List? ?? const []).whereType<Map>().toList();
    final concurrent =
        ((related['concurrentCount'] as num?)?.toInt() ?? 1).clamp(1, 8);
    final projectId = task.projectId ?? 0;
    final visualContext = _visualPackContext(projectId);

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
        final row = db.select(
            'SELECT * FROM o_assets WHERE id=?', [assetsId]).firstOrNull;
        if (row == null) continue;
        String? temporaryRefPath;
        try {
          final isDerived = item['derived'] == true;
          final referencePaths = <String>[];
          final b64 = item['refImageBase64'] as String?;
          if (isDerived) {
            final parentId = row['assetsId'] as int?;
            final parent = parentId == null
                ? null
                : db.select(
                    'SELECT a.describe, i.filePath FROM o_assets a '
                    'LEFT JOIN o_image i ON i.id=a.imageId WHERE a.id=?',
                    [parentId],
                  ).firstOrNull;
            final cfg = _typeConfigs[row['type'] as String?];
            if (cfg == null) {
              throw EngineException(
                  errTaskUnsupported, {'type': row['type'] as String? ?? ''});
            }
            final prompt = resolvePrompt(
              projectId: projectId,
              basePromptKey: 'asset_prompt_polish',
              visualSection: cfg.manualKeyDerivative,
            );
            final result = await gateway.generateText(
              prompt.system,
              '父级资产描述: ${parent?['describe'] as String? ?? '无详细描述'}\n'
              '当前资产描述: ${row['describe'] as String? ?? '无详细描述'}',
              stage: 'asset_extract',
              cancelToken: token,
            );
            final derivedPrompt = result.content.trim();
            db.execute('UPDATE o_assets SET prompt=? WHERE id=?',
                [derivedPrompt, assetsId]);
            final parentRel = parent?['filePath'] as String?;
            if (parentRel != null) {
              final parentPath = media.existingFilePath(parentRel);
              if (parentPath != null) referencePaths.add(parentPath);
            }
            final rel = await gateway.generateImage(
              derivedPrompt,
              '$projectId',
              stage: 'asset_image',
              cancelToken: token,
              referenceAbsPaths: referencePaths,
              quality: resolution,
              modelOverride: modelOverride,
            );
            if (token.isCancelled) return;
            final imageState = db.select('SELECT state FROM o_image WHERE id=?',
                [imageId]).firstOrNull?['state'] as String?;
            // 目标行已不是 generating（含已被删除，此时 firstOrNull 为 null）：
            // 只应跳过当前这一项，不能 return——那会把整个 worker() 提前退出，
            // 饿死同一 worker 队列里排在后面、原本仍然合法的其它资产。
            if (imageState != stateGenerating) continue;
            db.execute(
              'UPDATE o_image SET state=?, filePath=?, errorReason=NULL '
              'WHERE id=? AND state=?',
              [stateDone, rel, imageId, stateGenerating],
            );
            db.execute('UPDATE o_assets SET imageId=? WHERE id=?',
                [imageId, assetsId]);
            success++;
            continue;
          }
          if (b64 != null && b64.isNotEmpty) {
            final raw =
                b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64;
            final tmp =
                File('${Directory.systemTemp.path}/df_ref_$imageId.png');
            tmp.writeAsBytesSync(base64Decode(raw));
            temporaryRefPath = tmp.path;
            referencePaths.add(temporaryRefPath);
          }
          final user = _imageUserPrompt(
            (row['type'] as String?) ?? '',
            visualContext,
            (row['name'] as String?) ?? '',
            (row['prompt'] as String?) ?? '',
          );
          final rel = await gateway.generateImage(
            user,
            '$projectId',
            stage: 'asset_image',
            cancelToken: token,
            referenceAbsPaths: referencePaths,
            quality: resolution,
            modelOverride: modelOverride,
          );
          if (token.isCancelled) return;
          final imageState = db.select('SELECT state FROM o_image WHERE id=?',
              [imageId]).firstOrNull?['state'] as String?;
          // 同上：目标行已不是 generating 时只跳过当前项，不能提前退出整个
          // worker()，否则会饿死同一 worker 后续排队的其它资产。
          if (imageState != stateGenerating) continue;
          db.execute(
            'UPDATE o_image SET state=?, filePath=?, errorReason=NULL '
            'WHERE id=? AND state=?',
            [stateDone, rel, imageId, stateGenerating],
          );
          db.execute(
              'UPDATE o_assets SET imageId=? WHERE id=?', [imageId, assetsId]);
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
          if (temporaryRefPath != null) {
            final f = File(temporaryRefPath);
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
