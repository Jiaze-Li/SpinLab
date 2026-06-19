# Workbench - Workflow, Assembly, Main Board, Modules

> First-read architecture overview for the Workbench shell.

## Purpose

This document names the stable top-level model. Detailed contracts live in:

- [MAIN_BOARD_READINESS.md](MAIN_BOARD_READINESS.md)
- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)
- [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md)
- [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md)
- [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md)
- [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md) - implementation-level placement notes only
- `modules/`

## Architecture Model

```
Workflow
└── Workflow Assembly
    └── Main Board
        └── Modules
```

## Workflow

A workflow is the analysis title / analysis type. Examples include AHE, XY Rotation, 3ω, and future SOT.
It is not the Main Board and not a module.

## Workflow Assembly

A Workflow Assembly is the workflow-owned semantic contract for one workflow. It declares workflow-specific differences, overrides, contracts, and ownership; common Main Board and default module behavior stay out of Assembly. Adding a workflow means adding a new Workflow Assembly under that workflow's own docs.

It declares:

- Workflow identity / search hints
- Data / physics mapping
- Analysis pipeline
- Optional workflow contributions
- Plot semantics / overrides
- Validation / warning policy
- Persistence / pack-restore metadata
- Required behavior tests

It does not own:

- Main Board layout
- Readiness
- Search logic
- Selection logic
- Analyze lifecycle logic
- Save / Pack implementation
- Plot module internals

## Modules

A Module is a reusable capability with explicit ownership and read surfaces. Default modules are always present. Optional panels or contributions are declared by the active Workflow Assembly and mounted by the Main Board. Ownership, forbidden mutations, and module-specific boundaries live in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).

## Main Board

The Main Board is the persistent Workbench shell. It owns only readiness, layout, and module mounting. It reads the active Workflow Assembly, mounts or calls modules, and coordinates shell-level decisions across the mounted modules. It does not own scientific workflow logic or workflow assembly content.

## Layout

Layout is pure spatial structure: where things appear. It is implementation-level only. Injection points are shell implementation details, not formal architecture layers. Slot, Region, and Mount Surface are not part of the stable model.

## Cross-Links

- [Main Board Readiness](MAIN_BOARD_READINESS.md)
- [Module Boundaries](MODULE_BOUNDARIES.md)
- [Workflow Assembly](WORKFLOW_ASSEMBLY.md)
- [Extension Boundaries](EXTENSION_BOUNDARIES.md)
- [Workbench Roadmap](WORKBENCH_ROADMAP.md)
- [Main Board layout notes](MAIN_BOARD_LAYOUT.md)
- `modules/MEASUREMENT_SEARCH.md`
- `modules/SELECTION_DENOMINATOR_AUDIT.md`
- `modules/PLOT_SYSTEM.md`
- `modules/PACK_RESTORE.md`
- `workflows/three-omega/THREE_OMEGA_PHYSICS.md`

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` — thin AppColumnShell wrapper that mounts the shared workbench columns
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceLeftColumn.swift` — composes the shared left workspace column around search, controls, and results
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceSearchSection.swift` — mounts the search field, library-root line, and search-adjacent slot content
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift` — routes search, selection, analyze, and pack-load actions from the shared action row
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultsList.swift` — renders the searchable hit list and empty-state messaging
- `Sources/SpinLabApp/Features/Workbench/SelectedHitsTray.swift` — compact tray panel showing selected hit display cards after search results change, with per-row remove and basket clear
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRightColumn.swift` — composes the shared right workspace column around results, traces, warnings, and workflow extras
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultArea.swift` — wires result header, pack loading, and plot canvas presentation for the shared result stack
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceLoadPackPlacement.swift` — centralizes the shared load-pack popover placement for the action and result surfaces
- `Sources/SpinLabApp/Features/Workbench/WorkbenchLoadPackPopover.swift` — presents saved-analysis loading and vault-row editing in the shared pack popover
- `Sources/SpinLabApp/Features/Workbench/WorkbenchWarningPanel.swift` — renders the shared warning log disclosure and empty-state panel
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceStatusBlock.swift` — composes the shared lower-right trace and warning block
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` — owns AHE selection, plot, warning, pack, and render state
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` — mounts the AHE workflow shell and workflow-specific panels
- `Sources/SpinLabApp/Features/Workbench/OverlaySnapshot.swift` — stores decoupled overlay pack data for RAHE rendering
- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift` — owns IV analysis, pack, and render state for the IV workflow assembly
- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceView.swift` — mounts the IV workflow shell and workflow-specific control content
- `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift` — bridges mouse events into plot-canvas drag and tap tracking
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaRenderedPlots.swift` — carries rendered 3ω plot images, layouts, and pipeline warnings
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkbenchTab.swift` — defines 3ω tab identities and stable persistence keys
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift` — runs 3ω selection ingestion, rendering, and trace capture
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift` — manages 3ω fit range rows
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift` — builds 3ω manifest payloads from rendered analysis state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` — builds 3ω pack configs, results, and overlays
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift` — saves the active 3ω chart to Library
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift` — keeps 3ω series ordering and render-order helpers
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift` — manages 3ω RT search selection and sidecar rebuilds
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RelatedCharts.swift` — refreshes 3ω related-chart caches from library indices
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift` — rerenders 3ω tabs and scaling outputs from cached state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` — runs 3ω scaling analysis from geometry and fit ranges
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift` — owns 3ω selection clearing and search-hit toggling
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` — owns core 3ω workspace state, analysis lifecycle, and caches
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` — mounts the 3ω workflow shell and workflow-specific panels
- `Sources/SpinLabApp/Features/Workbench/UnitTagEditor.swift` — edits reusable unit tags inline
- `Sources/SpinLabApp/Features/Workbench/WorkbenchEnvironment.swift` — carries the workbench file-system and library access dependencies
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift` — renders plot images and handles canvas editing and legend drag
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift` — wraps shared plot controls chrome and shell-level draw mode
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift` — defines the shared plot-canvas interaction contract
- `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` — projects workspace state into a read-only shell-facing snapshot
- `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift` — renders the shared result header and save actions
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift` — renders the series-reorder chip layout
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSharedComponents.swift` — documents the split shared workbench component inventory
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift` — composes tab, stack, title, and reorder controls for stacked plots
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift` — renders shared search, plot, and load status messages
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift` — renders the shared title-template input and token hint
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTracePanel.swift` — renders the shared run-trace disclosure
- `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` — switches between registry and workflow workbench screens
- `Sources/SpinLabApp/Features/Workbench/WorkflowHitRow.swift` — renders the shared search-result row
- `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` — renders the workflow registry list and summary pane
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` — defines workspace-view and shell-facing workbench contracts
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSaveCoordinating.swift` — shared async save orchestration protocol; owns the common Task body (outcome, trace, message, refreshRelatedCharts) and the per-workflow didCompleteSave hook
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` — dispatches workflow IDs to workspace views
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` — owns XY Rotation search, analysis, and render state
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` — mounts the XY Rotation workflow shell and offset panel
