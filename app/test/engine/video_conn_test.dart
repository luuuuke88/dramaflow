// 视频连通测试（submitOnly）：确认只提交任务、不轮询到成片。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/engine/providers/volcengine_video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

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
  test('submitOnly 只提交任务即返回 taskId，不做任何轮询 GET', () async {
    final dir = Directory.systemTemp.createTempSync('df-vconn-');
    final db = openEngineDb(':memory:');
    final config = EngineConfig(db, isMobile: false);
    final media = MediaStore(p.join(dir.path, 'media'));
    final adapter = _FakeAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    final frame = File(p.join(dir.path, 'frame.png'))
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

    final result = await volcengineGenerateVideo(
      dio,
      config,
      media,
      const ResolvedModel(
        providerId: 'volcengine',
        protocol: 'volcengine',
        baseUrl: 'https://example.com/api/v3',
        apiKey: 'k',
        modelId: 'doubao-seedance',
      ),
      'connectivity test',
      frame.path,
      '__conn_test__',
      submitOnly: true,
    );

    expect(result, 'task_conn_123');
    expect(adapter.calls.where((c) => c.startsWith('GET')), isEmpty,
        reason: 'submitOnly 不得轮询');
    expect(adapter.calls.where((c) => c.startsWith('POST')), hasLength(1));

    db.close();
    dir.deleteSync(recursive: true);
  });
}
