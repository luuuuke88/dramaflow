import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import '../db.dart';
import '../media.dart';
import '../util.dart';
import '../providers/gateway.dart';
import 'prompts.dart' as p;
import 'schemas.dart';

class JobRow {
  final String id;
  final String projectId;
  final String kind;
  final String targetId;
  final String payload;
  const JobRow(this.id, this.projectId, this.kind, this.targetId, this.payload);
}

/// 流水线执行器（移植 server/src/pipeline/runners.ts）。
/// 保留 v0.1 修复语义：媒体类执行器先置实体 running，预检在 try 内——
/// 任何失败实体必落 failed+原因，绝不卡 queued。
class Runners {
  final Database db;
  final ProviderGateway gateway;
  final MediaStore media;
  Runners(this.db, this.gateway, this.media);

  Future<String> run(JobRow job, CancelToken token) => switch (job.kind) {
        'script_gen' => _runScriptGen(job, token),
        'asset_extract' => _runAssetExtract(job, token),
        'storyboard_gen' => _runStoryboardGen(job, token),
        'asset_image' => _runAssetImage(job, token),
        'shot_image' => _runShotImage(job, token),
        'shot_video' => _runShotVideo(job, token),
        _ => throw EngineException('未知任务类型 ${job.kind}'),
      };

  // ---------- 结构化文本调用（解析失败带错误反馈自愈重试一次） ----------

  Future<T> _structuredText<T>(String system, String user,
      T Function(dynamic) parse, CancelToken token) async {
    final first = await gateway.generateText(system, user, cancelToken: token);
    try {
      return parse(extractJson(first.content));
    } catch (e1) {
      final err1 = errMessage(e1);
      final second = await gateway.generateText(
          system,
          p.repairUser(user, first.content,
              err1.length > 300 ? err1.substring(0, 300) : err1),
          cancelToken: token);
      try {
        return parse(extractJson(second.content));
      } catch (e2) {
        final err2 = errMessage(e2);
        final head = second.content.length > 200
            ? second.content.substring(0, 200)
            : second.content;
        throw EngineException(
            '模型输出两次都无法解析。最后错误: ${err2.length > 300 ? err2.substring(0, 300) : err2}。原始输出开头: $head');
      }
    }
  }

  Row _mustGetProject(String projectId) {
    final rows =
        db.select('SELECT * FROM projects WHERE id=?', [projectId]);
    if (rows.isEmpty) throw EngineException('项目不存在（可能已被删除）');
    return rows.first;
  }

  // ---------- 小说 → 分集剧本 ----------

  Future<String> _runScriptGen(JobRow job, CancelToken token) async {
    final project = _mustGetProject(job.projectId);
    final payload = jsonDecode(job.payload) as Map<String, dynamic>;
    final novels = db.select(
        'SELECT title, content FROM novels WHERE projectId=?',
        [job.projectId]);
    if (novels.isEmpty ||
        (novels.first['content'] as String).trim().isEmpty) {
      throw EngineException('请先导入小说');
    }
    final novel = novels.first;
    final episodeCount =
        ((payload['episodeCount'] as num?)?.toInt() ?? 3).clamp(1, 12);

    final out = await _structuredText(
        p.scriptGenSystem,
        p.scriptGenUser(
            (novel['title'] as String).isNotEmpty
                ? novel['title'] as String
                : project['name'] as String,
            novel['content'] as String,
            episodeCount),
        parseScriptOut,
        token);

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM episodes WHERE projectId=?', [job.projectId]);
      final ins = db.prepare(
          'INSERT INTO episodes (id, projectId, idx, title, synopsis, scriptJson, createdAt) VALUES (?,?,?,?,?,?,?)');
      for (final (i, ep) in out.episodes.indexed) {
        ins.execute([
          newId(),
          job.projectId,
          i + 1,
          ep.title,
          ep.synopsis,
          jsonEncode(ep.scenes),
          nowIso()
        ]);
      }
      ins.dispose();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return '生成 ${out.episodes.length} 集剧本';
  }

  // ---------- 全部剧本 → 资产列表 ----------

  Future<String> _runAssetExtract(JobRow job, CancelToken token) async {
    final project = _mustGetProject(job.projectId);
    final episodes = db.select(
        'SELECT title, synopsis, scriptJson FROM episodes WHERE projectId=? ORDER BY idx',
        [job.projectId]);
    if (episodes.isEmpty) throw EngineException('请先生成剧本');

    final summary = episodes.indexed
        .map((e) =>
            '第${e.$1 + 1}集《${e.$2['title']}》：${e.$2['synopsis']}\n${e.$2['scriptJson']}')
        .join('\n\n');
    final assets = await _structuredText(
        p.assetExtractSystem,
        p.assetExtractUser(summary, project['artStyle'] as String),
        parseAssetsOut,
        token);

    var added = 0, updated = 0;
    db.execute('BEGIN');
    try {
      for (final a in assets) {
        final existing = db.select(
            'SELECT id FROM assets WHERE projectId=? AND name=? AND kind=?',
            [job.projectId, a.name, a.kind]);
        if (existing.isNotEmpty) {
          db.execute(
              'UPDATE assets SET description=?, imagePrompt=? WHERE id=?',
              [a.description, a.imagePrompt, existing.first['id']]);
          updated++;
        } else {
          db.execute(
              "INSERT INTO assets (id, projectId, kind, name, description, imagePrompt, status, createdAt) VALUES (?,?,?,?,?,?,'draft',?)",
              [
                newId(),
                job.projectId,
                a.kind,
                a.name,
                a.description,
                a.imagePrompt,
                nowIso()
              ]);
          added++;
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return '提取资产：新增 $added 个，更新 $updated 个';
  }

  // ---------- 单集剧本 → 分镜 ----------

  Future<String> _runStoryboardGen(JobRow job, CancelToken token) async {
    final project = _mustGetProject(job.projectId);
    final episodes =
        db.select('SELECT * FROM episodes WHERE id=?', [job.targetId]);
    if (episodes.isEmpty) throw EngineException('剧集不存在');
    final episode = episodes.first;

    final assets = db.select(
        'SELECT kind, name, description FROM assets WHERE projectId=?',
        [job.projectId]);
    final kindLabel = {'character': '角色', 'scene': '场景', 'prop': '道具'};
    final assetsContext = assets.isNotEmpty
        ? assets
            .map((a) =>
                '[${kindLabel[a['kind']] ?? a['kind']}] ${a['name']}：${a['description']}')
            .join('\n')
        : '（尚未提取资产，请根据剧本自行保持角色外观一致）';

    final shots = await _structuredText(
        p.storyboardGenSystem,
        p.storyboardGenUser(episode['title'] as String,
            episode['scriptJson'] as String, assetsContext,
            project['artStyle'] as String),
        parseShotsOut,
        token);

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM shots WHERE episodeId=?', [episode['id']]);
      final ins = db.prepare(
          "INSERT INTO shots (id, episodeId, projectId, idx, description, dialogue, camera, assetNames, imagePrompt, videoPrompt, imageStatus, videoStatus, createdAt) VALUES (?,?,?,?,?,?,?,?,?,?,'none','none',?)");
      for (final (i, sh) in shots.indexed) {
        ins.execute([
          newId(),
          episode['id'],
          job.projectId,
          i + 1,
          sh.description,
          sh.dialogue,
          sh.camera,
          jsonEncode(sh.assetNames),
          sh.imagePrompt,
          sh.videoPrompt,
          nowIso()
        ]);
      }
      ins.dispose();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return '生成 ${shots.length} 个镜头';
  }

  // ---------- 素材图 ----------

  Future<String> _runAssetImage(JobRow job, CancelToken token) async {
    final rows = db.select('SELECT * FROM assets WHERE id=?', [job.targetId]);
    if (rows.isEmpty) throw EngineException('资产不存在');
    final asset = rows.first;

    // 先置 running 再预检：任何失败（含预检）实体必落 failed+原因，不能卡 queued
    db.execute("UPDATE assets SET status='running', error=NULL WHERE id=?",
        [asset['id']]);
    try {
      final prompt = (asset['imagePrompt'] as String).trim().isNotEmpty
          ? (asset['imagePrompt'] as String).trim()
          : (asset['description'] as String).trim();
      if (prompt.isEmpty) throw EngineException('该资产没有图片提示词，请先填写');
      final rel = await gateway.generateImage(prompt, job.projectId,
          cancelToken: token);
      db.execute(
          "UPDATE assets SET status='done', imagePath=?, error=NULL WHERE id=?",
          [rel, asset['id']]);
      return rel;
    } catch (e) {
      final msg = errMessage(e);
      db.execute("UPDATE assets SET status='failed', error=? WHERE id=?",
          [msg.length > 2000 ? msg.substring(0, 2000) : msg, asset['id']]);
      rethrow;
    }
  }

  // ---------- 镜头静帧图 ----------

  Future<String> _runShotImage(JobRow job, CancelToken token) async {
    final rows = db.select('SELECT * FROM shots WHERE id=?', [job.targetId]);
    if (rows.isEmpty) throw EngineException('镜头不存在');
    final shot = rows.first;

    db.execute(
        "UPDATE shots SET imageStatus='running', imageError=NULL WHERE id=?",
        [shot['id']]);
    try {
      final prompt = (shot['imagePrompt'] as String).trim();
      if (prompt.isEmpty) throw EngineException('该镜头没有图片提示词');
      final rel = await gateway.generateImage(prompt, job.projectId,
          cancelToken: token);
      db.execute(
          "UPDATE shots SET imageStatus='done', imagePath=?, imageError=NULL WHERE id=?",
          [rel, shot['id']]);
      return rel;
    } catch (e) {
      final msg = errMessage(e);
      db.execute(
          "UPDATE shots SET imageStatus='failed', imageError=? WHERE id=?",
          [msg.length > 2000 ? msg.substring(0, 2000) : msg, shot['id']]);
      rethrow;
    }
  }

  // ---------- 镜头视频 ----------

  Future<String> _runShotVideo(JobRow job, CancelToken token) async {
    final rows = db.select('SELECT * FROM shots WHERE id=?', [job.targetId]);
    if (rows.isEmpty) throw EngineException('镜头不存在');
    final shot = rows.first;

    db.execute(
        "UPDATE shots SET videoStatus='running', videoError=NULL WHERE id=?",
        [shot['id']]);
    try {
      final imagePath = shot['imagePath'] as String?;
      if (imagePath == null || imagePath.isEmpty) {
        throw EngineException('请先生成镜头图（视频需要首帧）');
      }
      final prompt = (shot['videoPrompt'] as String).trim().isNotEmpty
          ? (shot['videoPrompt'] as String).trim()
          : (shot['description'] as String).trim();
      if (prompt.isEmpty) throw EngineException('该镜头没有视频提示词');
      final rel = await gateway.generateVideo(
          prompt, media.absPath(imagePath), job.projectId,
          cancelToken: token);
      db.execute(
          "UPDATE shots SET videoStatus='done', videoPath=?, videoError=NULL WHERE id=?",
          [rel, shot['id']]);
      return rel;
    } catch (e) {
      final msg = errMessage(e);
      db.execute(
          "UPDATE shots SET videoStatus='failed', videoError=? WHERE id=?",
          [msg.length > 2000 ? msg.substring(0, 2000) : msg, shot['id']]);
      rethrow;
    }
  }
}
