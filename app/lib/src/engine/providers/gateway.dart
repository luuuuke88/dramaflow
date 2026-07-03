import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import '../config.dart';
import '../media.dart';
import 'openai_text.dart';
import 'openai_image.dart';
import 'openai_tts.dart';
import 'resolve.dart';
import 'volcengine_video.dart';

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
    String? ratio,
    String? quality,
    String? modelOverride,
  });

  /// 返回 rel 媒体路径（如 `proj1/vid_xxx.mp4`）
  Future<String> generateVideo(
      String prompt, String firstFrameAbsPath, String projectId,
      {required String stage, CancelToken? cancelToken});

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

class HttpProviderGateway implements ProviderGateway {
  final Database db;
  final EngineConfig config;
  final MediaStore media;
  final Dio dio;
  final Duration pollInterval;
  final Duration pollTimeout;

  HttpProviderGateway(this.db, this.config, this.media,
      {Dio? dio,
      this.pollInterval = const Duration(seconds: 10),
      this.pollTimeout = const Duration(minutes: 30)})
      : dio = dio ?? Dio();

  @override
  Future<TextResult> generateText(String system, String user,
      {required String stage, CancelToken? cancelToken}) {
    final model = resolveStage(db, stage);
    return openaiGenerateText(dio, model, system, user,
        cancelToken: cancelToken);
  }

  @override
  Future<Map<String, dynamic>> generateToolJson(
    String system,
    String user, {
    required String stage,
    required String toolName,
    required Map<String, dynamic> schema,
    CancelToken? cancelToken,
  }) {
    final model = resolveStage(db, stage);
    return openaiGenerateToolJson(dio, model, system, user,
        toolName: toolName, schema: schema, cancelToken: cancelToken);
  }

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) {
    final model = resolveStage(db, stage);
    return openaiGenerateAgentTurn(dio, model, system, messages, tools,
        cancelToken: cancelToken);
  }

  @override
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    List<String> referenceAbsPaths = const [],
    String? editInstruction,
    String? ratio,
    String? quality,
    String? modelOverride,
  }) {
    // 逐次可覆盖阶段绑定的图模型（'providerId:modelId'）；否则按 stage 解析。
    ResolvedModel model;
    if (modelOverride != null && modelOverride.contains(':')) {
      final i = modelOverride.indexOf(':');
      model = resolveModelById(
          db, modelOverride.substring(0, i), modelOverride.substring(i + 1));
    } else {
      model = resolveStage(db, stage);
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
  Future<String> generateVideo(
      String prompt, String firstFrameAbsPath, String projectId,
      {required String stage, CancelToken? cancelToken}) {
    final model = resolveStage(db, stage);
    return volcengineGenerateVideo(
        dio, config, media, model, prompt, firstFrameAbsPath, projectId,
        cancelToken: cancelToken,
        pollInterval: pollInterval,
        pollTimeout: pollTimeout);
  }

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) {
    final model = resolveStage(db, stage);
    return openaiGenerateSpeech(
      dio,
      model,
      media,
      text,
      projectId,
      voice: voice,
      format: format,
      cancelToken: cancelToken,
    );
  }

  Future<int> testTextModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    await openaiGenerateText(dio, model, '', '只回复OK', cancelToken: cancelToken);
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// 图片模型连通测试：真实生成一张极简图并计时，随后清理测试产物。
  Future<int> testImageModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    final rel = await openaiGenerateImage(dio, model, media,
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
    final sw = Stopwatch()..start();
    final tmp = File(media.absPath('__conn_test__/vtest_frame.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(_tinyPngBytes);
    try {
      await volcengineGenerateVideo(dio, config, media, model,
          'connectivity test', tmp.path, '__conn_test__',
          submitOnly: true, cancelToken: cancelToken);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
    sw.stop();
    return sw.elapsedMilliseconds;
  }
}
