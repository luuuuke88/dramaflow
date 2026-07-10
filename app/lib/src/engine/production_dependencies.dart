import 'prompt_resolver.dart';
import 'engine.dart';

const directorPlanStateKey = 'directorPlan';
const storyboardTableStateKey = 'storyboardTable';
const structuredStoryboardStateKey = 'structuredStoryboards';

class ProductionDependencyState {
  final int projectId;
  final int scriptId;
  final String key;
  final String sourceHash;
  final bool stale;
  final int updateTime;

  const ProductionDependencyState({
    required this.projectId,
    required this.scriptId,
    required this.key,
    required this.sourceHash,
    required this.stale,
    required this.updateTime,
  });
}

extension ProductionDependenciesApi on Engine {
  ProductionDependencyState productionDependencyState(
    int projectId,
    String key, {
    int scriptId = 0,
  }) {
    final row = db.select(
      'SELECT sourceHash,stale,updateTime '
      'FROM o_productionDependencyState '
      'WHERE projectId=? AND scriptId=? AND key=? LIMIT 1',
      [projectId, scriptId, key],
    ).firstOrNull;
    return ProductionDependencyState(
      projectId: projectId,
      scriptId: scriptId,
      key: key,
      sourceHash: (row?['sourceHash'] as String?) ?? '',
      stale: ((row?['stale'] as num?)?.toInt() ?? 0) != 0,
      updateTime: (row?['updateTime'] as num?)?.toInt() ?? 0,
    );
  }

  void setProductionDependencyState({
    required int projectId,
    required int scriptId,
    required String key,
    required String sourceHash,
    required bool stale,
  }) {
    db.execute(
      'INSERT INTO o_productionDependencyState '
      '(projectId,scriptId,key,sourceHash,stale,updateTime) VALUES (?,?,?,?,?,?) '
      'ON CONFLICT(projectId,scriptId,key) DO UPDATE SET '
      'sourceHash=excluded.sourceHash, stale=excluded.stale, '
      'updateTime=excluded.updateTime',
      [
        projectId,
        scriptId,
        key,
        sourceHash,
        stale ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  void markStoryboardTableAndShotsStale(int projectId, int scriptId) {
    for (final key in [storyboardTableStateKey, structuredStoryboardStateKey]) {
      final current =
          productionDependencyState(projectId, key, scriptId: scriptId);
      setProductionDependencyState(
        projectId: projectId,
        scriptId: scriptId,
        key: key,
        sourceHash: current.sourceHash,
        stale: true,
      );
    }
  }

  void markProjectStoryboardTablesAndShotsStale(int projectId) {
    final scriptIds = db
        .select('SELECT id FROM o_script WHERE projectId=? ORDER BY id',
            [projectId])
        .map((row) => row['id'] as int)
        .toList();
    for (final scriptId in scriptIds) {
      markStoryboardTableAndShotsStale(projectId, scriptId);
    }
  }

  String projectScriptsHash(int projectId) {
    final material = db
        .select(
          'SELECT id,name,content FROM o_script WHERE projectId=? ORDER BY id',
          [projectId],
        )
        .map((row) => [
              row['id'],
              row['name'] ?? '',
              row['content'] ?? '',
            ].join('\u0000'))
        .join('\n');
    return promptContentHash(material);
  }

  String scriptAssetsHash(int projectId, int scriptId) {
    final material = db
        .select(
          "SELECT a.id,a.type,a.name,a.describe FROM o_scriptAssets sa "
          "JOIN o_assets a ON a.id=sa.assetId "
          "WHERE sa.scriptId=? AND a.projectId=? "
          "AND a.type IN ('role','tool','scene') ORDER BY a.id",
          [scriptId, projectId],
        )
        .map((row) => [
              row['id'],
              row['type'] ?? '',
              row['name'] ?? '',
              row['describe'] ?? '',
            ].join('\u0000'))
        .join('\n');
    return promptContentHash(material);
  }
}
