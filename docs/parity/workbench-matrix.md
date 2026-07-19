# 工作台对照：预览、生成与轨道

状态：2026-07-20 源码对照、实现与定向回归。本文只审计当前 ToonFlow 1.1.8 的
可达工作台；不把未接线草稿当成功能，也不触发真实视频生成。

## 结论先行

DramaFlow 已有一套比原版更重的本地时间线编辑能力：素材层可以添加、拖拽、
裁剪、切分、复制、删除、波纹操作、分组、吸附和避免重叠。它也已经覆盖了按
分镜批量生成提示词、选择视频候选、保存候选为素材、编辑时长和重排分镜。

其中原版的**快速预览**已经闭合：DramaFlow 从工作台顶栏进入全屏首帧预览，以 50ms
唤醒加单调时钟实际间隔按分镜时长轮播，支持播放、暂停、逐镜跳转、总进度 seek、
分段定位、资产/提示词审阅，以及所选本地首帧 ZIP 导出。导出只接受媒体根目录内的
普通文件，并在独立 isolate 流式写目标 ZIP。桌面为预览与信息两栏，低于 840dp 收敛
为可滚动单列；390dp 回归覆盖缩略图、选择与导出入口。

这仍不能掩盖一个明确的 1:1 缺口：原版可以新建一条**不关联分镜的空视频轨**；
DramaFlow 只会为某个分镜懒建轨道，无法先建独立轨。候选视频直接下载/批量 ZIP、
自由 NLE 的实时画布预览也仍是独立未闭合项。

快速预览不是成片播放器，也不需要视频供应商或实时渲染。本次实现严格保持这个
边界：没有新增视频提交、轮询、下载或合成逻辑。

## 基线与证据

| 范围 | ToonFlow 证据 | DramaFlow 证据 |
| --- | --- | --- |
| 工作台外壳 | `Toonflow-web/src/views/production/components/workbench/index.vue:16-45` | `app/lib/src/screens/production/workbench_screen.dart:196-348` |
| 快速预览 | `.../workbench/preview.vue:7-166, 211-445` | `workbench_preview.dart`（首帧预览/控制/信息/选择导出）、`workbench_preview_controller.dart`（纯时间轴）、`storyboard.dart`（本地 ZIP） |
| 轨道增加与删除 | `.../generate/components/track.vue:161-209`；`Toonflow-app/src/routes/production/workbench/{addTrack,deleteTrack}.ts` | `app/lib/src/engine/video_track.dart:175-199,1222-1243` |
| 时间线与候选 | `.../editVideo/index.vue`、`.../generate/components/video.vue` | `workbench_screen.dart`、`timeline_clip.dart`、`video_track.dart` |

## 用户动作逐项对照

| 用户动作 | 原版行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 打开工作台 | 全屏三页签：快速预览、视频生成、视频剪辑 | 全屏单屏工作台，顶栏“快速预览”打开首帧预览页；生成与时间线仍并置 | 部分实现：能力可达，但未复刻三 Tab 外壳 |
| 预览分镜首帧 | 按当前镜展示图片；播放、暂停、前后跳镜、分段 seek | 首帧/缺图占位、播放暂停、前后跳镜、Slider seek 与按时长比例分段定位 | 已验证等价 |
| 查看本镜信息 | 显示时长、关联资产和图片提示词；模板也尝试显示描述，但当前接口遗漏该字段，实际总是空态 | 预览侧栏显示时长、关联角色/场景/道具、图片提示词及本地 `videoDesc` | 已验证等价 |
| 重排分镜 | 拖动只改前端临时列表；原版“恢复排序”初始化有缺陷 | 拖动后持久化 `o_storyboard.index`，合成顺序随之变化 | 覆盖可用行为 |
| 新建视频轨 | 从模型默认时长创建独立 `o_videoTrack`，不要求关联分镜 | 仅 `ensureTrackForStoryboard`，严格一镜一轨 | 缺失 |
| 删除视频轨 | 删除轨道并清空关联分镜的 `trackId` | 删除轨道、清候选视频文件并清空关联 | 已验证等价 |
| 勾选并批量生成 | 勾选轨道，批量生成提示词或视频 | 勾选分镜对应轨道，批量生成提示词或视频 | 已验证等价 |
| 候选管理 | 浏览、选中、播放、删除、单个下载和批量 ZIP 下载 | 浏览、选中、播放、删除、保存为 clip 素材 | 部分实现：缺直接下载与 ZIP |
| 自由剪辑 | WebAV 时间线、媒体库、实时画布预览、浏览器导出 | 本地叠加层时间线和原生合成；无编辑器内实时预览 | 部分实现，详细见 [W3 NLE 参考](w3-nle-reference.md) |

## 原版“新增轨道”的精确定义

原版点击加号后先从当前视频模型读取第一个可用时长，再调用
`/production/workbench/addTrack`。后端只写入 `projectId`、`scriptId`、`duration`
和轨道 ID；不写入 `storyboardId`，因此它是独立轨道而不是“新建分镜”的别名。

DramaFlow 的 `ensureTrackForStoryboard` 则在创建时回填 `o_storyboard.trackId`。两者
数据模型并不等价。将来补这个缺口时，应新增明确的独立建轨 API/引擎方法和 UI
入口，不能把某个分镜自动创建后伪装成独立轨。

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

## 定向验证

本轮重新运行：

```sh
cd app
flutter test \
  test/widgets/workbench_preview_controller_test.dart \
  test/engine/storyboard_test.dart \
  test/widgets/workbench_screen_test.dart \
  test/widgets/production_screen_test.dart
flutter analyze
```

结果：**119 项通过**，`flutter analyze` 为零 issue。新增证据覆盖纯时间轴跨镜/边界
定位、选中且存在的本地首帧 ZIP 内容、绝对路径/`..`/符号链接拒绝、桌面入口及 390dp
缩略图/选择/导出入口，并覆盖 1024dp 英文工具栏和缺失资产图降级。视频相关用例仅使用
Dart fake gateway、本地假媒体和假合成器；没有提交、轮询、下载或渲染真实供应商的视频任务。

## 后续实施边界

这份审计不再把快速预览列为缺口。后续若要补齐其余能力，先单独做设计确认：

- 工作台外壳：决定是否需要在不牺牲单屏效率的前提下复刻三 Tab 结构与画幅初始化。
- 独立轨道：明确它与分镜轨的关联、删除级联、参与批量生成与合成时的排序规则。
- 候选下载：先决定原生桌面“存为文件”和多选打包的预期，再实现，不把“保存为
  素材”误报成下载等价。

总清单对应项：`W6B-WORKBENCH-SHELL-001`、`W6B-WORKBENCH-PREVIEW-001`、
`W6B-GEN-TRACK-001`、`W6B-GEN-CANDIDATE-001`、`W6B-EDITVIDEO-*`。
