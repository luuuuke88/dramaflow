// 整集合成导出（照抄 P4 参照 §5 定案：ToonFlow 无服务端合成步骤，DramaFlow 自建）。
// 按 o_storyboard.index 顺序取每个分镜的 trackId→selectVideoId→o_video.filePath，
// 用既有零 ffmpeg VideoComposer.concat 拼接为整集成片。
import 'dart:io';

import 'assets.dart';
import 'audio_bind.dart';
import 'compose.dart';
import 'engine.dart';
import 'errors.dart';
import 'timeline_clip.dart';

class ComposeResult {
  final String outputRelPath;
  final int segmentCount;
  final double? durationSec;
  final int? clipAssetId;
  const ComposeResult(
      {required this.outputRelPath,
      required this.segmentCount,
      required this.durationSec,
      this.clipAssetId});
}

extension ComposeEpisodeApi on Engine {
  /// 校验并返回按序排列的已选视频绝对路径（不做拼接，供 UI 预检提示缺口）。
  List<String?> orderedSelectedVideoPaths(int scriptId) {
    final rows = db.select(
      'SELECT sb."index" idx, v.filePath filePath '
      'FROM o_storyboard sb '
      'LEFT JOIN o_videoTrack t ON t.id=sb.trackId '
      'LEFT JOIN o_video v ON v.id=t.selectVideoId '
      'WHERE sb.scriptId=? ORDER BY sb."index" ASC',
      [scriptId],
    );
    return [for (final r in rows) r['filePath'] as String?];
  }

  List<ComposeSegment?> orderedComposeSegments(int scriptId) {
    final rows = db.select(
      'SELECT sb."index" idx, sb.duration storyboardDuration, '
      'v.filePath videoPath, '
      'sb.audioPath audioPath, sb.audioAssetId audioAssetId, '
      't.transition transition, t.filterPreset filterPreset, '
      't.duration trackDuration '
      'FROM o_storyboard sb '
      'LEFT JOIN o_videoTrack t ON t.id=sb.trackId '
      'LEFT JOIN o_video v ON v.id=t.selectVideoId '
      'WHERE sb.scriptId=? ORDER BY sb."index" ASC',
      [scriptId],
    );
    final extraClips = timelineClips(scriptId);
    if (extraClips.isEmpty) {
      return [
        for (final r in rows)
          _composeSegment(
            r['videoPath'] as String?,
            r['audioPath'] as String?,
            r['audioAssetId'] as int?,
            r['transition'] as String?,
            r['filterPreset'] as String?,
          ),
      ];
    }

    final timed = <_TimedComposeSegment>[];
    var cursorMs = 0;
    for (final r in rows) {
      final durationMs = _durationMs(
        r['trackDuration'] as int?,
        r['storyboardDuration'] as String?,
      );
      timed.add(_TimedComposeSegment(
        startMs: cursorMs,
        lane: 0,
        segment: _composeSegment(
          r['videoPath'] as String?,
          r['audioPath'] as String?,
          r['audioAssetId'] as int?,
          r['transition'] as String?,
          r['filterPreset'] as String?,
          timelineKind: 'storyboard',
          lane: 0,
          startMs: cursorMs,
          durationMs: durationMs,
        ),
      ));
      if (durationMs != null) cursorMs += durationMs;
    }
    for (final clip in extraClips) {
      timed.add(_TimedComposeSegment(
        startMs: clip.startMs,
        lane: clip.lane,
        segment: ComposeSegment(
          videoAbsPath: media.absPath(clip.filePath),
          timelineKind: 'clip',
          lane: clip.lane,
          startMs: clip.startMs,
          durationMs: clip.durationMs,
        ),
      ));
    }
    timed.sort((a, b) {
      final byStart = a.startMs.compareTo(b.startMs);
      if (byStart != 0) return byStart;
      final byLane = a.lane.compareTo(b.lane);
      if (byLane != 0) return byLane;
      return 0;
    });
    return [
      for (final item in timed) item.segment,
    ];
  }

  ComposeSegment? _composeSegment(String? videoPath, String? audioPath,
      int? audioAssetId, String? transition, String? filter,
      {String timelineKind = 'storyboard',
      int lane = 0,
      int? startMs,
      int? durationMs}) {
    if (videoPath == null || videoPath.isEmpty) return null;
    String? audioAbs;
    if (audioPath != null && audioPath.isNotEmpty) {
      audioAbs = media.absPath(audioPath);
    } else if (audioAssetId != null) {
      audioAbs = audioAssetAbsPath(audioAssetId);
    }
    return ComposeSegment(
      videoAbsPath: media.absPath(videoPath),
      audioAbsPath: audioAbs,
      transition: transition,
      filter: filter,
      timelineKind: timelineKind,
      lane: lane,
      startMs: startMs,
      durationMs: durationMs,
    );
  }

  /// 合成整集：任一分镜缺选中视频即报错中文可见（不做部分合成）。
  Future<ComposeResult> composeEpisode(int projectId, int scriptId) async {
    final segments = orderedComposeSegments(scriptId);
    if (segments.isEmpty) {
      throw const EngineException(errNoChapters, {'reason': 'no storyboards'});
    }
    final missingCount = segments.where((s) => s == null).length;
    if (missingCount > 0) {
      throw EngineException(
          errPromptMissing, {'type': 'selectedVideo', 'missing': missingCount});
    }
    final composeSegments = [for (final s in segments) s!];
    final outputRel = '$projectId/episode_${scriptId}_'
        '${DateTime.now().millisecondsSinceEpoch}.mp4';
    final outputAbs = media.absPath(outputRel);
    File(outputAbs).parent.createSync(recursive: true);
    final hasNleMetadata = composeSegments.any((s) =>
        s.transition != null || s.filter != null || s.hasTimelineMetadata);
    if (composeSegments.any((s) => s.hasAudio) || hasNleMetadata) {
      await composer.compose(composeSegments, outputAbs);
    } else {
      await composer.concat(
          [for (final segment in composeSegments) segment.videoAbsPath],
          outputAbs);
    }
    final duration = await composer.probeDurationSec(outputAbs);
    final scriptName = db.select('SELECT name FROM o_script WHERE id=?',
            [scriptId]).firstOrNull?['name'] as String? ??
        '$scriptId';
    final clipAssetId = registerClipAsset(
      projectId: projectId,
      name: '成片：$scriptName',
      relPath: outputRel,
    );
    return ComposeResult(
      outputRelPath: outputRel,
      segmentCount: composeSegments.length,
      durationSec: duration,
      clipAssetId: clipAssetId,
    );
  }
}

class _TimedComposeSegment {
  final int startMs;
  final int lane;
  final ComposeSegment? segment;

  const _TimedComposeSegment({
    required this.startMs,
    required this.lane,
    required this.segment,
  });
}

int? _durationMs(int? trackDurationSec, String? storyboardDuration) {
  final seconds = trackDurationSec ?? _parseDurationSeconds(storyboardDuration);
  return seconds == null || seconds <= 0 ? null : seconds * 1000;
}

int? _parseDurationSeconds(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final direct = int.tryParse(trimmed);
  if (direct != null) return direct;
  final match = RegExp(r'\d+').firstMatch(trimmed);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}
