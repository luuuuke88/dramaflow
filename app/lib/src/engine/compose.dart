import 'errors.dart';

class ComposeSegment {
  final String videoAbsPath;
  final String? audioAbsPath;
  final String? transition;
  final String? filter;
  final String timelineKind;
  final int lane;
  final int? startMs;
  final int? durationMs;

  const ComposeSegment({
    required this.videoAbsPath,
    this.audioAbsPath,
    this.transition,
    this.filter,
    this.timelineKind = 'storyboard',
    this.lane = 0,
    this.startMs,
    this.durationMs,
  });

  bool get hasAudio => audioAbsPath != null && audioAbsPath!.isNotEmpty;

  bool get hasTimelineMetadata =>
      timelineKind != 'storyboard' ||
      lane != 0 ||
      startMs != null ||
      durationMs != null;
}

abstract class VideoComposer {
  Future<double?> probeDurationSec(String inputAbsPath);

  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath);

  Future<void> compose(
    List<ComposeSegment> segments,
    String outputAbsPath,
  ) async {
    if (segments.any((s) => s.hasAudio)) {
      throw const EngineException(errFileType, {'reason': '当前平台暂不支持配音混合'});
    }
    await concat([for (final s in segments) s.videoAbsPath], outputAbsPath);
  }
}

class UnsupportedComposer implements VideoComposer {
  const UnsupportedComposer();

  @override
  Future<double?> probeDurationSec(String inputAbsPath) {
    throw const EngineException(errFileType, {'reason': '当前平台暂不支持视频合成'});
  }

  @override
  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath) {
    throw const EngineException(errFileType, {'reason': '当前平台暂不支持视频合成'});
  }

  @override
  Future<void> compose(List<ComposeSegment> segments, String outputAbsPath) {
    throw const EngineException(errFileType, {'reason': '当前平台暂不支持视频合成'});
  }
}
