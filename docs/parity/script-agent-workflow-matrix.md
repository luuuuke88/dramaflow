# Script Agent 工作流对照

状态：**核心工作流尚未等价。** 本文是 2026-07-21 的逐文件复核记录，补充
`master-checklist.md` 中的 `W6-SCRIPTAGENT-001`、`W6E-STORE-AGENT-001`、
`W7E-SCRIPTAGENT-PLAN-001`、`W7F-SOCKET-AGENT-001`、
`W8-AGENTTOOL-SCRIPTAGENT-001` 与 `W9C-SCRIPTSKILL-CORE-001`。不调用文字、图片、
音频或视频供应商。

## 结论先行

Flutter 已有一个可用的、按项目持久化的单层助手，并且已接入现有流水线与花费/破坏
确认闸；它**不是** ToonFlow 1.1.8 的 Script Agent。原版的用户可见主线是：

```text
剧本 Agent 对话
  -> 决策层收集改编参数和上下文
  -> 编剧：故事骨架
  -> 编辑：审核/用户确认
  -> 编剧：改编策略
  -> 编辑：审核/用户确认
  -> 编剧：按集生成剧本
  -> 右侧三个工作区可查看、编辑和保存
```

当前 Flutter 的 `assistant_chat.dart` 只有“模型返回一条文本或一次工具调用”的平面循环。
它不能用 `scriptPlan` 替代上述工作区：`scriptPlan` 是制作画布中的项目级导演规划，原版
Script Agent 则持久化 `storySkeleton`、`adaptationStrategy`，并把剧本列表同步到
`o_script`。

## 逐项证据

| 原版行为 | ToonFlow 1.1.8 证据 | 当前 Flutter 证据 | 判定 |
| --- | --- | --- | --- |
| 独立 `/scriptAgent` 页面，左侧聊天、右侧工作区 | `Toonflow-web/src/views/scriptAgent/index.vue:1-177` | `app/lib/src/app.dart:77-80` 路由到 `AgentChatScreen`；其 `agent_chat_screen.dart:177-283` 只有聊天列表 | **部分**：入口和聊天存在，右侧工作区缺失 |
| 发送、流式思考片段、停止 | 原版 `index.vue:7-28`；`stores/scriptAgent.ts:21-57` 使用 `useChat`，有 `stopGenerate` 和 XML 流标签回调 | `assistant_chat.dart:95-116,186-289` 等待整次 `generateAgentTurn` 完成后再持久化；`agent_chat_screen.dart:58-89` 没有取消按钮 | **缺失**：无逐 token/思考分段、无中止 |
| 0-3 思考等级 | `index.vue:54-77,220-225`；`stores/scriptAgent.ts:73-81` 通过 `updateThinkConfig` 发给 socket | Flutter 无 `thinkLevel` 或 `updateThinkConfig` 调用 | **缺失** |
| 清理消息、摘要、全部记忆；可重连 | `index.vue:35-49,297-341` 调 `/agents/clearMemory` 的三种类型 | `agent_chat_screen.dart:91-108` 仅删除整个 `assistantChat:<family>` JSON 会话 | **部分**：仅“全部清空”可用；无摘要层与重连 |
| 故事骨架、改编策略、剧本三个右侧 Tab | `index.vue:107-177,363-426` | `agent_chat_screen.dart` 无工作区；`script_plan.dart:15-59` 仅有制作画布的单 Markdown `scriptPlan` | **缺失**。`scriptPlan` 不能计为等价实现 |
| 编辑并持久化骨架、策略、剧本 | `routes/scriptAgent/getPlanData.ts:16-40`、`setPlanData.ts:20-37`、`updateData.ts:24-31` | `assistant_actions.dart:305-310` 只可用工具覆写单条 `o_script`；没有 `scriptAgent` 工作区数据模型 | **部分**：剧本存在独立编辑能力；双工作文档和面板保存缺失 |
| 决策 -> 编剧子 Agent -> 编辑监督的阶段化对话 | `src/agents/scriptAgent/index.ts:41-234`：1 决策 + 3 编剧执行 + 1 编辑监督；具名消息气泡 | `assistant_chat.dart:186-265`：同一 `_driveAssistantLoop`，两家族共用同一工具表 | **缺失**：不能以恢复旧的 2.5 万行实现为目标，应实现等价的分阶段会话状态和专属工具边界 |
| Agent 自取章节事件、原文、已存剧本、当前工作区 | `src/agents/scriptAgent/tools.ts:34-117` 的 `get_novel_events`、`get_novel_text`、`get_script_content`、`get_planData` | `assistant_actions.dart:39-142` 没有这些只读上下文工具；`generate_scripts` 反而读取 Flutter 独有的 `o_event` 数据流 | **缺失**。现有 `generate_scripts` 不能作为原版工具的替身 |
| 原版五份剧本改编方法论 | `skills/script_agent_decision.md`、`script_agent_supervision.md`、`script_execution_skeleton.md`、`script_execution_adaptation.md`、`script_execution_script.md`，由 `index.ts:46-47,145-216` 分别加载 | `assistant_skills.dart:1-5` 明确旧子 Agent skill seed 未迁；`assistant_chat.dart:360-372` 仅有通用提示词 | **缺失** |

## 已有能力，后续应保留

这些并不等于原版 Script Agent，但可作为新的 Flutter 实现底座，避免重复造轮子：

- `assistant_chat.dart`：按项目和家族隔离的消息持久化、模型工具调用、自动模式上限。
- `pipeline_policy.dart`：同一确认闸覆盖助手和页面的付费/破坏操作。
- `assistant_deploy.dart`：`scriptAgent` 模型部署配置。
- `assistant_skills.dart`：Markdown frontmatter 解析及文件路径边界保护。
- `scripts.dart` 和 Script 页面：`o_script` 的现有 CRUD、导入、批量添加和资产提取。

## 不能误判为已完成的替代物

| Flutter 项 | 实际职责 | 为什么不能抵扣原版 Script Agent 缺口 |
| --- | --- | --- |
| `scriptPlan` / `script_plan.dart` | 制作画布的导演规划，后续用于分镜表和分镜生成 | 数据键、使用阶段和文档形态都不同；没有故事骨架/改编策略双字段，也不由剧本 Agent 对话更新 |
| `generate_scripts` | 从 Flutter 扩展的 `o_event` 批量入队生成剧本 | 原版 Script Agent 是对话内分阶段改编；原版手动 Script 页面没有此入口，见 `script-event-entry-matrix.md` |
| `project_notes.dart` | 手动项目笔记的词法检索 | 不提供原版短期记忆、摘要记忆、语义检索或 `deepRetrieve` |
| 自动模式 | 最多五轮的平面工具循环 | 不提供原版“每阶段审核后由用户决定继续/修复/重做”的工作流 |

## 后续最小实现边界

待单独设计并获得实现批准后，按原版可观察行为分批完成，而不是复活已被证实非原版的
JS 解释器、ES-DSL 或无边界监督系统：

1. 建立 `scriptAgent` 工作区数据：骨架、策略、剧本镜像；跨端呈现为聊天与三个可编辑工作区。
2. 为剧本家族分出四个原版同职责的只读上下文工具和三个阶段执行动作；制作家族继续使用它自己的工具边界。
3. 引入可取消的增量消息状态和思考等级；传输保持 Flutter 进程内架构，不照搬 WebSocket。
4. 将原版五份剧本 skill 的方法论作为受版本管理的提示词资源迁入，阶段结果写入工作区；监督结论和用户继续/修复/重做决策可见、可恢复。
5. 每项同时补 engine、widget 的 390dp 与桌面宽度测试，并在本表和总清单逐项标记证据。

在上述项完成之前，所有相关总清单行继续保持“部分实现”或“缺失”。
