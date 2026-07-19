# Canvas Wheel Mode Design

## Scope

Close one verified ToonFlow parity gap: the production canvas setting that
chooses whether pointer scrolling zooms or pans the canvas. This is deliberately
limited to that one interaction setting. It does not add selection, inertia,
performance profiling, video calls, or a new persistent configuration format.

## Source Evidence

`Toonflow-web/src/components/setting/components/otherConfig.vue:20-25` renders
two choices bound to `canvasWheelEvent`: `zoom` and `scroll`.
`Toonflow-web/src/views/production/index.vue:29-30` maps the same value to
VueFlow `zoom-on-scroll` and `pan-on-scroll`.
`Toonflow-web/src/stores/setting.ts:6,35` defaults to `zoom`, but excludes
`canvasWheelEvent` from the persisted-store pick list. Therefore changing it is
effective for the running application only and resets to `zoom` after restart.

## Decision

Add a small application-scoped Riverpod state provider with a two-value enum:
`zoom` and `scroll`. Its default is `zoom`; it never touches `EngineConfig`,
SQLite, imports, exports, or credentials. The settings page and every `DFCanvas`
observe the same provider, so a change applies immediately without reopening the
production page.

The Other Settings panel receives a standard `SegmentedButton` control using
the existing adaptive layout. It appears on desktop and mobile and needs no
separate save action because this source setting is session-only.

## Canvas Behavior

`DFCanvas` accepts the current wheel mode explicitly.

| Mode | Mouse wheel | Trackpad scroll | Touch pinch | Space + primary mouse |
| --- | --- | --- | --- | --- |
| `zoom` | Focal-point zoom | Focal-point zoom | Scale | Pan |
| `scroll` | Pan by scroll delta | Pan by scroll delta | Scale | Pan |

Right-button drags remain ignored. Normal node content forwards the signal to
the viewport; the generated-image parameter region continues to stop it,
matching ToonFlow's explicit `@wheel.stop`.

## Tests And Evidence

- Provider tests: default `zoom`, in-memory switching, and no engine-config
  write.
- `DFCanvas` widget tests: mouse and trackpad each zoom in `zoom` mode and pan
  in `scroll` mode; transformed-card focal-position and parameter-stop tests
  remain green.
- Settings widget test: the Other Settings segmented control changes the
  provider immediately on desktop and at 390dp.
- Update `settings-module-matrix.md`, `master-checklist.md`,
  `w1-canvas-reference.md`, and the execution report with source links and
  concrete test evidence.

No test invokes image, text, TTS, or video providers.
