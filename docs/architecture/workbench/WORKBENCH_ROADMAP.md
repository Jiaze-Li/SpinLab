# Workbench - Shell Migration Roadmap

> Canonical phase progress and migration sequence for Workbench shell architecture.

## Purpose

This document is the single source of truth for Workbench shell migration phase status.

Use this file to track:

- completed phases
- current and upcoming phases
- completion criteria per phase
- the current gate plan

Detailed architecture contracts remain in sibling docs. This file tracks progress, not contract details.

## Phase Taxonomy

Workbench modularization phases fall into three categories:

**Framework / Governance** — architecture language, routing rules, Workflow / Workflow Assembly / Main Board / Modules terminology, docs/index alignment.

**Boundary Stabilization** — module ownership contracts, forbidden mutations, transition read surfaces, regression gates, and guardrails.

**Runtime Extraction** — coordinator extraction and removal of duplicated workflow-local implementations.

5.3.7 completed the first two categories. The third category is post-5.3.7 work.

## Gate Plan

Gates 1 through 7 are complete. Gate 7.9 is the architecture closeout. Gate 8 remains the next planned validation dry run.

| Gate | Status | Scope |
|---|---|---|
| Gate 1 | complete | Record Architecture Decisions / Finalize Gate Plan |
| Gate 2 | complete | Workflow Assembly Audit & Contract Validation |
| Gate 2.1 | complete | Workflow Semantic Assembly Audit |
| Gate 3 | complete | Module Audit & Contract Validation |
| Gate 4 | complete | Layout Audit |
| Gate 5 | complete | Layout Refactor |
| Gate 6 | complete | Readiness Consumption |
| Gate 7 | complete | Module Extraction Program |
| Gate 7.9 | complete | Workbench Architecture Closeout (docs) |
| Gate 8 | in progress | New Workflow Dry Run |
| Gate 8.1 | complete / PR #131 | IV Workflow — Phase A+B |

Gates 1 through 7 are closed out. Gate 7 completed the module extraction program across sub-gates 7.1–7.8. Gate 7.9 closes out the architecture documentation. Gate 8.1 (IV workflow) is complete as of PR #131. Deferred runtime cleanup items and non-candidates are classified in `MODULE_BOUNDARIES.md` and `history/gate7/GATE7_WORKBENCH_ARCHITECTURE_CLOSEOUT.md`.

Gate 8.1 (IV workflow — complete, PR #131): Full IV workflow wired across all five registration surfaces. V vs I and R vs I physics rendering live. X-axis displays in mA with Peak/RMS basis selectable via `xCurrentBasis`. Stacking supported via `stackOffsetMultiplier` / `minGapFraction`. Pack/restore round-trips all IV workspace state. Main Board unmodified. No existing module state touched. Assembly record: `docs/architecture/workbench/workflows/iv/ASSEMBLY.md`.

### Gate 2 - Workflow Assembly Audit & Contract Validation

Reference:

- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)

Purpose:

- Audit current AHE / XY Rotation / 3ω workflows
- Extract actual workflow assemblies
- Validate the Assembly Contract

Clarify:

If real workflows cannot be described cleanly by the current contract:

- Update `WORKFLOW_ASSEMBLY.md`

Do not force workflows into an incorrect contract.

Acceptance:

- Every workflow has an Assembly Record
- Every Assembly Record maps to real implementation files
- Every Assembly Record explains how the workflow operates
- Assembly Contract has no obvious missing sections
- Assembly Contract has no known invalid assumptions

Result:

- Assembly Contract v1.0
- Completed via PR #96 (`docs: record workflow assembly mappings`)

### Gate 2.1 - Workflow Semantic Assembly Audit

Reference:

- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)
- [workflows/ahe/ASSEMBLY.md](workflows/ahe/ASSEMBLY.md)
- [workflows/xy-rotation/ASSEMBLY.md](workflows/xy-rotation/ASSEMBLY.md)
- [workflows/three-omega/ASSEMBLY.md](workflows/three-omega/ASSEMBLY.md)

Purpose:

- Refine Assembly from "complete content and configuration" to workflow-owned semantic contract
- Keep common Main Board and default module behavior out of per-workflow Assembly records
- Audit AHE / XY Rotation / 3ω for search hints, data/physics mapping, analysis pipeline, optional contributions, plot semantics, validation policy, persistence, and behavior-test obligations
- Report contradictions instead of forcing code into a runtime Assembly-object model

Result:

- Assembly Contract v1.1
- Common search, selection, analyze/save lifecycle, plot shell internals, and default module behavior remain outside Assembly
- Workflow-specific semantics are now mapped to distributed implementation files and behavior-test classes
- Contradictions captured: AHE `R_H (Ω)` is a semantic default resolved to bridge resistance/resistivity columns, XY is search-tokenized from config rather than a `WorkflowID` case, and 3ω has workflow-specific RT search state that is not a common search module
- Documentation-only follow-up; no Swift code or runtime extraction

### Gate 3 - Module Audit & Contract Validation

Reference:

- [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md)

Purpose:

- Determine actual module inventory
- Validate module ownership rules
- Validate module boundaries

Clarify:

If current modules contradict the contract:

- Update `MODULE_BOUNDARIES.md`

Do not force modules into an incorrect contract.

Examples of rules to validate:

- ownership
- canonical state
- capability boundaries
- read surfaces
- forbidden mutation
- sibling isolation

Acceptance:

- Actual module inventory identified
- Ownership defined
- State ownership defined
- Capability ownership defined
- Known exceptions documented
- Contract updated if necessary

Result:

- Module Contract v1.0
- Module Inventory v1.0

### Gate 4 - Layout Audit

Purpose:

- Validate current `WorkflowWorkspaceShell` layout
- Distinguish Layout vs Module vs Assembly Contribution

Result:

- Complete
- Detailed layout audit history remains in `history/gate4/LAYOUT_AUDIT.md`

### Gate 5 - Layout Refactor

Purpose:

- Refactor layout only
- No behavior changes

Completed substeps:

- Gate 5.1 shell split complete
- Gate 5.2 pack/status layout cleanup complete

Completion note:

- Shell is thinner.
- Load Pack placement is explicit.
- Status / trace / warning layout is explicit.
- Search / selection / save / pack / warning ownership is unchanged.
- No module extraction was performed.

Result:

- Complete
- Layout-only refactor only; no runtime module extraction
- Detailed placement notes remain in `MAIN_BOARD_LAYOUT.md`

### Gate 6 - Readiness Consumption

Purpose:

- Connect `WorkbenchReadinessProjection` to:
  - button gating
  - status display
  - preflight checks

Result:

- Gate 6 complete
- Gate 6.1 audit recorded the current readiness projection producer, direct consumers, and direct readiness-adjacent checks
- Gate 6.2 consumed readiness in the action bar for Select All, Analyze, and progress display
- Gate 6.3 closed out the remaining explicit boundaries without moving pack-state, library-root, or Load Pack logic into readiness

#### Gate 6.1 - Readiness Consumption Audit

- Status: complete
- Scope: record the current readiness projection producer, current direct consumers, direct readiness-adjacent checks, and Gate 6.2 safe replacement candidates.
- Result: `history/gate6/READINESS_CONSUMPTION_AUDIT.md`
- Notes:
  - This is audit and discoverability work only.
  - No Swift runtime changes were made.
  - The audit now documents the implemented narrow action-bar readiness consumption and the explicit non-readiness result-header and pack-state boundaries.

#### Gate 6.2 - Readiness Consumption UI Wiring

- Status: complete
- Scope: consume `WorkbenchReadinessProjection` in the shell surfaces that already gate result-ready, active-image, and running-style UI state while preserving `matchingVaultPack`, `activePackID`, and analysis-vault pack-state logic.
- Result: action bar uses readiness for Select All, Analyze, and progress gating while library-root search preflight and direct search-running checks remain explicit.

#### Gate 6.3 - Readiness Closeout

- Status: complete
- Scope: tighten the remaining direct readiness-adjacent checks that stay outside the projection and record the final Gate 6 closeout state.
- Result: the result header, pack-state logic, library-root preflight, and Load Pack availability remain outside readiness.

### Gate 7 - Module Extraction Program

Status: complete (sub-gates 7.0–7.8 closed; Gate 7.9 docs closeout).

The extraction order below is the Gate 3 Final plan; all sub-gates are now closed. Deferred runtime cleanup items and non-candidates are recorded in `MODULE_BOUNDARIES.md` and `history/gate7/GATE7_WORKBENCH_ARCHITECTURE_CLOSEOUT.md`.

### Gate 3 Final / Gate 7 Extraction Plan

Summary:

- Common modules are runtime extraction targets.
- Optional module candidates are workflow-declared capability slots, not one-off workflow features.
- Boundary debt items are cleanup paths that require explicit bridge and restore coverage before extraction.

| Gate | Module / boundary name | Classification from Gate 3 | Target owner | Notes |
|---|---|---|---|---|
| 7.0 | Main Search extraction handoff audit | docs-only | n/a | Completed handoff audit; no runtime extraction. Gate 7.1 is complete. |
| 7.1 | Main Search | Common module | Common Search module | Canonical search state is already centralized; finish runtime extraction while preserving the explicit restore bridge and pack compatibility. |
| 7.2 | Selection | Boundary debt → Module-owned | Common Selection module | Complete. `WorkbenchSelectionRuntime` is the canonical owner. Workflow-local `selectionReading` typed bridge is the non-canonical compatibility read surface (migrated from raw closure to typed `SelectionReading` protocol in Gate 7.7B). |
| 7.3 | Secondary Input Search | Optional module candidate | Common auxiliary-slot Secondary Input Search module | Complete. `WorkbenchSecondaryInputSearchRuntime` is the canonical slot-state owner. `ThreeOmegaWorkspaceStore` retains workflow semantics and forwarding compatibility. |
| 7.4 | Analysis Overlay | Optional module candidate | Common Analysis Overlay module | Complete. `WorkbenchAnalysisOverlayRuntime` owns overlay IDs and chip display labels. `ThreeOmegaWorkspaceStore` retains snapshot content, rendering semantics, and active-tab rerender trigger. |
| 7.5 | Save to Library / Save Metadata Projection | Boundary debt | Split: common save writer + Assembly-owned semantic projection | Save writer is common; metric meaning, units, overrides, and semantic projection stay Assembly-owned. |
| 7.6 | Pack / Restore | Boundary debt | Common Pack / Restore module | Explicit restore write map required; include secondary input search and keep restore rerender-only. |
| 7.7 | Warning Display / Run Trace | Boundary debt | Split: common warning/trace display + Assembly-owned event sources | Centralize warning and trace projections without moving physics meaning into the display module. |
| 7.8 | Plot System module group audit and structural guards | Common module group | Common Plot System plus control modules | Complete. Boundaries clarified; `currentRunTrace` removed from plot protocol; Main Board layout confirmed outside Plot System; structural guards added. |
| 7.9 | Workbench Architecture Closeout | Docs | n/a | Complete. Roadmap updated; module boundary authority reframed; Gate 3 follow-ups classified; closeout doc added. |

#### Gate 7.0 - Main Search extraction handoff audit

- Status: complete, docs-only
- Source audit file: `docs/architecture/workbench/history/gate7/GATE7_MAIN_SEARCH_HANDOFF.md`
- Purpose: record the exact canonical Main Search ownership map, workflow-local mirror map, bridge state, restore paths, and test coverage that must remain intact before any runtime extraction begins.
- Gate 7.1 is complete.

#### Gate 7.1 - Main Search

- Source Gate 3 audit section: `Main Search`
- Classification: `Module-owned — common module`
- Actual Gate 3 finding: canonical search state is already centralized, but workflow stores still keep mirror state for pack compatibility and the select-all denominator.
- Target owner: common Search module, with workflow stores reduced to mirrors only where an explicit bridge is still required.
- Required work: finish runtime extraction of query, result, running, and status state; keep `restoreSearchState` as the explicit canonical restore path; retire workflow-local search ownership once pack and selection bridges are stable.
- Prerequisite bridges/tests: `WorkbenchSearchSnapshot`, the search mirror bridge, pack restore callback coverage, `V320WorkflowSearchAcrossDrawersTests`, `V537WorkbenchSearchMirrorTests`, and the AHE/XY/3ω search snapshot consumption tests.
- Extraction risks: stale mirror drift, broken select-all denominator, pack decode/restore regressions, and accidental analysis from canonical results without a selected-hit snapshot.
- Acceptance criteria: shell and workflows read canonical search state only through `WorkbenchSearchSnapshot`; workflow stores no longer own the canonical search lifecycle; restore still round-trips search state through the explicit restore callback; the existing search snapshot tests remain green.

#### Gate 7.2 - Selection

- Status: complete.
- Source Gate 3 audit section: `Selection`
- Classification: `Boundary debt` → `Module-owned — common module`
- Gate 3 finding: the run-scoped selected-hit read surface existed, but selected IDs still lived in workflow stores and the denominator bridge remained tied to workflow-local search mirrors.
- Outcome: `WorkbenchSelectionRuntime` is the canonical owner of selected IDs and all selection mutations. Workflow stores hold a `weak var selectionReading: (any SelectionReading)?` bridge injected by `WorkbenchFeatureStore` — a non-canonical typed read surface for pack serialization and analysis denomination only. (Gate 7.7B migrated this from a raw `selectionReader: (() -> Set<String>)?` closure to the typed `SelectionReading` protocol.) Select-all denominator is passed explicitly to `selectAll(for:denominator:)` by the facade. Pack restore writes selected IDs through `seedSelection()` → `seed()`. `WorkbenchSelectedHitsSnapshot` remains the run-scoped analysis input.
- Prerequisite bridges/tests confirmed green: `V537WorkbenchSelectionShellTests` (7 tests), `V537WorkbenchSelectedHitsSnapshotTests`, `V538SelectedHitsBridgeAuditTests`, `V537WorkbenchSearchMirrorTests`, `V537PackRestoreModuleBoundaryTests`, `V537AnalysisLifecycleBoundaryTests`, `V537SaveModuleBoundaryTests` — 90 targeted tests passed.
- Full suite closeout: 1114 swift-testing tests passed, 0 failures. `swift test` exit code 1 is a known artifact of the mixed XCTest + Swift Testing runner; `Test Suite 'All tests' passed` was confirmed in output and no `✖` symbols appeared. `check_required_actions.sh` clean.
- Remaining deferred work: `selectionReading` typed bridge removal awaits Save / Pack Module cleanup; `cachedSearchResults` rename deferred until pack `CodingKey` backward-compatibility handling is in place.

#### Gate 7.3 - Secondary Input Search

- Status: complete.
- Source Gate 3 audit section: `Secondary Input Search`
- Classification: `Module-owned — optional module candidate`
- Actual Gate 3 finding: the general auxiliary-slot shape is visible, but the only live instance is 3ω RT state and the runtime is still workflow-local, so the module shape must stay general rather than RT-specific.
- Target owner: common auxiliary-slot Secondary Input Search module declared by the Workflow Assembly.
- Required work: define a slot contract that covers slot ID, display label, query defaults, workflow/file-kind filter, selection cardinality, requiredness, selected-hit persistence, restore sidecar bridge, and fingerprint contribution; extract workflow-local RT fields into slot instances without moving file meaning into the module.
- Prerequisite bridges/tests: `ThreeOmegaPackContracts`, the 3ω RT selection bridge, 3ω search snapshot and pack/restore boundary tests, and future multi-slot contract coverage for workflows that declare more than one auxiliary input.
- Extraction risks: freezing a one-slot RT-specific API, blocking future multi-slot workflows, losing restore sidecar/file bridge behavior, and letting auxiliary search mutate main search or selection state.
- Acceptance criteria: the module supports zero, one, or many declared slots; no slot mutates Main Search; restore can rebind from a slot-scoped sidecar/file identity; 3ω RT remains one declared slot rather than the module shape itself.
- Outcome: `WorkbenchSecondaryInputSearchRuntime` is the canonical owner of all slot state for the `rt` slot: `rtQuery`, `rtSearchResults`, `isRTSearching`, `rtSearchMessage`, `showRTPopover`, `selectedRTHit`. `ThreeOmegaWorkspaceStore` retains workflow semantics, RT eligibility/whitelist policy, analysis contribution, and forwarding compatibility properties. Pack schema is unchanged; `selectedRTHit` serializes under the existing 3ω pack contract; restore writes through the forwarding/runtime path. Slot state does not enter `WorkbenchSearchSnapshot` or `WorkbenchSelectedHitsSnapshot`. Main Search and `WorkbenchSelectionRuntime` selection are fully isolated from slot state.
- Deferred debt: `cachedRTFilePath` standalone rebuild is not implemented. `cachedRTFilePath` is currently derived output from `selectedRTHit` / manifest snapshot, not a standalone restore input. Gate 7.6 Pack/Restore extraction should revisit the secondary input restore bridge.

#### Gate 7.4 - Analysis Overlay

- Status: complete.
- Source Gate 3 audit section: `Analysis Overlay`
- Classification: `Module-owned — optional module candidate`
- Actual Gate 3 finding: overlay state is session-only today, the common shell already hosts overlay entry points, and the 3ω Scaling Law overlay belongs here only as a validation case.
- Target owner: common Analysis Overlay module, with Workflow Assemblies owning eligibility, labels, snapshot-to-series mapping, warning policy, saved-manifest/sample-key policy, and metric-persistence policy.
- Outcome: `WorkbenchAnalysisOverlayRuntime` is the common owner of overlay ID list (`overlayIDs`) and chip display labels (`displayLabels`). `ThreeOmegaWorkspaceStore` delegates overlay ID mutations (addEntry / removeEntry / clear) to the runtime when wired, retains `OverlaySnapshot` content (sweeps, sampleKeys, sourceFiles) for rendering, and keeps all RAHE multi-group rendering semantics. `WorkbenchFeatureStore` owns the runtime instance and injects it into the 3ω workspace. Shell chips read from the runtime rather than from the workspace directly.
- What moved into common runtime: overlay pack IDs (ordered list), chip display labels. clear / reset operations. The runtime has no knowledge of RAHE, Scaling Law, OverlaySnapshot content, sample-key policy, or metric semantics.
- What stayed workflow/Assembly-owned: `OverlaySnapshot` struct and content (sweeps, sampleKeys, sourceFiles). `addOverlay` / `availableOverlayPacks` eligibility and vault decode logic. `_renderRAHEWithOverlays` and `_rebuildOverlayManifestPayloads` multi-group rendering. `activeChartSampleKeys` merging. All 3ω RAHE and Scaling Law semantics.
- Scaling Law overlay: has no live runtime path and was not implemented. Documented as a future validation case only; no overlay render path exists for the `.scaling` tab.
- Active-tab overlay rerender requests: not moved into the runtime. `addOverlay` and `removeOverlay` call `_renderRAHEWithOverlays()` directly on the workspace. Moving the rerender trigger into the runtime would require the workspace to observe a runtime counter and act — no boundary value justifies that indirection in this cut. Recorded as deferred debt.
- Deferred debt: (1) Active-tab overlay rerender trigger stays workflow-driven; a future cut may add a runtime-observable rerender token if a second workflow opts into overlay. (2) Scaling Law overlay render path not started; would require a multi-group Scaling renderer plus Assembly-declared eligibility. (3) Overlay persistence / pack-round-trip not in scope; first cut is session-only by design. (4) `_overlayPackIDs` standalone fallback can be removed once the no-WFS construction path is no longer needed in tests (Gate 7.6 or later cleanup).
- Tests added: `V740AnalysisOverlayBaselineTests` (8 tests, baseline before extraction) and `V740AnalysisOverlayRuntimeTests` (14 tests, runtime extraction validation). All 22 pass. Full suite (all tests) passes with exit code confirming `Test Suite 'All tests' passed`.

#### Gate 7.5 - Save to Library / Save Metadata Projection

- Status: complete (Gate 7.5 audit → Gate 7.5A semantic tests → Gate 7.5B coordinator extraction).
- Source Gate 3 audit section: `Save to Library` plus `Metric Extraction / Metric Override / Save Metadata`
- Classification: `Boundary debt`
- Actual Gate 3 finding: the common save writer already exists, but workflow metric semantics still reach it through raw `PendingMetricEntry` arrays and workflow-local save-message / override state.
- Target owner: split ownership. The save writer is common and module-owned; metric definitions, unit semantics, override policy, and the semantic save projection stay Assembly-owned.
- Audit result: `GATE7_SAVE_METADATA_AUDIT.md`
- Audit notes:
  - Common writer (`SaveActiveChartToLibraryUseCase`) is already clean: validation, artifact writes, condition normalization, trace construction. No physics knowledge.
  - Metric names, unit strings, unit scaling factors (`* 1e31`, `* 1e20`), condition keys, tab gate, and override policy are all Assembly-owned in `buildActiveChartMetrics()` per workflow.
  - `saveMessage`, `persistenceOutcome`, `currentRunTrace`, and `refreshRelatedCharts()` are duplicated identically across three `persistToLibrary()` implementations — primary extraction target.
  - AHE override is single-sample guarded; 3ω has no override; XY has no metrics yet.
- Gate 7.5A outcome:
  - Added `V750SaveSemanticProtectionTests.swift` (29 tests): 3ω metric projection correctness, AHE multi-sample override guard (source inspection), `PersistChartArtifactUseCase` tabKey read path.
- Gate 7.5B outcome (coordinator extraction):
  - Extracted shared async orchestration into `WorkbenchSaveCoordinating` protocol + extension (`executeSave`, `didCompleteSave` hook).
  - AHE, 3ω, XY each declare `WorkbenchSaveCoordinating` conformance; their `persistToLibrary` now consists only of guards + input construction calling `buildActiveChartMetrics()` + delegation to `executeSave`.
  - AHE-specific post-save behaviour (override clearing, `persistCount`) isolated in `didCompleteSave` override within `AHEWorkspaceStore.swift`.
  - `buildActiveChartMetrics()`, all metric names, unit strings, scaling factors, condition keys, tab gates, and override policy remain Assembly-owned and unchanged.
  - `SaveActiveChartToLibraryUseCase` semantic behaviour unchanged.
  - Pack/Restore and Analysis Overlay not touched.
  - Added `V750BMetricDelegationTests.swift` (11 tests): each workflow still calls `buildActiveChartMetrics()` before coordinator; coordinator owns machinery; no physics in coordinator; AHE hook present; 3ω/XY do not override hook.
  - Updated two V537 source inspection tests (`saveCoordinatorSetsTraceFromOutcome`, `relatedChartsRefreshRouting`) to reflect coordinator ownership.
- Deferred debt:
  - `PendingMetricEntry` bridge array is still untyped raw data; a future gate may introduce a typed semantic projection to replace it.
  - `saveMessage` / `persistenceOutcome` remain workflow-store-owned state; full decoupling deferred to Gate 7.7.
  - XY `buildActiveChartMetrics()` returns `[]` — no metric extraction implemented yet.

#### Gate 7.6 - Pack / Restore

- Source Gate 3 audit section: `Pack / Restore`
- Classification: `Boundary debt`
- **Audit status: complete (2026-06-10). Audit doc: `docs/architecture/workbench/history/gate7/GATE7_PACK_RESTORE_AUDIT.md`.**
- **Gate 7.6A status: complete (2026-06-10). 34 tests in `V760PackRestoreProtectionTests.swift`, all pass. No behavior drift.**
- Actual Gate 3 finding: restore is the only sanctioned multi-state mutation exception, but pack/restore is still implemented per workflow and needs coverage for every restored field, including secondary input search.
- Target owner: common Pack / Restore module with an explicit restore write map and a documented exception for workspace restoration.
- Required work: centralize pack load/save orchestration, `activePackID`, vault access, and restore writes behind the explicit contract; route canonical search restore through the existing callback; keep workflow-specific pack config and result metadata behind `AnalysisPackProviding`; include secondary input search in restore coverage.
- Prerequisite bridges/tests: `modules/PACK_RESTORE.md` write-map coverage, `RestoreAnalysisPackUseCase`, `AnalysisPackProviding`, `V4117AnalysisPackVaultTests`, `V5114RestoreUseCaseStatelessTests`, `V5114PackRestoreNoTraceCommitTests`, `V537PackRestoreModuleBoundaryTests`, `V535TabRenderStatePackTests`, and `V760PackRestoreProtectionTests`.
- Extraction risks: missed restore writes, accidental trace commit, broken legacy AHE nil-ingestion restore, stale search mirrors, and auxiliary-input fingerprint loss.
- Acceptance criteria: all restore writes are centralized and covered; restore rerenders rather than re-ingests; `activePackID` is still set by the caller after restore returns; secondary input search round-trips through the documented bridge; restore never serializes session-only trace or save fields.
- **Audit findings (all gaps closed by Gate 7.6A tests)**:
  - Safe: session-only fields (persistenceOutcome, saveMessage, currentRunTrace) confirmed not serialized and nil after restore. Overlay state confirmed not serialized and cleared on restore (both standalone fallback and wired-runtime path). Save coordinator confirmed not creating pack/restore state. Cross-workflow isolation confirmed. RT slot isolation confirmed.
  - `cachedRTFilePath` derivation confirmed: `selectedRTHit?.measurementFilePath` is the canonical source; `config.rtFilePath` is fingerprint-only. Overwrite sequence pinned by source-inspection tests.
- **Gate 7.6B extraction / fix targets**:
  - Remove intermediate `cachedRTFilePath = config.rtFilePath` assignment from `restoreFromPack` (it is always overwritten; retaining it is misleading).
  - Remove `_overlayPackIDs` standalone fallback after updating V740 tests to use the wired-runtime path.
  - See audit doc §8 for full details.

#### Gate 7.7 - Warning Display / Run Trace

- Source Gate 3 audit section: `Warning Display / Run Trace`
- Classification: `Boundary debt`
- Actual Gate 3 finding: the warning and trace display surface already exists, but the raw warning and trace fields still live in workflow stores and are mixed across analysis and save paths.
- Target owner: split ownership. The common module owns warning and trace display / projection; Workflow Assemblies emit typed warning and trace events.
- Required work: centralize warning-log and run-trace projection; keep session-only warning, analysis, plot, and save message data out of pack formats; separate save-side trace updates from analysis-side trace commits; keep duplicate-warning coalescing intact.
- Prerequisite bridges/tests: `BuildRunTraceProjectionUseCase`, `WorkbenchTracePanel`, `V326RunManifestTraceTests`, `V537AnalysisLifecycleBoundaryTests`, `V537SaveModuleBoundaryTests`, `V5114PackRestoreNoTraceCommitTests`, and `V537PackRestoreModuleBoundaryTests`.
- Extraction risks: trace being committed on restore, warnings duplicating across reruns, save-side trace being confused with analysis-side trace, and session-only fields being serialized by mistake.
- Acceptance criteria: warning and trace projections come from one common read/display owner; workflow stores shrink to typed event sources; restore leaves trace nil; duplicate-warning coalescing still behaves as it does now.

#### Gate 7.8 - Plot System Module Group Audit and Structural Guards

- Status: complete (7.8A–7.8E).
- Source Gate 3 audit section: `Plot System` plus `Title / Style / Legend Controls`
- Classification: `Module-owned — common module group within Plot System`
- Outcome:
  - Plot System module group boundaries clarified: Plot Display, Plot Controls, and Plot Preservation are distinct sub-modules; `TabRenderManager` / `TabRenderState` own Plot Preservation state.
  - Main Board layout (`WorkflowWorkspaceShell`, left/right column files) is outside the Plot System module group. Shell files pass plot controls as a ViewBuilder slot and must not manipulate `TabRenderState` / `TabRenderManager` internals.
  - `WorkbenchPlotCanvas` is the interaction and display surface only; it does not own canonical plot output or ingestion state.
  - Workflow / Assembly-owned display semantics (title token defaults, `stackOffsetMultiplier`, `minGapFraction`, AHE single-tab specialization, `legendAnchor` gap for AHE/XY) may remain in workflow stores where the semantics are workflow-owned.
  - `currentRunTrace` removed from `WorkbenchPlottingStore` (Gate 7.8D); now lives exclusively in `WorkbenchRunTraceProviding`.
  - Structural boundary tests added (7.8E): enforce Main Board / Plot System separation and canvas interaction rules.
- Tests added or updated: `V780PlotSystemBoundaryTests`, related `V537WorkflowShellPhase4Tests` and `V563WorkflowStateBoundaryTests` remain green.
- Deferred: `legendAnchor` pack coverage gap (AHE/XY packs do not serialize it); title template extraction gates; `titleTemplate` field still workflow-store-owned pending backward-compatible `CodingKeys`.

### Deferred Follow-Ups (not scheduled)

| Item | Recorded in | Notes |
|---|---|---|
| Search/Rules integration — workflow alias expansion | `modules/MEASUREMENT_SEARCH.md` § Deferred Boundary Debt | Library/Workbench search alias expansion is hardcoded; Rules Book-defined workflow IDs do not automatically participate in alias resolution. Not blocking Inbox → Library archival. Resolve in a future Search/Rules integration gate. |

### Gate 7 Non-Candidates Preserved from Gate 3

- Geometry / Fit Range / Scaling Panels remain Assembly-owned and are not Gate 7 extraction targets.
- AHE Hc / R_AHE extraction, XY phi/detrend/centering, and 3ω scaling semantics remain Assembly-owned.
- The 3ω Scaling Law overlay is a Gate 7.4 validation case under Analysis Overlay, not standalone feature work.

#### Gate 7.9 - Workbench Architecture Closeout

- Status: complete (docs-only).
- Scope: close out Workbench architecture documentation after Gate 7.1–7.8 so docs no longer read as stale process audits.
- Outcome:
  - `WORKBENCH_ROADMAP.md` updated: Gate 7 marked complete; sub-gate table updated; stale Gate 7.8 wording replaced with actual outcomes.
  - `MODULE_BOUNDARIES.md` reframed as current ownership authority (origin: Gate 3, updated through Gate 7.9); Gate 3 follow-ups section replaced by Boundary Closeout Status section.
  - `history/gate7/GATE7_WORKBENCH_ARCHITECTURE_CLOSEOUT.md` added: final module map, Gates 7.1–7.8 outcome summary, accepted bridges, deferred cleanup, non-candidates, and closeout rule.
- Production Swift: unchanged. Tests: unchanged. Rebuild/publish: not required.

### Post-PlotSystem Boundary Hardening Backlog

This branch already completed the following Plot System boundary hardening work:

- shared Workbench plot action strip
- shared title/label/font primitive cleanup
- Cartesian / DualAxis / Heatmap control boundary audit
- non-XY render output semantics audit

Deferred technical debt items remain in backlog only:

| Item | Status | Notes |
|---|---|---|
| Export behavior across workflows | deferred | Follow-up work for keeping export behavior aligned as workflows share or diverge on Plot System export paths. |
| RSM / Heatmap pack-export-runtime semantics | deferred | Follow-up work for keeping pack, export, and runtime semantics explicit for the RSM / Heatmap path. |
| Workflow input/search/result shell ownership | deferred | Follow-up work for clarifying shell ownership of workflow input, search, and result surfaces. |
| Stale architecture naming cleanup | deferred | Follow-up work for retiring stale architecture names and terminology after the boundary model is stable. |

### Gate 8 - New Workflow Dry Run

Purpose:

- Validate the architecture

Acceptance:

- Create a new workflow (for example SOT)
- The workflow should be added primarily through a new Workflow Assembly
- Verify that Main Board does not require modification
- Verify that Layout does not require modification
- Verify that existing Modules do not require modification
- Document any remaining friction points

Result:

- New workflow onboarding remains assembly-led

#### Gate 8.1 - IV Workflow

- Status: complete (PR #131).
- Scope: IV workflow Phase A+B — full physics rendering, mA display with Peak/RMS basis, stacking, and pack/restore.
- Outcome: Main Board unmodified. Layout unmodified. No existing module state touched. IV onboarded entirely through Workflow Assembly extension path. Assembly record: `docs/architecture/workbench/workflows/iv/ASSEMBLY.md`.

## 5.3.7 Scope Closure

5.3.7 delivered the **Workbench modularization safety baseline**.

### Completed in 5.3.7

- Architecture language / governance baseline (Workflow, Workflow Assembly, Main Board, Modules terminology; docs/index alignment)
- Module boundary contracts for Search, Selection, Plot Preservation, Analysis Lifecycle, Save, Pack / Restore
- Transition read surfaces:
  - `WorkbenchSearchSnapshot`
  - `WorkbenchSelectedHitsSnapshot`
  - `saveMessage`
- Boundary regression gates for: Search, Selection, Plot Preservation, Analysis Lifecycle, Save, Pack / Restore, Workflow state
- App bundle and web export guardrails

Search Module read-surface extraction began in 5.3.7; runtime ownership cleanup remains post-5.3.7.
`WorkbenchReadinessProjection` has been implemented. Consumption by shell and result-header gating remains future work.

### Not completed in 5.3.7

- Full Main Board cleanup
- Full runtime module extraction
- Complete `cachedSearchResults` removal
- `SaveCoordinator` extraction
- `PackRestoreCoordinator` extraction
- `AnalysisLifecycleCoordinator` extraction
- Workflow Function Contract
- SOT workflow onboarding

## Completed Phases

| Phase | Scope | Status |
|---|---|---|
| Phase 3A | app bundle regression gates | complete |
| Phase 3B | web export chart asset regression tests | complete |
| Phase 4 | Plot Preservation Module | complete |
| Phase 5A | Search Module Contract + boundary tests | complete |
| Phase 5B | Workflow / Workflow Assembly / Main Board / Module / Module Group architecture docs | complete |
| Phase 5C | Selection Module Contract + `WorkbenchSelectedHitsSnapshot` run-scoped read surface | complete |
| Phase 5D-1 | Analysis Lifecycle Module — boundary tests locking cross-module behavior | complete |
| Phase 5D-2 | Analysis Lifecycle Module — contract documentation | complete |
| Phase 5E-1 | Save Module — contract documentation | complete |
| Phase 5E-2 | Save Module — boundary tests locking current save-boundary behavior | complete |
| Phase 5F-1 | Pack / Restore Module — audit (restore write map, boundary risks, legacy paths, test gaps) | complete |
| Phase 5F-2 | Pack / Restore Module — contract documentation | complete |
| Phase 5F-3 | Pack / Restore Module — boundary tests (no-trace-commit, isAllSelected after restore, AHE legacy path) | complete |

## Post-5.3.7 Phases

All phases below are post-5.3.7 runtime extraction work. None were in scope for the 5.3.7 safety baseline.

| Phase | Scope |
|---|---|
| Phase 5A-3 | Search Read Surface / mirror risk reduction (runtime ownership cleanup) |
| Phase 5D-3 | Analysis Lifecycle Module — shared runtime extraction (deferred; awaits stable contract + tests) |
| Phase 5E-3 | Save Module — saveMessage field + refreshRelatedCharts extraction into shared coordinator (deferred until contract stable) |
| Phase 5F-4 | Pack / Restore Module — implementation extraction (deferred; awaits stable contract + tests) |
| Phase 6 | Workflow Function Contract |
| Future | SOT workflow onboarding through shell framework |

## Completion Rule (Per Phase)

A phase is complete only when all checks pass:

1. Contract: target boundary/ownership contract is explicit in architecture docs.
2. Implementation: runtime behavior matches the contract.
3. Regression tests: contract has dedicated regression tests.
4. Docs/index updates: affected workbench docs and index links are updated.
5. Required action checks: repository action-gate checks are run and clean for the round scope.

## Cross-Links

- [Shell Blocks](SHELL_BLOCKS.md)
- [Workflow Extension](WORKFLOW_EXTENSION.md)
- [Module Boundaries](MODULE_BOUNDARIES.md)
