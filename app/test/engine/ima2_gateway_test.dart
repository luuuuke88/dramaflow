import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore_for_file: depend_on_referenced_packages
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handler;
  final requests = <RequestOptions>[];

  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late Directory tempDir;
  late Database db;
  late InMemoryCredentialStore credentials;
  late MediaStore media;
  late EngineConfig config;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('df-ima2-gateway-');
    db = openEngineDb(':memory:');
    credentials = InMemoryCredentialStore();
    media = MediaStore(tempDir.path);
    config = EngineConfig(db, isMobile: false);
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  HttpProviderGateway gateway(_FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return HttpProviderGateway(db, config, media,
        credentials: credentials, dio: dio);
  }

  void bindIma2Image() {
    credentials.seed(providerCredentialRef('ima2'), 'dummy');
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'ima2',
        1,
        jsonEncode({
          'name': 'ima2 / Codex OAuth',
          'protocol': 'ima2',
          'baseUrl': 'http://127.0.0.1:10531/v1',
          'chatBaseUrl': 'http://127.0.0.1:10531/v1',
          'imageBaseUrl': 'http://127.0.0.1:3333',
          'imageQuality': 'medium',
          'imageSize': '',
          'imageTimeoutMs': '960000',
          'credentialRef': providerCredentialRef('ima2'),
          'createdAt': 'test',
        }),
        jsonEncode([
          {
            'id': 'ima2:gpt-image-2-gpt-5.5',
            'providerId': 'ima2',
            'modelId': 'gpt-image-2-gpt-5.5',
            'label': 'GPT Image 2 / GPT-5.5',
            'kind': 'image',
            'capabilities': {},
            'enabled': true,
          },
        ]),
      ],
    );
    db.execute(
      'INSERT INTO o_setting (key,value) VALUES (?,?)',
      ['binding.asset_image', 'ima2:gpt-image-2-gpt-5.5'],
    );
  }

  String writeReference(String name, List<int> bytes) {
    final file = File(media.absPath('refs/$name'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  void bindIma2TextWithStaleBaseUrl() {
    credentials.seed(providerCredentialRef('ima2'), 'dummy');
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'ima2',
        1,
        jsonEncode({
          'name': 'ima2 / Codex OAuth',
          'protocol': 'ima2',
          'baseUrl': 'https://stale.ima2.example.test/v1',
          'chatBaseUrl': 'https://chat.ima2.example.test/v1',
          'imageBaseUrl': 'https://images.ima2.example.test',
          'credentialRef': providerCredentialRef('ima2'),
          'createdAt': 'test',
        }),
        jsonEncode([
          {
            'id': 'ima2:gpt-5.5',
            'providerId': 'ima2',
            'modelId': 'gpt-5.5',
            'label': 'GPT-5.5',
            'kind': 'text',
            'capabilities': {},
            'enabled': true,
          },
        ]),
      ],
    );
    db.execute(
      'INSERT INTO o_setting (key,value) VALUES (?,?)',
      ['binding.script_gen', 'ima2:gpt-5.5'],
    );
  }

  test('ima2 图片走独立 /api/generate 并携带多参考负载', () async {
    bindIma2Image();
    final adapter = _FakeAdapter((request) {
      expect(request.uri.toString(), 'http://127.0.0.1:3333/api/generate');
      expect(request.method, 'POST');
      final body = request.data as Map<String, dynamic>;
      expect(body['provider'], 'oauth');
      expect(body['model'], 'gpt-5.5');
      expect(body['quality'], 'medium');
      expect(body['size'], '864x1536');
      expect(body['format'], 'png');
      expect(body['moderation'], 'low');
      expect(body['n'], 1);
      expect(body['mode'], 'direct');
      expect(body['webSearchEnabled'], isFalse);
      expect(body['references'], [
        'data:image/png;base64,AQID',
        'data:image/png;base64,BAUG',
      ]);
      return _jsonBody({
        'image': base64Encode([7, 8, 9])
      });
    });

    final rel = await gateway(adapter).generateImage(
      '画面提示词',
      'project-1',
      stage: 'asset_image',
      ratio: '9:16',
      referenceAbsPaths: [
        writeReference('one.png', [1, 2, 3]),
        writeReference('two.png', [4, 5, 6]),
      ],
    );

    expect(File(media.absPath(rel)).readAsBytesSync(), [7, 8, 9]);
    expect(adapter.requests, hasLength(1));
  });

  test('ima2 文本以 chatBaseUrl 为准，不受旧 baseUrl 漂移影响', () async {
    bindIma2TextWithStaleBaseUrl();
    final adapter = _FakeAdapter((request) {
      expect(request.uri.toString(),
          'https://chat.ima2.example.test/v1/chat/completions');
      return _jsonBody({
        'choices': [
          {
            'message': {'content': 'OK'},
          },
        ],
      });
    });

    final result = await gateway(adapter)
        .generateText('system', 'user', stage: 'script_gen');

    expect(result.content, 'OK');
    expect(adapter.requests, hasLength(1));
  });

  test('ima2 图片连通测试同样走独立 /api/generate 协议', () async {
    final adapter = _FakeAdapter((request) {
      expect(request.uri.toString(),
          'https://images.ima2.example.test/api/generate');
      expect(request.method, 'POST');
      expect((request.data as Map<String, dynamic>)['provider'], 'oauth');
      return _jsonBody({
        'image': base64Encode([4, 5, 6])
      });
    });
    final model = ResolvedModel(
      providerId: 'ima2',
      protocol: 'ima2',
      baseUrl: 'https://chat.ima2.example.test/v1',
      apiKey: 'dummy',
      modelId: 'gpt-image-2-gpt-5.5',
      providerInputs: const {
        'imageBaseUrl': 'https://images.ima2.example.test',
        'imageQuality': 'low',
        'imageSize': '1024x1024',
        'imageTimeoutMs': '960000',
      },
    );

    final elapsed = await gateway(adapter).testImageModel(model);

    expect(elapsed, greaterThanOrEqualTo(0));
    expect(adapter.requests, hasLength(1));
  });

  test('ima2 接受 images.url 返回并下载为本地媒体', () async {
    bindIma2Image();
    final adapter = _FakeAdapter((request) {
      if (request.method == 'POST') {
        expect(request.uri.toString(), 'http://127.0.0.1:3333/api/generate');
        return _jsonBody({
          'images': [
            {'url': 'https://cdn.ima2.example.test/image.png'},
          ],
        });
      }
      expect(request.method, 'GET');
      expect(request.uri.toString(), 'https://cdn.ima2.example.test/image.png');
      return ResponseBody.fromBytes(Uint8List.fromList([10, 11, 12]), 200,
          headers: {
            Headers.contentTypeHeader: ['image/png'],
          });
    });

    final rel = await gateway(adapter)
        .generateImage('提示词', 'project-url', stage: 'asset_image');

    expect(File(media.absPath(rel)).readAsBytesSync(), [10, 11, 12]);
    expect(adapter.requests, hasLength(2));
  });

  test('ima2 归一化非法质量、空尺寸与过短超时', () async {
    bindIma2Image();
    db.execute(
      'UPDATE o_vendorConfig SET inputValues=? WHERE id=?',
      [
        jsonEncode({
          'name': 'ima2 / Codex OAuth',
          'protocol': 'ima2',
          'baseUrl': 'http://127.0.0.1:10531/v1',
          'chatBaseUrl': 'http://127.0.0.1:10531/v1',
          'imageBaseUrl': 'http://127.0.0.1:3333',
          'imageQuality': 'fastest',
          'imageSize': '',
          'imageTimeoutMs': '5000',
          'credentialRef': providerCredentialRef('ima2'),
          'createdAt': 'test',
        }),
        'ima2',
      ],
    );
    final adapter = _FakeAdapter((request) {
      final body = request.data as Map<String, dynamic>;
      expect(body['quality'], 'low');
      expect(body['size'], '1536x864');
      expect(request.receiveTimeout, const Duration(milliseconds: 960000));
      return _jsonBody({
        'image': base64Encode([1])
      });
    });

    await gateway(adapter).generateImage('提示词', 'project-normalize',
        stage: 'asset_image', ratio: '16:9');

    expect(adapter.requests, hasLength(1));
  });

  test('ima2 接受 images.image 与顶层 url 两种返回形态', () async {
    bindIma2Image();
    var posts = 0;
    final adapter = _FakeAdapter((request) {
      if (request.method == 'POST') {
        posts++;
        return posts == 1
            ? _jsonBody({
                'images': [
                  {
                    'image': base64Encode([21, 22])
                  },
                ],
              })
            : _jsonBody({'url': 'https://cdn.ima2.example.test/top.png'});
      }
      expect(request.uri.toString(), 'https://cdn.ima2.example.test/top.png');
      return ResponseBody.fromBytes(Uint8List.fromList([23, 24]), 200,
          headers: {
            Headers.contentTypeHeader: ['image/png'],
          });
    });
    final client = gateway(adapter);

    final nested = await client.generateImage('嵌套图片', 'project-nested',
        stage: 'asset_image');
    final topUrl = await client.generateImage('顶层链接', 'project-top-url',
        stage: 'asset_image');

    expect(File(media.absPath(nested)).readAsBytesSync(), [21, 22]);
    expect(File(media.absPath(topUrl)).readAsBytesSync(), [23, 24]);
    expect(adapter.requests, hasLength(3));
  });
}
