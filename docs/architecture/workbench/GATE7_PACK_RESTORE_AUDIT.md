# Gate 7.6 — Pack / Restore Audit

**Audit status**: complete (docs-only, 2026-06-10)
**Gate 7.6A status**: complete (protection tests, 2026-06-10) — 34 tests in `V760PackRestoreProtectionTests.swift`, all pass
**Branch**: gate7.6
**Scope**: map current ownership boundary after Gate 7.4 and Gate 7.5; no runtime or schema changes.

---

## Gate 7.6A Result Summary (2026-06-10)

34 tests added in `V760PackRestoreProtectionTests.swift` across 5 suites. All pass. No behavior drift exposed.

**Key confirmations from running the tests:**
- `cachedRTFilePath` is derived output: confirmed `selectedRTHit?.measurementFilePath` is the source, not `config.rtFilePath`
- Overwrite sequence locked: intermediate write `cachedRTFilePath = config.rtFilePath` appears before `_snapshotAndCacheManifestPayloads()`, and no re-assignment appears after — the order is now pinned by source inspection
- 3ω and XY required fields all throw on missing input — decode failure is clean (no crash)
- AHE / XY / 3ω optional field backward-compat all produce correct defaults
- Wired `WorkbenchAnalysisOverlayRuntime` is cleared on restore (V740 only tested the standalone fallback; now both paths are covered)

**Gate 7.6B recommendation (cachedRTFilePath):**

Treat `cachedRTFilePath` as **derived output only**. The intermediate assignment `cachedRTFilePath = config.rtFilePath` in `restoreFromPack` is overwritten unconditionally by `_snapshotAndCacheManifestPayloads()`. It should be removed: it is noise that could mislead future engineers into thinking `config.rtFilePath` is a standalone restore input. `ThreeOmegaPackConfig.rtFilePath` (the serialized field) is still useful for the pack fingerprint; it does not need to be a restore input.

**Gate 7.6B recommendation (_overlayPackIDs standalone fallback):**

Remove `_overlayPackIDs` standalone fallback after updating tests that access `store._overlayPackIDs` or `store.overlayPackIDs` directly. V740 tests currently use this path. The wired-runtime path is now confirmed working (V760 §5).

---

## 1. Pack Schema

### 1a. ThreeOmegaPackConfig / ThreeOmegaPackResult

**Required fields** (bare `decode` — missing field crashes decode):
- `device`, `geometry`, `fitRanges`, `v3Method`, `sampleBatchAndSubstrate`, `activeTab`, `stackOffsetMultiplier`, `showPlotGrid`

**Optional with backward-compatible defaults** (`decodeIfPresent`):

| Field | Added | Default |
|---|---|---|
| `rahe1Method` | post-initial | falls back to `v3Method` |
| `rahe3Method` | post-initial | falls back to `v3Method` |
| `rtFilePath` | post-initial | `nil` |
| `titleTemplate` | post-initial | `""` |
| `minGapFraction` | post-initial | `0.15` |
| `plotLegendAnchor` | post-initial | `""` |
| `tabStates` | v5.3.3 | `[:]` |
| `chartStyleOverrides` | v5.3.5 | `[:]` |
| `cachedSearchResults` | v5.3.4 | `[]` |
| `selectedSearchResultIDs` | v5.3.4 | `[]` |
| `selectedRTHit` | v5.3.4 | `nil` |
| `rtQuery` | v5.3.4 | `""` |
| `searchQueryText` | v5.3.4 | `""` |

**ThreeOmegaPackResult**:
- `ingestionResult` — required
- `scalingResult` — optional (`nil` for pre-scaling packs)

### 1b. AHEPackConfig / AHEPackResult

**Hard rejection path**: packs containing `plotAxisXOverride` or `plotAxisYOverride` are actively refused with a user-facing message referencing the retired axis-override module. This is the only rejection-by-content decode guard in the codebase.

**All config fields are optional** (`decodeIfPresent`):

| Field | Default |
|---|---|
| `titleTemplate` | `""` |
| `showPlotGrid` | `true` |
| `tabStates` | `[:]` |
| `cachedSearchResults` | `[]` |
| `selectedSearchResultIDs` | `[]` |
| `searchQueryText` | `""` |

**AHEPackResult**: `ingestionResult` is `Optional<AHEIngestionResult>` — `nil` for legacy packs pre-v5.3.4. This is the only result type where a nil result is a legal pack state that triggers re-analysis on restore.

### 1c. XYRotationPackConfig / XYRotationPackResult

**Required fields**:
- `phiOffsetOverrides`, `centerBaseline`, `activeTab`

**Optional with backward-compatible defaults**:

| Field | Default |
|---|---|
| `linearDetrend` | `false` |
| `titleTemplate` | `""` |
| `stackOffsetMultiplier` | `0.0` |
| `minGapFraction` | `0.15` |
| `showPlotGrid` | `true` |
| `tabStates` | `[:]` |
| `cachedSearchResults` | `[]` |
| `selectedSearchResultIDs` | `[]` |
| `searchQueryText` | `""` |

**XYRotationPackResult**: `ingestionResult` — required.

### 1d. Old-pack compatibility paths

Five distinct compat paths exist:

1. **AHE deprecated-axis rejection** (`AHEPackContracts.swift`) — hard throw with user message. Tested in `V537PackRestoreModuleBoundaryTests.aheDeprecatedAxisOverridePackFailsWithClearMessage`.
2. **3ω RAHE method split** — `rahe1Method` / `rahe3Method` fall back to `v3Method` for pre-RAHE-split packs.
3. **AHE nil ingestion** — `AHEPackResult.ingestionResult == nil` is legal; triggers `runAnalysis()` on restore. Tested in `V537PackRestoreModuleBoundaryTests.aheRestoreNilIngestionActivatesRunAnalysis`.
4. **Pre-5.3.3 tabStates / pre-5.3.5 chartStyleOverrides** — default to `[:]` for all workflows.
5. **Pre-5.3.4 search state fields** — `cachedSearchResults`, `selectedSearchResultIDs`, `rtQuery`, `searchQueryText`, `selectedRTHit` all default to empty / nil.

---

## 2. Restore Ownership

### 2a. Who owns restore

The ownership chain has two layers:

- **Shell layer** — `AnalysisPackProviding` protocol extension provides `loadPack(id:restoreSearchState:seedSelection:)`. This default impl: cancels inflight work, fetches pack from vault, decodes config + result, calls `restoreFromPack`, then sets `activePackID` and `analysisMessage`. `activePackID` is explicitly set **after** `restoreFromPack` returns; conformers must not set it inside restore.
- **Workflow layer** — Each workflow store implements `restoreFromPack(config:result:pack:restoreSearchState:seedSelection:)`. The shell knows nothing about what fields each workflow restores.
- `WorkbenchFeatureStore` is the session-level coordinator that calls `loadPack` on the active workflow store and provides the `restoreSearchState` / `seedSelection` callbacks that route into `WorkbenchMainSearchRuntime` and `WorkbenchSelectionRuntime`.

### 2b. Fields restored per workflow

#### 3ω (ThreeOmegaWorkspaceStore, `ThreeOmegaWorkspaceStore+Pack.swift`)

| Category | Fields |
|---|---|
| Analysis params | `geometry`, `fitRanges`, `v3Method`, `rahe1omegaMethod`, `rahe3omegaMethod` |
| RT state | `rtQuery`, `selectedRTHit`, `persistRTQuery()` (UserDefaults sync) |
| Display | `activeTab`, `titleTemplate`, `stackOffsetMultiplier`, `minGapFraction`, `showPlotGrid`, `legendAnchor` |
| Per-tab | `tabStates`, `chartStyleOverrides` |
| Search | `cachedSearchResults`, `seedSelection()`, `restoreSearchState()` |
| Results | `ingestionResult`, `scalingResult` |
| Persistence context | `cachedInputFiles`, `cachedSampleKeys`, `cachedRTFilePath` (see §3 for caveat) |
| Library root | `lastLibraryRootPath` (from vault if empty) |
| Overlay | `overlayRuntime?.clear()`, `_overlayPackIDs = []`, `overlaySnapshots = [:]` |
| Title tokens | `_titleTokens` (rebuilt from first restored search hit) |
| Post-restore | `_rerenderAllTabsFromRestoredState()`, `_snapshotAndCacheManifestPayloads()`, `refreshRelatedCharts()` |
| Series order migration | pre-5.3.6 Int-keyed tabState override → sampleID key migration |

#### AHE (AHEWorkspaceStore)

| Category | Fields |
|---|---|
| Display | `titleTemplate`, `showPlotGrid` |
| Per-tab | `tabStates` |
| Search | `cachedSearchResults`, `seedSelection()`, `restoreSearchState()` |
| Results | `ingestionResult` |
| Persistence context | `cachedInputFiles`, `lastRenderedSampleKeys` (from pack.sampleKeys) |
| Library root | `lastLibraryRootPath` |
| Post-restore | `_rerenderActiveTab()` if ingestionResult != nil, else `runAnalysis()` (legacy path) |

Note: AHE has no overlay, no RT, no scaling result, no stack offset.

#### XY (XYRotationWorkspaceStore)

| Category | Fields |
|---|---|
| Analysis params | `phiOffsetOverrides`, `centerBaseline`, `linearDetrend` |
| Display | `activeTab`, `titleTemplate`, `stackOffsetMultiplier`, `minGapFraction`, `showPlotGrid` |
| Per-tab | `tabStates` |
| Search | `cachedSearchResults`, `seedSelection()`, `restoreSearchState()` |
| Results | `ingestionResult` |
| Persistence context | `cachedInputFiles`, `cachedSampleKeys` |
| Library root | `lastLibraryRootPath` |
| Post-restore | `_rerenderAllTabs()`, `refreshRelatedCharts()` |

### 2c. Fields deliberately NOT restored (session-only)

These fields are never written by `restoreFromPack` and must remain nil / zero after restore:

| Field | Owner | Reason |
|---|---|---|
| `persistenceOutcome` | Save module | set only by `applyPersistenceOutcome` after save |
| `saveMessage` | Save module | set only by `executeSave` |
| `currentRunTrace` | Analysis module | committed only by `commitRunTrace()` after analysis completes |
| `pendingMetricOverride` (AHE) | Save module | session-only override candidate |
| `pendingRAHEOverride` (AHE) | Save module | session-only override candidate |
| `isAnalyzing` / `isPlotRendering` | Analysis module | cancelled by `cancelInflightWork()` |
| `analysisMessage` / `plotMessage` | Analysis module | not a restored field |

Tests that protect this: `V537PackRestoreModuleBoundaryTests` §5 (all three workflows), `V537PackRestoreModuleBoundaryTests.threeOmegaRestoreFromPackNoDirectCommitTrace` (source inspection).

---

## 3. Secondary Input Search / Cached RT Path

### 3a. Pack fields related to RT

`ThreeOmegaPackConfig` contains three RT-related fields:
- `selectedRTHit: WorkflowMeasurementSearchHit?` — the full serialized hit struct
- `rtQuery: String` — the RT search query
- `rtFilePath: String?` — the measurement file path (a derived snapshot, **not** an independent restore input; see §3b)

### 3b. Restore priority chain (current behavior, locked by V730 tests)

1. **Priority 1** — `config.selectedRTHit` non-nil: `restoreFromPack` writes it directly to `store.selectedRTHit`. Most common case.
2. **Priority 2** — `pendingRTSidecarPath`: NOT set by `restoreFromPack`. This is the interaction-snapshot restore path, orthogonal to pack restore. `applyRestoredRTHit()` / `clearPendingRTRestore()` handle it after search completes.
3. **Priority 3** — `config.rtFilePath` non-nil but `selectedRTHit` nil: `restoreFromPack` writes `config.rtFilePath` to `cachedRTFilePath`, but `_snapshotAndCacheManifestPayloads()` at the end of restore **overwrites** `cachedRTFilePath` with `selectedRTHit?.measurementFilePath` — which is `nil` when no hit is selected. Net result: **`cachedRTFilePath` is nil after restore** regardless of `config.rtFilePath`. Documented as current behavior in `V730SecondaryInputSearchBaselineTests.priority3_cachedRTFilePathDerivedFromSelectedRTHit`.
4. **Priority 4** — all nil: slot stays unbound, no crash.

### 3c. cachedRTFilePath: derived output, not restore input

The intermediate assignment `cachedRTFilePath = config.rtFilePath` in `restoreFromPack` (line 155) is effectively a no-op: it is unconditionally overwritten by `_snapshotAndCacheManifestPayloads()` later in the same function. This means:

- `config.rtFilePath` in the pack is a redundant serialization of `cachedRTFilePath` at save time.
- The only effective restore path for RT state is `selectedRTHit`.
- If a user saves a pack with an RT file selected, the `selectedRTHit` carries the file identity. If the sidecar disappears after save, there is no independent fallback from `rtFilePath`.

**This is the deferred debt noted in Gate 7.3**: "cachedRTFilePath standalone rebuild is not implemented. Gate 7.6 Pack/Restore extraction should revisit the secondary input restore bridge."

### 3d. What is needed to make RT restore explicit and safe

To make the restore path explicit and correct (not implementing, documenting):

1. Decide whether `config.rtFilePath` is a standalone restore input or a cache-coherence snapshot:
   - If **standalone input**: `restoreFromPack` should write it directly and `_snapshotAndCacheManifestPayloads()` must not overwrite it when `selectedRTHit` is nil.
   - If **cache snapshot only**: the intermediate assignment at line 155 should be removed; `rtFilePath` in the pack becomes a fingerprint-only field (which it effectively is now).
2. If standalone: add a test that `cachedRTFilePath` survives restore when `selectedRTHit` is nil but `config.rtFilePath` is non-nil.
3. Consider whether `WorkbenchSecondaryInputSearchRuntime` should own the persisted RT query from pack (it currently restores from UserDefaults; the pack's `rtQuery` is written to `store.rtQuery` and then `persistRTQuery()` syncs to UserDefaults).

**Do not implement in Gate 7.6A** — audit only.

---

## 4. Analysis Overlay Interaction

### 4a. What is session-only (confirmed)

`WorkbenchAnalysisOverlayRuntime` owns:
- `overlayIDs: [AnalysisPack.ID]` — session-only ordered list
- `displayLabels: [AnalysisPack.ID: String]` — session-only chip labels

`ThreeOmegaWorkspaceStore` owns:
- `overlaySnapshots: [AnalysisPack.ID: OverlaySnapshot]` — session-only render content
- `_overlayPackIDs: [AnalysisPack.ID]` — standalone fallback, also session-only

### 4b. Overlay state is not serialized (confirmed)

`ThreeOmegaPackConfig` and `ThreeOmegaPackResult` have no overlay fields. `_buildPackConfig()` never reads overlay state. JSON round-trip test: `V740AnalysisOverlayBaselineTests.packConfigDoesNotSerializeOverlayState` and `packResultDoesNotSerializeOverlayState`.

### 4c. Restore clears overlay state (confirmed)

`restoreFromPack` in 3ω explicitly:
```
overlayRuntime?.clear()    // clears common runtime when wired
_overlayPackIDs = []       // resets standalone fallback unconditionally
overlaySnapshots = [:]     // clears snapshot content
```

Both clear paths run unconditionally to prevent drift in no-runtime-wired test contexts. Tests: `V740AnalysisOverlayBaselineTests.restoreFromPackClearsOverlayPackIDs` and `restoreFromPackClearsOverlaySnapshots`.

### 4d. Overlay snapshots are not restored from pack (confirmed)

`addOverlay()` in `ThreeOmegaWorkspaceStore+Pack.swift` reads a vault pack at add-time and captures the snapshot into `overlaySnapshots`. This is an add-session operation only. Pack restore does not load overlay packs or reconstruct snapshots. The design choice is intentional: overlay state is a session composition and not part of the saved workspace identity.

### 4e. Deferred debt from Gate 7.4

The `_overlayPackIDs` standalone fallback can be removed once no test constructs a `ThreeOmegaWorkspaceStore` without a wired `WorkbenchAnalysisOverlayRuntime`. The fallback exists to keep tests that don't construct a full `WorkbenchFeatureStore` green. This cleanup belongs in Gate 7.6 or a post-Gate-7.6 pass.

---

## 5. Save-to-Library Interaction

### 5a. Save coordinator state not serialized (confirmed)

Three fields are explicitly confirmed not written by restore:
- `saveMessage` — nil after all three workflow restores
- `persistenceOutcome` — nil after all three workflow restores
- `currentRunTrace` — nil after all three workflow restores (never committed by restore)

Source inspection test: `V537PackRestoreModuleBoundaryTests` §1 (`restoreFromPack source does not call commitRunTrace() directly`).

### 5b. Save coordinator did not create new pack/restore state (confirmed)

Gate 7.5B extracted `WorkbenchSaveCoordinating` as a shared async protocol. Audit of `WorkbenchSaveCoordinating.swift` confirms:
- `executeSave` only touches: `persistenceOutcome` (via `applyPersistenceOutcome`), `currentRunTrace`, `saveMessage`, `refreshRelatedCharts()`. No pack fields, no vault writes, no `activePackID` mutations.
- `didCompleteSave` hook is AHE-specific for override clearing; no pack state involved.
- `saveAnalysis()` on `AnalysisPackProviding` is a separate path that calls `vault.add()` / `vault.update()`; this is pack persistence, not save-to-library.

### 5c. Metric projection is save-time only (confirmed)

`buildActiveChartMetrics()` is called at `persistToLibrary()` call time. The result (`[PendingMetricEntry]`) is not cached in pack config or result. Each save generates a fresh projection from live session state (`scalingResult`, `lastExtractedMetrics`). No pack field stores extracted metrics.

### 5d. Pack save does NOT serialize save-module state

`_buildPackConfig()` and `_buildPackResult()` (all three workflows) do not touch:
- `saveMessage`
- `persistenceOutcome`
- `currentRunTrace`
- `pendingMetricOverride` / `pendingRAHEOverride`
- `persistCount`

Tests: `V537SaveModuleBoundaryTests` (Gate 7.5A/B coverage) + `V537PackRestoreModuleBoundaryTests` §5.

---

## 6. Test Coverage Map

### 6a. Tests that currently protect

| Area | Test file | Key tests |
|---|---|---|
| Old pack decode — AHE deprecated fields | `V537PackRestoreModuleBoundaryTests` | `aheDeprecatedAxisOverridePackFailsWithClearMessage` |
| Old pack decode — AHE nil ingestion | `V537PackRestoreModuleBoundaryTests` | `aheRestoreNilIngestionActivatesRunAnalysis` |
| AHE restore — session fields nil | `V537PackRestoreModuleBoundaryTests` | `aheRestoreNonLegacyDoesNotSetSessionOnlyFields` |
| AHE restore — tray hydration | `V537PackRestoreModuleBoundaryTests` | `aheRestoreTrayRowsHydratedImmediately`, `aheRestoreIsAllSelectedAllSelected` |
| 3ω restore — session fields nil | `V537PackRestoreModuleBoundaryTests` | `threeOmegaRestoreDoesNotSetSessionOnlyFields` |
| 3ω restore — trace nil after restore | `V537PackRestoreModuleBoundaryTests` | `threeOmegaRestoreTraceNilAfterRestore` |
| 3ω restore — tray / snapshot hydration | `V537PackRestoreModuleBoundaryTests` | `threeOmegaRestoreTrayRowsHydratedImmediately`, `threeOmegaRestoreSnapshotHydratedImmediately`, `threeOmegaRestoreOrphanIDKeptNoCrash` |
| XY restore — session fields nil | `V537PackRestoreModuleBoundaryTests` | `xyRestoreDoesNotSetSessionOnlyFields` |
| XY restore — tray hydration | `V537PackRestoreModuleBoundaryTests` | `xyRestoreIsAllSelectedAllSelected` |
| activePackID not set by restoreFromPack | `V537PackRestoreModuleBoundaryTests` | `threeOmegaRestoreFromPackDoesNotSetActivePackID`, `xyRestoreFromPackDoesNotSetActivePackID` |
| No commitRunTrace in restore | `V537PackRestoreModuleBoundaryTests` §1 | source inspection, all three workflows |
| Cross-workflow isolation | `V537PackRestoreModuleBoundaryTests` §6 | 3ω / XY / AHE canonical not corrupted by other workflow restore |
| Overlay not serialized | `V740AnalysisOverlayBaselineTests` | `packConfigDoesNotSerializeOverlayState`, `packResultDoesNotSerializeOverlayState`, `packRoundTripDoesNotPreserveOverlayIDs` |
| Overlay cleared on restore | `V740AnalysisOverlayBaselineTests` | `restoreFromPackClearsOverlayPackIDs`, `restoreFromPackClearsOverlaySnapshots` |
| clearPlot clears overlay | `V740AnalysisOverlayBaselineTests` | `clearPlotClearsOverlayState` |
| Overlay snapshot survives vault deletion | `V740AnalysisOverlayBaselineTests` | `overlaySnapshotSurvivesVaultDeletion` |
| RT restore priority chain | `V730SecondaryInputSearchBaselineTests` | `priority1–4` (4 tests) |
| RT slot isolation | `V730SecondaryInputSearchBaselineTests` | `guard_*` (4 tests) |
| Pack vault CRUD + round-trip | `V4117AnalysisPackVaultTests` | all tests |
| Restore use case stateless | `V5114RestoreUseCaseStatelessTests` | all tests |
| No trace commit on restore | `V5114PackRestoreNoTraceCommitTests` | all tests |
| Tab render state pack | `V535TabRenderStatePackTests` | all tests |
| Save coordinator state not serialized | `V537SaveModuleBoundaryTests`, `V750SaveSemanticProtectionTests` | various |

### 6b. Gaps identified before Gate 7.6 implementation

| Gap | Severity | Description |
|---|---|---|
| **cachedRTFilePath overwrite sequence** | HIGH | No test explicitly verifies the overwrite: `restoreFromPack` writes `config.rtFilePath` → `cachedRTFilePath`, then `_snapshotAndCacheManifestPayloads()` overwrites it. The V730 priority-3 test documents the final state (nil when selectedRTHit nil) but does not verify the intermediate write-then-overwrite order. Any refactor of this sequence could silently break fingerprint. |
| **3ω RT round-trip with non-nil selectedRTHit** | MEDIUM | No test saves a pack with a selectedRTHit, loads it back, and verifies `cachedRTFilePath == selectedRTHit.measurementFilePath`. This is the primary RT restore path and has no end-to-end coverage. |
| **3ω required-field decode failure** | MEDIUM | No test explicitly covers the path where a required field (e.g. `geometry`) is missing from a 3ω pack. The failure mode is `loadPack` setting `analysisMessage` and returning; no crash, but uncovered. |
| **XY required-field decode failure** | MEDIUM | Same as above for XY (`phiOffsetOverrides`, `centerBaseline`, `activeTab`). |
| **AHE showPlotGrid / tabStates missing** | LOW | The backward-compat decode defaults for AHE are implicit in V4117 round-trip tests but there is no test for a pack missing only `showPlotGrid` or only `tabStates`. |
| **XY linearDetrend backward-compat** | LOW | No test for a pack missing `linearDetrend` decoding as `false`. |
| **_overlayPackIDs standalone fallback** | LOW | Deferred from Gate 7.4: `_overlayPackIDs` fallback can be removed when no test uses `ThreeOmegaWorkspaceStore` without a wired overlay runtime. Current tests in `V740` use the fallback directly (e.g. `store.overlayPackIDs = [overlayID]`). Removing requires either a full-WFS fixture or a protocol accessor. |
| **AHE lastRenderedSampleKeys restore** | LOW | AHE restore sets `lastRenderedSampleKeys = pack.sampleKeys`. This is not the analyzed sample keys (those come from analysis output); it is the pack identity keys. Inconsistency is benign now but undocumented. |

---

## 7. Audit Conclusions

### What is currently safe

1. **Session-only fields** are not serialized and are nil after restore. Tested across all three workflows.
2. **Overlay state** is session-only, not in any pack, and cleared on every restore. Fully tested.
3. **Save coordinator state** never enters packs. Save-time metric projection is fresh on every save.
4. **AHE deprecated pack rejection** is hard and user-legible.
5. **Restore callback ordering** is correct: search state is seeded before analysis, `activePackID` is set after restore returns. Tested.
6. **Cross-workflow isolation**: restoring one workflow does not corrupt another workflow's canonical state. Tested.
7. **RT slot isolation**: RT slot state never contaminates `WorkbenchSearchSnapshot` or `WorkbenchSelectedHitsSnapshot`. Tested.

### What is dangerous

1. **`cachedRTFilePath` write-then-overwrite**: the intermediate assignment `cachedRTFilePath = config.rtFilePath` in `restoreFromPack` is overwritten by `_snapshotAndCacheManifestPayloads()`. Any future refactor that removes `_snapshotAndCacheManifestPayloads()` or reorders the post-restore calls could silently promote `config.rtFilePath` to a standalone restore path, changing fingerprint behavior. The current code is correct but brittle.
2. **No RT round-trip test with non-nil selectedRTHit**: the primary RT restore path (priority 1) has test coverage for the final state (`store.selectedRTHit == rtHit`) but no test that exercises full pack save → pack decode → restore with a non-nil selectedRTHit.

---

## 8. Implementation Targets

### Gate 7.6A — Baseline tests (add before any extraction)

These tests must be in place before any Gate 7.6 runtime extraction begins:

1. **3ω RT round-trip with selectedRTHit**: construct a pack with a non-nil `selectedRTHit` and non-nil `rtFilePath`, decode it, call `restoreFromPack`, verify `store.selectedRTHit == rtHit` and `store.cachedRTFilePath == selectedRTHit.measurementFilePath` (not `config.rtFilePath` if they differ).
2. **3ω cachedRTFilePath overwrite is documented**: a test (or an extension of the priority-3 test) that explicitly verifies the overwrite: write `config.rtFilePath` → restore → `cachedRTFilePath` ends up as `selectedRTHit?.measurementFilePath`, not `config.rtFilePath`.
3. **3ω decode failure path**: construct a JSON blob missing a required field, call `loadPack`, verify `analysisMessage` is set and store is not mutated.
4. **XY decode failure path**: same for XY.
5. **AHE missing optional fields**: construct an AHE pack JSON with only required-ish fields present, decode, verify default values.
6. **XY linearDetrend backward-compat**: pack without `linearDetrend` decodes as `false`.

### Gate 7.6B — Extraction / fix (if any)

Possible interventions based on audit (not all required; decide after 7.6A tests pass):

1. **Remove intermediate `cachedRTFilePath` assignment**: if the overwrite is intentional (derived-only), remove `cachedRTFilePath = config.rtFilePath` from `restoreFromPack`. The pack field `rtFilePath` becomes fingerprint-only (it is only used by `makeFingerprint` to derive `sourceFingerprint`). This makes the design explicit.
2. **OR: promote rtFilePath to standalone restore input**: if RT file path should survive when `selectedRTHit` is nil, guard `_snapshotAndCacheManifestPayloads()` to not overwrite `cachedRTFilePath` when `selectedRTHit` is nil. This is the path needed for full RT restore without a sidecar.
3. **`_overlayPackIDs` standalone fallback cleanup**: remove after updating V740 tests to use a full-WFS fixture or a protocol-level accessor.

### Deferred debt

- `selectionReader` bridge removal (Gate 7.2 deferred) — awaits this gate.
- XY `buildActiveChartMetrics()` returns `[]` — no metric extraction. Deferred post-7.6.
- Scaling Law overlay render path — Gate 7.4 deferred.
- Active-tab overlay rerender trigger into runtime — Gate 7.4 deferred.
- `PendingMetricEntry` bridge array typed projection — Gate 7.5 deferred.

---

## 9. Files Referenced

| File | Role |
|---|---|
| `Sources/.../Domain/AnalysisPack.swift` | Pack envelope, fingerprint, decode helpers |
| `Sources/.../Workbench/V3/ThreeOmegaPackContracts.swift` | 3ω config + result schema |
| `Sources/.../Workbench/V3/AHEPackContracts.swift` | AHE config + result schema |
| `Sources/.../Workbench/V3/XYRotationPackContracts.swift` | XY config + result schema |
| `Sources/.../Workbench/V3/AnalysisPackProviding.swift` | Shell protocol + default loadPack / saveAnalysis |
| `Sources/.../Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` | 3ω restoreFromPack, buildPackConfig/Result, overlay management |
| `Sources/.../Features/Workbench/AHEWorkspaceStore.swift` | AHE restoreFromPack |
| `Sources/.../Features/Workbench/XYRotationWorkspaceStore.swift` | XY restoreFromPack |
| `Sources/.../App/State/WorkbenchSecondaryInputSearchRuntime.swift` | RT slot session state |
| `Sources/.../App/State/WorkbenchAnalysisOverlayRuntime.swift` | Overlay session state |
| `Sources/.../Features/Workbench/WorkbenchSaveCoordinating.swift` | Save coordinator protocol + executeSave |
| `Sources/.../App/State/AnalysisVault.swift` | Vault CRUD + disk persistence |
| `Tests/.../V537PackRestoreModuleBoundaryTests.swift` | Primary restore contract tests |
| `Tests/.../V730SecondaryInputSearchBaselineTests.swift` | RT restore priority chain + isolation |
| `Tests/.../V740AnalysisOverlayBaselineTests.swift` | Overlay not serialized, cleared on restore |
| `Tests/.../V750SaveSemanticProtectionTests.swift` | Save coordinator state not in packs |
| `Tests/.../V4117AnalysisPackVaultTests.swift` | Vault CRUD + round-trip |
| `Tests/.../V5114RestoreUseCaseStatelessTests.swift` | RestoreAnalysisPackUseCase stateless |
| `Tests/.../V5114PackRestoreNoTraceCommitTests.swift` | Trace not committed by restore |
