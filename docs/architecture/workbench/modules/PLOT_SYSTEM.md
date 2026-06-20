# Workbench — Plot System Module Group

> **Module Group**: groups Plot Display, Plot Controls, and Plot Preservation modules within the Main Board. This document covers Plot System Module Group capabilities: workflow-independent plot shell、style params、legend dimension auto-inference、Copy PNG 倍率、point label、curve reorder opt-in。

## Terminology

| Term | Meaning |
|---|---|
| **XY Rotation** | A Workbench *workflow* — the angle-sweep resistance measurement workflow (`XYRotationWorkspaceStore`, `XYRotationPlotRenderer`). Not a render path. |
| **Cartesian XY render path** (also "XY render path") | The Plot System series renderer: `WorkbenchRenderPipeline` → `WorkbenchChartRenderer` → `WorkbenchPlotLayout`. Renders cartesian line/scatter charts from `WorkbenchPlotPayload`. |
| **XY workflow** | **Ambiguous — do not use.** Use "Cartesian XY render path" for the renderer and "XY Rotation workflow" for the measurement workflow. |

Workflows that currently use the Cartesian XY render path: AHE, XY Rotation, 3ω, IV.

## Module Group Structure

Plot System is a module group with three sub-modules:

- **Plot Display / Canvas**: render output and direct graphic interaction only. The canvas is a workflow-independent display surface. It shows plot images, handles pointer-driven interactions, and emits interaction callbacks. It does not own any persistent override state and does not host text or style editing widgets. Canonical interaction surface: legend drag, point dot toggle, Copy PNG, hover preview. Canonical owner: `WorkbenchPlotCanvas` / `TabRenderManager` projections.
- **Plot Controls**: the primary entry point for all text and style editing. Owns title override, x/y label override, legend label override, and tick density controls. Font sizes are wired to Global Plot Defaults, not workflow-local pack state. These editing surfaces live in the sidebar controls panel, not on the canvas. Canonical container: `WorkbenchPlotControlsPanel`. Shared layout for multi-tab stacking workflows: `WorkbenchStandardPlotControls`. AHE uses a workflow-local `AHEPlotControlsPanel` — a legitimate single-tab specialization. Binding targets are either `TabRenderManager`-owned (Plot Preservation), workflow-store-owned (Assembly-owned display parameters), or shared global plot defaults.
- **Plot Preservation**: per-tab display override state and pack round-trip. `TabRenderState` stores legend position, title/axis/label overrides, series order, and point label visibility. Canonical owner: `TabRenderManager`. No other module may write `TabRenderState` override fields directly.

`TabRenderManager` is the **existing extracted** Plot Preservation owner — not a new or proposed module. Its `buildPipelineInput` method assembles `WorkbenchRenderPipeline.Input` from per-tab state and shared display settings for AHE and XY. 3ω does not use `buildPipelineInput`; all 3ω rendering paths capture `tabs.legendAnchor` manually and pass it to `ThreeOmegaPlotRenderer.legendAnchor` directly — a consequence of 3ω's custom renderer architecture, not a boundary violation.

## Current-State Architecture

### Pipeline Map

The Plot System implements a single render path that all current workflows share:

```
Workflow analysis result
→ workflow plot builder
  (per-workflow renderer: XYRotationPlotRenderer, ThreeOmegaPlotRenderer, or AHEWorkspaceStore plot method)
→ WorkbenchPlotPayload  [XY series payload — current render path input contract]
  (x/y series arrays, axis mapping, series metadata, style params, legend dimension)
→ WorkbenchRenderPipeline.render(_:)
  (display overrides → style merge → legend auto-resolution → series reversal → series order check)
→ WorkbenchChartRenderer.renderPNG  [pure CoreGraphics, no SwiftUI/AppKit]
   WorkbenchPlotLayout.compute       [geometry shared by renderer drawing and canvas hit-testing]
→ PNG Data + WorkbenchPlotLayout
  (plotRect, title/axis centers, legend rows + box rect, point hit rects, axis ranges)
→ WorkbenchPlotCanvas
  (rendered PNG display + legend drag, point dot toggle, Copy PNG, hover preview)
→ copy / save / pack restore path
  (PNG exported via Copy PNG; manifestPayload persisted by save-to-library;
   TabRenderState restored from pack config)
```

### Component Classification

| Component | Classification |
|---|---|
| `WorkbenchPlotCanvas` | **Shared shell/display** — workflow-independent PNG display and interaction shell |
| `WorkbenchPlotPayload` / `WorkbenchPlotSeries` | **XY-specific payload** — current render path input contract (x/y series arrays, axis mapping, series metadata) |
| `WorkbenchChartRenderer` | **XY-specific renderer** — CoreGraphics rasteriser for XY line/scatter series |
| `WorkbenchPlotLayout` | **XY-specific layout** — geometry for axes, titles, legend rows, hit rects, axis range mirroring |
| `WorkbenchChartStyle` | **XY-specific renderer styling** — font name, font sizes, tick targets, parsed from `styleParams` |
| `WorkbenchRenderPipeline` | **XY render path orchestrator** — display overrides, legend auto-resolution, style merge, PNG output |
| `WorkbenchPlotControlsPanel` | **Shared controls container** — render mode picker, font sizes, tick density; workflow content injected via ViewBuilder |
| `WorkbenchStandardPlotControls` | **XY-specific controls** — tab picker, stack offset, gap, title template, grid, label overrides for multi-tab stacking workflows |
| `LegendDimensionResolver` | **Distributed legend capability** — auto-infers legend dimension from series metadata; invoked by the render pipeline |
| `WorkbenchPlottingStore` | **Save/canvas bridge protocol** — canvas interaction callbacks wired into workflow store and `TabRenderManager` |

### XY Render Path — Currently Implicit

The existing render path is **implicitly an "XY render path"**: it expects `WorkbenchPlotPayload` to carry x/y series arrays, renders cartesian line/scatter charts, and applies XY-specific layout (axes, tick labels, point labels). This path is not yet formally named as a separate XY module — it is simply the only render path that currently exists.

This distinction matters for future extension: a second render path (e.g., Heatmap) should be a parallel path inside Plot System, not an extension of the existing XY types. `WorkbenchPlotPayload`, `WorkbenchChartRenderer`, `WorkbenchPlotLayout`, and `WorkbenchChartStyle` are XY-specific and must not be extended to handle heatmap grid data.

### Legend — Distributed Capability, Not an Independent Module

Legend is **not a standalone module**. It is a distributed capability spanning five sites:

- `WorkbenchPlotLayout` — computes legend row positions, hit rects, and box geometry (single source of truth for renderer and canvas)
- `WorkbenchChartRenderer` — draws the legend box, color swatches, and text labels using pre-computed `LegendRow` positions
- `WorkbenchPlotCanvas` — handles legend drag interaction and renders the drag-preview overlay
- `WorkbenchRenderPipeline` / `LegendDimensionResolver` — auto-resolves legend dimension from series metadata and updates series labels before render
- `TabRenderManager` — stores legend position (`legendAnchor`, `legendPoint`) as per-tab override state

There is no gate-driven plan to extract Legend as an independent module. Future capabilities that add new legend behavior (e.g., a colorbar for heatmap) should be designed as heatmap render path internals, not as additions to the existing distributed legend sites.

### WorkbenchPlotCanvas — Display Shell, Not Renderer

`WorkbenchPlotCanvas` is a rendered PNG display and interaction shell. It accepts `imageData: Data?` (PNG bytes) and `layout: WorkbenchPlotLayout?` from the workflow store via `WorkflowWorkspaceResultArea`, displays the image using SwiftUI `Image(nsImage:)`, and provides legend drag, point dot toggle, Copy PNG, and hover preview.

It does **not** perform XY rendering. It has no knowledge of `WorkbenchPlotSeries`, axis math, or tick computation. `WorkbenchPlotCanvas` may be reused by a future render path (e.g., Heatmap) if that render path also produces a PNG + a `WorkbenchPlotLayout`-compatible hit-rect contract. Whether a new render path can satisfy that contract must be verified at the time of design.

## Heatmap Render Path (Gate 8.2 Architecture)

### Ownership: Plot System, Not RSM

Heatmap is a **Plot System-owned render path**, not an RSM workflow module. RSM is the first workflow to produce heatmap output, but:

- `HeatmapPlotPayload` is a **Plot System contract**, not an RSM contract.
- The heatmap renderer, color scale, colorbar, heatmap layout, and heatmap render pipeline are owned and implemented by Plot System.
- RSM Assembly is responsible only for scientific semantics: it interprets its analysis result and turns it into a `HeatmapPlotPayload`. It must not own or implement the renderer, colormap, colorbar geometry, or heatmap controls.
- Any future workflow that produces 2D grid data reuses the same heatmap render path by filling a `HeatmapPlotPayload`. The render path is not named or shaped around RSM physics.

**Forbidden**: RSM must not own or implement a heatmap renderer. Heatmap-rendering Swift code that lives in RSM workflow files is a boundary violation.

### Heatmap Pipeline (Target Architecture)

The heatmap render path runs **parallel** to the existing XY render path inside Plot System:

```
RSM (or future workflow) analysis result
→ workflow plot builder  [Assembly-owned; scientific semantics only]
→ HeatmapPlotPayload  [Plot System contract]
  (nX × nY grid of Z values, X/Y axis labels, Z-axis label,
   colormap hint key, optional Z-range clamp)
→ HeatmapRenderPipeline.render(_:)  [Plot System-owned]
  (display overrides → colormap resolution → Z-range auto-scale → colorbar geometry)
→ HeatmapChartRenderer.renderPNG  [pure CoreGraphics, no SwiftUI/AppKit]
   HeatmapPlotLayout.compute        [grid rect, colorbar rect, axis label positions, title position]
→ PNG Data + HeatmapPlotLayout
→ WorkbenchPlotCanvas
  (PNG display shell; layout: nil in V1 — Copy PNG only, no cell hit-testing)
→ copy / save / pack restore path
  (PNG via Copy PNG; manifest reference persisted by save-to-library;
   heatmap tab state restored from pack config)
```

The two render paths share `WorkbenchPlotCanvas` as a PNG display shell. They do **not** share payload types, renderer types, or layout types.

### V1 Scope

**In V1 — Plot System must implement:**

- `HeatmapPlotPayload` — new Plot System contract. Grid data (2D Z-value matrix), X/Y axis labels, Z-axis label, colormap hint, optional Z-range clamp.
- `HeatmapChartRenderer` — new CoreGraphics renderer. Renders 2D color grid + colorbar with tick labels + axis labels + title to PNG.
- `HeatmapPlotLayout` — new layout type. Owns gridRect, colorbarRect, title and axis label positions. Must not extend or inherit `WorkbenchPlotLayout` (XY-specific).
- Color scale — Plot System-owned. V1 supports at minimum one perceptually-uniform colormap (e.g., viridis). RSM may supply a colormap hint key in the payload; Plot System interprets and renders it.
- Colorbar — Plot System-owned. V1 renders a vertical colorbar with min/max tick labels and Z-axis title baked into the PNG.
- `WorkbenchPlotCanvas` reused with `layout: nil` — heatmap PNG displays correctly; Copy PNG works; XY hit-testing (legend drag, point dot toggle) is inactive.

**Not in V1:**

- Cell-level hit-testing (click grid cell to read Z value).
- Interactive color scale range adjustment via UI.
- Multiple colormap options in the controls UI.
- Colorbar drag or repositioning.
- Any heatmap-specific canvas interaction beyond Copy PNG.

### Canvas Reuse in V1

`WorkbenchPlotCanvas` accepts `imageData: Data?` and `layout: WorkbenchPlotLayout?`. For V1 heatmap:

- Pass `imageData` = heatmap PNG rendered by `HeatmapChartRenderer`. Canvas displays it.
- Pass `layout: nil`. Canvas shows the image without XY hit-testing. Legend drag, point dot toggle, and hover preview are inactive. Copy PNG remains available via right-click context menu.

This is a deliberate V1 simplification. The colorbar and axis labels are rendered into the PNG by `HeatmapChartRenderer` — no canvas overlay or hit-testing is required.

Future heatmap interactions (cell read-out, colorbar range drag) would require either:
- A `HeatmapPlotLayout` that the canvas learns to accept alongside `WorkbenchPlotLayout`, or
- A dedicated `HeatmapPlotCanvas` display shell.

V1 does not resolve this choice. The decision is deferred to the gate that puts cell-level interaction on the roadmap.

### Plot Controls — Render-Path Classification

`WorkbenchPlotControlsPanel` currently bundles controls that are XY-specific as if they were shared. The classification below is the **authoritative boundary** for all controls work going forward.

#### Shared controls (applicable to both XY and Heatmap)

- Title override
- X-axis label override
- Y-axis label override
- Font sizes: title, axis titles

#### XY-only controls (must not be shown for heatmap tabs)

- Render mode picker (line / scatter / line+scatter) — meaningless for a color grid
- X tick density stepper
- Y tick density stepper
- Stack offset slider + gap field (`WorkbenchStandardPlotControls`)
- Tab picker (multi-tab stacking workflows)
- Legend font size (`legendFontSize`)
- Point-label font size (`pointLabelFontSize`)
- Series label overrides
- Curve reorder panel (`WorkbenchSeriesOrderPanel`)

These controls must not be shown when the active tab is a heatmap render path. The gating mechanism (payload-type check, tab capability flag, or separate controls panel) is an implementation decision deferred to the implementation gate.

#### Heatmap-only controls (V1 future — none yet exist in code)

- Colormap picker (selects which perceptual colormap the renderer uses)
- Z-axis label override (colorbar label)
- Color scale range override (auto vs. manual min/max) — if included in V1 controls scope

### Plot Preservation — Heatmap Tab State Boundary

`TabRenderState` is XY-specific. Its fields assume XY series semantics:

- `seriesLabelOverrides` — series-indexed; meaningless for heatmap
- `seriesOrder` — series reorder; meaningless for heatmap
- `legendPoint` / `legendAnchor` — XY draggable legend position; colorbar has different semantics
- `hiddenPointLabelsBySeries` — point labels; meaningless for heatmap

These fields must **not** be reused or extended for heatmap tabs.

**V1 boundary (established before code):**

Heatmap tab state V1 minimum fields:
- `titleOverride`
- `xLabelOverride`
- `yLabelOverride`
- `zLabelOverride` (colorbar label)
- Color scale range override (if user-adjustable range is in V1 scope)

`TabRenderManager` must eventually support heatmap tab state as a parallel structure to `TabRenderState`. Implementation options (to be decided at the implementation gate):

- **Option A**: `HeatmapTabRenderState` — a parallel type owned by `TabRenderManager`, stored separately from `TabRenderState`.
- **Option B**: A variant enum `TabRenderStateKind { case xy(TabRenderState); case heatmap(HeatmapTabRenderState) }` indexed by tab key.
- **Option C**: A shared base type with render-path-specific extension fields.

No option is selected at Gate 8.2. Selecting the approach is an implementation-gate deliverable.

**Pack/restore boundary for heatmap:**

- Heatmap pack state serializes: colormap key, Z-range override if user-set, title/axis/colorbar label overrides.
- Heatmap pack state must **not** serialize the rendered PNG or `HeatmapPlotLayout` — re-derived on restore.
- RSM Assembly pack config owns the analysis parameters needed to re-derive the heatmap grid. Plot System heatmap tab state owns display overrides. The boundary between them is `HeatmapPlotPayload` — RSM writes it, Plot System reads it.

### Boundary: RSM Assembly vs Plot System Heatmap Path

| Owned by RSM Assembly | Owned by Plot System (Heatmap Render Path) |
|---|---|
| Surface fit analysis result | `HeatmapPlotPayload` type definition |
| Grid data values (nX × nY Z matrix) | `HeatmapChartRenderer` |
| X/Y axis physical labels and units | `HeatmapPlotLayout` |
| Z-axis physical label (e.g., "κ (W/m·K)") | `HeatmapRenderPipeline` |
| Colormap hint key (e.g., `"viridis"`) — optional | Color scale computation and colormap lookup |
| Pack config for analysis parameters | Colorbar geometry and rendering |
| Scientific identity of chart | Heatmap tab display state and pack/restore |
| Analysis re-run on restore | Heatmap controls (colormap picker, Z-range) |

RSM must not implement colormap logic, colorbar geometry, or Z-value-to-color mapping. Plot System must not interpret RSM's surface fit parameters or derive Z values from raw measurement data.

## Heatmap V1 Implementation Plan

This section is the **authoritative implementation plan** for Heatmap V1. It translates the Gate 8.2 Architecture decisions above into a concrete list of new types to create, existing types to leave unchanged, and hard rules to enforce during implementation. No Swift code is changed or created until the implementation gate; this section is documentation only.

### 1. New Types Required

All new types are owned by Plot System. None of them may live in RSM workflow files.

| Type | Role |
|---|---|
| `HeatmapPlotPayload` | Plot System input contract. Carries: nX × nY Z-value matrix, X/Y axis labels, Z-axis label (colorbar title), colormap hint key (`String?`), optional Z-range clamp (`ClosedRange<Double>?`), title, workflowID. Codable and Sendable. Must not reuse or inherit `WorkbenchPlotPayload`. |
| `HeatmapGrid` | Value type holding the 2D Z-matrix and its dimensional metadata (nX, nY, xValues, yValues). Owned by `HeatmapPlotPayload`. RSM fills this from its surface-fit result. |
| `HeatmapRenderPipeline` | Orchestrates heatmap render: display overrides → colormap resolution → Z-range auto-scale → colorbar geometry → PNG output. Parallel to `WorkbenchRenderPipeline`; does not call or extend it. |
| `HeatmapRenderer` | Pure CoreGraphics renderer. Rasterises 2D color grid + colorbar with tick labels + axis labels + title to PNG. No SwiftUI or AppKit. Parallel to `WorkbenchChartRenderer`; must not extend it. |
| `HeatmapPlotLayout` | Geometry type: gridRect, colorbarRect, title position, X/Y axis label positions, colorbar tick label positions. Must not extend or inherit `WorkbenchPlotLayout`. |
| `HeatmapColorScale` | Color scale computation. V1 minimum: one perceptually-uniform colormap (viridis). Maps a normalised Z value in [0, 1] to a `CGColor`. Lookup is keyed by colormap hint string; unknown hint falls back to viridis. |
| `HeatmapTabRenderState` (or equivalent variant) | Per-tab heatmap display override state. V1 minimum fields: `titleOverride`, `xLabelOverride`, `yLabelOverride`, `zLabelOverride` (colorbar label). Must be a parallel structure to `TabRenderState` — not an extension of it. Whether the final form is a standalone struct, a `TabRenderStateKind` enum variant, or a shared-base approach is an implementation-gate decision (see § Plot Preservation — Heatmap Tab State Boundary above). |

### 2. Existing Types That Must Remain XY-Only in V1

The following types are XY-specific. They must not be extended, subclassed, or modified to handle heatmap data at any point during V1 implementation.

| Type | Why it must not change |
|---|---|
| `WorkbenchPlotPayload` / `WorkbenchPlotSeries` | Carries x/y series arrays and XY axis mapping — wrong shape for a 2D grid. Adding heatmap fields here would couple two unrelated render paths. |
| `WorkbenchRenderPipeline` | Orchestrates series reversal, legend resolution, and series-order checks — all XY-specific operations. Heatmap has no series. |
| `WorkbenchChartRenderer` | CoreGraphics renderer for cartesian line/scatter. Heatmap cells, colorbar, and tick generation are completely different drawing operations. |
| `WorkbenchPlotLayout` | Geometry for cartesian axes, legend rows, tick hit-rects, and point hit-rects. Colorbar rect and grid rect do not fit this structure. |

### 3. Compatibility Rule

Existing workflows that use the Cartesian XY render path (AHE, XY Rotation, 3ω) must continue to render through that path **unchanged**. The heatmap render path runs in parallel and must not alter any shared state or shared type that the XY path depends on. Introducing `HeatmapRenderPipeline` must not add any conditional branch, property, or override field to `WorkbenchRenderPipeline`, `WorkbenchChartRenderer`, or `WorkbenchPlotLayout`.

### 4. Canvas Rule

`WorkbenchPlotCanvas` may be reused for heatmap V1 **as a PNG display shell only**:

- Pass `imageData` = heatmap PNG produced by `HeatmapRenderer`.
- Pass `layout: nil`. With `layout` nil, the canvas disables all XY hit-testing: legend drag, point dot toggle, and hover preview are inactive.
- Copy PNG remains available through the right-click context menu (`onCopyPNG`).
- The colorbar and axis labels are baked into the PNG by `HeatmapRenderer`. No canvas overlay or hit-testing is required in V1.

Do not pass a `WorkbenchPlotLayout` constructed from heatmap data. `WorkbenchPlotLayout` has no colorbar rect and its hit-rect logic is XY-specific. Passing a fake `WorkbenchPlotLayout` to enable canvas interactions is a boundary violation.

### 5. Controls Rule

Do not add heatmap controls to `WorkbenchStandardPlotControls` or `WorkbenchPlotControlsPanel`. Heatmap-only controls (colormap picker, Z-axis label override, color scale range override) belong on a future `HeatmapControls` surface that does not exist in V1. If any shared controls (title override, X/Y label override) are exposed for heatmap tabs, they must be gated by a render-path check so they do not appear alongside the XY-specific controls (render mode picker, tick density, stack offset, series labels, curve reorder) when a heatmap tab is active.

### 6. Preservation Rule

Do not extend `TabRenderState` with heatmap-only fields. `TabRenderState` is XY-specific: its `seriesLabelOverrides`, `seriesOrder`, `legendPoint`, `legendAnchor`, and `hiddenPointLabelIndicesBySeries` fields have no meaning for a heatmap tab. Heatmap tab state must live in a parallel state type (`HeatmapTabRenderState` or a `TabRenderStateKind` enum variant). `TabRenderManager` must never write heatmap override fields into a `TabRenderState` slot, and heatmap state must never be decoded from or encoded into a `TabRenderState` Codable envelope.

### 7. Save/Pack Rule

Full heatmap save/pack compatibility is required for workflow support, but may be staged after initial render tests pass. The boundary is defined now:

- **What serializes**: colormap key, Z-range override (if user-set), title/axis/colorbar label overrides. Owned by Plot System heatmap tab state.
- **What does not serialize**: rendered PNG, `HeatmapPlotLayout`. These are re-derived on restore from `HeatmapPlotPayload`.
- **Boundary**: RSM Assembly pack config serializes the analysis parameters needed to re-derive the heatmap grid. Plot System heatmap tab state serializes display overrides only. The re-entry point between them is `HeatmapPlotPayload` — RSM writes it, Plot System reads it.
- **Implementation gate**: pack/restore codec and `TabRenderManager` restore path for heatmap tab state may be implemented after initial render tests confirm the renderer produces correct output. The boundary above must be respected when that gate opens.

### 8. Test Plan

The following tests are required **before implementation**. They define the acceptance criteria for the V1 render path. No test may be skipped or deferred unless explicitly marked deferred.

| Test | What it verifies |
|---|---|
| `heatmapPayloadEncodingDecoding` | `HeatmapPlotPayload` round-trips through `JSONEncoder`/`JSONDecoder` without data loss; Z-matrix dimensions, axis labels, colormap key, Z-range clamp all survive. |
| `colorScaleLinearMapping` | `HeatmapColorScale` maps Z=zMin → colormap[0], Z=zMax → colormap[1.0], Z midpoint → correct midpoint color for linear scale. |
| `colorScaleLogMapping` | `HeatmapColorScale` applies log normalization correctly when log scale is requested; Z values below the minimum are clamped rather than producing NaN. |
| `colorbarTickGeneration` | `HeatmapPlotLayout` or `HeatmapRenderPipeline` produces a reasonable number of tick values (3–7) spanning the Z range; ticks are human-readable (nice numbers). |
| `rendererOutputNonEmptyPNG` | `HeatmapRenderer.renderPNG(payload:)` returns non-empty `Data` with PNG signature bytes for a minimal 2×2 grid payload. |
| `xyRegressionXYRendererUnchanged` | `WorkbenchChartRenderer`, `WorkbenchRenderPipeline`, and `WorkbenchPlotLayout` produce byte-identical output before and after `HeatmapRenderer` is added to the project. No XY rendering code is modified. |
| `canvasSmokeTestHeatmapImageDataNilLayout` | `WorkbenchPlotCanvas` initialized with `imageData` = valid heatmap PNG and `layout` = nil renders without crashing, displays the image, and does not show legend drag or point dot hit-targets. |
| `preservationStateDoesNotPollutXYTabRenderState` | After a heatmap render cycle, existing `TabRenderState` instances for XY tabs retain their original `seriesOrder`, `legendPoint`, `seriesLabelOverrides`, and `hiddenPointLabelIndicesBySeries` values unchanged. |

### 9. Explicit Non-Goals for V1

The following capabilities are **out of scope** for Heatmap V1. Implementing any of them before the gate that specifically authorizes them is a scope violation.

- RSM workflow code — no RSM Swift files are created or modified in V1.
- Cell hit-testing — no click-to-read-Z-value interaction.
- Contour overlays.
- Line cuts (1D profile extraction from a 2D grid).
- Peak fitting on heatmap data.
- Interactive cursor (crosshair readout).
- Q-space support or axis transformation.
- Multiple colormap options in the controls UI (V1 ships viridis; the picker is future).
- Colorbar drag or repositioning.
- Interactive color scale range adjustment via UI (V1 auto-scales; manual range override is future).

---

## Interaction Split

This section defines the authoritative split between the canvas surface and the controls surface.

### Plot Display / Canvas — canonical interactions

| Interaction | Mechanism | Owner |
|---|---|---|
| Legend drag | Pointer drag inside legend frame → `onLegendDrag` callback → `TabRenderManager.updateLegendPoint` | Canvas / Plot Preservation |
| Point dot toggle | Tap on dot hit-target → `onTogglePointLabelVisibility` callback → `TabRenderManager.togglePointLabelVisibility` | Canvas / Plot Preservation |
| Copy PNG | Right-click → scale submenu → `onCopyPNG` callback; 2x reuses cached data (fast path), 1x/3x re-renders | Canvas |
| Hover preview | Mouse-over related-chart thumbnails displayed inline on canvas | Canvas |

The canvas must not host any text input field, font size picker, tick density stepper, or style override widget. These belong in Plot Controls.

### Plot Controls — canonical editing surfaces

| Control | Binding target | State owner |
|---|---|---|
| Title override (per-tab inline) | `TabRenderState.titleOverride` via `TabRenderManager.updateTitleOverride` | Plot Preservation |
| X-axis label override | `TabRenderState.xLabelOverride` via `TabRenderManager.updateXLabelOverride` | Plot Preservation |
| Y-axis label override | `TabRenderState.yLabelOverride` via `TabRenderManager.updateYLabelOverride` | Plot Preservation |
| Legend label override (per-series) | `TabRenderState.seriesLabelOverrides` via `TabRenderManager.updateSeriesLabel` | Plot Preservation |
| Title font size | Global Plot Defaults (`titleFontSize`) | Shared across workflows |
| Axis font size | Global Plot Defaults (`axisTitleFontSize`) | Shared across workflows |
| Tick font size | Global Plot Defaults (`tickLabelFontSize`) | Shared across workflows |
| Legend font size | Global Plot Defaults (`legendFontSize`) | Shared across workflows |
| Point-label font size | Global Plot Defaults (`pointLabelFontSize`) | Shared across workflows |
| X tick density | `chartStyleOverrides[tickTargetX]` | Plot Preservation (shared transport) |
| Y tick density | `chartStyleOverrides[tickTargetY]` | Plot Preservation (shared transport) |

Plot Controls binds to these targets through the existing `onStyleOverrideChange` / `WorkbenchChartStyle` path or through direct `TabRenderManager` update calls. The sidebar controls panel is the single authoritative edit surface for all of the above.

**Render-path scope**: All controls in the table above assume XY render path semantics. Controls that reference series (legend labels, render mode, series order) and XY geometry (tick density, stack offset) must not be shown when the active tab uses a heatmap render path. See [§ Heatmap Render Path — Plot Controls Classification](#heatmap-render-path-gate-82-architecture) for the authoritative render-path breakdown.

### Global Plot Defaults

Global Plot Defaults are shared across workflows and inherited by every workflow renderer.

Owned keys:

- `titleFontSize`
- `axisTitleFontSize`
- `tickLabelFontSize`
- `legendFontSize`
- `pointLabelFontSize`
- `plotFontName`
- `plotBoldFontName`

Rules:

- These keys are not workflow semantics.
- A change in one workflow must be visible in the others.
- They are persisted at the app/workbench level, not in workflow pack config.
- When present in legacy workflow overrides, they must be treated as shared defaults and removed from workflow-local chart-style state.


## Universal Rules (all workflows)

- Plot canvas is a workflow-independent shell — legend, edit, and interaction behaviors apply uniformly to all workflows.
- Plot canvas never mutates render geometry; series order is applied before render in the workflow shell / controls path.
- Stack offset range default: `0...1.6` unless user specifies otherwise.
- Series render mode (line / scatter / line+scatter) selectable per workflow, applied uniformly to all series.
- Chart title is not bold.
- Axis titles (x/y) centered on plot drawing area, not the full image.
- Font sizes are shared global plot defaults; tick density (x/y) remains workflow-local style transport.
- Chart style settings stored in `styleParams`, parsed via `WorkbenchChartStyle`.
- Right-click → Copy PNG submenu: 1x / 2x / 3x scale options. 2x reuses cached `imageData` (fast path); 1x/3x re-render via pipeline.

## Point Labels (scatter series)

- Font size configurable via the font size picker in Plot Controls.
- Tap on dot toggles label visibility per-point; persists across Pack save/load.
- Current scope: 3ω Scaling Law tab (the only tab using point labels). Other workflows opt in at zero cost.

## Legend

- Legend dimension auto-inference: data-driven priority chain — temperature > field = device = harmonic = substrate = energy = pressure = growthTemperature > thickness. Ambiguous or indeterminate cases produce warnings.
- Legend-visual consistency: stacked charts guarantee legend top entry = visually highest curve. Controlled by `reverseSeriesForLegend` flag on payload; applied uniformly in render pipeline.
- `LegendDimensionResolver` is owned by the Plot System. It resolves legend labels from `WorkbenchPlotSeries.metadata`, and `WorkbenchRenderPipeline` invokes it when `payload.legendDimension` is nil. Workflow renderers must populate metadata such as `temperature`, `field`, `harmonic`, `device`, `substrate`, and `thickness`; workflow-local legend guessing is forbidden.
- `tickTargetX` and `tickTargetY` are approximate tick targets, not exact tick counts. Preferred UI wording is `X tick target`, `Y tick target`, or `Approx. X ticks`, `Approx. Y ticks`.

## Opt-In Capability — Curve Reorder

- Curve drag-to-reorder is canvas-level opt-in, gated by `seriesReorderable` flag in the workflow payload.
- Currently enabled: 3ω stacked R(1ω)/R(3ω) charts only.
- Drag in legend area pans all curves; drag outside legend area reorders a specific curve. Guide line shows target position during drag.
- Right-click → Reset Curve Order returns to workflow default.
- Order persists in AnalysisPack save/load.

### Series Reorder Contract

Rules:
1. `WorkbenchPlotCanvas` is display and legend interaction only — it does not own or trigger reorder.
2. Series reorder belongs to the Plot Controls Module (`WorkbenchSeriesOrderPanel`) and the workflow store, not the canvas.
3. Reorder identity is resolved by the shared `WorkbenchSeriesOrderKeyResolver` (sourceRef first, then sampleID, then original index). Reorderable payloads must still carry a non-empty `sourceRef` on every series; duplicate `sampleID` values may exist and only act as compatibility fallbacks.
4. Reorder intent is `updateSeriesOrder([seriesKey])` emitted by `WorkbenchSeriesOrderPanel`.
5. The render pipeline applies order; UI code does not mutate render geometry.
6. Direct curve hit-test reorder is forbidden.

Data shape: reorderable payloads must carry a non-empty `sourceRef` on every series. Manifest labels must stay aligned with the legend labels produced by the render pipeline.

Boundary note: `WorkbenchSeriesOrderKeyResolver` is Plot System-owned. Its role is to provide stable identity keys for series reordering and restore. `WorkbenchSeriesOrderPanel` and `WorkbenchRenderPipeline` consume it automatically. Workflow renderers must provide stable `sourceRef` and/or `sampleID` values on `WorkbenchPlotSeries`; workflow-local series key logic is forbidden.

Enforcement:
- `WorkflowWorkspaceShell` routes reorder intent from Plot Controls into the store.
- `WorkbenchSeriesOrderPanel` emits bottom-to-top keys from the current series rows.
- `ThreeOmegaWorkspaceStore+Plotting.swift` owns per-workflow order state and render reapplication.
- `WorkbenchRenderPipeline` applies order checks and refuses to rewrite geometry from UI state.

Review checklist for changes touching reorder:
- Did this change touch Canvas for reorder? → Reject.
- Did this change use `sampleID` as row identity? → Reject.
- Did this change mutate render output from UI? → Reject.
- Did this change preserve bottom-to-top semantics? → Verify.

## Plot Preservation Module

Plot Preservation is a member of this Module Group. It owns tab override state (`TabRenderState`: title, axis labels, legend position, series order, label overrides) and render output consistency across all rerender paths.

Full contract: [`SHELL_BLOCKS.md` § Plot Preservation Module](../SHELL_BLOCKS.md#plot-preservation-module-phase-4).

Boundary: no module other than Plot Preservation may write `TabRenderState` override fields or call `clearStates()`. Other Plot System modules consume plot output through `TabRenderManager` projections only.

## Tests

- `V531SeriesRenderModeTests` — Codable migration, ChartStyle parsing, axis alignment
- `V534LegendDimensionResolverTests` — resolver priority, tolerance, ambiguity, pipeline reversal, backward decode
- `V535PointLabelVisibilityTests`, `V535TabRenderStatePackTests`, `V535ScopeGateTests` — point label toggle logic, Pack Codable, payload-capability gate
- `V535CopyPNGScaleMenuTests` — scale array alignment, output pixel dimensions, 2x determinism
- `V536CurveDragOrderTests` — alignSeriesOrder, TabRenderState Codable, pipeline mismatch detection, hitTestSeries hit/miss/nil-id
- `V710PlotControlsMigrationTests` — stale override auto-reset on identity change, legendPoint/seriesOrder survival, legend rename/order coexistence, TabRenderState pack round-trip, legend layout width with renamed labels, canvas structural guards (removed callbacks absent, kept callbacks present)

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift` — workflow-independent plot shell; interaction, hit-test, legend overlay, Copy PNG
- `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift` — tracks mouse position and computes hit-test results on the plot canvas
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift` — sidebar controls panel for plot display settings (style, ranges, offsets)
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift` — standard plot control bindings and default implementations shared across workflows
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift` — reorders stacked series from plot controls by per-series identity keys
- `Sources/SpinLabApp/Workbench/V3/WorkbenchSeriesOrderKeyResolver.swift` — shared series identity key resolver for order persistence and compatibility
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift` — observable store for plot display state (style params, visibility, range overrides)
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift` — shared chart renderer producing plot layer output from workflow analysis data
- `Sources/SpinLabApp/UseCases/LegendDimensionResolver.swift` — resolves legend item dimensions for auto-sizing the plot legend overlay
- `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift` — manages tab-based rendering pipeline switching in the plot canvas
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartStyle.swift` — chart style parameters (colors, line widths, markers) shared across all workflows
- `Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift` — layout parameters for plot canvas regions (margins, axes, legend areas)
- `Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift` — render pipeline coordinating chart layers from workflow analysis results
- `Sources/SpinLabApp/Workbench/V3/WorkbenchSeriesOrderKeyResolver.swift` — shared series identity key resolver for stable reorder/restore identity

## Historical Notes

### Title Template — Three-Layer Model (Gate 7.8 audit)

The chart title is resolved through three independent layers with distinct owners:

1. **Default title template** (Layer 1): Workflow Assembly-owned. Each workflow declares its own token set that reflects which metadata fields are meaningful for that physics context. Layer 1 defaults must not migrate into common Plot Controls.
2. **Editable title template state** (Layer 2): Currently workflow-store-owned (`titleTemplate: String` on each store, serialized in each pack config). Candidate boundary debt for future common Plot Controls module ownership. Extraction gate: backward-compatible `CodingKeys` in all three pack configs plus boundary tests proving title template changes do not mutate search/selection/ingestion state. No code moves until both gates are met.
3. **Inline title override** (Layer 3): `TabRenderState.titleOverride`. Per-tab canvas-edit override. Already correctly owned by Plot Preservation / `TabRenderManager`.

Resolution order: Layer 2 template → `WorkbenchTitleResolver.resolve(template:tokens:)` → Layer 3 `titleOverride` per tab.

### stackOffsetMultiplier / minGapFraction (Gate 7.8 audit)

`stackOffsetMultiplier` and `minGapFraction` are Workflow Assembly-owned plot semantic parameters. Their defaults and applicability differ per workflow. They are exposed through the common `WorkbenchStandardPlotControls` View via Bindings, but the View does not own the values. These fields must not be reclassified as generic Plot System-owned state without an explicit MODULE_BOUNDARIES.md revision at a future gate.

### WorkbenchPlottingStore — currentRunTrace (resolved Gate 7.8D)

`currentRunTrace` has been removed from `WorkbenchPlottingStore`. It now lives in `WorkbenchRunTraceProviding`, a dedicated protocol for the Warning Display / Run Trace module. `WorkbenchWorkspaceProviding` composes `WorkbenchPlottingStore` and `WorkbenchRunTraceProviding`, so consumers that access `currentRunTrace` through the workspace-level protocol are unaffected. Plot System no longer exposes run-trace state through the plot protocol.

### Main Board Layout is Outside Plot System (Gate 7.8 audit)

`WorkflowWorkspaceShell`, `WorkflowWorkspaceLeftColumn`, and `WorkflowWorkspaceRightColumn` are Main Board shell files that own column structure and ViewBuilder slot placement. They are not Plot System components:

- Shell files pass `plotControls` as a slot; they do not construct workflow-specific plot controls themselves.
- Shell files must not import or directly manipulate `TabRenderState` / `TabRenderManager` internals.
- `WorkbenchPlotCanvas` is an interaction and display surface, not a canonical state owner. It must not store `TabRenderState`, `TabRenderManager`, `titleOverride`, `legendPoint`, `seriesOrder`, or workflow store types.
- Any new editing capability goes into Plot Controls, not the canvas.
- `WorkbenchRenderPipeline` and renderers consume input and produce image/layout/manifest output; they must not mutate workflow store state.

### legendAnchor Pack Coverage Gap (Gate 7.8 audit)

`legendAnchor` is stored in `TabRenderManager.legendAnchor` and is serialized by 3ω (`ThreeOmegaPackConfig.plotLegendAnchor`) but not by AHE or XY. This means `legendAnchor` resets to `""` after pack restore for AHE and XY. This is a documentation gap only — no pack schema change is required at Gate 7.8.

### Canvas Inline Edit Callbacks — Removed (Gate 7.10)

The following canvas callbacks and their `EditTarget` machinery were removed in Gate 7.10 as part of the controls-first migration. Plot Controls now owns all text and style editing surfaces.

| Removed callback | Previous mechanism | Current owner |
|---|---|---|
| `onEditTitle` | Click on `layout.titleHitRect` → `EditTarget.title` → inline text field | Plot Controls (`LabelOverrideField`) |
| `onEditXLabel` | Click on `layout.xLabelHitRect` → `EditTarget.xLabel` → inline text field | Plot Controls (`LabelOverrideField`) |
| `onEditYLabel` | Click on `layout.yLabelHitRect` → `EditTarget.yLabel` → inline text field | Plot Controls (`LabelOverrideField`) |
| `onEditLegendLabel` | Click on legend row hit-target → `EditTarget.legend` → inline text field | Plot Controls (per-chip rename in `WorkbenchSeriesOrderPanel`) |
| `onFontSizeChange` (title/axis/tick) | Click on title/axis/tick-label hit-target → `fontSizePicker` popover | Plot Controls (font size pickers in `WorkbenchPlotControlsPanel`) |
| Tick density stepper in canvas | `tickDensityStepper` inside the inline `editPanel` | Plot Controls (tick density steppers in `WorkbenchPlotControlsPanel`) |
| `onStyleOverrideChange` via canvas | Style override written from canvas-local `editPanel` | Plot Controls (`onStyleChange` callback in `WorkbenchPlotControlsPanel`) |

The `EditTarget` enum, `editingElement` state, `editPanel`, `fontSizePicker`, `tickDensityStepper`, `editorDismissLayer`, and all associated hit-rect handling were removed from `WorkbenchPlotCanvas`. `WorkflowWorkspaceResultArea` no longer passes these callbacks.

Canonical canvas interactions that must remain: `onLegendDrag`, `onTogglePointLabelVisibility`, `onCopyPNG`, hover preview.

### Canvas Controls Migration — Completed (Gate 7.10)

The controls-first migration was completed in Gate 7.10:

1. ✅ Font size pickers and tick density steppers moved to `WorkbenchPlotControlsPanel`.
2. ✅ Title / x-axis / y-axis label override fields added as `LabelOverrideField` widgets.
3. ✅ Per-series legend label rename added as inline pencil-button + `TextField` per chip in `WorkbenchSeriesOrderPanel`.
4. ✅ All legacy canvas editing callbacks removed from `WorkbenchPlotCanvas` and `WorkflowWorkspaceResultArea`.
5. ✅ `EditTarget` enum, `editingElement` state, and all inline edit panel machinery removed from `WorkbenchPlotCanvas`.
6. ✅ Stale text override auto-reset: `TabRenderManager.applyPipelineOutput` detects chart identity change and clears title/axis/seriesLabel overrides while preserving `legendPoint` and `seriesOrder`.
7. ✅ Legend label width regression fixed: `WorkbenchPlotLayout` now measures display (renamed) label width for drag preview geometry.
8. ✅ Axis label color fix: renderer now emits black axis labels instead of gray.
9. ✅ Gate 7.10 targeted tests added: `V710PlotControlsMigrationTests` (20 tests).
