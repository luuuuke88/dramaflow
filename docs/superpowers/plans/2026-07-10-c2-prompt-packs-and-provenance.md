# C2 Prompt Packs And Provenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bundle ToonFlow's model-specific video prompt templates and resolve every active generation prompt from deterministic base, manual, model, and user sources with persisted provenance.

**Architecture:** Default model prompt files are copied once into the app data directory alongside the existing manual packs, then registered as editable `o_modelPrompt` rows without overwriting an existing user edit. A small synchronous resolver composes ordered prompt sources and hashes their exact content. Existing asset polish, structured storyboard, and motion-prompt paths use that resolver and write the chosen source IDs and hashes into the task metadata they create or run.

**Tech Stack:** Flutter/Dart 3.5, SQLite, `archive`, `crypto` 3.0.7, existing `o_prompt`/`o_modelPrompt`/`o_tasks` tables, ToonFlow prompt files under `../Toonflow-app/data/modelPrompt/video`.

## Global Constraints

- Do not overwrite a local prompt-pack file or an existing `o_modelPrompt.prompt` user edit during application updates.
- Preserve the C1 provider security boundary: prompt packs contain no credentials and normal configuration export remains secret-free.
- Prompt source order is exact: base task template, selected visual manual section, selected director manual section, selected model template, current data, explicit user instruction.
- Source provenance records stable source IDs and SHA-256 hashes of the exact resolved content.
- `o_tasks.relatedObjects` carries prompt provenance; no broad database-table migration is needed for C2.
- Do not enable Seedance multi-reference request behavior in C2; C3 owns request modes, references, and upstream task recovery.

---

## File Structure

- `app/assets/default_prompts/toonflow_model_prompts.zip`: bundled copies of ToonFlow's four video model templates.
- `app/pubspec.yaml`: declares the prompt archive and `crypto: ^3.0.7`.
- `app/lib/src/bootstrap/bootstrap_io.dart`: copies missing individual prompt-pack files into `<dataDir>/model_prompts`.
- `app/lib/src/engine/prompt_resolver.dart`: prompt-source data classes, source hashing, model prompt lookup, and deterministic composition.
- `app/lib/src/engine/engine.dart`: registers the default Seedance Mini row after provider defaults exist; preserves `getPromptForStageModel` as a compatibility wrapper with exact model-template selection.
- `app/lib/src/engine/assets.dart`, `app/lib/src/engine/storyboard.dart`, `app/lib/src/engine/video_track.dart`: consume `PromptResolution` and persist `promptSources` in their job metadata.
- `app/test/bootstrap/bootstrap_io_test.dart`, `app/test/engine/prompt_resolver_test.dart`, `app/test/engine/assets_test.dart`, `app/test/engine/storyboard_test.dart`, `app/test/engine/video_track_test.dart`: regression coverage.

## Task 1: Bundle And Seed ToonFlow Model Prompt Templates

**Files:**
- Create: `app/assets/default_prompts/toonflow_model_prompts.zip`
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/src/bootstrap/bootstrap_io.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/test/bootstrap/bootstrap_io_test.dart`
- Modify: `app/test/engine/engine_facade_test.dart`

**Interfaces:**
- Produces `Future<void> seedBundledModelPrompts(String dataDir, {AssetBundle? bundle})`.
- Produces `<dataDir>/model_prompts/video/{seedance2Multi-parameterMode,universalFirstAndLastFrameMode,universalMulti-parameterMode,wan2.6Single-imageFirstFrameMode}.md`.
- Produces an editable default row for `volcengine:doubao-seedance-2-0-mini-260615` with `path='video/seedance2Multi-parameterMode.md'` and `fileName='seedance2Multi-parameterMode.md'`.

- [x] **Step 1: Write failing seed and model-template registration tests.**

  Extend the bootstrap fixture archive with a `model_prompts/video/seedance2Multi-parameterMode.md` entry. Assert that a custom local file does not suppress the missing default file, and that a second seed does not replace an edited default file. In `engine_facade_test.dart`, boot with an explicit `InMemoryCredentialStore`, create the default model-prompt source directory, and assert exactly one Seedance Mini model prompt row is created with nonempty prompt text and the expected path.

  ```dart
  expect(File(p.join(dataDir, 'model_prompts', 'video', 'seedance2Multi-parameterMode.md')).existsSync(), isTrue);
  expect(row['path'], 'video/seedance2Multi-parameterMode.md');
  expect(row['fileName'], 'seedance2Multi-parameterMode.md');
  expect((row['prompt'] as String).trim(), isNotEmpty);
  ```

- [x] **Step 2: Run the focused tests and verify both fail before implementation.**

  Run: `cd app && flutter test test/bootstrap/bootstrap_io_test.dart test/engine/engine_facade_test.dart`

  Expected: FAIL because the current bootstrap only seeds `skills/`, and no default model-prompt row exists.

- [x] **Step 3: Build the bundled archive and add per-file prompt seeding.**

  Create `assets/default_prompts/toonflow_model_prompts.zip` from the four original files, preserving their `video/` relative paths. Add the archive path to `pubspec.yaml`. In `bootstrap_io.dart`, add a separate archive constant and function which writes only `model_prompts/**` entries to `<dataDir>/model_prompts`, skipping existing targets.

  ```dart
  const _defaultPromptsZipAsset =
      'assets/default_prompts/toonflow_model_prompts.zip';

  Future<void> seedBundledModelPrompts(String dataDir, {AssetBundle? bundle}) =>
      _seedArchivePrefix(
        dataDir: dataDir,
        asset: _defaultPromptsZipAsset,
        prefix: 'model_prompts',
        bundle: bundle,
      );
  ```

  Call it from `bootstrap()` after `seedBundledDefaultSkills(dataDir)` and before `Engine.boot`.

- [x] **Step 4: Register the editable Seedance template after provider defaults.**

  In `Engine.boot`, call a private `_seedBundledModelPromptRows(db, dataDir)` after `_seedDefaults`. It reads `<dataDir>/model_prompts/video/seedance2Multi-parameterMode.md` and inserts only when no `o_modelPrompt` row exists for the same `(vendorId, model, path)`. Use the exact values below.

  ```dart
  const vendorId = 'volcengine';
  const modelId = 'doubao-seedance-2-0-mini-260615';
  const path = 'video/seedance2Multi-parameterMode.md';
  const fileName = 'seedance2Multi-parameterMode.md';
  ```

  Do not automatically return this full multi-parameter template from the legacy single-shot `getPromptForStageModel` path; C3 will pass its template path explicitly when it builds a compatible request.

- [x] **Step 5: Run focused tests and static analysis.**

  Run: `cd app && flutter test test/bootstrap/bootstrap_io_test.dart test/engine/engine_facade_test.dart && flutter analyze`

  Expected: PASS. Confirm with `unzip -l assets/default_prompts/toonflow_model_prompts.zip` that all four source files are present.

- [x] **Step 6: Commit the bundled prompt pack.**

  ```bash
  git add app/assets/default_prompts app/pubspec.yaml app/pubspec.lock app/lib/src/bootstrap/bootstrap_io.dart app/lib/src/engine/engine.dart app/test/bootstrap/bootstrap_io_test.dart app/test/engine/engine_facade_test.dart
  git commit -m "feat(prompts): bundle ToonFlow video prompt templates"
  ```

## Task 2: Add Deterministic Prompt Resolution And Provenance

**Files:**
- Create: `app/lib/src/engine/prompt_resolver.dart`
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/test/engine/prompt_resolver_test.dart`

**Interfaces:**
- Produces `class PromptSource { String id; String kind; String version; String content; }`.
- Produces `class PromptResolution { String system; List<PromptSource> sources; Map<String, dynamic> toTaskJson(); }`.
- Produces `PromptResolution Engine.resolvePrompt({required int projectId, required String basePromptKey, String? visualSection, String? directorSection, String? modelStage, String? modelPromptPath})`.
- Produces `String promptContentHash(String content)` using SHA-256 hex.

- [x] **Step 1: Write exact-order and hash-stability tests.**

  Construct a project with visual pack `ink_pack`, director pack `fast_cut`, a base prompt, and an explicit model prompt. Assert `resolution.system` joins the four content strings in order using exactly two newlines; assert its source IDs are `base:<key>`, `visual:ink_pack:<section>`, `director:fast_cut:<section>`, `model:<provider>:<model>:<path>`; assert an unchanged source produces the same SHA-256 and an edited manual produces a different source version.

  ```dart
  expect(resolution.system, 'BASE\n\nVISUAL\n\nDIRECTOR\n\nMODEL');
  expect(resolution.sources.map((s) => s.id), [
    'base:storyboard_gen',
    'visual:ink_pack:director_storyboard',
    'director:fast_cut:director_storyboard_table_narrative',
    'model:volcengine:seedance:video/seedance2Multi-parameterMode.md',
  ]);
  expect(resolution.toTaskJson()['promptSources'], isA<List>());
  ```

- [x] **Step 2: Run resolver tests and verify they fail because the API is absent.**

  Run: `cd app && flutter test test/engine/prompt_resolver_test.dart`

  Expected: FAIL with undefined `resolvePrompt` or `PromptResolution`.

- [x] **Step 3: Implement the resolver with strict source selection.**

  Add `crypto: ^3.0.7`. `promptContentHash` must return `sha256.convert(utf8.encode(content)).toString()`. The resolver reads the effective base content from `o_prompt` (`useData` when nonempty, otherwise `data`), then gets manual sections by stable `pack` ID, then gets a model prompt only when `modelPromptPath` is supplied. Model lookup resolves `binding.<modelStage>` and queries `o_modelPrompt` by exact `vendorId`, `model`, and `path`.

  A missing selected pack section throws `EngineException(errPromptMissing, {'type': '<kind>:<pack>:<section>'})`; a missing optional director/model source is omitted only when its corresponding parameter is null. Empty source content is omitted. `PromptResolution.toTaskJson()` returns only `id`, `kind`, and `version`, never prompt text.

- [x] **Step 4: Preserve compatibility without accidental template selection.**

  Rewrite `Engine.getPromptForStageModel(type, modelStage)` to select an override only when `o_modelPrompt.fileName == type` or `path == type` or `path LIKE '%/$type%'`; otherwise return `getPrompt(type)`. This prevents a Seedance template file from being selected by an older one-shot caller solely because it belongs to the same model.

- [x] **Step 5: Run resolver and existing prompt tests.**

  Run: `cd app && flutter test test/engine/prompt_resolver_test.dart test/engine/engine_facade_test.dart test/engine/video_track_test.dart && flutter analyze`

  Expected: PASS. Existing tests that install a `fileName='video_prompt_gen'` override still resolve it; the new bundled `seedance2Multi-parameterMode.md` row does not change legacy behavior.

- [x] **Step 6: Commit prompt resolution.**

  ```bash
  git add app/pubspec.yaml app/pubspec.lock app/lib/src/engine/prompt_resolver.dart app/lib/src/engine/engine.dart app/test/engine/prompt_resolver_test.dart app/test/engine/engine_facade_test.dart app/test/engine/video_track_test.dart
  git commit -m "feat(prompts): resolve ordered sources with provenance"
  ```

## Task 3: Route Active Generation Paths Through The Resolver

**Files:**
- Modify: `app/lib/src/engine/assets.dart`
- Modify: `app/lib/src/engine/storyboard.dart`
- Modify: `app/lib/src/engine/video_track.dart`
- Modify: `app/test/engine/assets_test.dart`
- Modify: `app/test/engine/storyboard_test.dart`
- Modify: `app/test/engine/video_track_test.dart`

**Interfaces:**
- `Engine.recordTaskPromptSources(int taskId, PromptResolution resolution)` merges `resolution.toTaskJson()` into `o_tasks.relatedObjects`.
- Asset prompt polishing uses `basePromptKey='asset_prompt_polish'` plus its asset-kind visual section.
- Structured storyboard generation uses `basePromptKey='storyboard_gen'`, visual `director_storyboard`, and `modelStage='storyboard_gen'`.
- Current one-shot motion prompt generation uses `basePromptKey='video_prompt_gen'`, visual `art_storyboard_video`, and `modelStage='shot_video'`; it does not request a model-specific full Seedance template before C3.

- [x] **Step 1: Write failing provenance tests for queued generators.**

  In the asset and storyboard tests, create visual/director packs with recognizable sections, run one queued generation, then read `o_tasks.relatedObjects` and assert `promptSources` has the expected stable IDs and hashes. Assert the fake gateway receives base content before visual content. In the video-track test, assert the motion generator system prompt includes the active visual video section while maintaining the existing generic/model-override behavior.

  ```dart
  final task = db.select('SELECT relatedObjects FROM o_tasks WHERE id=?', [taskId]).single;
  final data = jsonDecode(task['relatedObjects'] as String) as Map<String, dynamic>;
  expect((data['promptSources'] as List).first['id'], 'base:storyboard_gen');
  expect(system.indexOf('BASE'), lessThan(system.indexOf('VISUAL')));
  ```

- [x] **Step 2: Run focused generator tests and verify absent provenance fails.**

  Run: `cd app && flutter test test/engine/assets_test.dart test/engine/storyboard_test.dart test/engine/video_track_test.dart`

  Expected: FAIL because current tasks contain no `promptSources` and systems do not consistently include the selected sections.

- [x] **Step 3: Implement task metadata merge and integrate source selection.**

  Add `recordTaskPromptSources` to `Engine`; parse current `relatedObjects`, replace only `promptSources`, and update the same task row. In each task runner, resolve the prompt immediately before its gateway call, record provenance using the running task ID, and pass `resolution.system` to the gateway. Do not store raw prompt content in `relatedObjects`.

  Seed the `asset_prompt_polish` base prompt as an empty string so the manual remains the authoritative system instruction until a project deliberately edits its base task template. C4 will add director-plan and storyboard-table generators using the same resolver.

- [x] **Step 4: Run generation tests, all tests, analysis, and macOS Debug build.**

  Run: `cd app && flutter test test/engine/assets_test.dart test/engine/storyboard_test.dart test/engine/video_track_test.dart && flutter test && flutter analyze && flutter build macos --debug`

  Expected: all tests pass, analysis is clean, and the native build succeeds. Inspect one queued task's `relatedObjects` to confirm it contains source IDs/hashes but no API key or full prompt content.

- [x] **Step 5: Commit C2 integration.**

  ```bash
  git add app/lib/src/engine/assets.dart app/lib/src/engine/storyboard.dart app/lib/src/engine/video_track.dart app/lib/src/engine/engine.dart app/test/engine/assets_test.dart app/test/engine/storyboard_test.dart app/test/engine/video_track_test.dart
  git commit -m "feat(pipeline): record prompt source provenance"
  ```

## C2 Completion Review

- [ ] Run `rg -n "seedance2Multi-parameterMode|promptSources|resolvePrompt" app/lib/src app/test` and confirm all three have production and test coverage.
- [ ] Run `git diff 85f5a77..HEAD -- app/lib app/test app/pubspec.yaml` and confirm C2 did not introduce video-request mode logic reserved for C3.
- [ ] Update this plan's checkboxes with actual command evidence and commit the completed plan only with C2's final code commit.
