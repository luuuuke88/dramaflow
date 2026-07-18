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
| 已验证等价 | 75 | 已有源码对照与自动化证据 |
| 已验证更优 | 0 | 尚未以打包版黑盒用例证明“更优” |
| 不适用 | 11 | 有明确理由的 Electron/分发环境专属项 |
| 部分实现 | 94 | 功能、数据语义、交互或测试仍有缺口，不能算完成 |
| 缺失 | 20 | 尚无可接受的等价实现 |
| 未审计 | 0 | 无 |

已验证等价与不适用合计 **86/200（43.0%）**；以“用户可用的完整复刻”为标准，项目仍处于中段，不能宣称接近 100%。

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

95 个“部分实现”不是零散小毛病。下面四块决定了用户会不会觉得它真的是 ToonFlow 的 Flutter 版。

### A. 无限画布与制作页（W1）

制作画布的节点骨架和编辑入口已有。2026-07-19 已补齐标题栏拖动与自动布局复位：六个节点在当前会话共用一张与 ToonFlow `nodePositions` 同语义的坐标表，切换剧集不会丢失当前排布；拖动按当前缩放换算场景坐标，并会锁住画布视口以避免节点拖动与画布平移同时发生；自动布局可恢复原始主链。参考资料为 [`w1-canvas-reference.md`](w1-canvas-reference.md)。

尚未达标的部分：缩放围绕光标、触控板与 iOS/Android 的实际手势、选区，以及大量节点下的帧率没有 profile 实测。完成定义：同一套画布在 macOS 鼠标/触控板与 iOS/Android 手势下都能完成平移、缩放、节点编辑；性能指标必须通过 profile 实测，而不是凭视觉判断。

本项自动化证据：`app/test/widgets/df_widgets_test.dart` 验证 2 倍缩放下的节点拖动坐标换算；`app/test/widgets/production_screen_test.dart` 驱动真实制作页的节点拖动与自动布局复位。两项都不调用任何视频供应商。

### B. 原版 Agent 体系（W2）

当前是精简对话助手，尚未覆盖 ToonFlow 的剧本/制作 Agent 分层决策、执行、监督、摘要、向量记忆、Markdown 技能激活与复杂流程恢复。参考资料为 [`w2-agent-reference.md`](w2-agent-reference.md)。

完成定义：以 ToonFlow 可观察行为为准移植，**禁止**恢复旧 DramaFlow 那套非原版的 JS 解释器、ES 查询 DSL 或无法维护的 2 万行单体 Agent；所有花钱或破坏性工具必须经过同一确认策略。

### C. 非线性工作台与视频准备（W3）

视频轨、候选和基础状态机已有，但自由多轨编辑、媒体库、预览、分镜网格导出、按轨批量提示词后台任务、共享轨语义、音频参考装配等仍是部分实现。参考资料为 [`w3-nle-reference.md`](w3-nle-reference.md)。

完成定义：先把本地数据/编辑/导出代码和 fake-provider 测试做全；不在开发或 CI 中消耗 Seedance 额度。真实视频生成、下载质量和供应商账号权限由用户在最终验收单独测试。

### D. 设置、预设与移动适配（横切）

供应商预设、模型选择、画风库、导入导出、设置高级项和移动版对话框仍按主清单持续补齐。供应商预设已完成目录、预填表单、画廊、`/models` 候选导入和离线回归；2026-07-19 额外修复了 390px 模型编辑器工具栏溢出，并将桌面本地 OAuth 预设 azt 从 iOS/Android 画廊隐藏。预设创建现以“禁用 provisioning 记录 → 写入 Keychain → 启用”为顺序执行；冷启动会恢复已写入凭证的中断创建，并清除未写入凭证的远程残留。模型保存和视频网关也共同限制为：只有 `volcengine` 协议可声明或提交 video 模型，其他供应商不会被误送到 Seedance 接口。

它改善的是通用供应商配置体验，**不改变**主清单 `W6D-VENDOR-001` 的“部分实现”结论：原版可编辑 vendor 插件、私有协议适配和动态字段仍未复刻。正式人工验收表已存在于 [`provider-presets-acceptance.md`](provider-presets-acceptance.md)，但除 azt 外均保持“未验证”标识；原生私有协议也尚未实现。移动发现记录位于 [`mobile-adaptation-findings.md`](mobile-adaptation-findings.md)。这些改动不得因“桌面能用”而标绿。

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

视频协议当前只实现火山 Seedance。模型编辑层、正式 HTTP 网关和设置页的 `testVideoModel` 连通测试均拒绝非 `volcengine` 的 video 模型，且拒绝发生在任何 HTTP 请求之前；这不是减少视频能力，而是防止将 OpenAI 兼容供应商误按 Seedance 任务格式调用。未来接入新的视频供应商时，必须先实现对应的提交、轮询、取消和连通测试适配器，以及 fake-gateway 回归，再开放该协议的 video 类型。自动化证据：`app/test/engine/provider_preset_create_test.dart`、`app/test/engine/engine_facade_test.dart`、`app/test/engine/providers_test.dart` 与 `app/test/widgets/settings_screen_test.dart`；没有发起真实视频、图像或文本生成。

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
