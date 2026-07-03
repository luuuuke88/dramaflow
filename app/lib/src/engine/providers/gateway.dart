import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import '../config.dart';
import '../media.dart';
import 'openai_text.dart';
import 'openai_image.dart';
import 'resolve.dart';
import 'volcengine_video.dart';

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

  /// 返回 rel 媒体路径（如 `proj1/img_xxx.png`）
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    String? refImageAbsPath,
    String? editInstruction,
  });

  /// 返回 rel 媒体路径（如 `proj1/vid_xxx.mp4`）
  Future<String> generateVideo(
      String prompt, String firstFrameAbsPath, String projectId,
      {required String stage, CancelToken? cancelToken});

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
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    String? refImageAbsPath,
    String? editInstruction,
  }) {
    final model = resolveStage(db, stage);
    final directiveRows = db.select(
        'SELECT useData FROM o_prompt WHERE name=?', ['image_size_directive']);
    final directive = directiveRows.isEmpty
        ? config.str('imageSizeDirective')
        : directiveRows.first['useData'] as String;
    return openaiGenerateImage(dio, model, media, prompt, projectId,
        imageSizeDirective: directive,
        cancelToken: cancelToken,
        refImageAbsPath: refImageAbsPath,
        editInstruction: editInstruction);
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

  Future<int> testTextModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    await openaiGenerateText(dio, model, '', '只回复OK', cancelToken: cancelToken);
    sw.stop();
    return sw.elapsedMilliseconds;
  }
}
