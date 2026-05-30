# Workbench — Pack/Restore Module

> Persistence layer: AnalysisPack/AnalysisVault envelope, workspace state vs Library save distinction, restore as explicit cross-module operation, restore write map, what restore must not persist, per-workflow pack contracts, stale detection.

## Purpose

The Pack/Restore Module manages workspace state persistence across sessions. It is distinct from saving to Library.

- **Save to Library** — writes chart PNG + metrics into `_spinlab/` under the measurement directory. Managed by the Save Module via `SaveActiveChartToLibraryUseCase`. See "Workbench Write Boundary" below.
- **Pack/Restore** — saves and restores the full Workbench workspace state (analysis results, UI state, overlays) to/from `AnalysisVault`. No Library write occurs during pack/restore.

## Pack Envelope

`AnalysisPack` and `AnalysisVault` are the persistence envelope for a complete analysis session:

- `AnalysisPack` — domain model: workflow result + config + UI state snapshot. Contains `PackConfig` (UI state) and `PackResult` (must include `ingestionResult`).
- `AnalysisVault` — runtime collection of packs for a measurement; manages save/load/overlay lifecycle.

**Invariant**: `PackResult` must include `ingestionResult`. This allows restore to re-render without re-ingesting from disk.

## Restore Contract Summary

Pack restore is the **one documented exception** to ordinary sibling module mutation rules. Ordinarily, modules interact only through Main Board coordination; modules must not write each other's canonical state directly.

Pack restore is allowed to write multiple module states simultaneously because restoring a workspace is inherently cross-module. But this is not a license for ad hoc field writes. The restore contract is:

- **explicit** — every field written by restore is listed in the Restore Write Map below
- **bounded** — restore must not write state outside the documented set
- **non-triggering** — restore must not call `runAnalysis()` or `commitRunTrace()` (except the documented AHE legacy exception)

**Allowed:**
- restore may write analysis result, selection state, preservation state (tab overrides), search mirror, and physics parameters simultaneously via the restore contract
- restore may write canonical `WorkbenchFeatureStore` search state through the explicit `restoreSearchState` callback
- restore calls `_rerenderActiveTab()` / `_rerenderAllTabs()` / `_rerenderAllTabsFromRestoredState()` to reconstruct plot output from the restored state

**Forbidden:**
- restore must not call `runAnalysis()` or `commitRunTrace()` (except AHE legacy exception; see below)
- restore must not bypass the Pack Metadata Provider for pack structure
- restore must not write to Library (`_spinlab/` artifacts)
- restore must not write any field listed in "What Restore Must Not Persist"

## Restore Write Map

What restore writes, and which module owns the state:

| Restored state | Module owner | 3ω | AHE | XY |
|---|---|:---:|:---:|:---:|
| `cachedSearchResults` | Selection/Search mirror | ✓ | ✓ | ✓ |
| `selectedSearchResultIDs` | Selection Module | ✓ | ✓ | ✓ |
| `WorkbenchFeatureStore.searchResults[wf]` (via callback) | Search Module canonical | ✓ | ✓ | ✓ |
| `WorkbenchFeatureStore.searchQueryTexts[wf]` (via callback) | Search Module canonical | ✓ | ✓ | ✓ |
| `ingestionResult` | Analysis Lifecycle Module | ✓ | ✓ (optional) | ✓ |
| `scalingResult` | Analysis Lifecycle Module | ✓ | — | — |
| `tabs.activeTab` | Plot Preservation Module | ✓ | — | ✓ |
| `tabs.restoreStates(tabStates)` | Plot Preservation Module | ✓ | ✓ | ✓ |
| `tabs.chartStyleOverrides` | Plot Preservation Module | ✓ | — | — |
| `tabs.showPlotGrid` | Plot System | ✓ | ✓ | ✓ |
| `tabs.legendAnchor` | Plot System (3ω) | ✓ | — | — |
| `titleTemplate` | Plot Controls Module | ✓ | ✓ | ✓ |
| `stackOffsetMultiplier`, `minGapFraction` | Plot Controls / Physics | ✓ | — | ✓ |
| `geometry`, `fitRanges`, `v3Method`, `rahe1omegaMethod`, `rahe3omegaMethod` | 3ω Physics Function | ✓ | — | — |
| `rtQuery`, `selectedRTHit`; calls `persistRTQuery()` | 3ω RT Module | ✓ | — | — |
| `plotAxisXOverride`, `plotAxisYOverride` | AHE Plot Controls | — | ✓ | — |
| `phiOffsetOverrides`, `centerBaseline`, `linearDetrend` | XY Physics Function | — | — | ✓ |
| `cachedInputFiles` | Pack Module local | ✓ | ✓ | ✓ |
| `cachedSampleKeys` | Pack Module local | ✓ | — | ✓ |
| `lastRenderedSampleKeys` | AHE render cache | — | ✓ | — |
| `lastLibraryRootPath` (from vault if empty) | Save Module dependency | ✓ | ✓ | ✓ |
| `overlayPackIDs = []`, `overlaySnapshots = [:]` | 3ω overlay state | ✓ | — | — |
| `_titleTokens` (rebuilt from restored hits) | Workflow-local title context | ✓ | — | ✓ |

**After state restore:** each workflow calls a re-render function to reconstruct plot output from the restored ingestion result and tab states:

- 3ω: `_rerenderAllTabsFromRestoredState()` then `_snapshotAndCacheManifestPayloads()` then `refreshRelatedCharts()`
- AHE: `_rerenderActiveTab()` (or `runAnalysis()` for legacy path) then `refreshRelatedCharts()`
- XY: `_rerenderAllTabs()` then `refreshRelatedCharts()`

## What Restore Must Not Persist

These fields are explicitly excluded from pack content and must not be written by restore:

| Field | Reason |
|---|---|
| `persistenceOutcome` | Session-only save state; cleared on `clearPlot()` |
| `saveMessage` | Session-only; set only by `persistToLibrary()` |
| `analysisMessage` | Session-only; set only by analysis or pack load completion |
| `currentRunTrace` | Not packed; restore must not commit trace; remains nil until next `runAnalysis()` |
| `warningLog` | Session-only; cleared on `clearPlot()` |
| `activePackID` | Not in pack content; set by `loadPack()` caller after `restoreFromPack()` returns |
| Active PNG / manifest / layout output | Not serialized; re-derived by re-render call at end of restore |

**`activePackID` ownership rule:** `restoreFromPack()` must not write `activePackID`. The `loadPack()` protocol extension sets `activePackID = id` after `restoreFromPack()` returns. This ordering ensures `activePackID` reflects the correct loaded pack ID even when `restoreFromPack()` triggers `runAnalysis()` (legacy AHE path), which may temporarily clear `activePackID`.

## AHE Legacy Exception

**Normal invariant:** restore must not call `runAnalysis()` or `commitRunTrace()`.

**Exception:** legacy AHE packs have `AHEPackResult.ingestionResult == nil`. These packs predate the ingestion result storage introduced in v5.3.4. When `AHEPackResult.ingestionResult == nil`, AHE's `restoreFromPack()` calls `runAnalysis()` to reconstruct the missing analysis state from the restored `cachedSearchResults` and `selectedSearchResultIDs`.

When the legacy path activates:
- `runAnalysis()` is called, which calls `commitRunTrace()` — `currentRunTrace` is set
- `analysisMessage` is written with the analysis result message
- Canonical search state must already be restored (via the `restoreSearchState` callback) before this call; restore ordering guarantees this

This exception is:
- **Allowed** for legacy AHE compatibility only
- **Not a template** for other workflows or new packs
- **Required to be tested** — the AHE legacy path must be locked by a boundary test

For all new packs, `AHEPackResult.ingestionResult` must be non-nil. The optional type is retained for backward compat decoding only.

## cachedSearchResults

`cachedSearchResults` is a **workflow-local persistent mirror** of canonical search state, not canonical search state itself.

It serves four responsibilities in the current implementation:
1. **Pack save/restore compat field** — CodingKey in all 3 workflow pack configs
2. **Selection denominator** — `isAllSelected`, `selectAll()`, `deselectAll()` use it as the result set
3. **Auto-label/title context** — restores `_titleTokens` from first hit
4. **Nil-snapshot analysis fallback** — legacy `runAnalysis()` path uses it when no snapshot is available

After restore, canonical `WorkbenchFeatureStore.searchResults[wf]` is also populated via the `restoreSearchState` callback. `WorkbenchSelectedHitsSnapshot` uses canonical results first; `cachedSearchResults` activates as `legacyHits` fallback only when canonical is empty.

**Rename decision:** `cachedSearchResults` will not be renamed now. Possible future name: `searchResultMirror`. Any rename must be paired with `CodingKeys` backward compatibility in all three pack config structs (`ThreeOmegaPackConfig`, `AHEPackConfig`, `XYRotationPackConfig`) to decode both old and new key names from persisted pack data. This is a single atomic change, deferred to Pack Module extraction.

## UserDefaults Side Effects

Restore has two intentional UserDefaults write side effects:

1. **`setSearchQueryText(queryText, for: wf)` inside `restoreSearchState()`** — persists the restored search query text to UserDefaults. On next app launch, the workflow's search box shows the restored query. If a pack stores `searchQueryText = ""` (packs saved before the field was populated), the search box will be set to `""` rather than the workflow default prefix.

2. **`persistRTQuery()` called during 3ω restore** — persists the restored `rtQuery` to UserDefaults. This overwrites whatever RT query the user had typed in the current session.

These are known side effects of the restore contract, not hidden bugs. Future implementation may introduce non-persisting restore paths if product behavior requires it.

## activePackID / Trace / Save State

| Concern | Decision |
|---|---|
| `activePackID` | Owned by `loadPack()` caller; set after `restoreFromPack()` returns; never in pack content |
| `currentRunTrace` | Nil after normal restore; set only by `commitRunTrace()` which restore must not call |
| `saveMessage` | Session-only; nil after restore until the next `persistToLibrary()` call |
| `persistenceOutcome` | Session-only; nil after restore |
| `persistToLibrary()` after restore | Supported; restore sets `lastLibraryRootPath` from vault so save-to-library works without a prior search |

## Workflow-Specific Differences

| | 3ω | AHE | XY |
|---|---|---|---|
| Pack workflow ID | `"3w"` | `"ahe"` | `"xy"` |
| RT file in fingerprint | ✓ (`packRTFilePath`) | No | No |
| `ingestionResult` optional in result | No (required) | Yes (legacy compat) | No (required) |
| Overlay state in pack | No (cleared on restore) | n/a | n/a |
| Post-restore render | `_rerenderAllTabsFromRestoredState()` | `_rerenderActiveTab()` | `_rerenderAllTabs()` |
| Sample keys field | `cachedSampleKeys` | `lastRenderedSampleKeys` | `cachedSampleKeys` |

**AHE sample keys asymmetry:** AHE restore writes `lastRenderedSampleKeys = pack.sampleKeys`, while XY and 3ω write `cachedSampleKeys = pack.sampleKeys`. Each workflow's `activeChartSampleKeys` implementation reads from the correct field, so post-restore `persistToLibrary()` works. Do not normalize across workflows without testing all three save-after-restore paths.

**Future workflow requirement:** a new workflow must define its own `PackConfig` and `PackResult` types (conforming to `Codable`, `Hashable`, `Sendable`), implement `AnalysisPackProviding`, and conform `PackConfig` to `SearchQueryTextInjectable` for search query injection. `PackResult` must include `ingestionResult` as a non-optional field.

## Boundary Test Plan (Phase 5F-3)

### High Priority

1. **3ω and XY restore must not commit trace** — after `restoreFromPack`, `currentRunTrace` is nil; no trace is set until a subsequent `runAnalysis()` call.
2. **`isAllSelected` after restore** — `isAllSelected` reflects the restored `cachedSearchResults` count, not empty. Regression guard against restore ordering errors that leave `cachedSearchResults` empty when `selectedSearchResultIDs` is non-empty.
3. **AHE legacy nil-ingestion restore path** — when `AHEPackResult.ingestionResult == nil`, restore calls `runAnalysis()`; verify canonical search state is not corrupted; verify `commitRunTrace()` is called exactly once.

### Medium Priority

4. **`restoreSearchState` callback correctness** — after restore, `WorkbenchFeatureStore.searchResults[wf]` matches `cachedSearchResults`; `searchRunning[wf] == false`; message is "Restored from analysis pack".
5. **`activePackID` set post-restore** — `activePackID` equals the loaded pack ID after `loadPack()` completes.
6. **3ω pre-5.3.6 key migration** — `migrateStateIfNeeded` converts Int-string series keys to `sampleID` keys in restored `tabStates`.
7. **`persistToLibrary()` after restore without prior search** — `lastLibraryRootPath` from vault enables save; no search required.

### Low Priority

8. **AHE `lastRenderedSampleKeys` vs XY/3ω `cachedSampleKeys` post-restore** — `activeChartSampleKeys` returns correct value for each workflow after restore.
9. **Overlay cleared on 3ω restore** — `overlayPackIDs` and `overlaySnapshots` are empty after `restoreFromPack`.
10. **`searchQueryText = ""` in old packs** — when stored `searchQueryText` is empty, `WorkbenchFeatureStore` query text is set to `""`.

## Workbench Write Boundary (Save to Library)

Boundary rule `SP-007`: Workbench writes analysis results into `_spinlab/` under the Library measurement directory. Workbench owns generation; Library owns the storage namespace and cleanup invariants.

Boundary rule `SP-008`: All artifact path construction must go through `LibraryPathResolver`. No hand-built absolute or relative paths.

Library-side view (preview pipeline, stale banner, path resolution ownership): `docs/architecture/library/ARTIFACTS_AND_PREVIEWS.md`.

## Save Entry Point

`SaveActiveChartToLibraryUseCase` is the sole save entry point for Workbench. It orchestrates:

1. `PersistChartArtifactUseCase` — writes chart PNG and `_spinlab/` plot index entry
2. `PersistMeasurementDataUseCase` — writes metric data artifact alongside chart
3. `BackfillMeasurementPlotIndexUseCase` — backfills the plot index for pre-existing measurements that didn't have one

## Written Fields

| Artifact | Path | Owner |
|---|---|---|
| Chart PNG | `_spinlab/<uuid>.png` | Workbench writes |
| Plot index | `_spinlab/plot_index.json` | Workbench writes; Library reads |
| Related charts | `_spinlab/related_charts.json` | Workbench writes; Library reads |
| Measurement data | `_spinlab/<uuid>_data.json` | Workbench writes |

## Stale Detection

A stored artifact is stale when source data changed after last analysis. Detection uses dual-layer sidecar comparison (`ruleSnapshot` vs current rules). When stale, Library displays a banner; recompute is a Workbench operation.

Stale banner and Recompute UI hook: `RecomputeStaleBannerView` / `RecomputePreviewPanel` (Library-side display only). Route user to Workbench for re-analysis.

## State Boundaries

### Pack/Restore Module owns

- `activePackID` — current loaded pack identifier (set by `loadPack()` caller, not by `restoreFromPack()`)
- vault contents for the active measurement
- restore flow orchestration

### Pack/Restore Module does not own

- canonical Search Module state (`queryText`, `searchResults`, `isRunning`, `statusMessage`) — written during restore only through the explicit `restoreSearchState` callback
- `selectedSearchResultIDs` or `cachedSearchResults` — owned by Selection/Search modules; restored as part of the restore contract
- tab override state (`TabRenderState` / `tabStates`) — owned by Preservation Module; restore merges into it through `TabRenderManager.restoreStates()`
- `ingestionResult` or workflow output caches — owned by Analysis Lifecycle Module
- save-to-Library artifacts (`persistenceOutcome`) — owned by Save Module
- trace commit — owned by Analysis Lifecycle Module

### CodingKeys / Backward Compatibility

`cachedSearchResults` is the active `CodingKey` in all three workflow pack configs. Rename to `searchResultMirror` requires CodingKeys backward compatibility in all three structs and is deferred to Pack Module extraction. See "cachedSearchResults" section above.

### Current Implementation Note

Pack/Restore behavior currently lives in each workflow store (`ThreeOmegaWorkspaceStore+Pack.swift`, `AHEWorkspaceStore` + `AHEPackContracts.swift`, `XYRotationWorkspaceStore` + `XYRotationPackContracts.swift`). Phase 5F will extract this into a dedicated Pack/Restore Module.

## Per-Workflow Pack Contracts

### 3-Omega

- `ThreeOmegaPackConfig` — analysis params (geometry, fit ranges, method selectors, RT state), display settings (tab, title, grid, legend), per-tab states, chart style, search state
- `ThreeOmegaPackResult` — must include `ingestionResult`; may include `scalingResult`; restore re-renders without re-ingestion
- Semantic identity: fit ranges are part of scaling chart semantic identity — different fit configurations produce separate chart entries, not overwrites
- Physics reference: [`THREE_OMEGA_PHYSICS.md`](../workflows/three-omega/THREE_OMEGA_PHYSICS.md)

### AMR/PHE

- `AHEPackConfig` — axis overrides, title template, grid, per-tab states, search state
- `AHEPackResult` — `ingestionResult` is optional for backward compat; must be non-nil for new packs
- Tag normalization: AMR → `R_xx`; PHE → `R_xy`
- Legacy exception: nil `ingestionResult` triggers `runAnalysis()` in restore

### XY Rotation

- `XYRotationPackConfig` — phi offsets, baseline/detrend flags, display settings, per-tab states, search state
- `XYRotationPackResult` — must include `ingestionResult`
- Tag normalization: `XY_90shift` → workflow=XY + angle_shift=+90deg
- Semantic identity: default y-axis titles: Rxx tab → `"Rxx (Ω)"`, Rxy tab → `"Rxy (Ω)"`

## Invariants

- Workbench never reads Library preview artifacts directly — it reads raw measurement files and re-ingests.
- All path construction goes through `LibraryPathResolver`; no hand-built paths.
- Save to Library is user-triggered only — no auto-save on analysis completion.
- Pack restore must not call `runAnalysis()` or `commitRunTrace()` — except the AHE legacy exception for nil `ingestionResult`.
- `activePackID` must not be written by `restoreFromPack()` — set by `loadPack()` caller.
- `persistenceOutcome`, `saveMessage`, `currentRunTrace`, and `warningLog` must not appear in any pack format.

## Code Map

- `Sources/SpinLabApp/App/State/AnalysisVault.swift` — stores and retrieves AnalysisPack instances across Workbench sessions
- `Sources/SpinLabApp/Domain/AnalysisPack.swift` — domain model for a completed analysis artifact (pack result + provenance metadata)
- `Sources/SpinLabApp/Workbench/V3/AnalysisPackProviding.swift` — protocol for providing AnalysisPack instances to the Workbench shell
- `Sources/SpinLabApp/Workbench/V3/WorkbenchArtifactIdentity.swift` — uniquely identifies a Workbench artifact by workflow, session, and version
- `Sources/SpinLabApp/Domain/Capabilities/AnalysisVaultReading.swift` — capability protocol for reading packs from AnalysisVault; enables stateless UseCase injection
- `Sources/SpinLabApp/UseCases/RestoreAnalysisPackUseCase.swift` — stateless UseCase: resolves a pack from vault and returns it as a Result
- `Sources/SpinLabApp/UseCases/SaveActiveChartToLibraryUseCase.swift` — sole save entry point; orchestrates chart PNG and metric persistence
- `Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift` — persists a chart artifact to app-support storage and returns its identifier
- `Sources/SpinLabApp/UseCases/PersistMeasurementDataUseCase.swift` — persists processed measurement data as a typed artifact
- `Sources/SpinLabApp/UseCases/BackfillMeasurementPlotIndexUseCase.swift` — backfills missing plot index entries for existing measurement artifacts
- `Sources/SpinLabApp/UseCases/LoadLatestChartArtifactUseCase.swift` — loads the most recently saved chart artifact for a given measurement
- `Sources/SpinLabApp/UseCases/LoadMeasurementDataUseCase.swift` — loads processed measurement data from artifact storage by session key
- `Sources/SpinLabApp/UseCases/LoadWorkbenchResultsUseCase.swift` — loads saved Workbench analysis results for a given session identifier
- `Sources/SpinLabApp/Domain/RecomputePreviewItem.swift` — domain model for a queued chart preview recomputation item
- `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift` — pack config and result contracts for the 3ω workflow
- `Sources/SpinLabApp/Workbench/Domain/ThreeOmegaIngestionDomain.swift` — Tier 2 domain contracts for 3ω: file kind, raw LVM file, V3 method enum, RT result, and ingestion result
- `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` — ingests selected files into 3ω analysis via LVM parsing and condition mapping
- `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` — pack config and result contracts for the AHE workflow
- `Sources/SpinLabApp/Workbench/V3/AHEIngestionContracts.swift` — ingestion input contracts and result types for the AHE workflow
- `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` — ingests selected files into AHE analysis via data parsing and axis detection
- `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` — pack config and result contracts for the XY Rotation workflow
- `Sources/SpinLabApp/Workbench/V3/XYRotationIngestionContracts.swift` — ingestion input contracts and result types for the XY Rotation workflow
- `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` — ingests selected files into XY Rotation analysis via LVM/DAT parsing
