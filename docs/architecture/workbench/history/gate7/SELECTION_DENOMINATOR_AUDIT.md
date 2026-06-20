# Workbench Selection Denominator Audit

> 5.3.8 docs-only audit of the remaining selection denominator choice.

## Summary

- `AHEWorkspaceStore`, `XYRotationWorkspaceStore`, and `ThreeOmegaWorkspaceStore` still use workflow-local `cachedSearchResults` as the denominator for `isAllSelected` and `selectAll`.
- That is intentional in 5.3.8.
- Runtime replacement is deferred.

## Current Ownership Split

- `selectedSearchResultIDs` is workflow-local store state.
- Canonical search results, query text, running state, and message live in `WorkbenchFeatureStore` and are exposed through `WorkbenchSearchSnapshot`.
- The select-all denominator is currently workflow-local `cachedSearchResults`.

## Runtime Inventory

- `AHEWorkspaceStore.isAllSelected` / `selectAll`
- `XYRotationWorkspaceStore.isAllSelected` / `selectAll`
- `ThreeOmegaWorkspaceStore.isAllSelected` / `selectAll`
- `WorkflowWorkspaceShell` only reads `store.isAllSelected` for the button label and calls `store.selectAll()` / `store.deselectAll()`. It does not own the denominator yet.

## Existing Test Coverage

The current contract is already covered by:

- `Tests/SpinLabAppTests/V537WorkbenchSelectionShellTests.swift`
- `Tests/SpinLabAppTests/V537WorkbenchSearchMirrorTests.swift`
- `Tests/SpinLabAppTests/V537PackRestoreModuleBoundaryTests.swift`
- `Tests/SpinLabAppTests/V538SelectedHitsBridgeAuditTests.swift`

No new regression test is needed in this PR because the denominator contract is already locked by the existing suite.

## Decision

- Do not replace the denominator with `WorkbenchSearchSnapshot` yet.
- Defer the replacement until selection ownership moves to the shell/store boundary or a dedicated selection module.
- Replacement must move selected IDs and denominator ownership together.

## Relationship To Prior 5.3.8 PRs

- PR #91 documented the `cachedSearchResults` mirror categories.
- PR #92 locked the selected-hits shell bridge.
- This doc records the denominator-specific decision that remains after those audits.

## References

- `docs/architecture/workbench/modules/MEASUREMENT_SEARCH.md`
- `docs/architecture/workbench/history/gate7/SEARCH_READ_SURFACE_AUDIT.md`
- `docs/architecture/workbench/MODULE_BOUNDARIES.md`
