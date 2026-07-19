# 模型提示词文件库与绑定等价设计

## 目标

恢复 ToonFlow `modelMap` 的完整、可观察工作流：用户维护一组可复用的图像或视频 Markdown 提示词模板，并把其中任意一份绑定或解绑到已启用供应商的对应模型。模板修改后，已绑定模型应立即使用新内容。

这项工作直接覆盖此前 Seedance 模板因运行目录与源码目录不同步而错误回退的风险。它只实现本地模板管理、解析和 UI；不提交、轮询或测试任何视频生成请求。

## 原版行为基线

- `/Users/luke/Documents/aivideo/Toonflow-web/src/components/setting/components/modelMap.vue`
  - 展示供应商下模型及当前绑定。
  - 打开一个模型后可查看模板库、新建、编辑、删除、选择绑定或解绑。
- `/Users/luke/Documents/aivideo/Toonflow-app/src/routes/setting/modelMap/*.ts`
  - 模板正文以 `modelPrompt/{image|video}/{name}.md` 文件保存。
  - `o_modelPrompt` 仅保存 `vendorId/model/fileName/path` 映射；运行时按路径读取当前文件内容。

原版 `getImageAndVideoModel` 实际只列视频模型，和其名称、模板类型定义不一致。DramaFlow 将支持图像和视频两种已有模型类型，这是已验证的用户可见修正，不复制该筛选缺陷。

## 数据与解析

Flutter 应用没有 Electron 运行目录的可靠共享语义，因此使用本地数据库的模板库替代 `.md` 目录：

```text
o_modelPromptTemplate
  path TEXT PRIMARY KEY        // image/{name}.md 或 video/{name}.md
  name TEXT NOT NULL
  kind TEXT NOT NULL           // image 或 video
  prompt TEXT NOT NULL
  createTime INTEGER NOT NULL
  updateTime INTEGER NOT NULL

o_modelPrompt                 // 既有映射，保持兼容
  vendorId + model + path -> fileName + prompt
```

- 每次启动把旧 `o_modelPrompt` 中的唯一 `path` 回填为模板库条目，确保已存在的 Seedance 映射不会丢失。
- 新建、更新、删除和绑定在本地事务内完成；更新会同步所有同路径映射的 `prompt`，删除会原子解绑所有引用该模板的模型。
- 模板路径只允许 `image/<安全文件名>.md` 和 `video/<安全文件名>.md`，禁止 `/`、`\\`、控制字符、空白名称和路径穿越。
- `resolvePrompt` 仍以既有 `o_modelPrompt.prompt` 解析；同步策略让既有流水线和导入数据不需要分叉。
- 配置导出包含 `modelPromptTemplates`；导入先恢复模板库、再恢复映射，兼容没有该字段的旧备份。

## 界面与响应式行为

- 设置的“提示词”区保留既有全局提示词编辑器。
- “模型专属模板”改为按供应商分组的模型列表，显示当前绑定或未绑定状态；只列已启用且类型为 image/video 的模型。
- 进入模型编辑页后：可从同类型模板库选择、解绑、新建、编辑或删除模板。删除由共享破坏性确认流程保护，并说明会解除哪些模型的绑定。
- 在桌面上使用双栏“模型 / 模板库”布局；在小于 `840dp` 的壳内将模型详情和模板编辑器推为全屏页面，所有命令保持可达。
- 所有文字走现有 zh/en/ja 本地化；按钮使用现有图标和 tooltip，不引入新的视觉系统。

## 验收边界

1. 引擎测试覆盖旧映射迁移、创建/更新/删除、同路径同步、图像/视频类型校验、绑定/解绑和导入导出兼容。
2. Widget 测试分别从桌面和 `390dp` 设置入口完成“新建模板 -> 绑定 -> 编辑 -> 生效 -> 解绑”；测试使用内存 SQLite 和假网关。
3. 仅验证 `resolvePrompt` 的本地返回内容；禁止真实文本、图片、语音或视频供应商调用。
4. 通过后，`W6D-MODELMAP-001`、`W7A-MODELMAP-001` 和 `W9A-DBTABLE-MODELPROMPT-001` 才可从“部分实现”改为已验证等价。

