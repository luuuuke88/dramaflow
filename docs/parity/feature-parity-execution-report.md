# DramaFlow 对齐执行总览

更新时间：2026-07-19

目标基线：ToonFlow 1.1.8 的用户可观察行为；不是复制 Electron、Node 或 Vue 的内部实现。

适用平台：macOS 桌面、iOS、Android。任何一端不可用的功能不得标记为已完成。
视频边界：本阶段只实现视频相关的本地数据、队列、状态恢复、供应商协议和 UI；**不发起真实视频生成请求**。Seedance 等真实生成由用户在最终阶段自行验收。

## 1. 这份文档解决什么问题

[`master-checklist.md`](master-checklist.md) 是逐条、逐文件的权威对照清单：每行都包含 ToonFlow 源码证据、DramaFlow 对应代码、自动化测试与验收方式。本文件不重复那 201 行长表，而是把审计结果转换成开发顺序、完成标准和跨端门槛。

后续任何新功能或修复都必须：

1. 先定位并更新主清单对应 ID；没有 ID 的新增行为先入库存。
2. 证明 macOS 桌面和移动端均可操作，不能只在其中一端“看起来能显示”。
3. 写 engine/widget 测试；视频真实调用例外，但必须用 fake gateway 覆盖提交、轮询、恢复、取消、失败与重试。
4. 只有“已验证等价 / 已验证更优 / 不适用”才可算完成；“部分实现”一律仍在待办。

## 2. 审计基线与覆盖结论

审计同时冻结以下三类基线，避免只看一半源码得出错误结论：

- Electron 后端与随包资源：[`baseline-manifest.json`](baseline-manifest.json)
- ToonFlow Web 前端：[`inventory.json`](inventory.json)
- 已打包 macOS 应用的运行时能力：[`baseline-runtime-capabilities.json`](baseline-runtime-capabilities.json)

机械库存共 **538 项**，由 [`check_no_orphans.js`](../../tool/parity/check_no_orphans.js) 校验为 **538/538 已在主清单覆盖**。这说明没有已知路由、页面、Socket、表、设置项、资源或平台入口被审计遗漏；它不等于所有功能已经完成。

主清单当前有 **201 条 `W*` 审计记录**；其中 1 条是 W2 的历史架构证据留档，不代表用户功能、不参与六态评分。因此可评分的用户功能条目为 **200 条**，状态为：

| 状态 | 数量 | 含义 |
| --- | ---: | --- |
| 已验证等价 | 77 | 已有源码对照与自动化证据 |
| 已验证更优 | 0 | 尚未以打包版黑盒用例证明“更优” |
| 不适用 | 11 | 有明确理由的 Electron/分发环境专属项 |
| 部分实现 | 92 | 功能、数据语义、交互或测试仍有缺口，不能算完成 |
| 缺失 | 20 | 尚无可接受的等价实现 |
| 未审计 | 0 | 无 |

已验证等价与不适用合计 **88/200（44.0%）**；以“用户可用的完整复刻”为标准，项目仍处于中段，不能宣称接近 100%。

## 3. 已经具备的主流程

以下能力已经有较强对照与测试证据，后续以修缺口和跨端回归为主，不重写：

- 项目、小说章节、事件分析、剧本、资产、任务中心的核心 CRUD。
- 素材中心的角色/道具/场景管理、图片候选、TTS 绑定与批量生成入队。
- 分镜首帧批量生成的任务状态、参考图、恢复与错误落库。
- 单镜运镜提示词生成，以及视频候选的本地状态机、幂等提交、轮询、恢复、取消和删除代码。
- 工作台中已有的轨道选片、时长、提示词编辑及候选管理。
- 基础项目壳、桌面侧栏和移动底部导航。

这些结论的逐文件证据位于主清单中的 `W6-*`、`W7B-*` 与 `W7C-*` 行；“有基础代码”不意味着与其相关的画布、Agent、工作台或设置页面已经验收完毕。

## 4. 明确缺失的 20 项

下面项目必须实现等价能力，或在完成行为与许可证审查后给出可接受的“不适用”理由；不能静默删掉。

| 组别 | 主清单 ID | 缺口 |
| --- | --- | --- |
| 技能 | `W6E-LIB-SCANSKILLS-001` | 技能目录重扫 |
| 设置与供应商 | `W7A-AGENT-USEMODE-001`、`W7A-AGENT-SETKEY-001`、`W7A-DB-CLEARTABLE-001`、`W7A-ABOUT-UPDATE-001`、`W7A-MEMORY-PARAMS-001`、`W7A-VENDOR-CODE-001` | Agent 模式、快速配置、数据清理、更新、记忆参数与供应商高级配置 |
| 画风与 Agent | `W7E-ARTSTYLE-EXTRACT-001`、`W8-AGENTUTIL-MEMORY-001` | 画风提示词提取、三层 Agent 记忆/RAG |
| 数据与设置镜像 | `W9A-DBTABLE-SKILLATTRIB-001`、`W9A-SETTING-MEMORYPARAMS-001`、`W9A-SETTING-AGENTUSEMODE-001` | 技能归属映射、记忆参数和 Agent 模式的持久化/设置面 |
| 供应商兼容 | `W9A-VENDOR-BESPOKE-001`、`W9A-VENDOR-DEVTEMPLATE-001` | 私有协议适配能力与开发模板。实现应使用可维护的通用适配层，不能直接复制私有凭证或服务端代码。 |
| 原版 Agent 技能 | `W9C-PRODSKILL-CORE-001`、`W9C-SCRIPTSKILL-CORE-001`、`W9C-PRODSKILL-PIPELINE-001`、`W9C-PRODSKILL-TECHNIQUE-001` | 剧本/制作 Agent 的原版分层提示词与按需技法资料 |
| 平台生命周期 | `W10-BACKEND-LIFECYCLE-001`、`W10-APPLIFECYCLE-DOCK-001` | 数据目录预检/优雅退出，以及 macOS Dock 重开行为的 Flutter 等价方案 |

## 5. 部分实现的四个大块

92 个“部分实现”不是零散小毛病。下面四块决定了用户会不会觉得它真的是 ToonFlow 的 Flutter 版。

### A. 无限画布与制作页（W1）

制作画布的节点骨架和编辑入口已有。2026-07-19 已补齐标题栏拖动与自动布局复位：六个节点在当前会话共用一张与 ToonFlow `nodePositions` 同语义的坐标表，切换剧集不会丢失当前排布；拖动按当前缩放换算场景坐标，并会锁住画布视口以避免节点拖动与画布平移同时发生；自动布局可恢复原始主链。桌面保留画布，`<840dp` 则改为六个纵向 Tab、节点检查器和全屏 Agent；390dp widget 回归已走到同一工作台与本地 fake 合成链。参考资料为 [`w1-canvas-reference.md`](w1-canvas-reference.md)。

尚未达标的部分：缩放围绕光标、触控板与 iOS/Android 的实际手势、选区，以及大量节点下的帧率没有 profile 实测。2026-07-19 的静态复核还确认：ToonFlow 可在设置中选择画布滚轮“缩放”或“滚动”，而当前 Flutter 3.44.4 `InteractiveViewer` 未设置 `trackpadScrollCausesScale`，因此 macOS 触控板双指滚动默认平移且无模式选择。完成定义：同一套画布在 macOS 鼠标/触控板与 iOS/Android 手势下都能完成平移、缩放、节点编辑，并具备等价的滚轮模式选择；性能指标必须通过 profile 实测，而不是凭视觉判断。

本项自动化证据：`app/test/widgets/df_widgets_test.dart` 验证 2 倍缩放下的节点拖动坐标换算；`app/test/widgets/production_screen_test.dart` 驱动真实制作页的节点拖动与自动布局复位。两项都不调用任何视频供应商。

### B. 原版 Agent 体系（W2）

当前是精简对话助手，尚未覆盖 ToonFlow 的剧本/制作 Agent 分层决策、执行、监督、摘要、向量记忆、Markdown 技能激活与复杂流程恢复。2026-07-19 逐文件复核确认：Flutter 当前会把所有启用 Markdown 技能正文注入每轮 system prompt，虽有安全的文件读取 API，却没有将其作为模型可调用的按需工具；原版则以 `activate_skill` / `read_skill_file` 进行两段式加载，并按子 Agent 阶段筛选技能。原版 Web 的 `scanSkills` 客户端动作在 1.1.8 后端/打包 bundle 没有对应路由，不能按失效按钮复刻。完整证据和验收边界见 [`skill-runtime-matrix.md`](skill-runtime-matrix.md)。

完成定义：以 ToonFlow 可观察行为为准移植，**禁止**恢复旧 DramaFlow 那套非原版的 JS 解释器、ES 查询 DSL 或无法维护的 2 万行单体 Agent；所有花钱或破坏性工具必须经过同一确认策略。

### C. 非线性工作台与视频准备（W3）

视频轨、候选和基础状态机已有，但自由多轨编辑、媒体库、预览、分镜网格导出、按轨批量提示词后台任务、共享轨语义、音频参考装配等仍是部分实现。参考资料为 [`w3-nle-reference.md`](w3-nle-reference.md)。

完成定义：先把本地数据/编辑/导出代码和 fake-provider 测试做全；不在开发或 CI 中消耗 Seedance 额度。真实视频生成、下载质量和供应商账号权限由用户在最终验收单独测试。

### D. 设置、预设与移动适配（横切）

供应商预设、模型选择、画风库、导入导出、设置高级项和移动版对话框仍按主清单持续补齐。供应商预设已完成目录、预填表单、画廊、`/models` 候选导入和离线回归；2026-07-19 额外修复了 390px 模型编辑器工具栏溢出，并将桌面本地 OAuth 预设 azt 从 iOS/Android 画廊隐藏。预设创建现以“禁用 provisioning 记录 → 写入 Keychain → 启用”为顺序执行；冷启动会恢复已写入凭证的中断创建，并清除未写入凭证的远程残留。当前只允许 `volcengine` 声明或提交 video 模型，这是防止把其他模型错误按 Seedance 格式请求的**临时保护**，不是供应商视频能力已等价的结论。原版 16 个设置模块与 Flutter 7 个自适应分区的逐项映射、移动端证据强度及不适用边界见 [`settings-module-matrix.md`](settings-module-matrix.md)。

它改善的是通用供应商配置体验，**不改变**主清单 `W6D-VENDOR-001` 的“部分实现”结论：原版可编辑 vendor 插件、私有协议适配和动态字段仍未复刻。进一步的逐文件审计显示：原版 13 个 vendor 中，ima2、MiniMax、Kling、Vidu、AtlasCloud、GRSAI、ToonFlow 托管和独立 Seedance 2.0 线均未由当前三类 Flutter 协议完整承接。详见 [`vendor-protocol-matrix.md`](vendor-protocol-matrix.md)。正式人工验收表已存在于 [`provider-presets-acceptance.md`](provider-presets-acceptance.md)，但除 azt 外均保持“未验证”标识；移动发现记录位于 [`mobile-adaptation-findings.md`](mobile-adaptation-findings.md)。这些改动不得因“桌面能用”而标绿。

完成定义：设置与供应商配置不泄露凭证；模型列表拉取、失败提示、编辑回填、删除与导入导出均可离线 mock 验证；窄屏没有被截断的关键按钮或不可滚动的表单。

## 6. 推荐实施顺序

顺序以风险和用户体感为先，不以“代码行数”或“看起来很复杂”为先：

1. **收拢当前工作区**：审查并完成正在修改的供应商预设、画风库和移动布局；每项回写主清单。
2. **补齐 W1 画布**：先定义可量化的桌面/移动性能与手势测试，再改渲染和交互。
3. **补齐 W2 Agent**：按原版行为拆为小模块和明确接口，补记忆、技能、分层流程与确认策略。
4. **补齐 W3 工作台**：完善本地编辑、轨道语义、预览/导出和视频 fake-provider 状态机；保留真实视频调用给用户验收。
5. **消化设置与长尾缺口**：处理第 4 节 20 项和主清单余下的部分实现，逐项关闭。
6. **跨端收口**：仅当全部条目变为绿态或有可接受不适用理由后，再做一次完整的 macOS、iOS、Android 验收。

任何里程碑都应先写独立 spec 和任务计划，不允许把下一阶段的功能趁机塞进当前改动。

## 7. 统一验收门

每一个可见功能需要同时通过以下门槛：

| 门槛 | 必须证据 |
| --- | --- |
| 对照 | 主清单存在 ToonFlow 源码/打包版证据与对应 DramaFlow 文件 |
| 引擎 | 数据变更、失败、恢复和边界条件有 Dart engine 测试 |
| 桌面 | macOS 桌面尺寸可访问，鼠标/键盘操作完成主流程 |
| 移动 | iOS 与 Android 窄屏可访问，滚动、触控、弹层和关键命令可完成，不以“能渲染”代替可用 |
| 性能 | 对画布、列表、时间线等高负载区域有 profile 或基准证据 |
| 视频例外 | 只跑 fake gateway 和本地文件夹夹具；不得在自动化中调用真实视频模型 |

基础命令：

```bash
cd /Users/luke/Documents/aivideo/dramaflow
node tool/parity/check_no_orphans.js
cd app && flutter analyze && flutter test
```

## 8. 现在的真实结论

DramaFlow 已拥有短剧生产主链路的一部分可靠底座，但还不是 ToonFlow 的 1:1 Flutter 复刻。下一步的正确做法不是继续添加零散页面，而是以主清单为唯一账本，优先完成画布、Agent、工作台和跨端可用性四条主线；每完成一项就用证据把“部分实现/缺失”变为绿态。

### 最近核验：中等宽度移动壳

2026-07-19 已补充 760–800dp 回归：项目、画风、手册与剧本的编辑/删除操作在无 hover 的平板触控界面仍可达；剧本与小说工具栏的真实 `RenderFlex` 溢出已修正；素材和事件页同宽度通过渲染验证。详细证据与用例名称见 [`mobile-adaptation-findings.md`](mobile-adaptation-findings.md)。

### 最近核验：供应商预设的可恢复创建与协议边界

2026-07-19 对供应商预设做了针对性复核。远程预设或自定义供应商若没有 API Key，现在会在创建前拒绝并保持零落库；本机 loopback 代理仍允许无 Key 配置。由于 SQLite 与系统 Keychain 不能组成单一事务，两条创建路径都会先保存为禁用的 `provisioning` 状态，只有凭证写入完成后才启用；同名创建会在写 Key 前被拒绝，绝不覆盖已有凭证。应用重启时，已持久化凭证的中断创建会收敛为可用配置；没有凭证的远程残留会被清理，避免出现“列表中显示已添加、实际永远无法调用”的假成功。

视频协议当前只实现火山 Seedance。模型编辑层、正式 HTTP 网关和设置页的 `testVideoModel` 连通测试均拒绝非 `volcengine` 的 video 模型，且拒绝发生在任何 HTTP 请求之前；这是防止将 OpenAI 兼容供应商误按 Seedance 任务格式调用的临时保护，**同时也是对原版 MiniMax、Kling、Vidu、AtlasCloud、ToonFlow 托管视频线的明确缺口**，不能描述为“未减少视频能力”。未来接入新的视频供应商时，必须先实现对应的提交、轮询、取消和 fake-gateway 回归，再开放该协议的 video 类型；开发和 CI 始终不提交真实视频任务。自动化证据：`app/test/engine/provider_preset_create_test.dart`、`app/test/engine/engine_facade_test.dart`、`app/test/engine/providers_test.dart` 与 `app/test/widgets/settings_screen_test.dart`；没有发起真实视频、图像或文本生成。

### 最近核验：Claude 原生协议闭环

2026-07-19 已将 Anthropic 预设从错误的“OpenAI 兼容模式”改为原生 `anthropic` 协议。网关对普通文本、强制工具 JSON、**Agent 首轮工具调用**、参考图视觉理解、`/models` 鉴权和文本连通测试分别走 Messages API 规定的 `x-api-key`、`anthropic-version`、顶层 `system` 与 `tools[].input_schema` 格式；六条 fake-Dio 回归都断言请求不会落到 `/chat/completions`。xAI 的过期 `grok-4.3` 预设模型也已移除，仅保留当前目录可核实的 `grok-4.5`。

这不是云端验收：所有验证均在进程内假网关完成，未发起真实文本、图像或视频请求，Anthropic 画廊卡仍显示“未验证”。另外，当前 Agent 历史仍以现有的文本化工具结果接口传递上下文，尚未形成 Anthropic 原生 `tool_use_id` / `tool_result` 往返；这属于 Agent 完整协议对齐的后续缺口，不能借本轮适配宣称全量原生代理等价。证据见 `app/test/engine/anthropic_gateway_test.dart`、`app/test/engine/provider_presets_test.dart` 与 `app/test/widgets/provider_preset_gallery_test.dart`。

### 最近核验：首次启动引导

2026-07-19 已补齐欢迎页、中文/英文/日文切换、三步引导、供应商/模型绑定深链、返回引导以及本机一次性完成状态；390dp 路由回归还修正了底部操作栏的窄屏溢出。该功能仍是“部分实现”：原版第二步的完整 Agent 配置面未具备，不能因引导壳已出现而把相关 Agent 能力标绿。证据见 `app/test/engine/onboarding_test.dart`、`app/test/widgets/first_run_guide_test.dart` 和 `app/test/widgets/onboarding_router_test.dart`。

### 最近核验：小说章节编辑

2026-07-19 已为原有编辑弹窗补齐桌面和 390dp 回归：桌面端从真实章节入口编辑名称、事件和正文后立即落库并刷新列表；移动端使用全屏表单，取消不会写入任何修改。该行由“有实现但无 UI 证据”的部分实现提升为已验证等价。证据见 `app/test/widgets/novel_screen_test.dart` 的两个章节编辑用例与 `app/test/engine/novel_crud_test.dart`。

### 最近核验：音频资产弹窗

2026-07-19 已补齐音频 tab 的真实“新增音频”入口回归：桌面端覆盖三份不同的本地测试文件、删除中间条目后保存其余两份、再编辑且保留既有文件；390dp 端覆盖全屏表单与单条本地文件落库。随后按 ToonFlow `addAudioAssets.vue` 补上每条上传区的桌面 `DropTarget`：macOS 使用 `public.audio`、移动/Web 使用 `audio/*`、Windows/Linux 使用常见音频扩展名，点选和 Finder 拖入共用同一落库路径。新增回归直接调用 `DropTarget.onDragDone`，以路径型 OGG 夹具验证字节与扩展名正确保存。为覆盖打包 macOS 的安全作用域文件访问，图片与音频还共用 `desktop_drop_file.dart`：有 Apple bookmark 时读前申请权限、读后释放，文件名缺失时从路径回退。

素材库现也按 ToonFlow 的媒体预览语义区分图片、视频和音频：图片可缩放预览，视频显示播放入口，音频预览显示当前音频名称并在播放器加载失败时保留该上下文。移动端用本地缺失夹具覆盖真实点击、预览层和失败态文案，不初始化任何原生播放器或供应商。

该行暂仍保留“部分实现”：需要在解锁后的打包 macOS 应用里确认真实 Finder 拖入与本地音频试听，且需继续完成 iOS/Android 真机可用性检查。另发现桌面 `DataTable` 的整行多选与父子资产展开存在原生交互冲突；ToonFlow 使用“仅复选框选择、点击行不选择”的语义，Flutter 侧需在后续素材表重构中单独对齐，不能以移动端通过替代桌面验收。自动化不调用任何语音或视频供应商。证据见 `app/test/widgets/assets_tts_screen_test.dart` 与 `app/test/widgets/assets_mobile_screen_test.dart`。

### 最近核验：资产单图生成候选

2026-07-19 已为 `W6F-ASSETS-GENIMG-001` 补齐完整离线 widget/引擎回归：从角色行打开生成弹窗，覆盖智能提示词、模型和 1K/2K/4K 选择、任务入队、生成中到完成的候选刷新、版本选择与保存；另覆盖未选模型不入队、候选图删除二次确认、自定义上传后必须显式点选、以及参考图选择器在 macOS (`public.image`)、移动/Web (`image/*`) 与 Windows/Linux（常见扩展名）上的过滤语义。代码还将 Finder 拖放目标限制在桌面端，移动端保持系统文件选择器；实际读取经共享的 macOS security-scoped access 工具完成。

本轮复审发现总清单曾滞后地标注“无 UI 测试”，已纠正。新增的 390dp 回归从移动素材行的 `… → 生成` 真实入口进入全屏表单，验证模型选择、向下滚动到候选区，以及固定在底部的确认动作都可达；桌面仍覆盖双栏弹窗的完整生成与保存路径。所有七条用例使用假网关、内存数据库和临时图片文件，不请求真实图像或视频模型。

自动化证据为 `app/test/widgets/assets_generate_image_dialog_test.dart`（7 项，无真实供应商请求）。这条能力据当前源码、桌面与移动入口回归已标为“已验证等价”；打包 macOS 的真实 Finder 拖入和候选预览仍会纳入后续体验检查，但不再被误写成尚未实现的功能缺口。该检查只使用本地夹具，不调用视频模型或任何付费生成服务。

本批次已执行 `flutter analyze`、排除显式真实供应商 QA 与 P0 live preflight 的 81 个离线/模拟测试文件（665 项全绿），并以最新源码完成 `flutter build macos --debug`。`QA_FULL`、`P0_LIVE` 均未设置；没有发起 AZT、图片、语音或 Seedance 请求。macOS 应用的真实窗口与 Finder 拖放仍须在桌面解锁后手工验收，构建成功不替代该步骤。

### 最近核验：项目手册画廊与编辑器

2026-07-19 已对项目对话框中的视觉/导演手册完整补证。两类手册共用画廊与编辑器：封面现在对视觉和导演手册同样必填，已有封面的卡片可打开本地大图预览，触控宽度下编辑、删除和预览均无需 hover。桌面入口验证可从项目对话框打开新建视觉手册；390dp 路径验证可打开已有手册的编辑表单、保留既有名称、关闭后再经确认删除并从本地技能目录移除。导演手册的封面校验、三标签填写、上传与落盘由独立编辑器回归覆盖；项目保存回归同时验证视觉和导演手册选择会分别写入 `artStyle` 与 `directorManual`。

自动化证据为 `app/test/engine/manuals_test.dart`、`app/test/widgets/manual_gallery_test.dart`、`app/test/widgets/manual_editor_test.dart` 和 `app/test/widgets/project_page_test.dart`（本次相关 21 项通过）。测试使用临时目录、内存数据库和本地 1px PNG 夹具，不调用任何图像、文本或视频供应商。

### 最近核验：全局画风库与项目视觉手册的边界

2026-07-19 复核确认两者不能混为同一功能。当前 ToonFlow 项目页实际加载 `projectDialog.vue`，以视觉/导演手册包写入项目的 `artStyle` / `directorManual`；Flutter 已内置并逐文件校验两类默认手册包。旧 `addProject.vue` 虽引用全局 `artStyle.vue`，但该组件不在 `Toonflow-web` 的 9c4cb0e git 基线，不能作为可用前端流程的证据。

原版服务端仍保留 `o_artStyle` 的增改查和多参考图 AI 提取画风提示词接口。Flutter 已有本地 `o_artStyle`、封面落盘、CRUD 及独立弹窗测试，但生产代码没有调用 `showArtStyleLibrary`，所以用户无法进入该库；AI 提取也完全缺失。主清单据此把资产页与全局画风 CRUD 均校正为“部分实现”，不把底层代码或隔离测试冒充为用户可用功能。此处不改行为，也不发起任何真实模型调用；后续必须先决定独立画风库的正式入口和它与项目手册的关联语义，再做实现与验收。

### 最近核验：项目保存校验的完整契约

2026-07-19 复读当前有效的 ToonFlow `projectDialog.vue` 后，确认此前仅记录“视觉/导演手册必须选择”还不完整。原版按固定顺序要求十项都有值：项目名、小说类型、图片模型、视频模型、视觉手册、导演手册、影片比例、简介、图片画质、视频模式；任一项缺失就留在表单并提示，绝不写入项目。Flutter 当前只检查项目名，因而能保存配置不完整的项目，并在后续提示词解析或生成阶段才失败。

这项已回写 `W6F-PROJECT-DIALOG-001`。后续修复必须用一组桌面与 390dp 回归逐项验证“当前缺项不保存、提示对应文案、补齐后恰好创建一次”，并同时验证内置手册卡片标题从原始 README 首行读取，而非技术目录名。没有进行任何真实文本、图像或视频调用。

### 最近核验：项目入口的模型保护

2026-07-19 同一轮复核还确认，ToonFlow 点击项目卡片时会先验证图片模型和视频模型都已填写，并向已启用供应商查询两者是否仍可解析；任一为空或已失效，就显示模型不可用提示并直接打开该项目的编辑表单。Flutter 的 `_openProject` 目前没有这道保护，会对无模型或过期模型的项目直接路由进入小说/剧本页。现有 Flutter 点击卡片回归也正是以无模型项目成功跳转，故这不是推测。

该差异已与十项保存校验一起写入 `W6-PROJECT-001`。后续修复需覆盖桌面与 390dp：缺图像模型、缺视频模型、配置指向已禁用/已删除模型时均不进入项目而打开编辑；有效双模型时仍只进入一次目标页。验证只能查询本地配置和 fake gateway，不能为此调用真实图片或视频服务。

### 最近核验：塑角造景批量参考图工作区

2026-07-19 已完成 `W6-CORNERSCAPE-001` 与 `W6-CORNERSCAPE-002` 的页面级复核。`W6-CORNERSCAPE-001` 纠正了旧审计遗留的“仅角色数据源、绑定状态/名称筛选、全选未绑定、缺少通用测试”描述：原版 `getAllAssets` 与当前 `cornerScapeAssets` 均提供角色/场景/道具顶层资产，音频操作是任一资产详情内绑定或解绑一个音频，以及对当前所选通用资产批量 AI 匹配。桌面 widget 证据直接覆盖三类资产数据、场景/道具详情绑定/解绑/试听，以及筛选后角色选择的批量匹配任务提交；场景/道具通用批量匹配由 `app/test/engine/audio_bind_test.dart` 覆盖，对应资产数据边界由 `app/test/engine/assets_test.dart` 支持。

`W6-CORNERSCAPE-002` 的桌面证据覆盖角色/场景/道具类型筛选、按提示词和生成状态快捷选择、反选/清空、仅预览已选资产的生成图、取消生成的拒绝与确认路径、历史图切换、详情提示词失焦保存与 AI 润色、按当前模型/分辨率重生成，以及角色/场景/道具共用的音频入口。复审修复后，取消任务会把该任务仍为“生成中”的预插图片置为带 `errCanceled` 的“生成失败”，保留已完成历史，并阻止取消后晚到的图片结果回写；确认框只取消打开时捕获的同一任务，不会误取消替代任务。批量提示词命令现直接入队 `batchPolishAssetPrompts`，补充要求使用任务私有载荷，逐资产失败不会中断后续项。详情从当前选中图读取分辨率，切换带分辨率的历史图会同步重生成默认值，失败的当前图明确显示失败态。该证据来自 `app/test/widgets/corner_scape_screen_test.dart` 与 `app/test/engine/assets_test.dart`。

### 最近核验：模型提示词文件库与绑定

2026-07-19 已完成 ToonFlow `modelMap` 的本地等价闭环。设置页按供应商列出已启用的图片与视频模型；进入模型可筛选同类型的可复用模板，并完成新建、编辑、绑定、解绑和删除。删除前会显示受影响模型数。模板正文、路径校验和绑定关系全存于本地 SQLite 的 `o_modelPromptTemplate` / `o_modelPrompt`；导入导出、旧 `o_modelPrompt` 映射迁移、Seedance 解析优先级和多模式历史映射均由引擎测试覆盖，不再依赖 Electron 运行目录中的可写 Markdown 文件。

验证包含桌面完整流程（空名称保存不关闭、建模板、绑、编辑、删除确认、解绑）和 390dp 移动流程（滚动进入模型、绑定既有模板、编辑保存），并回归整个设置页的 15 条用例。所有测试使用内存 SQLite、临时目录、假网关和假凭据仓；没有调用文本、图像、音频或视频供应商，也没有提交或轮询视频任务。

紧随其后的 Seedance 模板审计也已闭环：此前完整 Seedance 2.0 的能力声明虽列出四种模式，但启动仅写入 Mini 的单条映射，导致 Full/Fast 可能在本地解析时缺模板。现在首次本地播种会为 Full 与 Fast 各写入 text、首帧、首尾帧和多参考四条映射，Mini 保留其多参考模板；四个模型路径共用四份模板正文。播种完成后记录本地标记，用户解绑某模型不会在重启时被重新绑定。验证只读取临时模板文件、SQLite 和假网关，未提交或测试视频生成。

新增的 390dp 回归使用 `Key('cornerscape-scroll')` 驱动同一工作区：实际筛选场景、快捷选择未生成项、滚动到单列资产卡、打开并关闭详情、确认详情底部操作可达，再滚动到批量命令，经真实 `ModelSelect` 夹具和共享花费确认策略只入队目标场景的 `asset_image_generation` 任务。用例同时断言卡片宽度不超过 390dp、单列宽度可用且整个交互无布局异常；桌面仍保留左侧设置与右侧多列卡片布局。

所有自动化均使用内存数据库、临时媒体目录、本地供应商/模型配置和假网关，只验证 UI、策略确认与本地任务入队，不发起真实文本、图像、音频或视频请求。`W6-CORNERSCAPE-002` 据此提升为“已验证等价”。真实供应商图像/视频生成仍是用户负责的最终验收，本轮明确未执行，也不将任务入队、分析通过或 macOS 构建成功表述为真实生成验收。

### 最近核验：单剧本导入与关联资产

2026-07-19 已补齐单个“新建剧本”对话框的真实入口回归。桌面端同时覆盖点击选择 TXT、Finder 拖入 TXT、旧 `.doc` 的明确转换提示，以及选择角色和场景后保存关联资产；音频不会混入该选择器。正文为空时会先按原版顺序提示补充正文，项目单集字数上限会即时禁用确认。`.docx` 的段落提取和损坏文件失败态由 `novel_parse_test.dart` 的引擎级夹具覆盖。

390dp 下相同入口使用全屏编辑表单，仍可直接输入并保存，确认操作不依赖桌面 hover 或被底部裁切。点击上传不预先限制系统文件面板，而是与拖入共用 MIME/扩展名校验，因而可以对旧 `.doc` 给出原版同样的转换提示；读取错误也会显示明确的本地化提示。实现按 `Platform` 仅在 macOS、Windows、Linux 创建 `DropTarget`，移动端走系统文件选择器。390dp widget 测试覆盖全屏 UI，但没有把宿主 macOS 上的测试冒充成 iOS/Android 文件插件的真机验证。通用自适应桌面对话框也补上 `Material` 容器，修复资产选择器内 `CheckboxListTile` 在桌面主题下无法产生 Ink/背景层的 Flutter 断言。

自动化证据为 `app/test/widgets/script_screen_test.dart`（新增单剧本相关 10 项，整组 17 项）与 `app/test/engine/novel_parse_test.dart`。测试仅使用内存数据库、临时 TXT/DOC 字节夹具和假网关；没有发起 AZT、GPT Image、Seedance 或其他真实供应商请求。`W6F-SCRIPT-ADD-001` 因此由“部分实现”提升为“已验证等价”。
