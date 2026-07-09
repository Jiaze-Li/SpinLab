# Workbench — Plot System Module Group

> **Module Group**: Plot Display / Canvas, Plot Controls, and Plot Preservation. This document is the active Plot System entry contract. Render-path-specific details live in dedicated module docs.

## Start Here

Read this file for the shared Plot System rules. Then route to the specific render-path or ownership document:

| Task | Read next |
|---|---|
| Add or move plot controls | `PLOT_CONTROLS_SPLIT_PLAN.md` |
| Change Heatmap rendering, colorbar, colormap, or heatmap display state | `HEATMAP_RENDER_PATH.md` |
| Change DualAxis rendering, controls, display state, export, or 3ω Temperature Dependence adapter | `DUAL_AXIS_CONTROL_CONTRACT.md` |
| Change pack / restore behavior | `../PACK_RESTORE.md` |
| Decide capability ownership or physical home | `../MODULE_CAPABILITY_MAP.md`; `../PHYSICAL_MODULE_LAYOUT.md` |

## Terminology

| Term | Meaning |
|---|---|
| **Cartesian XY render path** | Plot System line/scatter renderer: `WorkbenchPlotPayload` → `WorkbenchRenderPipeline` → `WorkbenchChartRenderer` → `WorkbenchPlotLayout`. |
| **XY Rotation workflow** | A measurement workflow. Do not call it the “XY render path”. |
| **Heatmap render path** | Plot System grid/Z-value renderer. Contract lives in `HEATMAP_RENDER_PATH.md`. |
| **DualAxis render path** | Plot System two-independent-Y-axis renderer. Control/state contract lives in `DUAL_AXIS_CONTROL_CONTRACT.md`. |
| **Workflow Assembly** | Workflow-owned semantic layer: parsing, physics, unit conversion, default labels, workflow-specific payload construction. |

Workflows currently using the Cartesian XY render path include AHE, XY Rotation, 3ω, and IV. Heatmap and DualAxis are parallel render paths, not extensions of Cartesian XY.

## Module Group Structure

Plot System has three sub-modules:

| Sub-module | Owns | Must not own |
|---|---|---|
| Plot Display / Canvas | rendered PNG display, direct graphic interaction callbacks, Copy PNG / Copy PDF (direct copy of current imageData/pdfData, no re-render) | persistent display override state, text/style editing widgets, workflow physics |
| Plot Controls | text/style/range/editing surfaces and control layout | workflow physics, unrelated module state |
| Plot Preservation | per-tab display override state and render-output consistency | scientific analysis state, search/selection state, workflow semantics |

`TabRenderManager` is the extracted Plot Preservation owner for Cartesian XY tab state and shared rendered-output state. Other modules may consume its projections but must not mutate its canonical state directly.

## Render Path Separation

Plot System render paths are parallel. Do not merge their payloads, layouts, or state shapes.

| Render path | Payload | Layout/state shape | Notes |
|---|---|---|---|
| Cartesian XY | `WorkbenchPlotPayload` / `WorkbenchPlotSeries` | `WorkbenchPlotLayout`; `TabRenderState` | line/scatter/stacked series, legend, point labels, series reorder |
| Heatmap | `HeatmapPlotPayload` | `HeatmapPlotLayout`; heatmap display state | grid/Z values, colorbar, colormap, Z range |
| DualAxis | `DualAxisPlotPayload` | `DualAxisPlotLayout`; DualAxis display-state snapshot | one X axis, left/right Y axes, left/right series families |

Forbidden shortcuts:

- Do not extend `WorkbenchPlotPayload` with heatmap or dual-axis fields.
- Do not pass fake `WorkbenchPlotLayout` values for non-XY charts.
- Do not store heatmap or dual-axis-only fields inside Cartesian XY-only `TabRenderState` without an explicit preservation redesign.
- Do not let renderers infer physics from workflow ID, tab name, axis-label text, or sample metadata.

## Canvas Contract

`WorkbenchPlotCanvas` is a workflow-independent, render-path-independent display shell. It does not know whether the active tab is Cartesian XY, DualAxis, Heatmap, or RSM — it only consumes a `WorkbenchGraphicExportArtifacts` envelope (`pngData`/`pdfData`) handed to it by the caller.

It may:

- display `exportArtifacts.pngData`;
- copy `exportArtifacts.pngData` / `exportArtifacts.pdfData` to the pasteboard via Copy PNG / Copy PDF;
- route allowed direct graphic interactions such as legend drag or point-label toggle when the active render path supports them;
- show hover previews when a valid layout/hit contract exists.

It must not:

- perform rendering;
- compute axes, ticks, color scales, or layout geometry;
- host text fields, font pickers, tick steppers, range editors, style editors, or workflow-specific controls;
- own persistent display override state.

## Controls Contract

Plot Controls are the primary editing surface for text, style, ranges, and display options.

Control modules are classified by scope:

- **Common controls**: reusable text/font/layout controls.
- **Cartesian XY controls**: line/scatter, tick density, X/Y range, series appearance, stack controls, series order, point tags.
- **Heatmap controls**: colormap, Z/colorbar label, color scale, Z range.
- **DualAxis controls**: title/X/left-Y/right-Y labels, X/left-Y/right-Y ranges, left/right series style, marker policy, axis color policy.
- **Workflow-owned controls**: geometry, fitting, methods, file-specific selectors, physics-specific panels.

Full ownership split: `PLOT_CONTROLS_SPLIT_PLAN.md`.

### Plot Controls Shell Blocks

These are layout shells, not plot-family control sets. Do not reinvent them per workflow.

| Shell | Scope | Used by |
|---|---|---|
| `WorkbenchPlotNavigationStrip` | Tab picker + stack offset slider + gap input, one row. Workflow-agnostic — not owned by CartesianXY, DualAxis, or Heatmap specifically. | AHE/IV/XY/RT inline via `WorkbenchStandardPlotControls`; 3ω via the thin `ThreeOmegaWorkspaceTabStrip` wrapper so it can sit above tab-specific plot types (e.g. temperatureDependence) that don't use `WorkbenchStandardPlotControls`. |
| `WorkbenchPlotControlsPanel` | Current Cartesian XY plot-controls shell: hosts caller content, then appends Draw/Range/Font/Series/`extraContent` in a fixed order. | `WorkbenchStandardPlotControls`. Not (yet) a universal shell for Heatmap/DualAxis — treat it as CartesianXY-scoped until a real Heatmap/DualAxis shell need proves otherwise. |
| `WorkbenchStandardPlotControls` | The CartesianXY stacked-curve adapter: composes Navigation Strip + title/grid/label-override rows + CartesianXY common controls (via `WorkbenchPlotControlsPanel`) + one workflow-owned `extraContent` slot. | AHE, IV, XY Rotation, RT. |
| `WorkbenchPlotControlsPluginSection` | Divider-delimited slot for workflow/tab-specific controls only (AHE Hc/R_AHE overrides, IV channel/basis, 3ω geometry/fit, RAHE method, XY toggles). Not for result/status/info display. | Workflow-owned `extraContent`/plugin content across AHE/IV/3ω/RAHE/XY. |

Result/status/info display (3ω Scaling Status, Fit Results, Last Run Trace, and similar) stays in the right result column. It must not be routed through `WorkbenchPlotControlsPluginSection`, even when it appears near workflow-specific controls.

DualAxis and Heatmap are their own plot-family control candidates (see `DUAL_AXIS_CONTROL_CONTRACT.md` and `HEATMAP_RENDER_PATH.md`). Do not force CartesianXY Draw/Line/Scatter controls onto them; they may still reuse common title/tick/font/range concepts through the Common controls layer.

## Preservation Contract

Display overrides are not workflow analysis state.

Rules:

1. Cartesian XY tab display state belongs to Plot Preservation (`TabRenderManager` / `TabRenderState`).
2. Heatmap and DualAxis display state must use render-path-appropriate state or snapshot types.
3. Renderers read captured inputs and return image/layout/warnings. They do not mutate stores or preservation state.
4. Pack/restore serializes display state and analysis state through their declared owners; rendered PNG bytes are generally re-derived unless a specific export path says otherwise.

## Copy Graphic Artifact Contract

Copy PNG and Copy PDF are global `WorkbenchPlotCanvas` capabilities, not a Cartesian XY-only feature. Both directly copy current rendered artifacts through a shared, render-path-agnostic envelope. There is no copy-time re-render path for either, for any render path.

### The export envelope

- `WorkbenchGraphicExportArtifacts` (`Sources/.../PlotSystem/Export/WorkbenchGraphicExportArtifacts.swift`) is a plain `{ pngData: Data?, pdfData: Data? }` struct. It carries no render-path identity.
- `WorkbenchPlotCanvas` takes a single `exportArtifacts: WorkbenchGraphicExportArtifacts` parameter. It displays `exportArtifacts.pngData` and copies whichever of `pngData`/`pdfData` the user asks for. It must not accept separate `imageData`/`pdfData` parameters, and it must not infer which render path produced the artifacts.
- Each caller assembles the envelope from its own render-path output. `WorkbenchWorkspaceProviding` provides a default `activeExportArtifacts` composed from `activeImageData`/`activePdfData`, so Cartesian XY/DualAxis workflow stores (all backed by `TabRenderManager`/`TabRenderOutput`) get it for free. RSM assembles it directly from `renderedImageData`/`renderedPdfData` (RSM does not use `TabRenderManager`).
- `WorkbenchPasteboardWriter` remains the only pasteboard-writing helper (`copyPNG(_:)` / `copyPDF(_:)`). Nothing else in Plot System calls `NSPasteboard` directly.
- Copy PDF is omitted from the canvas context menu whenever `exportArtifacts.pdfData` is nil.

### Per-render-path artifact responsibility

Every render path produces its own `pngData`/`pdfData`; Cartesian XY, DualAxis, Heatmap, and RSM payloads/layouts/state are never merged to share this feature.

| Render path | pngData | pdfData | Notes |
|---|---|---|---|
| Cartesian XY | `WorkbenchChartRenderer.renderPNG` | `WorkbenchChartRenderer.renderPDF` — true vector | Both reuse the identical `drawCanvas(...)` path from the same `renderPayload`/`options`/`chartStyle`/`layout`. `WorkbenchRenderPipeline.Output` carries both; `TabRenderOutput.pdfData` stores it beside `imageData`. |
| DualAxis | `DualAxisChartRenderer.renderPNG` | `DualAxisChartRenderer.renderPDF` — true vector | Same pattern: both reuse `drawCanvas(...)`. `DualAxisRenderPipeline.Output` carries both; the 3ω Temperature Dependence adapter threads `pdfData` into `TabRenderOutput` like any other tab. |
| Heatmap / RSM | `HeatmapRenderer.renderPNG` | `HeatmapRenderer.renderPDF` — true vector | `drawCanvas(...)` draws every grid cell as an individual `CGContext` fill-rect and every axis/colorbar element as real paths/text — there is no raster image embedded anywhere in the renderer, so redirecting the same draw calls into a PDF-writing `CGContext` produces genuine vector output, not a raster heatmap wrapped in a PDF container. Large grids trade off PDF file size (one path object per cell), not fidelity. `HeatmapRenderPipeline.Output` carries both; RSM stores `pdfData` in `renderedPdfData` beside `renderedImageData` (RSM has no `TabRenderState`/hit-testing layout, so this is the one render path outside `TabRenderManager`). |

Do not claim vector PDF for any render path without verifying its `drawCanvas`-equivalent never embeds a `CGImage`/`NSImage` — if a render path is ever rewritten to rasterize part of its output (e.g. a future performance optimization that pre-rasterizes the heatmap body), its PDF story must be re-audited and this table updated; `pdfData` must go back to nil rather than silently becoming a raster-in-PDF hybrid without saying so here.

### Shared rules

- Live plot render uses `WorkbenchPlotRenderScale.display` (3x) by default for all Cartesian XY workflows (AHE, XY Rotation, 3ω, IV, RT), so the screen already shows a high-resolution render. PDF is vector and resolution-independent, so pixel scale does not apply to it.
- `WorkbenchPlotCanvas`'s Copy PNG and Copy PDF context menu actions write `exportArtifacts.pngData` / `exportArtifacts.pdfData` straight to the pasteboard via `WorkbenchPasteboardWriter`. They must not call a render or export callback.
- What is on screen — series order, legend, labels, axis overrides, hidden series — is exactly what gets copied by both Copy PNG and Copy PDF, because nothing is re-derived at copy time.

## Universal Display Rules

- Chart title is not bold.
- Axis titles are centered on the plot drawing area, not the full image.
- Font sizes are shared global plot defaults, not workflow physics.
- Tick targets are approximate targets, not guaranteed exact counts.
- Plot canvas interactions must not mutate render geometry directly.
- Workflow renderers own domain-to-payload conversion and unit/display labels.

## Legend and Series Reorder

Legend auto-resolution and series reorder are Cartesian XY capabilities unless another render path defines its own equivalent.

Rules:

- `LegendDimensionResolver` reads `WorkbenchPlotSeries.metadata`; it must not parse filenames, sidecars, search hits, or workflow-local state.
- Reorderable Cartesian XY payloads need stable series identity (`sourceRef` preferred, `sampleID` as compatibility fallback).
- Series reorder intent comes from Plot Controls, not direct canvas geometry mutation.
- The render pipeline applies order; UI code does not rewrite geometry.

## Legend Drag Contract Debt

Current legend drag ownership is intentionally split across Plot System layers, but the shared drag math now lives in one Plot System module:

- `PlotLegendDragGeometry` / `PlotLegendDragEngine` own the shared legend-drag geometry and clamping math.
- `WorkbenchPlotCanvas` owns legend-drag detection and preview feedback.
- `TabRenderManager` owns per-tab `legendPoint` state.
- Render paths are responsible for consuming the captured legend point when they build layout.

The current implementation still has workflow-specific renderer code paths that must remember to apply `legendPoint` explicitly. That is acceptable as a short-term compatibility bridge, but it is architectural debt. Long term, legend consumption should flow through a shared Plot System render contract so workflows do not manually reapply the same state.

Scope boundaries:

- Heatmap remains excluded from legend drag.
- DualAxis now uses the shared legend-drag geometry adapter; keep future interactions on the same contract instead of adding another canvas-specific path.

## Display-state contract

Plot System generic display controls must not blur workflow ownership boundaries.

Workflow-owned responsibilities:

- parse raw files
- run workflow/domain analysis
- construct source-faithful `manifestPayload`
- construct render-faithful `displayPayload` when hidden, ordered, or stacked rendering is needed
- provide stable series identity metadata

PlotSystem-owned responsibilities:

- `TabRenderState`
- `legendPoint`
- title/x/y label overrides
- series label overrides
- `hiddenSeriesKeys`
- `seriesOrder`
- `axisRangeOverride`
- point-label visibility
- `seriesRenderMode`
- `chartStyleOverrides`
- final `displayPayload` + `TabRenderState` → imageData/layout render contract

Required invariant:

- For a valid non-empty Cartesian `displayPayload`, render output must include non-nil `imageData` and non-nil `layout`.

Required invariant:

- `manifestPayload` and `displayPayload` have different roles:
  - `manifestPayload` = full/source-safe payload for save/pack/library
  - `displayPayload` = render-faithful payload after display filtering, order, and offset

Required invariant:

- `legendPoint` has one shared meaning: normalized legend box origin relative to `plotRect`.
- This applies to XY and DualAxis.
- Heatmap/RSM is excluded unless explicitly adapted.

Forbidden pattern:

- A workflow renderer must not return:
  - `imageData == nil`
  - `layout == nil`
  - `displayPayload != nil`
  for a valid non-empty renderable Cartesian payload.

Forbidden pattern:

- Custom render paths must not manually omit `TabRenderState` fields.
- If a custom path exists, it must use a shared renderer builder or service that applies the full display-state snapshot.

Developer checklist before modifying chip / legend / display controls:

- Which workflows are touched?
- Does the change affect `manifestPayload`, `displayPayload`, or both?
- Does every touched workflow still produce `imageData` / `layout`?
- Does every touched custom render path consume the full `TabRenderState` snapshot?
- Are hidden, order, and rename flows tested against stable identity keys?
- Is heatmap intentionally excluded?
- Is dual-axis adapter behavior still consistent with XY `legendPoint` semantics?

## Code Map

### Shared / Cartesian XY Plot System

- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Canvas/WorkbenchPlotCanvas.swift` — PNG display shell and direct interaction callbacks.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Canvas/PlotCanvasMouseTracker.swift` — pointer tracking and hit-test support for supported layouts.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchPlottingStore.swift` — plot interaction contracts and Cartesian XY plot-state protocols.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift` — Cartesian XY payload/result contracts.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Pipeline/WorkbenchRenderPipeline.swift` — Cartesian XY render pipeline.
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift` — Cartesian XY CoreGraphics renderer.
- `Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift` — Cartesian XY layout geometry.
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartStyle.swift` — Cartesian XY chart style.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Preservation/TabRenderManager.swift` — Cartesian XY tab display state and active rendered output.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Legend/LegendDimensionResolver.swift` — Cartesian XY legend dimension resolver.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Legend/PlotLegendDragGeometry.swift` — shared legend drag geometry and clamp helper.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/SeriesOrder/WorkbenchSeriesOrderPanel.swift` — Cartesian XY series order UI.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/SeriesOrder/WorkbenchSeriesOrderKeyResolver.swift` — stable series identity keys.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Export/WorkbenchGraphicExportArtifacts.swift` — render-path-agnostic `{ pngData, pdfData }` envelope consumed by `WorkbenchPlotCanvas`.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Export/WorkbenchPasteboardWriter.swift` — direct PNG/PDF-to-pasteboard writer; no rendering.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/*` — common text/font/tick controls.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/WorkbenchPlotControlsPluginSection.swift` — divider-delimited slot for workflow-specific controls only; not for result/info display.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/*` — Cartesian XY controls.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotNavigationStrip.swift` — shared tab/stack/gap row; workflow-agnostic shell, not CartesianXY-only in spirit even though it currently lives in this folder.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift` — current CartesianXY plot-controls shell (caller content + Draw/Range/Font/Series/extraContent); not yet a universal shell for other render paths.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls.swift` — CartesianXY stacked-curve adapter combining Navigation Strip + label overrides + common controls + workflow plugin slot.

### Heatmap

See `HEATMAP_RENDER_PATH.md`.

### DualAxis

See `DUAL_AXIS_CONTROL_CONTRACT.md`.

## Tests

Start with:

- `V531SeriesRenderModeTests`
- `V534LegendDimensionResolverTests`
- `V535PointLabelVisibilityTests`
- `V535TabRenderStatePackTests`
- `V535ScopeGateTests`
- `V535CopyPNGScaleMenuTests`
- `V536CurveDragOrderTests`
- `V710PlotControlsMigrationTests`

Render-path-specific tests live with their corresponding workflow or render-path implementation.

## Historical Notes

Historical gate records and removed implementation details should live under `docs/architecture/workbench/history/`, not in this active module contract. If a past gate detail becomes a current rule, restate it above as a short rule rather than pasting the old implementation record here.
