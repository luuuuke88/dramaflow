# 2026-07-04 Codex 接力状态审计

Authority:

- Product target: `docs/superpowers/specs/2026-07-03-v0.3-toonflow-parity-design.md`
- Page evidence tracker: `docs/superpowers/progress/2026-07-04-page-parity-checklist.md`
- Current repo state: `master` at `d1e0829 feat(composer): render apple timeline overlays` before this follow-up Android overlay slice.

## 当前验证

本次接手后重新跑过：

- `cd app && flutter analyze`：通过，0 issues。
- `cd app && flutter test`：通过，342 tests。
- `cd app && dart run tool/e2e_local_smoke.dart`：通过，纯本地串起章节、剧本、素材、分镜、候选视频、镜头配音、合成导出。
- `cd app && flutter build web`：通过，但只证明 Web 预览入口可构建。

## 已经比较扎实的部分

- macOS/iOS/Android 原生客户端主线已是单体 Flutter + Dart 内嵌引擎，不需要 Node/JS 后端。
- 本地 sqlite3 schema、任务队列、供应商配置、提示词、模型绑定、媒体存储、错误码/i18n 基建都已落到 Flutter 工程内。
- 项目、章节/事件、剧本、素材/画风、制作画布、节点式图片编辑、工作台、配音、任务中心、Agent 页、设置页均有页面或引擎测试覆盖。
- 离线主链 smoke 证明“本地数据 + fake composer”可以完整走到导出成片文件。
- 移动端不是只做了响应式外壳：390px widget tests 已覆盖项目、章节、剧本、素材、制作、工作台、配音、任务、设置等主要路径。

## 不能再误判为完成的部分

### 1. Web/H5 不是完整客户端

`app/lib/src/bootstrap/bootstrap_web.dart` 当前启动的是 `DramaFlowWebPreviewApp`。`app/test/platform/web_bootstrap_static_test.dart` 还明确断言 Web 不导入 `src/engine`、`dart:io`、`sqlite3`。所以 Web 目前是 buildable preview，不是完整本地引擎。

要达到完整 H5，需要单独 M6：

- Web 数据库：sqlite3-wasm + OPFS，或先做 IndexedDB 适配层。
- Web 媒体存储：浏览器文件系统/OPFS，替代 `dart:io` 路径语义。
- Web 合成：WebCodecs + Mediabunny，至少先做同编码顺序拼接和音频 mux。
- Web 文件选择/预览：替代所有桌面/mobile 文件路径假设。

### 2. 工作台还不是 ToonFlow 完整 NLE/WebAV

当前工作台是顺序分镜工作流：候选视频、每镜时长/运镜、配音绑定、转场/滤镜元数据、原生端合成导出。它已经足够支撑第一版短剧流水线，但不是完整多层自由时间线。

2026-07-04 后续接力更新：Apple AVFoundation 与 Android Media3 都已接入 `o_timelineClip` 的 lane/start/duration metadata，并在 native composer 侧渲染 timeline overlay 素材层；工作台 UI 也已补素材层拖拽定位、左右边缘裁剪/缩放、以及中点分割。这解决的是“已记录的素材层能调整并进最终成片”，不是完整自由拖拽剪辑器。

缺口仍包括：

- Web 端转场/滤镜实际渲染。
- 多层素材轨 playhead 任意切点、吸附、叠放冲突处理、ripple 编辑。
- 更接近 ToonFlow WebAV 的 clip editor 行为。

### 3. Agent 体系仍是瘦身版

当前 Agent 页已有模型部署、技能开关、消息持久化、本地记忆和工具调用，但不是 ToonFlow/Claude 风格的多层 Agent + RAG + 自定义 JS 技能执行。

如果目标改回“完全复刻”，这块要重新定范围，而不能沿用之前文档里的“spec-cut”说法。

## 接力建议

短期最优路线不是马上啃 Web 全量，而是先把原生客户端闭环做成可演示版本：

1. 继续用 `page-parity-checklist.md` 收口每页按钮级证据，特别是制作画布视觉对照。
2. 补一个真机/模拟器人工验收记录：iPhone/Android 从导入章节到合成导出走一遍。
3. 然后再开 M6 Web 设计文档。Web 是大子项目，不能在现有 IO engine 上直接小修小补。

如果产品目标坚持“Flutter Web 也必须完整本地跑流程”，下一步应先写并确认 M6 Web 架构设计，再动代码。
