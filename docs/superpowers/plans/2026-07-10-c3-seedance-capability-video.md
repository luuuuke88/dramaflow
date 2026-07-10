# C3 Seedance Capability Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current first-frame-only Seedance call with capability-validated text, first-frame, first/last-frame, and multi-reference requests that persist, resume, and cancel without duplicate paid submission.

**Architecture:** Model capabilities remain data in `o_vendorConfig.models`; a pure Dart request layer parses that data and validates a `VideoGenerationRequest` before it reaches a provider. Per-shot choices are stored in one versioned `o_videoTrack.videoRequest` JSON document, while each generated candidate stores its immutable model/fingerprint and upstream identity. The Volcengine adapter becomes explicit submit/poll/cancel operations, letting an interrupted app resume only a known upstream task.

**Tech Stack:** Flutter/Dart 3.5, SQLite additive migration, existing `ProviderGateway`, Dio, Volcengine `contents/generations/tasks` API, `crypto` SHA-256, existing desktop/mobile workbench dialogs.

## Global Constraints

- Keep the user-approved scope: no vector/vision Agent, no web engine, no new backend service, and no custom JavaScript runtime.
- `ProjectRow.videoModel` is the preferred execution model; an empty project value falls back to `binding.shot_video` for old projects.
- A mode is available only when the selected model explicitly declares it. Do not infer Seedance Mini multi-reference or audio support from its name.
- Canonical C3 modes are `text`, `first_frame`, `first_last_frame`, and `multi_reference`; providers translate those to their native request roles.
- Existing first-frame flow stays compatible by migrating an empty per-shot request to the selected model's `first_frame` default when that capability exists.
- Task JSON stores candidate IDs, model binding, fingerprints, and upstream IDs only. It never stores API keys or a duplicate raw prompt.
- Keep storyboard composition audio (`audioAssetId`) separate from the provider's `generateAudio` setting.
- On restart, resume polling only candidates with a persisted upstream task ID. A candidate whose create response was uncertain must not be resubmitted automatically.
- Preserve current candidate history, first-success auto-selection, existing selection on later candidates, partial-batch success, and local media ownership rules.
- All user-visible copy has Chinese, English, and Japanese ARB entries. Desktop uses a compact dialog; mobile uses the same full-screen adaptive-dialog pattern.

---

## Capability Document

The value inside `ProviderModelInfo.capabilities` for a video model has this stable shape:

```json
{
  "video": {
    "modes": ["text", "first_frame", "first_last_frame", "multi_reference"],
    "references": {"image": 9, "video": 3, "audio": 3},
    "durations": [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    "resolutions": ["480p", "720p"],
    "ratios": ["16:9", "9:16"],
    "audio": "optional",
    "promptTemplates": {
      "text": "video/universalMulti-parameterMode.md",
      "first_frame": "video/wan2.6Single-imageFirstFrameMode.md",
      "first_last_frame": "video/universalFirstAndLastFrameMode.md",
      "multi_reference": "video/seedance2Multi-parameterMode.md"
    }
  }
}
```

`audio` is exactly `"none"`, `"optional"`, or `"required"`. `references` supplies upper bounds for `multi_reference`; first-frame modes have fixed image requirements independent of those limits. Unknown keys are preserved by the settings editor but ignored by the validator. Older models with only `durations`/`resolutions` receive a compatibility `first_frame` profile until the user edits their declaration.

## File Structure

- Create: `app/lib/src/engine/video_request.dart` — immutable request/reference/value classes, capability parser, validation, fingerprint material, JSON codecs.
- Modify: `app/lib/src/engine/engine.dart` — bundled explicit profiles, project-model resolution helpers, and default request migration helpers.
- Modify: `app/lib/src/engine/db.dart` — version 10 additive columns and migration.
- Modify: `app/lib/src/engine/queue.dart` — opt-in cold-start resumer without changing old task recovery behavior.
- Modify: `app/lib/src/engine/providers/gateway.dart` — typed video submit/poll/cancel contract and model override resolution.
- Modify: `app/lib/src/engine/providers/volcengine_video.dart` — native Seedance serialization, one-poll status parsing, download, and upstream cancellation.
- Modify: `app/lib/src/engine/video_track.dart` — per-shot request persistence, prompt-template provenance, preflight, candidate lifecycle, recovery and remote cancellation.
- Modify: `app/lib/src/screens/project/project_dialog.dart` — hydrate the selected model's capabilities for existing projects.
- Modify: `app/lib/src/screens/settings_screen.dart` — editable structured video-capability form for custom video models.
- Create: `app/lib/src/screens/production/video_request_dialog.dart` — adaptive per-shot parameters and reference selection.
- Modify: `app/lib/src/screens/production/workbench_screen.dart` — open the parameters dialog, distinguish composition audio from provider audio, and pass no ad-hoc request fields.
- Modify: `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_ja.arb` — video capability and parameter labels/errors.
- Test: `app/test/engine/video_request_test.dart`, `app/test/engine/db_test.dart`, `app/test/engine/providers_test.dart`, `app/test/engine/video_conn_test.dart`, `app/test/engine/video_track_test.dart`, `app/test/widgets/project_page_test.dart`, `app/test/widgets/settings_screen_test.dart`, `app/test/widgets/workbench_screen_test.dart`.

## Task 1: Capability Schema And Typed Video Requests

**Files:**
- Create: `app/lib/src/engine/video_request.dart`
- Modify: `app/lib/src/engine/engine.dart`
- Test: `app/test/engine/video_request_test.dart`
- Test: `app/test/engine/engine_facade_test.dart`

**Interfaces:**

```dart
enum VideoMode { text, firstFrame, firstLastFrame, multiReference }

class VideoReference {
  final String mediaType; // image | video | audio
  final String role; // first_frame | last_frame | reference_image | reference_video | reference_audio
  final String localPath; // media-relative path, never an absolute path
}

class VideoModelCapabilities {
  final Set<VideoMode> modes;
  final Map<String, int> referenceLimits;
  final Set<int> durations;
  final Set<String> resolutions;
  final Set<String> ratios;
  final String audio; // none | optional | required
  final Map<VideoMode, String> promptTemplates;
}

class VideoGenerationRequest {
  final String modelBinding; // providerId:modelId
  final VideoMode mode;
  final String prompt;
  final List<VideoReference> references;
  final int duration;
  final String resolution;
  final String ratio;
  final bool generateAudio;
  final int projectId;
  final int storyboardId;
  final int videoTrackId;
  VideoGenerationRequest copyWith({int? duration});
  String fingerprintMaterial();
  String fingerprint();
}
```

- [x] **Step 1: Write failing parser and local-validation tests.**

Create a fully declared capability fixture and assert parsing plus rejection before any provider call. Cover the exact cardinality rules below.

```dart
final firstFrameOnly = const VideoReference(
  mediaType: 'image', role: 'first_frame', localPath: 'p/first.png');
final fourImageReferences = [
  for (var i = 0; i < 4; i++) VideoReference(
      mediaType: 'image', role: 'reference_image', localPath: 'p/$i.png'),
];
VideoGenerationRequest requestFor({
  required VideoMode mode,
  required List<VideoReference> references,
}) => VideoGenerationRequest(
  modelBinding: 'volcengine:test-video', mode: mode, prompt: 'PROMPT',
  references: references, duration: 4, resolution: '720p', ratio: '16:9',
  generateAudio: false, projectId: 1, storyboardId: 2, videoTrackId: 3,
);
final caps = VideoModelCapabilities.fromJson({
  'video': {
    'modes': ['text', 'first_frame', 'first_last_frame', 'multi_reference'],
    'references': {'image': 3, 'video': 1, 'audio': 1},
    'durations': [4, 5],
    'resolutions': ['480p', '720p'],
    'ratios': ['16:9', '9:16'],
    'audio': 'optional',
  },
});
expect(caps.supports(VideoMode.multiReference), isTrue);
expect(
  () => caps.validate(requestFor(mode: VideoMode.firstLastFrame,
      references: [firstFrameOnly])),
  throwsA(isA<EngineException>()),
);
expect(
  () => caps.validate(requestFor(mode: VideoMode.text,
      references: [firstFrameOnly])),
  throwsA(isA<EngineException>()),
);
expect(
  () => caps.validate(requestFor(mode: VideoMode.multiReference,
      references: fourImageReferences)),
  throwsA(isA<EngineException>()),
);
```

Also test that fingerprints change when any paid-output input changes and do not embed an absolute media-root path:

```dart
expect(request.copyWith(duration: 5).fingerprint(),
    isNot(request.copyWith(duration: 4).fingerprint()));
expect(request.fingerprintMaterial(), isNot(contains(tempDirectory.path)));
```

- [x] **Step 2: Run the focused test and verify it fails because the capability/request API is absent.**

Run: `cd app && flutter test test/engine/video_request_test.dart --reporter compact`

Expected: FAIL with missing `VideoModelCapabilities`, `VideoGenerationRequest`, or `VideoMode` symbols.

- [x] **Step 3: Implement the pure domain layer.**

Use enum wire values and deterministic sorted fingerprint JSON. Compute the fingerprint directly with `sha256.convert(utf8.encode(material)).toString()` from `crypto`; do not import C2's `prompt_resolver.dart` into this pure request file. The validator must enforce:

```dart
switch (request.mode) {
  case VideoMode.text:
    require(references.isEmpty);
  case VideoMode.firstFrame:
    require(exactlyOneRole('first_frame'));
  case VideoMode.firstLastFrame:
    require(exactlyOneRole('first_frame'));
    require(exactlyOneRole('last_frame'));
  case VideoMode.multiReference:
    require(noFirstOrLastFrameRoles);
    requireCountAtMost('image', referenceLimits['image'] ?? 0);
    requireCountAtMost('video', referenceLimits['video'] ?? 0);
    requireCountAtMost('audio', referenceLimits['audio'] ?? 0);
}
require(durations.contains(request.duration));
require(resolutions.contains(request.resolution));
require(ratios.contains(request.ratio));
require(audio != 'none' || !request.generateAudio);
require(audio != 'required' || request.generateAudio);
```

Throw `EngineException(errModelMissing, {'reason': ...})` for a missing/unsupported profile and `EngineException(errLlmFormat, {'reason': ...})` for an invalid local request. Keep `VideoReference.localPath` relative and reject empty/absolute paths.

- [x] **Step 4: Seed explicit known profiles without overstating Mini support.**

In `Engine._seedDefaults`, retain the existing Mini duration/resolution data and add only its compatibility `first_frame` capability. Add the documented full/fast Seedance 2.0 entries with all declared modes only when no user row for the same model exists. Use the exact C3 capability document structure; neither model is selected automatically for an existing project.

The compatibility conversion is explicit:

```dart
VideoModelCapabilities.fromJson(oldCapabilities, legacyFirstFrame: true)
```

It returns `{firstFrame}`, the existing durations/resolutions, ratios `{16:9, 9:16}`, and audio `none` only for records with no `video` object. It must not invent `multi_reference`.

- [x] **Step 5: Run focused tests, format, and static analysis.**

Run: `cd app && dart format --output=none --set-exit-if-changed lib/src/engine/video_request.dart lib/src/engine/engine.dart test/engine/video_request_test.dart && flutter test test/engine/video_request_test.dart test/engine/engine_facade_test.dart --reporter compact && flutter analyze`

Expected: both test files pass and analysis reports `No issues found`.

- [x] **Step 6: Commit the capability layer.**

```bash
git add app/lib/src/engine/video_request.dart app/lib/src/engine/engine.dart app/test/engine/video_request_test.dart app/test/engine/engine_facade_test.dart
git commit -m "feat(video): add capability-validated request model"
```

## Task 2: Safe Persistence And Resumable Queue State

**Files:**
- Modify: `app/lib/src/engine/db.dart`
- Modify: `app/lib/src/engine/queue.dart`
- Modify: `app/lib/src/engine/video_track.dart`
- Test: `app/test/engine/db_test.dart`
- Test: `app/test/engine/video_track_test.dart`

**Interfaces:**

```dart
enum ColdStartDisposition { fail, resume }
typedef TaskColdStartResumer = ColdStartDisposition Function(TasksRow task);

void registerColdStartResumer(String taskClass, TaskColdStartResumer fn);

class VideoReferenceSource {
  final String sourceType; // storyboard | asset | video | audio
  final int sourceId;
  final String mediaType; // image | video | audio
  final String role;
}

class VideoRequestDraft {
  final int version;
  final VideoMode mode;
  final List<VideoReferenceSource> references;
  final int duration;
  final String resolution;
  final String ratio;
  final bool generateAudio;
  Map<String, Object?> toJson();
}

class VideoReferenceCandidate {
  final VideoReferenceSource source;
  final String label;
  final String localPath;
}

// o_videoTrack.videoRequest JSON (controls only)
{
  "version": 1,
  "mode": "first_frame",
  "references": [
    {"sourceType":"storyboard","sourceId":42,"mediaType":"image","role":"first_frame"}
  ],
  "duration": 5,
  "resolution": "720p",
  "ratio": "16:9",
  "generateAudio": false
}
```

- [x] **Step 1: Write failing migration and recovery-disposition tests.**

Create a v9 fixture database containing populated project/video/videoTrack rows, open it through `openEngineDb`, and assert every old value remains while the new nullable columns exist. Test the new queue behavior without changing any old recovery hook:

```dart
queue.registerColdStartResumer('video_generation', (task) {
  expect(task.id, taskId);
  return ColdStartDisposition.resume;
});
queue.recoverOnColdStart();
expect(taskState(taskId), 'pending');

queue.registerColdStartResumer('video_generation', (_) => ColdStartDisposition.fail);
queue.recoverOnColdStart();
expect(taskState(taskId), 'failed');
```

Add a video-track JSON round-trip assertion that provider audio does not alter the unrelated storyboard composition audio binding.

- [x] **Step 2: Run targeted tests and verify the missing schema/API failure.**

Run: `cd app && flutter test test/engine/db_test.dart test/engine/video_track_test.dart --reporter compact`

Expected: FAIL because schema version 10, `videoRequest`, and `registerColdStartResumer` do not exist.

- [x] **Step 3: Add only additive v10 storage.**

Bump `schemaVersion` to 10. In `initSchema`, declare these columns on new databases:

```sql
-- o_videoTrack
videoRequest TEXT,
promptProvenance TEXT,

-- o_video
modelBinding TEXT,
requestFingerprint TEXT,
submissionState TEXT,
upstreamTaskId TEXT,
upstreamState TEXT,
upstreamUpdatedAt INTEGER
```

In migration case `9`, use `_addColumnIfMissing` for each exact column. Do not recreate, delete, or copy any existing table. Add indexes:

```sql
CREATE INDEX IF NOT EXISTS idx_o_video_upstream ON o_video(upstreamTaskId);
CREATE INDEX IF NOT EXISTS idx_o_video_track_state ON o_video(videoTrackId, state);
```

Add the helper in `db.dart` before `migrateSchema`; it must query table metadata rather than catching a broad SQL error:

```dart
void _addColumnIfMissing(Database db, String table, String definition) {
  final name = definition.trim().split(RegExp(r'\\s+')).first;
  final columns = db.select('PRAGMA table_info($table)')
      .map((row) => row['name'] as String)
      .toSet();
  if (!columns.contains(name)) {
    db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }
}
```

`submissionState` values are exactly `prepared`, `submitting`, `accepted`, and `uncertain`. A newly created local candidate begins `prepared`; it changes to `submitting` before the HTTP create call and to `accepted` only after a nonempty upstream ID is committed.

- [x] **Step 4: Add opt-in queue resumption.**

Keep current `registerRecover` behavior. Add a separate `_coldStartResumers` map and change `recoverOnColdStart` to evaluate each processing task before the bulk failure update:

```dart
final resumableIds = <int>[];
for (final task in rows) {
  if (_coldStartResumers[task.taskClass]?.call(task) ==
      ColdStartDisposition.resume) {
    resumableIds.add(task.id);
  }
}
if (resumableIds.isNotEmpty) {
  db.execute("UPDATE o_tasks SET state='pending', reason=NULL "
      "WHERE id IN (${placeholders(resumableIds)})", resumableIds);
}
// Existing failure/recover path runs only for the remaining IDs.
```

Register one video resumer that returns `resume` only when the task has at least one associated `o_video` candidate with `submissionState='accepted'` and a nonempty `upstreamTaskId`. It marks `prepared`, `submitting`, and `uncertain` in-flight rows failed with `errAppRestart`, never submits them.

- [x] **Step 5: Store per-shot controls and raw-prompt provenance separately.**

Add `videoRequestForTrack`, `updateVideoRequest`, and a `VideoRequestDraft` value API in `video_track.dart`. It must normalize old/null rows to project model defaults, but it must not write until the user saves or a generation requires a compatibility migration. `generateVideoPrompt` resolves the exact `promptTemplates[mode]` path through C2's `resolvePrompt`, then writes only C2-style IDs/kinds/hashes to `o_videoTrack.promptProvenance`; it does not use `o_videoTrack.reason` as a storage shortcut.

- [x] **Step 6: Run the database, queue, and video-track tests.**

Run: `cd app && flutter test test/engine/db_test.dart test/engine/video_track_test.dart --reporter compact && flutter analyze`

Expected: new v9 migration and resume/fail cases pass; existing cold-start failures for tasks without an upstream ID still pass.

- [x] **Step 7: Commit persistence and recovery.**

```bash
git add app/lib/src/engine/db.dart app/lib/src/engine/queue.dart app/lib/src/engine/video_track.dart app/test/engine/db_test.dart app/test/engine/video_track_test.dart
git commit -m "feat(video): persist request state and resume upstream tasks"
```

## Task 3: Typed Seedance Submit, Poll, Download, And Cancel

**Files:**
- Modify: `app/lib/src/engine/providers/gateway.dart`
- Modify: `app/lib/src/engine/providers/volcengine_video.dart`
- Modify: `app/lib/src/engine/providers/resolve.dart`
- Test: `app/test/engine/providers_test.dart`
- Test: `app/test/engine/video_conn_test.dart`

**Interfaces:**

```dart
class VideoSubmission { final String upstreamTaskId; }
class VideoPollResult {
  final String upstreamState; // queued | running | succeeded | failed | cancelled | expired
  final String? localVideoPath;
  final String? errorMessage;
  bool get isTerminal;
}

abstract class ProviderGateway {
  Future<VideoSubmission> submitVideo(VideoGenerationRequest request,
      {required String stage, CancelToken? cancelToken});
  Future<VideoPollResult> pollVideo(String upstreamTaskId, String projectId,
      {required String stage, required String? modelOverride,
       CancelToken? cancelToken});
  Future<void> cancelVideo(String upstreamTaskId,
      {required String stage, required String? modelOverride});
}
```

- [x] **Step 1: Write failing provider serialization tests.**

Use Dio's fake adapter and a real temporary media directory. Assert exact request bodies for all four canonical modes:

```dart
expect(body['ratio'], '9:16');
expect(body['duration'], 5);
expect(body['resolution'], '720p');
expect(body['generate_audio'], isFalse);
expect(body['content'], [
  {'type': 'text', 'text': 'PROMPT'},
  {'type': 'image_url', 'image_url': isA<Map>(), 'role': 'first_frame'},
]);
```

For `first_last_frame`, assert ordered `first_frame`, `last_frame`; for `multi_reference`, assert image/video/audio roles are `reference_image`, `reference_video`, `reference_audio`; for text assert the content contains only the text item. Add one-poll cases for `queued`, `running`, `succeeded` (downloads and returns a local path), `failed`, `cancelled`, and `expired`. Assert DELETE is made to the same upstream task path and a 404/unsupported cancellation is ignored by the engine caller but observable in adapter test.

- [x] **Step 2: Run provider tests and verify the old three-argument API does not satisfy them.**

Run: `cd app && flutter test test/engine/providers_test.dart test/engine/video_conn_test.dart --reporter compact`

Expected: FAIL because `submitVideo`, `pollVideo`, `cancelVideo`, and `VideoGenerationRequest` are absent.

- [x] **Step 3: Split Volcengine transport into submission and one-poll operations.**

`volcengineSubmitVideo` reads each relative reference path through `media.absPath`, detects a concrete data URI MIME type from its extension, and serializes roles exactly as above. It uses the model resolved from `request.modelBinding`, not a global config model. The body has `watermark: false` and carries ratio/duration/resolution/audio directly from the validated request.

`volcenginePollVideo` performs one GET. On `succeeded`, it downloads `content.video_url`, calls `media.saveVideo`, and returns `VideoPollResult(upstreamState: 'succeeded', localVideoPath: rel)`. On pending states it does not download. On terminal failures it returns the upstream message without treating a provider error as a malformed LLM response.

`volcengineCancelVideo` sends DELETE to `contents/generations/tasks/<id>` using the same credential/model resolution path. It treats a provider's unsupported cancel response as a best-effort failure, not a reason to leave the local candidate processing.

- [x] **Step 4: Resolve a requested project model safely.**

Add a typed `resolveModelBinding` helper that parses exactly one `providerId:modelId`, checks it is enabled and kind `video`, and returns the credential-backed `ResolvedModel`. `HttpProviderGateway` uses it whenever the request provides a binding; the old stage binding is used only when the request binding is null for legacy compatibility.

- [x] **Step 5: Run provider tests and static analysis.**

Run: `cd app && flutter test test/engine/providers_test.dart test/engine/video_conn_test.dart --reporter compact && flutter analyze`

Expected: all role/parameter/poll/cancel cases pass and no production path still calls the removed all-in-one `generateVideo` function.

- [x] **Step 6: Commit the provider split.**

```bash
git add app/lib/src/engine/providers/gateway.dart app/lib/src/engine/providers/volcengine_video.dart app/lib/src/engine/providers/resolve.dart app/test/engine/providers_test.dart app/test/engine/video_conn_test.dart
git commit -m "feat(seedance): submit poll and cancel typed video tasks"
```

## Task 4: Capability-Driven Video Candidate Pipeline

**Files:**
- Modify: `app/lib/src/engine/video_track.dart`
- Modify: `app/lib/src/engine/assistant_actions.dart`
- Test: `app/test/engine/video_track_test.dart`
- Test: `app/test/engine/assistant_actions_test.dart`

**Interfaces:**

```dart
VideoGenerationRequest Engine.buildVideoRequest({
  required int projectId,
  required int storyboardId,
  required int trackId,
});

int Engine.batchGenerateVideos(int projectId, List<int> storyboardIds,
    {int concurrentCount = 2});
```

- [x] **Step 1: Write failing pipeline tests before implementation.**

Add focused cases that prove the request is constructed from persisted project/track controls and not globals:

```dart
engine.updateVideoRequest(trackId, VideoRequestDraft(
  mode: VideoMode.firstLastFrame,
  duration: 5,
  resolution: '720p',
  ratio: '9:16',
  generateAudio: false,
  references: [storyboardFirstFrame(sbId), assetImage(lastFrameAssetId,
      role: 'last_frame')],
));
final request = engine.buildVideoRequest(
    projectId: projectId, storyboardId: sbId, trackId: trackId);
expect(request.modelBinding, 'volcengine:test-video');
expect(request.ratio, '9:16');
expect(request.references.map((r) => r.role), ['first_frame', 'last_frame']);
```

Cover all of these behavior contracts:

1. Project model wins over `binding.shot_video`; blank project model falls back.
2. Unsupported mode, ratio, duration, resolution, audio, or reference count fails before `submitVideo` and leaves no candidate row.
3. A submitted candidate immediately records `accepted`, `upstreamTaskId`, model binding, and fingerprint before the first poll.
4. A successful poll saves a candidate and preserves current auto-selection behavior.
5. `prepared` candidate can retry only when a rebuilt fingerprint matches; `uncertain` candidate is never retried by recovery or task retry.
6. Cold restart turns a known accepted candidate back into pending and polls its stored upstream ID without invoking `submitVideo`.
7. Cancel invokes `cancelVideo` best-effort for accepted candidates and marks all local candidate/track states terminal.
8. Batch partial success remains a success when one candidate completes and another fails.

- [x] **Step 2: Run the focused engine tests and verify they fail.**

Run: `cd app && flutter test test/engine/video_track_test.dart test/engine/assistant_actions_test.dart --reporter compact`

Expected: FAIL because the current pipeline needs a first frame, ignores model/request controls, and has no upstream identity.

- [x] **Step 3: Build and validate each request before enqueueing.**

`batchGenerateVideos` resolves all selected storyboard/track rows synchronously and calls `buildVideoRequest` before it changes a track state or creates an `o_tasks` row. It stores:

```dart
relatedObjects: {
  'kind': 'videoTrack',
  'trackIds': trackIds,
  'videoIds': candidateIds,
  'concurrentCount': concurrentCount,
}
model: modelBinding,
```

Create candidate rows with `submissionState='prepared'`, `modelBinding`, and a request fingerprint. Request control JSON references source IDs, not absolute paths. A valid retry may reuse only a `prepared` candidate with the same fingerprint; all other user-triggered regenerations create a new candidate, retaining history.

- [x] **Step 4: Submit first, persist the upstream identity, then poll.**

For every prepared candidate:

```dart
UPDATE o_video SET submissionState='submitting' WHERE id=?;
final submission = await gateway.submitVideo(request, stage: 'shot_video');
UPDATE o_video SET submissionState='accepted', upstreamTaskId=?,
  upstreamState='queued', upstreamUpdatedAt=? WHERE id=?;
```

On a submission exception after attempting HTTP, set `submissionState='uncertain'` and fail locally. Do not re-submit it from a queue retry/cold start. Poll accepted IDs until terminal with the existing 10-second interval and 30-minute ceiling. Write every observed upstream state/time. On success, save the returned media path, select the first candidate only if no selection exists, and clear the track reason. On failure, store the provider reason on both candidate and track.

- [x] **Step 5: Implement restart and cancellation behavior.**

The cold-start resumer returns `resume` only if the task has accepted candidates. `_runVideoGeneration` sees accepted rows and invokes only `pollVideo`; it never calls `submitVideo` for them. It marks interrupted `prepared/submitting/uncertain` rows failed and allows a manual fresh generation to make a distinct candidate.

When queue cancellation is observed, call `cancelVideo` once per distinct accepted upstream ID without the cancelled Dio token, ignore a transport/404 cancel failure, then mark locally pending/generating candidates and tracks `vtFailed` with `errCanceled`. This repairs the current dangling `生成中` state for both pending and active cancellations.

- [x] **Step 6: Integrate the assistant without a separate path.**

Keep `generate_videos` calling `batchGenerateVideos`; it receives the same preflight/confirmation/capability behavior as the workbench. Update its result text to distinguish unsupported local request errors from queued work; do not add a direct provider call in `assistant_actions.dart`.

- [x] **Step 7: Run focused tests, the full suite, analysis, and macOS build.**

Run: `cd app && flutter test test/engine/video_track_test.dart test/engine/assistant_actions_test.dart --reporter compact && flutter test --reporter compact && flutter analyze && flutter build macos --debug`

Expected: all engine and existing candidate-history tests pass, the full suite is green, analysis is clean, and the debug app builds.

- [x] **Step 8: Commit the pipeline.**

```bash
git add app/lib/src/engine/video_track.dart app/lib/src/engine/assistant_actions.dart app/test/engine/video_track_test.dart app/test/engine/assistant_actions_test.dart
git commit -m "feat(video): run capability-validated Seedance candidates"
```

## Task 5: Project, Settings, And Workbench Controls

**Files:**
- Modify: `app/lib/src/screens/project/project_dialog.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Create: `app/lib/src/screens/production/video_request_dialog.dart`
- Modify: `app/lib/src/screens/production/workbench_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Test: `app/test/widgets/project_page_test.dart`
- Test: `app/test/widgets/settings_screen_test.dart`
- Test: `app/test/widgets/workbench_screen_test.dart`

**Interfaces:**

```dart
Future<VideoRequestDraft?> showVideoRequestDialog(
  BuildContext context, {
  required VideoRequestDraft initial,
  required VideoModelCapabilities capabilities,
  required List<VideoReferenceCandidate> candidates,
});
```

- [ ] **Step 1: Write failing widget tests for capability-derived controls.**

Add a project-dialog test that opens an existing project with a declared multi-reference model and verifies its saved mode is visible without reselecting the model. Add a settings test that edits a video model's modes/reference limits/durations/resolutions/ratios/audio/template paths and verifies the serialized provider model map on save.

Add desktop and 390px workbench tests that:

```dart
await tester.tap(find.byKey(ValueKey('workbench-video-params-$shotId')));
expect(find.byKey(const ValueKey('video-request-mode')), findsOneWidget);
expect(find.text('first_last_frame'), findsOneWidget);
expect(find.text('multi_reference'), findsOneWidget);
expect(find.byKey(const ValueKey('video-request-provider-audio')), findsOneWidget);
```

For a text-only capability, assert that no reference picker is rendered. For `audio='none'`, assert that the provider-audio switch is absent; for `audio='required'`, assert it is checked and disabled. Select a last frame or multi-reference asset, save, rebuild, and assert the persisted draft is used by `buildVideoRequest`. Separately assert the pre-existing storyboard audio selector still invokes `bindStoryboardAudio` and does not mutate `generateAudio`.

- [ ] **Step 2: Run widget tests and verify they fail before UI implementation.**

Run: `cd app && flutter test test/widgets/project_page_test.dart test/widgets/settings_screen_test.dart test/widgets/workbench_screen_test.dart --reporter compact`

Expected: FAIL because existing projects do not hydrate capability modes, models have no capability editor, and the workbench has no parameters dialog.

- [ ] **Step 3: Make project model mode selection truthful.**

In `_ProjectDialogBody.initState`, resolve the existing video model through the same enabled `ModelSelect` data and fill `_videoModes` before first build. `onChanged` keeps the existing behavior of clearing an unsupported mode. The mode dropdown displays canonical names through l10n labels but persists exactly `text`, `first_frame`, `first_last_frame`, or `multi_reference`.

Do not add a per-shot model selector: project model remains the shot default and model changes happen in the project dialog.

- [ ] **Step 4: Add a bounded video-capability editor in Settings.**

For a `_ModelDraft` whose kind is `video`, render an expandable details row with:

```text
Supported modes: four checkboxes
Image / video / audio reference limits: numeric inputs
Durations: comma-separated positive integers
Resolutions and ratios: comma-separated chips/text values
Provider audio: none / optional / required segmented control
Template path per enabled mode: text input
```

On save, normalize whitespace, deduplicate lists while preserving entered order, reject negative limits and empty capability lists, then emit the exact `{"video": ...}` map. Non-video drafts keep their existing untouched capability map. Unknown keys remain copied through `_ModelDraft` so an app upgrade does not destroy provider-specific metadata.

- [ ] **Step 5: Add the per-shot parameters dialog.**

`showVideoRequestDialog` loads the engine-generated draft and candidate list. It presents only values permitted by the selected capability:

- Mode uses a segmented control/dropdown with declared modes only.
- Duration, resolution, and ratio are dropdowns from allowed values; duration uses the existing track value when valid, otherwise the first declared default.
- Provider audio is a switch only for `optional`; it is checked and locked for `required`, absent for `none`.
- `first_frame` shows its required storyboard image as a fixed first-frame source.
- `first_last_frame` shows that fixed first frame plus one required image picker for last frame.
- `multi_reference` shows grouped selectable local candidates for associated asset images, storyboard images, existing video candidates/clip assets, and audio assets; it stops selection at each declared limit.
- `text` shows no reference picker.

Reference candidates are local rows only. Saving calls `Engine.updateVideoRequest`; cancelling changes nothing. The dialog must fit at 390px using a scrolling single column and the existing adaptive full-screen route.

- [ ] **Step 6: Wire a single workbench entry point and preserve composition audio.**

Add an icon-only settings button with tooltip and key `workbench-video-params-<storyboardId>` beside each shot's duration/prompt controls. It calls the dialog and refreshes only the local card state after a save. Add a visible label for the existing `_ShotAudioPicker` that makes it composition audio, while the provider-audio switch stays inside video parameters. The Generate button still calls `batchGenerateVideos` with no UI-side parameter assembly.

- [ ] **Step 7: Add l10n and run all UI checks.**

Add all new labels/errors to all three ARB files, regenerate localization artifacts using the repository's normal Flutter generation step if required, then run:

`cd app && flutter test test/l10n_test.dart test/ui_i18n_static_test.dart test/widgets/project_page_test.dart test/widgets/settings_screen_test.dart test/widgets/workbench_screen_test.dart --reporter compact && flutter analyze`

Expected: all UI/l10n tests pass and no UI-facing Dart file contains a new hardcoded Chinese string.

- [ ] **Step 8: Commit C3 controls.**

```bash
git add app/lib/src/screens/project/project_dialog.dart app/lib/src/screens/settings_screen.dart app/lib/src/screens/production/video_request_dialog.dart app/lib/src/screens/production/workbench_screen.dart app/lib/l10n app/test/widgets/project_page_test.dart app/test/widgets/settings_screen_test.dart app/test/widgets/workbench_screen_test.dart
git commit -m "feat(workbench): configure capability-driven video requests"
```

## C3 Completion Review

- [ ] Run `rg -n "generateVideo\(|firstFrameAbsPath|ratio: '1:1'|generate_audio: true" app/lib app/test` and confirm the old all-in-one/forced parameter implementation is gone outside intentional migration tests.
- [ ] Inspect one queued `video_generation` task and one `o_video` candidate: task metadata contains candidate IDs/model/fingerprints only; candidate has a persisted upstream ID/state after submission; no API key exists in either record.
- [ ] Run `cd app && flutter test --reporter compact && flutter analyze && flutter build macos --debug` on the final C3 commit.
- [ ] Independently review the complete C3 range before starting C4. Critical/Important findings must be resolved; minor findings go into `.superpowers/sdd/progress.md` with a concrete disposition.
- [ ] Verify the UI manually on macOS with a configured model in text, first-frame, and a model-declared multi-reference mode. Do not create a paid real task until the user explicitly approves the provider spend; unit/widget/provider-fake verification is the C3 code gate.
