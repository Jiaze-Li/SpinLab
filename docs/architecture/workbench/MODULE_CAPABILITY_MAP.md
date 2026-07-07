# Workbench Module Capability Map

> Status: reverse lookup map for Gate 8.4 physical-layout work. This document supplements `MODULE_BOUNDARIES.md`; it does not replace ownership authority.

## Purpose

Use this file when the question is capability-first:

```text
I need to change X. Which module owns it? Which doc and source files should I inspect first?
```

This is intentionally different from `MODULE_BOUNDARIES.md`, which is ownership-authority-first, and `PHYSICAL_MODULE_LAYOUT.md`, which is target-file-layout-first.

## How to Read This Map

- **Capability / task** is the phrase a developer or agent is likely to search for.
- **Owner** is the architectural owner.
- **Layer** is one of Main Board, Module, Workflow, or cross-domain bridge.
- **Start docs** are the first architecture documents to read.
- **Primary files today** use the current repository layout. Some files are expected to move during Gate 8.4.
- **Target physical home** is the intended location after physical module layout normalization.

If this map conflicts with `MODULE_BOUNDARIES.md`, `MODULE_BOUNDARIES.md` wins.

## Core Routing Table

| Capability / task | Owner | Layer | Start docs | Primary files today | Target physical home | Notes |
|---|---|---|---|---|---|---|
| Workbench shell composition | Main Board | Main Board | `SHELL_BLOCKS.md`, `MAIN_BOARD_LAYOUT.md`, `MODULE_BOUNDARIES.md` | `Features/Workbench/WorkflowWorkspaceShell.swift`, `WorkflowWorkspaceLeftColumn.swift`, `WorkflowWorkspaceRightColumn.swift`, `WorkflowWorkspaceResultArea.swift` | `Workbench/MainBoard/` | Shell mounts modules and workflow content; it should not own workflow physics. |
| Workflow dispatch / workspace view registration | Main Board / Workflow Assembly | Main Board + Workflow | `WORKFLOW_ASSEMBLY.md`, `WORKFLOW_EXTENSION.md` | `Features/Workbench/WorkflowWorkspaceRegistry.swift`, workflow workspace views | `Workbench/MainBoard/` + `Workbench/Workflows/<Workflow>/` | Registry dispatches views; workflow records define semantics. |
| Workbench facade / module wiring | Main Board facade | Main Board | `MODULE_BOUNDARIES.md`, `PHYSICAL_MODULE_LAYOUT.md` | `App/State/WorkbenchFeatureStore.swift` | `Workbench/MainBoard/WorkbenchFeatureStore.swift` | Mixed by design today. Do not split during Gate 8.4 move-only work. |
| Main measurement search | Main Search | Common module | `modules/MEASUREMENT_SEARCH.md`, `MODULE_BOUNDARIES.md` | `App/State/WorkbenchMainSearchRuntime.swift`, `UseCases/SearchWorkflowMeasurementsUseCase.swift`, `Domain/WorkflowSearchModels.swift`, `Features/Workbench/WorkflowHitRow.swift` | `Workbench/Modules/Search/` | Search returns hits and snapshots; it must not infer workflow physics. |
| Search snapshot consumed by analysis | Main Search + workflow analysis entry | Module + Workflow | `modules/MEASUREMENT_SEARCH.md`, `WORKFLOW_EXTENSION.md` | `App/State/WorkbenchSearchSnapshot.swift`, workflow stores' `runAnalysis` paths | `Workbench/Modules/Search/` + `Workbench/Workflows/<Workflow>/` | Analysis must consume run-scoped search/selected-hit snapshots, not workflow-local mirrors as canonical input. |
| Selection / selected IDs | Selection | Common module | `MODULE_BOUNDARIES.md`, `STATE_OWNERSHIP.md` | `App/State/WorkbenchSelectionRuntime.swift`, `App/State/WorkbenchSelectedHitsSnapshot.swift`, `Features/Workbench/WorkflowWorkspaceProvider.swift` | `Workbench/Modules/Selection/` | Selection owns selected IDs only, not search, ingestion, or physics. |
| Select all denominator | Selection + Main Board facade | Common module + facade | `MODULE_BOUNDARIES.md` | `WorkbenchSelectionRuntime.swift`, `WorkbenchFeatureStore.swift` | `Workbench/Modules/Selection/` + `Workbench/MainBoard/` | Denominator is passed explicitly; do not recompute inside workflow stores. |
| Secondary / auxiliary input search | Secondary Input Search | Optional module | `MODULE_BOUNDARIES.md`, `WORKFLOW_ASSEMBLY.md` | `App/State/WorkbenchSecondaryInputSearchRuntime.swift`, `ThreeOmegaWorkspaceStore+RTSelection.swift` | `Workbench/Modules/SecondaryInputSearch/` | Module owns slot state; Workflow Assembly owns the auxiliary file meaning and analysis contribution. |
| Cartesian XY plot payload contract | Plot System | Common module group | `modules/PLOT_SYSTEM.md`, `WORKFLOW_EXTENSION.md` | `Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift` | `Workbench/Modules/PlotSystem/Contracts/` | Payload carries x/y series arrays, axis mapping, labels, metadata, and capability flags. |
| Render pipeline | Plot System | Common module group | `modules/PLOT_SYSTEM.md` | `Workbench/Modules/PlotSystem/Pipeline/WorkbenchRenderPipeline.swift` | `Workbench/Modules/PlotSystem/Pipeline/` | Pipeline orchestrates style merge, legend auto-resolution, series reversal/order checks, and PNG output. |
| Legend auto-resolution / automatic legend labels | Plot System distributed legend capability | Common module group | `modules/PLOT_SYSTEM.md`, `WORKFLOW_EXTENSION.md` | `Workbench/Modules/PlotSystem/Legend/LegendDimensionResolver.swift`, `Workbench/Modules/PlotSystem/Pipeline/WorkbenchRenderPipeline.swift`, `WorkbenchResultContracts.swift` | `Workbench/Modules/PlotSystem/Legend/` | Resolver reads `WorkbenchPlotSeries.metadata`. It must not parse filenames, sidecars, search hits, or workflow-local state. |
| Manual legend label rename | Plot Controls + Plot Preservation | Common module group | `modules/PLOT_SYSTEM.md`, `STATE_OWNERSHIP.md` | `WorkbenchSeriesOrderPanel.swift`, `TabRenderManager.swift`, `TabRenderState` | `Workbench/Modules/PlotSystem/SeriesOrder/` + `Preservation/` | Per-series label overrides are tab display state, not workflow physics. |
| Series reorder / curve order | Plot Controls + Plot Preservation + workflow renderer opt-in | Common module + Workflow opt-in | `modules/PLOT_SYSTEM.md`, `WORKFLOW_EXTENSION.md` | `WorkbenchSeriesOrderPanel.swift`, `WorkbenchSeriesOrderKeyResolver.swift`, `TabRenderManager.swift`, workflow plot renderers | `Workbench/Modules/PlotSystem/SeriesOrder/` + workflow folders | Reorderable payloads need stable `sourceRef`; workflow renderer must apply order before render. |
| Legend drag position | Plot Canvas + Plot Preservation | Common module group | `modules/PLOT_SYSTEM.md`, `STATE_OWNERSHIP.md` | `WorkbenchPlotCanvas.swift`, `TabRenderManager.swift`, `WorkbenchPlotLayout.swift` | `Workbench/Modules/PlotSystem/Canvas/` + `Preservation/` | Canvas emits interaction; Plot Preservation owns tab state. |
| Point label visibility | Plot Canvas + Plot Preservation | Common module group | `modules/PLOT_SYSTEM.md` | `WorkbenchPlotCanvas.swift`, `TabRenderManager.swift`, `WorkbenchResultContracts.swift` | `Workbench/Modules/PlotSystem/Canvas/` + `Preservation/` | Point labels are opt-in display behavior for scatter-like series. |
| Copy PNG | Plot Canvas | Common module group | `modules/PLOT_SYSTEM.md` | `WorkbenchPlotCanvas.swift`, `Workbench/Modules/PlotSystem/Contracts/WorkbenchPlotRenderScale.swift` | `Workbench/Modules/PlotSystem/Canvas/` | Copy PNG copies the canvas's current imageData directly; no re-render, no scale menu. Live render defaults to `WorkbenchPlotRenderScale.display` (3x) via the render pipeline. |
| Plot controls panel | Plot Controls | Common module group | `modules/PLOT_SYSTEM.md`, `modules/PLOT_CONTROLS_SPLIT_PLAN.md` | `WorkbenchPlotControlsPanel.swift`, `WorkbenchStandardPlotControls.swift` | `Workbench/Modules/PlotSystem/Controls/` | Shared control host; workflow-specific controls must enter through explicit slots/bindings. |
| Font defaults | Global Plot Defaults / Plot System | Common module group | `STATE_OWNERSHIP.md`, `modules/PLOT_SYSTEM.md` | `WorkbenchGlobalPlotDefaultsProviding`, `WorkbenchFeatureStore.swift`, plot controls | `Workbench/Modules/PlotSystem/Controls/` plus Main Board facade | Font defaults are shared across workflows, not workflow pack state. |
| Axis range override | Plot Controls + Plot Preservation | Common module group | `modules/PLOT_SYSTEM.md`, `STATE_OWNERSHIP.md` | `WorkbenchAxisRangeControls.swift`, `TabRenderManager.swift`, `WorkbenchPlotLayout.swift` | `Workbench/Modules/PlotSystem/Controls/` + `Preservation/` | Axis range is display override, not raw data mutation. |
| Stack offset / stacked chart gap | Workflow Assembly plot semantics + Plot Controls surface | Workflow + module host | `WORKFLOW_ASSEMBLY.md`, `modules/PLOT_SYSTEM.md` | `WorkbenchStandardPlotControls.swift`, workflow stores/renderers | `Workbench/Modules/PlotSystem/Controls/` + workflow folders | Control surface is shared; applicability and renderer consumption are workflow-owned. |
| Heatmap render path | Plot System heatmap path | Common module group | `modules/PLOT_SYSTEM.md` | `Workbench/V3/Heatmap/*` | `Workbench/Modules/PlotSystem/Heatmap/` | Heatmap is parallel to Cartesian XY; do not extend XY payloads for heatmap data. |
| Dual-axis render path | Plot System dual-axis path | Common module group | `modules/PLOT_SYSTEM.md`, `WORKFLOW_EXTENSION.md`, `modules/PLOT_CONTROLS_SPLIT_PLAN.md` | `Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotPayload.swift`, `DualAxisPlotLayout.swift`, `DualAxisChartRenderer.swift`, `DualAxisRenderPipeline.swift` | `Workbench/Modules/PlotSystem/DualAxis/` | DualAxis is parallel to Cartesian XY and Heatmap. Must not extend `WorkbenchPlotPayload` for secondary-axis data. Workflow-specific semantics enter only through explicit DualAxis payloads. |
| Dual-axis plot controls / display state | Plot Controls + Plot Preservation | Common module group | `modules/PLOT_CONTROLS_SPLIT_PLAN.md`, `modules/PLOT_SYSTEM.md`, `STATE_OWNERSHIP.md` | not implemented yet | `Workbench/Modules/PlotSystem/DualAxis/` + `Preservation/` if shared state is generalized | Owns title/X/left-Y/right-Y label override, X/left-Y/right-Y range override, left/right series style, marker policy, and axis color policy for DualAxis charts. Must read captured display snapshots; must not infer workflow physics. |
| RSM heatmap payload construction | RSM Workflow Assembly | Workflow | `workflows/rsm/DRAFT_ASSEMBLY.md`, `modules/PLOT_SYSTEM.md` | RSM heatmap payload builder / RSM workspace files | `Workbench/Workflows/RSM/` | RSM supplies scientific grid data; Plot System renders heatmap. |
| Pack save / restore lifecycle | Pack Restore | Common module + workflow pack contracts | `modules/PACK_RESTORE.md`, `STATE_OWNERSHIP.md` | `App/State/AnalysisVault.swift`, `Domain/AnalysisPack.swift`, `UseCases/RestoreAnalysisPackUseCase.swift`, workflow pack contracts | `Workbench/Modules/PackRestore/` + workflow folders | Restore is cross-module orchestration; workflow pack result must include ingestion result. |
| Workflow pack config/result | Workflow Assembly | Workflow | `WORKFLOW_EXTENSION.md`, `modules/PACK_RESTORE.md` | `<Workflow>PackContracts.swift` | `Workbench/Workflows/<Workflow>/` | Workflow owns what its pack means; common Pack Restore owns lifecycle. |
| Save active chart to Library | Save module / Workbench-to-Library bridge | Cross-domain bridge | `MODULE_BOUNDARIES.md`, Library artifact docs | `UseCases/SaveActiveChartToLibraryUseCase.swift`, `PersistChartArtifactUseCase.swift`, `PersistMeasurementDataUseCase.swift`, `WorkbenchResultContracts.swift` | `Workbench/Modules/Save/` | Workbench generates artifacts; Library owns storage namespace and cleanup invariants. |
| Active chart provider | Save + Plot output bridge | Common module / provider | `modules/PACK_RESTORE.md`, `modules/PLOT_SYSTEM.md` | `ActiveChartProviding`, workflow stores | `Workbench/Modules/Save/` or `PlotSystem/Contracts/` depending on final ownership audit | Provider surfaces chart data without giving Save ownership of plot state. |
| Warning log / user-visible warnings | Warning Display / Run Trace | Common module | `MODULE_BOUNDARIES.md`, `WORKFLOW_EXTENSION.md` | warning/run-trace provider files, workflow stores | `Workbench/Modules/WarningTrace/` | Physics-specific warning causes belong to workflow; display/run-trace state belongs to module. |
| Analysis lifecycle / runAnalysis state | Analysis Lifecycle | Common module / workflow entry | `WORKFLOW_EXTENSION.md`, `MODULE_BOUNDARIES.md` | workflow stores' `runAnalysis`, shared run trace providers | `Workbench/Modules/AnalysisLifecycle/` if extracted later | Existing docs treat running/message/warning/trace as non-physics lifecycle state. |
| Workflow-specific parsing | Workflow Assembly | Workflow | workflow assembly docs, `WORKFLOW_EXTENSION.md` | workflow parsers / ingestion use cases | `Workbench/Workflows/<Workflow>/` | Parser meaning belongs to workflow, even if parser filename currently sits in `UseCases/`. |
| Workflow-specific plot renderer | Workflow Assembly | Workflow | workflow assembly docs, `WORKFLOW_EXTENSION.md` | `AHEPlotRenderer`, `XYRotationPlotRenderer`, `ThreeOmegaPlotRenderer`, `IVPlotRenderer`, `RTPlotRenderer` | `Workbench/Workflows/<Workflow>/` | Renderer owns domain transform and data-to-module-payload conversion. |
| Workflow-specific title template | Workflow Assembly + Plot Preservation override layer | Workflow + module | `WORKFLOW_ASSEMBLY.md`, `modules/PLOT_SYSTEM.md` | workflow stores, `WorkbenchTitleResolver`, `TabRenderManager` | workflow folders + `PlotSystem/Preservation/` | Default template is workflow-owned; inline override is tab state. |
| Workflow registration | Workflow Assembly + Main Board | Workflow + Main Board | `WORKFLOW_EXTENSION.md`, `WORKFLOW_ASSEMBLY.md` | `WorkflowID.swift`, `WorkflowDefinition.swift`, `WorkflowRegistry.swift`, `WorkflowWorkspaceRegistry.swift` | `Workflow/` registry files + `Workbench/MainBoard/` | Rule Book id is canonical; workspace registry mounts implementation. |
| Library sidecar / condition projection | Library/Inbox boundary + Main Search | Cross-domain bridge | `modules/MEASUREMENT_SEARCH.md`, Library sidecar docs | `SpinLabFileSidecar.swift`, `WorkflowSearchModels.swift`, search use case | Library/InBox docs + `Workbench/Modules/Search/` | Search consumes sidecar fields; Workbench must not become sidecar schema owner. |

## Capability Search Keywords

Use these synonyms when searching this map or the repository:

| Search phrase | Prefer this capability row |
|---|---|
| auto legend, legend guess, legend dimension, legend labels | Legend auto-resolution / automatic legend labels |
| curve order, reorder curves, series order, stacked order | Series reorder / curve order |
| drag legend, legend position | Legend drag position |
| copy image, export PNG, scale PNG | Copy PNG |
| selected files, select all, denominator | Selection / selected IDs; Select all denominator |
| auxiliary input, secondary file, RT input for 3ω | Secondary / auxiliary input search |
| pack, restore, analysis pack, reload chart | Pack save / restore lifecycle |
| save chart, save metric, Library artifact | Save active chart to Library |
| heatmap, colorbar, colormap, grid render | Heatmap render path |
| dual-axis, two y axes, secondary y axis, left/right y axis | Dual-axis render path; Dual-axis plot controls / display state |
| workflow renderer, x/y units, plot semantics | Workflow-specific plot renderer |
| file parser, ingestion, raw data columns | Workflow-specific parsing |

## Gate 8.4 Usage Rule

Before moving a file, use this map to classify its capability and owner, then use `PHYSICAL_MODULE_LAYOUT.md` to choose the target folder.

A Gate 8.4 move-only commit should state:

```text
Capability: <row name from this map>
Owner: <owner from this map>
Target home: <target physical home>
Behavior change: none
```

If the file does not fit any row, do not guess. Add or revise a capability row first, then perform the move in a later commit.
