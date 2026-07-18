// 配音绑定（cornerScape）：契约照抄 ToonFlow /api/cornerScape/batchBindAudio
// （详见 docs/reference/p4-workbench-brief.md §4）。一资产对一音频，写入
// o_assetsRole2Audio；本模块只做"LLM 按名称/描述匹配最合适音色"的绑定动作，
// 复用 P2 的 tool-calling 模式。TTS 生成走素材中心的文本配音入口与 tts.dart。
import 'package:dio/dio.dart';

import 'engine.dart';
import 'errors.dart';
import 'queue.dart';

/// resultTool schema：批量匹配结果。
const audioBindToolSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'matches': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'assetId': {'type': 'integer'},
          'audioAssetId': {'type': 'integer'},
        },
        'required': ['assetId', 'audioAssetId'],
      },
    },
  },
  'required': ['matches'],
};

class RoleAudioBinding {
  final int roleId;
  final String? roleName;
  final int? audioAssetId;
  final String? audioName;
  const RoleAudioBinding({
    required this.roleId,
    required this.roleName,
    required this.audioAssetId,
    required this.audioName,
  });
}

class AssetAudioBinding {
  final int assetId;
  final String? assetName;
  final String assetType;
  final int? audioAssetId;
  final String? audioName;
  const AssetAudioBinding({
    required this.assetId,
    required this.assetName,
    required this.assetType,
    required this.audioAssetId,
    required this.audioName,
  });
}

String _ph(Iterable<Object?> values) =>
    List.filled(values.length, '?').join(',');

const _bindableAssetTypes = {'role', 'scene', 'tool'};

extension AudioBindApi on Engine {
  void installAudioBindPipeline() {
    taskRunners['audio_bind'] = _runAudioBind;
    queue.registerRecover('audio_bind', _recoverAudioBind);
  }

  /// 当前项目内的可配音父资产及其绑定音频。
  List<AssetAudioBinding> assetAudioBindings(
    int projectId, {
    Set<String> types = _bindableAssetTypes,
  }) {
    final selectedTypes = types.intersection(_bindableAssetTypes).toList();
    if (selectedTypes.isEmpty) return const [];
    final rows = db.select(
      'SELECT a.id assetId,a.name assetName,a.type assetType,'
      'au.id audioAssetId,au.name audioName '
      'FROM o_assets a '
      'LEFT JOIN o_assetsRole2Audio link ON link.assetsRoleId=a.id '
      'LEFT JOIN o_assets au ON au.id=link.assetsAudioId '
      "AND au.projectId=a.projectId AND au.type='audio' AND au.assetsId IS NULL "
      'WHERE a.projectId=? AND a.assetsId IS NULL '
      'AND a.type IN (${_ph(selectedTypes)}) '
      'ORDER BY a.id',
      [projectId, ...selectedTypes],
    );
    return [
      for (final row in rows)
        AssetAudioBinding(
          assetId: row['assetId'] as int,
          assetName: row['assetName'] as String?,
          assetType: row['assetType'] as String,
          audioAssetId: row['audioAssetId'] as int?,
          audioName: row['audioName'] as String?,
        ),
    ];
  }

  /// 历史角色查询 API，内部复用通用资产查询。
  List<RoleAudioBinding> roleAudioBindings(int projectId) => [
        for (final binding in assetAudioBindings(projectId, types: {'role'}))
          RoleAudioBinding(
            roleId: binding.assetId,
            roleName: binding.assetName,
            audioAssetId: binding.audioAssetId,
            audioName: binding.audioName,
          ),
      ];

  /// 可选音频池（audio 类型父资产，供手动绑定下拉与 LLM 匹配候选）。
  List<({int id, String name})> audioPool(int projectId) => db
      .select(
        "SELECT id,name FROM o_assets WHERE projectId=? AND type='audio' "
        'AND assetsId IS NULL ORDER BY id',
        [projectId],
      )
      .map((r) => (id: r['id'] as int, name: (r['name'] as String?) ?? ''))
      .toList();

  /// 解析可试听的音频文件绝对路径（供 cornerScape 试听）。传入音频**父资产** id
  /// （audioPool / 绑定关系里的 audioAssetId 都是父资产）。音频文件既可能挂在父资产自身
  /// 的 imageId 上，也可能挂在其某个子资产上（见 assets.dart _writeAudioItems 的落盘方式），
  /// 因此按父自身 → 首个可用子资产的顺序回退。找不到文件返回 null（UI 据此禁用试听）。
  String? audioAssetAbsPath(int audioAssetId) {
    String? relForAsset(int assetId) {
      final row = db.select(
        'SELECT i.filePath filePath FROM o_assets a '
        'JOIN o_image i ON i.id=a.imageId '
        "WHERE a.id=? AND i.filePath IS NOT NULL AND i.filePath<>''",
        [assetId],
      ).firstOrNull;
      return row?['filePath'] as String?;
    }

    final own = relForAsset(audioAssetId);
    if (own != null) return media.absPath(own);
    // 回退：父资产的子资产（type=audio）里第一个带文件的。
    final child = db.select(
      "SELECT i.filePath filePath FROM o_assets a "
      'JOIN o_image i ON i.id=a.imageId '
      "WHERE a.assetsId=? AND i.filePath IS NOT NULL AND i.filePath<>'' "
      'ORDER BY a.id LIMIT 1',
      [audioAssetId],
    ).firstOrNull;
    final rel = child?['filePath'] as String?;
    return rel != null ? media.absPath(rel) : null;
  }

  /// 手动绑定/解绑（仅允许项目内父角色/场景/道具绑定父音频）。
  void bindAssetAudio(int assetId, int? audioAssetId) {
    final target = db.select(
      'SELECT projectId FROM o_assets WHERE id=? AND assetsId IS NULL '
      'AND type IN (?,?,?)',
      [assetId, ..._bindableAssetTypes],
    ).firstOrNull;
    if (target == null) return;

    if (audioAssetId != null) {
      final audio = db.select(
        "SELECT id FROM o_assets WHERE id=? AND projectId=? "
        "AND type='audio' AND assetsId IS NULL",
        [audioAssetId, target['projectId']],
      ).firstOrNull;
      if (audio == null) return;
    }

    db.execute(
        'DELETE FROM o_assetsRole2Audio WHERE assetsRoleId=?', [assetId]);
    if (audioAssetId != null) {
      db.execute(
        'INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)',
        [audioAssetId, assetId],
      );
    }
  }

  /// 历史角色绑定 API，内部委托通用资产绑定。
  void bindRoleAudio(int roleId, int? audioAssetId) =>
      bindAssetAudio(roleId, audioAssetId);

  /// LLM 批量匹配绑定（队列任务，text lane）。
  int batchBindAudio(int projectId, List<int> assetIds) {
    if (assetIds.isEmpty) return 0;
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'audio_bind',
      describe: '配音绑定',
      relatedObjects: {'kind': 'asset', 'assetIds': assetIds},
    );
  }

  Future<void> _runAudioBind(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final projectId = task.projectId ?? 0;
    final assetIds = (related['assetIds'] as List? ??
            related['roleIds'] as List? ??
            const [])
        .map((e) => (e as num).toInt())
        .toList();
    final pool = audioPool(projectId);
    if (pool.isEmpty) {
      throw EngineException(errPromptMissing, {'type': 'audioPool'});
    }
    if (assetIds.isEmpty) return;
    final assets = db.select(
      'SELECT id,name,describe,type FROM o_assets WHERE projectId=? '
      'AND assetsId IS NULL AND type IN (?,?,?) '
      'AND id IN (${_ph(assetIds)})',
      [projectId, ..._bindableAssetTypes, ...assetIds],
    );
    if (assets.isEmpty) return;
    final system = await getPrompt('audio_bind');
    final assetsDesc = [
      for (final asset in assets)
        '资产ID:${asset['id']} 名称:${asset['name']} '
            '描述:${asset['describe'] ?? ''} 类型:${asset['type']}',
    ].join('\n');
    final poolDesc = [
      for (final a in pool) '音频ID:${a.id} 名称:${a.name}',
    ].join('\n');
    final user = '候选音频列表：\n$poolDesc\n\n待匹配资产：\n$assetsDesc';
    final result = await gateway.generateToolJson(
      system,
      user,
      stage: 'asset_extract',
      toolName: 'resultTool',
      schema: audioBindToolSchema,
      cancelToken: token,
    );
    final matches = (result['matches'] as List? ?? const []).whereType<Map>();
    if (matches.isEmpty) {
      throw const EngineException(errLlmFormat, {'reason': 'empty matches'});
    }
    final poolIds = pool.map((a) => a.id).toSet();
    final allowedAssetIds = assets.map((asset) => asset['id'] as int).toSet();
    for (final m in matches) {
      final assetId = (((m['assetId'] ?? m['roleId']) as num?) ?? 0).toInt();
      final audioId = ((m['audioAssetId'] as num?) ?? 0).toInt();
      if (!allowedAssetIds.contains(assetId) || !poolIds.contains(audioId)) {
        continue;
      }
      bindAssetAudio(assetId, audioId);
    }
  }

  void _recoverAudioBind(TasksRow task) {
    // 绑定动作本身是幂等覆盖写入，中断不会留下半绑定的脏状态，任务本身标记失败
    // 供用户重试即可（不需要额外实体状态补偿——与 storyboard_generate 的中断
    // 恢复策略一致）。
  }
}
