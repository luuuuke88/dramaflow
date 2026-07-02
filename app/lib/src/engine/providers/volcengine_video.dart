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
}) async {
  final apiKey = model.apiKey;
  if (apiKey.isEmpty) {
    throw EngineException('未配置视频 API Key（供应商 ${model.providerId}）');
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
    throw EngineException('视频任务创建失败：未返回任务ID (${createRes.data})');
  }

  final deadline = DateTime.now().add(pollTimeout);
  while (true) {
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: '$base/tasks/$taskId'),
          reason: '用户取消');
    }
    if (DateTime.now().isAfter(deadline)) {
      throw EngineException('视频生成轮询超时(${pollTimeout.inMinutes}分钟)');
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
          throw EngineException('任务成功但未返回视频URL');
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
        throw EngineException('视频生成任务超时(上游)');
      case 'cancelled':
        throw EngineException('视频生成任务已被上游取消');
      default:
        break; // queued / running → 继续轮询
    }
  }
}
