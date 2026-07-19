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
- Modify: `app/test/engine/engine_facade_test.dart`（复审发现的同路径 provider 凭据写入顺序回归）

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

- [x] 先写失败测试：旧 `o_modelPrompt` 中的 image/video 映射迁移一次且保留正文，既有 `text/*.md` 直连映射仍可解析且不会被库迁移删除；相同 `path` 的更新同步到所有绑定；删除返回被解绑模型且不留下悬挂映射；非法路径/不匹配 kind/不存在模型全部拒绝。
- [x] 加入 `o_modelPromptTemplate` 表及幂等迁移；模板库和映射操作使用事务，路径验证在所有入口复用。
- [x] 将 `listModelPrompts` 的现有调用平滑迁到 `listModelPromptBindings`，不得破坏既有 Seedance 编辑测试。
- [x] 为 `exportConfig/importConfig` 加模板库字段，覆盖旧备份缺字段、覆盖导入和映射引用顺序。
- [x] 运行：`cd app && flutter test --concurrency=1 test/engine/model_prompt_library_test.dart test/engine/prompt_resolver_test.dart`，然后 `flutter analyze`。本任务的定向回归覆盖模板解析、视频提示词、schema、旧配置 Key 迁移、供应商更新与预设供应商；全部使用内存或临时 SQLite、假网关和假凭据仓，未调用任何真实供应商或视频任务。最终全套数量在 Task 3 的新鲜验收输出中记录。

## Task 2: 设置页模板库与绑定体验

**Files**
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/lib/src/state/providers.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Modify: `app/lib/src/widgets/common.dart`（动作失败时返回结果，编辑器不能误关）
- Modify: `app/lib/src/engine/engine.dart`（供应商配置串行门的 widget-test zone 回归）
- Modify: `app/test/widgets/settings_screen_test.dart`

- [x] 先写失败 widget 测试：桌面设置入口显示一个未绑定的视频模型；从其入口新建模板、绑定，列表显示绑定名且重新打开能看到正文；解绑回到未绑定。额外断言空名称保存后编辑器不关闭，删除确认准确显示将解绑的模型数。
- [x] 再写 `390dp` 测试：从移动设置页进入同一模型页，选择既有模板、编辑、保存；使用真实设置滚动容器定位可点击目标，无 overflow/exception。
- [x] 实现按供应商分组的模型列表、模型详情页、模板库选择/新增/编辑/删除/解绑；删除走确认框并展示去重后的受影响模型数。
- [x] 现有已绑定行仍可一键进入并编辑；不要求用户先创建新模板。
- [x] 运行：`cd app && flutter test --concurrency=1 test/widgets/settings_screen_test.dart`（15 条通过），然后 `flutter analyze`（No issues found）。

### Task 2 收尾复审（2026-07-19）

- [x] 首次供应商保存曾在 widget test 的 `FakeAsync` zone 中卡在构造期 `Future.value()`；串行门现仅在存在前序操作时等待，并在队列排空时释放尾部 Future。原有供应商新建回归与新增桌面提示词库回归均覆盖该路径。
- [x] `runAction` 现返回成功状态；模板绑定、解绑、删除和保存只在成功后更新局部 UI 或关闭编辑器，避免错误被 SnackBar 捕获后仍伪造成功状态。

## Task 1 复审修正（完成 Task 2 前必须关闭）

- [x] **绑定可达性**：`video_track.dart` 生成提示词时，模型库中已绑定的 video 模板必须优先于模型能力里的模式路径；补假网关测试，只断言本地 system prompt，不提交视频。
- [x] **导入原子性**：`importConfig` 的数据库写入必须以一个可回滚 savepoint 包裹；任何后段模型模板校验失败不得留下供应商、模型、全局提示词或模板库的半份配置。凭据仍走既有安全存储，测试不写真实凭据。
- [x] **启用状态**：绑定时同时要求供应商和模型启用，禁用供应商必须拒绝且不改旧绑定。
- [x] **不做历史多路径去重**：驳回“每模型只能一条历史映射”的建议。Flutter 的视频能力可为不同模式保留不同路径，启动迁移自动合并会丢失这些用户配置；新的显式绑定操作仍会原子替换同模型的模板库绑定。

## Task 1 终审修正（完成 Task 2 前必须关闭）

- [x] **项目模型一致性**：视频提示词的模板查询、旧映射回退及 `promptProvenance` 均使用项目的 `videoModel`（若项目未指定才回退 `binding.shot_video`），不能混用项目模型能力与全局阶段模型的模板。
- [x] **导入保留多模式映射**：导入多个合法 image/video 路径时只替换同一 `providerId + model + path` 的重复行，不能删掉同模型的其他路径；新增导出→导入→解析双路径回归。
- [x] **同步数据库事务与旧 Key 导入**：`config_import` savepoint 内不得 `await`。历史配置带 `apiKey` 时，先在同步事务中把全部涉及供应商写成 `enable=0 + provisioning`，再逐把写 Keychain，全部成功后才在第二个同步 savepoint 恢复导入指定的启用状态。任一 Keychain 或最终数据库步骤已捕获失败时，会将所有涉及供应商标记为 `provisioningFailed` 并保持禁用；启动恢复明确跳过这类已知失败，设置页仅切换启用状态也不能绕过，用户必须重新保存 key 才会清除标记并重走暂存流程。供应商凭据变更由单一串行门保护，失败导入不会覆盖用户随后保存的新 key。创建/预设创建和正常硬杀仍沿用原有 provisioning 恢复路径。SQLite 与系统 Keychain 无法组成分布式事务：若记录失败标记本身也因 SQLite 全面故障写不进去，保留禁用 provisioning 行并在下次启动按既有恢复规则收敛；这是已披露的跨存储全失败残余，而不是伪造“已回滚”。测试覆盖无关 SQLite 写入不被回滚、模型校验失败零触碰旧 key、迁移等待期全部禁用、失败后重启仍禁用、单纯启用无法绕过、并发保存新 key 不被失败导入覆盖，以及更新/创建的暂存失败路径。

## Task 3: 端到端本地验证与对照归档

**Files**
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: this plan

- [x] 运行本地验证：`cd app && env -u QA_FULL -u P0_LIVE flutter test --concurrency=1`、`flutter analyze`（No issues found）及 `flutter build macos --debug`（`dramaflow.app` 成功构建）。全套执行期间不设置 `QA_FULL` / `P0_LIVE`，不发起真实供应商或视频请求。
- [x] 运行对照检查：`cd .. && node tool/parity/check_no_orphans.js`（538 项全部覆盖）与 `git diff --check`（通过）。
- [x] 回写三条清单状态与证据；明确测试未发起任何真实生成或视频请求。
- [x] 独立全功能 review；修复了 widget-test zone 串行门、动作失败误关闭编辑器和移动滚动目标歧义后，定向引擎/设置页/本地化回归与全套离线验证完成。
