# Agent 按需技能运行时实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` task-by-task. Every code task starts with a failing test.

**Goal:** 将当前“所有启用 Markdown 技能正文注入每轮 system prompt”替换为 ToonFlow 可观察等价的技能目录、`activate_skill` 与受限 `read_skill_file` 工具闭环。

**Architecture:** 保持 `assistant_chat.dart` 的项目/家族会话、确认闸和现有供应商 `generateAgentTurn` 接口。`assistant_skills.dart` 负责目录与会话激活状态，`assistant_chat.dart` 只注册和分发两个零副作用上下文工具。激活状态存于独立的 `o_agentWorkData` 行，不能混进消息 JSON 或第二份业务真相。

**Tech Stack:** Dart、Flutter test、SQLite `o_agentWorkData`/`o_skillList`、现有 `ProviderGateway` fake。

## Global Constraints

- 不调用任何文字、图片、音频或视频供应商；测试使用 fake gateway。
- 不修改 `/Users/luke/Documents/aivideo/Toonflow-app` 或 `Toonflow-web`。
- 不恢复 JS 执行、ES-DSL、向量/RAG、子 Agent 编排或流式传输。
- 所有 Markdown 和资源只允许来自应用自有 `dataDir/skills/<id>/`；拒绝未激活、禁用、外部、`..` 与符号链接逃逸读取。
- `manual` 模式仍只允许一个业务动作；零副作用技能工具可在同一次模型循环内继续，最多 3 次，随后必须返回文本或结束。
- 清空某个 Agent 家族会话必须同步清空它的已激活技能集合；剧本和制作家族绝不共享集合。
- 保持 390dp 与桌面复用同一聊天入口，不新增仅桌面可用控制。
- 不暂存 `.superpowers/sdd/progress.md` 或 `docs/superpowers/acceptance/`。

---

### Task 1: 受限技能目录与会话激活状态

**Files:**
- Modify: `app/lib/src/engine/assistant_skills.dart`
- Modify: `app/lib/src/engine/assistant_skill_library.dart`
- Test: `app/test/engine/assistant_skills_deploy_test.dart`

**Produces:**

```dart
class AssistantSkillCatalogEntry {
  final String id;
  final String name;
  final String description;
}

List<AssistantSkillCatalogEntry> assistantSkillCatalog();
String activateAssistantSkill(int projectId, {required String family, required String skillName});
String readActivatedAssistantSkillFile(int projectId, {required String family, required String skillName, required String relativePath});
Set<String> activatedAssistantSkillIds(int projectId, {required String family});
void clearActivatedAssistantSkills(int projectId, {required String family});
```

- [ ] **Step 1: Write failing engine tests**

Add these tests under a new `on-demand skill runtime` group:

The test file must add a local fixture helper before the group (it writes only
under the existing temporary `dir`):

```dart
AssistantSkill importSkill(String name, String description, String body) {
  final file = File(p.join(dir.path, '$name.md'))
    ..writeAsStringSync('---\\nname: $name\\ndescription: $description\\n---\\n$body');
  return engine.saveMarkdownAssistantSkill(filePath: file.path);
}

AssistantSkill importSkillPackage(String name, {
  required String body,
  String? resource,
}) {
  final package = Directory(p.join(dir.path, '$name-package'))..createSync();
  final entry = File(p.join(package.path, 'SKILL.md'))
    ..writeAsStringSync('---\\nname: $name\\ndescription: 运镜规范\\n---\\n$body');
  if (resource != null) {
    File(p.join(package.path, resource)).writeAsStringSync('资源：$resource');
  }
  return engine.saveMarkdownAssistantSkill(filePath: entry.path);
}
```

```dart
test('目录仅暴露启用技能元数据，不包含正文', () {
  final skill = importSkill('camera_guide', '运镜规范', '绝密正文');
  expect(engine.assistantSkillCatalog(), [
    isA<AssistantSkillCatalogEntry>()
        .having((item) => item.id, 'id', skill.id)
        .having((item) => item.description, 'description', '运镜规范'),
  ]);
});

test('激活技能按项目和家族持久化，返回正文和资源清单', () {
  importSkillPackage('camera_guide', body: '镜头规则', resource: 'notes.md');
  final reply = engine.activateAssistantSkill(projectId,
      family: assistantFamilyScript, skillName: 'camera_guide');
  expect(reply, contains('镜头规则'));
  expect(reply, contains('notes.md'));
  expect(engine.activatedAssistantSkillIds(projectId,
      family: assistantFamilyScript), {'camera_guide'});
  expect(engine.activatedAssistantSkillIds(projectId,
      family: assistantFamilyProduction), isEmpty);
});

test('资源读取必须先激活，且符号链接不能逃逸技能包', () {
  importSkillPackage('camera_guide', body: '镜头规则', resource: 'notes.md');
  expect(
    () => engine.readActivatedAssistantSkillFile(projectId,
        family: assistantFamilyScript,
        skillName: 'camera_guide',
        relativePath: 'notes.md'),
    throwsA(isA<EngineException>()),
  );
  engine.activateAssistantSkill(projectId,
      family: assistantFamilyScript, skillName: 'camera_guide');
  final packageRoot = File(engine.managedAssistantSkillPath('camera_guide')).parent;
  final outside = File(p.join(dir.path, 'outside.md'))..writeAsStringSync('不可读取');
  Link(p.join(packageRoot.path, 'escape.md')).createSync(outside.path);
  expect(
    () => engine.readActivatedAssistantSkillFile(projectId,
        family: assistantFamilyScript,
        skillName: 'camera_guide',
        relativePath: 'escape.md'),
    throwsA(isA<EngineException>()),
  );
});
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd app
flutter test test/engine/assistant_skills_deploy_test.dart \
  --plain-name "on-demand skill runtime"
```

Expected: compilation failure because the catalog, activation and activated-resource APIs do not exist.

- [ ] **Step 3: Implement the catalog, persistence and safe resource list**

Use `o_agentWorkData` key `assistantSkillActivation:<family>` with `episodesId IS NULL`; JSON is a sorted list of stable skill IDs. Resolve `skillName` against enabled managed Markdown `id` or unique display `name`; disabled/unknown skills throw `EngineException(errLlmFormat, {'reason': 'skillMissing'})`.

`assistantSkillCatalog()` must return only `{id,name,description}` for enabled Markdown skills and never read a body. `activateAssistantSkill` parses the managed `SKILL.md`, records its ID idempotently, then returns a Chinese tool result containing the body and a recursively enumerated, relative resource list. `readActivatedAssistantSkillFile` first checks the family activation set and then reads only a regular, canonical file below that exact managed package root. Resolve the target with `resolveSymbolicLinksSync()` before `readAsStringSync()` so a user-created link inside the package cannot point outside it.

- [ ] **Step 4: Run GREEN**

Run the focused command from Step 2. Expected: all runtime tests pass, including disabled/unknown rejection, family isolation, repeat activation dedupe, clearing, `../` rejection and in-package symlink rejection.

- [ ] **Step 5: Commit Task 1**

```bash
git add app/lib/src/engine/assistant_skills.dart \
  app/lib/src/engine/assistant_skill_library.dart \
  app/test/engine/assistant_skills_deploy_test.dart
git commit -m "feat(agent): add scoped skill activation runtime"
```

### Task 2: Tool registration and safe continuation in the chat loop

**Files:**
- Modify: `app/lib/src/engine/assistant_chat.dart`
- Test: `app/test/engine/assistant_chat_test.dart`

**Consumes:** Task 1 catalog/activation APIs.

**Produces:** `activate_skill` and `read_skill_file` are registered `AgentToolDef`s and dispatched without `pipeline_policy`; a manual chat can use up to three context-tool hops before it renders a text reply, while one business action remains the existing manual limit.

- [ ] **Step 1: Write failing chat tests**

Add these fake-gateway assertions:

```dart
test('技能正文不进入初始 system prompt，目录和两个工具可见', () async {
  importSkill('camera_guide', '运镜规范', '不可预先泄露的正文');
  gateway.turns = const [AgentTurnResult.text('收到')];
  await engine.sendAssistantMessage(projectId, '帮我规划镜头',
      family: assistantFamilyScript, autoMode: false);
  expect(gateway.lastSystem, contains('camera_guide'));
  expect(gateway.lastSystem, isNot(contains('不可预先泄露的正文')));
  expect(gateway.lastTools.map((tool) => tool.name),
      containsAll(['activate_skill', 'read_skill_file']));
});

test('manual 会话在激活后自动继续一次并将正文作为工具结果回传', () async {
  importSkill('camera_guide', '运镜规范', '先建立空间关系');
  gateway.turns = const [
    AgentTurnResult.tool('activate_skill', {'skillName': 'camera_guide'}),
    AgentTurnResult.text('我会按空间关系设计镜头。'),
  ];
  await engine.sendAssistantMessage(projectId, '规划镜头',
      family: assistantFamilyScript, autoMode: false);
  expect(gateway.callCount, 2);
  expect(gateway.lastMessages.last['content'], contains('先建立空间关系'));
  expect(engine.assistantMessages(projectId,
      family: assistantFamilyScript).map((m) => m.role),
      ['user', 'tool', 'assistant']);
});

test('未激活资源读取以工具错误回传，不能绕过当前会话边界', () async {
  importSkillPackage('camera_guide', body: '规则', resource: 'notes.md');
  gateway.turns = const [
    AgentTurnResult.tool('read_skill_file', {
      'skillName': 'camera_guide', 'relativePath': 'notes.md',
    }),
    AgentTurnResult.text('请先激活技能。'),
  ];
  await engine.sendAssistantMessage(projectId, '读取资源',
      family: assistantFamilyProduction, autoMode: false);
  expect(gateway.callCount, 2);
  expect(gateway.lastMessages.last['content'], contains('skillMissing'));
});
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd app
flutter test test/engine/assistant_chat_test.dart \
  --plain-name "技能正文不进入初始 system prompt"
```

Expected: failure because initial system content still includes Markdown bodies and no skill tools are registered.

- [ ] **Step 3: Implement registration and context-tool loop**

Replace `assistantSkillContexts()` in `_assistantSystemPrompt` with an inventory block built from `assistantSkillCatalog()`:

```text
<available_skills>
- camera_guide: 运镜规范
</available_skills>
当任务匹配时，调用 activate_skill；只有已激活技能可以调用 read_skill_file。
```

Add two `AgentToolDef`s with required schemas:

```dart
AgentToolDef(
  name: 'activate_skill',
  description: '按名称加载已启用技能的完整说明和资源清单。',
  schema: {
    'type': 'object',
    'properties': {'skillName': {'type': 'string'}},
    'required': ['skillName'],
  },
)
```

`read_skill_file` has required `skillName` and `relativePath`. Dispatch these names before `_assistantActionByName`; catch `EngineException` and append the existing JSON error envelope as an `assistantRoleTool` message, so invalid model calls do not abort a chat. Refactor `_driveAssistantLoop` to count business-action turns separately from `contextToolHops`; context tools never enter the confirmation gate and may continue up to `3`, then append `errLlmFormat` reason `assistantSkillToolLimit`. Existing manual business actions still return after their first action, and auto mode keeps the five-action limit.

`clearAssistantChat` must also call `clearActivatedAssistantSkills` for the same project/family.

- [ ] **Step 4: Run GREEN and regression suite**

Run:

```bash
cd app
flutter test test/engine/assistant_chat_test.dart \
  test/engine/assistant_skills_deploy_test.dart \
  test/widgets/agent_chat_screen_test.dart --concurrency=1
flutter analyze
```

Expected: focused tests pass; existing confirmation, auto-turn and 390dp Agent-entry tests remain green.

- [ ] **Step 5: Commit Task 2**

```bash
git add app/lib/src/engine/assistant_chat.dart \
  app/test/engine/assistant_chat_test.dart
git commit -m "feat(agent): expose on-demand skill tools"
```

### Task 3: Parity record and full verification

**Files:**
- Modify: `docs/parity/skill-runtime-matrix.md`
- Modify: `docs/parity/w2-agent-reference.md`
- Modify: `docs/parity/feature-parity-execution-report.md`

- [ ] **Step 1: Record only the closed boundary**

Mark the skill runtime's metadata catalogue, activation, resource guard, family isolation and cross-platform Agent entry as verified evidence. Keep multi-layer sub-agent attribution, production/script-specific skills, streaming, RAG and decision/supervision orchestration explicitly missing. Do not change the overall W2 completion claim.

- [ ] **Step 2: Verify the complete project**

Run:

```bash
node tool/parity/check_no_orphans.js
cd app
flutter test --concurrency=1 --reporter compact
flutter analyze
flutter build macos --debug
cd ..
git diff --check
```

Expected: 538/538 inventory coverage, all Flutter tests and analyzer pass, macOS debug build succeeds, and no whitespace errors. No command may call a real video provider.

- [ ] **Step 3: Commit Task 3**

```bash
git add docs/parity/skill-runtime-matrix.md \
  docs/parity/w2-agent-reference.md \
  docs/parity/feature-parity-execution-report.md \
  docs/superpowers/plans/2026-07-21-on-demand-agent-skill-runtime.md
git commit -m "docs(parity): record on-demand skill runtime"
```
