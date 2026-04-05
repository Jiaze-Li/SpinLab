# SpinLab V3.4 Iteration Plan (2026-04-05)

Status: planning
Type: additive (does not delete or replace existing V3 plan text)

---

## Context

V3.4 goal (from V3_2_ITERATION_ADDENDUM_2026-04-03.md):

> Library Writeback + Read Models (was V3.3 in original plan).
> Sample index and measurement data writeback paths operational.
> Manual override info persisted.
> Library read models expose Workbench Results + Measurement Data in read-only mode.

This file splits V3.4 into four version numbers (V3.4.0–V3.4.3). V3.4.2 and V3.4.3
are each delivered in two rounds (UseCase/Store first, UI second), per codebase rules
requiring logic and UI to be handled in separate rounds.

---

## Review Adjustments (2026-04-05)

Ten constraints applied after two rounds of plan review. All are non-negotiable before implementation starts.

### Adj-1: V3.4.2 and V3.4.3 each split into two rounds
Repository rules require UI and logic to be handled in separate rounds. Each of these
two versions is delivered as: round A (UseCase + Store projection) then round B (Library
section UI). Version numbers are unchanged.

### Adj-2: runID must be generated once and passed into both persistence paths
`PersistChartArtifactUseCase` currently generates its own `runID` internally
(`AHEWorkspaceStore.swift:310`, `try? useCase.execute(...)`).
To guarantee that the run manifest and the metric record in `measurement_data.json` share
the same `runID`, the render flow in `AHEWorkspaceStore` must generate `runID` once
(e.g. `UUID().uuidString`) and pass it explicitly into both `PersistChartArtifactUseCase`
and `PersistMeasurementDataUseCase`.

### Adj-3: Error handling must not silently swallow failures
`attemptPersistAndTrace` (`AHEWorkspaceStore.swift:301`) currently uses `try?`, which
silently discards errors. If the chart writes successfully but the metric write fails,
the user receives no indication. Both persistence calls must return a typed
`PersistenceOutcome` (success / partial / failure) mapped from `AppError`, surfaced to
store state so the UI can reflect the outcome.

### Adj-4: Override state in AHEWorkspaceStore (confirmed)
`pendingMetricOverride` belongs in `AHEWorkspaceStore`. `WorkbenchMetricOverrideInfo`
model is already defined and reusable. No change from original plan — review confirmed
direction.

### Adj-5: Read models must live in UseCase + LibraryFeatureStore; View only renders
Library detail UI must not read JSON directly. `LibraryView.swift` and its subviews only
consume projected state from `LibraryFeatureStore`. All JSON loading is done inside
`LoadWorkbenchResultsUseCase` / `LoadMeasurementDataUseCase`, with `LibraryFeatureStore`
maintaining the `sampleKey → workbenchResults / measurementData` projection.

### Adj-6: AppVersion bump + build at every iteration
Each delivered iteration must bump `Sources/SpinLabApp/App/AppVersion.swift` and run
`./scripts/build_desktop_app.sh debug` to produce a Desktop `.app`, per AGENTS rules.

### Adj-7: Add `source` field to override info
`WorkbenchMetricOverrideInfo` must include a `source: OverrideSource` enum
(cases: `manual`, `import`, `recompute`) in addition to `reason`. This is added in
V3.4.1 when the model is first written to disk. Cost of adding it later is high
(schema migration required); cost now is trivial. Future audit and UI drill-down depend on it.

### Adj-8: latestIndex key rule frozen — alias resolution is display-layer only
`WorkbenchMetricIdentity.makeIdentityKey` (confirmed in `WorkbenchArtifactIdentity.swift:50`)
uses `normalizeDictionary` (lowercase + trim) on condition keys — no alias resolution.
This is correct. Rule: condition keys passed into `makeIdentityKey` must always be
canonical keys, never alias keys. Alias → canonical mapping via `ConditionAliasBook`
must happen before the identity key is computed, or in the display layer only.
This rule must be documented in the use case and verified by test in V3.4.0.

### Adj-9: "Show" button loads the selected reference, not always the latest
`WorkbenchResultsSectionView` "Show" button behavior: opens the specific chart PNG
referenced by the row the user clicks, resolved via `LibraryPathResolver`. It does not
load the "latest" chart — each row is independently openable. This avoids returning to
fix behavior after UI is built (V3.4.2 Round B).

### Adj-10: Add fail-soft tests for degraded reads; concurrent write deferred to V3.5
Corrupt or partially written JSON files must not crash the read path — use cases must
return nil (fail-soft). Add tests in V3.4.2 and V3.4.3: corrupt JSON → nil, truncated
file → nil, schema version unknown → nil. Concurrent write consistency tests (two
processes writing the same sample simultaneously) are V3.5 scope and must not be
mixed into V3.4 test files.

---

## Current State (baseline for V3.4)

After V3.3 closure (v3.3.3.10, 237 tests):

### Already built
- `WorkbenchResultContracts.swift` — all data contract types:
  `WorkbenchMetricRecord`, `WorkbenchMeasurementDataStore`, `WorkbenchResultsIndex`,
  `WorkbenchResultReference`, `WorkbenchRunManifest`, `WorkbenchLatestMetricPointer`,
  `WorkbenchMetricOverrideInfo`.
- `PersistChartArtifactUseCase` — writes PNG + manifest + upserts `results_index.json`
  per sample (already uses `AtomicFileWriter`; single + multi-sample paths).
  **Known issue:** generates `runID` internally; must be changed in V3.4.0 (Adj-2).
- `AtomicFileWriter` — fsync + temp-file swap commit; crash-safe single-file interface.
- `LibraryPathResolver` — relative ↔ absolute path translation; root-escape rejection.
- `ConditionAliasConfig` / `ConditionAliasBook` — alias resolution + `displayLabel(for:)`
  already implemented; `ConditionAliasConfigLoader` enforces schema version strictly.
- `LibraryDetailSections.swift` — `LibraryMeasurementsDoneSection` exists; ready to be
  extended with two new read-only sections.
- `AHEWorkspaceStore` — `attemptPersistAndTrace` is the current persist entry point.
  **Known issues:** uses `try?` (Adj-3); does not generate a shared `runID` (Adj-2).

### Not yet built
- Shared `runID` generation in `AHEWorkspaceStore` render flow.
- `PersistenceOutcome` type and error surfacing in `AHEWorkspaceStore`.
- `PersistMeasurementDataUseCase` — `measurement_data.json` write path.
- AHE metric extraction (Hc) → metric record → `measurement_data.json`.
- `pendingMetricOverride` state in `AHEWorkspaceStore` + override UI.
- `LoadWorkbenchResultsUseCase` + `LibraryFeatureStore` projection.
- `LoadMeasurementDataUseCase` + `LibraryFeatureStore` projection.
- `WorkbenchResultsSectionView` — Library read model UI for chart references.
- `MeasurementDataSectionView` — Library read model UI for latest metric values.
- Override marker (`*`) and alias badge in `MeasurementDataSectionView`.

---

## V3.4.0 — Measurement Data Write Path + runID Alignment

Scope:
- Generate `runID` once in `AHEWorkspaceStore` render flow; pass explicitly into
  both `PersistChartArtifactUseCase` and `PersistMeasurementDataUseCase` (Adj-2).
- Replace `try?` in `attemptPersistAndTrace` with a typed `PersistenceOutcome`
  (`.success`, `.partial(chartOK: Bool, metricOK: Bool)`, `.failure(AppError)`)
  returned to the store and surfaced in UI state (Adj-3).
- Implement `PersistMeasurementDataUseCase`:
  - Reads existing `measurement_data.json` (or creates fresh `WorkbenchMeasurementDataStore`).
  - Calls `store.append(record)` to add `WorkbenchMetricRecord` and update `latestIndex`.
  - Writes via `AtomicFileWriter`. Path: `samples/<sampleKey>/_spinlab/measurement_data.json`.
- Wire AHE Hc extraction as the first metric producer:
  - Extract Hc estimate (or placeholder) from rendered series.
  - Build `WorkbenchMetricRecord` with shared `runID`, `overrideInfo = nil`.
  - Call `PersistMeasurementDataUseCase` after `PersistChartArtifactUseCase`.
- Bump `AppVersion`; run `build_desktop_app.sh debug` (Adj-6).

User-visible acceptance:
- After Workbench AHE render+persist, `measurement_data.json` exists under the sample
  drawer and contains a metric record for the run.
- If metric write fails, store reflects `partial` outcome and UI shows an error message.

Definition of Done (DoD):
- `runID` generated once per render; shared by manifest and metric record.
- `PersistMeasurementDataUseCase` uses `AtomicFileWriter`; no raw `Data.write`.
- `PersistenceOutcome` type defined; `attemptPersistAndTrace` no longer uses `try?`.
- Store exposes outcome state; UI reflects partial/failure conditions.
- `latestIndex` updated correctly after each append.
- Condition keys passed to `WorkbenchMetricIdentity.makeIdentityKey` are canonical
  (not alias) keys — enforced by use case, verified by test (Adj-8).
- All 237+ existing tests pass.

Test naming:
- `Tests/SpinLabAppTests/V340MeasurementDataWritePathTests.swift`
- Tests:
  - Round-trip: append one record → decode store → record present + `latestIndex` updated.
  - Same metric identity key appended twice → `latestIndex` shows only latest.
  - Different condition values → both keys present in `latestIndex`.
  - `runID` in metric record matches `runID` in manifest from same render.
  - `PersistenceOutcome.partial` emitted when metric write throws.
  - Path is Library-root-relative; resolved via `LibraryPathResolver`.
  - Alias key and canonical key passed separately → produce **distinct** `latestIndex` entries (storage layer does NOT resolve aliases — Adj-8).

---

## V3.4.1 — Manual Override Capture

Scope:
- Add `OverrideSource` enum to `WorkbenchResultContracts.swift`:
  cases `manual`, `import`, `recompute` (Adj-7).
- Add `source: OverrideSource` field to `WorkbenchMetricOverrideInfo` (Adj-7).
  All existing `WorkbenchMetricOverrideInfo` callsites (currently none in production)
  must supply `source`.
- Add `WorkbenchMetricOverrideCandidate` value type to AHE layer:
  `{ proposedValue: Double, reason: String, source: OverrideSource }`.
- Extend `AHEWorkspaceStore` with `pendingMetricOverride: WorkbenchMetricOverrideCandidate?`.
- Extend `AHEWorkspaceView` (or a subcomponent) with a pre-persist correction field:
  - Shown after ingestion, before "Save to Library".
  - User can leave blank (no override) or enter corrected value + reason.
  - `source` defaults to `.manual` for user-entered corrections.
- When `PersistMeasurementDataUseCase` is called:
  - If `pendingMetricOverride` is set, populate `WorkbenchMetricOverrideInfo`
    (`oldValue` = extracted value, `newValue` = user value, `reason` = user reason,
    `source` = candidate source, `at` = `generatedAt`).
  - Clear `pendingMetricOverride` after successful persist.
- `latestIndex` records the override value (not the raw extracted value).
- Bump `AppVersion`; run `build_desktop_app.sh debug` (Adj-6).

User-visible acceptance:
- User can enter a corrected Hc value + reason before saving.
- `measurement_data.json` record shows `overrideInfo` with old/new/reason/at.
- If no correction entered, `overrideInfo` is nil (identical to V3.4.0 behavior).

Definition of Done (DoD):
- `pendingMetricOverride` cleared from store after successful persist.
- Override logic is contained within `AHEWorkspaceStore`; nothing leaks to `WorkbenchFeatureStore`.
- All 237+ existing tests pass.

Test naming:
- `Tests/SpinLabAppTests/V341ManualOverrideCaptureTests.swift`
- Tests:
  - No override → `overrideInfo` nil in persisted record.
  - Override set → `overrideInfo.oldValue`, `.newValue`, `.reason`, `.source`, `.at` correct.
  - `source == .manual` for user-entered correction.
  - Override cleared from store after successful persist.
  - `latestIndex` pointer reflects override value, not raw extracted value.

---

## V3.4.2 — Library Read Model: Workbench Results

### Round A — UseCase + Store Projection

Scope:
- Implement `LoadWorkbenchResultsUseCase`:
  - Reads `samples/<sampleKey>/_spinlab/results_index.json`.
  - Returns `WorkbenchResultsIndex?` (nil if file absent or schema mismatch).
  - Read-only; no write side effects.
- Extend `LibraryFeatureStore` with `workbenchResults: WorkbenchResultsIndex?` projection.
- Trigger load when sample selection changes in Library.
- No UI changes in this round.

Test naming (included in V342 test file):
- Load missing file → nil (no crash).
- Valid index with two references → both present.
- Schema version mismatch → nil (graceful, not crash).

### Round B — Library Section UI

Scope:
- Add `WorkbenchResultsSectionView` to `LibraryDetailSections.swift`:
  - `DisclosureGroup` titled "Workbench Results" (collapsed by default).
  - Lists each `WorkbenchResultReference`: workflow ID, `generatedAt`, "Show" button.
  - "Show" button: opens the PNG referenced by that specific row via `NSWorkspace.open`
    resolved through `LibraryPathResolver` — not the latest chart, but the exact artifact
    linked to the reference (Adj-9).
  - Shows "No Workbench results yet" when projection is nil or empty.
  - Read-only: no edit, no delete.
- Wire into Library sample detail panel; binds to `LibraryFeatureStore.workbenchResults`.
- Bump `AppVersion`; run `build_desktop_app.sh debug` (Adj-6).

User-visible acceptance:
- Selecting a sample with results shows "Workbench Results" with chart reference list.
- "Show" opens chart PNG.
- Sample with no results shows "No Workbench results yet".

Test naming:
- `Tests/SpinLabAppTests/V342WorkbenchResultsReadModelTests.swift`
- Tests (covering both rounds):
  - Use case returns nil for missing file.
  - Use case returns index for valid file.
  - Corrupt JSON → nil, no crash (Adj-10).
  - Truncated file → nil, no crash (Adj-10).
  - Schema version unknown → nil, no crash (Adj-10).
  - `WorkbenchResultsSectionView` renders reference list (mock projection).
  - Section renders empty state when projection is nil.

---

## V3.4.3 — Library Read Model: Measurement Data + Override Marker + Alias Badge

### Round A — UseCase + Store Projection

Scope:
- Implement `LoadMeasurementDataUseCase`:
  - Reads `samples/<sampleKey>/_spinlab/measurement_data.json`.
  - Returns `WorkbenchMeasurementDataStore?` (nil if absent or schema mismatch).
  - Read-only.
- Extend `LibraryFeatureStore` with `measurementData: WorkbenchMeasurementDataStore?` projection.
- Load `ConditionAliasBook` in `LibraryFeatureStore` (best-effort; nil if config absent
  or load fails — non-fatal per Adj-5).
- Trigger load when sample selection changes.
- No UI changes in this round.

Test naming (included in V343 test file):
- Load missing file → nil.
- Valid store with two entries → both in `latestIndex`.
- Schema mismatch → nil.
- Alias config absent → book is nil; no crash.

### Round B — Library Section UI + Override Marker + Alias Badge

Scope:
- Add `MeasurementDataSectionView` to `LibraryDetailSections.swift`:
  - `DisclosureGroup` titled "Measurement Data" (collapsed by default).
  - Iterates `latestIndex` sorted by key.
  - Each row: metric name, value + canonical unit, condition key/value pairs.
  - Override marker: if `latestIndex` pointer's `recordID` matches a record with
    non-nil `overrideInfo`, append `*` (e.g. `1.05 T *`). No other override detail shown.
  - Alias badge: condition keys rendered via `ConditionAliasBook.displayLabel(for:)`
    when book is non-nil; plain key when book is nil.
  - Shows "No measurement data yet" when projection is nil or `latestIndex` is empty.
  - Read-only.
- Wire into Library sample detail panel; binds to `LibraryFeatureStore.measurementData`
  and `LibraryFeatureStore.conditionAliasBook`.
- Bump `AppVersion`; run `build_desktop_app.sh debug` (Adj-6).

User-visible acceptance:
- Selecting a sample with measurement data shows "Measurement Data" with latest values.
- Overridden values show `*`.
- Alias condition keys show `canonical (alias: legacy)`.
- Sample with no data shows "No measurement data yet".
- Alias config absent → condition keys shown plain; no crash.

Test naming:
- `Tests/SpinLabAppTests/V343MeasurementDataReadModelTests.swift`
- Tests (covering both rounds):
  - Use case returns nil for missing file; nil for schema mismatch.
  - Corrupt JSON → nil, no crash (Adj-10).
  - Truncated file → nil, no crash (Adj-10).
  - Store with override record → `*` shown; non-override record → no `*`.
  - Alias book present → display label with alias badge.
  - Alias book nil → plain key, no crash.
  - `MeasurementDataSectionView` renders empty state when projection is nil.

---

## V3.4 Stage Gate

V3.4 is complete only when all are true:

- [ ] `runID` generated once per render; shared by manifest and metric record (Adj-2).
- [ ] No `try?` on persistence paths; `PersistenceOutcome` surfaced to UI (Adj-3).
- [ ] `PersistMeasurementDataUseCase` writes `measurement_data.json` via `AtomicFileWriter`.
- [ ] Manual override captured pre-persist; `overrideInfo` populated correctly.
- [ ] `LoadWorkbenchResultsUseCase` + `LibraryFeatureStore` projection operational.
- [ ] `LoadMeasurementDataUseCase` + `LibraryFeatureStore` projection operational.
- [ ] Library "Workbench Results" section renders chart references (read-only).
- [ ] Library "Measurement Data" section renders latest values (read-only).
- [ ] Override marker `*` shown for overridden values only.
- [ ] `WorkbenchMetricOverrideInfo` includes `source: OverrideSource` (Adj-7).
- [ ] Alias badge shown when `ConditionAliasBook` present; plain key when absent.
- [ ] Condition keys into `makeIdentityKey` are canonical, not alias keys (Adj-8).
- [ ] "Show" button opens the exact referenced PNG, not always latest (Adj-9).
- [ ] Corrupt/truncated JSON returns nil in all read use cases; no crash (Adj-10).
- [ ] No JSON reads in `LibraryView.swift` or any Library subview (Adj-5).
- [ ] All new write paths use `AtomicFileWriter`; no raw `Data.write` to Library paths.
- [ ] All tests pass (237 baseline + V3.4 new tests).
- [ ] `AppVersion` bumped at each iteration; `build_desktop_app.sh debug` passed (Adj-6).
- [ ] QA Desktop `.app` produced at V3.4 closure.

Stage gate checklist to be tracked in:
- `docs/plans/V3_4_ACCEPTANCE_CHECKLIST.md` (created when V3.4.0 implementation starts)

---

## Decision Log

1. `PersistMeasurementDataUseCase` is separate from `PersistChartArtifactUseCase` —
   distinct write responsibilities; keeps each use case independently testable.

2. `runID` generated once in `AHEWorkspaceStore`, passed explicitly into both use cases —
   required for cross-reference traceability between manifest and metric record (Adj-2).

3. `PersistenceOutcome` replaces `try?` — partial failure (chart OK, metric fail) must
   be visible to the user; silent swallow is unacceptable (Adj-3).

4. Override UI in `AHEWorkspaceStore` / `AHEWorkspaceView` only — AHE-specific in V3.4;
   a workflow-generic pre-write correction protocol deferred to future iteration (Adj-4).

5. Library read models in UseCase + `LibraryFeatureStore`; Views only render projected
   state — no JSON reads in view layer (Adj-5).

6. V3.4.2 and V3.4.3 each delivered in two rounds (UseCase/Store then UI) — required by
   codebase rule separating logic and UI into distinct rounds (Adj-1).

7. Override marker is inline `*` only — detail drill-down (old value, reason, timestamp)
   deferred to future UI iteration.

8. `NSWorkspace.open` for chart preview — inline image preview deferred; OS viewer
   sufficient for V3.4 acceptance.

9. `OverrideSource` enum added to `WorkbenchMetricOverrideInfo` in V3.4.1 — cheapest
   point to add it; schema migration cost grows after first production write (Adj-7).

10. `latestIndex` stores canonical condition keys only; alias resolution is display-layer
    only via `ConditionAliasBook.displayLabel` — storage layer must never contain alias
    keys as identity keys (Adj-8). `WorkbenchArtifactIdentity.makeIdentityKey` already
    normalizes but does not resolve aliases; caller is responsible for canonical input.

11. "Show" loads specific referenced PNG — per-row action, not a "load latest" shortcut.
    Confirmed before UI build to avoid post-delivery behavior rework (Adj-9).

12. Concurrent write consistency tests deferred to V3.5 — V3.4 only covers fail-soft
    degraded reads (Adj-10). Mixing concurrency tests into V3.4 would conflate two
    separate reliability concerns.
