# P2 素材子系统移植参照（源码取材固化版，2026-07-03）

来源：Toonflow-web/src/views/assets/*（index/addAssets/addAudioAssets/generateImage/batchGeneration）
+ Toonflow-app/src/routes/{assets,assetsGenerate}/*。实现时以本文为准，缺细节再回源码。

## 页面结构（index.vue）
- **5 tabs**：role 角色 / tool 道具 / scene 场景 / clip 素材 / audio 音频。
- 工具栏：`新增{tab名}`（primary）；批量菜单（clip/audio 禁用）：`生成提示词`→批量对话框模式1、`生成图片`→模式2；`批量删除`；搜索框+搜索钮。
- 父资产表列：复选50/预览100（80px 缩略图，生成中转圈遮罩）/名称100/提示词200（promptState=生成中 → 斜体"生成中..."+小转圈）/描述200/备注 min200/创建时间200（YYYY-MM-DD HH:mm:ss）/操作280（生成/编辑/删除，生成中禁用）。
- **子资产**：行可展开（最多同时展开 3 行）显示 sonAssets（assetsId=父 id 的 o_assets），列同父但无创建时间。
- audio 表列：复选/音色(name)/性别(sex)/描述/时间/操作；展开子音频：复选/预览(音乐图标+悬停播放)/音频文本(prompt)/操作。
- 分页 page/limit 默认 10；搜索 name LIKE；换 tab 清搜索。
- **状态枚举（DB 中文字符串，逐字）**：o_assets.promptState 与 o_image.state ∈ "生成中"/"已完成"/"生成失败"。

## 对话框
### addAssets：名称*（必填）/描述*（必填）/备注/提示词（clip 隐藏）。新增 POST addAssets{name,describe,type,projectId,remark,prompt,startTime=now}；编辑 updateAssets{id,name,describe,remark,prompt}。
### generateImage（单资产生图，左40%右60%）
- 左：参考图上传（可选，t-tag"可选"）；提示词 textarea 15 行 + **智能生成**按钮→polishAssetsPrompt；模型选择(image kind)；分辨率 1K/2K/4K（默认1K）；生成按钮（校验 prompt/模型/分辨率）。
- 右：结果图网格 180px（生成中转圈遮罩/失败红X/完成可选中黑框）+ 悬停预览/选中勾/删除(delImage)；自定义上传格（+，base64 入列表 state=已完成）；计数 tag"已生成 {count} 张"；**确定**（无选中禁用）→saveAssets{id,base64?,type,prompt,projectId,imageId?}。
- 轮询语义：getImage{assetsId}→{id,imageId,tempAssets:[{id,filePath,state,selected=imageId==id}]}（DramaFlow 用队列事件替代轮询）。
### addAudioAssets：音色*（name）/描述*/性别；动态音频条目数组[{上传音频文件, 音频文本(text→prompt), 描述}]，可增删；提交 describe="性别|描述" 管道拼接；addAudioAssets 落父 o_assets(type=audio)+每条子 o_assets(assetsId=父,prompt=text)+o_image(filePath=音频路径,type=audio,state=已完成)+子.imageId。音频扩展名 mp3/wav/m4a/flac/aiff。
### batchGeneration（批量对话框，模式1提示词/模式2图片）
- 工具栏：已选{count}/全选/清空/搜索/生成提示词钮/生成图片钮；表列：复选/预览图100/名称150/提示词（**行内可编辑 textarea**）。
- 数据源 batchGenerationData{projectId,type,name,page,limit}（分页）。
- 批量提示词：按并发数（设置 assetsBatchGenereateSize 默认5）逐个 polish；批量图片：过滤空提示词，逐个 generateAssets；p-limit 并发；取消=标志位（已发出的继续但忽略结果）→DramaFlow 用队列取消语义替代。
- 底部：取消 / 保存已选({count})→逐项 updateAssets(+saveAssets)。

## 生成管线（引擎侧移植要点）
### polishAssetsPrompt（提示词润色）
1. promptState=生成中。2. 读项目 artStyle（=视觉手册名）。3. typeConfig：role→{label:"角色标准四视图",nameLabel:"角色",manualKey: 父资产 art_character / 子资产 art_character_derivative}；scene→art_scene(_derivative)，nameLabel 场景；tool→art_prop(_derivative)，nameLabel 道具。
4. **system = 视觉手册对应 key 的 md 内容**（DramaFlow：ManualPack(name==artStyle).data[manualKey]）。
5. **user 模板逐字**：`**基础参数：**\n**{nameLabel}设定：**\n- {nameLabel}名称:{name},\n- {nameLabel}描述:{describe},`
6. 成功：prompt=文本，promptState=已完成，promptErrorReason=NULL；失败：生成失败+原因（DramaFlow 存 errKey JSON）。
- 批量版：items 预置生成中→并发→同上；system 追加 "\n"+otherTextPrompt（可选）。

### generateAssets（生图）
1. typeConfig：role→{taskClass:"角色图生成",dir:"role",promptTitle:"角色标准四视图",promptEnd:"人物角色四视图"}；scene→{场景图生成,scene,标准场景图,标准场景图}；tool→{道具图生成,props,标准道具图,标准道具图}。
2. 预插 o_image{type,state=生成中,assetsId,model,resolution}；o_assets.imageId=新图。
3. **user prompt 模板逐字**：
```
请根据以下参数生成{promptTitle}：

**基础参数：**
- 画风风格: {artStyle}

**{label}设定：**
- 名称:{name},
- 提示词:{prompt},

请严格按照系统规范生成{promptEnd}。
```
4. 图片调用：referenceList=[{type:image,base64}]（有参考图时）、size=resolution、aspectRatio=项目 videoRatio（ToonFlow 写死 16:9，DramaFlow 用项目 videoRatio 更正确，记偏差）。
5. 成功：o_image{state=已完成,filePath}；失败：{state=生成失败,errorReason}。
6. 图片路径 `{projectId}/{dir}/{uuid}.jpg|png`（走 MediaStore）。
- 批量版：预插全部 o_image 生成中→并发→逐个同上；taskClass 中文照抄（o_tasks.taskClass："角色图生成"/"场景图生成"/"道具图生成"——注意 ToonFlow此处用中文 taskClass，与 P1 的 event_generation 英文风格不同；DramaFlow 统一策略：taskClass 用英文 `asset_prompt_polish`/`asset_image_generation`，describe 存中文标签，记偏差）。

## 其它端点语义
- getAssetsApi：父资产（assetsId IS NULL）分页 + LEFT JOIN o_image(imageId)取 filePath/state + sonAssets 子查询；audio 的 sex=describe.split("|")[0]。
- delImage{id}: o_assets.imageId 置 NULL where imageId=id → 删 o_image 行 → 删文件。
- delAssets/batchDelete：删资产（连带其 o_image 版本与文件、子资产）。
- pollingPromptAssets/pollingImageAssets：state != 生成中 过滤（工具用）。
- saveAssets：base64→存文件+插 o_image(已完成)+更新 imageId+prompt；imageId→仅更新。

## i18n 注意
ToonFlow zh-CN.json 的 workbench.assets 仅 10 键，70+ 键缺失（代码里 $t 直接落空）。DramaFlow 需自行补全三语（zh 按上文中文文案，en/ja 自译），键名规约 assetsXxx / assetsAddXxx / assetsGenXxx / assetsBatchXxx。
