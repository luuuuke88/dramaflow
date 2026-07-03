import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../config.dart';
import '../media.dart';
import '../util.dart';
import 'resolve.dart';

/// Volcengine Seedance 视频生成（移植 server/src/providers/video.ts，
/// 其源头为 ToonFlow volcengine vendor v2.4）。
/// 流程：POST /contents/generations/tasks → 轮询 → 下载 video_url。
/// ⚠️ 通道按同款参数移植，实测留给用户（spec 约定）。
Future<String> volcengineGenerateVideo(
  Dio dio,
  EngineConfig config,
  MediaStore media,
  ResolvedModel model,
  String prompt,
  String firstFrameAbsPath,
  String projectId, {
  CancelToken? cancelToken,
  Duration pollInterval = const Duration(seconds: 10),
  Duration pollTimeout = const Duration(minutes: 30),
  // 连通测试用：提交任务、确认已受理后立即返回 taskId，不轮询到渲染完成
  // （视频渲染耗时且计费，测试无需等待成片）。
  bool submitOnly = false,
}) async {
  final apiKey = model.apiKey;
  if (apiKey.isEmpty) {
    throw EngineException(errProviderMissing, {'providerId': model.providerId, 'reason': 'apiKey'});
  }
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final headers = {
    'Authorization': 'Bearer ${apiKey.replaceAll(RegExp(r'^Bearer\s+'), '')}'
  };

  final imgB64 = base64Encode(File(firstFrameAbsPath).readAsBytesSync());
  final createRes = await dio.post(
    '$base/contents/generations/tasks',
    data: {
      'model': model.modelId,
      'content': [
        {'type': 'text', 'text': prompt},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$imgB64'},
          'role': 'first_frame',
        },
      ],
      'ratio': '1:1',
      'duration': config.intOf('videoDuration'),
      'resolution': config.str('videoResolution'),
      'watermark': false,
      'generate_audio': true,
    },
    options: Options(
        headers: headers,
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (s) => s != null && s < 400),
    cancelToken: cancelToken,
  );
  final taskId = (createRes.data as Map?)?['id'] as String?;
  if (taskId == null || taskId.isEmpty) {
    throw EngineException(errLlmFormat, {'message': '视频任务创建未返回任务ID'});
  }
  // 连通测试：任务已受理即返回，不等待渲染成片。
  if (submitOnly) return taskId;

  final deadline = DateTime.now().add(pollTimeout);
  while (true) {
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: '$base/tasks/$taskId'),
          reason: '用户取消');
    }
    if (DateTime.now().isAfter(deadline)) {
      throw EngineException(errNetwork, {'message': '轮询超时${pollTimeout.inMinutes}分钟'});
    }
    await Future<void>.delayed(pollInterval);
    final q = await dio.get(
      '$base/contents/generations/tasks/$taskId',
      options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 400),
      cancelToken: cancelToken,
    );
    final task = q.data as Map? ?? const {};
    switch (task['status'] as String?) {
      case 'succeeded':
        final videoUrl = (task['content'] as Map?)?['video_url'] as String?;
        if (videoUrl == null || videoUrl.isEmpty) {
          throw EngineException(errLlmFormat, {'message': '任务成功但未返回视频URL'});
        }
        final dl = await dio.get<List<int>>(videoUrl,
            options: Options(
                responseType: ResponseType.bytes,
                receiveTimeout: const Duration(seconds: 300)),
            cancelToken: cancelToken);
        return media.saveVideo(dl.data ?? const [], projectId);
      case 'failed':
        throw EngineException(
            ((task['error'] as Map?)?['message'] as String?) ?? '视频生成失败');
      case 'expired':
        throw EngineException(errNetwork, {'message': '上游任务超时'});
      case 'cancelled':
        throw EngineException(errCanceled, {'message': '上游取消'});
      default:
        break; // queued / running → 继续轮询
    }
  }
}
