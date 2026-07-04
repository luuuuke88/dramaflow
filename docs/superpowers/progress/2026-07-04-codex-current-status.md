# 2026-07-04 Codex 当前接力快照

## 当前基线

- 分支：`master`
- 当前代码指针：以 `git log -1` / `git status` 为准；不要把本文档里的历史提交号当作实时 HEAD。
- 最近接力：`16f83d0 docs(progress): record current flutter parity status` 之后继续推进工作台/NLE 素材层属性编辑、移动端全屏单列添加/属性编辑/媒体库按播放头添加/本镜候选选择/本镜候选视频全屏预览/本镜候选删除确认/本镜时长编辑/清空已选轨道确认/合成成功结果/批量移动起点/批量改轨/批量裁剪尾部/按播放头切分、透明度编辑/合成、复制、波纹复制、波纹移动、按时间起点可视拉开、按 lane 可视分轨、选中多素材层后按播放头批量切分/复制到播放头/对齐播放头/尾部对齐播放头/中心对齐播放头/裁到播放头/裁开头到播放头/批量删除/批量波纹删除/批量复制/批量波纹复制/批量移动/批量改轨/批量波纹移动/批量裁剪/批量波纹裁剪/整组拖拽平移并后移避让同轨冲突、自动放层、纵向拖拽到占用层时自动下探空层、媒体库按播放头快捷添加到时间线、媒体库 clip 按落点坐标拖放到时间线，以及媒体库拖放起点/尾部接近锚点时自动吸附。
- 权威目标：`docs/superpowers/specs/2026-07-03-v0.3-toonflow-parity-design.md`
- 页面证据账本：`docs/superpowers/progress/2026-07-04-page-parity-checklist.md`

本文件记录当前事实，避免后续接力时误读旧的 `238 tests`、`268 tests` 或 `342 tests` 阶段记录。

## 2026-07-05 接力验证

Codex 接上 Claude/Codex 交替开发后的最新实测基线：

- `git status --short --branch`：`## master`，工作树干净。
- `git log -1 --oneline`：`88bf7eb feat(agent): configure memory rag limit`。
- `cd app && flutter analyze`：通过，0 issues。
- `cd app && flutter test`：通过，430 tests。
- `cd app && dart run tool/e2e_local_smoke.dart`：通过，纯本地从章节、剧本、素材、分镜、候选视频、镜头配音走到合成导出 mp4。
- `cd app && flutter build macos --debug`：通过，产物 `build/macos/Build/Products/Debug/dramaflow.app`。
- `cd app && flutter build ios --simulator --debug`：通过，产物 `build/ios/iphonesimulator/Runner.app`。
- `cd app && flutter build apk --debug`：通过，产物 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd app && flutter build web`：通过，产物 `build/web`；仍只代表 Web 预览入口可构建，不代表 H5 完整本地流程。
- Claude 遗留的 `.claude/worktrees/agent-a0a8eaa3ee84e1075` 上有旧 i18n 未提交 diff，但该分支是当前 `master` 的祖先；`commonClear`、settings storage 等相关 l10n key 和 `df_search_field.dart` 的本地化改动已经存在于 `master`。不要把那个旧 worktree 的 diff 当成必须合入的最新补丁。

这次验证没有改变功能代码；它只把当前可构建、可 smoke 的状态重新钉住，并澄清旧 worktree 状态。

## 刚完成的验证

2026-07-04 本轮 Codex 接手后重新跑过：

- `cd app && flutter analyze`：通过，0 issues。
- `cd app && flutter test`：通过，430 tests。
- `cd app && dart run tool/e2e_local_smoke.dart`：通过，纯本地、不调用供应商，从章节、剧本、素材、分镜、候选视频、镜头配音走到合成导出 mp4。
- `cd app && flutter build macos --debug`：通过，产物 `build/macos/Build/Products/Debug/dramaflow.app`。
- `cd app && flutter build ios --simulator --debug`：通过，产物 `build/ios/iphonesimulator/Runner.app`。
- `cd app && flutter build apk --debug`：通过，产物 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd app && flutter build web`：通过，产物 `build/web`，但这只证明 Web 预览入口可构建，不代表 H5 完整本地流程已完成。

已知构建警告：

- macOS/iOS：`media_kit_video` 相关插件暂未支持 Swift Package Manager，Flutter 将来可能提升为错误。
- Android：`wakelock_plus` 仍使用旧 Kotlin Gradle Plugin 接入方式，Flutter 将来可能提升为错误。
- Web：构建时提示 CupertinoIcons 字体缺失，但当前 Web 仍是预览入口，不是完整客户端验收目标。

## 当前完成度判断

原生客户端主线已经比较扎实：

- macOS/iOS/Android 使用单体 Flutter App + Dart 内嵌 engine，不依赖旧 `server/`、Node 或 JS 后端。
- 本地 sqlite3 schema、任务队列、供应商配置、提示词模板、模型绑定、媒体存储、错误码/i18n 基建都在 Flutter 工程内。
- 项目、章节/事件、剧本、素材/画风、制作画布、节点式图片编辑器、工作台、配音、任务中心、Agent 页、设置页都有 engine/widget/platform 测试证据。
- 离线 smoke 已证明第一版客户端本地链路能从章节走到成片导出。
- 移动端不是空壳：390px widget tests 已覆盖项目、章节、剧本、素材、制作、工作台入口/重排/素材层添加/素材层属性编辑/媒体库按播放头添加/本镜候选选择/本镜候选视频全屏预览/本镜候选删除确认/本镜时长编辑/清空已选轨道确认/合成成功结果/批量移动起点/批量改轨/批量裁剪尾部/按播放头切分、配音、任务、Agent 入口/清空记忆确认/内置能力说明/技能编辑/自定义技能新增/长期记忆新增编辑和设置路径。

页面 parity 当前状态：

- `Verified`：项目列表 + 新建向导、章节管理 + 事件、剧本、素材库、制作画布、节点式图片编辑器、配音、任务中心、全套设置。
- `Partial`：多轨工作台、Agent 体系页。制作画布已进入 `Verified`：有 source-anchored visual evidence、桌面/移动截图、生产页 widget 覆盖；如严格要求 live ToonFlow 浏览器并排截图，仍可作为加强证据补充。

## 仍不能称为“完全复刻”的部分

1. Web/H5 仍是预览入口。
   - `app/lib/src/bootstrap/bootstrap_web.dart` 运行 `DramaFlowWebPreviewApp`。
   - `app/test/platform/web_bootstrap_static_test.dart` 明确断言 Web bootstrap 不导入 `src/engine`、`dart:io` 或 `sqlite3`。
   - 真正完整 H5 需要单独 M6：Web 数据库、浏览器文件存储、WebCodecs/Mediabunny 合成器、Web 媒体预览、Web 文件选择。

2. 工作台仍不是完整 ToonFlow WebAV/NLE。
   - 已有顺序分镜、候选视频、音频绑定、转场/滤镜 metadata、原生端合成、timeline overlay 渲染、overlay 素材层按时间起点可视拉开、按 lane 可视分轨、媒体库快捷添加/媒体库按落点拖放并支持起点与尾部吸附/时间线拖拽/裁剪/属性编辑/透明度编辑与合成/复制/波纹复制/波纹移动/自动找空层/纵向拖拽占用层自动下探/吸附/分割/按播放头批量切分/复制到播放头/对齐播放头/尾部对齐播放头/中心对齐播放头/裁到播放头/裁开头到播放头/删除/批量删除/批量波纹删除/批量复制/批量波纹复制/批量移动/批量改轨/批量波纹移动/批量裁剪/批量波纹裁剪/多选整组拖拽平移并后移避让同轨冲突/ripple/同轨避让。
   - 仍缺完整 WebAV clip editor 级别能力：复杂 snapping、复杂叠放冲突、更多 ripple、多素材自由编排细节、Web 端转场/滤镜真实渲染。

3. Agent 体系仍是瘦身版。
   - 已有模型部署、技能开关、消息持久化、本地记忆、RAG 检索条数配置、工具调用、简单 custom-js-agent return 模板。
   - 未完整复刻 ToonFlow/Claude 风格的多层 Agent 编排、向量 RAG 召回/重排、完整 QuickJS/flutter_js 自定义技能运行时。

4. 制作画布 live 浏览器并排截图只是加强证据。
   - 当前 `page-parity-checklist.md` 已用 source-anchored visual evidence 和 committed PNG 截图把制作画布页收为 `Verified`；若后续验收坚持 live ToonFlow 运行截图，再补该环境证据。

## 接力建议

短期最优路线：先把“原生客户端第一版”闭环做到可演示、可验收，再单独开 Web/H5 M6。

推荐顺序：

1. 继续推进工作台 NLE：补复杂重叠策略、更多 ripple 规则或更完整的属性面板能力，每次一小片并锁测试。
2. 单独写 M6 Web 架构设计后再动 Web engine。不要在现有 `dart:io + sqlite3 FFI` engine 上直接硬塞 H5。
3. 如果 luke 坚持“完全复刻 Agent”，先写 Agent/RAG 子系统设计，再实现多层编排和向量检索；不要把当前瘦身版误判为完整。

## 不要误踩的边界

- 不要运行或修改 `server/`；它是弃用参照。
- 不要把 `flutter build web` 当成 Web 完成证据。
- 不要把 page checklist 里的 `Verified` 外推到“整个 ToonFlow 完全复刻”；它只证明当前页面范围内的已列能力。
- 改 engine 必须补 `app/test/engine/`；完成任何代码任务前必须跑 `flutter analyze` 和 `flutter test`。
