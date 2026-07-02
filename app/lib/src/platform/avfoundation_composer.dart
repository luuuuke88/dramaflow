import 'package:flutter/services.dart';

import '../engine/compose.dart';
import '../engine/util.dart';

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

  Future<T?> _invoke<T>(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw EngineException(e.message ?? e.details?.toString() ?? e.code);
    }
  }
}
