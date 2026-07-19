# 模型提示词文件库与绑定等价实施计划

> **For agentic workers:** Use `superpowers:subagent-driven-development`. Each task is implemented by a fresh worker, independently reviewed, and only then committed. Keep user-owned uncommitted files outside the task scope.

**Goal:** 把设置中的模型提示词从“仅能编辑已绑定的一条正文”补齐为 ToonFlow 的可复用模板库、模型绑定和解绑工作流，同时保持既有 Seedance 运行时解析兼容。

**Constraints:** 不调用真实文本、图片、语音或视频服务；不改视频提交或轮询代码；不使用文件系统模板目录；所有模板正文和映射都必须是本地数据、可导入导出且路径安全。

## Task 1: 引擎模板库、映射与兼容迁移

**Files**
- Modify: `app/lib/src/engine/db.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/engine/prompt_resolver.dart`（仅当本地解析测试证明需要）
- Modify: `app/test/engine/prompt_resolver_test.dart`
- Add: `app/test/engine/model_prompt_library_test.dart`

**Required APIs**

```dart
class ModelPromptTemplate {
  final String path;
  final String name;
  final String kind;
  final String prompt;
  final int createTime;
  final int updateTime;
}

Future<List<ModelPromptTemplate>> listModelPromptTemplates({String? kind});
Future<ModelPromptTemplate> createModelPromptTemplate({
  required String kind,
  required String name,
  required String prompt,
});
Future<void> updateModelPromptTemplate(String path, String prompt);
Future<List<String>> deleteModelPromptTemplate(String path);
Future<void> bindModelPromptTemplate(String providerId, String modelId, String path);
Future<void> unbindModelPromptTemplate(String providerId, String modelId);
Future<List<ModelPromptBinding>> listModelPromptBindings();
```

- [ ] 先写失败测试：旧 `o_modelPrompt` 中的 image/video 映射迁移一次且保留正文，既有 `text/*.md` 直连映射仍可解析且不会被库迁移删除；相同 `path` 的更新同步到所有绑定；删除返回被解绑模型且不留下悬挂映射；非法路径/不匹配 kind/不存在模型全部拒绝。
- [ ] 加入 `o_modelPromptTemplate` 表及幂等迁移；模板库和映射操作使用事务，路径验证在所有入口复用。
- [ ] 将 `listModelPrompts` 的现有调用平滑迁到 `listModelPromptBindings`，不得破坏既有 Seedance 编辑测试。
- [ ] 为 `exportConfig/importConfig` 加模板库字段，覆盖旧备份缺字段、覆盖导入和映射引用顺序。
- [ ] 运行：`cd app && flutter test --concurrency=1 test/engine/model_prompt_library_test.dart test/engine/prompt_resolver_test.dart`，然后 `flutter analyze`。

## Task 2: 设置页模板库与绑定体验

**Files**
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Modify: `app/test/widgets/settings_screen_test.dart`

- [ ] 先写失败 widget 测试：桌面设置入口显示一个未绑定的视频模型；从其入口新建模板、绑定，列表显示绑定名且重新打开能看到正文；解绑回到未绑定。
- [ ] 再写 `390dp` 测试：从移动设置页进入同一模型页，新建或选择既有模板、编辑、保存，所有确认按钮可见且没有 overflow/exception。
- [ ] 实现按供应商分组的模型列表、模型详情页、模板库选择/新增/编辑/删除/解绑；删除必须走现有确认机制，且展示会解绑的模型数。
- [ ] 现有已绑定行仍可一键进入并编辑；不要求用户先创建新模板。
- [ ] 运行：`cd app && flutter test --concurrency=1 test/widgets/settings_screen_test.dart`，然后 `flutter analyze`。

## Task 3: 端到端本地验证与对照归档

**Files**
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: this plan

- [ ] 运行本地验证：`cd app && env -u QA_FULL -u P0_LIVE flutter test && flutter analyze && flutter build macos --debug`。
- [ ] 运行对照检查：`cd .. && node tool/parity/check_no_orphans.js && git diff --check`。
- [ ] 回写三条清单状态与证据；明确测试未发起任何真实生成或视频请求。
- [ ] 独立全功能 review；发现问题先修复再勾选本任务。
