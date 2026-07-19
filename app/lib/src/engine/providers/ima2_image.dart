import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../media.dart';
import '../util.dart';
import 'resolve.dart';

/// ima2 的图片端点不是 OpenAI Images API。该适配器复刻本地
/// `/api/generate` 的 JSON 协议，并有意不把请求改写为 `/images/edits`。
Future<String> ima2GenerateImage(
  Dio dio,
  ResolvedModel model,
  MediaStore media,
  String prompt,
  String projectId, {
  required String? ratio,
  CancelToken? cancelToken,
  List<String> referenceAbsPaths = const [],
  String? maskAbsPath,
}) async {
  if (maskAbsPath?.trim().isNotEmpty ?? false) {
    throw const EngineException(
        errTaskUnsupported, {'reason': 'ima2MaskUnsupported'});
  }
  final imageBaseUrl = (model.providerInputs['imageBaseUrl'] ?? '').trim();
  if (imageBaseUrl.isEmpty) {
    throw EngineException(errProviderMissing, {
      'providerId': model.providerId,
      'reason': 'ima2ImageBaseUrlRequired',
    });
  }

  final references = [
    for (final path in referenceAbsPaths)
      if (path.trim().isNotEmpty)
        'data:image/png;base64,${base64Encode(await File(path).readAsBytes())}',
  ];
  final response = await dio.post<dynamic>(
    '${imageBaseUrl.replaceAll(RegExp(r'/+$'), '')}/api/generate',
    data: {
      'prompt': prompt,
      'provider': 'oauth',
      'model': _requestModelId(model.modelId),
      'quality': _normalizeQuality(model.providerInputs['imageQuality']),
      'size': _normalizeSize(model.providerInputs['imageSize'], ratio),
      'format': 'png',
      'moderation': 'low',
      'n': 1,
      'references': references,
      'mode': 'direct',
      'webSearchEnabled': false,
      'requestId': 'dramaflow_ima2_${DateTime.now().microsecondsSinceEpoch}',
    },
    options: Options(
      contentType: Headers.jsonContentType,
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: _normalizeTimeout(model.providerInputs['imageTimeoutMs']),
      validateStatus: (status) => status != null && status < 400,
    ),
    cancelToken: cancelToken,
  );

  final image = _pickImage(response.data);
  if (image.startsWith('http://') || image.startsWith('https://')) {
    final downloaded = await dio.get<List<int>>(
      image,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 120),
      ),
      cancelToken: cancelToken,
    );
    return media.saveImage(downloaded.data ?? const [], projectId);
  }
  return media.saveImage(base64Decode(_base64Payload(image)), projectId);
}

String _requestModelId(String modelId) =>
    modelId.replaceFirst(RegExp(r'^gpt-image-2-'), '');

String _normalizeQuality(String? value) {
  final normalized = value?.trim().toLowerCase();
  return const {'low', 'medium', 'high'}.contains(normalized)
      ? normalized!
      : 'low';
}

String _normalizeSize(String? configuredSize, String? ratio) {
  final explicit = configuredSize?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  return switch (ratio) {
    '16:9' => '1536x864',
    '9:16' => '864x1536',
    _ => '1024x1024',
  };
}

Duration _normalizeTimeout(String? value) {
  final milliseconds = int.tryParse(value?.trim() ?? '');
  return Duration(
      milliseconds: milliseconds != null && milliseconds >= 60000
          ? milliseconds
          : 960000);
}

String _pickImage(Object? data) {
  if (data is Map) {
    final direct = data['image'];
    if (direct is String && direct.isNotEmpty) return direct;
    final images = data['images'];
    if (images is List) {
      for (final item in images) {
        if (item is String && item.isNotEmpty) return item;
        if (item is Map) {
          final image = item['image'];
          if (image is String && image.isNotEmpty) return image;
          final url = item['url'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
    }
    final url = data['url'];
    if (url is String && url.isNotEmpty) return url;
  }
  throw const EngineException(errLlmFormat, {'reason': 'ima2ImageMissing'});
}

String _base64Payload(String value) {
  if (!value.startsWith('data:')) return value;
  final comma = value.indexOf(',');
  if (comma < 0) {
    throw const EngineException(errLlmFormat, {'reason': 'ima2ImageDataUri'});
  }
  return value.substring(comma + 1);
}
