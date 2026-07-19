# Other Settings: Network Timeout and Canvas Interaction Design

## Scope

Close the remaining two verified gaps in ToonFlow's `otherConfig` settings:

1. request timeout; and
2. production-canvas interaction reduction while dragging or panning.

This is a parity change for the current Flutter architecture, not a new
provider system or a canvas rewrite. It follows the project's permanent
credential policy: provider secrets stay only in local SQLite `o_secret`; no
Keychain or `flutter_secure_storage` work is in scope.

## Source Evidence

`Toonflow-web/src/components/setting/components/otherConfig.vue:11-19` exposes
`axiosTimeOut` in seconds with a minimum of 10. Its computed setter persists
milliseconds. `src/stores/setting.ts:13-19,35` defaults it to 600 seconds and
persists it as part of `otherSetting`. `src/utils/axios.ts:9-18` applies that
value to every browser-to-local-backend Axios request.

`otherConfig.vue:26-30` exposes the persisted `interacting` boolean, default
`true` in `setting.ts:13-19`. The main production canvas turns on an
interaction flag at node-drag or viewport-move start and clears it 150ms after
move end (`src/views/production/index.vue:173-191`). While that flag and the
setting are both true, CSS applies containment to nodes and the transform pane,
makes image surfaces non-interactive, and hides hover-only image and
insert-between tools (`index.vue:569-590`).

DramaFlow has no browser-to-local-backend Axios layer: the UI calls its
embedded Dart engine directly. It does have direct provider requests. Generic
text, structured-output, vision, TTS, and model-list calls currently carry
hard-coded Dio receive timeouts, while image and Seedance paths deliberately
carry protocol-specific limits. The Flutter production canvas already culls to
the visible scene and isolates grid, edges, and nodes behind
`RepaintBoundary`, but it has no user-controlled active-interaction mode.

## Decisions

### Persisted request timeout

Add `requestTimeoutSeconds` to `EngineConfig` with default `600`. Values below
10 are normalized to 10 before a network request uses them. The Other Settings
panel shows a numeric seconds field and validates the same lower bound on both
desktop and 390dp mobile layouts.

The embedded-engine equivalent of ToonFlow's Axios timeout is a single
`HttpProviderGateway.requestTimeout` duration. It is passed explicitly to
generic synchronous provider operations:

- OpenAI-compatible and Anthropic text generation;
- structured tool JSON and Agent turns;
- vision analysis;
- TTS; and
- remote `/models` discovery and connection testing.

It must **not** replace a more-specific protocol timeout:

- GPT Image / ima2 retain their model-specific long image timeout;
- Seedance submission, polling, cancellation, and download retain their
  intentionally short request/poll/download limits; and
- local media file work remains unaffected.

This is the narrowest meaningful adaptation: the setting changes the actual
network operations that replaced Electron's frontend requests, without making
slow asynchronous media protocols accidentally unusable.

### Persisted interaction reduction

Add `production.interacting` to `EngineConfig`, default `1`. The settings UI
names it "制作画布拖动性能优化" and uses a binary control. It remains visible
and editable on mobile because it is a persistent project-independent
preference; its explanatory text states that the effect is applied to the
desktop production canvas, because mobile intentionally uses tabbed panels
instead of an infinite canvas.

`DFCanvas` receives a plain `bool interactionReductionEnabled`, defaulting to
false. A source-wide call-site audit found that `image_flow_editor.dart` also
uses this shared canvas; a disabled default is therefore necessary to keep the
optimization exclusive to the desktop production canvas. It owns short-lived
interaction state:

- enter on a real node drag, Space-pan, background pan/pinch, or pointer-wheel
  viewport change;
- remain active for 150ms after the final interaction event; and
- cancel the pending recovery timer on the next start or on disposal.

During that state, only node *content* is wrapped in `IgnorePointer` and
`TickerMode(enabled: false)`. The outer drag handle and background gesture
layers remain live. This has the same user-facing safety intent as ToonFlow's
temporary image pointer-event removal and hover-tool suppression, while
preserving Flutter's existing viewport culling and repaint isolation rather
than duplicating Web CSS concepts that Flutter does not have. When the setting
is off, the wrapper is absent and no active-state timer alters node interaction.

Only `ProductionScreen` passes the persisted setting to its desktop main
`DFCanvas`. `image_flow_editor.dart` inherits the disabled default, matching
the original where `canvasWheelEvent` and `interacting` are consumed only by production's
main VueFlow.

## Tests and Verification

- The opt-in `app/test/qa/full_pipeline_test.dart` real-AZT harness is removed
  from the automated test tree. Its `QA_FULL=1` switch can otherwise make a
  test spend text and image quota. Real-provider acceptance belongs to the
  user's manual packaged-App workflow, never an environment-variable branch
  inside `flutter test`.
- Engine configuration tests prove defaults, persistence, rejected/normalized
  sub-10 input, and ordinary config exports contain the two non-secret values.
- Fake-Dio adapter tests inspect the `receiveTimeout` used for generic OpenAI
  and Anthropic requests and `/models`; separate regressions prove ima2/GPT
  Image and Seedance retain their existing dedicated values. No test reaches a
  live provider or generates video.
- `DFCanvas` widget tests prove the 150ms activation/recovery boundary, node
  content is non-hit-testable only while the switch is enabled, the drag handle
  remains usable, and existing mouse/trackpad/touch/Space gestures stay green.
- Settings tests exercise values and the performance toggle on desktop and at
  390dp; localization tests cover zh/en/ja.
- Update the settings matrix, master checklist, canvas evidence, and execution
  report. These two settings become verified only after source links and exact
  command evidence are recorded; unrelated canvas performance profiling stays
  explicitly open.
