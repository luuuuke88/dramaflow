# 供应商预设体系（Provider Presets）设计

日期：2026-07-18。状态：已与用户逐段确认的设计稿。

## 1. 背景与动机

DramaFlow 现状：添加供应商是一个裸表单（名称/BaseURL/API Key 全手填），默认只种 2 个供应商（azt 桌面端、volcengine），协议只有 `openai_compatible` 和 `volcengine` 两种。对照 ToonFlow：13 个预设供应商，每个预填好名称、BaseURL、模型清单和能力标签，用户只填 Key。

用户诉求：预设体验对齐并超越 ToonFlow——尤其要国际供应商（Claude、Gemini、OpenAI、Grok），ToonFlow 的国际线只有一个裸的"OpenAI标准接口"转发。

## 2. 已确认的三个关键决策

1. **协议架构：预设优先，协议后补。** 第一期所有预设走现有 `openai_compatible` 协议——OpenAI 原生即此格式；Anthropic 官方支持 OpenAI SDK 指向 `api.anthropic.com/v1`；Google 提供 `generativelanguage.googleapis.com/v1beta/openai/` 兼容层。预设结构保留 `protocol` 字段，未来要 Gemini 原生图片、Claude 思考预算控制时按供应商补原生适配器，数据结构不动。
2. **目录广度：12 家真实预设 + "自定义"入口**（用户裁剪自 18 家草案；画廊共 13 张卡）。裁剪原则：列了就意味着"我们声称能用"，没人真用的预设伤可信度；目录是常量列表，后续加一家约 10 行代码。砍掉：Mistral、Groq（对短剧场景无独特价值）、Ollama/LM Studio（走"自定义"即可）、可灵/Vidu 灰显占位（不能点的东西是噪音，等视频协议真接了再上架）。Grok 因用户明确有需求而保留。
3. **UI 形态：预设画廊式添加。** 不重建设置页双栏布局（ToonFlow 那种在手机上要拆两级导航，且现有设置页已有 12 个手机视口测试）。"添加供应商"先弹画廊，选中后进预填表单；"自定义"卡保留现在的裸表单原样。

## 3. 数据模型

新增 `app/lib/src/engine/provider_presets.dart`，纯 Dart 常量目录。**数据库 schema（`o_vendorConfig`）、现有引擎 API、协议层零改动。**

```dart
class ProviderPreset {
  final String id;            // 'openai', 'anthropic', 'gemini', ...
  final String name;          // 品牌名，不翻译（DeepSeek、Kimi 等中文名直接写）
  final String baseUrl;       // 预填端点
  final String keyUrl;        // "前往平台"拿 Key 的控制台链接
  final String protocol;      // 第一期均为 'openai_compatible'（火山为 'volcengine'）
  final List<PresetModel> models;
}

class PresetModel {
  final String modelId;
  final String label;
  final String kind;          // text | image | video | tts，与现有 models JSON 的 kind 一致
  final Map<String, Object?> capabilities; // 视频类沿用现有 capabilities 结构
}
```

许可证红线：目录内容全部独立编写。公开 API 端点与模型 ID 是事实数据；**不复制 ToonFlow 的 `data/vendor/*.ts` 任何代码或文案**（其许可证非标准 Apache-2.0，W0 审计已确认）。

## 4. 目录内容（12 家预设 + 自定义入口，画廊 13 张卡）

预置模型为 2-4 个旗舰模型的**策展快照**；下表模型 ID 以设计时点的公开资料为准，**实施时逐家用官方文档或 `GET /models` 核实**（核实属于实施计划的一个显式步骤，不是可跳过的注脚）。过时问题由"从 API 拉取模型列表"按钮（§5.4）长效解决。

| # | id | 名称 | BaseURL | 预置模型（kind） |
|---|---|---|---|---|
| 1 | openai | OpenAI | https://api.openai.com/v1 | gpt-5.1(text)、gpt-5.1-mini(text)、gpt-image-1(image) |
| 2 | anthropic | Claude (Anthropic) | https://api.anthropic.com/v1 | claude-sonnet-5(text)、claude-opus-4-8(text)、claude-haiku-4-5(text) |
| 3 | gemini | Gemini (Google) | https://generativelanguage.googleapis.com/v1beta/openai | gemini-3-pro(text)、gemini-2.5-flash(text)；图片走原生 API，待协议后补 |
| 4 | xai | Grok (xAI) | https://api.x.ai/v1 | grok-4(text)、grok-4-fast(text) |
| 5 | openrouter | OpenRouter | https://openrouter.ai/api/v1 | anthropic/claude-sonnet-5(text)、google/gemini-3-pro(text)、openai/gpt-5.1(text) |
| 6 | siliconflow | 硅基流动 | https://api.siliconflow.cn/v1 | deepseek-ai/DeepSeek-V3.2(text)、Qwen/Qwen3-Max(text)、Kwai-Kolors/Kolors(image) |
| 7 | deepseek | DeepSeek | https://api.deepseek.com/v1 | deepseek-chat(text)、deepseek-reasoner(text) |
| 8 | moonshot | Kimi (Moonshot) | https://api.moonshot.cn/v1 | kimi-latest(text)、kimi-thinking-preview(text) |
| 9 | zhipu | 智谱 GLM | https://open.bigmodel.cn/api/paas/v4 | glm-4.6(text)、cogview-4(image) |
| 10 | dashscope | 通义 Qwen | https://dashscope.aliyuncs.com/compatible-mode/v1 | qwen3-max(text)、qwen-plus(text)；图片是否过兼容层实施时验证，不通则不预置 |
| 11 | volcengine | 火山豆包 | https://ark.cn-beijing.volces.com/api/v3 | 与现有种子一致：doubao-seed(text)、seedream(image)、seedance(video，protocol=volcengine) |
| 12 | azt | azt (本地 Codex OAuth) | http://127.0.0.1:8787/v1 | 与现有种子一致：gpt-5.x(text)、gpt-image-2(image) |
| 13 | custom | 自定义 | —（画廊末位卡，进现有裸表单） | 无预置 |

keyUrl 每家指向其控制台 API Key 页（如 platform.openai.com/api-keys、console.anthropic.com、aistudio.google.com/apikey 等，实施时逐一核实链接有效）。

默认种子行为不变：仍只种 azt（桌面）+ volcengine，其余 11 家通过画廊按需添加。

## 5. UI 流程

1. **画廊**：点"添加供应商"→ `showDFAdaptiveDialog` 弹预设画廊（手机 <840dp 自动全屏，与全 app 一致）。网格卡片 = 字母色块头像（不采购品牌 logo，避免商标与素材问题）+ 名称 + 能力角标（文字/图片/视频 chips）。手机 2 列、桌面 3-4 列。末位"自定义"卡。
2. **预填表单**：选中预设后进入表单：名称可改、BaseURL 已预填可改、**焦点直接落在 API Key 输入框**、旁置"前往平台"外链（keyUrl）、下方预置模型清单（勾选框默认全勾，可取消不要的）。保存 = 调现有 `createProvider` + `saveProviderModels`。azt 类 loopback 地址沿用现有"本地地址免 Key"逻辑。
3. **自定义路径**：与现在的裸表单完全一致，现有测试零改动即应继续通过（回归保障）。
4. **从 API 拉取模型列表**：模型管理弹窗新增按钮，调 `GET {baseUrl}/models`（OpenAI 兼容端点普遍支持）。返回的新模型 ID 合并进清单（**默认禁用**，用户手动勾启用；已有条目不覆盖）。拉取失败就地报错——部分供应商不实现该端点，属预期而非 bug。

国际化：画廊/表单的 UI 文案（"选择供应商""前往平台""从 API 拉取"等）走现有 l10n（zh/en 双份）；品牌名不翻译。

## 6. 引擎改动（刻意最小）

- 新增 `provider_presets.dart`：常量目录 + 单元测试。
- 新增 `fetchRemoteModels(providerId)`：gateway 层小函数，dio 调 `GET /models`、解析 `data[].id`、按 §5.4 规则合并。仅此一个新网络调用。
- 不改：数据库 schema、`createProvider`/`saveProviderModels` 签名、协议分发、种子逻辑。

## 7. 测试计划

- **目录单测**（`provider_presets_test.dart`）：12 家预设 id 唯一（custom 是 UI 入口不进目录常量）；URL 均为合法 https（azt 例外允许 http loopback）；每家 protocol ∈ {openai_compatible, volcengine}；模型清单非空且 kind ∈ {text,image,video,tts}；keyUrl 非空。
- **画廊 widget 测试**：390px 与桌面各渲染一遍（沿用现有测试的手机视口约定）；断言 13 卡 + 自定义卡齐全、能力角标正确。
- **预填流程测试**：选中某预设 → 断言表单 BaseURL/模型清单与目录一致；填 Key 保存 → 断言 in-memory 引擎里真实建出供应商与模型（含 kind/capabilities）。
- **自定义回归**：现有添加供应商测试不改动、继续绿。
- **拉取合并单测**：mock 网络层——新模型进来默认禁用、已有条目不被覆盖、端点 404/超时时报错不崩。

## 8. 范围外（明确不做）

- Anthropic/Gemini 原生协议适配器（思考预算、Gemini 原生图片）——协议后补阶段。
- 可灵、Vidu、MiniMax 等视频供应商预设——等视频协议扩展后上架（避免灰显占位噪音）。
- 品牌 logo 素材、远程可更新的预设目录（常量目录 + 拉取模型按钮已够）。
- 供应商启用/禁用开关的 ToonFlow 式双栏重构——现有卡片列表不动。
