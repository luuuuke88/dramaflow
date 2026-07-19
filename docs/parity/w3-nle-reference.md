# W3 NLE 工作台 — Scope Reference

状态：已完成源码与定向回归审计。本文档界定未来 W3 的真实范围，不包含实现计划，也不把已有的轻量时间线夸大为自由剪辑器。

Baseline：`Toonflow-web` 前端源码（WebAV 剪辑器）与 DramaFlow `app/lib/src/**` + 原生合成器（`avfoundation_composer.dart`/`ComposerPlugin.swift`/`MainActivity.kt`）。

## 当前验证基线（2026-07-19）

以下现有能力已在当前工作区重新运行定向回归验证：时间线素材层的
新增、移动、裁剪、切分、复制、删除、波纹、分组、吸附与避让；视频候选的
幂等提交状态机、冷启动恢复、取消和删除；合成输入的排序、转场/滤镜白名单
与额外素材层；以及桌面和移动工作台的关键交互。命令为：

```sh
flutter test --concurrency=1 \
  test/engine/timeline_clip_test.dart \
  test/engine/compose_episode_test.dart \
  test/engine/video_track_test.dart \
  test/widgets/workbench_screen_test.dart
```

结果为 **155 项通过**。视频相关用例只使用 Dart fake gateway 或本地假合成器，
没有提交、轮询或下载任何真实视频任务。这个证据只证明下文已经列出的
DramaFlow 现有能力，不缩小自由多轨、实时预览、特效与跨平台合成等缺口。

---

## 0. Spec 原文关键措辞的核验结论（先说结论）

spec §8 对 W3 的框定是"解冻现有被隐藏的高级时间线能力"（"现有被隐藏的"暗示 DramaFlow 引擎可能已经实现了比 UI 暴露更多的能力）。**本次直接核验：这个假设不成立。** 转场与滤镜在 DramaFlow 的 Dart 校验层（`compose.dart`）、macOS/iOS 原生合成器（`ComposerPlugin.swift`，两端逻辑除插件注册样板代码外完全一致）、Android 原生合成器（`MainActivity.kt`）三处的实现集合**完全相同**，且都与 UI 下拉框暴露的选项一一对应——没有"引擎已实现、UI 未暴露"的隐藏能力可以"解冻"。真正的缺口是集合本身偏窄（3 转场 vs ToonFlow 6 种、4 滤镜 vs 10 种、0 特效 vs 8 种+2 贴纸），需要新增实现，而非解锁已有代码。详见第 2 节的逐证据核验。

---

## 1. 精确缺口清单：转场 / 滤镜 / 特效

### 1.1 转场（Transition）

| ToonFlow（6 种，`mediaData.ts:44-53`） | DramaFlow UI 暴露（`workbench_screen.dart:3749-3753`） | DramaFlow 引擎允许（`compose.dart:3-7`） |
|---|---|---|
| fade（淡入淡出） | fade | fade |
| slide（滑动） | — | — |
| wipe（擦除） | — | — |
| dissolve（溶解） | dissolve | dissolve |
| zoom（缩放） | — | — |
| rotate（旋转） | — | — |
| — | whip_pan（甩镜，ToonFlow 无此项，DramaFlow 独有） | whip_pan |

DramaFlow 实际支持 **3/6**（fade、dissolve 与 ToonFlow 重合；whip_pan 是 DramaFlow 自研、ToonFlow 没有的额外转场），缺 slide/wipe/zoom/rotate 4 种。

### 1.2 滤镜（Filter）

| ToonFlow（10 种，`mediaData.ts:72-120`） | DramaFlow UI/引擎（`compose.dart:9-14`，`ComposerPlugin.swift:811-826` CoreImage 实现） |
|---|---|
| grayscale（灰度） | — |
| sepia（怀旧褐色） | — |
| warm（暖色，sepia@0.3） | warm（暖色，但实现是 RGB 色彩矩阵偏红，非 sepia） |
| cool（冷色，hue-rotate 180°） | cool（冷色，RGB 色彩矩阵偏蓝，非 hue-rotate） |
| saturate（鲜艳） | — |
| brightness（提亮） | — |
| contrast（高对比度） | — |
| blur（模糊） | — |
| invert（反相） | — |
| opacity（半透明） | — |
| — | cinematic（电影感：饱和度+对比度调整，ToonFlow 无此项） |
| — | vintage（复古：CISepiaTone+饱和度衰减，概念上最接近 ToonFlow 的 sepia，但参数/命名不同，非同一实现） |

DramaFlow 实际支持 **4/10**，且即便是名称重合的 warm/cool 也是不同算法（色彩矩阵 vs ToonFlow 的 sepia 混合/色相旋转），cinematic/vintage 是 DramaFlow 自研、ToonFlow 没有的额外滤镜。命中的核心 10 种缺 grayscale/sepia/saturate/brightness/contrast/blur/invert/opacity 8 种。

### 1.3 特效（Effect）

| ToonFlow（8 特效 + 2 贴纸，`mediaData.ts:56-69`） | DramaFlow |
|---|---|
| fadeIn / fadeOut / flash / shake / zoomIn / zoomOut / pulse / rotateIn（8 种片段级特效） | **完全没有这个能力分类** |
| sticker-1 / sticker-2（贴纸） | **完全没有这个能力分类** |

DramaFlow 实际支持 **0/8**（+0/2 贴纸）。这是三个能力类别里唯一"从零开始"而非"窄集合"的缺口——不存在特效这个概念，`compose.dart`/`ComposerPlugin.swift`/`MainActivity.kt` 均无任何特效相关代码路径。对应 checklist 行 `W6B-EDITVIDEO-PREVIEW-EXPORT-001` 原文措辞："转场(3 vs 6)/滤镜(4 vs 10)/特效(0 vs 8)"。

---

## 2. "隐藏能力"核验证据（逐处引用）

1. **Dart 校验层是一个硬性白名单，超出即抛错**：`compose.dart:3-14` 定义 `supportedComposeTransitions = {fade, dissolve, whip_pan}` 与 `supportedComposeFilters = {cinematic, warm, cool, vintage}`；`validateComposeSegments`（`compose.dart:16-37`）对任何不在集合内的值直接 `throw EngineException(errPlatformComposer, ...)`。这不是"引擎支持但校验层保守拦截"的情况——校验集合本身就是引擎全部能力的准确反映（见下两点）。
2. **macOS/iOS 原生合成器逐一核验**：`ComposerPlugin.swift` 中转场判定 `hasDissolveTransition`/`hasFadeTransition`/`hasWhipPanTransition`（:226-235, :592-601）与实际渲染 `applyFadeOpacityRamps`（:662-682，仅响应 `"fade"`）、`applyWhipPanTransformRamps`（:684-715，仅响应 `"whip_pan"`）、dissolve 交叉淡化（:611-660）三个函数只覆盖这 3 种；滤镜 `filterImage(_:preset:)`（:809-826）是一个 `switch preset` 语句，`case` 分支精确对应 cinematic/warm/cool/vintage 四种，`default` 直接原样返回图像不做任何处理。**没有第五个 `case` 分支、没有被 UI 忽略的额外能力。**（`app/macos/Runner/ComposerPlugin.swift` 与 `app/ios/Runner/ComposerPlugin.swift` 除 Flutter 插件注册样板代码外逐字节相同，此结论对两端同时成立。）
3. **Android 原生合成器同样核验**：`MainActivity.kt` 转场判定（:351, :373, :422-424, :610, :689, :699, :704）与滤镜 `when` 分支（:724-727 起，`"cinematic"`/`"warm"`/`"cool"`/`"vintage"`）与 macOS/iOS 端集合完全一致，无额外能力。
4. **UI 下拉框与引擎允许集合一一对应**：`workbench_screen.dart:3749-3760` 的 `transitionOptions`/`filterOptions` 精确列出 fade/dissolve/whip_pan 与 cinematic/warm/cool/vintage，不多不少。

**结论**：三端（Dart 校验、macOS/iOS 原生、Android 原生）与 UI 完全对齐，没有可以低成本"解冻"的既有能力。W3 若要补齐 slide/wipe/zoom/rotate 转场、grayscale/sepia/saturate/brightness/contrast/blur/invert/opacity 滤镜、8 特效+2 贴纸，都需要在三端合成器中**新增实现**，不是简单的 UI 暴露开关。spec 的"解冻隐藏能力"措辞在转场/滤镜/特效这个具体维度上不成立——真正对应"低成本解冻"模式的，是下面第 4 节里的属性面板与预览能力缺口（那些确实是"引擎已有数据结构，UI 未提供入口"的情况）。

---

## 3. 自由剪辑能力对比

依据 checklist `W6B-EDITVIDEO-TIMELINE-001` 与 `W6B-EDITVIDEO-PROPPANEL-001` 与 `W6B-EDITVIDEO-PREVIEW-EXPORT-001`：

| 能力 | ToonFlow（`editVideo/index.vue` + WebAV） | DramaFlow（`workbench_screen.dart` + `timeline_clip.dart`） |
|---|---|---|
| 时间线模型 | 自由多轨（video/image/audio/subtitle/text/sticker/filter/effect 轨），任意素材可拖入任意轨、跨轨拖拽 | **叠加层模型**：底层视频/音频轨只读（顺序分镜），仅 `clip` 资产可写入 `o_timelineClip`；该表只有资产、文件、轨道、起点、时长、名称和不透明度，不能表达音频、字幕、特效或素材类型——不是自由任意素材多轨 NLE |
| 片段操作 | 拖入/跨轨移动/裁剪/播放头切分/删除/复制/转场 | 新增/移动/裁剪/切分/复制/删除 + 波纹(ripple)/分组/吸附/避让（DramaFlow 独有，ToonFlow 未显式暴露，checklist 未据此判定更优） |
| 撤销/重做 | 有（`index.vue:46-68` 历史栈） | **无**——编辑器内没有撤销重做 |
| 属性面板 | 常驻停靠面板：名称/起止/总时长/不透明度/音量/播放倍速/音频淡入淡出/转场类型+时长/字幕文本+字号，复制/删除 | 模态弹窗（`_EditTimelineClipDialog`）：轨道/起始/时长/不透明度。现有 `o_timelineClip` 没有音量、倍速、淡入淡出、字幕或转场字段，故这些不是“补几个控件”即可；名称虽存储在表中，当前更新 API 也没有编辑入口。 |
| 素材库 Tab | 8 类可拖拽 Tab：分镜视频/媒体/图片/音频/字幕文本/转场/特效/滤镜 | 仅 clip 类素材条（`_TimelineMediaBin`），无转场/特效/滤镜/文本预设/独立图片/音频 Tab 可拖入——参数化配置（下拉框）与"可拖拽库项目"是两种不同的交互模型 |
| 编辑器内实时预览 | WebAV `AVCanvas` 实时合成画布（含滤镜/特效/转场逐帧渲染），编辑时所见即所得 | **无**——编辑器内没有实时时间线预览，合成只发生在最终导出阶段 |
| 导出/合成平台覆盖 | Web 端 WebAV，浏览器内导出 MP4 | 仅 macOS/iOS/Android 三端有原生合成器；**Web/Windows/Linux 为 `UnsupportedComposer`，完全无法合成** |

---

## 4. 面向未来 W3 spec 的具体缺口清单（按"低成本/高成本"分组）

### A 组 — 纯 UI 收口（小，不改变现有媒体语义）

1. **常驻属性面板替代模态弹窗**：将现有的轨道、起始、时长和不透明度放入选中片段的固定检查器；这只改变布局与窄屏呈现，不涉及数据层或合成器。
2. **现有名称的编辑入口**：`o_timelineClip` 已有 `name` 列，但 `TimelineClipRow` 和 `updateTimelineClip` 没有暴露写入参数。补一个受测试保护的名称更新入口即可，不应借此误称为完整属性面板。

已完成的字段核验：`db.dart:347-358` 定义的 `o_timelineClip` 只有 `assetId`、`durationMs`、`filePath`、`id`、`lane`、`name`、`opacity`、`projectId`、`scriptId`、`startMs`。因此音量、播放倍速、淡入淡出、字幕文字/字号、转场时长、效果参数都不存在“引擎已有、只差 UI”的解冻空间。

### B 组 — 需要新增引擎/合成器实现（中～大，三端合成器都要动）

3. **自由素材时间线的数据模型**：这是后续功能的前提。需要区分视频、图片、音频、字幕、文本、贴纸、滤镜、特效等片段，并保存来源裁剪、音量、倍速、淡入淡出、文本样式和参数。现有 `o_timelineClip` 仅表示一个不透明度可调的 `clip` 视频叠加；直接往现有表打补丁会让模型继续混淆，应在设计阶段确定兼容迁移或新的片段表。
4. **转场扩容**（slide/wipe/zoom/rotate，4 种）：每种都要在 `ComposerPlugin.swift`（macOS+iOS 共享逻辑）与 `MainActivity.kt`（Android）各自新增 `AVMutableVideoCompositionLayerInstruction`/等价 Android 合成变换，`compose.dart` 允许集合同步扩容。三端工作量对称，逐种转场独立可交付。
5. **滤镜扩容**（grayscale/sepia/saturate/brightness/contrast/blur/invert/opacity，8 种）：iOS/macOS 端多数可直接映射到现成 CoreImage filter（`CIColorControls`/`CISepiaTone`/`CIGaussianBlur`/`CIColorInvert` 等，`filterImage(_:preset:)` 已有可扩展的 `switch` 结构），实现成本低于转场；Android 端需要等价 GL/矩阵实现，工作量视现有 `colorScaleMatrix` 基础设施可复用程度而定。
6. **特效系统（0→8+2，全新能力）**：最大的一块。需要新的数据模型（特效类型+作用片段+时长参数）、`compose.dart` 新增特效校验与序列化、三端合成器新增关键帧动画（fadeIn/fadeOut 可复用现有 opacity ramp 机制；flash/shake/zoomIn/zoomOut/pulse/rotateIn 需要新的变换插值逻辑）、贴纸需要额外的图层合成与素材管理。建议作为独立子任务，不与转场/滤镜扩容合并。
7. **编辑器内实时预览**：DramaFlow 目前合成只在最终导出时发生，没有编辑时所见即所得。ToonFlow 用 WebAV `AVCanvas` 做浏览器内实时合成；DramaFlow 若要对等，需要在 Flutter 侧构建时间线实时预览渲染路径（不一定要复刻 WebAV 架构，但需要产品/工程共同定义"实时预览"的具体交付形态）——这是本文档四条缺口里唯一需要先明确产品设计再定工程方案的一项，不建议直接进入实施排期。
8. **平台覆盖**：Web/Windows/Linux 完全没有合成器（`UnsupportedComposer`）。是否要补齐是产品范围决策（这几个平台是否在 DramaFlow 的支持矩阵内），不是本文档能替用户决定的事项，仅如实记录现状。
9. **撤销/重做**：编辑器内完全没有这个能力，需要设计一个操作历史栈（`timeline_clip.dart` 层面）+ UI 快捷键/按钮，工作量中等，不依赖转场/滤镜/特效扩容，可独立排期。

---

## 5. 一句话总结

DramaFlow 的"叠加层时间线"有合理且独到之处（波纹/分组/吸附/避让是 ToonFlow 没有的能力），但它不是原版自由多轨 NLE 的底座。W3 的首要事实是：`o_timelineClip` 不具备原版片段属性的数据模型，不能把缺口包装成“解冻”。真正的工作依次是确立自由素材片段模型，再补转场/滤镜/特效、实时预览、撤销重做和平台合成覆盖；常驻检查器与名称编辑才是少数可以独立、小步完成的 UI 收口。
