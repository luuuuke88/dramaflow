# W1 Canvas Performance & Gesture-Feel Metrics — Reference Draft

Status: evidence record. Read-only source investigation started 2026-07-18; the
Flutter interaction implementation and local regression evidence were refreshed
2026-07-20. All factual claims cite `file:line`; profile/real-device conclusions
remain explicitly open.

## 0. Scope note: there are two canvases

DramaFlow has **two** distinct canvas surfaces, both built on the same `DFCanvas` widget but with different interaction profiles. W1's motivating complaint ("无限画布的感觉体验也不好") is about the **main production canvas**. Both surfaces now support node dragging, so the metrics must cover both:

| Canvas | File | Node count | Draggable nodes? | Heaviest content |
|---|---|---|---|---|
| Main production canvas | `production_screen.dart:138-234` (`_CanvasLayout`) | Six container nodes | **Yes** — title-handle dragging, with positions held for the current session and reset by automatic layout (`:152-160`, `:179-224`) | The `storyboard` node, whose grid holds up to ~99 image cells |
| editImage node editor | `image_flow_editor.dart:984-1016` | Variable (user-built upload/generated nodes) | **Yes** — shared `DFCanvasDragRegion`; generated-node parameters block viewport pan without moving the node | Per-node 320px image cards |

This matters: the spec's "数百节点下拖拽" (hundreds of nodes under drag) maps onto the editImage editor's node count *plus* the storyboard node's internal image-cell count — not onto the main canvas's 6 top-level nodes.

---

## 1. What made ToonFlow's canvas feel bad (source-evidenced)

ToonFlow's canvas is `@vue-flow/core` (VueFlow) in `Toonflow-web/src/views/production/index.vue`. The source itself carries strong evidence that its authors were fighting performance and had to trade away interaction quality to cope.

1. **Virtualization was explicitly turned OFF.** `index.vue:12` sets `:only-render-visible-elements="false"`. VueFlow ships off-screen culling; ToonFlow disabled it, so **every node stays mounted regardless of viewport**. Combined with the storyboard node (below), that means every shot image and its overlay tooling is live in the DOM at all times.

2. **The storyboard node renders every cell with no windowing, each cell heavy.** `storyboard.vue:11-82` maps the full `storyboard` array into a flex-wrap grid where each cell is a full TDesign `t-image` (`:38-49`) plus overlay tools, a checkbox, a colored tag, a delete button, and an edit button, each with its own tooltip and hover handlers. There is no virtualization inside the node. At an episode's worth of shots this is dozens-to-~100 image components always mounted, multiplied by "no culling" above.

3. **They shipped an "interaction mode" that strips affordances to survive pan/drag.** `index.vue:173-191` toggles an `isInteracting` flag on `onNodeDragStart`/`onMoveStart` and clears it 150 ms after `onMoveEnd`. The matching CSS (`index.vue:569-590`) forces `will-change: transform; contain: layout style paint` on nodes, sets images to `pointer-events: none; contain: strict`, and **hides hover tools entirely** (`.imageToolsWrap`, `.addBetween` → `display: none !important`) *while the user is interacting*. Needing to blank out interactive UI just to keep panning smooth is direct evidence the default render could not sustain interaction — and it degrades the feel (tools flicker away the moment you touch the canvas).

4. **A permanent on-screen FPS meter.** `index.vue:98` renders a live `{{ fps }}` tag, fed by a `requestAnimationFrame` sampling loop at `index.vue:491-512`. A product shipping its own always-visible frame-rate readout is strong evidence frame rate was a known, watched problem.

5. **Space-drag panning writes the viewport on every mousemove with no rAF throttle.** `index.vue:156-158` — `onSpaceMouseMove` calls `setViewport({...})` synchronously per `mousemove` event. There is no `requestAnimationFrame` coalescing in this custom pan path, so pointer-rate events drive viewport recomputation directly.

6. **A deep watcher over the whole graph model.** `index.vue:222-230` watches `flowData` with `{ deep: true }` and, on any change, iterates every node to sync positions. Deep-watching the entire episode's data (script, plan, table, all storyboard rows, assets) is O(model size) per mutation. Not per-frame, but a heavy reactivity cost on every edit.

7. **Per-cell hover reactivity.** Each storyboard cell has `@mouseenter`/`@mouseleave` (`storyboard.vue:13`) writing a shared reactive `hoveredIndex` (`storyboard.vue:149,152-154`); every cell's `:class="{ expanded: hoveredIndex === index }"` binding re-evaluates when it changes. Moving the mouse across the grid churns reactivity across all cells.

Net: the "bad feel" was not one bug but a stack — no culling, unbounded heavy cells, and a coping mechanism (interaction-mode) that sacrifices affordances precisely when the user is manipulating the canvas.

---

## 2. DramaFlow's current canvas architecture (factual)

Rendering, gestures, and existing optimizations, all in `app/lib/src/widgets/df_canvas.dart` unless noted.

- **Viewport input is custom, not `InteractiveViewer`.** `df_canvas.dart:493-515` keeps the transformation matrix itself; pointer scrolling uses the selected mode: `zoom` focal-scales mouse and trackpad events, `scroll` pans both by their deltas. Scale is clamped to `0.1–10`. The sibling background `RawGestureDetector` handles primary-button drag/pinch, while the root custom recognizers preserve Space + primary mouse and two-touch ownership without participating in normal text fields, taps, or single-touch drags. There is no fling/inertia implementation; whether that is a visible ToonFlow delta still needs profile/black-box evidence.
- **Scene = a fixed 12000×8000 logical surface**, not mathematically infinite. `OverflowBox` preserves that full size for both paint and hit testing, then `Transform` renders it under the current matrix (`df_canvas.dart:669-764`). Nodes are `Positioned` children of a single `Stack`; this fixed a mobile regression where a card could be visible after `fitView()` but not tappable.
- **Main-canvas nodes can be dragged.** `production_screen.dart:262-345` maintains a session-scoped position map and wires all six `DFCanvasNode`s through `onDragUpdate`. `DFCanvas` converts pointer movement from screen to scene coordinates (`df_canvas.dart:334-380`). Automatic layout restores the default six-node chain. Positions are not persisted and are shared while the page remains mounted, matching ToonFlow's in-memory `nodePositions` intent.
- **Edges = `CustomPainter` cubic béziers.** `_EdgePainter`, `df_canvas.dart:792-822`, `Path.cubicTo`.
- **Grid = `CustomPainter`.** `_GridPainter`, `df_canvas.dart:767-789`, a nested loop over the full 12000×8000 at 40px step (≈300×200 ≈ 60,000 `drawCircle` calls); `shouldRepaint` returns true only on color change.

**Existing optimizations already present** (this is genuinely ahead of ToonFlow on the culling axis):

- **Viewport culling of nodes AND edges.** `df_canvas.dart:557-640`: `_visibleSceneRect` projects the viewport into scene space (inflated 600px), and only nodes/edges intersecting it are built. This is the opposite of ToonFlow's `only-render-visible-elements="false"`.
- **`RepaintBoundary` around grid, the edge layer, and every node** (`df_canvas.dart:682-753`).
- **Fit-on-init** (`_fitView`, `df_canvas.dart:530-555`), clamping scale to 0.1–1.0.

**The one structural cost to flag:** `df_canvas.dart:330-332` — `_handleTransformChanged` calls `setState(() {})` on **every** transformation tick. So during a continuous pan or pinch, the whole `LayoutBuilder` body re-runs each frame: it rebuilds `nodesById`, recomputes `visibleNodes`/`visibleEdges`, and re-diffs the `Stack` children every frame. Culling bounds *how many* widgets get built; `RepaintBoundary` bounds repaint; but the per-frame **rebuild + element diff of the node list is unavoidably O(nodes) every pan frame**. This is the single most likely DramaFlow-side source of pan/zoom jank and the thing W1 still needs to measure.

**Node dragging (both canvases).** The main production canvas has the title-handle path above. In the editImage editor, `image_flow_editor.dart` supplies `n.position += delta` through `DFCanvasNode.onDragUpdate`; `DFCanvasDragRegion` claims the drag from the visual card surface, while the expanded parameter region sets `movesNode:false` to block viewport pan without changing the node. Each pointer-move still rebuilds the editor's `DFCanvas` node list (`image_flow_editor.dart:984-1016`), not just the dragged node. Main-canvas dragging likewise updates `_CanvasLayout` state per movement. Counts are usually small, but both paths require profile evidence rather than assumptions.

**Storyboard grid inside its node.** `storyboard_canvas_node.dart:569-587`: a `SingleChildScrollView` + `Wrap` over all rows with no windowing (same shape as ToonFlow's grid, minus the always-mounted-across-viewport problem since the whole node is culled when off-screen). Cell zoom is a session-only `_cellSize` clamped 90–260 via +/- buttons (`:51, :482-491`), not a continuous pinch.

### User-visible parity deltas confirmed by source

These are behavior differences, not performance guesses. They keep the production-canvas checklist at **partial** even though its six-node workflow and mobile alternative are already covered by widget tests.

### 已关闭的画布差异

| Behavior | ToonFlow evidence | DramaFlow evidence | Verification |
| --- | --- | --- | --- |
| Automatic layout recenters the viewport | `Toonflow-web/src/views/production/index.vue:440` calls `fitView({ duration: 300 })` after layout | `production_screen.dart` now calls public `DFCanvasController.fitView()` after restoring node positions; `df_canvas.dart` attaches/detaches that controller safely | `df_widgets_test.dart` verifies a wide graph fits its viewport; `production_screen_test.dart` drives the real auto-layout command. |
| Production canvas onboarding guide | `index.vue:97,463-489` persists `productionCurrent` and teaches four steps | `production_guide.dart` provides four target-aware desktop steps and a 390dp scrollable full-screen counterpart; `production_screen.dart` persists `production.guide.completed` in SQLite | `config_test.dart`, `production_guide_test.dart`, and `production_screen_test.dart` verify persistence, target highlight, one-time completion, desktop re-entry, compact Tab access, small-height scrolling, and remeasurement after a compact-to-desktop change. |
| Space + left-button pan | `index.vue:143-171` captures Space-held primary mouse movement even when it starts on a node | `DFCanvas` custom recognizer captures only Space-held mouse primary drags, translates `TransformationController` in screen pixels, and suppresses title-handle, card-region, and nested image gestures for that gesture | `df_widgets_test.dart` verifies 2× and 0.5× translation, no node or nested-image delta on a card drag region, and that touch dragging remains available even if an external keyboard reports Space down. |

The closed rows are retained here so the audit trail shows the original evidence and the exact replacement, rather than silently dropping resolved differences.

| Behavior | ToonFlow evidence | DramaFlow evidence | Parity consequence |
| --- | --- | --- | --- |
| Visible canvas controls | VueFlow renders `<Controls />` at `index.vue:55` | Desktop overlay has automatic-layout and Agent buttons only (`production_screen.dart:240-258`) | There is no user-visible equivalent for the reference canvas control surface. Exact button semantics still need black-box confirmation before an implementation choice. |
| Episode switch during active production Agent work | `index.vue:255-295` asks for confirmation while status is `pending` or `streaming` | The Flutter episode bar directly assigns `_scriptId` (`production_screen.dart:65-70`) | The original protection is absent. Flutter's simplified Agent has different status architecture; the user-facing switch guard is nevertheless not present. |
| Agent panel initial state | `openShowVisible = ref(true)` at `index.vue:127` | `_chatOpen = false` at `production_screen.dart:140` | Small default-state difference: ToonFlow opens production chat by default; DramaFlow requires an explicit click. |

### Closed interaction: Space-held pan

This is a narrow, reusable `DFCanvas` behavior rather than a production-page
button. ToonFlow listens for `Space` at the document level, captures a left
button press while that key is held, suppresses node handling, and updates the
viewport from the pointer delta (`index.vue:143-171`). The effect is deliberate:
users can pan even when their pointer starts on a draggable node.

DramaFlow now gives that precedence only to a Space-held **mouse** primary
drag: it changes the `TransformationController` translation in logical screen
pixels, never calls a node's `onDragUpdate`, and leaves scale unchanged.
Releasing or cancelling the pointer ends the temporary mode. Touch drag/pinch
is handled by the background gesture layer and remains available when an
external keyboard happens to report Space down. This shared implementation
covers both the six-node production canvas and the image-flow editor.

`df_widgets_test.dart` proves the behavior at 2× and 0.5× zoom, including a
`DFCanvasDragRegion` card surface, and proves the mobile guard.
`image_flow_editor_test.dart` then verifies the real editor saves a dragged
generated node on desktop and 390dp, while a parameter-field drag leaves its
coordinates unchanged. The fixtures are local only: no provider call, media
task, or persisted project state is involved.

---

## 3. Proposed measurable metrics for W1

### Realistic scale (choosing N)

- The design numbers shots **S01–S99** (`p3-production-canvas-brief.md:29`; `storyboard_canvas_node.dart:397` renders `S{index+1}` zero-padded to 2 digits). So **~99 shots/episode is the design-anticipated upper bound**; there is no hard cap in code (I found no shot-count limit in `app/lib` or the ToonFlow routes).
- Main-canvas top-level nodes are fixed at **6** (`production_screen.dart:176-234`).
- Therefore the canvas's real element-count stress comes from **shot cells inside the storyboard node** (target ~100) and, separately, **user-built nodes in the editImage editor**. The spec's "hundreds of nodes" is best read as an aspirational headroom target rather than the main canvas's actual node count.

Proposed test tiers: **N = 50 (typical-heavy), 100 (design max), 200 (headroom/stress)** shot cells; and for editImage, **10 / 25 / 50 nodes**.

### The metrics

| # | Metric | Concrete target | How to measure in Flutter (concrete) |
|---|---|---|---|
| M1 | **Continuous pan stays full-frame** on the main canvas with the storyboard node fully populated | With N=100 cells on screen, median frame **build+raster ≤ 16.6 ms** (60fps); **no frame > 33 ms** (no dropped-below-30 stutter) across a scripted 2s pan | `integration_test` + `WidgetsBinding.instance.addTimingsCallback` to collect `FrameTiming.totalSpan` (or `buildDuration`/`rasterDuration` separately) while driving `tester.timedDrag` / repeated `TransformationController` updates in **profile mode** (`flutter test --profile` / `flutter drive`). Assert p50 ≤ 16.6ms, p99 ≤ 33ms. |
| M2 | **Continuous pinch-zoom stays full-frame** | Same budget as M1 during a scripted zoom sweep 0.1→2.0→0.1 | Same harness; drive a zoom gesture (`tester.zoomBy` / synthetic scale pointers) or programmatic `_controller.value` scale ramp; collect `addTimingsCallback` timings. |
| M3 | **Zoom follows cursor / focal point** | After a pinch or mouse-wheel zoom, the focal scene point stays under the current focal point within **≤ 2 logical px** | Pure widget test: set a known transform, apply a focal-point scale, assert `controller.toScene(P)` has the expected origin relation. Direct regressions cover the background and a transformed node-content region, so transformed pointer coordinates cannot silently drift the focal point; this is still a guard, not a performance claim. |
| M4 | **Pointer-device behavior matches the selected mode** | `zoom`: mouse wheel and trackpad scroll scale around the focal point; `scroll`: both pan. Pinch always scales; any future inertia must meet the frame budget. | **Widget semantics verified.** `CanvasWheelMode` is an in-memory session value (default `zoom`); Other Settings changes it immediately, and only the desktop production `DFCanvas` receives it. Tests cover mouse/trackpad in both modes, production-page propagation, 390dp control reachability, and parameter-region wheel stop in `scroll`. Physical-device recording and inertia remain open. |
| M5 | **Node drag has no stutter** (main and editImage canvases) | Dragging one node among N=25: median frame ≤ 16.6ms, no frame > 33ms across a 1s scripted drag | `integration_test`: drive each canvas's real drag handle and collect `addTimingsCallback` timings. Also assert rebuild scope with a build counter on non-dragged editImage nodes to catch the whole-list rebuild cost (`image_flow_editor.dart:992`). |
| M6 | **Culling correctness under pan** (protects M1) | With N=200 cells spread across the scene, the number of built node widgets stays bounded to those intersecting viewport±600px at all pan positions | Existing widget coverage already exercises a stronger 1,000-top-level-node culling case: `test/widgets/df_widgets_test.dart:128-172`. W1 should preserve that regression guard and extend it only where the production storyboard's nested cells reveal a distinct failure mode. |
| M7 | **Grid layer cost is bounded** | First-frame raster after canvas mount ≤ a chosen budget (TBD in W1); no per-pan grid repaint | `addTimingsCallback` on the mount frame; verify `_GridPainter.shouldRepaint` never fires during pan (it depends only on color, `df_canvas.dart:787-789`). See §5 note — the 12000×8000 paint area needs real measurement. |

General methodology (aligns with the spec's "profile 基准 + 录屏证据"): run M1/M2/M5/M6 as automated `integration_test` assertions in **profile mode** (debug-mode timings are meaningless), and back M4 and the subjective "feel" with a DevTools timeline export + screen recording. Seed a synthetic project with N shots via the engine's `addStoryboard` path so the storyboard node is genuinely populated.

---

## 4. What is explicitly NOT benchmarked today

**Zero frame-timing / FPS benchmark coverage** exists for either canvas. That statement needs to stay narrow: the project does have meaningful canvas behavior coverage and three real-process integration tests.

- `test/widgets/df_widgets_test.dart:128-172` proves off-screen culling across a **1,000-node** `DFCanvas`; `:174-207` proves title-handle drag converts screen movement into scene coordinates. `test/widgets/production_screen_test.dart:155-178` covers desktop node dragging, episode selection, and automatic layout; mobile canvas alternatives are covered at `:197-208`.
- `test/widgets/storyboard_canvas_node_test.dart` and `test/widgets/canvas_chat_panel_test.dart` add storyboard editing / production-chat behavior, but they are not rendering-performance tests.
- `integration_test/` exists: `golden_path_desktop_test.dart`, `golden_path_navigation_test.dart`, and `composer_audio_smoke_test.dart` boot a real process or exercise the native compositor. They do **not** collect canvas `FrameTiming`, profile scripted pan/zoom, or assert frame budgets.
- A repository search found no `FrameTiming`, benchmark harness, or canvas FPS assertion under `app/test`, `app/integration_test`, or `app/lib`.

So M1/M2/M4/M5/M7 are new validation work. M6's basic culling correctness is already covered; W1 should retain, not duplicate, that 1,000-node guard. A profile-mode run path must be added only if measured evidence shows the interaction work needs it.

---

## 5. Rough implementation-scope sense per metric

Honest calibration from static reading. Where I cannot tell without running the app, I say so — that is an expected limitation, not a gap.

| Metric | Likely current status | Rationale |
|---|---|---|
| M1 (pan fps) | **Likely needs moderate tuning** | Culling + RepaintBoundary are already in place (`df_canvas.dart:557-753`), which is the right foundation. The risk is the per-frame `setState` full rebuild (`df_canvas.dart:330-332`) diffing the node list every pan frame. Whether that actually drops frames at N=100 **cannot be determined without profiling** — the culling may keep built-node count low enough. Plausible fix if it does drop: rebuild only the transform/culling layer, or repaint edges/grid via a `RepaintBoundary`-isolated painter listening to the controller rather than `setState` on the whole subtree. |
| M2 (zoom fps) | **Likely needs moderate tuning** | Same rebuild path as M1; additionally, at low zoom more cells fall inside the culling rect, so worst case is different from pan. Needs measurement. |
| M3 (cursor-follow zoom) | **Widget regression verified** | The custom background gesture layer keeps the focal scene coordinate fixed for pinch and mouse-wheel zoom. This guards matrix math, not physical-device feel or performance. |
| M4 (pointer-device behavior + inertia) | **Selector semantics verified; feature partial** | The session-only `zoom` / `scroll` selector now matches ToonFlow's setting: both mouse and trackpad focal-zoom in `zoom`, and pan in `scroll`. Generated-image parameter regions intentionally stop the signal in either mode, matching ToonFlow's `.parameter @wheel.stop`. Inertia and real-device feel still need recording. |
| M5 (node drag, both canvases) | **Likely needs moderate tuning** | Main-canvas dragging updates `_CanvasLayout` on every pointer movement; editImage's `onPanUpdate → setState` rebuilds the editor's whole node list per delta (`image_flow_editor.dart:992, 984-1016`). At small N either may be fine; profile data should choose whether a drag-local state refinement is needed. |
| M6 (culling correctness) | **Verified for generic nodes; storyboard-cell coverage still open** | `test/widgets/df_widgets_test.dart:128-172` already verifies culling in a 1,000-node `DFCanvas`. The outstanding question is not whether generic nodes are culled, but whether the nested storyboard grid behaves acceptably under the production workload. |
| M7 (grid layer cost) | **Uncertain — needs measurement; possible rearchitecture** | The grid `CustomPaint` covers the full **12000×8000** scene (`df_canvas.dart:669-702, 767-789`). Whether Flutter rasterizes that as one very large cached layer (potentially large raster memory) or clips it is **not determinable from static reading** — I'm flagging it as a specific thing to measure. If it proves costly, switching the grid to a viewport-space tiled/repeating painter (paint only the visible rect, follow the transform) would be a moderate change. *(Raster-memory concern here is speculation pending measurement.)* |

### Cross-cutting note for the W1 spec author

The highest-leverage single question W1 profiling should answer first: **does the `setState`-per-transform-tick rebuild (`df_canvas.dart:330-332`) actually cost frames at N≈100, or does culling absorb it?** Most of M1/M2/M5's scope hinges on that answer, and it is exactly the kind of thing that cannot be resolved by reading — it needs a profile-mode timeline. Everything else (culling, RepaintBoundary, focal-point zoom, and explicit card/parameter gesture ownership) is already structurally present, which is why DramaFlow starts from a materially better place than ToonFlow's no-virtualization + interaction-mode-hack baseline.

---

## 6. Evidence refresh — 2026-07-19

This refresh reran the canvas-facing widget suite against the current `develop`
worktree. It is deliberately an interaction regression result, **not** a
performance claim and not a real video-provider test.

```text
cd app
flutter test --concurrency=1 \
  test/widgets/df_widgets_test.dart \
  test/widgets/production_screen_test.dart \
  test/widgets/storyboard_canvas_node_test.dart \
  test/widgets/canvas_chat_panel_test.dart

37 tests passed
```

| Verified by this run | What it proves | What it does not prove |
| --- | --- | --- |
| `DFCanvas` 1,000-node culling | Off-screen top-level nodes are not mounted and become visible after a viewport transform | Raster/build time while panning, nested storyboard-cell cost, or device frame rate |
| Background drag/pinch/wheel/trackpad plus title-handle and card-region drag | Primary-button desktop pan, right-button isolation, background and node-start mobile pinch, both pointer devices in session `zoom` and `scroll` modes, transformed-card focal zoom, title/card drag coordinates, Space precedence, touch dragging, real image-flow desktop/390dp persistence, and parameter isolation all have widget evidence | Drag performance under a populated canvas or physical-device feel |
| Desktop production page | Six nodes render; the Agent panel opens; node positions survive episode switching; refresh rebuilds the current local view; automatic layout restores positions and recenters the viewport | Active-Agent episode switch protection or the default chat-open state |
| 390dp production alternative | The Tab layout, node inspector, full-screen Agent entry, storyboard/workbench routes and local fake-composition path remain reachable | Native iOS/Android gesture feel, touch performance, or a desktop infinite-canvas equivalent on a narrow screen |
| Storyboard and production chat | Editing and local confirmation paths still render through the production surface | Real image/video generation; this run invokes no real media provider |

The source comparison was also rechecked in the same worktree. The session
`zoom` / `scroll` control is now closed: `settings_screen.dart:950-1017`
changes the in-memory provider, and `production_screen.dart:83-124,215-285`
passes it only to the main desktop `DFCanvas`. `image_flow_editor.dart` does
not read the setting, matching ToonFlow's separate edit-image VueFlow. Open
user-visible deltas remain selection, active-Agent episode-switch confirmation,
and the default-open production chat. The post-layout `fitView`, persisted
guide, and Space-held pan are also closed differences. No test above covers the
W1 frame-time metrics M1/M2/M4/M5/M7, so `W6-PRODUCTION-001` correctly remains **partial** in
[`master-checklist.md`](master-checklist.md).
