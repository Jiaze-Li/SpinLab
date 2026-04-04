# SpinLab V3.2-V3.5 Iteration Addendum (2026-04-03)

Status: active  
Type: additive update (does not delete or replace existing V3 plan text)

---

## [ADDED 2026-04-03] Why This Addendum Exists

This file refines execution order into user-verifiable functional iterations.

- Keep the original `V3_EXECUTION_PLAN.md` as architecture source context.
- Add a practical acceptance sequence where each version has app-visible changes.
- [UPDATED 2026-04-03] Keep `V3.2.0` minimal (risk-controlled), but with a reusable architecture boundary.
- [UPDATED 2026-04-03] Move Plot UX Freeze to the end of V3.2 after persistence closure.
- [ADDED 2026-04-03] Add a V3.2 stage gate checklist document.

---

## [ADDED 2026-04-03] Version Renumbering

- New `V3.3`: Workbench UI architecture iteration (layered, workflow-generic shell).
- Original `V3.3` (Library writeback + read models) moves to `V3.4`.
- Original `V3.4` (reliability hardening) moves to `V3.5`.

---

## [ADDED 2026-04-03] V3.2 Functional Micro-iterations

### V3.2.0 Generic Workflow Search Layer (Cross-drawer)

Scope:
- [UPDATED 2026-04-03] Ship minimum behavior first: cross-drawer lookup by workflow `type` text.
- Keep search layer independent from workflow-specific parsing/plotting.
- Keep extension structure ready so future workflows do not require rewriting search flow.

User-visible acceptance:
- User can input a workflow keyword/type and get cross-drawer results in Workbench.
- Initial acceptance can be done with `AHE`, and the same UI/query flow can be reused for `RT` and `3W`.

Definition of Done (DoD):
- Broad direct-input query works and does not require preconfigured `id=AHE` to return AHE results.
- Minimum implementation may use directory/metadata heuristics; no parser/plot dependency is introduced.
- Output result shape is unified and reusable by downstream V3.2.1 ingestion flow.
- [ADDED 2026-04-03] Keep structural seams in this iteration:
  - `WorkflowSearchQuery` (input contract)
  - `WorkflowMeasurementSearchHit` (output contract)
  - `WorkflowMeasurementSearching` (search capability protocol)
  - optional alias normalization component (enhancement path, non-blocking)

Test naming draft:
- `Tests/SpinLabAppTests/V320WorkflowSearchAcrossDrawersTests.swift`

Status: `done` (accepted on 2026-04-04)

Implementation record (2026-04-04):
- Search is workflow-generic and supports direct type-text query across drawers (AHE/RT/3W aliases), not AHE-only gating.
- `WorkflowSearchQuery` -> `WorkflowMeasurementSearchHit` contract path is active in Workbench and validated by `V320WorkflowSearchAcrossDrawersTests`.
- Search matching remains independent from workflow ingestion/plot pipeline.
- Rule-governance consolidation delivered in same cycle:
  - Added rule source baseline manifest: `docs/architecture/RULE_BASELINE_MANIFEST.md`.
  - Added drift guard script: `scripts/test_rule_drift_guard.sh`.
  - Added CI gate: `.github/workflows/rule-drift-guard.yml`.
  - Locked parser arbitration behavior with golden tests in `V210ImportAndParseTests` (channel/file/folder priority, fallback warning boundary, tie/shortcut behavior).
  - Exposed/recorded rule runtime observability fields and composite fingerprint contract for drift tracing.

### V3.2.1 AHE Ingestion + Axis Detection

Scope:
- Parse AHE `.dat` and `.lvm`.
- Produce normalized candidate axis fields and default `x/y` mapping.

User-visible acceptance:
- In Workbench (AHE), user can load file(s) and see detected `x/y` candidates and default mapping.

Definition of Done (DoD):
- AHE parser path returns deterministic normalized payload-ready data.
- Default axis selection is stable for the same input files.
- No plotting yet; no persistence side effects.

Test naming draft:
- `Tests/SpinLabAppTests/V321AHEIngestionAxisDetectionTests.swift`

### V3.2.2 Unified Plot Entry (Default Render)

Scope:
- Introduce single plot render entry from standardized payload.
- Generate PNG using default mapping/style.

User-visible acceptance:
- User can click one action in AHE workspace and get a rendered plot.

Definition of Done (DoD):
- Unified plot API accepts only standardized payload.
- Default render generates valid PNG and preview can load it.
- Plot layer contains no workflow-specific computation logic.
- [ADDED 2026-04-03] Include atomic write-path smoke check in this iteration:
  - write rendered PNG via `AtomicFileWriter`
  - resolve destination via `LibraryPathResolver`
  - confirm no integration error on expected path

Test naming draft:
- `Tests/SpinLabAppTests/V322UnifiedPlotDefaultRenderTests.swift`
- [ADDED 2026-04-03] `Tests/SpinLabAppTests/V322AtomicWritePathSmokeTests.swift`

### V3.2.3 Parameterized Plot Controls

Scope:
- Manual `x/y` remap.
- Basic style controls (title/grid/theme/line presentation) and rerender.

User-visible acceptance:
- User changes mapping/style and sees plot update accordingly.

Definition of Done (DoD):
- Manual mapping override takes precedence over default mapping.
- Style changes are applied without modifying ingestion logic.
- Payload `semanticParams/styleParams` are serialized consistently.

Test naming draft:
- `Tests/SpinLabAppTests/V323PlotParameterOverrideTests.swift`

### V3.2.4 Identity + Overwrite Behavior

Scope:
- Apply chart identity by semantic payload.
- Enforce overwrite for style-only mutation and new artifact for semantic mutation.

User-visible acceptance:
- Changing style only overwrites same chart artifact.
- Changing semantic inputs creates a new chart artifact.

Definition of Done (DoD):
- Identity generation excludes style-only fields.
- Overwrite path updates image + manifest consistently for same identity.
- New identity produces distinct artifact path/key.

Test naming draft:
- `Tests/SpinLabAppTests/V324ChartIdentityOverwriteTests.swift`

### V3.2.6 Run Trace + Manifest Visibility

Scope:
- Emit per-run manifest after plot generation.
- Provide app-visible trace info (inputs/params/output/runID/timestamp).

User-visible acceptance:
- User can inspect last run trace details from Workbench.

Definition of Done (DoD):
- Manifest includes required provenance fields.
- Trace UI reads manifest projection only (no hidden recomputation).
- Manifest path uses Library-root-relative format.

Test naming draft:
- `Tests/SpinLabAppTests/V326RunManifestTraceTests.swift`

### V3.2.7 Persistence Closure

Scope:
- Route all V3.2 writes through `AtomicFileWriter`.
- Resolve/store paths through `LibraryPathResolver`.
- Ensure restart can restore generated artifacts.
- [ADDED 2026-04-04] Wire `PersistChartArtifactUseCase` into `WorkbenchFeatureStore.renderAHEPlot()`.
- [ADDED 2026-04-04] Persist `libraryRootPath` in store so `renderAHEPlot` can resolve artifact paths.
- [ADDED 2026-04-04] Expose `currentRunTrace: WorkbenchRunTraceProjection?` in store; populate via `BuildRunTraceProjectionUseCase` after each render.
- [ADDED 2026-04-04] Wire trace projection into `WorkbenchView` so user can see last run trace (closes V3.2.6 product-level acceptance).

User-visible acceptance:
- After app restart, previous V3.2 generated outputs remain discoverable/openable.
- [ADDED 2026-04-04] User can inspect last run trace (runID, inputs, axis, output path, timestamp) in Workbench after any plot render.

Definition of Done (DoD):
- No direct non-atomic write path remains in V3.2 scope.
- Relative path round-trip passes for artifacts.
- Root-escape paths are rejected explicitly.
- [ADDED 2026-04-04] `currentRunTrace` is populated after render and reflects the persisted manifest (not live payload).
- [ADDED 2026-04-04] V3.2.6 product-level acceptance ("User can inspect last run trace from Workbench") is closed here.

Test naming draft:
- `Tests/SpinLabAppTests/V327V32PersistenceClosureTests.swift`

### V3.2.8 Plot UX Freeze (Reusable Across Workflows)

Scope:
- [UPDATED 2026-04-03] Freeze after data/persistence closure.
- Legend drag/reposition.
- In-plot title editing.
- Stabilize reusable plot interaction/state model for all workflows.

User-visible acceptance:
- User can drag legend and edit title directly in plot UI.
- Updated interactions are reflected in rerender/export output behavior.

Definition of Done (DoD):
- Plot interactions are implemented in workflow-agnostic plot module/UI layer.
- Interaction state maps to standardized style payload fields.
- AHE does not own plot interaction logic directly.
- No persistence contract changes are required after UX freeze acceptance.

Test naming draft:
- `Tests/SpinLabAppTests/V328PlotUXFreezeTests.swift`

---

## [ADDED 2026-04-03] Post-V3.2 Roadmap (Renumbered)

### V3.3 Workbench Layered UI Architecture

Scope:
- Design workflow-generic layered Workbench UI shell.
- Prioritize AHE directory UI first, but keep UI abstraction reusable.
- Keep this iteration UI-focused and interface-ready.
- [ADDED 2026-04-03] Before implementation, split V3.3 into micro-iterations (V3.3.x) with separate acceptance checkpoints.

DoD:
- UI information architecture is layered (not feature-coupled).
- Workflow-specific content is plugged into shared shell regions.
- Future interface hookup can be done with minimal layout churn.

Test naming draft:
- `Tests/SpinLabAppTests/V330WorkbenchLayeredUITests.swift`

### V3.4 Library Writeback + Read Models (was V3.3)

DoD:
- Sample index and measurement data writeback paths operational.
- Manual override info persisted.
- Library read models expose Workbench Results + Measurement Data in read-only mode.

Test naming draft:
- `Tests/SpinLabAppTests/V340LibraryWritebackReadModelTests.swift`

### V3.5 Reliability Hardening (was V3.4)

DoD:
- Cross-artifact consistency hardening in place.
- Per-sample write lock prevents concurrent corruption.
- Crash/interruption does not leave half-written references.

Test naming draft:
- `Tests/SpinLabAppTests/V350ReliabilityHardeningTests.swift`

---

## [ADDED 2026-04-03] Plot Module Boundary (Confirmed)

Architecture rule for future workflows:

- Each workflow computes its own processing output.
- All workflows converge to one unified plot render interface.
- Plot module must remain workflow-agnostic and reusable.

---

## [ADDED 2026-04-03] V3.2 Stage Gate

V3.2 completion should be evaluated by:

- `docs/plans/V3_2_ACCEPTANCE_CHECKLIST.md`

This checklist aggregates V3.2.0 through V3.2.8 completion and defines readiness criteria before MR/RT onboarding discussion.

---

## [ADDED 2026-04-04] V3.2.0.10 SampleKey Canonical Migration Interface

Goal:
- Standardize sample identity to canonical key form:
  - `<Batch>|<Treatment>|<Material>|<Orientation>`
  - example: `PN30|HF|STO|111`
- Keep legacy formats readable during migration.

Migration strategy (additive, backward-compatible):
- Introduce a shared normalizer (`SampleKeyNormalizer`) as compatibility interface.
- Canonicalize where sample input enters cross-module contracts.
- Preserve legacy IDs in storage until full migration round is scheduled.

Interface touchpoints updated in this iteration:
- Workflow search path parsing:
  - normalize `/samples/<sampleKey>/` folder key to canonical sampleKey in search hits.
- Inbox/Library drawer matching boundary:
  - drawer match index now derives canonical identity even when `LibrarySample.id` is legacy/non-canonical.
  - canonical search input can resolve legacy display-style sample IDs.
- Inbox routing draft input:
  - draft default/channel sample inputs are normalized before route planning and drawer matching.

Compatibility commitments:
- Legacy sample IDs remain resolvable via fallback token matching.
- Canonical key matching is preferred when deterministically available.
- No destructive rewrite of existing Library sample IDs in this iteration.

Next migration checkpoints:
- Introduce optional persisted alias map (`legacySampleID -> canonicalSampleKey`) in Library index.
- Add one-time migration tool/command for batch rewriting sample directories to canonical IDs (separate controlled iteration).
