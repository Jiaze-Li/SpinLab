# Workbench Module Boundaries

This document is the ownership authority for Workbench modules. A module owns concrete capability and state. The Main Board mounts and calls modules, and sibling modules must not mutate each other's canonical state. This is not a process guide.

## Module Concepts

### What is a Module?

A Module is a reusable Workbench capability mounted and called by the Main Board. It owns its own canonical state and exposes explicit read surfaces to the Main Board and sibling modules.

### Default Module

A Default Module is always loaded by the Main Board, regardless of the active workflow.

### Optional Module

An Optional Module is declared by the active Workflow Assembly and mounted only when that workflow is active.

### Module Group

A Module Group is an organizational grouping of related modules. It has no state ownership and no behavioral authority.

### Ownership Rule

Each module owns its canonical state. Other modules may read only through explicit read surfaces or projections.

### Forbidden Mutation Rule

Sibling modules must not write each other's canonical state directly. Cross-module changes must flow through the Main Board, explicit snapshots, or provider protocols.

### Read Surface Rule

Read surfaces must be explicit. If a module needs another module's state, the dependency must be named as a snapshot, projection, or provider contract rather than implied through shared mutable state.

### Module-Specific Boundaries

The sections below document the current boundary contracts for each module and module group.

## Gate 3 Module Inventory and Boundary Audit

Status: Gate 3 audit record. This section classifies current Workbench ownership surfaces only; it does not authorize extraction or runtime behavior changes.

Classification vocabulary:

- **Assembly-owned** — workflow-specific semantic contract and implementation surface: data interpretation, physics/analysis logic, plot semantics, metric definitions, unit conversions, workflow-specific warnings, and workflow-specific persistence semantics.
- **Module-owned** — reusable capability that does not own workflow physics meaning.
- **Common module** — Module-owned default capability available to all workflows.
- **Optional module** — Module-owned reusable capability declared by a Workflow Assembly when needed.
- **Boundary debt** — temporary mixed or unclear ownership state. Every boundary debt item must state its target owner and exit condition.

Important correction: Assembly-owned surfaces are not modules. AHE Hc / R_AHE extraction, XY phi/detrend/centering, and 3ω fitting/scaling stay in Workflow Assembly ownership even when the common shell hosts their controls.

### Main Search

- Classification: Module-owned — common module.
- Current implementation files:
  - `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift`
  - `Sources/SpinLabApp/App/State/WorkbenchSearchSnapshot.swift`
  - `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift`
  - `Sources/SpinLabApp/Domain/WorkflowSearchModels.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkflowHitRow.swift`
  - workflow-local mirror fields in `AHEWorkspaceStore.swift`, `XYRotationWorkspaceStore.swift`, and `ThreeOmegaWorkspaceStore.swift`
- Current consumers: `WorkflowWorkspaceShell`, all three workflow stores, selection snapshot construction, pack restore callback, title/context builders, tests that inspect `WorkbenchFeatureStore` search lists.
- State it owns: workflow-keyed query text, result list, running flag, status message, and `WorkbenchSearchSnapshot`.
- State it must not own: selected IDs, scientific ingestion/output, render output, title/legend/style overrides, pack vault state, save state.
- How workflow-specific semantics enter: workflow ID, query aliases, condition fields, and search defaults come from workflow/rules configuration; Search returns hits only and does not interpret physics.
- Pack/restore implications: restore writes canonical search state only through `restoreSearchState`; `cachedSearchResults` remains a persistent mirror for pack compatibility and selection denominator.
- Tests currently protecting it: `V320WorkflowSearchAcrossDrawersTests`, `V5114SearchUseCaseCapabilityInjectionTests`, `V537WorkbenchSearchMirrorTests`, `V537AHESearchSnapshotConsumptionTests`, `V537XYSearchSnapshotConsumptionTests`, `V537ThreeOmegaSearchSnapshotConsumptionTests`.
- Extraction readiness: medium. Canonical search state is already centralized, but `cachedSearchResults` remains a required bridge.
- Risks if extracted too early: stale mirror drift, broken select-all denominator, pack decode/restore regressions, accidental analysis from canonical results without selected-hit snapshot.

### Selection

- Classification: Boundary debt.
- Target owner: Module-owned — common Selection module.
- Exit condition: selected IDs, select/deselect actions, select-all denominator, and selected-hit snapshot construction have one canonical Selection owner or a formally documented mirror bridge with pack-compatible decode/restore tests.
- Current implementation files:
  - `Sources/SpinLabApp/App/State/WorkbenchSelectedHitsSnapshot.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`
  - workflow-local selection fields/methods in `AHEWorkspaceStore.swift`, `XYRotationWorkspaceStore.swift`, and `ThreeOmegaWorkspaceStore+Selection.swift`
- Current consumers: `WorkflowWorkspaceShell`, all workflow stores, analysis entry points, pack contracts, restore paths.
- Target state it would own: selected hit IDs, select/deselect/toggle/select-all actions, selected count, all-selected projection, and run-scoped `WorkbenchSelectedHitsSnapshot`.
- Target state it must not own: query text, search execution, search running/message state, ingestion/output, pack vault state, plot output, save state.
- How workflow-specific semantics enter: only through selected hits handed to workflow analysis; selection itself must not infer file meaning.
- Pack/restore implications: pack configs serialize selected IDs; restore must write selected IDs before rerender and keep denominator mirror aligned.
- Tests currently protecting it: `V537WorkbenchSelectionShellTests`, `V537WorkbenchSelectedHitsSnapshotTests`, `V538SelectedHitsBridgeAuditTests`, `V537PackRestoreModuleBoundaryTests`, search snapshot consumption tests for AHE/XY/3ω.
- Extraction readiness: medium-low. Snapshot contract is ready; canonical selected IDs still live in each workflow store.
- Risks if extracted too early: select-all denominator mismatch, nil-snapshot restore fallback breakage, analysis triggered with unselected or stale hits.

### Secondary Input Search

- Classification: Module-owned — optional module candidate.
- Ownership rule: the module owns auxiliary slot state and slot UI only; the Workflow Assembly owns the file meaning, analysis contribution, and requiredness policy.
- Current implementation files:
  - Current instance only: 3ω RT auxiliary input in `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`
  - `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`
- Current consumers: 3ω scaling ingestion/analysis, 3ω view popover, 3ω pack/restore, 3ω search snapshot boundary tests.
- Target state it would own: auxiliary query text, auxiliary running flag, auxiliary search results, auxiliary search message/status, popover/list UI state, selected auxiliary hit, deferred sidecar/file bridge for restore, and persisted auxiliary query default. Current 3ω concrete names are `rtQuery`, `isRTSearching`, `rtSearchResults`, `rtSearchMessage`, `showRTPopover`, `selectedRTHit`, `pendingRTSidecarPath`, and `cachedRTFilePath`.
- Target state it must not own: main search query/results/running/message, main selected IDs, primary workflow selection, physics calculations, plot output, generic pack vault orchestration.
- How workflow-specific semantics enter: the Workflow Assembly declares optional secondary search slots, their slot ID, display label, query hint/default, workflow/file-kind filter, selection cardinality, requiredness, analysis contribution, and fingerprint policy. 3ω RT search is the current `rt` instance of this optional module candidate. The RT/Rxx(T) meaning belongs to the 3ω Assembly, not to the module itself. Future workflows such as SOT may declare multiple auxiliary slots; the default pattern must not be named or shaped as 3ω-only RT search.
- Pack/restore implications: each declared secondary slot must serialize query text plus selected hit identity or stable sidecar/file identity. Restore may rebuild the selected hit from a slot-scoped sidecar bridge, but it must not infer auxiliary meaning from Main Search state. The pack fingerprint may include auxiliary file identity when the Workflow Assembly says that file changes analysis identity.
- Slot contract:
  - Slot ID: workflow-owned stable key. Current 3ω slot ID is `rt`.
  - Display label: workflow-owned user-facing label. Current 3ω label is `RT / Rxx(T)`.
  - Current behavior: `rtQuery` is passed through the generic `searchWorkflowMeasurements` path, returned hits are assigned to `rtSearchResults` directly, and restore can rebuild or accept auxiliary sidecars whose workflow is currently `3w` or `rt`.
  - Query default / search hint / workflow filter: workflow-declared search token(s), hints, and filter rules. The module only stores and executes the slot query; it does not invent the token or interpret the file meaning.
  - Allowed workflow IDs / file kinds: target contract uses an explicit whitelist per slot. Current 3ω runtime does not yet enforce a strict RT-only filter, so any future extraction that depends on strict allowed-kind filtering must add runtime guards and tests first.
  - Selection mode: single or multiple, as declared by the Workflow Assembly. Current 3ω is single-select.
  - Requiredness: optional by default, or required only for specific tabs/results that depend on the slot. Missing slots may disable only the dependent analysis surfaces.
  - Analysis contribution: the selected auxiliary hit contributes input data only. The module must not derive physics meaning or trigger analysis by itself.
  - Pack fingerprint: include auxiliary file identity only when the Workflow Assembly says that auxiliary identity changes analysis identity. Current 3ω includes the auxiliary RT file identity in pack identity.
  - Persisted fields: query text plus selected hit identity and stable sidecar/file bridge. Search results, search message, and running flag are session state unless the Workflow Assembly explicitly promotes them.
  - Restore bridge behavior: restore may rebind the slot from a pending sidecar path or cached file path; if the identity no longer resolves, leave the slot unbound and warn.
  - Warning behavior: missing or invalid auxiliary input must warn only through the dependent workflow surfaces. It must not mutate Main Search, and it must not auto-convert into a primary search result.
  - Multiple-slot support: the module must support zero, one, or many independently declared auxiliary slots. Each slot owns its own query, result list, selection, persistence bridge, and warning surface.
- Forbidden behavior:
  - must not mutate Main Search state
  - must not own workflow physics meaning
  - must not trigger analysis by itself
  - must not be named around RT as a default module
- Tests currently protecting it: `V537ThreeOmegaSearchSnapshotConsumptionTests`, `V537PackRestoreModuleBoundaryTests`, `V4117AnalysisPackVaultTests`, 3ω ingestion/scaling tests in `V413ThreeOmegaFitUseCaseTests` and `V41216ThreeOmegaScalingUseCaseTests`.
- Extraction readiness: low-medium. The general module shape is visible, but there is only one concrete instance and it is still implemented as workflow-local RT state.
- Risks if extracted too early: freezing a one-slot RT-specific API, blocking SOT-style multiple auxiliary inputs, losing restore sidecar/file bridge behavior, or letting auxiliary search mutate main search/selection state.

### Plot System

- Classification: Module-owned — common module group.
- Current implementation files:
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift`
  - `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift`
  - `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift`
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift`
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift`
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchChartStyle.swift`
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift`
- Current consumers: all workflow views/stores, renderers, save-to-library, pack/restore, plot tests.
- State it owns: tab render states, tab outputs, active tab, grid flag, legend anchor, chart style overrides, series label/title/axis overrides, point-label visibility, series order where opted in.
- State it must not own: search/selection state, ingestion result, workflow physics parameters, save/pack vault state, metric extraction semantics.
- How workflow-specific semantics enter: workflow renderer provides payloads, tabs, axis defaults, style parameters, capability flags such as `seriesReorderable`, and semantic labels. Plot System applies common display and preservation rules.
- Pack/restore implications: pack configs serialize tab state, active tab, grid, legend/style overrides, point label state, and series order; restore re-renders output from analysis result rather than serializing active image/layout.
- Tests currently protecting it: `V531SeriesRenderModeTests`, `V532WorkbenchRenderPipelineTests`, `V534LegendDimensionResolverTests`, `V535PointLabelVisibilityTests`, `V535TabRenderStatePackTests`, `V535CopyPNGScaleMenuTests`, `V536CurveDragOrderTests`, `V537WorkflowShellPhase4Tests`, `V563WorkflowStateBoundaryTests`.
- Extraction readiness: high for display/preservation contracts; medium for controls because workflow stores still host some control state.
- Risks if extracted too early: moving workflow semantics into common plot code, breaking tab override survival, using sample ID instead of sourceRef for reorder, serializing render output instead of rerendering.

### Pack / Restore

- Classification: Boundary debt.
- Target owner: Module-owned — common Pack / Restore module with a documented cross-module restore exception.
- Exit condition: pack load/save orchestration, `activePackID`, vault access, and every restore write are centralized behind the explicit restore contract, while workflow Assemblies provide only workflow-specific pack config/result semantics and restore metadata.
- Current implementation files:
  - `Sources/SpinLabApp/App/State/AnalysisVault.swift`
  - `Sources/SpinLabApp/Domain/AnalysisPack.swift`
  - `Sources/SpinLabApp/Workbench/V3/AnalysisPackProviding.swift`
  - `Sources/SpinLabApp/UseCases/RestoreAnalysisPackUseCase.swift`
  - `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift`
  - `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift`
  - `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift`
  - workflow restore/save-pack code in `AHEWorkspaceStore.swift`, `XYRotationWorkspaceStore.swift`, and `ThreeOmegaWorkspaceStore+Pack.swift`
- Current consumers: workflow stores, Workbench shell pack controls, restore use case, save-after-restore paths, tests.
- Target state it would own: active pack ID, vault contents, pack load/save orchestration, explicit restore write map.
- Target state it must not own: search/selection semantics except documented restore writes, ingestion semantics, plot display behavior, save-to-library outcome, analysis trace commits, workflow-specific persistence meaning.
- How workflow-specific semantics enter: each workflow Assembly supplies `PackConfig`, `PackResult`, pack metadata/fingerprint fields, and restore-time physics parameters through `AnalysisPackProviding`.
- Pack/restore implications: this is the module itself; restore is allowed to write multiple module states only through the documented write map and must rerender rather than re-ingest.
- Tests currently protecting it: `V4117AnalysisPackVaultTests`, `V5114RestoreUseCaseStatelessTests`, `V5114PackRestoreNoTraceCommitTests`, `V537PackRestoreModuleBoundaryTests`, `V535TabRenderStatePackTests`.
- Extraction readiness: medium. Contracts are documented; implementation remains per-workflow.
- Risks if extracted too early: missed restore write, accidental trace commit, broken legacy AHE nil-ingestion restore, stale search mirror, auxiliary input fingerprint loss.

### Save to Library

- Classification: Boundary debt.
- Target owner: split ownership. Save writer is Module-owned and common. Metric definitions, unit semantics, override policy, and semantic identity are Assembly-owned. The mapping from workflow metrics into generic save metadata remains the audited boundary.
- Exit condition: `SaveActiveChartToLibraryUseCase` receives an explicit workflow save metadata projection whose metric names, units, conditions, overrides, and semantic identity are already Assembly-owned, while the save writer owns only validation and artifact writes.
- Current implementation files:
  - `Sources/SpinLabApp/UseCases/SaveActiveChartToLibraryUseCase.swift`
  - `Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift`
  - `Sources/SpinLabApp/UseCases/PersistMeasurementDataUseCase.swift`
  - `Sources/SpinLabApp/UseCases/BackfillMeasurementPlotIndexUseCase.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`
  - save methods in `AHEWorkspaceStore.swift`, `XYRotationWorkspaceStore.swift`, and `ThreeOmegaWorkspaceStore+Persistence.swift`
  - save-metadata builders in `AHEWorkspaceStore.swift`, `XYRotationWorkspaceStore.swift`, and `ThreeOmegaWorkspaceStore+Plotting.swift`
  - metric/provider contracts in `Sources/SpinLabApp/Workbench/V3/WorkbenchResultContracts.swift`
- Current consumers: all workflow stores, Library artifact preview/read model, related chart refresh, save boundary tests.
- Target common save-writer state it would own: save status/message target, `persistenceOutcome`, save-side trace update from `PersistenceOutcome.trace`, and chart/data artifact write orchestration.
- Target common save-writer state it must not own: search/selection, analysis trigger, ingestion result mutation, tab override state, pack vault state, metric definitions, unit conversions, workflow semantic identity rules, or any physics/analysis interpretation.
- How workflow-specific semantics enter: workflow Assembly provides active chart PNG/manifest, sample keys, and a workflow save metadata projection. Today that bridge is the `ActiveChartProviding` protocol plus `buildActiveChartMetrics()`, which returns a generic `PendingMetricEntry` array. Save module must not derive physics.
- Pack/restore implications: restore sets enough library-root and active chart state to allow save after restore, but restore must not persist save outcome or trigger save. Metric override candidates stay save-time only and must not become pack state.
- Tests currently protecting it: `V537SaveModuleBoundaryTests`, `V4111SaveActiveChartToLibraryUseCaseTests`, `V343DeleteWorkbenchResultTests`, `V41217MeasurementPlotIndexTests`, `V342WorkbenchResultsReadModelTests`, `V5111ExtractAHEMetricsUseCaseTests`, `V5114AHEMetricSourceTests`, `V41216ThreeOmegaScalingUseCaseTests`, `V413ThreeOmegaFitUseCaseTests`, `V420XYRotationTests`.
- Extraction readiness: medium-high for write orchestration, medium for UI/status because `saveMessage` is still workflow-local and the save metadata projection is still a raw array bridge.
- Risks if extracted too early: duplicated save messages, trace update confusion, metric/provider gaps, bypassing `LibraryPathResolver`, or common code learning workflow semantics.

### Warning Display / Run Trace

- Classification: Boundary debt.
- Target owner: split ownership. Display/projection is Module-owned — common Analysis Lifecycle / Warning Display module. Workflow-specific warning meaning remains Assembly-owned.
- Exit condition: warnings and trace projections have a common read/display owner, while workflow Assemblies emit typed warnings/trace inputs without the display module interpreting physics.
- Current implementation files:
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchTracePanel.swift`
  - `Sources/SpinLabApp/UseCases/BuildRunTraceProjectionUseCase.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift`
  - workflow-local `warningLog`, `currentRunTrace`, `analysisMessage`, `plotMessage`, `saveMessage` fields in all workflow stores
- Current consumers: workflow views, result header, save/persist paths, analysis lifecycle tests.
- Target state it would own: warning log display/projection and run trace display/projection. Current stores own raw warning log and trace fields.
- Target state it must not own: search/selection, physics calculations, workflow-specific warning meaning, pack format, save artifact writes, plot override state.
- How workflow-specific semantics enter: workflow analysis/save use cases emit warnings and trace events; common display coalesces and renders them without assigning scientific meaning.
- Pack/restore implications: `warningLog`, `analysisMessage`, `saveMessage`, and `currentRunTrace` are session-only and must not be packed. Normal restore must leave trace nil.
- Tests currently protecting it: `V326RunManifestTraceTests`, `V537AnalysisLifecycleBoundaryTests`, `V537SaveModuleBoundaryTests`, `V5114PackRestoreNoTraceCommitTests`, `V537PackRestoreModuleBoundaryTests`.
- Extraction readiness: low-medium. Display components exist; ownership is still distributed across stores and save/analysis paths.
- Risks if extracted too early: trace committed on restore, warnings duplicated across reruns, save-side trace confused with analysis-side trace, session-only fields accidentally serialized.

### Analysis Overlay

- Classification: Module-owned — optional module candidate.
- Ownership rule: the module owns overlay pack IDs, overlay snapshots, overlay chips, and active-tab rerender requests; the Workflow Assembly owns eligibility, labels, snapshot-to-series mapping, warning policy, saved-manifest/sample-key policy, and metric-persistence policy.
- Current implementation files:
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`
  - `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`
- Current consumers: 3ω RAHE "Add Analysis" overlay today; 3ω Scaling Law overlay target next.
- Target state it would own: eligible overlay pack list, add/remove overlay actions, overlay IDs and snapshots, overlay chips, and session-only overlay state.
- Target state it must not own: primary ingestionResult/scalingResult mutation, combined pack creation, saved chart manifest policy, sample-key policy, or metric persistence.
- How workflow-specific semantics enter: the Workflow Assembly declares which tabs support overlay, which pack/result types are eligible, how overlay snapshots become plot series, the user-facing labels, warning behavior for missing or invalid overlay input, whether overlay changes saved chart manifests or sample keys, and whether overlay metrics are excluded from metric persistence.
- Pack/restore implications: the first version keeps overlay state session-only; restore clears it and does not serialize it into pack content. Future persistence must be explicitly declared by the Workflow Assembly.
- Extraction readiness: low-medium.
- Risks if extracted too early: pack-into-pack ambiguity, overlay state leaking into restore/save paths, or common code learning workflow-specific plot semantics.

### Title / Style / Legend Controls

- Classification: Module-owned — common module group within Plot System.
- Current implementation files:
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift`
  - `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift`
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift`
  - `Sources/SpinLabApp/UseCases/WorkbenchTitleResolver.swift`
  - workflow-local `titleTemplate`, grid, legend anchor, and chart style bindings in all workflow stores
- Current consumers: all workflow views/stores, render pipeline, pack configs, plot canvas editors.
- State it owns: display override state such as title template/overrides, chart style overrides, grid flag, legend anchor/position, axis and series display label overrides.
- State it must not own: search/selection, ingestion, workflow metric semantics, geometry/fit/phi physics state, save/pack orchestration, default axis meaning.
- How workflow-specific semantics enter: workflow Assembly supplies title tokens, default template, tab meanings, default axis labels, and whether legend/order capabilities apply.
- Pack/restore implications: title template, grid, legend anchor/position, chart style overrides, and tab render states are serialized in pack configs.
- Tests currently protecting it: `V323PlotParameterOverrideTests`, `V328PlotUXFreezeTests`, `V531SeriesRenderModeTests`, `V534LegendDimensionResolverTests`, `V537WorkflowShellPhase4Tests`, `V563WorkflowStateBoundaryTests`.
- Extraction readiness: medium-high. Common controls exist; workflow stores still host binding endpoints.
- Risks if extracted too early: default workflow titles lost, display overrides leaking into manifest semantics, tab override survival regression.

### Metric Extraction / Metric Override / Save Metadata

- Classification: Boundary debt.
- Target owner: split ownership. Metric definitions, extraction semantics, unit conversions, and overrides are Assembly-owned. Generic save metadata envelope and artifact writer are Module-owned and common. The boundary debt is the projection from workflow metrics into generic save records.
- Exit condition: AHE Hc / R_AHE extraction, 3ω alpha/beta/R² mapping, XY metric choices, unit conversions, and override rules are exposed through workflow Assembly save projections; the common Save module receives already-semantic metadata and never invents or transforms metric meaning.
- Current implementation files:
  - `Sources/SpinLabApp/Workbench/V3/WorkbenchResultContracts.swift`
  - `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`
  - `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift`
  - `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift`
  - `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`
- Current consumers: save-to-library use case, Library result index/data artifacts, AHE UI override controls, 3ω scaling save metadata, XY chart-only persistence.
- Target state ownership: no standalone module state yet. Current workflow stores own metric records to save, metric override candidates/info, active chart sample keys, and semantic chart identity metadata. Current AHE owns pending Hc/R_AHE overrides and extracted metrics. Current 3ω owns alpha/beta/R² save inputs when scaling is active. Current XY owns the explicit absence of a saved metric contract.
- Target state it must not own: plot image/layout generation, search/selection, pack vault state, generic save write mechanics, or any common-module definition of workflow metrics.
- How workflow-specific semantics enter: each workflow Assembly declares which metrics exist, how to extract them, canonical units, conditions, whether manual override is allowed, and whether the active chart saves chart-only or chart-plus-metrics.
- Pack/restore implications: metric override candidates are save-time state and should not become generic pack state unless a workflow explicitly declares restored unsaved overrides. Saved metrics belong to Library artifacts, not AnalysisPack. Restore may repopulate enough workflow state and library root to save after restore, but it must never restore metric records or save outcome.
- Tests currently protecting it: `V341ManualOverrideCaptureTests`, `V4111SaveActiveChartToLibraryUseCaseTests`, `V5111ExtractAHEMetricsUseCaseTests`, `V5114AHEMetricSourceTests`, `V537SaveModuleBoundaryTests`, `V41216ThreeOmegaScalingUseCaseTests`, `V413ThreeOmegaFitUseCaseTests`, `V420XYRotationTests`.
- Extraction readiness: low-to-medium. The common save envelope exists, but the workflow metric semantics are still bridged through raw `PendingMetricEntry` arrays rather than an explicit provider/projection contract.
- Risks if extracted too early: generic code invents metrics, overrides are applied to multi-sample results incorrectly, saved metadata diverges from workflow semantics, or Library artifacts get wrong canonical units.

### Geometry / Fit Range / Scaling Panels

- Classification: Assembly-owned. This is not a module candidate.
- Current implementation files:
  - `Sources/SpinLabApp/Domain/ThreeOmegaGeometry.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift`
  - `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`
  - `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift`
  - `Sources/SpinLabApp/Domain/ThreeOmegaScalingResult.swift`
- Current consumers: 3ω scaling, 3ω right-side controls, 3ω pack/restore, 3ω save metadata.
- State it owns: geometry values, fit range list, scaling result, V3/RAHE method choices where used by scaling or field-sweep semantics.
- State it must not own: common search/selection, generic plot controls, save write orchestration, pack vault mechanics.
- How workflow-specific semantics enter: directly; these controls are the 3ω physics contract and remain in the 3ω Assembly/Physics Function.
- Pack/restore implications: geometry, fit ranges, methods, and scaling result are serialized because they are required to interpret restored scaling charts and chart identity.
- Tests currently protecting it: `V41216ThreeOmegaScalingUseCaseTests`, `V41216ThreeOmegaPlotRendererTests`, `V4112ThreeOmegaV3MethodTests`, `V413ThreeOmegaFitUseCaseTests`, `V4117AnalysisPackVaultTests`.
- Extraction readiness: not a Gate 7 common-module extraction target. It may be internally cleaned within 3ω Assembly implementation only.
- Risks if extracted too early: common shell starts owning physics, fit-range identity gets detached from saved chart identity, scaling rerun no longer reflects current geometry/range state.

### Phi Offset Panel

- Classification: Assembly-owned. This is not a module candidate.
- Current implementation files:
  - `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`
  - `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`
  - `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift`
  - `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`
  - `Sources/SpinLabApp/UseCases/AlignXYSeriesOrderUseCase.swift`
- Current consumers: XY Rotation view/store, XY renderer, XY pack/restore, XY analysis tests.
- State it owns: `phiOffsetOverrides`, baseline-centering flag, linear detrend flag, and XY-specific rerender inputs.
- State it must not own: common title/style/legend controls, search/selection, save write mechanics, generic plot output.
- How workflow-specific semantics enter: directly; phi offset, detrend, and centering change XY angle alignment and belong to XY Assembly semantics.
- Pack/restore implications: phi offsets and baseline/detrend flags are serialized in `XYRotationPackConfig` and restored before rerender.
- Tests currently protecting it: `V420XYRotationTests`, `V5111AlignXYSeriesOrderUseCaseTests`, `V537XYSearchSnapshotConsumptionTests`, `V537PackRestoreModuleBoundaryTests`, `V537WorkflowShellPhase4Tests`.
- Extraction readiness: not a common-module extraction target. It may be internally cleaned as an XY Assembly-owned panel only.
- Risks if extracted too early: offset state treated as generic plot style, restored XY packs rerender with wrong angle alignment, future workflows inherit XY-specific assumptions.

## Gate 3 Remaining Debts and Follow-Ups

### Recommended Gate 3.1 follow-ups

- Define the workflow-declared **Secondary Input Search** optional module contract: slot ID, display label, search query defaults, workflow token/filter, selection cardinality, selected-hit persistence, restore sidecar bridge, and fingerprint contribution. Keep auxiliary file meaning in Assembly.
- Audit whether `cachedSearchResults` can be renamed to `searchResultMirror` with backward-compatible `CodingKeys` across all pack configs.
- Split warning/run-trace target ownership into a concrete Analysis Lifecycle read surface before moving fields out of workflow stores.
- Define a save metadata provider contract that separates common save envelope fields from Assembly-owned metric definitions, unit conversions, and manual overrides.

### Recommended Gate 7 prerequisites

- Do not extract Selection until selected IDs have one canonical owner or the local mirror/denominator bridge is formally preserved.
- Do not extract Pack/Restore until the restore write map has test coverage for every restored field, including secondary input search.
- Do not extract Secondary Input Search as an RT module. Extract only a general auxiliary-slot module with 3ω RT as one declared slot.
- Do not extract 3ω fitting/scaling, AHE Hc / R_AHE extraction, or XY phi/detrend/centering into default modules; they are Assembly-owned surfaces unless future workflows prove a real shared semantic contract.

## Search Boundary

- Canonical owner: `WorkbenchFeatureStore`
- Canonical state:
  - `searchQueryTexts`
  - `searchResults`
  - `searchMessages`
  - `searchRunning`
- Scope model:
  - all canonical search state is workflow-keyed
  - route switch preserves per-workflow search state by default
- Workflow-local projections/caches:
  - `cachedSearchResults`
  - `cachedSampleNumericDisplay`
  - workflow-specific query defaults such as `rtQuery`
- Canonical read surface for shell-triggered analysis:
  - `WorkbenchSearchSnapshot` (`queryText`, `results`, `isRunning`, `message`)
- Read path:
  - Shell search UI reads `WorkbenchFeatureStore` for query text, result lists, status messages, and running state.
  - Workflow rows read workflow-local cached results and numeric display projections.
- Forbidden reverse dependencies:
  - Workflow stores must not become the source of truth for top-level search status.
  - Search UI must not infer canonical search results from render output or canvas state.
  - New analysis paths must not use `cachedSearchResults` as primary analysis input.
  - New shell UI paths must not treat `cachedSearchResults` as canonical search state.
  - Plot controls/title/legend/rerender paths must not read/write search query/results/running/message.
  - Plot controls/title/legend/rerender/preservation paths must not mutate `cachedSearchResults`.
  - Search state must not depend on `TabRenderState`, `TabRenderOutput`, manifest payload, or image/layout output.

### Search Module does not own

- selection IDs (`selectedSearchResultIDs`)
- workflow scientific ingestion/analysis state
- plot payload/layout/image output
- title/legend/axis override state
- rerender preservation state

### Search Module reset rules

- canonical reset: `clearSearch` resets query/results/message/running for one workflow key
- workflow-local `clearResults` is not canonical Search Module clear
- analysis/rerender must not implicitly clear search state

### Search Module and Selection Module relationship

- Search Module owns hit-list and query lifecycle state
- Selection Module owns selected IDs
- Selection Module consumes hit identities from `WorkbenchSearchSnapshot`
- Selection Module must not mutate query/results/running/message except through explicit Search Module API
- Select All denominator must be explicit; current transition denominator is workflow-local `cachedSearchResults`

## Selection Boundary (Phase 5C-1A)

- Canonical owner (target contract): Selection Module (formerly SelectionShell)
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore`)
- Canonical state (contract):
  - `selectedSearchResultIDs`
  - selection mutations (`toggle`, `selectAll`, `deselectAll`, `clearSelection`)
  - `selectedCount` / `isAllSelected`
  - run-scoped `selectedHitsSnapshot`
- Current transition state (Phase 5C-3 checkpoint):
  - `selectedSearchResultIDs` remains workflow-local
  - `WorkbenchSelectedHitsSnapshot` is now the run-scoped selected-hit read surface (Phase 5C complete)
  - `cachedSearchResults` remains local mirror / selection denominator / pack compatibility
  - `legacyHits` parameter in `WorkbenchSelectedHitsSnapshot` factory is the explicit bridge from mirror to ephemeral snapshot
  - duplicate-state bridge is intentional and deferred — rename/removal awaits Save / Pack Module work

### Selection Module does not own

- search query text
- search result generation
- search running/message state
- plot output/layout/image state
- rerender/preservation state
- workflow scientific ingestion/calculation

### Selection Module and Workflow Function relationship

- Workflow Function should consume a run-scoped `selectedHitsSnapshot`
- Workflow Function should not read workflow-local `cachedSearchResults` as primary analysis input
- nil-snapshot analysis entry remains legacy/restore compatibility only

### Clear semantics

- `clearSelection`: clears selected IDs only
- `clearSearch`: belongs to SearchShell (`query/results/message/running`)
- current `clearResults` in workflow stores is legacy mixed behavior and must not be treated as Selection Module canonical clear
- 3ω `clearResults` also resets RT-side state; this is workflow-specific cleanup, not generic Selection Module behavior

### Migration direction

- `WorkbenchSelectedHitsSnapshot` is complete (Phase 5C); run-scoped selected-hit read surface is established.
- `selectAll` / `isAllSelected` denominator remains `cachedSearchResults` — correct by definition; denominator is intrinsically the search result set.
- `cachedSearchResults` will not be renamed now; deferred to Save / Pack Module (rename requires pack `CodingKey` backward compatibility handling).
- Possible future name: `searchResultMirror`.

### Phase 5C selection regression plan

- selection toggle does not mutate search query/results/running/message
- selectAll uses declared denominator source-of-truth
- deselectAll clears selected IDs only
- clearResults behavior remains explicit and workflow-scoped
- analysis consumes selected-hit snapshot
- pack restore restores selected IDs without corrupting canonical search state

### Search Module and Workflow Function relationship

- workflow functions consume a selected-hit snapshot
- workflow functions must not own top-level search query/results/running/message
- analysis and rerender paths must not mutate Search Module lifecycle state

### Current state and migration direction (Phase 5C-3)

- `WorkbenchSearchSnapshot` is the canonical run-scoped search read surface (Phase 5A complete).
- `WorkbenchSelectedHitsSnapshot` is the run-scoped selected-hit read surface (Phase 5C complete).
- `cachedSearchResults` mirrors canonical search results into workflow-local store; also serves as pack-compat field, selection denominator, and nil-snapshot fallback.
- No current path incorrectly reads `cachedSearchResults` when a snapshot is available (verified Phase 5C-3 audit).
- `cachedSearchResults` will not be renamed until Save / Pack Module work; rename requires pack `CodingKey` backward compatibility handling.
- Search Module remains canonical query/results/running/message owner.

### Current shell invocation note

- AHE / XY / 3ω analysis consumes `WorkbenchSelectedHitsSnapshot` when called from `WorkflowWorkspaceShell` (Phase 5C complete).
- `WorkbenchSelectedHitsSnapshot` is built from `WorkbenchSearchSnapshot` (canonical) with `cachedSearchResults` as `legacyHits` fallback.
- Nil-snapshot `runAnalysis()` is legacy/restore compatibility only.

### Phase 5A test plan

- title edit does not mutate search query/results/running/message
- legend edit does not mutate search query/results/running/message
- rerender path does not mutate search query/results/running/message
- selection toggle does not mutate query text
- workflow route switch preserves per-workflow search state by default
- mirror consistency after run/restore/clear while bridge still exists

## Analysis / Ingestion Boundary

- Canonical owner: each workflow store
  - `AHEWorkspaceStore`
  - `ThreeOmegaWorkspaceStore`
  - `XYRotationWorkspaceStore`
- Canonical state:
  - `ingestionResult`
  - `analysisTask` / `plotTask`
  - `isAnalyzing` / `isPlotRendering`
  - workflow-specific analysis parameters
- Workflow-local projections/caches:
  - `cachedInputFiles`
  - `cachedSampleKeys`
  - `cachedConditionsBySampleKey`
  - `_titleTokens`
  - `currentRunTrace`
  - `analysisMessage` / `plotMessage`
  - `persistenceOutcome`
- Forbidden reverse dependencies:
  - Render output must not replace ingestion state.
  - Canvas interaction must not mutate ingestion contracts.
  - Save-to-Library must not re-run analysis.

## Analysis Lifecycle Module Boundary (Phase 5D)

- Target contract owner: Analysis Lifecycle Module (default Main Board module)
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore`)
- Canonical state (contract):
  - analysis running / loading state (`isAnalyzing`, `isPlotRendering`, task handles)
  - user-facing message / error state (`analysisMessage`, `plotMessage`)
  - warning log (via `WorkbenchWarningLog`)
  - run trace (`currentRunTrace`)
  - workflow result / output state (`ingestionResult` and workflow-specific caches)
  - plot-ready output projection
  - save/pack-ready handoff data (stable post-analysis state)

### Analysis Lifecycle Module does not own

- canonical Search Module state (query, results, running, message)
- selected IDs except through explicit selection actions
- tab override state (owned by Preservation Module via `TabRenderState`)
- save-to-library write paths
- pack vault write paths
- physics logic (owned by Physics Function inside Workflow Assembly)

### Clear semantics

- `clearAnalysis` / `clearPlot`: belongs to Analysis Lifecycle Module
- `clearSearch`: belongs to Search Module
- `clearSelection`: belongs to Selection Module
- workflow-specific extras (e.g., 3ω `clearResults` RT-side cleanup): workflow-owned behavior inside Physics Function, not generic Analysis Lifecycle Module behavior

### Forbidden mutations

- analysis lifecycle state changes must not mutate canonical Search Module state
- rerender and restore paths must not commit trace
- analysis trigger must not write to save-to-library or pack vault
- Analysis Lifecycle Module must not read `TabRenderState` to decide ingestion inputs

### Handoff rules

- Analysis Lifecycle outputs plot-ready state to Plot Display / Preservation modules
- Save Module reads stable post-analysis output only
- Pack/Restore Module target: consume a stable `AnalysisResultSnapshot` envelope (deferred; current implementation reads ad hoc workflow store internals)

### Current transition state (Phase 5D-1 checkpoint)

- Analysis lifecycle state remains workflow-local in all three workflow stores
- `WorkbenchSelectedHitsSnapshot` is the run-scoped analysis input (Phase 5C complete)
- Phase 5D-1 tests lock current cross-module boundaries: no mutation of Search / Selection / Preservation state during analysis
- `AnalysisRunContext` / `AnalysisResultSnapshot` extraction deferred until contract and tests are stable

## Save Module Boundary (Phase 5E)

- Target contract owner: Save Module (default Main Board module)
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore+Persistence`)
- Canonical state (contract):
  - `persistenceOutcome` — set after each `persistToLibrary()` call; nil on `clearPlot()`
  - save status / message — current: `plotMessage` (AHE) or `analysisMessage` (XY / 3ω); target: dedicated `saveMessage` field (Phase 5E-3)
  - `currentRunTrace` — updated from `outcome.trace` after save

### Save Module does not own

- canonical Search Module state (`queryText`, `searchResults`, `isRunning`, `statusMessage`)
- `selectedSearchResultIDs` or `cachedSearchResults`
- tab override state (`TabRenderState` / `tabStates`) — owned by Preservation Module
- `ingestionResult` or any workflow output cache — owned by Analysis Lifecycle Module
- pack vault state (`activePackID`, vault contents) — owned by Pack / Restore Module
- analysis trigger or plot re-render

### Save Module read contract

- PNG: `TabRenderManager.activeImageData` (Preservation Module projection)
- Manifest payload: `TabRenderManager.activeManifestPayload` (Preservation Module projection)
- Sample keys and metrics: Workflow Assembly Save Metadata Provider (`ActiveChartProviding` protocol)
- Library root path: set by search flow; consumed as write target

### Save-side trace update rule

`currentRunTrace` is written from `outcome.trace` inside `persistToLibrary()` after a successful or partial save. This is the save-side trace update and is distinct from the analysis-side `commitRunTrace()` call. `persistToLibrary()` must never call `commitRunTrace()`.

### Forbidden mutations

- Save must not mutate canonical Search Module state
- Save must not mutate `selectedSearchResultIDs` or `cachedSearchResults`
- Save must not mutate tab override state (`TabRenderState`)
- Save must not mutate `ingestionResult` or workflow output caches
- Save must not call `commitRunTrace()` (analysis-side only)
- Save must not re-trigger analysis or plot re-render

### Current transition state (Phase 5E-2 checkpoint)

- `persistToLibrary()` remains workflow-local in all three workflow stores
- `SaveActiveChartToLibraryUseCase` is already a generic, workflow-agnostic write path
- All three workflow stores now use `saveMessage` field; `refreshRelatedCharts()` called after save in all three
- Phase 5E-2 boundary tests complete
- Shared save coordinator extraction deferred to Phase 5E-3

## Pack / Restore Module Boundary (Phase 5F)

- Target contract owner: Pack/Restore Module
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore+Pack.swift`)

Pack/Restore is the **only module** allowed to write multiple module states simultaneously, and only through the explicit restore contract documented in [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md). This is not a general permission for cross-module mutation — it is a bounded exception for workspace restoration.

### Forbidden mutations

- Restore must not write `persistenceOutcome`, `saveMessage`, `analysisMessage`, `currentRunTrace`, or `warningLog` — these are session-only and excluded from all pack formats
- Restore must not write `activePackID` inside `restoreFromPack()` — `activePackID` is set by the `loadPack()` caller after restore returns
- Restore must not call `runAnalysis()` or `commitRunTrace()` — except the documented AHE legacy exception for packs with nil `ingestionResult`
- Restore must not treat `cachedSearchResults` as canonical search state — canonical state is written only through the explicit `restoreSearchState` callback to `WorkbenchFeatureStore`
- Restore must not serialize or restore active PNG / manifest / layout output — these are re-derived by the re-render call at the end of restore
- Save must not be triggered by restore — no pack format may encode `persistenceOutcome` or save-side state

### What restore is allowed to write (summary)

Full write map: [`modules/PACK_RESTORE.md` § Restore Write Map](modules/PACK_RESTORE.md#restore-write-map). Key categories:

- search mirror (`cachedSearchResults`) and canonical search state (via `restoreSearchState` callback)
- selection IDs (`selectedSearchResultIDs`)
- analysis result (`ingestionResult`, `scalingResult`)
- plot preservation state (`tabStates`, `chartStyleOverrides`, `activeTab`, `showPlotGrid`, `legendAnchor`) through `TabRenderManager.restoreStates()`
- workflow-specific physics parameters (geometry, fit ranges, phi offsets, etc.)
- local pack inputs (`cachedInputFiles`, `cachedSampleKeys`)
- library root dependency (`lastLibraryRootPath` from vault)

### Tests

Phase 5F-3 boundary tests: see [`modules/PACK_RESTORE.md` § Boundary Test Plan](modules/PACK_RESTORE.md#boundary-test-plan-phase-5f-3).

## Render / Output Boundary

- Canonical owner: `TabRenderManager`
- Canonical state:
  - `activeTab`
  - `tabStates`
  - `tabOutputs`
  - shared render settings (`showPlotGrid`, `seriesRenderMode`, `chartStyleOverrides`)
- Projections:
  - `activeImageData`
  - `activeLayout`
  - `activeManifestPayload`
  - `activeSeriesLabelOverrides`
- Forbidden reverse dependencies:
  - Workflow stores must not keep a second canonical copy of rendered image/layout/manifest output.
  - Plot rendering code must not write directly into canvas UI state.
  - `activeImageData` must remain a projection over `tabOutputs`.

## Canvas Interaction Boundary

- Canonical owner: `TabRenderManager` for canvas-owned plot state; workflow store for workflow data.
- Canonical state:
  - legend position
  - title / axis / label overrides
  - per-series ordering
  - point-label visibility
- Projections:
  - `WorkbenchPlotCanvas` receives `imageData`, `layout`, `seriesLabelOverrides`, `seriesPayload`, and related chart data as read-only inputs.
- Forbidden reverse dependencies:
  - Canvas must not own canonical plot output or ingestion state.
  - Canvas must not mutate search results or library storage state.

### Series Reorder Boundary

Series reorder is a Plot Controls Module concern, not a canvas concern.

- Canvas must not own or trigger series reorder. Direct curve hit-test reorder is forbidden.
- Reorder intent (`updateSeriesOrder([seriesKey])`) must flow from Plot Controls Module → workflow store → render pipeline.
- The render pipeline applies order; canvas code must not mutate render geometry to achieve reorder.
- Reorder identity is the per-series `sourceRef` key, not `sampleID`.

Full series reorder contract and review checklist: [`modules/PLOT_SYSTEM.md` § Series Reorder Contract](modules/PLOT_SYSTEM.md).

## Phase 4: Plot Preservation Module (Plot System Module Group)

Boundary: no module other than Plot Preservation may write `TabRenderState` override fields or call `clearStates()`. `TabRenderManager` is the single owner of override state and render output.

**Enforcement**: `XYRotationWorkspaceStore.runAnalysis()` previously called `tabs.clearStates()` (Phase 4 regression); removed in 5.3.7.

Tests: `V537WorkflowShellPhase4Tests` (AHE + XY), `V563WorkflowStateBoundaryTests` (TabRenderManager + 3ω).

## Module Override Boundary (Phase 3)

- Canonical owners: each override is owned by its respective module; workflow function output is separate.
- Canonical state:
  - `defaultPlotPayload` — produced by Workflow Function; read-only input to the composer.
  - `titleOverride` — owned by the title module.
  - `legendOverride` — owned by the legend module.
  - `axisLabelOverride` — owned by the axis-label module.
  - `seriesOrder` — owned by the series-order module.
- Composition:
  - `WorkflowWorkspaceShell` (parent composer) merges `defaultPlotPayload` with the four override layers to produce the final display payload.
  - No sibling module may perform this merge.
- Forbidden reverse dependencies:
  - Plot-control changes must not reset search or selection state.
  - Title, legend, or axis-label overrides must not depend on each other's state.
  - Override modules must not read from `tabOutputs` or `activeImageData`.
  - Workflow Function output (`defaultPlotPayload`) must not be mutated by any module.

## Persistence Boundary

- Canonical owner: `SaveActiveChartToLibraryUseCase`
- Canonical state:
  - `SaveActiveChartInput`
  - persistence validation
  - chart/metric write orchestration
- Lower-level path ownership:
  - `LibraryPathResolver` owns canonical root-relative path construction.
  - `LibraryRootAccess` owns library-root discovery and security-scoped traversal.
- Projections:
  - `PersistenceOutcome`
  - `WorkbenchRunTraceProjection`
- Forbidden reverse dependencies:
  - Persistence must not depend on canvas internals.
  - Save logic must not bypass `LibraryPathResolver`.
  - Search must not become the path-resolution authority for writes.

## Canonical Identity and Duplicate Identity

- Stable sample identity:
  - `sampleID` is the preferred stable series identity for reorderable payloads.
- Search identity:
  - `WorkflowMeasurementSearchHit.id` is a selection/UI identity, not the same thing as sample identity.
- Chart identity:
  - `WorkbenchChartIdentity.makeIdentityKey(from:)` identifies persisted chart artifacts.
- Remaining duplicate identity surfaces:
  - `selectedSearchResultIDs` duplicates information already present in `cachedSearchResults`.
  - legacy Int-string series keys still exist in `TabRenderState` migration paths.

### Workflow ID Mapping

| Old ID | New ID | Workflow |
|--------|--------|----------|
| `A` | `ahe` | AMR/PHE (Anomalous Hall Effect) |
| `B` | `3w` | 3 Omega |

Pre-v4.1.3 `"A"` / `"B"` IDs in sidecar files or persisted JSON are legacy artifacts. No backward-compatibility code exists — replace with new IDs. Search accepts both old and new IDs as query aliases; all persisted data uses new IDs only.
