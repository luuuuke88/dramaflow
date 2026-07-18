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
  final bool compatMode;      // true = 走官方 OpenAI 兼容层而非原生 API（Claude/Gemini/Grok），
                              // 画廊卡片显示"兼容模式"角标，不暗示完整原生能力
  final bool desktopOnly;     // true = iOS/Android 画廊不展示（本机 loopback 预设）
  final String sourceUrl;     // 模型清单出处（官方模型文档页）
  final String verifiedAt;    // 'YYYY-MM-DD'，最后一次按 sourceUrl 人工核实模型清单的日期
  final List<PresetModel> models;
}

class PresetModel {
  final String modelId;
  final String label;
  final String kind;          // text | image | video | tts，与现有 models JSON 的 kind 一致
  final Map<String, Object?> capabilities; // 视频类沿用现有 capabilities 结构
}
```

**模型清单硬门**：`verifiedAt`/`sourceUrl` 不是注释是门禁——实施计划中，任何模型 ID 未经当日对照 sourceUrl 核实（或经该家真实 API 调用验证）不得写入常量；核实后必须填 `verifiedAt`。目录单测断言两字段非空。

**平台可达性硬门**：预设不能只因在桌面可用就出现在移动端。`azt` 的地址是本机 loopback OAuth 代理，iOS/Android 上会指向手机自身，因此标为 `desktopOnly` 并从移动画廊隐藏；这与引擎移动端不播种 azt 的既有行为一致。

许可证红线：目录内容全部独立编写。公开 API 端点与模型 ID 是事实数据；**不复制 ToonFlow 的 `data/vendor/*.ts` 任何代码或文案**（其许可证非标准 Apache-2.0，W0 审计已确认）。

## 4. 目录内容（12 家预设 + 自定义入口，画廊 13 张卡）

预置模型为 2-4 个旗舰模型的**策展快照**；下表模型 ID 以设计时点的公开资料为准，**实施时逐家用官方文档或 `GET /models` 核实**（核实属于实施计划的一个显式步骤，不是可跳过的注脚）。过时问题由"从 API 拉取模型列表"按钮（§5 第 5 条）长效解决。

| # | id | 名称 | BaseURL | 预置模型（kind）——写入常量前逐条过 §3 硬门 |
|---|---|---|---|---|
| 1 | openai | OpenAI | https://api.openai.com/v1 | GPT-5.6 系（sol/terra/luna，text）、gpt-image-2(image)；出处 developers.openai.com/api/docs/models |
| 2 | anthropic | Claude (Anthropic) | https://api.anthropic.com/v1 | claude-sonnet-5(text)、claude-opus-4-8(text)、claude-haiku-4-5(text)；**兼容模式** |
| 3 | gemini | Gemini (Google) | https://generativelanguage.googleapis.com/v1beta/openai | gemini-3.5-flash(text) 及当期 pro 型号；**兼容模式**（官方标 beta）；图片走原生 API，待协议后补 |
| 4 | xai | Grok (xAI) | https://api.x.ai/v1 | Grok 4.3/4.5 当期型号(text)；**兼容模式**（Chat Completions 已被 xAI 标 legacy） |
| 5 | openrouter | OpenRouter | https://openrouter.ai/api/v1 | anthropic/claude-sonnet-5(text)、google/gemini-3-pro(text) 等当期热门(text) |
| 6 | siliconflow | 硅基流动 | https://api.siliconflow.cn/v1 | deepseek-ai/DeepSeek-V3.2(text)、Qwen/Qwen3-Max(text)、Kwai-Kolors/Kolors(image) |
| 7 | deepseek | DeepSeek | https://api.deepseek.com/v1 | deepseek-chat(text)、deepseek-reasoner(text) |
| 8 | moonshot | Kimi (Moonshot) | https://api.moonshot.cn/v1 | kimi-latest(text)、kimi-thinking-preview(text) |
| 9 | zhipu | 智谱 GLM | https://open.bigmodel.cn/api/paas/v4 | glm-4.6(text)、cogview-4(image) |
| 10 | dashscope | 通义 Qwen | https://dashscope.aliyuncs.com/compatible-mode/v1 | qwen3-max(text)、qwen-plus(text)；图片是否过兼容层实施时验证，不通则不预置 |
| 11 | volcengine | 火山豆包 | https://ark.cn-beijing.volces.com/api/v3 | 与现有种子一致：doubao-seed(text)、seedream(image)、seedance(video，protocol=volcengine) |
| 12 | azt | azt (本地 Codex OAuth) | http://127.0.0.1:8787/v1 | 与现有种子一致：gpt-5.x(text)、gpt-image-2(image)；**仅桌面展示** |
| 13 | custom | 自定义 | —（画廊末位卡，进现有裸表单） | 无预置 |

keyUrl 每家指向其控制台 API Key 页（如 platform.openai.com/api-keys、console.anthropic.com、aistudio.google.com/apikey 等，实施时逐一核实链接有效）。

**兼容模式的诚实标注**：Anthropic 官方明确其 OpenAI 兼容层"主要用于测试比较，非长期生产方案"；Gemini 兼容层官方标 beta；xAI 已把 Chat Completions 标 legacy。这三家画廊卡片显示"兼容模式"角标（`compatMode: true`），文案不得暗示完整原生能力；这也是"协议后补"阶段的优先级依据。

**每家预设的验收标准**（不是"模型出现在 /models 就算通"——现有引擎文本恒走 `/chat/completions` 且携带 `tools/tool_choice/max_completion_tokens`，openai_text.dart:64）：
1. 普通文本生成真实调用通过；
2. 强制工具调用/结构化 JSON 输出通过（剧本、事件抽取、Agent 全依赖此路径）；
3. 声称有"图片"角标的，图片生成与编辑真实调用通过——不通过则该家不显示图片能力；
4. `GET /models` 拉取通过（不通的记录进该家 preset 备注，拉取按钮就地报错属预期）。
验收方式：实施计划中的人工验收清单（需真实 Key，不进默认 CI），可另配 env-gated 集成测试。

默认种子行为不变：仍只种 azt（桌面）+ volcengine，其余 10 家通过画廊按需添加。

## 5. UI 流程

1. **画廊**：点"添加供应商"→ `showDFAdaptiveDialog` 弹预设画廊（手机 <840dp 自动全屏，与全 app 一致）。网格卡片 = 字母色块头像（不采购品牌 logo，避免商标与素材问题）+ 名称 + 能力角标（文字/图片/视频 chips）。手机 2 列、桌面 3-4 列；`desktopOnly` 预设在 iOS/Android 不渲染。末位"自定义"卡。
2. **预填表单**：选中预设后进入表单：名称可改、BaseURL 已预填可改、**焦点直接落在 API Key 输入框**（`obscureText: true` + 明文切换眼睛按钮，对齐现有供应商表单的 Key 处理）、旁置"前往平台"外链（keyUrl）、下方预置模型清单（勾选框默认全勾，可取消不要的）。保存 = 调新增的 **`createProviderFromPreset`**（§6，单次原子调用，不用现有两步 create+saveModels——两步在第二步失败时会留下空供应商）。azt 类 loopback 地址沿用现有"本地地址免 Key"逻辑。
3. **重复防护与"已添加"态**：画廊里已存在实例的预设（含默认种子 azt/volcengine）显示"已添加"角标，点击进入该供应商的**编辑**而非再次创建。第一版每个预设只允许一个实例；同一家要多账号走"自定义"。这同时封死现有 `createProvider` 的凭证覆盖缺陷路径（engine.dart:1163-1168 先写凭证后 INSERT，同名 slug 冲突时旧 Key 已被覆盖）——预设路径根本不会走到同名创建。
4. **自定义路径**：与现在的裸表单完全一致，现有测试零改动即应继续通过（回归保障）。
5. **从 API 拉取模型列表**：模型管理弹窗新增按钮，调 `GET {baseUrl}/models`。**拉取只返回候选，不直接写库**——标准 /models 响应只有 ID、无法判定模态，而引擎要求 kind ∈ {text,image,video,tts}（engine.dart:1578）。候选列表中：ID 与该家预设目录匹配的自动带出目录里的 kind；未知 ID 标"未分类"且**默认禁用，用户指定 kind 后才能启用保存，绝不默认猜成 text**。已有条目不覆盖。拉取失败就地报错——部分供应商不实现该端点，属预期而非 bug。

国际化：画廊/表单的 UI 文案（"选择供应商""前往平台""从 API 拉取""兼容模式""已添加""未分类"等）走现有 l10n，**中/英/日三语**（app.dart:78-82 supportedLocales 为 zh/en/ja）；品牌名不翻译。

## 6. 引擎改动（刻意最小）

- 新增 `provider_presets.dart`：常量目录 + 单元测试。
- 新增 **`createProviderFromPreset(presetId, apiKey, selectedModelIds)`**：单次原子创建。顺序与失败语义：
  1. 先查 `o_vendorConfig` 是否已有该 preset 实例（按 preset id 即 slug 查）——已存在直接抛"已添加"错误，**凭证一个字节都不写**（修复现有 `createProvider` 先写凭证后 INSERT、同名冲突时覆盖旧 Key 的缺陷路径）；
  2. 无冲突后写凭证、INSERT 供应商与模型（同一调用内完成，不存在"建了供应商没模型"的半成品窗口）；
  3. INSERT 失败时删除刚写入的新凭证再抛错，不留孤儿凭证。
- 新增 `fetchRemoteModelCandidates(providerId)`：gateway 层小函数，dio 调 `GET /models`、解析 `data[].id`，**只返回候选列表不写库**（写库由 UI 在用户定 kind 后走现有 `saveProviderModels`）。仅此一个新网络调用。
- 不改：数据库 schema、现有 `createProvider`/`saveProviderModels` 签名（自定义路径继续用）、协议分发、种子逻辑。

## 7. 测试计划

- **目录单测**（`provider_presets_test.dart`）：12 家预设 id 唯一（custom 是 UI 入口不进目录常量）；URL 均为合法 https（azt 例外允许 http loopback）；每家 protocol ∈ {openai_compatible, volcengine}；模型清单非空且 kind ∈ {text,image,video,tts}；keyUrl 非空；**verifiedAt/sourceUrl 非空**（§3 硬门的机器锁）。
- **`createProviderFromPreset` 单测**：重复创建 → 抛"已添加"且断言旧凭证值未变（直击 P0 缺陷场景）；INSERT 失败注入 → 断言新凭证被回滚删除；正常路径 → 供应商+模型一次到位无中间态。
- **画廊 widget 测试**：390px 与桌面各渲染一遍，并显式模拟 iOS；桌面断言 12 预设卡 + 自定义卡齐全，iOS/Android 断言 `desktopOnly` 的 azt 不出现；能力角标正确、兼容模式角标只出现在 anthropic/gemini/xai、已存在实例的卡显示"已添加"并进编辑。
- **预填流程测试**：选中某预设 → 断言表单 BaseURL/模型清单与目录一致、Key 框 obscureText 且可切换明文；填 Key 保存 → 断言 in-memory 引擎里真实建出供应商与模型（含 kind/capabilities）。
- **自定义回归**：现有添加供应商测试不改动、继续绿。
- **拉取候选单测**：mock 网络层——候选不落库；目录内 ID 自动带 kind；未知 ID 标未分类且不能不选 kind 就保存；已有条目不被覆盖；端点 404/超时报错不崩。
- **每家真实连通验收**（人工/env-gated，需真实 Key，不进默认 CI）：按 §4 验收标准逐家过文本、工具调用/JSON、图片（如声称）、/models 四项。

## 8. 范围外（明确不做）

- Anthropic/Gemini 原生协议适配器（思考预算、Gemini 原生图片）——协议后补阶段。
- 可灵、Vidu、MiniMax 等视频供应商预设——等视频协议扩展后上架（避免灰显占位噪音）。
- 品牌 logo 素材、远程可更新的预设目录（常量目录 + 拉取模型按钮已够）。
- 供应商启用/禁用开关的 ToonFlow 式双栏重构——现有卡片列表不动。
