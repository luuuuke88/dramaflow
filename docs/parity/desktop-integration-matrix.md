# 桌面集成对照：启动、系统链接与 macOS 生命周期

这份对照聚焦**用户能感觉到的桌面应用行为**，而不是 Electron 的进程模型。它把原版的无边框窗口、Node 服务和 `toonflow://` 协议拆开：纯粹为 Electron 补洞的机制不复制；在 macOS 原生应用上仍有用户价值的启动失败提示、外部链接和窗口生命周期则必须据实记录。

本轮只核对源码、既有回归和 Flutter macOS 壳文件；没有启动真实供应商，也没有提交、轮询或下载任何视频任务。

## 结论一览

| 用户动作 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 数据目录无法写入时启动 | 先创建/写删测试文件；失败显示含目录与解决建议的原生警告，确认后退出 | `bootstrap()` 直接调用播种和 `Engine.boot()`；`Directory.createSync` / 打开 SQLite 的异常没有应用层捕获或说明窗口 | **缺失** |
| 关闭 macOS 最后一个窗口 | `window-all-closed` 在 Darwin 不退出；Dock 激活时重建窗口 | `applicationShouldTerminateAfterLastWindowClosed` 返回 `true`，最后一个窗口关闭即退出进程 | **缺失** |
| 点击侧栏反馈、GitHub | 使用 `shell.openExternal` 交给系统默认浏览器 | 两个侧栏入口通过 `url_launcher` 打开外部 URL | **已有但未完整验证** |
| 点击 Agent 或其他 Markdown 中的外部链接 | 全局 Markdown 渲染器把链接交给 `handleLinkClick`，Electron 下以系统浏览器外开 | Agent 输出没有 Markdown 链接渲染/点击分发；仅两个硬编码侧栏入口可外开 | **部分实现** |
| 原生标题栏、窗口最小化/缩放/拖动 | Electron 主动 `frame:false` 后自行补回这套控件 | 使用 macOS 原生窗口和系统红黄绿控制；用户完成同一窗口操作 | **不适用：不复制自绘替代层** |

## 启动失败不是“引擎内部异常”

原版在 [`src/app.ts`](../../../Toonflow-app/src/app.ts) 的 `checkPermissions()` 中，应用后端开始前就会验证用户数据目录。失败时它显示“权限不足”窗口，文本包含实际目录和处理建议。这一行为不依赖浏览器页面，属于桌面用户的明确保护。

Flutter 的启动链是 [`bootstrap_io.dart`](../../app/lib/src/bootstrap/bootstrap_io.dart) 的 `bootstrap()` → [`engine.dart`](../../app/lib/src/engine/engine.dart) 的 `Engine.boot()`。它在 `runApp` 之前同步创建目录、播种文件和打开 SQLite；此路径没有 `try/catch`、错误页或退出策略。现有 [`bootstrap_io_test.dart`](../../app/test/bootstrap/bootstrap_io_test.dart) 只证明正常播种时不会覆盖用户文件，不能证明只读目录或数据库无法打开时用户能看懂发生了什么。

因此总清单的 `W10-BACKEND-LIFECYCLE-001` 保持**缺失**。将来修复应只建立一个可测试的启动错误边界：保留异常的原始原因和数据目录，向桌面/移动用户显示可理解的失败页或原生对话框，并提供明确退出/重试路径。它不应模仿 Express、Electron `dialog` 或 `app.quit()` 的内部实现。

## macOS 的关闭与重新打开

ToonFlow 的 [`build/main.js`](../../../Toonflow-app/build/main.js) 在 `window-all-closed` 中仅在非 Darwin 平台退出，并在 `activate` 时没有窗口便新建。这表达的是标准 macOS 应用约定：关最后一个窗口不等于退出应用，点击 Dock 图标会重开窗口。

DramaFlow 的 [`AppDelegate.swift`](../../app/macos/Runner/AppDelegate.swift) 仍是 Flutter 模板的 `return true`，因此表现相反。这个差异不能用 widget 测试代替：需要在实际 macOS Debug/App 包中关闭最后一个窗口并从 Dock 重新激活，才能将 `W10-APPLIFECYCLE-DOCK-001` 由缺失改判。

另一个需要避免误读的细节是，ToonFlow 自绘标题栏的关闭按钮调用 `app.exit(0)`，这可能绕过它自己的 `before-quit` 清理钩子。这个原版内部矛盾不降低上述“正常关闭窗口时应保留 Dock 应用”的源码证据，也不构成把 DramaFlow 改成强制杀进程的理由。

## 外部链接：机制存在，覆盖范围不够

ToonFlow 的 [`App.vue`](../../../Toonflow-web/src/App.vue) 重写了全局 Markdown 的链接渲染：每个链接被注入 `handleLinkClick`，Electron 下通过 `openurlwithbrowser` 交给 `shell.openExternal`。设置更新、API Key 申请、反馈、GitHub 和 Agent 富文本链接都走同一出口。

DramaFlow 在 [`shell.dart`](../../app/lib/src/widgets/shell.dart) 中已经用 `url_launcher` 接了“反馈/问题”和“跳转 GitHub”，语义正确，但 [`shell_test.dart`](../../app/test/widgets/shell_test.dart) 尚未驱动点击并断言平台调用；Agent 聊天页也没有 Markdown 链接渲染。因此 `W10-BRIDGE-EXTERNALLINK-001` 只能保持**部分实现**。

后续修复的最小边界是：

1. 把应用文本中的外部 URL 收敛到一个受测试的 `openExternalUri` 适配层，拒绝非安全 scheme；
2. 用真正的 Markdown 富文本组件或链接识别器让 Agent 回复中的 `https` 链接可点击外开；
3. 为桌面和窄屏分别覆盖链接动作的可达性。无需建立 Electron 风格的自定义 URI 协议。

侧栏目前仍指向上游 `HBAI-Ltd/Toonflow-app` 及其 issues。它不影响“能否调用系统浏览器”的功能结论，但品牌和反馈地址应在发布前按许可证/产品决定统一替换，不能悄悄当作 DramaFlow 的正式反馈渠道。

## 证据与后续验收

| 范围 | 原版证据 | Flutter 证据 | 当前可执行验证 |
| --- | --- | --- | --- |
| 数据目录保护 | `Toonflow-app/src/app.ts:22-47` | `app/lib/src/bootstrap/bootstrap_io.dart:22-41`、`app/lib/src/engine/engine.dart:586-613` | 正常播种：`flutter test test/bootstrap/bootstrap_io_test.dart`；不可写目录需以后加入受控集成测试 |
| Dock 生命周期 | `Toonflow-app/build/main.js:251-258` | `app/macos/Runner/AppDelegate.swift:6-8` | macOS Debug 包人工关闭最后窗口、Dock 重开；当前没有可替代的 widget 证据 |
| 外部链接 | `Toonflow-app/build/main.js:216-226`、`Toonflow-web/src/App.vue:55-115` | `app/lib/src/widgets/shell.dart:151-166` | 现有壳回归：`flutter test test/widgets/shell_test.dart`；链接动作专项测试仍缺 |

这份矩阵对应总清单 `W10-BACKEND-LIFECYCLE-001`、`W10-BRIDGE-EXTERNALLINK-001`、`W10-APPLIFECYCLE-DOCK-001` 与 `W10-WINDOW-CHROME-001`。它不把 Electron 的后端启动、无边框窗口或私有协议误算成 Flutter 的待办，同时不掩盖在原生端仍应补齐的用户保护。

## 本机构建与启动复核（2026-07-19）

本轮在 macOS 上执行 `flutter analyze`，结果为 `No issues found`；随后执行
`flutter build macos --debug`，成功生成 `build/macos/Build/Products/Debug/dramaflow.app`。
通过 macOS 可访问性树和窗口截图复核，应用实际启动至项目壳的“供应商”设置分区，
`azt` 与 `volcengine` 卡片、启用开关和“添加供应商”按钮均可见，未复现黑屏。

构建仍报告 `media_kit_libs_macos_video` 和 `media_kit_video` 尚未支持 Swift Package
Manager；当前 Flutter 仅给出未来兼容性警告，未阻塞 CocoaPods Debug 构建。该烟雾验证
只证明当前应用可编译和呈现首个真实界面，不替代本页尚未完成的不可写数据目录错误边界、
Dock 生命周期、外部链接覆盖或视频供应商人工验收。
