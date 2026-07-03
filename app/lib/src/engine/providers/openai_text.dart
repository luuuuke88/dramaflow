import 'dart:convert';

import 'package:dio/dio.dart';
import '../util.dart';
import 'gateway.dart';
import 'resolve.dart';

/// OpenAI 兼容 chat completions（移植 server/src/providers/text.ts）。
/// 该路径（azt→Codex OAuth / ark）不支持 response_format，结构化输出靠 prompt 约定+上层校验。
Future<TextResult> openaiGenerateText(
  Dio dio,
  ResolvedModel model,
  String system,
  String user, {
  CancelToken? cancelToken,
}) async {
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final res = await dio.post(
    '$base/chat/completions',
    data: {
      'model': model.modelId,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'max_completion_tokens': 32000,
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
  if (content == null || content.isEmpty) {
    throw EngineException(errLlmFormat, {'message': _head(data)});
  }
  final usage = (data is Map ? data['usage'] : null) as Map? ?? const {};
  return TextResult(content,
      promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0);
}

String _head(Object? data) {
  final s = data.toString();
  return s.length > 300 ? s.substring(0, 300) : s;
}

/// 结构化输出（ToonFlow resultTool 语义）。
/// 优先 tools + tool_choice 强制调用；azt/Codex OAuth 等不支持工具调用的后端
/// 回退解析正文 JSON（user 消息已附加纯 JSON 输出指令兜底）。
Future<Map<String, dynamic>> openaiGenerateToolJson(
  Dio dio,
  ResolvedModel model,
  String system,
  String user, {
  required String toolName,
  required Map<String, dynamic> schema,
  CancelToken? cancelToken,
}) async {
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final res = await dio.post(
    '$base/chat/completions',
    data: {
      'model': model.modelId,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': '$user\n\n（若无法调用 $toolName 工具，请直接输出符合其参数 '
              'schema 的纯 JSON，不要输出任何其他文字）',
        },
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': toolName,
            'description': '结构化结果提交工具',
            'parameters': schema,
          },
        },
      ],
      'tool_choice': {
        'type': 'function',
        'function': {'name': toolName},
      },
      'max_completion_tokens': 32000,
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
  if (data is Map) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map?)?['message'];
      if (msg is Map) {
        final toolCalls = msg['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) {
          final args = ((toolCalls.first as Map?)?['function']
              as Map?)?['arguments'];
          final parsed = _tryParseJsonObject(args is String ? args : null);
          if (parsed != null) return parsed;
        }
        final content = msg['content'];
        if (content is String) {
          final parsed = _tryParseJsonObject(_extractJsonBlock(content));
          if (parsed != null) return parsed;
        }
      }
    }
  }
  throw EngineException(errLlmFormat, {'message': _head(data)});
}

/// 一个可供模型自由选择调用的工具定义（Agent 多工具场景，对应 P5 AgentRunner）。
class AgentToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  const AgentToolDef(
      {required this.name, required this.description, required this.schema});
}

/// Agent 对话轮次结果：要么是纯文本回复，要么是一次工具调用（互斥）。
class AgentTurnResult {
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  const AgentTurnResult.text(this.text)
      : toolName = null,
        toolArgs = null;
  const AgentTurnResult.tool(this.toolName, this.toolArgs) : text = null;
  bool get isToolCall => toolName != null;
}

/// 多轮对话+多工具自由选择（tool_choice=auto，模型可回文本也可调用任一工具）。
/// messages 为 [{role,content}] 历史（不含 system）。
Future<AgentTurnResult> openaiGenerateAgentTurn(
  Dio dio,
  ResolvedModel model,
  String system,
  List<Map<String, String>> messages,
  List<AgentToolDef> tools, {
  CancelToken? cancelToken,
}) async {
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final res = await dio.post(
    '$base/chat/completions',
    data: {
      'model': model.modelId,
      'messages': [
        {'role': 'system', 'content': system},
        ...messages,
      ],
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.schema,
            },
          },
      ],
      'tool_choice': 'auto',
      'max_completion_tokens': 8000,
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
  if (data is Map) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map?)?['message'];
      if (msg is Map) {
        final toolCalls = msg['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) {
          final call = (toolCalls.first as Map?)?['function'];
          final name = call?['name'] as String?;
          final args = _tryParseJsonObject(
                  call?['arguments'] is String ? call!['arguments'] as String : null) ??
              const {};
          if (name != null) return AgentTurnResult.tool(name, args);
        }
        final content = msg['content'];
        if (content is String && content.trim().isNotEmpty) {
          return AgentTurnResult.text(content.trim());
        }
      }
    }
  }
  throw EngineException(errLlmFormat, {'message': _head(data)});
}

Map<String, dynamic>? _tryParseJsonObject(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(s);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// 从正文提取首个 JSON 对象块（容忍 ```json 围栏与前后杂文）。
String? _extractJsonBlock(String content) {
  final fenced =
      RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content)?.group(1);
  final candidate = fenced ?? content;
  final start = candidate.indexOf('{');
  final end = candidate.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  return candidate.substring(start, end + 1);
}
