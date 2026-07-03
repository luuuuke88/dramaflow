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

  test('prompt update/reset 使用 o_prompt', () async {
    await engine.updatePrompt('script_gen_system', '自定义');
    expect(
      (await engine.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'script_gen_system')['content'],
      '自定义',
    );

    await engine.resetPrompt('script_gen_system');

    expect(
      (await engine.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'script_gen_system')['content'],
      isNot('自定义'),
    );
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
    ]);
    await engine.setBinding('script_gen', provider.id, 'm1');
    await engine.updatePrompt('script_gen_system', '导出提示词');

    final data = await engine.exportConfig();
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
    expect(
      (await other.listPrompts()).singleWhere(
          (prompt) => prompt['key'] == 'script_gen_system')['content'],
      '导出提示词',
    );
  });

  test('health 返回版本与绑定摘要', () async {
    final health = await engine.health();

    expect(health['version'], Engine.version);
    expect((health['providers'] as Map), contains('text'));
  });
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
    String? refImageAbsPath,
    String? editInstruction,
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
}
