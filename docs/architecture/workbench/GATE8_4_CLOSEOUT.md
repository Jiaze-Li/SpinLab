# Gate 8.4 Closeout — PlotSystem Physical Layout Alignment

Gate 8.4 aligns the Workbench plot-related code architecture with the physical folder layout.

This gate is intentionally scoped to PlotSystem and closely related plot-control boundaries. It does not complete the later workflow-directory migration for AHE, IV, RSM, XY Rotation, or 3ω workflow store/view files.

## Completed Scope

### PlotSystem physical module layout

The following PlotSystem responsibilities now have dedicated physical folders under:

`Sources/SpinLabApp/Workbench/Modules/PlotSystem/`

- `Canvas/`
  - Plot display surface and interaction dispatch.
  - Owns `WorkbenchPlotCanvas.swift` and `PlotCanvasMouseTracker.swift`.

- `Pipeline/`
  - Render pipeline input/output construction.
  - Owns `WorkbenchRenderPipeline.swift`.

- `Preservation/`
  - Per-tab render state preservation and shared rendered-output state.
  - Owns `TabRenderManager.swift`.

- `Contracts/`
  - Plot-facing interaction and result contracts.
  - Owns `WorkbenchPlottingStore.swift` and `WorkbenchResultContracts.swift`.

- `Controls/Common/`
  - Plot controls that are reusable across plot families.
  - Owns shared title/X/Y label controls, font-size controls, tick-count controls, and inline label override fields.

- `Controls/CartesianXY/`
  - Controls that are specific to Cartesian XY line/scatter/stacked plot surfaces.
  - Owns axis range controls, series appearance controls, the Cartesian XY plot controls panel, the standard Cartesian XY controls composer, and title-template editing.

- `Legend/`
  - Legend dimension resolution.

- `SeriesOrder/`
  - Series identity/order resolution and series order UI.

### Plot controls split

Gate 8.4 establishes the following ownership rule:

- Controls usable across plot families belong in `Controls/Common/`.
- Controls meaningful only for Cartesian XY plots belong in `Controls/CartesianXY/`.
- Workflow-specific controls stay workflow-owned or domain-owned and enter shared panels only through explicit host-control slots.

This is why `SharedPlotTextControls`, `SharedPlotFontSizeControls`, `SharedPlotTickCountControls`, and `SharedPlotLabelOverrideField` are Common controls, while `WorkbenchPlotControlsPanel`, `WorkbenchStandardPlotControls`, `WorkbenchAxisRangeControls`, `WorkbenchSeriesAppearanceControls`, and `WorkbenchTitleTemplateField` are Cartesian XY controls.

### Plot store contract split

`WorkbenchPlottingStore.swift` was split from run-trace read access.

Current boundary:

- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchPlottingStore.swift`
  - owns plot interaction contracts and Cartesian XY plot-state contracts.

- `Sources/SpinLabApp/Features/Workbench/WorkbenchRunTraceProviding.swift`
  - owns workspace-level read access to the latest run trace.

`currentRunTrace` is not part of PlotSystem.

### RSM selector placement

`RSMViewSelector.swift` is RSM-specific and lives with the RSM heatmap module:

`Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/RSMViewSelector.swift`

It must not be moved into PlotSystem Common or Cartesian XY controls because it depends on RSM-specific semantics:

- `RSMView`
- `CanonicalRSMDataset`
- view compatibility checks
- recommended RSM view selection

The generic heatmap controls panel stays RSM-agnostic and accepts RSM-specific controls through `hostControls`.

## Explicitly Deferred Scope

Gate 8.4 does not complete workflow physical modularization.

The following files still live under `Sources/SpinLabApp/Features/Workbench/` and are intentionally deferred to a later gate:

- `AHEWorkspaceStore.swift`
- `AHEWorkspaceView.swift`
- `IVWorkspaceStore.swift`
- `IVWorkspaceView.swift`
- `RSMWorkspaceStore.swift`
- `RSMWorkspaceView.swift`
- `XYRotationWorkspaceStore.swift`
- `XYRotationWorkspaceView.swift`
- `ThreeOmegaWorkspaceStore*.swift`
- `ThreeOmegaWorkspaceView.swift`

A future gate should consider moving these into workflow-owned physical folders such as:

- `Sources/SpinLabApp/Workbench/Workflows/AHE/`
- `Sources/SpinLabApp/Workbench/Workflows/IV/`
- `Sources/SpinLabApp/Workbench/Workflows/RSM/`
- `Sources/SpinLabApp/Workbench/Workflows/XYRotation/`
- `Sources/SpinLabApp/Workbench/Workflows/ThreeOmega/`

That migration should be reviewed separately because it changes the physical organization of workflow assemblies rather than PlotSystem internals.

## Historical References

Historical and archived handoff documents may still mention old file paths such as `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift`.

Those references are intentionally not rewritten when they appear under archival or historical documentation. Active architecture maps and source-inspection tests should use the current physical paths.

## Validation

Gate 8.4 closeout was validated with:

- `swift build`
- `swift test --filter V78EPlotSystemStructuralBoundaryTests`
- `swift test --filter V710PlotControlsMigrationTests`
- targeted RSM V78C source tests:
  - `rsmDefinesHeatmapPanel`
  - `rsmColorScaleLabelIsPrimary`
  - `rsmViewSelectorRemainsSpecific`
- architecture coverage pre-commit check

## Closeout Judgment

Gate 8.4 is complete for PlotSystem physical layout alignment.

The PlotSystem module architecture and physical folders are now substantially aligned. Remaining workflow store/view physical migration is known, documented, and intentionally deferred.
