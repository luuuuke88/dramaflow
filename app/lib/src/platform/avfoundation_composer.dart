import 'package:flutter/services.dart';

import '../engine/compose.dart';
import '../engine/util.dart';

class ComposerMediaInfo {
  final int videoTrackCount;
  final int audioTrackCount;
  final double? durationSec;

  const ComposerMediaInfo({
    required this.videoTrackCount,
    required this.audioTrackCount,
    this.durationSec,
  });

  factory ComposerMediaInfo.fromMap(Map<Object?, Object?> value) {
    final videoTrackCount = value['videoTrackCount'];
    final audioTrackCount = value['audioTrackCount'];
    final durationSec = value['durationSec'];
    if (videoTrackCount is! num || audioTrackCount is! num) {
      throw EngineException('读取媒体轨道失败：平台返回值无效');
    }
    return ComposerMediaInfo(
      videoTrackCount: videoTrackCount.toInt(),
      audioTrackCount: audioTrackCount.toInt(),
      durationSec: durationSec is num ? durationSec.toDouble() : null,
    );
  }
}

class AVFoundationComposer implements VideoComposer {
  static const MethodChannel _channel = MethodChannel('dramaflow/composer');

  const AVFoundationComposer();

  @override
  Future<double?> probeDurationSec(String inputAbsPath) async {
    final value =
        await _invoke<Object?>('probeDuration', {'path': inputAbsPath});
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw EngineException('读取视频时长失败：平台返回值无效');
  }

  @override
  Future<void> concat(
      List<String> segmentAbsPaths, String outputAbsPath) async {
    await _invoke<void>(
      'concat',
      {'paths': segmentAbsPaths, 'output': outputAbsPath},
    );
  }

  @override
  Future<void> compose(
      List<ComposeSegment> segments, String outputAbsPath) async {
    await _invoke<void>(
      'compose',
      {
        'segments': [
          for (final segment in segments)
            {
              'videoPath': segment.videoAbsPath,
              'audioPath': segment.audioAbsPath,
            },
        ],
        'output': outputAbsPath,
      },
    );
  }

  Future<ComposerMediaInfo> inspectMedia(String inputAbsPath) async {
    final value =
        await _invoke<Object?>('inspectMedia', {'path': inputAbsPath});
    if (value is Map<Object?, Object?>) {
      return ComposerMediaInfo.fromMap(value);
    }
    throw EngineException('读取媒体轨道失败：平台返回值无效');
  }

  Future<T?> _invoke<T>(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw EngineException(e.message ?? e.details?.toString() ?? e.code);
    }
  }
}
