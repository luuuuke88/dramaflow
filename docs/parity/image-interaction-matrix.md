# 图片交互对照：逐图操作与提示词参考素材

这份对照把两个容易被混为一谈的原版组件拆开：`imageTools.vue` 是对已经存在的单张图片做复制、预览和下载；`promptEditor.vue` 是在文字提示词里插入可视化的 `@图片1`、`@视频1` 一类引用。Flutter 已经有图片画廊、分镜批量导出和结构化参考素材，但这些不自动等于复刻了两种具体交互。

本轮只验证本地文件、SQLite、widget 和 fake gateway。视频请求相关测试仅检查草稿、能力限制与引用序列化，不提交、轮询或下载真实视频。

## 逐图图片操作

| 动作 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 放大查看单图 | 图片悬浮工具条点预览，交给 `t-image-viewer` | 分镜“预览全部”打开整屏 PageView，支持左右切换、双指/滚轮缩放和缺图占位 | **部分等价**：分镜首帧场景更完整，但不是每个图片位置都有同一工具条 |
| 复制图片到剪贴板 | 将跨域图片绘制到 canvas，再写入 `ClipboardItem` | 没有图片二进制复制入口或适配层 | **缺失** |
| 单张另存为 | fetch blob 后触发浏览器下载；CORS 失败时新窗口打开 | 分镜页有“导出全部”到用户选择目录，按 `S01.*` 命名；没有对任意单张图片的另存为动作 | **部分实现** |
| 在资产、分镜、图片编辑器、工作台参考图上复用 | 同一个 `ImageTools` 组件被资产节点、分镜、海报、图片编辑器和视频参考选择器复用 | 预览/导出分散在分镜画廊、图片编辑器和各页面的本地文件路径中 | **部分实现** |

原版的 [`imageTools.vue`](../../../Toonflow-web/src/components/imageTools.vue) 是纯浏览器补偿层：图片来自 HTTP URL，所以复制要经 canvas，下载要经 fetch/blob。它实际挂载在资产节点、分镜节点、海报、图片编辑器生成节点和工作台参考图等多个位置。

DramaFlow 的 [`storyboard_gallery.dart`](../../app/lib/src/screens/production/storyboard_gallery.dart) 已提供合适的原生图片查看体验；[`storyboard_canvas_node.dart`](../../app/lib/src/screens/production/storyboard_canvas_node.dart) 也有“导出全部”。`storyboard_canvas_node_test.dart` 验证整屏画廊包含所有镜头和无图片时不弹出系统导出面板。它们不能证明任意图片均可复制或另存为，因此总表的 `W6E-CMP-IMGTOOLS-001` 保持**部分实现**。

未来如需补齐，应做一个小型、平台安全的图片动作适配层：对本地文件提供“复制图片”和“导出此图”，桌面显示图标工具条、移动端放入长按/更多菜单。它应只接受应用媒体目录内的文件，不使用网页式 CORS 回退，也不为每个页面各写一套文件复制逻辑。

## 提示词里的参考素材

| 能力 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 文字内插入引用 | 输入 `@` 弹出图片/视频/音频/文本候选，键盘上下、Enter/Tab/Escape 可操作 | 纯文本提示词与参考素材选择分开；没有 `@` 候选浮层或内联标签 | **缺失该交互** |
| 提示词序列化 | 标签序列化为 `@图片1`、`@视频1`、`@音频1`、`@文本1`，序号按媒体类型计数 | 图片流保存独立节点、边与参考路径；视频草稿保存 `VideoReferenceSource(role, mediaType, sourceType, sourceId)` | **结构化能力更可靠，但非同一文本 UX** |
| 参考素材实际传递 | 工作台 `imageList` 同时供编辑器预览和视频请求使用 | 图片流由连线推导全部参考图；视频请求按模型能力限制选择图片/视频/音频并保存角色 | **已有且有测试** |

原版 [`promptEditor.vue`](../../../Toonflow-web/src/components/promptEditor.vue) 被当前工作台视频生成页和图片编辑器生成节点实际使用。它是 `contenteditable` 编辑器，而不是简单的文本框：引用标签既可见又会序列化回字符串，用户可以在同一段 prompt 中调整文字和媒体位置。

Flutter 选择了结构化表达：[`image_flow_editor.dart`](../../app/lib/src/screens/production/image_flow_editor.dart) 的生成节点从入边推导参考图；[`video_request_dialog.dart`](../../app/lib/src/screens/production/video_request_dialog.dart) 按模型能力让用户选择参考素材，并保存带角色的引用对象。`image_flow_test.dart` 已验证全部连线参考图会传给 fake 图像网关；`workbench_screen_test.dart` 覆盖多参考与首尾帧引用角色。这减少了“文字写了 @图2 但实际引用顺序变了”的漂移风险，但用户不能享受原版的内联 `@` 编辑体验。

因此 `W6E-CMP-PROMPTEDITOR-001` 保持**部分实现**。若后续实现内联编辑器，保存时必须以结构化引用为权威，不应反过来让脆弱的 `@图片N` 文本成为请求数据源：可以在编辑器里显示 token，序列化时保持用户提示词可读，同时将 token 的稳定 ID 单独持久化。这样才既接近原版交互，又不退化当前的请求安全性。

## 验收边界

| 验收 | 当前证据 | 尚缺证据 |
| --- | --- | --- |
| 整屏查看和批量导出空态 | `app/test/widgets/storyboard_canvas_node_test.dart` | 已有图片时系统目录选择、逐文件复制与移动端分享出口 |
| 图片流多参考 | `app/test/engine/image_flow_test.dart` | 不测试真实图像供应商 |
| 视频草稿参考角色/数量 | `app/test/widgets/workbench_screen_test.dart` | 不测试真实视频生成、轮询或下载 |
| `@` 输入、键盘选择、token 删除/序列化 | 无 | 桌面键盘与 390dp 触控的专门 widget 回归 |

本专题对应总清单 `W6E-CMP-IMGTOOLS-001` 与 `W6E-CMP-PROMPTEDITOR-001`。它把“已有结构化参考数据”与“缺少原版内联编辑器”同时记录，避免为了一个漂亮的 `@` 控件破坏已经可验证的引用模型。
