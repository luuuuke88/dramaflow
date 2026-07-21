# 技能库文件管理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:executing-plans` task-by-task. Each task starts from a failing test.

**Goal:** 在桌面和移动端管理应用自有的 Markdown 技能文件，并提供真实可用的扫描对账。

**Architecture:** `assistant_skill_library.dart` 处理文件根目录、复制、扫描与内容读写；`assistant_skills.dart` 保留 `o_skillList`、frontmatter、启停和现有上下文接口。UI 只调用 Engine API，不直接访问磁盘。

**Tech Stack:** Flutter/Dart、SQLite、`file_selector`、`crypto`、Riverpod。

## Global Constraints

- 仅 Markdown 和同目录资源；不恢复 JS 技能执行、向量检索、子 Agent 或按需激活。
- 不从技能根目录外读取已托管技能，不跟随越界符号链接，不持久化外部绝对路径。用户经
  系统选择器明确选择的导入源允许是绝对路径，但只能被一次性复制。
- 不调用真实文本、图片或视频供应商。
- 每个 UI 行为有桌面和 390dp 的离线 widget 证据。
- 不修改 Toonflow-app/Toonflow-web，也不暂存 `.superpowers/sdd/progress.md` 与 `docs/superpowers/acceptance/`。

---

### Task 1: 受限工作区与导入

**Files:**
- Create: `app/lib/src/engine/assistant_skill_library.dart`
- Modify: `app/lib/src/engine/assistant_skills.dart`
- Test: `app/test/engine/assistant_skill_library_test.dart`

**Produces:**

```dart
String assistantSkillLibraryRoot();
AssistantSkill importMarkdownAssistantSkill(String sourcePath);
String readManagedAssistantSkill(String id);
void saveManagedAssistantSkill(String id, String markdown);
```

- [ ] Write a failing test that imports an external `SKILL.md`, then asserts the saved path is below `dirname(media.rootDir)/skills`, the copied contents match, and `o_skillList.md5` is non-empty.
- [ ] Run `cd app && flutter test test/engine/assistant_skill_library_test.dart --concurrency=1`; it must fail because the import API is missing.
- [ ] Implement a lazily-created skills root, canonical-path containment checks, copy-to-ID-directory import, MD5 persistence, and a compatibility alias from `saveMarkdownAssistantSkill` to the new import API. A system-picker source may be absolute, but destination and every later managed read must reject absolute, `..`, and symlink-escaping paths with `EngineException`.
- [ ] Re-run the focused test until it passes; add red tests for duplicate ID replacement and invalid frontmatter rollback.
- [ ] Commit only the engine files and test with message `feat(skills): manage local markdown skill workspace`.

### Task 2: 扫描与对账

**Files:**
- Modify: `app/lib/src/engine/assistant_skill_library.dart`
- Test: `app/test/engine/assistant_skill_library_test.dart`

**Produces:**

```dart
class AssistantSkillScanResult {
  final List<AssistantSkill> added;
  final List<AssistantSkill> updated;
  final List<AssistantSkillScanIssue> missing;
  final List<AssistantSkillScanIssue> invalid;
}
AssistantSkillScanResult scanMarkdownAssistantSkills();
```

- [ ] Write a failing test with four files/rows: a new file, a changed managed file, a database row whose managed file was removed, and invalid frontmatter. Assert each result collection reports exactly the corresponding path or ID.
- [ ] Run the focused engine test and observe the missing scan API compile failure.
- [ ] Implement recursive `skills/<id>/SKILL.md` discovery of regular files inside the resolved root only; package-internal Markdown remains a resource, never a separately registered skill. Preserve a row's enabled state, upsert changed parsed metadata/hash, retain missing database rows for repair, and collect invalid entries without aborting the scan.
- [ ] Re-run focused tests, including a symlink fixture where supported by the host; assert it is ignored or reported and never read outside the root.
- [ ] Commit engine and test updates with message `feat(skills): reconcile managed markdown skills`.

### Task 3: 响应式文件管理界面

**Files:**
- Modify: `app/lib/src/screens/agent/agent_chat_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Test: `app/test/widgets/agent_chat_screen_test.dart`

**Stable UI keys:** `assistant-skills-import`, `assistant-skills-scan`, `assistant-skills-search`, `assistant-skill-edit-<id>`, `assistant-skill-save-<id>`.

- [ ] Write failing desktop widget coverage: a `file_selector` fake returns `SKILL.md`; importing makes it searchable, selecting it shows a preview, editing and saving changes the managed file.
- [ ] Write failing 390dp coverage: scan shows new/changed/missing/invalid totals; opening a Markdown skill enters a detail page and its back command returns to the list without overflow.
- [ ] Run `cd app && flutter test test/widgets/agent_chat_screen_test.dart --concurrency=1`; both tests must fail because the controls do not exist.
- [ ] Implement one pane backed by Task 1/2: width >= 840 has list plus detail; narrow width has list then full-height detail. Builtin actions remain toggle-only. The import command selects a single Markdown file; desktop-only directory import is deferred until its file-selector support has a direct test.
- [ ] Add zh/en/ja labels for import, scan, search, preview, edit, save, back, and scan totals. Run the focused widget test plus `flutter analyze` until both are green.
- [ ] Commit UI/l10n/tests with message `feat(skills): add responsive markdown skill manager`.

### Task 4: 对照记录、全量验证与审查

**Files:**
- Modify: `docs/parity/skill-runtime-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Test: `app/test/docs/page_parity_checklist_test.dart`

- [ ] Update evidence paths and test names. Mark only file management and reliable rescan as verified when the preceding tests prove them. Keep lazy activation, resource-read exposure, stage attribution, and custom JS execution explicitly missing.
- [ ] Run `cd app && flutter test test/docs/page_parity_checklist_test.dart --concurrency=1`, then one non-overlapping full `flutter test --concurrency=1 --reporter compact`, `flutter analyze`, and `flutter build macos --debug`.
- [ ] Run `git diff --check`, review only skill/UI/document changes, and commit documents with message `docs(parity): record skill manager evidence`. Leave user-owned progress and acceptance files untouched.
