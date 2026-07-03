# P3 制作画布 + 分镜表 + 节点式图片编辑器移植参照（源码取材固化版，2026-07-03）

来源：Toonflow-web/src/views/production/*（index/node/{scriptPlan,poster,workbench,
storyboardTable,script,storyboard,assets}/components/{editImage,rightChatBox}）
+ Toonflow-app/src/routes/production/*。实现时以本文为准，缺细节再回源码。

## §1 画布架构（@vue-flow/core → Flutter InteractiveViewer+CustomPainter）
- 缩放 0.1–10；空格+左键拖拽平移（自定义，非标准 VueFlow 行为）；边不可编辑；双击不缩放；
  拖拽/平移期间 `is-interacting` 标记降级渲染（隐藏 hover 特效、图片 `contain:strict`）。
- **7 种节点**（水平主链 + assets 挂在 script 下方，防碰撞右移）：
  | 节点 | 内容 | 位置(初始) |
  |---|---|---|
  | script | 剧本 markdown 预览+编辑弹窗 | x:0,y:0 |
  | scriptPlan | 剧本规划 markdown | x:900,y:0 |
  | assets | 资产卡片网格（原始/衍生 tag，缩略图+状态） | x:1200,y:4000（挂 script 下方）|
  | storyboardTable | 分镜表 markdown 预览 | x:1800,y:0 |
  | storyboard | **分镜网格**（详见 §2） | x:2500,y:0 |
  | workbench | 视频预览卡（封面+播放图标，点开工作台弹窗） | x:3000,y:0 |
  | poster | 已禁用（未来功能，DramaFlow 不做）| — |
- 边（黑色实线，无箭头，不动画）：script→assets, script→scriptPlan, scriptPlan→storyboardTable,
  storyboardTable→storyboard, storyboard→workbench。
- 布局：默认手动 LR 链式（节点间距 80px），dagre 仅 TB 方向用（DramaFlow 只做 LR，足够）；
  初始 fitView。
- `o_imageFlow`/getFlowData 语义：DramaFlow 用 `o_project` 关联的画布状态表存节点位置+边（新表
  或复用 o_imageFlow 语义，P3 任务卡里定）。

## §2 分镜（storyboard）子系统——本批重点
- **网格**：卡片 200×200px（可缩放 0.1–3，本地持久化），每卡：复选框(左上)/彩色编号 tag
  "S01"-"S99"(8色轮换)/图片(contain)/删除按钮(右上)/编辑按钮(左下，编辑 prompt+videoDesc)/
  左右两侧悬停展开"+"插入按钮(在相邻两镜间插入新镜，打开图片编辑器 modal，参考图=前后两镜)。
- 控制栏：缩放滑块/已选计数"已选择 N 个"/清空选择/全选/**批量删除**/**整体预览**(拼图)/
  **生成图片**(批量)。
- **状态枚举**（照抄，中文字符串）：`未生成`/`生成中`/`已完成`/`生成失败`。
- **batchAddStoryboardInfo**（剧本→分镜生成，LLM 产出后落库）：批量 INSERT o_storyboard
  {prompt,duration,track,state,videoDesc,shouldGenerateImage,associateAssetsIds}+
  o_assets2Storyboard 关联；按 track 名分组创建/复用 o_videoTrack 累加时长。
- **batchGenerateImage**（首帧图生成，本批核心）：
  1. 选中分镜置 `生成中`（`shouldGenerateImage!=0` 过滤，除非 compulsory=true）。
  2. 关联资产（经 o_assets2Storyboard→o_assets→o_image）取图片转 base64 作为 referenceList。
  3. 生图调用：prompt=分镜 prompt，size=项目 imageQuality，aspectRatio=项目 videoRatio。
  4. 并发默认 5（DramaFlow 复用 asset_image_generation 同款并发+队列+中文状态枚举模式）。
  5. 成功：filePath+state=已完成；失败：state=生成失败+reason。
- **单镜编辑**：editStoryboardInfo{id,prompt,videoDesc}。
- **插入分镜**：addStoryboard（新建一行，插入本地数组指定位置）。
- **预览/下载**：previewImage(拼接全部帧为一张网格图)/downPreviewImage(下载二进制)——
  DramaFlow 用 Flutter Canvas 本地拼图，不走后端。

## §3 节点式图片编辑器（editImage）——本批核心
- 独立 VueFlow 实例，全屏弹窗。2 种节点：`upload`（参考图输入）/`generated`（AI 生成+可选中显示参数面板）；
  1 种自定义边 `removeLine`（中点显示删除按钮的贝塞尔曲线）。
- **uploadNode**：320px 卡，标题栏+图片区(320×320 contain)+上传下拉("资产图片"/"分镜图片")+
  保存按钮(emit keep)+删除；仅一个右侧 source handle。
- **generatedNode**：320px 卡，标题栏+图片区(生成中转圈/完成态描边高亮)+上传下拉+删除；
  **选中时展开参数面板**：参考图缩略条(45px)/提示词编辑区/模型选择/画质(1K/2K/4K)/画幅(16:9/9:16/1:1)/
  生成按钮(生成中禁用)/保存按钮。数据结构：`{generatedImage?, references:[{image}], prompt, model?, ratio?, quality?, steps}`。
  一个左侧 target handle（接收上游）+ 一个右侧 source handle（可继续连出）。
- **连接规则**：禁自环、禁重复边（双向检查）；连接自动挂 `removeLine` 类型边。
- **syncReferences（防抖 60ms）**：每个 generated 节点根据其入边收集上游 upload/generated 节点的
  图片，写入 `references` 数组（仅变化时更新，O(n) diff）——这是"参考图随连线自动汇总"的核心机制，
  DramaFlow 必须复刻此行为（不是静态选择参考图，而是画布连线驱动）。
- **持久化**：getImageFlow/saveImageFlow/updateImageFlow，序列化仅保留 `{id,type,position,data}`
  （剥离 VueFlow 内部字段；generated 节点序列化时丢弃 `steps`）。
- **生成后端语义**（generateFlowImage，本批照抄进 Dart）：
  1. 入参：references(URL/相对路径数组)、prompt、model、quality、ratio、projectId。
  2. 每个 reference 转 base64（DramaFlow：本地文件直接读取，无需网络转换）。
  3. `referenceList=[{type:image,base64}]`、prompt、size、aspectRatio 调生图供应商。
  4. 落盘路径 `{projectId}/workFlow/{uuid}.jpg`（复用 MediaStore）。
  5. 返回图片 URL/相对路径，回填该节点 `generatedImage`。

## §4 rightChatBox（Agent 对话框）—— P3 只做最小占位
- 完整实现（WebSocket 流式、o_agentDeploy 绑定、记忆清空菜单、建议动作）**归属 P5**，与 spec
  §4 Agent 体系设计一致。
- **P3 最小占位**：静态侧栏，输入框禁用+提示"Agent 对话在后续批次开放"，不接任何后端；
  仅占位面板结构（可展开/收起），为 P5 预留挂载点。

## §5 i18n 键盘点
`workbench.production.*` 命名空间体量大（300+ 键，含节点标题/按钮/对话框/引导提示/editImage/
chatBox 子命名空间），DramaFlow 按 P2 惯例自行补齐三语（zh 参照上文中文术语，en/ja 自译），
键名规约：`productionNodeStoryboardXxx` / `productionEditImageXxx` / `productionChatBoxXxx`。

## §6 Flutter 落地对照表
| VueFlow 能力 | Flutter 方案 |
|---|---|
| 节点渲染 | 每种节点一个 StatefulWidget，`Positioned` 摆放在 `Stack` 内 |
| 拖拽 | `GestureDetector.onPanUpdate` 更新节点 position，`setState` |
| 平移缩放 | `InteractiveViewer`（`minScale:0.1, maxScale:10, constrained:false`） |
| 贝塞尔边 | `CustomPainter` + `Path.cubicTo`，删除按钮用 `Positioned` 叠在中点 |
| 背景网格 | `CustomPainter` 画点/线 |
| 选中态 | 节点内部 `isSelected` 状态位，重绘描边 |
| 连接手柄 | 自绘小圆点 + 拖拽预览线 + drop 命中检测 |
| 自动布局 | 手动 LR 链式布局函数（不需要移植 dagre，主链够用）|
| 性能 | `RepaintBoundary` 包节点；仅渲染视口内节点/边（视口裁剪） |

## 执行边界（写入 P3 计划自查）
- 分镜生成/生图管线复用 P1/P2 的队列+中文状态枚举+冷启动恢复模式（不重新发明）。
- 图片编辑器的"连线驱动参考图汇总"（syncReferences）是唯一必须逐一复刻的非显然机制——
  测试要单独覆盖："连接 upload→generated 后 generated.references 自动更新"。
- Agent 对话框 P3 只做外壳占位，不接生成动作，不算功能缺失（P5 补齐）。
