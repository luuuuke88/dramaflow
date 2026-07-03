// 配音绑定（cornerScape）：契约照抄 ToonFlow /api/cornerScape/batchBindAudio
// （详见 docs/reference/p4-workbench-brief.md §4）。一角色对一音频，写入
// o_assetsRole2Audio；语音合成不做（音频素材来自 P2 的音频资产上传），本模块
// 只做"LLM 按名称/描述匹配最合适音色"的绑定动作，复用 P2 的 tool-calling 模式。
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
          'roleId': {'type': 'integer'},
          'audioAssetId': {'type': 'integer'},
        },
        'required': ['roleId', 'audioAssetId'],
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

String _ph(List<int> ids) => List.filled(ids.length, '?').join(',');

extension AudioBindApi on Engine {
  void installAudioBindPipeline() {
    taskRunners['audio_bind'] = _runAudioBind;
    queue.registerRecover('audio_bind', _recoverAudioBind);
  }

  /// 当前项目内全部角色资产及其绑定音频（供 cornerScape 页展示）。
  List<RoleAudioBinding> roleAudioBindings(int projectId) {
    final roles = db.select(
      "SELECT id,name FROM o_assets WHERE projectId=? AND type='role' "
      'AND assetsId IS NULL ORDER BY id',
      [projectId],
    );
    if (roles.isEmpty) return const [];
    final roleIds = roles.map((r) => r['id'] as int).toList();
    final links = db.select(
      'SELECT assetsRoleId,assetsAudioId FROM o_assetsRole2Audio '
      'WHERE assetsRoleId IN (${_ph(roleIds)})',
      roleIds,
    );
    final audioByRole = {
      for (final l in links)
        l['assetsRoleId'] as int: l['assetsAudioId'] as int,
    };
    final audioIds = audioByRole.values.toSet().toList();
    final audioNames = audioIds.isEmpty
        ? <int, String>{}
        : {
            for (final r in db.select(
              'SELECT id,name FROM o_assets WHERE id IN (${_ph(audioIds)})',
              audioIds,
            ))
              r['id'] as int: (r['name'] as String?) ?? '',
          };
    return [
      for (final r in roles)
        RoleAudioBinding(
          roleId: r['id'] as int,
          roleName: r['name'] as String?,
          audioAssetId: audioByRole[r['id']],
          audioName: audioByRole[r['id']] != null
              ? audioNames[audioByRole[r['id']]]
              : null,
        ),
    ];
  }

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
      final row = db
          .select(
            'SELECT i.filePath filePath FROM o_assets a '
            'JOIN o_image i ON i.id=a.imageId '
            "WHERE a.id=? AND i.filePath IS NOT NULL AND i.filePath<>''",
            [assetId],
          )
          .firstOrNull;
      return row?['filePath'] as String?;
    }

    final own = relForAsset(audioAssetId);
    if (own != null) return media.absPath(own);
    // 回退：父资产的子资产（type=audio）里第一个带文件的。
    final child = db
        .select(
          "SELECT i.filePath filePath FROM o_assets a "
          'JOIN o_image i ON i.id=a.imageId '
          "WHERE a.assetsId=? AND i.filePath IS NOT NULL AND i.filePath<>'' "
          'ORDER BY a.id LIMIT 1',
          [audioAssetId],
        )
        .firstOrNull;
    final rel = child?['filePath'] as String?;
    return rel != null ? media.absPath(rel) : null;
  }

  /// 手动绑定/解绑（roleId 对应唯一一条记录，覆盖写入）。
  void bindRoleAudio(int roleId, int? audioAssetId) {
    db.execute('DELETE FROM o_assetsRole2Audio WHERE assetsRoleId=?', [roleId]);
    if (audioAssetId != null) {
      db.execute(
        'INSERT INTO o_assetsRole2Audio (assetsAudioId,assetsRoleId) VALUES (?,?)',
        [audioAssetId, roleId],
      );
    }
  }

  /// LLM 批量匹配绑定（队列任务，text lane）。
  int batchBindAudio(int projectId, List<int> roleIds) {
    if (roleIds.isEmpty) return 0;
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'audio_bind',
      describe: '配音绑定',
      relatedObjects: {'kind': 'role', 'roleIds': roleIds},
    );
  }

  Future<void> _runAudioBind(TasksRow task, CancelToken token) async {
    final related = task.relatedObjectsJson;
    final projectId = task.projectId ?? 0;
    final roleIds = (related['roleIds'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final pool = audioPool(projectId);
    if (pool.isEmpty) {
      throw EngineException(errPromptMissing, {'type': 'audioPool'});
    }
    final roles = db.select(
      'SELECT id,name,describe FROM o_assets WHERE id IN (${_ph(roleIds)})',
      roleIds,
    );
    final system = await getPrompt('audio_bind');
    final rolesDesc = [
      for (final r in roles)
        '角色ID:${r['id']} 名称:${r['name']} 描述:${r['describe'] ?? ''}',
    ].join('\n');
    final poolDesc = [
      for (final a in pool) '音频ID:${a.id} 名称:${a.name}',
    ].join('\n');
    final user = '候选音频列表：\n$poolDesc\n\n待匹配角色：\n$rolesDesc';
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
    for (final m in matches) {
      final roleId = ((m['roleId'] as num?) ?? 0).toInt();
      final audioId = ((m['audioAssetId'] as num?) ?? 0).toInt();
      if (!roleIds.contains(roleId) || !poolIds.contains(audioId)) continue;
      bindRoleAudio(roleId, audioId);
    }
  }

  void _recoverAudioBind(TasksRow task) {
    // 绑定动作本身是幂等覆盖写入，中断不会留下半绑定的脏状态，任务本身标记失败
    // 供用户重试即可（不需要额外实体状态补偿——与 storyboard_generate 的中断
    // 恢复策略一致）。
  }
}
