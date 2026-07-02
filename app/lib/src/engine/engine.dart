import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';
import '../api/models.dart';
import 'config.dart';
import 'db.dart';
import 'media.dart';
import 'providers/gateway.dart';
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
  late final JobQueue queue;

  Engine({
    required this.db,
    required this.media,
    required this.gateway,
    required this.config,
  }) {
    final runners = Runners(db, gateway, media);
    queue = JobQueue(db, run: runners.run);
  }

  /// 生产入口：开库、建媒体仓库、恢复中断任务、启动队列。
  static Future<Engine> boot(
      {required String dataDir, required bool isMobile}) async {
    Directory(dataDir).createSync(recursive: true);
    final db = openEngineDb(path.join(dataDir, 'dramaflow.sqlite'));
    final config = EngineConfig(db, isMobile: isMobile);
    final media = MediaStore(path.join(dataDir, 'media'));
    final engine = Engine(
        db: db,
        media: media,
        gateway: HttpProviderGateway(config, media),
        config: config);
    engine.queue.recoverOnColdStart();
    engine.queue.start();
    return engine;
  }

  String mediaAbsPath(String rel) => media.absPath(rel);

  Map<String, dynamic> _row(Row r) => Map<String, dynamic>.from(r);

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
        "SELECT COUNT(*) n FROM jobs WHERE projectId=? AND state IN ('queued','running') AND kind IN ('storyboard_gen','shot_image','shot_video')",
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

  String? _enqueueAssetImage(String assetId) {
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
        targetLabel: '素材图·${a['name']}');
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

  Future<List<String>> generateAllAssetImages(String projectId) async => db
      .select(
          "SELECT id FROM assets WHERE projectId=? AND status NOT IN ('done','queued','running')",
          [projectId])
      .map((r) => _enqueueAssetImage(r['id'] as String))
      .whereType<String>()
      .toList();

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
        "SELECT COUNT(*) n FROM jobs WHERE state IN ('queued','running') AND kind IN ('shot_image','shot_video') AND targetId IN (SELECT id FROM shots WHERE episodeId=?)",
        [episodeId]).first['n'] as int;
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
        queue.hasActiveJob('shot_video', id)) {
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
