# Workbench - Series Order Boundary

> Series reorder is a shell/control concern, not a canvas concern. The boundary keeps render geometry immutable from UI interaction code.

## Rules

1. `WorkbenchPlotCanvas` is display and legend interaction only.
2. Series reorder belongs to the Workflow Shell and Plot Controls, not the canvas.
3. Reorder identity is the per-series `sourceRef` key, not `sampleID`.
4. Reorder intent is `updateSeriesOrder([seriesKey])`.
5. The render pipeline applies order; UI code does not mutate render geometry.
6. Direct curve hit-test reorder is forbidden.

## Enforcement Points

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` routes reorder intent from Plot Controls into the store.
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift` emits bottom-to-top keys from the current series rows.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift` owns the per-workflow order state and render reapplication.
- `Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift` applies order checks and refuses to rewrite geometry from UI state.

## Expected Data Shape

- Reorderable payloads must carry a non-empty `sourceRef` on every series.
- Duplicate `sampleID` values may still exist, but they do not define reorder identity.
- Manifest labels must stay aligned with the legend labels produced by the render pipeline.

## Review Checklist

- Did this change touch Canvas for reorder? Reject.
- Did this change use `sampleID` as row identity? Reject.
- Did this change mutate render output from UI? Reject.
- Did this change preserve bottom-to-top semantics?

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift` — coordinates sourceRef-based series reordering from plot controls
