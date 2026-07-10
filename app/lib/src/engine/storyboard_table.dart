// 分镜表节点（照抄 ToonFlow production storyboardTable：制作画布上的可编辑
// Markdown 文档节点，剧集级——存 o_agentWorkData(key='storyboardTable')，
// episodesId 绑定到 scriptId）。与 scriptPlan 共用一张 o_agentWorkData 表，
// 但 key 不同、episodesId 维度不同，互不干扰（见 script_plan.dart 的项目级模式）。
import 'package:dio/dio.dart';

import 'engine.dart';
import 'errors.dart';
import 'events.dart' show stripThink;
import 'production_dependencies.dart';
import 'prompt_resolver.dart';
import 'queue.dart';
import 'script_plan.dart' show ScriptPlanApi;

const storyboardTableKey = 'storyboardTable';

extension StoryboardTableApi on Engine {
  void installStoryboardTablePipeline() {
    taskRunners['storyboard_table_generation'] = _runStoryboardTableGeneration;
    queue.registerRecover('storyboard_table_generation', (_) {});
  }

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

  int generateStoryboardTable(int projectId, int scriptId) {
    final script = db.select(
      'SELECT content FROM o_script WHERE id=? AND projectId=? LIMIT 1',
      [scriptId, projectId],
    ).firstOrNull;
    final plan = scriptPlan(projectId);
    if (script == null || plan.trim().isEmpty) return 0;
    final content = script['content'] as String? ?? '';
    return queue.enqueue(
      projectId: projectId,
      taskClass: 'storyboard_table_generation',
      describe: '生成分镜表',
      relatedObjects: {
        'kind': 'script',
        'scriptId': scriptId,
        'scriptHash': promptContentHash(content),
        'planHash': promptContentHash(plan),
        'assetsHash': scriptAssetsHash(projectId, scriptId),
      },
    );
  }

  Future<void> _runStoryboardTableGeneration(
    TasksRow task,
    CancelToken token,
  ) async {
    final projectId = task.projectId ?? 0;
    final related = task.relatedObjectsJson;
    final scriptId = ((related['scriptId'] as num?) ?? 0).toInt();
    final script = db.select(
      'SELECT content FROM o_script WHERE id=? AND projectId=? LIMIT 1',
      [scriptId, projectId],
    ).firstOrNull;
    if (script == null) {
      throw EngineException(
        errPromptMissing,
        {'type': 'storyboardTable:script:$scriptId'},
      );
    }
    final content = script['content'] as String? ?? '';
    final plan = scriptPlan(projectId);
    if (plan.trim().isEmpty) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboardTable:directorPlan'},
      );
    }
    if ((related['scriptHash'] ?? '').toString() !=
        promptContentHash(content)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboardTable:staleScript'},
      );
    }
    if ((related['planHash'] ?? '').toString() != promptContentHash(plan)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboardTable:stalePlan'},
      );
    }
    if ((related['assetsHash'] ?? '').toString() !=
        scriptAssetsHash(projectId, scriptId)) {
      throw const EngineException(
        errPromptMissing,
        {'type': 'storyboardTable:staleAssets'},
      );
    }

    final resolution = resolvePrompt(
      projectId: projectId,
      basePromptKey: 'storyboard_table',
      visualSection: 'director_storyboard_table_style',
      directorSection: 'director_storyboard_table_narrative',
      modelStage: 'storyboard_table',
      modelPromptPath: 'text/storyboard_table.md',
      requireModelPrompt: false,
    );
    final assets = db.select(
      "SELECT a.id,a.type,a.name,a.describe FROM o_scriptAssets sa "
      "JOIN o_assets a ON a.id=sa.assetId "
      "WHERE sa.scriptId=? AND a.projectId=? "
      "AND a.type IN ('role','tool','scene') ORDER BY a.id",
      [scriptId, projectId],
    ).map((row) {
      final name = (row['name'] as String? ?? '').trim();
      final type = (row['type'] as String? ?? '').trim();
      final describe = (row['describe'] as String? ?? '').trim();
      return '$name（$type）：$describe';
    }).join('\n');
    final user = '导演规划：\n$plan\n\n'
        '当前剧本：\n$content\n\n'
        '候选资产：\n${assets.isEmpty ? '（无）' : assets}';
    recordTaskPromptSources(
      task.id,
      resolution,
      requests: [
        PromptRequestTrace(
          targetType: 'script',
          targetId: scriptId,
          sources: [
            ...resolution.sources,
            PromptSource(
              id: 'data:directorPlan:$projectId',
              kind: 'data',
              version: promptContentHash(plan),
              content: plan,
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
              content: assets,
            ),
          ],
        ),
      ],
    );
    final result = await gateway.generateText(
      resolution.system,
      user,
      stage: 'storyboard_table',
      cancelToken: token,
    );
    if (token.isCancelled) throw const EngineException(errCanceled);
    final markdown = stripThink(result.content);
    if (markdown.isEmpty) {
      throw const EngineException(
        errLlmFormat,
        {'reason': 'empty_storyboard_table'},
      );
    }
    saveStoryboardTable(projectId, scriptId, markdown);
  }
}
