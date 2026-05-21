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

- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` — owns 3ω workspace state and task lifetimes
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift` — manages independent 3ω RT search state and restoration
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift` — manages 3ω measurement selection and clearing state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift` — manages 3ω scaling fit range editing state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift` — runs 3ω ingestion analysis and commits run traces
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` — computes 3ω scaling results from frozen ingestion state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift` — rerenders 3ω plot tabs from stored tab state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift` — snapshots 3ω manifest payloads and input identities
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift` — saves active 3ω charts and metrics into library artifacts
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RelatedCharts.swift` — loads 3ω related result references for chart overlays
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` — builds and restores 3ω analysis pack state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift` — implements 3ω plot editing and active chart protocols
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaRenderedPlots.swift` — carries rendered 3ω plot data and layouts
- `Sources/SpinLabApp/Features/Workbench/OverlaySnapshot.swift` — stores detached 3ω overlay data for restored packs
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` — shell layout, slot wiring, and lifecycle orchestration for all workflow workspaces
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` — WorkbenchWorkspaceProviding protocol and default slot implementations
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` — maps workflow IDs to their workspace view factory functions
- `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` — top-level Workbench region entry view
- `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` — workflow selector view in the Workbench sidebar
- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` — Workbench store; manages search, condition projection, and analysis lifecycle
- `Sources/SpinLabApp/App/State/WorkbenchState.swift` — Workbench state value types for persistence and cross-store observation

- `Sources/SpinLabApp/App/AppEnvironment.swift` — runtime dependency container; holds all injected services at app startup
- `Sources/SpinLabApp/App/AppError.swift` — unified error type mapping all domain and infrastructure errors to AppError
- `Sources/SpinLabApp/App/AppLogger.swift` — structured logging facade used across all feature regions
- `Sources/SpinLabApp/App/AppVersion.swift` — app version and build metadata constants
- `Sources/SpinLabApp/App/InteractionMemoryStore.swift` — persists and restores interaction state snapshots across sessions
- `Sources/SpinLabApp/App/InteractionSnapshotCoordinator.swift` — coordinates capture and restore of per-feature interaction snapshots
- `Sources/SpinLabApp/App/InteractionSnapshotKeyCodec.swift` — encodes and decodes interaction snapshot keys for persistence
- `Sources/SpinLabApp/App/RootSplitView.swift` — root three-pane split view hosting Inbox, Library, and Workbench regions
- `Sources/SpinLabApp/App/SidebarMenuModel.swift` — sidebar navigation menu state and item model
- `Sources/SpinLabApp/App/SidebarTreeView.swift` — sidebar tree view rendering region navigation hierarchy
- `Sources/SpinLabApp/App/SpinLabAppState.swift` — root app state; class body, stored properties, init, and app-state revision
- `Sources/SpinLabApp/App/SpinLabAppContextProvider.swift` — ArchivedRecordDomainContextAdapter providing domain context to the archived-record pipeline
- `Sources/SpinLabApp/App/SpinLabAppState+Navigation.swift` — navigation dispatch: navigate, openDeepLink, route-path switching
- `Sources/SpinLabApp/App/SpinLabAppState+DrawerMatching.swift` — drawer conflict detection, routing snapshot queries, name-conflict checker wiring
- `Sources/SpinLabApp/App/SpinLabAppState+RepositoryProjection.swift` — repository projection tasks, pending/archived record replacement, migration
- `Sources/SpinLabApp/App/SpinLabAppState+InteractionSnapshot.swift` — interaction snapshot capture, restore, flush, and routing-rules change notification
- `Sources/SpinLabApp/App/SpinLabAppState+InboxImport.swift` — inbox file import, pending-import clearing, condition-rule recompute
- `Sources/SpinLabApp/App/SpinLabAppState+RegistryCoordination.swift` — sample registry load, reload, routing-rule refresh, registry context application
- `Sources/SpinLabApp/App/SpinLabAppState+LibraryCoordination.swift` — library preview load/sync, drawer index application, mutation commit, cache validation
- `Sources/SpinLabApp/App/SpinLabAppState+ImportDeduplication.swift` — import deduplication via path/fingerprint/filename sets and library-path caching
- `Sources/SpinLabApp/App/SpinLabAppState+ApplyPipeline.swift` — apply-selected and apply-all orchestration, progress tracking, outcome finalization
- `Sources/SpinLabApp/App/SpinLabAppState+RoutingPresentation.swift` — pending routing presentation, draft resolution, tag readiness, alert helpers, audit trail
- `Sources/SpinLabApp/App/SpinLabAppState+WorkbenchEntry.swift` — workbench entry points: open pending/archived record, save workbench result
- `Sources/SpinLabApp/App/State/ApplyProgressState.swift` — value type tracking apply-pipeline progress counters
- `Sources/SpinLabApp/App/State/PendingTagReadiness.swift` — enum classifying pending-import tag completeness for apply gating
- `Sources/SpinLabApp/App/SpinLabDataActor.swift` — data actor isolating background I/O from main-actor app state
- `Sources/SpinLabApp/App/SpinLabSidebarMenuProvider.swift` — provides sidebar menu items registered by each region
- `Sources/SpinLabApp/App/State/AppCoordinator.swift` — app-level cross-store coordinator for multi-region workflows
- `Sources/SpinLabApp/App/State/AppRouter.swift` — navigation routing and sheet/alert presentation coordinator
- `Sources/SpinLabApp/App/State/InteractionStateModels.swift` — value types for interaction state serialization and restore
- `Sources/SpinLabApp/Domain/Models.swift` — core domain models: SampleRecord, LibraryItem, DrawerID, and shared value types
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift` — status and warning log area at the bottom of the Workbench shell
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift` — title template text field in the Workbench analysis header
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTracePanel.swift` — trace log panel displaying analysis warnings and run events
- `Sources/SpinLabApp/Persistence/Persistence.swift` — app persistence protocol and LocalJSON file-backed implementation
- `Sources/SpinLabApp/SpinLabApp.swift` — SwiftUI app entry point; wires AppEnvironment and AppState at launch
- `Sources/SpinLabApp/UI/AppColumnShell.swift` — shared two-column layout shell with configurable sidebar and detail panels
- `Sources/SpinLabApp/UI/AppFontScale.swift` — app-wide font scale constants and scale-aware view modifiers
- `Sources/SpinLabApp/UI/AppSpacing.swift` — app-wide spacing constants used across all region layouts
- `Sources/SpinLabApp/UI/CollapsibleSectionHeader.swift` — reusable collapsible section header with disclosure chevron
- `Sources/SpinLabApp/UI/FlowLayout.swift` — wrapping flow layout for dynamic tag and chip collections
- `Sources/SpinLabApp/UI/HoverPopoverModifier.swift` — view modifier presenting a popover on mouse hover
- `Sources/SpinLabApp/UseCases/WorkbenchTitleResolver.swift` — resolves display titles for Workbench analysis sessions

Not in this layer: workflow workspace stores (→ `WORKFLOW_CONTRACTS.md`), plot canvas (→ `PLOT_CANVAS.md`).
