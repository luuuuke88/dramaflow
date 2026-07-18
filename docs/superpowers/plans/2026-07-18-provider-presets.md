# 供应商预设体系 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 预设画廊式添加供应商——12 家预设（含 OpenAI/Claude/Gemini/Grok 国际线）一键预填，原子创建防 Key 覆盖，`/models` 拉取候选。

**Architecture:** 纯常量目录（`provider_presets.dart`）+ 一个新引擎 API（`createProviderFromPreset`，原子语义）+ 一个新网关方法（`listRemoteModelIds`，只出候选不写库）+ 设置页画廊/预填表单/候选合并三段 UI。数据库 schema、协议分发、现有 `createProvider`/`saveProviderModels` 零改动。

**Tech Stack:** Flutter/Dart，sqlite3，dio，flutter_secure_storage（经 `CredentialStore`），riverpod，go_router，现有 l10n（zh/en/ja 三语）。

**Spec:** `docs/superpowers/specs/2026-07-18-provider-presets-design.md`（本计划的唯一需求来源，冲突以 spec 为准）

## Global Constraints

- 模型 ID 硬门：任何模型 ID 未经当日对照 `sourceUrl` 核实（或经该家真实 API 调用验证）**不得写入常量**；核实后必须填 `verifiedAt`（'YYYY-MM-DD'）。目录单测断言两字段非空。
- 许可证红线：**不复制 ToonFlow `data/vendor/*.ts` 任何代码或文案**；预设内容独立编写（公开端点与模型 ID 是事实数据）。
- 兼容模式诚实标注：anthropic/gemini/xai 三家 `compatMode: true`，画廊卡片显示"兼容模式"角标，文案不得暗示完整原生能力。
- 新 UI 文案一律三语（zh/en/ja），品牌名不翻译。模板 arb 是 `app/lib/l10n/app_zh.arb`，改后跑 `flutter gen-l10n`。
- 原子创建语义：已存在同 id 供应商时**凭证一个字节都不写**；INSERT 失败回滚删除新写凭证；供应商+模型一次调用写入，无中间态。
- 拉取只出候选：`/models` 结果不直接写库；未知 ID 标"未分类"默认禁用，用户指定 kind 才能保存，**绝不默认猜成 text**。
- 每预设一实例：画廊对已存在实例显示"已添加"并进编辑；多账号走"自定义"。
- 默认种子不变：仍只种 azt（桌面）+ volcengine。
- git 纪律：新提交不 amend、`git add` 逐个文件不用 `-A`、不 `--no-verify`。
- 所有命令在 `/Users/luke/Documents/aivideo/dramaflow/app` 下执行；每个任务收尾跑 `flutter analyze <改动文件>` 须 0 issues。

---

### Task 1: 预设目录常量 + 模型 ID 核实 + 目录单测

**Files:**
- Create: `app/lib/src/engine/provider_presets.dart`
- Test: `app/test/engine/provider_presets_test.dart`

**Interfaces:**
- Produces: `class ProviderPreset`、`class PresetModel`、`const List<ProviderPreset> kProviderPresets`（12 项）、`ProviderPreset? providerPresetById(String id)`、`Map<String, String> presetModelKinds(String presetId)`（modelId→kind，Task 6 用）。

- [ ] **Step 1: 核实模型 ID（硬门，先于写代码）**

对下表 6 家"易变"供应商，逐家用 WebFetch 打开 sourceUrl，核对/修正"候选模型"列，记录当日日期作为 `verifiedAt`。其余 6 家：azt/volcengine 以仓库现有种子为准（`engine.dart` `_seedDefaults` 里的模型即真值）；anthropic 的三个 ID（claude-sonnet-5 / claude-opus-4-8 / claude-haiku-4-5）与 deepseek 的两个 ID（deepseek-chat / deepseek-reasoner）为稳定公开 ID，仍须对 sourceUrl 快速确认后填 verifiedAt。

| presetId | sourceUrl（核实处） | 候选模型（核实后可改） |
|---|---|---|
| openai | https://developers.openai.com/api/docs/models | gpt-5.6-sol(text)、gpt-5.6-terra(text)、gpt-5.6-luna(text)、gpt-image-2(image) |
| gemini | https://ai.google.dev/gemini-api/docs/openai | gemini-3.5-flash(text)、当期 pro 型号(text) |
| xai | https://docs.x.ai/developers/models | grok-4.5(text)、grok-4.3(text) |
| openrouter | https://openrouter.ai/models | anthropic/claude-sonnet-5(text)、google/gemini-3-pro(text)、openai/gpt-5.1(text) |
| siliconflow | https://docs.siliconflow.cn/cn/api-reference/models/get-model-list | deepseek-ai/DeepSeek-V3.2(text)、Qwen/Qwen3-Max(text)、Kwai-Kolors/Kolors(image) |
| moonshot / zhipu / dashscope | https://platform.moonshot.cn/docs / https://docs.bigmodel.cn / https://help.aliyun.com/zh/model-studio/models | kimi-latest、kimi-thinking-preview / glm-4.6、cogview-4(image) / qwen3-max、qwen-plus |

WebFetch 失败（网络/反爬）时的回退：改用该家 `GET {baseUrl}/models` 真实调用核实（需要环境变量里有对应 Key），仍不可得则**该家降级为只保留有把握的 1 个旗舰 ID**并在 preset 的 label 备注"清单待补"，不许臆造。

- [ ] **Step 2: 写失败测试**

```dart
// app/test/engine/provider_presets_test.dart
import 'package:dramaflow/src/engine/provider_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('目录：12 家 id 唯一且必填字段完备', () {
    expect(kProviderPresets.length, 12);
    final ids = kProviderPresets.map((p) => p.id).toSet();
    expect(ids.length, 12, reason: 'preset id 不得重复');
    for (final p in kProviderPresets) {
      expect(p.name.trim(), isNotEmpty);
      expect(p.keyUrl.trim(), isNotEmpty, reason: '${p.id} 缺 keyUrl');
      expect(p.sourceUrl.trim(), isNotEmpty, reason: '${p.id} 缺 sourceUrl（硬门）');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p.verifiedAt), isTrue,
          reason: '${p.id} verifiedAt 必须是 YYYY-MM-DD（硬门）');
      expect({'openai_compatible', 'volcengine'}.contains(p.protocol), isTrue,
          reason: '${p.id} 协议必须是已实现协议');
      final uri = Uri.parse(p.baseUrl);
      if (p.id == 'azt') {
        expect(uri.host, '127.0.0.1', reason: 'azt 是本地网关');
      } else {
        expect(uri.scheme, 'https', reason: '${p.id} 必须 https');
      }
      expect(p.models, isNotEmpty, reason: '${p.id} 模型清单不得为空');
      for (final m in p.models) {
        expect({'text', 'image', 'video', 'tts'}.contains(m.kind), isTrue,
            reason: '${p.id}:${m.modelId} kind 非法');
      }
    }
  });

  test('兼容模式只标在 anthropic/gemini/xai 三家', () {
    final compat = kProviderPresets.where((p) => p.compatMode).map((p) => p.id).toSet();
    expect(compat, {'anthropic', 'gemini', 'xai'});
  });

  test('providerPresetById 与 presetModelKinds', () {
    expect(providerPresetById('openai'), isNotNull);
    expect(providerPresetById('nope'), isNull);
    final kinds = presetModelKinds('volcengine');
    expect(kinds.values.toSet(), containsAll({'text', 'image', 'video'}));
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/engine/provider_presets_test.dart`
Expected: FAIL（provider_presets.dart 不存在，编译错误）

- [ ] **Step 4: 实现目录**

```dart
// app/lib/src/engine/provider_presets.dart
/// 供应商预设目录（spec: docs/superpowers/specs/2026-07-18-provider-presets-design.md §3-4）。
/// 内容独立编写；模型 ID 经 sourceUrl 核实后方可入列（verifiedAt 为核实日）。
/// 不得从 ToonFlow data/vendor/*.ts 复制任何代码或文案（许可证红线）。
class PresetModel {
  final String modelId;
  final String label;
  final String kind; // text | image | video | tts
  final Map<String, Object?> capabilities;

  const PresetModel(this.modelId, this.kind,
      {String? label, this.capabilities = const {}})
      : label = label ?? modelId;
}

class ProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String keyUrl;
  final String protocol; // openai_compatible | volcengine
  final bool compatMode;
  final String sourceUrl;
  final String verifiedAt; // YYYY-MM-DD
  final List<PresetModel> models;

  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.keyUrl,
    this.protocol = 'openai_compatible',
    this.compatMode = false,
    required this.sourceUrl,
    required this.verifiedAt,
    required this.models,
  });
}

ProviderPreset? providerPresetById(String id) {
  for (final p in kProviderPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// modelId -> kind 映射，供 /models 候选自动归类（spec §5 第 5 条）。
Map<String, String> presetModelKinds(String presetId) {
  final p = providerPresetById(presetId);
  if (p == null) return const {};
  return {for (final m in p.models) m.modelId: m.kind};
}

const kProviderPresets = <ProviderPreset>[
  ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    sourceUrl: 'https://developers.openai.com/api/docs/models',
    verifiedAt: '2026-07-18', // Step 1 核实日，实施时以实际日期为准
    models: [
      PresetModel('gpt-5.6-sol', 'text'),
      PresetModel('gpt-5.6-terra', 'text'),
      PresetModel('gpt-5.6-luna', 'text'),
      PresetModel('gpt-image-2', 'image'),
    ],
  ),
  ProviderPreset(
    id: 'anthropic',
    name: 'Claude (Anthropic)',
    baseUrl: 'https://api.anthropic.com/v1',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    compatMode: true,
    sourceUrl: 'https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('claude-sonnet-5', 'text'),
      PresetModel('claude-opus-4-8', 'text'),
      PresetModel('claude-haiku-4-5', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'gemini',
    name: 'Gemini (Google)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    keyUrl: 'https://aistudio.google.com/apikey',
    compatMode: true,
    sourceUrl: 'https://ai.google.dev/gemini-api/docs/openai',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('gemini-3.5-flash', 'text'),
      PresetModel('gemini-3-pro', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'xai',
    name: 'Grok (xAI)',
    baseUrl: 'https://api.x.ai/v1',
    keyUrl: 'https://console.x.ai',
    compatMode: true,
    sourceUrl: 'https://docs.x.ai/developers/models',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('grok-4.5', 'text'),
      PresetModel('grok-4.3', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/settings/keys',
    sourceUrl: 'https://openrouter.ai/models',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('anthropic/claude-sonnet-5', 'text'),
      PresetModel('google/gemini-3-pro', 'text'),
      PresetModel('openai/gpt-5.1', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'siliconflow',
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    keyUrl: 'https://cloud.siliconflow.cn/account/ak',
    sourceUrl: 'https://docs.siliconflow.cn/cn/api-reference/models/get-model-list',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('deepseek-ai/DeepSeek-V3.2', 'text'),
      PresetModel('Qwen/Qwen3-Max', 'text'),
      PresetModel('Kwai-Kolors/Kolors', 'image'),
    ],
  ),
  ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    sourceUrl: 'https://api-docs.deepseek.com',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('deepseek-chat', 'text'),
      PresetModel('deepseek-reasoner', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'moonshot',
    name: 'Kimi (Moonshot)',
    baseUrl: 'https://api.moonshot.cn/v1',
    keyUrl: 'https://platform.moonshot.cn/console/api-keys',
    sourceUrl: 'https://platform.moonshot.cn/docs',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('kimi-latest', 'text'),
      PresetModel('kimi-thinking-preview', 'text'),
    ],
  ),
  ProviderPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    keyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    sourceUrl: 'https://docs.bigmodel.cn',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('glm-4.6', 'text'),
      PresetModel('cogview-4', 'image'),
    ],
  ),
  ProviderPreset(
    id: 'dashscope',
    name: '通义 Qwen',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1',
    sourceUrl: 'https://help.aliyun.com/zh/model-studio/models',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('qwen3-max', 'text'),
      PresetModel('qwen-plus', 'text'),
      // 图片是否过兼容层：spec §4 要求实施时验证，不通则不预置（Task 7 人工验收清单项）
    ],
  ),
  ProviderPreset(
    id: 'volcengine',
    name: '火山豆包',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    keyUrl: 'https://console.volcengine.com/ark',
    protocol: 'volcengine',
    sourceUrl: 'https://www.volcengine.com/docs/82379',
    verifiedAt: '2026-07-18',
    models: [
      // 与 engine.dart _seedDefaults 现有种子逐字一致（仓库内真值）
      PresetModel('doubao-seed-1-6-250615', 'text'),
      PresetModel('doubao-seedream-4-0-250828', 'image'),
      PresetModel('doubao-seedance-1-0-pro-250528', 'video',
          capabilities: {
            'modes': ['text', 'singleImage'],
          }),
    ],
  ),
  ProviderPreset(
    id: 'azt',
    name: 'azt (本地 Codex OAuth)',
    baseUrl: 'http://127.0.0.1:8787/v1',
    keyUrl: 'http://127.0.0.1:8787',
    sourceUrl: 'http://127.0.0.1:8787/v1/models',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('gpt-5.5', 'text'),
      PresetModel('gpt-5.4', 'text'),
      PresetModel('gpt-5.4-mini', 'text'),
      PresetModel('gpt-image-2', 'image'),
    ],
  ),
];
```

实现前先打开 `app/lib/src/engine/engine.dart` 搜 `_seedDefaults`，把 volcengine/azt 两家的模型 ID、capabilities **逐字对齐现有种子**（上面代码块按当前仓库内容写好，若种子已变以仓库为准）。Step 1 核实结果若与上面候选不同，以核实结果为准修改。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/engine/provider_presets_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 6: analyze + commit**

```bash
flutter analyze lib/src/engine/provider_presets.dart test/engine/provider_presets_test.dart
git add lib/src/engine/provider_presets.dart test/engine/provider_presets_test.dart
git commit -m "feat(engine): 供应商预设目录常量（12 家，模型 ID 经 sourceUrl 核实）"
```

---

### Task 2: `createProviderFromPreset` 原子创建

**Files:**
- Modify: `app/lib/src/engine/errors.dart`（加一个错误码常量）
- Modify: `app/lib/src/engine/engine.dart`（在 `createProvider` 方法之后加新方法 + import provider_presets.dart）
- Test: `app/test/engine/provider_preset_create_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `providerPresetById`。
- Produces: `Future<ProviderInfo> createProviderFromPreset({required String presetId, required String apiKey, List<String>? selectedModelIds})`；错误码 `errProviderExists`。语义：presetId 不存在→`errProviderMissing`；已有同 id 供应商→`errProviderExists` 且**不写凭证**；INSERT 失败→回滚删除新写凭证后 rethrow；成功→供应商+选中模型一次写入。

- [ ] **Step 1: 写失败测试**

```dart
// app/test/engine/provider_preset_create_test.dart
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Engine engine;
  late InMemoryCredentialStore credentials;

  setUp(() {
    final db = openEngineDb(':memory:');
    credentials = InMemoryCredentialStore();
    engine = Engine(
      db: db,
      media: MediaStore('/tmp/df-preset-test-media'),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
      credentials: credentials,
    );
  });

  tearDown(() => engine.dispose());

  test('正常路径：供应商+选中模型一次写入', () async {
    final info = await engine.createProviderFromPreset(
      presetId: 'deepseek',
      apiKey: 'sk-test',
      selectedModelIds: ['deepseek-chat'],
    );
    expect(info.id, 'deepseek');
    expect(info.hasCredential, isTrue);
    final models = await engine.listProviderModels('deepseek');
    expect(models.map((m) => m.modelId).toList(), ['deepseek-chat']);
  });

  test('未知 presetId 抛 errProviderMissing', () async {
    expect(
      () => engine.createProviderFromPreset(presetId: 'nope', apiKey: 'k'),
      throwsA(isA<EngineException>()
          .having((e) => e.code, 'code', 'errProviderMissing')),
    );
  });

  test('P0 场景：重复创建抛 errProviderExists 且旧凭证一个字节不动', () async {
    await engine.createProviderFromPreset(presetId: 'deepseek', apiKey: 'old-key');
    expect(
      () => engine.createProviderFromPreset(presetId: 'deepseek', apiKey: 'NEW'),
      throwsA(isA<EngineException>()
          .having((e) => e.code, 'code', 'errProviderExists')),
    );
    final stored = await credentials.read(providerCredentialRef('deepseek'));
    expect(stored, 'old-key', reason: '重复创建绝不能覆盖旧 Key');
  });

  test('INSERT 失败回滚删除新凭证', () async {
    // 先用自定义路径造一个 id 冲突但绕过 preset 查重的场景不可行（查重按 id），
    // 改为直接验证回滚分支：关闭 db 让 INSERT 必然抛错。
    engine.db.dispose();
    await expectLater(
      engine.createProviderFromPreset(presetId: 'moonshot', apiKey: 'k1'),
      throwsA(anything),
    );
    final stored = await credentials.read(providerCredentialRef('moonshot'));
    expect(stored, isNull, reason: 'INSERT 失败必须回滚删除新写入的凭证');
  });
}
```

先读 `test/engine/engine_facade_test.dart` 开头，确认 `Engine(...)` 构造参数名与上面一致（尤其 `credentials:` 是否为具名参数；若引擎不支持注入 credentials，改用引擎内部默认 `InMemoryCredentialStore` 的既有测试写法，并通过 `engine.credentials` 读取——以现有测试文件的真实写法为准调整 harness，断言不变）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/engine/provider_preset_create_test.dart`
Expected: FAIL（`createProviderFromPreset` 未定义 / `errProviderExists` 未定义）

- [ ] **Step 3: 实现**

`app/lib/src/engine/errors.dart` 在 `errProviderMissing` 下一行加：

```dart
const errProviderExists = 'errProviderExists';
```

`app/lib/src/engine/engine.dart` 顶部 import 区加 `import 'provider_presets.dart';`，在 `createProvider` 方法后加：

```dart
  /// 预设一键创建（spec §6）：原子语义——已存在同 id 供应商时凭证一个字节不写；
  /// INSERT 失败回滚删除新凭证；供应商与选中模型同一调用写入，无中间态。
  Future<ProviderInfo> createProviderFromPreset({
    required String presetId,
    required String apiKey,
    List<String>? selectedModelIds,
  }) async {
    final preset = providerPresetById(presetId);
    if (preset == null) {
      throw EngineException(errProviderMissing, {'presetId': presetId});
    }
    final existing = db
        .select('SELECT id FROM o_vendorConfig WHERE id=?', [preset.id]);
    if (existing.isNotEmpty) {
      throw EngineException(errProviderExists, {'providerId': preset.id});
    }
    final credentialRef = providerCredentialRef(preset.id);
    final key = apiKey.trim();
    final wroteCredential = key.isNotEmpty;
    if (wroteCredential) {
      await credentials.write(credentialRef, key);
    }
    final createdAt = nowIso();
    try {
      final models = [
        for (final m in preset.models)
          if (selectedModelIds == null || selectedModelIds.contains(m.modelId))
            {
              'id': '${preset.id}:${m.modelId}',
              'providerId': preset.id,
              'modelId': m.modelId,
              'label': m.label,
              'kind': m.kind,
              'capabilities': m.capabilities,
              'enabled': true,
            },
      ];
      if (models.isEmpty) {
        throw const EngineException(errModelMissing, {'reason': '至少选择一个模型'});
      }
      db.execute(
        'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
        [
          preset.id,
          1,
          jsonEncode({
            'name': preset.name,
            'protocol': preset.protocol,
            'baseUrl': preset.baseUrl,
            'credentialRef': credentialRef,
            'presetId': preset.id,
            'createdAt': createdAt,
          }),
          jsonEncode(models),
        ],
      );
    } catch (_) {
      if (wroteCredential) {
        try {
          await credentials.delete(credentialRef);
        } catch (_) {}
      }
      rethrow;
    }
    return ProviderInfo(
      id: preset.id,
      name: preset.name,
      protocol: preset.protocol,
      baseUrl: preset.baseUrl,
      hasCredential: wroteCredential,
      enabled: true,
      createdAt: createdAt,
    );
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/engine/provider_preset_create_test.dart`
Expected: PASS（4 tests）

- [ ] **Step 5: 全量引擎测试防回归 + commit**

```bash
flutter test test/engine/
flutter analyze lib/src/engine/errors.dart lib/src/engine/engine.dart test/engine/provider_preset_create_test.dart
git add lib/src/engine/errors.dart lib/src/engine/engine.dart test/engine/provider_preset_create_test.dart
git commit -m "feat(engine): createProviderFromPreset 原子创建（防旧 Key 覆盖/失败回滚）"
```

---

### Task 3: `/models` 拉取候选（网关 + 引擎转发）

**Files:**
- Modify: `app/lib/src/engine/providers/gateway.dart`（接口默认方法 + `HttpProviderGateway` 实现）
- Modify: `app/lib/src/engine/engine.dart`（转发方法）
- Test: `app/test/engine/remote_model_candidates_test.dart`

**Interfaces:**
- Produces: `ProviderGateway.listRemoteModelIds(String providerId)`（默认 `Future.error(UnsupportedError(...))`，与 `submitVideo` 同款样式）；`HttpProviderGateway` 真实现（dio GET `{baseUrl}/models`，Bearer 头，解析 `data[].id`，DioException→`EngineException(errNetwork,...)`）；`Engine.fetchProviderModelCandidates(String providerId)` 转发。**只返回 `List<String>` 候选，不写库。**

- [ ] **Step 1: 写失败测试**

```dart
// app/test/engine/remote_model_candidates_test.dart
import 'package:dio/dio.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/engine/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpProviderGateway gateway;
  late Dio dio;

  setUp(() {
    final db = openEngineDb(':memory:');
    db.execute(
      'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
      [
        'p1',
        1,
        '{"name":"p1","protocol":"openai_compatible","baseUrl":"https://x.test/v1","credentialRef":"provider:p1"}',
        '[]',
      ],
    );
    dio = Dio();
    gateway = HttpProviderGateway(db, EngineConfig(db, isMobile: false),
        MediaStore('/tmp/df-candidates-test-media'),
        dio: dio);
  });

  test('解析标准 /models 响应为 ID 列表', () async {
    dio.httpClientAdapter = _FakeAdapter((options) {
      expect(options.path, 'https://x.test/v1/models');
      return ResponseBody.fromString(
        '{"object":"list","data":[{"id":"m-a"},{"id":"m-b"}]}',
        200,
        headers: {'content-type': ['application/json']},
      );
    });
    final ids = await gateway.listRemoteModelIds('p1');
    expect(ids, ['m-a', 'm-b']);
  });

  test('网络错误包装为 errNetwork', () async {
    dio.httpClientAdapter = _FakeAdapter((options) =>
        throw DioException(requestOptions: options, type: DioExceptionType.connectionTimeout));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(isA<EngineException>().having((e) => e.code, 'code', 'errNetwork')),
    );
  });

  test('未知 providerId 抛 errProviderMissing', () {
    expect(
      () => gateway.listRemoteModelIds('nope'),
      throwsA(isA<EngineException>()
          .having((e) => e.code, 'code', 'errProviderMissing')),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handler;
  _FakeAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? _,
          Future<void>? __) async =>
      handler(options);
  @override
  void close({bool force = false}) {}
}
```

先看 `test/engine/` 里是否已有 mock dio 的既有模式（grep `httpClientAdapter`），有则沿用既有写法替换 `_FakeAdapter`。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/engine/remote_model_candidates_test.dart`
Expected: FAIL（`listRemoteModelIds` 未定义）

- [ ] **Step 3: 实现**

`gateway.dart` 抽象类 `ProviderGateway` 里（`cancelVideo` 之后）加：

```dart
  /// GET {baseUrl}/models，仅返回远端模型 ID 候选（不写库；spec §5 第 5 条）。
  Future<List<String>> listRemoteModelIds(String providerId) =>
      Future.error(UnsupportedError('此网关不支持模型列表拉取'));
```

`HttpProviderGateway` 类内加实现：

```dart
  @override
  Future<List<String>> listRemoteModelIds(String providerId) async {
    final rows = db.select(
        'SELECT id, inputValues FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
        [providerId]);
    if (rows.isEmpty) {
      throw EngineException(errProviderMissing, {'providerId': providerId});
    }
    final inputValues = jsonDecode(
            (rows.first['inputValues'] as String?)?.trim().isNotEmpty == true
                ? rows.first['inputValues'] as String
                : '{}') as Map;
    final baseUrl = (inputValues['baseUrl'] ?? '').toString().trimRight();
    final credentialRef = (inputValues['credentialRef'] ??
            providerCredentialRef(providerId))
        .toString();
    var apiKey = '';
    try {
      apiKey = await credentials.read(credentialRef) ?? '';
    } catch (_) {}
    try {
      final resp = await dio.get<dynamic>(
        '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/models',
        options: Options(headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        }),
      );
      final body = resp.data;
      final list = body is Map ? body['data'] : body;
      if (list is! List) {
        throw EngineException(errLlmFormat, {'reason': '/models 响应缺 data 数组'});
      }
      return [
        for (final item in list.whereType<Map>())
          if ((item['id'] ?? '').toString().trim().isNotEmpty)
            (item['id'] as Object).toString(),
      ];
    } on DioException catch (e) {
      throw EngineException(errNetwork, {
        'op': 'listRemoteModels',
        'status': e.response?.statusCode,
        'message': e.message,
      });
    }
  }
```

（`gateway.dart` 已 import dio/sqlite3/credentials/util——若 `jsonDecode` 未引入则补 `import 'dart:convert';`。）

`engine.dart` 在 `saveProviderModels` 附近加转发：

```dart
  /// /models 拉取候选（只出列表不写库，UI 定 kind 后走 saveProviderModels）。
  Future<List<String>> fetchProviderModelCandidates(String providerId) {
    _mustProvider(providerId);
    return gateway.listRemoteModelIds(providerId);
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/engine/remote_model_candidates_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 5: analyze + commit**

```bash
flutter analyze lib/src/engine/providers/gateway.dart lib/src/engine/engine.dart test/engine/remote_model_candidates_test.dart
git add lib/src/engine/providers/gateway.dart lib/src/engine/engine.dart test/engine/remote_model_candidates_test.dart
git commit -m "feat(engine): /models 拉取模型候选（只出候选不写库）"
```

---

### Task 4: 三语文案 + 预设画廊

**Files:**
- Modify: `app/lib/l10n/app_zh.arb`、`app/lib/l10n/app_en.arb`、`app/lib/l10n/app_ja.arb`
- Create: `app/lib/src/screens/provider_preset_gallery.dart`
- Test: `app/test/widgets/provider_preset_gallery_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `kProviderPresets`/`ProviderPreset`。
- Produces: `Future<String?> showProviderPresetGallery(BuildContext context, {required Set<String> existingProviderIds})`——返回选中的 presetId；返回 `'custom'` 表示走自定义；返回 null 表示取消。已存在实例的卡显示"已添加"角标，点击返回该 presetId 并由调用方进编辑（Task 5 处理）。

- [ ] **Step 1: 加 l10n 键（三语）**

`app_zh.arb` 追加（模板文件，跑 gen-l10n 后 `untranslated.txt` 必须为空）：

```json
  "presetGalleryTitle": "选择供应商",
  "presetGalleryCustom": "自定义",
  "presetGalleryCustomDesc": "手动填写名称、地址与密钥",
  "presetCompatMode": "兼容模式",
  "presetAdded": "已添加",
  "presetOpenPlatform": "前往平台",
  "presetKindText": "文字",
  "presetKindImage": "图片",
  "presetKindVideo": "视频",
  "presetKindTts": "语音",
  "presetFetchModels": "从 API 拉取模型",
  "presetUncategorized": "未分类",
  "presetKindRequired": "请先为勾选的模型选择类型",
  "presetFetchEmpty": "未拉取到新模型",
  "presetAddCandidates": "加入清单",
  "presetProviderExists": "该供应商已添加，请直接编辑"
```

`app_en.arb` 追加：

```json
  "presetGalleryTitle": "Choose a provider",
  "presetGalleryCustom": "Custom",
  "presetGalleryCustomDesc": "Enter name, base URL and key manually",
  "presetCompatMode": "Compat mode",
  "presetAdded": "Added",
  "presetOpenPlatform": "Open platform",
  "presetKindText": "Text",
  "presetKindImage": "Image",
  "presetKindVideo": "Video",
  "presetKindTts": "Speech",
  "presetFetchModels": "Fetch models from API",
  "presetUncategorized": "Uncategorized",
  "presetKindRequired": "Choose a type for each checked model first",
  "presetFetchEmpty": "No new models found",
  "presetAddCandidates": "Add to list",
  "presetProviderExists": "This provider is already added — edit it instead"
```

`app_ja.arb` 追加：

```json
  "presetGalleryTitle": "プロバイダーを選択",
  "presetGalleryCustom": "カスタム",
  "presetGalleryCustomDesc": "名称・URL・キーを手動入力",
  "presetCompatMode": "互換モード",
  "presetAdded": "追加済み",
  "presetOpenPlatform": "プラットフォームへ",
  "presetKindText": "テキスト",
  "presetKindImage": "画像",
  "presetKindVideo": "動画",
  "presetKindTts": "音声",
  "presetFetchModels": "APIからモデルを取得",
  "presetUncategorized": "未分類",
  "presetKindRequired": "先にチェックしたモデルの種類を選択してください",
  "presetFetchEmpty": "新しいモデルはありません",
  "presetAddCandidates": "リストに追加",
  "presetProviderExists": "このプロバイダーは追加済みです。編集してください"
```

Run: `flutter gen-l10n`，然后 `cat untranslated.txt`——Expected: 空（三语齐）。

- [ ] **Step 2: 写失败 widget 测试**

```dart
// app/test/widgets/provider_preset_gallery_test.dart
import 'package:dramaflow/src/screens/provider_preset_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required Set<String> existing, required void Function(String?) onResult}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open-gallery'),
            onPressed: () async {
              onResult(await showProviderPresetGallery(context,
                  existingProviderIds: existing));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('手机宽度：12 预设卡+自定义卡齐全，兼容模式角标只在三家', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(_host(existing: {}, onResult: (v) => picked = v));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preset-card-openai')), findsOneWidget);
    expect(find.byKey(const Key('preset-card-custom')), findsOneWidget);
    // 12 家全渲染（滚动到底确认最后一家）
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-azt')), 300);
    expect(find.byKey(const Key('preset-card-azt')), findsOneWidget);
    // 兼容模式角标恰好 3 个
    expect(find.text('兼容模式'), findsNWidgets(3));

    await tester.tap(find.byKey(const Key('preset-card-openai')));
    await tester.pumpAndSettle();
    expect(picked, 'openai');
  });

  testWidgets('已存在实例的卡显示已添加角标', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(existing: {'volcengine'}, onResult: (_) {}));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('自定义卡返回 custom', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(_host(existing: {}, onResult: (v) => picked = v));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-custom')), 300);
    await tester.tap(find.byKey(const Key('preset-card-custom')));
    await tester.pumpAndSettle();
    expect(picked, 'custom');
  });
}
```

实现前 grep 现有 widget 测试确认 `AppLocalizations` 的 import 路径（`flutter_gen/gen_l10n/` 还是项目内路径），以现有测试为准。

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/widgets/provider_preset_gallery_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 4: 实现画廊**

```dart
// app/lib/src/screens/provider_preset_gallery.dart
import 'package:flutter/material.dart';

import '../engine/provider_presets.dart';
import '../theme.dart';
import '../widgets/df_adaptive_dialog.dart';
import 'l10n_ext.dart';

/// 预设画廊（spec §5 第 1 条）：返回选中的 presetId；'custom' 表示走自定义；null 取消。
Future<String?> showProviderPresetGallery(
  BuildContext context, {
  required Set<String> existingProviderIds,
}) {
  final l10n = context.l10n;
  return showDFAdaptiveDialog<String>(
    context,
    title: l10n.presetGalleryTitle,
    desktopWidthFactor: .72,
    builder: (context) => _PresetGalleryBody(existing: existingProviderIds),
  );
}

class _PresetGalleryBody extends StatelessWidget {
  final Set<String> existing;
  const _PresetGalleryBody({required this.existing});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600 ? 2 : (width < 1100 ? 3 : 4);
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: columns,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        for (final p in kProviderPresets)
          _PresetCard(preset: p, added: existing.contains(p.id)),
        const _CustomCard(),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final ProviderPreset preset;
  final bool added;
  const _PresetCard({required this.preset, required this.added});

  @override
  Widget build(BuildContext context) {
    final df = DFTheme.of(context);
    final l10n = context.l10n;
    final kinds = {for (final m in preset.models) m.kind};
    String kindLabel(String k) => switch (k) {
          'image' => l10n.presetKindImage,
          'video' => l10n.presetKindVideo,
          'tts' => l10n.presetKindTts,
          _ => l10n.presetKindText,
        };
    return InkWell(
      key: Key('preset-card-${preset.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop(preset.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 14,
                child: Text(preset.name.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 13)),
              ),
              const Spacer(),
              if (added)
                _Badge(text: l10n.presetAdded)
              else if (preset.compatMode)
                _Badge(text: l10n.presetCompatMode),
            ]),
            const SizedBox(height: 8),
            Text(preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final k in kinds)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: df.surfaceMuted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(kindLabel(k),
                      style: TextStyle(fontSize: 11, color: df.textSecondary)),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _CustomCard extends StatelessWidget {
  const _CustomCard();

  @override
  Widget build(BuildContext context) {
    final df = DFTheme.of(context);
    final l10n = context.l10n;
    return InkWell(
      key: const Key('preset-card-custom'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop('custom'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: df.textSecondary),
            const SizedBox(height: 6),
            Text(l10n.presetGalleryCustom,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(l10n.presetGalleryCustomDesc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: df.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final df = DFTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: df.surfaceMuted,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: df.textSecondary)),
    );
  }
}
```

实现前核对：`DFTheme.of(context)` 的真实字段名（`stroke`/`surfaceMuted`/`textSecondary`/`textTertiary`）以 `app/lib/src/theme.dart` 为准，不存在的字段换成最接近的既有 token；`l10n_ext.dart`（`context.l10n` 扩展）的真实路径以 settings_screen.dart 的 import 为准。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/widgets/provider_preset_gallery_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 6: analyze + commit**

```bash
flutter analyze lib/src/screens/provider_preset_gallery.dart test/widgets/provider_preset_gallery_test.dart
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/src/screens/provider_preset_gallery.dart test/widgets/provider_preset_gallery_test.dart
git commit -m "feat(ui): 供应商预设画廊（12+自定义，兼容模式/已添加角标，三语）"
```

（若 `flutter gen-l10n` 产物文件在 git 内也被改动，一并 `git add` 生成的 `app_localizations*.dart`。）

---

### Task 5: 预填表单 + 设置页接线

**Files:**
- Create: `app/lib/src/screens/provider_preset_form.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`（`_openCreateProviderDialog`，约 :462）
- Test: `app/test/widgets/provider_preset_form_test.dart`

**Interfaces:**
- Consumes: Task 1 `providerPresetById`；Task 2 `createProviderFromPreset`；Task 4 `showProviderPresetGallery`。
- Produces: `Future<bool> showProviderPresetForm(BuildContext context, WidgetRef ref, {required String presetId})`——true 表示已创建成功。settings 的添加流程变为：画廊 → presetId 进预填表单 / 'custom' 进现有 `_ProviderFormDialog` / 已添加的 presetId 进现有编辑弹窗。

- [ ] **Step 1: 写失败 widget 测试**

```dart
// app/test/widgets/provider_preset_form_test.dart
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/provider_preset_form.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Engine engine;

  setUp(() {
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore('/tmp/df-preset-form-test-media'),
      gateway: _NoopGateway(),
      config: EngineConfig(db, isMobile: false),
    );
  });

  tearDown(() => engine.dispose());

  Widget host() => ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                key: const Key('open-form'),
                onPressed: () => showProviderPresetForm(context, ref,
                    presetId: 'deepseek'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('预填正确：BaseURL/模型清单来自目录，Key 框遮蔽可切换', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-form')));
    await tester.pumpAndSettle();

    expect(find.text('https://api.deepseek.com/v1'), findsOneWidget);
    expect(find.text('deepseek-chat'), findsOneWidget);
    expect(find.text('deepseek-reasoner'), findsOneWidget);

    final keyField = tester.widget<TextField>(
        find.byKey(const Key('preset-form-apikey')));
    expect(keyField.obscureText, isTrue);
    await tester.tap(find.byKey(const Key('preset-form-apikey-toggle')));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-apikey')))
            .obscureText,
        isFalse);
  });

  testWidgets('保存：取消勾选一个模型后创建，引擎真实落库', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-form')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('preset-form-apikey')), 'sk-test');
    await tester.tap(find.byKey(const Key('preset-model-deepseek-reasoner')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('preset-form-save')));
    await tester.pumpAndSettle();

    final models = await engine.listProviderModels('deepseek');
    expect(models.map((m) => m.modelId).toList(), ['deepseek-chat']);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/widgets/provider_preset_form_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现表单**

```dart
// app/lib/src/screens/provider_preset_form.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/provider_presets.dart';
import '../state/providers.dart';
import '../widgets/df_adaptive_dialog.dart';
import 'l10n_ext.dart';

/// 预设预填表单（spec §5 第 2 条）。返回 true = 创建成功。
Future<bool> showProviderPresetForm(
  BuildContext context,
  WidgetRef ref, {
  required String presetId,
}) async {
  final preset = providerPresetById(presetId);
  if (preset == null) return false;
  final created = await showDFAdaptiveDialog<bool>(
    context,
    title: preset.name,
    desktopWidthFactor: .5,
    builder: (context) => _PresetFormBody(preset: preset),
  );
  return created == true;
}

class _PresetFormBody extends ConsumerStatefulWidget {
  final ProviderPreset preset;
  const _PresetFormBody({required this.preset});

  @override
  ConsumerState<_PresetFormBody> createState() => _PresetFormBodyState();
}

class _PresetFormBodyState extends ConsumerState<_PresetFormBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.preset.name);
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.preset.baseUrl);
  final TextEditingController _apiKey = TextEditingController();
  late final Set<String> _selected = {
    for (final m in widget.preset.models) m.modelId,
  };
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(engineProvider).createProviderFromPreset(
            presetId: widget.preset.id,
            apiKey: _apiKey.text,
            selectedModelIds: _selected.toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.settingsProviderName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            decoration: const InputDecoration(labelText: 'Base URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('preset-form-apikey'),
            controller: _apiKey,
            autofocus: true,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API Key',
              suffixIcon: IconButton(
                key: const Key('preset-form-apikey-toggle'),
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l10n.presetOpenPlatform),
              onPressed: () =>
                  launchUrl(Uri.parse(widget.preset.keyUrl)),
            ),
          ),
          const Divider(height: 24),
          for (final m in widget.preset.models)
            CheckboxListTile(
              key: Key('preset-model-${m.modelId}'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(m.modelId),
              title: Text(m.modelId,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(m.modelId);
                } else {
                  _selected.remove(m.modelId);
                }
              }),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('preset-form-save'),
            onPressed: _saving || _selected.isEmpty ? null : _save,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}
```

实现前核对：`l10n.settingsProviderName`/`l10n.commonSave` 的真实键名以现有 `_ProviderFormDialog` 用的键为准（grep settings_screen.dart），不存在就换成它实际用的键。

- [ ] **Step 4: 接线 settings_screen.dart**

`_openCreateProviderDialog`（约 :462）改为：

```dart
  Future<void> _openCreateProviderDialog() async {
    final providers = await ref.read(engineProvider).listProviders();
    if (!mounted) return;
    final picked = await showProviderPresetGallery(context,
        existingProviderIds: {for (final p in providers) p.id});
    if (picked == null || !mounted) return;

    if (picked == 'custom') {
      final result = await showDialog<_ProviderFormResult>(
        context: context,
        builder: (_) => const _ProviderFormDialog(),
      );
      if (result == null || !mounted) return;
      final l10n = context.l10n;
      await runAction(context, ref, () async {
        await ref.read(engineProvider).createProvider(
              name: result.name,
              protocol: result.protocol,
              baseUrl: result.baseUrl,
              apiKey: result.apiKey,
            );
      }, successMessage: l10n.settingsProviderAdded);
      if (!mounted) return;
      _invalidateProvidersAndBindings();
      return;
    }

    final existing =
        providers.where((p) => p.id == picked).toList();
    if (existing.isNotEmpty) {
      await _openEditProviderDialog(existing.first);
      return;
    }

    final created =
        await showProviderPresetForm(context, ref, presetId: picked);
    if (created && mounted) _invalidateProvidersAndBindings();
  }
```

顶部加 import：`import 'provider_preset_gallery.dart';`、`import 'provider_preset_form.dart';`。
实现前核对引擎取供应商列表的真实方法名（grep settings_screen.dart 现在怎么拿 `List<ProviderInfo>`——若走 riverpod provider 而非 `listProviders()`，改用同款读法）。

- [ ] **Step 5: 跑测试确认通过 + 设置页回归**

Run: `flutter test test/widgets/provider_preset_form_test.dart test/widgets/settings_screen_test.dart`
Expected: 全 PASS——settings_screen_test 里现有"添加供应商"用例走的是 `_ProviderFormDialog` 直开路径；若其点击"添加供应商"按钮后因画廊插入而断言失败，修改该用例为：点按钮 → 画廊出现 → 点 `preset-card-custom` → 后续断言不变（这是 spec 规定的新流程，自定义表单本身零改动）。

- [ ] **Step 6: analyze + commit**

```bash
flutter analyze lib/src/screens/provider_preset_form.dart lib/src/screens/settings_screen.dart test/widgets/provider_preset_form_test.dart
git add lib/src/screens/provider_preset_form.dart lib/src/screens/settings_screen.dart test/widgets/provider_preset_form_test.dart test/widgets/settings_screen_test.dart
git commit -m "feat(ui): 预设预填表单+设置页画廊接线（原子创建，已添加进编辑）"
```

---

### Task 6: 模型管理"从 API 拉取"候选合并

**Files:**
- Modify: `app/lib/src/screens/settings_screen.dart`（`_ProviderModelsEditorState`，约 :2145）
- Test: 追加用例到 `app/test/widgets/settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 `Engine.fetchProviderModelCandidates`；Task 1 `presetModelKinds`。
- Produces: 模型管理弹窗新增 `presetFetchModels` 按钮 → 候选底部弹层：每个候选一行（勾选框 + ID + kind 下拉，目录内 ID 预填 kind，未知 ID 显示"未分类"占位）；"加入清单"仅将**已勾选且已定 kind** 的候选加为 `_ModelDraft`（enabled=false）；已存在于草稿的 ID 不出现在候选里。

- [ ] **Step 1: 写失败测试（追加到 settings_screen_test.dart 末尾）**

```dart
  testWidgets('模型管理：从 API 拉取候选，未分类必须定 kind 才能加入', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // harness：沿用本文件既有 setUp 的 engine；把 gateway 换成能答 /models 的 fake
    // （在本文件顶部加：）
    // class _ModelsGateway extends _NoopGateway {
    //   @override
    //   Future<List<String>> listRemoteModelIds(String providerId) async =>
    //       ['deepseek-chat', 'brand-new-model'];
    // }
    // 并在本用例里用 _ModelsGateway 构造 engine（复制本文件既有 engine 构造行，仅换 gateway）。
    final provider = await engine.createProviderFromPreset(
        presetId: 'deepseek', apiKey: 'k', selectedModelIds: ['deepseek-chat']);
    await pumpSettings(tester); // 本文件既有的泵设置页 helper，名字以文件内为准
    // 打开该供应商的模型管理（沿用本文件既有"模型管理"用例的打开手法）
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('从 API 拉取模型'));
    await tester.pumpAndSettle();

    // deepseek-chat 已在清单 → 候选只剩 brand-new-model，且是未分类
    expect(find.text('brand-new-model'), findsOneWidget);
    expect(find.text('deepseek-chat'), findsAtLeastNWidgets(1)); // 草稿区原有
    expect(find.text('未分类'), findsOneWidget);

    // 不定 kind 直接勾选加入 → 报错提示
    await tester.tap(find.byKey(const Key('candidate-check-brand-new-model')));
    await tester.pump();
    await tester.tap(find.text('加入清单'));
    await tester.pump();
    expect(find.text('请先为勾选的模型选择类型'), findsOneWidget);

    // 定 kind 后加入成功，且新草稿默认禁用
    await tester.tap(find.byKey(const Key('candidate-kind-brand-new-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入清单'));
    await tester.pumpAndSettle();
    expect(find.text('brand-new-model'), findsAtLeastNWidgets(1));
    // 新草稿 enabled=false 的断言：保存后查引擎
    // （保存按钮名与既有模型管理用例一致）
  });
```

以上代码块中两处"以文件内为准"的 helper/按钮名，动手前先读 `settings_screen_test.dart` 既有"模型管理"用例（:225 附近）拿到真实写法后落实——断言语义不得削弱。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/widgets/settings_screen_test.dart --plain-name 从 API 拉取`
Expected: FAIL（按钮不存在）

- [ ] **Step 3: 实现候选弹层**

`_ProviderModelsEditorState` 里加（完整逻辑，UI 结构随现有编辑器风格微调）：

```dart
  Future<void> _fetchCandidates() async {
    final l10n = context.l10n;
    List<String> ids;
    try {
      ids = await ref
          .read(engineProvider)
          .fetchProviderModelCandidates(widget.provider.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    final known = {for (final d in _drafts) d.modelIdController.text.trim()};
    final candidates = [
      for (final id in ids)
        if (!known.contains(id)) id,
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.presetFetchEmpty)));
      return;
    }
    final kinds = presetModelKinds(widget.provider.id);
    final picked = await showModalBottomSheet<List<(String, String)>>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CandidateSheet(candidates: candidates, knownKinds: kinds),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final (id, kind) in picked) {
        final draft = _ModelDraft.empty();
        draft.modelIdController.text = id;
        draft.labelController.text = id;
        draft.kind = kind;
        draft.enabled = false; // spec：候选默认禁用，用户手动启用
        _drafts.add(draft);
      }
    });
  }
```

`_ModelDraft` 的字段名（`modelIdController`/`labelController`/`kind`/`enabled`）以 :2283 的真实定义为准替换。`_CandidateSheet` 新私有 widget：`ListView` 每行 `Checkbox + Text(id, ellipsis) + DropdownButton<String>(kind, hint: 未分类)`（key 分别为 `candidate-check-<id>`/`candidate-kind-<id>`，目录内 ID 用 `knownKinds[id]` 预填），底部 `FilledButton(加入清单)`——点击时若有勾选项未定 kind，行内显示 `presetKindRequired` 错误文本不关闭；全部合法则 `Navigator.pop` 已勾选的 `(id, kind)` 列表。按钮放在编辑器工具行 `_addModel` 按钮旁：`TextButton.icon(icon: Icons.cloud_download_outlined, label: Text(l10n.presetFetchModels), onPressed: _fetchCandidates)`。

- [ ] **Step 4: 跑测试确认通过 + 全文件回归**

Run: `flutter test test/widgets/settings_screen_test.dart`
Expected: 全 PASS（新用例 + 既有全部）

- [ ] **Step 5: analyze + commit**

```bash
flutter analyze lib/src/screens/settings_screen.dart test/widgets/settings_screen_test.dart
git add lib/src/screens/settings_screen.dart test/widgets/settings_screen_test.dart
git commit -m "feat(ui): 模型管理从 API 拉取候选（未分类需定 kind，默认禁用）"
```

---

### Task 7: 全量收尾 + 人工验收清单

**Files:**
- Create: `docs/parity/provider-presets-acceptance.md`
- Modify: `.superpowers/sdd/progress.md`（追加台账条目）

- [ ] **Step 1: 全量回归**

```bash
flutter analyze
flutter test
```
Expected: analyze 0 issues；全套件 PASS（此前基线 613 + 本计划新增用例）。任何失败先修再进 Step 2。

- [ ] **Step 2: 写人工验收清单**

`docs/parity/provider-presets-acceptance.md`，内容为 spec §4 验收标准的逐家执行表：

```markdown
# 供应商预设人工验收清单（需真实 Key，不进默认 CI）

按 spec 2026-07-18-provider-presets-design.md §4：每家过 4 项——
①普通文本生成；②强制工具调用/结构化 JSON；③图片生成与编辑（仅声称有图片角标的家）；④GET /models。
记录格式：日期 + 通过/失败 + 失败摘要。①②任一失败 = 该家不可标"可用"；③失败 = 去掉该家图片角标；④失败 = 在 preset 备注"该家不支持 /models"。

| preset | ①文本 | ②工具/JSON | ③图片 | ④/models | 记录 |
|---|---|---|---|---|---|
| openai | 待验 | 待验 | 待验(gpt-image-2) | 待验 | |
| anthropic（兼容模式） | 待验 | 待验 | 无图片 | 待验 | |
| gemini（兼容模式） | 待验 | 待验 | 无图片(协议后补) | 待验 | |
| xai（兼容模式） | 待验 | 待验 | 无图片 | 待验 | |
| openrouter | 待验 | 待验 | 无图片 | 待验 | |
| siliconflow | 待验 | 待验 | 待验(Kolors) | 待验 | |
| deepseek | 待验 | 待验 | 无图片 | 待验 | |
| moonshot | 待验 | 待验 | 无图片 | 待验 | |
| zhipu | 待验 | 待验 | 待验(cogview-4) | 待验 | |
| dashscope | 待验 | 待验 | 图片过兼容层待验证，不通则不预置 | 待验 | |
| volcengine | 已有链路（今晚 e2e 已验） | 已有链路 | 已有链路 | 待验 | |
| azt | 已有链路（今晚 e2e 已验） | 已有链路 | 已有链路 | 已验(今晚) | |
```

"待验"是这份验收文档的合法状态标记（验收由用户持真实 Key 执行），不属于计划禁止的占位符。

- [ ] **Step 3: 更新台账 + commit**

`.superpowers/sdd/progress.md` 末尾追加一段：本计划 7 个任务的完成记录（commit 号 + 一句话 + 测试计数），格式沿用文件既有条目。

```bash
git add docs/parity/provider-presets-acceptance.md .superpowers/sdd/progress.md
git commit -m "docs: 供应商预设人工验收清单 + 台账"
```

---

## Self-Review 记录（计划作者已执行）

1. **Spec 覆盖**：§3 数据模型+硬门→Task 1；§5.1 画廊→Task 4；§5.2 预填表单/obscure/前往平台→Task 5；§5.3 重复防护/已添加进编辑→Task 2（引擎）+ Task 5 Step 4（UI）；§5.4 自定义回归→Task 5 Step 5；§5.5 拉取候选/未分类→Task 3+6；§6 三个引擎改动→Task 2/3；§7 测试计划全部落到各任务 + Task 7；§4 验收标准→Task 7 人工清单。兼容模式标注→Task 1 字段 + Task 4 角标。三语→Task 4 Step 1。无遗漏。
2. **占位符扫描**：代码块均为完整实现；"以文件内为准核对后替换"的点（DFTheme 字段名、l10n 键名、_ModelDraft 字段名、providers 列表读法、AppLocalizations import 路径）是对既有私有代码的核对指令并给出了核对位置，非空白占位。验收清单的"待验"为文档语义状态。
3. **类型一致性**：`createProviderFromPreset({presetId, apiKey, selectedModelIds})` 在 Task 2 定义、Task 5/6 测试同签名调用；`fetchProviderModelCandidates(String)` Task 3 定义、Task 6 调用；`showProviderPresetGallery(context, {existingProviderIds})` Task 4 定义、Task 5 调用；`presetModelKinds` Task 1 定义、Task 6 调用。一致。
