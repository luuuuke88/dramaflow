import 'package:dio/dio.dart';
import '../config.dart';
import '../util.dart';
import 'gateway.dart';

/// OpenAI 兼容 chat completions（移植 server/src/providers/text.ts）。
/// 该路径（azt→Codex OAuth / ark）不支持 response_format，结构化输出靠 prompt 约定+上层校验。
Future<TextResult> openaiGenerateText(
  Dio dio,
  EngineConfig config,
  String system,
  String user, {
  CancelToken? cancelToken,
}) async {
  final base = config.str('textBaseUrl').replaceAll(RegExp(r'/+$'), '');
  final res = await dio.post(
    '$base/chat/completions',
    data: {
      'model': config.str('textModel'),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'max_completion_tokens': 32000,
    },
    options: Options(
      headers: {'Authorization': 'Bearer ${config.str('textApiKey')}'},
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
  if (content == null || content.isEmpty) {
    throw EngineException('文本模型未返回内容: ${_head(data)}');
  }
  final usage =
      (data is Map ? data['usage'] : null) as Map? ?? const {};
  return TextResult(content,
      promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0);
}

String _head(Object? data) {
  final s = data.toString();
  return s.length > 300 ? s.substring(0, 300) : s;
}
