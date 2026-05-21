# Workbench — Shell Blocks and Workflow Boundaries

> Shell composition layer: `WorkflowWorkspaceShell` -> reusable `ShellBlock`s -> workflow-specific slots -> workflow function.

## Purpose

Workbench uses a compositional shell model so shared UI structure can be reused without collapsing workflow semantics into one large runtime.

This document defines the boundary between:

- shared shell composition
- reusable shell blocks
- workflow-specific slots
- workflow functions
- standard result envelopes

It is intentionally narrower than `SHELL_AND_LIFECYCLE.md`, `PLOT_CANVAS.md`, `WORKFLOW_CONTRACTS.md`, `ARTIFACT_PERSISTENCE.md`, and `EXTENSION_BOUNDARIES.md`.

## Layered Model

The intended layering is:

`WorkflowWorkspaceShell`
-> `ShellBlock`
-> workflow-specific `Feature`
-> workflow `Function`

Interpretation:

- `WorkflowWorkspaceShell` owns layout and block composition only.
- `ShellBlock` is a reusable UI unit with a focused concern.
- `Feature` is workflow-owned UI state or a workflow-specific control surface.
- `Workflow Function` is the scientific / analytical implementation for that workflow.

## Why We Avoid One Large Runtime

Workbench workflows are similar in shell structure but not in scientific meaning.

We avoid a monolithic runtime because:

- AHE, XY Rotation, and 3ω share lifecycle shape but differ in analysis semantics.
- UI reuse is useful at the block level, not at the domain-logic level.
- A large runtime would force unrelated workflows into one abstraction and make future SOT support harder, not easier.
- The shell should stay readable as a composition layer, not become a second application state.

The goal is reuse by feature block, not by centralizing every workflow behavior behind one orchestrator.

## Core Definitions

### Shared Shell

The `WorkflowWorkspaceShell` container that:

- owns the two-column layout
- arranges shell blocks
- wires workflow-specific slots into the layout
- delegates all workflow semantics to stores / functions

It does not interpret scientific data.

### Shell Blocks

Reusable shell units that each own one stable UI concern. They are compositional building blocks, not a workflow runtime.

Current block inventory:

- `SearchShell`
- `SelectionShell`
- `AnalyzeLifecycleShell`
- `ResultHeaderShell`
- `PlotShell`
- `PlotControlsShell`
- `SaveShell`
- `PackRestoreShell`
- `TraceShell`
- `WarningShell`
- `StatusShell`

### Workflow-specific Slots

Slots are injected into the shared shell, but their semantics belong to a workflow.

Examples:

- AHE override panels
- XY phi / detrend controls
- 3ω RT / geometry / fit / scaling controls
- future SOT parameter controls

Slots are not shell blocks. They are workflow-owned content hosted by the shell.

### Workflow Function

The workflow function is the scientific layer that owns:

- parsing and ingestion
- calculations and inference
- payload construction
- metrics and warnings
- workflow-specific pack content

Shell blocks may present its output, but they must not own its semantics.

### Standard Result

Standard Result is the shell-facing contract that lets a workflow analysis be rendered, saved, restored, and traced without the shell needing to know the workflow's physics.

Minimum responsibilities:

- carry the ingestion snapshot needed for restore
- expose renderable payload / layout state
- carry warnings and trace data
- carry pack config / result data
- allow tab-level rerender and save/restore flows

Standard Result is an envelope, not a domain model replacement.

## Shell Blocks

### SearchShell

Owns the shared measurement search surface and query presentation.

### SelectionShell

Owns selection state presentation and selection actions.

### AnalyzeLifecycleShell

Owns the shared analyze / rerun / lifecycle gating surface.

### ResultHeaderShell

Owns the shared result action header, including clear, save, and load-pack entry points.

### PlotShell

Owns the shared plot canvas surface and render presentation.

### PlotControlsShell

Owns controls that affect plot presentation or tab rendering.

This block is common infrastructure, not workflow semantics. It should host shared plot configuration patterns, but it must not absorb workflow-specific meaning.

### SaveShell

Owns save-to-library presentation and save entry points.

### PackRestoreShell

Owns pack load / restore presentation and restore entry points.

### TraceShell

Owns last-run trace presentation.

### WarningShell

Owns warning presentation and warning log display.

### StatusShell

Owns current status and lightweight progress presentation.

## PlotControlsShell vs Workflow Slots

`PlotControlsShell` is for controls that are structurally common across workflows.

Workflow-specific slots are for controls that are semantically tied to one workflow.

Examples:

- Shared pattern: tab switcher, legend-related display control, generic plot style toggles
- Workflow slot: AHE metric override, XY phi offset / detrend, 3ω RT and fit-range control

The rule is simple:

- if the control changes generic plot presentation, it belongs to `PlotControlsShell`
- if the control changes workflow meaning, it belongs to a workflow-specific slot

## What Stays Workflow-Specific

### AHE

Must stay workflow-specific:

- channel inference
- axis override
- metric extraction
- AHE-specific override panels
- AHE-specific pack content

### XY Rotation

Must stay workflow-specific:

- phi offset
- center / detrend
- dual-tab semantics
- XY-specific control panels
- XY-specific pack content

### 3ω

Must stay workflow-specific:

- RT selection
- geometry
- fit ranges
- scaling law
- RAHE method
- overlays
- multi-tab render semantics
- 3ω-specific pack content

These behaviors define scientific meaning and should not be folded into shell blocks.

## Future SOT

Future SOT should plug into the same shell block model as a complex workflow.

That means:

- the shell should not learn SOT physics
- SOT should adapt its workflow function output into Standard Result
- SOT-specific controls should live in workflow-specific slots
- reusable shell blocks should render lifecycle, save, restore, trace, warning, and status concerns

If SOT needs a special representation, it should add an adapter or workflow-specific result layer, not expand the shell into domain logic.

## Migration Path

The migration direction is incremental:

1. Keep `WorkflowWorkspaceShell` as the shell composer.
2. Extract or formalize shell blocks one by one.
3. Keep workflow-specific slots separate from reusable blocks.
4. Standardize the shell-facing result surface.
5. Preserve workflow functions as the scientific owner for AHE, XY Rotation, 3ω, and future SOT.

The immediate design goal is to make composition explicit without forcing a monolithic runtime abstraction.

## Incremental Migration Rule

Future refactors should stay incremental instead of jumping straight into one large runtime or one giant `Standard Result`.

1. Start from the existing workflows first:
   - AHE
   - XY Rotation
   - 3ω
2. Extract one shell-facing boundary at a time.
3. Test after each extraction before moving to the next one.
4. Prefer read/adaptor surfaces before execution lifecycle helpers.
5. Do not introduce one giant `Standard Result` struct.
   Prefer a minimal shell-facing result surface / adapter capability.
6. Recommended extraction order:
   - Phase 0: baseline tests
   - Phase 1: active result read surface
   - Phase 2: warning / trace surface
   - Phase 3: tab output / active plot surface
   - Phase 4: save input surface
   - Phase 5: pack restore / rerender surface
   - Phase 6: thin lifecycle helper
7. Recommended workflow order:
   - AHE first
   - XY Rotation second
   - 3ω last as the stress test
8. Scientific logic must remain workflow-specific.

## Cross-Links

- [Shell and Lifecycle](SHELL_AND_LIFECYCLE.md)
- [Plot Canvas](PLOT_CANVAS.md)
- [Workflow Contracts](WORKFLOW_CONTRACTS.md)
- [Artifact Persistence](ARTIFACT_PERSISTENCE.md)
- [Extension Boundaries](EXTENSION_BOUNDARIES.md)

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` — composes shared workflow shell layout and injects workflow slots
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` — defines the workspace provider contract for shell composition
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` — owns AHE workflow workspace state and rendering lifecycle
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` — renders the AHE workflow workspace shell
- `Sources/SpinLabApp/Features/Workbench/OverlaySnapshot.swift` — stores detached overlay state for restored Workbench packs
- `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift` — tracks mouse position for the shared plot canvas
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaRenderedPlots.swift` — carries rendered 3ω plot data and layouts
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkbenchTab.swift` — defines the 3ω workflow tab identity set
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` — owns 3ω workflow workspace state and orchestration
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift` — runs 3ω ingestion analysis and trace commit
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift` — manages 3ω fit range editing state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift` — snapshots 3ω manifest payloads and input identities
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` — builds and restores 3ω analysis pack state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift` — saves 3ω charts and metrics to library artifacts
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift` — exposes 3ω plot editing and chart access
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift` — manages 3ω RT search and restore state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RelatedCharts.swift` — loads 3ω related result references
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift` — rerenders 3ω tabs from stored tab state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` — computes 3ω scaling results from frozen ingestion state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift` — manages 3ω measurement selection and clearing state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` — renders the 3ω workflow workspace shell
- `Sources/SpinLabApp/Features/Workbench/UnitTagEditor.swift` — edits unit-tag values in Workbench forms
- `Sources/SpinLabApp/Features/Workbench/WorkbenchEnvironment.swift` — supplies Workbench-specific environment capabilities
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift` — renders the shared Workbench plot canvas
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift` — hosts shared plot controls for Workbench
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift` — defines the shared Workbench plotting contract
- `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` — snapshots shell-facing result state for workflow read paths
- `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift` — presents shared result actions and save/load entry points
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSharedComponents.swift` — groups shared Workbench component declarations
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift` — renders standard shared plot controls
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift` — presents shared status content for workflow workspaces
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift` — provides the Workbench title template field
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTracePanel.swift` — presents last-run trace content for workflow workspaces
- `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` — routes Workbench region content by selected section
- `Sources/SpinLabApp/Features/Workbench/WorkflowHitRow.swift` — renders a measurement search hit row
- `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` — renders the workflow registry selection view
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` — maps workflow IDs to workspace view factories
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` — owns XY Rotation workflow workspace state and orchestration
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` — renders the XY Rotation workflow workspace shell
