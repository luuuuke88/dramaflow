# 制作画布图片流对照：资产派生与节点编辑

状态：2026-07-21 静态源码对照 + 定向 Flutter 回归。本文只讨论制作画布内的
`资产 → 派生资产 → 节点式图片编辑` 路径；资产中心的普通生图另见
[资产中心对照](assets-library-matrix.md)。

## 结论先行

DramaFlow 的图片流编辑器核心并不弱：节点和边可以保存/恢复，生成节点可从
图片区拖动并在桌面/390dp 保存位置，参数区的文本选择不会误移动节点；上传和
已生成节点都可作为下一生成节点的参考源，连线会同步所有参考图并阻止自连、
同向和反向重复。上传节点可直接采用参考图；生成节点可从本地、素材库或分镜
直接设为结果并采用。生成节点有模型、画幅、清晰度校验，多参考图会直接传给
图像网关；自动布局会稳定重排为 LR 层级并适配视口，关闭前会确认且回写已有
流程。同时还额外具备重绘和局部重绘。

2026-07-21 已补齐制作画布资产派生闭环：节点会将 `o_assets.assetsId` 关系读取为
“原始资产 → 衍生资产”分组；原始资产只承担层级起点和参考图角色，点击衍生项才
进入图片流。若衍生项尚没有历史 `flowId`，编辑器会同时装入父图参考和已有衍生图
结果；若已有 flow，则照常从保存的节点/边恢复。应用结果只回写该衍生资产，删除也
只删除该子项并走确认与图片流生命周期清理。

这里**不添加手工“新建衍生资产”按钮**：原版资产节点同样只展示、编辑和删除已有
子项，创建由 Production Agent 的 `add_deriveAsset` 工具完成。这条 Agent 能力与
批量派生出图仍在各自的清单项中独立验收，不能因为节点 UI 已对齐而提前判绿。

## 基线与实现位置

| 范围 | ToonFlow | DramaFlow |
| --- | --- | --- |
| 资产节点 | `Toonflow-web/src/views/production/node/assets.vue:8-75, 103-160` | `app/lib/src/screens/production/production_screen.dart:801-1059` |
| 图片流容器 | `.../components/editImage/index.vue:14-59,145-323` | `app/lib/src/screens/production/image_flow_editor.dart:84-210,589-625,959-1017` |
| 上传节点 | `.../editImage/uploadNode.vue:3-47,100-124` | `image_flow_editor.dart:363-464,628-686` |
| 生成节点 | `.../editImage/generatedNode.vue:23-205` | `image_flow_editor.dart:466-586,804-956` |
| 流数据 | `/production/editImage/*` 路由 + `o_imageFlow` | `app/lib/src/engine/image_flow.dart:76-142` |

## 用户动作逐项对照

| 用户动作 | ToonFlow 当前行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 在资产节点浏览资产 | 原始资产卡与派生资产卡按父子关系同屏展示，分别呈现未生成、生成中、失败、完成 | `assetsByIds` 读取直接子项，节点按原始资产分组显示衍生横向条；无子项有明确空态，生成中与无图均有稳定缩略图占位 | 已验证等价 |
| 编辑派生资产 | 点击派生资产，以原始资产为参考图初始化图片流；应用结果回写派生资产 URL 和 flowId | 只允许点击衍生项；父图作为上传参考，已有衍生图/提示词作为生成结果种子，应用结果经 `attachAssetImage(derived.id)` 回写子项与 flowId | 已验证等价 |
| 删除派生资产 | 派生卡有独立删除确认，删除该子资产 | 衍生项有独立图标与确认；仅对该子 id 调用 `deleteAssets`，复用已验证的关联/图片流清理 | 已验证等价 |
| 流图保存/恢复 | 保存或更新 `o_imageFlow.flowData`，载入后恢复节点、边、位置 | `saveImageFlow/getImageFlow` 等价保存/恢复 | 已验证等价 |
| 图片流节点拖动 | VueFlow 默认允许拖动节点；生成节点展开的 `.parameter` 以 `@wheel.stop @mousedown.stop` 防止表单区域触发节点移动或画布滚轮操作 | `DFCanvasDragRegion` 让上传节点整卡、生成节点标题/图片区移动节点；生成参数区以 `movesNode:false` 保留输入手势且不改节点/视口坐标。普通卡片区域会将滚轮信号透传给画布，参数区则有回归保证继续拦截，和原版的两种区域语义一致。 | 已验证等价 |
| 连线同步参考 | 所有入边来源图同步到生成节点 `references`，阻止自连/重复/反向重复 | 上传和已生成节点都可作来源、生成节点可作目标；同步所有入边来源，拦截自连、同向与反向重复。桌面和 390dp 均已保存回归。 | 已验证等价 |
| 上传节点选择参考 | 从资产图或分镜图选取；可“保存”当前参考图为最终结果 | 从本地、资产库、分镜三处选择；有图时保存会回写当前资产或分镜并保存图片流。 | 已验证等价 |
| 生成节点图片种子 | 可从资产、分镜或本地上传，直接把图片设为生成节点结果，再保存应用 | 同一三来源选择器可直接写入 `generatedImage`，再沿用保存/应用出口；同时可生成、重绘或局部重绘。 | 已验证等价 |
| 生成图片 | 提示词 + 模型 + 画幅 + 清晰度 + 全部参考图，同步请求 | 同一组校验与多参考同步请求；额外有重绘/局部重绘 | 已验证等价 |
| 关闭编辑器 | 二次确认；已有 flow 时关闭前保存图结构 | `PopScope` 与关闭按钮统一走二次确认；已有 `flowId` 同步回写，未显式保存的新图不会创建空记录。 | 已验证等价 |
| 图自动排布 | 提供 LR 自动布局并适配视口 | 按当前有向边的稳定拓扑层级重排为 LR，循环图确定性降级，再调用 `fitView()`；桌面与 390dp 均有回归。 | 已验证等价 |

## 已验证的核心证据

本轮重新运行以下测试：

```sh
cd app
flutter test --concurrency=1 \
  test/engine/image_flow_test.dart \
  test/widgets/image_flow_editor_test.dart \
  test/widgets/production_screen_test.dart
```

本轮额外锁定了三条节点级回归：引擎查询不丢失子项；桌面父/子层级、已有结果种子、
编辑与删除确认可完整走通；390dp 的资产 Tab 同样可见且没有布局异常。下方命令实际
通过 **78 项测试**，`flutter analyze` 为零问题。测试图像调用均为 fake gateway，
本地临时图片仅用于组件渲染；没有调用真实图像或视频供应商。

## 删除生命周期复验（2026-07-19）

`o_imageFlow` 没有外键，不能依赖 SQLite 自动级联。现在所有会删除其归属对象的
引擎路径都会先收集候选 `flowId`，删除资产或分镜后，再由
`image_flow_cleanup.dart` 只删除已不被 `o_assets` 和 `o_storyboard` 任一行引用的
流程。这样既对齐 ToonFlow 删除派生资产、删除分镜和替换分镜时清理图片流的行为，
也能保护导入历史数据中意外共用的流程。

覆盖入口包括：资产及其子资产删除、音频资产编辑时替换旧子项、单条或批量分镜删除、
剧本删除、项目删除，以及“重新生成分镜”验证通过后的原子替换。单条分镜删除还按
ToonFlow `removeFrame` 语义删除已空的视频轨；批量删除保留 `batchDelete` 不主动删空轨的
原始差异。

定向引擎回归覆盖五条主删除链和两个边界：替换验证失败时旧流程仍存在、共享 `flowId`
在另一资产仍引用时被保留。命令为：

```bash
cd app
flutter test --concurrency=1 test/engine/assets_test.dart test/engine/storyboard_test.dart test/engine/scripts_test.dart test/engine/projects_test.dart
```

## 验收记录（2026-07-21）

```sh
cd app
flutter test --concurrency=1 \
  test/engine/image_flow_test.dart \
  test/engine/assets_test.dart \
  test/widgets/image_flow_editor_test.dart \
  test/widgets/production_screen_test.dart
flutter analyze
```

此批次没有真实供应商调用，也没有提交、轮询或下载任何视频。剩余相关功能只剩
`W7B-ASSETS-GEN-001` 的“父图自动参考 + 子资产批量派生出图”合并任务；它与本页
已经验收的手工图片流编辑不是同一用户动作。
