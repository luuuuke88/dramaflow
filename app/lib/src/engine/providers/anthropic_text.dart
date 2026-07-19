import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../util.dart';
import 'gateway.dart';
import 'resolve.dart';

const anthropicApiVersion = '2023-06-01';

Future<TextResult> anthropicGenerateText(
  Dio dio,
  ResolvedModel model,
  String system,
  String user, {
  CancelToken? cancelToken,
}) async {
  final data = await _post(
    dio,
    model,
    {
      'model': model.modelId,
      'max_tokens': model.maxOutputTokens ?? 32000,
      if (system.trim().isNotEmpty) 'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
    },
    cancelToken: cancelToken,
  );
  final content = _textContent(data);
  if (content == null || content.isEmpty) {
    throw EngineException(errLlmFormat, {'message': _head(data)});
  }
  final usage = (data['usage'] as Map?) ?? const {};
  return TextResult(
    content,
    promptTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
    completionTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
  );
}

Future<Map<String, dynamic>> anthropicGenerateToolJson(
  Dio dio,
  ResolvedModel model,
  String system,
  String user, {
  required String toolName,
  required Map<String, dynamic> schema,
  CancelToken? cancelToken,
}) async {
  final data = await _post(
    dio,
    model,
    {
      'model': model.modelId,
      'max_tokens': model.maxOutputTokens ?? 32000,
      if (system.trim().isNotEmpty) 'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
      'tools': [
        {
          'name': toolName,
          'description': '结构化结果提交工具',
          'input_schema': schema,
        },
      ],
      'tool_choice': {'type': 'tool', 'name': toolName},
    },
    cancelToken: cancelToken,
  );
  for (final block in _contentBlocks(data)) {
    if (block['type'] == 'tool_use' && block['input'] is Map) {
      return Map<String, dynamic>.from(block['input'] as Map);
    }
  }
  throw EngineException(errLlmFormat, {'message': _head(data)});
}

Future<AgentTurnResult> anthropicGenerateAgentTurn(
  Dio dio,
  ResolvedModel model,
  String system,
  List<Map<String, String>> messages,
  List<AgentToolDef> tools, {
  CancelToken? cancelToken,
}) async {
  final data = await _post(
    dio,
    model,
    {
      'model': model.modelId,
      'max_tokens': model.maxOutputTokens ?? 8000,
      if (system.trim().isNotEmpty) 'system': system,
      'messages': messages,
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.schema,
            },
        ],
      if (tools.isNotEmpty) 'tool_choice': {'type': 'auto'},
    },
    cancelToken: cancelToken,
  );
  for (final block in _contentBlocks(data)) {
    if (block['type'] == 'tool_use' && block['name'] is String) {
      return AgentTurnResult.tool(
        block['name'] as String,
        block['input'] is Map
            ? Map<String, dynamic>.from(block['input'] as Map)
            : const {},
      );
    }
  }
  final content = _textContent(data);
  if (content != null && content.trim().isNotEmpty) {
    return AgentTurnResult.text(content.trim());
  }
  throw EngineException(errLlmFormat, {'message': _head(data)});
}

Future<TextResult> anthropicAnalyzeImage(
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
  final data = await _post(
    dio,
    model,
    {
      'model': model.modelId,
      'max_tokens': model.maxOutputTokens ?? 1200,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': prompt.trim().isEmpty ? '分析这张参考图。' : prompt.trim(),
            },
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': _imageMimeType(imageAbsPath),
                'data': base64Encode(file.readAsBytesSync()),
              },
            },
          ],
        },
      ],
    },
    cancelToken: cancelToken,
  );
  final content = _textContent(data);
  if (content == null || content.trim().isEmpty) {
    throw EngineException(errLlmFormat, {'message': _head(data)});
  }
  final usage = (data['usage'] as Map?) ?? const {};
  return TextResult(
    content.trim(),
    promptTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
    completionTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
  );
}

Future<Map<String, dynamic>> _post(
  Dio dio,
  ResolvedModel model,
  Map<String, dynamic> body, {
  CancelToken? cancelToken,
}) async {
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final response = await dio.post<dynamic>(
    '$base/messages',
    data: body,
    options: _options(model),
    cancelToken: cancelToken,
  );
  if (response.data is! Map) {
    throw EngineException(errLlmFormat, {'message': _head(response.data)});
  }
  return Map<String, dynamic>.from(response.data as Map);
}

Options _options(ResolvedModel model) => Options(
      headers: {
        'x-api-key': model.apiKey,
        'anthropic-version': anthropicApiVersion,
      },
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 300),
      validateStatus: (status) => status != null && status < 400,
    );

List<Map<dynamic, dynamic>> _contentBlocks(Map<String, dynamic> data) => [
      for (final block in (data['content'] as List? ?? const []))
        if (block is Map) block,
    ];

String? _textContent(Map<String, dynamic> data) {
  final texts = [
    for (final block in _contentBlocks(data))
      if (block['type'] == 'text' && block['text'] is String)
        (block['text'] as String).trim(),
  ].where((text) => text.isNotEmpty).toList();
  return texts.isEmpty ? null : texts.join('\n');
}

String _head(Object? data) {
  final text = data.toString();
  return text.length > 300 ? text.substring(0, 300) : text;
}

String _imageMimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}
