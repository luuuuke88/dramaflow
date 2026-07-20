# 剧本页事件入口对照

状态：**剧本页的 Flutter 独有入口已收口；Agent 与事件表扩展仍待独立审计。**

这份补充矩阵从小说事件表写入反向追踪到剧本页，避免把“小说页不再显示事件 Tab”误判为事件扩展已经完全隔离。所有结论基于 ToonFlow 1.1.8 固定源码与当前 Flutter `develop`，本轮没有调用任何真实模型或视频供应商。

## 原版可达入口

| 原版位置 | 用户可执行动作 | 事件相关性 |
| --- | --- | --- |
| `Toonflow-web/src/views/script/index.vue:1-68` | 搜索、新增剧本、批量添加、全选、导出、提取资产、批量删除、编辑卡片 | 模板、imports 和 handlers 均无 `getEvent`、`eventAnalysis` 或“从事件生成剧本”入口。 |
| `Toonflow-web/src/views/script/components/addScript.vue:1-220` | 手填或导入文件创建剧本，并关联已有资产 | 不读取 `o_event` / `o_eventChapter`。 |
| `Toonflow-web/src/views/script/components/batchAddScript.vue` | 按“第 N 集”拆分并批量保存剧本 | 不读取事件表。 |

原版确有未挂载的小说事件遗留组件，但 `/script` 主页面没有导入或调用它们。因此“从事件生成剧本”不能列为 ToonFlow 1.1.8 的剧本管理功能。

## 审计到的 Flutter 扩展

| Flutter 位置 | 当前行为 | 与原版关系 |
| --- | --- | --- |
| `app/lib/src/screens/script/script_screen.dart`（收口前） | 工具栏提供“从事件生成剧本”，弹出 `_EventScriptPicker`，读取 `Engine.events` 并提交任务 | **Flutter 独有可达入口，已于 2026-07-21 删除。** |
| `app/lib/src/engine/scripts.dart:171-255` | `generateScriptsFromEvents` 读取 `o_event/o_eventChapter` 并通过 LLM 生成剧本 | **Flutter 独有数据流。** |
| `app/lib/src/engine/events.dart:155-188` | 事件提取成功后写入 `o_event/o_eventChapter` | 为上述独有入口提供数据，原版 `generateEvents.ts:17-36` 不写两表。 |
| `app/lib/src/engine/assistant_actions.dart:233-243` | 通用助手 `generate_scripts` 默认从事件表读取 | 同样依赖该扩展；需在 Agent 总审计中单独处理，不能在页面收口时隐式保留。 |

## 结论与收口边界

`W6-SCRIPT-001` 的页面差异已关闭：`ScriptScreen` 不再导入事件模型或自适应事件选择器，也不提供“从事件生成剧本”按钮。跨端 widget 回归在预先写入 `o_event/o_eventChapter` 的情况下，仍断言该入口、对话框和 `script_generation` 任务均不可达，因此剧本手动管理页可以恢复为**已验证等价**。

下一步应先区分两层：

1. 已完成：移除 `/script` 页面上的事件生成入口和 `_EventScriptPicker`，使手动剧本管理页与原版一致。
2. 待办：审计 Agent 的“从章节事件生成剧本”是否应依原版 `scriptAgent` 行为重建，还是作为整个 Agent 模块的缺失项处理；不得用现有 `o_event` 简化链替代原版 Agent。

`o_event/o_eventChapter` 的额外写入继续由 `W9A-DBTABLE-EVENT-001` 跟踪，不能因剧本页入口已移除而上调为等价。
