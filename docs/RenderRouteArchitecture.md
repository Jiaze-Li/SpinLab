# Render Route Architecture

Current-state reference for how Workbench plots get from workflow state to pixels.
For the cleanup history that produced this state, see `docs/RenderRouteAudit.md` and
the detailed audits under `docs/archive/render-route-cleanup/`.

## 1. Model

A workflow's job is to produce a **plot payload** (data + minimal presentation intent)
and nothing else — no axis-override bookkeeping, no pipeline construction.

`TabRenderManager` owns **display/control state**: per-tab overrides (title, axis
range/tick overrides, series order, hidden series), shared display settings (grid,
series render mode, chart style, legend anchor), and merging that state into a
renderer `Input` via `preparedDisplayState(...)` + `buildPipelineInput(...)`.
`TabRenderManager` never calls a render pipeline itself — it only assembles `Input`.
The workflow store calls the pipeline's `render(...)`.

Rendering is organized **by plot type**, not by workflow. Three plot types exist
today, each with its own pipeline:

| Plot type | Pipeline | Shape |
|---|---|---|
| Ordinary XY | `WorkbenchRenderPipeline` | One or more line series on a shared coordinate axis |
| Dual-axis | `DualAxisRenderPipeline` | Two Y axes with independent scales sharing one X axis |
| Heatmap | `HeatmapRenderPipeline` | 2D x-y grid with z/color-scale semantics (colormap, colorbar) |

Dual-axis and heatmap are not exceptions to the XY route or leftover custom routes —
they are separate plot types with genuinely different rendering semantics, each with
a pipeline structurally parallel to (not a subclass of) `WorkbenchRenderPipeline`.

## 2. Boundary between layers

```
Workflow store (e.g. ThreeOmegaWorkspaceStore)
  builds a plot payload (WorkbenchPlotPayload / DualAxisPlotPayload / HeatmapPlotPayload)
        │
        ▼
TabRenderManager
  preparedDisplayState(...)   — resolves per-tab overrides against current payload identity
  buildPipelineInput(...)     — merges display state + shared settings into pipeline Input
        │  (XY route only — dual-axis and heatmap build Input directly, see §4)
        ▼
Render pipeline (WorkbenchRenderPipeline / DualAxisRenderPipeline / HeatmapRenderPipeline)
  applies series visibility/order, computes layout, calls the renderer
        │
        ▼
Renderer (WorkbenchChartRenderer / DualAxisChartRenderer / HeatmapRenderer)
  pure CoreGraphics/CoreText/ImageIO — renderPNG / renderPDF from one shared drawCanvas
        │
        ▼
Output (imageData, pdfData, layout) → workflow store → WorkbenchPlotCanvas / export
```

Nothing workflow-specific should live inside a pipeline call. Nothing pipeline- or
renderer-specific should live inside a workflow store.

## 3. Ordinary XY route

Every visible xy-plot-kind tab follows: workflow store builds a payload → a
payload-only accessor (`make*Payload`) → `tabs.buildPipelineInput(...)` →
`WorkbenchRenderPipeline.render(...)`. No workflow-owned code calls
`WorkbenchRenderPipeline.render` from inside a `PlotRenderer` method for any of these
tabs — that pattern (custom `_render`/`_consume` entry points bypassing
`TabRenderManager`) was the obsolete route this cleanup removed (§8.3 of
`docs/RenderRouteAudit.md`).

Workflows/tabs on this route:

- **AHE** — main
- **IV** — 1st/I (voltage), 2nd/I (resistance)
- **RT** — R(T)
- **XYRotation** — Rxx vs φ, Rxy vs φ
- **ThreeOmega** — RAHE, RAHE(1ω) Dev, RAHE(3ω) Dev, Hc, RT, Scaling Law,
  fieldSweep1omega (AHE 1ω), fieldSweep3omega (AHE 3ω)

## 4. Dual-axis route

`ThreeOmega Temperature Dependence` is the sole consumer today. Two entry points
(`renderThreeOmegaTab(.temperatureDependence, ...)` for a full re-render, and
`rerenderTemperatureDependenceForDualAxisControlChange()` for control-only edits)
converge on the same `renderer.renderTemperatureDependence(...)` →
`DualAxisRenderPipeline.render(Input(...))` call. This route builds its `Input`
directly rather than through `tabs.buildPipelineInput(...)`, and uses its own
display-state type (`DualAxisDisplayState`) and persistence field, independent of the
generic `WorkbenchTabDisplayStateSnapshot` XY tabs use. Hidden-series and series-order
concepts don't apply — the payload always has exactly two series (one per axis).

## 5. Heatmap/RSM route

`RSM` heatmap tabs are the sole consumer today. `RSMWorkspaceStore` builds a
`HeatmapPlotPayload` via `RSMHeatmapPayloadBuilder`, then calls
`HeatmapRenderPipeline.render(Input(...))` directly — RSM was built on
`HeatmapRenderPipeline` from the start, so there is no legacy custom-renderer route to
clean up here. Hit-testing (`activeLayout`) is hard-coded `nil` — a documented V1
limitation, not a gap. X/Y axis range overrides don't exist (grid extents are
data-derived); Z-range clamping, tick counts, colormap choice, and colorbar visibility
all work.

## 6. Non-goals

- **Do not force dual-axis or heatmap payloads through the ordinary XY pipeline.**
  They are structurally different plot types (independent-scale second Y axis;
  2D z-grid with colorbar). Routing them through `WorkbenchRenderPipeline` would add
  an adapter layer for routes that are already correctly isolated, not reduce
  complexity.
- Unifying dual-axis or heatmap onto a `TabRenderManager`-mediated path (so they gain
  `buildPipelineInput`-style state merging) is legitimate future work, but only
  justified if a second consumer of either plot type appears. With one consumer each
  today, the added abstraction cost isn't worth it.
