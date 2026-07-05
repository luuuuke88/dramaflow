# Agent/RAG Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first ToonFlow-grade Agent/RAG parity layer for DramaFlow: full script/production Agent deployment registry, message/summary/note memory, deep retrieval, skill activation, and staged orchestrators that write through the existing engine.

**Architecture:** Keep the Flutter/Dart single-app engine. Split the current slim `agent.dart` responsibilities into focused pure-Dart engine files, while preserving existing public extension methods so UI and old tests keep working. All media-producing actions continue through current engine APIs and `o_tasks`; Agent code orchestrates but does not bypass the queue.

**Tech Stack:** Dart, Flutter test, sqlite3, existing `ProviderGateway`, existing `o_agentDeploy`, `o_agentWorkData`, `o_skillList`, `o_skillAttribution`, `memories`, and `o_setting` tables.

---

## File Structure

- Create `app/lib/src/engine/agent_stage_registry.dart`
  - Defines ToonFlow-compatible stage metadata, old pipeline compatibility keys, family/role grouping, fallback stage, display name, default limits, and sort order.
- Create `app/lib/src/engine/agent_memory.dart`
  - Implements message/summary/note memory operations against `memories`, including local token embedding, RAG ranking, deep retrieval, scoped clearing, and settings.
- Create `app/lib/src/engine/agent_skills.dart`
  - Implements Markdown skill frontmatter parsing, seeded skill metadata, attribution, `activate_skill`, and safe `read_skill_file`.
- Create `app/lib/src/engine/agent_orchestrator.dart`
  - Implements `ScriptAgentOrchestrator`, `ProductionAgentOrchestrator`, workspace tools, turn limits, duplicate-call protection, and XML parsing hooks.
- Modify `app/lib/src/engine/agent.dart`
  - Remove the old "slim Agent" assumptions, delegate deployment/memory/skill/orchestration work to the new files, and preserve existing extension APIs.
- Modify `app/lib/src/engine/providers/resolve.dart`
  - Let ToonFlow Agent stage keys resolve through `o_agentDeploy`, then fallback to their registry `fallbackStage` such as `script_gen`.
- Modify `app/lib/src/screens/agent/agent_chat_screen.dart`
  - Display stage groups by Agent family and role; add memory settings and skill attribution UI in later tasks.
- Modify `app/test/engine/agent_test.dart`
  - Extend engine tests for registry, memory summary/deepRetrieve, skill activation, and staged orchestrator behavior.
- Modify `app/test/widgets/agent_chat_screen_test.dart`
  - Extend widget tests for grouped deployment rows and memory/skill controls.

## Task 1: Agent Stage Registry And Deployment Seed

**Files:**
- Create: `app/lib/src/engine/agent_stage_registry.dart`
- Modify: `app/lib/src/engine/agent.dart`
- Modify: `app/lib/src/engine/providers/resolve.dart`
- Test: `app/test/engine/agent_test.dart`

- [x] **Step 1: Write failing registry test**

Add a test asserting `agentDeployments()` includes all ToonFlow script/production keys plus old pipeline keys, in registry order:

```dart
test('Agent stage registry seeds ToonFlow script/production families without dropping pipeline keys', () {
  final keys = engine.agentDeployments().map((item) => item.key).toList();
  expect(keys, containsAllInOrder([
    'scriptAgent',
    'scriptAgent:decisionAgent',
    'scriptAgent:storySkeletonAgent',
    'scriptAgent:adaptationStrategyAgent',
    'scriptAgent:scriptAgent',
    'scriptAgent:supervisionAgent',
    'productionAgent',
    'productionAgent:decisionAgent',
    'productionAgent:deriveAssetsAgent',
    'productionAgent:generateAssetsAgent',
    'productionAgent:directorPlanAgent',
    'productionAgent:storyboardGenAgent',
    'productionAgent:storyboardPanelAgent',
    'productionAgent:storyboardTableAgent',
    'productionAgent:supervisionAgent',
  ]));
  expect(keys, containsAll([
    'script_gen',
    'event_extract',
    'asset_extract',
    'storyboard_gen',
    'video_prompt_gen',
  ]));
});
```

- [x] **Step 2: Run the focused test to verify RED**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "Agent stage registry seeds ToonFlow script/production families without dropping pipeline keys"
```

Expected: FAIL because the current hard-coded `_agentDeploymentKeys` only contains the five old pipeline keys.

- [x] **Step 3: Implement `agent_stage_registry.dart`**

Define immutable `AgentStageDefinition` records and export:

```dart
const agentStageDefinitions = <AgentStageDefinition>[
  AgentStageDefinition(key: 'scriptAgent', name: '剧本 Agent', family: 'scriptAgent', role: 'decision', fallbackStage: 'script_gen', sortOrder: 0),
  AgentStageDefinition(key: 'scriptAgent:decisionAgent', name: '剧本决策 Agent', family: 'scriptAgent', role: 'decision', fallbackStage: 'script_gen', sortOrder: 1),
  AgentStageDefinition(key: 'scriptAgent:storySkeletonAgent', name: '故事骨架 Agent', family: 'scriptAgent', role: 'execution', fallbackStage: 'script_gen', sortOrder: 2),
  AgentStageDefinition(key: 'scriptAgent:adaptationStrategyAgent', name: '改编策略 Agent', family: 'scriptAgent', role: 'execution', fallbackStage: 'script_gen', sortOrder: 3),
  AgentStageDefinition(key: 'scriptAgent:scriptAgent', name: '剧本执行 Agent', family: 'scriptAgent', role: 'execution', fallbackStage: 'script_gen', sortOrder: 4),
  AgentStageDefinition(key: 'scriptAgent:supervisionAgent', name: '剧本监督 Agent', family: 'scriptAgent', role: 'supervision', fallbackStage: 'script_gen', sortOrder: 5),
  AgentStageDefinition(key: 'productionAgent', name: '生产 Agent', family: 'productionAgent', role: 'decision', fallbackStage: 'storyboard_gen', sortOrder: 20),
  AgentStageDefinition(key: 'productionAgent:decisionAgent', name: '生产决策 Agent', family: 'productionAgent', role: 'decision', fallbackStage: 'storyboard_gen', sortOrder: 21),
  AgentStageDefinition(key: 'productionAgent:deriveAssetsAgent', name: '资产推导 Agent', family: 'productionAgent', role: 'execution', fallbackStage: 'asset_extract', sortOrder: 22),
  AgentStageDefinition(key: 'productionAgent:generateAssetsAgent', name: '资产生成 Agent', family: 'productionAgent', role: 'execution', fallbackStage: 'asset_extract', sortOrder: 23),
  AgentStageDefinition(key: 'productionAgent:directorPlanAgent', name: '导演规划 Agent', family: 'productionAgent', role: 'execution', fallbackStage: 'storyboard_gen', sortOrder: 24),
  AgentStageDefinition(key: 'productionAgent:storyboardGenAgent', name: '分镜生成 Agent', family: 'productionAgent', role: 'execution', fallbackStage: 'storyboard_gen', sortOrder: 25),
  AgentStageDefinition(key: 'productionAgent:storyboardPanelAgent', name: '分镜画面 Agent', family: 'productionAgent', role: 'execution', fallbackStage: 'storyboard_gen', sortOrder: 26),
  AgentStageDefinition(key: 'productionAgent:storyboardTableAgent', name: '分镜表 Agent', family: 'productionAgent', role: 'execution', fallbackStage: 'storyboard_gen', sortOrder: 27),
  AgentStageDefinition(key: 'productionAgent:supervisionAgent', name: '生产监督 Agent', family: 'productionAgent', role: 'supervision', fallbackStage: 'storyboard_gen', sortOrder: 28),
  AgentStageDefinition(key: 'script_gen', name: '剧本生成', family: 'pipeline', role: 'pipeline', fallbackStage: 'script_gen', sortOrder: 100),
  AgentStageDefinition(key: 'event_extract', name: '事件提取', family: 'pipeline', role: 'pipeline', fallbackStage: 'event_extract', sortOrder: 101),
  AgentStageDefinition(key: 'asset_extract', name: '资产提取', family: 'pipeline', role: 'pipeline', fallbackStage: 'asset_extract', sortOrder: 102),
  AgentStageDefinition(key: 'storyboard_gen', name: '分镜生成', family: 'pipeline', role: 'pipeline', fallbackStage: 'storyboard_gen', sortOrder: 103),
  AgentStageDefinition(key: 'video_prompt_gen', name: '视频提示词', family: 'pipeline', role: 'pipeline', fallbackStage: 'video_prompt_gen', sortOrder: 104),
];
```

- [x] **Step 4: Replace hard-coded deployment keys**

In `agent.dart`, use `agentStageDefinitions` for seed/query/update validation. Insert `name` from the registry and seed `vendorId/modelName` from `binding.<fallbackStage>` instead of only `binding.<key>`.

- [x] **Step 5: Add fallback resolution test**

Add a test:

```dart
test('ToonFlow Agent stage resolves through fallback text binding when deployment row is empty or disabled', () async {
  final provider = await engine.createProvider(
    name: 'azt',
    protocol: 'openai_compatible',
    baseUrl: 'http://127.0.0.1:8787/v1',
    apiKey: 'local',
  );
  await engine.saveProviderModels(provider.id, const [
    {'modelId': 'gpt-5.5', 'label': 'gpt-5.5', 'kind': 'text', 'enabled': true},
  ]);
  await engine.setBinding('script_gen', provider.id, 'gpt-5.5');

  final resolved = resolveAgentStage(db, 'scriptAgent:decisionAgent');
  expect(resolved.providerId, provider.id);
  expect(resolved.modelId, 'gpt-5.5');
});
```

- [x] **Step 6: Run focused tests to verify GREEN**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "Agent stage registry"
flutter test test/engine/agent_test.dart --plain-name "ToonFlow Agent stage resolves"
```

Expected: both focused tests pass.

- [x] **Step 7: Commit Task 1**

```bash
git add app/lib/src/engine/agent_stage_registry.dart app/lib/src/engine/agent.dart app/lib/src/engine/providers/resolve.dart app/test/engine/agent_test.dart docs/superpowers/plans/2026-07-05-agent-rag-parity.md
git commit -m "feat(agent): seed toonflow stage registry"
```

## Task 2: Agent Memory Service

**Files:**
- Create: `app/lib/src/engine/agent_memory.dart`
- Modify: `app/lib/src/engine/agent.dart`
- Test: `app/test/engine/agent_test.dart`

- [x] **Step 1: Write failing tests**

Add three concrete tests:

- `AgentMemoryService writes message records and generates a summary after threshold`: insert three user/assistant messages through the service, return `前三条对话摘要` from the fake gateway, then assert `memories` contains three `type='message'` rows, one `type='summary'` row, and the three message rows have `summarized=1`.
- `AgentMemoryService deepRetrieve expands matching summary related messages`: create a summary row whose `relatedMessageIds` points to two message rows about `寒山剑修`, call `deepRetrieve(keyword: '寒山')`, then assert both original message records are returned in create-time order.
- `Agent memory settings persist messagesPerSummary summaryLimit shortTermLimit ragLimit`: save values `4`, `8`, `6`, and `2`, read them back through the public settings API, and assert the values are clamped when saving `-1` and `999`.

Use fake gateway text responses for summaries so tests do not call network.

- [x] **Step 2: Verify RED**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "AgentMemoryService"
```

Expected: FAIL because `AgentMemoryService` does not exist and `memories(type='message'/'summary')` is not used.

- [x] **Step 3: Implement service**

Add pure-Dart service methods:

```dart
Future<String> add({required String isolationKey, required String role, required String content, String name = ''});
AgentMemoryContext get({required String isolationKey, required String query});
List<AgentMemoryRecord> deepRetrieve({required String isolationKey, required String keyword});
void clear({required String isolationKey, required AgentMemoryClearScope scope});
```

Generate local token embeddings, mark summarized messages, store `relatedMessageIds` JSON, and enforce configurable limits.

- [x] **Step 4: Verify GREEN**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "AgentMemoryService"
```

Expected: new memory tests pass and old long-term note tests still pass.

## Task 3: Skill Runtime V1

**Files:**
- Create: `app/lib/src/engine/agent_skills.dart`
- Modify: `app/lib/src/engine/agent.dart`
- Test: `app/test/engine/agent_test.dart`

- [x] **Step 1: Write failing tests**

Add tests for Markdown frontmatter parsing, `activate_skill`, `read_skill_file`, attribution filtering, and path traversal rejection.

- [x] **Step 2: Verify RED**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "SkillRuntime"
```

Expected: FAIL because runtime APIs do not exist.

- [x] **Step 3: Implement runtime**

Seed built-in skill metadata into `o_skillList`; store attribution rows in `o_skillAttribution`; read files only from the configured skill root; return readable Chinese errors for missing skill or unsafe path.

- [x] **Step 4: Verify GREEN**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "SkillRuntime"
```

Expected: all SkillRuntime tests pass.

## Task 4: Script Agent Orchestrator

**Files:**
- Create: `app/lib/src/engine/agent_orchestrator.dart`
- Modify: `app/lib/src/engine/agent.dart`
- Test: `app/test/engine/agent_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests for `scriptAgent:decisionAgent` calling `run_sub_agent_storySkeleton`, `run_sub_agent_adaptationStrategy`, `run_sub_agent_script`, and `run_supervision_agent`, with XML output writing to `o_agentWorkData` and `o_script`.

- [ ] **Step 2: Verify RED**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "ScriptAgentOrchestrator"
```

Expected: FAIL because all turns currently use `stage: script_gen` and no subagent dispatcher exists.

- [ ] **Step 3: Implement orchestrator**

Route `sendAgentMessage` through `ScriptAgentOrchestrator` for script family; call `gateway.generateAgentTurn` with the exact ToonFlow stage key; parse XML elements into existing engine APIs.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "ScriptAgentOrchestrator"
```

Expected: Script Agent tests pass and existing manual/auto tests still pass.

## Task 5: Production Agent Orchestrator

**Files:**
- Modify: `app/lib/src/engine/agent_orchestrator.dart`
- Modify: `app/lib/src/engine/agent.dart`
- Test: `app/test/engine/agent_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests for production decision tools: `run_sub_agent_derive_assets`, `run_sub_agent_generate_assets`, `run_sub_agent_director_plan`, `run_sub_agent_storyboard_gen`, `run_sub_agent_storyboard_panel`, `run_sub_agent_storyboard_table`, and `run_sub_agent_supervision`.

- [ ] **Step 2: Verify RED**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "ProductionAgentOrchestrator"
```

Expected: FAIL because production family dispatcher does not exist.

- [ ] **Step 3: Implement production tools**

Map production subagent outputs through existing asset/storyboard/image-flow/video-track APIs; submit long-running generation to `o_tasks`.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
cd app
flutter test test/engine/agent_test.dart --plain-name "ProductionAgentOrchestrator"
```

Expected: production orchestration tests pass.

## Task 6: Agent UI Grouping And Controls

**Files:**
- Modify: `app/lib/src/screens/agent/agent_chat_screen.dart`
- Test: `app/test/widgets/agent_chat_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Assert the deployment pane groups rows under Script Agent, Production Agent, and Pipeline; assert memory settings fields save; assert skills can be filtered by attribution.

- [ ] **Step 2: Verify RED**

Run:

```bash
cd app
flutter test test/widgets/agent_chat_screen_test.dart --plain-name "Agent 体系页"
```

Expected: FAIL for the new grouped UI expectations.

- [ ] **Step 3: Implement UI**

Use `AgentDeployment.family` and `AgentDeployment.role` metadata from the registry. Keep compact mobile layout and existing save buttons.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
cd app
flutter test test/widgets/agent_chat_screen_test.dart --plain-name "Agent 体系页"
```

Expected: widget tests pass.

## Task 7: Full Verification

**Files:**
- All changed files

- [ ] **Step 1: Run static analysis**

```bash
cd app
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Run full test suite**

```bash
cd app
flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Commit verified implementation**

Commit remaining task changes with conventional commit messages. Do not commit build outputs.

## Self-Review

- Spec coverage: Tasks 1-6 map to the spec sections for stage registry, memory, skills, script orchestrator, production orchestrator, and UI. NLE/Web/H5/vision are outside this Agent/RAG plan and remain separate goal work.
- Placeholder scan: This plan contains no empty future-work markers or repeated-by-reference steps; every task has exact paths and commands.
- Type consistency: Stage keys use the exact ToonFlow-compatible names from the design spec; fallback stages use existing DramaFlow model binding keys.
