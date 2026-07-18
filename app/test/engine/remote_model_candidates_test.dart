import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handler;
  _FakeAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpProviderGateway gateway;
  late Dio dio;

  setUp(() {
    final db = openEngineDb(':memory:');
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'p1',
        1,
        jsonEncode({
          'name': 'p1',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://x.test/v1',
          'credentialRef': providerCredentialRef('p1'),
        }),
        '[]',
      ],
    );
    dio = Dio();
    gateway = HttpProviderGateway(db, EngineConfig(db, isMobile: false),
        MediaStore('/tmp/df-candidates-test-media'),
        dio: dio);
  });

  test('解析标准 /models 响应为 ID 列表', () async {
    dio.httpClientAdapter = _FakeAdapter((options) {
      expect(options.path, 'https://x.test/v1/models');
      return ResponseBody.fromString(
        '{"object":"list","data":[{"id":"m-a"},{"id":"m-b"}]}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
    expect(await gateway.listRemoteModelIds('p1'), ['m-a', 'm-b']);
  });

  test('网络错误包装为 errNetwork', () async {
    dio.httpClientAdapter = _FakeAdapter((options) => throw DioException(
        requestOptions: options, type: DioExceptionType.connectionTimeout));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(
          isA<EngineException>().having((e) => e.errKey, 'errKey', errNetwork)),
    );
  });

  test('未知 providerId 抛 errProviderMissing', () {
    expect(
      () => gateway.listRemoteModelIds('nope'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errProviderMissing)),
    );
  });

  test('响应 data 非数组时抛 errLlmFormat', () async {
    dio.httpClientAdapter = _FakeAdapter((options) => ResponseBody.fromString(
          '{"object":"list","data":{"oops":"not-a-list"}}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errLlmFormat)),
    );
  });
}
