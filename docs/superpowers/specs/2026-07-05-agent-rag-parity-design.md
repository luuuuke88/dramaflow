# DramaFlow Agent/RAG Parity Design

日期：2026-07-05
状态：方案 1 已获 luke 确认；本文为正式设计落稿，等待 review 后进入实施计划。
前置：`2026-07-03-v0.3-toonflow-parity-design.md`，本设计只收窄其中 Agent/RAG 子系统，不改变已验证的 Flutter/Dart 单体架构。

## 0. 背景

当前 DramaFlow 原生客户端主流程已经能在 macOS/iOS/Android 上跑通：小说、事件、剧本、素材、分镜、首帧、视频、配音、合成都在 Dart engine 内闭环，且不依赖旧 `server/`。

Agent 体系仍是最大产品差距。当前 `app/lib/src/engine/agent.dart` 是单层 AgentRunner：能持久化消息、调用可见任务工具、保存长期 note 记忆、限制 RAG 条数、执行简单 `custom-js-agent` return 模板，但它不是 ToonFlow 的真实多层 Agent + 记忆摘要 + 向量召回系统。

本设计目标是把 Agent 产品形态向 ToonFlow 拉齐，同时保留 DramaFlow 的底线：所有会改数据或生成媒体的动作必须走现有 engine API 和 `o_tasks`，错误可见、可重试、可恢复。

## 1. 设计决策

采用 **方案 1：分层 Agent + 兼容记忆，先不用真 ONNX/完整 QuickJS**。

第一刀完成：

1. ToonFlow 风格的 `scriptAgent` 与 `productionAgent` 双 Agent 家族。
2. 决策 Agent、监督 Agent、执行子 Agent 的分层编排。
3. `memories` 表启用 `message` / `summary` / `note` 三类记忆。
4. `Memory.add/get/deepRetrieve` 语义对齐 ToonFlow。
5. `activate_skill` / `read_skill_file` 风格的技能激活与资源读取。
6. Agent 页 UI 从 5 个通用 stage 升级为 ToonFlow 风格层级部署与记忆配置。

第一刀不做：

1. 不接 ONNX/HF 本地模型运行时；先复用现有 Dart token embedding 接口，保留可替换边界。
2. 不接完整 QuickJS/flutter_js；保留现有 return 模板，自定义技能执行能力单独切片。
3. 不改 Web/H5；Web 完整引擎归后续 M6。
4. 不绕过任务队列直接改媒体或生成结果。

## 2. ToonFlow 参照

本设计以这些本地源码为参照：

- `Toonflow-app/src/utils/agent/memory.ts`
- `Toonflow-app/src/utils/agent/embedding.ts`
- `Toonflow-app/src/utils/agent/skillsTools.ts`
- `Toonflow-app/src/agents/scriptAgent/index.ts`
- `Toonflow-app/src/agents/scriptAgent/tools.ts`
- `Toonflow-app/src/agents/productionAgent/index.ts`
- `Toonflow-app/src/agents/productionAgent/tools.ts`
- `Toonflow-app/src/utils/ai.ts`
- `Toonflow-app/src/lib/initDB.ts`

关键行为：

- `Memory.add(role, content)` 写入 `memories(type='message')`，达到 `messagesPerSummary` 后生成 `summary`，并把源 message 标记为 summarized。
- `Memory.get(text)` 返回三段上下文：相关记忆、历史摘要、近期对话。
- `deepRetrieve(keyword)` 先召回 summary，再由 LLM 判断相关 summary，最后展开原始 message。
- `scriptAgent` 和 `productionAgent` 都是 decision Agent 调度多个子 Agent。
- 子 Agent 输出 XML 或调用 workspace tools，再写入剧本规划、分镜表、资产、分镜等工作区。
- 技能系统通过 `activate_skill` 和 `read_skill_file` 延迟加载 Markdown 技能内容。

## 3. 目标能力

### 3.1 Script Agent

补齐以下部署 key：

- `scriptAgent`
- `scriptAgent:decisionAgent`
- `scriptAgent:storySkeletonAgent`
- `scriptAgent:adaptationStrategyAgent`
- `scriptAgent:scriptAgent`
- `scriptAgent:supervisionAgent`

行为：

- decision Agent 接收用户输入、项目信息、记忆上下文和可用工具。
- decision Agent 可调用：
  - `deepRetrieve`
  - `get_novel_events`
  - `get_planData`
  - `get_novel_text`
  - `get_script_content`
  - `run_sub_agent_storySkeleton`
  - `run_sub_agent_adaptationStrategy`
  - `run_sub_agent_script`
  - `run_supervision_agent`
- 子 Agent 输出写入现有工作区：
  - `storySkeleton` 与 `adaptationStrategy` 写入 `o_agentWorkData` 中的 `scriptPlan` 或独立 planning key。
  - `scriptItem` 输出解析为 `o_script` 行，复用现有剧本 CRUD 与资产提取链路。
- 每轮用户输入和 Agent 输出都写入 `memories(type='message')`。

### 3.2 Production Agent

补齐以下部署 key：

- `productionAgent`
- `productionAgent:decisionAgent`
- `productionAgent:deriveAssetsAgent`
- `productionAgent:generateAssetsAgent`
- `productionAgent:directorPlanAgent`
- `productionAgent:storyboardGenAgent`
- `productionAgent:storyboardPanelAgent`
- `productionAgent:storyboardTableAgent`
- `productionAgent:supervisionAgent`

行为：

- decision Agent 接收项目信息、模型信息、视频多参信息、记忆上下文和可用工具。
- decision Agent 可调用：
  - `deepRetrieve`
  - `get_flowData`
  - `add_deriveAsset`
  - `del_deriveAsset`
  - `generate_deriveAsset`
  - `generate_storyboard`
  - `add_flowData_storyboard`
  - `run_sub_agent_derive_assets`
  - `run_sub_agent_generate_assets`
  - `run_sub_agent_director_plan`
  - `run_sub_agent_storyboard_gen`
  - `run_sub_agent_storyboard_panel`
  - `run_sub_agent_storyboard_table`
  - `run_sub_agent_supervision`
- 子 Agent 只能通过现有 engine API 或 workspace tool 写数据；禁止直接拼 SQL 改核心业务表。
- 资产生成、首帧图、视频生成、配音绑定、合成导出继续进入 `o_tasks`。

## 4. 架构

### 4.1 AgentStageRegistry

新增 Agent stage registry，统一定义：

- stage key
- 显示名称
- agent family：`scriptAgent` / `productionAgent`
- role：decision / execution / supervision
- 默认模型来源
- 允许工具集
- 默认 maxOutputTokens / temperature

现有 `_agentDeploymentKeys` 扩展为完整 ToonFlow key。`o_agentDeploy` 继续作为配置表，保留现有 fallback 到 `binding.<stage>` 的机制。

兼容规则：

- 已存在的 `script_gen`、`event_extract`、`asset_extract`、`storyboard_gen`、`video_prompt_gen` 不删除。
- 新 Agent key 优先用于 Agent 编排。
- 普通流水线 stage 继续用于非 Agent 页面按钮。

### 4.2 AgentMemoryService

新增独立服务，替代 `agent.dart` 内部零散记忆函数。

数据类型：

- `type='message'`：Agent 对话、子 Agent 输出、工具结果。
- `type='summary'`：压缩后的历史摘要。
- `type='note'`：用户手动维护的长期记忆，兼容现有 UI。

配置项写入 `o_setting`：

- `messagesPerSummary`，默认 3
- `summaryMaxLength`，默认 500
- `shortTermLimit`，默认 5
- `summaryLimit`，默认 10
- `ragLimit`，默认 3
- `deepRetrieveSummaryLimit`，默认 5

接口：

- `add(isolationKey, role, content, name?, createTime?)`
- `get(isolationKey, query)`
- `deepRetrieve(isolationKey, keyword)`
- `clear(isolationKey, scope)`，scope 为 `message` / `summary` / `note` / `all`
- `searchNotes(projectId, query)`，保留现有手写 note 搜索。

Embedding：

- 第一刀复用现有 token embedding JSON，保证离线、跨端、可测。
- 接口命名保持 `EmbeddingProvider`，未来可换成本地 ONNX 或远端 embedding。

Summary：

- 触发条件与 ToonFlow 一致：未总结 message 数量达到 `messagesPerSummary`。
- summary 文本由当前 Agent family 的 text model 生成。
- 测试中用 fake gateway，禁止真实网络。

### 4.3 AgentOrchestrator

新增：

- `ScriptAgentOrchestrator`
- `ProductionAgentOrchestrator`
- `AgentTurnStore`
- `AgentWorkspaceTools`
- `AgentXmlParser`

编排原则：

1. decision Agent 只负责判断和调度。
2. execution subAgent 输出 XML 或调用 workspace tool。
3. supervision Agent 只做审查、修改建议或二次执行建议。
4. 所有写库动作通过 engine facade。
5. 所有长任务通过 `o_tasks`，任务中心可见。
6. manual 模式每次最多一个工具或子 Agent。
7. auto 模式可多轮，但必须有轮次上限和重复工具保护。

### 4.4 SkillRuntime v1

实现 ToonFlow 技能系统的可用子集：

- Markdown skill frontmatter 解析：`name`、`description`。
- `activate_skill(name)`：把技能正文注入当前 Agent 上下文。
- `read_skill_file(path)`：只允许读取技能目录内文件，防止路径穿越。
- `o_skillList` 存技能元信息。
- `o_skillAttribution` 存归属，例如 `script_agent_decision`、`production_agent_execution`。

技能来源：

- 第一刀可把 ToonFlow 关键技能 markdown 复制为 DramaFlow 本地 seed 资源。
- 技能内容不写死进 Dart 字符串；放入可维护资源目录或 DB seed。

自定义技能：

- 保留现有 `custom-js-agent` return 模板。
- UI 明示当前为 v1 模板执行，不承诺完整 JS runtime。
- 完整 QuickJS/flutter_js 后续独立设计。

### 4.5 UI

Agent 页调整为三层：

1. 对话
   - 剧本 Agent / 生产 Agent 切换。
   - 显示 decision / subAgent / supervision 消息来源。
   - 工具调用结果、任务 id、失败原因可见。

2. 部署
   - 按 Agent family 分组。
   - 展示完整 stage key。
   - 每个 stage 可配置 vendor、model、temperature、maxOutputTokens、disabled。

3. 记忆与技能
   - 记忆配置：messagesPerSummary、summaryMaxLength、shortTermLimit、summaryLimit、ragLimit、deepRetrieveSummaryLimit。
   - 记忆列表按 message / summary / note 过滤。
   - 支持按 scope 清空。
   - 技能列表按 attribution 过滤、启停、查看正文。

移动端：

- 仍用全屏表单与 tab，不砍功能。
- 长列表用分组卡片，不强塞桌面表格。

## 5. 数据与迁移

不新增表，优先复用：

- `o_agentDeploy`
- `o_agentWorkData`
- `o_skillList`
- `o_skillAttribution`
- `memories`
- `o_setting`

如实现中需要新增索引，可 bump `schemaVersion` 并写初始化 schema。第一刀目标是不改表结构，只补 seed 与服务层。

需要修正的兼容点：

- 当前 note 记忆隔离键为 `project:$projectId`，新 Agent message/summary 使用：
  - `scriptAgent:$projectId`
  - `productionAgent:$projectId:$scriptId?`
- 删除项目时必须清理以上 isolationKey，避免旧记忆泄漏。

## 6. 错误与恢复

- LLM 失败：写入 Agent 消息，保留 `errKey`，不中断 UI。
- 子 Agent XML 无法解析：写入 supervision 可见错误，允许用户手动重试。
- 工具提交任务失败：工具结果消息写失败原因，任务中心若已建任务则可重试。
- auto 模式循环：限制总轮数、连续相同工具次数、同一参数重复次数。
- App 重启：已提交的 `o_tasks` 按现有恢复逻辑处理；Agent 消息和记忆已落库。

## 7. 测试计划

引擎测试：

- seed 完整 Agent deployment keys。
- `AgentMemoryService.add/get` 生成 message、summary、rag 三段上下文。
- `deepRetrieve` 从 summary 展开原始 message。
- `messagesPerSummary`、`summaryLimit`、`ragLimit` 等配置生效。
- Script decision Agent 能调用 storySkeleton/adaptation/script/supervision 子 Agent。
- Production decision Agent 能调用 derive/generate/director/storyboard/table/panel/supervision 子 Agent。
- 子 Agent 输出 XML 能写入对应工作区。
- 所有生成动作进入 `o_tasks`。
- manual/auto 模式行为不回退。
- 项目删除清理相关 isolationKey 记忆。

Widget 测试：

- 桌面 Agent 部署页展示完整 stage 分组。
- 390px 移动端可编辑 Agent stage 配置。
- 记忆配置表单可保存并影响 engine。
- message/summary/note 过滤与清空可用。
- 技能 attribution 过滤、启停、查看正文可用。

验证命令：

```bash
cd app
flutter analyze
flutter test
```

## 8. 实施切片

后续 implementation plan 应拆为：

1. `AgentStageRegistry` + seed 完整部署 key。
2. `AgentMemoryService` + message/summary/deepRetrieve。
3. `SkillRuntime v1` + skill seed/activation/read file。
4. `ScriptAgentOrchestrator` + XML 写入剧本规划/剧本。
5. `ProductionAgentOrchestrator` + workspace tools。
6. Agent UI 分组、记忆配置、技能 attribution。
7. 旧单层 AgentRunner 迁移与回归测试。

## 9. 完成标准

可以声明 Agent/RAG parity 第一阶段完成，需要同时满足：

1. `scriptAgent` 与 `productionAgent` 均有 decision/subAgent/supervision 编排。
2. `memories` 中真实产生 message 与 summary，且 `deepRetrieve` 可展开历史消息。
3. Agent 页能配置 ToonFlow 风格完整 stage。
4. 技能可按 attribution 激活并读取资源文件。
5. 旧的工具调用、任务可见、manual/auto 模式全部保持。
6. `flutter analyze` 0 issues，`flutter test` 全绿。

这仍不代表完整 ToonFlow 全产品复刻；NLE/Web/H5/vision/真实并排验收仍按后续目标推进。
