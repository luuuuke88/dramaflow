# Task Center Pagination Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make DramaFlow's task history match ToonFlow's usable task-center scope: all-project browsing, SQL-filtered history, page navigation, page size, and explicit refresh on desktop and mobile.

**Architecture:** Keep task history in the embedded SQLite engine. One immutable query value describes the optional project, class, state, page, and limit; the engine returns rows plus a total count. Riverpod observes that query and the existing task-generation revision. The screen uses the same responsive controls and pagination model at every width rather than maintaining separate mobile data paths.

**Tech Stack:** Flutter Material 3, Riverpod 3, sqlite3, existing `Engine`, widget and engine tests, generated l10n.

## Global Constraints

- Match `Toonflow-web/src/views/task/index.vue` and `Toonflow-app/src/routes/task/getTaskApi.ts`: newest-first history, optional project/class/state filters, total count, page, and page size.
- A null project filter means all projects; a concrete project ID means only that project. Do not default to the first project.
- Apply history filters in parameterized SQLite queries. Never load all historical tasks into Flutter merely to filter them.
- Keep the existing active-task panel and DramaFlow-only cancel/retry actions. Those actions must refresh the same paginated history query.
- Do not change provider credentials, `o_secret`, task execution, video submission/polling, or make any real provider request.
- No schema migration is needed. Tests use in-memory SQLite and fake gateways only.

---

### Task 1: Engine Task-History Query Contract

**Files:**
- Modify: `app/lib/src/engine/queue.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Create: `app/test/engine/task_history_test.dart`

**Interfaces:**
- `TaskHistoryQuery({int? projectId, String? taskClass, String? state, int page = 1, int limit = 10})` normalizes blank class/state to null and clamps page/limit to at least one.
- `TaskHistoryPage({required List<TasksRow> items, required int total, required TaskHistoryQuery query})` reports `totalPages` as at least one.
- `Engine.taskHistory(TaskHistoryQuery query)` runs one parameterized `COUNT(*)` and one newest-first (`o_tasks.id DESC`) page query.
- `Engine.taskHistoryClasses()` returns all nonblank task classes in ascending order.
- `TasksRow.projectName` is optional and populated when a history query joins `o_project.name AS projectName`; non-history task paths retain null.

- [x] **Step 1: Write failing engine tests**

Create 27 tasks across two projects, with mixed `event_generation` / `asset_extraction` classes and `success` / `failed` states. Assert all-project page 2 returns IDs 17 through 8 in descending order and `total == 27`; assert a project/class/state query returns only its matching rows and count; assert the joined project name is present. Assert distinct classes are global, sorted, and do not include an empty class.

- [x] **Step 2: Verify RED**

```sh
cd app
flutter test --concurrency=1 test/engine/task_history_test.dart
```

Expected: compilation fails because `TaskHistoryQuery`, `TaskHistoryPage`, `taskHistory`, and `taskHistoryClasses` do not yet exist.

- [x] **Step 3: Implement the smallest query boundary**

Add the two immutable data classes beside `TasksRow`. Extend `TasksRow.fromRow` with an optional `projectName` field. In `Engine.taskHistory`, build only these SQL clauses:

```dart
final where = <String>[];
final params = <Object?>[];
if (query.projectId != null) { where.add('o_tasks.projectId=?'); params.add(query.projectId); }
if (query.taskClass != null) { where.add('o_tasks.taskClass=?'); params.add(query.taskClass); }
if (query.state != null) { where.add('o_tasks.state=?'); params.add(query.state); }
final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
```

Use `SELECT COUNT(*) AS total FROM o_tasks$whereSql` with `params`, then select `o_tasks.*,
o_project.name AS projectName` with the same clauses, `LEFT JOIN o_project`, `ORDER BY o_tasks.id DESC`, `LIMIT ? OFFSET ?`. Add no database index or cache in this task because the original table has no index requirement and the bounded query fixes the current unbounded UI issue.

- [x] **Step 4: Verify green and commit**

```sh
cd app
flutter analyze
flutter test --concurrency=1 test/engine/task_history_test.dart test/engine/engine_facade_test.dart
cd ..
git add app/lib/src/engine/queue.dart app/lib/src/engine/engine.dart app/test/engine/task_history_test.dart
git commit -m "feat(tasks): add paged task history query"
```

### Task 2: Shared Query Provider And Responsive Task-Center Controls

**Files:**
- Modify: `app/lib/src/state/providers.dart`
- Modify: `app/lib/src/screens/tasks_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`
- Modify: `app/test/widgets/tasks_screen_test.dart`

**Interfaces:**
- `taskHistoryProvider` is a `FutureProvider.autoDispose.family<TaskHistoryPage, TaskHistoryQuery>` and watches `jobsGenerationProvider`.
- `taskHistoryClassesProvider` is an auto-dispose future provider and watches `jobsGenerationProvider`.
- The history screen owns a `TaskHistoryQuery`, begins at `projectId: null`, and resets `page` to one whenever project, class, state, or limit changes.
- Stable keys: `task-history-refresh`, `task-project-filter`, `task-class-filter`, `task-state-filter`, `task-page-size`, `task-page-previous`, and `task-page-next`.

- [x] **Step 1: Write failing widget tests**

Extend the fixture with a second project and enough rows to exceed 10 items. Add one desktop test that starts in “all projects,” shows task project names, selects a class filter, changes page size, moves to the next page, and verifies only the engine-returned page is visible. Add a 390 x 760 test that switches to one project, moves pages with icon controls, then returns to all projects. Add a refresh test that inserts a new row after the first load, taps the explicit refresh control, and observes it without recreating the screen.

- [x] **Step 2: Verify RED**

```sh
cd app
flutter test --concurrency=1 test/widgets/tasks_screen_test.dart
```

Expected: the tests fail because the current picker has no all-project item, the page controls do not exist, and history is limited to one project's 50 rows.

- [x] **Step 3: Wire the existing screen to the engine contract**

Replace `projectJobsProvider` consumption inside `_HistorySection` with the new query provider. Keep `activeJobsProvider` untouched. Render project/type/state controls in a wrapping layout, with a null project represented by the localized “all projects” item. Put the explicit refresh `IconButton` in the AppBar and retain pull-to-refresh; both bump `jobsGenerationProvider`, refresh active jobs, and invalidate the project/class providers.

Render pagination below history: page-size selection `10/25/50`, previous/next icon buttons with tooltips, and a localized `page / totalPages` summary. Disable prior/next at the ends. Use `Wrap` and fixed icon buttons so the same controls fit at 390dp. When `TasksRow.projectName` is nonblank, include it in the tile subtitle; otherwise retain the existing numeric fallback.

After cancel or retry, bump `jobsGenerationProvider` so an all-project, filtered, or later-page history view refreshes correctly. Do not query or alter any video task beyond showing its existing row.

- [x] **Step 4: Verify green and commit**

```sh
cd app
flutter gen-l10n
flutter analyze
flutter test --concurrency=1 test/widgets/tasks_screen_test.dart test/l10n_test.dart
cd ..
git add app/lib/src/state/providers.dart app/lib/src/screens/tasks_screen.dart \
  app/lib/l10n/app_*.arb app/lib/l10n/app_localizations*.dart \
  app/test/widgets/tasks_screen_test.dart
git commit -m "feat(tasks): add cross-project history pagination"
```

### Task 3: Parity Evidence And Authoritative Gates

**Files:**
- Modify: `docs/parity/task-center-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/feature-parity-execution-report.md`
- Modify: this plan

**Interfaces:**
- `W6-TASK-001` and `W7F-TASK-LIST-001` become `已验证等价` only after all gates pass.
- `W9A-DBTABLE-TASKS-001` is reassessed from its dependent rows; unrelated task-table facets remain honestly scoped.

- [x] **Step 1: Update evidence from measured behavior**

Replace the current “first project / recent 50 / client filters” statements with the concrete engine query contract, page controls, 390dp evidence, and retained cancel/retry extension. Record that all checks use local SQLite and fake gateways and that no video generation, polling, or provider request ran. Update aggregate counts only after counting the changed checklist statuses.

- [x] **Step 2: Run authoritative gates**

```sh
cd app
flutter analyze
flutter test --concurrency=1
flutter build macos --debug
cd ..
node tool/parity/check_no_orphans.js
git diff --check
```

Expected: no analyzer issues, full offline suite and debug build pass, every inventory item remains covered, and no whitespace errors appear.

- [x] **Step 3: Commit**

```sh
git add docs/parity/task-center-matrix.md docs/parity/master-checklist.md \
  docs/parity/feature-parity-execution-report.md \
  docs/superpowers/plans/2026-07-20-task-center-pagination-parity.md
git commit -m "docs(parity): verify paged task center"
```

## Plan Self-Review

- **Coverage:** all four confirmed gaps in `task-center-matrix.md` are mapped: all projects, SQL filtering, page size/pagination, and explicit refresh. Failure details and existing cancel/retry remain covered rather than being replaced.
- **Scope:** task execution, providers, credentials, queue lanes, video generation, and schema remain untouched.
- **Type consistency:** the engine's `TaskHistoryQuery` / `TaskHistoryPage` types are defined before Riverpod consumes them; UI state changes produce a new query and therefore cannot silently reuse a stale page.
