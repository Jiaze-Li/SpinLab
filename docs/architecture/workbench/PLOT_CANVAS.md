# Workbench — Plot Canvas

> Render layer: workflow-independent plot shell、style params、legend dimension auto-inference、Copy PNG 倍率、point label、curve reorder opt-in。

## Universal Rules (all workflows)

- Plot canvas is a workflow-independent shell — legend, edit, and interaction behaviors apply uniformly to all workflows.
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

## Tests

- `V531SeriesRenderModeTests` — Codable migration, ChartStyle parsing, axis alignment
- `V534LegendDimensionResolverTests` — resolver priority, tolerance, ambiguity, pipeline reversal, backward decode
- `V535PointLabelVisibilityTests`, `V535TabRenderStatePackTests`, `V535ScopeGateTests` — point label toggle logic, Pack Codable, payload-capability gate
- `V535CopyPNGScaleMenuTests` — scale array alignment, output pixel dimensions, 2x determinism
- `V536CurveDragOrderTests` — alignSeriesOrder, TabRenderState Codable, pipeline mismatch detection, hitTestSeries hit/miss/nil-id

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift` (728 lines — ⭐ large file; shared plot shell, interaction, hit-test, Copy PNG)
- `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift`
- `Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift` (604 lines — shared chart renderer)
