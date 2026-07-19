# DramaFlow ToonFlow Core Parity Convergence Design

Date: 2026-07-10

Status: approved in conversation for specification writing

> **历史状态**：本设计已被 2026-07-17 的 100% 复刻总路线部分取代。尤其本文件
> 关于“系统安全凭证设施/密钥不落 SQLite”的约束已于 2026-07-19 明确废止；当前
> 凭证策略为 `DbCredentialStore` → 本地 SQLite `o_secret`，不使用系统钥匙串。

## 1. Objective

Build a single Flutter application that reproduces ToonFlow's useful short-drama production workflow, while removing or deferring infrastructure that does not improve the first successful episode.

Core parity means a user can complete this workflow with the same production concepts and comparable control:

```text
Create project and select visual/director manuals
  -> import novel
  -> extract and analyze events
  -> generate scripts
  -> extract assets
  -> generate asset images
  -> generate director plan and storyboard table
  -> create structured storyboard shots
  -> generate first frames
  -> generate Seedance videos with the selected mode and references
  -> choose video versions and bind audio
  -> compose and play the final episode
```

Parity is judged by this real workflow, persisted data, generated media, and recovery behavior. Matching ToonFlow table names, page count, or code volume is not completion evidence.

## 2. Evidence From The Current Codebase

The current Flutter application is substantial and internally tested. At the time of this audit:

- `flutter analyze` completed with no issues.
- `flutter test` completed with 493 passing tests.
- Project, novel, event, script, asset, storyboard, task, provider, TTS, assistant, workbench, and native composition modules exist.
- The SQLite schema mirrors most ToonFlow tables and adds local composition fields and `o_timelineClip`.

The tests prove the implemented contracts, but they do not prove ToonFlow-equivalent behavior or a real provider workflow. The following gaps are authoritative for the convergence work.

| Area | Current evidence | Parity judgment |
| --- | --- | --- |
| Visual manual | Asset prompt polishing reads selected visual-manual files | Partial |
| Director manual | Can be selected, edited, and persisted, but no generation path consumes it | Missing core wiring |
| Director plan | `scriptPlan` is a manually edited Markdown record | Missing generation and downstream dependency |
| Storyboard table | Manually edited Markdown record, separate from structured shots | Missing generation and downstream dependency |
| Seedance video | Sends one required first-frame image | Missing text, first/last-frame, and multi-reference modes |
| Video parameters | Ratio is hard-coded to `1:1`; audio is hard-coded on; duration and resolution are global | Incorrect for project/model capabilities |
| Model prompt templates | Management UI and table exist, but Seedance templates are not bundled and selected by default | Missing default behavior |
| Assistant | Can call 12 existing actions, but does not generate scripts, director plans, or storyboard tables | Useful shortcut, not ToonFlow Agent parity |
| Agent vector/vision settings | Binding controls exist without a runtime feature path | Misleading overdesign |
| Database upgrade | Opening an older schema deletes and recreates the database | Release blocker |
| Provider credentials | API keys are stored in provider JSON and included in configuration export | Release security blocker |
| Web | Builds a preview-only page without the engine | Explicitly deferred |
| Real providers | Unit and widget tests primarily use controlled gateways | Real end-to-end acceptance missing |

Relevant source evidence includes:

- `app/lib/src/engine/providers/volcengine_video.dart`
- `app/lib/src/engine/db.dart`
- `app/lib/src/engine/manuals.dart`
- `app/lib/src/engine/assets.dart`
- `app/lib/src/engine/script_plan.dart`
- `app/lib/src/engine/storyboard_table.dart`
- `app/lib/src/engine/assistant_actions.dart`
- `app/lib/src/screens/settings_screen.dart`
- `app/lib/src/screens/production/workbench_screen.dart`
- ToonFlow references under `../Toonflow-app/src` and `../Toonflow-app/data/modelPrompt`

## 3. Chosen Product Boundary

The first release targets core workflow parity, not complete feature parity.

### 3.1 Required in the first release

- Native Flutter UI and embedded Dart engine with no required companion server.
- macOS as the first real acceptance platform.
- iOS/iPadOS and Android after the Mac workflow passes.
- Project, novel, event, script, asset, production, dubbing, task, and settings pages.
- Bundled ToonFlow visual and director manual packs.
- Configurable text, image, video, and TTS providers.
- Model-to-stage bindings and editable model-specific prompts.
- Seedance text, first-frame, first/last-frame, and multi-reference generation modes when declared by the configured model.
- Persistent tasks, retryable failures, upstream task recovery, and local media.
- Native episode composition with shot order, selected candidates, audio, and basic transitions.
- A simple assistant that invokes the same workflow commands used by UI buttons.

### 3.2 Retained but not expanded

- Desktop production node canvas.
- Mobile production tabs using the same underlying data.
- Image flow editor and image version management.
- Existing advanced timeline implementation remains in source until a later deletion decision.
- Existing schema-only legacy tables may remain when dropping them would create migration risk.

### 3.3 Hidden or removed from the first-release UI

- Agent embedding/vector-recall binding.
- Agent vision binding until a real user workflow consumes it.
- Vector database or `o_memoryVector` runtime reads and writes.
- Multi-layer decision/execution/supervision Agents.
- Custom JavaScript skill execution.
- Project notes, assistant deployment, and Markdown skill administration as primary workflow surfaces. They may remain behind an advanced section if retaining them is cheaper than deleting them.
- Advanced batch ripple, group alignment, group splitting, and similar NLE actions from the default workbench toolbar.

### 3.4 Deferred

- Full Flutter Web application and browser-side composition.
- Windows packaging.
- Complete professional NLE parity.
- Full ToonFlow multi-Agent hierarchy and long-term semantic memory.
- Accounts, billing, cloud synchronization, and the future first-party API relay.
- Importing an existing ToonFlow database. A later one-time importer is safer than two applications sharing one database.

## 4. Architecture

The application has one workflow implementation. UI buttons and the assistant call the same command layer.

```text
Flutter UI / simple assistant
          |
          v
Production command layer
          |
          +--> prompt-pack resolver
          +--> model capability validator
          |
          v
Persistent job queue
          |
          +--> text adapter
          +--> image adapter
          +--> video adapter
          +--> TTS adapter
          |
          v
SQLite records + local media
          |
          v
Native platform composer
```

### 4.1 Production command layer

The command layer owns the public use cases:

- generate events
- generate scripts from events
- extract and generate assets
- generate director plan
- generate storyboard table
- materialize structured storyboard shots
- generate first-frame images
- generate motion prompts
- generate video candidates
- bind or synthesize audio
- compose an episode

Each command performs input validation, creates or updates domain state, and submits a queue task when provider work is required. The assistant contains no duplicate production logic.

### 4.2 Prompt-pack resolver

The resolver composes prompts in this deterministic order:

```text
base task template
  + selected visual-manual section
  + selected director-manual section
  + selected model-specific template
  + current project/script/asset/storyboard data
  + explicit user instruction
```

Every generation task records the IDs or versions of prompt sources it used. This makes results reproducible and failures diagnosable.

Prompt sections map to stages rather than being loaded ad hoc. The first mapping is:

| Stage | Visual manual section | Director manual section | Model prompt |
| --- | --- | --- | --- |
| Asset role prompt | `art_character` or derivative | None | Image model override when present |
| Asset scene prompt | `art_scene` or derivative | None | Image model override when present |
| Asset prop prompt | `art_prop` or derivative | None | Image model override when present |
| Director plan | `director_planning_style` | `director_planning_narrative` | Text model override when present |
| Storyboard table | `director_storyboard_table_style` | `director_storyboard_table_narrative` | Text model override when present |
| Structured shots | `director_storyboard` | Relevant narrative context | Text model override when present |
| First frame | Prefix plus referenced asset definitions | None | Image model override when present |
| Motion prompt | `art_storyboard_video` | Relevant plan/table context | Video model prompt, including Seedance mode template |

Missing required manual sections produce an actionable validation error before paid generation starts.

### 4.3 Visual and director manual storage

Bundled defaults use ToonFlow's directory layout under `skills/art_skills` and `skills/story_skills`. A manifest gives each pack a stable `packId`, display name, version, cover list, and supported sections.

Project records reference stable pack IDs. Display names may change without breaking projects.

The current lightweight `o_artStyle` library and visual-manual packs must not remain two competing sources for `o_project.artStyle`. In the converged UI:

- the visual-manual gallery is the only project style selector;
- bundled visual packs provide the default gallery data;
- `o_project.artStyle` temporarily stores the visual `packId` for schema compatibility;
- `o_artStyle` is not derived from bundled manuals and is not shown in the project wizard;
- existing lightweight rows can be preserved as legacy data until a separate migration policy is required.

Therefore, the current uncommitted approach that derives lightweight `o_artStyle` rows from bundled visual manuals must be revised before it is committed as product behavior.

## 5. Provider And Model Capability Design

Provider connection data and model capability data are separate.

### 5.1 Provider connection

A provider instance owns:

- stable provider ID and display name
- protocol adapter type
- base URL and a credential reference
- request, polling, and download timeouts
- enabled state

Raw API keys are stored through the operating system's secure credential facility, using Keychain on Apple platforms and Keystore-backed secure storage on Android. SQLite stores only the provider configuration and credential reference. Configuration export excludes credentials by default; an explicit credential export, if added later, must be encrypted and is outside this release.

Loopback development providers such as `azt` may use a non-secret placeholder value such as `local`, but this exception does not change remote-provider credential handling. Mobile builds never assume a desktop loopback provider exists.

The first adapters are:

- OpenAI-compatible text, image, and TTS
- Volcengine Seedance video

Additional provider-specific protocols are added only when a real configured model cannot be expressed by these adapters.

### 5.2 Model capability

A model declaration owns:

- modality: text, image, video, or TTS
- supported input modes
- image, video, and audio reference limits
- first-frame and last-frame requirements
- supported duration and resolution values
- supported aspect ratios or provider ratio behavior
- audio generation support
- model-specific prompt template binding

The UI derives its controls from this declaration. Unsupported combinations are rejected locally before a request is submitted.

### 5.3 Seedance request contract

Video generation receives a structured request rather than a prompt plus one path:

```text
model
mode
prompt
references[] { mediaType, role, localPath }
duration
resolution
ratio
generateAudio
projectId
storyboardId
videoTrackId
```

Reference roles include first frame, last frame, image reference, video reference, and audio reference. The Volcengine adapter translates this request into the provider `content` list.

The project ratio is never hard-coded. Per-shot duration takes priority over the project/model default. Audio generation follows the user's choice and model capability.

## 6. Page Behavior

### 6.1 Project page

- Create or edit a project with project type, genre, introduction, visual pack, director pack, image model, image quality, video model, video mode, ratio, and defaults.
- Show missing provider or model bindings before entering paid workflow stages.
- Ship with visible default visual and director packs on first launch.

### 6.2 Novel and event pages

- Import TXT, Markdown, and DOCX chapter content.
- Generate events with visible per-chapter state and failure reason.
- Retry selected failures without duplicating successful event records.
- Analyze selected events for adaptation decisions.

### 6.3 Script page

- Generate scripts from selected events.
- Add, import, edit, delete, and export scripts.
- Extract assets and show extraction state.
- The simple assistant exposes script generation through the same command used by this page.

### 6.4 Asset page

- Manage role, scene, prop, audio, and reusable clip assets.
- Polish prompts using the selected visual pack.
- Generate image versions with references, model, quality, ratio/resolution, and low default concurrency.
- Select, replace, delete, and redraw versions.

### 6.5 Production page

The desktop node canvas remains the production overview. Its nodes are real dependencies:

```text
script
  -> director plan
  -> storyboard table
  -> structured storyboard panel
  -> video workbench
```

Assets branch from the script and feed structured shots and first-frame generation.

The director plan and storyboard table are generated documents with manual editing, not decorative note fields. Regenerating or editing upstream content marks affected downstream outputs stale and asks before replacement.

Mobile uses a linear tab/step presentation over the same records and commands; mobile is not required to imitate the desktop canvas layout.

### 6.6 Video workbench

The default workbench supports:

- shot reorder
- motion-prompt generation and editing
- model mode and reference-media selection
- per-shot duration, resolution, ratio, and audio controls allowed by the model
- multiple video candidates and selected candidate
- shot audio binding
- basic transition
- preview and episode export

Advanced timeline functions stay frozen and hidden from the default toolbar. No new advanced NLE behavior is added before the real core workflow passes.

### 6.7 Dubbing and tasks

- Audio can be uploaded or created through an OpenAI-compatible TTS model.
- Roles can be manually or automatically matched to audio assets.
- Shots can bind audio assets for composition.
- The task center shows queued, submitted, processing, success, failed, canceled, and recoverable states with structured reasons.

### 6.8 Settings and assistant

Settings expose provider connections, model declarations, stage bindings, prompt templates, storage, appearance, and data export/import.

Agent embedding, Agent vision, advanced skill management, deployment tuning, and project-note search are absent from the default first-release settings.

The assistant can inspect project progress and invoke the command layer. It is not a separate multi-Agent production system.

## 7. Persistence, Migration, And Recovery

### 7.1 Database migration

Opening an older database must run ordered, transactional migrations. It must never delete the database or media directory as an upgrade strategy.

Each migration:

- checks the current `PRAGMA user_version`;
- applies one version step in a transaction;
- verifies required columns and indexes;
- updates `user_version` only after success;
- leaves the original database usable when a migration fails.

A pre-migration backup is created for on-device release upgrades where platform storage permits it.

### 7.2 Task state and provider recovery

Provider jobs store structured state in existing task fields or a narrowly scoped migration:

```json
{
  "stage": "shot_video",
  "providerId": "volcengine",
  "modelId": "doubao-seedance-2-0-mini-260615",
  "upstreamTaskId": "...",
  "requestFingerprint": "...",
  "retryable": true,
  "promptSources": ["..."],
  "attempt": 1
}
```

On restart:

- a task with an upstream ID resumes polling;
- a task that was never accepted upstream may be resubmitted only after fingerprint and state checks;
- completed rows are not regenerated;
- a retry creates a visible new attempt without deleting the prior reason;
- cancellation attempts upstream cancellation when supported and always stops local polling.

This prevents duplicate paid submissions.

### 7.3 Error contract

Errors persist as structured JSON with:

- stable code
- localized display parameters
- provider and stage
- retryable flag
- upstream task ID when available
- short diagnostic message

The task center, row status, and assistant render the same error contract.

## 8. Native Composition

The first-release composer contract is intentionally smaller than a professional editor:

- order selected shot videos by storyboard index;
- respect chosen per-shot duration where supported;
- mix bound shot audio;
- apply supported basic transitions;
- write one playable MP4;
- register the result as a reusable clip asset.

macOS and iOS use AVFoundation. Android uses Media3. A platform may reject an unsupported transition before export, but it must not silently drop requested audio or effects.

Flutter Web remains a preview build and is excluded from this acceptance cycle.

## 9. Implementation Order

### C1. Data safety and misleading UI removal

- Replace delete-and-recreate schema behavior with migrations.
- Move remote provider credentials out of SQLite and exclude them from normal configuration export.
- Remove or hide dead Agent vector and vision bindings.
- Define visual/director pack IDs and remove the duplicate project style selector.
- Freeze and hide advanced timeline controls.

### C2. Bundled content and prompt resolution

- Bundle default visual and director packs without deriving duplicate `o_artStyle` rows.
- Bundle model-specific prompt templates, including Seedance multi-parameter mode.
- Implement the stage-to-manual-section resolver.
- Record prompt source versions with tasks.

### C3. Seedance capability-driven generation

- Add structured video requests and model capabilities.
- Implement text, first-frame, first/last-frame, and multi-reference translation.
- Bind workbench controls to model capabilities.
- Persist and recover upstream video tasks.

### C4. Real production dependencies

- Generate and persist director plans.
- Generate storyboard tables from plan, script, and manuals.
- Materialize structured shots from the table and project assets.
- Add stale/downstream replacement handling.
- Add the missing script-generation assistant command.

### C5. Episode close and real acceptance

- Verify candidate selection, shot audio, basic transitions, and native MP4 export.
- Run a real Mac workflow with configured text, image, Seedance, and optional TTS providers.
- Fix all workflow-blocking defects and repeat the real run.
- Validate iOS/iPadOS and Android only after Mac acceptance passes.

## 10. Testing And Acceptance

### 10.1 Automated tests

- Migration tests start from each supported historical schema and assert preserved project/media references.
- Credential tests assert remote API keys are absent from SQLite rows, logs, and normal configuration exports.
- Prompt tests assert exact source order and stage-to-manual mapping.
- Capability tests cover valid and invalid Seedance mode/reference combinations.
- Adapter tests assert request content roles, ratio, duration, resolution, and audio flags.
- Recovery tests prove restart polling does not create a second paid task.
- Widget tests assert controls are derived from model capabilities and real commands are invoked.
- Composition tests verify order, audio, transitions, output registration, and unsupported-effect errors.

Tests that merely assert a page, label, or table exists do not count as parity evidence for a workflow capability.

### 10.2 Real Mac acceptance

The release gate is a user-observed run using real configured providers:

1. Create a fresh novel-based project.
2. Select a bundled visual pack and director pack.
3. Import a small novel and generate events.
4. Generate at least one script.
5. Extract and generate role, scene, and prop assets.
6. Generate a director plan, storyboard table, and structured shots.
7. Generate first frames with associated asset references.
8. Generate Seedance video in at least first-frame and multi-reference modes when the selected model supports them.
9. Select video candidates and bind or generate audio.
10. Export and play the final MP4.
11. Restart the app during one long provider task and verify recovery without duplicate submission.
12. Inspect failures in the task center and successfully retry one controlled failure.

Completion requires the user to accept both the produced episode and the experience of each step. Automated tests cannot replace this gate.

## 11. Decision Log

- Chosen approach: core workflow parity.
- Rejected approach: complete ToonFlow feature parity in the first release, because it keeps Agent and NLE work on the critical path.
- Rejected approach: a minimal linear generator with no production canvas, because the canvas is a useful ToonFlow production overview on desktop.
- The assistant is a natural-language command surface, not an independent production architecture.
- Desktop keeps the node canvas; mobile uses the same data in linear tabs.
- Visual manuals replace the duplicate lightweight project-style selector.
- Advanced timeline behavior is frozen and hidden, not immediately deleted.
- Mac real acceptance precedes iOS/iPadOS and Android acceptance.
- Existing ToonFlow project import and full Web support are deferred.
