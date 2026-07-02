import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

import '../api/models.dart';
import 'db.dart';
import 'media.dart';
import 'util.dart';

abstract class VideoComposer {
  Future<double?> probeDurationSec(String inputAbsPath);

  /// 顺序拼接 segments（绝对路径），统一输出 720p/30fps/H.264/AAC 到 outputAbsPath。
  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath);
}

class UnsupportedComposer implements VideoComposer {
  const UnsupportedComposer();

  @override
  Future<double?> probeDurationSec(String inputAbsPath) {
    throw EngineException('当前平台暂不支持视频合成');
  }

  @override
  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath) {
    throw EngineException('当前平台暂不支持视频合成');
  }
}

class ComposeService {
  final Database db;
  final MediaStore media;
  final VideoComposer composer;

  ComposeService({
    required this.db,
    required this.media,
    VideoComposer? composer,
  }) : composer = composer ?? const UnsupportedComposer();

  Map<String, dynamic> _row(Row row) => Map<String, dynamic>.from(row);

  VideoTake _take(Row row) => VideoTake.fromJson(_row(row));

  Future<VideoTake> addTake({
    required String shotId,
    required String videoPath,
    bool select = true,
  }) async {
    final shots = db.select('SELECT id FROM shots WHERE id=?', [shotId]);
    if (shots.isEmpty) throw EngineException('镜头不存在');
    final durationSec =
        await composer.probeDurationSec(media.absPath(videoPath));
    final takeId = newId();
    db.execute('BEGIN');
    try {
      db.execute(
          'INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES (?,?,?,?,?)',
          [takeId, shotId, videoPath, durationSec, nowIso()]);
      if (select) {
        db.execute(
            "UPDATE shots SET selectedTakeId=?, videoPath=?, videoStatus='done', videoError=NULL WHERE id=?",
            [takeId, videoPath, shotId]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return _take(
        db.select('SELECT * FROM video_takes WHERE id=?', [takeId]).first);
  }

  Future<String> composeEpisode(String episodeId) async {
    final episodes = db.select(
        'SELECT id, projectId FROM episodes WHERE id=? LIMIT 1', [episodeId]);
    if (episodes.isEmpty) throw EngineException('剧集不存在');
    final projectId = episodes.first['projectId'] as String;
    final rows = db.select('''
SELECT s.id shotId, s.idx, vt.videoPath, vt.durationSec
FROM shots s
JOIN video_takes vt ON vt.id = s.selectedTakeId AND vt.shotId = s.id
WHERE s.episodeId=?
ORDER BY s.idx
''', [episodeId]);
    final shotCount = db.select(
        'SELECT COUNT(*) n FROM shots WHERE episodeId=?',
        [episodeId]).first['n'] as int;
    if (shotCount == 0) throw EngineException('本集还没有分镜');
    if (rows.length != shotCount) {
      throw EngineException('本集存在未选择视频的镜头，请刷新后重试');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final outputRel = '$projectId/ep_${episodeId}_$stamp.mp4';
    final outputAbs = media.absPath(outputRel);
    File(outputAbs).parent.createSync(recursive: true);
    try {
      final segments = <String>[];
      for (final row in rows) {
        final inputRel = row['videoPath'] as String;
        final inputAbs = media.absPath(inputRel);
        segments.add(inputAbs);
        if (row['durationSec'] == null) {
          final durationSec = await composer.probeDurationSec(inputAbs);
          if (durationSec == null) continue;
          db.execute('UPDATE video_takes SET durationSec=? WHERE videoPath=?',
              [durationSec, inputRel]);
        }
      }
      await composer.concat(segments, outputAbs);
      return outputRel;
    } catch (e) {
      throw EngineException('合成失败：${_tail(errMessage(e))}');
    }
  }
}

String _tail(String value, {int maxChars = 500}) {
  if (value.length <= maxChars) return value;
  return value.substring(value.length - maxChars);
}
