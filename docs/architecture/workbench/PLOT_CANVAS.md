# Workbench — Plot Canvas

> Render layer: workflow-independent plot shell、style params、legend dimension auto-inference、Copy PNG 倍率、point label、curve reorder opt-in。

## Universal Rules (all workflows)

- Plot canvas is a workflow-independent shell — legend, edit, and interaction behaviors apply uniformly to all workflows.
- Plot canvas never mutates render geometry; series order is applied before render in the workflow shell / controls path.
- Stack offset range default: `0...1.6` unless user specifies otherwise.
- Series render mode (line / scatter / line+scatter) selectable per workflow, applied uniformly to all series.
- Chart title is not bold.
- Axis titles (x/y) centered on plot drawing area, not the full image.
- Font sizes (title, axis, tick, legend) and tick density (x/y) configurable via Chart Style disclosure panel.
- Chart style settings stored in `styleParams`, parsed via `WorkbenchChartStyle`.
- Right-click → Copy PNG submenu: 1x / 2x / 3x scale options. 2x reuses cached `imageData` (fast path); 1x/3x re-render via pipeline.

## Point Labels (scatter series)

- Font size configurable via tap on label.
- Tap on dot toggles label visibility per-point; persists across Pack save/load.
- Current scope: 3ω Scaling Law tab (the only tab using point labels). Other workflows opt in at zero cost.

## Legend

- Legend dimension auto-inference: data-driven priority chain — temperature > substrate = energy = pressure > thickness. Ambiguous or indeterminate cases produce warnings.
- Legend-visual consistency: stacked charts guarantee legend top entry = visually highest curve. Controlled by `reverseSeriesForLegend` flag on payload; applied uniformly in render pipeline.

## Opt-In Capability — Curve Reorder

- Curve drag-to-reorder is canvas-level opt-in, gated by `seriesReorderable` flag in the workflow payload.
- Currently enabled: 3ω stacked R(1ω)/R(3ω) charts only.
- Drag in legend area pans all curves; drag outside legend area reorders a specific curve. Guide line shows target position during drag.
- Right-click → Reset Curve Order returns to workflow default.
- Order persists in AnalysisPack save/load.
- Boundary details and guardrails: [`SERIES_ORDER_BOUNDARY.md`](SERIES_ORDER_BOUNDARY.md)

## Tests

- `V531SeriesRenderModeTests` — Codable migration, ChartStyle parsing, axis alignment
- `V534LegendDimensionResolverTests` — resolver priority, tolerance, ambiguity, pipeline reversal, backward decode
- `V535PointLabelVisibilityTests`, `V535TabRenderStatePackTests`, `V535ScopeGateTests` — point label toggle logic, Pack Codable, payload-capability gate
- `V535CopyPNGScaleMenuTests` — scale array alignment, output pixel dimensions, 2x determinism
- `V536CurveDragOrderTests` — alignSeriesOrder, TabRenderState Codable, pipeline mismatch detection, hitTestSeries hit/miss/nil-id

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift` — workflow-independent plot shell; interaction, hit-test, legend overlay, Copy PNG
- `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift` — tracks mouse position and computes hit-test results on the plot canvas
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift` — sidebar controls panel for plot display settings (style, ranges, offsets)
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift` — standard plot control bindings and default implementations shared across workflows
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift` — reorders stacked series from plot controls by per-series identity keys
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift` — observable store for plot display state (style params, visibility, range overrides)
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift` — shared chart renderer producing plot layer output from workflow analysis data
- `Sources/SpinLabApp/UseCases/LegendDimensionResolver.swift` — resolves legend item dimensions for auto-sizing the plot legend overlay
- `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift` — manages tab-based rendering pipeline switching in the plot canvas
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartStyle.swift` — chart style parameters (colors, line widths, markers) shared across all workflows
- `Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift` — layout parameters for plot canvas regions (margins, axes, legend areas)
- `Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift` — render pipeline coordinating chart layers from workflow analysis results
