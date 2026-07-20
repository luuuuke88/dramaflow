# 图片交互对照：逐图操作与提示词参考素材

这份对照把两个容易被混为一谈的原版组件拆开：`imageTools.vue` 是对已经存在的单张图片做复制、预览和下载；`promptEditor.vue` 是在文字提示词里插入可视化的 `@图片1`、`@视频1` 一类引用。Flutter 已经有图片画廊、分镜批量导出和结构化参考素材，但这些不自动等于复刻了两种具体交互。

本轮只验证本地文件、SQLite、widget 和 fake gateway。视频请求相关测试仅检查草稿、能力限制与引用序列化，不提交、轮询或下载真实视频。

## 逐图图片操作

| 动作 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 放大查看单图 | 图片悬浮工具条点预览，交给 `t-image-viewer` | 分镜“预览全部”打开整屏 PageView，支持左右切换、双指/滚轮缩放和缺图占位 | **部分等价**：分镜首帧场景更完整，但不是每个图片位置都有同一工具条 |
| 复制图片到剪贴板 | 将跨域图片绘制到 canvas，再写入 `ClipboardItem` | [`AssetImagePreviewPage`](../../app/lib/src/widgets/asset_image_preview.dart) 将本地 PNG 原样交给平台剪贴板，JPEG 等其他可解码图片转成 PNG 后复制；成功/失败均有本地化反馈 | **部分实现**：共享预览入口已可复制，尚未挂到每一张内嵌缩略图的悬浮层 |
| 单张另存为 | fetch blob 后触发浏览器下载；CORS 失败时新窗口打开 | 全屏预览的“另存此图”复用 `file_selector` 系统保存面板，以原文件名和原始字节写出；分镜页仍保留“导出全部” | **部分实现**：单图另存已可达，但不等于所有原版图片位置都已接线 |
| 在资产、分镜、图片编辑器、工作台参考图上复用 | 同一个 `ImageTools` 组件被资产节点、分镜、海报、图片编辑器和视频参考选择器复用 | 本地图片走同一 `showAssetImagePreview` 时都会获得复制/另存/缩放；当前调用者包括通用本地媒体预览、画风库、塑角造景和资产生成候选 | **部分实现**：基础动作已共享，资产节点、分镜格、图片流节点和工作台参考缩略图仍缺原版同位工具条 |

原版的 [`imageTools.vue`](../../../Toonflow-web/src/components/imageTools.vue) 是纯浏览器补偿层：图片来自 HTTP URL，所以复制要经 canvas，下载要经 fetch/blob。它实际挂载在资产节点、分镜节点、海报、图片编辑器生成节点和工作台参考图等多个位置。

DramaFlow 的 [`asset_image_preview.dart`](../../app/lib/src/widgets/asset_image_preview.dart) 现为共享的原生动作层：全屏缩放预览右上角始终提供“复制图片 / 另存此图 / 关闭”三个固定尺寸图标；桌面与移动端共用同一安全区布局。复制遵循原生插件的 PNG 输入要求：PNG 直接复制，JPEG 等可解码源图在内存中转成 PNG；另存交给系统保存面板并保留原文件名、原始字节与格式，不搬用浏览器的 CORS 失败回退。`asset_image_preview_test.dart` 用 JPEG fixture 验证剪贴板转 PNG、用预览页动作验证读取源路径并把原路径交给另存适配器；没有调用图片或视频供应商。

[`storyboard_gallery.dart`](../../app/lib/src/screens/production/storyboard_gallery.dart) 仍提供分镜序列的专用查看体验；[`storyboard_canvas_node.dart`](../../app/lib/src/screens/production/storyboard_canvas_node.dart) 仍有“导出全部”。这次没有假装它们已经自动拥有逐格工具条：原版 `ImageTools` 在资产节点、分镜节点、图片编辑器和工作台参考选择器的就地悬浮入口，Flutter 还需要逐处接到共享预览或同一动作层。因此总表的 `W6E-CMP-IMGTOOLS-001` 保持**部分实现**。

后续补齐只需让尚未接线的图片入口调用既有动作层：桌面可以在原地显示紧凑图标，移动端应以点按预览或“更多”入口抵达同一页面。任何新入口都必须只接受应用媒体目录内的普通文件，不使用网页式 CORS 回退，也不为每个页面复制一套文件读取或保存逻辑。

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
| 共享全屏预览的复制与另存 | `app/test/widgets/asset_image_preview_test.dart`：JPEG fixture 转 PNG 后交给复制适配器，预览页把源路径交给另存适配器 | macOS/iOS/Android 真实系统剪贴板和保存面板属于最终人工验收；不涉及供应商 |
| 整屏查看和批量导出空态 | `app/test/widgets/storyboard_canvas_node_test.dart` | 已有图片时系统目录选择、逐文件复制与移动端分享出口 |
| 图片流多参考 | `app/test/engine/image_flow_test.dart` | 不测试真实图像供应商 |
| 视频草稿参考角色/数量 | `app/test/widgets/workbench_screen_test.dart` | 不测试真实视频生成、轮询或下载 |
| `@` 输入、键盘选择、token 删除/序列化 | 无 | 桌面键盘与 390dp 触控的专门 widget 回归 |

本专题对应总清单 `W6E-CMP-IMGTOOLS-001` 与 `W6E-CMP-PROMPTEDITOR-001`。它把“已有结构化参考数据”与“缺少原版内联编辑器”同时记录，避免为了一个漂亮的 `@` 控件破坏已经可验证的引用模型。
