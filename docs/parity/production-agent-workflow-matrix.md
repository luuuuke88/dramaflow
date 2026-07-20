# Production Agent 工作流对照

状态：**制作画布主体已独立存在，Agent-画布实时联动尚未等价。** 本文记录
2026-07-21 的逐文件复核，补充总清单 `W6E-STORE-AGENT-001`、
`W7F-SOCKET-AGENT-001`、`W8-AGENTTOOL-PRODUCTION-001` 与
`W9C-PRODSKILL-*`。本轮未调用任何文字、图像、音频或视频供应商。

## 原版可观察主线

```text
制作画布右侧“视频策划”对话
  -> 决策层读取当前剧集、模型和当前画布数据
  -> 执行导演/监制以具名消息分阶段工作
  -> XML 流式产物同步当前画布的导演规划、分镜表、衍生资产、分镜面板
  -> 用户仍可在画布节点上编辑、生成首帧图或视频
```

原版不是只把任务放进队列：Production Agent 有独立的 `get_flowData`、
`add_deriveAsset`、`del_deriveAsset`、`generate_deriveAsset`、
`generate_storyboard` 和 `add_flowData_storyboard` 工具。它们经 socket 与当前打开
剧集的 `flowData` 双向同步。

## 逐项对照

| 原版行为 | ToonFlow 1.1.8 证据 | 当前 Flutter 证据 | 判定 |
| --- | --- | --- | --- |
| 画布右侧 Agent；移动端可进入同一对话 | `Toonflow-web/src/stores/productionAgent.ts:13-65`；生产页挂载该 store | `production_screen.dart:359-411` 桌面右侧滑出 `CanvasChatPanel`；`:444-453` 移动端全屏打开 | **已具备入口适配**，但不代表内部 Agent 等价 |
| 当前剧集隔离 | `productionAgent.ts:35-44,443-451` 以 `projectId:productionAgent:episodesId` 建 socket 上下文，并能 `updateContext` | `assistant_chat.dart:391-395` 仅用 project + `production` family；`episodesId` 恒为 `NULL` | **部分**：项目隔离有，当前剧集隔离缺失 |
| 流式消息、思考片段、停止、0-3 思考等级 | `productionAgent.ts:42-100,477-510`；`useChat` XML 流解析 | `canvas_chat_panel.dart:50-72` 只等待整个 `sendAssistantMessage`；无停止和思考等级控件 | **缺失** |
| Agent 读取当前画布的 script/plan/table/assets/storyboard/workbench | `productionAgent/tools.ts:89-111` 的 `get_flowData`，经 socket 从页面 `flowData` 获取 | `assistant_actions.dart:39-142` 两个家族共用 13 个动作；无当前画布读取工具 | **缺失** |
| Agent 直接新增/更新/删除衍生资产，并同步画布 | `tools.ts:113-181`；`productionAgent.ts` 注册 `addDeriveAsset` / `delDeriveAsset` 回调 | Flutter 资产中心与画布节点可各自 CRUD，但 `assistant_actions.dart` 没有对应工具 | **部分**：资产功能存在，Agent 画布联动缺失 |
| Agent 直接插入分镜面板，保持当前画布更新 | `tools.ts:243-299` 的 `add_flowData_storyboard`；`productionAgent.ts:46-99` 的 XML 回写 | Flutter `storyboard.dart`/`storyboard_canvas_node.dart` 有独立的分镜持久化和节点 UI；Agent 只有 `generate_storyboards` 入队动作 | **部分**：分镜节点存在，Agent 直接写回缺失 |
| Agent 可触发衍生资产、首帧图并显示进度 | `tools.ts:183-241`；页面对资产/分镜状态轮询 | Flutter `assistant_actions.dart:244-286` 能提交资产提取、分镜和首帧图任务；任务中心和节点各自显示状态 | **部分**：任务触发与状态展示存在，但没有原版的当前画布工具语义 |
| 7 个执行/监督子 Agent 与专属 skill | `src/agents/productionAgent/index.ts:197-374` | `assistant_chat.dart:360-388` 是通用单层 prompt + 统一工具表；`assistant_skills.dart:1-5` 明确旧子 Agent seeds 未迁入 | **缺失** |
| 风格/导演 skill 按需激活 | `productionAgent/index.ts:377-490`；执行子 Agent 按职责获取不同 skill 目录 | Flutter 只会把全部启用 Markdown skill 拼进通用系统提示词 | **缺失** |

## Flutter 已有且应复用的底座

- 无限画布与桌面拖拽、移动端六个等价 Tab：`production_screen.dart`。
- 项目级导演规划、剧集级分镜表、分镜和工作台的实体化持久化：
  `script_plan.dart`、`storyboard_table.dart`、`storyboard.dart`、`workbench_screen.dart`。
- `CanvasChatPanel` 的桌面滑出、移动全屏入口，以及统一付费/破坏确认闸。
- 队列任务与界面刷新机制。Agent 对接应调用这些现有实体 API，不复制一套
  `flowData` 内存镜像。

## 迁移边界

Production Agent 的目标是**用户可观察效果等价**，不是复制 Electron 的 socket 架构：

1. 以当前 `projectId + scriptId` 和数据库实体组装一个只读画布快照，代替原版
   `socket.emit('getFlowData')`。
2. 为生产家族单独注册原版同职责的读取、资产变更、分镜写入和生成动作；所有写入
   走 Flutter 现有 Engine API 与 `pipeline_policy`。
3. 写入成功后使 Riverpod/节点重新读取实体数据，达到原版“当前画布立刻可见”的结果，
   不引入第二份 `flowData` 真相来源。
4. 具名的执行导演/监制消息、阶段产物、可取消增量输出和按需 skill 载入，与
   `scriptAgent` 共用同一套新会话基础设施，但各自保有严格独立的工具表和提示词。
5. 先在 390dp 与桌面宽度补 widget/engine 回归；视频生成只验证请求入队、参数和状态，
   不在自动化中调用上游视频服务。

在以上项得到代码和测试证据前，制作端 Agent 相关清单条目保持“部分实现”或“缺失”；
画布本身已验证的条目不因 Agent 缺口回退，也不能抵扣这些缺口。
