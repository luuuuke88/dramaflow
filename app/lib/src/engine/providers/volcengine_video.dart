import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

import '../media.dart';
import '../util.dart';
import '../video_request.dart';
import 'resolve.dart';

class VideoSubmission {
  final String upstreamTaskId;

  const VideoSubmission(this.upstreamTaskId);
}

class VideoPollResult {
  final String upstreamState;
  final String? localVideoPath;
  final String? errorMessage;

  const VideoPollResult({
    required this.upstreamState,
    this.localVideoPath,
    this.errorMessage,
  });

  bool get isTerminal =>
      upstreamState != 'queued' && upstreamState != 'running';
}

Future<VideoSubmission> volcengineSubmitVideo(
  Dio dio,
  MediaStore media,
  ResolvedModel model,
  VideoGenerationRequest request, {
  CancelToken? cancelToken,
}) async {
  final base = _baseUrl(model);
  final response = await dio.post(
    '$base/contents/generations/tasks',
    data: {
      'model': model.modelId,
      'content': _contentForRequest(media, request),
      'ratio': request.ratio,
      'duration': request.duration,
      'resolution': request.resolution,
      'watermark': false,
      'generate_audio': request.generateAudio,
    },
    options: _options(model, receiveTimeout: const Duration(seconds: 60)),
    cancelToken: cancelToken,
  );
  final taskId = (response.data as Map?)?['id'] as String?;
  if (taskId == null || taskId.isEmpty) {
    throw const EngineException(errLlmFormat, {'reason': '视频任务创建未返回任务ID'});
  }
  return VideoSubmission(taskId);
}

Future<VideoPollResult> volcenginePollVideo(
  Dio dio,
  MediaStore media,
  ResolvedModel model,
  String upstreamTaskId,
  String projectId, {
  CancelToken? cancelToken,
}) async {
  final base = _baseUrl(model);
  final response = await dio.get(
    '$base/contents/generations/tasks/$upstreamTaskId',
    options: _options(model, receiveTimeout: const Duration(seconds: 30)),
    cancelToken: cancelToken,
  );
  final task = response.data as Map? ?? const {};
  final state = task['status'] as String?;
  if (state == null || state.isEmpty) {
    throw const EngineException(errLlmFormat, {'reason': '视频任务未返回状态'});
  }
  if (state != 'succeeded') {
    return VideoPollResult(
      upstreamState: state,
      errorMessage: _upstreamError(task),
    );
  }

  final videoUrl = (task['content'] as Map?)?['video_url'] as String?;
  if (videoUrl == null || videoUrl.isEmpty) {
    throw const EngineException(errLlmFormat, {'reason': '任务成功但未返回视频URL'});
  }
  final download = await dio.get<List<int>>(
    videoUrl,
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 300),
    ),
    cancelToken: cancelToken,
  );
  return VideoPollResult(
    upstreamState: state,
    localVideoPath: media.saveVideo(download.data ?? const [], projectId),
  );
}

Future<void> volcengineCancelVideo(
  Dio dio,
  ResolvedModel model,
  String upstreamTaskId,
) async {
  try {
    await dio.delete(
      '${_baseUrl(model)}/contents/generations/tasks/$upstreamTaskId',
      options: _options(model, receiveTimeout: const Duration(seconds: 30)),
    );
  } on DioException {
    // Seedance cancellation is not available on every upstream deployment.
  }
}

String _baseUrl(ResolvedModel model) {
  if (model.apiKey.isEmpty) {
    throw EngineException(errProviderMissing,
        {'providerId': model.providerId, 'reason': 'apiKey'});
  }
  return model.baseUrl.replaceAll(RegExp(r'/+$'), '');
}

Options _options(ResolvedModel model, {required Duration receiveTimeout}) =>
    Options(
      headers: {
        'Authorization':
            'Bearer ${model.apiKey.replaceAll(RegExp(r'^Bearer\s+'), '')}',
      },
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: receiveTimeout,
      validateStatus: (status) => status != null && status < 400,
    );

List<Map<String, Object>> _contentForRequest(
  MediaStore media,
  VideoGenerationRequest request,
) =>
    [
      {'type': 'text', 'text': request.prompt},
      for (final reference in _orderedReferences(request))
        _referenceContent(media, reference),
    ];

Map<String, Object> _referenceContent(
  MediaStore media,
  VideoReference reference,
) {
  final url = _dataUrl(media, reference.localPath);
  return switch (reference.mediaType) {
    'image' => {
        'type': 'image_url',
        'image_url': {'url': url},
        'role': reference.role,
      },
    'video' => {
        'type': 'video_url',
        'video_url': {'url': url},
        'role': reference.role,
      },
    'audio' => {
        'type': 'audio_url',
        'audio_url': {'url': url},
        'role': reference.role,
      },
    _ => throw EngineException(
        errFileType,
        {'reason': '不支持的视频参考媒体类型'},
      ),
  };
}

Iterable<VideoReference> _orderedReferences(VideoGenerationRequest request) {
  switch (request.mode) {
    case VideoMode.text:
      return const [];
    case VideoMode.firstFrame:
      return [
        request.references
            .singleWhere((reference) => reference.role == 'first_frame'),
      ];
    case VideoMode.firstLastFrame:
      return [
        request.references
            .singleWhere((reference) => reference.role == 'first_frame'),
        request.references
            .singleWhere((reference) => reference.role == 'last_frame'),
      ];
    case VideoMode.multiReference:
      return request.references;
  }
}

String _dataUrl(MediaStore media, String localPath) {
  final mime = _mimeForPath(localPath);
  if (mime == null) {
    throw EngineException(errFileType, {'reason': '不支持的视频参考文件类型'});
  }
  final bytes = File(media.absPath(localPath)).readAsBytesSync();
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

String? _mimeForPath(String localPath) {
  switch (path.extension(localPath).toLowerCase()) {
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.mp4':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.webm':
      return 'video/webm';
    case '.mp3':
      return 'audio/mpeg';
    case '.wav':
      return 'audio/wav';
    case '.m4a':
      return 'audio/mp4';
    case '.aac':
      return 'audio/aac';
    default:
      return null;
  }
}

String? _upstreamError(Map task) {
  final error = task['error'];
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  return task['message'] as String?;
}
