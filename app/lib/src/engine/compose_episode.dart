// 整集合成导出（照抄 P4 参照 §5 定案：ToonFlow 无服务端合成步骤，DramaFlow 自建）。
// 按 o_storyboard.index 顺序取每个分镜的 trackId→selectVideoId→o_video.filePath，
// 用既有零 ffmpeg VideoComposer.concat 拼接为整集成片。
import 'dart:io';

import 'engine.dart';
import 'errors.dart';

class ComposeResult {
  final String outputRelPath;
  final int segmentCount;
  final double? durationSec;
  const ComposeResult(
      {required this.outputRelPath,
      required this.segmentCount,
      required this.durationSec});
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

  /// 合成整集：任一分镜缺选中视频即报错中文可见（不做部分合成）。
  Future<ComposeResult> composeEpisode(int projectId, int scriptId) async {
    final paths = orderedSelectedVideoPaths(scriptId);
    if (paths.isEmpty) {
      throw const EngineException(errNoChapters, {'reason': 'no storyboards'});
    }
    final missingCount = paths.where((p) => p == null || p.isEmpty).length;
    if (missingCount > 0) {
      throw EngineException(
          errPromptMissing, {'type': 'selectedVideo', 'missing': missingCount});
    }
    final absPaths = [for (final p in paths) media.absPath(p!)];
    final outputRel = '$projectId/episode_${scriptId}_'
        '${DateTime.now().millisecondsSinceEpoch}.mp4';
    final outputAbs = media.absPath(outputRel);
    File(outputAbs).parent.createSync(recursive: true);
    await composer.concat(absPaths, outputAbs);
    final duration = await composer.probeDurationSec(outputAbs);
    return ComposeResult(
      outputRelPath: outputRel,
      segmentCount: absPaths.length,
      durationSec: duration,
    );
  }
}
