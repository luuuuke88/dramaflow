import 'package:dramaflow/src/api/models.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
