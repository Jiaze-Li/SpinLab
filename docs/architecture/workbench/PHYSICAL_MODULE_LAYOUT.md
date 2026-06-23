# Workbench Physical Module Layout

> Status: planning contract for aligning Swift file placement with the stable Workbench architecture model. This document does not authorize behavior changes by itself.

## Purpose

Workbench's stable architecture model is:

```text
Workflow -> Workflow Assembly -> Main Board -> Modules
```

The current documentation already defines this logical model, but the Swift file layout still reflects earlier implementation phases: files are spread across `Features/Workbench`, `App/State`, `UseCases`, `Domain`, and `Workbench/V3`. That layout makes capability discovery harder; for example, a developer searching for legend auto-resolution has to know that `LegendDimensionResolver` exists before they can find it.

This document defines the target physical layout and the migration plan for making file paths communicate ownership:

- **Main Board**: orchestration, shell mounting, workflow dispatch, and module wiring.
- **Modules**: reusable Workbench capabilities and canonical module state.
- **Workflows**: experiment-specific physics, ingestion, plotting semantics, pack/save semantics, and workflow-owned controls.

## Non-Goals

This gate is a physical-layout normalization gate, not a behavior gate.

Do not use physical layout work to:

- change workflow behavior;
- fix RT metadata, legend, or series-order bugs;
- change Plot System rendering semantics;
- rewrite `WorkbenchFeatureStore` into smaller coordinators;
- change pack schemas except when a later explicit migration gate authorizes it;
- alter Library, Inbox, or sidecar ownership.

Each implementation commit in this gate should be either documentation-only or move-only plus required import/path/doc updates.

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

Workflow renderers are responsible for converting analysis results into module payloads. For Cartesian XY workflows this includes `WorkbenchPlotPayload` and `WorkbenchPlotSeries` semantic identity such as `sourceRef`, `sampleID`, and `metadata`.

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
          WorkbenchPlotControlsPanel.swift
          WorkbenchStandardPlotControls.swift
          WorkbenchAxisRangeControls.swift
          WorkbenchSeriesAppearanceControls.swift
          SharedPlotTextControls.swift
          SharedPlotFontSizeControls.swift
          SharedPlotTickCountControls.swift

        Heatmap/
          HeatmapPlotPayload.swift
          HeatmapRenderPipeline.swift
          HeatmapRenderer.swift
          HeatmapPlotLayout.swift
          HeatmapTabRenderState.swift
          HeatmapColorScale.swift

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

## Current Audit Findings

1. The logical model is already documented. `INDEX.md` states the stable model as Workflow -> Workflow Assembly -> Main Board -> Modules, but the current physical paths do not consistently expose that model.
2. The current docs provide entry points by document type and module contract, but they do not yet provide a capability-first reverse lookup.
3. Plot System is the strongest candidate for the first physical cleanup because its current capability set is mature and widely reused: render pipeline, legend auto-resolution, plot controls, plot preservation, canvas, heatmap, point labels, and series order.
4. Some files currently named as generic `UseCases` are actually module internals or workflow internals. Example classifications:
   - `LegendDimensionResolver` belongs to `Modules/PlotSystem/Legend`.
   - `SearchWorkflowMeasurementsUseCase` belongs to `Modules/Search`.
   - `IVPlotRenderer` belongs to `Workflows/IV`.
   - `SaveActiveChartToLibraryUseCase` belongs to `Modules/Save` as a Workbench-to-Library bridge.
5. `WorkbenchFeatureStore` is intentionally mixed today. Treat it as a Main Board facade during physical layout normalization. Do not split it in this gate.

## Migration Plan

### Gate P0 — Documentation and Audit Map

Scope:

- Add this physical layout contract.
- Add a capability-first map (`MODULE_CAPABILITY_MAP.md`) in a follow-up commit.
- Update `INDEX.md` so physical layout and capability map are discoverable.
- Do not move Swift files.

Acceptance:

- Docs identify Main Board / Modules / Workflows as the target physical structure.
- Docs include explicit non-goals and move-only rule.
- No Swift, build, runtime, or pack schema changes.

### Gate P1 — Plot System Move-Only Pass

Scope:

- Move Plot System files into `Workbench/Modules/PlotSystem/...`.
- Start with high-discovery files:
  - `LegendDimensionResolver.swift`
  - `WorkbenchRenderPipeline.swift`
  - `WorkbenchResultContracts.swift`
  - `WorkbenchSeriesOrderKeyResolver.swift`
  - `WorkbenchSeriesOrderPanel.swift`
  - `TabRenderManager.swift`
  - `WorkbenchPlotCanvas.swift`
  - common plot control files.
- Update code maps in `modules/PLOT_SYSTEM.md`, `MODULE_BOUNDARIES.md`, and `INDEX.md`.

Rules:

- Move-only plus necessary import/path/project membership updates.
- No renderer behavior changes.
- No RT metadata or legend bug fixes in the same commit.

Validation:

- Desktop build succeeds.
- Plot System tests still pass.
- Existing workflow render tests still pass.

### Gate P2 — Search / Selection Move-Only Pass

Scope:

- Move Main Search and Selection module files into `Workbench/Modules/Search` and `Workbench/Modules/Selection`.
- Keep `WorkbenchFeatureStore` in Main Board as the facade.

Rules:

- Do not change search semantics, selected-hit snapshots, or select-all denominators.
- Do not remove compatibility mirrors in this gate.

### Gate P3 — Pack / Save / WarningTrace Move-Only Pass

Scope:

- Move Workbench-owned pack/restore, save/export, warning, and run-trace files into their module folders.
- Preserve Library ownership and storage namespace boundaries.

Rules:

- No pack schema migration.
- No artifact path behavior changes.

### Gate P4 — Workflow Grouping Pass

Scope:

- Move workflow-owned stores, views, renderers, ingestion contracts, pack contracts, and parsers into `Workbench/Workflows/<WorkflowName>/`.

Rules:

- One workflow per commit where possible.
- No workflow behavior changes.
- Update workflow assembly docs and code maps as files move.

### Gate P5 — Facade Slimming Candidate Audit

Scope:

- Audit whether `WorkbenchFeatureStore` can be split into coordinators or registries after the physical layout is stable.

Rules:

- This is an audit only unless a later gate explicitly authorizes code extraction.

## Move-Only Review Checklist

For every physical-layout commit:

- Did the commit move files without changing behavior?
- Are all updated imports, project membership entries, and references required by the move only?
- Did docs Code Maps update to the new paths?
- Did the commit avoid opportunistic bug fixes?
- Did the final report state rebuild/test status?

## Stop Conditions

Stop the layout migration and open a separate architecture gate if a file move reveals:

- circular dependencies that require behavior changes;
- pack schema changes;
- Library/Workbench ownership ambiguity;
- a need to change module state ownership;
- a need to change `WorkbenchFeatureStore` responsibilities beyond file placement.
