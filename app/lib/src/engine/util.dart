import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';

const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
final _rng = Random.secure();

/// 14位 id，字符集与 v0.1 nanoid 配置一致（server/src/util.ts）
String newId() =>
    List.generate(14, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();

/// 引擎业务异常：message 始终是人类可读中文。
class EngineException implements Exception {
  final String message;
  EngineException(this.message);
  @override
  String toString() => message;
}

/// 从 LLM 输出提取 JSON（容忍围栏与前后杂文）——移植 server/src/util.ts extractJson
dynamic extractJson(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  try {
    return jsonDecode(text);
  } catch (_) {/* fallthrough */}
  final candidates =
      ['{', '['].map((c) => text.indexOf(c)).where((i) => i != -1).toList();
  final end = max(text.lastIndexOf('}'), text.lastIndexOf(']'));
  if (candidates.isNotEmpty) {
    final start = candidates.reduce(min);
    if (end > start) return jsonDecode(text.substring(start, end + 1));
  }
  throw EngineException('输出中未找到有效 JSON');
}

/// 错误 → 人类可读中文消息；Dio 错误附上游响应体（移植 server/src/util.ts errMessage）
String errMessage(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    var detail = '';
    if (data != null) {
      try {
        detail = data is String ? data : jsonEncode(data);
      } catch (_) {
        detail = data.toString();
      }
    }
    final head = status != null ? 'HTTP $status' : '网络错误';
    final tail =
        detail.isEmpty ? '' : '：${detail.substring(0, min(500, detail.length))}';
    return '$head ${e.message ?? ''}$tail';
  }
  return e.toString();
}
