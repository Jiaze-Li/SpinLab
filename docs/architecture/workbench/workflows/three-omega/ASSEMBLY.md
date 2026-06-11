# 3-Omega Workflow Assembly

> Semantic assembly audit for the 3-Omega workflow.

## Reality Check

- Workflow ID: `3w`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`.
- There is no runtime Assembly object. The workflow contract is distributed across registry dispatch, workspace view/store extensions, parser, fitting/scaling/render use cases, domain contracts, pack contracts, and tests.
- Common Main Board behavior stays out of this record: default search execution, selection mechanics, analyze/save lifecycle, plot-canvas internals, related-chart hover behavior, and default pack button behavior.
- 3ω is the only audited workflow with a workflow-specific secondary input search slot: an RT/Rxx(T) auxiliary input for scaling. It also has a current RAHE "Add Analysis" overlay surface on RAHE tabs, and the next target is a Scaling Law overlay fed by saved 3ω packs with `scalingResult`. These are current instances of the general optional Secondary Input Search / Analysis Overlay patterns, not hard-coded 3ω-only modules.

## Search Hints

| Semantic item | Current behavior | Trace |
|---|---|---|
| Workflow match token | Workflow config matches token `3w`; RT is a separate workflow config row matching token `rt`. | `Sources/SpinLabApp/config/workflow.json`; `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` |
| Search aliases | `3w` and `3omega` are search aliases; `ω`/`Ω` normalize to `w`. | `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift`; `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift` |
| Secondary Input Search slot | 3ω declares one auxiliary search slot for RT/Rxx(T) input. It has independent query/results/selection state, persists the auxiliary query text, can select a dedicated auxiliary hit, and can rebuild that hit from a restored sidecar/file bridge. The semantic target is RT/Rxx(T), but the current runtime path is still generic and does not yet enforce an RT-only whitelist. Slot state is owned by `WorkbenchSecondaryInputSearchRuntime` (Gate 7.3); `ThreeOmegaWorkspaceStore` provides forwarding compatibility and workflow semantics. | `Sources/SpinLabApp/App/State/WorkbenchSecondaryInputSearchRuntime.swift` (slot-state owner, Gate 7.3); `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` (forwarding, workflow semantics); `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` |
| Result mirror | Main 3w search results use the common `cachedSearchResults` bridge for selection, title context, pack restore, and legacy fallback. The secondary input slot adds separate workflow-local state beyond the common bridge. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` |

## Secondary Input Search Slot Contract

Slot state is owned by `WorkbenchSecondaryInputSearchRuntime` (Gate 7.3). `ThreeOmegaWorkspaceStore` retains workflow semantics, RT eligibility/whitelist policy, analysis contribution, and forwarding compatibility properties.

| Contract field | 3ω instance |
|---|---|
| Slot ID | `rt` |
| Display label | `RT / Rxx(T)` |
| Query default / search hint / workflow filter | The stored query text is `rtQuery`; the slot hint points the user at RT/Rxx(T) auxiliary files. Current runtime behavior still routes through the generic search path and does not enforce an RT-only whitelist. |
| Allowed workflow IDs / file kinds | Target contract: `rt` file-kind / RT sweep files only. Current runtime: generic hits may still be accepted through the sidecar/search bridge, so this whitelist is not yet fully enforced. |
| Selection mode | Single-select. |
| Requiredness | Optional in the workspace, but required for scaling and any RT-dependent result surfaces. |
| Analysis contribution | The selected auxiliary RT hit supplies the Rxx(T) input used by scaling. It does not mutate Main Search and does not trigger analysis by itself. |
| Pack fingerprint | Yes. The auxiliary RT file identity participates in 3ω pack identity. |
| Persisted fields | `rtQuery`, `selectedRTHit`, and the stable sidecar bridge field (`pendingRTSidecarPath`). `cachedRTFilePath` is currently derived output from `selectedRTHit` / manifest snapshot, not a standalone restore input (deferred to Gate 7.6). Search results, message, and running state remain session-only. |
| Restore bridge behavior | Restore can rebind the slot from a pending sidecar path or cached file path, then rerender from the restored state. The bridge may accept current `3w` or `rt` auxiliary sidecars, so it is not yet an RT-only validator. |
| Warning behavior | Missing or invalid RT input warns that Rxx(T)-dependent outputs such as Scaling Law are unavailable. Invalid or ambiguous RT selection must not backfill from Main Search. |
| Multiple-slot support | 3ω uses one slot today, but the contract must support future workflows such as SOT declaring multiple independent auxiliary slots. |

## Data / Physics Mapping Contract

| Semantic item | Current behavior | Trace |
|---|---|---|
| Accepted file formats | Zurich Instruments `.lvm` files. Field sweeps and RT sweeps share the parser but differ by file kind. | `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift`; `Sources/SpinLabApp/Workbench/Domain/ThreeOmegaIngestionDomain.swift` |
| Parser entry point | `ThreeOmegaLVMParser.parse(fileURL:temperatureOverride:kindOverride:)` parses positional numeric rows after `Tableau:` or first numeric line fallback. | `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift` |
| Field-sweep column mapping | Column 0 H in Oe, column 1 V1ω_X, column 5 V3ω_X, column 9 R_H. `I_rms = mean(col1 / col9)`. Field-sweep temperature prefers sidecar override, then filename `T_<value>K`. | `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift`; `Sources/SpinLabApp/Workbench/Domain/ThreeOmegaIngestionDomain.swift` |
| RT column mapping | For RT files, column 0 is temperature K and column 9 is Rxx. RT files have no single field-sweep temperature. | `Sources/SpinLabApp/Workbench/Domain/ThreeOmegaIngestionDomain.swift`; `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` |
| File-kind mapping | Sidecar canonical workflow ID overrides filename heuristic: `rt` → RT sweep, `3w` → field sweep. Without override, filename containing `_RT_` or prefix `RT_` becomes RT; otherwise field sweep. | `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift`; `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` |
| Unit conversions | Renderer converts H Oe to T for R(1ω)/R(3ω) plots. Scaling converts geometry nm/μm to m, sigma display units to `10^7 S^2/cm^2`, and Y display units to `Ω·μm^3·V^-2 × 10^2`. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift` |
| Derived quantities | Fit use case derives R1ω/R3ω from voltage/current, centers, subtracts linear background, extracts V3ω_AHE by window average and high-field extrapolation, extracts RAHE/Hc, and stores sweep-level results. Scaling derives rho, sigma, E_xx, E3ω_AHE, scaling points, alpha/beta/R² segments. | `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift`; `docs/architecture/workbench/workflows/three-omega/THREE_OMEGA_PHYSICS.md` |
| UI overrides | Geometry, fit ranges, V3ω method, RAHE methods, RT selection, stack offset, gap fraction, title template, grid, chart style, point labels, and series order are workflow-controlled state. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` |

## Analysis Pipeline

| Stage | Current behavior | Trace |
|---|---|---|
| Parse | Parse selected LVM files; sidecar conditions provide device/temperature/file kind when available. | `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift`; `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` |
| Ingest | Deduplicate selected files, split field sweeps from RT files, fit each field sweep, sort by temperature, collect `I_rms` by temperature, and choose RT result from dedicated RT hit or longest RT file among selections. | `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` |
| Transform/fit | Field-sweep fitting derives centered/background-subtracted R1ω/R3ω, V3ω_AHE, RAHE, and Hc. Scaling combines field sweeps, RT interpolation, geometry, I_rms, fit ranges, and selected V3 method. | `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift` |
| Render payload | Renders field-sweep tabs, RAHE vs T tabs, Hc vs T, RT, and Scaling Law through `ThreeOmegaPlotRenderer` and the common render pipeline. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` |
| Metrics | Scaling result carries alpha, beta, R², point count, and participating x values. RAHE/Hc are stored in field-sweep results. | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift`; `Sources/SpinLabApp/Domain/ThreeOmegaScalingResult.swift` |
| Warnings/failure | Parse failures, HFE/WA divergence, multiple RT files, mixed device angles, missing RT, incomplete geometry, missing Rxx/I_rms, invalid rho/E/non-finite scaling, too few scaling points, fit-range overlap, and degenerate segment fits all produce warnings. | `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift`; `Tests/SpinLabAppTests/V413ThreeOmegaFitUseCaseTests.swift`; `Tests/SpinLabAppTests/V41216ThreeOmegaScalingUseCaseTests.swift` |

## Optional Contributions

| Contribution | Assembly-owned semantics | Trace |
|---|---|---|
| Secondary Input Search field/popover | Dedicated RT/Rxx(T) auxiliary selection is required for scaling when that file is not part of the main selection. This is the `rt` slot instance of the general optional module pattern, not a default RT module. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift` |
| Geometry panel | Scaling requires Lxx, Lxy, and thickness geometry. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`; `Sources/SpinLabApp/Domain/ThreeOmegaGeometry.swift` |
| Fit ranges panel | Scaling can fit full range or independent temperature ranges. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift` |
| Scaling result panel | Displays alpha, beta, R², and segment status. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`; `Sources/SpinLabApp/Domain/ThreeOmegaScalingResult.swift` |
| RAHE overlay controls | RAHE tabs can overlay saved packs and choose RAHE extraction method per harmonic. This is the current overlay instance and stays display-only. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift` |
| Scaling Law overlay controls | Scaling Law overlays selected 3ω packs with `scalingResult`, renders scaling data points and fit line(s), disables or rejects packs without `scalingResult`, and never creates a combined pack or mutates the primary scaling result. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` |

## Plot Contract / Overrides

| Semantic item | Current behavior | Trace |
|---|---|---|
| Common plot behavior | Plot canvas interactions, style editor, copy PNG, legend positioning, label overrides, and tab state preservation are common shell behavior. | `docs/architecture/workbench/modules/PLOT_SYSTEM.md`; `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift` |
| Tabs | Field-sweep R(1ω), field-sweep R(3ω), RAHE(1ω) vs T, RAHE(3ω) vs T, Hc vs T, RT, and Scaling Law. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkbenchTab.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift` |
| Field-sweep axes | R(1ω)/R(3ω): x `H (T)` from Oe/10000; y `R(1ω) (Ω)` / `R(3ω) (Ω)`. Series are stacked by temperature, legend reversed, and reorderable. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Tests/SpinLabAppTests/V563ThreeOmegaFieldSweepSeriesOrderTests.swift` |
| RAHE/Hc axes | RAHE tabs use x `T (K)` and y `RAHE(1ω/3ω) (Ω)`. Hc tab uses x `T (K)` and y `Hc (Oe)`. RAHE method tag is part of title and semantic params for overlays. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Tests/SpinLabAppTests/V4116ThreeOmegaRAHETests.swift` |
| RT axes | RT tab uses x `T (K)` and y `Rxx (Ω)` from RT column 9. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Tests/SpinLabAppTests/V413ThreeOmegaFitUseCaseTests.swift` |
| Scaling axes and annotations | Scaling plot uses display-unit conversions and includes fit lines. R² is included in title only for a single full-range fit. Point labels are temperatures. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Tests/SpinLabAppTests/V41216ThreeOmegaPlotRendererTests.swift` |
| Title/legend | Default title template `#tab #method #device #sample` is Assembly-owned (Layer 1 of the three-layer title model; see `docs/architecture/workbench/modules/PLOT_SYSTEM.md`). The editable template state (`titleTemplate` on the workspace store) is workflow-store-owned boundary debt; the per-tab inline title override is `TabRenderState.titleOverride` (Plot Preservation-owned). Field-sweep series labels default to temperature. | `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` |
| Stack offset and gap fraction | `stackOffsetMultiplier` (default 1.2) and `minGapFraction` (default 0.15) are Assembly-owned plot semantic parameters governing curve spacing in stacked field-sweep tabs. 3ω uses `WorkbenchStandardPlotControls` for the common tab/stack/title/grid layout; these parameters bind into that View but are owned and serialized by the 3ω workspace store. `legendAnchor` is captured manually in all 3ω rendering paths (read from `tabs.legendAnchor`, passed to `ThreeOmegaPlotRenderer.legendAnchor`) rather than through `TabRenderManager.buildPipelineInput` — a consequence of 3ω's custom renderer architecture, not a boundary violation. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift` |

## Validation / Warning Policy

- Parser errors identify missing marker/data rows, insufficient columns, temperature resolution failure, and I_rms derivation failure.
- Parse errors are converted to ingestion warnings with file names.
- Multiple RT files warn and choose the one with most rows unless a dedicated RT hit is selected.
- Missing RT warns that Rxx(T) and Scaling Law are unavailable.
- Scaling Law overlay packs without `scalingResult` are disabled or rejected clearly.
- Mixed device angles warn and switch device metadata to `angle_sweep`.
- Geometry must be complete and positive for scaling; incomplete geometry returns a warning and no scaling points.
- Scaling skips points with missing RT interpolation, missing I_rms, invalid rho/E values, non-finite results, or insufficient fit points, and reports why.
- Method divergence warnings exist for RAHE(1ω) HFE/WA and V3ω extraction methods.

## Persistence / Pack-Restore Contract

| State | Current persistence behavior | Trace |
|---|---|---|
| Analysis parameters | Saves device, geometry, fit ranges, V3 method, RAHE 1ω/3ω methods, RT file path, and sample display context. | `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` |
| Display state | Saves active tab, title template, stack offset, gap fraction, grid flag, legend anchor, per-tab render states, and chart style overrides. | `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift` |
| Overlay save policy | Session-only in pack/restore; current RAHE overlay may include overlay series/sample provenance in the saved chart artifact/manifest, while future Scaling Law overlays must explicitly declare saved-manifest/sample-key policy before implementation. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`; `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift` |
| Search/selection state | Saves main cached search results, selected IDs, selected auxiliary RT hit, RT query, and main search query text. The auxiliary slot bridge is workflow-local, not Main Search-owned. | `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift` |
| Overlay state | Session-only in v1; overlay pack IDs and snapshots are not serialized into pack content and restore clears them before rerender. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` |
| Result snapshot | Saves `ThreeOmegaIngestionResult` and optional `ThreeOmegaScalingResult` so restore can rerender without re-ingestion. | `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` |
| Restore bridge | Restore reapplies search state, selected auxiliary RT hit or pending RT sidecar/file path, library root, and rerenders manifests. Restore writes through the forwarding/runtime path (`ThreeOmegaWorkspaceStore` forwarding → `WorkbenchSecondaryInputSearchRuntime`). `cachedRTFilePath` is derived output from `selectedRTHit` / manifest snapshot; standalone rebuild from `cachedRTFilePath` alone is not implemented (deferred to Gate 7.6). If the bridge does not resolve, the slot stays unbound and the workflow warns. | `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`; `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift`; `Sources/SpinLabApp/App/State/WorkbenchSecondaryInputSearchRuntime.swift` |

## Save Metadata / Metric Contract

Target owner: 3ω Assembly owns alpha, beta, R², and any RAHE/Hc semantics where the workflow exposes them. The common Save module owns the generic write path only.

| Concern | Current state |
|---|---|
| Metric definitions | Alpha, beta, and R² are Assembly-owned scaling metrics. RAHE/Hc remain Assembly-owned analysis outputs when present. |
| Current implementation surface | `ThreeOmegaScalingUseCase` computes `scalingResult`; `ThreeOmegaWorkspaceStore.buildActiveChartMetrics()` emits `PendingMetricEntry` records only for the active scaling tab, currently using record keys `alpha`, `beta`, and `r_squared` plus range/v3method/device conditions. `persistToLibrary()` forwards those entries to `SaveActiveChartToLibraryUseCase`. Overlay-derived metrics stay out of this projection in v1. |
| Forbidden ownership | Common save code must not infer 3ω physics, units, or when metrics are valid; it may only persist the provided projection. |
| Pack/restore implications | Geometry, fit ranges, V3/RAHE methods, RT state, and active tab restore so save-after-restore works, but `persistenceOutcome`, saved metric records, and overlay-derived metrics stay out of pack content. If scaling state is absent, no metrics are emitted. |
| Tests protecting current behavior | `V413ThreeOmegaFitUseCaseTests`, `V41216ThreeOmegaScalingUseCaseTests`, `V537SaveModuleBoundaryTests`, `V4111SaveActiveChartToLibraryUseCaseTests`, `V537PackRestoreModuleBoundaryTests`. |
| Extraction readiness | Medium. The workflow already derives the metrics, but the save bridge is still a generic `PendingMetricEntry[]` rather than an explicit save metadata projection. |
| Exit condition | 3ω exposes a typed save metadata projection for the scaling tab that names metrics, units, conditions, and semantic identity without common save code reading `scalingResult` or deriving physics. |

## Required Behavior Tests

| Behavior class | Current coverage | Missing / later consideration |
|---|---|---|
| Data mapping | Parser/ingestion tests cover field sweep, RT sweep, sorting, multiple RT selection, and RT warnings. | Add explicit sidecar kind override tests before changing RT/3w workflow-ID mapping. |
| Unit conversion | Fit/scaling tests cover current voltage/current and scaling formulas; plot renderer tests cover display payload behavior. | Add direct plot payload assertions for H Oe→T if field units change. |
| Analysis pipeline | Fit use case tests cover V3ω window/HFE, RAHE, Hc, RT render, ingestion sorting, and pipeline outputs. Scaling tests cover formula and fit behavior. | No single Assembly manifest test exists. |
| Warning/failure | Coverage includes multiple RT warnings, insufficient high-field points, empty sweeps, geometry/scaling failure classes, and renderer warning independence. | Add explicit tests for mixed device-angle warning if device-mode semantics change. |
| Pack/restore | Pack contracts, secondary input restore bridge, search snapshot consumption, field-sweep series order, and workflow state boundary tests cover restore-sensitive behavior. | Add restore tests around `selectedRTHit` vs `pendingRTSidecarPath` before extracting pack or Secondary Input Search modules. |
| Plot semantics | Renderer tests cover RAHE, scaling, stack offsets, point labels, series order, and tab-state override survival. | Add explicit R²-title single-vs-segment tests if scaling title rules change. |

## Findings Summary

- Common and out of Assembly: common Workbench search, selection, analyze/save lifecycle, plot-canvas internals, common render pipeline, and common pack button mechanics.
- Assembly-owned: `3w`/`3omega` identity and the `rt` secondary RT/Rxx(T) input contribution, LVM positional mapping, sidecar-driven file kind/device/temperature mapping, 3ω fitting/scaling formulas, geometry/fit-range/method state, multi-tab plot semantics, RAHE overlays, Scaling Law overlay eligibility and warnings, and auxiliary-input restore metadata.
- Currently implicit/distributed: the 3ω Assembly is partly explicit in physics docs but runtime behavior is spread across parser/use cases/store extensions; secondary input search is workflow-local state rather than a formal optional module; overlay eligibility is still assembly-declared rather than module-owned; scaling availability is warning-driven rather than readiness-gated.
- Later Gate 3 / Gate 7 consideration: Secondary Input Search may deserve module-boundary treatment, but extraction must preserve the general auxiliary-slot pattern and 3ω Assembly-owned semantics. Scaling warning policy should be locked further before moving analysis or pack/restore behavior into shared coordinators.
