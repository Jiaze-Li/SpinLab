# Plot Actions Boundary Audit

**Date:** 2026-07-01  
**Scope:** Clear Plot / clearPlot / reset-plot behavior across Workbench workflows  
**Purpose:** Determine whether Clear Plot should be extracted into a reusable Workbench-level module boundary, and identify the smallest safe extraction plan.  
**Status:** audit only. No runtime behavior changed.

## Summary

Clear Plot is already rendered in a shared Workbench shell, not inside XY-specific controls.

- Physical placement: `WorkflowWorkspaceResultArea` renders `WorkbenchResultHeaderShell`, and that shell renders the `Clear Plot` button.
- Ownership split: the shared shell owns button placement and enablement; each workflow store owns clear semantics.
- Current safe boundary: a reusable button strip can be extracted without unifying clear semantics, as long as the store still owns the actual reset logic.

The main constraint is semantic divergence. `clearPlot()` does not mean the same thing in every workflow:

- Some workflows clear only render output and analysis state.
- Some also clear workflow-local overlay state.
- Some keep display overrides across clear.
- Some have separate `clearResults()` behavior for search-state cleanup.

That means the reusable module should stay shallow: shared layout and shared button affordance only, with store-owned callbacks.

## Answers

### 1. Where is Clear Plot currently physically rendered?

Clear Plot is rendered in the shared result header:

- [`WorkbenchResultHeaderShell.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift#L22-L54)
- [`WorkflowWorkspaceResultArea.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultArea.swift#L13-L31)
- `WorkflowWorkspaceRightColumn` mounts that result area for every workflow.

So Clear Plot is not rendered by XY controls, DualAxis controls, or Heatmap controls.

### 2. Is it owned by XY controls, workflow view, or a shared shell?

It is owned by a shared shell.

- `WorkflowWorkspaceResultArea` wires `onClearPlot: { store.clearPlot() }`.
- `WorkbenchResultHeaderShell` owns the button layout and disabled state.
- The workflow view only supplies the store and shell slots.

### 3. Which workflows expose Clear Plot?

All current workbench workflows that use `WorkflowWorkspaceResultArea`:

- AHE
- IV
- RT
- XY Rotation
- 3ω
- RSM

There is no workflow-local Clear Plot button in any of the plot control panels.

### 4. For each workflow, what does Clear Plot actually clear?

#### AHE

`clearPlot()` clears:

- plot output and render state
- trace
- warning log
- ingestion result
- persistence outcome
- pending metric overrides
- extracted metrics cache
- analysis/save messages
- cached input files
- active pack ID
- related charts cache

It does not clear:

- cached search results
- selection state
- manager-level plot defaults such as grid or legend anchor

Relevant files:

- [`AHEWorkspaceStore.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift#L203-L222)
- [`V333AHEWorkspaceStoreIsolationTests.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Tests/SpinLabAppTests/V333AHEWorkspaceStoreIsolationTests.swift#L60-L90)

#### IV

`clearPlot()` clears:

- plot output and render state
- trace
- warning log
- ingestion result
- persistence outcome
- analysis/save messages
- title-token cache
- cached sample keys and input files
- related charts cache
- active pack ID
- tab render state

It does not clear:

- cached search results
- selection state

Relevant file:

- [`IVWorkspaceStore.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift#L119-L137)

#### RT

`clearPlot()` clears:

- chart/analysis output
- trace
- warning log
- RT analysis results
- related charts cache
- cached sample keys and input files
- active pack ID
- tab render state

It does not clear:

- cached search results
- selection state

Relevant file:

- [`RTWorkspaceStore.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/RTWorkspaceStore.swift#L159-L177)

#### XY Rotation

`clearPlot()` clears:

- ingestion result
- trace
- warning log
- analysis/save messages
- title-token cache
- cached sample keys and input files
- related charts cache
- active pack ID
- tab render state

It does not clear:

- cached search results
- selection state
- baseline / detrend toggles
- phi-offset overrides

Relevant files:

- [`XYRotationWorkspaceStore.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift#L188-L206)
- [`XYRotationWorkspaceView.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift#L12-L80)

#### 3ω

`clearPlot()` clears:

- ingestion result
- scaling result
- transport-derived status
- refresh state
- trace
- warning log
- analysis/save messages
- title-token cache
- overlay runtime and overlay snapshots
- related charts cache
- cached sample keys, conditions, and input files
- cached RT file path
- active pack ID
- tab render state

It does not clear:

- cached search results
- selection state
- RT search state
- heatmap/dual-axis display state in the current `temperatureDependenceDisplayState`

`clearResults()` is separate and clears the RT search/session surface:

- cached search results
- numeric display cache
- RT query
- persisted RT query
- RT search results and message
- RT search progress and popover state
- selected RT hit

Relevant files:

- [`ThreeOmegaWorkspaceStore+Selection.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift#L8-L46)
- [`ThreeOmegaWorkspaceStore+Analysis.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift#L1-L82)
- [`ThreeOmegaWorkspaceStore+Pack.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift#L1-L71)
- [`ThreeOmegaWorkspaceView.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift#L43-L216)

#### RSM

`clearPlot()` clears:

- parsed dataset
- rendered image data
- trace
- warning log
- analysis/save messages
- cached sample keys and input files
- active pack ID
- persistence outcome

It does not clear:

- cached search results
- selection state
- heatmap display state

That means RSM keeps its heatmap overrides (`titleOverride`, labels, color scale, z-range, tick counts, colorbar toggle) across Clear Plot.

Relevant files:

- [`RSMWorkspaceStore.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift#L160-L179)
- [`HeatmapTabRenderState.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapTabRenderState.swift#L1-L32)

### 5. Does any workflow rely on Clear Plot being inside XY-specific controls?

No.

Evidence:

- Clear Plot is rendered in the shared result header, not the plot-controls panel.
- `WorkbenchStandardPlotControls` only owns the XY/stacked controls row set; it does not render Clear Plot.
- 3ω’s workspace-level tab strip is about navigation only; it is separate from Clear Plot.

Relevant files:

- [`WorkbenchStandardPlotControls.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls.swift#L5-L171)
- [`ThreeOmegaWorkspaceView.swift`](/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-v5.5.5/Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift#L43-L165)

### 6. Can the UI button/action be safely extracted without unifying the clear semantics?

Yes.

The safe seam is button layout, not reset behavior:

- shared module owns the button group and disabled logic
- workflow store owns `clearPlot()`
- no workflow semantics move into the shared module

The extraction is safe only if the shared module stays callback-driven and never decides what clear means.

### 7. What is the smallest reusable module boundary?

Proposed module name: `WorkbenchPlotActionStrip`

Ownership:

- shared module owns button layout only
- workflow store owns clear behavior

Proposed API:

```swift
clearPlotTitle: String = "Clear Plot"
canClearPlot: Bool
onClearPlot: () -> Void
```

Optional future actions can be added later, but not in this audit stage.

This is smaller than moving the entire result header. It keeps the current `WorkbenchResultHeaderShell` shape intact while allowing the action cluster to be reused or restyled later.

## Immediate Adoption

The current Clear Plot action can be adopted immediately by:

- AHE
- IV
- RT
- XY Rotation
- 3ω
- RSM

Reason: all of them already flow through the same shared result header.

## Should Not Adopt Yet

No current workflow should be blocked from the shared Clear Plot action strip.

What should not be generalized yet is a broader `Reset Plot` module or a “clear everything” composite action, because the semantics are still workflow-specific:

- 3ω has distinct RT search/session state and overlay state
- RSM keeps heatmap display state across Clear Plot
- AHE has pre-persist override state that is not the same as plot output

That is a semantic boundary, not a UI placement boundary.

## Risks

- Over-generalizing the action strip into a workflow reset API would hide real differences in 3ω and RSM.
- Moving clear semantics into the shared module would couple the shell to analysis lifecycle behavior.
- Conflating `clearPlot()` and `clearResults()` would break search/session persistence and selection behavior.

## Tests Required

Keep or add characterization tests that lock down the seam:

- A shared-shell smoke test that Clear Plot remains in `WorkbenchResultHeaderShell`.
- Workflow boundary tests proving `clearPlot()` does not clear selection or search state.
- Workflow-specific tests proving clear/reset differences remain local:
  - AHE pending override state
  - 3ω RT search/session reset via `clearResults()`
  - RSM heatmap display state persistence across `clearPlot()`

Existing coverage already points in the right direction:

- `V333AHEWorkspaceStoreIsolationTests`
- `V537AnalysisLifecycleBoundaryTests`
- `V5115ThreeOmegaWorkspaceStoreCharacterizationTests`

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift` - shared action row and Clear Plot button placement
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultArea.swift` - shared result area wiring for every workflow
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRightColumn.swift` - mounts the shared result area in the shell
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` - `clearPlot` / `clearResults` contract
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` - AHE clear semantics
- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift` - IV clear semantics
- `Sources/SpinLabApp/Features/Workbench/RTWorkspaceStore.swift` - RT clear semantics
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` - XY Rotation clear semantics
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift` - 3ω plot clear vs RT-session clear split
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` - 3ω workspace-level tab strip and plot-controls composition
- `Sources/SpinLabApp/Features/Workbench/RSMWorkspaceStore.swift` - RSM clear semantics and heatmap persistence split
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls.swift` - XY plot controls; no Clear Plot button
- `Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapTabRenderState.swift` - heatmap display state that survives RSM clearPlot
