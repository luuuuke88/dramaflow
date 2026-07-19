# 设置模块对照矩阵

更新时间：2026-07-20

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
| `otherConfig.vue` | 其他 | 部分实现 | 章节正则、单集字数、素材并发和会话级画布滚轮模式已对齐；超时和交互开关缺失 |
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

## 当前验证基线（2026-07-19）

本轮没有执行任何真实图片或视频请求。以下回归只使用内存 SQLite、假供应商网关和 widget
测试夹具，因此可在不消耗供应商额度的条件下重复执行：

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/engine/db_admin_test.dart \
  test/engine/engine_facade_test.dart \
  test/widgets/settings_screen_test.dart
```

结果：53 项通过。其证据边界需要如实保留：

- `dbInfo()` 可列出业务表及行数；`clearAllData()` 会在事务内清空项目、章节、剧本、素材、
  分镜、任务和记忆，并删除媒体文件，但刻意保留供应商、模型、绑定、提示词、画风、外观和
  语言配置。
- 配置导出/导入只覆盖供应商元数据、模型、绑定和提示词；API Key 按当前产品决策直接
  存在本地 SQLite `o_secret` 表，但导出白名单不读取该表，JSON 中始终没有密钥。`clearAllData()`
  也会保留 `o_secret`，避免清空业务数据后再次要求用户填写。它仍不是 ToonFlow 的完整
  数据库快照/恢复能力。
- 390dp 设置页覆盖了数据库信息、内容清空确认、导入导出错误可见性、模型管理与视频能力
  编辑。测试并没有证明“按表清空”“整库恢复出厂”“完整数据库备份/恢复”或原版 Agent
  普通/高级模式已经存在。
- 当前 `assistantDeployments()` 被测试锁定为仅 `scriptAgent` 与 `productionAgent` 两个
  家族基座。它们可逐项更新温度和最大输出，但不等价于原版的多 Agent 普通/高级分组与批量
  设置，仍按本表和总清单标为部分实现。

Agent 配置的独立回归也可离线复跑：

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/engine/assistant_skills_deploy_test.dart \
  test/widgets/agent_chat_screen_test.dart
```

结果：17 项通过。它锁定了两个家族基座的播种、文本模型类型校验、温度和输出上限保存，以及
桌面/移动壳中的按需展开入口；也直接断言列表中没有已被裁掉的多层流水线部署。该断言是当前
  行为的证据，不是对原版高级模式的替代证明。

### 画布滚轮模式补充证据（2026-07-20）

`otherConfig.vue:20-25` 的 `canvasWheelEvent` 已由
`settings_screen.dart:950-1017` 的两段式控件承接。它更新的是
`canvasWheelModeProvider` 的内存值，默认 `zoom`，不写 `EngineConfig`、SQLite、导出或凭据；
和原版未把 `canvasWheelEvent` 放入持久化 pick 列表的行为一致。

- 桌面设置回归断言默认值、即时切换和 `engine.config.getAll()` 不变。
- 390dp 回归断言两个选项都在视口内并可来回切换。
- 生产页回归断言该值只传给桌面主 `DFCanvas`；画布回归断言 `zoom` 中鼠标/触控板焦点缩放、
  `scroll` 中二者平移，且参数区在 `scroll` 时仍阻断滚轮。

这些均使用内存数据库与 widget 夹具，不调用任何模型或媒体供应商。剩余缺口仍是请求超时和
`interacting` 降级开关，故本分区不能标记完成。

## 不适用的边界

本表的四项“不适用”均已在 `inventory-na.md` 写明两项依据：

1. 它们依赖浏览器 SPA、Electron 主进程或 Node/Vercel AI SDK 的特定运行时；
2. DramaFlow 的单体原生架构没有相同的用户旅程，而不是简单地“还没做”。

这不包括供应商 `baseUrl`、本地 SQLite 凭据或云账号：这些具有原生用户价值，仍属于
供应商和配置工作，不能借 `requestConfig` / `loginConfig` 的结论跳过。

## 近期修复顺序

1. `uiConfig` 的主题色和字号：范围小、跨端真实可见、可做离线测试。
2. 请求超时和交互开关：滚轮模式已于 2026-07-20 关闭；其余两项应与 W1 性能实测一起设计，
   避免添加无效开关。
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
