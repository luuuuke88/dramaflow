# 任务中心对照：完整历史、筛选与任务追踪

状态：2026-07-20 源码对照、SQLite 引擎回归与桌面/390px widget 验收。

本文覆盖当前实际路由的 `Toonflow-web/src/views/task/index.vue`。未注册到路由的
`views/taskList/index.vue` 是遗留页面，不计入 ToonFlow 1.1.8 的用户可观察功能。

## 对齐结论

DramaFlow 的任务中心现在覆盖原版的完整历史查询闭环：默认查看全部项目、按项目/类型/
状态筛选、按最新任务倒序分页、调整每页数量、显式刷新，以及查看失败原因与完整详情。
筛选和分页在本地 SQLite 中完成，Flutter 只接收当前页，不会先载入无限历史再在界面层截断。

原版是表格界面，DramaFlow 采用更适合窄屏的任务卡片和 `Wrap` 控件；两者的筛选、追溯和
分页行为等价。进行中任务仍独立置顶，取消与失败重试是 DramaFlow 的额外操作，不替代原版能力。

## 源码与数据边界

| 范围 | ToonFlow 1.1.8 | DramaFlow |
| --- | --- | --- |
| 页面与路由 | `Toonflow-web/src/router/index.ts`，`views/task/index.vue` | `app/lib/src/screens/tasks_screen.dart` |
| 历史查询 | `src/routes/task/getTaskApi.ts`：`page/limit/total`、项目/类型/状态条件、ID 倒序 | `Engine.taskHistory(TaskHistoryQuery)`：参数化 `COUNT(*)` + `LEFT JOIN o_project` + `LIMIT/OFFSET` |
| 候选筛选项 | `getTaskCategories.ts`、`getProject.ts` | `Engine.taskHistoryClasses()`、`projectsProvider` |
| 单项详情 | `taskDetails.ts` | `_showTaskDetail()` 使用当前页的完整 `TasksRow` |

`TaskHistoryQuery` 是唯一的历史查询值：`projectId` 为 `null` 时表示全部项目；任务类型、
状态、页码和页大小一并构成缓存键。`TaskHistoryPage` 返回当前 `items`、`total` 与页码边界，
因此筛选条件或页大小变化都会回到第一页，不能误复用上一页的结果。

## 用户动作对照

| 用户动作 | ToonFlow 当前行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 浏览任务历史 | 全项目或单项目，按 ID 倒序分页 | 默认全部项目或可切单项目，按 ID 倒序分页 | 已验证等价 |
| 按项目筛选 | 下拉含“全部”与项目项 | “全部项目”作为默认项，项目名写入任务副标题 | 已验证等价 |
| 按类型/状态筛选 | 服务端条件查询 | 参数化 SQLite 条件查询；候选类型从全局历史去重 | 已验证等价 |
| 翻页与页大小 | 页码、前后翻页与 `limit` | 10 / 25 / 50 条，前后翻页、总页数和总数量 | 已验证等价 |
| 手动刷新 | 页面刷新按钮 | AppBar 刷新与下拉刷新都刷新活动任务、项目、类型和当前历史查询 | 已验证等价 |
| 查看失败原因 | 状态悬停显示原因 | 状态 chip 提示原因，点击任务可查看完整原因 | 已验证等价 |
| 查看完整详情 | 按任务 ID 读取完整字段 | 当前页完整行展示类型、状态、描述、模型、关联对象、原因和时间 | 已验证等价 |
| 取消/重试 | 原版任务页没有此操作 | 进行中可取消；失败可重试且阻止重复创建 | DramaFlow 扩展 |

## 跨端验证证据

`app/test/engine/task_history_test.dart` 在内存 SQLite 中创建两个项目的 27 条混合任务，验证：

- 第二页只返回最新倒序中的对应十条，同时返回 `total=27`、项目名称和正确页边界；
- 项目、类型、状态的组合筛选全部在 SQL 读路径生效；
- 类型候选全局去重、排序，并不依赖当前页。

`app/test/widgets/tasks_screen_test.dart` 覆盖：

- 桌面默认全项目范围、项目名显示、总数、分页按钮与第二页结果；
- 类型/状态筛选、失败详情、显式刷新后读取新写入任务；
- 390 x 760 下项目切换、详情、滚动至分页控件并成功翻页；
- 进行中任务取消与失败任务重试后的列表刷新。

所有测试使用内存 SQLite、临时目录和假网关。没有调用文本、图像、音频或视频供应商；
视频任务只验证既有任务行的显示和本地状态，不提交、轮询或生成视频。

关联主清单：`W6-TASK-001`、`W7F-TASK-LIST-001`、`W7F-TASK-DETAIL-001`、
`W9A-DBTABLE-TASKS-001`。
