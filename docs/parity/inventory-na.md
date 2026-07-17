# 库存 N/A 判定表

不进入总对照清单的库存项。每条必须有理由（spec §5.1："不适用"仅限 Electron/浏览器平台特有且 macOS 原生形态无对应用户价值）。

| 库存 ID | 理由 |
| --- | --- |
| web.page:pages/error/404.vue | 浏览器 hash 路由 catchAll 的兜底 404 页（pages/error/404.vue：显示"404 / 页面不存在 / 返回首页"按钮）。macOS 原生无地址栏，用户经按钮/标签导航无法抵达未知路由；程序性误导航由 GoRouter 默认错误页作为开发兜底，无对应原生用户价值。属浏览器 SPA 路由特有。 |
| web.route:/:catchAll(.*) | 与 404 页配对的浏览器 catchAll 路由入口（Toonflow-web/src/router/index.ts:5-12）。macOS 原生无用户可达的未知 URL 触发路径，同属浏览器 SPA 路由特有，无对应原生用户价值。 |
| web.page:pages/login/index.vue | ToonFlow 登录是浏览器 SPA 与本地 Electron HTTP 后端之间的 JWT 鉴权门：Toonflow-app/src/app.ts:152-170 对除 /api/login/login 外的全部 /api 路由校验 token，凭据存 o_user、签发 180 天 Bearer JWT。DramaFlow 为单用户原生应用、内嵌引擎无 HTTP 服务与会话，启动直接进入项目列表、无鉴权门（o_user 表在 app/lib/src/engine/db.dart:343 保留但 UI 不用于鉴权），登录鉴权在 macOS 原生形态下无用户价值。登录页仅有的非鉴权能力（语言切换、供应商请求地址配置）由设置页承接（app/lib/src/screens/settings_screen.dart:364-384 语言、:391+ 供应商配置）。 |
| web.page:views/test/index.vue | 开发者诊断页（Toonflow-web/src/views/test/index.vue：单个"测试按钮"调用 GET /test/test 并原样打印后端响应）。未被工作台任何菜单/导航引用，仅可手动改 hash 抵达，无面向最终用户的可观察能力；复刻它对用户零价值。**判定说明（2026-07-18 审查标注）**：本条仅满足 spec §5.1 两个必要条件中的"无对应用户价值"，不满足"平台特有"——它不是 Electron/浏览器专属机制（一个开发诊断页在任何平台都可能存在），只是恰好零用户价值。这是有意的"取精神舍字面"的例外（判绿/判缺失都不准确：DramaFlow 没有也不需要对应的开发诊断页），**需在 W0 范围确认时经用户明确追认**，不视为自动合规。 |
| web.page:views/production/components/workbench/generate copy.vue | 死代码：live 版 generate/ 目录的并行重复副本。经全仓 grep（src 内全部 .vue/.ts/.js）验证：generate copy.vue 及其 3 个嵌套文件在自身目录外零引用（无 import/from/动态 import/组件注册），从不被任何路由或组件挂载，故无任何用户可观察行为可复刻。与已排除的 scriptAgent/index copy.vue 同型（编辑遗留副本）。非 spec §5.1 的平台特有类，属"无用户价值的死代码"排除，逻辑对应的 live 能力由 generate/ 目录条目（W6B-GEN-*）承接。 |
| web.page:views/production/components/workbench/generate copy/index.vue | 死代码：generate copy.vue 死副本的嵌套 index，同上 grep 验证零外部引用、从不挂载、无用户可观察行为；对应 live 能力见 W6B-GEN-* 条目。 |
| web.page:views/production/components/workbench/generate copy/components/trackList.vue | 死代码：generate copy 死副本的嵌套组件，同上 grep 验证零外部引用、从不挂载、无用户可观察行为；对应 live 轨道能力见 W6B-GEN-TRACK-001。 |
| web.page:views/production/components/workbench/generate copy/components/videogenerate.vue | 死代码：generate copy 死副本的嵌套组件，同上 grep 验证零外部引用、从不挂载、无用户可观察行为；对应 live 生成能力见 W6B-GEN-VIDEO-001/W6B-GEN-CANDIDATE-001。 |
| web.page:views/production/components/editImage/results.vue | 死代码：节点式图片编辑器的"生成结果"展示卡组件（results.vue：标题栏 + 全屏/下载图标[两个 icon 均无 @click，纯装饰] + 结果图或"等待生成"占位 + 标签）。经全仓 grep 验证：无任何 import（`editImage/results`、`./results` 零命中）、无全局组件注册，且 editImage 画布仅注册 node-upload/node-generated/edge-removeLine 三个模板（index.vue:23-32）而无 node-results/node-generateResults，故该组件从不被挂载、无用户可观察行为可复刻。与 6b 排除的 generate copy 死副本同型。非 spec §5.1 平台特有类，属"无用户价值的死代码"排除；其暗示的"生成结果展示"能力由 live 生成节点图片区（W6C-EDIT-GENERATED-001）承接。 |
