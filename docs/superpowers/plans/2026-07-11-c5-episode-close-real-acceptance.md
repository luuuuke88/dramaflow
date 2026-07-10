# C5 Episode Close And Real Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the episode-export workflow with safe retry attempts, fail-closed NLE effects, real AVFoundation evidence, and a user-observed Mac provider acceptance run.

**Architecture:** Keep production work in the existing engine command layer. A retry clones a failed task into a new persisted attempt while preserving the failed row and its reason; video retries reuse accepted non-terminal upstream work and never resubmit uncertain work. Composition validates effect metadata before invoking the shared native method channel, then the existing AVFoundation/Media3 implementations export and register the final clip.

**Tech Stack:** Flutter/Dart, SQLite, Riverpod, Flutter integration tests, AVFoundation, Media3, local AZT/OpenAI-compatible providers, Volcengine Seedance.

## Global Constraints

- No real provider call is made by automated tests.
- UI buttons and assistant actions continue to call the same engine commands.
- A retry must preserve the original failed task and reason as visible history.
- An accepted non-terminal Seedance task resumes polling and is never submitted twice.
- An uncertain Seedance submission is never automatically retried.
- Unknown transitions or filters fail before native export; they are never silently dropped.
- macOS real acceptance precedes iOS/iPadOS and Android validation.
- The user must observe and accept the real provider workflow and final episode.

---

### Task 1: Persist Retry Attempts Without Erasing Failure History

**Files:**
- Modify: `app/lib/src/engine/queue.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/screens/tasks_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Test: `app/test/engine/engine_facade_test.dart`
- Test: `app/test/engine/assets_test.dart`
- Test: `app/test/widgets/tasks_screen_test.dart`

**Interfaces:**
- Consumes: `Engine.retryJob(int taskId)`, `TasksRow.relatedObjectsJson`, and task-private payload files.
- Produces: `TasksRow.attempt`, `TasksRow.previousAttemptId`, `TasksRow.supersededByTaskId`, and a new task ID from every successful retry.

- [ ] **Step 1: Write failing retry-history tests.**

Replace the old in-place retry expectation with assertions equivalent to:

```dart
final retryId = await engine.retryJob(failedId);
expect(retryId, isNot(failedId));
final rows = db.select(
  'SELECT id,state,reason,relatedObjects FROM o_tasks ORDER BY id',
);
expect(rows, hasLength(2));
expect(rows.first['state'], 'failed');
expect(rows.first['reason'], contains(errNetwork));
expect(rows.last['state'], 'pending');
expect(TasksRow.fromRow(rows.last).attempt, 2);
expect(TasksRow.fromRow(rows.last).previousAttemptId, failedId);
expect(TasksRow.fromRow(rows.first).supersededByTaskId, retryId);
```

Update the private-payload regression so the payload moves to `$retryId.payload`, the failed attempt retains its reason, and the new payload is removed only after the new attempt succeeds.

Update the task-center test to assert that both the failed row and the pending retry row remain visible, the retry row shows `第 2 次`/`Attempt 2`, and the superseded failed row no longer exposes another retry button.

- [ ] **Step 2: Run the focused tests and verify failure.**

Run:

```bash
cd app
flutter test test/engine/engine_facade_test.dart test/engine/assets_test.dart test/widgets/tasks_screen_test.dart --reporter compact
```

Expected: FAIL because retry currently mutates the failed row in place.

- [ ] **Step 3: Add retry metadata accessors to `TasksRow`.**

Use a reserved `_retry` object inside `relatedObjects` so no schema migration is required:

```dart
Map<String, dynamic> get retryJson {
  final value = relatedObjectsJson['_retry'];
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

int get attempt => ((retryJson['attempt'] as num?)?.toInt() ?? 1).clamp(1, 9999);
int? get previousAttemptId => (retryJson['previousTaskId'] as num?)?.toInt();
int? get supersededByTaskId =>
    (retryJson['supersededByTaskId'] as num?)?.toInt();
```

- [ ] **Step 4: Clone failed tasks atomically in `retryJob`.**

Preserve the old state/reason, create a new pending row, and link both rows:

```dart
final oldRelated = Map<String, dynamic>.from(task.relatedObjectsJson);
final oldRetry = task.retryJson;
if (task.supersededByTaskId != null) {
  throw const EngineException(errLlmFormat, {'reason': '任务已有后续重试'});
}
final newRelated = Map<String, dynamic>.from(oldRelated)
  ..['_retry'] = {
    'attempt': task.attempt + 1,
    'rootTaskId': oldRetry['rootTaskId'] ?? task.id,
    'previousTaskId': task.id,
  };
```

Insert the new row with the same project, class, description, model, and business payload. Then update the old row's `_retry.supersededByTaskId`. Use a savepoint; if task-private payload copying fails, roll back the database and remove the partial new file. After commit, delete the old private payload and notify the queue. Return the new task ID.

- [ ] **Step 5: Show attempt lineage in the task center.**

Add localized `taskAttemptLabel(int attempt)` strings and include the label when `attempt > 1`. Hide the retry icon when `task.supersededByTaskId != null`.

- [ ] **Step 6: Run focused tests and commit.**

Run the Step 2 command, then:

```bash
cd app
flutter gen-l10n
flutter analyze
```

Expected: focused tests pass and analyze reports no issues.

Commit:

```bash
git add app/lib/src/engine/queue.dart app/lib/src/engine/engine.dart \
  app/lib/src/screens/tasks_screen.dart app/lib/l10n \
  app/test/engine/engine_facade_test.dart app/test/engine/assets_test.dart \
  app/test/widgets/tasks_screen_test.dart
git commit -m "fix(tasks): preserve retry attempt history"
```

### Task 2: Make Video Retry Submission-Safe

**Files:**
- Modify: `app/lib/src/engine/engine.dart`
- Modify: `app/lib/src/engine/video_track.dart`
- Test: `app/test/engine/video_track_test.dart`

**Interfaces:**
- Consumes: Task 1's cloned retry row and existing `submissionState`, `upstreamTaskId`, `upstreamState`, `modelBinding`, and `requestFingerprint` fields.
- Produces: `prepareVideoRetry(TasksRow task) -> Map<String, Object?>`, used by `retryJob` before the new task is inserted.

- [ ] **Step 1: Write failing video retry tests.**

Cover these three contracts:

```dart
test('accepted running retry reuses upstream id without submit', () async {
  // Failed task references an accepted candidate with upstreamState=running.
  final retryId = await engine.retryJob(failedTaskId);
  await waitTask(retryId);
  expect(gateway.submitCalls, 0);
  expect(gateway.polledIds, ['upstream-existing']);
});

test('terminal failed retry creates a new candidate and submits once', () async {
  final retryId = await engine.retryJob(failedTaskId);
  final retryVideoIds = TasksRow.fromRow(taskRow(retryId))
      .relatedObjectsJson['videoIds'] as List;
  expect(retryVideoIds.single, isNot(oldVideoId));
  await waitTask(retryId);
  expect(gateway.submitCalls, 1);
});

test('uncertain submission cannot be retried', () async {
  expect(
    () => engine.retryJob(failedTaskId),
    throwsA(isA<EngineException>().having(
      (e) => e.errParams['reason'], 'reason', 'videoSubmissionUncertain')),
  );
});
```

- [ ] **Step 2: Run the video tests and verify failure.**

Run:

```bash
cd app
flutter test test/engine/video_track_test.dart --reporter compact
```

Expected: FAIL because generic retry does not classify provider submission state.

- [ ] **Step 3: Implement `prepareVideoRetry`.**

For every referenced candidate:

- `uncertain`: throw before any database write.
- `accepted` with `queued`, `running`, or `succeeded`: reuse the candidate and reset only local row/track state to generating; polling continues with the stored upstream ID.
- `accepted` with terminal `failed` or `canceled`, or `prepared`: build the current validated request and insert a new prepared candidate with its current model binding and fingerprint; preserve the old candidate as failed history.
- Return cloned task business data with only the retry candidate/track IDs.

`Engine.retryJob` calls this method only for `video_generation`; all other task classes clone their existing business data unchanged.

- [ ] **Step 4: Run tests and commit.**

Run:

```bash
cd app
flutter test test/engine/video_track_test.dart test/engine/engine_facade_test.dart --reporter compact
flutter analyze
```

Commit:

```bash
git add app/lib/src/engine/engine.dart app/lib/src/engine/video_track.dart \
  app/test/engine/video_track_test.dart
git commit -m "fix(video): retry without duplicate submission"
```

### Task 3: Reject Unsupported Composition Effects

**Files:**
- Modify: `app/lib/src/engine/compose.dart`
- Modify: `app/lib/src/engine/compose_episode.dart`
- Modify: `app/lib/src/platform/avfoundation_composer.dart`
- Test: `app/test/engine/compose_episode_test.dart`
- Test: `app/test/platform/apple_composer_static_test.dart`
- Test: `app/test/platform/android_composer_static_test.dart`

**Interfaces:**
- Consumes: `ComposeSegment.transition` and `ComposeSegment.filter`.
- Produces: `validateComposeSegments(List<ComposeSegment>)` and exported supported preset constants.

- [ ] **Step 1: Write failing validation tests.**

```dart
test('unknown transition fails before composer invocation', () async {
  // Seed one selected segment, then corrupt/import an unsupported transition.
  engine.updateVideoTransition(trackId, 'unknown_transition');
  expect(
    () => engine.composeEpisode(projectId, scriptId),
    throwsA(isA<EngineException>().having(
      (e) => e.errKey, 'errKey', errPlatformComposer)),
  );
  expect(composer.composeCalls, isEmpty);
});

test('known transition and filter pass validation', () {
  expect(
    () => validateComposeSegments(const [
      ComposeSegment(
        videoAbsPath: '/tmp/a.mp4',
        transition: 'dissolve',
        filter: 'vintage',
      ),
    ]),
    returnsNormally,
  );
});
```

- [ ] **Step 2: Run focused tests and verify failure.**

Run:

```bash
cd app
flutter test test/engine/compose_episode_test.dart test/platform/apple_composer_static_test.dart test/platform/android_composer_static_test.dart --reporter compact
```

Expected: FAIL because unknown presets are currently silently ignored.

- [ ] **Step 3: Implement shared validation.**

```dart
const supportedComposeTransitions = {'fade', 'dissolve', 'whip_pan'};
const supportedComposeFilters = {'cinematic', 'warm', 'cool', 'vintage'};

void validateComposeSegments(List<ComposeSegment> segments) {
  for (final segment in segments) {
    final transition = segment.transition;
    if (transition != null &&
        transition.isNotEmpty &&
        !supportedComposeTransitions.contains(transition)) {
      throw EngineException(errPlatformComposer, {
        'effect': 'transition',
        'value': transition,
      });
    }
    final filter = segment.filter;
    if (filter != null &&
        filter.isNotEmpty &&
        !supportedComposeFilters.contains(filter)) {
      throw EngineException(errPlatformComposer, {
        'effect': 'filter',
        'value': filter,
      });
    }
  }
}
```

Call it in `composeEpisode` before creating/exporting the output and in `AVFoundationComposer.compose` before invoking the platform channel. Keep native implementations defensive, but do not duplicate preset lists in UI code.

- [ ] **Step 4: Run tests and commit.**

Run the Step 2 command and `flutter analyze`.

Commit:

```bash
git add app/lib/src/engine/compose.dart app/lib/src/engine/compose_episode.dart \
  app/lib/src/platform/avfoundation_composer.dart \
  app/test/engine/compose_episode_test.dart \
  app/test/platform/apple_composer_static_test.dart \
  app/test/platform/android_composer_static_test.dart
git commit -m "fix(composer): reject unsupported effects"
```

### Task 4: Prove The Native Mac Episode Closure

**Files:**
- Modify: `app/integration_test/composer_audio_smoke_test.dart`
- Test fixture: `app/integration_test/fixtures/clip_red_2s.mp4`
- Test fixture: `app/integration_test/fixtures/clip_blue_2s.mp4`
- Test fixture: `app/integration_test/fixtures/voice_880hz_1500ms.m4a`

**Interfaces:**
- Consumes: `Engine.composeEpisode`, `AVFoundationComposer`, selected `o_video` candidates, storyboard audio binding, transition metadata, and clip registration.
- Produces: a device integration test proving a playable MP4 with video/audio tracks and persisted clip output.

- [ ] **Step 1: Add a full engine-to-native integration test.**

The test must:

1. Create an in-memory engine with a temporary media root and `AVFoundationComposer`.
2. Create a project, script, and two storyboards in reverse insertion order, then reorder by storyboard IDs.
3. Add an invalid unselected candidate plus valid red/blue selected candidates.
4. Bind the standalone audio fixture to one storyboard.
5. Set a supported `fade` transition.
6. Call `composeEpisode`.
7. Assert output exists, `segmentCount == 2`, video track count is one, audio track count is one, duration is within the expected combined range, and the returned `clipAssetId` resolves to the output path.

- [ ] **Step 2: Run the real macOS integration test.**

Run:

```bash
cd app
flutter test integration_test/composer_audio_smoke_test.dart -d macos --reporter expanded
```

Expected: all integration tests pass and AVFoundation writes inspectable MP4 files.

- [ ] **Step 3: Run automated release checks and commit.**

Run:

```bash
cd app
flutter test --reporter compact
flutter analyze
flutter build macos --debug
```

Commit:

```bash
git add app/integration_test/composer_audio_smoke_test.dart
git commit -m "test(macos): verify native episode closure"
```

### Task 5: Run And Record Real Mac Provider Acceptance

**Files:**
- Create: `docs/superpowers/acceptance/2026-07-11-c5-mac-provider-acceptance.md`
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: configured AZT text/image provider, configured Volcengine Seedance credential, bundled manuals, task retry lineage, video recovery, and native composer.
- Produces: user-signed evidence for all twelve acceptance steps in spec section 10.2.

- [ ] **Step 1: Record preflight without exposing credentials.**

Record:

- App commit and build path.
- Provider/model bindings.
- `hasCredential` status only; never write API keys.
- Local service health for ports 8787/3333/10531.
- Selected visual/director pack IDs and Seedance capability modes.

- [ ] **Step 2: Complete the twelve real workflow steps.**

Use a fresh novel project and record the project ID, task IDs, generated asset/image/video IDs, selected candidate IDs, output clip asset ID, and final MP4 relative path. At least one video must use first-frame mode and one must use multi-reference mode when the configured Seedance model declares both.

- [ ] **Step 3: Exercise recovery and visible retry.**

During one accepted long Seedance task, quit and reopen the app. Record the same upstream task ID before/after and prove no second submission was created. Trigger one controlled provider/configuration failure, then retry from the task center and record both the preserved failed attempt and the successful new attempt.

- [ ] **Step 4: User playback and experience sign-off.**

The user plays the final MP4 and records accepted/rejected for:

- episode image/video consistency;
- audio presence and timing;
- transition behavior;
- every workflow step's usability;
- overall first-episode acceptance.

No automated assertion substitutes for this signature.

- [ ] **Step 5: Commit the acceptance record only after user sign-off.**

```bash
git add docs/superpowers/acceptance/2026-07-11-c5-mac-provider-acceptance.md \
  .superpowers/sdd/progress.md
git commit -m "docs(acceptance): record C5 Mac provider run"
```

### Task 6: Validate iOS/iPadOS And Android After Mac Acceptance

**Files:**
- Modify: `docs/superpowers/acceptance/2026-07-11-c5-mac-provider-acceptance.md`

**Interfaces:**
- Consumes: a signed Mac acceptance record from Task 5.
- Produces: build/smoke evidence for iPhone, iPad, and Android targets.

- [ ] **Step 1: Verify the Mac signature exists.**

Do not run this task while the Mac record is unsigned or rejected.

- [ ] **Step 2: Build and smoke-test Apple mobile targets.**

```bash
cd app
flutter build ios --simulator --debug
```

Launch on one iPhone and one iPad simulator. Verify project/manual/provider configuration, local database persistence, and production navigation. Provider generation may use a configured remote provider; mobile must not assume AZT loopback exists.

- [ ] **Step 3: Build and smoke-test Android.**

```bash
cd app
flutter build apk --debug
```

Launch on an Android emulator/device and verify the same persistence and production navigation plus one local Media3 composition smoke test.

- [ ] **Step 4: Record platform results and commit.**

Append device/runtime/build evidence to the acceptance record, then commit:

```bash
git add docs/superpowers/acceptance/2026-07-11-c5-mac-provider-acceptance.md
git commit -m "docs(acceptance): record mobile validation"
```

## Plan Self-Review

**Spec coverage:** Task 1 preserves visible retry history; Task 2 proves restart/retry does not duplicate paid video submission; Task 3 enforces unsupported-effect errors; Task 4 verifies candidate selection, shot order, audio, transition, native MP4 export, and output registration; Task 5 covers all twelve real Mac acceptance steps; Task 6 preserves the required Mac-before-mobile order.

**Scope limits:** No new NLE feature, provider protocol, assistant hierarchy, Web engine, Windows package, or ToonFlow database import is introduced.

**Placeholder scan:** Every implementation step names concrete files, contracts, commands, and expected evidence. The acceptance record intentionally remains unsigned until the user performs the real run; that is a release gate, not a code placeholder.

**Type consistency:** Retry metadata stays inside `relatedObjects._retry`; video retry consumes the same task/candidate fields already introduced in C3; composition validation consumes existing `ComposeSegment` fields.
