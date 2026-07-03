import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../media.dart';
import '../util.dart';
import 'resolve.dart';

/// OpenAI-compatible speech synthesis (`/audio/speech`).
Future<String> openaiGenerateSpeech(
  Dio dio,
  ResolvedModel model,
  MediaStore media,
  String text,
  String projectId, {
  required String voice,
  String? format,
  CancelToken? cancelToken,
}) async {
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final responseFormat = _speechFormat(format);
  final res = await dio.post(
    '$base/audio/speech',
    data: {
      'model': model.modelId,
      'input': text,
      'voice': voice,
      'response_format': responseFormat,
    },
    options: Options(
      headers: model.apiKey.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer ${model.apiKey}'},
      responseType: ResponseType.bytes,
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 300),
      validateStatus: (s) => s != null && s < 400,
    ),
    cancelToken: cancelToken,
  );
  final data = res.data;
  final bytes = switch (data) {
    Uint8List b => b,
    List<int> b => Uint8List.fromList(b),
    _ => throw EngineException(errLlmFormat, {'message': data.toString()}),
  };
  if (bytes.isEmpty) {
    throw const EngineException(errLlmFormat, {'message': 'empty audio'});
  }
  return media.saveAudio(bytes, projectId, ext: responseFormat);
}

String _speechFormat(String? format) {
  final value = (format ?? 'mp3').trim().toLowerCase();
  return switch (value) {
    'mp3' || 'opus' || 'aac' || 'flac' || 'wav' || 'pcm' => value,
    _ => 'mp3',
  };
}
