# 项目创建向导对照

更新时间：2026-07-19

基线：ToonFlow 1.1.8 的 `Toonflow-web/src/views/project/components/projectDialog.vue`，以及项目列表页 `Toonflow-web/src/views/project/index.vue`。

这份记录只比较用户真正经过的“新建或编辑项目 → 打开项目”旅程。它不因 Flutter 已有相同字段或能够写入 SQLite，就把未被阻止的无效项目算作等价。

## 结论先行

Flutter 已承接双栏表单、项目字段存储、视觉/导演手册画廊及其编辑、十项保存校验，以及打开项目前的本地模型可用性保护；模块仍因无模型引导和默认手册标题两个可见缺口维持“部分实现”。

| 旅程环节 | ToonFlow 可观察行为与证据 | DramaFlow 现状与证据 | 状态 |
| --- | --- | --- | --- |
| 表单布局 | 左栏依次展示项目类型、名称、题材、图片模型+清晰度、视频模型+模式、比例、简介；右栏为视觉手册和导演手册画廊，`projectDialog.vue:13-134` | 同一字段和两套画廊位于 `app/lib/src/screens/project/project_dialog.dart:194-337`；可用宽度小于 700 时切为单列，`:346-367` | 已承接 |
| 项目类型 | 可选择“基于小说原文”或“基于剧本”，`projectDialog.vue:16-20` | `novel` / `script` 下拉，`project_dialog.dart:198-210` | 已承接 |
| 模型与视频模式 | 图片、视频模型各有选择器；视频模型变化后刷新可选模式，`projectDialog.vue:28-47` | `ModelSelect` 按 `image` / `video` 过滤；模型 capability 驱动模式选择，`project_dialog.dart:69-86,221-288` | 已承接 |
| 无模型引导 | 原版选择器为空时展示“去设置”动作，点击直接打开供应商配置，`Toonflow-web/src/components/modelSelect.vue:24-31,158-162` | Flutter `ModelSelect` 在无候选时只显示空下拉框，`app/lib/src/screens/project/model_select.dart:54-79`；用户无法从当前向导跳转到模型配置 | 缺失 |
| 视觉/导演手册 | 画廊选中、创建、编辑、删除、封面预览，`projectDialog.vue:60-131` | `ManualGallery` 选中、创建、编辑、删除均接到本地引擎，`project_dialog.dart:299-337` | 已承接 |
| 字段持久化 | 确认时将 11 个表单字段提交给 add/edit，`projectDialog.vue:432-460` | 新建与编辑均将 11 项传给 `Engine.addProject/editProject`，`project_dialog.dart:108-150`；引擎 CRUD 回归覆盖，`app/test/engine/projects_test.dart:36-90` | 已承接 |
| 保存前校验 | 原版依序拒绝：名称、题材、图片模型、视频模型、视觉手册、导演手册、视频比例、简介、图片清晰度、视频模式，`projectDialog.vue:421-431` | `firstMissingProjectIntakeField()` 以相同顺序检查十项，`project_dialog.dart:20-62`；保存时显示本地化首个错误并保持对话框打开，`:108-152`。纯函数回归覆盖十项顺序，桌面向导回归覆盖名称与题材拦截 | 已验证 |
| 打开项目保护 | 项目卡片被点击时，原版先检查 image/video binding 非空且该模型仍可由启用供应商解析；不满足时提示并打开编辑，`Toonflow-web/src/views/project/index.vue:92-121` | `Engine.projectModelsAvailable()` 只解析本地已启用绑定，`engine.dart:995-1011`；`_openProject()` 阻断失效绑定、提示并打开编辑，`project_list_screen.dart:33-52`。引擎回归覆盖禁用模型，widget 回归覆盖失效项目不路由 | 已验证 |
| 手册名称 | 原版视觉手册名称来自每包 README 首行；见 `Toonflow-app/src/routes/project/getVisualManual.ts:65-66` | 内置包无 `meta.json` 时回退技术目录名；详细证据已记于 `master-checklist.md` 的 `W9B-ARTSKILLS-001` | 缺失 |

## 跨端验证现状

- 桌面：`app/test/widgets/project_page_test.dart` 覆盖空态、有效模型卡片打开、失效模型阻断并进入编辑、鼠标悬停编辑删除、手册编辑入口和十项校验的前两步；`app/test/widgets/project_intake_validation_test.dart` 覆盖十项固定顺序。
- 移动端：同文件以 390×760 点选全套字段、滚动至两类手册并保存；失效图片/视频绑定同样只能打开编辑而不能进入小说页；另覆盖触控场景的编辑删除与平板宽度。
- 这些回归使用内存 SQLite、本地模型记录和假网关；只验证字段、绑定解析和路由阻断，不调用文本、图像或视频供应商。

## 默认视觉手册基线（2026-07-19）

这里的“默认画风”是随项目提供的视觉手册包，不是 `o_artStyle` 的用户自建画风卡。原版
`o_artStyle` 只有新增、读取和编辑路由，没有首启插入默认卡片的路径；把视觉手册复制成另一套
数据库卡片会产生两份内容来源，反而偏离原版。

DramaFlow 将相同类型的资源随包保存为
`app/assets/default_skills/toonflow_default_skills.zip`，`pubspec.yaml` 已声明该资源，首启通过
`seedBundledDefaultSkills()` 按文件补齐到本地 `skills/` 目录。资源库存为 11 套
`art_skills` 视觉手册与 12 套 `story_skills` 导演手册；压缩包 SHA-256 为
`7101fc169dbb22065b3409c749f82bb00693d1142fa1e5a3835fd7f80c23ff35`。

可重复的离线验证命令：

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/bootstrap/bootstrap_io_test.dart \
  test/engine/manuals_test.dart \
  test/widgets/manual_gallery_test.dart \
  test/widgets/project_page_test.dart \
  test/engine/art_style_test.dart \
  test/widgets/art_style_library_test.dart
```

结果：28 项通过，覆盖首启按文件补齐且不覆盖用户编辑、手册读写与封面、画廊预览，以及
390dp 和 800dp 触控宽度下无需 hover 的编辑/删除操作。该测试集不调用任何文本、图像或视频
供应商。

仍未达到等价的地方必须单独保留：原版画廊从每个 `README.md` 的首行派生可读标题；当前
Flutter 内置包没有 `meta.json` 时回退显示技术目录名。这会使用户看到
`2D_chinese_guofeng` 一类标识，而不是“国风二次元新国潮风格说明”等标题。后续修复应只补
安全的 README 标题提取与测试，不把视觉手册再复制成 `o_artStyle` 默认数据。

### 生成消费证据

视觉手册不是只供画廊展示。`resolvePrompt()` 会按“基础模板 → 指定视觉章节 → 指定导演章节
→ 模型模板”的顺序组装系统提示词，并在任务元数据中只记录来源 ID、类型和内容 SHA-256。
素材润色会根据角色、场景、道具及其衍生关系选择相应的 `art_*` 章节；手册章节缺失或任务
私有要求文件被篡改时，会在任何模型调用前报错并关闭任务。

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/engine/prompt_resolver_test.dart \
  test/engine/assets_test.dart
```

结果：26 项通过。测试使用内存 SQLite、临时文件和假网关，未调用真实文本、图像或视频供应商。
这项证据只确认视觉手册的解析、溯源和失败保护；视频生成仍按项目约束留给你进行真实验收。

## 后续实施边界

1. 没有可选图片或视频模型时，在相应选择器给出到“供应商”设置区的明确动作；不重复实现供应商编辑表单。
2. 从默认手册的 `README.md` 首行派生可读标题，保持与 ToonFlow 的画廊命名一致。
3. 项目直接 CRUD 保持对导入和恢复记录的宽容性；十项非空限制属于用户向导契约，不能借此改变底层数据修复能力。
4. 入口保护的桌面与 390dp 回归只查询本地绑定并使用假网关；绝不提交真实视频任务。

## 关联记录

- 总清单：[`master-checklist.md`](master-checklist.md) 的 `W6-PROJECT-001`、`W6F-PROJECT-DIALOG-001`、`W9B-ARTSKILLS-001`。
- 画风包逐文件记录：[`../superpowers/acceptance/`](../superpowers/acceptance/) 中的对应资产证据，以及 `W9B-ARTSKILLS-001` 的逐文件 SHA-256 说明。
