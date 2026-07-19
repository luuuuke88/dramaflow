# Canvas Wheel Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match ToonFlow's session-only `zoom` / `scroll` setting for pointer scrolling on the main production canvas.

**Architecture:** Define the two-value UI state in `state/`, expose it with one in-memory Riverpod notifier, and pass the selected value from `ProductionScreen` into `DFCanvas`. The canvas remains independently usable and defaults to `zoom`; image-flow editing keeps its original independent default because ToonFlow's edit-image VueFlow does not consume `canvasWheelEvent`.

**Tech Stack:** Flutter, Riverpod 3, Material `SegmentedButton`, Flutter widget tests, Flutter gen-l10n.

## Global Constraints

- Default is `zoom`; switching is session-only and must not write `EngineConfig`, SQLite, config exports, or credentials.
- Only `ProductionScreen` passes the selected mode to `DFCanvas`; `image_flow_editor.dart` remains unmodified for this setting.
- `zoom`: mouse wheel and trackpad scroll both zoom around the pointer focal point. `scroll`: both pan by the pointer delta. Touch pinch and Space + primary-mouse pan are unchanged.
- Right mouse drag remains ignored; generated-image parameter regions retain their explicit wheel stop.
- UI must work at desktop width and 390dp; all user-facing strings exist in zh/en/ja.
- Do not invoke text, image, TTS, or video providers in tests.
- Do not stage `.superpowers/sdd/progress.md` or `docs/superpowers/acceptance/`.

---

## File Structure

- Create `app/lib/src/state/canvas_wheel_mode.dart`: shared enum with no widget or engine dependency.
- Modify `app/lib/src/state/providers.dart`: session-only `CanvasWheelModeNotifier` and provider.
- Modify `app/lib/src/widgets/df_canvas.dart`: explicit `wheelMode` input and mode-specific pointer-signal behavior.
- Modify `app/lib/src/screens/production/production_screen.dart`: watch the provider and pass it to the main `DFCanvas` only.
- Modify `app/lib/src/screens/settings_screen.dart`: Other Settings segmented control with immediate provider update.
- Modify `app/lib/l10n/app_{zh,en,ja}.arb` and generated localizations: three settings labels.
- Modify `app/test/widgets/df_widgets_test.dart`, `app/test/widgets/settings_screen_test.dart`, and parity evidence documents.

## Task 1: Session State And Canvas Semantics

**Files:**
- Create: `app/lib/src/state/canvas_wheel_mode.dart`
- Modify: `app/lib/src/state/providers.dart`
- Modify: `app/lib/src/widgets/df_canvas.dart`
- Test: `app/test/widgets/df_widgets_test.dart`

**Interfaces:**
- Produces `enum CanvasWheelMode { zoom, scroll }`.
- Produces `canvasWheelModeProvider`, whose notifier exposes `void setMode(CanvasWheelMode mode)` and whose `build()` returns `CanvasWheelMode.zoom`.
- Extends `DFCanvas` with `final CanvasWheelMode wheelMode`, defaulting to `CanvasWheelMode.zoom`.

- [ ] **Step 1: Write the failing provider and canvas tests**

Add the state import and assertions that the provider starts as `CanvasWheelMode.zoom` and changes only through `setMode` in memory. The state module must not import or depend on `Engine`/`EngineConfig`; the settings-page test in Task 2 owns the separate assertion that toggling the visible control leaves `engine.config.getAll()` unchanged. Add two `DFCanvas` tests using a `TransformationController` and a `TestPointer`:

```dart
test('canvas wheel mode is session-only and starts at zoom', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  expect(container.read(canvasWheelModeProvider), CanvasWheelMode.zoom);
  container.read(canvasWheelModeProvider.notifier)
      .setMode(CanvasWheelMode.scroll);
  expect(container.read(canvasWheelModeProvider), CanvasWheelMode.scroll);
});

testWidgets('DFCanvas scroll mode pans mouse and trackpad signals',
    (tester) async {
  final controller = TransformationController();
  await tester.pumpWidget(themed(SizedBox(
    width: 900, height: 600,
    child: DFCanvas(
      controller: controller,
      fitOnInit: false,
      wheelMode: CanvasWheelMode.scroll,
      nodes: const [],
    ),
  )));
  final pointer = TestPointer(1, PointerDeviceKind.mouse)
    ..hover(const Offset(450, 300));
  await tester.sendEventToBinding(pointer.scroll(const Offset(20, 100)));
  await tester.pump();
  expect(controller.value.storage[0], 1);
  expect(controller.value.storage[12], closeTo(-20, 0.1));
  expect(controller.value.storage[13], closeTo(-100, 0.1));
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
cd app
flutter test test/widgets/df_widgets_test.dart \
  --plain-name 'DFCanvas scroll mode pans mouse and trackpad signals'
```

Expected: compilation fails because `CanvasWheelMode` / `wheelMode` do not exist, or the assertion fails because current mouse scrolling zooms.

- [ ] **Step 3: Add the state boundary and minimal canvas implementation**

Create the value-only enum:

```dart
// app/lib/src/state/canvas_wheel_mode.dart
enum CanvasWheelMode { zoom, scroll }
```

Add the in-memory notifier in `providers.dart`:

```dart
class CanvasWheelModeNotifier extends Notifier<CanvasWheelMode> {
  @override
  CanvasWheelMode build() => CanvasWheelMode.zoom;

  void setMode(CanvasWheelMode mode) => state = mode;
}

final canvasWheelModeProvider =
    NotifierProvider<CanvasWheelModeNotifier, CanvasWheelMode>(
  CanvasWheelModeNotifier.new,
);
```

Import the enum in `df_canvas.dart`, add the constructor field, and branch only
inside `_handleBackgroundPointerSignal`:

```dart
if (widget.wheelMode == CanvasWheelMode.scroll) {
  transform.storage[12] -= event.scrollDelta.dx;
  transform.storage[13] -= event.scrollDelta.dy;
  _controller.value = transform;
  return;
}
// zoom mode: apply the existing focal-point scaling for every PointerScrollEvent
```

Keep `_viewportPositionOf(event)` for transformed card content; do not alter
touch, Space, right-button, or parameter-region handling.

- [ ] **Step 4: Run focused semantics and existing gesture regressions**

Run:

```sh
cd app
flutter analyze
flutter test --concurrency=1 test/widgets/df_widgets_test.dart
```

Expected: no analyzer issues and all existing drag, transformed-card focal,
parameter-stop, Space, right-button, and new wheel-mode tests pass.

- [ ] **Step 5: Commit the self-contained state/canvas change**

```sh
git add app/lib/src/state/canvas_wheel_mode.dart \
  app/lib/src/state/providers.dart \
  app/lib/src/widgets/df_canvas.dart \
  app/test/widgets/df_widgets_test.dart
git commit -m "feat(canvas): add session wheel interaction mode"
```

## Task 2: Settings UI, Production Wiring, Localization, And Evidence

**Files:**
- Modify: `app/lib/src/screens/production/production_screen.dart`
- Modify: `app/lib/src/screens/settings_screen.dart`
- Modify: `app/lib/l10n/app_zh.arb`
- Modify: `app/lib/l10n/app_en.arb`
- Modify: `app/lib/l10n/app_ja.arb`
- Regenerate: `app/lib/l10n/app_localizations*.dart`
- Test: `app/test/widgets/settings_screen_test.dart`
- Modify: `docs/parity/settings-module-matrix.md`
- Modify: `docs/parity/master-checklist.md`
- Modify: `docs/parity/w1-canvas-reference.md`
- Modify: `docs/parity/feature-parity-execution-report.md`

**Interfaces:**
- Consumes `CanvasWheelMode`, `canvasWheelModeProvider`, and `DFCanvas.wheelMode` from Task 1.
- `ProductionScreen` is the sole application caller that passes its watched
  mode into the main `_CanvasLayout` / `DFCanvas` path.

- [ ] **Step 1: Write failing desktop and 390dp settings tests**

Use the existing `app()` fixture and `_selectSection(tester, '其他设置')`.
Assert the default zoom segment is selected, tap scroll, then assert the
provider immediately reads `CanvasWheelMode.scroll` while
`engine.config.getAll()` is byte-for-byte unchanged. Repeat after setting the
viewport to `Size(390, 760)` and verify both segments are hit-testable.

```dart
expect(container.read(canvasWheelModeProvider), CanvasWheelMode.zoom);
await tester.tap(find.byKey(const Key('settings-canvas-wheel-scroll')));
await tester.pump();
expect(container.read(canvasWheelModeProvider), CanvasWheelMode.scroll);
expect(engine.config.getAll(), beforeConfig);
```

- [ ] **Step 2: Run the new settings test and verify RED**

Run:

```sh
cd app
flutter test test/widgets/settings_screen_test.dart \
  --plain-name '其他设置：画布滚轮模式仅本次会话生效'
```

Expected: fails because the segmented control and keys are absent.

- [ ] **Step 3: Wire the visible control and main production canvas**

Add three l10n keys in every ARB file, with these baseline values:

```json
"settingsOtherCanvasWheelMode": "画布滚轮行为",
"settingsOtherCanvasWheelZoom": "缩放",
"settingsOtherCanvasWheelScroll": "滚动"
```

Use translated equivalents in English and Japanese, then run `flutter gen-l10n`.
In `_otherPanel`, render a `SegmentedButton<CanvasWheelMode>` before the save
button. Give each segment keys `settings-canvas-wheel-zoom` and
`settings-canvas-wheel-scroll`; its `selected` set comes from
`ref.watch(canvasWheelModeProvider)` and `onSelectionChanged` calls the
provider notifier immediately.

In `ProductionScreen.build`, watch `canvasWheelModeProvider`, pass the value
to `_CanvasLayout`, store it as a required widget field, and pass it to the
main `DFCanvas(wheelMode: widget.wheelMode)`. Do not pass it to
`ImageFlowEditorPage`.

- [ ] **Step 4: Run localization and cross-device UI regressions**

Run:

```sh
cd app
flutter gen-l10n
flutter test --concurrency=1 test/l10n_test.dart test/widgets/settings_screen_test.dart \
  test/widgets/production_screen_test.dart test/widgets/df_widgets_test.dart
```

Expected: generated localization API compiles, desktop and 390dp settings tests
pass, the production canvas accepts the provider value, and no existing canvas
regression changes behavior unexpectedly.

- [ ] **Step 5: Update the evidence record**

Change only the four listed parity documents. Mark the canvas wheel-mode part
of `W6-PRODUCTION-001` and `W6D-OTHER-001` as verified, while preserving the
remaining separate gaps: request timeout, interaction reduction toggle,
selection, Agent episode-switch confirmation, default-open chat, and profile
performance evidence. Record the exact source files, the session-only boundary,
and focused test commands. Do not call the whole pages complete.

- [ ] **Step 6: Run final project gates and commit**

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

Expected: analyzer has zero issues, all tests pass, macOS debug build succeeds,
all inventory items remain covered, and diff check is clean.

Commit only the Task 2 files:

```sh
git add app/lib/src/screens/production/production_screen.dart \
  app/lib/src/screens/settings_screen.dart \
  app/lib/l10n/app_zh.arb app/lib/l10n/app_en.arb app/lib/l10n/app_ja.arb \
  app/lib/l10n/app_localizations.dart \
  app/lib/l10n/app_localizations_zh.dart \
  app/lib/l10n/app_localizations_en.dart \
  app/lib/l10n/app_localizations_ja.dart \
  app/test/widgets/settings_screen_test.dart \
  docs/parity/settings-module-matrix.md docs/parity/master-checklist.md \
  docs/parity/w1-canvas-reference.md docs/parity/feature-parity-execution-report.md
git commit -m "feat(settings): match ToonFlow canvas wheel mode"
```
