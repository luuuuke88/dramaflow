# DramaFlow 设计文档

> 2026-07-02 深夜构建。目标：里程碑 A 的核心垂直切片 —— 显式可控的 AI 短剧流水线 + Flutter 多端客户端。

## 为什么重新设计（相对 ToonFlow 的差异）

ToonFlow 的三个结构性问题（实测扫描确认）：

1. **隐式 AI 对话驱动流程**：Agent 用 LLM 决策循环决定下一步做什么，用户"要说话才能继续"，控制力弱。
2. **浏览器充当状态存储和执行器**：断开网页 Agent 就失忆/瘫痪，无法做成服务端流水线。
3. **错误不可观测**：Agent 循环错误只 console.error，生成失败原因经常丢失。

DramaFlow 的对策：**显式流水线 + 数据库任务队列**。没有决策 Agent —— 每一步都是用户明确触发的动作，产生持久化的 job，状态/失败原因全部落库，界面直接展示可重试。

## 流水线（5 个显式阶段）

```
小说导入 → 剧本生成 → 素材(角色/场景)提取+生图 → 分镜生成+镜头图 → 视频生成
 (手动)    (gpt-5.5)      (gpt-5.5 + gpt-image-2)     (gpt-5.5 + gpt-image-2)  (seedance,接好未测)
```

每个阶段：用户点按钮 → 创建 job → 队列执行 → 轮询看状态 → 失败显示原因+重试按钮。
LLM 结构化输出用 zod 校验，解析失败自动带错误反馈重试一次，再失败则 job 失败并保留原始输出供诊断。

## 技术栈

**后端** (`server/`)：Node 20+ / TypeScript / Hono / better-sqlite3(WAL) / zod。tsx 直跑，无构建步骤。
**客户端** (`app/`)：Flutter (macOS/Windows/Android/iOS/Web) / Riverpod / dio / go_router。

## 供应商层

| 用途 | 提供方 | 说明 |
|---|---|---|
| 文本 | azt `http://127.0.0.1:8787/v1` `gpt-5.5` | OpenAI 兼容 chat completions。azt 内部对 Codex 请求串行化(2.5s min delay)，后端文本并发=1 |
| 图片 | azt 同上 `gpt-image-2` | `/v1/images/generations`，b64_json。**注意**：响应头等到生成完才返回(3-6min)，HTTP 客户端不能设短 header 超时；size/quality 是建议性的，prompt 里注入"MUST be 1024x1024 SQUARE"类指令控制构图 |
| 视频 | Volcengine Seedance `doubao-seedance-2-0-mini-260615` | 从 ToonFlow vendor 移植，首帧图+prompt 模式。**接好但未测试，留给用户** |

Provider 是普通 TS 模块（不搞 ToonFlow 的 vm2 沙箱），接口统一：`generateText(sys, user) → string`、`generateImage(prompt) → localPath`、`generateVideo(imagePath, prompt) → localPath`。配置存 settings 表，可从界面改。

## 数据模型（SQLite）

- `projects` id, name, artStyle, createdAt, updatedAt
- `novels` id, projectId, title, content
- `episodes` id, projectId, idx, title, synopsis, scriptJson(场景+台词), status, error
- `assets` id, projectId, kind(character|scene), name, description, imagePrompt, imagePath, status, error
- `shots` id, episodeId, projectId, idx, description, dialogue, camera, assetNames(json), imagePrompt, imagePath, imageStatus, imageError, videoPrompt, videoPath, videoStatus, videoError
- `jobs` id, projectId, kind, targetId, state(queued|running|done|failed|canceled), attempt, error, payload, result, createdAt/startedAt/finishedAt
- `settings` key, value

状态机一律：`none → queued → running → done | failed(error 落库)`，失败可重试（新 job，attempt+1 记录在案）。

## 任务队列

- DB 表为唯一事实源，进程内 worker 循环消费（每 500ms tick）
- 每类并发上限：text=1、image=1、video=1（配置可调；azt/OAuth 路径脆弱，宁慢勿炸）
- 启动恢复：`running` 的 job 一律标记 `failed("服务重启中断")`，用户可见可重试
- 超时：text 300s / image 960s / video 轮询 20min

## 认证

MVP：单 token（settings 表 `apiToken`，默认 `local-dev`），`Authorization: Bearer` 或 `?token=` (媒体文件用)。多租户/账号体系是里程碑 B 的事，本版不做但路由结构预留。

## Flutter 客户端

**响应式**：<700px 底部导航（手机），≥700px NavigationRail（桌面/平板），核心内容区自适应网格。
**主题**：深色影棚风（炭黑底 + 琥珀主色 + 状态色系），Material 3。
**界面**（8 个）：
1. 项目列表（网格卡片）
2. 项目流水线总览（5 阶段卡片：状态/计数/主操作 —— 产品核心，"一眼看懂进行到哪、哪里失败"）
3. 小说（导入/编辑）
4. 剧本（分集查看/编辑/重新生成）
5. 素材库（角色/场景网格，图片生成状态徽章，批量生成，失败原因+重试）
6. 分镜（镜头列表：描述/台词/镜头图/视频状态，逐镜生成）
7. 任务中心（全部 job 实时状态+失败原因，全局重试入口）
8. 设置（后端地址、token、模型配置、健康检查）

**实时性**：活跃 job 存在时 2s 轮询 `/api/jobs/active`，无活跃任务时停止轮询（省电/省请求）。

## 测试范围（今晚）

- ✅ 自测：文本生成(gpt-5.5)、图片生成(gpt-image-2 2-4张)、全 REST API、Flutter 界面（macOS + Web 双端验证响应式）
- ⏸ 留给用户：视频生成（volcengine 通道接好、配置就绪、界面可点）
