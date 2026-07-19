# 项目创建向导对照

更新时间：2026-07-19

基线：ToonFlow 1.1.8 的 `Toonflow-web/src/views/project/components/projectDialog.vue`，以及项目列表页 `Toonflow-web/src/views/project/index.vue`。

这份记录只比较用户真正经过的“新建或编辑项目 → 打开项目”旅程。它不因 Flutter 已有相同字段或能够写入 SQLite，就把未被阻止的无效项目算作等价。

## 结论先行

Flutter 已承接双栏表单、项目字段存储、视觉/导演手册画廊及其编辑、桌面和 390dp 移动端单列可达性；但**保存前的完整性校验**和**打开项目时的模型可用性保护**尚未承接。因此本模块维持“部分实现”。

| 旅程环节 | ToonFlow 可观察行为与证据 | DramaFlow 现状与证据 | 状态 |
| --- | --- | --- | --- |
| 表单布局 | 左栏依次展示项目类型、名称、题材、图片模型+清晰度、视频模型+模式、比例、简介；右栏为视觉手册和导演手册画廊，`projectDialog.vue:13-134` | 同一字段和两套画廊位于 `app/lib/src/screens/project/project_dialog.dart:194-337`；可用宽度小于 700 时切为单列，`:346-367` | 已承接 |
| 项目类型 | 可选择“基于小说原文”或“基于剧本”，`projectDialog.vue:16-20` | `novel` / `script` 下拉，`project_dialog.dart:198-210` | 已承接 |
| 模型与视频模式 | 图片、视频模型各有选择器；视频模型变化后刷新可选模式，`projectDialog.vue:28-47` | `ModelSelect` 按 `image` / `video` 过滤；模型 capability 驱动模式选择，`project_dialog.dart:69-86,221-288` | 已承接 |
| 无模型引导 | 原版选择器为空时展示“去设置”动作，点击直接打开供应商配置，`Toonflow-web/src/components/modelSelect.vue:24-31,158-162` | Flutter `ModelSelect` 在无候选时只显示空下拉框，`app/lib/src/screens/project/model_select.dart:54-79`；用户无法从当前向导跳转到模型配置 | 缺失 |
| 视觉/导演手册 | 画廊选中、创建、编辑、删除、封面预览，`projectDialog.vue:60-131` | `ManualGallery` 选中、创建、编辑、删除均接到本地引擎，`project_dialog.dart:299-337` | 已承接 |
| 字段持久化 | 确认时将 11 个表单字段提交给 add/edit，`projectDialog.vue:432-460` | 新建与编辑均将 11 项传给 `Engine.addProject/editProject`，`project_dialog.dart:108-150`；引擎 CRUD 回归覆盖，`app/test/engine/projects_test.dart:36-90` | 已承接 |
| 保存前校验 | 原版依序拒绝：名称、题材、图片模型、视频模型、视觉手册、导演手册、视频比例、简介、图片清晰度、视频模式，`projectDialog.vue:421-431` | 当前只拒绝空名称，`project_dialog.dart:108-113`。其余任意缺失值都能保存为后续流水线会失败的项目 | 缺失 |
| 打开项目保护 | 项目卡片被点击时，原版先检查 image/video binding 非空且该模型仍可由启用供应商解析；不满足时提示并打开编辑，`Toonflow-web/src/views/project/index.vue:92-121` | Flutter 项目卡直接选择项目并路由；现有 widget 回归专门以无模型项目成功跳转，`project_page_test.dart:82-98` | 缺失 |
| 手册名称 | 原版视觉手册名称来自每包 README 首行；见 `Toonflow-app/src/routes/project/getVisualManual.ts:65-66` | 内置包无 `meta.json` 时回退技术目录名；详细证据已记于 `master-checklist.md` 的 `W9B-ARTSKILLS-001` | 缺失 |

## 跨端验证现状

- 桌面：`app/test/widgets/project_page_test.dart` 覆盖空态、卡片打开、鼠标悬停编辑删除、手册编辑入口和名称必填。
- 移动端：同文件 `:218-315` 使用 390×760 真实点选全套字段、滚动至两类手册并保存；`:336-388` 覆盖触控场景的编辑删除与平板宽度。
- 这些回归证明控件可到达且保存完整表单不会溢出，**不**证明缺失字段会被阻止。因此不能用“完整保存用例通过”替代完整性校验的验收。

## 后续实施边界

1. 新建和编辑共用一套按原版顺序的字段校验，逐项使用本地化提示；保留目前默认项目类型、比例、清晰度的初始值。
2. 没有可选图片或视频模型时，在相应选择器给出到“供应商”设置区的明确动作；不重复实现供应商编辑表单。
3. 项目卡入口在路由前解析已绑定的图片和视频模型；模型为空、禁用、供应商不可用或型号被删除时，不进入工作区，转为提示并打开该项目编辑。
4. 校验既要有引擎级模型解析测试，也要有桌面和 390dp widget 回归；视频只验证本地模型解析和路由阻断，绝不提交真实视频任务。
5. 视觉/导演手册的创建、编辑和删除不在本批次重写，除非实现入口保护时发现确实影响其选择值。

## 关联记录

- 总清单：[`master-checklist.md`](master-checklist.md) 的 `W6-PROJECT-001`、`W6F-PROJECT-DIALOG-001`、`W9B-ARTSKILLS-001`。
- 画风包逐文件记录：[`../superpowers/acceptance/`](../superpowers/acceptance/) 中的对应资产证据，以及 `W9B-ARTSKILLS-001` 的逐文件 SHA-256 说明。
