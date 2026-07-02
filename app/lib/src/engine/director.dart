import 'dart:convert';

import '../api/models.dart';
import 'db.dart';
import 'engine.dart';
import 'util.dart';

/// 自动连跑导演循环：只读 DB 判断下一步，所有入队动作都走 Engine 既有方法。
class Director {
  final Engine engine;

  Director(this.engine);

  String _key(String projectId) => 'director.$projectId';

  DirectorState state(String projectId) {
    final rows = engine.db
        .select('SELECT value FROM settings WHERE key=?', [_key(projectId)]);
    if (rows.isEmpty) return DirectorState.off;
    try {
      final json = jsonDecode(rows.first['value'] as String);
      if (json is Map) {
        return DirectorState.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (_) {
      // 配置损坏时退回分步模式，避免自动循环误触发。
    }
    return DirectorState.off;
  }

  Future<void> startAuto(String projectId) async {
    _mustProject(projectId);
    _save(
      projectId,
      const DirectorState(
        mode: 'auto',
        scope: 'all',
        pausedReason: '',
        currentStage: '',
        finished: false,
        finishedAt: null,
      ),
    );
    await evaluate(projectId);
  }

  Future<void> stopAuto(String projectId) async {
    _mustProject(projectId);
    _save(projectId, DirectorState.off);
  }

  Future<void> onJobFinished(
      String jobId, String kind, String finalState) async {
    final rows = engine.db.select(
        'SELECT projectId, error FROM jobs WHERE id=? LIMIT 1', [jobId]);
    if (rows.isEmpty) return;
    final projectId = rows.first['projectId'] as String;
    final s = state(projectId);
    if (!s.isAuto) return;

    if (finalState == 'failed') {
      _pause(projectId, _stageLabel(kind),
          rows.first['error'] as String? ?? '未知错误');
      return;
    }
    if (finalState == 'done') {
      await evaluate(projectId);
    }
  }

  Future<void> evaluate(String projectId) async {
    final s = state(projectId);
    if (!s.isAuto || s.pausedReason.isNotEmpty) return;
    if (!_projectExists(projectId)) {
      _pause(projectId, '项目', '项目不存在');
      return;
    }

    final activeKind = _firstActiveKind(projectId);
    if (activeKind != null) {
      _setStage(projectId, _stageLabel(activeKind));
      return;
    }

    final episodeCount =
        _count('SELECT COUNT(*) FROM episodes WHERE projectId=?', [projectId]);
    if (episodeCount == 0) {
      await _enqueueStage(projectId, '剧本', () async {
        await engine.generateScript(projectId);
      });
      return;
    }

    final assetCount =
        _count('SELECT COUNT(*) FROM assets WHERE projectId=?', [projectId]);
    if (assetCount == 0) {
      await _enqueueStage(projectId, '素材提取', () async {
        await engine.extractAssets(projectId);
      });
      return;
    }

    final unfinishedAssets = _unfinishedAssets(projectId);
    if (unfinishedAssets.isNotEmpty) {
      final canEnqueue = unfinishedAssets.any((asset) {
        final status = asset.status;
        if (status == 'queued' || status == 'running') return false;
        if (status != 'failed') return true;
        return asset.maxAttempt < 2;
      });
      if (canEnqueue) {
        await _enqueueStage(
          projectId,
          '素材图',
          () async {
            await engine.generateAllAssetImages(
              projectId,
              retryFailedOnce: true,
            );
          },
        );
        return;
      }
      final failed = unfinishedAssets.firstWhere(
        (asset) => asset.status == 'failed',
        orElse: () => unfinishedAssets.first,
      );
      _pause(projectId, '素材图', failed.error ?? '素材图生成失败');
      return;
    }

    final episodesWithoutShots = engine.db.select('''
SELECT e.id
FROM episodes e
WHERE e.projectId=?
  AND NOT EXISTS (SELECT 1 FROM shots s WHERE s.episodeId=e.id)
ORDER BY e.idx
''', [projectId]).map((r) => r['id'] as String).toList();
    if (episodesWithoutShots.isNotEmpty) {
      await _enqueueStage(projectId, '分镜', () async {
        for (final episodeId in episodesWithoutShots) {
          await engine.generateStoryboard(episodeId);
        }
      });
      return;
    }

    final shotCount =
        _count('SELECT COUNT(*) FROM shots WHERE projectId=?', [projectId]);
    final shotImagesDone = _count(
        "SELECT COUNT(*) FROM shots WHERE projectId=? AND imageStatus='done' AND imagePath IS NOT NULL",
        [projectId]);
    if (shotCount > 0 && shotImagesDone < shotCount) {
      final episodeIds = engine.db.select('''
SELECT DISTINCT e.id, e.idx
FROM episodes e
JOIN shots s ON s.episodeId=e.id
WHERE e.projectId=?
  AND (s.imageStatus!='done' OR s.imagePath IS NULL)
ORDER BY e.idx
''', [projectId]).map((r) => r['id'] as String).toList();
      await _enqueueStage(projectId, '镜头图', () async {
        for (final episodeId in episodeIds) {
          await engine.generateAllShotImages(episodeId);
        }
      });
      return;
    }

    final shotsMissingVideo = engine.db.select('''
SELECT s.id
FROM shots s
JOIN episodes e ON e.id=s.episodeId
LEFT JOIN video_takes vt ON vt.id=s.selectedTakeId AND vt.shotId=s.id
WHERE s.projectId=?
  AND s.imageStatus='done'
  AND s.imagePath IS NOT NULL
  AND vt.id IS NULL
ORDER BY e.idx, s.idx
''', [projectId]).map((r) => r['id'] as String).toList();
    if (shotsMissingVideo.isNotEmpty) {
      await _enqueueStage(projectId, '视频', () async {
        for (final shotId in shotsMissingVideo) {
          await engine.generateShotVideo(shotId);
        }
      });
      return;
    }

    final episodesMissingCompose = engine.db.select('''
SELECT e.id
FROM episodes e
WHERE e.projectId=?
  AND EXISTS (SELECT 1 FROM shots s WHERE s.episodeId=e.id)
  AND (e.composeStatus!='done' OR e.composedPath IS NULL)
ORDER BY e.idx
''', [projectId]).map((r) => r['id'] as String).toList();
    if (episodesMissingCompose.isNotEmpty) {
      await _enqueueStage(projectId, '合成', () async {
        for (final episodeId in episodesMissingCompose) {
          await engine.composeEpisode(episodeId);
        }
      });
      return;
    }

    _save(
      projectId,
      DirectorState(
        mode: 'off',
        scope: 'all',
        pausedReason: '',
        currentStage: '完成',
        finished: true,
        finishedAt: nowIso(),
      ),
    );
  }

  Future<void> _enqueueStage(
    String projectId,
    String stage,
    Future<void> Function() action,
  ) async {
    _setStage(projectId, stage);
    try {
      await action();
    } on EngineException catch (e) {
      _pause(projectId, stage, e.message);
    } catch (e) {
      _pause(projectId, stage, errMessage(e));
    }
  }

  void _setStage(String projectId, String stage) {
    final s = state(projectId);
    if (!s.isAuto || s.pausedReason.isNotEmpty || s.currentStage == stage) {
      return;
    }
    _save(projectId, s.copyWith(currentStage: stage, finished: false));
  }

  void _pause(String projectId, String stage, String reason) {
    final trimmed = reason.trim().isEmpty ? '未知错误' : reason.trim();
    final brief = trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
    _save(
      projectId,
      DirectorState(
        mode: 'auto',
        scope: 'all',
        pausedReason: '$stage失败：$brief',
        currentStage: stage,
        finished: false,
        finishedAt: null,
      ),
    );
  }

  void _save(String projectId, DirectorState state) {
    engine.db.execute(
        'INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)',
        [_key(projectId), jsonEncode(state.toJson())]);
    engine.queue.notifyChanged();
  }

  void _mustProject(String projectId) {
    if (!_projectExists(projectId)) throw EngineException('项目不存在');
  }

  bool _projectExists(String projectId) => engine.db.select(
      'SELECT id FROM projects WHERE id=? LIMIT 1', [projectId]).isNotEmpty;

  int _count(String sql, [List<Object?> args = const []]) =>
      engine.db.select(sql, args).first.values.first as int;

  String? _firstActiveKind(String projectId) {
    final rows = engine.db.select('''
SELECT kind
FROM jobs
WHERE projectId=? AND state IN ('queued','running')
ORDER BY CASE state WHEN 'running' THEN 0 ELSE 1 END, createdAt
LIMIT 1
''', [projectId]);
    return rows.isEmpty ? null : rows.first['kind'] as String;
  }

  List<_AssetProgress> _unfinishedAssets(String projectId) => engine.db
      .select('''
SELECT a.id, a.status, a.error,
  COALESCE((
    SELECT MAX(j.attempt)
    FROM jobs j
    WHERE j.kind='asset_image' AND j.targetId=a.id
  ), 0) maxAttempt
FROM assets a
WHERE a.projectId=? AND a.status!='done'
ORDER BY a.createdAt
''', [projectId])
      .map((r) => _AssetProgress(
            id: r['id'] as String,
            status: r['status'] as String,
            error: r['error'] as String?,
            maxAttempt: r['maxAttempt'] as int,
          ))
      .toList();

  String _stageLabel(String kind) => switch (kind) {
        'script_gen' => '剧本',
        'asset_extract' => '素材提取',
        'asset_image' => '素材图',
        'storyboard_gen' => '分镜',
        'shot_image' => '镜头图',
        'shot_video' => '视频',
        'compose' => '合成',
        _ => '任务',
      };
}

class _AssetProgress {
  final String id;
  final String status;
  final String? error;
  final int maxAttempt;

  const _AssetProgress({
    required this.id,
    required this.status,
    required this.error,
    required this.maxAttempt,
  });
}
