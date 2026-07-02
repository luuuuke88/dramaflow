import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';
import '../api/models.dart';
import 'compose.dart';
import 'config.dart';
import 'db.dart';
import 'director.dart';
import 'media.dart';
import 'providers/gateway.dart';
import 'providers/resolve.dart';
import 'pipeline/prompts.dart' as prompt_defs;
import 'pipeline/runners.dart';
import 'queue.dart';
import 'util.dart';

/// DramaFlow 内嵌引擎门面（移植 server/src/routes.ts 业务逻辑）。
/// App 级单例：main() 经 [Engine.boot] 创建一次；业务方法签名与 v0.1 ApiClient 一致。
class Engine {
  static const version = '0.2.0-m0';

  final Database db;
  final MediaStore media;
  final ProviderGateway gateway;
  final EngineConfig config;
  late final ComposeService compose;
  late final JobQueue queue;
  late final Director director;

  Engine({
    required this.db,
    required this.media,
    required this.gateway,
    required this.config,
    FfmpegRunner? ffmpegRunner,
    Duration queueTick = const Duration(milliseconds: 500),
  }) {
    _migrateLegacyVideoPaths(db);
    final runner = ffmpegRunner ?? const ProcessFfmpegRunner();
    compose = ComposeService(db: db, media: media, runner: runner);
    final runners = Runners(db, gateway, media, ffmpegRunner: runner);
    queue = JobQueue(db, run: runners.run, tick: queueTick);
    director = Director(this);
    queue.onJobFinished = (jobId, kind, state) {
      unawaited(director.onJobFinished(jobId, kind, state));
    };
  }

  /// 生产入口：开库、建媒体仓库、恢复中断任务、启动队列。
  static Future<Engine> boot(
      {required String dataDir,
      required bool isMobile,
      FfmpegRunner? ffmpegRunner}) async {
    Directory(dataDir).createSync(recursive: true);
    final db = openEngineDb(path.join(dataDir, 'dramaflow.sqlite'));
    final config = EngineConfig(db, isMobile: isMobile);
    _seedM2Defaults(db, config, isMobile: isMobile);
    final media = MediaStore(path.join(dataDir, 'media'));
    final engine = Engine(
        db: db,
        media: media,
        gateway: HttpProviderGateway(db, config, media),
        config: config,
        ffmpegRunner: ffmpegRunner);
    engine.queue.recoverOnColdStart();
    engine.queue.start();
    return engine;
  }

  String mediaAbsPath(String rel) => media.absPath(rel);

  Map<String, dynamic> _row(Row r) => Map<String, dynamic>.from(r);

  VideoTake _take(Row r) => VideoTake.fromJson(_row(r));

  static void _migrateLegacyVideoPaths(Database db) {
    final legacy = db.select('''
SELECT s.id shotId, s.videoPath
FROM shots s
WHERE s.videoPath IS NOT NULL
  AND s.videoPath != ''
  AND NOT EXISTS (
    SELECT 1 FROM video_takes vt
    WHERE vt.shotId=s.id AND vt.videoPath=s.videoPath
  )
''');
    if (legacy.isNotEmpty) {
      final stmt = db.prepare(
          'INSERT INTO video_takes (id,shotId,videoPath,createdAt) VALUES (?,?,?,?)');
      try {
        for (final row in legacy) {
          stmt.execute([
            newId(),
            row['shotId'] as String,
            row['videoPath'] as String,
            nowIso(),
          ]);
        }
      } finally {
        stmt.close();
      }
    }
    final needsSelection = db.select('''
SELECT s.id shotId, vt.id takeId, vt.videoPath
FROM shots s
JOIN video_takes vt ON vt.shotId=s.id AND vt.videoPath=s.videoPath
WHERE s.videoPath IS NOT NULL
  AND s.videoPath != ''
  AND s.selectedTakeId IS NULL
ORDER BY vt.createdAt ASC
''');
    final seen = <String>{};
    for (final row in needsSelection) {
      final shotId = row['shotId'] as String;
      if (!seen.add(shotId)) continue;
      db.execute(
          "UPDATE shots SET selectedTakeId=?, videoPath=?, videoStatus='done' WHERE id=?",
          [row['takeId'] as String, row['videoPath'] as String, shotId]);
    }
  }

  static void _seedM2Defaults(Database db, EngineConfig config,
      {required bool isMobile}) {
    if ((db.select('SELECT COUNT(*) n FROM providers').first['n'] as int) ==
        0) {
      final now = nowIso();
      void provider(String id, String name, String protocol, String baseUrl,
          String apiKey) {
        db.execute(
            'INSERT INTO providers (id,name,protocol,baseUrl,apiKey,createdAt) VALUES (?,?,?,?,?,?)',
            [id, name, protocol, baseUrl, apiKey, now]);
      }

      void model(String providerId, String modelId, String label, String kind,
          [Map<String, dynamic> capabilities = const {}]) {
        db.execute(
            'INSERT INTO provider_models (id,providerId,modelId,label,kind,capabilities,enabled) VALUES (?,?,?,?,?,?,1)',
            [
              '$providerId:$modelId',
              providerId,
              modelId,
              label,
              kind,
              jsonEncode(capabilities)
            ]);
      }

      if (!isMobile) {
        provider('azt', 'azt', 'openai_compatible', 'http://127.0.0.1:8787/v1',
            'local');
        for (final modelId in ['gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini']) {
          model('azt', modelId, modelId, 'text');
        }
        model('azt', 'gpt-image-2', 'gpt-image-2', 'image');
      }

      provider(
          'volcengine',
          'volcengine',
          'volcengine',
          'https://ark.cn-beijing.volces.com/api/v3',
          isMobile ? '' : config.str('videoApiKey'));
      model('volcengine', 'doubao-seed-1-6-250615', 'doubao-seed-1-6-250615',
          'text');
      model('volcengine', 'doubao-seedream-4-0-250828',
          'doubao-seedream-4-0-250828', 'image');
      model('volcengine', 'doubao-seedance-2-0-mini-260615',
          'doubao-seedance-2-0-mini-260615', 'video', {
        'durations': [for (var i = 4; i <= 15; i++) i],
        'resolutions': ['480p', '720p']
      });
    }

    void binding(String stage, String value) {
      final key = 'binding.$stage';
      final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
      if (rows.isEmpty || (rows.first['value'] as String).trim().isEmpty) {
        db.execute('INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)',
            [key, value]);
      }
    }

    if (isMobile) {
      binding('script_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('asset_extract', 'volcengine:doubao-seed-1-6-250615');
      binding('storyboard_gen', 'volcengine:doubao-seed-1-6-250615');
      binding('asset_image', 'volcengine:doubao-seedream-4-0-250828');
      binding('shot_image', 'volcengine:doubao-seedream-4-0-250828');
      binding('shot_video', 'volcengine:doubao-seedance-2-0-mini-260615');
    } else {
      binding('script_gen', 'azt:gpt-5.5');
      binding('asset_extract', 'azt:gpt-5.5');
      binding('storyboard_gen', 'azt:gpt-5.5');
      binding('asset_image', 'azt:gpt-image-2');
      binding('shot_image', 'azt:gpt-image-2');
      binding('shot_video', 'volcengine:doubao-seedance-2-0-mini-260615');
    }

    if ((db.select('SELECT COUNT(*) n FROM prompts').first['n'] as int) == 0) {
      final now = nowIso();
      final prompts = {
        ...prompt_defs.defaultSystemPrompts,
        prompt_defs.promptKeyImageSizeDirective:
            config.str('imageSizeDirective'),
      };
      final stmt = db.prepare(
          'INSERT INTO prompts (key,content,updatedAt) VALUES (?,?,?)');
      try {
        for (final entry in prompts.entries) {
          stmt.execute([entry.key, entry.value, now]);
        }
      } finally {
        stmt.close();
      }
    }
  }

  // ---------- health ----------

  Future<Map<String, dynamic>> health() async => {
        'version': version,
        'providers': {
          'text': '${config.str('textBaseUrl')} / ${config.str('textModel')}',
          'image':
              '${config.str('imageBaseUrl')} / ${config.str('imageModel')}',
          'video': config.str('videoApiKey').isNotEmpty
              ? 'configured (${config.str('videoModel')})'
              : 'unconfigured',
        },
      };

  // ---------- projects ----------

  Map<String, dynamic> _projectStats(String projectId) {
    int one(String sql) =>
        db.select(sql, [projectId]).first.values.first as int;
    return {
      'episodes': one('SELECT COUNT(*) FROM episodes WHERE projectId=?'),
      'assets': one('SELECT COUNT(*) FROM assets WHERE projectId=?'),
      'assetsDone': one(
          "SELECT COUNT(*) FROM assets WHERE projectId=? AND status='done'"),
      'shots': one('SELECT COUNT(*) FROM shots WHERE projectId=?'),
      'shotsImageDone': one(
          "SELECT COUNT(*) FROM shots WHERE projectId=? AND imageStatus='done'"),
      'shotsVideoDone': one(
          "SELECT COUNT(*) FROM shots WHERE projectId=? AND videoStatus='done'"),
      'hasNovel':
          one("SELECT COUNT(*) FROM novels WHERE projectId=? AND content != ''") >
              0,
    };
  }

  Project _project(Row r) {
    final m = _row(r);
    m['stats'] = _projectStats(r['id'] as String);
    return Project.fromJson(m);
  }

  Future<List<Project>> listProjects() async => db
      .select('SELECT * FROM projects ORDER BY updatedAt DESC')
      .map(_project)
      .toList();

  Future<Project> createProject(String name, {String artStyle = ''}) async {
    if (name.trim().isEmpty) throw EngineException('项目名不能为空');
    final id = newId();
    final now = nowIso();
    db.execute(
        'INSERT INTO projects (id, name, artStyle, createdAt, updatedAt) VALUES (?,?,?,?,?)',
        [id, name.trim(), artStyle, now, now]);
    return getProject(id);
  }

  Row _mustProject(String id) {
    final rows = db.select('SELECT * FROM projects WHERE id=?', [id]);
    if (rows.isEmpty) throw EngineException('项目不存在');
    return rows.first;
  }

  Future<Project> getProject(String id) async => _project(_mustProject(id));

  Future<Project> updateProject(String id,
      {String? name, String? artStyle}) async {
    _mustProject(id);
    db.execute(
        'UPDATE projects SET name=COALESCE(?,name), artStyle=COALESCE(?,artStyle), updatedAt=? WHERE id=?',
        [name, artStyle, nowIso(), id]);
    return getProject(id);
  }

  Future<void> deleteProject(String id) async {
    db.execute('DELETE FROM projects WHERE id=?', [id]);
    db.execute('DELETE FROM jobs WHERE projectId=?', [id]);
    media.deleteProject(id);
  }

  // ---------- novel ----------

  Future<Novel?> getNovel(String projectId) async {
    final rows = db.select(
        'SELECT id, title, content FROM novels WHERE projectId=?', [projectId]);
    return rows.isEmpty ? null : Novel.fromJson(_row(rows.first));
  }

  Future<Novel> saveNovel(String projectId,
      {required String title, required String content}) async {
    _mustProject(projectId);
    if (content.trim().isEmpty) throw EngineException('小说内容不能为空');
    final existing =
        db.select('SELECT id FROM novels WHERE projectId=?', [projectId]);
    if (existing.isNotEmpty) {
      db.execute('UPDATE novels SET title=?, content=?, updatedAt=? WHERE id=?',
          [title, content, nowIso(), existing.first['id']]);
    } else {
      db.execute(
          'INSERT INTO novels (id, projectId, title, content, updatedAt) VALUES (?,?,?,?,?)',
          [newId(), projectId, title, content, nowIso()]);
    }
    db.execute(
        'UPDATE projects SET updatedAt=? WHERE id=?', [nowIso(), projectId]);
    return (await getNovel(projectId))!;
  }

  // ---------- script generation & episodes ----------

  Future<String> generateScript(String projectId, {int? episodeCount}) async {
    _mustProject(projectId);
    final novel =
        db.select('SELECT content FROM novels WHERE projectId=?', [projectId]);
    if (novel.isEmpty || (novel.first['content'] as String).trim().isEmpty) {
      throw EngineException('请先导入小说');
    }
    if (queue.hasActiveJob('script_gen', projectId)) {
      throw EngineException('剧本生成任务已在进行中');
    }
    final downstream = db.select(
        "SELECT COUNT(*) n FROM jobs WHERE projectId=? AND state IN ('queued','running') AND kind IN ('storyboard_gen','shot_image','shot_video','compose')",
        [projectId]).first['n'] as int;
    if (downstream > 0) {
      throw EngineException('有分镜/镜头图/视频任务进行中，请等待完成或取消后再重新生成剧本');
    }
    return queue.enqueue(
        projectId: projectId,
        kind: 'script_gen',
        targetId: projectId,
        targetLabel: '剧本生成',
        payload: {if (episodeCount != null) 'episodeCount': episodeCount});
  }

  Future<List<EpisodeSummary>> listEpisodes(String projectId) async =>
      db.select(
        'SELECT id, idx, title, synopsis, scriptJson FROM episodes WHERE projectId=? ORDER BY idx',
        [projectId],
      ).map((r) {
        final shotCount = db.select(
            'SELECT COUNT(*) n FROM shots WHERE episodeId=?',
            [r['id']]).first['n'] as int;
        return EpisodeSummary.fromJson({
          ..._row(r),
          'sceneCount': (jsonDecode(r['scriptJson'] as String) as List).length,
          'shotCount': shotCount,
        });
      }).toList();

  Future<Episode> getEpisode(String id) async {
    final rows = db.select('SELECT * FROM episodes WHERE id=?', [id]);
    if (rows.isEmpty) throw EngineException('剧集不存在');
    final m = _row(rows.first);
    m['scenes'] = jsonDecode(m['scriptJson'] as String);
    return Episode.fromJson(m);
  }

  Future<Episode> updateEpisode(String id,
      {String? title, String? synopsis, List<Scene>? scenes}) async {
    db.execute(
        'UPDATE episodes SET title=COALESCE(?,title), synopsis=COALESCE(?,synopsis), scriptJson=COALESCE(?,scriptJson) WHERE id=?',
        [
          title,
          synopsis,
          scenes != null
              ? jsonEncode(scenes.map((s) => s.toJson()).toList())
              : null,
          id
        ]);
    return getEpisode(id);
  }

  // ---------- assets ----------

  Future<String> extractAssets(String projectId) async {
    final n = db.select('SELECT COUNT(*) n FROM episodes WHERE projectId=?',
        [projectId]).first['n'] as int;
    if (n == 0) throw EngineException('请先生成剧本');
    if (queue.hasActiveJob('asset_extract', projectId)) {
      throw EngineException('资产提取任务已在进行中');
    }
    return queue.enqueue(
        projectId: projectId,
        kind: 'asset_extract',
        targetId: projectId,
        targetLabel: '素材提取');
  }

  Asset _asset(Row r) {
    final m = _row(r);
    m['imageUrl'] = m['imagePath']; // rel 路径，UI 经 mediaAbsPath 转绝对
    return Asset.fromJson(m);
  }

  Future<List<Asset>> listAssets(String projectId) async => db
      .select('SELECT * FROM assets WHERE projectId=? ORDER BY kind, createdAt',
          [projectId])
      .map(_asset)
      .toList();

  Future<Asset> createAsset(String projectId,
      {required String kind,
      required String name,
      String description = '',
      String imagePrompt = '',
      String note = ''}) async {
    if (!const {'character', 'scene', 'prop'}.contains(kind)) {
      throw EngineException('资产类型无效');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw EngineException('名称不能为空');
    _mustProject(projectId);
    final existing = db.select(
        'SELECT id FROM assets WHERE projectId=? AND kind=? AND name=? LIMIT 1',
        [projectId, kind, trimmedName]);
    if (existing.isNotEmpty) throw EngineException('同名资产已存在');

    final id = newId();
    db.execute(
        "INSERT INTO assets (id, projectId, kind, name, description, imagePrompt, note, status, createdAt) VALUES (?,?,?,?,?,?,?,'draft',?)",
        [
          id,
          projectId,
          kind,
          trimmedName,
          description,
          imagePrompt,
          note,
          nowIso()
        ]);
    return _asset(db.select('SELECT * FROM assets WHERE id=?', [id]).first);
  }

  Future<void> deleteAssets(List<String> ids) async {
    for (final id in ids) {
      if (queue.hasActiveJob('asset_image', id)) {
        throw EngineException('有资产正在生成图片，请先取消或等待完成');
      }
    }
    final del = db.prepare('DELETE FROM assets WHERE id=?');
    try {
      for (final id in ids) {
        del.execute([id]);
      }
    } finally {
      del.close();
    }
  }

  Future<Asset> updateAsset(String id,
      {String? name,
      String? description,
      String? imagePrompt,
      String? note}) async {
    final rows = db.select('SELECT id FROM assets WHERE id=?', [id]);
    if (rows.isEmpty) throw EngineException('资产不存在');
    db.execute(
        'UPDATE assets SET name=COALESCE(?,name), description=COALESCE(?,description), imagePrompt=COALESCE(?,imagePrompt), note=COALESCE(?,note) WHERE id=?',
        [name, description, imagePrompt, note, id]);
    return _asset(db.select('SELECT * FROM assets WHERE id=?', [id]).first);
  }

  String? _enqueueAssetImage(String assetId, {int attempt = 1}) {
    final rows = db
        .select('SELECT id, projectId, name FROM assets WHERE id=?', [assetId]);
    if (rows.isEmpty) return null;
    final a = rows.first;
    if (queue.hasActiveJob('asset_image', assetId)) return null;
    db.execute(
        "UPDATE assets SET status='queued', error=NULL WHERE id=?", [assetId]);
    return queue.enqueue(
        projectId: a['projectId'] as String,
        kind: 'asset_image',
        targetId: assetId,
        targetLabel: '素材图·${a['name']}',
        attempt: attempt);
  }

  Future<String?> generateAssetImage(String assetId) async {
    if (db.select('SELECT id FROM assets WHERE id=?', [assetId]).isEmpty) {
      throw EngineException('资产不存在');
    }
    if (queue.hasActiveJob('asset_image', assetId)) {
      throw EngineException('该资产已有生成任务进行中');
    }
    return _enqueueAssetImage(assetId);
  }

  Future<List<String>> generateAllAssetImages(String projectId,
      {bool retryFailedOnce = false}) async {
    final rows = retryFailedOnce
        ? db.select('''
SELECT a.id, a.status,
  COALESCE((
    SELECT MAX(j.attempt)
    FROM jobs j
    WHERE j.kind='asset_image' AND j.targetId=a.id
  ), 0) maxAttempt
FROM assets a
WHERE a.projectId=?
  AND a.status NOT IN ('done','queued','running')
''', [projectId])
        : db.select(
            "SELECT id, status, 0 maxAttempt FROM assets WHERE projectId=? AND status NOT IN ('done','queued','running')",
            [projectId]);
    return rows
        .map((r) {
          final status = r['status'] as String;
          var attempt = 1;
          if (retryFailedOnce && status == 'failed') {
            final maxAttempt = r['maxAttempt'] as int;
            if (maxAttempt >= 2) return null;
            attempt = maxAttempt <= 0 ? 2 : maxAttempt + 1;
          }
          return _enqueueAssetImage(r['id'] as String, attempt: attempt);
        })
        .whereType<String>()
        .toList();
  }

  // ---------- storyboard & shots ----------

  Future<String> generateStoryboard(String episodeId) async {
    final rows = db.select(
        'SELECT id, projectId, title FROM episodes WHERE id=?', [episodeId]);
    if (rows.isEmpty) throw EngineException('剧集不存在');
    final ep = rows.first;
    if (queue.hasActiveJob('storyboard_gen', episodeId)) {
      throw EngineException('分镜生成任务已在进行中');
    }
    final downstream = db.select(
        "SELECT COUNT(*) n FROM jobs WHERE state IN ('queued','running') AND ((kind IN ('shot_image','shot_video') AND targetId IN (SELECT id FROM shots WHERE episodeId=?)) OR (kind='compose' AND targetId=?))",
        [episodeId, episodeId]).first['n'] as int;
    if (downstream > 0) {
      throw EngineException('本集有镜头图/视频任务进行中，请等待完成或取消后再重新生成分镜');
    }
    return queue.enqueue(
        projectId: ep['projectId'] as String,
        kind: 'storyboard_gen',
        targetId: episodeId,
        targetLabel: '分镜·${ep['title']}');
  }

  Shot _shot(Row r) {
    final m = _row(r);
    m['assetNames'] = jsonDecode((m['assetNames'] as String?) ?? '[]');
    m['imageUrl'] = m['imagePath'];
    m['videoUrl'] = m['videoPath'];
    return Shot.fromJson(m);
  }

  Future<List<Shot>> listShots(String episodeId) async => db
      .select('SELECT * FROM shots WHERE episodeId=? ORDER BY idx', [episodeId])
      .map(_shot)
      .toList();

  Future<List<VideoTake>> listTakes(String shotId) async {
    if (db.select('SELECT id FROM shots WHERE id=?', [shotId]).isEmpty) {
      throw EngineException('镜头不存在');
    }
    return db
        .select(
            'SELECT * FROM video_takes WHERE shotId=? ORDER BY createdAt DESC, id DESC',
            [shotId])
        .map(_take)
        .toList();
  }

  Future<void> selectTake(String shotId, String takeId) async {
    final rows = db.select(
        'SELECT id, videoPath FROM video_takes WHERE id=? AND shotId=?',
        [takeId, shotId]);
    if (rows.isEmpty) throw EngineException('视频版本不存在');
    db.execute(
        "UPDATE shots SET selectedTakeId=?, videoPath=?, videoStatus='done', videoError=NULL WHERE id=?",
        [takeId, rows.first['videoPath'] as String, shotId]);
  }

  Future<void> deleteTake(String takeId) async {
    final rows = db.select('''
SELECT vt.id, vt.shotId, s.selectedTakeId
FROM video_takes vt
JOIN shots s ON s.id=vt.shotId
WHERE vt.id=?
''', [takeId]);
    if (rows.isEmpty) throw EngineException('视频版本不存在');
    final shotId = rows.first['shotId'] as String;
    final wasSelected = rows.first['selectedTakeId'] == takeId;
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM video_takes WHERE id=?', [takeId]);
      if (wasSelected) {
        final fallback = db.select(
            'SELECT id, videoPath FROM video_takes WHERE shotId=? ORDER BY createdAt DESC, id DESC LIMIT 1',
            [shotId]);
        if (fallback.isEmpty) {
          db.execute(
              "UPDATE shots SET selectedTakeId=NULL, videoPath=NULL, videoStatus='none', videoError=NULL WHERE id=?",
              [shotId]);
        } else {
          db.execute(
              "UPDATE shots SET selectedTakeId=?, videoPath=?, videoStatus='done', videoError=NULL WHERE id=?",
              [
                fallback.first['id'] as String,
                fallback.first['videoPath'] as String,
                shotId
              ]);
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> reorderShots(String episodeId, List<String> orderedIds) async {
    final currentIds = db
        .select(
            'SELECT id FROM shots WHERE episodeId=? ORDER BY idx', [episodeId])
        .map((r) => r['id'] as String)
        .toList();
    final currentSet = currentIds.toSet();
    final orderedSet = orderedIds.toSet();
    if (currentIds.length != orderedIds.length ||
        currentSet.length != orderedSet.length ||
        !orderedSet.containsAll(currentSet)) {
      throw EngineException('镜头列表与当前不一致，请刷新后重试');
    }

    db.execute('BEGIN');
    try {
      final upd = db.prepare('UPDATE shots SET idx=? WHERE id=?');
      try {
        for (final (i, id) in orderedIds.indexed) {
          upd.execute([i + 1, id]);
        }
      } finally {
        upd.close();
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Shot> insertShot(String episodeId, {int? afterIdx}) async {
    final episodes =
        db.select('SELECT projectId FROM episodes WHERE id=?', [episodeId]);
    if (episodes.isEmpty) throw EngineException('剧集不存在');
    final maxIdx = db.select(
        'SELECT COALESCE(MAX(idx), 0) n FROM shots WHERE episodeId=?',
        [episodeId]).first['n'] as int;
    if (afterIdx != null && (afterIdx < 0 || afterIdx > maxIdx)) {
      throw EngineException('插入位置不存在，请刷新后重试');
    }
    final insertIdx = (afterIdx ?? maxIdx) + 1;
    final id = newId();

    db.execute('BEGIN');
    try {
      db.execute('UPDATE shots SET idx=idx+1 WHERE episodeId=? AND idx>=?',
          [episodeId, insertIdx]);
      db.execute(
          "INSERT INTO shots (id, episodeId, projectId, idx, description, dialogue, camera, assetNames, imagePrompt, videoPrompt, imageStatus, videoStatus, createdAt) VALUES (?,?,?,?,?,?,?,?,?,?,'none','none',?)",
          [
            id,
            episodeId,
            episodes.first['projectId'] as String,
            insertIdx,
            '',
            '',
            '',
            '[]',
            '',
            '',
            nowIso()
          ]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return _shot(db.select('SELECT * FROM shots WHERE id=?', [id]).first);
  }

  Future<void> deleteShot(String id) async {
    final rows = db.select('SELECT episodeId, idx FROM shots WHERE id=?', [id]);
    if (rows.isEmpty) throw EngineException('镜头不存在');
    if (queue.hasActiveJob('shot_image', id) ||
        queue.hasActiveJob('shot_video', id) ||
        queue.hasActiveJob('compose', rows.first['episodeId'] as String)) {
      throw EngineException('该镜头有任务进行中，请先取消');
    }
    final shot = rows.first;
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM shots WHERE id=?', [id]);
      db.execute('UPDATE shots SET idx=idx-1 WHERE episodeId=? AND idx>?',
          [shot['episodeId'] as String, shot['idx'] as int]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Shot> updateShot(String id, Map<String, String> patch) async {
    if (db.select('SELECT id FROM shots WHERE id=?', [id]).isEmpty) {
      throw EngineException('镜头不存在');
    }
    db.execute(
        'UPDATE shots SET description=COALESCE(?,description), dialogue=COALESCE(?,dialogue), camera=COALESCE(?,camera), imagePrompt=COALESCE(?,imagePrompt), videoPrompt=COALESCE(?,videoPrompt) WHERE id=?',
        [
          patch['description'],
          patch['dialogue'],
          patch['camera'],
          patch['imagePrompt'],
          patch['videoPrompt'],
          id
        ]);
    return _shot(db.select('SELECT * FROM shots WHERE id=?', [id]).first);
  }

  String? _enqueueShotImage(String shotId) {
    final rows =
        db.select('SELECT id, projectId, idx FROM shots WHERE id=?', [shotId]);
    if (rows.isEmpty) return null;
    final s = rows.first;
    if (queue.hasActiveJob('shot_image', shotId)) return null;
    db.execute(
        "UPDATE shots SET imageStatus='queued', imageError=NULL WHERE id=?",
        [shotId]);
    return queue.enqueue(
        projectId: s['projectId'] as String,
        kind: 'shot_image',
        targetId: shotId,
        targetLabel: '镜头图·#${s['idx']}');
  }

  Future<String?> generateShotImage(String shotId) async {
    if (db.select('SELECT id FROM shots WHERE id=?', [shotId]).isEmpty) {
      throw EngineException('镜头不存在');
    }
    if (queue.hasActiveJob('shot_image', shotId)) {
      throw EngineException('该镜头已有生成任务进行中');
    }
    return _enqueueShotImage(shotId);
  }

  Future<List<String>> generateAllShotImages(String episodeId) async => db
      .select(
          "SELECT id FROM shots WHERE episodeId=? AND imageStatus NOT IN ('done','queued','running')",
          [episodeId])
      .map((r) => _enqueueShotImage(r['id'] as String))
      .whereType<String>()
      .toList();

  Future<String> generateShotVideo(String shotId) async {
    final rows = db.select(
        'SELECT id, projectId, idx, imagePath, imageStatus FROM shots WHERE id=?',
        [shotId]);
    if (rows.isEmpty) throw EngineException('镜头不存在');
    final s = rows.first;
    if (s['imageStatus'] != 'done' || s['imagePath'] == null) {
      throw EngineException('请先生成镜头图（视频需要首帧）');
    }
    if (queue.hasActiveJob('shot_video', shotId)) {
      throw EngineException('该镜头已有视频任务进行中');
    }
    db.execute(
        "UPDATE shots SET videoStatus='queued', videoError=NULL WHERE id=?",
        [shotId]);
    return queue.enqueue(
        projectId: s['projectId'] as String,
        kind: 'shot_video',
        targetId: shotId,
        targetLabel: '视频·#${s['idx']}');
  }

  Future<String> composeEpisode(String episodeId) async {
    final episodes = db.select(
        'SELECT id, projectId, idx FROM episodes WHERE id=?', [episodeId]);
    if (episodes.isEmpty) throw EngineException('剧集不存在');
    final missing = db.select('''
SELECT s.idx
FROM shots s
LEFT JOIN video_takes vt ON vt.id=s.selectedTakeId AND vt.shotId=s.id
WHERE s.episodeId=? AND vt.id IS NULL
ORDER BY s.idx
''', [episodeId]).map((r) => r['idx'] as int).toList();
    final shotCount = db.select(
        'SELECT COUNT(*) n FROM shots WHERE episodeId=?',
        [episodeId]).first['n'] as int;
    if (shotCount == 0) throw EngineException('本集还没有分镜');
    if (missing.isNotEmpty) {
      throw EngineException('第 ${missing.join('、')} 镜缺少视频');
    }
    if (queue.hasActiveJob('compose', episodeId)) {
      throw EngineException('本集合成任务已在进行中');
    }
    db.execute(
        "UPDATE episodes SET composeStatus='queued', composeError=NULL WHERE id=?",
        [episodeId]);
    return queue.enqueue(
        projectId: episodes.first['projectId'] as String,
        kind: 'compose',
        targetId: episodeId,
        targetLabel: '合成·第${episodes.first['idx']}集');
  }

  // ---------- jobs ----------

  Job _job(Row r) {
    final m = _row(r);
    final started = m['startedAt'] as String?;
    final finished = m['finishedAt'] as String?;
    m['durationMs'] = (started != null && finished != null)
        ? DateTime.parse(finished)
            .difference(DateTime.parse(started))
            .inMilliseconds
        : null;
    return Job.fromJson(m);
  }

  Future<List<Job>> activeJobs() async => db
      .select(
          "SELECT * FROM jobs WHERE state IN ('queued','running') ORDER BY createdAt")
      .map(_job)
      .toList();

  Future<List<Job>> projectJobs(String projectId, {int limit = 50}) async => db
      .select(
          'SELECT * FROM jobs WHERE projectId=? ORDER BY createdAt DESC LIMIT ?',
          [projectId, limit.clamp(1, 200)])
      .map(_job)
      .toList();

  Future<String> retryJob(String jobId) async {
    final rows = db.select('SELECT * FROM jobs WHERE id=?', [jobId]);
    if (rows.isEmpty) throw EngineException('任务不存在');
    final j = rows.first;
    if (j['state'] != 'failed') throw EngineException('只有失败的任务可以重试');
    final kind = j['kind'] as String;
    final targetId = j['targetId'] as String;
    if (queue.hasActiveJob(kind, targetId)) {
      throw EngineException('同目标已有任务进行中');
    }
    switch (kind) {
      case 'asset_image':
        db.execute("UPDATE assets SET status='queued', error=NULL WHERE id=?",
            [targetId]);
      case 'shot_image':
        db.execute(
            "UPDATE shots SET imageStatus='queued', imageError=NULL WHERE id=?",
            [targetId]);
      case 'shot_video':
        db.execute(
            "UPDATE shots SET videoStatus='queued', videoError=NULL WHERE id=?",
            [targetId]);
      case 'compose':
        db.execute(
            "UPDATE episodes SET composeStatus='queued', composeError=NULL WHERE id=?",
            [targetId]);
    }
    return queue.enqueue(
        projectId: j['projectId'] as String,
        kind: kind,
        targetId: targetId,
        targetLabel: j['targetLabel'] as String,
        payload:
            (jsonDecode(j['payload'] as String) as Map).cast<String, dynamic>(),
        attempt: (j['attempt'] as int) + 1);
  }

  Future<void> cancelJob(String jobId) async => queue.cancel(jobId);

  // ---------- director / auto mode ----------

  Future<void> startAuto(String projectId) => director.startAuto(projectId);

  Future<void> stopAuto(String projectId) => director.stopAuto(projectId);

  DirectorState directorState(String projectId) => director.state(projectId);

  // ---------- providers / models / bindings / prompts ----------

  String _maskSecret(String v) =>
      v.isEmpty ? '' : '****${v.substring(v.length < 4 ? 0 : v.length - 4)}';

  bool _enabled(Object? v, {bool defaultValue = true}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v.toString() != '0' && v.toString().toLowerCase() != 'false';
  }

  String _capabilitiesJson(Object? value) {
    if (value == null) return '{}';
    if (value is String) {
      if (value.trim().isEmpty) return '{}';
      jsonDecode(value);
      return value;
    }
    return jsonEncode(value);
  }

  ProviderInfo _provider(Row r, {bool maskKey = true}) {
    final m = _row(r);
    if (maskKey) m['apiKey'] = _maskSecret(m['apiKey'] as String? ?? '');
    return ProviderInfo.fromJson(m);
  }

  ProviderModelInfo _providerModel(Row r) =>
      ProviderModelInfo.fromJson(_row(r));

  Future<List<ProviderInfo>> listProviders() async => db
      .select('SELECT * FROM providers ORDER BY name, id')
      .map(_provider)
      .toList();

  Future<ProviderInfo> createProvider({
    required String name,
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw EngineException('供应商名称不能为空');
    if (!const {'openai_compatible', 'volcengine'}.contains(protocol)) {
      throw EngineException('供应商协议无效');
    }
    final id = newId();
    db.execute(
        'INSERT INTO providers (id,name,protocol,baseUrl,apiKey,createdAt) VALUES (?,?,?,?,?,?)',
        [id, trimmedName, protocol, baseUrl.trim(), apiKey, nowIso()]);
    return _provider(
        db.select('SELECT * FROM providers WHERE id=?', [id]).first);
  }

  Future<ProviderInfo> updateProvider(String id,
      {String? name, String? baseUrl, String? apiKey}) async {
    if (db.select('SELECT id FROM providers WHERE id=?', [id]).isEmpty) {
      throw EngineException('供应商不存在');
    }
    final assignments = <String>[];
    final args = <Object?>[];
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) throw EngineException('供应商名称不能为空');
      assignments.add('name=?');
      args.add(trimmed);
    }
    if (baseUrl != null) {
      assignments.add('baseUrl=?');
      args.add(baseUrl.trim());
    }
    if (apiKey != null && apiKey.isNotEmpty && !apiKey.startsWith('****')) {
      assignments.add('apiKey=?');
      args.add(apiKey);
    }
    if (assignments.isNotEmpty) {
      args.add(id);
      db.execute(
          'UPDATE providers SET ${assignments.join(', ')} WHERE id=?', args);
    }
    return _provider(
        db.select('SELECT * FROM providers WHERE id=?', [id]).first);
  }

  Future<void> deleteProvider(String id) async {
    final bindings =
        db.select("SELECT value FROM settings WHERE key LIKE 'binding.%'");
    for (final row in bindings) {
      final value = row['value'] as String;
      final sep = value.indexOf(':');
      if (sep > 0 && value.substring(0, sep) == id) {
        throw EngineException('该供应商正被环节绑定使用，请先解绑');
      }
    }
    db.execute('DELETE FROM providers WHERE id=?', [id]);
  }

  Future<List<ProviderModelInfo>> listProviderModels(String providerId) async {
    return db
        .select(
            'SELECT * FROM provider_models WHERE providerId=? ORDER BY kind, modelId, id',
            [providerId])
        .map(_providerModel)
        .toList();
  }

  Future<List<ProviderModelInfo>> saveProviderModels(
      String providerId, List<Map<String, dynamic>> models) async {
    if (db
        .select('SELECT id FROM providers WHERE id=?', [providerId]).isEmpty) {
      throw EngineException('供应商不存在');
    }
    db.execute('BEGIN');
    try {
      db.execute(
          'DELETE FROM provider_models WHERE providerId=?', [providerId]);
      final stmt = db.prepare(
          'INSERT INTO provider_models (id,providerId,modelId,label,kind,capabilities,enabled) VALUES (?,?,?,?,?,?,?)');
      try {
        for (final model in models) {
          final modelId = (model['modelId'] ?? '').toString().trim();
          if (modelId.isEmpty) throw EngineException('模型 ID 不能为空');
          final kind = (model['kind'] ?? '').toString();
          if (!const {'text', 'image', 'video', 'tts'}.contains(kind)) {
            throw EngineException('模型类型无效');
          }
          stmt.execute([
            model['id']?.toString() ?? newId(),
            providerId,
            modelId,
            (model['label'] ?? modelId).toString(),
            kind,
            _capabilitiesJson(model['capabilities']),
            _enabled(model['enabled']) ? 1 : 0,
          ]);
        }
      } finally {
        stmt.close();
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return listProviderModels(providerId);
  }

  Future<int> testProvider(String id, String modelId) async {
    final rows = db.select('''
SELECT p.id providerId, p.protocol, p.baseUrl, p.apiKey, pm.modelId, pm.kind
FROM providers p
JOIN provider_models pm ON pm.providerId=p.id
WHERE p.id=? AND pm.modelId=?
LIMIT 1
''', [id, modelId]);
    if (rows.isEmpty) throw EngineException('模型不存在');
    final row = rows.first;
    if (row['kind'] != 'text') throw EngineException('暂只支持文本模型连通测试');
    final http = gateway;
    if (http is! HttpProviderGateway) {
      throw EngineException('当前网关不支持供应商连通测试');
    }
    return http.testTextModel(ResolvedModel(
      providerId: row['providerId'] as String,
      protocol: row['protocol'] as String,
      baseUrl: row['baseUrl'] as String,
      apiKey: row['apiKey'] as String,
      modelId: row['modelId'] as String,
    ));
  }

  Future<Map<String, String>> getBindings() async => {
        for (final row in db.select(
            "SELECT key,value FROM settings WHERE key LIKE 'binding.%' ORDER BY key"))
          (row['key'] as String).substring('binding.'.length):
              row['value'] as String
      };

  void _setBinding(String stage, String providerId, String modelId) {
    final requiredKind = requiredKindForStage(stage);
    final rows = db.select('''
SELECT pm.kind
FROM providers p
JOIN provider_models pm ON pm.providerId=p.id
WHERE p.id=? AND pm.modelId=?
LIMIT 1
''', [providerId, modelId]);
    if (rows.isEmpty) throw EngineException('模型不存在，请先保存模型');
    final actualKind = rows.first['kind'] as String;
    if (actualKind != requiredKind) {
      throw EngineException('环节 $stage 需要 $requiredKind 模型，当前是 $actualKind');
    }
    db.execute('INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)',
        ['binding.$stage', '$providerId:$modelId']);
  }

  Future<void> setBinding(
      String stage, String providerId, String modelId) async {
    _setBinding(stage, providerId, modelId);
  }

  String _defaultPromptContent(String key) {
    if (key == prompt_defs.promptKeyImageSizeDirective) {
      return config.str('imageSizeDirective');
    }
    final content = prompt_defs.defaultSystemPrompts[key];
    if (content == null) throw EngineException('未知提示词：$key');
    return content;
  }

  Future<List<Map<String, dynamic>>> listPrompts() async => db
      .select('SELECT key,content,updatedAt FROM prompts ORDER BY key')
      .map(_row)
      .toList();

  Future<void> updatePrompt(String key, String content) async {
    _defaultPromptContent(key);
    db.execute(
        'INSERT INTO prompts (key,content,updatedAt) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET content=excluded.content, updatedAt=excluded.updatedAt',
        [key, content, nowIso()]);
  }

  Future<void> resetPrompt(String key) async {
    db.execute(
        'INSERT INTO prompts (key,content,updatedAt) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET content=excluded.content, updatedAt=excluded.updatedAt',
        [key, _defaultPromptContent(key), nowIso()]);
  }

  Map<String, dynamic> _providerExport(Row provider) {
    final providerId = provider['id'] as String;
    return {
      ..._row(provider),
      'enabled': (provider['enabled'] as int) != 0,
      'models': db.select(
          'SELECT * FROM provider_models WHERE providerId=? ORDER BY kind, modelId, id',
          [providerId]).map((model) {
        final m = _row(model);
        m['enabled'] = (model['enabled'] as int) != 0;
        m['capabilities'] = jsonDecode(model['capabilities'] as String);
        return m;
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> exportConfig() async => {
        'providers': db
            .select('SELECT * FROM providers ORDER BY name, id')
            .map(_providerExport)
            .toList(),
        'bindings': await getBindings(),
        'prompts': await listPrompts(),
      };

  Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> importConfig(Map<String, dynamic> data) async {
    final providers = data['providers'] is List
        ? data['providers'] as List
        : const <Object?>[];
    final bindings = _stringMap(data['bindings']);
    final prompts =
        data['prompts'] is List ? data['prompts'] as List : const <Object?>[];
    final providerIdMap = <String, String>{};

    db.execute('BEGIN');
    try {
      for (final rawProvider in providers) {
        final p = _stringMap(rawProvider);
        final exportedId = (p['id'] ?? newId()).toString();
        final name = (p['name'] ?? '').toString().trim();
        if (name.isEmpty) throw EngineException('供应商名称不能为空');
        final protocol = (p['protocol'] ?? '').toString();
        if (!const {'openai_compatible', 'volcengine'}.contains(protocol)) {
          throw EngineException('供应商协议无效');
        }
        final existing =
            db.select('SELECT id FROM providers WHERE name=? LIMIT 1', [name]);
        var finalId =
            existing.isNotEmpty ? existing.first['id'] as String : exportedId;
        if (existing.isEmpty &&
            db.select(
                'SELECT id FROM providers WHERE id=?', [finalId]).isNotEmpty) {
          finalId = newId();
        }
        providerIdMap[exportedId] = finalId;
        final providerArgs = [
          name,
          protocol,
          (p['baseUrl'] ?? '').toString(),
          (p['apiKey'] ?? '').toString(),
          _enabled(p['enabled']) ? 1 : 0,
          (p['createdAt'] ?? nowIso()).toString(),
        ];
        if (existing.isNotEmpty) {
          db.execute(
              'UPDATE providers SET name=?, protocol=?, baseUrl=?, apiKey=?, enabled=?, createdAt=? WHERE id=?',
              [...providerArgs, finalId]);
        } else {
          db.execute(
              'INSERT INTO providers (id,name,protocol,baseUrl,apiKey,enabled,createdAt) VALUES (?,?,?,?,?,?,?)',
              [finalId, ...providerArgs]);
        }

        db.execute('DELETE FROM provider_models WHERE providerId=?', [finalId]);
        final rawModels = p['models'] is List ? p['models'] as List : const [];
        final stmt = db.prepare(
            'INSERT INTO provider_models (id,providerId,modelId,label,kind,capabilities,enabled) VALUES (?,?,?,?,?,?,?)');
        try {
          for (final rawModel in rawModels) {
            final m = _stringMap(rawModel);
            final modelId = (m['modelId'] ?? '').toString().trim();
            if (modelId.isEmpty) throw EngineException('模型 ID 不能为空');
            final kind = (m['kind'] ?? '').toString();
            if (!const {'text', 'image', 'video', 'tts'}.contains(kind)) {
              throw EngineException('模型类型无效');
            }
            var rowId = (m['id'] ?? newId()).toString();
            if (db.select('SELECT id FROM provider_models WHERE id=?',
                [rowId]).isNotEmpty) {
              rowId = newId();
            }
            stmt.execute([
              rowId,
              finalId,
              modelId,
              (m['label'] ?? modelId).toString(),
              kind,
              _capabilitiesJson(m['capabilities']),
              _enabled(m['enabled']) ? 1 : 0,
            ]);
          }
        } finally {
          stmt.close();
        }
      }

      db.execute("DELETE FROM settings WHERE key LIKE 'binding.%'");
      for (final entry in bindings.entries) {
        final stage = entry.key;
        final value = entry.value.toString();
        final sep = value.indexOf(':');
        if (sep <= 0 || sep == value.length - 1) {
          throw EngineException('环节 $stage 绑定格式无效');
        }
        final oldProviderId = value.substring(0, sep);
        final providerId = providerIdMap[oldProviderId] ?? oldProviderId;
        final modelId = value.substring(sep + 1);
        _setBinding(stage, providerId, modelId);
      }

      for (final rawPrompt in prompts) {
        final p = _stringMap(rawPrompt);
        final key = (p['key'] ?? '').toString();
        _defaultPromptContent(key);
        db.execute(
            'INSERT INTO prompts (key,content,updatedAt) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET content=excluded.content, updatedAt=excluded.updatedAt',
            [
              key,
              (p['content'] ?? '').toString(),
              (p['updatedAt'] ?? nowIso()).toString()
            ]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ---------- settings ----------

  Future<AppSettings> getSettings() async =>
      AppSettings.fromJson(config.getAllMasked());

  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async {
    config.update(patch);
    return getSettings();
  }

  Future<String> getThemeMode() async => config.str('themeMode');

  Future<void> setThemeMode(String themeMode) async {
    if (!{'light', 'dark', 'system'}.contains(themeMode)) {
      throw EngineException('主题模式无效：$themeMode');
    }
    config.update({'themeMode': themeMode});
  }

  void dispose() {
    queue.dispose();
    db.close();
  }
}
