# Workbench — Shell and Lifecycle

> Shell layer: `WorkflowWorkspaceShell` 协议、6 阶段 lifecycle、4 ViewBuilder 槽、3 条 [HARD] 不变式、WorkspaceStore contract。

## Shell Layout

All workflow workspaces share a single generic shell (`WorkflowWorkspaceShell`) that owns the full two-column layout. Workflow-specific content is injected via ViewBuilder slots.

Shell layout (fixed for all workflows):
- Left column: title bar → search section → plot controls slot → left extra slot → results list
- Right column: result header (save/update) → status area → plot canvas → right extra slot → trace panel → warning panel

## Shell-Driven Lifecycle (6 stages)

Shell-driven behavior is uniform across all workflows:

| Stage | Shell action | Store call |
|---|---|---|
| Search | Renders search bar + action bar; executes search | `WorkbenchFeatureStore.runWorkflowMeasurementSearch()` |
| Select | User selects results from list | (selection state in store) |
| Analyze | Renders Analyze button | `store.runAnalysis()` → ingests + renders + calls `commitRunTrace()` |
| Save | Renders Save to Library button | `store.persistToLibrary()` |
| Pack load | Renders Load Pack popover | `store.restoreFromPack()` → uses `_rerenderActiveTab()` / `_rerenderAllTabs()` |
| Clear | Renders Clear / Clear Plot buttons | `store.clearResults()` / `store.clearPlot()` |

## [HARD] Invariants

- **Trace is committed only in `runAnalysis()`**. Restore and rerender paths (`restoreFromPack`, `_rerenderActiveTab`, `_rerenderAllTabs`) must never call `commitRunTrace()`.
- **`PackResult` must include `ingestionResult`** so that restore can rerender without re-ingestion.
- **New workflows must use the shell**. Do not build standalone two-column views.

## WorkspaceStore Contract (`WorkbenchWorkspaceProviding`)

Inherits: `WorkbenchPlottingStore`, `AnalysisPackProviding`, `ActiveChartProviding`

Must implement: selection, execution, rerender, clear, trace, persistence.

Default implementations provided: `appendWarning()`, `commitRunTrace()`.

Warning panel: shell-level `WorkbenchWarningLog` container coalesces identical (source, message) pairs. Reruns of analyze / load / scaling never stack duplicate entries. New workflows inherit the rule via `WorkbenchWorkspaceProviding`. (v5.3.5)

## ViewBuilder Slots

| Slot | Purpose | Example |
|---|---|---|
| `searchExtra` | Additional search fields (e.g. RT file picker) | `ThreeOmegaRTSearchField` / `EmptyView` |
| `plotControls` | Tab picker, stack offset, grid toggle, style panel | `WorkbenchStandardPlotControls` or custom |
| `leftExtra` | Left column bottom panels (geometry, overrides) | `ThreeOmegaGeometryPanel` / `EmptyView` |
| `rightExtra` | Right column extra panels (scaling results) | `ThreeOmegaScalingResultPanel` / `EmptyView` |

## Code Map

Primary files for this layer:

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` (567 lines — ⭐ large file; shell layout + slot wiring + lifecycle orchestration)
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` (`WorkbenchWorkspaceProviding` protocol + default implementations)
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` (workflow view registration)
- `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` (top-level Workbench region entry)
- `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` (workflow selector)
- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` (877 lines — ⭐ large file; Workbench store, search, condition projection)
- `Sources/SpinLabApp/App/State/WorkbenchState.swift` (Workbench state value types)

Not in this layer: workflow workspace stores (→ `WORKFLOW_CONTRACTS.md`), plot canvas (→ `PLOT_CANVAS.md`).
