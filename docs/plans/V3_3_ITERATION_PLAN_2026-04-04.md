# SpinLab V3.3 Iteration Plan (2026-04-04)

Status: planning
Type: additive (does not delete or replace existing V3 plan text)

---

## Context

V3.3 goal (from V3_2_ITERATION_ADDENDUM_2026-04-03.md):

> Design workflow-generic layered Workbench UI shell. Prioritize AHE directory UI first, but keep UI abstraction reusable.
> Before implementation, split V3.3 into micro-iterations (V3.3.x) with separate acceptance checkpoints.

This file contains that split. The original V3.3 entry in the addendum is unchanged.

---

## Current State (baseline for V3.3)

After V3.2.8 closure:

- `WorkbenchView` contains an inline computed var `workflowWorkspacePlaceholder` (lines ~55–277) with all AHE-specific UI embedded directly.
- `.workflow` route in `WorkbenchView` dispatches unconditionally to this AHE-specific block regardless of `workflowID`.
- `WorkbenchFeatureStore` holds AHE-specific state (`plotAxisXOverride`, `plotAxisYOverride`, `plotTitleOverride`, `showPlotGrid`, `plotLegendAnchor`, `currentPlotImageData`, `currentCandidateAxisFields`, `currentRunTrace`, `selectedSearchResultIDs`, `artifactLoadMessage`, `plotMessage`) alongside generic search state.
- No protocol or dispatch mechanism exists to route different `workflowID` values to different workspace views.

Target state after V3.3:

- `WorkbenchView` is workflow-agnostic; it dispatches to a per-workflow workspace view via a generic mechanism.
- AHE-specific UI lives in `AHEWorkspaceView`.
- AHE-specific state lives in `AHEWorkspaceStore` (isolated from `WorkbenchFeatureStore`).
- Adding a new workflow (RT/3W) requires no changes to `WorkbenchView` or `WorkbenchFeatureStore`.

---

## V3.3.0 — Shell Region Contract + WorkflowWorkspaceProvider Protocol

Scope:
- Define the named shell regions that every workflow workspace must supply: query bar, action controls, results list, plot canvas, plot controls, trace panel.
- Define `WorkflowWorkspaceProvider` protocol (or equivalent interface) that a workflow workspace must conform to.
- No behavior or layout changes to any existing view.
- This iteration is types/contracts only — it establishes the extensibility seam before any extraction begins.

User-visible acceptance:
- No visible change. Code compiles. Protocol definition exists in codebase.

Definition of Done (DoD):
- `WorkflowWorkspaceProvider` protocol is defined and compiles.
- Shell regions are documented as named constants or associated types in the protocol.
- `WorkbenchView` is not yet changed; AHE placeholder is not yet extracted.
- Protocol is intentionally minimal: only what is needed to drive V3.3.1–V3.3.3 dispatch.

Test naming:
- `Tests/SpinLabAppTests/V330WorkbenchShellContractTests.swift`
- Tests: protocol conformance compileability (mock conformance), region name correctness.

---

## V3.3.1 — Extract AHEWorkspaceView

Scope:
- Move all content from `workflowWorkspacePlaceholder` in `WorkbenchView` into a new standalone `AHEWorkspaceView.swift`.
- `WorkbenchView` `.workflow` route dispatches to `AHEWorkspaceView` directly for the AHE case (hardcoded `workflowID == "A"` branch is acceptable in this iteration — generic dispatch comes in V3.3.2).
- `AHEWorkspaceView` conforms to `WorkflowWorkspaceProvider` (defined in V3.3.0).
- No state changes. `AHEWorkspaceView` reads from `WorkbenchFeatureStore` exactly as the inline placeholder did.
- No logic changes. Behavior must be identical to V3.2.8.

User-visible acceptance:
- AHE workspace looks and functions identically to V3.2.8.
- No regression in search, plot, trace, or axis controls.

Definition of Done (DoD):
- `WorkbenchView` no longer contains `workflowWorkspacePlaceholder` computed var.
- `AHEWorkspaceView.swift` exists and contains all extracted content.
- `WorkbenchView` `.workflow` route compiles to a dispatch to `AHEWorkspaceView`.
- 228/228 existing tests pass (extraction must not break any logic).

Test naming:
- `Tests/SpinLabAppTests/V331AHEWorkspaceViewExtractionTests.swift`
- Tests: AHEWorkspaceView renders without crash, WorkbenchView `.workflow` route reaches AHEWorkspaceView, no AHE-specific symbols remain in `WorkbenchView.swift`.

---

## V3.3.2 — Generic Workspace Dispatch in WorkbenchView

Scope:
- Introduce a `WorkflowWorkspaceRegistry` (or equivalent factory/lookup) that maps `workflowID: String` → a view conforming to `WorkflowWorkspaceProvider`.
- `WorkbenchView` resolves workspace view from registry; no direct `AHEWorkspaceView` import or reference in `WorkbenchView`.
- AHE workspace is registered as the entry for `workflowID == "A"`.
- Unknown `workflowID` renders a generic unsupported-workflow placeholder (not a crash).
- Dispatch mechanism must require no changes to `WorkbenchView` when a new workflow is added in the future.

User-visible acceptance:
- AHE workspace continues to function identically.
- Unknown workflow ID shows a clean unsupported placeholder instead of crashing.

Definition of Done (DoD):
- `WorkbenchView.swift` contains zero AHE-specific symbols (no import of AHE types, no `workflowID == "A"` branch).
- `WorkflowWorkspaceRegistry` routes workflowID → workspace view.
- Adding RT workspace in future requires only: (1) create `RTWorkspaceView`, (2) register it — no other file changes.
- 228/228 existing tests pass.

Test naming:
- `Tests/SpinLabAppTests/V332WorkflowWorkspaceDispatchTests.swift`
- Tests: workflowID "A" resolves to AHEWorkspaceView, unknown ID resolves to fallback, registry is closed to WorkbenchView internals.

---

## V3.3.3 — AHE State Isolation into AHEWorkspaceStore

Scope:
- Extract AHE-specific state from `WorkbenchFeatureStore` into a focused `AHEWorkspaceStore`.
- `AHEWorkspaceStore` owns: `selectedSearchResultIDs`, `plotAxisXOverride`, `plotAxisYOverride`, `plotTitleOverride`, `showPlotGrid`, `plotLegendAnchor`, `currentPlotImageData`, `currentCandidateAxisFields`, `currentRunTrace`, `artifactLoadMessage`, `plotMessage`.
- `WorkbenchFeatureStore` retains: `workflowSearchQueryText`, `workflowSearchResults`, `isWorkflowSearchRunning`, generic search methods, `currentRoute`, `selectedSection`.
- `AHEWorkspaceView` binds directly to `AHEWorkspaceStore`.
- `WorkbenchFeatureStore` holds an `aheWorkspace: AHEWorkspaceStore` reference (or AppState owns it at the same level).
- AHE-specific actions (`renderAHEPlot`, `clearPlot`, `loadPersistedArtifact`) move into `AHEWorkspaceStore` or a dedicated coordinator owned by it.
- `WorkbenchFeatureStore` must retain no AHE-specific methods after this iteration.

User-visible acceptance:
- Full AHE workflow: search → select → plot → trace remains fully functional.
- No visible change. Internal isolation only.

Definition of Done (DoD):
- `WorkbenchFeatureStore.swift` contains no AHE-specific state properties or AHE-specific methods.
- `AHEWorkspaceStore.swift` exists with all extracted state.
- `grep -n "AHE\|plotAxis\|plotTitle\|showPlotGrid\|legendAnchor\|currentPlotImage\|candidateAxis\|currentRunTrace" WorkbenchFeatureStore.swift` returns zero hits on state/method definitions.
- 228/228 existing tests pass + new AHEWorkspaceStore isolation tests.

Test naming:
- `Tests/SpinLabAppTests/V333AHEWorkspaceStoreIsolationTests.swift`
- Tests: AHEWorkspaceStore holds correct state shape, WorkbenchFeatureStore has no AHE-specific symbols, store reset/clear behavior isolated correctly.

---

## V3.3 Stage Gate

V3.3 is complete only when all are true:

- [ ] `WorkbenchView.swift` contains zero workflow-specific (AHE) symbols.
- [ ] `WorkbenchFeatureStore.swift` contains zero AHE-specific state or methods.
- [ ] Adding RT/3W workspace requires: new `<Workflow>WorkspaceView`, new `<Workflow>WorkspaceStore`, one registry registration — no other file changes.
- [ ] All existing 228+ tests pass.
- [ ] App build passes on QA target.
- [ ] App version bumped to v3.3.x at completion.

Stage gate checklist to be tracked in:
- `docs/plans/V3_3_ACCEPTANCE_CHECKLIST.md` (to be created when V3.3.0 implementation starts)

---

## Decision Log

1. Shell region contract is defined as a protocol, not a concrete base class — keeps Swift's value-type idioms and avoids inheritance hierarchy.
2. V3.3.0 is types-only; no view changes. Risk-controlled entry point before extraction begins.
3. V3.3.1 extracts before generic dispatch (V3.3.2) to keep each step independently reviewable and testable.
4. V3.3.3 state isolation is last: UI structure must be stable before state ownership is moved, to avoid tangled refactors.
5. `WorkbenchFeatureStore` retains search state (query/results/running flag) — these are truly workflow-generic and belong at the Workbench level, not per-workflow level.
6. `renderAHEPlot` and `loadPersistedArtifact` move to `AHEWorkspaceStore` in V3.3.3, not earlier. Moving them before the view is stable would create unnecessary churn.
