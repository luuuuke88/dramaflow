import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handler;
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;
  late InMemoryCredentialStore credentials;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('df-anthropic-gateway-');
    credentials = InMemoryCredentialStore();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  HttpProviderGateway seededGateway(
    HttpClientAdapter adapter, {
    int? timeoutSeconds,
  }) {
    final db = openEngineDb(':memory:');
    addTearDown(db.close);
    const providerId = 'anthropic';
    final credentialRef = providerCredentialRef(providerId);
    credentials.seed(credentialRef, 'anthropic-secret');
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        providerId,
        1,
        jsonEncode({
          'name': 'Claude (Anthropic)',
          'protocol': 'anthropic',
          'baseUrl': 'https://api.anthropic.com/v1',
          'credentialRef': credentialRef,
        }),
        jsonEncode([
          {
            'id': '$providerId:claude-test',
            'providerId': providerId,
            'modelId': 'claude-test',
            'label': 'Claude test',
            'kind': 'text',
            'enabled': true,
          },
        ]),
      ],
    );
    db.execute(
      'INSERT INTO o_setting (key,value) VALUES (?,?)',
      ['binding.script_gen', '$providerId:claude-test'],
    );
    final config = EngineConfig(db, isMobile: false);
    if (timeoutSeconds != null) {
      config.update({'requestTimeoutSeconds': '$timeoutSeconds'});
    }
    final dio = Dio()..httpClientAdapter = adapter;
    return HttpProviderGateway(
      db,
      config,
      MediaStore(tmp.path),
      credentials: credentials,
      dio: dio,
    );
  }

  test('Anthropic 文本走 Messages API 并解析 content 数组', () async {
    final gateway = seededGateway(_FakeAdapter((options) {
      expect(options.method, 'POST');
      expect(options.path, 'https://api.anthropic.com/v1/messages');
      expect(options.receiveTimeout, const Duration(seconds: 42));
      expect(options.headers['x-api-key'], 'anthropic-secret');
      expect(options.headers['anthropic-version'], isNotEmpty);
      final body = options.data as Map;
      expect(body['model'], 'claude-test');
      expect(body['system'], 'system prompt');
      expect(body['messages'], [
        {'role': 'user', 'content': 'user prompt'},
      ]);
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'native Claude response'},
          ],
          'usage': {'input_tokens': 7, 'output_tokens': 11},
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }), timeoutSeconds: 42);

    final result = await gateway.generateText('system prompt', 'user prompt',
        stage: 'script_gen');

    expect(result.content, 'native Claude response');
    expect(result.promptTokens, 7);
    expect(result.completionTokens, 11);
  });

  test('Anthropic 结构化输出使用 input_schema 并读取 tool_use.input', () async {
    final gateway = seededGateway(_FakeAdapter((options) {
      expect(options.path, 'https://api.anthropic.com/v1/messages');
      expect(options.receiveTimeout, const Duration(seconds: 42));
      final body = options.data as Map;
      expect(body['tool_choice'], {'type': 'tool', 'name': 'extract_event'});
      expect(body['tools'], [
        {
          'name': 'extract_event',
          'description': '结构化结果提交工具',
          'input_schema': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'}
            },
          },
        },
      ]);
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {
              'type': 'tool_use',
              'name': 'extract_event',
              'input': {'title': '宗门试炼'},
            },
          ],
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }), timeoutSeconds: 42);

    final result = await gateway.generateToolJson(
      'system prompt',
      'user prompt',
      stage: 'script_gen',
      toolName: 'extract_event',
      schema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'}
        },
      },
    );

    expect(result, {'title': '宗门试炼'});
  });

  test('Anthropic 助手回退阶段仍使用 Messages 的多工具格式', () async {
    final gateway = seededGateway(_FakeAdapter((options) {
      expect(options.path, 'https://api.anthropic.com/v1/messages');
      expect(options.receiveTimeout, const Duration(seconds: 42));
      final body = options.data as Map;
      expect(body['tool_choice'], {'type': 'auto'});
      expect(body['tools'], [
        {
          'name': 'get_project_status',
          'description': '读取项目状态',
          'input_schema': {'type': 'object', 'properties': {}},
        },
      ]);
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {
              'type': 'tool_use',
              'name': 'get_project_status',
              'input': {'projectId': 12},
            },
          ],
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }), timeoutSeconds: 42);

    final result = await gateway.generateAgentTurn(
      'assistant system',
      [
        {'role': 'user', 'content': '项目进行到哪一步？'},
      ],
      const [
        AgentToolDef(
          name: 'get_project_status',
          description: '读取项目状态',
          schema: {'type': 'object', 'properties': {}},
        ),
      ],
      stage: 'scriptAgent',
    );

    expect(result.isToolCall, isTrue);
    expect(result.toolName, 'get_project_status');
    expect(result.toolArgs, {'projectId': 12});
  });

  test('Anthropic 视觉理解按原生 base64 image block 提交', () async {
    final image = File('${tmp.path}/reference.png')
      ..writeAsBytesSync([1, 2, 3]);
    final gateway = seededGateway(_FakeAdapter((options) {
      expect(options.path, 'https://api.anthropic.com/v1/messages');
      final body = options.data as Map;
      final content =
          ((body['messages'] as List).single as Map)['content'] as List;
      expect(content[0], {'type': 'text', 'text': '分析构图'});
      expect(content[1], {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': 'AQID',
        },
      });
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '水墨风格，近景人物'},
          ],
          'usage': {'input_tokens': 13, 'output_tokens': 5},
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }));

    final result =
        await gateway.analyzeImage('分析构图', image.path, stage: 'script_gen');

    expect(result.content, '水墨风格，近景人物');
    expect(result.promptTokens, 13);
    expect(result.completionTokens, 5);
  });

  test('Anthropic 模型列表使用原生鉴权头', () async {
    final gateway = seededGateway(_FakeAdapter((options) {
      expect(options.method, 'GET');
      expect(options.path, 'https://api.anthropic.com/v1/models');
      expect(options.headers['x-api-key'], 'anthropic-secret');
      expect(options.headers['anthropic-version'], isNotEmpty);
      expect(options.headers.containsKey('Authorization'), isFalse);
      return ResponseBody.fromString(
        jsonEncode({
          'data': [
            {'id': 'claude-test'},
            {'id': 'claude-next'},
          ],
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }));

    expect(await gateway.listRemoteModelIds('anthropic'),
        ['claude-test', 'claude-next']);
  });

  test('Anthropic 文本连通测试也走 Messages API', () async {
    final gateway = seededGateway(_FakeAdapter((options) {
      expect(options.path, 'https://api.anthropic.com/v1/messages');
      expect(options.receiveTimeout, const Duration(seconds: 42));
      expect(options.headers['x-api-key'], 'anthropic-secret');
      return ResponseBody.fromString(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'OK'},
          ],
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }), timeoutSeconds: 42);

    final elapsed = await gateway.testTextModel(const ResolvedModel(
      providerId: 'anthropic',
      protocol: 'anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      apiKey: 'anthropic-secret',
      modelId: 'claude-test',
    ));

    expect(elapsed, greaterThanOrEqualTo(0));
  });
}
