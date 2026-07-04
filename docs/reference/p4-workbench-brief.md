# P4 多轨工作台 + 配音 + 合成导出移植参照（源码取材固化版，2026-07-03）

> 2026-07-04 接力更新：本文的「视频编辑器不做」是 P4 当时的阶段性边界。
> 当前长期目标已恢复为完整 ToonFlow 复刻，因此 editVideo/NLE/WebAV parity 重新打开。
> 现有实现已补 `o_timelineClip` 式素材层记录、compose metadata handoff、Apple AVFoundation overlay 渲染、Android Media3 overlay 渲染、素材层按时间起点拉开可视间距、素材层按 lane 分成可视多轨并同起点对齐、素材层基础拖拽定位、左右边缘裁剪/缩放、属性面板式层级/起点/时长编辑、普通添加时同轨重叠避让、添加时自动寻找同时间空层、时间线媒体库按播放头快捷添加并自动寻找空层、媒体库 clip 拖放到时间线并按落点坐标/起点与尾部吸附自动寻找空层、纵向拖拽到占用层时保持时间并自动下探首个空层、基础吸附、播放头吸附、基础吸附参考线、拖拽/裁剪/属性编辑时同轨重叠避让、中点分割、按 playhead 任意切点分割、复制素材层到原片段后方并向后避让冲突、波纹复制素材层并后移同轨后续片段、波纹移动素材层并同步移动同轨后续片段、时间线素材层移除且保留源素材、素材层波纹删除、素材层尾部波纹裁剪、素材层波纹插入、以及选中多素材层后按播放头批量切分/复制到播放头/对齐播放头/批量删除/批量波纹删除/批量复制/批量波纹复制/批量移动/批量改轨/批量波纹移动/批量裁剪/批量波纹裁剪/整组拖拽平移并后移避让同轨冲突；复杂吸附规则、更多复杂 ripple、复杂叠放冲突处理、多轨自由非线编与 WebAV parity 仍按后续切片推进。

来源：Toonflow-web/src/views/production/components/workbench/*（index/preview/editVideo/generate/*）
+ views/cornerScape/index.vue + Toonflow-app/src/routes/production/workbench/* + routes/cornerScape/*。

## §1 数据模型澄清（关键纠偏）
- **"多轨"≠并行图层叠加**，而是：**`o_videoTrack` = 一个分镜（镜头）的视频槽位**，与
  `o_storyboard.trackId` 一一对应（`o_storyboard.trackId → o_videoTrack.id`），语义与
  P3 的 `o_storyboard`=分镜图片槽位完全对称。
- `o_video` = 该槽位下的候选生成结果（可有多条，每条一次生成尝试），`o_videoTrack.selectVideoId`
  指向用户选中的那条——即"多版本挑选"机制，和 P2 资产多图版本、P3 分镜首帧图同构。
- 状态枚举（中文字符串，逐字）：`未生成`/`生成中`/`已完成`/`生成失败`（与 P1-P3 一致）。
- `o_assetsRole2Audio`：角色资产 ↔ 音频资产绑定表，**一角色对一音频**（非多对多）。

## §2 视频生成管线
1. **generateVideoPrompt**：LLM 根据分镜 prompt+videoDesc 生成运镜/动作描述的视频提示词
   （复用 P3 分镜生成的同类 LLM 调用模式）。
2. **generateVideo**（单个）：DramaFlow 已具备底层能力——`gateway.generateVideo(prompt,
   firstFrameAbsPath, projectId, stage:'shot_video')`（volcengine seedance，v0.1 时代移植，
   real 实测留用户）；本批要做的是**围绕它的任务编排**：插入 `o_video`(生成中)→调用→
   成功写 filePath+已完成→**首个候选自动设为选中**（无选择时，减少摩擦，行为已文档化）。
3. **batchGenerateVideo**：并发模式与 P2/P3 一致（worker 池+队列 video lane，lane cap=1，
   任务内部并发由 concurrentCount 控制——与图片生成的 lane 语义相同）。
4. **selectVideo**：更新 `o_videoTrack.selectVideoId`，供合成时取用。

## §3 工作台 UI（3 分区）
- **快速预览**（preview.vue）：镜头播放器+信息面板+可拖拽镜头列表——DramaFlow 简化为
  只读预览列表+选中态高亮（不做拖拽重排，镜头顺序已由 storyboard.index 决定）。
- **视频生成**（generate/*）：imageSelect（选哪张分镜图作首帧，默认取当前选中图）→
  提示词编辑（可编辑 videoDesc/prompt）→ 生成→候选网格（多版本挑选，同 P3 分镜网格模式）。
- **视频编辑**（editVideo/*，含 AVCanvas 多轨时间线/转场/滤镜）：**明确不做**——这是
  ToonFlow 用 WebAV 实现的完整非线性编辑器，超出零 ffmpeg 拼接的既定范围（spec §1
  合成定案=简单顺序拼接，不做转场特效）。DramaFlow 用**只读时间线预览**替代（显示各镜头
  时长/选中缩略图，无剪辑操作），如实反映能力边界，不做假交互。

## §4 配音（cornerScape）—— 重点
- **左栏**：批量设置（模型/分辨率/类型筛选/快捷操作）；**内容区**：角色/场景/道具资产卡片
  网格（图+音频标签）。DramaFlow 简化为**角色音频绑定表**（复用 P2 已建的 audio 类型资产
  作为音频池，本批只做"绑定"不做语音合成——与 ToonFlow 一致：cornerScape 只管绑定，
  语音素材本身经由素材中心的音频资产上传，addAudioAssets 已在 P2 完成）。
- **batchBindAudio**（核心）：LLM tool-calling，输入候选音频池+待绑定角色（名称/描述），
  输出 `{roleId, audioAssetId}` 匹配结果，写入 `o_assetsRole2Audio`。照抄复用 P2 剧本
  提取资产的 tool-calling 模式（`generateToolJson`）。
- 三个轮询循环（ToonFlow 用 3s 轮询三条状态）：DramaFlow 统一用**队列事件广播**替代（P1
  起的既定优化，好于轮询），不单独复刻轮询代码。

## §5 合成导出（本批交付核心之一）
- ToonFlow **没有服务端最终合成步骤**——editVideo 的导出走客户端 WebAV AVCanvas。
- DramaFlow：**新建 compose 模块**，按 `o_storyboard.index` 顺序取每个分镜的 `trackId→
  selectVideoId→o_video.filePath`，调用既有 `VideoComposer.concat(segments, output)`
  （macOS/iOS AVFoundation，已集成测试验证过）拼接为整集成片。
- **发现的既存 bug（已修复）**：`Engine` 构造函数签名一直接受 `composer` 参数，但 T3
  schema 重写时忘记把它存成字段——传入的合成器被静默丢弃，`engine.composer` 根本不存在。
  已修复为存字段（默认 `UnsupportedComposer()`），本批合成模块基于修复后的字段构建。

## §6 i18n
`workbench.production.wb.*`（快速预览/视频生成/视频编辑）+ `workbench.cornerScape.*`
（含拼写不一致的 `batchBingAudio` 等历史遗留 key，DramaFlow 用规范英文键名不照抄拼写错误）
自行三语补全，键名规约 `workbenchXxx` / `cornerScapeXxx`。

## 执行边界
- 视频编辑器（剪辑/转场/滤镜）不做，只读预览代替，如实标注。
- 语音合成（TTS）不做，cornerScape 只做绑定，音频素材来源=P2 已有的 audio 资产上传。
- 真实视频生成（seedance）效果留 luke 实机验证；本批测试用 stub 网关覆盖任务编排/状态流转/
  合成拼接逻辑本身。
