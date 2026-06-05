# Workbench - Layout Audit

> Gate 4 audit record. This document evaluates the current shell layout only.
> It prepares Gate 5 Layout Refactor and does not authorize runtime changes,
> module extraction, or semantic reassignment.

## Scope

Audited implementation files:

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTracePanel.swift`
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift`
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`

## Current Layout Map

### Search / Selection Region

Current placement:

- Left column top block in `WorkflowWorkspaceShell`
- Search row in `searchSection`
- Selection actions in `actionBar`
- Result list in `resultsList`

Current content:

- Main search field
- Clear / Search / Select All / Analyze actions
- Optional workflow search-extra slot
- Library root status line
- Selectable measurement rows

Layout note:

- Search state, selection state, and search result semantics are not layout-owned.
- The shell only mounts the controls and routes actions to the workbench store.

### Workflow Contribution Region

Current placement:

- `searchExtra`
- `plotControls`
- `leftExtra`
- `rightExtra`

Current consumers:

- `AHEWorkspaceView`
- `XYRotationWorkspaceView`
- `ThreeOmegaWorkspaceView`

Layout note:

- These are injection surfaces, not stable architecture layers.
- They carry workflow-owned panels into the shared shell without changing ownership.

### Result Header

Current placement:

- Right column top block in `WorkflowWorkspaceShell`
- Implemented by `WorkbenchResultHeaderShell`

Current content:

- Result title row
- Clear Plot / Save Analysis / Update Analysis / Save to Library actions
- Current vault-pack label
- Analysis/save message line
- Warning count annotation

Layout note:

- This is shell chrome plus action routing.
- The save action is routed through the workflow store, while library refresh callbacks stay in the shell.

### Plot Canvas

Current placement:

- Right column, below the result header
- Implemented by `WorkbenchPlotCanvas`

Current content:

- Rendered plot image or empty-state placeholder
- Legend drag interaction
- Inline edit overlays for title, axes, legend labels, point labels, and tick labels
- Copy PNG context menu
- Related-chart hover popover

Metadata surfaces:

- `relatedCharts`
- `libraryRootURL`
- `seriesPayload`
- `seriesLabelOverrides`

Layout note:

- The canvas is display-only.
- It does not own plot semantics, series order policy, or workflow defaults.

### Plot Controls

Current placement:

- Left column, under search / selection
- Implemented by `WorkbenchPlotControlsPanel`
- Workflow-specific controls are injected by the workflow view

Current content:

- Shared plot-control chrome
- Workflow-specific control rows
- Shell-level render-mode picker
- Optional series-order panel via the plot-control shell

Layout note:

- The shell provides the container and shared chrome.
- The workflow owns the meaning of any injected controls.

### Status / Warning / Trace Region

Current placement:

- Right column lower stack in `WorkflowWorkspaceShell`

Current content:

- `WorkbenchTracePanel`
- `WorkbenchWarningPanel`
- Status messaging is currently distributed instead of mounted through one explicit status block

Current status surfaces:

- `searchMessage`
- `analysisMessage`
- `saveMessage`

Layout note:

- `WorkbenchStatusArea` exists but is not currently mounted by the shell.
- Warning and trace are explicit surfaces; status is still partially implicit.

### Save / Pack Controls

Current placement:

- Result header buttons
- Pack-load popover mounted in both columns

Current content:

- Save Analysis / Update Analysis
- Save to Library
- Load pack popover
- Unsaved-analysis confirmation when restoring

Layout note:

- Save is workflow-store routed.
- Pack restore is shell-coordinated and writes back into workbench search state through the explicit restore callback.

### Related Charts / Metadata Surfaces

Current placement:

- Plot canvas hover popover
- Result header pack label
- Trace panel detail rows

Current content:

- Related chart previews
- Matching vault-pack label
- Output image path
- Generated timestamp
- Plot axis mapping

Layout note:

- These are presentation surfaces for existing state.
- They must not become new owners of the underlying metadata.

## Layout-Owned Responsibilities

- Arrange the workbench shell into stable spatial regions
- Mount shared shell chrome and workflow-provided panels
- Route user actions from layout controls to provider/store interfaces
- Keep the shell responsive across the available column structure
- Preserve the current visual grouping of search, plot, and result surfaces
- Present status, warning, trace, and save affordances without reinterpreting their meaning

## Layout Must Not Own

- Search state
- Selection state
- Analysis / physics semantics
- Plot semantic defaults
- Save metadata
- Pack / restore state
- Warning meaning
- Workflow-specific metric definitions
- Tab semantics
- Auxiliary-input meaning

## Module Mount Slots

| Slot | Current runtime carrier | Notes |
|---|---|---|
| Main Search | Left-column `searchSection` | The shell owns placement; the workbench store owns query and results. |
| Selection | Left-column `actionBar` + `resultsList` | Selection actions and row toggles stay wired through the workflow store. |
| Plot System / controls | `plotControls` + `WorkbenchPlotCanvas` | The shell owns placement; the plot system owns render state and edit semantics. |
| Save to Library | `WorkbenchResultHeaderShell` | Save is routed through the workflow store and the library completion callback. |
| Pack / Restore | `WorkbenchLoadPackPopover` | Restore is shell-coordinated and rehydrates search state through the explicit callback. |
| Secondary Input Search optional slot | `searchExtra` | Current 3ω RT search field is the only live instance. |
| Analysis Overlay optional slot | `plotControls` / workflow-local overlay chip area | Current 3ω overlay controls are embedded in the workflow view rather than mounted as a generic slot. Gate 5 may only change mounting; Gate 7.4 owns extraction. |
| Warning / Trace display | Right-column lower stack | Trace and warning are explicit shell surfaces; status remains partially implicit. |

## Workflow Assembly Contribution Slots

| Workflow | Contribution slot | Current implementation note |
|---|---|---|
| AHE | Metric extraction / override contribution | `AHEMetricOverridePanel` and `AHERAHEOverridePanel` remain assembly-owned layout content. |
| XY Rotation | Phi / detrend / centering contribution | `WorkbenchStandardPlotControls` plus `XYRotationPhiOffsetPanel` carry workflow-specific controls. |
| 3ω | Geometry / fit range / scaling contribution | `ThreeOmegaGeometryPanel` is workflow-owned and mounts only in scaling mode. |
| 3ω | Secondary input search contribution | `ThreeOmegaRTSearchField` is the current RT slot instance. |
| 3ω | RAHE / scaling overlay declaration | `ThreeOmegaAddOverlayButton` and overlay chips are workflow-owned assembly content. |

Important:

- Do not classify AHE metric panels, XY phi panels, or 3ω geometry/scaling panels as common modules.
- Layout may host the slots, but Assembly owns their meaning.

## Current Layout / State Coupling Debts

### Shell-level routing that still mixes layout and workflow coordination

- `WorkflowWorkspaceShell` builds the selected-hits snapshot in the action bar before analysis.
- `WorkflowWorkspaceShell` routes legend-drag updates directly into the store and flushes the interaction snapshot from the shell.
- `WorkflowWorkspaceShell` threads library-root and library settings into search actions directly.
- `WorkflowWorkspaceShell` mounts pack loading in both columns, which duplicates one shell affordance in two places.

### Workflow-local views that duplicate common shell chrome

- `AHEWorkspaceView`, `XYRotationWorkspaceView`, and `ThreeOmegaWorkspaceView` each reconstruct the same shell scaffold with different injected panels.
- `WorkbenchStandardPlotControls` and workflow-specific plot-control builders each repeat the same shared plot-control pattern with different content.
- `AHEMetricOverridePanel` and `AHERAHEOverridePanel` duplicate nearly identical override-editor structure with different semantics.
- `ThreeOmegaAddOverlayButton` and the overlay-chip row are embedded directly in workflow-local plot controls rather than being mounted through a generic overlay slot. This is a slot/mounting debt only; Gate 7.4 owns the actual overlay extraction.

### Implicit status composition

- `WorkbenchStatusArea` is defined but not mounted.
- Status messaging is split between the result header, search message line, and lower-right warning/trace stack.
- The shell therefore has a status concept, but not one explicit status mount point.

## Gate 5 Readiness

### Safe refactor targets

- Split `WorkflowWorkspaceShell` into smaller layout-only subviews without changing the slot set or action routing.
- Isolate the left-column and right-column composition helpers so the shell body stays shallow.
- Deduplicate pure view chrome, such as repeated row styling and repeated pack-load placement, without changing callback behavior.
- Keep `WorkbenchPlotCanvas`, `WorkbenchResultHeaderShell`, `WorkbenchTracePanel`, and `WorkbenchWarningPanel` as view-level surfaces only.
- Keep Selection, Analysis Overlay, Warning/Trace, Save, and Pack ownership unchanged in Gate 5.

### What must wait for module extraction

- Main Search canonical ownership changes
- Selection canonical ownership changes
- Secondary input search generalization
- Analysis overlay extraction into a common module
- Pack / restore ownership consolidation
- Save metadata projection redesign
- Warning / trace ownership split

### Tests that currently protect layout behavior

- `V330WorkbenchShellContractTests` guards the provider/shell dispatch contract.
- `V538SelectedHitsBridgeAuditTests` guards the analyze-action selected-hits bridge.
- `V563WorkflowStateBoundaryTests` guards plot-canvas surface boundaries and tab-output projection.
- `V537AnalysisLifecycleBoundaryTests` guards clear/lifecycle boundaries across the workbench shell.
- `V537PackRestoreModuleBoundaryTests` and `V4117AnalysisPackVaultTests` guard pack/restore layout-adjacent state handling.

### What must not change in Gate 5

- Shell-slot names and routing semantics
- Workflow-specific panel ownership
- Selected-hits bridge behavior
- Pack restore callback contract
- Plot canvas edit behavior
- Save / update decision logic
- Warning coalescing behavior

## Gate 5 Recommended Refactor Targets

1. Extract `WorkflowWorkspaceShell` column composition into smaller layout-only subviews, while keeping the same action closures and slot inputs.
2. Consolidate the repeated pack-load affordance into one explicit layout helper if the user-facing affordance remains unchanged.
3. Clarify the lower-right status composition by making the warning / trace / message grouping explicit in layout code, without moving ownership out of the stores.
4. Reduce duplication in the workflow wrappers so they read as thin slot declarations rather than repeated shell scaffolds.
