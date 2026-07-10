// 视频连通测试（submitOnly）：确认只提交任务、不轮询到成片。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/engine/providers/volcengine_video.dart';
import 'package:dramaflow/src/engine/video_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅对创建任务的 POST 返回 taskId；记录所有请求路径，用于断言未发生轮询 GET。
class _FakeAdapter implements HttpClientAdapter {
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (options.method == 'POST' && options.path.contains('/tasks')) {
      return ResponseBody.fromString(
        jsonEncode({'id': 'task_conn_123'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // 任何 GET（轮询）都不应发生。
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('submitVideo 只提交任务即返回 taskId，不做任何轮询 GET', () async {
    final dir = Directory.systemTemp.createTempSync('df-vconn-');
    final db = openEngineDb(':memory:');
    final media = MediaStore('${dir.path}/media');
    final adapter = _FakeAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    File(media.absPath('__conn_test__/vtest_frame.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

    final result = await volcengineSubmitVideo(
      dio,
      media,
      const ResolvedModel(
        providerId: 'volcengine',
        protocol: 'volcengine',
        baseUrl: 'https://example.com/api/v3',
        apiKey: 'k',
        modelId: 'doubao-seedance',
      ),
      VideoGenerationRequest(
        modelBinding: 'volcengine:doubao-seedance',
        mode: VideoMode.firstFrame,
        prompt: 'connectivity test',
        references: const [
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
    );

    expect(result.upstreamTaskId, 'task_conn_123');
    expect(adapter.calls.where((c) => c.startsWith('GET')), isEmpty,
        reason: 'submitOnly 不得轮询');
    expect(adapter.calls.where((c) => c.startsWith('POST')), hasLength(1));

    db.close();
    dir.deleteSync(recursive: true);
  });
}
