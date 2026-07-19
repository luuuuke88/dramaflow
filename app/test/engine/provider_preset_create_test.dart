import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/api/models.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/providers/resolve.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 只记录视频测试是否被分派；绝不触发真实 HTTP。
class _VideoTestRecordingGateway extends HttpProviderGateway {
  int videoTestCalls = 0;

  _VideoTestRecordingGateway(super.db, super.config, super.media);

  @override
  Future<int> testVideoModel(ResolvedModel model,
      {CancelToken? cancelToken}) async {
    videoTestCalls++;
    return 1;
  }
}

/// write 恒抛错的凭证仓——用于真实走到"凭证失败→删行"分支。
class _FailingCredentialStore implements CredentialStore {
  final read_ = <String, String>{};
  @override
  Future<String?> read(String key) async => read_[key];
  @override
  Future<void> write(String key, String value) async {
    throw StateError('secure storage unavailable');
  }

  @override
  Future<void> delete(String key) async {}
}

/// 可控的异步凭证仓：用于证明创建请求尚未结束时，供应商绝不可参与路由。
class _DeferredCredentialStore implements CredentialStore {
  final values = <String, String>{};
  final writeStarted = Completer<void>();
  final _writeCompleter = Completer<void>();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeStarted.complete();
    await _writeCompleter.future;
    values[key] = value;
  }

  void finishWrite() => _writeCompleter.complete();

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Engine _engine(Database db, {CredentialStore? credentials}) => Engine(
      db: db,
      media: MediaStore('/tmp/df-preset-create-test-media'),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );

void main() {
  test('正常路径：供应商+选中模型一次写入，name/baseUrl 覆盖生效', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    final info = await engine.createProviderFromPreset(
      presetId: 'deepseek',
      apiKey: 'sk-test',
      selectedModelIds: ['deepseek-v4-flash'],
      name: '我的 DeepSeek',
      baseUrl: 'https://proxy.example.com/v1',
    );
    expect(info.id, 'deepseek');
    expect(info.name, '我的 DeepSeek');
    expect(info.baseUrl, 'https://proxy.example.com/v1');
    expect(info.hasCredential, isTrue);
    final listed = (await engine.listProviders()).single;
    expect(listed.name, '我的 DeepSeek', reason: '覆盖值必须真实落库');
    expect(listed.baseUrl, 'https://proxy.example.com/v1');
    final models = await engine.listProviderModels('deepseek');
    expect(models.map((m) => m.modelId).toList(), ['deepseek-v4-flash']);
  });

  test('未知 presetId 抛 errProviderMissing；选空模型抛 errModelMissing 且零写入', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    expect(
      () => engine.createProviderFromPreset(presetId: 'nope', apiKey: 'k'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', 'errProviderMissing')),
    );
    await expectLater(
      engine.createProviderFromPreset(
          presetId: 'deepseek', apiKey: 'k', selectedModelIds: const []),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', 'errModelMissing')),
    );
    expect(await engine.listProviders(), isEmpty);
    expect(await engine.credentials.read(providerCredentialRef('deepseek')),
        isNull,
        reason: '校验失败不得写凭证');
  });

  test('远程预设缺少 Key 时拒绝创建且零落库，本地 loopback 例外', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);

    await expectLater(
      engine.createProviderFromPreset(presetId: 'deepseek', apiKey: ''),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', 'errProviderMissing')),
    );
    expect(await engine.listProviders(), isEmpty);

    await engine.createProviderFromPreset(
      presetId: 'deepseek',
      apiKey: '',
      baseUrl: 'http://127.0.0.1:8787/v1',
    );
    expect((await engine.listProviders()).single.hasCredential, isFalse);
  });

  test('无 Key 的 loopback 供应商不能改为启用的远程地址', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    final local = await engine.createProvider(
      name: 'Local Gateway',
      protocol: 'openai_compatible',
      baseUrl: 'http://127.0.0.1:8787/v1',
      apiKey: '',
    );

    await expectLater(
      engine.updateProvider(local.id, baseUrl: 'https://proxy.example.com/v1'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errProviderMissing)),
    );

    final unchanged = (await engine.listProviders()).single;
    expect(unchanged.baseUrl, 'http://127.0.0.1:8787/v1');
    expect(unchanged.enabled, isTrue);
  });

  test('凭证尚未写完时供应商保持禁用，成功后才启用', () async {
    final db = openEngineDb(':memory:');
    final credentials = _DeferredCredentialStore();
    final engine = _engine(db, credentials: credentials);
    addTearDown(engine.dispose);

    final creating = engine.createProviderFromPreset(
      presetId: 'deepseek',
      apiKey: 'sk-test',
    );
    await credentials.writeStarted.future;

    final pending = db.select(
        'SELECT enable,inputValues FROM o_vendorConfig WHERE id=?',
        ['deepseek']);
    expect(pending.single['enable'], 0);
    expect(
        (jsonDecode(pending.single['inputValues'] as String)
            as Map)['provisioning'],
        true);

    credentials.finishWrite();
    await creating;
    final ready = db.select(
        'SELECT enable,inputValues FROM o_vendorConfig WHERE id=?',
        ['deepseek']);
    expect(ready.single['enable'], 1);
    expect(
        (jsonDecode(ready.single['inputValues'] as String) as Map)
            .containsKey('provisioning'),
        isFalse);
  });

  test('启动恢复已写凭证的 provisioning 供应商，不暴露半成品', () async {
    final dir = Directory.systemTemp.createTempSync('df-provider-recovery-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = '${dir.path}/dramaflow.sqlite';
    final db = openEngineDb(dbPath);
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'deepseek',
        0,
        jsonEncode({
          'name': 'DeepSeek',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://api.deepseek.com/v1',
          'credentialRef': providerCredentialRef('deepseek'),
          'provisioning': true,
        }),
        '[]',
      ],
    );
    db.close();
    final credentials = InMemoryCredentialStore()
      ..seed(providerCredentialRef('deepseek'), 'sk-survived-crash');

    final engine = await Engine.boot(
      dataDir: dir.path,
      isMobile: false,
      credentialStore: credentials,
    );
    addTearDown(engine.dispose);

    final row = engine.db.select(
        'SELECT enable,inputValues FROM o_vendorConfig WHERE id=?',
        ['deepseek']);
    expect(row.single['enable'], 1);
    expect(
        (jsonDecode(row.single['inputValues'] as String) as Map)
            .containsKey('provisioning'),
        isFalse);
  });

  test('启动清理没有凭证的远程 provisioning 供应商', () async {
    final dir = Directory.systemTemp.createTempSync('df-provider-recovery-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = openEngineDb('${dir.path}/dramaflow.sqlite');
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'deepseek',
        0,
        jsonEncode({
          'name': 'DeepSeek',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://api.deepseek.com/v1',
          'credentialRef': providerCredentialRef('deepseek'),
          'provisioning': true,
        }),
        '[]',
      ],
    );
    db.close();

    final engine = await Engine.boot(
      dataDir: dir.path,
      isMobile: false,
      credentialStore: InMemoryCredentialStore(),
    );
    addTearDown(engine.dispose);
    expect(
      engine.db
          .select('SELECT id FROM o_vendorConfig WHERE id=?', ['deepseek']),
      isEmpty,
    );
  });

  test('非火山供应商不能保存 video 模型', () async {
    final db = openEngineDb(':memory:');
    final engine = _engine(db);
    addTearDown(engine.dispose);
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'custom-openai',
        1,
        jsonEncode({
          'name': 'Custom OpenAI',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://proxy.example.com/v1',
        }),
        '[]',
      ],
    );

    await expectLater(
      engine.saveProviderModels('custom-openai', [
        {'modelId': 'video-model', 'kind': 'video', 'enabled': true},
      ]),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', 'errModelMissing')),
    );
    expect(
      db.select('SELECT models FROM o_vendorConfig WHERE id=?',
          ['custom-openai']).single['models'],
      '[]',
    );
  });

  test('Anthropic 供应商只允许保存 text 模型，导入也不能绕过', () async {
    final db = openEngineDb(':memory:');
    final engine = _engine(db);
    addTearDown(engine.dispose);
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'anthropic',
        1,
        jsonEncode({
          'name': 'Claude (Anthropic)',
          'protocol': 'anthropic',
          'baseUrl': 'https://api.anthropic.com/v1',
        }),
        '[]',
      ],
    );

    await expectLater(
      engine.saveProviderModels('anthropic', [
        {'modelId': 'not-an-image-model', 'kind': 'image', 'enabled': true},
      ]),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errModelMissing)
          .having((e) => e.errParams['reason'], 'reason',
              'unsupportedAnthropicModelKind')),
    );
    expect(
      db.select('SELECT models FROM o_vendorConfig WHERE id=?',
          ['anthropic']).single['models'],
      '[]',
    );

    await expectLater(
      engine.importConfig({
        'configVersion': 3,
        'providers': [
          {
            'id': 'imported-anthropic',
            'name': 'Imported Anthropic',
            'protocol': 'anthropic',
            'baseUrl': 'https://api.anthropic.com/v1',
            'enabled': true,
            'models': [
              {
                'modelId': 'not-a-tts-model',
                'kind': 'tts',
                'enabled': true,
              },
            ],
          },
        ],
        'bindings': const {},
        'prompts': const [],
        'modelPrompts': const [],
      }),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errModelMissing)
          .having((e) => e.errParams['reason'], 'reason',
              'unsupportedAnthropicModelKind')),
    );
    expect(
      db.select('SELECT id FROM o_vendorConfig WHERE id=?',
          ['imported-anthropic']),
      isEmpty,
    );
  });

  test('导入配置不能绕过非火山 video 模型限制', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);

    await expectLater(
      engine.importConfig({
        'configVersion': 3,
        'providers': [
          {
            'id': 'imported-openai',
            'name': 'Imported OpenAI',
            'protocol': 'openai_compatible',
            'baseUrl': 'https://proxy.example.com/v1',
            'enabled': true,
            'models': [
              {
                'modelId': 'unsupported-video',
                'kind': 'video',
                'enabled': true,
              },
            ],
          },
        ],
        'bindings': const {},
        'prompts': const [],
        'modelPrompts': const [],
      }),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', errModelMissing)
          .having((e) => e.errParams['reason'], 'reason',
              'unsupportedVideoProtocol')),
    );

    expect(await engine.listProviders(), isEmpty);
  });

  test('视频模型连通测试被拒绝，且不会分派给上游网关', () async {
    final db = openEngineDb(':memory:');
    final config = EngineConfig(db, isMobile: false);
    final media = MediaStore('/tmp/df-video-test-deferred-media');
    final gateway = _VideoTestRecordingGateway(db, config, media);
    final engine = Engine(
      db: db,
      media: media,
      gateway: gateway,
      config: config,
    );
    addTearDown(engine.dispose);
    final provider = await engine.createProvider(
      name: 'Volcengine',
      protocol: 'volcengine',
      baseUrl: 'https://ark.example.test',
      apiKey: 'sk-test',
    );
    await engine.saveProviderModels(provider.id, const [
      {
        'modelId': 'doubao-seedance-2-0-mini-260615',
        'label': 'Seedance Mini',
        'kind': 'video',
        'enabled': true,
      },
    ]);

    await expectLater(
      engine.testProvider(provider.id, 'doubao-seedance-2-0-mini-260615'),
      throwsA(
        isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errTaskUnsupported)
            .having(
                (e) => e.errParams['reason'], 'reason', 'videoTestDeferred'),
      ),
    );
    expect(gateway.videoTestCalls, 0);
  });

  test('P0 场景：重复创建抛 errProviderExists 且旧凭证一字节不动', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    await engine.createProviderFromPreset(
        presetId: 'deepseek', apiKey: 'old-key');
    await expectLater(
      engine.createProviderFromPreset(presetId: 'deepseek', apiKey: 'NEW'),
      throwsA(isA<EngineException>()
          .having((e) => e.errKey, 'errKey', 'errProviderExists')),
    );
    expect(await engine.credentials.read(providerCredentialRef('deepseek')),
        'old-key');
  });

  test('INSERT 失败（BEFORE INSERT 触发器）：不写凭证、不留行', () async {
    final db = openEngineDb(':memory:');
    db.execute('''
      CREATE TRIGGER fail_vendor_insert BEFORE INSERT ON o_vendorConfig
      BEGIN SELECT RAISE(ABORT, 'boom'); END;
    ''');
    final engine = _engine(db);
    addTearDown(engine.dispose);
    await expectLater(
      engine.createProviderFromPreset(presetId: 'moonshot', apiKey: 'k1'),
      throwsA(anything),
    );
    expect(await engine.credentials.read(providerCredentialRef('moonshot')),
        isNull,
        reason: '凭证写在 INSERT 之后，INSERT 失败凭证必须从未写过');
    expect(db.select('SELECT id FROM o_vendorConfig WHERE id=?', ['moonshot']),
        isEmpty);
  });

  test('凭证写失败：刚 INSERT 的行被删除', () async {
    final db = openEngineDb(':memory:');
    final engine = _engine(db, credentials: _FailingCredentialStore());
    addTearDown(engine.dispose);
    await expectLater(
      engine.createProviderFromPreset(presetId: 'zhipu', apiKey: 'k2'),
      throwsA(isA<StateError>()),
    );
    expect(db.select('SELECT id FROM o_vendorConfig WHERE id=?', ['zhipu']),
        isEmpty,
        reason: '凭证失败必须删除刚插入的供应商行');
  });

  test('并发：两个同 preset 创建恰一成一败，胜者凭证完好', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    final results = await Future.wait([
      engine
          .createProviderFromPreset(presetId: 'xai', apiKey: 'key-A')
          .then<Object>((v) => v, onError: (Object e) => e),
      engine
          .createProviderFromPreset(presetId: 'xai', apiKey: 'key-B')
          .then<Object>((v) => v, onError: (Object e) => e),
    ]);
    final successes = results.whereType<ProviderInfo>().toList();
    final failures = results.whereType<EngineException>().toList();
    expect(successes.length, 1, reason: '恰好一个成功');
    expect(failures.single.errKey, 'errProviderExists');
    final key = await engine.credentials.read(providerCredentialRef('xai'));
    expect(key, isNotNull, reason: '败者绝不能删掉胜者的凭证');
    expect({'key-A', 'key-B'}.contains(key), isTrue);
  });
}
