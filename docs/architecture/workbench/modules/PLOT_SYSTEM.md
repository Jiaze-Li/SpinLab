# Workbench — Plot System Module Group

> **Module Group**: groups Plot Display, Plot Controls, and Plot Preservation modules within the Main Board. This document covers Plot System Module Group capabilities: workflow-independent plot shell、style params、legend dimension auto-inference、Copy PNG 倍率、point label、curve reorder opt-in。

## Module Group Structure

Plot System is a module group with three sub-modules:

- **Plot Display**: render output (`tabOutputs`, projections `activeImageData` / `activeLayout` / `activeManifestPayload`), active tab switching, and shared display settings (`showPlotGrid`, `seriesRenderMode`, `chartStyleOverrides`, `legendAnchor`). Canonical owner: `TabRenderManager`.
- **Plot Controls**: user-facing display override input components. `WorkbenchPlotControlsPanel` is the common container View. `WorkbenchStandardPlotControls` is the shared two-row layout for multi-tab stacking workflows (XY Rotation, 3ω). `WorkbenchTitleTemplateField` is the shared title input. AHE uses a workflow-local `AHEPlotControlsPanel` — a legitimate specialization for a single-tab workflow with no curve stacking. Binding targets are either `TabRenderManager`-owned (Plot Preservation) or workflow-store-owned (Assembly-owned display parameters).
- **Plot Preservation**: per-tab display overrides and pack round-trip. `TabRenderState` stores legend position, title/axis/label overrides, series order, and point label visibility. Canonical owner: `TabRenderManager`.

`TabRenderManager` is the **existing extracted** Plot Preservation owner — not a new or proposed module. Its `buildPipelineInput` method assembles `WorkbenchRenderPipeline.Input` from per-tab state and shared display settings for AHE and XY. 3ω does not use `buildPipelineInput`; all 3ω rendering paths capture `tabs.legendAnchor` manually and pass it to `ThreeOmegaPlotRenderer.legendAnchor` directly — a consequence of 3ω's custom renderer architecture, not a boundary violation.

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

### Series Reorder Contract

Rules:
1. `WorkbenchPlotCanvas` is display and legend interaction only — it does not own or trigger reorder.
2. Series reorder belongs to the Plot Controls Module (`WorkbenchSeriesOrderPanel`) and the workflow store, not the canvas.
3. Reorder identity is the per-series `sourceRef` key, not `sampleID`. Duplicate `sampleID` values may exist; they do not define reorder identity.
4. Reorder intent is `updateSeriesOrder([seriesKey])` emitted by `WorkbenchSeriesOrderPanel`.
5. The render pipeline applies order; UI code does not mutate render geometry.
6. Direct curve hit-test reorder is forbidden.

Data shape: reorderable payloads must carry a non-empty `sourceRef` on every series. Manifest labels must stay aligned with the legend labels produced by the render pipeline.

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

## Boundary Notes (Gate 7.8)

### Title Template — Three-Layer Model

The chart title is resolved through three independent layers with distinct owners:

1. **Default title template** (Layer 1): Workflow Assembly-owned. Each workflow declares its own token set that reflects which metadata fields are meaningful for that physics context. Layer 1 defaults must not migrate into common Plot Controls.
2. **Editable title template state** (Layer 2): Currently workflow-store-owned (`titleTemplate: String` on each store, serialized in each pack config). Candidate boundary debt for future common Plot Controls module ownership. Extraction gate: backward-compatible `CodingKeys` in all three pack configs plus boundary tests proving title template changes do not mutate search/selection/ingestion state. No code moves until both gates are met.
3. **Inline title override** (Layer 3): `TabRenderState.titleOverride`. Per-tab canvas-edit override. Already correctly owned by Plot Preservation / `TabRenderManager`.

Resolution order: Layer 2 template → `WorkbenchTitleResolver.resolve(template:tokens:)` → Layer 3 `titleOverride` per tab.

### stackOffsetMultiplier / minGapFraction

`stackOffsetMultiplier` and `minGapFraction` are Workflow Assembly-owned plot semantic parameters. Their defaults and applicability differ per workflow. They are exposed through the common `WorkbenchStandardPlotControls` View via Bindings, but the View does not own the values. These fields must not be reclassified as generic Plot System-owned state without an explicit MODULE_BOUNDARIES.md revision at a future gate.

### WorkbenchPlottingStore — currentRunTrace Debt

`WorkbenchPlottingStore` includes `currentRunTrace: WorkbenchRunTraceProjection?`, which belongs to the Warning Display / Run Trace module (Gate 7.7 target). It was included in the plot protocol only because `WorkflowWorkspaceRightColumn` accesses it through the combined `WorkbenchWorkspaceProviding` protocol. Exit condition: remove from `WorkbenchPlottingStore` at Gate 7.7.

### legendAnchor Pack Coverage Gap

`legendAnchor` is stored in `TabRenderManager.legendAnchor` and is serialized by 3ω (`ThreeOmegaPackConfig.plotLegendAnchor`) but not by AHE or XY. This means `legendAnchor` resets to `""` after pack restore for AHE and XY. This is a documentation gap only — no pack schema change is required at Gate 7.8.

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
