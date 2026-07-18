# W1 Canvas Performance & Gesture-Feel Metrics — Reference Draft

Status: draft input for a future W1 spec. Read-only investigation, 2026-07-18. All factual claims cite `file:line`. Anything I could not verify from static source is explicitly labeled speculation. I did not run either app.

## 0. Scope note: there are two canvases

DramaFlow has **two** distinct canvas surfaces, both built on the same `DFCanvas` widget but with very different interaction profiles. W1's motivating complaint ("无限画布的感觉体验也不好") is about the **main production canvas**, but node-drag feel only actually exists on the second one, so the metrics must cover both:

| Canvas | File | Node count | Draggable nodes? | Heaviest content |
|---|---|---|---|---|
| Main production canvas | `production_screen.dart:136-211` (`_CanvasLayout`) | Fixed 6 container nodes (`production_screen.dart:161-203`) | **No** — fixed chain layout, recomputed each build | The `storyboard` node, whose grid holds up to ~99 image cells |
| editImage node editor | `image_flow_editor.dart:984-1016` | Variable (user-built upload/generated nodes) | **Yes** — `image_flow_editor.dart:992` | Per-node 320px image cards |

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

- **Pan/zoom = `InteractiveViewer`.** `df_canvas.dart:179-184`: `minScale: 0.1, maxScale: 10` (matches VueFlow), `constrained: false`, `boundaryMargin: EdgeInsets.all(4000)`. All gesture handling (trackpad pinch, drag-pan, scroll-zoom, inertia) is delegated to Flutter's stock `InteractiveViewer` — DramaFlow writes no custom gesture code for the main canvas.
- **Scene = a fixed 12000×8000 `SizedBox`**, not truly infinite (`df_canvas.dart:185-215`). Nodes are `Positioned` children of a single `Stack`.
- **Nodes are laid out, not dragged, on the main canvas.** `production_screen.dart:141-211` computes fixed chain positions every build (`x += nodeW + gap`); `DFCanvasNode` exposes no drag callback. Positions are not persisted (matches ToonFlow main-canvas semantics).
- **Edges = `CustomPainter` cubic béziers.** `_EdgePainter`, `df_canvas.dart:248-277`, `Path.cubicTo`.
- **Grid = `CustomPainter`.** `_GridPainter`, `df_canvas.dart:223-246`, a nested loop over the full 12000×8000 at 40px step (≈300×200 ≈ 60,000 `drawCircle` calls); `shouldRepaint` returns true only on color change.

**Existing optimizations already present** (this is genuinely ahead of ToonFlow on the culling axis):

- **Viewport culling of nodes AND edges.** `df_canvas.dart:118-178`: `_visibleSceneRect` projects the viewport into scene space (inflated 600px), and only nodes/edges intersecting it (`_nodeIntersects` `:133-141`, `_edgeIntersects` `:143-160`) are built. This is the opposite of ToonFlow's `only-render-visible-elements="false"`.
- **`RepaintBoundary` around grid, the edge layer, and every node** (`df_canvas.dart:189, 197, 212`).
- **Fit-on-init** (`_fitView`, `df_canvas.dart:91-116`), clamping scale to 0.1–1.0.

**The one structural cost to flag:** `df_canvas.dart:76-78` — `_handleTransformChanged` calls `setState(() {})` on **every** `TransformationController` tick. So during a continuous pan or pinch, the whole `LayoutBuilder` body re-runs each frame: it rebuilds `nodesById`, recomputes `visibleNodes`/`visibleEdges`, and re-diffs the `Stack` children every frame. Culling bounds *how many* widgets get built; `RepaintBoundary` bounds repaint; but the per-frame **rebuild + element diff of the node list is unavoidably O(nodes) every pan frame**. This is the single most likely DramaFlow-side source of pan/zoom jank and the thing W1 most needs to measure.

**Node dragging (editImage editor only).** `image_flow_editor.dart:992`: `onPanUpdate: (d) => setState(() => n.position += d.delta)`. The `setState` is on the editor's own `State`, so **each pointer-move rebuilds the entire `DFCanvas` node list** (`image_flow_editor.dart:984-1016`), not just the dragged node. Node counts here are typically small, so this may be fine in practice — but it is the classic "rebuild-the-world-per-drag-delta" pattern and should be measured, not assumed.

**Storyboard grid inside its node.** `storyboard_canvas_node.dart:569-587`: a `SingleChildScrollView` + `Wrap` over all rows with no windowing (same shape as ToonFlow's grid, minus the always-mounted-across-viewport problem since the whole node is culled when off-screen). Cell zoom is a session-only `_cellSize` clamped 90–260 via +/- buttons (`:51, :482-491`), not a continuous pinch.

---

## 3. Proposed measurable metrics for W1

### Realistic scale (choosing N)

- The design numbers shots **S01–S99** (`p3-production-canvas-brief.md:29`; `storyboard_canvas_node.dart:397` renders `S{index+1}` zero-padded to 2 digits). So **~99 shots/episode is the design-anticipated upper bound**; there is no hard cap in code (I found no shot-count limit in `app/lib` or the ToonFlow routes).
- Main-canvas top-level nodes are fixed at **6** (`production_screen.dart:161-203`).
- Therefore the canvas's real element-count stress comes from **shot cells inside the storyboard node** (target ~100) and, separately, **user-built nodes in the editImage editor**. The spec's "hundreds of nodes" is best read as an aspirational headroom target rather than the main canvas's actual node count.

Proposed test tiers: **N = 50 (typical-heavy), 100 (design max), 200 (headroom/stress)** shot cells; and for editImage, **10 / 25 / 50 nodes**.

### The metrics

| # | Metric | Concrete target | How to measure in Flutter (concrete) |
|---|---|---|---|
| M1 | **Continuous pan stays full-frame** on the main canvas with the storyboard node fully populated | With N=100 cells on screen, median frame **build+raster ≤ 16.6 ms** (60fps); **no frame > 33 ms** (no dropped-below-30 stutter) across a scripted 2s pan | `integration_test` + `WidgetsBinding.instance.addTimingsCallback` to collect `FrameTiming.totalSpan` (or `buildDuration`/`rasterDuration` separately) while driving `tester.timedDrag` / repeated `TransformationController` updates in **profile mode** (`flutter test --profile` / `flutter drive`). Assert p50 ≤ 16.6ms, p99 ≤ 33ms. |
| M2 | **Continuous pinch-zoom stays full-frame** | Same budget as M1 during a scripted zoom sweep 0.1→2.0→0.1 | Same harness; drive a zoom gesture (`tester.zoomBy` / synthetic scale pointers) or programmatic `_controller.value` scale ramp; collect `addTimingsCallback` timings. |
| M3 | **Zoom follows cursor / focal point** | After a pinch centered at point P, the scene point under P stays under P within **≤ 2 logical px** | Pure widget test: set a known transform, apply a focal-point scale, assert `controller.toScene(P)` is invariant. `InteractiveViewer` already does focal-point zoom; this is a *regression guard*, not new behavior. |
| M4 | **Trackpad pinch + pan inertia present and smooth** | Fling-pan decelerates over **≥ 300 ms** with no frame > 33 ms during the inertia tail; two-finger pinch recognized | Harder to script deterministically. Guard the *enablement* in a widget test (`InteractiveViewer` default `panEnabled`/`scaleEnabled` true, `panAxis` free). Actual inertia smoothness → profile-mode timeline capture during a manual fling, exported from DevTools; treat as **manual + screen-recording evidence** per the spec, not an assert. |
| M5 | **Node drag has no stutter** (editImage editor) | Dragging one node among N=25: median frame ≤ 16.6ms, no frame > 33ms across a 1s scripted drag | `integration_test`: `tester.drag` on a node's `GestureDetector`, collect `addTimingsCallback` timings. **Also** assert rebuild scope via a build counter on non-dragged nodes to catch the "whole list rebuilds per delta" cost (`image_flow_editor.dart:992`). |
| M6 | **Culling correctness under pan** (protects M1) | With N=200 cells spread across the scene, the number of built node widgets stays bounded to those intersecting viewport±600px at all pan positions | Widget test using a build-tap counter or `find`-count on node keys after moving the `TransformationController`; assert built count ≪ N when most nodes are off-screen. Directly exercises `_visibleSceneRect`/`_nodeIntersects` (`df_canvas.dart:118-178`). |
| M7 | **Grid layer cost is bounded** | First-frame raster after canvas mount ≤ a chosen budget (TBD in W1); no per-pan grid repaint | `addTimingsCallback` on the mount frame; verify `_GridPainter.shouldRepaint` never fires during pan (it depends only on color, `df_canvas.dart:244-245`). See §5 note — the 12000×8000 paint area needs real measurement. |

General methodology (aligns with the spec's "profile 基准 + 录屏证据"): run M1/M2/M5/M6 as automated `integration_test` assertions in **profile mode** (debug-mode timings are meaningless), and back M4 and the subjective "feel" with a DevTools timeline export + screen recording. Seed a synthetic project with N shots via the engine's `addStoryboard` path so the storyboard node is genuinely populated.

---

## 4. What is explicitly NOT benchmarked today

**Zero** performance/frame-timing coverage exists for either canvas. Confirmed by:

- The only canvas-related tests are `test/widgets/storyboard_canvas_node_test.dart` and `test/widgets/canvas_chat_panel_test.dart`, both **purely behavioral** (preview-all page count, export button, insert-before ordering, generate-button gating, chat send/clear — see their `testWidgets` names).
- Grep of the entire `app/test/` tree for `FrameTiming`, `SchedulerBinding`, `timeDilation`, `frameBuildTime`, `BenchmarkResultPrinter`, `integration_test`, `benchmark`, `fps` returns **nothing** (the only "frame" hits are the string `'old/frame.png'` in `storyboard_test.dart:503,594`).
- There is no `integration_test/` directory and no benchmark harness.

So every metric in §3 is **new work**. None of it is silently covered by an existing test. W1 will need to add an `integration_test` target and a profile-mode run path that does not exist yet.

---

## 5. Rough implementation-scope sense per metric

Honest calibration from static reading. Where I cannot tell without running the app, I say so — that is an expected limitation, not a gap.

| Metric | Likely current status | Rationale |
|---|---|---|
| M1 (pan fps) | **Likely needs moderate tuning** | Culling + RepaintBoundary are already in place (`df_canvas.dart:118-178, 189-212`), which is the right foundation. The risk is the per-frame `setState` full rebuild (`df_canvas.dart:76-78`) diffing the node list every pan frame. Whether that actually drops frames at N=100 **cannot be determined without profiling** — the culling may keep built-node count low enough. Plausible fix if it does drop: rebuild only the transform/culling layer, or repaint edges/grid via a `RepaintBoundary`-isolated painter listening to the controller rather than `setState` on the whole subtree. |
| M2 (zoom fps) | **Likely needs moderate tuning** | Same rebuild path as M1; additionally, at low zoom more cells fall inside the culling rect, so worst case is different from pan. Needs measurement. |
| M3 (cursor-follow zoom) | **Likely already satisfied** | Stock `InteractiveViewer` does focal-point scaling; this is a cheap regression guard. |
| M4 (pinch + inertia) | **Likely already satisfied for enablement; feel is unknown** | `InteractiveViewer` provides pinch and fling inertia by default. Whether the inertia *feels* good (and whether the per-frame rebuild stutters during the inertia tail) **cannot be judged statically** — needs a device + recording. |
| M5 (node drag, editImage) | **Likely needs moderate tuning** | `onPanUpdate → setState` on the editor state rebuilds the whole node list per delta (`image_flow_editor.dart:992, 984-1016`). At small N it may be fine; the fix (drag-local state / `ValueListenable` per node) is well-understood and contained. Not a rearchitecture. |
| M6 (culling correctness) | **Likely already satisfied** | Logic exists and is straightforward (`df_canvas.dart:133-160`); this metric mostly locks in current behavior against regressions. |
| M7 (grid layer cost) | **Uncertain — needs measurement; possible rearchitecture** | The grid `CustomPaint` covers the full **12000×8000** scene (`df_canvas.dart:191-194, 233-240`). Whether Flutter rasterizes that as one very large cached layer (potentially large raster memory) or clips it is **not determinable from static reading** — I'm flagging it as a specific thing to measure. If it proves costly, switching the grid to a viewport-space tiled/repeating painter (paint only the visible rect, follow the transform) would be a moderate change. *(Raster-memory concern here is speculation pending measurement.)* |

### Cross-cutting note for the W1 spec author

The highest-leverage single question W1 profiling should answer first: **does the `setState`-per-transform-tick rebuild (`df_canvas.dart:76-78`) actually cost frames at N≈100, or does culling absorb it?** Most of M1/M2/M5's scope hinges on that answer, and it is exactly the kind of thing that cannot be resolved by reading — it needs a profile-mode timeline. Everything else (culling, RepaintBoundary, focal-point zoom, inertia) is already structurally present, which is why DramaFlow starts from a materially better place than ToonFlow's no-virtualization + interaction-mode-hack baseline.