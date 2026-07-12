# Assistant Primary UI Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make assistant chat the only primary assistant surface while retaining deployment, Markdown-skill, and project-note administration behind an explicit advanced panel.

**Architecture:** `AgentChatScreen` keeps the two existing conversation families, auto-mode switch, confirmation cards, and message persistence in its default body. A top-bar icon opens a dialog with the existing deployment, skills, and notes panes inside a local three-tab controller. No engine or database API changes are needed.

**Tech Stack:** Flutter, Riverpod, Material dialogs, `showDFAdaptiveDialog`, Flutter widget tests, generated ARB localizations.

## Global Constraints

- Implement the approved convergence-spec section 3.3 boundary: assistant administration is not a primary workflow surface.
- Preserve existing assistant deployments, Markdown skills, project notes, and their engine APIs.
- Do not introduce a provider call, paid workflow, schema migration, or model binding.
- UI-facing copy must use zh/en/ja localizations.

---

### Task 1: Move Assistant Administration Behind An Advanced Dialog

**Files:**
- Modify: `app/lib/src/screens/agent/agent_chat_screen.dart:120-296`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Regenerate: `app/lib/l10n/app_localizations.dart`
- Regenerate: `app/lib/l10n/app_localizations_zh.dart`
- Regenerate: `app/lib/l10n/app_localizations_en.dart`
- Regenerate: `app/lib/l10n/app_localizations_ja.dart`
- Modify: `app/test/widgets/agent_chat_screen_test.dart`

**Interfaces:**
- Consumes: `AgentChatScreen(projectId)`, `_AssistantDeployPane`, `_AssistantSkillsPane`, `_ProjectNotesPane`, and `showDFAdaptiveDialog`.
- Produces: a default assistant screen with no `TabBar`, plus `assistant-advanced-button` that opens all three retained administration panes.

- [x] **Step 1: Write the failing primary-surface widget test.**

Add a test that asserts the default page has no `TabBar` and no visible `部署`, `技能`, or `项目笔记` labels. It must tap `const ValueKey('assistant-advanced-button')` and then assert all three labels appear. Update the existing deployment, skills, and note tests to open that advanced panel before selecting their existing tabs.

- [x] **Step 2: Verify the test fails against the legacy tab layout.**

Run:

```bash
cd app
flutter test test/widgets/agent_chat_screen_test.dart --reporter expanded
```

Expected: failure because the default page owns a `TabBar` and has no `assistant-advanced-button`.

- [x] **Step 3: Add localizations and implement the minimal dialog boundary.**

Add `agentChatAdvanced` and `agentChatAdvancedTitle` to all ARB files and run `flutter gen-l10n`. Add `_openAdvanced()` to the state class, using `showDFAdaptiveDialog<void>` and `_AssistantAdvancedPanel(projectId: widget.projectId)`. Replace the four-tab root with the existing chat column. Add an `IconButton` keyed `assistant-advanced-button`, with `Icons.tune_rounded`, localized tooltip, and `_openAdvanced` callback. `_AssistantAdvancedPanel` has a three-tab controller and reuses the existing deploy, skills, and notes panes.

- [x] **Step 4: Verify focused behavior and static analysis.**

Run:

```bash
cd app
dart format lib/src/screens/agent/agent_chat_screen.dart test/widgets/agent_chat_screen_test.dart
flutter test test/widgets/agent_chat_screen_test.dart --reporter expanded
flutter analyze
```

Expected: default chat behavior and all retained advanced workflows pass; analysis reports no issues.

- [x] **Step 5: Run the full suite and commit.**

Run:

```bash
cd app
flutter test --reporter compact
```

Commit all files above plus this plan with:

```bash
git commit -m "refactor(assistant): move administration behind advanced panel"
```

## Plan Self-Review

**Spec coverage:** This implements only section 3.3: deployment, Markdown-skill, and project-note administration are no longer primary workflow surfaces. Existing conversation and administration behavior stays intact.

**Scope:** No data model, provider protocol, generation command, or media behavior changes.

**Consistency:** `_AssistantAdvancedPanel` receives the existing `int projectId`; `_ProjectNotesPane` already takes that value. `_AssistantDeployPane` and `_AssistantSkillsPane` remain parameterless.
