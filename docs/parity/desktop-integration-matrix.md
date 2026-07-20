# 桌面集成对照：启动、系统链接与 macOS 生命周期

这份对照聚焦**用户能感觉到的桌面应用行为**，而不是 Electron 的进程模型。它把原版的无边框窗口、Node 服务和 `toonflow://` 协议拆开：纯粹为 Electron 补洞的机制不复制；在 macOS 原生应用上仍有用户价值的启动失败提示、外部链接和窗口生命周期则必须据实记录。

本轮只核对源码、既有回归和 Flutter macOS 壳文件；没有启动真实供应商，也没有提交、轮询或下载任何视频任务。

## 结论一览

| 用户动作 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 数据目录无法写入时启动 | 先创建/写删测试文件；失败显示含目录与解决建议的原生警告，确认后退出 | `buildDramaFlowApp()` 在读取资源和打开 SQLite 前创建、写入并删除一次性探针；任何失败由 `bootstrap()` 换到无 Engine 的本地化失败页，显示目录并可重试，macOS 可退出 | **部分实现** |
| 关闭 macOS 最后一个窗口 | `window-all-closed` 在 Darwin 不退出；Dock 激活时重建窗口 | `AppDelegate` 保持进程存活；无可见窗口时，Dock/LaunchServices 重开会将原窗口带回前台 | **已验证等价** |
| 点击侧栏反馈、GitHub | 使用 `shell.openExternal` 交给系统默认浏览器 | 两个侧栏入口经受测的 `openExternalUri` 使用系统浏览器打开 | **已验证等价** |
| 点击 Agent 或其他 Markdown 中的外部链接 | 全局 Markdown 渲染器把链接交给 `handleLinkClick`，Electron 下以系统浏览器外开 | 两个 Agent 入口支持裸 `https` 与 `[标签](https://...)`；其他 Markdown 文本尚未全局接线 | **部分实现** |
| 原生标题栏、窗口最小化/缩放/拖动 | Electron 主动 `frame:false` 后自行补回这套控件 | 使用 macOS 原生窗口和系统红黄绿控制；用户完成同一窗口操作 | **不适用：不复制自绘替代层** |

## 启动失败不是“引擎内部异常”

原版在 [`src/app.ts`](../../../Toonflow-app/src/app.ts) 的 `checkPermissions()` 中，应用后端开始前就会验证用户数据目录。失败时它显示“权限不足”窗口，文本包含实际目录和处理建议。这一行为不依赖浏览器页面，属于桌面用户的明确保护。

Flutter 的启动链是 [`bootstrap_io.dart`](../../app/lib/src/bootstrap/bootstrap_io.dart) 的 `bootstrap()` → `buildDramaFlowApp()` → [`engine.dart`](../../app/lib/src/engine/engine.dart) 的 `Engine.boot()`。`buildDramaFlowApp()` 现在在任何内置资源读取、播种或 SQLite 打开前，先递归创建数据目录并写入后删除一个一次性探针；这复刻了原版写删预检的用户保护，同时避免固定探针文件误碰用户文件。无论预检、资源播种、SQLite 打开还是引擎初始化失败，外层都会换成 [`startup_failure_app.dart`](../../app/lib/src/bootstrap/startup_failure_app.dart) 的无引擎失败页；页面展示已知工作区目录、提供重试，并仅在 macOS 显示退出应用。错误日志仅保留异常类型，避免把文件内容或凭据带入日志。

真实文件系统夹具已把“父路径是普通文件”传入装配器，确认预检会先于内置资源读取失败、失败会带着目标目录进入失败页；正向夹具同时断言探针不会遗留。390dp widget 回归也验证了目录可见、重试可点。`W10-BACKEND-LIFECYCLE-001` 保持**部分实现**：数据目录保护已验证等价，但 iOS/Android 不提供程序化退出按钮，且 DramaFlow 没有独立 Node 后端可对应异步 shutdown；这些属于剩余跨端验收边界。

## macOS 的关闭与重新打开

ToonFlow 的 [`build/main.js`](../../../Toonflow-app/build/main.js) 在 `window-all-closed` 中仅在非 Darwin 平台退出，并在 `activate` 时没有窗口便新建。这表达的是标准 macOS 应用约定：关最后一个窗口不等于退出应用，点击 Dock 图标会重开窗口。

DramaFlow 的 [`AppDelegate.swift`](../../app/macos/Runner/AppDelegate.swift) 现在明确返回 `false`，并在 `applicationShouldHandleReopen` 中把不可见窗口重新置前、激活应用。这个边界没有引入窗口管理插件或改动 Flutter 引擎：它只采用 AppKit 已有的生命周期回调，保持原生窗口的红黄绿控制。

另一个需要避免误读的细节是，ToonFlow 自绘标题栏的关闭按钮调用 `app.exit(0)`，这可能绕过它自己的 `before-quit` 清理钩子。这个原版内部矛盾不降低上述“正常关闭窗口时应保留 Dock 应用”的源码证据，也不构成把 DramaFlow 改成强制杀进程的理由。

## 外部链接：安全出口已收敛，Markdown 覆盖仍有边界

ToonFlow 的 [`App.vue`](../../../Toonflow-web/src/App.vue) 重写了全局 Markdown 的链接渲染：每个链接被注入 `handleLinkClick`，Electron 下通过 `openurlwithbrowser` 交给 `shell.openExternal`。设置更新、API Key 申请、反馈、GitHub 和 Agent 富文本链接都走同一出口。

DramaFlow 现在由 [`external_link_text.dart`](../../app/lib/src/widgets/external_link_text.dart) 提供唯一的网页外链出口：只有带有效 ASCII 主机名的 `http/https` URI 可到达 `url_launcher` 的 `LaunchMode.externalApplication`，其余 scheme、空主机和伪 URL 均继续按普通文本展示。该组件识别裸链接与 `[标签](https://...)` 两种 Agent 常见回复形式，并在组件销毁时释放手势识别器。

已接线的入口是侧栏的反馈/GitHub、剧本 Agent、制作画布 Agent 和供应商预设“申请 Key”；`settings_screen.dart` 的 `Uri.file(dataDir)` 仍是特意独立的系统文件夹动作，不混进网页 scheme 白名单。`external_link_text_test.dart` 覆盖安全识别、危险文本不升级和点击注入打开器；两个 Agent widget 回归覆盖各自的回复入口；侧栏与预设表单的静态契约回归锁定统一出口。全部只使用假网关、内存 SQLite 和注入打开器，不会发出网页、模型或视频请求。

`W10-BRIDGE-EXTERNALLINK-001` 仍是**部分实现**：ToonFlow 把拦截器挂在全局 Markdown 渲染器，覆盖更新日志、重新安装说明和全部 Markdown 预览；DramaFlow 尚无通用 Markdown 富文本渲染层，且应用内更新页本身也未实现。因此不能以 Agent 已可点击链接冒充全局覆盖。

侧栏目前仍指向上游 `HBAI-Ltd/Toonflow-app` 及其 issues。它不影响“能否调用系统浏览器”的功能结论，但品牌和反馈地址应在发布前按许可证/产品决定统一替换，不能悄悄当作 DramaFlow 的正式反馈渠道。

## 证据与后续验收

| 范围 | 原版证据 | Flutter 证据 | 当前可执行验证 |
| --- | --- | --- | --- |
| 数据目录保护 | `Toonflow-app/src/app.ts:22-47` | `app/lib/src/bootstrap/bootstrap_io.dart` 的 `verifyDataDirectoryWritable`、`app/lib/src/bootstrap/startup_failure_app.dart` | `bootstrap_io_test.dart` 真实不可建目录夹具验证预检优先于资源读取、可写目录不遗留探针；`bootstrap_failure_test.dart` 验证异常接管与 390dp 重试；不启动供应商 |
| Dock 生命周期 | `Toonflow-app/build/main.js:251-258` | `app/macos/Runner/AppDelegate.swift:6-19`、`app/test/platform/macos_lifecycle_static_test.dart` | `flutter build macos --debug` 后启动隔离 App；关闭唯一窗口仍保留同一 PID；经 LaunchServices 重开后同一 PID 恢复窗口（2026-07-21） |
| 外部链接 | `Toonflow-app/build/main.js:216-226`、`Toonflow-web/src/App.vue:55-115` | `external_link_text.dart`、`shell.dart`、两个 Agent 面板、`provider_preset_form.dart` | `external_link_text_test.dart`（安全 scheme+点击）；`shell_test.dart`、`agent_chat_screen_test.dart`、`canvas_chat_panel_test.dart`、`provider_preset_form_test.dart`（入口接线）；全为离线测试 |

这份矩阵对应总清单 `W10-BACKEND-LIFECYCLE-001`、`W10-BRIDGE-EXTERNALLINK-001`、`W10-APPLIFECYCLE-DOCK-001` 与 `W10-WINDOW-CHROME-001`。它不把 Electron 的后端启动、无边框窗口或私有协议误算成 Flutter 的待办，同时不掩盖在原生端仍应补齐的用户保护。

## 数据目录预检复验（2026-07-21）

本轮先新增“父路径是普通文件且内置资源读取会失败”的离线夹具。旧实现先读取资源，红测得到资源 `StateError`；加入 `verifyDataDirectoryWritable` 后，预检先抛 `FileSystemException` 并携带目标目录，证明用户会进入既有失败页而非被后续资源错误掩盖。第二条正向夹具验证可写目录在检测后不保留探针。

在该变更后的独立 worktree 中执行 `flutter test --concurrency=1`、`flutter analyze`、`flutter build macos --debug` 和 `node tool/parity/check_no_orphans.js`，均以成功退出；后者仍报告 538 项库存已覆盖。验证只使用临时目录、内存/本地数据库和假资源包，未触发文本、图片、配音或视频供应商，也没有写入或读取供应商密钥。

## 本机构建与启动复核（2026-07-19）

本轮在 macOS 上执行 `flutter analyze`，结果为 `No issues found`；随后执行
`flutter build macos --debug`，成功生成 `build/macos/Build/Products/Debug/dramaflow.app`。
通过 macOS 可访问性树和窗口截图复核，应用实际启动至项目壳的“供应商”设置分区，
`azt` 与 `volcengine` 卡片、启用开关和“添加供应商”按钮均可见，未复现黑屏。

构建仍报告 `media_kit_libs_macos_video` 和 `media_kit_video` 尚未支持 Swift Package
Manager；当前 Flutter 仅给出未来兼容性警告，未阻塞 CocoaPods Debug 构建。该烟雾验证
只证明当前应用可编译和呈现首个真实界面，不替代本页剩余的生命周期跨端边界、
Dock 生命周期、Markdown 全局外链覆盖或视频供应商人工验收。

## 独立复验快照（2026-07-19）

本次在当前 `develop` 工作树重新执行了以下只读或本地验证：

```bash
cd app
flutter test --concurrency=1
flutter analyze
flutter build macos --debug
cd ..
node tool/parity/check_no_orphans.js
```

四项命令均成功；静态分析为 `No issues found`，Debug 包再次生成在
`app/build/macos/Build/Products/Debug/dramaflow.app`，库存对账为 `538/538`。
全量测试运行时没有设置 `QA_FULL=1`，因此 `test/qa/full_pipeline_test.dart` 按其
默认零副作用分支退出；没有调用文本、图片、音频或视频上游，更没有发起真实视频任务。

本次尝试通过 macOS 可访问性树检查刚构建的应用时，系统处于锁屏状态，自动化无法解锁。
因此这组命令本身不能作为新的可视化启动证据；它只重新证明当前代码可测试、可分析、可构建且审计库存未漂移。

## Dock 生命周期实机复验（2026-07-21）

在隔离 worktree 的 Debug 包中启动 `dramaflow.app` 后，通过 macOS 可访问性树关闭唯一窗口。关闭后该 App 的 PID 仍存在、窗口列表为空；随后由 LaunchServices 对**同一 app bundle**执行重开，PID 未变化且窗口列表恢复为 `dramaflow`。这验证的是“关闭窗口不退出 → 重新激活恢复窗口”的完整系统路径，不依赖 Flutter widget 的模拟。

对应静态契约测试是 `flutter test --concurrency=1 test/platform/macos_lifecycle_static_test.dart`；随后 `flutter build macos --debug` 成功。两项验证均未启动任何 AI 供应商，也没有提交、轮询或下载视频任务。`W10-APPLIFECYCLE-DOCK-001` 因此改判为**已验证等价**；数据目录错误边界和 Markdown 全局外链覆盖仍保留原有缺口结论。
