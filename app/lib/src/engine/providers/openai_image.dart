import 'dart:convert';
import 'package:dio/dio.dart';
import '../config.dart';
import '../media.dart';
import '../util.dart';

/// OpenAI 兼容 images/generations（移植 server/src/providers/image.ts）。
/// 已知行为（azt/Codex OAuth 实测）：响应头等到生成完才返回（可达 3-6 分钟）→ receiveTimeout 960s；
/// size/quality 是建议性的，构图靠 prompt 内注入尺寸指令。
Future<String> openaiGenerateImage(
  Dio dio,
  EngineConfig config,
  MediaStore media,
  String prompt,
  String projectId, {
  CancelToken? cancelToken,
}) async {
  final base = config.str('imageBaseUrl').replaceAll(RegExp(r'/+$'), '');
  final fullPrompt = '${prompt.trim()}\n\n${config.str('imageSizeDirective')}';
  final res = await dio.post(
    '$base/images/generations',
    data: {
      'model': config.str('imageModel'),
      'prompt': fullPrompt,
      'size': '1024x1024',
      'quality': 'low',
      'response_format': 'b64_json',
    },
    options: Options(
      headers: {'Authorization': 'Bearer ${config.str('imageApiKey')}'},
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 960),
      validateStatus: (s) => s != null && s < 400,
    ),
    cancelToken: cancelToken,
  );
  final first =
      ((res.data as Map?)?['data'] as List?)?.firstOrNull as Map?;
  final b64 = first?['b64_json'] as String?;
  if (b64 != null && b64.isNotEmpty) {
    return media.saveImage(base64Decode(b64), projectId);
  }
  final url = first?['url'] as String?;
  if (url != null && url.isNotEmpty) {
    final img = await dio.get<List<int>>(url,
        options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 120)),
        cancelToken: cancelToken);
    return media.saveImage(img.data ?? const [], projectId);
  }
  throw EngineException(
      '图片模型未返回图像数据: ${res.data.toString().substring(0, res.data.toString().length > 300 ? 300 : res.data.toString().length)}');
}
