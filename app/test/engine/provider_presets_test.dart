import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/provider_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('目录：13 家 id 唯一且必填字段完备（含硬门字段）', () {
    expect(kProviderPresets.length, 13);
    expect(kProviderPresets.map((p) => p.id).toSet().length, 13);
    for (final p in kProviderPresets) {
      expect(p.name.trim(), isNotEmpty);
      expect(p.keyUrl.trim(), isNotEmpty, reason: '${p.id} 缺 keyUrl');
      expect(p.sourceUrl.trim(), isNotEmpty, reason: '${p.id} 缺 sourceUrl（硬门）');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p.verifiedAt), isTrue,
          reason: '${p.id} verifiedAt 必须 YYYY-MM-DD（硬门）');
      expect(
          {'openai_compatible', 'anthropic', 'ima2', 'volcengine'}
              .contains(p.protocol),
          isTrue);
      final uri = Uri.parse(p.baseUrl);
      if (const {'azt', 'ima2'}.contains(p.id)) {
        expect(uri.host, '127.0.0.1');
      } else {
        expect(uri.scheme, 'https', reason: '${p.id} 必须 https');
      }
      expect(p.models, isNotEmpty);
      for (final m in p.models) {
        expect({'text', 'image', 'video', 'tts'}.contains(m.kind), isTrue,
            reason: '${p.id}:${m.modelId} kind 非法');
      }
    }
  });

  test('Anthropic 走原生协议；兼容模式仅保留 gemini/xai', () {
    expect(providerPresetById('anthropic')!.protocol, 'anthropic');
    expect(kProviderPresets.where((p) => p.compatMode).map((p) => p.id).toSet(),
        {'gemini', 'xai'});
    expect(
        kProviderPresets
            .where((p) => p.acceptanceVerified)
            .map((p) => p.id)
            .toSet(),
        {'azt'},
        reason: '未过人工验收（Task 7 证据表）的预设不得标已验');
  });

  test('providerPresetById 与 presetModelKinds', () {
    expect(providerPresetById('openai'), isNotNull);
    expect(providerPresetById('nope'), isNull);
    expect(presetModelKinds('volcengine').values.toSet(),
        containsAll({'text', 'image', 'video'}));
  });

  test('xAI 默认模型只保留当前官方目录可核实的型号', () {
    expect(
      providerPresetById('xai')!.models.map((model) => model.modelId),
      ['grok-4.5'],
    );
  });

  test('azt 预设目录同步本机服务可见的文本模型，并保留独立验证的图片模型', () {
    final preset = providerPresetById('azt')!;
    final textModels = [
      for (final model in preset.models)
        if (model.kind == 'text') model.modelId,
    ];

    // 2026-07-19 的本机 GET /v1/models 证据：这五个文本模型均由
    // AI Zero Token 暴露。图片模型不出现在该端点，但已有独立图片冒烟证据，
    // 因而不能被这份文本目录错误移除。
    expect(textModels, [
      'gpt-5.6-sol',
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-5.5',
      'gpt-5.3-codex-spark',
    ]);
    expect(
      preset.models
          .where((model) => model.kind == 'image')
          .map((model) => model.modelId),
      ['gpt-image-2'],
    );
    expect(preset.verifiedAt, '2026-07-19');
  });

  test('启动时将完全未编辑的旧 azt 默认目录升级为当前目录', () async {
    final dir = await Directory.systemTemp.createTemp('df-azt-upgrade-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = '${dir.path}/dramaflow.sqlite';
    final db = openEngineDb(dbPath);
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'azt',
        1,
        jsonEncode({
          'name': 'azt',
          'protocol': 'openai_compatible',
          'baseUrl': 'http://127.0.0.1:8787/v1',
          'credentialRef': providerCredentialRef('azt'),
          'createdAt': '2026-07-18T00:00:00.000Z',
        }),
        jsonEncode(_legacyAztSeedModels()),
      ],
    );
    db.close();

    final engine = await Engine.boot(
      dataDir: dir.path,
      isMobile: false,
      credentialStore: InMemoryCredentialStore(),
    );
    addTearDown(engine.dispose);

    expect(_modelIds(engine), _aztPresetModelIds());
  });

  test('启动时不覆盖用户改过的 azt 模型目录', () async {
    final dir = await Directory.systemTemp.createTemp('df-azt-user-model-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = '${dir.path}/dramaflow.sqlite';
    final db = openEngineDb(dbPath);
    final customized = [
      ..._legacyAztSeedModels(),
      {
        'id': 'azt:my-local-model',
        'providerId': 'azt',
        'modelId': 'my-local-model',
        'label': '我的本地模型',
        'kind': 'text',
        'capabilities': <String, Object?>{},
        'enabled': true,
      },
    ];
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'azt',
        1,
        jsonEncode({
          'name': 'azt',
          'protocol': 'openai_compatible',
          'baseUrl': 'http://127.0.0.1:8787/v1',
          'credentialRef': providerCredentialRef('azt'),
          'createdAt': '2026-07-18T00:00:00.000Z',
        }),
        jsonEncode(customized),
      ],
    );
    db.close();

    final engine = await Engine.boot(
      dataDir: dir.path,
      isMobile: false,
      credentialStore: InMemoryCredentialStore(),
    );
    addTearDown(engine.dispose);

    expect(_modelIds(engine), [
      'gpt-5.5',
      'gpt-5.4',
      'gpt-5.4-mini',
      'gpt-image-2',
      'my-local-model',
    ]);
  });

  test('防漂移：Engine.boot 种子与目录逐字段一致（桌面含 azt，移动不含）', () async {
    final dir = await Directory.systemTemp.createTemp('df-seed-lock-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final engine = await Engine.boot(
      dataDir: dir.path,
      isMobile: false,
      credentialStore: InMemoryCredentialStore(),
    );
    addTearDown(engine.dispose);

    for (final presetId in ['azt', 'volcengine']) {
      final preset = providerPresetById(presetId)!;
      final row = engine.db.select(
          'SELECT inputValues, models FROM o_vendorConfig WHERE id=?',
          [presetId]).single;
      final inputValues = jsonDecode(row['inputValues'] as String) as Map;
      expect(inputValues['baseUrl'], preset.baseUrl,
          reason: '$presetId baseUrl 漂移');
      expect(inputValues['protocol'], preset.protocol);
      final seeded = (jsonDecode(row['models'] as String) as List)
          .whereType<Map>()
          .toList();
      // volcengine 的种子行还叠加了 `_seedSeedanceVideoProfiles`（engine.dart，
      // Task 1 范围外、对新旧库都做增量迁移的独立机制，未从目录构建）追加的 2 个
      // Seedance 2.0 全量/极速档模型；这里精确断言"目录 3 项 + 该已知 2 项"，
      // 而不是弱化为“至少”，以继续对任何非预期漂移保持敏感。azt 无此叠加，加数为 0。
      final knownExtra = presetId == 'volcengine' ? 2 : 0;
      expect(seeded.length, preset.models.length + knownExtra,
          reason: '$presetId 模型数漂移');
      for (var i = 0; i < preset.models.length; i++) {
        final s = seeded[i];
        final m = preset.models[i];
        expect(s['modelId'], m.modelId, reason: '$presetId[$i] modelId 漂移');
        expect(s['label'], m.label);
        expect(s['kind'], m.kind);
        expect(jsonEncode(s['capabilities'] ?? {}), jsonEncode(m.capabilities),
            reason: '$presetId:${m.modelId} capabilities 漂移');
      }
    }

    final mobileDir = await Directory.systemTemp.createTemp('df-seed-lock-m-');
    addTearDown(() => mobileDir.deleteSync(recursive: true));
    final mobile = await Engine.boot(
      dataDir: mobileDir.path,
      isMobile: true,
      credentialStore: InMemoryCredentialStore(),
    );
    addTearDown(mobile.dispose);
    expect(
        mobile.db.select('SELECT id FROM o_vendorConfig WHERE id=?', ['azt']),
        isEmpty,
        reason: '移动端不种 azt（loopback 到不了手机）');
  });
}

List<Map<String, Object?>> _legacyAztSeedModels() => [
      for (final (modelId, kind) in const [
        ('gpt-5.5', 'text'),
        ('gpt-5.4', 'text'),
        ('gpt-5.4-mini', 'text'),
        ('gpt-image-2', 'image'),
      ])
        {
          'id': 'azt:$modelId',
          'providerId': 'azt',
          'modelId': modelId,
          'label': modelId,
          'kind': kind,
          'capabilities': <String, Object?>{},
          'enabled': true,
        },
    ];

List<String> _aztPresetModelIds() => [
      for (final model in providerPresetById('azt')!.models) model.modelId,
    ];

List<String> _modelIds(Engine engine) {
  final row = engine.db
      .select('SELECT models FROM o_vendorConfig WHERE id=?', ['azt']).single;
  return [
    for (final model in (jsonDecode(row['models'] as String) as List))
      (model as Map)['modelId'] as String,
  ];
}
