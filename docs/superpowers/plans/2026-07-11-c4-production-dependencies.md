# C4 Production Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the production canvas chain from decorative Markdown nodes into a persisted ToonFlow-style workflow: project director plan -> episode storyboard table -> replaceable structured shots, with explicit stale state and the missing script-generation assistant command.

**Architecture:** Keep the existing Markdown documents in `o_agentWorkData`, and add one small additive state table rather than changing their content shape. Paid director-plan, table, and structured-shot tasks use the same prompt resolver and queue as existing stages; only a successful structured-shot result atomically replaces prior shots. Editing or regenerating upstream data keeps downstream media intact, marks it stale, and makes the next replacement explicit in the UI.

**Tech Stack:** Flutter/Dart 3.5, SQLite additive migration, existing `JobQueue`, `ProviderGateway`, `PromptResolverApi`, Riverpod, existing adaptive dialogs and policy confirmation, Flutter tests with fake gateways only.

## Global Constraints

- Preserve the approved core workflow: `script -> director plan -> storyboard table -> structured storyboard -> workbench`.
- Do not add vector recall, vision models, custom JavaScript skills, a companion backend, web-engine work, or real-provider test calls.
- Keep document Markdown in `o_agentWorkData` under the existing `scriptPlan` and `storyboardTable` keys; never silently reinterpret old document text as JSON.
- Use additive schema migration only. Existing projects and their existing shots remain readable after upgrading.
- Prompt order is exactly: base template, visual-manual section, director-manual section, optional selected-model template, then current project data and explicit instruction. Task JSON records hashes/IDs only, never prompt bodies or credentials.
- Required manual mappings are: director plan `director_planning_style` + `director_planning_narrative`; storyboard table `director_storyboard_table_style` + `director_storyboard_table_narrative`; structured shots `director_storyboard` + the current plan/table narrative data.
- Missing scripts, plan, table, manual sections, malformed model output, or changed queued inputs must fail before a paid provider call whenever possible and use an actionable `EngineException` reason.
- Regenerating or editing an upstream document marks descendants stale but does not delete them. Replacing existing structured shots requires user confirmation; the old shots/videos are removed only after a new LLM result has parsed and validated successfully.
- All visible copy has Chinese, English, and Japanese ARB entries. Buttons use stable keys in widget tests.
- UI buttons and the assistant must delegate to the same `Engine` commands; no duplicate generation logic in widgets or chat code.

---

## File Structure

- Create: `app/lib/src/engine/production_dependencies.dart` - additive document-state storage, hashes, stale propagation, and reusable state APIs.
- Modify: `app/lib/src/engine/db.dart` - schema version 11 and additive `o_productionDependencyState` table.
- Modify: `app/lib/src/engine/queue.dart` - add director-plan and storyboard-table text task classes.
- Modify: `app/lib/src/engine/pipeline_policy.dart` - make the two text tasks charge-confirmed and add the structured-shot replacement destructive key.
- Modify: `app/lib/src/engine/providers/resolve.dart` - declare both stages as text stages so bindings resolve safely.
- Modify: `app/lib/src/engine/engine.dart` - register default prompts and bindings for the two new stages.
- Modify: `app/lib/src/engine/prompt_resolver.dart` - include an optional model-specific template when a matching row exists, without making it required for text stages.
- Modify: `app/lib/src/engine/script_plan.dart` - director-plan queue runner, persistence, provenance, and downstream invalidation.
- Modify: `app/lib/src/engine/storyboard_table.dart` - storyboard-table queue runner, persistence, provenance, and downstream invalidation.
- Modify: `app/lib/src/engine/scripts.dart` - mark the episode table/shots stale after content or script-asset changes.
- Modify: `app/lib/src/engine/storyboard.dart` - generate structured shots from a storyboard table plus current project data, validate queued source hashes, and atomically replace old shots only after success.
- Modify: `app/lib/src/engine/assistant_actions.dart` - add `generate_scripts`; update the existing structured-shot action to use the same table-driven command.
- Modify: `app/lib/src/screens/production/script_plan_node.dart` - generate/regenerate director plan and show stale state.
- Modify: `app/lib/src/screens/production/production_screen.dart` - generate/regenerate storyboard table, stale state, and dependency-aware refresh.
- Modify: `app/lib/src/screens/production/storyboard_canvas_node.dart` - require a table, show stale state, and confirm before requesting replacement.
- Modify: `app/lib/src/screens/tasks_screen.dart` - labels/icons for the two new text tasks.
- Modify: `app/lib/src/screens/settings_screen.dart` - expose two bindings and two editable base prompts.
- Modify: `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_ja.arb` - all new copy.
- Test: `app/test/engine/db_test.dart`, `app/test/engine/prompt_resolver_test.dart`, `app/test/engine/script_plan_test.dart`, `app/test/engine/storyboard_table_test.dart`, `app/test/engine/storyboard_test.dart`, `app/test/engine/scripts_test.dart`, `app/test/engine/assistant_actions_test.dart`, `app/test/widgets/script_plan_node_test.dart`, `app/test/widgets/production_screen_test.dart`, `app/test/widgets/storyboard_canvas_node_test.dart`, `app/test/widgets/settings_screen_test.dart`, `app/test/widgets/tasks_screen_test.dart`.

## Stable C4 Interfaces

```dart
const directorPlanStateKey = 'directorPlan';
const storyboardTableStateKey = 'storyboardTable';
const structuredStoryboardStateKey = 'structuredStoryboards';

class ProductionDependencyState {
  final int projectId;
  final int scriptId; // 0 means project-wide
  final String key;
  final String sourceHash;
  final bool stale;
  final int updateTime;
}

class StoryboardTableShot {
  final String prompt;
  final String videoDesc;
  final String duration;
  final String track;
  final List<String> assetNames;
  final bool shouldGenerateImage;
}

extension ProductionDependenciesApi on Engine {
  ProductionDependencyState productionDependencyState(
    int projectId, String key, {int scriptId = 0});
  void setProductionDependencyState({
    required int projectId,
    required int scriptId,
    required String key,
    required String sourceHash,
    required bool stale,
  });
  void markStoryboardTableAndShotsStale(int projectId, int scriptId);
  void markProjectStoryboardTablesAndShotsStale(int projectId);
  String projectScriptsHash(int projectId);
  String scriptAssetsHash(int projectId, int scriptId);
}

extension ScriptPlanApi on Engine {
  int generateDirectorPlan(int projectId);
}

extension StoryboardTableApi on Engine {
  int generateStoryboardTable(int projectId, int scriptId);
}

extension StoryboardApi on Engine {
  int generateStoryboards(
    int projectId,
    int scriptId, {
    required bool replaceExisting,
  });
  List<StoryboardTableShot> parseStoryboardTable(String markdown);
}
```

The table generator writes this exact Markdown table shape. It may add a title and explanatory text above or below the table, but it must emit one nonempty table whose header uses the Chinese labels below. A literal pipe inside a cell is escaped as `\\|`.

```markdown
| 镜头 | 画面提示词 | 画面描述 | 时长 | 分轨 | 资产 | 生成首帧 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 雪夜山门，林朝雪拔剑，中景，冷蓝月光 | 镜头缓慢推进，少女拔剑转身 | 5 | 主线 | 林朝雪, 山门, 青霜剑 | 是 |
```

`parseStoryboardTable` accepts exactly the required columns `画面提示词`, `画面描述`, and `时长`; `镜头`, `分轨`, `资产`, and `生成首帧` are optional. English aliases (`prompt`, `videoDesc`, `duration`, `track`, `assetNames`, `shouldGenerateImage`) are accepted for hand-authored tables. It rejects an empty table or a row without a prompt using `errLlmFormat` and a reason starting `storyboard_table:`.

### Task 1: Add Additive Dependency State And Stale Propagation

**Files:**
- Create: `app/lib/src/engine/production_dependencies.dart`
- Modify: `app/lib/src/engine/db.dart`
- Modify: `app/lib/src/engine/scripts.dart`
- Test: `app/test/engine/db_test.dart`
- Test: `app/test/engine/script_plan_test.dart`
- Test: `app/test/engine/storyboard_table_test.dart`
- Test: `app/test/engine/scripts_test.dart`

**Consumes:** Existing `o_agentWorkData`, `o_script`, `o_scriptAssets`, and `promptContentHash` from `prompt_resolver.dart`.

**Produces:** `ProductionDependencyState`, state keys, durable source hashes, and the stale-propagation API consumed by generation and widgets.

- [ ] **Step 1: Write failing state/migration tests.**

Add tests that start with a version-10 database, open it through `openEngineDb`, and prove the new table exists without losing a project. Add these behavioral tests to the existing document suites:

```dart
test('保存导演规划使项目所有分镜表和结构分镜过期', () {
  final scriptId = engine.addScript(
      projectId: projectId, name: '第一集', content: '旧剧本');
  engine.saveStoryboardTable(projectId, scriptId, tableMarkdown);
  engine.setProductionDependencyState(
      projectId: projectId, scriptId: scriptId,
      key: structuredStoryboardStateKey, sourceHash: 'old', stale: false);

  engine.saveScriptPlan(projectId, '新的导演规划');

  expect(engine.productionDependencyState(
      projectId, storyboardTableStateKey, scriptId: scriptId).stale, isTrue);
  expect(engine.productionDependencyState(
      projectId, structuredStoryboardStateKey, scriptId: scriptId).stale, isTrue);
});

test('手改分镜表仅使同剧集结构分镜过期', () {
  engine.saveStoryboardTable(projectId, scriptA, tableMarkdown);
  engine.saveStoryboardTable(projectId, scriptB, tableMarkdown);
  engine.setProductionDependencyState(
      projectId: projectId, scriptId: scriptB,
      key: structuredStoryboardStateKey, sourceHash: 'fresh-b', stale: false);
  expect(engine.productionDependencyState(
      projectId, structuredStoryboardStateKey, scriptId: scriptA).stale, isTrue);
  expect(engine.productionDependencyState(
      projectId, structuredStoryboardStateKey, scriptId: scriptB).stale, isFalse);
});
```

Add a script test that either `updateScript(content: ...)` or `updateScript(name: ...)` marks only that script's table and structured shots stale. The plan/table prompt includes both values, so a title edit is an upstream change too.

- [ ] **Step 2: Run focused tests and verify the new state symbols/table fail.**

Run: `cd app && flutter test test/engine/db_test.dart test/engine/script_plan_test.dart test/engine/storyboard_table_test.dart test/engine/scripts_test.dart --reporter compact`

Expected: FAIL with missing `productionDependencyState`, missing state keys, or missing `o_productionDependencyState`.

- [ ] **Step 3: Implement schema version 11 and the state API.**

In `db.dart`, change `schemaVersion` from `10` to `11` and add this table inside `initSchema`:

```sql
CREATE TABLE IF NOT EXISTS o_productionDependencyState (
  projectId INTEGER NOT NULL,
  scriptId INTEGER NOT NULL DEFAULT 0,
  key TEXT NOT NULL,
  sourceHash TEXT NOT NULL DEFAULT '',
  stale INTEGER NOT NULL DEFAULT 0,
  updateTime INTEGER NOT NULL,
  PRIMARY KEY (projectId, scriptId, key)
);
```

Create `production_dependencies.dart`. Read a missing state row as `sourceHash: ''`, `stale: false`, and `updateTime: 0`, so old projects remain usable. Use this exact upsert:

```dart
db.execute(
  'INSERT INTO o_productionDependencyState '
  '(projectId,scriptId,key,sourceHash,stale,updateTime) VALUES (?,?,?,?,?,?) '
  'ON CONFLICT(projectId,scriptId,key) DO UPDATE SET '
  'sourceHash=excluded.sourceHash, stale=excluded.stale, '
  'updateTime=excluded.updateTime',
  [projectId, scriptId, key, sourceHash, stale ? 1 : 0, now],
);
```

`projectScriptsHash` must hash scripts ordered by ID as `id + name + content`; `scriptAssetsHash` must hash linked role/tool/scene assets ordered by asset ID as `id + type + name + describe`. Use `promptContentHash` for both, and never include absolute file paths.

Call `markProjectStoryboardTablesAndShotsStale(projectId)` after `saveScriptPlan`. Call `markStoryboardTableAndShotsStale(projectId, scriptId)` after any screenplay name/content or script-asset-link update.

- [ ] **Step 4: Run focused tests and verify stale propagation passes.**

Run: `cd app && flutter test test/engine/db_test.dart test/engine/script_plan_test.dart test/engine/storyboard_table_test.dart test/engine/scripts_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit the independently valid state layer.**

```bash
git add app/lib/src/engine/db.dart app/lib/src/engine/production_dependencies.dart \
  app/lib/src/engine/script_plan.dart app/lib/src/engine/storyboard_table.dart \
  app/lib/src/engine/scripts.dart app/test/engine/db_test.dart \
  app/test/engine/script_plan_test.dart app/test/engine/storyboard_table_test.dart \
  app/test/engine/scripts_test.dart
git commit -m "feat(production): track document dependencies"
```

### Task 2: Extend Prompt Resolution And Register C4 Text Stages

**Files:**
- Modify: `app/lib/src/engine/prompt_resolver.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/engine/queue.dart`
- Modify: `app/lib/src/engine/pipeline_policy.dart`
- Modify: `app/lib/src/engine/providers/resolve.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Test: `app/test/engine/prompt_resolver_test.dart`
- Test: `app/test/engine/engine_facade_test.dart`
- Test: `app/test/engine/pipeline_policy_test.dart`
- Test: `app/test/widgets/settings_screen_test.dart`

**Consumes:** Task provenance format and existing `binding.<stage>` settings.

**Produces:** `director_plan` and `storyboard_table` stages, editable base prompts, and optional `text/<stage>.md` model-template resolution used by Tasks 3-5.

- [ ] **Step 1: Write failing resolution/default tests.**

Extend `prompt_resolver_test.dart` to prove a missing optional template does not throw, while a saved template is appended after both manuals:

```dart
final noModel = engine.resolvePrompt(
  projectId: projectId,
  basePromptKey: 'director_plan',
  visualSection: 'director_planning_style',
  directorSection: 'director_planning_narrative',
  modelStage: 'director_plan',
  modelPromptPath: 'text/director_plan.md',
  requireModelPrompt: false,
);
expect(noModel.sources.map((s) => s.kind), ['base', 'visual', 'director']);

db.execute('INSERT INTO o_modelPrompt (vendorId,model,fileName,path,prompt) '
    'VALUES (?,?,?,?,?)',
    ['azt', 'gpt-5.5', 'director_plan.md', 'text/director_plan.md', 'MODEL']);
final withModel = engine.resolvePrompt(/* same args */);
expect(withModel.system, contains('MODEL'));
expect(withModel.sources.last.id, 'model:azt:gpt-5.5:text/director_plan.md');
```

Test freshly seeded desktop and mobile engines expose `binding.director_plan`, `binding.storyboard_table`, `o_prompt` rows named `director_plan` and `storyboard_table`, and the settings screen lists both text stages/prompt editors.

- [ ] **Step 2: Run focused tests and verify they fail.**

Run: `cd app && flutter test test/engine/prompt_resolver_test.dart test/engine/engine_facade_test.dart test/widgets/settings_screen_test.dart --reporter compact`

Expected: FAIL because `requireModelPrompt`, new bindings, and new settings entries are absent.

- [ ] **Step 3: Implement optional templates and stage defaults.**

Add `bool requireModelPrompt = true` to `resolvePrompt`. This preserves the existing strict behavior for C3 video templates. When `modelPromptPath` is set but no matching binding/model row/template exists, skip the source only when the C4 caller explicitly passes `requireModelPrompt: false`; otherwise retain today's actionable error.

Seed these text bindings beside existing `script_gen` and `storyboard_gen` bindings:

```dart
binding('director_plan', isMobile
    ? 'volcengine:doubao-seed-1-6-250615' : 'azt:gpt-5.5');
binding('storyboard_table', isMobile
    ? 'volcengine:doubao-seed-1-6-250615' : 'azt:gpt-5.5');
```

Seed exactly these editable base prompt contracts:

```dart
prompt(
  name: 'director_plan', type: 'director_plan',
  data: '你是短剧总导演。根据项目已有剧本写出可执行的导演规划。'
      '必须覆盖：整体视觉与节奏、人物弧光、分集冲突升级、场景复用、关键转场和每集钩子。'
      '只输出 Markdown 导演规划，不要解释生成过程。',
);
prompt(
  name: 'storyboard_table', type: 'storyboard_table',
  data: '你是短剧分镜导演。根据导演规划、当前剧本和资产清单生成可执行的 Markdown 分镜表。'
      '必须只输出一个包含“镜头、画面提示词、画面描述、时长、分轨、资产、生成首帧”列的表格；'
      '资产列只写候选清单中的原名，单元格内的竖线必须写成\\|。',
);
```

Add `director_plan_generation` and `storyboard_table_generation` to the queue text lane and `actionPolicyByTaskClass` as `costsMoney: true`. Add the same stages to `_stages` and prompt keys to `_promptMetas`; use their raw stage keys as a temporary switch fallback only until Task 6 supplies localized labels.

- [ ] **Step 4: Run focused tests and verify all stage/default contracts pass.**

Run: `cd app && flutter test test/engine/prompt_resolver_test.dart test/engine/engine_facade_test.dart test/widgets/settings_screen_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit stage registration.**

```bash
git add app/lib/src/engine/prompt_resolver.dart app/lib/src/engine/engine.dart \
  app/lib/src/engine/queue.dart app/lib/src/engine/pipeline_policy.dart \
  app/lib/src/screens/settings_screen.dart app/test/engine/prompt_resolver_test.dart \
  app/test/engine/engine_facade_test.dart app/test/widgets/settings_screen_test.dart
git commit -m "feat(production): register director planning stages"
```

### Task 3: Generate And Persist The Project Director Plan

**Files:**
- Modify: `app/lib/src/engine/script_plan.dart`
- Test: `app/test/engine/script_plan_test.dart`

**Consumes:** Task 1 dependency state; Task 2 `director_plan` prompt resolution and text queue class.

**Produces:** `generateDirectorPlan(projectId)`, a recoverable `director_plan_generation` task, plan task provenance, and project-wide stale propagation.

- [ ] **Step 1: Write failing queue/provenance tests.**

Use a fake `ProviderGateway.generateText` and assert the output becomes the existing Markdown document, records all sources, and marks existing descendant state stale:

```dart
gateway.textResult = (system, user, stage) {
  expect(stage, 'director_plan');
  expect(system, 'BASE\n\nVISUAL\n\nDIRECTOR');
  expect(user, contains('第一集'));
  expect(user, contains('林朝雪拔剑'));
  return '# 导演规划\n\n## 节奏\n快切推进';
};
final taskId = engine.generateDirectorPlan(projectId);
await waitTask(taskId);
expect(engine.scriptPlan(projectId), contains('导演规划'));
final related = taskRelatedObjects(db, taskId);
expect(related['promptSources'], isNotEmpty);
expect(related['promptRequests'], hasLength(1));
```

Also assert no task is enqueued when the project has no scripts, and a missing `director_planning_style` or `director_planning_narrative` throws before `gateway.generateText` executes.

- [ ] **Step 2: Run the focused plan tests and verify failure.**

Run: `cd app && flutter test test/engine/script_plan_test.dart --reporter compact`

Expected: FAIL because `generateDirectorPlan` and its runner are absent.

- [ ] **Step 3: Implement the plan task.**

Extend `installScriptPlanPipeline` (create it if absent and call it from `Engine` initialization alongside the existing pipelines) with:

```dart
taskRunners['director_plan_generation'] = _runDirectorPlanGeneration;
queue.registerRecover('director_plan_generation', (_) {});
```

`generateDirectorPlan` must load ordered scripts and reject an empty project with `EngineException(errPromptMissing, {'type': 'scripts'})` before enqueueing. Enqueue only `{ 'kind': 'project', 'scriptsHash': projectScriptsHash(projectId) }`.

The runner must recompute that hash before calling the provider. On mismatch, throw `EngineException(errPromptMissing, {'type': 'directorPlan:staleScripts'})`. Resolve the prompt with:

```dart
resolvePrompt(
  projectId: projectId,
  basePromptKey: 'director_plan',
  visualSection: 'director_planning_style',
  directorSection: 'director_planning_narrative',
  modelStage: 'director_plan',
  modelPromptPath: 'text/director_plan.md',
  requireModelPrompt: false,
);
```

Build one `PromptRequestTrace(targetType: 'project', targetId: projectId, ...)` whose final data source is the ordered scripts user payload. Call `recordTaskPromptSources` before `gateway.generateText`. Strip `<think>` using the existing `stripThink`; reject blank output with `errLlmFormat`. Finally call `saveScriptPlan`, then set the plan's own state fresh with the output hash. `saveScriptPlan` marks old tables/shots stale; it must not erase them.

- [ ] **Step 4: Run focused plan tests and verify pass.**

Run: `cd app && flutter test test/engine/script_plan_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit director-plan generation.**

```bash
git add app/lib/src/engine/script_plan.dart app/lib/src/engine/engine.dart \
  app/test/engine/script_plan_test.dart
git commit -m "feat(production): generate director plans"
```

### Task 4: Generate And Persist Episode Storyboard Tables

**Files:**
- Modify: `app/lib/src/engine/storyboard_table.dart`
- Test: `app/test/engine/storyboard_table_test.dart`

**Consumes:** Tasks 1-3, current script, the persisted project director plan, and project role/tool/scene assets.

**Produces:** `generateStoryboardTable(projectId, scriptId)`, a recoverable `storyboard_table_generation` task, provenance, and episode-scoped stale propagation.

- [ ] **Step 1: Write failing table-generation tests.**

Set up a selected visual/director pack with all required manual sections, one plan, one script, and named assets. Assert the fake gateway receives the correct stage and all three documents:

```dart
gateway.textResult = (system, user, stage) {
  expect(stage, 'storyboard_table');
  expect(system, 'BASE\n\nVISUAL\n\nDIRECTOR');
  expect(user, allOf(contains('# 导演规划'), contains('# 第一集'),
      contains('林朝雪（role）')));
  return tableMarkdown;
};
final taskId = engine.generateStoryboardTable(projectId, scriptId);
await waitTask(taskId);
expect(engine.storyboardTable(projectId, scriptId), tableMarkdown);
expect(engine.productionDependencyState(projectId, structuredStoryboardStateKey,
    scriptId: scriptId).stale, isTrue);
```

Test empty plan rejects before enqueue; missing director-table manual sections reject before the text call; changing the plan/script/assets after enqueue makes the runner fail before a provider call; task JSON stores `promptSources` and hashes but not document text.

- [ ] **Step 2: Run focused table tests and verify failure.**

Run: `cd app && flutter test test/engine/storyboard_table_test.dart --reporter compact`

Expected: FAIL because the generator and its runner do not exist.

- [ ] **Step 3: Implement table generation.**

Install `storyboard_table_generation` in a new `installStoryboardTablePipeline`, called during Engine initialization. `generateStoryboardTable` validates the script exists and `scriptPlan(projectId).trim().isNotEmpty`, then enqueues the IDs/hashes only:

```dart
{
  'kind': 'script',
  'scriptId': scriptId,
  'scriptHash': promptContentHash(scriptContent),
  'planHash': promptContentHash(plan),
  'assetsHash': scriptAssetsHash(projectId, scriptId),
}
```

The runner rechecks all hashes before resolving:

```dart
resolvePrompt(
  projectId: projectId,
  basePromptKey: 'storyboard_table',
  visualSection: 'director_storyboard_table_style',
  directorSection: 'director_storyboard_table_narrative',
  modelStage: 'storyboard_table',
  modelPromptPath: 'text/storyboard_table.md',
  requireModelPrompt: false,
);
```

Build the user prompt in this stable order: `导演规划`, `当前剧本`, `候选资产`. Record each as a `PromptSource` in a single `PromptRequestTrace(targetType: 'script', targetId: scriptId, ...)`. After a nonblank text result, call `saveStoryboardTable`; then store fresh table state with `promptContentHash(markdown)`. That save invalidates only the same episode's structured shots.

- [ ] **Step 4: Run focused table tests and verify pass.**

Run: `cd app && flutter test test/engine/storyboard_table_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit storyboard-table generation.**

```bash
git add app/lib/src/engine/storyboard_table.dart app/lib/src/engine/engine.dart \
  app/test/engine/storyboard_table_test.dart
git commit -m "feat(production): generate storyboard tables"
```

### Task 5: Generate Structured Shots From The Table And Replace Safely

**Files:**
- Modify: `app/lib/src/engine/storyboard.dart`
- Modify: `app/lib/src/engine/pipeline_policy.dart`
- Test: `app/test/engine/storyboard_test.dart`

**Consumes:** Generated or manually edited Markdown table, director plan, current script/assets, Task 1 state, and the existing `storyboard_gen` model stage.

**Produces:** Strict table parsing, table-driven LLM structured shots, associated asset IDs, prompt provenance, stale checks, and atomic replacement semantics.

- [ ] **Step 1: Write failing parser/replacement tests.**

Add pure parser tests:

```dart
final shots = engine.parseStoryboardTable(tableMarkdown);
expect(shots, hasLength(1));
expect(shots.single.prompt, contains('雪夜山门'));
expect(shots.single.assetNames, ['林朝雪', '山门', '青霜剑']);
expect(shots.single.shouldGenerateImage, isTrue);
expect(() => engine.parseStoryboardTable('| 镜头 | 时长 |\n|---|---|\n|1|5|'),
    throwsA(isA<EngineException>()));
```

Then test a successful replacement preserves old rows on malformed/new-provider failure and replaces them after validated output. The table rows remain authoritative for duration, track, named assets, and `shouldGenerateImage`; the provider enriches `prompt` and `videoDesc` in the same order:

```dart
final oldId = engine.addStoryboard(projectId: projectId, scriptId: scriptId,
    prompt: '旧镜头');
gateway.toolResult = (_) => {'shots': []};
final failed = engine.generateStoryboards(projectId, scriptId,
    replaceExisting: true);
await waitTask(failed, expectState: 'failed');
expect(engine.storyboards(scriptId).single.id, oldId);

gateway.toolResult = (_) => {'shots': [
  {'prompt': '新镜头', 'videoDesc': '推进', 'duration': '5',
   'track': '主线', 'assetNames': ['林朝雪']},
]};
final succeeded = engine.generateStoryboards(projectId, scriptId,
    replaceExisting: true);
await waitTask(succeeded);
expect(engine.storyboards(scriptId).single.prompt, '新镜头');
```

Cover all of: no table -> no task; existing rows with `replaceExisting: false` -> no task; table/script/plan/assets hash changes after enqueue -> provider not called; named assets get `o_assets2Storyboard` links; state becomes fresh using the table hash; task trace lists plan, table, script, and asset data sources.

- [ ] **Step 2: Run focused storyboard tests and verify failure.**

Run: `cd app && flutter test test/engine/storyboard_test.dart --reporter compact`

Expected: FAIL because table parsing, table requirements, or replacement semantics are absent.

- [ ] **Step 3: Implement strict parsing and table-driven generation.**

Replace the old direct-script body in `_runStoryboardGenerate`; retain `storyboard_generate` as the paid structured-shot task class for task history compatibility. `generateStoryboards` must:

1. validate the script and nonblank table before enqueue;
2. reject existing rows unless `replaceExisting` is true;
3. snapshot only `scriptId`, `replaceExisting`, `scriptHash`, `planHash`, `tableHash`, and `assetsHash`.

Implement a small local parser, not another LLM call. It must locate a pipe-delimited header, split escaped pipes correctly, normalize header aliases, trim cells, split asset names on Chinese/English commas, and convert `是/true/1` to true and `否/false/0/empty` to false. It returns `StoryboardTableShot` records but does not write the database. Extend `storyboardListToolSchema` with `shouldGenerateImage` only if it is returned for diagnostics; do not trust it as the source of truth.

The runner must recheck all four source hashes and parse the current table before provider use. Resolve structured-shot prompt sources with:

```dart
resolvePrompt(
  projectId: projectId,
  basePromptKey: 'storyboard_gen',
  visualSection: 'director_storyboard',
  modelStage: 'storyboard_gen',
  modelPromptPath: 'text/storyboard_gen.md',
  requireModelPrompt: false,
);
```

The user payload has this exact order: `导演规划`, `分镜表`, `当前剧本`, `候选资产`, followed by the instruction to preserve each table row's intended order, duration, and named assets. `recordTaskPromptSources` records a request trace with hashes for each of those data sources.

After `generateToolJson` yields a nonempty `shots` list of exactly the parsed table length, create a database savepoint. Use the table row at the same index for `duration`, `track`, `assetNames`, and `shouldGenerateImage`, and use the provider result only for its required `prompt` and `videoDesc`. If replacement is requested, delete existing linked rows/media in the same order used by script deletion: asset links, storyboard image files, videos/video tracks/video files, and timeline clips for this script. Then insert new rows and associations. On any insertion error, roll back the savepoint. Do not delete old output before tool output is validated. Mark `structuredStoryboardStateKey` fresh with the successful table hash only after the savepoint releases.

Add `replace_storyboards` to `destructiveActionKeys`; it represents planned replacement, not deletion on an LLM failure.

- [ ] **Step 4: Run focused storyboard tests and verify pass.**

Run: `cd app && flutter test test/engine/storyboard_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit table-driven structured shots.**

```bash
git add app/lib/src/engine/storyboard.dart app/lib/src/engine/pipeline_policy.dart \
  app/test/engine/storyboard_test.dart
git commit -m "feat(production): build shots from storyboard tables"
```

### Task 6: Expose The Real Dependency Chain In Settings, Tasks, And Production UI

**Files:**
- Modify: `app/lib/src/screens/production/script_plan_node.dart`
- Modify: `app/lib/src/screens/production/production_screen.dart`
- Modify: `app/lib/src/screens/production/storyboard_canvas_node.dart`
- Modify: `app/lib/src/screens/tasks_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Test: `app/test/widgets/script_plan_node_test.dart`
- Test: `app/test/widgets/production_screen_test.dart`
- Test: `app/test/widgets/storyboard_canvas_node_test.dart`
- Test: `app/test/widgets/tasks_screen_test.dart`

**Consumes:** Tasks 1-5 engine commands and `confirmPolicyAction`.

**Produces:** Clear generate/regenerate controls, stale badges, confirmed replacement, task labels, and immediate UI refresh after task completion.

- [ ] **Step 1: Write failing widget tests.**

Add stable-key tests for all three nodes:

```dart
expect(find.byKey(const Key('script-plan-generate')), findsOneWidget);
await tester.tap(find.byKey(const Key('script-plan-generate')));
expect(fakeEngine.enqueuedTaskClasses, contains('director_plan_generation'));

expect(find.byKey(const Key('storyboard-table-generate-$scriptId')), findsOneWidget);
expect(find.byKey(const Key('storyboard-table-stale-$scriptId')), findsOneWidget);

await tester.tap(find.byKey(const Key('storyboard-generate-$scriptId')));
await tester.pumpAndSettle();
expect(find.text(l10n.policyConfirmDestructiveTitle), findsOneWidget);
```

In the last test, seed existing shots and a nonblank table; tap cancel in the destructive dialog and assert no `storyboard_generate` task exists. Confirm the destructive dialog, cancel the subsequent money dialog, and again assert no task exists. Confirm both dialogs and assert one `storyboard_generate` task exists with `replaceExisting: true`.

- [ ] **Step 2: Run widget tests and verify failure.**

Run: `cd app && flutter test test/widgets/script_plan_node_test.dart test/widgets/production_screen_test.dart test/widgets/storyboard_canvas_node_test.dart test/widgets/tasks_screen_test.dart --reporter compact`

Expected: FAIL because the controls, keys, stale UI, and task labels are absent.

- [ ] **Step 3: Implement dependency-aware controls.**

`ScriptPlanNode` gets a compact header/empty-state `FilledButton.icon` with key `script-plan-generate`. It calls `confirmPolicyAction(... taskClass: 'director_plan_generation', description: l10n.directorPlanGenerateDescription)` then `engine.generateDirectorPlan`. It continues to offer manual edit. It watches `jobsGenerationProvider` so a completed queue task refreshes the preview and stale badge without reopening the page.

`_StoryboardTableNode` gets key `storyboard-table-generate-$scriptId`, confirmation with `storyboard_table_generation`, and calls `engine.generateStoryboardTable`. Its stale label uses `storyboard-table-stale-$scriptId`. Keep manual Markdown editing; saving is deliberately not a replacement dialog because it only marks descendants stale.

`StoryboardCanvasNode` changes its existing generate callback to require a nonblank table. If it has existing rows, first call:

```dart
final allowed = await confirmPolicyAction(
  context, engine.config,
  destructiveKey: 'replace_storyboards',
  description: l10n.storyboardReplaceDescription,
);
if (!allowed) return;
```

Then, for both new and replacement generation, call `confirmPolicyAction` a second time with `taskClass: 'storyboard_generate'` and return unless it is approved. Finally call `engine.generateStoryboards(projectId, scriptId, replaceExisting: hasExistingRows)`. Show the stale state with key `storyboard-stale-$scriptId`; do not hide existing images/videos merely because they are stale.

Add explicit ARB keys for director-plan/table generation, `stale`, `needsRegeneration`, structured-shot replacement description, task labels, and tooltips. Regenerate localization Dart code using the repository's established Flutter localization command, then update the localized generated files only through that command. Add task labels/icons for `director_plan_generation` and `storyboard_table_generation`.

- [ ] **Step 4: Run widget tests and verify pass.**

Run: `cd app && flutter test test/widgets/script_plan_node_test.dart test/widgets/production_screen_test.dart test/widgets/storyboard_canvas_node_test.dart test/widgets/tasks_screen_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit production controls.**

```bash
git add app/lib/src/screens/production/script_plan_node.dart \
  app/lib/src/screens/production/production_screen.dart \
  app/lib/src/screens/production/storyboard_canvas_node.dart \
  app/lib/src/screens/tasks_screen.dart app/lib/l10n \
  app/test/widgets/script_plan_node_test.dart \
  app/test/widgets/production_screen_test.dart \
  app/test/widgets/storyboard_canvas_node_test.dart \
  app/test/widgets/tasks_screen_test.dart
git commit -m "feat(production): surface dependency generation"
```

### Task 7: Add The Missing Script Assistant Command And Verify The C4 Flow

**Files:**
- Modify: `app/lib/src/engine/assistant_actions.dart`
- Test: `app/test/engine/assistant_actions_test.dart`
- Test: `app/test/engine/scripts_test.dart`
- Test: `app/test/engine/storyboard_test.dart`
- Test: `app/test/widgets/production_screen_test.dart`

**Consumes:** Existing `generateScriptsFromEvents`, C4 structured-shot `generateStoryboards`, and policy metadata.

**Produces:** Assistant-visible `generate_scripts` command delegating to the existing script queue and test evidence for the full fake-provider C4 chain.

- [ ] **Step 1: Write failing assistant and chain tests.**

Expand the action registry expectation and add:

```dart
test('generate_scripts delegates to the script-generation command', () async {
  seedTwoEvents(engine, projectId);
  final result = await runAssistantAction(
      engine, projectId, 'generate_scripts', {'eventIds': [eventId]});
  expect(result, contains('剧本生成'));
  expect(db.select("SELECT taskClass FROM o_tasks").single['taskClass'],
      'script_generation');
});
```

Add one integration-style engine test using fake text/tool responses which runs: event-generated script fixture -> `generateDirectorPlan` -> `generateStoryboardTable` -> `generateStoryboards(replaceExisting: false)`, and asserts persisted plan, table, one associated structured shot, source hashes, and no API key/prompt body in task JSON.

- [ ] **Step 2: Run focused tests and verify failure.**

Run: `cd app && flutter test test/engine/assistant_actions_test.dart test/engine/scripts_test.dart test/engine/storyboard_test.dart --reporter compact`

Expected: FAIL because `generate_scripts` is absent or the C4 chain is incomplete.

- [ ] **Step 3: Implement only the missing command mapping.**

Add this registry item immediately after `generate_events`:

```dart
AssistantAction(
  name: 'generate_scripts',
  description: '根据已提取事件生成短剧剧本。不传 eventIds 时对项目内全部事件执行。',
  schema: {'eventIds': _idArraySchema},
  costsMoney: true,
  taskClass: 'script_generation',
),
```

Add `eventId`/`eventIds` Chinese aliases. In `runAssistantAction`, default to project events when no IDs are supplied, call only `engine.generateScriptsFromEvents(projectId, ids)`, and return the queued task summary. Do not add separate Agent logic, family-specific tools, director-plan tools, or table-generation tools in this task.

Update the existing `generate_storyboards` action description to say it creates structured shots from the saved table. Keep it a normal money-confirmed action. It must call `generateStoryboards(..., replaceExisting: false)` and, when the target script already has shots, return the explicit summary `该剧集已有分镜，请在制作面板确认替换后重新生成。` without enqueueing or deleting anything. This deliberately keeps replacement confirmation in the production UI and avoids inventing a second multi-step assistant confirmation flow in C4.

- [ ] **Step 4: Run C4-focused tests and verify pass.**

Run: `cd app && flutter test test/engine/script_plan_test.dart test/engine/storyboard_table_test.dart test/engine/storyboard_test.dart test/engine/scripts_test.dart test/engine/assistant_actions_test.dart test/widgets/script_plan_node_test.dart test/widgets/production_screen_test.dart test/widgets/storyboard_canvas_node_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Run static analysis and the full Flutter suite.**

Run: `cd app && flutter analyze && flutter test --reporter compact`

Expected: `flutter analyze` exits 0 with no diagnostics, and the complete test suite passes. Do not call external providers in these commands.

- [ ] **Step 6: Build the macOS Debug application.**

Run: `cd app && flutter build macos --debug`

Expected: exit 0 and a runnable `build/macos/Build/Products/Debug/dramaflow.app`.

- [ ] **Step 7: Commit the assistant command and verified C4 implementation.**

```bash
git add app/lib/src/engine/assistant_actions.dart \
  app/test/engine/assistant_actions_test.dart app/test/engine/scripts_test.dart \
  app/test/engine/storyboard_test.dart app/test/widgets/production_screen_test.dart
git commit -m "feat(assistant): generate scripts from events"
```

## Plan Self-Review

**Spec coverage:** C4 requirements map directly to Tasks 3 (director plans), 4 (tables), 5 (table-to-shot generation), 1/5/6 (stale state and user-confirmed replacement), and 7 (script assistant action). Prompt source order and manual mappings are covered by Tasks 2-5. The UI retains both manual editing and the desktop/mobile canvas flow in Task 6.

**Deliberate scope limits:** C4 does not add assistant commands for every production stage; only `generate_scripts` was missing from the approved scope. It does not delete stale content automatically and does not call real providers.

**Failure safety:** A queued input hash mismatch fails before a provider call. A structured-shot request validates provider output before deleting old output, then replaces rows in one savepoint. Manual upstream edits only mark stale.

**Type consistency:** `ProductionDependencyState`, source-hash helpers, stage keys, document state keys, `replaceExisting`, and task class names are defined once above and used consistently in every task.
