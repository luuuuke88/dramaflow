# 工作台对照：预览、生成与轨道

状态：2026-07-21 源码对照、实现与定向回归。本文只审计当前 ToonFlow 1.1.8 的
可达工作台；不把未接线草稿当成功能，也不触发真实视频生成。

## 结论先行

DramaFlow 已有一套比原版更重的本地时间线编辑能力：素材层可以添加、拖拽、
裁剪、切分、复制、删除、波纹操作、分组、吸附和避免重叠。它也已经覆盖了按
分镜后台批量生成运镜提示词、选择视频候选、保存候选为素材、编辑时长和重排分镜。

工作台现在是同一全屏容器中的**快速预览 / 视频生成 / 视频剪辑**三工作面：顶栏以三个
图标 Tab 切换，默认打开快速预览，且不会额外占用移动端的垂直编辑空间。项目画幅会映射
为预览画布的 `16:9`、`1:1` 或 `9:16`；剪辑面沿用本地时间线而非伪造一个未接通的实时
渲染画布。

其中原版的**快速预览**已经闭合：DramaFlow 从工作台顶栏进入内嵌首帧预览，以 50ms
唤醒加单调时钟实际间隔按分镜时长轮播，支持播放、暂停、逐镜跳转、总进度 seek、
分段定位、资产/提示词审阅，以及所选本地首帧 ZIP 导出。导出只接受媒体根目录内的
普通文件，并在独立 isolate 流式写目标 ZIP。桌面为预览与信息两栏，低于 840dp 收敛
为可滚动单列；390dp 回归覆盖缩略图、选择与导出入口。

原版的**新增独立视频轨**也已经闭合：DramaFlow 从工作台顶栏按当前视频模型的首个
可用时长创建一条不关联分镜的轨道；独立轨按创建顺序横列展示，可经确认删除，并且
不会被并入分镜合成顺序。候选视频的单个另存与按勾选镜头批量 ZIP 已闭合；自由 NLE
的实时画布预览仍是独立未闭合项。

快速预览不是成片播放器，也不需要视频供应商或实时渲染。本次实现严格保持这个
边界：没有新增视频提交、轮询、下载或合成逻辑。

## 基线与证据

| 范围 | ToonFlow 证据 | DramaFlow 证据 |
| --- | --- | --- |
| 工作台外壳 | `Toonflow-web/src/views/production/components/workbench/index.vue:16-45, 70-88` | `app/lib/src/screens/production/workbench_screen.dart`（`WorkbenchTab`、顶栏三工作面、项目画幅解析） |
| 快速预览 | `.../workbench/preview.vue:7-166, 211-445` | `workbench_preview.dart`（首帧预览/控制/信息/选择导出）、`workbench_preview_controller.dart`（纯时间轴）、`storyboard.dart`（本地 ZIP） |
| 轨道增加与删除 | `.../generate/components/track.vue:161-209`；`Toonflow-app/src/routes/production/workbench/{addTrack,deleteTrack}.ts` | `app/lib/src/engine/video_track.dart:175-199,1222-1243` |
| 批量运镜提示词 | `Toonflow-app/src/routes/production/workbench/batchGeneratePrompt.ts:92-207`；`checkVideoPrompt.ts:17-24` | `video_track.dart:639-739,1231-1244`、`workbench_screen.dart:134-159,200-205,3761-3774` |
| 时间线与候选 | `.../editVideo/index.vue`、`.../generate/components/video.vue` | `workbench_screen.dart`、`timeline_clip.dart`、`video_track.dart` |

## 用户动作逐项对照

| 用户动作 | 原版行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 打开工作台 | 全屏三页签：快速预览、视频生成、视频剪辑；默认预览；按 `videoRatio` 初始化剪辑画布 | 同一全屏页顶部三个图标 Tab，默认内嵌快速预览；预览舞台按项目 `16:9`/`1:1`/`9:16` 映射，视频生成与视频剪辑内容严格分面 | 部分实现：三工作面、默认入口、生成/剪辑分面与预览画幅已验证；剪辑面尚无原版实时画布 |
| 预览分镜首帧 | 按当前镜展示图片；播放、暂停、前后跳镜、分段 seek | 首帧/缺图占位、播放暂停、前后跳镜、Slider seek 与按时长比例分段定位 | 已验证等价 |
| 查看本镜信息 | 显示时长、关联资产和图片提示词；模板也尝试显示描述，但当前接口遗漏该字段，实际总是空态 | 预览侧栏显示时长、关联角色/场景/道具、图片提示词及本地 `videoDesc` | 已验证等价 |
| 重排分镜 | 拖动只改前端临时列表；原版“恢复排序”初始化有缺陷 | 拖动后持久化 `o_storyboard.index`，合成顺序随之变化 | 覆盖可用行为 |
| 新建视频轨 | 从模型默认时长创建独立 `o_videoTrack`，不要求关联分镜 | 顶栏图标从当前视频能力取首个可用时长创建独立轨；横列按创建顺序显示、可确认删除；不改写 `storyboard.trackId` | 已验证等价 |
| 删除视频轨 | 删除轨道并清空关联分镜的 `trackId` | 删除轨道、清候选视频文件并清空关联 | 已验证等价 |
| 勾选并批量生成 | 勾选轨道后，提示词任务即时返回、逐轨显示生成中/完成/失败；视频另走批量任务 | 勾选分镜对应轨道后，提示词即时入文本车道任务、逐轨显示状态；视频另走批量任务 | 已验证等价 |
| 候选管理 | 浏览、选中、播放、删除、单个下载和批量 ZIP 下载 | 浏览、选中、播放、删除、保存为 clip 素材、单个另存和按勾选镜头批量 ZIP | 已验证等价 |
| 自由剪辑 | WebAV 时间线、媒体库、实时画布预览、浏览器导出 | 本地叠加层时间线和原生合成；无编辑器内实时预览 | 部分实现，详细见 [W3 NLE 参考](w3-nle-reference.md) |

## 原版“新增轨道”的精确定义与 Flutter 对应

原版点击加号后先从当前视频模型读取第一个可用时长，再调用
`/production/workbench/addTrack`。后端只写入 `projectId`、`scriptId`、`duration`
和轨道 ID；不写入 `storyboardId`，因此它是独立轨道而不是“新建分镜”的别名。

DramaFlow 保留 `ensureTrackForStoryboard` 作为分镜懒建路径，并新增完全独立的
`createStandaloneVideoTrack`：只写入 `projectId`、`scriptId`、`duration` 和初始状态，
绝不回填 `o_storyboard.trackId`。`standaloneVideoTracks` 使用 `NOT EXISTS` 排除已有
分镜引用的轨道，确保同一轨不会在独立区与分镜列表重复出现；删除仍复用同一条
`deleteVideoTrack` 级联清理路径。

## 快速预览的数据边界

`preview.vue` 的右侧信息面板写的是 `currentShot.description`，但
`getStoryboardData.ts` 最终只投影 `id`、`createTime`、`duration`、`filePath`、
`prompt`、`scriptId`、`characters` 和 `index`。它没有返回 `description`，也没有返回
`o_storyboard.videoDesc`。因此当前打包版中“分镜描述”一栏会稳定显示“无描述”，并不是
一个已经可用的描述审阅能力。

这条结论来自同一条真实数据链，而不是只看 Vue 模板：

```text
o_storyboard.videoDesc
  └─ getStoryboardData.ts 的最终 return 未投影
       └─ preview.vue 读取不存在的 currentShot.description
            └─ noDescription 空态
```

Flutter 实现没有为了复制这个断链而隐藏已有的 `StoryboardRow.videoDesc`：
`workbench_preview.dart` 将它作为“分镜描述”展示，同时仍保留原版的首帧轮播、
按时长进度、跳镜、资产和提示词审阅。它是对原版无效字段的本地修正，不是视频
播放器扩展；本行判为“已验证等价”而非“已验证更优”，因为尚未取得打包版黑盒
用例来量化这一改进。

## 批量运镜提示词的状态边界

原版在 `batchGeneratePrompt` 里先把每条轨道标为“生成中”，立即返回，再由后台并发
任务逐轨写入“已完成”或“生成失败”；前端用 `checkVideoPrompt` 轮询这些轨道。
DramaFlow 对应地创建 `video_prompt_generation` 任务，并由队列事件驱动界面刷新，不采用
HTTP 轮询。每条轨道增加独立的 `promptState` / `promptErrorReason`，因此提示词工作流不会
改写视频候选的 `state`、失败原因或已选视频。

该任务沿文本车道执行，部分镜头失败不会抹掉已经成功的提示词。每条轨道持有当前
`promptTaskId`：用户取消、应用冷启动恢复、手动编辑、单镜替代、单镜失败或清空轨道都会使旧任务
失去写入权；晚到回包只能按自己的任务归属条件写入，不能覆盖新内容或复活被删轨道。
失败的批量任务重试时会在同一 SQLite 保存点内重新认领新任务 ID。已有活跃任务的轨道会被引擎拒绝再次入队，避免重复收费。这与原版的可观察“后台、逐轨
状态”行为等价，同时避免旧的同步循环阻塞工作台。

## 验证

本轮重新运行：

```sh
cd app
flutter test --concurrency=1 --reporter compact
flutter analyze
flutter build macos --debug
cd .. && node tool/parity/check_no_orphans.js
git diff --check
```

全量 963 条离线回归通过，`flutter analyze` 为零 issue，macOS Debug 构建成功，库存检查为
538/538。证据覆盖纯时间轴跨镜/边界定位、选中且存在的本地首帧 ZIP 内容、绝对路径/`..`/
符号链接拒绝、桌面入口及 390dp 缩略图/选择/导出入口，并覆盖 1024dp 英文工具栏、缺失
资产图降级和后台运镜提示词的逐轨成功/失败、取消竞态、手工编辑/单镜替代、重复收费拒绝、
清轨竞态、冷启动恢复和失败 Tooltip。视频相关用例仅使用 Dart fake gateway、本地假媒体和
假合成器；没有提交、轮询、下载或渲染真实供应商的视频任务。

## 后续实施边界

这份审计不再把快速预览、三工作面外壳、项目预览画幅或独立建轨列为缺口。后续的
工作台缺口是：

- 剪辑工作面：接入可真实预览时间线层的画布与可控导出路径；不能用静态比例框冒充
  `editVideo` 的实时画布。
- 独立轨道生成：原版可为活动独立轨编辑参考素材、提示词并提交生成；Flutter 现已复刻
  新增/显示/删除和不进入分镜合成的行为，但尚未让独立轨进入独立的参考素材与生成面板。

总清单对应项：`W6B-WORKBENCH-SHELL-001`、`W6B-WORKBENCH-PREVIEW-001`、
`W6B-GEN-TRACK-001`、`W6B-GEN-CANDIDATE-001`、`W6B-EDITVIDEO-*`。
