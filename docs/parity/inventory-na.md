# 库存 N/A 判定表

不进入总对照清单的库存项。每条必须有理由（spec §5.1："不适用"仅限 Electron/浏览器平台特有且 macOS 原生形态无对应用户价值）。

| 库存 ID | 理由 |
| --- | --- |
| web.page:pages/error/404.vue | 浏览器 hash 路由 catchAll 的兜底 404 页（pages/error/404.vue：显示"404 / 页面不存在 / 返回首页"按钮）。macOS 原生无地址栏，用户经按钮/标签导航无法抵达未知路由；程序性误导航由 GoRouter 默认错误页作为开发兜底，无对应原生用户价值。属浏览器 SPA 路由特有。 |
| web.route:/:catchAll(.*) | 与 404 页配对的浏览器 catchAll 路由入口（Toonflow-web/src/router/index.ts:5-12）。macOS 原生无用户可达的未知 URL 触发路径，同属浏览器 SPA 路由特有，无对应原生用户价值。 |
| web.page:pages/login/index.vue | ToonFlow 登录是浏览器 SPA 与本地 Electron HTTP 后端之间的 JWT 鉴权门：Toonflow-app/src/app.ts:152-170 对除 /api/login/login 外的全部 /api 路由校验 token，凭据存 o_user、签发 180 天 Bearer JWT。DramaFlow 为单用户原生应用、内嵌引擎无 HTTP 服务与会话，启动直接进入项目列表、无鉴权门（o_user 表在 app/lib/src/engine/db.dart:343 保留但 UI 不用于鉴权），登录鉴权在 macOS 原生形态下无用户价值。登录页仅有的非鉴权能力（语言切换、供应商请求地址配置）由设置页承接（app/lib/src/screens/settings_screen.dart:364-384 语言、:391+ 供应商配置）。 |
| web.page:views/test/index.vue | 开发者诊断页（Toonflow-web/src/views/test/index.vue：单个"测试按钮"调用 GET /test/test 并原样打印后端响应）。未被工作台任何菜单/导航引用，仅可手动改 hash 抵达，无面向最终用户的可观察能力；复刻它对用户零价值。 |
