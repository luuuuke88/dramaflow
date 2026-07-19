# 设置模块对照矩阵

更新时间：2026-07-19

基线：ToonFlow 1.1.8 的 `Toonflow-web/src/components/setting/index.vue` 与其 16 个
设置组件。Flutter 不照抄 Electron 对话框布局，但必须保留每一项跨平台的用户价值。

## 总览

原版以一个桌面设置弹窗承载 16 个菜单项；DramaFlow 以完整页面承载 7 个自适应分区：
宽度至少 900dp 时为左侧导航，小于 900dp 时为横向分区标签和可滚动内容。这个结构差异
本身是合理的，但不能掩盖每个分区内的功能差异。

| ToonFlow 设置组件 | DramaFlow 分区或对应 | 当前结论 | 说明 |
| --- | --- | --- | --- |
| `uiConfig.vue` | 外观 | 部分实现 | 深浅色/跟随系统可用；主题色和七档全局字号缺失 |
| `languageConfig.vue` | 外观 | 部分实现 | 有中/英/日；缺繁中、泰、越、俄四种语言 |
| `vendorConfig.vue` | 供应商 | 部分实现 | CRUD、模型管理、能力编辑已存在；私有协议/插件代码和原版 13 条供应商线未覆盖 |
| `modelMap.vue` | 供应商内模型模板库 | 已验证等价 | 模板建改删、绑定/解绑、桌面和 390dp 测试都有证据 |
| `agentConfog.vue` | 模型绑定 | 部分实现 | 流水线阶段绑定已实现；原版每 Agent 高级调参、普通/高级分组和批量设置未对齐 |
| `promptManage.vue` | 提示词 | 已验证等价 | 默认值、覆写、恢复默认和编辑闭环已覆盖 |
| `skillManagement.vue` | Agent 对话的技能页 | 部分实现 | 有技能列表/启停；没有文件树、预览、应用内编辑和保存 |
| `memoryConfig.vue` | 无完整对应分区 | 部分实现 | 仅有项目级对话清空；向量模型及摘要/RAG 参数没有实现 |
| `dbConfig.vue` | 存储与引擎 | 部分实现 | 表信息和业务数据清理可用；缺整库备份/还原、恢复出厂和按表清空 |
| `fileManagement.vue` | 存储与引擎 | 部分实现 | 能打开数据根目录；缺原版可选子目录快捷入口 |
| `otherConfig.vue` | 其他 | 部分实现 | 章节正则、单集字数、素材并发已对齐；超时、画布滚轮模式和交互开关缺失 |
| `about.vue` | 关于 | 部分实现 | 应用/引擎版本已展示；检查、下载和安装更新尚未实现 |
| `requestConfig.vue` | 不适用 | 不适用 | 原版是浏览器 SPA 寻址 Electron 本地 HTTP 后端；Flutter 引擎在进程内，无可配置的本地后端地址 |
| `loginConfig.vue` | 不适用 | 不适用 | 原版只修改 SPA 与本地 Node 后端的 JWT 登录凭据；DramaFlow 是单用户原生应用 |
| `logoutConfig.vue` | 不适用 | 不适用 | 原版只清浏览器 localStorage 会话并回登录页；Flutter 无该会话模型 |
| `devConfig.vue` | 不适用 | 不适用 | Chromium DevTools、Vercel AI SDK DevTools、浏览器 localStorage 管理均为开发者平台机制 |

## 用户可达性证据

Flutter 的 `SettingsScreen` 有真实的窄屏结构，不是缩小的桌面导航：`<900dp` 使用
`_TopSectionTabs`，内容始终置于可滚动 `ListView`。已有 390 x 760 widget 回归确认下列
路径可达：外观/语言、供应商预设与自定义表单、提示词编辑、存储清理，以及图片和视频
模型连通测试弹层。

这只是基础可达性证据，**不等于所有设置功能已经在移动端完成**。特别是供应商模型
编辑器、模板库、复杂表单与未来的技能文件管理，仍必须各自补 390dp 实际交互回归；仅能
渲染或仅桌面测试不能升为“已验证等价”。

## 不适用的边界

本表的四项“不适用”均已在 `inventory-na.md` 写明两项依据：

1. 它们依赖浏览器 SPA、Electron 主进程或 Node/Vercel AI SDK 的特定运行时；
2. DramaFlow 的单体原生架构没有相同的用户旅程，而不是简单地“还没做”。

这不包括供应商 `baseUrl`、Keychain 凭据或云账号：这些具有原生用户价值，仍属于
供应商和配置工作，不能借 `requestConfig` / `loginConfig` 的结论跳过。

## 近期修复顺序

1. `uiConfig` 的主题色和字号：范围小、跨端真实可见、可做离线测试。
2. 设置中的画布滚轮模式、请求超时和交互开关：应与 W1 画布手势一起设计，避免单独加
   无效开关。
3. 技能文件管理与按需激活：属于 W2，设计和证据见
   [`skill-runtime-matrix.md`](skill-runtime-matrix.md)。
4. 数据库管理、记忆、Agent 高级部署和应用更新：各自独立设计，不能在“设置页重构”里
   混做。

## 关联记录

- 逐条权威结论：[`master-checklist.md`](master-checklist.md) 中 `W6D-*`、`W7A-*`、
  `W9A-*`。
- 合理不适用证明：[`inventory-na.md`](inventory-na.md)。
- 供应商协议缺口：[`vendor-protocol-matrix.md`](vendor-protocol-matrix.md)。
- 技能文件与 Agent 运行时差异：[`skill-runtime-matrix.md`](skill-runtime-matrix.md)。
