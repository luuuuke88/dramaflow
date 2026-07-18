# 供应商预设体系 Implementation Plan（v2，吸收 5+1 条评审）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 预设画廊式添加供应商——12 家预设（含 OpenAI/Claude/Gemini/Grok 国际线）一键预填，原子创建防 Key 覆盖，`/models` 拉取候选。

**Architecture:** 目录常量（`provider_presets.dart`，同时成为种子的单一事实来源）+ 一个新引擎 API（`createProviderFromPreset`：先 INSERT 抢占、后写凭证、失败删行——结构性消除并发删 Key）+ 一个新网关方法（`listRemoteModelIds`，只出候选不写库）+ 设置页画廊/预填表单/候选合并三段 UI。数据库 schema、协议分发、现有 `createProvider`/`saveProviderModels` 零改动。

**Tech Stack:** Flutter/Dart，sqlite3，dio，flutter_secure_storage（经 `CredentialStore`），riverpod，url_launcher，现有 l10n（zh/en/ja）。

**Spec:** `docs/superpowers/specs/2026-07-18-provider-presets-design.md`（唯一需求来源，冲突以 spec 为准）

**v2 变更记录（对 `cf41f32` 评审的回应）**：①原子创建改"INSERT 先行抢占（SELECT+INSERT 连续同步无 await，单 isolate 无插入窗口；PK 冲突→errProviderExists）→ 凭证后写 → 凭证失败删行"，并发场景下不存在"删掉别人凭证"的代码路径，补并发测试；②回滚测试改用 `BEFORE INSERT` 触发器与注入失败的 `CredentialStore`，真实走到目标分支；③`createProviderFromPreset` 增加 `name/baseUrl` 覆盖参数，表单可编辑字段真实生效；④volcengine 预设对齐真实种子（`doubao-seedance-2-0-mini-260615` + Mini capabilities），种子改为从目录构建（单一定义），`Engine.boot` 对照测试锁漂移；⑤Task 6 全量代码化（真实 `_ModelDraft` 字段名 `modelId`/`label`/`kind`/`enabled`，完整 `_CandidateSheet` 实现，真实测试 harness）；⑥新增 `acceptanceVerified` 字段与"未验证"角标——未过人工验收的预设上架但明示未验证，azt 的"已验"在验收表中附证据。

## Global Constraints

- 模型 ID 硬门：任何模型 ID 未经当日对照 `sourceUrl` 核实（或经该家真实 API 调用验证）**不得写入常量**；核实后必须填 `verifiedAt`（'YYYY-MM-DD'）。目录单测断言两字段非空。
- 许可证红线：**不复制 ToonFlow `data/vendor/*.ts` 任何代码或文案**。
- 兼容模式诚实标注：anthropic/gemini/xai 三家 `compatMode: true`，画廊显示"兼容模式"角标。
- 验收诚实标注：`acceptanceVerified` 仅在人工验收表（Task 7）留下证据行后方可置 true；false 的预设画廊显示"未验证"角标。初始仅 azt 为 true（证据见 Task 7）。
- 新 UI 文案一律三语（zh/en/ja）。模板 arb 是 `app/lib/l10n/app_zh.arb`，改后跑 `flutter gen-l10n`，`untranslated.txt` 必须为空。
- 原子创建语义：重复创建**不写凭证**（结构上：凭证写在 INSERT 成功之后）；凭证写失败删除刚 INSERT 的行；无"建了供应商没模型"中间态。
- 拉取只出候选：`/models` 结果不直接写库；未知 ID 标"未分类"默认禁用，用户定 kind 才能保存，绝不猜成 text。
- 每预设一实例；"已添加"进编辑；多账号走"自定义"。
- 默认种子**内容**不变（azt 桌面 + volcengine；实现重构为从目录构建，逐字段一致由 `Engine.boot` 对照测试锁定）。
- git 纪律：新提交不 amend、`git add` 逐个文件、不 `--no-verify`。
- 所有命令在 `/Users/luke/Documents/aivideo/dramaflow/app` 下执行；每任务收尾 `flutter analyze <改动文件>` 0 issues。

## 已核实的代码事实（实现者直接引用，不必再查）

- `Engine` 构造器（engine.dart:366）：`Engine({required db, required media, required gateway, required config, CredentialStore? credentials, ...})`——credentials 可注入。
- 种子只在 `Engine.boot()`（engine.dart:395-404）里跑；测试用裸 `Engine(...)` 构造不种子。
- volcengine 种子真值（engine.dart:~488-508）：`doubao-seed-1-6-250615`(text)、`doubao-seedream-4-0-250828`(image)、`doubao-seedance-2-0-mini-260615`(video, `_legacySeedanceMiniCapabilities()`)；azt 种子（桌面 only）：gpt-5.5/gpt-5.4/gpt-5.4-mini(text)+gpt-image-2(image)。
- `_legacySeedanceMiniCapabilities()` 在 engine.dart:94-106，依赖 `VideoMode`（video_request.dart）；engine.dart:163（`_seedSeedanceVideoProfiles`）也调用它。
- `_ModelDraft`（settings_screen.dart:2283）：`TextEditingController modelId`、`TextEditingController label`、`String kind`、`bool enabled`、`Map<String,dynamic> capabilities`；`_ModelDraft.empty()` 是 kind:'text'/enabled:true。
- `ProviderModelInfo`（api/models.dart:544）有 `enabled` 字段。
- l10n：`import 'package:dramaflow/l10n/app_localizations.dart'`；`context.l10n` 来自 `../util/l10n_ext.dart`；主题 token 来自 `../theme/theme.dart` 的 `context.df`（`DFColors`，已验字段：`stroke`/`strokeStrong`/`textSecondary`/`textTertiary`）。
- settings_screen_test.dart harness：`setUp` 建 `engine`（`_NoopGateway`、`EngineConfig(db, isMobile: true)`、`MediaStore(p.join(dir.path,'media'))`）；`app()` helper 包 ProviderScope+MaterialApp(home: SettingsScreen)；`_selectSection(tester, '供应商')` 切分区；模型管理经 `find.byTooltip('模型管理')` 打开，"添加模型"/"保存"是真实按钮文案；供应商列表读法 `engine.listProviders()`。
- 现有"添加供应商"用例在 `移动端设置页：外观语言、供应商与提示词入口可用` 内：点"添加供应商"→ 直接 3 个 TextField。Task 5 需把它改为：点按钮 → 画廊 → 点 `preset-card-custom` → 后续不变。

---

### Task 1: 预设目录常量（含种子单一化）+ 目录/防漂移单测

**Files:**
- Create: `app/lib/src/engine/provider_presets.dart`
- Modify: `app/lib/src/engine/engine.dart`（`_legacySeedanceMiniCapabilities` 移出为公共函数；`_seedDefaults` 的 azt/volcengine 模型清单改为从目录构建）
- Test: `app/test/engine/provider_presets_test.dart`

**Interfaces:**
- Produces: `class ProviderPreset`（含 `compatMode`/`sourceUrl`/`verifiedAt`/`acceptanceVerified`）、`class PresetModel`、`final List<ProviderPreset> kProviderPresets`（12 项，final 非 const——volcengine capabilities 来自函数调用）、`ProviderPreset? providerPresetById(String id)`、`Map<String, String> presetModelKinds(String presetId)`、`Map<String, Object?> seedanceMiniCapabilities()`（从 engine.dart 迁来，engine 内两处调用点改引此处）。

- [ ] **Step 1: 核实模型 ID（硬门）**

对 6 家"易变"供应商逐家 WebFetch sourceUrl 核对/修正候选模型，记录当日 `verifiedAt`。评审人已对当前官方文档确认的大方向：OpenAI GPT-5.6 系、Claude Sonnet 5/Opus 4.8、Gemini 3.5 Flash、Grok 4.5（来源：developers.openai.com/api/docs/models、platform.claude.com/docs/en/about-claude/models/model-ids-and-versions、ai.google.dev/gemini-api/docs/openai、docs.x.ai/developers/models）——实施日仍须复核精确 ID 串写法。azt/volcengine 以仓库种子为真值（上面"已核实事实"）。WebFetch 失败回退：用该家 `GET {baseUrl}/models` 真实调用核实；仍不可得则该家只保留有把握的 1 个旗舰 ID，不臆造。

- [ ] **Step 2: 写失败测试**

```dart
// app/test/engine/provider_presets_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/provider_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('目录：12 家 id 唯一且必填字段完备（含硬门字段）', () {
    expect(kProviderPresets.length, 12);
    expect(kProviderPresets.map((p) => p.id).toSet().length, 12);
    for (final p in kProviderPresets) {
      expect(p.name.trim(), isNotEmpty);
      expect(p.keyUrl.trim(), isNotEmpty, reason: '${p.id} 缺 keyUrl');
      expect(p.sourceUrl.trim(), isNotEmpty, reason: '${p.id} 缺 sourceUrl（硬门）');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p.verifiedAt), isTrue,
          reason: '${p.id} verifiedAt 必须 YYYY-MM-DD（硬门）');
      expect({'openai_compatible', 'volcengine'}.contains(p.protocol), isTrue);
      final uri = Uri.parse(p.baseUrl);
      if (p.id == 'azt') {
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

  test('兼容模式恰为 anthropic/gemini/xai；acceptanceVerified 初始仅 azt', () {
    expect(
        kProviderPresets.where((p) => p.compatMode).map((p) => p.id).toSet(),
        {'anthropic', 'gemini', 'xai'});
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
      expect(inputValues['baseUrl'], preset.baseUrl, reason: '$presetId baseUrl 漂移');
      expect(inputValues['protocol'], preset.protocol);
      final seeded = (jsonDecode(row['models'] as String) as List)
          .whereType<Map>()
          .toList();
      expect(seeded.length, preset.models.length, reason: '$presetId 模型数漂移');
      for (var i = 0; i < seeded.length; i++) {
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
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/engine/provider_presets_test.dart`
Expected: FAIL（provider_presets.dart 不存在）

- [ ] **Step 4: 实现目录 + 种子单一化**

`app/lib/src/engine/provider_presets.dart`：

```dart
/// 供应商预设目录（spec §3-4），同时是 azt/volcengine 种子的单一事实来源
/// （engine.dart `_seedDefaults` 从这里构建，防漂移测试锁定）。
/// 内容独立编写；模型 ID 经 sourceUrl 核实后方可入列（verifiedAt 为核实日）。
/// 不得从 ToonFlow data/vendor/*.ts 复制任何代码或文案（许可证红线）。
import 'video_request.dart';

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
  final bool acceptanceVerified; // 仅当 Task 7 验收表有证据行才可 true
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
    this.acceptanceVerified = false,
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

/// modelId -> kind，供 /models 候选自动归类（spec §5 第 5 条）。
Map<String, String> presetModelKinds(String presetId) {
  final p = providerPresetById(presetId);
  if (p == null) return const {};
  return {for (final m in p.models) m.modelId: m.kind};
}

/// Seedance Mini 能力集：从 engine.dart `_legacySeedanceMiniCapabilities` 迁来的
/// 唯一定义（engine 的种子与 `_seedSeedanceVideoProfiles` 迁移均引用此处）。
Map<String, Object?> seedanceMiniCapabilities() => {
      'durations': [for (var i = 4; i <= 15; i++) i],
      'resolutions': ['480p', '720p'],
      'video': {
        'modes': [VideoMode.firstFrame.wireValue],
        'references': const {},
        'durations': [for (var i = 4; i <= 15; i++) i],
        'resolutions': ['480p', '720p'],
        'ratios': ['16:9', '9:16'],
        'audio': 'none',
        'promptTemplates': const {},
      },
    };

final kProviderPresets = <ProviderPreset>[
  const ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    sourceUrl: 'https://developers.openai.com/api/docs/models',
    verifiedAt: '2026-07-18', // Step 1 核实日，实施时以实际为准（下同）
    models: [
      PresetModel('gpt-5.6-sol', 'text'),
      PresetModel('gpt-5.6-terra', 'text'),
      PresetModel('gpt-5.6-luna', 'text'),
      PresetModel('gpt-image-2', 'image'),
    ],
  ),
  const ProviderPreset(
    id: 'anthropic',
    name: 'Claude (Anthropic)',
    baseUrl: 'https://api.anthropic.com/v1',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    compatMode: true,
    sourceUrl:
        'https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('claude-sonnet-5', 'text'),
      PresetModel('claude-opus-4-8', 'text'),
      PresetModel('claude-haiku-4-5', 'text'),
    ],
  ),
  const ProviderPreset(
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
  const ProviderPreset(
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
  const ProviderPreset(
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
  const ProviderPreset(
    id: 'siliconflow',
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    keyUrl: 'https://cloud.siliconflow.cn/account/ak',
    sourceUrl:
        'https://docs.siliconflow.cn/cn/api-reference/models/get-model-list',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('deepseek-ai/DeepSeek-V3.2', 'text'),
      PresetModel('Qwen/Qwen3-Max', 'text'),
      PresetModel('Kwai-Kolors/Kolors', 'image'),
    ],
  ),
  const ProviderPreset(
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
  const ProviderPreset(
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
  const ProviderPreset(
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
  const ProviderPreset(
    id: 'dashscope',
    name: '通义 Qwen',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1',
    sourceUrl: 'https://help.aliyun.com/zh/model-studio/models',
    verifiedAt: '2026-07-18',
    models: [
      PresetModel('qwen3-max', 'text'),
      PresetModel('qwen-plus', 'text'),
      // 图片是否过兼容层：spec §4 要求实施时验证，不通则不预置（Task 7 验收项）
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
      const PresetModel('doubao-seed-1-6-250615', 'text'),
      const PresetModel('doubao-seedream-4-0-250828', 'image'),
      PresetModel('doubao-seedance-2-0-mini-260615', 'video',
          capabilities: seedanceMiniCapabilities()),
    ],
  ),
  const ProviderPreset(
    id: 'azt',
    name: 'azt (本地 Codex OAuth)',
    baseUrl: 'http://127.0.0.1:8787/v1',
    keyUrl: 'http://127.0.0.1:8787',
    acceptanceVerified: true, // 证据：Task 7 验收表 azt 行（2026-07-18 e2e/smoke）
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

`engine.dart` 改动：
1. 顶部加 `import 'provider_presets.dart';`。
2. 删除 `_legacySeedanceMiniCapabilities`（:94-106），其两处调用（`_seedSeedanceVideoProfiles` 内 :163 附近与种子处）改调 `seedanceMiniCapabilities()`。
3. `_seedDefaults` 里 azt/volcengine 两段 `provider(...)` 调用的 `models:` 参数改为从目录构建：

```dart
      List<Map<String, Object?>> presetModels(String presetId) {
        final preset = providerPresetById(presetId)!;
        return [
          for (final m in preset.models)
            model(presetId, m.modelId, m.label, m.kind, m.capabilities),
        ];
      }

      if (!isMobile) {
        final azt = providerPresetById('azt')!;
        provider(
          id: azt.id,
          name: azt.id, // 种子历史名就是 'azt'，保持不变
          protocol: azt.protocol,
          baseUrl: azt.baseUrl,
          models: presetModels('azt'),
        );
      }

      final volc = providerPresetById('volcengine')!;
      provider(
        id: volc.id,
        name: volc.id, // 种子历史名 'volcengine'，保持不变
        protocol: volc.protocol,
        baseUrl: volc.baseUrl,
        models: presetModels('volcengine'),
      );
```

（注意：种子的 `name` 历史值是 `'azt'`/`'volcengine'`（小写 id），不是目录展示名"火山豆包"——保持种子内容零变化，防漂移测试只对 baseUrl/protocol/models 断言，不对 name 断言，画廊展示名走目录。）

- [ ] **Step 5: 跑测试确认通过 + 既有引擎回归**

Run: `flutter test test/engine/provider_presets_test.dart && flutter test test/engine/`
Expected: 新 4 test PASS；既有引擎套件全绿（种子内容未变）。

- [ ] **Step 6: analyze + commit**

```bash
flutter analyze lib/src/engine/provider_presets.dart lib/src/engine/engine.dart test/engine/provider_presets_test.dart
git add lib/src/engine/provider_presets.dart lib/src/engine/engine.dart test/engine/provider_presets_test.dart
git commit -m "feat(engine): 供应商预设目录（12 家，种子单一事实来源+防漂移锁）"
```

---

### Task 2: `createProviderFromPreset` 原子创建（INSERT 先行抢占）

**Files:**
- Modify: `app/lib/src/engine/errors.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Test: `app/test/engine/provider_preset_create_test.dart`

**Interfaces:**
- Consumes: Task 1 `providerPresetById`。
- Produces: `Future<ProviderInfo> createProviderFromPreset({required String presetId, required String apiKey, List<String>? selectedModelIds, String? name, String? baseUrl})`；错误码 `errProviderExists`。语义：未知 preset→`errProviderMissing`；选空模型→`errModelMissing`（任何写入之前）；已存在→`errProviderExists` 且不写凭证（含并发：SELECT+INSERT 连续同步、PK 冲突兜底）；凭证写失败→删除刚 INSERT 的行后 rethrow；`name`/`baseUrl` 缺省用目录值，传入则覆盖。

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
      selectedModelIds: ['deepseek-chat'],
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
    expect(models.map((m) => m.modelId).toList(), ['deepseek-chat']);
  });

  test('未知 presetId 抛 errProviderMissing；选空模型抛 errModelMissing 且零写入',
      () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    expect(
      () => engine.createProviderFromPreset(presetId: 'nope', apiKey: 'k'),
      throwsA(isA<EngineException>()
          .having((e) => e.code, 'code', 'errProviderMissing')),
    );
    await expectLater(
      engine.createProviderFromPreset(
          presetId: 'deepseek', apiKey: 'k', selectedModelIds: const []),
      throwsA(isA<EngineException>()
          .having((e) => e.code, 'code', 'errModelMissing')),
    );
    expect(await engine.listProviders(), isEmpty);
    expect(await engine.credentials.read(providerCredentialRef('deepseek')),
        isNull, reason: '校验失败不得写凭证');
  });

  test('P0 场景：重复创建抛 errProviderExists 且旧凭证一字节不动', () async {
    final engine = _engine(openEngineDb(':memory:'));
    addTearDown(engine.dispose);
    await engine.createProviderFromPreset(presetId: 'deepseek', apiKey: 'old-key');
    await expectLater(
      engine.createProviderFromPreset(presetId: 'deepseek', apiKey: 'NEW'),
      throwsA(isA<EngineException>()
          .having((e) => e.code, 'code', 'errProviderExists')),
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
        isNull, reason: '凭证写在 INSERT 之后，INSERT 失败凭证必须从未写过');
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
        isEmpty, reason: '凭证失败必须删除刚插入的供应商行');
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
    expect(failures.single.code, 'errProviderExists');
    final key = await engine.credentials.read(providerCredentialRef('xai'));
    expect(key, isNotNull, reason: '败者绝不能删掉胜者的凭证');
    expect({'key-A', 'key-B'}.contains(key), isTrue);
  });
}
```

（`engine.credentials` 若非公共字段，测试改为向 `_engine` 显式传入 `InMemoryCredentialStore` 实例并直接持有引用读取——两种写法二选一，断言不变。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/engine/provider_preset_create_test.dart`
Expected: FAIL（`createProviderFromPreset`/`errProviderExists` 未定义）

- [ ] **Step 3: 实现**

`errors.dart` 在 `errProviderMissing` 下一行加：

```dart
const errProviderExists = 'errProviderExists';
```

`engine.dart` 在 `createProvider` 之后加（文件顶部确认已有 `import 'package:sqlite3/sqlite3.dart';`——引擎本来就用 sqlite3）：

```dart
  /// 预设一键创建（spec §6，v2 语义）：
  /// 先校验与查重、再 INSERT（SELECT+INSERT 连续同步执行，单 isolate 下无
  /// 交错窗口；即便未来出现多写入方，PK 冲突兜底映射为 errProviderExists）、
  /// 凭证写在 INSERT 成功之后——重复/冲突路径在结构上不可能触碰既有凭证；
  /// 凭证写失败则删除刚插入的行，不留半成品。
  Future<ProviderInfo> createProviderFromPreset({
    required String presetId,
    required String apiKey,
    List<String>? selectedModelIds,
    String? name,
    String? baseUrl,
  }) async {
    final preset = providerPresetById(presetId);
    if (preset == null) {
      throw EngineException(errProviderMissing, {'presetId': presetId});
    }
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
    final effectiveName =
        (name?.trim().isNotEmpty ?? false) ? name!.trim() : preset.name;
    final effectiveBaseUrl =
        (baseUrl?.trim().isNotEmpty ?? false) ? baseUrl!.trim() : preset.baseUrl;
    final credentialRef = providerCredentialRef(preset.id);
    final createdAt = nowIso();

    // —— 抢占段（连续同步，无 await）——
    final existing =
        db.select('SELECT id FROM o_vendorConfig WHERE id=?', [preset.id]);
    if (existing.isNotEmpty) {
      throw EngineException(errProviderExists, {'providerId': preset.id});
    }
    try {
      db.execute(
        'INSERT INTO o_vendorConfig (id,enable,inputValues,models) VALUES (?,?,?,?)',
        [
          preset.id,
          1,
          jsonEncode({
            'name': effectiveName,
            'protocol': preset.protocol,
            'baseUrl': effectiveBaseUrl,
            'credentialRef': credentialRef,
            'presetId': preset.id,
            'createdAt': createdAt,
          }),
          jsonEncode(models),
        ],
      );
    } on SqliteException catch (e) {
      // 仅主键/唯一约束冲突（扩展码 1555/2067）映射为"已存在"；
      // 不可按 primary code 19 一刀切——RAISE(ABORT) 触发器等其它约束错误也报 19，
      // 那些必须原样上抛（Task 2 触发器测试依赖此语义）。
      if (e.extendedResultCode == 1555 || e.extendedResultCode == 2067) {
        throw EngineException(errProviderExists, {'providerId': preset.id});
      }
      rethrow;
    }
    // —— 抢占成功后才允许触碰凭证 ——
    final key = apiKey.trim();
    final wroteCredential = key.isNotEmpty;
    if (wroteCredential) {
      try {
        await credentials.write(credentialRef, key);
      } catch (_) {
        db.execute('DELETE FROM o_vendorConfig WHERE id=?', [preset.id]);
        rethrow;
      }
    }
    return ProviderInfo(
      id: preset.id,
      name: effectiveName,
      protocol: preset.protocol,
      baseUrl: effectiveBaseUrl,
      hasCredential: wroteCredential,
      enabled: true,
      createdAt: createdAt,
    );
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/engine/provider_preset_create_test.dart`
Expected: PASS（6 tests）

- [ ] **Step 5: 全量引擎回归 + commit**

```bash
flutter test test/engine/
flutter analyze lib/src/engine/errors.dart lib/src/engine/engine.dart test/engine/provider_preset_create_test.dart
git add lib/src/engine/errors.dart lib/src/engine/engine.dart test/engine/provider_preset_create_test.dart
git commit -m "feat(engine): createProviderFromPreset（INSERT 先行抢占，结构性消除并发删 Key）"
```

---

### Task 3: `/models` 拉取候选（网关 + 引擎转发）

**Files:**
- Modify: `app/lib/src/engine/providers/gateway.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Test: `app/test/engine/remote_model_candidates_test.dart`

**Interfaces:**
- Produces: `ProviderGateway.listRemoteModelIds(String providerId)`（默认 `Future.error(UnsupportedError('此网关不支持模型列表拉取'))`，与 `submitVideo` 同款样式）；`HttpProviderGateway` 实现（GET `{baseUrl}/models`、Bearer 头、解析 `data[].id`、`DioException`→`EngineException(errNetwork,...)`、非 List `data`→`errLlmFormat`）；`Engine.fetchProviderModelCandidates(String providerId)` 转发（前置 `_mustProvider`）。只返回 `List<String>`，不写库。

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
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
    expect(await gateway.listRemoteModelIds('p1'), ['m-a', 'm-b']);
  });

  test('网络错误包装为 errNetwork', () async {
    dio.httpClientAdapter = _FakeAdapter((options) => throw DioException(
        requestOptions: options, type: DioExceptionType.connectionTimeout));
    expect(
      () => gateway.listRemoteModelIds('p1'),
      throwsA(
          isA<EngineException>().having((e) => e.code, 'code', 'errNetwork')),
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
```

（动手前 grep `test/engine` 里既有 `httpClientAdapter` mock 模式，有则沿用既有类替换 `_FakeAdapter`；`credentialRef: 'provider:p1'` 的格式以 `providerCredentialRef` 真实前缀为准调整。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/engine/remote_model_candidates_test.dart`
Expected: FAIL（`listRemoteModelIds` 未定义）

- [ ] **Step 3: 实现**

`gateway.dart` 抽象类里 `cancelVideo` 之后加：

```dart
  /// GET {baseUrl}/models，仅返回远端模型 ID 候选（不写库；spec §5 第 5 条）。
  Future<List<String>> listRemoteModelIds(String providerId) =>
      Future.error(UnsupportedError('此网关不支持模型列表拉取'));
```

`HttpProviderGateway` 类内加实现（`jsonDecode` 需要时补 `import 'dart:convert';`）：

```dart
  @override
  Future<List<String>> listRemoteModelIds(String providerId) async {
    final rows = db.select(
        'SELECT id, inputValues FROM o_vendorConfig WHERE id=? AND COALESCE(enable,1)=1',
        [providerId]);
    if (rows.isEmpty) {
      throw EngineException(errProviderMissing, {'providerId': providerId});
    }
    final raw = rows.first['inputValues'] as String?;
    final inputValues = raw != null && raw.trim().isNotEmpty
        ? jsonDecode(raw) as Map
        : const {};
    var baseUrl = (inputValues['baseUrl'] ?? '').toString().trim();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final credentialRef =
        (inputValues['credentialRef'] ?? providerCredentialRef(providerId))
            .toString();
    var apiKey = '';
    try {
      apiKey = await credentials.read(credentialRef) ?? '';
    } catch (_) {}
    try {
      final resp = await dio.get<dynamic>(
        '$baseUrl/models',
        options: Options(headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        }),
      );
      final body = resp.data;
      final list = body is Map ? body['data'] : body;
      if (list is! List) {
        throw const EngineException(
            errLlmFormat, {'reason': '/models 响应缺 data 数组'});
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

`engine.dart` 在 `saveProviderModels` 附近加：

```dart
  /// /models 拉取候选（只出列表不写库；UI 定 kind 后走 saveProviderModels）。
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

### Task 4: 三语文案 + 预设画廊（含未验证角标）

**Files:**
- Modify: `app/lib/l10n/app_zh.arb`、`app/lib/l10n/app_en.arb`、`app/lib/l10n/app_ja.arb`
- Create: `app/lib/src/screens/provider_preset_gallery.dart`
- Test: `app/test/widgets/provider_preset_gallery_test.dart`

**Interfaces:**
- Consumes: Task 1 `kProviderPresets`/`ProviderPreset`。
- Produces: `Future<String?> showProviderPresetGallery(BuildContext context, {required Set<String> existingProviderIds})`——选中 presetId；`'custom'` 走自定义；null 取消。角标规则：已存在实例 →"已添加"；否则未过验收（`!acceptanceVerified`）显示"未验证"，且 `compatMode` 再叠加"兼容模式"（两枚可同现）。

- [ ] **Step 1: 加 l10n 键（三语，17 个）**

`app_zh.arb` 追加：

```json
  "presetGalleryTitle": "选择供应商",
  "presetGalleryCustom": "自定义",
  "presetGalleryCustomDesc": "手动填写名称、地址与密钥",
  "presetCompatMode": "兼容模式",
  "presetUnverified": "未验证",
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
  "presetUnverified": "Unverified",
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
  "presetUnverified": "未検証",
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

Run: `flutter gen-l10n && cat untranslated.txt`
Expected: `untranslated.txt` 空。

- [ ] **Step 2: 写失败 widget 测试**

```dart
// app/test/widgets/provider_preset_gallery_test.dart
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/screens/provider_preset_gallery.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
    {required Set<String> existing,
    required void Function(String?) onResult}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
    locale: const Locale('zh'),
    theme: buildTheme(Brightness.light),
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

Finder _inCard(String presetId, String text) => find.descendant(
    of: find.byKey(Key('preset-card-$presetId')), matching: find.text(text));

void main() {
  testWidgets('手机宽度：卡片、兼容模式+未验证双角标、选中回传', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(_host(existing: {}, onResult: (v) => picked = v));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();

    // openai 未过验收 → 未验证；非兼容模式 → 无兼容模式角标
    expect(_inCard('openai', '未验证'), findsOneWidget);
    expect(_inCard('openai', '兼容模式'), findsNothing);
    // anthropic 双角标
    expect(_inCard('anthropic', '未验证'), findsOneWidget);
    expect(_inCard('anthropic', '兼容模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset-card-openai')));
    await tester.pumpAndSettle();
    expect(picked, 'openai');
  });

  testWidgets('桌面宽度：已添加优先于未验证；azt 已验不显示未验证', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(_host(existing: {'volcengine'}, onResult: (_) {}));
    await tester.tap(find.byKey(const Key('open-gallery')));
    await tester.pumpAndSettle();

    expect(_inCard('volcengine', '已添加'), findsOneWidget);
    expect(_inCard('volcengine', '未验证'), findsNothing,
        reason: '已添加态优先，不再叠未验证');
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-azt')), 300);
    expect(_inCard('azt', '未验证'), findsNothing,
        reason: 'azt acceptanceVerified=true');
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

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/widgets/provider_preset_gallery_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 4: 实现画廊**

```dart
// app/lib/src/screens/provider_preset_gallery.dart
import 'package:flutter/material.dart';

import '../engine/provider_presets.dart';
import '../theme/theme.dart';
import '../util/l10n_ext.dart';
import '../widgets/df_adaptive_dialog.dart';

/// 预设画廊（spec §5 第 1 条）：返回选中 presetId；'custom' 走自定义；null 取消。
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
      childAspectRatio: 1.3,
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
    final df = context.df;
    final l10n = context.l10n;
    final kinds = {for (final m in preset.models) m.kind};
    String kindLabel(String k) => switch (k) {
          'image' => l10n.presetKindImage,
          'video' => l10n.presetKindVideo,
          'tts' => l10n.presetKindTts,
          _ => l10n.presetKindText,
        };
    final badges = <String>[
      if (added)
        l10n.presetAdded
      else ...[
        if (!preset.acceptanceVerified) l10n.presetUnverified,
        if (preset.compatMode) l10n.presetCompatMode,
      ],
    ];
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(preset.name.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 13)),
                ),
                const Spacer(),
                Flexible(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [for (final b in badges) _Badge(text: b)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final k in kinds)
                _Badge(text: kindLabel(k)),
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
    final df = context.df;
    final l10n = context.l10n;
    return InkWell(
      key: const Key('preset-card-custom'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop('custom'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke),
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
    final df = context.df;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: df.stroke),
        borderRadius: BorderRadius.circular(4),
      ),
      child:
          Text(text, style: TextStyle(fontSize: 10, color: df.textSecondary)),
    );
  }
}
```

（`DFColors` 的 `stroke`/`textSecondary`/`textTertiary` 已在"已核实事实"确认存在。）

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/widgets/provider_preset_gallery_test.dart`
Expected: PASS（3 tests）

- [ ] **Step 6: analyze + commit**

```bash
flutter analyze lib/src/screens/provider_preset_gallery.dart test/widgets/provider_preset_gallery_test.dart
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/src/screens/provider_preset_gallery.dart test/widgets/provider_preset_gallery_test.dart
git commit -m "feat(ui): 供应商预设画廊（未验证/兼容模式/已添加角标，三语）"
```

（`flutter gen-l10n` 产物若被 git 跟踪则一并 add。）

---

### Task 5: 预填表单（name/baseUrl 覆盖真实生效）+ 设置页接线

**Files:**
- Create: `app/lib/src/screens/provider_preset_form.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`（`_openCreateProviderDialog`）
- Test: `app/test/widgets/provider_preset_form_test.dart`；更新 `app/test/widgets/settings_screen_test.dart` 现有添加供应商用例

**Interfaces:**
- Consumes: Task 1 `providerPresetById`；Task 2 `createProviderFromPreset`（含 `name`/`baseUrl` 覆盖）；Task 4 `showProviderPresetGallery`。
- Produces: `Future<bool> showProviderPresetForm(BuildContext context, WidgetRef ref, {required String presetId})`。settings 添加流程：画廊 → presetId 进预填表单 / 'custom' 进现有 `_ProviderFormDialog` / 已存在 presetId 进现有编辑弹窗。

- [ ] **Step 1: 写失败 widget 测试**

```dart
// app/test/widgets/provider_preset_form_test.dart
import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/engine.dart';
import 'package:dramaflow/src/engine/media.dart';
import 'package:dramaflow/src/engine/providers/gateway.dart';
import 'package:dramaflow/src/screens/provider_preset_form.dart';
import 'package:dramaflow/src/state/providers.dart';
import 'package:dramaflow/src/theme/theme.dart';
import 'package:flutter/material.dart';
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
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          locale: const Locale('zh'),
          theme: buildTheme(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                key: const Key('open-form'),
                onPressed: () =>
                    showProviderPresetForm(context, ref, presetId: 'deepseek'),
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

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-baseurl')))
            .controller!
            .text,
        'https://api.deepseek.com/v1');
    expect(find.text('deepseek-chat'), findsOneWidget);
    expect(find.text('deepseek-reasoner'), findsOneWidget);

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-apikey')))
            .obscureText,
        isTrue);
    await tester.tap(find.byKey(const Key('preset-form-apikey-toggle')));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('preset-form-apikey')))
            .obscureText,
        isFalse);
  });

  testWidgets('保存：改名+改 BaseURL+取消一个模型，全部真实落库', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-form')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('preset-form-name')), '我的 DeepSeek');
    await tester.enterText(find.byKey(const Key('preset-form-baseurl')),
        'https://proxy.example.com/v1');
    await tester.enterText(
        find.byKey(const Key('preset-form-apikey')), 'sk-test');
    await tester.tap(find.byKey(const Key('preset-model-deepseek-reasoner')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('preset-form-save')));
    await tester.pumpAndSettle();

    final provider = (await engine.listProviders()).single;
    expect(provider.name, '我的 DeepSeek', reason: '可编辑名称必须真实生效（评审 P1-3）');
    expect(provider.baseUrl, 'https://proxy.example.com/v1');
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
import '../util/l10n_ext.dart';
import '../widgets/df_adaptive_dialog.dart';

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
            name: _name.text,
            baseUrl: _baseUrl.text,
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
            key: const Key('preset-form-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('preset-form-baseurl'),
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
                icon:
                    Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l10n.presetOpenPlatform),
              onPressed: () => launchUrl(Uri.parse(widget.preset.keyUrl)),
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
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('preset-form-save'),
            onPressed: _saving || _selected.isEmpty ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
```

（"名称"/"保存"两处文案：先 grep settings_screen.dart 现有 `_ProviderFormDialog` 用的 l10n 键（如 `l10n.settingsProviderName`/`l10n.commonSave` 之类的真实键名），有键用键，确无键才允许沿用它的硬编码写法——与现有表单保持同一来源。）

- [ ] **Step 4: 接线 settings_screen.dart**

`_openCreateProviderDialog` 改为（顶部加 `import 'provider_preset_gallery.dart';`、`import 'provider_preset_form.dart';`）：

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

    final existing = providers.where((p) => p.id == picked).toList();
    if (existing.isNotEmpty) {
      await _openEditProviderDialog(existing.first);
      return;
    }

    final created =
        await showProviderPresetForm(context, ref, presetId: picked);
    if (created && mounted) _invalidateProvidersAndBindings();
  }
```

- [ ] **Step 5: 更新既有用例 + 跑测试**

`settings_screen_test.dart` 的 `移动端设置页：外观语言、供应商与提示词入口可用` 用例：在 `tap(find.text('添加供应商'))` 与 3 个 TextField 输入之间插入：

```dart
    await tester.scrollUntilVisible(
        find.byKey(const Key('preset-card-custom')), 300);
    await tester.tap(find.byKey(const Key('preset-card-custom')));
    await tester.pumpAndSettle();
```

其余断言不变（自定义表单本身零改动）。

Run: `flutter test test/widgets/provider_preset_form_test.dart test/widgets/settings_screen_test.dart`
Expected: 全 PASS。

- [ ] **Step 6: analyze + commit**

```bash
flutter analyze lib/src/screens/provider_preset_form.dart lib/src/screens/settings_screen.dart test/widgets/provider_preset_form_test.dart
git add lib/src/screens/provider_preset_form.dart lib/src/screens/settings_screen.dart test/widgets/provider_preset_form_test.dart test/widgets/settings_screen_test.dart
git commit -m "feat(ui): 预设预填表单（name/baseUrl 覆盖生效）+ 设置页画廊接线"
```

---

### Task 6: 模型管理"从 API 拉取"候选合并（全量代码）

**Files:**
- Modify: `app/lib/src/screens/settings_screen.dart`（`_ProviderModelsEditorState` + 新私有 `_CandidateSheet`）
- Test: 追加用例到 `app/test/widgets/settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 `Engine.fetchProviderModelCandidates`；Task 1 `presetModelKinds`；Task 2 `createProviderFromPreset`（测试造数据用）。
- Produces: 模型管理弹窗"从 API 拉取模型"按钮 → `_CandidateSheet` 底部弹层 → 选中且已定 kind 的候选加为 `_ModelDraft(enabled: false)`。

- [ ] **Step 1: 写失败测试（settings_screen_test.dart 末尾追加；文件顶部追加 fake gateway 类）**

文件顶部（`_NoopGateway` 类之后）加：

```dart
class _CandidatesGateway implements ProviderGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<String>> listRemoteModelIds(String providerId) async =>
      ['deepseek-chat', 'brand-new-model'];
}
```

末尾追加用例：

```dart
  testWidgets('模型管理：从 API 拉取候选，未分类必须定 kind 才能加入，且默认禁用', (tester) async {
    // 换成能应答 /models 的 fake gateway（沿用本文件 setUp 的 db/media 构造方式）
    engine.dispose();
    final db = openEngineDb(':memory:');
    engine = Engine(
      db: db,
      media: MediaStore(p.join(dir.path, 'media')),
      gateway: _CandidatesGateway(),
      config: EngineConfig(db, isMobile: true),
    );
    await engine.createProviderFromPreset(
        presetId: 'deepseek', apiKey: 'k', selectedModelIds: ['deepseek-chat']);

    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await _selectSection(tester, '供应商');
    await tester.tap(find.byTooltip('模型管理').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('从 API 拉取模型'));
    await tester.pumpAndSettle();

    // deepseek-chat 已在清单 → 候选只剩 brand-new-model（未分类）
    expect(find.byKey(const Key('candidate-row-brand-new-model')),
        findsOneWidget);
    expect(find.byKey(const Key('candidate-row-deepseek-chat')), findsNothing);
    expect(find.text('未分类'), findsOneWidget);

    // 不定 kind 勾选加入 → 行内报错，不关弹层
    await tester.tap(find.byKey(const Key('candidate-check-brand-new-model')));
    await tester.pump();
    await tester.tap(find.text('加入清单'));
    await tester.pump();
    expect(find.text('请先为勾选的模型选择类型'), findsOneWidget);

    // 定 kind = 图片 → 加入成功
    await tester.tap(find.byKey(const Key('candidate-kind-brand-new-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入清单'));
    await tester.pumpAndSettle();
    expect(find.text('brand-new-model'), findsOneWidget); // 已入草稿区

    // 保存后落库：新模型 kind=image 且默认禁用；原模型不受影响
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final models = await engine.listProviderModels('deepseek');
    final byId = {for (final m in models) m.modelId: m};
    expect(byId['brand-new-model']!.kind, 'image');
    expect(byId['brand-new-model']!.enabled, isFalse,
        reason: '拉取候选默认禁用（spec §5 第 5 条）');
    expect(byId['deepseek-chat']!.enabled, isTrue, reason: '已有条目不受影响');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/widgets/settings_screen_test.dart --plain-name 从 API 拉取`
Expected: FAIL（按钮不存在）

- [ ] **Step 3: 实现**

`_ProviderModelsEditorState` 内加方法（`_ModelDraft` 真实字段：`modelId`/`label` 是 `TextEditingController`，`kind` String，`enabled` bool，`capabilities` Map——已核实 :2283）：

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
    final known = {for (final d in _drafts) d.modelId.text.trim()};
    final candidates = [
      for (final id in ids)
        if (!known.contains(id)) id,
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.presetFetchEmpty)));
      return;
    }
    final picked = await showModalBottomSheet<List<(String, String)>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CandidateSheet(
        candidates: candidates,
        knownKinds: presetModelKinds(widget.provider.id),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final (id, kind) in picked) {
        _drafts.add(_ModelDraft(
          id: '',
          modelId: TextEditingController(text: id),
          label: TextEditingController(text: id),
          kind: kind,
          capabilities: <String, dynamic>{},
          enabled: false, // spec：候选默认禁用，用户手动启用
        ));
      }
    });
  }
```

按钮放在"添加模型"按钮同一工具行旁：

```dart
            TextButton.icon(
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(context.l10n.presetFetchModels),
              onPressed: _fetchCandidates,
            ),
```

新私有 widget（放在 `_ModelDraft` 类附近）：

```dart
class _CandidateSheet extends StatefulWidget {
  final List<String> candidates;
  final Map<String, String> knownKinds;
  const _CandidateSheet({required this.candidates, required this.knownKinds});

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  late final Map<String, String?> _kinds = {
    for (final id in widget.candidates) id: widget.knownKinds[id],
  };
  final Set<String> _checked = {};
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String kindLabel(String k) => switch (k) {
          'image' => l10n.presetKindImage,
          'video' => l10n.presetKindVideo,
          'tts' => l10n.presetKindTts,
          _ => l10n.presetKindText,
        };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final id in widget.candidates)
                    Row(
                      key: Key('candidate-row-$id'),
                      children: [
                        Checkbox(
                          key: Key('candidate-check-$id'),
                          value: _checked.contains(id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _checked.add(id);
                            } else {
                              _checked.remove(id);
                            }
                          }),
                        ),
                        Expanded(
                          child: Text(id,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownButton<String>(
                          key: Key('candidate-kind-$id'),
                          value: _kinds[id],
                          hint: Text(l10n.presetUncategorized),
                          items: [
                            for (final k in const [
                              'text',
                              'image',
                              'video',
                              'tts'
                            ])
                              DropdownMenuItem(
                                  value: k, child: Text(kindLabel(k))),
                          ],
                          onChanged: (v) => setState(() => _kinds[id] = v),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final missing =
                    _checked.where((id) => _kinds[id] == null).toList();
                if (missing.isNotEmpty) {
                  setState(() => _error = l10n.presetKindRequired);
                  return;
                }
                Navigator.of(context).pop([
                  for (final id in _checked) (id, _kinds[id]!),
                ]);
              },
              child: Text(l10n.presetAddCandidates),
            ),
          ],
        ),
      ),
    );
  }
}
```

（"保存"按钮与草稿持久化沿用编辑器现有逻辑——`enabled: false` 的 draft 由既有保存路径原样写库，无需改动。）

- [ ] **Step 4: 跑全文件回归**

Run: `flutter test test/widgets/settings_screen_test.dart`
Expected: 全 PASS（新用例 + 既有全部）

- [ ] **Step 5: analyze + commit**

```bash
flutter analyze lib/src/screens/settings_screen.dart test/widgets/settings_screen_test.dart
git add lib/src/screens/settings_screen.dart test/widgets/settings_screen_test.dart
git commit -m "feat(ui): 模型管理从 API 拉取候选（未分类需定 kind，默认禁用）"
```

---

### Task 7: 全量收尾 + 人工验收清单（含 azt 证据）

**Files:**
- Create: `docs/parity/provider-presets-acceptance.md`
- Modify: `.superpowers/sdd/progress.md`

- [ ] **Step 1: 全量回归**

```bash
flutter analyze
flutter test
```
Expected: 0 issues；全套件 PASS。失败先修再继续。

- [ ] **Step 2: 写人工验收清单（含证据规则）**

`docs/parity/provider-presets-acceptance.md`：

```markdown
# 供应商预设人工验收清单（需真实 Key，不进默认 CI）

规则（spec §4 + 评审 P2）：
- 每家 4 项——①普通文本生成；②强制工具调用/结构化 JSON；③图片生成与编辑（仅声称图片角标的家）；④GET /models。
- ①②任一失败 = 该家不可置 `acceptanceVerified: true`；③失败 = 移除该家图片模型；④失败 = preset 备注"不支持 /models"。
- **`provider_presets.dart` 里把某家 `acceptanceVerified` 翻 true 的唯一合法途径：本表该行填入日期+模型+证据路径。**画廊"未验证"角标随字段自动消失。
- 记录格式：日期 / 所测模型 / 证据（日志路径、测试名或截图路径）。

| preset | ①文本 | ②工具/JSON | ③图片 | ④/models | 证据 |
|---|---|---|---|---|---|
| azt | ✅ 2026-07-18 | ✅ 2026-07-18 | ✅ 2026-07-18 | ✅ 2026-07-18 | gpt-5.6-luna 文本+工具链路：macOS/iOS golden-path e2e 全流程（建项目→剧本→分镜表均真实调用，`.superpowers/sdd/progress.md` P0 Task 4 与"早晨总结"条目）；gpt-image-2 1024 图片 26.7s：`/tmp/p0-azt-smoke.txt`；/v1/models 当日实测返回 gpt-5.6 系列 |
| volcengine | 待验 | 待验 | 待验 | 待验 | 今晚视频生成被明确搁置，无真实调用证据 → acceptanceVerified=false，画廊显示"未验证" |
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
```

"待验"是验收文档的合法状态：**未验的家在产品里持续显示"未验证"角标**，两者一致，不存在"全待验却宣告可用"。

- [ ] **Step 3: 更新台账 + commit**

`.superpowers/sdd/progress.md` 末尾追加本计划 7 任务完成记录（commit 号+一句话+测试计数），沿用既有格式。

```bash
git add docs/parity/provider-presets-acceptance.md .superpowers/sdd/progress.md
git commit -m "docs: 供应商预设人工验收清单（azt 附证据，未验持续标未验证）+ 台账"
```

---

## Self-Review 记录（v2）

1. **Spec 覆盖**：§3 数据模型+硬门→Task 1（含 `acceptanceVerified` 扩展，源自评审 P2）；§4 目录+验收标准→Task 1/7；§5.1 画廊→Task 4；§5.2 预填/obscure/前往平台/**可编辑生效**→Task 5+Task 2 覆盖参数；§5.3 重复防护→Task 2（结构性）+Task 5 已添加进编辑；§5.4 自定义回归→Task 5 Step 5；§5.5 拉取候选→Task 3+6；§6 引擎三改动→Task 1/2/3；§7 测试→各任务+Task 7。
2. **评审 5+1 条逐一回应**：P1-1 并发删 Key→INSERT 先行+同步抢占段+并发测试（Task 2）；P1-2 假回滚测试→触发器+注入失败凭证仓两条真路径测试（Task 2）；P1-3 name/baseUrl 静默忽略→API 覆盖参数+落库断言（Task 2/5）；P1-4 volcengine 漂移→真值对齐+种子单一来源+Engine.boot 防漂移锁（Task 1）；P1-5 Task 6 半成品→全代码化+真实字段名+完整 _CandidateSheet（Task 6）；P2 验收门→acceptanceVerified 字段+未验证角标+证据规则+azt 证据行（Task 1/4/7）。
3. **占位符扫描**：全部代码块完整；仅存的"以真实键名为准"点（Task 5 表单两处文案）给出了 grep 位置与回退规则。验收表"待验"为文档状态语义且与产品"未验证"角标一致。
4. **类型一致性**：`createProviderFromPreset({presetId, apiKey, selectedModelIds, name, baseUrl})` Task 2 定义=Task 5/6 调用；`fetchProviderModelCandidates` Task 3=Task 6；`showProviderPresetGallery({existingProviderIds})` Task 4=Task 5；`presetModelKinds`/`seedanceMiniCapabilities` Task 1=Task 6/engine。`_ModelDraft` 构造与 :2283 真实签名一致（id/modelId/label/kind/capabilities/enabled）。
