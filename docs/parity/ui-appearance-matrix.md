# 外观设置对照

更新时间：2026-07-20
基线：ToonFlow 1.1.8 的 `Toonflow-web/src/components/setting/components/uiConfig.vue`、
`src/utils/theme.ts` 与 `src/stores/setting.ts`。

## 结论先行

DramaFlow 已对齐颜色模式的用户行为：浅色、深色和跟随系统均可从设置页切换，设置会写入
本地 SQLite 并在应用重建时恢复。原版的主题主色和七档全局字号尚未实现，因而本模块保持
**部分实现**。这不是文案或控件缺失，而是两项都必须影响整套 Flutter `ThemeData` 与移动、
桌面布局，不能用只改变设置页自身颜色或字号的假实现冒充完成。

| 用户能力 | ToonFlow 事实 | DramaFlow 当前事实 | 判定 |
| --- | --- | --- | --- |
| 颜色模式 | `uiConfig.vue:4-10` 提供 `auto` / `light` / `dark`；`theme.ts:61-77,137-155` 立即应用并监听系统模式变化 | `settings_screen.dart:_appearanceCard` 提供浅色/深色/跟随系统；`themeModeProvider` 保存 `themeMode`；`MaterialApp.themeMode` 消费它 | 已验证等价 |
| 主题主色 | `uiConfig.vue:11-23` 有 7 个圆形预设和 HEX 取色器；`theme.ts:47-59,80-101` 生成并写入品牌色阶 | `theme.dart` 的 `DFColors.light()` / `.dark()` 是固定调色板，设置页无颜色控件或持久化键 | 缺失 |
| 全局字号 | `uiConfig.vue:24-34` 有 12/13/14/16/18/20/22 七档；`theme.ts:90-99` 改浏览器根字号 | Flutter 文本同时来自 `ThemeData.textTheme`、设计 token 和大量语义明确的局部 `TextStyle(fontSize: ...)`；无全局字号设置 | 缺失 |

## 原版行为边界

### 颜色模式

原版持久化 `themeSetting.mode`、`primaryColor` 和 `fontSize`，默认分别为 `auto`、`#0052D9`
和 `16`（`setting.ts:18-29`）。`auto` 只改变实际明暗模式，仍保留用户选择的主色；系统模式
变化时会重新应用主色。浏览器的 View Transition 是实现细节，不是 Flutter 必须模仿的用户
功能。

### 主题主色

原版预设依次为黑、蓝、绿、橙、红、紫和深灰：
`#000000`、`#0052D9`、`#2BA471`、`#ED7B2F`、`#E34D59`、`#7B61FF`、`#111111`。
用户也可输入任意 6 位 HEX；无效值回退为蓝色。`theme.ts` 用 HSL 生成十级色阶，并在深色模式
反转色阶。Flutter 不需要照抄 CSS 变量或 HSL 算法，但最终的主色、悬停/按下、弱强调、选中态、
焦点和文本链接必须由一个一致的主题输入派生，不能散落修改控件颜色。

### 字号

Web 根字号影响使用 `rem` 的布局；它不会逐个重写原版组件的固定像素样式。Flutter 没有等价的
根 `font-size`，而且 DramaFlow 在数据表、时间线、紧凑操作栏、移动全屏表单中存在有意固定的
信息密度字号。因此 1:1 的目标是提供相同七档用户选择并让**主题文字层级**按比例变化，同时
保留安全关键的最小点击目标、图标尺寸、时间线刻度和防溢出约束。不能把 `MediaQuery.textScaler`
粗暴写死，也不能全局把每个 `TextStyle` 乘倍数后声称性能或可用性已验证。

## DramaFlow 架构落点

当前 `app/lib/src/theme/theme.dart` 是唯一 `ThemeData` 组装点，`DFColors` 是通过
`ThemeExtension` 提供给页面的调色板。`app/lib/src/app.dart` 在 `MaterialApp.router` 同时注入
亮/暗主题；`app/lib/src/state/providers.dart` 的 `ThemeModeNotifier` 负责异步加载和失败回退。
这是扩展主题色、字号的正确边界：增加有类型的外观偏好和 ThemeExtension/ThemeData 派生，页面
只读取 `context.df` 或 `Theme.of(context)`，不在各业务页添加临时颜色/字号状态。

落实时需要同时验证：

1. 本地设置值在应用重建后恢复，非法 HEX 或字号不会破坏现有主题。
2. 主题色改变后，按钮、选择态、输入焦点、导航选中、滑块、复选框和进度条共同变化；深浅主题
   都保持可读对比度。
3. 390dp 移动设置页可以选择预设、填写自定义色和选择字号，不依赖 hover；桌面布局不发生溢出。
4. 文本比例至少覆盖设置、项目列表、资产表格、制作画布、工作台和全屏表单；每个覆盖项保持
   最小触控面积和可滚动性。
5. 全部测试仅用内存数据库和 widget 夹具，不发起文本、图像、TTS 或视频请求。

## 现有证据与后续门槛

`app/test/engine/config_test.dart` 已验证 `themeMode` 的默认值和持久化；
`app/test/engine/engine_facade_test.dart` 验证 API 拒绝非法模式；
`app/test/widgets/settings_screen_test.dart` 验证移动端切换深色模式会写入配置。
这些证据只覆盖颜色模式，**不能**作为主题色或字号已实现的证据。

实现完成前，主清单 `W6D-UI-001` 与 `W6E-LIB-THEME-001` 继续保持部分实现；实现后必须以
桌面与 390dp 的真实控件路径、跨重建持久化、亮暗主题对比和代表性界面无溢出回归更新本页及
`master-checklist.md`。
