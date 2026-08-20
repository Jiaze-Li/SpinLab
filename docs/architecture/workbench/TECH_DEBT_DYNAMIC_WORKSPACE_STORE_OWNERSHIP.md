# Architecture Note: Dynamic Workspace Store Ownership

**Status**: Architecture Note / Informational — debt lifecycle state (if any) lives exclusively in `docs/TASK_BOARD.md`, not in this document.
**Related work**: Phase 6 workflow identity cleanup

Current invariant, audited against HEAD 2026-08-19: the fixed six-store model matches the product schema, there is no correctness bug, and no current product capability is blocked. `WorkspaceWorkflowIDResolver` is bootstrap-only. This document is retained as a design reference for a future redesign that has no current payoff.

**Revisit trigger:**
- the product supports multiple Rule Book entries per workspace implementation
- workflowID-keyed workspace instances become a real requirement
- the current fixed-store model starts causing correctness or maintenance pain

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

## Design Observation

`WorkspaceWorkflowIDResolver` is a transitional bootstrap adapter. It exists because workspace stores are pre-created at `WorkbenchFeatureStore` initialization time, before a route-specific workflow ID is selected.

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

## Future Design Constraints (not current open debt)

This is not a small cleanup — it would require changing workspace store lifecycle end to end. These are the areas a future redesign would need to reconsider; they are recorded here as design constraints for if/when the revisit trigger above fires, not as scheduled work:

- store creation / retention / reuse / disposal lifecycle
- `restoreInteraction` dynamic-store creation
- task cancellation on store disposal
- 3ω ↔ RT pairing when multiple RT-like workflow entries exist
- `WorkbenchFeatureStore`, `WorkbenchView`, `WorkflowWorkspaceRegistry`
- all workspace views and workspace stores
- search and selection runtime wiring
- tests that assume `WorkbenchFeatureStore` owns fixed workspace stores

---

## History

Phase 6 removed the main workflow identity risks (no `WorkflowKey.rawValue` usage; workspace dispatch no longer goes through `WorkflowKey(rawValue:)`; UI search/selection state uses `String` workflowID; renderer/use-case/payload/store identity flows through injected workflow IDs). A "Phase 7: Dynamic Workspace Store Ownership" was proposed as follow-on work but was never scheduled or committed — it is not active or deferred work, and this document does not track it as such. Debt lifecycle state, if this is ever tracked as debt, is recorded in `docs/TASK_BOARD.md`.
