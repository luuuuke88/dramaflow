import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/assistant_skills.dart';
import 'package:dramaflow/src/engine/art_style.dart';
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/manuals.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/video_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;

  Future<Engine> bootForTest(String dataDir, {CredentialStore? credentials}) =>
      Engine.boot(
        dataDir: dataDir,
        isMobile: false,
        credentialStore: credentials ?? InMemoryCredentialStore(),
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dramaflow-engine-');
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

  test('themeMode 持久化并拒绝非法值', () async {
    expect(await engine.getThemeMode(), 'light');
    await engine.setThemeMode('system');
    expect(await engine.getThemeMode(), 'system');
    expect(() => engine.setThemeMode('sepia'), throwsA(isA<EngineException>()));
  });

  test('locale 持久化并拒绝非法值', () async {
    expect(await engine.getAppLocale(), '');
    await engine.setAppLocale('zh');
    expect(await engine.getAppLocale(), 'zh');
    await engine.setAppLocale('');
    expect(await engine.getAppLocale(), '');
    expect(() => engine.setAppLocale('fr'), throwsA(isA<EngineException>()));
  });

  test('createProject/listProjects 兼容包装使用 o_project', () async {
    final project = await engine.createProject('兼容项目', artStyle: '国风');

    expect(project.id, 1);
    expect(project.name, '兼容项目');
    expect(engine.projects().single.artStyle, '国风');
  });

  test('activeJobs/projectJobs 读取 o_tasks', () async {
    final projectId = engine.addProject(projectType: 'drama', name: 'p');
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass) VALUES (?,'pending','event_generation')",
      [projectId],
    );
    db.execute(
      "INSERT INTO o_tasks (projectId,state,taskClass) VALUES (?,'success','asset_extraction')",
      [projectId],
    );

    expect((await engine.activeJobs()).map((task) => task.state), ['pending']);
    expect(await engine.projectJobs(projectId), hasLength(2));
  });

  test('retryJob 将 failed 任务重新置为 pending', () async {
    final projectId = engine.addProject(projectType: 'drama', name: 'p');
    db.execute(
      "INSERT INTO o_tasks (id,projectId,state,taskClass,reason) VALUES (5,?,'failed','event_generation',?)",
      [projectId, const EngineException(errNetwork).toReasonJson()],
    );

    final id = await engine.retryJob(5);

    expect(id, 5);
    expect(
      db.select('SELECT state FROM o_tasks WHERE id=5').first['state'],
      'pending',
    );
    expect(db.select('SELECT reason FROM o_tasks WHERE id=5').first['reason'],
        isNull);
  });

  test('provider CRUD + model 保存走 o_vendorConfig', () async {
    final provider = await engine.createProvider(
      name: '测试供应商',
      protocol: 'openai_compatible',
      baseUrl: 'https://api.test/v1',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'm1',
        'label': 'M1',
        'kind': 'text',
        'enabled': true,
      }
    ]);

    final listed = await engine.listProviders();
    final models = await engine.listProviderModels(provider.id);

    expect(listed.single.name, '测试供应商');
    expect(models.single.modelId, 'm1');
    expect(models.single.kind, 'text');
  });

  test('供应商 API Key 不写入 SQLite 或普通配置导出', () async {
    const secret = 'sk-provider-secret';
    final provider = await engine.createProvider(
      name: '安全供应商',
      protocol: 'openai_compatible',
      baseUrl: 'https://api.test/v1',
      apiKey: secret,
    );

    final stored = db.select(
      'SELECT inputValues FROM o_vendorConfig WHERE id=?',
      [provider.id],
    ).single['inputValues'] as String;
    final exported = jsonEncode(await engine.exportConfig());

    expect(stored, isNot(contains(secret)));
    expect(exported, isNot(contains(secret)));
  });

  test('导入旧配置时迁移 API Key 到凭据存储', () async {
    const secret = 'sk-imported-secret';
    await engine.importConfig({
      'configVersion': 3,
      'providers': [
        {
          'id': 'legacy-provider',
          'name': 'Legacy',
          'protocol': 'openai_compatible',
          'baseUrl': 'https://api.test/v1',
          'apiKey': secret,
          'enabled': true,
          'models': const [],
        },
      ],
      'bindings': const {},
      'prompts': const [],
      'modelPrompts': const [],
    });

    final stored = db.select(
      'SELECT inputValues FROM o_vendorConfig WHERE id=?',
      ['legacy-provider'],
    ).single['inputValues'] as String;

    expect(
      await engine.credentials.read(providerCredentialRef('legacy-provider')),
      secret,
    );
    expect(stored, isNot(contains(secret)));
    expect(jsonEncode(await engine.exportConfig()), isNot(contains(secret)));
  });

  test('setBinding 校验模型类型并持久化', () async {
    final provider = await engine.createProvider(
      name: '绑定供应商',
      protocol: 'openai_compatible',
      baseUrl: 'https://api.test/v1',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, [
      {'modelId': 'text-1', 'kind': 'text', 'enabled': true},
      {'modelId': 'img-1', 'kind': 'image', 'enabled': true},
    ]);

    await engine.setBinding('script_gen', provider.id, 'text-1');

    expect((await engine.getBindings())['script_gen'], '${provider.id}:text-1');
    expect(
      () => engine.setBinding('script_gen', provider.id, 'img-1'),
      throwsA(isA<EngineException>()),
    );
  });

  test('setBinding 拒绝已移除的 Agent embedding 阶段', () async {
    final provider = await engine.createProvider(
      name: 'Embedding供应商',
      protocol: 'openai_compatible',
      baseUrl: 'https://api.test/v1',
      apiKey: 'sk',
    );
    db.execute(
      'UPDATE o_vendorConfig SET models=? WHERE id=?',
      [
        jsonEncode([
          {
            'id': '${provider.id}:embed-1',
            'providerId': provider.id,
            'modelId': 'embed-1',
            'kind': 'embedding',
            'enabled': true,
          },
        ]),
        provider.id,
      ],
    );

    await expectLater(
      engine.setBinding('agent_embedding', provider.id, 'embed-1'),
      throwsA(isA<EngineException>()),
    );
  });

  test('seeded ToonFlow prompt 可通过 getPrompt 读取', () async {
    final seeded = await bootForTest(p.join(dir.path, 'seeded'));
    addTearDown(() {
      seeded.dispose();
      seeded.db.close();
    });

    final expected = _referencePrompt('eventExtraction');

    expect(
      await seeded.getPrompt('eventExtraction'),
      startsWith(expected.substring(0, 20)),
    );
    expect(
      await seeded.getPrompt('script_gen_system'),
      contains('资深短剧编剧'),
    );

    final rows = seeded.db.select(
      'SELECT name,type,useData FROM o_prompt WHERE name IN (?,?,?) ORDER BY name',
      ['eventExtraction', 'scriptAssetExtraction', 'scriptGen'],
    );
    expect(rows.map((row) => row['name']), [
      'eventExtraction',
      'scriptAssetExtraction',
      'scriptGen',
    ]);
    for (final row in rows) {
      expect(
        row['type'],
        row['name'] == 'scriptGen' ? 'script_gen_system' : row['name'],
      );
      expect(row['useData'], isNull);
    }

    final bindings = await seeded.getBindings();
    expect(bindings['director_plan'], 'azt:gpt-5.5');
    expect(bindings['storyboard_table'], 'azt:gpt-5.5');
    final c4Prompts = seeded.db.select(
      'SELECT name,type FROM o_prompt WHERE name IN (?,?) ORDER BY name',
      ['director_plan', 'storyboard_table'],
    );
    expect(c4Prompts.map((row) => row['name']),
        ['director_plan', 'storyboard_table']);
    expect(c4Prompts.map((row) => row['type']),
        ['director_plan', 'storyboard_table']);

    final mobile = await Engine.boot(
      dataDir: p.join(dir.path, 'seeded-mobile'),
      isMobile: true,
      credentialStore: InMemoryCredentialStore(),
    );
    addTearDown(() {
      mobile.dispose();
      mobile.db.close();
    });
    final mobileBindings = await mobile.getBindings();
    expect(
        mobileBindings['director_plan'], 'volcengine:doubao-seed-1-6-250615');
    expect(mobileBindings['storyboard_table'],
        'volcengine:doubao-seed-1-6-250615');
  });

  test('boot 不再 seed ToonFlow 根级 Markdown 技能；助手内置技能懒播种且不重置禁用状态', () async {
    final dataDir = p.join(dir.path, 'toonflow-skill-seed');
    final skillsRoot = Directory(p.join(dataDir, 'skills'))
      ..createSync(recursive: true);
    File(p.join(skillsRoot.path, 'script_execution_skeleton.md'))
        .writeAsStringSync('''
---
name: script_execution_skeleton.md
description: 故事骨架搭建 Agent
---

# 故事骨架搭建 Agent
请输出 <storySkeleton>。
''');
    File(p.join(skillsRoot.path, 'production_execution_storyboard_table.md'))
        .writeAsStringSync('''
---
name: production_execution_storyboard_table.md
description: 分镜表构建 Agent
---

# 分镜表构建
请输出 <storyboardTable>。
''');
    File(p.join(
      skillsRoot.path,
      'production_skills',
      'storyboard_table_techniques.md',
    ))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('分镜表技法：必须包含时长。');

    final seeded = await bootForTest(dataDir);
    final legacyRows = seeded.db.select(
      "SELECT id FROM o_skillList WHERE id IN (?,?) ORDER BY id",
      [
        'production_execution_storyboard_table.md',
        'script_execution_skeleton.md',
      ],
    );
    expect(legacyRows, isEmpty, reason: 'T13 删除旧 ToonFlow 子代理 Markdown 自动播种');
    expect(
      seeded.assistantSkills().map((skill) => skill.id),
      containsAll(['get_status', 'generate_events']),
    );
    seeded.db.execute(
      'UPDATE o_skillList SET state=0, description=? WHERE id=?',
      ['用户禁用且改过描述', 'generate_events'],
    );
    seeded.dispose();
    seeded.db.close();

    final rebooted = await bootForTest(dataDir);
    addTearDown(() {
      rebooted.dispose();
      rebooted.db.close();
    });
    rebooted.assistantSkills();
    final rows = rebooted.db.select(
      'SELECT description,state FROM o_skillList WHERE id=?',
      ['generate_events'],
    );
    expect(rows.single['description'], '用户禁用且改过描述');
    expect(rows.single['state'], 0);
    expect(
      rebooted.db.select(
        "SELECT id FROM o_skillList WHERE id IN (?,?)",
        [
          'production_execution_storyboard_table.md',
          'script_execution_skeleton.md',
        ],
      ),
      isEmpty,
    );
  });

  test('prompt update/get/reset 使用 useData 覆写并回落 data', () async {
    final seeded = await bootForTest(p.join(dir.path, 'prompt-reset'));
    addTearDown(() {
      seeded.dispose();
      seeded.db.close();
    });
    final fallback = _referencePrompt('eventExtraction');

    await seeded.updatePrompt('eventExtraction', '自定义');
    expect(await seeded.getPrompt('eventExtraction'), '自定义');
    expect(
      (await seeded.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'eventExtraction')['content'],
      '自定义',
    );
    expect(
      (await seeded.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'eventExtraction')['isOverridden'],
      isTrue,
    );

    await seeded.resetPrompt('eventExtraction');

    expect(await seeded.getPrompt('eventExtraction'), fallback);
    expect(
      (await seeded.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'eventExtraction')['content'],
      fallback,
    );
    expect(
      (await seeded.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'eventExtraction')['isOverridden'],
      isFalse,
    );
  });

  test('getPrompt 查无提示词时抛 errPromptMissing', () async {
    await expectLater(
      engine.getPrompt('missingPrompt'),
      throwsA(
        isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errPromptMissing)
            .having((e) => e.errParams['type'], 'type', 'missingPrompt'),
      ),
    );
  });

  test('model prompt list/update 支持模型专属模板维护', () async {
    final provider = await engine.createProvider(
      name: '火山',
      protocol: 'volcengine',
      baseUrl: 'https://ark.test',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, [
      {
        'modelId': 'doubao-seedance-2-0-mini-260615',
        'label': 'Seedance 2.0 Mini',
        'kind': 'video',
        'enabled': true,
      },
    ]);
    await engine.setBinding(
      'shot_video',
      provider.id,
      'doubao-seedance-2-0-mini-260615',
    );
    db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        provider.id,
        'doubao-seedance-2-0-mini-260615',
        'video_prompt_gen',
        'video/seedance2Multi-parameterMode.md',
        '旧模板',
      ],
    );

    final rows = await (engine as dynamic).listModelPrompts()
        as List<Map<String, dynamic>>;

    expect(rows.single['providerName'], '火山');
    expect(rows.single['modelLabel'], 'Seedance 2.0 Mini');
    expect(rows.single['prompt'], '旧模板');

    await (engine as dynamic)
        .updateModelPrompt(rows.single['id'] as int, '新模板');

    expect(
        await engine.getPromptForStageModel('video_prompt_gen', 'shot_video'),
        '新模板');
  });

  test('boot 注册 Seedance Mini 默认模板且不覆盖用户编辑', () async {
    final dataDir = p.join(dir.path, 'seeded-model-prompts');
    final template = File(p.join(
      dataDir,
      'model_prompts',
      'video',
      'seedance2Multi-parameterMode.md',
    ));
    template.createSync(recursive: true);
    template.writeAsStringSync('Seedance bundled template');

    final seeded = await bootForTest(dataDir);
    var seededDisposed = false;
    addTearDown(() {
      if (!seededDisposed) seeded.dispose();
    });

    final rows = await seeded.listModelPrompts();
    expect(rows, hasLength(1));
    expect(rows.single['vendorId'], 'volcengine');
    expect(rows.single['model'], 'doubao-seedance-2-0-mini-260615');
    expect(rows.single['fileName'], 'seedance2Multi-parameterMode.md');
    expect(rows.single['path'], 'video/seedance2Multi-parameterMode.md');
    expect(rows.single['prompt'], 'Seedance bundled template');
    expect(
      await seeded.getPromptForStageModel('video_prompt_gen', 'shot_video'),
      await seeded.getPrompt('video_prompt_gen'),
    );

    await seeded.updateModelPrompt(rows.single['id'] as int, 'user edited');
    seeded.dispose();
    seededDisposed = true;

    final rebooted = await bootForTest(dataDir);
    addTearDown(rebooted.dispose);
    final rebootedRows = await rebooted.listModelPrompts();
    expect(rebootedRows, hasLength(1));
    expect(rebootedRows.single['prompt'], 'user edited');
  });

  test('boot seeds structured Seedance video capabilities', () async {
    final seeded = await bootForTest(p.join(dir.path, 'seeded-video-caps'));
    addTearDown(seeded.dispose);

    final models = await seeded.listProviderModels('volcengine');
    final byId = {for (final model in models) model.modelId: model};

    final mini = VideoModelCapabilities.fromJson(
      byId['doubao-seedance-2-0-mini-260615']!.capabilities,
    );
    final full = VideoModelCapabilities.fromJson(
      byId['doubao-seedance-2-0-260128']!.capabilities,
    );
    final fast = VideoModelCapabilities.fromJson(
      byId['doubao-seedance-2-0-fast-260128']!.capabilities,
    );

    expect(mini.modes, {VideoMode.firstFrame});
    expect(mini.durations, {for (var i = 4; i <= 15; i++) i});
    expect(mini.resolutions, {'480p', '720p'});
    expect(mini.ratios, {'16:9', '9:16'});
    expect(mini.audio, 'none');

    expect(
      full.modes,
      {
        VideoMode.text,
        VideoMode.firstFrame,
        VideoMode.firstLastFrame,
        VideoMode.multiReference,
      },
    );
    expect(full.referenceLimits, {'image': 9, 'video': 3, 'audio': 3});
    expect(full.audio, 'optional');
    expect(
      full.promptTemplates[VideoMode.multiReference],
      'video/seedance2Multi-parameterMode.md',
    );

    expect(fast.modes, full.modes);
    expect(fast.referenceLimits, full.referenceLimits);
    expect(fast.audio, 'optional');
  });

  test(
      'boot backfills full fast profiles and upgrades legacy mini capabilities without overwriting the row',
      () async {
    final dataDir = p.join(dir.path, 'seeded-video-cap-upgrade');
    final seeded = await bootForTest(dataDir);
    var seededDisposed = false;
    addTearDown(() {
      if (!seededDisposed) seeded.dispose();
    });

    final existingModels = await seeded.listProviderModels('volcengine');
    final downgraded = [
      for (final model in existingModels)
        if (!{
          'doubao-seedance-2-0-260128',
          'doubao-seedance-2-0-fast-260128',
        }.contains(model.modelId))
          {
            'id': model.id,
            'modelId': model.modelId,
            'label': model.modelId == 'doubao-seedance-2-0-mini-260615'
                ? 'Custom Mini'
                : model.label,
            'kind': model.kind,
            'capabilities': model.modelId == 'doubao-seedance-2-0-mini-260615'
                ? {
                    'durations': [4, 5],
                    'resolutions': ['720p'],
                  }
                : model.capabilities,
            'enabled': model.enabled,
          },
    ];
    await seeded.saveProviderModels('volcengine', downgraded);
    seeded.dispose();
    seededDisposed = true;

    final rebooted = await bootForTest(dataDir);
    addTearDown(rebooted.dispose);
    final rebootedModels = await rebooted.listProviderModels('volcengine');
    final byId = {for (final model in rebootedModels) model.modelId: model};

    expect(byId['doubao-seedance-2-0-mini-260615']!.label, 'Custom Mini');
    final mini = VideoModelCapabilities.fromJson(
      byId['doubao-seedance-2-0-mini-260615']!.capabilities,
    );
    expect(mini.modes, {VideoMode.firstFrame});
    expect(mini.durations, {4, 5});
    expect(mini.resolutions, {'720p'});
    expect(
      byId.containsKey('doubao-seedance-2-0-260128'),
      isTrue,
    );
    expect(
      byId.containsKey('doubao-seedance-2-0-fast-260128'),
      isTrue,
    );
  });

  test('boot preserves an existing custom full Seedance model declaration',
      () async {
    final dataDir = p.join(dir.path, 'seeded-video-cap-preserve');
    final seeded = await bootForTest(dataDir);
    final models = await seeded.listProviderModels('volcengine');
    await seeded.saveProviderModels('volcengine', [
      for (final model in models)
        if (model.modelId == 'doubao-seedance-2-0-260128')
          {
            'id': model.id,
            'providerId': model.providerId,
            'modelId': model.modelId,
            'label': 'My Full Seedance',
            'kind': 'video',
            'capabilities': {
              'video': {
                'modes': ['text'],
                'references': const {},
                'durations': [8],
                'resolutions': ['720p'],
                'ratios': ['16:9'],
                'audio': 'none',
                'promptTemplates': const {},
              },
            },
            'enabled': true,
          }
        else
          {
            'id': model.id,
            'providerId': model.providerId,
            'modelId': model.modelId,
            'label': model.label,
            'kind': model.kind,
            'capabilities': model.capabilities,
            'enabled': model.enabled,
          },
    ]);
    seeded.dispose();

    final rebooted = await bootForTest(dataDir);
    addTearDown(rebooted.dispose);
    final full = (await rebooted.listProviderModels('volcengine'))
        .singleWhere((model) => model.modelId == 'doubao-seedance-2-0-260128');

    expect(full.label, 'My Full Seedance');
    final caps = VideoModelCapabilities.fromJson(full.capabilities);
    expect(caps.modes, {VideoMode.text});
    expect(caps.durations, {8});
    expect(caps.audio, 'none');
  });

  test('exportConfig/importConfig 往返供应商、绑定、提示词', () async {
    final provider = await engine.createProvider(
      name: '导出供应商',
      protocol: 'openai_compatible',
      baseUrl: 'https://api.test/v1',
      apiKey: 'sk',
    );
    await engine.saveProviderModels(provider.id, [
      {'modelId': 'm1', 'kind': 'text', 'enabled': true},
      {'modelId': 'seedance-mini', 'kind': 'video', 'enabled': true},
    ]);
    await engine.setBinding('script_gen', provider.id, 'm1');
    await engine.setBinding('shot_video', provider.id, 'seedance-mini');
    await engine.updatePrompt('eventExtraction', '导出提示词');
    engine.db.execute(
      'INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
      'VALUES (?,?,?,?,?)',
      [
        provider.id,
        'seedance-mini',
        'video_prompt_gen',
        'video/seedance2Multi-parameterMode.md',
        '导出模型专属提示词',
      ],
    );

    final data = await engine.exportConfig();
    expect(data['configVersion'], 3);
    expect(data['modelPrompts'], isA<List>());
    final otherDb = openEngineDb(':memory:');
    final other = Engine(
      db: otherDb,
      media: MediaStore(p.join(dir.path, 'other-media')),
      gateway: _NoopGateway(),
      config: EngineConfig(otherDb, isMobile: false),
    );
    addTearDown(() {
      other.dispose();
      otherDb.close();
    });

    await other.importConfig(data);

    expect((await other.listProviders()).single.name, '导出供应商');
    expect((await other.getBindings())['script_gen'], '${provider.id}:m1');
    expect((await other.getBindings())['shot_video'],
        '${provider.id}:seedance-mini');
    expect(
      (await other.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'eventExtraction')['content'],
      '导出提示词',
    );
    expect(
      await other.getPromptForStageModel('video_prompt_gen', 'shot_video'),
      '导出模型专属提示词',
    );
  });

  test('importConfig 版本不符抛 errConfigVersion', () async {
    await expectLater(
      engine.importConfig({
        'configVersion': 2,
        'providers': const [],
        'bindings': const {},
        'prompts': const [],
      }),
      throwsA(
        isA<EngineException>()
            .having((e) => e.errKey, 'errKey', errConfigVersion)
            .having((e) => e.errParams['found'], 'found', 2),
      ),
    );
  });

  test('prompt 种子幂等补种缺失单行', () async {
    final dataDir = p.join(dir.path, 'seed-idempotent');
    final seeded = await bootForTest(dataDir);
    seeded.db.execute(
      'DELETE FROM o_prompt WHERE name=?',
      ['eventExtraction'],
    );
    expect(
      seeded.db.select('SELECT COUNT(*) n FROM o_prompt WHERE name=?',
          ['eventExtraction']).first['n'],
      0,
    );
    seeded.dispose();
    seeded.db.close();

    final rebooted = await bootForTest(dataDir);
    addTearDown(() {
      rebooted.dispose();
      rebooted.db.close();
    });

    final expected = _referencePrompt('eventExtraction');
    expect(await rebooted.getPrompt('eventExtraction'), expected);
    expect(
      rebooted.db.select('SELECT COUNT(*) n FROM o_prompt WHERE name=?',
          ['scriptAssetExtraction']).first['n'],
      1,
    );
  });

  test('视觉手册是项目画风的唯一种子来源，不派生画风库条目', () async {
    final dataDir = p.join(dir.path, 'art-style-seed');
    final packDir = Directory(
      p.join(dataDir, 'skills', 'art_skills', 'toonflow_default'),
    )..createSync(recursive: true);
    File(p.join(packDir.path, 'README.md'))
        .writeAsStringSync('# 国风二次元新国潮风格说明\n');
    File(p.join(packDir.path, 'prefix.md')).writeAsStringSync('国风二次元提示词前缀');
    final imagesDir = Directory(p.join(packDir.path, 'images'))
      ..createSync(recursive: true);
    File(p.join(imagesDir.path, '1.png')).writeAsBytesSync([137, 80, 78, 71]);

    final seeded = await bootForTest(dataDir);
    addTearDown(() {
      seeded.dispose();
      seeded.db.close();
    });

    final manuals = seeded.visualManuals();
    expect(manuals, hasLength(1));
    expect(manuals.single.pack, 'toonflow_default');
    expect(manuals.single.data['prefix'], '国风二次元提示词前缀');
    expect(seeded.artStyles(), isEmpty);
  });

  test('health 返回版本与绑定摘要', () async {
    final health = await engine.health();

    expect(health['version'], Engine.version);
    expect((health['providers'] as Map), contains('text'));
  });
}

String _referencePrompt(String type) {
  final file = File(
    p.normalize(
      p.join(
        Directory.current.path,
        '..',
        'docs',
        'reference',
        'toonflow-prompts.md',
      ),
    ),
  );
  final source = file.readAsStringSync();
  final match = RegExp(
    '## type: ${RegExp.escape(type)}\\s+````\\n([\\s\\S]*?)\\n````',
  ).firstMatch(source);
  if (match == null) {
    throw StateError('missing prompt reference: $type');
  }
  return match.group(1)!;
}

class _NoopGateway extends ProviderGateway {
  @override
  Future<TextResult> generateText(
    String system,
    String user, {
    required String stage,
    CancelToken? cancelToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateImage(
    String prompt,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
    List<String> referenceAbsPaths = const [],
    String? editInstruction,
    String? maskAbsPath,
    String? ratio,
    String? quality,
    String? modelOverride,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateSpeech(
    String text,
    String projectId, {
    required String stage,
    required String voice,
    CancelToken? cancelToken,
    String? format,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> generateToolJson(String system, String user,
          {required String stage,
          required String toolName,
          required Map<String, dynamic> schema,
          CancelToken? cancelToken}) async =>
      const <String, dynamic>{};

  @override
  Future<AgentTurnResult> generateAgentTurn(
    String system,
    List<Map<String, String>> messages,
    List<AgentToolDef> tools, {
    required String stage,
    CancelToken? cancelToken,
  }) async =>
      const AgentTurnResult.text('');
}
