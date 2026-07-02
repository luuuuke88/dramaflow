import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../api/models.dart';
import 'db.dart';
import 'media.dart';
import 'util.dart';

class MediaProbe {
  final double? durationSec;
  final bool hasAudio;

  const MediaProbe({required this.durationSec, required this.hasAudio});
}

class FfmpegRunResult {
  final bool success;
  final String stderr;

  const FfmpegRunResult({required this.success, this.stderr = ''});
}

abstract class FfmpegRunner {
  Future<MediaProbe> probe(String inputPath);
  Future<FfmpegRunResult> run(List<String> args);
}

class ProcessFfmpegRunner implements FfmpegRunner {
  const ProcessFfmpegRunner();

  @override
  Future<MediaProbe> probe(String inputPath) async {
    final result = await Process.run('ffprobe', [
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      inputPath,
    ]);
    if (result.exitCode != 0) {
      throw EngineException(
          'ffprobe 读取媒体信息失败：${_tail(result.stderr.toString())}');
    }
    final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    final streams = (json['streams'] as List? ?? const []);
    final hasAudio = streams.any((s) =>
        s is Map && (s['codec_type']?.toString().toLowerCase() == 'audio'));
    final format = json['format'];
    double? duration;
    if (format is Map) {
      duration = double.tryParse(format['duration']?.toString() ?? '');
    }
    duration ??= streams
        .whereType<Map>()
        .map((s) => double.tryParse(s['duration']?.toString() ?? ''))
        .whereType<double>()
        .fold<double?>(null, (maxDuration, value) {
      if (maxDuration == null) return value;
      return max(maxDuration, value);
    });
    return MediaProbe(durationSec: duration, hasAudio: hasAudio);
  }

  @override
  Future<FfmpegRunResult> run(List<String> args) async {
    final result = await Process.run('ffmpeg', args);
    return FfmpegRunResult(
      success: result.exitCode == 0,
      stderr: result.stderr.toString(),
    );
  }
}

class ComposeService {
  final Database db;
  final MediaStore media;
  final FfmpegRunner runner;

  ComposeService({
    required this.db,
    required this.media,
    FfmpegRunner? runner,
  }) : runner = runner ?? const ProcessFfmpegRunner();

  Map<String, dynamic> _row(Row row) => Map<String, dynamic>.from(row);

  VideoTake _take(Row row) => VideoTake.fromJson(_row(row));

  Future<VideoTake> addTake({
    required String shotId,
    required String videoPath,
    bool select = true,
  }) async {
    final shots = db.select('SELECT id FROM shots WHERE id=?', [shotId]);
    if (shots.isEmpty) throw EngineException('镜头不存在');
    final probe = await runner.probe(media.absPath(videoPath));
    final takeId = newId();
    db.execute('BEGIN');
    try {
      db.execute(
          'INSERT INTO video_takes (id,shotId,videoPath,durationSec,createdAt) VALUES (?,?,?,?,?)',
          [takeId, shotId, videoPath, probe.durationSec, nowIso()]);
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
    final workRel = '$projectId/_compose/ep_${episodeId}_$stamp';
    final workDir = Directory(media.absPath(workRel))
      ..createSync(recursive: true);
    final outputRel = '$projectId/ep_${episodeId}_$stamp.mp4';
    final outputAbs = media.absPath(outputRel);
    File(outputAbs).parent.createSync(recursive: true);
    final segments = <String>[];
    try {
      for (final (index, row) in rows.indexed) {
        final inputRel = row['videoPath'] as String;
        final inputAbs = media.absPath(inputRel);
        final probe = await runner.probe(inputAbs);
        if (probe.durationSec != null && row['durationSec'] == null) {
          db.execute('UPDATE video_takes SET durationSec=? WHERE videoPath=?',
              [probe.durationSec, inputRel]);
        }
        final segmentAbs = path.join(workDir.path, 'segment_${index + 1}.mp4');
        await _runFfmpeg(_transcodeArgs(
          inputAbs: inputAbs,
          outputAbs: segmentAbs,
          probe: probe,
        ));
        segments.add(segmentAbs);
      }

      final concatFile = File(path.join(workDir.path, 'concat.txt'));
      concatFile.writeAsStringSync(
        segments.map((s) => "file '${_escapeConcatPath(s)}'").join('\n'),
      );
      await _runFfmpeg([
        '-y',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        concatFile.path,
        '-c',
        'copy',
        outputAbs,
      ]);
      return outputRel;
    } finally {
      if (workDir.existsSync()) {
        workDir.deleteSync(recursive: true);
      }
    }
  }

  Future<void> _runFfmpeg(List<String> args) async {
    final result = await runner.run(args);
    if (!result.success) {
      throw EngineException('ffmpeg 执行失败：${_tail(result.stderr)}');
    }
  }

  List<String> _transcodeArgs({
    required String inputAbs,
    required String outputAbs,
    required MediaProbe probe,
  }) {
    final args = <String>[
      '-y',
      '-i',
      inputAbs,
    ];
    if (!probe.hasAudio) {
      args.addAll([
        '-f',
        'lavfi',
        if (probe.durationSec != null && probe.durationSec! > 0) ...[
          '-t',
          probe.durationSec!.toStringAsFixed(3),
        ],
        '-i',
        'anullsrc=channel_layout=stereo:sample_rate=48000',
      ]);
    }
    args.addAll([
      '-vf',
      'scale=1280:720:force_original_aspect_ratio=decrease,'
          'pad=1280:720:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p',
      '-map',
      '0:v:0',
      '-map',
      probe.hasAudio ? '0:a:0' : '1:a:0',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-ar',
      '48000',
      '-ac',
      '2',
      '-shortest',
      '-movflags',
      '+faststart',
      outputAbs,
    ]);
    return args;
  }

  String _escapeConcatPath(String value) => value.replaceAll("'", r"'\''");
}

String _tail(String value, {int maxChars = 500}) {
  if (value.length <= maxChars) return value;
  return value.substring(value.length - maxChars);
}
