// 分镜表节点（照抄 ToonFlow production storyboardTable：制作画布上的可编辑
// Markdown 文档节点，剧集级——存 o_agentWorkData(key='storyboardTable')，
// episodesId 绑定到 scriptId）。与 scriptPlan 共用一张 o_agentWorkData 表，
// 但 key 不同、episodesId 维度不同，互不干扰（见 script_plan.dart 的项目级模式）。
import 'engine.dart';
import 'production_dependencies.dart';
import 'prompt_resolver.dart';

const storyboardTableKey = 'storyboardTable';

extension StoryboardTableApi on Engine {
  /// 读取某剧集的分镜表 Markdown（无则返回空串）。
  String storyboardTable(int projectId, int scriptId) {
    final row = db.select(
      "SELECT data FROM o_agentWorkData "
      "WHERE projectId=? AND episodesId=? AND key='$storyboardTableKey'",
      [projectId, scriptId],
    ).firstOrNull;
    return (row?['data'] as String?) ?? '';
  }

  /// 写入/更新某剧集的分镜表 Markdown（upsert）。
  void saveStoryboardTable(int projectId, int scriptId, String markdown) {
    final exists = db.select(
      "SELECT id FROM o_agentWorkData "
      "WHERE projectId=? AND episodesId=? AND key='$storyboardTableKey'",
      [projectId, scriptId],
    ).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,episodesId,key,data,createTime,updateTime) '
        "VALUES (?,?,'$storyboardTableKey',?,?,?)",
        [projectId, scriptId, markdown, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [markdown, now, exists['id']],
      );
    }
    setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptId,
      key: storyboardTableStateKey,
      sourceHash: promptContentHash(markdown),
      stale: false,
    );
    final shots = productionDependencyState(
      projectId,
      structuredStoryboardStateKey,
      scriptId: scriptId,
    );
    setProductionDependencyState(
      projectId: projectId,
      scriptId: scriptId,
      key: structuredStoryboardStateKey,
      sourceHash: shots.sourceHash,
      stale: true,
    );
  }
}
