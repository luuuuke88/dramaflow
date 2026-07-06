import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../util.dart';
import 'gateway.dart';
import 'resolve.dart';

Future<TextResult> openaiAnalyzeImage(
  Dio dio,
  ResolvedModel model,
  String prompt,
  String imageAbsPath, {
  CancelToken? cancelToken,
}) async {
  final file = File(imageAbsPath);
  if (!file.existsSync()) {
    throw EngineException(errLlmFormat, {'reason': 'image_not_found'});
  }
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final imageUrl = 'data:${_imageMimeType(imageAbsPath)};base64,'
      '${base64Encode(file.readAsBytesSync())}';
  final res = await dio.post(
    '$base/chat/completions',
    data: {
      'model': model.modelId,
      'messages': [
        {
          'role': 'system',
          'content': '你是短剧视觉分析助手。请根据参考图提炼可用于角色、场景、画风和生图提示词的客观视觉信息。',
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': prompt.trim().isEmpty ? '分析这张参考图。' : prompt.trim(),
            },
            {
              'type': 'image_url',
              'image_url': {'url': imageUrl},
            },
          ],
        },
      ],
      'max_completion_tokens': model.maxOutputTokens ?? 1200,
      if (model.temperature != null) 'temperature': model.temperature! / 100,
    },
    options: Options(
      headers: model.apiKey.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer ${model.apiKey}'},
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 300),
      validateStatus: (s) => s != null && s < 400,
    ),
    cancelToken: cancelToken,
  );
  final data = res.data;
  String? content;
  if (data is Map) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map?)?['message'];
      if (msg is Map) content = msg['content'] as String?;
    }
  }
  if (content == null || content.trim().isEmpty) {
    throw EngineException(errLlmFormat, {'message': _head(data)});
  }
  final usage = (data is Map ? data['usage'] : null) as Map? ?? const {};
  return TextResult(
    content.trim(),
    promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
    completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
  );
}

String _imageMimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}

String _head(Object? data) {
  final s = data.toString();
  return s.length > 300 ? s.substring(0, 300) : s;
}
