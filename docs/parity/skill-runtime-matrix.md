# 技能运行时对照矩阵

更新时间：2026-07-19

基线：ToonFlow 1.1.8 的 `skills/` 资源、`skillManagement` 设置页、
`src/utils/agent/skillsTools.ts` 与剧本/制作 Agent 调用点。

这份记录区分三件常被混为一谈的事：用户管理 Markdown 文件、Agent 如何把
技能放进上下文、以及前端遗留的“扫描”动作。目标是复刻用户真正能使用的能力，
不照搬已在打包基线失效的 HTTP 调用。

## 结论摘要

| 能力 | ToonFlow 1.1.8 实际行为 | DramaFlow 当前行为 | 状态 |
| --- | --- | --- | --- |
| 技能文件库管理 | 树形浏览、搜索、预览、编辑并保存既有 `.md` 文件 | 仅列出已入库技能，提供启用/停用；没有浏览、预览、编辑、保存或文件夹导入界面 | 部分实现 |
| Agent 主技能加载 | 首轮只给 `name`/`description`，模型调用 `activate_skill` 后才收到正文 | 每轮把所有启用 Markdown 技能全文拼进 system prompt | 缺失 |
| 技能资源读取 | 已激活技能可通过 `read_skill_file` 按需读其受限目录内的资源 | 有引擎级安全读取 API，但未注册给模型调用 | 缺失 |
| 阶段归属 | 技能按剧本/制作子 Agent 阶段筛选可见集合 | 无阶段归属读取；所有启用 Markdown 技能对两个助手家族同样注入 | 缺失 |
| “扫描 Skills” | Web 客户端会请求一个未在 1.1.8 后端/打包 bundle 注册的路由 | 无用户可触发的导入或重载 | 缺失，不能复制原版失效动作 |

## 1. 原版真正可用的文件管理

`Toonflow-web/src/components/setting/components/skillManagement.vue` 在挂载时调用
`/setting/skillManagement/getSkillList`，把 `skills/**/*.md` 组织成可检索目录树。用户
选文件后读取内容、预览 Markdown，点击编辑并保存原文件。

对应后端在 `Toonflow-app/src/routes/setting/skillManagement/` 中完整存在：

- `getSkillList.ts` 用 `fast-glob` 列出全部 Markdown 文件；
- `getSkillContent.ts` 在 `isPathInside` 校验后读取选中路径；
- `saveSkillContent.ts` 在同一边界校验后覆写既有文件。

Flutter 的 `_AssistantSkillsPane` 只展示 `Engine.assistantSkills()` 的数据库行并切换
启用状态。`saveMarkdownAssistantSkill(filePath:)` 可以被 Dart 调用导入单个文件，
但没有可达的文件选择、目录树、内容预览或内容编辑 UI。因此 `W6D-SKILL-001` 保持
“部分实现”，不能以“可直接改磁盘文件”的提示替代应用内管理。

## 2. 原版的按需激活协议

原版 `skillsTools.ts` 先解析 frontmatter，只把主技能的名称与说明写进
`<available_skills>`。模型需要具体指令时才调用 `activate_skill`，工具返回该技能正文及
可读取资源清单；随后 `read_skill_file` 只允许读取已激活技能目录内的相对路径。路径穿越
会被拒绝。制作 Agent 在 `productionAgent/index.ts` 还会按当前子任务选择 art、story
和 production 技能集合。

Flutter 已有相近的基础安全件：`readAssistantSkillFile()` 会拒绝越界相对路径。但
`assistantSkillContexts()` 会逐个读取所有启用 Markdown 技能正文，而
`_assistantSystemPrompt()` 每轮都将其注入。`readAssistantSkillFile()` 也没有成为
`AssistantAction` 或其他 LLM 工具。因此它既缺少延迟加载，也缺少向模型公开的安全资源
读取面；技能数或正文变大时还会不必要地放大上下文和成本。

恢复时应保留 Flutter 的文件边界保护和统一确认闸，但改为：技能清单元数据 ->
`activate_skill` -> 受限 `read_skill_file` 三段式，并让阶段/助手家族显式决定可见技能。
这是一项 W2 Agent 工作，不能作为供应商预设计划的附带改动。

## 3. 关于 `scanSkills` 的纠正

`Toonflow-web/src/utils/scanSkills.ts` 会显示 0--90% 的定时进度，然后 POST
`/setting/skillManagement/scanSkills`，期待新增、更新、删除和 frontmatter 告警统计。
但对完整 `Toonflow-app/src/routes`、打包的 `data/serve/app.js` 和当前路由文件逐项检索，
没有发现这个路由的注册或实现。打包 bundle 中唯一的 `scanSkills` 是 Agent 在磁盘上发现
Markdown 文件的内部函数，不是设置页 HTTP 端点。

所以不能把这个会失败的请求当作“原版已完成的扫描功能”照写。Flutter 要补的是一个可靠、
用户可见的等价闭环：选择文件或技能根目录、发现/更新/移除记录、报告结果，并能在桌面和
移动端完成。具体 UI 与数据迁移应先出 W2 设计和 TDD 任务卡；本次只记录缺口。

## 4. 验收边界

- 文件管理：桌面目录树、预览、编辑保存；移动端以全屏列表/编辑器完成同一流程。
- 激活协议：假网关断言首轮没有正文，`activate_skill` 后才携带正文；未激活时读取资源被拒。
- 边界：`../`、绝对路径、已删除文件、重复激活和禁用技能各有引擎测试。
- 归属：剧本与制作至少有不同的可见技能集合，不能靠消息关键字猜测。
- 不调用真实文本、图片或视频供应商；视频仍只做 fake gateway 状态测试。

## 关联条目

- 主清单：`W6D-SKILL-001`、`W6E-LIB-SCANSKILLS-001`、
  `W9A-DBTABLE-SKILLATTRIB-001`、`W9C-PRODSKILL-*`。
- W2 总览：[`feature-parity-execution-report.md`](feature-parity-execution-report.md)。
- 供应商协议缺口另见 [`vendor-protocol-matrix.md`](vendor-protocol-matrix.md)，两者不得
  用同一份“预设”计划混合结案。
