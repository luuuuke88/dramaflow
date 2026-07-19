import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/engine/video_request.dart';

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
  late InMemoryCredentialStore credentials;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('prov');
    media = MediaStore(tmp.path);
    db = openEngineDb(':memory:');
    config = EngineConfig(db, isMobile: false);
    credentials = InMemoryCredentialStore();
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  void bindModel(String stage, String kind,
      {String providerId = 'p1',
      String modelId = 'm1',
      String protocol = 'openai_compatible',
      String apiKey = 'sk-test',
      String baseUrl = 'https://api.test/v1'}) {
    final credentialRef = providerCredentialRef(providerId);
    credentials.seed(credentialRef, apiKey);
    db.execute(
        'INSERT OR REPLACE INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
        [
          providerId,
          1,
          jsonEncode({
            'name': providerId,
            'protocol': protocol,
            'baseUrl': baseUrl,
            'credentialRef': credentialRef,
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
        credentials: credentials, dio: dio, pollInterval: Duration.zero);
  }

  String writeMedia(String rel, List<int> bytes) {
    File(media.absPath(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return rel;
  }

  VideoGenerationRequest videoRequest({
    required VideoMode mode,
    required List<VideoReference> references,
    String modelBinding = 'volc:seedance',
  }) =>
      VideoGenerationRequest(
        modelBinding: modelBinding,
        mode: mode,
        prompt: 'PROMPT',
        references: references,
        duration: 5,
        resolution: '720p',
        ratio: '9:16',
        generateAudio: false,
        projectId: 7,
        storyboardId: 8,
        videoTrackId: 9,
      );

  void expectVideoParameters(Map body) {
    expect(body['model'], 'seedance');
    expect(body['ratio'], '9:16');
    expect(body['duration'], 5);
    expect(body['resolution'], '720p');
    expect(body['watermark'], isFalse);
    expect(body['generate_audio'], isFalse);
  }

  group('generateText', () {
    for (final baseUrl in <String>[
      'http://127.0.0.1:8787/v1',
      'http://localhost:8787/v1',
      'http://[::1]:8787/v1',
    ]) {
      test('回环地址 $baseUrl 允许空 API Key', () async {
        final adapter = FakeAdapter((o) => jsonBody({
              'choices': [
                {
                  'message': {'content': 'LOCAL'}
                }
              ],
            }));
        bindModel('script_gen', 'text', apiKey: '', baseUrl: baseUrl);

        final result =
            await gw(adapter).generateText('sys', 'user', stage: 'script_gen');

        expect(result.content, 'LOCAL');
        expect(
            adapter.requests.single.headers, isNot(contains('Authorization')));
      });
    }

    test('回环地址保留显式配置的 API Key', () async {
      final adapter = FakeAdapter((o) => jsonBody({
            'choices': [
              {
                'message': {'content': 'AUTHED'}
              }
            ],
          }));
      bindModel(
        'script_gen',
        'text',
        apiKey: 'local-secret',
        baseUrl: 'http://127.0.0.1:8787/v1',
      );

      await gw(adapter).generateText('sys', 'user', stage: 'script_gen');

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer local-secret',
      );
    });

    for (final baseUrl in <String>[
      'https://api.test/v1',
      'http://localhost.evil.example/v1',
      'http://localhost@evil.example/v1',
    ]) {
      test('远程地址 $baseUrl 拒绝空 API Key', () async {
        final adapter = FakeAdapter((o) => jsonBody({}));
        bindModel('script_gen', 'text', apiKey: '', baseUrl: baseUrl);

        expect(
          () => gw(adapter).generateText('sys', 'user', stage: 'script_gen'),
          throwsA(isA<EngineException>()),
        );
        expect(adapter.requests, isEmpty);
      });
    }

    test('正常解析 content 与 usage', () async {
      final adapter = FakeAdapter((o) => jsonBody({
            'choices': [
              {
                'message': {'content': 'OK啦'}
              }
            ],
            'usage': {'prompt_tokens': 3, 'completion_tokens': 5},
          }));
      final g = gw(adapter);
      bindModel('script_gen', 'text');
      config.update({'requestTimeoutSeconds': '42'});
      final r = await g.generateText('sys', 'user', stage: 'script_gen');
      expect(r.content, 'OK啦');
      expect(r.completionTokens, 5);
      expect(
          adapter.requests.single.receiveTimeout, const Duration(seconds: 42));
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

  group('generateAgentTurn', () {
    test('无工具时不发送空 tools/tool_choice', () async {
      final adapter = FakeAdapter((o) => jsonBody({
            'choices': [
              {
                'message': {'content': 'APPROVE'}
              }
            ],
          }));
      bindModel('script_gen', 'text');
      config.update({'requestTimeoutSeconds': '42'});

      final r = await gw(adapter).generateAgentTurn(
        'sys',
        const [
          {'role': 'user', 'content': 'review'}
        ],
        const [],
        stage: 'scriptAgent',
      );

      expect(r.text, 'APPROVE');
      expect(
          adapter.requests.single.receiveTimeout, const Duration(seconds: 42));
      final body = adapter.requests.single.data as Map;
      expect(body, isNot(contains('tools')));
      expect(body, isNot(contains('tool_choice')));
    });
  });

  group('generateToolJson', () {
    test('使用用户配置的通用请求超时', () async {
      final adapter = FakeAdapter((_) => jsonBody({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'arguments': '{"title":"宗门试炼"}',
                      },
                    },
                  ],
                },
              },
            ],
          }));
      bindModel('script_gen', 'text');
      config.update({'requestTimeoutSeconds': '42'});

      expect(
        await gw(adapter).generateToolJson(
          'sys',
          'user',
          stage: 'script_gen',
          toolName: 'extract_event',
          schema: const {'type': 'object'},
        ),
        {'title': '宗门试炼'},
      );
      expect(
          adapter.requests.single.receiveTimeout, const Duration(seconds: 42));
    });
  });

  group('analyzeImage', () {
    test('OpenAI 兼容 chat completions 发送本地图像 data URL', () async {
      final image = File('${tmp.path}/style.png')
        ..writeAsBytesSync([137, 80, 78, 71]);
      final adapter = FakeAdapter((o) => jsonBody({
            'choices': [
              {
                'message': {'content': '冷白水墨、低饱和、角色边缘清晰'}
              }
            ],
            'usage': {'prompt_tokens': 11, 'completion_tokens': 7},
          }));
      bindModel('script_gen', 'text', modelId: 'gpt-vision');
      config.update({'requestTimeoutSeconds': '42'});

      final r = await (gw(adapter) as dynamic).analyzeImage(
        '提炼这张参考图的短剧画风关键词',
        image.path,
        stage: 'script_gen',
      ) as TextResult;

      expect(r.content, '冷白水墨、低饱和、角色边缘清晰');
      expect(r.promptTokens, 11);
      final request = adapter.requests.single;
      expect(request.receiveTimeout, const Duration(seconds: 42));
      expect(request.path, endsWith('/chat/completions'));
      final body = request.data as Map;
      expect(body['model'], 'gpt-vision');
      final messages = body['messages'] as List;
      final userContent = (messages[1] as Map)['content'] as List;
      expect(userContent[0], {
        'type': 'text',
        'text': '提炼这张参考图的短剧画风关键词',
      });
      final imageUrl = userContent[1] as Map;
      expect(imageUrl['type'], 'image_url');
      expect(
        ((imageUrl['image_url'] as Map)['url'] as String),
        startsWith('data:image/png;base64,'),
      );
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
      expect(
          adapter.requests.single.receiveTimeout, const Duration(seconds: 960));
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

  group('typed video gateway', () {
    setUp(() {
      bindModel('shot_video', 'video',
          providerId: 'volc',
          modelId: 'seedance',
          protocol: 'volcengine',
          apiKey: 'vk-test');
    });

    test('submitVideo serializes text mode with only the text item', () async {
      final adapter = FakeAdapter((_) => jsonBody({'id': 'task-text'}));
      final result = await gw(adapter).submitVideo(
        videoRequest(mode: VideoMode.text, references: const []),
        stage: 'shot_video',
      );

      expect(result.upstreamTaskId, 'task-text');
      expect(
          adapter.requests.single.receiveTimeout, const Duration(seconds: 60));
      final body = adapter.requests.single.data as Map;
      expectVideoParameters(body);
      expect(body['content'], [
        {'type': 'text', 'text': 'PROMPT'},
      ]);
    });

    test('submitVideo strips an optional Bearer prefix from the stored key',
        () async {
      bindModel('shot_video', 'video',
          providerId: 'volc',
          modelId: 'seedance',
          protocol: 'volcengine',
          apiKey: 'Bearer vk-test');
      final adapter = FakeAdapter((_) => jsonBody({'id': 'task-auth'}));

      await gw(adapter).submitVideo(
        videoRequest(mode: VideoMode.text, references: const []),
        stage: 'shot_video',
      );

      expect(
          adapter.requests.single.headers['Authorization'], 'Bearer vk-test');
    });

    test('submitVideo serializes first-frame role and concrete image MIME',
        () async {
      final adapter = FakeAdapter((_) => jsonBody({'id': 'task-first'}));
      final first = writeMedia('7/first.png', [1, 2, 3]);

      await gw(adapter).submitVideo(
        videoRequest(
          mode: VideoMode.firstFrame,
          references: [
            VideoReference(
              mediaType: 'image',
              role: 'first_frame',
              localPath: first,
            ),
          ],
        ),
        stage: 'shot_video',
      );

      final body = adapter.requests.single.data as Map;
      expectVideoParameters(body);
      expect(body['content'], [
        {'type': 'text', 'text': 'PROMPT'},
        {'type': 'image_url', 'image_url': isA<Map>(), 'role': 'first_frame'},
      ]);
      final imageUrl = (body['content'] as List)[1]['image_url'] as Map;
      expect(imageUrl['url'], startsWith('data:image/png;base64,'));
    });

    test('submitVideo serializes first-last frames in role order', () async {
      final adapter = FakeAdapter((_) => jsonBody({'id': 'task-first-last'}));
      final first = writeMedia('7/first.png', [1]);
      final last = writeMedia('7/last.jpg', [2]);

      await gw(adapter).submitVideo(
        videoRequest(
          mode: VideoMode.firstLastFrame,
          references: [
            VideoReference(
              mediaType: 'image',
              role: 'first_frame',
              localPath: first,
            ),
            VideoReference(
              mediaType: 'image',
              role: 'last_frame',
              localPath: last,
            ),
          ],
        ),
        stage: 'shot_video',
      );

      final body = adapter.requests.single.data as Map;
      expectVideoParameters(body);
      expect((body['content'] as List).skip(1).map((item) => item['role']),
          ['first_frame', 'last_frame']);
    });

    test('submitVideo serializes multi-reference media roles', () async {
      final adapter = FakeAdapter((_) => jsonBody({'id': 'task-multi'}));
      final image = writeMedia('7/reference.webp', [1]);
      final video = writeMedia('7/reference.mp4', [2]);
      final audio = writeMedia('7/reference.mp3', [3]);

      await gw(adapter).submitVideo(
        videoRequest(
          mode: VideoMode.multiReference,
          references: [
            VideoReference(
              mediaType: 'image',
              role: 'reference_image',
              localPath: image,
            ),
            VideoReference(
              mediaType: 'video',
              role: 'reference_video',
              localPath: video,
            ),
            VideoReference(
              mediaType: 'audio',
              role: 'reference_audio',
              localPath: audio,
            ),
          ],
        ),
        stage: 'shot_video',
      );

      final body = adapter.requests.single.data as Map;
      expectVideoParameters(body);
      final references = (body['content'] as List).skip(1).toList();
      expect(references.map((item) => item['role']),
          ['reference_image', 'reference_video', 'reference_audio']);
      expect(references[0]['type'], 'image_url');
      expect((references[0]['image_url'] as Map)['url'],
          startsWith('data:image/webp;base64,'));
      expect(references[1]['type'], 'video_url');
      expect((references[1]['video_url'] as Map)['url'],
          startsWith('data:video/mp4;base64,'));
      expect(references[2]['type'], 'audio_url');
      expect((references[2]['audio_url'] as Map)['url'],
          startsWith('data:audio/mpeg;base64,'));
    });

    test('submitVideo resolves request binding as an enabled video model',
        () async {
      bindModel('shot_video', 'text',
          providerId: 'wrong', modelId: 'not-video', apiKey: 'sk-wrong');
      final adapter = FakeAdapter((_) => jsonBody({'id': 'never'}));

      expect(
        () => gw(adapter).submitVideo(
          videoRequest(
            modelBinding: 'wrong:not-video',
            mode: VideoMode.text,
            references: const [],
          ),
          stage: 'shot_video',
        ),
        throwsA(isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errModelMissing)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('submitVideo rejects a non-Volcengine video model before HTTP',
        () async {
      bindModel(
        'shot_video',
        'video',
        providerId: 'openai',
        modelId: 'sora-like-model',
        protocol: 'openai_compatible',
      );
      final adapter = FakeAdapter((_) => fail('不支持的视频协议不得发起 HTTP'));

      await expectLater(
        gw(adapter).submitVideo(
          videoRequest(
            modelBinding: 'openai:sora-like-model',
            mode: VideoMode.text,
            references: const [],
          ),
          stage: 'shot_video',
        ),
        throwsA(isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errModelMissing)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('testVideoModel rejects a non-Volcengine model before HTTP', () async {
      final adapter = FakeAdapter((_) => fail('连通测试不得发起错误协议 HTTP'));

      await expectLater(
        gw(adapter).testVideoModel(const ResolvedModel(
          providerId: 'openai',
          protocol: 'openai_compatible',
          baseUrl: 'https://api.example.test/v1',
          apiKey: 'test-key',
          modelId: 'sora-like-model',
        )),
        throwsA(isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errModelMissing)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('pollVideo makes one GET for queued and running states', () async {
      for (final state in const ['queued', 'running']) {
        final adapter = FakeAdapter((_) => jsonBody({'status': state}));
        final result = await gw(adapter).pollVideo('task-$state', '7',
            stage: 'shot_video', modelOverride: 'volc:seedance');
        expect(result.upstreamState, state);
        expect(result.isTerminal, isFalse);
        expect(result.localVideoPath, isNull);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.method, 'GET');
      }
    });

    test('pollVideo downloads a succeeded result once and saves it locally',
        () async {
      final adapter = FakeAdapter((o) {
        if (o.path.endsWith('/tasks/task-success')) {
          return jsonBody({
            'status': 'succeeded',
            'content': {'video_url': 'https://cdn.test/result.mp4'},
          });
        }
        return ResponseBody.fromBytes(Uint8List.fromList([4, 5]), 200,
            headers: {});
      });

      final result = await gw(adapter).pollVideo('task-success', '7',
          stage: 'shot_video', modelOverride: 'volc:seedance');
      expect(result.upstreamState, 'succeeded');
      expect(result.isTerminal, isTrue);
      expect(result.localVideoPath, startsWith('7/vid_'));
      expect(File(media.absPath(result.localVideoPath!)).readAsBytesSync(),
          [4, 5]);
      expect(adapter.requests.where((o) => o.method == 'GET'), hasLength(2));
    });

    test('pollVideo returns terminal upstream failures without downloading',
        () async {
      for (final entry in <String, String>{
        'failed': '内容违规',
        'cancelled': '已取消',
        'expired': '已过期',
      }.entries) {
        final adapter = FakeAdapter((_) => jsonBody({
              'status': entry.key,
              'error': {'message': entry.value},
            }));
        final result = await gw(adapter).pollVideo('task-${entry.key}', '7',
            stage: 'shot_video', modelOverride: 'volc:seedance');
        expect(result.upstreamState, entry.key);
        expect(result.isTerminal, isTrue);
        expect(result.errorMessage, entry.value);
        expect(adapter.requests, hasLength(1));
      }
    });

    test('cancelVideo DELETEs task path and ignores unsupported cancellation',
        () async {
      final adapter =
          FakeAdapter((_) => jsonBody({'error': 'unsupported'}, status: 404));

      await gw(adapter).cancelVideo('task-cancel',
          stage: 'shot_video', modelOverride: 'volc:seedance');

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.requests.single.path,
          endsWith('/contents/generations/tasks/task-cancel'));
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
      config.update({'requestTimeoutSeconds': '42'});

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
      expect(request.receiveTimeout, const Duration(seconds: 42));
    });
  });

  group('listRemoteModelIds', () {
    test('使用用户配置的通用请求超时', () async {
      final adapter = FakeAdapter((_) => jsonBody({
            'data': [
              {'id': 'm1'},
            ],
          }));
      bindModel('script_gen', 'text');
      config.update({'requestTimeoutSeconds': '42'});

      expect(await gw(adapter).listRemoteModelIds('p1'), ['m1']);
      expect(
          adapter.requests.single.receiveTimeout, const Duration(seconds: 42));
    });
  });
}
