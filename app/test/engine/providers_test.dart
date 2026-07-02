import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';

class FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  FakeAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object data, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

void main() {
  late Directory tmp;
  late MediaStore media;
  late EngineConfig config;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('prov');
    media = MediaStore(tmp.path);
    config = EngineConfig(openEngineDb(':memory:'), isMobile: false);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  HttpProviderGateway gw(FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return HttpProviderGateway(config, media,
        dio: dio, pollInterval: Duration.zero);
  }

  group('generateText', () {
    test('正常解析 content 与 usage', () async {
      final g = gw(FakeAdapter((o) => jsonBody({
            'choices': [
              {
                'message': {'content': 'OK啦'}
              }
            ],
            'usage': {'prompt_tokens': 3, 'completion_tokens': 5},
          })));
      final r = await g.generateText('sys', 'user');
      expect(r.content, 'OK啦');
      expect(r.completionTokens, 5);
    });

    test('上游 500 → DioException 且 errMessage 带响应体', () async {
      final g = gw(FakeAdapter(
          (o) => jsonBody({'error': '配额没了'}, status: 500)));
      try {
        await g.generateText('s', 'u');
        fail('应当抛出');
      } on DioException catch (e) {
        expect(errMessage(e), contains('HTTP 500'));
        expect(errMessage(e), contains('配额没了'));
      }
    });
  });

  group('generateImage', () {
    test('b64 落盘且 prompt 注入尺寸指令', () async {
      final adapter = FakeAdapter((o) => jsonBody({
            'data': [
              {'b64_json': base64Encode([7, 8, 9])}
            ]
          }));
      final rel = await gw(adapter).generateImage('一只猫', 'projX');
      expect(rel, startsWith('projX/img_'));
      expect(File(media.absPath(rel)).readAsBytesSync(), [7, 8, 9]);
      final body = adapter.requests.single.data as Map;
      expect(body['prompt'] as String, contains('一只猫'));
      expect(body['prompt'] as String, contains('SQUARE 1:1'));
    });

    test('无图像数据抛 EngineException', () async {
      final g = gw(FakeAdapter((o) => jsonBody({'data': []})));
      expect(() => g.generateImage('x', 'p'),
          throwsA(isA<EngineException>()));
    });
  });

  group('generateVideo', () {
    late String frame;
    setUp(() {
      frame = '${tmp.path}/frame.png';
      File(frame).writeAsBytesSync([1]);
      config.update({'videoApiKey': 'vk-test'});
    });

    test('succeeded 全流程：创建→轮询→下载落盘', () async {
      var polls = 0;
      final adapter = FakeAdapter((o) {
        if (o.path.endsWith('/tasks') && o.method == 'POST') {
          return jsonBody({'id': 'task1'});
        }
        if (o.path.contains('/tasks/task1')) {
          polls++;
          return polls < 2
              ? jsonBody({'status': 'running'})
              : jsonBody({
                  'status': 'succeeded',
                  'content': {'video_url': 'https://cdn/v.mp4'}
                });
        }
        return ResponseBody.fromBytes(
            Uint8List.fromList([4, 5]), 200, headers: {});
      });
      final rel = await gw(adapter).generateVideo('动起来', frame, 'projV');
      expect(rel, startsWith('projV/vid_'));
      expect(File(media.absPath(rel)).readAsBytesSync(), [4, 5]);
    });

    test('failed 带上游原因', () async {
      final adapter = FakeAdapter((o) =>
          o.method == 'POST' && o.path.endsWith('/tasks')
              ? jsonBody({'id': 't2'})
              : jsonBody({
                  'status': 'failed',
                  'error': {'message': '内容违规'}
                }));
      expect(
          () => gw(adapter).generateVideo('x', frame, 'p'),
          throwsA(predicate(
              (e) => e is EngineException && e.message.contains('内容违规'))));
    });

    test('cancelToken 取消后轮询前抛 cancel', () async {
      final token = CancelToken();
      final adapter = FakeAdapter((o) {
        if (o.method == 'POST') return jsonBody({'id': 't3'});
        return jsonBody({'status': 'running'});
      });
      final fut = gw(adapter).generateVideo('x', frame, 'p', cancelToken: token);
      token.cancel();
      expect(
          fut,
          throwsA(predicate(
              (e) => e is DioException && e.type == DioExceptionType.cancel)));
    });

    test('无 key 抛配置错误', () async {
      final freshConfig =
          EngineConfig(openEngineDb(':memory:'), isMobile: false);
      final g = HttpProviderGateway(freshConfig, media,
          dio: Dio()..httpClientAdapter = FakeAdapter((o) => jsonBody({})),
          pollInterval: Duration.zero);
      expect(() => g.generateVideo('x', frame, 'p'),
          throwsA(predicate((e) =>
              e is EngineException && e.message.contains('未配置视频 API Key'))));
    });
  });
}
