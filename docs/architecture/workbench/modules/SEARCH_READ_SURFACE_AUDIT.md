# Workbench Search Read Surface Audit

> Phase 5A-3 audit of the remaining `cachedSearchResults` mirror usage.

## Summary

`cachedSearchResults` is still a workflow-local compatibility mirror.
It is not yet removable in 5.3.8 because the remaining runtime uses fall into three buckets:

- `selection denominator`
- `pack compatibility`
- `nil-snapshot fallback / legacy restore bridge`

The runtime surface is therefore still intentionally duplicated. This audit documents the remaining uses and the replacement path for each class of read.

## Runtime Inventory

### 1. Search completion writes and clear resets

- `WorkbenchFeatureStore` writes search completion results into each workflow store mirror after a search completes.
- `WorkbenchFeatureStore` clears the mirror on workflow search reset.

Why it stays:

- the workflow store still owns local selection, pack, and restore compatibility state
- clearing the mirror remains part of the explicit workflow reset contract

Replacement status:

- no direct snapshot replacement; this is mirror population, not a read path

### 2. Selection denominator uses

Current runtime reads:

- `AHEWorkspaceStore.isAllSelected` and `selectAll`
- `XYRotationWorkspaceStore.isAllSelected` and `selectAll`
- `ThreeOmegaWorkspaceStore.isAllSelected` and `selectAll`

Why it stays:

- these paths define whether all locally visible search hits are selected
- the denominator is the workflow-local result set, not the run-scoped analysis snapshot

Replacement status:

- `WorkbenchSearchSnapshot` is the eventual target if canonical selection/search ownership is moved fully into the shell/store boundary
- `WorkbenchSelectedHitsSnapshot` is not a direct replacement for the denominator

### 3. Pack serialization and restore bridge uses

Current runtime reads and writes:

- `AHEWorkspaceStore` pack config serialization and restore
- `XYRotationWorkspaceStore` pack config serialization and restore
- `ThreeOmegaWorkspaceStore` pack config serialization and restore
- pack config structs in `Sources/SpinLabApp/Workbench/V3/*PackContracts.swift`

Why it stays:

- `cachedSearchResults` is part of the persisted pack schema
- restore must still rebuild local workflow state before canonical search ownership is fully migrated

Replacement status:

- cannot be replaced safely without a schema migration and backward-compatible decoding for existing packs

### 4. Nil-snapshot analysis fallbacks

Current runtime reads:

- `AHEWorkspaceStore.runAnalysis(searchSnapshot:)`
- `AHEWorkspaceStore.runAnalysis(selectedHitsSnapshot:)`
- `XYRotationWorkspaceStore.runAnalysis(searchSnapshot:)`
- `XYRotationWorkspaceStore.runAnalysis(selectedHitsSnapshot:)`
- `ThreeOmegaWorkspaceStore.runAnalysis(searchSnapshot:)`
- `ThreeOmegaWorkspaceStore.runAnalysis(selectedHitsSnapshot:)`

Why it stays:

- these are the legacy/direct-call compatibility paths
- some entry points still rely on the workflow-local mirror when a snapshot is not provided

Replacement status:

- `WorkbenchSearchSnapshot` is the target for explicit search-result read paths
- `WorkbenchSelectedHitsSnapshot` is the target for selected-hit analysis entry paths
- the nil branches should be removed only after all callers are snapshot-driven

### 5. Rerender and title-token rebuild reads

Current runtime reads:

- `AHEWorkspaceStore._rerenderActiveTab`
- `ThreeOmegaWorkspaceStore+Rendering._rerenderActiveTab`
- `XYRotationWorkspaceStore` pack restore title-token setup
- `AHEWorkspaceStore` pack restore title-token setup
- `ThreeOmegaWorkspaceStore` pack restore title-token setup
- `XYRotationWorkspaceStore` pack restore title-token setup

Why it stays:

- these paths rebuild presentation context from the most recent local search mirror
- title text and rerender metadata still need a local hit source when the canonical search surface is not directly threaded through

Replacement status:

- `WorkbenchSearchSnapshot` is the safer explicit source for future canonical read paths
- `WorkbenchSelectedHitsSnapshot` is not sufficient for rerender/title-token rebuilds that need the search result set, not just selected hits

### 6. ThreeOmega manifest restore overload

Current runtime reads:

- `ThreeOmegaWorkspaceStore+ManifestCache._snapshotAndCacheManifestPayloads()`

Why it stays:

- the no-arg restore overload reconstructs cached manifest payloads from the workflow-local mirror after pack restore
- it preserves legacy restore ordering and keeps pack restore behavior stable

Replacement status:

- defer until restore flow ownership is simplified and the restore entry points are fully snapshot-driven

### 7. WorkflowWorkspaceShell legacyHits bridge

Current runtime reads:

- `WorkflowWorkspaceShell` passes `store.cachedSearchResults` as `legacyHits` into `WorkbenchFeatureStore.selectedHitsSnapshot(...)`

Why it stays:

- the shell still needs an explicit bridge from the workflow-local mirror into the run-scoped selected-hit snapshot
- canonical search wins first, but the mirror remains the documented fallback for legacy restore paths

Replacement status:

- `WorkbenchSelectedHitsSnapshot` is already the target output surface
- the mirror input can be removed only after the legacy restore bridge is eliminated or fully moved into canonical search ownership

## Replacement Guidance

- `WorkbenchSearchSnapshot` is the target for explicit search-result read paths.
- `WorkbenchSelectedHitsSnapshot` is the target for selected-hit analysis entry paths.
- Persisted `cachedSearchResults` fields in pack configs cannot be replaced without a schema migration.
- Selection-denominator cleanup requires canonical selection/search ownership cleanup.
- Nil-fallback branches should be removed only after all callers are snapshot-driven.

## Current Decision

No runtime removals in this PR.

Keep all remaining `cachedSearchResults` runtime uses for now.

Defer cleanup to:

- Search runtime ownership cleanup
- PackRestoreCoordinator / schema migration
- removal of nil-snapshot legacy entry points

## Validation

- `./scripts/check_required_actions.sh`
