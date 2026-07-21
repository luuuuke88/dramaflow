# 技能运行时对照矩阵

更新时间：2026-07-21

基线：ToonFlow 1.1.8 的 `skills/` 资源、`skillManagement` 设置页、
`src/utils/agent/skillsTools.ts` 与剧本/制作 Agent 调用点。

这份记录区分三件常被混为一谈的事：用户管理 Markdown 文件、Agent 如何把
技能放进上下文、以及前端遗留的“扫描”动作。目标是复刻用户真正能使用的能力，
不照搬已在打包基线失效的 HTTP 调用。

## 结论摘要

| 能力 | ToonFlow 1.1.8 实际行为 | DramaFlow 当前行为 | 状态 |
| --- | --- | --- | --- |
| 技能文件库管理 | 树形浏览、搜索、预览、编辑并保存既有 `.md` 文件 | 应用自有工作区中的单 Markdown 导入、搜索、预览、编辑保存和启停；桌面双栏、窄屏详情返回 | 部分实现（仍无目录树/目录包导入） |
| Agent 主技能加载 | 首轮只给 `name`/`description`，模型调用 `activate_skill` 后才收到正文 | 初始提示词仅有启用技能目录；`activate_skill` 将正文和资源清单作为工具结果写入同一项目/家族会话 | 已验证等价（单层范围） |
| 技能资源读取 | 已激活技能可通过 `read_skill_file` 按需读其受限目录内的资源 | `read_skill_file` 仅能读当前项目、当前家族已激活的托管包常规文件，拒绝路径穿越和符号链接 | 已验证等价（单层范围） |
| 阶段归属 | 技能按剧本/制作子 Agent 阶段筛选可见集合 | 无阶段归属读取；所有启用 Markdown 技能对两个助手家族同样注入 | 缺失 |
| “扫描 Skills” | Web 客户端会请求一个未在 1.1.8 后端/打包 bundle 注册的路由 | 对应用私有目录做新增/更新/丢失/无效 frontmatter 的真实本地对账，并显示统计 | 已验证等价（承接用户意图，不复制失效路由） |

## 1. 原版真正可用的文件管理

`Toonflow-web/src/components/setting/components/skillManagement.vue` 在挂载时调用
`/setting/skillManagement/getSkillList`，把 `skills/**/*.md` 组织成可检索目录树。用户
选文件后读取内容、预览 Markdown，点击编辑并保存原文件。

对应后端在 `Toonflow-app/src/routes/setting/skillManagement/` 中完整存在：

- `getSkillList.ts` 用 `fast-glob` 列出全部 Markdown 文件；
- `getSkillContent.ts` 在 `isPathInside` 校验后读取选中路径；
- `saveSkillContent.ts` 在同一边界校验后覆写既有文件。

Flutter 现在通过 `_AssistantSkillsPane` 提供可达的单 Markdown 导入、搜索、预览、编辑
保存和启停。文件会复制到 `dataDir/skills`，不把外部绝对路径写入数据库；`SKILL.md`
导入还会复制同目录常规资源，因此源文件和资源删除后，托管内容仍可读取。桌面使用列表+
详情双栏，窄屏进入详情后可返回列表。`assistant_skill_library_test.dart`、
`assistant_skills_deploy_test.dart` 与 `agent_chat_screen_test.dart` 已覆盖这些本地行为。

`W6D-SKILL-001` 仍是“部分实现”：原版目录树没有复刻，当前只支持单 Markdown 文件而非
桌面目录包导入；这些缺口不能被“文件已可编辑”掩盖。

## 2. 原版的按需激活协议

原版 `skillsTools.ts` 先解析 frontmatter，只把主技能的名称与说明写进
`<available_skills>`。模型需要具体指令时才调用 `activate_skill`，工具返回该技能正文及
可读取资源清单；随后 `read_skill_file` 只允许读取已激活技能目录内的相对路径。路径穿越
会被拒绝。制作 Agent 在 `productionAgent/index.ts` 还会按当前子任务选择 art、story
和 production 技能集合。

2026-07-21，Flutter 已将这一单层协议落在 `assistant_skills.dart` 与
`assistant_chat.dart`：`assistantSkillCatalog()` 只从启用 Markdown 行读取 `id`、名称和
说明；初始 system prompt 以 `<available_skills>` 提供目录，完全不读取正文。模型可调用
`activate_skill`，工具结果才返回解析后的正文和递归资源清单；`read_skill_file` 只能读取
同一项目、同一剧本/制作家族已激活的应用私有技能包。

激活集合独立持久化为 `o_agentWorkData` 的
`assistantSkillActivation:<family>`，按稳定 ID 排序；重复激活不重复写入，清空该家族聊天
会同步清空集合。任何读取都会依次校验启用状态、激活状态、相对路径、非链接常规文件及
解析后的真实路径仍在技能包内。`../`、外部历史路径、未激活资源、已删除正文和符号链接
逃逸都会以工具错误回传，而不会中断对话。上下文工具至多连续三跳，不经过花费/破坏确认闸；
手动模式的一次业务动作及自动模式的五次业务动作上限不变。

这只完成原版**按需 Markdown 协议的单层可观察闭环**。Flutter 仍没有原版按子 Agent
阶段挑选 art/story/production 技能的归属读取，也没有原版的子 Agent、向量记忆或流式
编排；不能以本节结案替代这些 W2 缺口。

## 3. 关于 `scanSkills` 的纠正

`Toonflow-web/src/utils/scanSkills.ts` 会显示 0--90% 的定时进度，然后 POST
`/setting/skillManagement/scanSkills`，期待新增、更新、删除和 frontmatter 告警统计。
但对完整 `Toonflow-app/src/routes`、打包的 `data/serve/app.js` 和当前路由文件逐项检索，
没有发现这个路由的注册或实现。打包 bundle 中唯一的 `scanSkills` 是 Agent 在磁盘上发现
Markdown 文件的内部函数，不是设置页 HTTP 端点。

所以不能把这个会失败的请求当作“原版已完成的扫描功能”照写。Flutter 已提供真实、
用户可见的等价闭环：`scanMarkdownAssistantSkills()` 只递归扫描应用自有的
`dataDir/skills/<id>/SKILL.md` 入口，按稳定 ID 对账新增、更新、丢失和无效 frontmatter；
包内其它 Markdown 保持资源身份，丢失记录保留供修复，旧外部路径不会被读取。界面在桌面
和 390dp 均可触发扫描并显示四类统计。引擎测试还锁住了“无效文件不同时算丢失”和
“资源不误注册”的边界。没有伪进度、HTTP 路由或供应商调用。

## 4. 验收边界

- 文件管理：已验证单 Markdown 导入、预览、编辑保存和窄屏详情返回；目录树与目录包导入
  仍是未完成的 W6D 缺口。
- 激活协议：fake gateway 断言首轮没有正文，`activate_skill` 后正文才作为工具结果回传，
  且手动对话会继续取得文本回答。
- 边界：未激活资源、`../`、绝对路径、已删除文件、重复激活、禁用技能、包内符号链接
  和清空会话各有本地引擎/对话测试。
- 归属：已验证剧本/制作会话的**激活集合**隔离；原版的阶段级可见技能集合仍缺失，不能
  靠消息关键字猜测。
- 不调用真实文本、图片或视频供应商；视频仍只做 fake gateway 状态测试。

## 关联条目

- 主清单：`W6D-SKILL-001`、`W6E-LIB-SCANSKILLS-001`、
  `W9A-DBTABLE-SKILLATTRIB-001`、`W9C-PRODSKILL-*`。
- W2 总览：[`feature-parity-execution-report.md`](feature-parity-execution-report.md)。
- 供应商协议缺口另见 [`vendor-protocol-matrix.md`](vendor-protocol-matrix.md)，两者不得
  用同一份“预设”计划混合结案。
