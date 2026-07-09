# Workbench Physical Module Layout

> Status: planning contract for aligning Swift file placement with the stable Workbench architecture model. This document does not authorize behavior changes by itself.

## Purpose

Workbench's stable architecture model is:

```text
Workflow -> Workflow Assembly -> Main Board -> Modules
```

This document defines the target physical layout for making file paths communicate ownership:

- **Main Board**: orchestration, shell mounting, workflow dispatch, and module wiring.
- **Modules**: reusable Workbench capabilities and canonical module state.
- **Workflows**: experiment-specific physics, ingestion, plotting semantics, pack/save semantics, and workflow-owned controls.

For capability-first routing, use `MODULE_CAPABILITY_MAP.md`. For ownership authority, use `MODULE_BOUNDARIES.md`.

## Non-Goals

Physical layout work must not be used to:

- change workflow behavior;
- fix RT metadata, legend, or series-order bugs;
- change Plot System rendering semantics;
- rewrite `WorkbenchFeatureStore` into smaller coordinators;
- change pack schemas except when a later explicit migration gate authorizes it;
- alter Library, Inbox, or sidecar ownership.

Each physical-layout commit should be either documentation-only or move-only plus required import/path/doc updates.

## Classification Rules

### Main Board

A file belongs under `Workbench/MainBoard/` when it answers orchestration questions:

- Which workflow is active?
- Which workspace view is mounted?
- Which modules are mounted into the shell?
- Which snapshots, callbacks, or provider protocols are passed between shell, modules, and workflow stores?
- How are shared Workbench facades exposed to the UI?

Main Board files may call modules and workflows, but they must not own workflow physics or module-internal canonical state.

### Modules

A file belongs under `Workbench/Modules/<ModuleName>/` when it implements a reusable Workbench capability that can be used by multiple workflows and does not depend on one workflow's physics meaning.

Module-owned files define one or more of:

- canonical module state;
- module input/output contracts;
- reusable UI/control surfaces;
- reusable rendering/persistence/search/selection behavior;
- explicit read surfaces or provider protocols.

Modules must not infer workflow physics meaning. Workflow-specific semantics enter modules only through explicit payloads, snapshots, providers, or assembly-declared configuration.

### Workflows

A file belongs under `Workbench/Workflows/<WorkflowName>/` when it interprets domain data for a specific measurement workflow.

Workflow-owned files define:

- raw-file parsing or ingestion for that workflow;
- physics-specific analysis;
- x/y/z axis semantics and display units;
- workflow-specific plot payload construction;
- default title templates and workflow labels;
- workflow-specific pack/save metadata;
- workflow-specific optional panels and controls.

Workflow renderers convert analysis results into module payloads. For Cartesian XY workflows this includes `WorkbenchPlotPayload` and `WorkbenchPlotSeries` semantic identity such as `sourceRef`, `sampleID`, and `metadata`.

## Target Physical Layout

```text
Sources/SpinLabApp/
  Workbench/
    MainBoard/
      WorkbenchView.swift
      WorkbenchFeatureStore.swift
      WorkflowWorkspaceShell.swift
      WorkflowWorkspaceRegistry.swift
      WorkflowWorkspaceProvider.swift
      WorkflowWorkspaceResultArea.swift
      WorkflowWorkspaceLeftColumn.swift
      WorkflowWorkspaceRightColumn.swift

    Modules/
      Search/
        WorkbenchMainSearchRuntime.swift
        WorkbenchSearchSnapshot.swift
        SearchWorkflowMeasurementsUseCase.swift
        WorkflowSearchModels.swift
        WorkflowHitRow.swift

      Selection/
        WorkbenchSelectionRuntime.swift
        WorkbenchSelectedHitsSnapshot.swift
        SelectionReading.swift

      SecondaryInputSearch/
        WorkbenchSecondaryInputSearchRuntime.swift

      PlotSystem/
        Contracts/
          WorkbenchResultContracts.swift
          WorkbenchPlottingStore.swift

        Pipeline/
          WorkbenchRenderPipeline.swift

        Legend/
          LegendDimensionResolver.swift

        SeriesOrder/
          WorkbenchSeriesOrderPanel.swift
          WorkbenchSeriesOrderKeyResolver.swift

        Preservation/
          TabRenderManager.swift
          TabRenderState.swift

        Canvas/
          WorkbenchPlotCanvas.swift
          PlotCanvasMouseTracker.swift

        Controls/
          Common/
            SharedPlotTextControls.swift
            SharedPlotFontSizeControls.swift
            SharedPlotTickCountControls.swift
            SharedPlotLabelOverrideField.swift
          CartesianXY/
            WorkbenchPlotControlsPanel.swift
            WorkbenchStandardPlotControls.swift
            WorkbenchAxisRangeControls.swift
            WorkbenchSeriesAppearanceControls.swift
            WorkbenchTitleTemplateField.swift

        Heatmap/
          HeatmapPlotPayload.swift
          HeatmapRenderPipeline.swift
          HeatmapRenderer.swift
          HeatmapPlotLayout.swift
          HeatmapTabRenderState.swift
          HeatmapColorScale.swift
          HeatmapColorScaleControls.swift
          HeatmapZLabelControl.swift

        DualAxis/
          DualAxisPlotPayload.swift
          DualAxisPlotLayout.swift
          DualAxisChartRenderer.swift
          DualAxisRenderPipeline.swift
          // Display-state and control targets are documented in modules/DUAL_AXIS_CONTROL_CONTRACT.md

      PackRestore/
        AnalysisPackProviding.swift
        AnalysisVault.swift
        RestoreAnalysisPackUseCase.swift

      Save/
        ActiveChartProviding.swift
        SaveActiveChartToLibraryUseCase.swift
        PersistChartArtifactUseCase.swift
        PersistMeasurementDataUseCase.swift

      WarningTrace/
        WorkbenchWarningLog.swift
        WorkbenchRunTraceProjection.swift
        WorkbenchRunTraceProviding.swift

    Workflows/
      AHE/
        AHEWorkspaceStore.swift
        AHEWorkspaceView.swift
        AHEPlotRenderer.swift
        AHEIngestionContracts.swift
        AHEPackContracts.swift

      ThreeOmega/
        ThreeOmegaWorkspaceStore.swift
        ThreeOmegaWorkspaceView.swift
        ThreeOmegaPlotRenderer.swift
        ThreeOmegaPackContracts.swift

      XYRotation/
        XYRotationWorkspaceStore.swift
        XYRotationWorkspaceView.swift
        XYRotationPlotRenderer.swift

      IV/
        IVWorkspaceStore.swift
        IVWorkspaceView.swift
        IVPlotRenderer.swift
        IVIngestionContracts.swift
        IVPackContracts.swift

      RT/
        RTWorkspaceStore.swift
        RTWorkspaceView.swift
        RTPlotRenderer.swift
        RTIngestionContracts.swift
        RTPackContracts.swift
        AnalyzeRTWorkflowUseCase.swift

      RSM/
        RSMWorkspaceStore.swift
        RSMWorkspaceView.swift
        RSMHeatmapPayloadBuilder.swift
        RSM ingestion / pack / save projection files
```

The layout above is a target map, not a statement that every listed file already exists or has the exact listed name today. The move gate must verify each file before moving it.

## Current Status

Completed:

- Gate 8.4 aligned the PlotSystem physical module layout and controls split. Historical closeout: `history/gate8/GATE8_4_CLOSEOUT.md`.
- `MODULE_CAPABILITY_MAP.md` now provides capability-first routing.
- Plot Controls ownership split is documented in `modules/PLOT_CONTROLS_SPLIT_PLAN.md`.
- DualAxis controls/display-state target is documented in `modules/DUAL_AXIS_CONTROL_CONTRACT.md`.

Still future:

- Search / Selection move-only pass.
- Pack / Save / WarningTrace move-only pass.
- Workflow grouping pass.
- `WorkbenchFeatureStore` facade slimming audit after layout stabilizes.

## Current Audit Findings

1. The logical model is already documented: Workflow -> Workflow Assembly -> Main Board -> Modules.
2. PlotSystem is the most mature physically aligned module group; future changes should keep render-path-specific details in specialized docs rather than expanding `modules/PLOT_SYSTEM.md` indefinitely.
3. Some files currently named as generic `UseCases` are actually module internals or workflow internals. Example classifications:
   - `LegendDimensionResolver` belongs to `Modules/PlotSystem/Legend`.
   - `SearchWorkflowMeasurementsUseCase` belongs to `Modules/Search`.
   - `IVPlotRenderer` belongs to `Workflows/IV`.
   - `SaveActiveChartToLibraryUseCase` belongs to `Modules/Save` as a Workbench-to-Library bridge.
4. `WorkbenchFeatureStore` is intentionally mixed today. Treat it as a Main Board facade during physical layout normalization. Do not split it without a later explicit gate.

## Remaining Move Gates

### Search / Selection Move-Only Pass

Scope:

- Move Main Search and Selection module files into `Workbench/Modules/Search` and `Workbench/Modules/Selection`.
- Keep `WorkbenchFeatureStore` in Main Board as the facade.

Rules:

- Do not change search semantics, selected-hit snapshots, or select-all denominators.
- Do not remove compatibility mirrors in this gate.

### Pack / Save / WarningTrace Move-Only Pass

Scope:

- Move Workbench-owned pack/restore, save/export, warning, and run-trace files into their module folders.
- Preserve Library ownership and storage namespace boundaries.

Rules:

- No pack schema migration.
- No artifact path behavior changes.

### Workflow Grouping Pass

Scope:

- Move workflow-owned stores, views, renderers, ingestion contracts, pack contracts, and parsers into `Workbench/Workflows/<WorkflowName>/`.

Rules:

- One workflow per commit where possible.
- No workflow behavior changes.
- Update workflow assembly docs and code maps as files move.

### Facade Slimming Candidate Audit

Scope:

- Audit whether `WorkbenchFeatureStore` can be split into coordinators or registries after the physical layout is stable.

Rules:

- This is an audit only unless a later gate explicitly authorizes code extraction.

## Move-Only Review Checklist

For every physical-layout commit:

1. State the capability row from `MODULE_CAPABILITY_MAP.md`.
2. State the owner and target physical home.
3. Confirm behavior change is none.
4. Update code maps and dispatch docs if the moved file is a first-read file.
5. Run the relevant structural/source-inspection tests plus the smallest runtime/build check available.
