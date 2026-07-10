// 剧本规划节点（照抄 ToonFlow scriptAgent/getPlanData/setPlanData）：
// 制作画布上的一个 Markdown 文档节点，项目级，存 o_agentWorkData(key='scriptPlan')。
// 与 Agent 对话共用同一张 o_agentWorkData 表，但 key 不同、互不干扰。
import 'engine.dart';
import 'production_dependencies.dart';
import 'prompt_resolver.dart';

const scriptPlanKey = 'scriptPlan';

extension ScriptPlanApi on Engine {
  /// 读取项目的剧本规划 Markdown（无则返回空串）。
  String scriptPlan(int projectId) {
    final row = db.select(
      "SELECT data FROM o_agentWorkData "
      "WHERE projectId=? AND episodesId IS NULL AND key='$scriptPlanKey'",
      [projectId],
    ).firstOrNull;
    return (row?['data'] as String?) ?? '';
  }

  /// 写入/更新项目的剧本规划 Markdown（upsert）。
  void saveScriptPlan(int projectId, String markdown) {
    final exists = db.select(
      "SELECT id FROM o_agentWorkData "
      "WHERE projectId=? AND episodesId IS NULL AND key='$scriptPlanKey'",
      [projectId],
    ).firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exists == null) {
      db.execute(
        'INSERT INTO o_agentWorkData (projectId,key,data,createTime,updateTime) '
        "VALUES (?,'$scriptPlanKey',?,?,?)",
        [projectId, markdown, now, now],
      );
    } else {
      db.execute(
        'UPDATE o_agentWorkData SET data=?, updateTime=? WHERE id=?',
        [markdown, now, exists['id']],
      );
    }
    setProductionDependencyState(
      projectId: projectId,
      scriptId: 0,
      key: directorPlanStateKey,
      sourceHash: promptContentHash(markdown),
      stale: false,
    );
    markProjectStoryboardTablesAndShotsStale(projectId);
  }
}
