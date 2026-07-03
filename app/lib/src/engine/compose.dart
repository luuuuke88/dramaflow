import 'errors.dart';

abstract class VideoComposer {
  Future<double?> probeDurationSec(String inputAbsPath);

  Future<void> concat(List<String> segmentAbsPaths, String outputAbsPath);
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
}
