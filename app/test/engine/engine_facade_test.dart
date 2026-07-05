import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/errors.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late Database db;
  late Engine engine;

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

  test('seeded ToonFlow prompt 可通过 getPrompt 读取', () async {
    final seeded = await Engine.boot(
      dataDir: p.join(dir.path, 'seeded'),
      isMobile: false,
    );
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
  });

  test('boot 自动 seed ToonFlow 根级 Agent Markdown 技能且不重置禁用状态', () async {
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

    final seeded = await Engine.boot(dataDir: dataDir, isMobile: false);
    seeded.dispose();
    seeded.db.close();

    final db1 = sqlite3.open(p.join(dataDir, 'dramaflow.sqlite'));
    var rows = db1.select(
      "SELECT id,name,description,state,type,path,md5 FROM o_skillList "
      "WHERE id IN (?,?) ORDER BY id",
      [
        'production_execution_storyboard_table.md',
        'script_execution_skeleton.md',
      ],
    );
    expect(rows.map((row) => row['id']), [
      'production_execution_storyboard_table.md',
      'script_execution_skeleton.md',
    ]);
    expect(rows.first['type'], 'markdown-agent');
    expect(
      rows.first['path'],
      p.join(skillsRoot.path, 'production_execution_storyboard_table.md'),
    );
    expect(rows.first['md5'], contains('production_skills'));
    expect(
      db1.select(
        'SELECT skillId FROM o_skillAttribution WHERE attribution=?',
        ['production_execution_storyboard_table'],
      ).map((row) => row['skillId']),
      contains('production_execution_storyboard_table.md'),
    );

    db1.execute(
      'UPDATE o_skillList SET state=0, description=? WHERE id=?',
      ['用户禁用且改过描述', 'script_execution_skeleton.md'],
    );
    db1.close();

    final rebooted = await Engine.boot(dataDir: dataDir, isMobile: false);
    addTearDown(() {
      rebooted.dispose();
      rebooted.db.close();
    });
    rows = rebooted.db.select(
      'SELECT description,state FROM o_skillList WHERE id=?',
      ['script_execution_skeleton.md'],
    );
    expect(rows.single['description'], '用户禁用且改过描述');
    expect(rows.single['state'], 0);
  });

  test('prompt update/get/reset 使用 useData 覆写并回落 data', () async {
    final seeded = await Engine.boot(
      dataDir: p.join(dir.path, 'prompt-reset'),
      isMobile: false,
    );
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
    final seeded = await Engine.boot(dataDir: dataDir, isMobile: false);
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

    final rebooted = await Engine.boot(dataDir: dataDir, isMobile: false);
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

class _NoopGateway implements ProviderGateway {
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
  Future<String> generateVideo(
    String prompt,
    String firstFrameAbsPath,
    String projectId, {
    required String stage,
    CancelToken? cancelToken,
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
