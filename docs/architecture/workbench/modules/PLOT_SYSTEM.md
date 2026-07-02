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
| Plot Display / Canvas | rendered PNG display, direct graphic interaction callbacks, Copy PNG surface | persistent display override state, text/style editing widgets, workflow physics |
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

`WorkbenchPlotCanvas` is a workflow-independent display shell.

It may:

- display PNG image data;
- route Copy PNG;
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

## Preservation Contract

Display overrides are not workflow analysis state.

Rules:

1. Cartesian XY tab display state belongs to Plot Preservation (`TabRenderManager` / `TabRenderState`).
2. Heatmap and DualAxis display state must use render-path-appropriate state or snapshot types.
3. Renderers read captured inputs and return image/layout/warnings. They do not mutate stores or preservation state.
4. Pack/restore serializes display state and analysis state through their declared owners; rendered PNG bytes are generally re-derived unless a specific export path says otherwise.

## Export / Copy PNG Contract

Copy PNG and export must be idempotent with respect to the current displayed payload and display state.

Rules:

- Cartesian XY 2x may reuse cached image data as a fast path; 1x/3x should re-render through the pipeline.
- Heatmap and DualAxis export should re-render from payload + display snapshot at the requested scale once their export paths support scaling.
- Export must not re-run workflow analysis or apply non-idempotent workflow transforms.
- If cached image data is used as fallback, the fallback must be explicit and documented.

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
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/*` — common text/font/tick controls.
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/*` — Cartesian XY controls.

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
