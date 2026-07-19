# 供应商协议对照矩阵

更新时间：2026-07-19

基线：ToonFlow 1.1.8 的 `Toonflow-app/data/vendor/*.ts`（13 个文件）
范围：供应商的用户可见配置、默认模型模态、请求/轮询/取消能力和本地 OAuth 路径。本文不复制原版实现代码，也不把 Electron 的可写 TypeScript 插件机制搬进 Flutter。

## 读法

- **已验证等价**：当前没有任何供应商文件达到此状态。
- **部分实现**：存在同类入口或协议，但模型能力、参数、任务生命周期或跨端证据未覆盖完整。
- **缺失**：原版存在用户可配置的默认供应商能力，Flutter 没有对应协议适配器。
- **待分类**：原版文件主要服务于开发/兜底；需要在总清单范围门决定是否有独立用户价值，不能静默忽略。

所有视频行的开发验收仅允许本地数据、请求序列和 fake gateway 覆盖；不提交真实视频任务，不轮询真实任务，不消耗供应商额度。真实视频生成由用户最终手动验收。

## 原版逐文件对照

| 原版文件 | 原版默认模型与能力证据 | DramaFlow 当前对应 | 状态 | 必须补的可观察行为 |
| --- | --- | --- | --- | --- |
| `atlascloud.ts` | 16 个默认模型，含文本、图像和多种视频任务 | 无 AtlasCloud 协议或预设 | 缺失 | 多模态模型配置、视频提交/轮询/取消、能力映射与 fake 协议回归 |
| `azt.ts` | 本机 OAuth 文本和 GPT Image 2；图片质量、尺寸、超时为配置项 | 桌面 `azt` 种子，OpenAI 兼容文本/图片 | 部分实现 | 以实际本机 `/models` 刷新默认模型；验证图片尺寸/质量提示和多参考的可观察结果；移动端继续明确不可达。**当前复核（2026-07-19）**：本机 `GET http://127.0.0.1:8787/v1/models` 返回 `gpt-5.6-sol`、`gpt-5.6-terra`、`gpt-5.6-luna`、`gpt-5.5`、`gpt-5.3-codex-spark`；Flutter 种子/预设仍为 `gpt-5.5`、`gpt-5.4`、`gpt-5.4-mini`、`gpt-image-2`。后两条文字模型没有出现在当次服务列表，5.6 三档又没有被预设，故模型目录硬门尚未闭合。`/models` 未列 `gpt-image-2` 不单独证明图片不可用，图片端点已有独立冒烟记录；目录修复须保留这种模态差异。 |
| `deepseek.ts` | 2 个文本模型 | DeepSeek 预设经 OpenAI 兼容路径 | 部分实现 | 假网关合同和模型拉取证据；真实 Key 验收仍待用户 |
| `grsai.ts` | 4 个默认图像模型，带图像请求适配 | 无 GRSAI 私有图片请求适配 | 缺失 | 图像生成/参考图参数、结果解析和错误态的 fake 回归 |
| `ima2.ts` | 本机双端点：文本 OAuth 代理与图片服务；3 个文本、3 个图片模型 | 无 ima2 供应商；`azt` 不是等价替代 | 缺失 | 桌面专用 ima2 配置、双端点字段、图片多参考与长超时状态；iOS/Android 明确不展示本机回环预设 |
| `klingai.ts` | 20 个默认视频模型，支持图像/首尾帧/多参考等模式 | 无 Kling 协议 | 缺失 | 视频请求、任务状态映射、轮询、取消和能力编辑，全部以 fake gateway 验证 |
| `minimax.ts` | 12 个默认文本、图像、视频模型，包含参考素材上传 | 无 MiniMax 协议 | 缺失 | 多凭证字段、上传引用、图像/视频任务和能力映射的 fake 回归 |
| `null.ts` | 1 个文本模型的开发/兜底适配 | 测试中有 fake gateway，但没有同名用户供应商 | 待分类 | 在范围门确认其是否有用户可达入口；若无，记录 N/A 理由和替代测试位置 |
| `openai.ts` | 5 个默认文本模型 | OpenAI 预设及通用 OpenAI 兼容文本/图像/TTS | 部分实现 | 将默认模型目录与当前官方目录分开管理；图像/TTS 为 Flutter 扩展，仍需各模态 fake 合同和用户验收记录 |
| `toonflow.ts` | 11 个托管文本、图像、视频模型 | 无 ToonFlow 托管协议 | 缺失 | 托管鉴权、模型目录、视频任务生命周期和失败态 |
| `vidu.ts` | 11 个图像、视频模型；视频带时长、分辨率、首尾帧和音频能力 | 无 Vidu 协议 | 缺失 | Vidu 视频/图像请求、轮询、取消及能力映射的 fake 回归 |
| `volcengine.ts` | 42 个默认文本、图像、视频模型；含完整 Seedance 与 Seedream 目录 | 火山文本/图片/Seedance 协议，默认种子约 5 个模型 | 部分实现 | 补齐原版能力目录、模型级参考素材/音频/时长-分辨率语义，并为每项写本地协议测试 |
| `volcengineSd2.ts` | 3 个 Seedance 视频模型，独立供应商预设与配置面 | Flutter 以 `volcengine` 的 Seedance profile 承接部分模型 | 部分实现 | 证明配置字段、提示词模板和任务协议与该独立预设一致；不应只因模型名相同而判等价 |

## Flutter 现有协议面

| Flutter 协议/文件 | 已覆盖 | 不能代表的原版能力 |
| --- | --- | --- |
| `openai_compatible`，`providers/openai_*.dart` | 文本、视觉理解、结构化输出、图像、TTS、`/models` 候选 | 私有图像/视频负载、供应商特有认证、多端点和异步视频任务 |
| `anthropic`，`providers/anthropic_text.dart` | 原生 Messages 文本、视觉、结构化 JSON、首轮工具调用、`/models` | 原生多轮工具闭环。当前没有保留 `tool_use_id` 或 content block，不能发送 `tool_result` |
| `volcengine`，`providers/volcengine_video.dart` | Seedance 提交、轮询、取消；现有火山图像/文本路径 | Kling、MiniMax、Vidu、AtlasCloud、ToonFlow 等非火山视频协议；完整火山目录与逐模型能力 |

当前的模型编辑器允许录入 `video` 类型，但引擎会拒绝任何非 `volcengine` 视频模型。这是防止把别家模型错误送往 Seedance 的临时保护，不是 1:1 完成状态；后续必须以独立适配器替换这条全局拒绝，而不是取消视频模型配置能力。

## 当前配置链路的核验门（2026-07-19）

本节只记录供应商配置基础设施的当前结论，不改变上表对原版私有协议
“部分实现/缺失”的判定。所有验证均为本地引擎、fake gateway 或 widget
测试；没有提交、轮询或下载任何真实视频任务。

| 核验门 | 当前行为 | 自动化证据 | 结论 |
| --- | --- | --- | --- |
| 远程地址与凭证 | 启用中的 loopback 供应商改为远程地址时，必须已有 Key 或同时提供新 Key；校验失败不改写原配置。 | `provider_preset_create_test.dart`：`无 Key 的 loopback 供应商不能改为启用的远程地址` | 已关闭 |
| 视频协议边界 | 非 `volcengine` 的 video 模型在模型编辑和配置导入两条入口均被拒绝；video 连通测试在分派网关前拒绝。 | `provider_preset_create_test.dart`：保存、导入、连通测试三条回归 | 已关闭；正常视频生成代码保留给用户最终手动验收 |
| Anthropic 模态边界 | 原生 Messages 适配当前只实现文本、视觉理解和文本工具；模型编辑或配置导入若将 `anthropic` 设为 `image`/`tts`，会在写库前拒绝，避免后续误走 OpenAI 图片或语音端点。 | `provider_preset_create_test.dart`：`Anthropic 供应商只允许保存 text 模型，导入也不能绕过` | 已关闭；完整原生多轮工具闭环仍是独立缺口 |
| 付费连通测试 | 文本、图片、配音测试在 `policy.confirmMoney` 开启时均先弹出明确的真实请求/可能计费确认；关闭开关才直接发起。 | `settings_screen_test.dart`：`付费连通测试先确认，视频保持人工验收` | 已关闭 |
| 凭证可见性 | 预设与自定义表单的 API Key 默认遮蔽，并都提供本地显隐切换。 | `settings_screen_test.dart`：`自定义供应商表单默认遮蔽 API Key`；`provider_preset_form_test.dart` | 已关闭 |
| 协议表述 | `anthropic` 在列表和编辑表单显示“Anthropic 原生”，不再伪装为 OpenAI 兼容；自定义供应商可明确选择该协议。 | `settings_screen_test.dart`：`Anthropic 供应商在列表和编辑页都显示原生协议` | 已关闭 |

仍待处理的是 **azt 默认目录漂移**：本机 `/v1/models` 可见
`gpt-5.6-sol`、`gpt-5.6-terra`、`gpt-5.6-luna`、`gpt-5.5`、
`gpt-5.3-codex-spark`，而预设仍保留历史的 `gpt-5.4`、`gpt-5.4-mini`。
`/models` 不返回 `gpt-image-2` 不能单独推断图片不可用，图片能力应继续以
独立模态证据判断。这个目录同步问题不影响本次配置安全收口，但不能据此
把 azt 或供应商模块判为完整等价。

## 收敛原则

1. 以“一个稳定的 Dart 协议适配器 + 明确 capability 元数据”承接一个上游线，不恢复或执行原版 TypeScript 插件代码。
2. 每新增视频适配器先写 fake gateway：提交负载、状态归一化、下载成功结果、失败、取消、重启恢复。通过后才在设置页开放该视频模型。
3. 不以 12 张新供应商画廊卡替代原版 13 个文件的逐项复刻。国际新预设可保留，但必须作为扩展项，和原版基线行分开计分。
4. 供应商卡的“未验证”只表示没有真实 Key 验收，不能把“无协议实现”伪装成“可用但未验证”。

## 关联记录

- 主清单：[`master-checklist.md`](master-checklist.md) 的 `W6D-VENDOR-001`、`W6D-VENDORTEST-001`、`W9A-VENDOR-BESPOKE-001`、`W9A-VENDOR-DEVTEMPLATE-001`。
- 供应商预设人工证据：[`provider-presets-acceptance.md`](provider-presets-acceptance.md)。
- 供应商画廊实施记录：[`../superpowers/plans/2026-07-18-provider-presets.md`](../superpowers/plans/2026-07-18-provider-presets.md)。该计划的已落地部分仅作为通用配置基础设施，不改变本矩阵的状态判定。
