# Workbench — Measurement Search

> Search layer: sidecar 字段消费、condition projection、workflow ID alias、search 返回 file list 语义。

## Search Semantics

- Workbench search fields must use sidecar condition names, never invent new variable names.
- Search accepts old (`"A"` / `"B"`) and new (`"ahe"` / `"3w"`) workflow IDs as query aliases; persisted data uses new IDs only.
- Search returns file list only — no auto-loading of artifacts, no auto-analysis on search completion.
- Condition projection from Rules lives in `WorkbenchFeatureStore`; the store reads condition definitions and exposes searchable condition fields (`SP-002`).

## Cross-Domain Dependencies

- **Sidecar schema canonical**: `docs/architecture/inbox/OUTPUT_CONTRACTS.md` — Workbench search reads sidecar fields written by Inbox apply; schema changes must maintain the Inbox → Workbench read contract.
- **Library sidecar display**: `docs/architecture/library/SIDECAR_AND_CONDITIONS.md` — Library presents the same sidecar from the Library storage perspective; Workbench reads it from the filesystem during search.
- **Sample key semantics** (`SP-009`, `SP-012`): changes to `SampleKeyNormalizer` or `SampleSemanticDescriptor` affect Inbox drawer matching, Workbench search, and ingestion together.

## Boundary Rules

| Shared point | Classification | Risk |
|---|---|---|
| Condition projection from Rules lives in Workbench store | `coordination_surface` (`SP-002`) | Verify rule reload path when editing condition definitions or Workbench condition options. |
| Workbench search reads Library sidecars and Import semantics | `coordination_surface` (`SP-009`) | Sample key semantics affect search, ingestion, and drawer matching together. |

## Deferred Boundary Debt

### Library Search — Workflow ID Alias Expansion

> Not blocking Inbox → Library archival. Recorded for future Search/Rules integration gate.

Library and Workbench search currently perform workflow ID alias expansion via hardcoded mappings (e.g. `RT`, `MR`, `IV` → canonical workflow IDs). Rules Book-defined workflow IDs can be stored in Library sidecars, but alias expansion is not driven by the Rules Book — it is resolved in the search layer using a fixed alias table.

**What still works:** raw workflow ID search continues to function correctly. Measurements stored under Rules Book-defined IDs (e.g. `RT`) are findable by that exact ID string.

**What is deferred:** alias resolution that would let search understand workflow ID synonyms as declared by the Rules Book rather than as a hardcoded table. This means a user querying by one alias form may not hit results stored under a different alias form unless both happen to be in the hardcoded table.

**Future gate:** a Search/Rules integration gate should replace the hardcoded workflow alias expansion with Rules Book-driven workflow alias metadata. At that point the alias table becomes a runtime projection from the Rules Book, and new workflow IDs defined in the Rules Book automatically participate in search aliasing without a code change.

**Risk surface:** `coordination_surface` between the Search module and Rules Book. Any Rules Book change that adds or renames workflow IDs does not automatically update search alias expansion until this debt is resolved.

## Search Module Contract Notes (Phase 5A)

> The Search module is a default Main Board module (formerly referred to as Search Shell).

Canonical base ownership rules (what state Search owns, what it does not own, forbidden mutations) are in [`MODULE_BOUNDARIES.md` § Search Boundary](../MODULE_BOUNDARIES.md#search-boundary). This section covers search-specific semantics: sidecar field consumption, three-layer representation, workflow ID aliasing, and mirror bridge rules.

- Canonical search lifecycle orchestration lives behind the `WorkbenchFeatureStore` facade in `WorkbenchMainSearchRuntime`:
  - query text
  - search results
  - running/loading state
  - status message
  - all keyed by workflow
- `WorkbenchFeatureStore` remains the public read/write facade for existing views and mirror bridges.
- `WorkbenchFeatureStore` keeps compatibility mirrors only:
  - workflow-local `cachedSearchResults`
  - workflow-local numeric display caches
  - legacy `searchMessages` bridge for existing tests/callers
- `WorkbenchMainSearchRuntime` is the canonical owner of search state; the store forwards to it and no longer owns the Main Search orchestration loop.
- Search state is preserved per workflow on route switch by default.
- Canonical clear path is `clearSearch`; workflow-local `clearResults` is not canonical search reset.
- Search does not own selection IDs, workflow scientific analysis, plot payload/layout/image output, title/legend/axis overrides, or rerender preservation state.
- Analysis and rerender paths must not mutate canonical search query/results/running/message.

Current temporary bridge and risk:

- canonical `searchResults` is mirrored into workflow-local `cachedSearchResults`
- `cachedSearchResults` is a workflow-local mirror, not canonical search state
- this is a known duplicate-state surface and can drift if updates diverge
- migration direction is a single shell-facing adapter/read surface that replaces mirrored result caches

### Three-Layer Search/Selection Representation (Phase 5C-3)

Search and selection state are represented in three distinct layers:

| Layer | Type | Lifetime | Purpose |
|---|---|---|---|
| **Canonical search** | `WorkbenchSearchSnapshot` | Ephemeral; per run | Query text, results, running state, status message — owned by Search Module / `WorkbenchFeatureStore`. |
| **Run-scoped selected hits** | `WorkbenchSelectedHitsSnapshot` | Ephemeral; per analysis entry | Selected hits for a single analysis run — built from canonical search results plus selected IDs, with explicit `legacyHits` fallback. |
| **Persistent mirror** | `cachedSearchResults` | Persistent; per workflow store | Pack save/restore, selection denominator, auto-label/title context, nil-snapshot legacy fallback. |

`WorkbenchSearchSnapshot` is the canonical run-scoped read surface for query text, results, running state, and status message.

`cachedSearchResults` remains for workflow-local responsibilities only:

- selection UI denominator/source (`isAllSelected`, `selectAll`, `deselectAll`)
- pack save/restore compatibility field
- local auto-label/title context
- nil-snapshot `runAnalysis` legacy/restore fallback

No current path incorrectly reads `cachedSearchResults` instead of a snapshot (verified Phase 5C-3 audit).

Forbidden usage:

- New analysis paths must not read `cachedSearchResults` as primary analysis input.
- New shell UI paths must not treat `cachedSearchResults` as canonical search results.
- Plot controls/rerender/preservation paths must not mutate canonical search or `cachedSearchResults`.

Bridge rule:

- `legacyHits` passed into `WorkbenchSelectedHitsSnapshot` factory is the explicit bridge from persistent mirror to ephemeral selected snapshot.
- The bridge selects canonical first; `legacyHits` activates only when canonical search results are empty (e.g., immediately after pack restore).
- This bridge path must remain explicit and tested.

Rename decision:

- `cachedSearchResults` will not be renamed now.
- Possible future name: `searchResultMirror`.
- Rename deferred to Save / Pack Module work: pack `CodingKey` backward compatibility must be handled together with the rename.

Current shell call note:

- AHE / XY / 3ω analysis consumes `WorkbenchSelectedHitsSnapshot` when called from `WorkflowWorkspaceShell` (Phase 5C complete).
- `WorkbenchSelectedHitsSnapshot` is built from `WorkbenchSearchSnapshot` (canonical) with `cachedSearchResults` as `legacyHits` fallback.
- Nil-snapshot `runAnalysis()` remains legacy/restore compatibility only.

Phase 5A regression plan:

- title edit does not mutate search state
- legend edit does not mutate search state
- rerender does not mutate search state
- selection toggle does not mutate query text
- workflow switch preserves per-workflow search state by default
- run/restore/clear preserve mirror consistency while bridge exists

### Selection Module test additions (Phase 5C — complete)

- selection toggle does not mutate canonical search query/results/running/message ✓
- selectAll uses declared source-of-truth denominator ✓
- deselectAll clears selected IDs only ✓
- clearResults behavior remains explicit (legacy mixed clear vs canonical clearSelection/clearSearch split) ✓
- analysis consumes selected-hit snapshot ✓
- pack restore restores selected IDs without corrupting canonical search state ✓

Future test (Save / Pack Module):

- pack-restore isAllSelected reflects restored `cachedSearchResults`, not empty (regression guard against restoreFromPack ordering errors)

## Code Map

- `Sources/SpinLabApp/Domain/Capabilities/LibraryAccessCapability.swift` — capability protocol abstracting LibraryStore index reads for workbench search and workspace stores <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift` — coordinates canonical search execution, restore, clear, and mirror sync behind the WorkbenchFeatureStore facade
- `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift` — executes measurement search queries against Library using sidecar conditions
- `Sources/SpinLabApp/Domain/WorkflowSearchModels.swift` — domain models for search query parameters and search result types
- `Sources/SpinLabApp/Features/Workbench/WorkflowHitRow.swift` — renders a single measurement search result row in the hit list
