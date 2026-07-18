import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
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
  late Directory tmp;
  late MediaStore media;
  late EngineConfig config;
  late Database db;
  late InMemoryCredentialStore credentials;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('df-candidates');
    media = MediaStore(tmp.path);
    db = openEngineDb(':memory:');
    config = EngineConfig(db, isMobile: false);
    // 每个用例显式传入这个 store（而非依赖 HttpProviderGateway 的默认
    // InMemoryCredentialStore()），这样才能精确控制某个用例里到底存了什么凭据。
    credentials = InMemoryCredentialStore();
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  /// 写入一条非 loopback（`https://x.test/v1`）供应商行；仅当传入 [apiKey] 时才
  /// 往 [credentials] 里写对应凭据 —— 省略它即可精确构造"未配置 Key"场景。
  void seedProvider(String id,
      {String baseUrl = 'https://x.test/v1', String? apiKey}) {
    final credentialRef = providerCredentialRef(id);
    if (apiKey != null) {
      credentials.seed(credentialRef, apiKey);
    }
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        id,
        1,
        jsonEncode({
          'name': id,
          'protocol': 'openai_compatible',
          'baseUrl': baseUrl,
          'credentialRef': credentialRef,
        }),
        '[]',
      ],
    );
  }

  HttpProviderGateway gw(_FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return HttpProviderGateway(db, config, media,
        credentials: credentials, dio: dio);
  }

  test('解析标准 /models 响应为 ID 列表', () async {
    seedProvider('p1', apiKey: 'test-key-123');
    final gateway = gw(_FakeAdapter((options) {
      expect(options.path, 'https://x.test/v1/models');
      return ResponseBody.fromString(
        '{"object":"list","data":[{"id":"m-a"},{"id":"m-b"}]}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }));
    expect(await gateway.listRemoteModelIds('p1'), ['m-a', 'm-b']);
  });

  test('网络错误包装为 errNetwork', () async {
    seedProvider('p1', apiKey: 'test-key-123');
    final gateway = gw(_FakeAdapter((options) => throw DioException(
        requestOptions: options, type: DioExceptionType.connectionTimeout)));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(
          isA<EngineException>().having((e) => e.errKey, 'errKey', errNetwork)),
    );
  });

  test('接收超时错误同样包装为 errNetwork（回归：新增 receiveTimeout 不破坏错误映射）', () async {
    seedProvider('p1', apiKey: 'test-key-123');
    final gateway = gw(_FakeAdapter((options) => throw DioException(
        requestOptions: options, type: DioExceptionType.receiveTimeout)));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(
          isA<EngineException>().having((e) => e.errKey, 'errKey', errNetwork)),
    );
  });

  test('未知 providerId 抛 errProviderMissing', () {
    final gateway = gw(
        _FakeAdapter((options) => fail('未知 providerId 应在查库阶段短路，不应发起 HTTP 请求')));
    expect(
      () => gateway.listRemoteModelIds('nope'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errProviderMissing)),
    );
  });

  test('响应 data 非数组时抛 errLlmFormat', () async {
    seedProvider('p1', apiKey: 'test-key-123');
    final gateway = gw(_FakeAdapter((options) => ResponseBody.fromString(
          '{"object":"list","data":{"oops":"not-a-list"}}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        )));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errLlmFormat)),
    );
  });

  test('非 loopback 供应商未配置 Key 时抛 errProviderMissing，且不发起 HTTP 请求', () async {
    seedProvider('p1'); // 故意不传 apiKey：credentials 中没有这个 providerId 的任何凭据
    var httpCalled = false;
    final gateway = gw(_FakeAdapter((options) {
      httpCalled = true;
      throw StateError('不应发起 HTTP 请求：未配置 Key 时应在请求前抛 errProviderMissing');
    }));
    // 用 expectLater 完整等待整条 async 链路落定，再检查 httpCalled ——
    // 避免同步检查在 credentials.read 的微任务恢复之前就跑完，产生误判。
    await expectLater(
      gateway.listRemoteModelIds('p1'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errProviderMissing)),
    );
    expect(httpCalled, isFalse, reason: '未配置 Key 时应在请求前短路，不应调用底层 HTTP adapter');
  });

  test('已配置 Key 时请求携带 Authorization: Bearer <key>', () async {
    seedProvider('p1', apiKey: 'secret-abc-789');
    String? capturedAuth;
    final gateway = gw(_FakeAdapter((options) {
      capturedAuth = options.headers['Authorization'] as String?;
      return ResponseBody.fromString(
        '{"object":"list","data":[]}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }));
    await gateway.listRemoteModelIds('p1');
    expect(capturedAuth, 'Bearer secret-abc-789');
  });
}
