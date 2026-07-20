# DramaFlow 对齐执行总览

更新时间：2026-07-21

目标基线：ToonFlow 1.1.8 的用户可观察行为；不是复制 Electron、Node 或 Vue 的内部实现。

适用平台：macOS 桌面、iOS、Android。任何一端不可用的功能不得标记为已完成。
视频边界：本阶段只实现视频相关的本地数据、队列、状态恢复、供应商协议和 UI；**不发起真实视频生成请求**。Seedance 等真实生成由用户在最终阶段自行验收。

## 1. 这份文档解决什么问题

[`master-checklist.md`](master-checklist.md) 是逐条、逐文件的权威对照清单：202 行记录中有 201 行可评分用户能力，每行都包含 ToonFlow 源码证据、DramaFlow 对应代码、自动化测试与验收方式。本文件不重复整张长表，而是把审计结果转换成开发顺序、完成标准和跨端门槛。

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

主清单当前有 **202 条 `W*` 审计记录**；其中 1 条是 W2 的历史架构证据留档，不代表用户功能、不参与六态评分。因此可评分的用户功能条目为 **201 条**，状态为：

| 状态 | 数量 | 含义 |
| --- | ---: | --- |
| 已验证等价 | 83 | 已有源码对照与自动化或平台实机证据 |
| 已验证更优 | 0 | 尚未以打包版黑盒用例证明“更优” |
| 不适用 | 13 | 有明确理由的 Electron/分发环境专属项 |
| 部分实现 | 88 | 功能、数据语义、交互或测试仍有缺口，不能算完成 |
| 缺失 | 17 | 尚无可接受的等价实现 |
| 未审计 | 0 | 无 |

已验证等价与不适用合计 **96/201（47.8%）**；以“用户可用的完整复刻”为标准，项目仍处于中段，不能宣称接近 100%。

### 审计更正：项目手册必选

2026-07-21 复核发现，主清单的 `W9B-ARTSKILLS-001` 与
`W9B-STORYSKILLS-001` 早期备注仍写着“DramaFlow 不强制选择手册”，
这已不符合当前实现。项目向导实际通过
`firstMissingProjectIntakeField()` 按 ToonFlow 十项顺序拦截
`artStyle` 与 `directorManual`，两者未选时都不会写入项目。该结论由
`project_intake_validation_test.dart` 的字段顺序回归，以及桌面与 390dp
项目保存回归共同证明。两行仍维持“部分实现”，但理由应只保留尚未解决的
提示词拼装差异，不能再把已关闭的必选校验计作缺口。

### 审计更正：项目手册目录标识与重复保护

2026-07-21 已补齐 `W6F-PROJECT-DIALOG-001` 早期遗留的手册目录缺口。原版新建视觉/导演手册会以固定目录名创建包并拒绝覆盖同名目录；编辑只写回原目录。Flutter 现在以 `pack` 作为稳定目录 ID：新建时可填写，未填写则从名称派生；已有目录的新建会返回 `errManualExists` 且保留原内容；编辑界面锁定既有 ID，并通过显式 `overwriteExisting` 写回。`manuals_test.dart`、`manual_editor_test.dart` 和 `prompt_resolver_test.dart` 已分别覆盖引擎拒重、跨端表单状态和既有包的受控更新。主清单该长行仍待结构化整理，但本节与 `project-intake-matrix.md` 的“已验证”记录已取代其中“同名保存会覆盖”的旧备注。

### 审计更正：分镜联系表预览与单 PNG 导出

2026-07-21 已关闭 `W6B-NODE-STORYBOARD-002` 与 `W7B-SB-EXPORT-001` 的同一端到端缺口。Flutter 不再以逐镜 `PageView` 代替原版联系表，也不再把首帧散存进目录；它会在后台 isolate 读取有效首帧，按原版最多五列、列/行最大尺寸、白底和连续 `S01` 标签合成为单图。预览先将每图宽度限制在 512px 并输出 JPEG，导出保留原尺寸 PNG，经系统保存面板输出一个文件。纯函数、后台 isolate、桌面实际写盘和 390dp 入口均已有离线回归；完整证据见 [`storyboard-preview-export-matrix.md`](storyboard-preview-export-matrix.md)。

## 3. 已经具备的主流程

以下能力已经有较强对照与测试证据，后续以修缺口和跨端回归为主，不重写：

- 项目、小说章节、事件分析、剧本、资产、任务中心的核心 CRUD。
- 素材中心的角色/道具/场景管理、图片候选、TTS 绑定与批量生成入队。
- 分镜首帧批量生成的任务状态、参考图、恢复与错误落库。
- 单镜与后台批量运镜提示词生成（逐轨任务归属、防重复入队、编辑/清轨不被迟到回包覆写），以及视频候选的本地状态机、幂等提交、轮询、恢复、取消和删除代码。
- 工作台中已有的轨道选片、时长、提示词编辑、候选管理，以及按分镜时长的首帧快速预览与本地 ZIP 导出。
- 基础项目壳、桌面侧栏和移动底部导航。

这些结论的逐文件证据位于主清单中的 `W6-*`、`W7B-*` 与 `W7C-*` 行；“有基础代码”不意味着与其相关的画布、Agent、工作台或设置页面已经验收完毕。

## 4. 明确缺失的 17 项

下面项目必须实现等价能力，或在完成行为与许可证审查后给出可接受的“不适用”理由；不能静默删掉。

| 组别 | 主清单 ID | 缺口 |
| --- | --- | --- |
| 技能 | `W6E-LIB-SCANSKILLS-001` | 技能目录重扫 |
| 设置与供应商 | `W7A-AGENT-USEMODE-001`、`W7A-AGENT-SETKEY-001`、`W7A-ABOUT-UPDATE-001`、`W7A-MEMORY-PARAMS-001`、`W7A-VENDOR-CODE-001` | Agent 模式、快速配置、更新、记忆参数与供应商高级配置 |
| 画风与 Agent | `W7E-ARTSTYLE-EXTRACT-001`、`W8-AGENTUTIL-MEMORY-001` | 画风提示词提取、三层 Agent 记忆/RAG |
| 数据与设置镜像 | `W9A-DBTABLE-SKILLATTRIB-001`、`W9A-SETTING-MEMORYPARAMS-001`、`W9A-SETTING-AGENTUSEMODE-001` | 技能归属映射、记忆参数和 Agent 模式的持久化/设置面 |
| 供应商兼容 | `W9A-VENDOR-BESPOKE-001`、`W9A-VENDOR-DEVTEMPLATE-001` | 私有协议适配能力与开发模板。实现应使用可维护的通用适配层，不能直接复制私有凭证或服务端代码。 |
| 原版 Agent 技能 | `W9C-PRODSKILL-CORE-001`、`W9C-SCRIPTSKILL-CORE-001`、`W9C-PRODSKILL-PIPELINE-001`、`W9C-PRODSKILL-TECHNIQUE-001` | 剧本/制作 Agent 的原版分层提示词与按需技法资料 |

## 5. 部分实现的四个大块

91 个“部分实现”不是零散小毛病。下面四块决定了用户会不会觉得它真的是 ToonFlow 的 Flutter 版。

### A. 无限画布与制作页（W1）

制作画布的节点骨架和编辑入口已有。2026-07-19 已补齐标题栏拖动、刷新、自动布局和首次四步操作教学：六个节点在当前会话共用一张与 ToonFlow `nodePositions` 同语义的坐标表，切换剧集不会丢失当前排布；拖动按当前缩放换算场景坐标，并会锁住画布视口以避免节点拖动与画布平移同时发生。共享画布的 `DFCanvasDragRegion` 还让图片流的卡片图片区可拖动，参数区只锁住画布、不改节点位置。刷新会重建当前本地画布，自动布局会恢复原始主链并重新 fit 视口。首次引导以 SQLite `production.guide.completed` 持久化，桌面高亮真实控件并在窗口跨越紧凑阈值后重新测量，`<840dp` 则使用可滚动的全屏步骤页、六个纵向 Tab、节点检查器和全屏 Agent；390dp widget 回归已走到同一工作台与本地 fake 合成链。参考资料为 [`w1-canvas-reference.md`](w1-canvas-reference.md)。

尚未达标的部分：选区，以及大量节点下的帧率没有 profile 实测。2026-07-20 已用本地 widget 回归验证背景主键鼠标拖拽、右键隔离、从节点开始的移动端双指缩放、节点拖动和参数输入隔离；新增会话级滚轮模式默认 `zoom`，切为 `scroll` 后鼠标和触控板均平移，切回后均按指针焦点缩放。它只接入桌面主制作画布，不影响图片流，且切换不写配置、数据库、导出或凭据，对齐原版的临时 `canvasWheelEvent`。这些仍不是 macOS/iOS/Android 真机手感或性能结论。还缺运行中切换剧集确认和默认展开的制作 Agent 面板。完成定义：同一套画布在 macOS 鼠标/触控板与 iOS/Android 手势下都能完成平移、缩放、节点编辑，并具备等价的滚轮模式选择；性能指标必须通过 profile 实测，而不是凭视觉判断。

本项自动化证据：`app/test/widgets/df_widgets_test.dart` 验证背景主键鼠标拖拽、右键隔离、两个滚轮模式下鼠标/触控板行为、背景和变换后节点内容的焦点缩放、背景和节点起点的移动端双指缩放、2 倍和缩小视口下的节点拖动坐标换算、空格+鼠标左键优先平移、嵌套图片手势隔离、参数区在 `scroll` 模式仍阻断滚轮、触摸不受该桌面快捷键影响及显式 `fitView()`；`app/test/widgets/settings_screen_test.dart` 验证桌面和 390dp 的滚轮模式控件、默认值和零配置写入；`app/test/widgets/production_screen_test.dart` 驱动真实制作页的节点拖动、刷新重建、自动布局、模式传递和跨端引导完成；`app/test/widgets/image_flow_editor_test.dart` 验证桌面/390dp 卡片位置持久化和参数区隔离；`production_guide_test.dart` 验证四步、高亮、390dp 全屏、小高度滚动与紧凑/桌面切换后的重测；`config_test.dart` 验证完成状态持久化。全部不调用任何供应商。

### B. 原版 Agent 体系（W2）

当前是精简对话助手，尚未覆盖 ToonFlow 的剧本/制作 Agent 分层决策、执行、监督、摘要、向量记忆、Markdown 技能激活与复杂流程恢复。2026-07-19 逐文件复核确认：Flutter 当前会把所有启用 Markdown 技能正文注入每轮 system prompt，虽有安全的文件读取 API，却没有将其作为模型可调用的按需工具；原版则以 `activate_skill` / `read_skill_file` 进行两段式加载，并按子 Agent 阶段筛选技能。原版 Web 的 `scanSkills` 客户端动作在 1.1.8 后端/打包 bundle 没有对应路由，不能按失效按钮复刻。完整证据和验收边界见 [`skill-runtime-matrix.md`](skill-runtime-matrix.md)。

完成定义：以 ToonFlow 可观察行为为准移植，**禁止**恢复旧 DramaFlow 那套非原版的 JS 解释器、ES 查询 DSL 或无法维护的 2 万行单体 Agent；所有花钱或破坏性工具必须经过同一确认策略。

### C. 非线性工作台与视频准备（W3）

视频轨、候选和基础状态机已有；2026-07-20 已闭合工作台的首帧快速预览、逐镜信息审阅、已选本地首帧 ZIP 导出，以及按轨后台批量运镜提示词任务。后者以本地任务队列的事件刷新替代原版轮询，并以每轨任务归属保护手工编辑、单镜替代和清轨不被旧回包覆写，同时拒绝活跃轨重复入队。逐轨部分失败、取消、冷启动恢复和界面错误提示均有 fake-provider 回归。自由多轨编辑、媒体库、实时 NLE 预览、分镜拼图导出、共享轨语义、音频参考装配等仍是部分实现。参考资料为 [`w3-nle-reference.md`](w3-nle-reference.md) 与 [`workbench-matrix.md`](workbench-matrix.md)。

完成定义：先把本地数据/编辑/导出代码和 fake-provider 测试做全；不在开发或 CI 中消耗 Seedance 额度。真实视频生成、下载质量和供应商账号权限由用户在最终验收单独测试。

### D. 设置、预设与移动适配（横切）

供应商预设、模型选择、画风库、导入导出、设置高级项和移动版对话框仍按主清单持续补齐。供应商预设已完成目录、预填表单、画廊、`/models` 候选导入和离线回归；2026-07-19 额外修复了 390px 模型编辑器工具栏溢出，并将桌面本地 OAuth 预设 azt 从 iOS/Android 画廊隐藏。预设创建现以“禁用 provisioning 记录 → 写入本地 SQLite `o_secret` → 启用”为顺序执行；冷启动会恢复已写入凭证的中断创建，并清除未写入凭证的远程残留。当前只允许 `volcengine` 声明或提交 video 模型，这是防止把其他模型错误按 Seedance 格式请求的**临时保护**，不是供应商视频能力已等价的结论。原版 16 个设置模块与 Flutter 7 个自适应分区的逐项映射、移动端证据强度及不适用边界见 [`settings-module-matrix.md`](settings-module-matrix.md)。

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

### 最近核验：指定内容表清空

2026-07-21 已补齐 ToonFlow 数据库管理中的“清空指定表”主流程：设置页会先展示当前表名与行数，390dp 使用全屏可滚动选择页、1280dp 使用桌面对话框，选表后必须再确认明确的表名才会删除。引擎只接受运行时枚举出的内容表，事务完成后通知观察者刷新；任意 SQL 片段、SQLite 内部表和 `o_secret`/供应商/模型绑定/提示词/画风/设置表都会被拒绝。该收紧是本地 SQLite 凭证策略的刻意差异，所以 `W7A-DB-CLEARTABLE-001` 从“缺失”转为“部分实现”，而不是虚标为完全等价。证据与剩余整库备份/恢复出厂缺口见 [`database-management-matrix.md`](database-management-matrix.md)。全程未调用文本、图片或视频供应商。

### 最近核验：中等宽度移动壳

2026-07-19 已补充 760–800dp 回归：项目、画风、手册与剧本的编辑/删除操作在无 hover 的平板触控界面仍可达；剧本与小说工具栏的真实 `RenderFlex` 溢出已修正；素材和事件页同宽度通过渲染验证。详细证据与用例名称见 [`mobile-adaptation-findings.md`](mobile-adaptation-findings.md)。

### 最近核验：供应商预设的可恢复创建与协议边界

2026-07-19 对供应商预设做了针对性复核。远程预设或自定义供应商若没有 API Key，现在会在创建前拒绝并保持零落库；本机 loopback 代理仍允许无 Key 配置。凭证存于本地 SQLite `o_secret` 表，创建路径仍会先保存为禁用的 `provisioning` 状态，只有凭证写入完成后才启用；同名创建会在写 Key 前被拒绝，绝不覆盖已有凭证。应用重启时，已持久化凭证的中断创建会收敛为可用配置；没有凭证的远程残留会被清理，避免出现“列表中显示已添加、实际永远无法调用”的假成功。

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

2026-07-19 已完成这项收口：`firstMissingProjectIntakeField()` 按原版固定顺序检查项目名、题材、图片模型、视频模型、视觉手册、导演手册、比例、简介、图片画质和视频模式。缺项只显示对应本地化提示并保持表单打开，不会写入项目。纯函数回归锁定十项顺序；桌面向导覆盖名称与题材拦截，既有 390dp 完整表单回归覆盖所有字段可达与一次写入。

这项已回写 `W6F-PROJECT-DIALOG-001`。底层 Engine 不承担 UI 的十项非空规则，仍允许导入和恢复记录保存部分字段；这与 ToonFlow Node 路由只做字符串形状验证的职责一致。没有进行任何真实文本、图像或视频调用。

### 最近核验：项目入口的模型保护

2026-07-19 同一轮复核还完成了入口保护：`Engine.projectModelsAvailable()` 在路由前只解析本地保存的图片和视频模型绑定，空值、禁用供应商、禁用或删除模型都会返回不可用；不发生 HTTP 或供应商调用。`_openProject()` 随后显示原版同义提示并打开项目编辑，只有有效双模型才选择项目并进入小说或剧本页。

引擎回归覆盖有效绑定与禁用模型，桌面 widget 回归覆盖失效绑定不进入小说页而打开编辑、有效绑定仍正常路由。该差异已回写 `W6-PROJECT-001`；无候选模型时的“去设置”动作及默认手册 README 标题均已关闭。所有验证只使用内存数据库、本地记录和假网关，不调用图片或视频服务。

### 最近闭合：项目向导无模型设置入口

2026-07-19 已补齐 `modelSelect.vue` 的空态动作。`ModelSelect` 在没有同类型启用模型时显示设置图标和本地化“去设置”按钮；项目向导通过显式回调先关闭对话框，再打开已有的 `/settings?section=providers` 深链。通用选择器不自行关闭页面，因此不会影响工作区中其他选择器的宿主生命周期。

`app/test/widgets/project_page_test.dart` 分别以 1200px 与 390px 宽度验证图片、视频空选择器均会离开向导并进入供应商设置路由。验证只读本地空供应商列表，无供应商 HTTP、文本、图像或视频请求。随后 `manuals_test.dart` 验证内置视觉与导演包在无 `meta.json` 时从 README 首行取标题、移除 `--`；项目页本轮已没有剩余的显式命名差异。

### 最近核验：塑角造景批量参考图工作区

2026-07-19 已完成 `W6-CORNERSCAPE-001` 与 `W6-CORNERSCAPE-002` 的页面级复核。`W6-CORNERSCAPE-001` 纠正了旧审计遗留的“仅角色数据源、绑定状态/名称筛选、全选未绑定、缺少通用测试”描述：原版 `getAllAssets` 与当前 `cornerScapeAssets` 均提供角色/场景/道具顶层资产，音频操作是任一资产详情内绑定或解绑一个音频，以及对当前所选通用资产批量 AI 匹配。桌面 widget 证据直接覆盖三类资产数据、场景/道具详情绑定/解绑/试听，以及筛选后角色选择的批量匹配任务提交；场景/道具通用批量匹配由 `app/test/engine/audio_bind_test.dart` 覆盖，对应资产数据边界由 `app/test/engine/assets_test.dart` 支持。

2026-07-21 完成这条工作流最后的可见状态缺口：`audio_bind` 任务在提交时把选中的
角色、场景、道具父资产置“生成中”，成功、失败和冷启动恢复后进入终态；卡片匹配中优先
显示“音频匹配中”，失败显示标签但仍可打开详情。引擎与 390dp widget 回归均使用内存库和
fake gateway；未请求任何文本、图片、TTS 或视频供应商。原版没有音频绑定错误原因列，
所以 Flutter 只复刻状态、不伪造错误字段。`W6-CORNERSCAPE-001` 和
`W7E-CORNERSCAPE-AUDIO-001` 现均改为“已验证等价”，详见
[`corner-scape-matrix.md`](corner-scape-matrix.md)。

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

### 最近核验：其他设置的超时与制作画布交互降级

2026-07-20 已完成 ToonFlow `otherConfig.vue` 剩余两项的等价路径。请求超时为本地持久化的秒数，默认 600、最小 10；它统一覆盖 OpenAI/Anthropic 的通用文本、结构化工具、Agent、视觉理解、TTS、连接测试和 `/models` 请求。图片与视频没有被这个通用值误覆盖：OpenAI 图片维持 960 秒，ima2 保持供应商图片超时，Seedance 保留 60/30/300 秒的提交、轮询和下载策略。

制作画布的 `production.interacting` 默认开启且跨重建保留。它只传给桌面主制作 `DFCanvas`，真实节点拖拽、空格平移、视口变换或成功滚轮变换期间才临时关闭节点内容的命中与 ticker，并在结束后 150ms 恢复；拖拽手柄仍可操作。共享图片流画布默认关闭该行为，390dp 仍使用纵向内容，不把这个桌面性能策略误应用到其它页面。该行为是可开关的交互降级，而非“性能已经达到某个 FPS”的结论；W1 的 profile 和真机手感验证仍未关闭。

自动化证据为 `config_test.dart`、`providers_test.dart`、`anthropic_gateway_test.dart`、`settings_screen_test.dart`、`df_widgets_test.dart`、`production_screen_test.dart`（本模块聚焦组合 93 项通过）。它们只使用内存 SQLite、假 Dio 网关和 widget 夹具；没有发起任何实时文本、图片、TTS 或视频请求，也没有提交或轮询 Seedance 任务。

### 最近核验：外观主题色与字号

2026-07-20 已闭合 ToonFlow `uiConfig.vue` 与 `theme.ts` 的三项外观能力。默认主题模式从错误的
浅色改为原版对应的跟随系统；浅/深/系统模式、七个原样主色预设、完整六位 HEX 自定义输入和
12/13/14/16/18/20/22 七档字号都写入本地 `o_setting`。主色由唯一的 Flutter `ThemeData` 输入派生，
字号由应用根 `MediaQuery` 缩放一次，避免双重缩放。

最大字号回归在工作台发现了时间线卡片固定高度溢出，视频、音频和素材卡片现在只在文字缩放大于
1 时增高，默认密度不变。390 x 760 项目新建与 1440 x 960 工作台镜头选择均以绿色 `#2BA471`、
字号 22 验证主色生效、交互可继续且无布局异常。全量 Flutter 离线测试、静态分析和 macOS debug
构建均通过；全部用内存 SQLite 和假网关，未调用文本、图片、音频或视频供应商。

### 最近核验：任务中心完整历史

2026-07-20 已闭合任务中心此前的范围缺口。历史查询改为不可变 `TaskHistoryQuery`：项目可空即
全部项目，任务类型、状态、页码与页大小共同作为参数化 SQLite 查询条件。引擎先取总数，再以
`LEFT JOIN o_project` 和 `LIMIT/OFFSET` 返回当前倒序页，因此不再把单项目最近 50 条载入 Flutter
后再在界面层筛选。

页面默认“全部项目”，可切具体项目，项目名写入任务副标题；类型候选来自全局去重结果。桌面和
窄屏共用 10/25/50 条、前后翻页和总数控件，AppBar 刷新与下拉刷新都更新活动任务和当前历史。
取消或重试也会刷新同一查询。390 x 760 widget 回归实际滚到分页栏并切换第二页，不把“能显示”
当作移动端可用证据。

引擎测试用两个项目的 27 条混合任务验证全局/组合过滤、倒序第二页、总数与项目名；widget 测试
验证桌面全项目、刷新、失败详情、取消/重试以及 390px 项目切换和分页。所有证据只使用内存
SQLite、临时目录和假网关；没有请求任何供应商，也没有提交、轮询或生成视频。对应主清单
`W6-TASK-001`、`W7F-TASK-LIST-001`、`W9A-DBTABLE-TASKS-001` 已提升为已验证等价；详见
[`task-center-matrix.md`](task-center-matrix.md)。

收尾门禁：`flutter analyze` 无问题，`flutter test --concurrency=1` 退出码为 0，
`flutter build macos --debug` 成功，`check_no_orphans.js` 仍为 538/538，且 `git diff --check`
无空白错误。上述命令均未启用真实供应商或视频生成。

### 最近核验：工作台快速预览

2026-07-20 已闭合 ToonFlow 工作台的轻量快速预览。原版 `preview.vue` 实际只显示当前
分镜的首帧图或占位，而非播放已生成视频；Flutter 因而在工作台顶栏增加全屏预览入口，
以独立的纯时间轴控制器按 50ms 唤醒和单调时钟实际间隔推进分镜，提供播放/暂停、上一/
下一镜、总进度 Slider、按时长比例的分段定位、首帧缺失态、当前分镜的时长/关联资产/
图片提示词，以及已选本地首帧 ZIP 导出。导出只读取媒体根目录内的普通文件，并在独立
isolate 流式写入目标 ZIP。桌面采用预览与详情两栏；840dp 以下为完整可滚动单列，390dp
回归实际选择缩略图、勾选并访问导出入口。

原版 `getStoryboardData` 没有把 `description` 或 `videoDesc` 投影到预览数据，故其模板
中的描述区始终是空态。Flutter 显示本地已持久化的 `StoryboardRow.videoDesc`；这是一处
有意的断链修正，但没有用打包版黑盒用例量化“更优”，因此主清单仅将
`W6B-WORKBENCH-PREVIEW-001` 升为“已验证等价”。原版拖拽只改变页面内存且恢复排序
初始快照为空；Flutter 延用既有的持久化分镜重排，不复制无效恢复按钮。

自动化证据覆盖时间轴跨镜/边界/三秒兜底、ZIP 内容、绝对路径/`..`/符号链接拒绝、桌面
预览信息、390dp 导出路径、1024dp 英文工具栏和缺失资产图降级；本批相关 119 项通过，
`flutter analyze` 无 issue。所有夹具使用内存 SQLite、本地临时媒体、fake gateway 与 fake
composer；没有发送文本、图片、音频或视频供应商请求。独立空视频轨、候选视频直接下载/
批量 ZIP、实时 NLE 预览和真实视频生成仍明确保留为未完成条目。
