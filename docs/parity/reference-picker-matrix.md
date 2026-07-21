# 参考素材选择器对照：资产、分镜与视频请求

状态：2026-07-21 源码逐调用点审计 + 定向 Flutter 回归。

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
| 剧本关联角色/道具/场景 | 弹出完整资产选择器，多选返回资产 | 多选 `role/tool/scene` 父/子资产，支持搜索和每页 10 条，并保存关联 | **已在剧本场景等价** |
| 图片流上传节点选图 | 从资产或分镜图单选，可搜索/分页浏览分镜 | 本地文件、完整项目资产（角色/场景/道具/片段/音频，含子资产）或本剧集分镜首帧单选 | **部分实现** |
| 视频生成参考素材 | 依据模式从完整资产库或分镜列表填入单图、首尾帧、多参考及音频/视频 | 在参数弹窗中列出当前分镜优先的候选和整个项目的可用角色/道具/场景/片段/音频，按媒体类型限额保存结构化引用 | **部分实现** |

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
剧集已生成首帧图，以 `S01` 形式展示；素材来源复用完整项目资产选择器，允许
`role/scene/tool/clip/audio`、父/子资产和单选确认。资产来源由选择的资产 ID 回查其本地
相对路径；分镜来源改由
[`storyboard_image_picker.dart`](../../app/lib/src/screens/production/storyboard_image_picker.dart)
提供可搜索、每页 10 条的单选列表。

这条路径满足“已有分镜图可成为图片编辑参考”的核心结果，也在桌面与 390dp 上有
widget 证据。分镜单选已补齐名称/提示词搜索与每页 10 条，但尚无原版表格的缩略图详情、
生成中禁选和多选调用场景。因此不能把它写成 `storyboardImageCheck` 的完整复刻。

| 可观察项 | ToonFlow | DramaFlow | 证据 |
| --- | --- | --- | --- |
| 选已有分镜首帧图 | 有 | 有 | `image_flow_editor_test.dart`：无剧本空态、列出 `S01` |
| 选已有资产图 | 有 | 有（项目角色/场景/道具/片段/音频，含子资产） | `image_flow_editor_test.dart`：选择“林朝雪”、图片片段并采用 |
| 本地文件作为图片流输入 | 原版此节点另有上传路径 | 有 | `image_flow_editor.dart` 本地文件分支 |
| 分镜搜索/分页/跳页 | 有 | 有（搜索重置页码、每页 10 条、前后翻页） | `storyboard_image_picker.dart` + `image_flow_editor_test.dart`（第 11 镜翻页、按“战损”搜索） |
| 分镜多选 | 组件支持，图片流调用处单选 | 无 | Flutter 回传单一 `String` 路径 |

## 2. 通用资产选择器

### 原版行为

[`assetsCheck.ts`](../../../Toonflow-web/src/utils/assetsCheck.ts) 会把完整资产页嵌入
80% 宽的模态框。调用者可以要求 `role/tool/scene/clip/audio` 的任意组合、限制
`clip` 的图片/视频/音频子类型，并决定单选或多选。确认时会合并已选父资产与子资产。

剧本新增和编辑仅传 `role/tool/scene`，所以它们是这个通用选择器的一个较窄使用场景；
图片流和视频工作台则使用更宽的资产类型组合。

### Flutter 对应

[`asset_picker.dart`](../../app/lib/src/screens/script/asset_picker.dart) 已成为可复用的项目
资产选择器：调用方可指定 `role/tool/scene/clip/audio` 任意类型集合及单/多选；引擎将
父资产与衍生资产稳定展开。界面保留初始已选项、取消和确认，并提供名称/描述/提示词搜索、
每页 10 条和前后翻页。剧本新增/编辑以多选三类资产调用，工作台“素材库”以单选 `clip`
调用。

它仍未实现原版的 `clip` 图片/视频/音频子类型过滤；视频参考面板也还没有统一接入此
入口。因此它是可复用的基础选择器，但不是原版所有调用点都已迁移完毕的结论。

| 使用位置 | Flutter 对应 | 结论 |
| --- | --- | --- |
| 新增/编辑剧本关联 `role/tool/scene` | `showAssetPicker` 多选父/子资产、搜索、分页 | 当前调用场景等价 |
| 工作台镜头“素材库”单选 `clip` | `showAssetPicker(types: {'clip'}, multiple: false)` | 当前调用场景等价（不含媒体子类型过滤） |
| 图片流挑一张资产图 | `showAssetPicker(types: {'role', 'tool', 'scene', 'clip', 'audio'}, multiple: false)` | 当前调用场景等价（不含通用 clip 媒体子类型过滤） |
| 视频引用挑素材 | `videoReferenceCandidates()` + 统一资产/分镜选择器 | 可从完整项目资产库或同剧集分镜单/多选，按模型能力过滤片段类型并保存结构化引用 |

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
数组。`video_track.dart` 将以下本地存在的媒体列为候选：当前分镜首帧、已关联资产（优先
显示）、**项目全部可用的角色/道具/场景/片段/音频及其子资产**，以及项目中已完成的视频；
`clip` 依据实际扩展名而非资产类型归类为图片、视频或音频。用户点“添加参考素材”后可明确
选择素材库或同剧集分镜：素材库复用搜索/分页/父子资产/单多选选择器，并按模型的
`image/video/audio` 能力过滤片段；分镜复用搜索分页选择器。选择一个绑定了音色的非音频
资产时，弹窗会在音频参考上限内自动加入其绑定音频。

这覆盖模式、首尾帧角色、多参考限额、项目级素材发现、父子资产、按片段真实媒体类型筛选、
绑定音频自动追加和引用持久化，且已有桌面/390dp widget 与引擎回归。它仍与原版有两个
可观察差异：原版在“取消资产选择”后直接转入分镜网格，而 Flutter 先显示明确的来源选择；
原版的音频父资产可一次展开所有样本，Flutter 单选父资产时采用其首个有效样本。因此本行仍
为“部分实现”，不能因核心素材集合已经可达就报成完整复刻。

| 可观察项 | ToonFlow | DramaFlow | 判定 |
| --- | --- | --- | --- |
| 模型能力驱动模式 | 有 | 有 | 等价 |
| 单图/首尾帧/多参考及引用角色 | 有 | 有 | 等价 |
| 图片/视频/音频数量限制 | 有 | 有 | 等价 |
| 从完整项目资产库挑选 | 有 | 有（统一选择器的搜索、分页、父子资产、单/多选） | 当前调用场景等价 |
| 从同剧集分镜挑选 | 取消资产后可打开分镜网格 | 有（明确来源选择后打开分镜搜索/分页选择器） | 核心结果等价，入口时序不同 |
| clip 图片/视频/音频过滤 | 有 | 有（按文件扩展名和模型能力过滤） | 等价 |
| 选择资产后自动追加其绑定音频 | 有 | 有，且受 `references.audio` 上限约束 | 等价 |
| 保存引用身份 | URL/资产字段混合 | 稳定 `sourceType/sourceId/mediaType/role` | 数据表达更明确，但不抵消剩余选择体验缺口 |

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
- `workbench_screen_test.dart` 覆盖多参考、纯文生隐藏参考、首尾帧角色、390dp 参数保存、完整素材库选择的媒体类型过滤、同剧集分镜选择，以及选择项目角色时自动携带绑定音频；
- `video_track_test.dart` 验证候选只接受本地存在媒体，并覆盖项目级角色/片段/音频和衍生子资产进入候选、图片/视频片段的实际扩展名分类；
- `script_screen_test.dart` 覆盖剧本关联资产的多选保存。

这些测试不调用真实图像或视频供应商。视频生成、轮询和下载仍完全留给用户最终验收。

## 后续实现边界

当前共享选择器已承接项目、资产类型、片段媒体类型、父子资产、单/多选、搜索、分页和
稳定 ID；视频请求仍负责按模型能力对已选引用做最后校验。下一步只应补上剩余的音频父资产
多样本展开语义，而不是再造一套选择器。

关联总清单：`W6B-GEN-REF-001`、`W6E-CMP-STORYCHECK-001`、
`W6E-LIB-ASSETSEL-001`。

## 历史复验快照（2026-07-19）

当前 `develop` 工作树重新运行了本页列出的跨模块回归：

```bash
cd app
flutter test --concurrency=1 \
  test/widgets/image_flow_editor_test.dart \
  test/widgets/workbench_screen_test.dart \
  test/widgets/script_screen_test.dart \
  test/engine/video_request_test.dart \
  test/engine/video_track_test.dart
```

结果为 `151` 条测试全部通过。用例只使用内存 SQLite、临时媒体文件与 fake gateway；
即使覆盖了视频请求的校验、提交状态、冷启动恢复、取消和重试，也没有连接、提交、轮询
或下载任何真实视频服务。这是本功能更新前的历史快照：项目级素材发现和自动追加绑定音频
由后续回归补齐；搜索、分页、按片段真实媒体类型筛选和原版独立资产选择器的取消后跳转
分镜选择，仍是待补的选择体验缺口。
