# Other Settings Network and Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce ToonFlow's persisted request-timeout setting and its temporary production-canvas interaction reduction without changing image/video protocol limits.

**Architecture:** `EngineConfig` owns both persisted values. `HttpProviderGateway` reads one normalized duration and passes it explicitly to generic provider adapters, avoiding a hidden global Dio mutation. `DFCanvas` owns its transient 150ms interaction state and receives only a boolean feature flag from the desktop production screen; it retains all existing culling, repaint boundaries, gestures, and image-flow isolation.

**Tech Stack:** Flutter/Dart, sqlite3, Dio, Riverpod 3, Material controls, Flutter widget and engine tests, Flutter gen-l10n.

## Global Constraints

- `requestTimeoutSeconds` defaults to `600`, persists in `o_setting`, and never resolves below `10` seconds.
- Generic text/tool/agent/vision/TTS/model-list and connection-test requests use that duration. ima2/GPT Image and all Seedance paths retain their existing dedicated timeouts.
- `production.interacting` defaults to `'1'`; it is a non-secret regular setting included in normal configuration export.
- Interaction reduction applies only to the desktop main production `DFCanvas`; mobile settings remain editable and explain the desktop-only canvas effect. `image_flow_editor.dart` remains untouched.
- While active, only node content loses pointer/ticker activity; drag handles and background gestures must continue working. Recovery is exactly 150ms after the final interaction.
- All UI strings must exist in zh/en/ja and fit at 390dp. Tests use fake Dio/local fixtures only. Do not invoke text, image, TTS, or video providers.
- Do not stage `.superpowers/sdd/progress.md` or `docs/superpowers/acceptance/`.

---

## File Structure

- Modify `app/lib/src/engine/config.dart`: persisted defaults and a single normalized timeout getter.
- Modify `app/lib/src/engine/providers/gateway.dart`: compute the gateway timeout once and pass it into generic adapter calls.
- Modify `app/lib/src/engine/providers/openai_text.dart`, `anthropic_text.dart`, `openai_vision.dart`, and `openai_tts.dart`: require an explicit generic request timeout in their request options.
- Modify `app/lib/src/widgets/df_canvas.dart`: interaction-state timer and reduced node-content wrapper.
- Modify `app/lib/src/screens/production/production_screen.dart`: pass the persisted flag to only the desktop main canvas.
- Modify `app/lib/src/screens/settings_screen.dart` plus `app/lib/l10n/app_{zh,en,ja}.arb` and generated localization files: numeric timeout field, canvas performance toggle, and responsive labels.
- Modify `app/test/engine/config_test.dart`, `app/test/engine/providers_test.dart`, `app/test/widgets/df_widgets_test.dart`, and `app/test/widgets/settings_screen_test.dart`.
- Modify `docs/parity/settings-module-matrix.md`, `docs/parity/master-checklist.md`, `docs/parity/w1-canvas-reference.md`, and `docs/parity/feature-parity-execution-report.md` after verified execution.

## Task 1: Persisted Timeout and Explicit Generic Request Policy

**Files:**
- Modify: `app/lib/src/engine/config.dart`
- Modify: `app/lib/src/engine/providers/gateway.dart`
- Modify: `app/lib/src/engine/providers/openai_text.dart`
- Modify: `app/lib/src/engine/providers/anthropic_text.dart`
- Modify: `app/lib/src/engine/providers/openai_vision.dart`
- Modify: `app/lib/src/engine/providers/openai_tts.dart`
- Test: `app/test/engine/config_test.dart`
- Test: `app/test/engine/providers_test.dart`

**Interfaces:**
- Add `String` config defaults `requestTimeoutSeconds: '600'` and `production.interacting: '1'`.
- Add `Duration EngineConfig.requestTimeout`, returning `Duration(seconds: max(10, parsedValueOr600))`.
- Add required named `Duration requestTimeout` to generic OpenAI/Anthropic text, tool JSON, Agent turn, vision, and TTS helper calls.
- `HttpProviderGateway` passes `config.requestTimeout` to those helpers and uses it for `listRemoteModelIds`; image/video helpers receive no new timeout argument.

- [ ] **Step 1: Write focused failing engine tests**

Extend `config_test.dart` with defaults, persistence, and normalization:

```dart
test('其他设置持久化请求超时和制作画布性能开关', () {
  final db = openEngineDb(':memory:');
  final config = EngineConfig(db, isMobile: false);
  expect(config.requestTimeout, const Duration(seconds: 600));
  expect(config.str('production.interacting'), '1');

  config.update({
    'requestTimeoutSeconds': '42',
    'production.interacting': '0',
  });
  final again = EngineConfig(db, isMobile: false);
  expect(again.requestTimeout, const Duration(seconds: 42));
  expect(again.str('production.interacting'), '0');

  again.update({'requestTimeoutSeconds': '3'});
  expect(again.requestTimeout, const Duration(seconds: 10));
});
```

In `providers_test.dart`, set `config.update({'requestTimeoutSeconds': '42'})`,
then assert a generic text request's captured `RequestOptions.receiveTimeout`
is `const Duration(seconds: 42)`. Add a model-list request assertion with the
same value. Preserve and extend existing image/video tests to assert their
current values are still `960s` for OpenAI image, configured `imageTimeoutMs`
for ima2, and `60s` for Seedance submission.

- [ ] **Step 2: Verify RED**

Run:

```sh
cd app
flutter test test/engine/config_test.dart test/engine/providers_test.dart \
  --plain-name '其他设置持久化请求超时和制作画布性能开关'
```

Expected: compilation failure because `EngineConfig.requestTimeout` and the new
defaults do not exist.

- [ ] **Step 3: Implement one normalized config boundary**

In `EngineConfig`, add only these defaults and getter:

```dart
'requestTimeoutSeconds': '600',
'production.interacting': '1',

Duration get requestTimeout {
  final seconds = int.tryParse(str('requestTimeoutSeconds')) ?? 600;
  return Duration(seconds: seconds < 10 ? 10 : seconds);
}
```

Do not add a database table or special export path. `getAll()` already
serializes default keys and `update()` already admits only declared defaults.

Thread `required Duration requestTimeout` through the named helper calls. Each
helper uses it solely as `Options.receiveTimeout`; preserve its existing
`sendTimeout`, headers, content type, response type, and status validator.
For Anthropic, make `_post` receive the duration and have its callers forward
the one argument. In `HttpProviderGateway`, read `config.requestTimeout`
once at each public generic operation and forward it. Change only `/models`
from the hard-coded 20 seconds to the same configured duration. Do not touch
`openai_image.dart`, `ima2_image.dart`, or `volcengine_video.dart`.

- [ ] **Step 4: Verify generic policy and media exceptions**

Run:

```sh
cd app
flutter analyze
flutter test --concurrency=1 test/engine/config_test.dart test/engine/providers_test.dart
```

Expected: no analyzer diagnostics; generic OpenAI/Anthropic/text/TTS/model
requests capture the configured duration; image and video assertions retain
their former dedicated limits.

- [ ] **Step 5: Commit Task 1**

```sh
git add app/lib/src/engine/config.dart \
  app/lib/src/engine/providers/gateway.dart \
  app/lib/src/engine/providers/openai_text.dart \
  app/lib/src/engine/providers/anthropic_text.dart \
  app/lib/src/engine/providers/openai_vision.dart \
  app/lib/src/engine/providers/openai_tts.dart \
  app/test/engine/config_test.dart app/test/engine/providers_test.dart
git commit -m "feat(settings): persist generic request timeout"
```

## Task 2: Canvas Interaction Reduction and Settings UI

**Files:**
- Modify: `app/lib/src/widgets/df_canvas.dart`
- Modify: `app/lib/src/screens/production/production_screen.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`
- Test: `app/test/widgets/df_widgets_test.dart`
- Test: `app/test/widgets/settings_screen_test.dart`

**Interfaces:**
- Extend `DFCanvas` with `final bool interactionReductionEnabled`, default
  `true`.
- Expose no global interaction provider. The persistent boolean is read by
  `ProductionScreen` and passed into `_CanvasLayout` then its main `DFCanvas`.
- `DFCanvas` owns `bool _isInteracting` and a cancelable 150ms `Timer`.

- [ ] **Step 1: Write failing canvas and settings tests**

Add a lightweight tappable node child and a drag callback to
`df_widgets_test.dart`. With `interactionReductionEnabled: true`, begin an
actual drag on `df-canvas-drag-<id>`, pump, and assert the child is absent from
hit testing while the drag handle still moves the node. Release, pump 149ms,
assert the child remains unavailable; pump 1ms, assert it is tappable again.
Create a separate false-flag test proving a node child is never wrapped/blocked
during a drag.

In `settings_screen_test.dart`, choose Other Settings, set the timeout to
`42`, tap the performance switch off, save, rebuild the settings page with the
same engine, and assert:

```dart
expect(engine.config.requestTimeout, const Duration(seconds: 42));
expect(engine.config.str('production.interacting'), '0');
```

Repeat only the visible-control/hit-test assertions after a `Size(390, 760)`
viewport. Include a `9`-second entry assertion that save keeps the current
config and displays the existing human-readable validation error.

- [ ] **Step 2: Verify RED**

Run:

```sh
cd app
flutter test test/widgets/df_widgets_test.dart \
  --plain-name 'DFCanvas interaction reduction blocks content for 150ms'
```

Expected: compilation failure because `interactionReductionEnabled` and its
temporary interaction behavior do not exist.

- [ ] **Step 3: Implement the canvas-only transient state**

Add `interactionReductionEnabled = true` to `DFCanvas`. In its state class,
own one `Timer? _interactionRecovery` and a `_setInteracting(bool active)`
method: when disabled, cancel and leave `_isInteracting` false; when starting,
cancel recovery and set true only on a state change; when stopping, schedule
exactly `const Duration(milliseconds: 150)` to clear it; cancel in `dispose`.

Call start from real node-drag activation, Space-pan start, viewport gesture
start, two-finger start, and successful pointer-scroll transform. Call delayed
stop from their matching end paths. A node's `child` becomes:

```dart
final content = _isInteracting && widget.interactionReductionEnabled
    ? TickerMode(
        enabled: false,
        child: IgnorePointer(child: node.child),
      )
    : node.child;
```

Place `content` inside the existing `_DFCanvasNodeDragScope`; keep the drag
handle sibling outside it. Do not remove `RepaintBoundary`, visible-scene
culling, or any existing gesture recognizer.

In `ProductionScreen`, derive the flag as
`engine.config.str('production.interacting') != '0'`, pass it through
`_CanvasLayout`, and refresh only its local widget state after setting changes
via the normal route rebuild. Do not pass it to image flow or mobile tabs.

Add a timeout controller in `SettingsScreen`, dispose it, initialize it from
`config.requestTimeout.inSeconds`, put a numeric field before episode length,
and include its parsed value in `_saveOtherSettings`. Add a `SwitchListTile`
with a desktop-canvas helper text and update `production.interacting`
immediately. The timeout field saves through the existing Save button; reject
an invalid or `<10` value with `settingsOtherInvalidNumber` rather than
silently changing what the user typed.

Add zh/en/ja labels for request timeout, seconds, canvas performance title,
and mobile/desktop explanatory copy, then run `flutter gen-l10n`.

- [ ] **Step 4: Run responsive UI and gesture regressions**

Run:

```sh
cd app
flutter gen-l10n
flutter analyze
flutter test --concurrency=1 test/widgets/df_widgets_test.dart \
  test/widgets/settings_screen_test.dart test/widgets/production_screen_test.dart \
  test/l10n_test.dart
```

Expected: no analyzer diagnostics; existing zoom/scroll, mouse, trackpad,
touch, Space, right-button, parameter-stop, and mobile settings tests all pass.

- [ ] **Step 5: Commit Task 2**

```sh
git add app/lib/src/widgets/df_canvas.dart \
  app/lib/src/screens/production/production_screen.dart \
  app/lib/src/screens/settings_screen.dart \
  app/lib/l10n/app_zh.arb app/lib/l10n/app_en.arb app/lib/l10n/app_ja.arb \
  app/lib/l10n/app_localizations*.dart \
  app/test/widgets/df_widgets_test.dart app/test/widgets/settings_screen_test.dart
git commit -m "feat(canvas): add interaction reduction setting"
```

## Task 3: Evidence, Whole-Suite Verification, and Documentation Commit

**Files:**
- Modify: `docs/parity/settings-module-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/w1-canvas-reference.md`
- Modify: `docs/parity/feature-parity-execution-report.md`

**Interfaces:**
- Consumes the verified Task 1/2 test output and exact original source evidence.
- Produces a corrected `W6D-OTHER-001` record: timeout and interaction setting
  are verified; only unrelated settings/canvas gaps remain open.

- [ ] **Step 1: Update only evidenced parity claims**

In `settings-module-matrix.md` and `master-checklist.md`, replace the
statement that timeout/interacting are missing with the implemented behavior,
source lines, configured generic-call boundary, image/video exception, 150ms
desktop canvas state, and focused test files. Do not mark the whole settings
module or main production page complete: theme color/global font size, formal
profile metrics, selection, and the other listed gaps remain separately tracked.

In `w1-canvas-reference.md`, distinguish this user-controlled hit-test/ticker
reduction from a measured frame-rate guarantee. In the execution report, record
that verification used fake Dio and no live text/image/TTS/video provider.

- [ ] **Step 2: Run authoritative project gates**

Run:

```sh
cd app
flutter analyze
flutter test --concurrency=1
flutter build macos --debug
cd ..
node tool/parity/check_no_orphans.js
git diff --check
```

Expected: analyzer has no issues, every test passes, macOS debug build succeeds,
the parity checker reports all inventory items covered, and whitespace check is
empty.

- [ ] **Step 3: Commit documentation evidence**

```sh
git add docs/parity/settings-module-matrix.md \
  docs/parity/master-checklist.md docs/parity/w1-canvas-reference.md \
  docs/parity/feature-parity-execution-report.md \
  docs/superpowers/plans/2026-07-20-other-settings-network-and-interaction.md
git commit -m "docs(parity): verify other settings network and canvas behavior"
```

## Plan Self-Review

- **Spec coverage:** Task 1 covers persisted timeout, generic provider mapping,
  and image/video exclusions. Task 2 covers persisted interaction preference,
  exact 150ms canvas state, desktop/mobile UI, and untouched image flow. Task 3
  records evidence without overstating performance or video verification.
- **Placeholder scan:** no unfinished placeholder instructions are present.
- **Type consistency:** `EngineConfig.requestTimeout`,
  `requestTimeoutSeconds`, `production.interacting`, and
  `DFCanvas.interactionReductionEnabled` are the exact names used throughout.
