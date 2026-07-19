# 外观设置对照

更新时间：2026-07-20

基线：ToonFlow 1.1.8 的 `Toonflow-web/src/components/setting/components/uiConfig.vue`、
`src/utils/theme.ts` 与 `src/stores/setting.ts`。

## 结论先行

DramaFlow 已完成 `uiConfig` 的可观察能力等价：首次启动跟随系统，用户可切换浅色、深色或跟随
系统；可选择原版七个主色预设、输入自定义六位 HEX，并在七档字号间切换。三项偏好都存于本地
SQLite `o_setting`，不触碰供应商、`o_secret` 或系统钥匙串。

| 用户能力 | ToonFlow 事实 | DramaFlow 当前事实 | 判定 |
| --- | --- | --- | --- |
| 颜色模式 | `uiConfig.vue:4-10` 提供 `auto` / `light` / `dark`；`theme.ts:61-77,137-155` 立即应用并监听系统模式变化 | `EngineConfig` 默认 `system`；设置页提供浅色/深色/跟随系统，`MaterialApp.themeMode` 消费持久化值 | 已验证等价 |
| 主题主色 | `uiConfig.vue:11-23` 有 7 个圆形预设和 HEX 取色器；`theme.ts:47-59,80-101` 生成并写入品牌色阶 | 相同 7 个预设、可校验 HEX 输入框和色块预览；同一主色派生亮暗 `ColorScheme` 与 `DFColors` | 已验证等价 |
| 全局字号 | `uiConfig.vue:24-34` 有 12/13/14/16/18/20/22 七档；`theme.ts:90-99` 改浏览器根字号 | 相同 7 个离散选项，经应用根 `MediaQuery` 只缩放一次；工作台紧凑时间线在增大时扩高防溢出 | 已验证等价 |

## 实现边界

原版默认 `themeSetting.mode=auto`、`primaryColor=#0052D9`、`fontSize=16`。DramaFlow 对应默认值为
`system`、`#0052D9`、`16`。`ThemeModeNotifier` 在配置异步加载前和加载失败时也保持 `system`，避免
首次绘制闪成浅色。用户已保存的 `light` 或 `dark` 值仍会完整恢复。

主色预设依次为黑、蓝、绿、橙、红、紫和深灰：`#000000`、`#0052D9`、`#2BA471`、`#ED7B2F`、
`#E34D59`、`#7B61FF`、`#111111`。自定义值只接受完整六位 HEX，统一保存为大写 `#RRGGBB`；无效
输入保留当前颜色并显示本地化错误。Flutter 不复制 CSS 变量或浏览器 View Transition，而是以
`buildTheme` 的一个主色输入派生按钮、选择态、焦点、滑块、复选框、进度条和亮暗 `DFColors`。

字号选择使用一个应用根 `MediaQuery.textScaler`，不会再额外按比例改写 `TextTheme`。这匹配原版
“全局根字号”的用户效果，同时保留图标、最小触控目标和时间线刻度的固定语义。最大 22px 测试
暴露了工作台视频、音频和素材时间线卡片的固定高度溢出，已改为只在缩放大于 1 时增高卡片，默认
密度不变。

## 代码与自动化证据

- `app/lib/src/engine/config.dart`：允许的预设、字号、标准化与安全回退，默认 `themeMode=system`。
- `app/lib/src/engine/engine.dart`：主色和字号的验证型读写 API。
- `app/lib/src/state/providers.dart` 与 `app/lib/src/app.dart`：持久化 notifier、根主题和唯一的文字
  缩放边界。
- `app/lib/src/screens/settings_screen.dart`：颜色模式、七个带 tooltip 的语义色块、自定义 HEX 输入和
  七个字号选项。
- `app/lib/src/screens/production/workbench_screen.dart`：22px 下时间线卡片的防溢出高度约束。

以下回归已在 2026-07-20 重跑，全部只使用内存 SQLite、临时媒体目录、假网关和 widget 夹具：

```sh
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter analyze
flutter test --concurrency=1
flutter build macos --debug
```

外观专属断言包括：默认跟随系统、模式/颜色/字号跨重建持久化、非法 HEX/字号回退、亮暗主题主色
派生、390 x 760 设置页的预设与自定义色路径、390dp 新建项目，以及 1440 x 960 工作台中镜头选择。
后两条均以绿色 `#2BA471` 和最大字号 `22` 运行并断言无 Flutter 布局异常。

验证没有发起任何文本、图片、音频或视频供应商请求，也没有提交、轮询或下载 Seedance 任务。macOS
debug 构建成功；移动端证据是 390dp widget 回归，不把它表述为 iOS/Android 真机供应商验收。
