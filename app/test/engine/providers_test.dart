import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
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
  late Database db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('prov');
    media = MediaStore(tmp.path);
    db = openEngineDb(':memory:');
    config = EngineConfig(db, isMobile: false);
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  void bindModel(String stage, String kind,
      {String providerId = 'p1',
      String modelId = 'm1',
      String protocol = 'openai_compatible',
      String apiKey = 'sk-test'}) {
    db.execute(
        'INSERT OR REPLACE INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
        [
          providerId,
          1,
          jsonEncode({
            'name': providerId,
            'protocol': protocol,
            'baseUrl': 'https://api.test/v1',
            'apiKey': apiKey,
            'createdAt': 'x',
          }),
          jsonEncode([
            {
              'id': '$providerId-$modelId-$kind',
              'providerId': providerId,
              'modelId': modelId,
              'label': modelId,
              'kind': kind,
              'capabilities': {},
              'enabled': true,
            }
          ]),
        ]);
    db.execute('INSERT OR REPLACE INTO o_setting (key,value) VALUES (?,?)',
        ['binding.$stage', '$providerId:$modelId']);
  }

  HttpProviderGateway gw(FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return HttpProviderGateway(db, config, media,
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
      bindModel('script_gen', 'text');
      final r = await g.generateText('sys', 'user', stage: 'script_gen');
      expect(r.content, 'OK啦');
      expect(r.completionTokens, 5);
    });

    test('上游 500 → DioException 且 errMessage 带响应体', () async {
      final g =
          gw(FakeAdapter((o) => jsonBody({'error': '配额没了'}, status: 500)));
      bindModel('script_gen', 'text');
      try {
        await g.generateText('s', 'u', stage: 'script_gen');
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
              {
                'b64_json': base64Encode([7, 8, 9])
              }
            ]
          }));
      bindModel('asset_image', 'image');
      final rel =
          await gw(adapter).generateImage('一只猫', 'projX', stage: 'asset_image');
      expect(rel, startsWith('projX/img_'));
      expect(File(media.absPath(rel)).readAsBytesSync(), [7, 8, 9]);
      final body = adapter.requests.single.data as Map;
      expect(body['prompt'] as String, contains('一只猫'));
      expect(body['prompt'] as String, contains('SQUARE 1:1'));
    });

    test('无图像数据抛 EngineException', () async {
      final g = gw(FakeAdapter((o) => jsonBody({'data': []})));
      bindModel('asset_image', 'image');
      expect(() => g.generateImage('x', 'p', stage: 'asset_image'),
          throwsA(isA<EngineException>()));
    });

    test('o_prompt 种子 useData=NULL 时尺寸指令回落到 data（回归：P2 生图 Null 强转崩溃）',
        () async {
      db.execute(
          'INSERT INTO o_prompt (name,type,data,useData) VALUES (?,?,?,NULL)',
          ['image_size_directive', 'system', 'PORTRAIT 9:16 指令']);
      final adapter = FakeAdapter((o) => jsonBody({
            'data': [
              {
                'b64_json': base64Encode([1, 2, 3])
              }
            ]
          }));
      bindModel('asset_image', 'image');
      final rel =
          await gw(adapter).generateImage('少年', 'projX', stage: 'asset_image');
      expect(rel, startsWith('projX/img_'));
      final body = adapter.requests.single.data as Map;
      expect(body['prompt'] as String, contains('PORTRAIT 9:16 指令'));
    });

    test('带参考图时走 edits multipart 并拼接修改意见', () async {
      final ref = File('${tmp.path}/ref.png')..writeAsBytesSync([1, 2, 3]);
      final adapter = FakeAdapter((o) => jsonBody({
            'data': [
              {
                'b64_json': base64Encode([9, 8, 7])
              }
            ]
          }));
      bindModel('asset_image', 'image');

      final rel = await gw(adapter).generateImage(
        '青衣少女',
        'projX',
        stage: 'asset_image',
        referenceAbsPaths: [ref.path],
        editInstruction: '把衣服改成红色',
      );

      expect(rel, startsWith('projX/img_'));
      final request = adapter.requests.single;
      expect(request.path, endsWith('/images/edits'));
      expect(request.data, isA<FormData>());
      final form = request.data as FormData;
      final fields = {for (final field in form.fields) field.key: field.value};
      expect(fields['model'], 'm1');
      expect(fields['response_format'], 'b64_json');
      final prompt = fields['prompt']!;
      expect(prompt, contains('青衣少女'));
      expect(prompt, contains('把衣服改成红色'));
      expect(prompt, contains('SQUARE 1:1'));
      expect(form.files.single.key, 'image');
    });

    test('带 mask 时 edits multipart 传递 mask 文件', () async {
      final ref = File('${tmp.path}/ref.png')..writeAsBytesSync([1, 2, 3]);
      final mask = File('${tmp.path}/mask.png')..writeAsBytesSync([9, 9, 9]);
      final adapter = FakeAdapter((o) => jsonBody({
            'data': [
              {
                'b64_json': base64Encode([7, 7, 7])
              }
            ]
          }));
      bindModel('asset_image', 'image');

      await gw(adapter).generateImage(
        '青衣少女',
        'projX',
        stage: 'asset_image',
        referenceAbsPaths: [ref.path],
        editInstruction: '只重绘袖口',
        maskAbsPath: mask.path,
      );

      final form = adapter.requests.single.data as FormData;
      final fileKeys = form.files.map((f) => f.key).toList();
      expect(fileKeys, contains('image'));
      expect(fileKeys, contains('mask'));
    });
  });

  group('generateVideo', () {
    late String frame;
    setUp(() {
      frame = '${tmp.path}/frame.png';
      File(frame).writeAsBytesSync([1]);
      bindModel('shot_video', 'video',
          providerId: 'volc',
          modelId: 'seedance',
          protocol: 'volcengine',
          apiKey: 'vk-test');
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
        return ResponseBody.fromBytes(Uint8List.fromList([4, 5]), 200,
            headers: {});
      });
      final rel = await gw(adapter)
          .generateVideo('动起来', frame, 'projV', stage: 'shot_video');
      expect(rel, startsWith('projV/vid_'));
      expect(File(media.absPath(rel)).readAsBytesSync(), [4, 5]);
    });

    test('failed 带上游原因', () async {
      final adapter =
          FakeAdapter((o) => o.method == 'POST' && o.path.endsWith('/tasks')
              ? jsonBody({'id': 't2'})
              : jsonBody({
                  'status': 'failed',
                  'error': {'message': '内容违规'}
                }));
      expect(
          () => gw(adapter).generateVideo('x', frame, 'p', stage: 'shot_video'),
          throwsA(predicate(
              (e) => e is EngineException && e.message.contains('内容违规'))));
    });

    test('cancelToken 取消后轮询前抛 cancel', () async {
      final token = CancelToken();
      final adapter = FakeAdapter((o) {
        if (o.method == 'POST') return jsonBody({'id': 't3'});
        return jsonBody({'status': 'running'});
      });
      final fut = gw(adapter).generateVideo('x', frame, 'p',
          stage: 'shot_video', cancelToken: token);
      token.cancel();
      expect(
          fut,
          throwsA(predicate(
              (e) => e is DioException && e.type == DioExceptionType.cancel)));
    });

    test('无 key 抛配置错误', () async {
      final freshDb = openEngineDb(':memory:');
      final freshConfig = EngineConfig(freshDb, isMobile: false);
      freshDb.execute(
          'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
          [
            'volc',
            1,
            jsonEncode({
              'name': '火山',
              'protocol': 'volcengine',
              'baseUrl': 'https://api.test/v1',
              'apiKey': '',
              'createdAt': 'x',
            }),
            jsonEncode([
              {
                'id': 'vm',
                'providerId': 'volc',
                'modelId': 'seedance',
                'label': 'seedance',
                'kind': 'video',
                'capabilities': {},
                'enabled': true,
              }
            ]),
          ]);
      freshDb.execute(
          "INSERT INTO o_setting (key,value) VALUES ('binding.shot_video','volc:seedance')");
      final g = HttpProviderGateway(freshDb, freshConfig, media,
          dio: Dio()..httpClientAdapter = FakeAdapter((o) => jsonBody({})),
          pollInterval: Duration.zero);
      expect(
          () => g.generateVideo('x', frame, 'p', stage: 'shot_video'),
          throwsA(predicate((e) =>
              e is EngineException &&
              e.errKey == errProviderMissing &&
              e.errParams['reason'] == 'apiKey')));
      freshDb.close();
    });
  });

  group('generateSpeech', () {
    test('OpenAI 兼容 /audio/speech 返回音频字节并落盘', () async {
      final adapter = FakeAdapter(
        (o) => ResponseBody.fromBytes(
          Uint8List.fromList([3, 2, 1]),
          200,
          headers: {
            Headers.contentTypeHeader: ['audio/mpeg'],
          },
        ),
      );
      bindModel('tts', 'tts', modelId: 'tts-1');

      final rel = await gw(adapter).generateSpeech(
        '你好，少侠',
        'projT',
        stage: 'tts',
        voice: 'alloy',
        format: 'mp3',
      );

      expect(rel, startsWith('projT/aud_'));
      expect(rel, endsWith('.mp3'));
      expect(File(media.absPath(rel)).readAsBytesSync(), [3, 2, 1]);
      final request = adapter.requests.single;
      expect(request.path, endsWith('/audio/speech'));
      expect(request.responseType, ResponseType.bytes);
      final body = request.data as Map;
      expect(body['model'], 'tts-1');
      expect(body['input'], '你好，少侠');
      expect(body['voice'], 'alloy');
      expect(body['response_format'], 'mp3');
    });
  });
}
