import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore_for_file: depend_on_referenced_packages

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/engine/util.dart';

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

class StubGateway implements ProviderGateway {
  @override
  Future<TextResult> generateText(String system, String user,
          {required String stage, CancelToken? cancelToken}) async =>
      const TextResult('{}');

  @override
  Future<String> generateImage(String prompt, String projectId,
          {required String stage, CancelToken? cancelToken}) async =>
      '$projectId/img_stub.png';

  @override
  Future<String> generateVideo(
          String prompt, String firstFrameAbsPath, String projectId,
          {required String stage, CancelToken? cancelToken}) async =>
      '$projectId/vid_stub.mp4';
}

void main() {
  late Directory tmp;
  late Database db;
  late Engine engine;

  Engine makeEngine({ProviderGateway? gateway, bool isMobile = false}) {
    db = openEngineDb(':memory:');
    tmp = Directory.systemTemp.createTempSync('engine_m2');
    return Engine(
      db: db,
      media: MediaStore(tmp.path),
      gateway: gateway ?? StubGateway(),
      config: EngineConfig(db, isMobile: isMobile),
    );
  }

  void closeEngine() {
    engine.dispose();
    tmp.deleteSync(recursive: true);
  }

  void insertProvider(
      {String id = 'p1',
      String name = '供应商',
      String protocol = 'openai_compatible',
      String baseUrl = 'https://api.test/v1',
      String apiKey = 'sk-test',
      int enabled = 1}) {
    db.execute(
        'INSERT INTO providers (id,name,protocol,baseUrl,apiKey,enabled,createdAt) VALUES (?,?,?,?,?,?,?)',
        [id, name, protocol, baseUrl, apiKey, enabled, 'x']);
  }

  void insertModel(
      {String id = 'm-row',
      String providerId = 'p1',
      String modelId = 'm1',
      String kind = 'text',
      String label = '模型',
      int enabled = 1}) {
    db.execute(
        'INSERT INTO provider_models (id,providerId,modelId,label,kind,capabilities,enabled) VALUES (?,?,?,?,?,?,?)',
        [id, providerId, modelId, label, kind, '{}', enabled]);
  }

  void bind(String stage, String providerId, String modelId) {
    db.execute('INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)',
        ['binding.$stage', '$providerId:$modelId']);
  }

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  test('boot 首启 seed 桌面供应商、绑定、提示词且二次启动不重复', () async {
    tmp = Directory.systemTemp.createTempSync('engine_boot_m2');
    final first = await Engine.boot(dataDir: tmp.path, isMobile: false);
    expect(first.db.select('SELECT COUNT(*) n FROM providers').first['n'], 2);
    expect(
        first.db
            .select("SELECT COUNT(*) n FROM providers WHERE id='azt'")
            .first['n'],
        1);
    expect(
        first.db
            .select(
                "SELECT COUNT(*) n FROM provider_models WHERE providerId='azt'")
            .first['n'],
        4);
    expect(await first.getBindings(), {
      'script_gen': 'azt:gpt-5.5',
      'asset_extract': 'azt:gpt-5.5',
      'storyboard_gen': 'azt:gpt-5.5',
      'asset_image': 'azt:gpt-image-2',
      'shot_image': 'azt:gpt-image-2',
      'shot_video': 'volcengine:doubao-seedance-2-0-mini-260615',
    });
    expect(first.db.select('SELECT COUNT(*) n FROM prompts').first['n'], 4);
    first.dispose();

    final second = await Engine.boot(dataDir: tmp.path, isMobile: false);
    expect(second.db.select('SELECT COUNT(*) n FROM providers').first['n'], 2);
    expect(
        second.db.select('SELECT COUNT(*) n FROM provider_models').first['n'],
        7);
    expect(second.db.select('SELECT COUNT(*) n FROM prompts').first['n'], 4);
    second.dispose();
  });

  group('resolveStage', () {
    setUp(() {
      engine = makeEngine();
    });
    tearDown(closeEngine);

    test('返回启用供应商与模型', () {
      insertProvider(baseUrl: 'https://api.example/v1', apiKey: 'sk-real');
      insertModel(modelId: 'gpt-x');
      bind('script_gen', 'p1', 'gpt-x');

      final resolved = resolveStage(db, 'script_gen');

      expect(resolved.providerId, 'p1');
      expect(resolved.protocol, 'openai_compatible');
      expect(resolved.baseUrl, 'https://api.example/v1');
      expect(resolved.apiKey, 'sk-real');
      expect(resolved.modelId, 'gpt-x');
    });

    test('未绑定、供应商缺失、模型缺失分别抛中文错误', () {
      expect(
          () => resolveStage(db, 'script_gen'),
          throwsA(predicate((e) =>
              e is EngineException &&
              e.message.contains('环节 script_gen 未绑定模型'))));

      bind('script_gen', 'missing', 'm1');
      expect(
          () => resolveStage(db, 'script_gen'),
          throwsA(predicate((e) =>
              e is EngineException && e.message.contains('绑定的供应商不存在或已停用'))));

      insertProvider(id: 'missing');
      expect(
          () => resolveStage(db, 'script_gen'),
          throwsA(predicate((e) =>
              e is EngineException && e.message.contains('绑定的模型不存在或已停用'))));
    });
  });

  group('providers/models/bindings/prompts', () {
    setUp(() {
      engine = makeEngine();
    });
    tearDown(closeEngine);

    test('setBinding 按环节 kind 校验拒绝错配模型', () async {
      final provider = await engine.createProvider(
          name: '本地',
          protocol: 'openai_compatible',
          baseUrl: 'http://x',
          apiKey: 'k');
      await engine.saveProviderModels(provider.id, [
        {
          'modelId': 'image-1',
          'label': '图像',
          'kind': 'image',
          'capabilities': {},
          'enabled': true,
        }
      ]);

      expect(
          () => engine.setBinding('script_gen', provider.id, 'image-1'),
          throwsA(predicate((e) =>
              e is EngineException &&
              e.message.contains('环节 script_gen 需要 text 模型'))));
    });

    test('deleteProvider 被绑定引用时拒绝删除', () async {
      final provider = await engine.createProvider(
          name: '本地',
          protocol: 'openai_compatible',
          baseUrl: 'http://x',
          apiKey: 'k');
      await engine.saveProviderModels(provider.id, [
        {'modelId': 'gpt-x', 'label': '文本', 'kind': 'text'}
      ]);
      await engine.setBinding('script_gen', provider.id, 'gpt-x');

      expect(
          () => engine.deleteProvider(provider.id),
          throwsA(predicate((e) =>
              e is EngineException && e.message == '该供应商正被环节绑定使用，请先解绑')));
    });

    test('prompt 更新与重置回内置默认', () async {
      await engine.updatePrompt('storyboard_gen_system', '自定义');
      expect(
          (await engine.listPrompts()).singleWhere(
              (p) => p['key'] == 'storyboard_gen_system')['content'],
          '自定义');

      await engine.resetPrompt('storyboard_gen_system');
      final reset = (await engine.listPrompts())
          .singleWhere((p) => p['key'] == 'storyboard_gen_system');
      expect(reset['content'], contains('你是短剧分镜师'));
    });
  });

  test('testProvider 对文本模型发真实请求并返回耗时', () async {
    tmp = Directory.systemTemp.createTempSync('engine_m2_test_provider');
    db = openEngineDb(':memory:');
    final adapter = FakeAdapter((o) => jsonBody({
          'choices': [
            {
              'message': {'content': 'OK'}
            }
          ],
        }));
    final gateway = HttpProviderGateway(
      db,
      EngineConfig(db, isMobile: false),
      MediaStore(tmp.path),
      dio: Dio()..httpClientAdapter = adapter,
    );
    engine = Engine(
      db: db,
      media: MediaStore(tmp.path),
      gateway: gateway,
      config: EngineConfig(db, isMobile: false),
    );
    final provider = await engine.createProvider(
        name: '测试供应商',
        protocol: 'openai_compatible',
        baseUrl: 'https://api.test/v1',
        apiKey: 'sk-test');
    await engine.saveProviderModels(provider.id, [
      {'modelId': 'gpt-test', 'label': '测试', 'kind': 'text'}
    ]);

    final elapsedMs = await engine.testProvider(provider.id, 'gpt-test');

    expect(elapsedMs, greaterThanOrEqualTo(0));
    expect(
        adapter.requests.single.path, 'https://api.test/v1/chat/completions');
    expect((adapter.requests.single.data as Map)['model'], 'gpt-test');
    final messages = (adapter.requests.single.data as Map)['messages'] as List;
    expect((messages.last as Map)['content'], '只回复OK');
    closeEngine();
  });

  test('export 清库 import 后配置往返一致', () async {
    engine = makeEngine();
    final provider = await engine.createProvider(
        name: '可导入供应商',
        protocol: 'openai_compatible',
        baseUrl: 'https://api.test/v1',
        apiKey: 'sk-secret');
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'gpt-test',
        'label': '测试文本',
        'kind': 'text',
        'capabilities': {'ctx': 128000},
        'enabled': true,
      }
    ]);
    await engine.setBinding('script_gen', provider.id, 'gpt-test');
    await engine.updatePrompt('script_gen_system', '导出的提示词');
    final exported = await engine.exportConfig();

    db.execute("DELETE FROM settings WHERE key LIKE 'binding.%'");
    db.execute('DELETE FROM providers');
    db.execute('DELETE FROM prompts');

    await engine.importConfig(exported);
    final imported = await engine.exportConfig();

    expect(imported, exported);
    closeEngine();
  });
}
