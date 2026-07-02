import 'package:dio/dio.dart';
import '../config.dart';
import '../media.dart';
import 'openai_text.dart';
import 'openai_image.dart';
import 'volcengine_video.dart';

class TextResult {
  final String content;
  final int promptTokens;
  final int completionTokens;
  const TextResult(this.content,
      {this.promptTokens = 0, this.completionTokens = 0});
}

/// 供应商网关：runners 只面对这三个方法。M2 会在此层引入 providers 表的 resolve。
abstract class ProviderGateway {
  Future<TextResult> generateText(String system, String user,
      {CancelToken? cancelToken});

  /// 返回 rel 媒体路径（如 `proj1/img_xxx.png`）
  Future<String> generateImage(String prompt, String projectId,
      {CancelToken? cancelToken});

  /// 返回 rel 媒体路径（如 `proj1/vid_xxx.mp4`）
  Future<String> generateVideo(
      String prompt, String firstFrameAbsPath, String projectId,
      {CancelToken? cancelToken});
}

class HttpProviderGateway implements ProviderGateway {
  final EngineConfig config;
  final MediaStore media;
  final Dio dio;
  final Duration pollInterval;
  final Duration pollTimeout;

  HttpProviderGateway(this.config, this.media,
      {Dio? dio,
      this.pollInterval = const Duration(seconds: 10),
      this.pollTimeout = const Duration(minutes: 30)})
      : dio = dio ?? Dio();

  @override
  Future<TextResult> generateText(String system, String user,
          {CancelToken? cancelToken}) =>
      openaiGenerateText(dio, config, system, user, cancelToken: cancelToken);

  @override
  Future<String> generateImage(String prompt, String projectId,
          {CancelToken? cancelToken}) =>
      openaiGenerateImage(dio, config, media, prompt, projectId,
          cancelToken: cancelToken);

  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {CancelToken? cancelToken}) =>
      volcengineGenerateVideo(dio, config, media, prompt, firstFrameAbsPath,
          projectId,
          cancelToken: cancelToken,
          pollInterval: pollInterval,
          pollTimeout: pollTimeout);
}
