import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-model-prompts-');
    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() {
    engine.dispose();
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('openEngineDb 新库包含模板表，Engine 构造迁移安全旧映射且保留 text 直连', () async {
    expect(_tables(db), contains('o_modelPromptTemplate'));
    engine.dispose();
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      ['p', 'image-1', 'portrait.md', 'image/portrait.md', 'IMAGE BODY'],
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      ['p', 'video-1', 'shot.md', 'video/shot.md', 'VIDEO BODY'],
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      ['p', 'text-1', 'director.md', 'text/director.md', 'TEXT BODY'],
    );
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'constructor-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );

    final templates = await engine.listModelPromptTemplates();

    expect(
      templates.map((template) => (
            template.path,
            template.kind,
            template.prompt,
          )),
      containsAll([
        ('image/portrait.md', 'image', 'IMAGE BODY'),
        ('video/shot.md', 'video', 'VIDEO BODY'),
      ]),
    );
    expect(
      templates.map((template) => template.path),
      isNot(contains('text/director.md')),
    );
    expect(
      db.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['text/director.md'],
      ).single['prompt'],
      'TEXT BODY',
    );
  });

  test('Engine.boot 从持久化旧库幂等迁移 image/video，text 映射保持直接存储', () async {
    engine.dispose();
    db.close();

    final dataDir = p.join(dir.path, 'persistent');
    Directory(dataDir).createSync(recursive: true);
    final dbPath = p.join(dataDir, 'dramaflow.sqlite');
    final legacy = sqlite3.open(dbPath);
    initSchema(legacy);
    legacy.execute('DROP TABLE o_modelPromptTemplate');
    legacy.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      ['legacy', 'image-1', 'portrait.md', 'image/portrait.md', 'OLD IMAGE'],
    );
    legacy.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      ['legacy', 'text-1', 'director.md', 'text/director.md', 'OLD TEXT'],
    );
    legacy.execute('PRAGMA user_version = 11');
    legacy.close();

    final booted = await Engine.boot(
      dataDir: dataDir,
      isMobile: false,
      credentialStore: InMemoryCredentialStore(),
    );
    final templates = await booted.listModelPromptTemplates();
    expect(templates, hasLength(1));
    expect(templates.single.path, 'image/portrait.md');
    expect(templates.single.prompt, 'OLD IMAGE');
    expect(
      booted.db.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['text/director.md'],
      ).single['prompt'],
      'OLD TEXT',
    );
    booted.dispose();

    final reopened = await Engine.boot(
      dataDir: dataDir,
      isMobile: false,
      credentialStore: InMemoryCredentialStore(),
    );
    expect(await reopened.listModelPromptTemplates(), hasLength(1));
    expect(
      reopened.db
          .select(
            'SELECT COUNT(*) n FROM o_modelPromptTemplate',
          )
          .single['n'],
      1,
    );
    reopened.dispose();

    db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'replacement-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  test('模板创建更新同步所有绑定，旧 list/update API 继续工作', () async {
    await _installModels(engine);
    final template = await engine.createModelPromptTemplate(
      kind: 'video',
      name: 'Seedance 多参',
      prompt: 'V1',
    );

    expect(template.path, 'video/Seedance 多参.md');
    expect(template.kind, 'video');
    expect(template.name, 'Seedance 多参');
    expect(template.createTime, greaterThan(0));
    expect(template.updateTime, template.createTime);

    await engine.bindModelPromptTemplate(
        'provider-a', 'video-1', template.path);
    await engine.bindModelPromptTemplate(
        'provider-b', 'video-2', template.path);
    await engine.updateModelPromptTemplate(template.path, 'V2');

    expect(
      db.select(
        'SELECT DISTINCT prompt FROM o_modelPrompt WHERE path=?',
        [template.path],
      ).map((row) => row['prompt']),
      ['V2'],
    );
    final bindings = await engine.listModelPromptBindings();
    expect(
      bindings.map((binding) => '${binding.providerId}:${binding.modelId}'),
      ['provider-a:video-1', 'provider-b:video-2'],
    );
    expect(bindings.every((binding) => binding.prompt == 'V2'), isTrue);

    final legacyRows = await engine.listModelPrompts();
    final firstId = legacyRows.first['id'] as int;
    await engine.updateModelPrompt(firstId, 'V3');
    expect(
      (await engine.listModelPromptTemplates()).single.prompt,
      'V3',
    );
    expect(
      db.select(
        'SELECT DISTINCT prompt FROM o_modelPrompt WHERE path=?',
        [template.path],
      ).single['prompt'],
      'V3',
    );
  });

  test('删除模板原子解绑全部模型并返回稳定模型标识，text 映射不受影响', () async {
    await _installModels(engine);
    final template = await engine.createModelPromptTemplate(
      kind: 'image',
      name: '角色立绘',
      prompt: 'PORTRAIT',
    );
    await engine.bindModelPromptTemplate(
        'provider-a', 'image-1', template.path);
    await engine.bindModelPromptTemplate(
        'provider-b', 'image-2', template.path);
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'provider-a',
        'text-1',
        'director.md',
        'text/director.md',
        'DIRECTOR',
      ],
    );

    final unbound = await engine.deleteModelPromptTemplate(template.path);

    expect(unbound, ['provider-a:image-1', 'provider-b:image-2']);
    expect(await engine.listModelPromptTemplates(), isEmpty);
    expect(await engine.listModelPromptBindings(), isEmpty);
    expect(
      db.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['text/director.md'],
      ).single['prompt'],
      'DIRECTOR',
    );
  });

  test('绑定校验路径、模板类型和模型存在性，失败不会破坏原绑定', () async {
    await _installModels(engine);
    final image = await engine.createModelPromptTemplate(
      kind: 'image',
      name: '安全图像',
      prompt: 'IMAGE',
    );
    final video = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '安全视频',
      prompt: 'VIDEO',
    );
    await engine.bindModelPromptTemplate('provider-a', 'video-1', video.path);

    for (final name in [' ', '../escape', r'bad\name', 'bad/name']) {
      await expectLater(
        engine.createModelPromptTemplate(
          kind: 'image',
          name: name,
          prompt: 'X',
        ),
        throwsA(isA<EngineException>()),
      );
    }
    await expectLater(
      engine.createModelPromptTemplate(
        kind: 'text',
        name: 'legacy',
        prompt: 'X',
      ),
      throwsA(isA<EngineException>()),
    );
    await expectLater(
      engine.bindModelPromptTemplate(
        'provider-a',
        'video-1',
        '../escape.md',
      ),
      throwsA(isA<EngineException>()),
    );
    await expectLater(
      engine.bindModelPromptTemplate('provider-a', 'video-1', image.path),
      throwsA(
        isA<EngineException>().having(
          (error) => error.errKey,
          'errKey',
          errModelMissing,
        ),
      ),
    );
    await expectLater(
      engine.bindModelPromptTemplate('provider-a', 'missing', video.path),
      throwsA(
        isA<EngineException>().having(
          (error) => error.errKey,
          'errKey',
          errModelMissing,
        ),
      ),
    );

    final remaining = await engine.listModelPromptBindings();
    expect(remaining, hasLength(1));
    expect(remaining.single.path, video.path);
  });

  test('禁用供应商下的模型不能换绑模板，旧绑定保持不变', () async {
    await _installModels(engine);
    final existing = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '旧绑定',
      prompt: 'KEEP',
    );
    final replacement = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '新绑定',
      prompt: 'REPLACE',
    );
    await engine.bindModelPromptTemplate(
      'provider-a',
      'video-1',
      existing.path,
    );
    db.execute(
      'UPDATE o_vendorConfig SET enable=0 WHERE id=?',
      ['provider-a'],
    );

    await expectLater(
      engine.bindModelPromptTemplate(
        'provider-a',
        'video-1',
        replacement.path,
      ),
      throwsA(
        isA<EngineException>()
            .having((error) => error.errKey, 'errKey', errProviderMissing)
            .having(
              (error) => error.errParams['reason'],
              'reason',
              'disabled',
            ),
      ),
    );

    final remaining = await engine.listModelPromptBindings();
    expect(remaining, hasLength(1));
    expect(remaining.single.path, existing.path);
    expect(remaining.single.prompt, 'KEEP');
  });

  test('解绑仅删除 image/video 库映射，不删除 text 直连映射', () async {
    await _installModels(engine);
    final template = await engine.createModelPromptTemplate(
      kind: 'image',
      name: '解绑测试',
      prompt: 'IMAGE',
    );
    await engine.bindModelPromptTemplate(
        'provider-a', 'image-1', template.path);
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'provider-a',
        'image-1',
        'legacy.md',
        'text/legacy.md',
        'LEGACY',
      ],
    );

    await engine.unbindModelPromptTemplate('provider-a', 'image-1');

    expect(await engine.listModelPromptBindings(), isEmpty);
    expect(
      db.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['text/legacy.md'],
      ).single['prompt'],
      'LEGACY',
    );
  });

  test('导出导入包含模板并先恢复模板再绑定，同时保留 text 直连映射', () async {
    await _installModels(engine);
    final template = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '可移植模板',
      prompt: 'PORTABLE',
    );
    await engine.bindModelPromptTemplate(
        'provider-a', 'video-1', template.path);
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'provider-a',
        'text-1',
        'director.md',
        'text/director.md',
        'TEXT PORTABLE',
      ],
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'retired-provider',
        'retired-text',
        'retired.md',
        'text/retired.md',
        'RETIRED TEXT',
      ],
    );

    final exported = await engine.exportConfig();
    expect(exported['modelPromptTemplates'], hasLength(1));
    expect(
      (exported['modelPromptTemplates'] as List).single,
      containsPair('path', template.path),
    );

    final targetDb = openEngineDb(':memory:');
    final target = Engine(
      db: targetDb,
      media: MediaStore(p.join(dir.path, 'target-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(targetDb, isMobile: false),
    );
    addTearDown(() {
      target.dispose();
      targetDb.close();
    });

    await target.importConfig(exported);

    expect((await target.listModelPromptTemplates()).single.prompt, 'PORTABLE');
    expect((await target.listModelPromptBindings()).single.path, template.path);
    expect(
      targetDb.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['text/director.md'],
      ).single['prompt'],
      'TEXT PORTABLE',
    );
    expect(
      targetDb.select(
        'SELECT prompt FROM o_modelPrompt '
        'WHERE vendorId=? AND model=? AND path=?',
        ['retired-provider', 'retired-text', 'text/retired.md'],
      ).single['prompt'],
      'RETIRED TEXT',
    );
  });

  test('导出导入同一模型的两个安全模板路径时都保留且重复元组仅剩一条', () async {
    await _installModels(engine);
    final first = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '首帧模式',
      prompt: 'FIRST FRAME',
    );
    final second = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '首尾帧模式',
      prompt: 'FIRST LAST FRAME',
    );
    for (final template in [first, second]) {
      db.execute(
        'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
        'VALUES (?,?,?,?,?)',
        [
          'provider-a',
          'video-1',
          p.basename(template.path),
          template.path,
          template.prompt,
        ],
      );
    }
    final exported = await engine.exportConfig();

    final targetDb = openEngineDb(':memory:');
    final target = Engine(
      db: targetDb,
      media: MediaStore(p.join(dir.path, 'two-path-target-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(targetDb, isMobile: false),
    );
    addTearDown(() {
      target.dispose();
      targetDb.close();
    });
    targetDb.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?),(?,?,?,?,?)',
      [
        'provider-a',
        'video-1',
        p.basename(first.path),
        first.path,
        'STALE ONE',
        'provider-a',
        'video-1',
        p.basename(first.path),
        first.path,
        'STALE TWO',
      ],
    );

    await target.importConfig(exported);

    final bindings = (await target.listModelPromptBindings())
        .where((binding) =>
            binding.providerId == 'provider-a' && binding.modelId == 'video-1')
        .toList();
    expect(bindings.map((binding) => binding.path).toSet(), {
      first.path,
      second.path,
    });
    expect(
      bindings.map((binding) => binding.prompt).toSet(),
      {'FIRST FRAME', 'FIRST LAST FRAME'},
    );
    expect(
      targetDb.select(
        'SELECT id FROM o_modelPrompt '
        'WHERE vendorId=? AND model=? AND path=?',
        ['provider-a', 'video-1', first.path],
      ),
      hasLength(1),
    );
  });

  test('旧备份没有模板字段时从安全映射回填，覆盖导入以模板正文为准', () async {
    await _installModels(engine);
    final existing = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '旧备份',
      prompt: 'BEFORE',
    );
    await engine.bindModelPromptTemplate(
      'provider-a',
      'video-1',
      existing.path,
    );

    final providers = (await engine.exportConfig())['providers'];
    await engine.importConfig({
      'configVersion': 3,
      'providers': providers,
      'bindings': const {},
      'prompts': const [],
      'modelPrompts': [
        {
          'vendorId': 'provider-a',
          'model': 'video-1',
          'fileName': '旧备份.md',
          'path': 'video/旧备份.md',
          'prompt': 'LEGACY IMPORT',
        },
        {
          'vendorId': 'provider-a',
          'model': 'text-1',
          'fileName': 'director.md',
          'path': 'text/director.md',
          'prompt': 'LEGACY TEXT',
        },
      ],
    });

    expect((await engine.listModelPromptTemplates()).single.prompt,
        'LEGACY IMPORT');
    expect((await engine.listModelPromptBindings()).single.prompt,
        'LEGACY IMPORT');
    expect(
      db.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['text/director.md'],
      ).single['prompt'],
      'LEGACY TEXT',
    );

    await engine.importConfig({
      'configVersion': 3,
      'providers': providers,
      'bindings': const {},
      'prompts': const [],
      'modelPromptTemplates': [
        {
          'path': 'video/旧备份.md',
          'name': '旧备份',
          'kind': 'video',
          'prompt': 'TEMPLATE WINS',
          'createTime': 10,
          'updateTime': 20,
        },
      ],
    });

    expect(
      db.select(
        'SELECT prompt FROM o_modelPrompt WHERE path=?',
        ['video/旧备份.md'],
      ).single['prompt'],
      'TEMPLATE WINS',
    );
  });

  test('非法导入在模板映射事务内回滚且不破坏既有绑定', () async {
    await _installModels(engine);
    final template = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '保留',
      prompt: 'KEEP',
    );
    await engine.bindModelPromptTemplate(
        'provider-a', 'video-1', template.path);
    final providers = (await engine.exportConfig())['providers'];

    await expectLater(
      engine.importConfig({
        'configVersion': 3,
        'providers': providers,
        'bindings': const {},
        'prompts': const [],
        'modelPromptTemplates': [
          {
            'path': 'video/new.md',
            'name': 'new',
            'kind': 'video',
            'prompt': 'NEW',
          },
        ],
        'modelPrompts': [
          {
            'vendorId': 'provider-a',
            'model': 'video-1',
            'fileName': 'new.md',
            'path': '../escape.md',
            'prompt': 'INVALID',
          },
        ],
      }),
      throwsA(isA<EngineException>()),
    );

    expect(
      (await engine.listModelPromptTemplates())
          .map((item) => item.path)
          .toList(),
      [template.path],
    );
    expect((await engine.listModelPromptBindings()).single.path, template.path);
  });

  test('导入后段模板类型校验失败时整份数据库配置回滚', () async {
    await _installModels(engine);
    await engine.updatePrompt('rollback-global', 'GLOBAL BEFORE');
    db.execute(
      "INSERT OR REPLACE INTO o_setting (key,value) VALUES "
      "('binding.shot_video','provider-a:video-1')",
    );
    final existing = await engine.createModelPromptTemplate(
      kind: 'video',
      name: '回滚保留',
      prompt: 'TEMPLATE BEFORE',
    );
    await engine.bindModelPromptTemplate(
      'provider-a',
      'video-1',
      existing.path,
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        'provider-a',
        'text-1',
        'existing.md',
        'text/existing.md',
        'MAPPING BEFORE',
      ],
    );
    final before = _databaseConfigSnapshot(db);

    await expectLater(
      engine.importConfig({
        'configVersion': 3,
        'providers': [
          {
            'id': 'provider-a',
            'name': 'Imported Provider A',
            'protocol': 'openai_compatible',
            'baseUrl': 'https://import.invalid/v1',
            'enabled': false,
            'models': [
              {
                'modelId': 'image-1',
                'label': 'Imported Image',
                'kind': 'image',
                'enabled': true,
              },
              {
                'modelId': 'video-1',
                'label': 'Imported Video',
                'kind': 'video',
                'enabled': true,
              },
              {
                'modelId': 'text-1',
                'label': 'Imported Text',
                'kind': 'text',
                'enabled': true,
              },
            ],
          },
          {
            'id': 'provider-new',
            'name': 'Imported New Provider',
            'protocol': 'openai_compatible',
            'baseUrl': 'https://new.invalid/v1',
            'enabled': true,
            'models': const [],
          },
        ],
        'bindings': const {'shot_video': 'provider-a:image-1'},
        'prompts': const [
          {'key': 'rollback-global', 'content': 'GLOBAL IMPORTED'},
        ],
        'modelPromptTemplates': const [
          {
            'path': 'video/rollback-new.md',
            'name': 'rollback-new',
            'kind': 'video',
            'prompt': 'TEMPLATE IMPORTED',
          },
        ],
        'modelPrompts': const [
          {
            'vendorId': 'provider-a',
            'model': 'text-1',
            'fileName': 'imported.md',
            'path': 'text/imported.md',
            'prompt': 'MAPPING IMPORTED',
          },
          {
            'vendorId': 'provider-a',
            'model': 'image-1',
            'fileName': 'rollback-new.md',
            'path': 'video/rollback-new.md',
            'prompt': 'TYPE MISMATCH',
          },
        ],
      }),
      throwsA(
        isA<EngineException>().having(
          (error) => error.errKey,
          'errKey',
          errModelMissing,
        ),
      ),
    );

    expect(_databaseConfigSnapshot(db), before);
  });

  test('凭据写入等待期间不持有配置 savepoint，后续数据库失败不回滚无关写入', () async {
    final credentials = _DeferredCredentialStore();
    engine.dispose();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'transaction-boundary-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );
    db.execute(
      '''
CREATE TRIGGER reject_imported_provider
BEFORE UPDATE ON o_vendorConfig
WHEN NEW.id='provider-trigger' AND NEW.enable=1
BEGIN
  SELECT RAISE(ABORT, 'forced config write failure');
END
''',
    );
    final before = _databaseConfigSnapshot(db);

    final importFuture = engine.importConfig({
      'configVersion': 3,
      'providers': const [
        {
          'id': 'provider-trigger',
          'name': 'Trigger Provider',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://trigger.invalid/v1',
          'apiKey': 'test-only-key',
          'enabled': true,
          'models': [],
        },
      ],
      'bindings': const {},
      'prompts': const [],
      'modelPromptTemplates': const [],
      'modelPrompts': const [],
    });
    await credentials.writeStarted.future;
    db.execute(
      'INSERT INTO o_setting (key,value) VALUES (?,?)',
      ['unrelated.runtime.state', 'must-survive'],
    );
    credentials.resumeWrite.complete();

    await expectLater(importFuture, throwsA(isA<SqliteException>()));

    expect(
      db.select(
        'SELECT value FROM o_setting WHERE key=?',
        ['unrelated.runtime.state'],
      ).single['value'],
      'must-survive',
    );
    expect(
      _providerInput(db, 'provider-trigger'),
      containsPair('provisioningFailed', true),
    );
    expect(
      db.select('SELECT enable FROM o_vendorConfig WHERE id=?',
          ['provider-trigger']).single['enable'],
      0,
    );
    expect(
        _databaseConfigSnapshot(db)['providers'], isNot(before['providers']));
  });

  test('模型映射校验失败时不触碰既有供应商凭据', () async {
    final credentials = InMemoryCredentialStore()
      ..seed(providerCredentialRef('provider-a'), 'old-key');
    engine.dispose();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'credential-rollback-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );
    await _installModels(engine);
    final before = _databaseConfigSnapshot(db);

    await expectLater(
      engine.importConfig({
        'configVersion': 3,
        'providers': const [
          {
            'id': 'provider-a',
            'name': 'Provider A',
            'protocol': 'openai_compatible',
            'baseUrl': 'https://provider-a.invalid/v1',
            'apiKey': 'new-key',
            'enabled': true,
            'models': [],
          },
        ],
        'bindings': const {},
        'prompts': const [],
        'modelPromptTemplates': const [
          {
            'path': 'video/imported.md',
            'name': 'imported',
            'kind': 'video',
            'prompt': 'IMPORTED',
            'createTime': 1,
            'updateTime': 1,
          },
        ],
        'modelPrompts': const [
          {
            'vendorId': 'provider-a',
            'model': 'image-1',
            'fileName': 'imported.md',
            'path': 'video/imported.md',
            'prompt': 'IMPORTED',
          },
        ],
      }),
      throwsA(isA<EngineException>()),
    );

    expect(
      await credentials.read(providerCredentialRef('provider-a')),
      'old-key',
    );
    expect(_databaseConfigSnapshot(db), before);
  });

  test('旧配置凭据迁移期间使全部受影响供应商保持禁用', () async {
    final credentials = _BlockedImportCredentialStore();
    engine.dispose();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'credential-repair-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );
    final importFuture = engine.importConfig(_validLegacyCredentialImport());
    await credentials.blockedWriteStarted.future;

    for (final providerId in ['provider-a', 'provider-b']) {
      expect(
        db.select('SELECT enable FROM o_vendorConfig WHERE id=?',
            [providerId]).single['enable'],
        0,
      );
      expect(
          _providerInput(db, providerId), containsPair('provisioning', true));
    }

    credentials.resumeBlockedWrite.complete();
    await expectLater(importFuture, throwsA(isA<StateError>()));

    for (final providerId in ['provider-a', 'provider-b']) {
      expect(
        db.select('SELECT enable FROM o_vendorConfig WHERE id=?',
            [providerId]).single['enable'],
        0,
      );
      expect(
        _providerInput(db, providerId),
        containsPair('provisioningFailed', true),
      );
    }
  });

  test('凭据迁移失败后重启仍保持半导入供应商禁用', () async {
    final credentials = _BlockedImportCredentialStore();
    engine.dispose();
    db.close();
    final dataDir = p.join(dir.path, 'failed-import-restart');
    engine = await Engine.boot(
      dataDir: dataDir,
      isMobile: false,
      credentialStore: credentials,
    );
    db = engine.db;

    final importFuture = engine.importConfig(_validLegacyCredentialImport());
    await credentials.blockedWriteStarted.future;
    credentials.resumeBlockedWrite.complete();
    await expectLater(importFuture, throwsA(isA<StateError>()));

    engine.dispose();
    db.close();
    engine = await Engine.boot(
      dataDir: dataDir,
      isMobile: false,
      credentialStore: credentials,
    );
    db = engine.db;

    for (final providerId in ['provider-a', 'provider-b']) {
      expect(
        db.select('SELECT enable FROM o_vendorConfig WHERE id=?',
            [providerId]).single['enable'],
        0,
      );
      expect(
        _providerInput(db, providerId),
        containsPair('provisioningFailed', true),
      );
    }
  });

  test('凭据迁移失败后不能只切换启用状态绕过显式重试', () async {
    final credentials = _BlockedImportCredentialStore();
    engine.dispose();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'failed-import-toggle-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );

    final importFuture = engine.importConfig(_validLegacyCredentialImport());
    await credentials.blockedWriteStarted.future;
    credentials.resumeBlockedWrite.complete();
    await expectLater(importFuture, throwsA(isA<StateError>()));

    await expectLater(
      engine.updateProvider('provider-a', enabled: true),
      throwsA(
        isA<EngineException>().having(
          (error) => error.errKey,
          'errKey',
          errProviderMissing,
        ),
      ),
    );
    expect(
      db.select('SELECT enable FROM o_vendorConfig WHERE id=?',
          ['provider-a']).single['enable'],
      0,
    );
    expect(
      _providerInput(db, 'provider-a'),
      containsPair('provisioningFailed', true),
    );
  });

  test('失败导入不会覆盖等待期间的同供应商凭据更新', () async {
    final credentials = _BlockedImportCredentialStore()
      ..seed(providerCredentialRef('provider-a'), 'old-key');
    engine.dispose();
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'credential-gate-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );
    await _installModels(engine);
    final importFuture = engine.importConfig(_validLegacyCredentialImport());
    await credentials.blockedWriteStarted.future;
    final updateFuture = engine.updateProvider(
      'provider-a',
      apiKey: 'newer',
      enabled: true,
    );
    credentials.resumeBlockedWrite.complete();

    await expectLater(importFuture, throwsA(isA<StateError>()));
    await updateFuture;

    expect(
      await credentials.read(providerCredentialRef('provider-a')),
      'newer',
    );
    expect(
      db.select('SELECT enable FROM o_vendorConfig WHERE id=?',
          ['provider-a']).single['enable'],
      1,
    );
    expect(_providerInput(db, 'provider-a'), isNot(contains('provisioning')));
    expect(
      _providerInput(db, 'provider-a'),
      isNot(contains('provisioningFailed')),
    );
  });
}

Map<String, dynamic> _validLegacyCredentialImport() => {
      'configVersion': 3,
      'providers': const [
        {
          'id': 'provider-a',
          'name': 'Provider A',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://provider-a.invalid/v1',
          'apiKey': 'new-key',
          'enabled': true,
          'models': [],
        },
        {
          'id': 'provider-b',
          'name': 'Provider B',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://provider-b.invalid/v1',
          'apiKey': 'blocked-key',
          'enabled': true,
          'models': [],
        },
      ],
      'bindings': const {},
      'prompts': const [],
      'modelPromptTemplates': const [],
      'modelPrompts': const [],
    };

Map<String, dynamic> _providerInput(Database db, String providerId) {
  final raw = db.select(
    'SELECT inputValues FROM o_vendorConfig WHERE id=?',
    [providerId],
  ).single['inputValues'] as String;
  return Map<String, dynamic>.from(jsonDecode(raw) as Map);
}

Set<String> _tables(Database db) => db
    .select("SELECT name FROM sqlite_master WHERE type='table'")
    .map((row) => row['name'] as String)
    .toSet();

Map<String, Object?> _databaseConfigSnapshot(Database db) => {
      'providers': _rows(
        db,
        'SELECT id,enable,inputValues,models FROM o_vendorConfig ORDER BY id',
      ),
      'bindings': _rows(
        db,
        "SELECT key,value FROM o_setting WHERE key LIKE 'binding.%' ORDER BY key",
      ),
      'prompts': _rows(
        db,
        'SELECT name,type,data,useData FROM o_prompt ORDER BY id',
      ),
      'templates': _rows(
        db,
        'SELECT path,name,kind,prompt,createTime,updateTime '
        'FROM o_modelPromptTemplate ORDER BY path',
      ),
      'mappings': _rows(
        db,
        'SELECT vendorId,model,fileName,path,prompt '
        'FROM o_modelPrompt ORDER BY id',
      ),
    };

List<Map<String, Object?>> _rows(Database db, String sql) => [
      for (final row in db.select(sql)) Map<String, Object?>.from(row),
    ];

Future<void> _installModels(Engine engine) async {
  for (final providerId in ['provider-a', 'provider-b']) {
    engine.db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        providerId,
        1,
        jsonEncode({
          'name': providerId,
          'protocol': 'volcengine',
          'baseUrl': 'https://example.invalid',
        }),
        jsonEncode([
          {
            'id': '$providerId:image-${providerId == 'provider-a' ? 1 : 2}',
            'providerId': providerId,
            'modelId': 'image-${providerId == 'provider-a' ? 1 : 2}',
            'label': 'Image',
            'kind': 'image',
            'capabilities': const <String, Object?>{},
            'enabled': true,
          },
          {
            'id': '$providerId:video-${providerId == 'provider-a' ? 1 : 2}',
            'providerId': providerId,
            'modelId': 'video-${providerId == 'provider-a' ? 1 : 2}',
            'label': 'Video',
            'kind': 'video',
            'capabilities': const <String, Object?>{},
            'enabled': true,
          },
          if (providerId == 'provider-a')
            {
              'id': '$providerId:text-1',
              'providerId': providerId,
              'modelId': 'text-1',
              'label': 'Text',
              'kind': 'text',
              'capabilities': const <String, Object?>{},
              'enabled': true,
            },
        ]),
      ],
    );
  }
}

class _DeferredCredentialStore implements CredentialStore {
  final writeStarted = Completer<void>();
  final resumeWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    writeStarted.complete();
    await resumeWrite.future;
  }

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> delete(String key) async {}
}

class _BlockedImportCredentialStore implements CredentialStore {
  final values = <String, String>{};
  final blockedWriteStarted = Completer<void>();
  final resumeBlockedWrite = Completer<void>();

  void seed(String key, String value) => values[key] = value;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (value == 'blocked-key') {
      blockedWriteStarted.complete();
      await resumeBlockedWrite.future;
      throw StateError('credential write unavailable');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
