# 参考素材选择器对照：资产、分镜与视频请求

状态：2026-07-19 源码逐调用点审计 + 定向 Flutter 回归。

这不是把所有“选择图片”的按钮混在一起计算。ToonFlow 有两套可复用的
选择器，并在图片流和视频工作台按不同方式使用它们：

- `storyboardImageCheck.vue` 是可搜索、分页的分镜图表格；
- `assetsCheck.ts` 是承载完整资产页的通用选择器，可限制资产类型、片段媒体类型和单/多选；
- 工作台 `imageSelect.vue` 通过这两套入口填充单图、首尾帧和多参考槽位。

DramaFlow 选择了更明确的本地引用对象 `VideoReferenceSource`，这能避免把
展示 URL 当成业务身份保存。但“引用结构更稳”不能替代原版的资产发现范围、
搜索分页和多选交互。本文件逐项分开记录。

所有验证只使用 SQLite、本地临时媒体与 fake gateway。视频测试只检查参考
素材、能力限制和草稿序列化，不提交、轮询或下载真实视频任务。

## 结论概览

| 场景 | ToonFlow 可观察行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 剧本关联角色/道具/场景 | 弹出完整资产选择器，多选返回资产 | 多选 `role/tool/scene` 顶层资产并保存关联 | **已在剧本场景等价** |
| 图片流上传节点选图 | 从资产或分镜图单选，可搜索/分页浏览分镜 | 本地文件、当前项目角色/场景/道具图或本剧集分镜首帧单选 | **部分实现** |
| 视频生成参考素材 | 依据模式从完整资产库或分镜列表填入单图、首尾帧、多参考及音频/视频 | 依据模型能力选择分镜首帧、当前镜头关联资产或已完成视频，按媒体类型限额保存结构化引用 | **部分实现** |

## 1. 分镜图选择器

### 原版行为

[`storyboardImageCheck.vue`](../../../Toonflow-web/src/components/storyboardImageCheck.vue)
打开时重置查询、页码和选中项。它调用
`/production/storyboard/getStoryboardData`，以 `scriptId + name + page + limit`
读取数据；表格具有缩略图预览、搜索、每页 10 条、跳页、单选/多选两种模式，
生成中的行不可选。确认时返回当前页中被选中的分镜行。

图片流的 `uploadNode.vue` 与 `generatedNode.vue` 都以单选方式调用它；视频工作台
则有一个较轻的分镜网格选择弹窗。因此原版自身也并非所有使用位置都拥有同样的
搜索和分页能力。

### Flutter 对应

[`image_flow_editor.dart`](../../app/lib/src/screens/production/image_flow_editor.dart)
的上传节点先让用户选“本地文件 / 从素材库选择 / 从分镜选择”。分镜来源读取当前
剧集已生成首帧图，以 `S01` 形式展示；素材来源读取角色、场景、道具的当前选中图。
两者都使用同一个自适应网格，点击即返回一张本地相对路径。

这条路径满足“已有分镜图可成为图片编辑参考”的核心结果，也在桌面与 390dp 上有
widget 证据。但它没有原版分镜表的搜索、分页、缩略图详情表格和多选模式；当分镜
数量很多时，用户无法按名称筛选。因此不能把轻量网格写成 `storyboardImageCheck`
的完整复刻。

| 可观察项 | ToonFlow | DramaFlow | 证据 |
| --- | --- | --- | --- |
| 选已有分镜首帧图 | 有 | 有 | `image_flow_editor_test.dart`：无剧本空态、列出 `S01` |
| 选已有资产图 | 有 | 有（当前角色/场景/道具图） | `image_flow_editor_test.dart`：选择“林朝雪” |
| 本地文件作为图片流输入 | 原版此节点另有上传路径 | 有 | `image_flow_editor.dart` 本地文件分支 |
| 分镜搜索/分页/跳页 | 有 | 无 | 原版表格 `pageSize=10`；Flutter 直接列全量 |
| 分镜多选 | 组件支持，图片流调用处单选 | 无 | Flutter 回传单一 `String` 路径 |

## 2. 通用资产选择器

### 原版行为

[`assetsCheck.ts`](../../../Toonflow-web/src/utils/assetsCheck.ts) 会把完整资产页嵌入
80% 宽的模态框。调用者可以要求 `role/tool/scene/clip/audio` 的任意组合、限制
`clip` 的图片/视频/音频子类型，并决定单选或多选。确认时会合并已选父资产与子资产。

剧本新增和编辑仅传 `role/tool/scene`，所以它们是这个通用选择器的一个较窄使用场景；
图片流和视频工作台则使用更宽的资产类型组合。

### Flutter 对应

[`asset_picker.dart`](../../app/lib/src/screens/script/asset_picker.dart) 是剧本专用的
多选列表，确实承接了剧本的角色、道具、场景关联，并保留初始已选项、取消和确认。
它不是全局通用资产选择器：没有 `clip/audio`、媒体子类型过滤、父子资产选择或搜索。

图片流又单独做了只取当前图片的三类资产网格；视频请求再单独生成候选列表。三个
页面都能完成各自的核心工作，但没有一个与原版 `openAssetsSelector` 同等通用的公共
入口。

| 使用位置 | Flutter 对应 | 结论 |
| --- | --- | --- |
| 新增/编辑剧本关联 `role/tool/scene` | `showAssetPicker` 多选列表 | 当前调用场景等价 |
| 图片流挑一张资产图 | `_assetImageItems()` 网格单选 | 只覆盖当前图和三类资产 |
| 视频引用挑素材 | `videoReferenceCandidates()` + 分组复选 | 只覆盖当前镜头关联资产和已完成视频 |

## 3. 视频请求的参考素材

### 原版行为

[`imageSelect.vue`](../../../Toonflow-web/src/views/production/components/workbench/generate/components/imageSelect.vue)
按视频模型模式渲染单图、首尾帧和多参考槽位。选择资产时，它打开完整资产选择器，
允许 `role/tool/scene/clip/audio`，并以模式过滤片段的图片、视频或音频。用户取消资产
选择时可改选分镜；多参考还会请求资产绑定音频并加入引用列表。

### Flutter 对应

[`video_request_dialog.dart`](../../app/lib/src/screens/production/video_request_dialog.dart)
按模型能力展示文本、首帧、首尾帧、多参考模式。它按 `image/video/audio` 限额禁用超额
选择，并把结果保存为带 `sourceType/sourceId/mediaType/role` 的结构化引用，而不是 URL
数组。`video_track.dart` 只将以下本地存在的媒体列为候选：当前分镜首帧、**已关联到当前
分镜的资产**、以及项目中已完成的视频。

这覆盖模式、首尾帧角色、多参考限额和引用持久化，且已有桌面/390dp widget 与引擎回归。
不过原版可以从当前项目的完整资产库选择，而 Flutter 只显示本镜已关联资产；原版还会把
选中资产的绑定音频加入多参考，Flutter 没有同一动作。因此这行必须是“部分实现”，此前
总清单标为“已验证等价”属于范围判断过宽。

| 可观察项 | ToonFlow | DramaFlow | 判定 |
| --- | --- | --- | --- |
| 模型能力驱动模式 | 有 | 有 | 等价 |
| 单图/首尾帧/多参考及引用角色 | 有 | 有 | 等价 |
| 图片/视频/音频数量限制 | 有 | 有 | 等价 |
| 从完整项目资产库挑选 | 有 | 仅当前镜头已关联资产 | 缺口 |
| 选择资产后自动追加其绑定音频 | 有 | 无同一选择动作 | 缺口 |
| 保存引用身份 | URL/资产字段混合 | 稳定 `sourceType/sourceId/mediaType/role` | 数据表达更明确，但不抵消发现范围缺口 |

## 自动化证据

```sh
cd app
flutter test --concurrency=1 \
  test/widgets/image_flow_editor_test.dart \
  test/widgets/workbench_screen_test.dart \
  test/widgets/script_screen_test.dart \
  test/engine/video_request_test.dart \
  test/engine/video_track_test.dart
```

- `image_flow_editor_test.dart` 覆盖三来源菜单、从资产/分镜选图、分镜空态，以及
  390dp 下选资产后保存参考图；
- `workbench_screen_test.dart` 覆盖多参考、纯文生隐藏参考、首尾帧角色和 390dp 参数保存；
- `video_track_test.dart` 验证候选只能来自本地存在且关联到当前镜头的媒体；
- `script_screen_test.dart` 覆盖剧本关联资产的多选保存。

这些测试不调用真实图像或视频供应商。视频生成、轮询和下载仍完全留给用户最终验收。

## 后续实现边界

要补齐而不重复造三套选择器，应新增一个**可配置的本地媒体选择器**，由调用者传入：

1. 项目和可选资产类型；
2. 片段媒体类型与是否显示子资产；
3. 单选/多选、是否允许分镜首帧；
4. 搜索、分页或按类型筛选；
5. 返回稳定的资产/分镜 ID 与媒体路径，而非仅返回展示 URL。

剧本、图片流和视频工作台都应复用它；视频请求仍负责按模型能力对已选引用做最后校验。
这样补的是原版真实的“发现与选择”能力，不会削弱现有的结构化视频请求模型。

关联总清单：`W6B-GEN-REF-001`、`W6E-CMP-STORYCHECK-001`、
`W6E-LIB-ASSETSEL-001`。
