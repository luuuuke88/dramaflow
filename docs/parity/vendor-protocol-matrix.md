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

本节记录的是已经落地的预设基础设施在当前工作区中仍需关闭的
一致性与付费保护缺口。它们不涉及真实视频调用，也不改变上表的协议
对齐结论。

1. **本机目录是运行时真值，不是历史种子真值。** `azt` 的本机
   `GET /v1/models` 当前列出 `gpt-5.6-sol`、`gpt-5.6-terra`、
   `gpt-5.6-luna`、`gpt-5.5`、`gpt-5.3-codex-spark`，而
   `app/lib/src/engine/provider_presets.dart` 仍以 `gpt-5.4` 和
   `gpt-5.4-mini` 作为默认文字模型。后续修复应把可见文字模型同步到
   目录与默认绑定；`/models` 不返回 `gpt-image-2` 不能单独推断图片
   端点不可用，图片模型需保留独立模态证据。
2. **编辑已存在供应商必须复用远程 Key 校验。** 当前
   `Engine.updateProvider` 在 API Key 为空时可把原本无 Key 的 loopback
   供应商改为远程 `baseUrl` 且保持启用，直到真正解析模型才报缺 Key。
   远程地址转换必须要求已有或新的凭证，或将供应商保持禁用，并补回归。
3. **图片连通测试是付费动作。** 设置页的图片测试会调用
   `HttpProviderGateway.testImageModel` 发起一张真实图片生成，而它没有
   进入流水线的 `policy.confirmMoney` 确认闸。后续应提供明确的
   "将生成一张测试图，可能计费"确认，或默认仅测试文本；视频仍维持
   现有的零 HTTP 拒绝边界。
4. **两个创建入口的凭证显示策略必须一致。** 预设表单已经将 API Key
   设为隐藏输入并提供显隐切换；设置页的“自定义供应商”表单仍以普通
   `TextField` 显示 Key。后者会在录屏、旁观或移动端肩窥场景直接暴露
   凭证，且没有 widget 回归锁定。应复用预设表单的隐藏/显隐交互并补齐
   两个入口的测试；这只影响本地显示，不改变 Keychain 存储语义。

这些门关闭后，供应商预设才可以作为可靠的配置入口；它们仍不能替代
每个私有供应商协议的 fake gateway 合同测试与用户最终真实验收。

## 收敛原则

1. 以“一个稳定的 Dart 协议适配器 + 明确 capability 元数据”承接一个上游线，不恢复或执行原版 TypeScript 插件代码。
2. 每新增视频适配器先写 fake gateway：提交负载、状态归一化、下载成功结果、失败、取消、重启恢复。通过后才在设置页开放该视频模型。
3. 不以 12 张新供应商画廊卡替代原版 13 个文件的逐项复刻。国际新预设可保留，但必须作为扩展项，和原版基线行分开计分。
4. 供应商卡的“未验证”只表示没有真实 Key 验收，不能把“无协议实现”伪装成“可用但未验证”。

## 关联记录

- 主清单：[`master-checklist.md`](master-checklist.md) 的 `W6D-VENDOR-001`、`W6D-VENDORTEST-001`、`W9A-VENDOR-BESPOKE-001`、`W9A-VENDOR-DEVTEMPLATE-001`。
- 供应商预设人工证据：[`provider-presets-acceptance.md`](provider-presets-acceptance.md)。
- 供应商画廊实施记录：[`../superpowers/plans/2026-07-18-provider-presets.md`](../superpowers/plans/2026-07-18-provider-presets.md)。该计划的已落地部分仅作为通用配置基础设施，不改变本矩阵的状态判定。
