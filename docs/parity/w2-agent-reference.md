# W2 Agent 体系移植 — Scope Reference

Status: Synthesis of completed W0 audit findings (`docs/parity/master-checklist.md`, do not modify). Every claim below traces to a checklist row ID or a file:line verified during this pass. This document is a scope reference for the future W2 milestone; it prescribes no implementation.

Baseline: `Toonflow-app` backend (SHA-256 manifest baseline). All ToonFlow citations are backend TypeScript; all DramaFlow citations are `app/lib/src/…`.

## Evidence refresh — 2026-07-19

The current Flutter baseline was re-run before this reference was used for
implementation planning:

```text
flutter test --concurrency=1 \
  test/engine/assistant_actions_test.dart \
  test/engine/assistant_chat_test.dart \
  test/engine/assistant_skills_deploy_test.dart \
  test/widgets/agent_chat_screen_test.dart \
  test/widgets/canvas_chat_panel_test.dart
# 45 passed

flutter analyze lib/src/engine/assistant_actions.dart \
  lib/src/engine/assistant_chat.dart \
  lib/src/engine/assistant_deploy.dart \
  lib/src/engine/assistant_skills.dart \
  lib/src/engine/project_notes.dart \
  lib/src/screens/agent/agent_chat_screen.dart \
  lib/src/screens/production/canvas_chat_panel.dart
# No issues found
```

These are in-memory/fake-gateway tests. They prove the documented current
flat-assistant behavior, confirmation gate, persistence, and responsive entry
surfaces; they do **not** prove parity with ToonFlow's layered Agent system and
do not invoke text, image, audio, or video providers.

### Deployment controls recheck — 2026-07-19

This pass re-ran the deployment and responsive Agent-entry evidence directly:

```text
flutter test --concurrency=1 \
  test/engine/assistant_skills_deploy_test.dart \
  test/widgets/agent_chat_screen_test.dart
# 17 passed

flutter analyze lib/src/engine/assistant_deploy.dart \
  lib/src/engine/assistant_chat.dart \
  lib/src/engine/assistant_actions.dart \
  lib/src/screens/agent/agent_chat_screen.dart \
  test/engine/assistant_skills_deploy_test.dart \
  test/widgets/agent_chat_screen_test.dart
# No issues found
```

The result intentionally locks the present reduced contract: Flutter seeds and
shows exactly `scriptAgent` and `productionAgent`; their model binding,
`temperature`, and `maxOutputTokens` can persist. ToonFlow seeds three active
top-level Agent deployments (plus its disabled TTS row) and 13 colon-keyed
advanced sub-Agent deployments, then exposes normal/advanced mode selection,
single-item tuning, and batch tuning in `agentConfog.vue`. Flutter has no
`agentUseMode`, no advanced deployment rows, and no batch deployment action.
The passing tests prove this current behavior is stable on desktop and at a
390 px mobile entry, not that the omitted original controls are equivalent.

### Managed skill-library refresh — 2026-07-21

`f430c17` added a real application-owned Markdown skill workspace without
changing the Agent activation contract. `assistant_skill_library.dart` now
copies an imported skill into `dataDir/skills/<id>/SKILL.md`, preserves sibling
resources, rejects path escape and external legacy rows, and reconciles only
package entry files. `_AssistantSkillsPane` exposes import, scan, search,
preview and edit/save on desktop and 390dp layouts. The focused library,
deployment and Agent-page suites passed, followed by the full Flutter suite,
`flutter analyze`, macOS debug build and the 538/538 parity-inventory check.
All evidence used temporary files, in-memory SQLite and fake gateways.

This closes file management and reliable rescan only. The next evidence refresh
below records the separate Agent runtime protocol.

### On-demand skill-runtime refresh — 2026-07-21

Commits `441e93e`, `71a8123` and `fbb6200` replace blanket Markdown-body
injection with the original observable three-step shape: an initial metadata
catalogue, `activate_skill`, then constrained `read_skill_file`. The catalogue
contains only enabled managed skills' stable ID/name/description; a fake gateway
asserts that a body is absent from the initial system prompt and present only in
the subsequent tool-result history. Activation is persisted per project plus
explicit `script`/`production` family in `o_agentWorkData`, so the two visible
entry points never share state.

The engine rejects disabled/unknown skills, resources before activation, path
traversal, deleted entries and package symlinks; a failed body read writes no
activation residue. `clearAssistantChat` clears the paired activation row. The
local test suite also locks three context-tool hops without weakening manual's
one business-action or auto's five business-action boundaries. All evidence is
in-memory SQLite plus fake gateways; it makes no provider request.

This does **not** add original stage-specific skill attribution, sub-agent tool
bags, decision/execution/supervision orchestration, vector RAG, summaries or
streaming. Those remain W2 work rather than being hidden behind the word
"skills".

---

## 1. ToonFlow's actual Agent architecture

ToonFlow ships **two separate Agent families** — `scriptAgent` ("统筹"/剧本) and `productionAgent` ("视频策划"/制作画布). Their decision prompts and domain tool bags are distinct, while both intentionally share the same `Memory.getTools()` retrieval tool and streaming-consumption pattern. Each is a **layered decision → execution → supervision orchestration** driven by real streaming LLM tool-calls, backed by a **3-tier memory subsystem** and an **on-demand Markdown skill loader**. Entry is over socket.io (`src/socket/routes/scriptAgent.ts:21-94`, `productionAgent.ts:21-104`; row `W7F-SOCKET-AGENT-001`) with events `chat` / `stop` (AbortController) / `updateThinkConfig` (think toggle + 0–3 level) / `updateContext`.

### 1.1 Decision-layer orchestration (`runDecisionAI`)

Both families follow the same shape (`productionAgent/index.ts:43-95`, `scriptAgent/index.ts:41-89`):

1. Read the family's decision skill as the full system message — `production_agent_decision.md` (267 lines) / `script_agent_decision.md` (235 lines), read whole, no truncation (`productionAgent/index.ts:48-49`, `scriptAgent/index.ts:46-47`).
2. Assemble project-model info + **3-tier memory context** via `buildMemPrompt(await memory.get(text))` (`productionAgent/index.ts:27-41,69`; `scriptAgent/index.ts:25-39,49`).
3. Call `u.Ai.Text(...).stream()` with a merged tool bag: `{ ...memory.getTools(), ...useTools(), ...createSubAgent() }` (`productionAgent/index.ts:78-82`).
4. Stream is consumed by `consumeFullStream` (`productionAgent/index.ts:397-448`), which dispatches `reasoning-start/delta/end` (live "思考中…" segment with elapsed timer) and `text-delta` into message bubbles in real time, per token.
5. `onFinish` writes the decision output (XML tags stripped by `removeAllXmlTags`) back into memory (`productionAgent/index.ts:83-85`).

### 1.2 Sub-agent spawning (`createSubAgent`)

Sub-agents are **first-class LLM tool calls** the decision layer invokes. Each reads its own dedicated skill md as system prompt, streams into a **separately-named message bubble**, and on completion writes its (XML-stripped) product into memory before the parent re-opens a "视频策划" bubble (`runAgent`, `productionAgent/index.ts:100-138`; `scriptAgent/index.ts:95-133`).

- **productionAgent spawns 7 sub-agents** (`index.ts:366-374`): `run_sub_agent_derive_assets` (:197), `_generate_assets` (:219), `_director_plan` (:241), `_storyboard_gen` (:266), `_storyboard_panel` (:300), `_storyboard_table` (:326), `_supervision` (:350, bubble name "监制"). The first six carry `activate_skill` sub-tools (art/director skills); several also inject an XML output contract (e.g. `<scriptPlan>`, `<storyboardItem …>`). Rows `W8-AGENTTOOL-PRODUCTION-001`, `W9C-PRODSKILL-CORE-001`, `W9C-PRODSKILL-PIPELINE-001`.
- **scriptAgent spawns 4 sub-agents** (`index.ts:228-233`): `run_sub_agent_storySkeleton` (:141), `_adaptationStrategy` (:161), `_script` (:181, carries the project's available-script `id:name` list), `run_supervision_agent` (:211, bubble name "编辑"). Each demands its product be written as `<storySkeleton>` / `<adaptationStrategy>` / `<scriptItem>` XML for the right-side workspace panels. Rows `W8-AGENTTOOL-SCRIPTAGENT-001`, `W9C-SCRIPTSKILL-CORE-001`.

The decision skills encode strict pipeline choreography: productionAgent's 6-stage pipeline (导演规划 → 衍生资产分析 → 衍生资产生成 → 分镜表 → 分镜面板写入 → 分镜图生成), supervision red-lines R1–R4 and a 20-item storyboard-table audit rubric with A–D scoring; scriptAgent's mandatory 6-parameter project init + 3-stage serial pipeline (故事骨架 → 改编策略 → 剧本) with per-stage supervision gating. Full methodology content is catalogued in `W9C-PRODSKILL-CORE-001` / `W9C-SCRIPTSKILL-CORE-001` / `W9C-PRODSKILL-PIPELINE-001` (13 sub-agent skill files) and `W9C-PRODSKILL-TECHNIQUE-001` (2 second-tier technique files).

### 1.3 Workspace / canvas tools (`useTools`)

Distinct per family, `tools.ts`:

- **productionAgent** (`tools.ts:88-296`): `get_flowData` reads the **currently-open canvas** live via `socket.emit("getFlowData")`; `add_deriveAsset` / `del_deriveAsset` write DB then push a canvas update; `generate_deriveAsset` / `generate_storyboard` trigger async generation; `add_flowData_storyboard` serially inserts new storyboard panels onto the open canvas via `socketQueue`. Net user-observable effect: the Agent mutates the canvas the user is looking at, no manual refresh (`W8-AGENTTOOL-PRODUCTION-001`).
- **scriptAgent** (`tools.ts:34-117`): read-only context — `get_novel_events` (event summary by chapter), `get_planData` (live workspace skeleton/strategy/draft), `get_novel_text` (chapter source), `get_script_content` (stored script by id). Lets the Agent self-fetch context without the user pasting source (`W8-AGENTTOOL-SCRIPTAGENT-001`).

### 1.4 Three-tier memory subsystem (`utils/agent/memory.ts` + `embedding.ts`)

Row `W8-AGENTUTIL-MEMORY-001` and `W9A-DBTABLE-AGENTCORE-001` (`memories` table). Verified mechanics:

- **Local ONNX embedding, no network** (`embedding.ts:13-35`): loads `onnxruntime-web` + `@huggingface/transformers` pipeline, default `all-MiniLM-L6-v2` fp16 ONNX (model file / dtype overridable via `o_setting.modelOnnxFile`/`modelDtype`), with `transformersEnv.allowRemoteModels = false`. `getEmbedding` mean-pools + normalizes (:37-41); `cosineSimilarity` is a plain dot product since vectors are pre-normalized (:43-45).
- **Config defaults** (`memory.ts:8-23`): `messagesPerSummary=3`, `summaryMaxLength=500`, `shortTermLimit=5`, `summaryLimit=10`, `ragLimit=3`, `deepRetrieveSummaryLimit=5`, all `o_setting`-overridable (row `W7A-MEMORY-PARAMS-001` = the 8-key config panel).
- **`add`** (`memory.ts:86-131`): every message is embedded and inserted into `memories` immediately; once ≥ `messagesPerSummary` unsummarized messages accumulate, it **auto-triggers** an LLM summary (`generateSummary`, :45-52), embeds the summary, inserts it as `type='summary'` with `relatedMessageIds`, and marks the batch `summarized=1`.
- **`get`** (`memory.ts:133-168`): assembles all three tiers per turn — shortTerm (recent unsummarized messages) + summaries (recent) + **rag** (vector similarity over all messages) — injected into the system prompt's Memory section.
- **`deepRetrieve`** (`memory.ts:170-198): vector-recall candidate summaries → LLM relevance judge (`judgeSummaryRelevance`, :54-66) → expand back to the original full-text messages. Exposed as an Agent-callable tool via `getTools()` (:200-218).

### 1.5 On-demand Markdown skill loading (`utils/agent/skillsTools.ts`)

Row `W8-AGENTUTIL-SKILLS-001`. Two tools created by `createSkillTools` (:180-273):

- **`activate_skill`** (:186-226): the Agent loads a named skill's full body into context on demand; an `activated` Set dedupes so a skill loads at most once per conversation; the return includes a `<skill_resources>` file listing.
- **`read_skill_file`** (:227-271): reads a resource file under an activated skill dir, with `isPathInside` path-traversal guard that returns `{ error }` (never throws, never breaks the conversation) on out-of-bounds access.
- Skill inventory is built by scanning frontmatter (`parseFrontmatter`, :44-119) into a "name + description" list (not full text) handed to the sub-agent alongside `activate_skill`, so the model pulls full instructions only when a task matches (`buildSkillPrompt`, :166-178). `productionSkills`/`artSkills` are mounted **only to specific sub-agents** (e.g. `production_skills` only to `storyboard_panel` and `storyboard_table`, `productionAgent/index.ts:320,345,466-490`).

---

## 2. DramaFlow's current state (the "v0.4 assistant")

DramaFlow replaced the whole system with a **single flat tool-calling loop shared by both families** — no sub-agents, no vector memory, no live canvas and no streaming. It now has the on-demand Markdown protocol above, but not ToonFlow's stage-specific skill selection. There is no WebSocket/backend; socket semantics are approximated by in-process direct calls + the task-queue event bus (`queue.dart:87-114`; `W7F-SOCKET-AGENT-001`).

### 2.1 The one loop

`assistant_chat.dart`: `_maxAutoTurns=5` (:20); `_driveAssistantLoop` (:186-264) runs manual = 1 turn / auto = up to 5, each turn at most one tool call or one plain-text reply, whole-turn request→wait→render (no per-token streaming). `_nextAssistantTurn` (:266-289) calls `gateway.generateAgentTurn(...)`. **Family only routes the model binding stage and the storage key** (`_assistantStage`, :393-395); `_assistantToolDefs` (:374-388) hands both families the **same** tool set — no per-family differentiation. System prompt (`_assistantSystemPrompt`, :360-372) is 4 generic sentences + blanket-injected skills.

### 2.2 The 13 flat actions and what actually works

`assistant_actions.dart:39-142` defines exactly 13 actions; `runAssistantAction` (:213-334) dispatches each to an existing engine method (one-shot enqueue / direct execute), returning a Chinese summary:

- **Real generation triggers, ported and tested** (map to genuine pipeline enqueues): `generate_events`, `generate_scripts`, `extract_assets`, `generate_storyboards`, `generate_shot_images`, `generate_videos`, `bind_audio`, `compose_episode`, `write_script` (`assistant_actions.dart:222-310`). Test evidence: `app/test/engine/assistant_chat_test.dart:74-250`, `assistant_actions_test.dart:136-176`, `canvas_chat_panel_test.dart:86-182`.
- **Read-only / notes**: `get_status` (:220), `note_save`/`note_search`/`note_delete` (:311-330).
- **Working infra**: money/destructive **confirm gate** via `pipeline_policy.checkAction` (`assistant_chat.dart:227-252`, `confirmPendingAssistantAction:118-162`), tested; message persistence + family isolation in `o_agentWorkData[key=assistantChat:family]` single JSON blob (`assistantMessages:74-93`; row `W7F-AGENT-MEM-READ-001` = **已验证等价**); clear-all chat (`clearAssistantChat:164-170`, = `type=all`, tested).
- **Skill parsing and managed-file infra**: `assistant_skill_library.dart` now owns
  folded/literal frontmatter parsing, application-owned file copying and a
  canonical-path workspace; `assistant_skills.dart:126-140` keeps the guarded
  resource reader. Focused engine and desktop/390dp widget tests cover import,
  source deletion, resource copying, scan reconciliation and path escape
  rejection. This is stronger file management, not Agent activation parity.

### 2.3 What is NOT there at all

- **Sub-agent delegation architecture** — no concept of nested agent invocation; the loop has one flat registry (`W8-AGENTTOOL-PRODUCTION-001`, `W8-AGENTTOOL-SCRIPTAGENT-001`). `assistant_stage_registry.dart:1-3` notes the old 15 multi-layer sub-agent stages were cut per spec §2.
- **Live canvas read/write tools** — no `get_flowData`/`add_deriveAsset`/`add_flowData_storyboard` equivalents; no in-dialogue derive-asset CRUD or storyboard-panel insertion (`W8-AGENTTOOL-PRODUCTION-001`).
- **Vector / 3-tier memory** — **缺失** (`W8-AGENTUTIL-MEMORY-001`). `_assistantHistory` (`assistant_chat.dart:404-417`) linearly replays the entire message list every turn (no summary, no window, no retrieval). `project_notes.dart:1-108` is an explicit **downgrade rename** of "长期记忆": it reuses the `memories` table with `type='note'`, **abandons the embedding column**, and its `searchProjectNotes` (:68-91) is **lexical** (char bi-gram×2 + substring×3 + token×1), not semantic. The file header (`:4`) forbids re-attaching the old vector module. No ONNX/transformers/cosine/deepRetrieve code exists in `app/lib` (only dead l10n strings remain).
- **On-demand skill activation** — skills are **blanket-injected**. `assistantSkillContexts`
  (`assistant_skills.dart:142-159`) concatenates **all** enabled managed Markdown
  bodies into every system prompt (`assistant_chat.dart:369`).
  `readAssistantSkillFile` exists but is **unreachable** — it is not in
  `_assistantToolDefs`; only engine tests call it (`W8-AGENTUTIL-SKILLS-001`).
- **The 13 sub-agent skill files' methodology content** — the decision/supervision/execution skill bodies (6-stage pipeline constants, R1–R4 red-lines, 大三角/矛盾四级阶梯, 付费点比例, etc.) are entirely absent; where DramaFlow keeps same-named workspace slots (`director_plan`/`storyboard_table`/`storyboard_gen` in `script_plan.dart`/`storyboard_table.dart`/`storyboard.dart`), the default seed prompts are single-paragraph generic instructions (`engine.dart:592-614`), not the methodology (`W9C-PRODSKILL-CORE-001`, `-PIPELINE-001`, `-SCRIPTSKILL-CORE-001`, `-TECHNIQUE-001`, all **缺失**).
- **Per-token streaming, `stop`/abort, think-level (0–3)** — none (`W7F-SOCKET-AGENT-001`). Chat is request→wait→whole render.
- **Typed rich message segments** — none. ToonFlow `useChat.ts` accepts `text` and `markdown` content blocks, keeps `thinking` blocks before normal content and collapses them by default; the two Agent runners publish reasoning start/delta/end into those blocks. DramaFlow persists one `String` per message and `_AssistantMessageBubble` renders it with plain `Text`; Markdown lists/code/links are not rendered, and an Agent reply URL cannot open in the system browser. This is distinct from merely adding a stream transport: W2 must retain segment type, streaming/complete state and safe external-link handling across desktop and mobile.
- **Per-Agent temperature / maxOutputTokens / batch deploy / normal-vs-advanced mode** — `W7A-AGENT-DEPLOY-001` (部分), `W7A-AGENT-USEMODE-001` (**缺失**, `agentUseMode` grep 0 hits), `W7A-MEMORY-PARAMS-001` (**缺失**).
- **`agentSetKey` one-click** — DramaFlow doesn't bundle ToonFlow's hosted `toonflow` Claude proxy; **缺失** (`W7A-AGENT-SETKEY-001`).
- **Memory-clear granularity** — only clear-all; `type=message`/`type=summary` and the `summarized→shortTerm` reflow have no equivalent (needs a `memories`-with-summary layer) (`W7F-AGENT-MEM-CLEAR-001` 部分, `W7A-MEMORY-CLEAR-001` 部分).

### 2.4 DB substrate already present

`W9A-DBTABLE-AGENTCORE-001`: `db.dart:107-140` already declares `memories` (with `embedding`, `relatedMessageIds`, `summarized`, `type` columns, column-for-column matching ToonFlow), `o_agentDeploy`, and `o_agentWorkData`; plus a DramaFlow-side `o_memoryVector` table (`db.dart:208-218`) for vector-search splitting. So the schema for the memory subsystem largely exists — it is the read/write/embed code paths that are gone.

---

## 3. Scoped gap list (discrete implementable chunks)

Each chunk: what it is · why it matters (user-observable) · size · natural starting file(s) · source rows. Dependencies noted.

### Chunk A — Sub-agent delegation backbone  ·  **LARGE**
- **What**: introduce nested-agent invocation into the tool-calling loop — a sub-agent is a tool the decision turn can call, running its own system prompt, streaming into its own named bubble, writing its product back to memory/workspace. Then wire the 7 production + 4 script sub-agents.
- **Why**: this is the core "decision/execution/supervision multi-agent orchestration" of spec §8; without it there is no supervision report, no named "执行导演/监制/编剧/编辑" bubbles, no staged pipeline.
- **Size**: LARGE — DramaFlow's flat loop (`_driveAssistantLoop`) has no concept of nested agent invocation at all; this is a structural change to the loop plus per-family tool bags. This is the backbone D, E, and the methodology content (I) build on.
- **Start**: `assistant_chat.dart:186-264` (loop) + `assistant_actions.dart` (new sub-agent tool defs). Model of the target: `productionAgent/index.ts:97-375`, `scriptAgent/index.ts:91-234`.
- **Rows**: `W8-AGENTTOOL-PRODUCTION-001`, `W8-AGENTTOOL-SCRIPTAGENT-001`, `W6-SCRIPTAGENT-001`, `W7F-SOCKET-AGENT-001`.

### Chunk B — Three-tier vector memory subsystem  ·  **LARGE**
- **What**: restore auto-embedding of each message, auto-summary at `messagesPerSummary`, the 3-way `get` (shortTerm + summaries + RAG) injected per turn, and `deepRetrieve` as an Agent tool. Requires a local embedding path (ONNX all-MiniLM-L6-v2 or a Dart-compatible equivalent).
- **Why**: every utterance is remembered semantically without user action; long conversations auto-compress; the Agent "recalls" relevant history by meaning not exact match. Today this is entirely gone (lexical notes only).
- **Size**: LARGE — no embedding/vector/summary code exists in `app/lib`; the biggest open question is how to run a local embedding model from Dart/Flutter (ToonFlow uses `onnxruntime-web` + HF transformers). Schema is mostly present (`memories`, `o_memoryVector` in `db.dart`), which reduces DB work.
- **Start**: new engine file paralleling `project_notes.dart`; `db.dart:107-118,208-218` (tables); replace the linear replay in `assistant_chat.dart:404-417`.
- **Rows**: `W8-AGENTUTIL-MEMORY-001` (缺失), `W7A-MEMORY-PARAMS-001`, `W9A-DBTABLE-AGENTCORE-001`.

### Chunk C — On-demand skill activation (activate_skill / read_skill_file)  ·  **MEDIUM**
- **What**: change skill delivery from blanket-inject to tool-call-gated. Expose the already-ported `readAssistantSkillFile` and a new `activate_skill` in `_assistantToolDefs`, give the system prompt a name+description skill catalogue, dedupe per conversation.
- **Why**: avoids system-prompt bloat / token waste; lets specialized (art/director) skills load only when a task matches, so sub-agent output professionalizes on demand; illegal-path reads are rejected without breaking the dialogue.
- **Size**: MEDIUM — the hard file-boundary pieces (frontmatter parsing, canonical
  workspace, package-resource copying and path-traversal guard) are now ported
  and tested in `assistant_skill_library.dart` plus `assistant_skills.dart:126-159`.
  The remaining change is the **injection mechanism** (blanket → tool-gated),
  catalogue prompt and per-conversation dedupe set. Naturally couples with A
  when skills mount per sub-agent.
- **Start**: `assistant_skills.dart:142-159` (replace `assistantSkillContexts`
  injection) + `assistant_chat.dart:360-388` (system prompt and tool defs).
- **Rows**: `W8-AGENTUTIL-SKILLS-001` (部分).

### Chunk D — Live canvas read/write tools  ·  **MEDIUM–LARGE**
- **What**: in-dialogue tools that read the currently-open production canvas and mutate it (add/del derive-asset, insert storyboard panel), reflected live without manual refresh — plus the read-only script-context tools (`get_novel_text`/`get_novel_events`/`get_script_content`/`get_planData`).
- **Why**: today the Agent can only one-shot-enqueue jobs; ToonFlow's Agent directly manipulates the canvas the user is viewing and self-fetches context. Read-only script tools are the cheaper half.
- **Size**: read-only script-context tools = MEDIUM (straight engine reads). Live canvas write-back = LARGE and needs an architecture decision: DramaFlow has no socket; the "reflect to open canvas live" behavior must be re-expressed over the in-process engine + Riverpod/task-event bus (see Open Question Q3).
- **Start**: `assistant_actions.dart` (new tools) + `screens/production/production_screen.dart` / `canvas_chat_panel.dart` (canvas state) + `queue.dart:87-114` (event bus). Target: `productionAgent/tools.ts:88-296`, `scriptAgent/tools.ts:34-117`.
- **Rows**: `W8-AGENTTOOL-PRODUCTION-001`, `W8-AGENTTOOL-SCRIPTAGENT-001`.

### Chunk E — Family-differentiated tool sets + decision/supervision skill prompts  ·  **MEDIUM** (depends on A)
- **What**: split the shared 13-action registry so each family exposes its own tool set + decision/supervision system prompts, instead of one flat set for both.
- **Why**: the two families serve different professional scenarios; ToonFlow's tool faces are completely disjoint. Today `_assistantToolDefs` ignores family.
- **Size**: MEDIUM once A exists (the differentiation lives in per-family tool bags + which decision skill loads).
- **Start**: `assistant_chat.dart:374-388,360-372`.
- **Rows**: `W8-AGENTTOOL-SCRIPTAGENT-001`, `W8-AGENTTOOL-PRODUCTION-001`.

### Chunk F — 流式、富内容段、停止/中止、思考等级  ·  **MEDIUM** (gateway-dependent)
- **What**: per-token streaming into typed bubbles (including collapsed reasoning segments with elapsed timer and Markdown rendering), a `stop` control, a 0–3 think-level toggle, and safe external-link opening from Agent Markdown.
- **Why**: user-observable "看到流式回复、可中止、调思考档，并能阅读 Markdown/点击链接" — these are separate behaviors currently absent because the Flutter chat persists and renders whole plain strings.
- **Size**: MEDIUM but bounded by whether `gateway.generateAgentTurn` / the provider layer can stream (today it returns a whole turn). May be spec-deferrable independent of orchestration.
- **Start**: `assistant_chat.dart:266-289` + `providers/gateway.dart` + `canvas_chat_panel.dart`/`agent_chat_screen.dart`. Target: `consumeFullStream` (`productionAgent/index.ts:397-448`).
- **Rows**: `W7F-SOCKET-AGENT-001`.

### Chunk G — Memory-clear granularity + memory config panel  ·  **SMALL–MEDIUM** (depends on B)
- **What**: `type=message` / `type=summary` clear granularity with `summarized→shortTerm` reflow, and the settings memory panel (8 keys: `messagesPerSummary`/`shortTermLimit`/`summaryMaxLength`/`summaryLimit`/`ragLimit`/`deepRetrieveSummaryLimit`/`modelOnnxFile`/`modelDtype`).
- **Why**: the memory-management panel and per-granularity clearing; only clear-all exists today.
- **Size**: SMALL–MEDIUM, but strictly **downstream of B** (needs the summary layer to exist).
- **Start**: `assistant_chat.dart:164-170` (clear) + `settings_screen.dart`. Rows: `W7F-AGENT-MEM-CLEAR-001`, `W7A-MEMORY-CLEAR-001`, `W7A-MEMORY-PARAMS-001`.

### Chunk H — Agent deploy params: temperature / maxOutputTokens / batch / normal-advanced mode  ·  **SMALL–MEDIUM**
- **What**: per-Agent temperature + max-output-tokens, batch deploy, and the normal/advanced mode switch (`o_setting.agentUseMode`) that toggles between 3 top-level assignments and per-decision/supervision/sub-task fine-grained assignment.
- **Why**: users assign models + tuning per Agent; advanced mode only makes sense once the multi-layer agents (A) exist.
- **Size**: SMALL–MEDIUM; advanced mode naturally arrives with A. `o_agentDeploy` columns already present (`db.dart:119-131`).
- **Start**: `settings_screen.dart:661-706` (`_bindingsPanel`). Rows: `W7A-AGENT-DEPLOY-001` (部分), `W7A-AGENT-USEMODE-001` (缺失).

### Chunk I — Skill methodology content porting (13 + 2 md files)  ·  **MEDIUM** (depends on C)
- **What**: port the actual methodology bodies of the 13 sub-agent skill files and 2 second-tier technique files (decision pipelines, supervision red-lines/rubrics, skeleton/adaptation/script methodology, storyboard technique library).
- **Why**: without this, even with orchestration wired, sub-agents have no professional rules to follow — the difference between a same-named empty slot and the actual ToonFlow behavior.
- **Size**: MEDIUM (content transcription + a licensing check — these are ToonFlow-authored asset files). Only meaningful once C (skill activation) and A (sub-agents) exist.
- **Start**: skill asset bundle (currently `app/assets/default_skills/toonflow_default_skills.zip` contains only `art_skills`/`story_skills`, not these files). Rows: `W9C-PRODSKILL-CORE-001`, `W9C-PRODSKILL-PIPELINE-001`, `W9C-SCRIPTSKILL-CORE-001`, `W9C-PRODSKILL-TECHNIQUE-001`.

**Suggested dependency order**: A (backbone) → {B, C} in parallel → {D, E, I} → {F, G, H} as finishing/independent work.

---

## 4. Explicit prohibition (restated, with the scope boundary made unambiguous)

Spec §8 forbids, for W2: **restoring a custom JS interpreter, ES-DSL queries, or wholesale-reverting to the pre-v0.4 old implementation.** The port must be onto the existing Dart assistant architecture, based on ToonFlow's user-observable behavior only.

Row `W2-EVIDENCE-AGENT-JSDSL-001` establishes the precise, non-obvious scope of this prohibition — **do not read it as "ToonFlow has no JS interpreter":**

1. The brief-specified pattern set (`custom-js` / `new Function` / `queryPlan`) returns **0 hits** across all of `Toonflow-app/src` (211 files) and `Toonflow-web/src` (435 files) — formally confirming §8's phrasing under that literal pattern set. The traversal was validated against known strings (`socket.io` → 8 files, `<script`/`defineComponent` → 86 files) to rule out false negatives.
2. All **7 audited Agent-surface files** (`productionAgent/index.ts`, `productionAgent/tools.ts`, `scriptAgent/index.ts`, `scriptAgent/tools.ts`, `embedding.ts`, `memory.ts`, `skillsTools.ts`) reference **no** `vm`/`vm2`/`eval`/`new Function`/`runCode`. The Agent tool-calling surface is clean.
3. **However — a real vm2-based interpreter DOES exist**, verified this pass: `Toonflow-app/src/utils/vm.ts:1` (`import { VM } from "vm2"`) and `:47-55` (`new VM({ compiler: "javascript", eval: false, wasm: false })` running arbitrary compiled TS with injected `createOpenAI`/`createAnthropic`/… factories, axios, crypto). It is the **native core of ToonFlow's vendor/model-adapter subsystem** — a model-dispatch hot path (`ai.ts:127`, plus 5 more call sites in `vendor.ts`, `fixDB.ts`, and two `vendorConfig` HTTP routes). It does not match the three literal patterns, so the brief's grep legitimately misses it — it is a genuinely-present interpreter under different naming.
4. This vm2 subsystem is **out of W2 scope** and separate from the Agent surface. Its DramaFlow status is already settled independently as "缺失, consistent with W2's ban on reintroducing a JS runtime" by rows `W7A-VENDOR-CODE-001` and `W6E-LIB-VENDORTPL-001`.

**Scope boundary for the W2 spec**: the "no JS interpreter / no ES-DSL" prohibition applies to the **Agent tool-calling surface** (the 7 files above), where it is formally confirmed. It must not be worded as an unqualified statement about ToonFlow overall, which would contradict the vendor-adapter vm2 reality (that subsystem is out of W2 scope and governed by `W7A-VENDOR-CODE-001`). Toonflow-web (browser frontend) contains no interpreter trace at all; vm2 appears only in the Toonflow-app backend.

---

## 5. Open questions for the user (flagged by the source rows as needing judgment before W2 starts)

1. **Commercial hosted-Claude proxy in scope?** (`W7A-AGENT-SETKEY-001`) ToonFlow's `agentSetKey` one-click flow validates a **ToonFlow-hosted (HBAI commercial) Claude proxy** subscription key and auto-binds three core Agents to default Claude models. DramaFlow uses azt (Codex OAuth) + volcengine and bundles no such hosted vendor. The row explicitly defers this: *"是否纳入复刻范围建议 W0 范围确认时由用户裁定"* — decide whether replicating this commercial-service integration is in W2 scope at all.

2. **How to realize "live canvas manipulation" without a socket?** (`W8-AGENTTOOL-PRODUCTION-001`, Chunk D) ToonFlow's `get_flowData`/`add_flowData_storyboard` real-time two-way canvas sync is a browser-SPA↔backend socket product. DramaFlow has no WebSocket/backend. A design decision is needed on how the Agent's in-dialogue canvas reads/writes reflect live onto the open production canvas via the in-process engine + task-event bus.

3. **JS-interpreter prohibition wording** (§4 above / `W2-EVIDENCE-AGENT-JSDSL-001`): confirm the W2 spec will scope the ban to the "Agent tool-calling surface" rather than stating it unqualified, to avoid a documented conflict with the out-of-scope vendor-adapter vm2 subsystem.

4. **Streaming / stop / think-level: W2 or deferred?** (Chunk F, `W7F-SOCKET-AGENT-001`) Per-token streaming, abort, and the 0–3 think-level are gated by whether the gateway/provider layer will support streaming. Confirm whether these are in W2 or split out, since they are largely independent of the orchestration backbone.

5. **Local embedding model runtime** (Chunk B, `W8-AGENTUTIL-MEMORY-001`): ToonFlow runs `all-MiniLM-L6-v2` fp16 ONNX via `onnxruntime-web`/HF transformers with `allowRemoteModels=false`. A decision is needed on the Dart/Flutter-side local-inference path (bundled ONNX runtime vs. alternative), since this is the largest technical unknown in the memory port and affects app packaging/size.
