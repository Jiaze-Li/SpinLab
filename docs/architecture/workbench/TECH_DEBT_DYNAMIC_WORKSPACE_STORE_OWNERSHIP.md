# Tech Debt: Dynamic Workspace Store Ownership

**Status**: Deferred
**Priority**: Medium
**Related work**: Phase 6 workflow identity cleanup

---

## Background

Current Workbench architecture uses a fixed-store ownership model. `WorkbenchFeatureStore` creates all implemented workspace stores during initialization:

- `AHEWorkspaceStore`
- `ThreeOmegaWorkspaceStore`
- `XYRotationWorkspaceStore`
- `IVWorkspaceStore`
- `RSMWorkspaceStore`
- `RTWorkspaceStore`

Because these stores are created before the user selects a left-sidebar workspace entry, each store needs a startup-time context/provenance ID. `WorkspaceWorkflowIDResolver` currently provides those IDs by resolving the corresponding Rule Book workflow definitions.

After Phase 6, this resolver no longer participates in workflow matching, workspace dispatch, renderer identity, payload identity, or persistence fallback. Its remaining role is limited to bootstrap-time ID injection for the fixed six-store model.

---

## Current Model

The current functional model is:

```
Rule Book workflow entry = left-sidebar workspace entry
workflowID = workspace entry context/provenance marker
WorkspaceStore.workflowID = marker used for search state, selection state, plots, packs, restore, and metadata
```

The user selects a workspace entry from the left sidebar. That entry opens the corresponding workspace. The store's `workflowID` marks which entry context produced the analysis, plot, pack, or restored state.

---

## Technical Debt

`WorkspaceWorkflowIDResolver` is still a transitional bootstrap adapter. It exists because workspace stores are pre-created at `WorkbenchFeatureStore` initialization time, before a route-specific workflow ID is selected.

A cleaner long-term architecture would avoid pre-creating all workspace stores. Instead, the selected Rule Book entry ID should flow directly into the workspace view/store when the user opens that entry.

---

## Future Target

Refactor Workbench store ownership so that the selected route entry ID directly creates or binds the corresponding workspace store:

```
User selects Rule Book workspace entry
→ route workflowID = selected entry.id
→ WorkspaceRegistry opens matching WorkspaceView
→ WorkspaceView / WorkbenchFeatureStore creates or retrieves WorkspaceStore for that workflowID
→ WorkspaceStore.workflowID = selected entry.id
```

In this model, `WorkspaceWorkflowIDResolver` can be removed because the route ID itself becomes the store context/provenance ID.

---

## Expected Benefits

- Removes the final fixed-slot resolver layer from Workbench bootstrap.
- Makes the code model match the product model more directly: left-sidebar entry opens a workspace, and that entry ID marks all generated state.
- Reduces the need to pre-create all workspace stores at startup.
- Makes future dynamic workspace entries easier to support.

---

## Cost / Risk

This is not a small cleanup. It requires changing workspace store ownership and lifecycle.

Likely affected areas:

- `WorkbenchFeatureStore`
- `WorkbenchView`
- `WorkflowWorkspaceRegistry`
- all workspace views
- all workspace stores
- search and selection runtime wiring
- pack restore / restore routing
- 3ω secondary RT input handling
- tests that assume `WorkbenchFeatureStore` owns fixed workspace stores

---

## Decision

Do not pursue this during Phase 6. Phase 6 has already removed the main workflow identity risks:

- no `WorkflowKey.rawValue` usage
- workspace dispatch no longer goes through `WorkflowKey(rawValue:)`
- UI search/selection state uses `String` workflowID
- renderer/use-case/payload/store identity flows through injected workflow IDs

Defer dynamic workspace store ownership to a later phase.

---

## Future Phase Proposal

**Phase 7: Dynamic Workspace Store Ownership**

Goal: user-selected Rule Book workspace entry ID directly creates or binds the corresponding workspace store. `WorkbenchFeatureStore` no longer pre-creates all six workspace stores at initialization. `WorkspaceWorkflowIDResolver` is removed.
