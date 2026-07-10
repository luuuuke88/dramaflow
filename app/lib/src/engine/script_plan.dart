// 剧本规划节点（照抄 ToonFlow scriptAgent/getPlanData/setPlanData）：
// 制作画布上的一个 Markdown 文档节点，项目级，存 o_agentWorkData(key='scriptPlan')。
// 与 Agent 对话共用同一张 o_agentWorkData 表，但 key 不同、互不干扰。
import 'package:dio/dio.dart';

import 'engine.dart';
import 'errors.dart';
import 'events.dart' show stripThink;
import 'production_dependencies.dart';
import 'prompt_resolver.dart';
import 'queue.dart';

const scriptPlanKey = 'scriptPlan';

extension ScriptPlanApi on Engine {
  void installScriptPlanPipeline() {
    taskRunners['director_plan_generation'] = _runDirectorPlanGeneration;
    queue.registerRecover('director_plan_generation', (_) {});
  }

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

  int generateDirectorPlan(int projectId) {
    final hasScripts = db.select(
      'SELECT id FROM o_script WHERE projectId=? LIMIT 1',
      [projectId],
    ).isNotEmpty;
    if (!hasScripts) return 0;
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'director_plan_generation',
      describe: '生成导演规划',
      relatedObjects: {
        'kind': 'project',
        'scriptsHash': projectScriptsHash(projectId),
      },
    );
  }

  Future<void> _runDirectorPlanGeneration(
    TasksRow task,
    CancelToken token,
  ) async {
    final projectId = task.projectId ?? 0;
    final rows = db.select(
      'SELECT id,name,content FROM o_script WHERE projectId=? ORDER BY id',
      [projectId],
    );
    if (rows.isEmpty) {
      throw const EngineException(errPromptMissing, {'type': 'scripts'});
    }
    final expectedHash =
        (task.relatedObjectsJson['scriptsHash'] ?? '').toString();
    if (expectedHash != projectScriptsHash(projectId)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'directorPlan:staleScripts'},
      );
    }
    final resolution = resolvePrompt(
      projectId: projectId,
      basePromptKey: 'director_plan',
      visualSection: 'director_planning_style',
      directorSection: 'director_planning_narrative',
      modelStage: 'director_plan',
      modelPromptPath: 'text/director_plan.md',
      requireModelPrompt: false,
    );
    final scripts = rows
        .map(
          (row) => '===== 【剧本ID: ${row['id']}】${row['name'] ?? ''} =====\n'
              '${row['content'] ?? ''}',
        )
        .join('\n\n');
    final user = '请根据以下项目剧本生成导演规划：\n\n$scripts';
    recordTaskPromptSources(
      task.id,
      resolution,
      requests: [
        PromptRequestTrace(
          targetType: 'project',
          targetId: projectId,
          sources: [
            ...resolution.sources,
            PromptSource(
              id: 'data:projectScripts:$projectId',
              kind: 'data',
              version: promptContentHash(scripts),
              content: scripts,
            ),
          ],
        ),
      ],
    );
    final result = await gateway.generateText(
      resolution.system,
      user,
      stage: 'director_plan',
      cancelToken: token,
    );
    if (token.isCancelled) throw const EngineException(errCanceled);
    final markdown = stripThink(result.content);
    if (markdown.isEmpty) {
      throw const EngineException(
          errLlmFormat, {'reason': 'empty_director_plan'});
    }
    saveScriptPlan(projectId, markdown);
  }
}
