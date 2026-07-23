import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import '../config.dart';
import '../credentials.dart';
import '../errors.dart';
import '../media.dart';
import '../util.dart';
import 'openai_text.dart';
import 'openai_vision.dart';
import 'anthropic_text.dart';
import 'ima2_image.dart';
import 'openai_image.dart';
import 'openai_tts.dart';
import 'resolve.dart';
import 'volcengine_video.dart';
import '../video_request.dart';

export 'openai_text.dart' show AgentTurnResult, AgentToolDef;

/// 1×1 透明 PNG（最小合法图容器），用于视频连通测试的首帧占位。
final _tinyPngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class TextResult {
  final String content;
  final int promptTokens;
  final int completionTokens;
  const TextResult(this.content,
      {this.promptTokens = 0, this.completionTokens = 0});
}

/// 供应商网关：runners 只面对这三个方法。M2 会在此层引入 providers 表的 resolve。
abstract class ProviderGateway {
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken});

  /// 返回 rel 媒体路径（如 `proj1/img_xxx.png`）。
  /// referenceAbsPaths：多张参考图（对齐 ToonFlow 的 referenceList，全部传给图模型）。
  /// ratio/quality：逐次生成的画幅/清晰度（对齐 generatedNode / generateAssets）。
  /// modelOverride：'providerId:modelId'，覆盖阶段绑定的图模型（为空则用 stage 解析）。
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    List<String> referenceAbsPaths = const [],
    String? editInstruction,
    String? maskAbsPath,
    String? ratio,
    String? quality,
    String? modelOverride,
  });

  /// Submits a typed video request without waiting for rendering.
  Future<VideoSubmission> submitVideo(VideoGenerationRequest request,
          {required String stage, CancelToken? cancelToken}) =>
      Future.error(UnsupportedError('此网关不支持视频提交'));

  /// Reads exactly one upstream video-task state, downloading only successes.
  Future<VideoPollResult> pollVideo(String upstreamTaskId, String projectId,
          {required String stage,
          required String? modelOverride,
          CancelToken? cancelToken}) =>
      Future.error(UnsupportedError('此网关不支持视频轮询'));

  /// Requests best-effort cancellation of an upstream video task.
  Future<void> cancelVideo(String upstreamTaskId,
          {required String stage, required String? modelOverride}) =>
      Future.error(UnsupportedError('此网关不支持视频取消'));

  /// GET {baseUrl}/models，仅返回远端模型 ID 候选（不写库；spec §5 第 5 条）。
  Future<List<String>> listRemoteModelIds(String providerId) =>
      Future.error(UnsupportedError('此网关不支持模型列表拉取'));

  /// 返回 rel 媒体路径（如 `proj1/aud_xxx.mp3`）。
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  });

  /// 结构化输出（ToonFlow resultTool 语义）：优先走 tools/tool_choice，
  /// 后端不支持工具调用时回退解析正文中的 JSON；两路都失败抛 errLlmFormat。
  Future<Map<String, dynamic>> generateToolJson(
    String system,
    String user, {
    required String stage,
    required String toolName,
    required Map<String, dynamic> schema,
    CancelToken? cancelToken,
  });

  /// Agent 多轮对话：模型自由选择回文本或调用任一已注册工具（P5 AgentRunner 专用）。
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  });
}

abstract class ImageUnderstandingGateway {
  Future<TextResult> analyzeImage(
    String prompt,
    String imageAbsPath, {
    required String stage,
    CancelToken? cancelToken,
  });
}

class HttpProviderGateway
    implements ProviderGateway, ImageUnderstandingGateway {
  final Database db;
  final EngineConfig config;
  final MediaStore media;
  final CredentialStore credentials;
  final Dio dio;
  final Duration pollInterval;
  final Duration pollTimeout;

  HttpProviderGateway(this.db, this.config, this.media,
      {Dio? dio,
      CredentialStore? credentials,
      this.pollInterval = const Duration(seconds: 10),
      this.pollTimeout = const Duration(minutes: 30)})
      : dio = dio ?? Dio(),
        credentials = credentials ?? InMemoryCredentialStore();

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) async {
    final model = await resolveStage(db, credentials, stage);
    if (model.protocol == 'anthropic') {
      return anthropicGenerateText(dio, model, system, user,
          requestTimeout: config.requestTimeout, cancelToken: cancelToken);
    }
    return openaiGenerateText(dio, model, system, user,
        requestTimeout: config.requestTimeout, cancelToken: cancelToken);
  }

  @override
  Future<TextResult> analyzeImage(
    String prompt,
    String imageAbsPath, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final model = await resolveStage(db, credentials, stage);
    if (model.protocol == 'anthropic') {
      return anthropicAnalyzeImage(dio, model, prompt, imageAbsPath,
          requestTimeout: config.requestTimeout, cancelToken: cancelToken);
    }
    return openaiAnalyzeImage(dio, model, prompt, imageAbsPath,
        requestTimeout: config.requestTimeout, cancelToken: cancelToken);
  }

  @override
  Future<Map<String, dynamic>> generateToolJson(
    String system,
    String user, {
    required String stage,
    required String toolName,
    required Map<String, dynamic> schema,
    CancelToken? cancelToken,
  }) async {
    final model = await resolveStage(db, credentials, stage);
    if (model.protocol == 'anthropic') {
      return anthropicGenerateToolJson(dio, model, system, user,
          toolName: toolName,
          schema: schema,
          requestTimeout: config.requestTimeout,
          cancelToken: cancelToken);
    }
    return openaiGenerateToolJson(dio, model, system, user,
        toolName: toolName,
        schema: schema,
        requestTimeout: config.requestTimeout,
        cancelToken: cancelToken);
  }

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final model = await resolveAssistantStage(db, credentials, stage);
    if (model.protocol == 'anthropic') {
      return anthropicGenerateAgentTurn(dio, model, system, messages, tools,
          requestTimeout: config.requestTimeout, cancelToken: cancelToken);
    }
    return openaiGenerateAgentTurn(dio, model, system, messages, tools,
        requestTimeout: config.requestTimeout, cancelToken: cancelToken);
  }

  @override
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    List<String> referenceAbsPaths = const [],
    String? editInstruction,
    String? maskAbsPath,
    String? ratio,
    String? quality,
    String? modelOverride,
  }) async {
    // 逐次可覆盖阶段绑定的图模型（'providerId:modelId'）；否则按 stage 解析。
    ResolvedModel model;
    if (modelOverride != null && modelOverride.contains(':')) {
      final i = modelOverride.indexOf(':');
      model = await resolveModelById(db, credentials,
          modelOverride.substring(0, i), modelOverride.substring(i + 1));
    } else {
      model = await resolveStage(db, credentials, stage);
    }
    if (model.protocol == 'ima2') {
      return ima2GenerateImage(dio, model, media, prompt, projectId,
          ratio: ratio,
          cancelToken: cancelToken,
          referenceAbsPaths: referenceAbsPaths,
          maskAbsPath: maskAbsPath);
    }
    final directiveRows = db.select(
        'SELECT useData, data FROM o_prompt WHERE name=?',
        ['image_size_directive']);
    final directive = directiveRows.isEmpty
        ? config.str('imageSizeDirective')
        : (directiveRows.first['useData'] as String?) ??
            (directiveRows.first['data'] as String?) ??
            config.str('imageSizeDirective');
    return openaiGenerateImage(dio, model, media, prompt, projectId,
        imageSizeDirective: directive,
        cancelToken: cancelToken,
        referenceAbsPaths: referenceAbsPaths,
        editInstruction: editInstruction,
        maskAbsPath: maskAbsPath,
        size: _ratioToSize(ratio),
        quality: _qualityLabelToApi(quality));
  }

  /// 画幅 → OpenAI gpt-image 尺寸（近似映射；size 对 OAuth 供应商为建议性）。
  static String? _ratioToSize(String? ratio) {
    switch (ratio) {
      case '16:9':
        return '1536x1024';
      case '9:16':
        return '1024x1536';
      case '1:1':
        return '1024x1024';
      default:
        return null;
    }
  }

  /// 清晰度档位（1K/2K/4K）→ OpenAI quality（low/medium/high）。
  static String? _qualityLabelToApi(String? quality) {
    switch (quality) {
      case '1K':
        return 'low';
      case '2K':
        return 'medium';
      case '4K':
        return 'high';
      default:
        return null;
    }
  }

  @override
  Future<VideoSubmission> submitVideo(
    VideoGenerationRequest request, {
    required String stage,
    CancelToken? cancelToken,
  }) async {
    final model = await _resolveVideoModel(request.modelBinding, stage);
    _requireVolcengineVideo(model);
    return volcengineSubmitVideo(dio, media, model, request,
        cancelToken: cancelToken);
  }

  @override
  Future<VideoPollResult> pollVideo(
    String upstreamTaskId,
    String projectId, {
    required String stage,
    required String? modelOverride,
    CancelToken? cancelToken,
  }) async {
    final model = await _resolveVideoModel(modelOverride, stage);
    _requireVolcengineVideo(model);
    return volcenginePollVideo(dio, media, model, upstreamTaskId, projectId,
        cancelToken: cancelToken);
  }

  @override
  Future<void> cancelVideo(
    String upstreamTaskId, {
    required String stage,
    required String? modelOverride,
  }) async {
    final model = await _resolveVideoModel(modelOverride, stage);
    _requireVolcengineVideo(model);
    await volcengineCancelVideo(dio, model, upstreamTaskId);
  }

  void _requireVolcengineVideo(ResolvedModel model) {
    if (model.protocol != 'volcengine') {
      throw EngineException(errModelMissing, {
        'providerId': model.providerId,
        'reason': 'unsupportedVideoProtocol',
      });
    }
  }

  Future<ResolvedModel> _resolveVideoModel(String? modelBinding, String stage) {
    if (modelBinding != null && modelBinding.trim().isNotEmpty) {
      return resolveModelBinding(db, credentials, modelBinding, kind: 'video');
    }
    return resolveStage(db, credentials, stage);
  }

  @override
  Future<List<String>> listRemoteModelIds(String providerId) async {
    final rows = db.select(
        'SELECT id, inputValues FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
        [providerId]);
    if (rows.isEmpty) {
      throw EngineException(errProviderMissing, {'providerId': providerId});
    }
    final raw = rows.first['inputValues'] as String?;
    final inputValues = raw != null && raw.trim().isNotEmpty
        ? jsonDecode(raw) as Map
        : const {};
    var baseUrl = (inputValues['baseUrl'] ?? '').toString().trim();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final credentialRef =
        (inputValues['credentialRef'] ?? providerCredentialRef(providerId))
            .toString();
    final isLoopback = isLoopbackBaseUrl(baseUrl);
    final protocol =
        (inputValues['protocol'] ?? 'openai_compatible').toString();
    var apiKey = '';
    try {
      apiKey = await credentials.read(credentialRef) ?? '';
    } catch (_) {
      if (!isLoopback) rethrow;
    }
    if (!isLoopback && apiKey.isEmpty) {
      throw EngineException(errProviderMissing, {
        'providerId': providerId,
        'reason': '未配置 API Key',
      });
    }
    try {
      final resp = await dio.get<dynamic>(
        '$baseUrl/models',
        options: Options(
          headers: {
            if (protocol == 'anthropic') ...{
              'x-api-key': apiKey,
              'anthropic-version': anthropicApiVersion,
            } else if (apiKey.isNotEmpty)
              'Authorization': 'Bearer $apiKey',
          },
          receiveTimeout: config.requestTimeout,
        ),
      );
      final body = resp.data;
      final list = body is Map ? body['data'] : body;
      if (list is! List) {
        throw const EngineException(
            errLlmFormat, {'reason': '/models 响应缺 data 数组'});
      }
      return [
        for (final item in list.whereType<Map>())
          if ((item['id'] ?? '').toString().trim().isNotEmpty)
            (item['id'] as Object).toString(),
      ];
    } on DioException catch (e) {
      throw EngineException(errNetwork, {
        'op': 'listRemoteModels',
        'status': e.response?.statusCode,
        'message': e.message,
      });
    }
  }

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) async {
    final model = await resolveStage(db, credentials, stage);
    return openaiGenerateSpeech(
      dio,
      model,
      media,
      text,
      projectId,
      voice: voice,
      format: format,
      requestTimeout: config.requestTimeout,
      cancelToken: cancelToken,
    );
  }

  Future<int> testTextModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    if (model.protocol == 'anthropic') {
      await anthropicGenerateText(dio, model, '', '只回复OK',
          requestTimeout: config.requestTimeout, cancelToken: cancelToken);
    } else {
      await openaiGenerateText(dio, model, '', '只回复OK',
          requestTimeout: config.requestTimeout, cancelToken: cancelToken);
    }
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// 对话测试：设置页"对话测试"弹窗专用，发送完整多轮历史并返回真实文本回复
  /// （不落库、不占用阶段绑定，仅供人工核对连通性与回复质量）。
  Future<String> chatTestModel(
    ResolvedModel model,
    List<Map<String, String>> messages, {
    CancelToken? cancelToken,
  }) async {
    final result = await openaiGenerateAgentTurn(
        dio, model, '', messages, const [],
        requestTimeout: config.requestTimeout, cancelToken: cancelToken);
    return result.text ?? '';
  }

  /// 拉取供应商可用模型 ID 列表（GET {baseUrl}/models，OpenAI 兼容协议），
  /// 供"模型管理"里的"拉取模型"辅助操作使用，不影响已保存的模型配置。
  Future<List<String>> fetchModelIds(String baseUrl, String apiKey,
      {CancelToken? cancelToken}) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final res = await dio.get(
      '$base/models',
      options: Options(
        headers: apiKey.isEmpty
            ? const <String, String>{}
            : {'Authorization': 'Bearer $apiKey'},
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s < 400,
      ),
      cancelToken: cancelToken,
    );
    final data = res.data;
    final list = data is Map ? data['data'] : null;
    if (list is! List) {
      throw EngineException(errLlmFormat, {'message': '$data'});
    }
    final ids = <String>{
      for (final item in list)
        if (item is Map && item['id'] is String) item['id'] as String,
    }.toList()
      ..sort();
    return ids;
  }

  /// 图片模型连通测试：真实生成一张极简图并计时，随后清理测试产物。
  Future<int> testImageModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    final rel = model.protocol == 'ima2'
        ? await ima2GenerateImage(
            dio,
            model,
            media,
            'a small solid circle icon, minimal',
            '__conn_test__',
            ratio: null,
            cancelToken: cancelToken,
          )
        : await openaiGenerateImage(dio, model, media,
            'a small solid circle icon, minimal', '__conn_test__',
            imageSizeDirective: '', cancelToken: cancelToken);
    sw.stop();
    final f = File(media.absPath(rel));
    if (f.existsSync()) f.deleteSync();
    return sw.elapsedMilliseconds;
  }

  /// 视频模型连通测试：只提交任务、确认服务受理即可，不轮询到成片
  /// （渲染耗时且计费）。用 1×1 占位首帧提交。
  Future<int> testVideoModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    _requireVolcengineVideo(model);
    final sw = Stopwatch()..start();
    final tmp = File(media.absPath('__conn_test__/vtest_frame.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(_tinyPngBytes);
    try {
      await volcengineSubmitVideo(
        dio,
        media,
        model,
        VideoGenerationRequest(
          modelBinding: '',
          mode: VideoMode.firstFrame,
          prompt: 'connectivity test',
          references: [
            VideoReference(
              mediaType: 'image',
              role: 'first_frame',
              localPath: '__conn_test__/vtest_frame.png',
            ),
          ],
          duration: 5,
          resolution: '720p',
          ratio: '16:9',
          generateAudio: false,
          projectId: 0,
          storyboardId: 0,
          videoTrackId: 0,
        ),
        cancelToken: cancelToken,
      );
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
    sw.stop();
    return sw.elapsedMilliseconds;
  }
}
