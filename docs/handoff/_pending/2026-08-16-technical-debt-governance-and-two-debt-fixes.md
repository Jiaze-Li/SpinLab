# Handoff — Technical-debt governance + two debt fixes

Date: 2026-08-16
Owner: Claude
Scope: governance normalization, then current-HEAD verification and resolution of the two remaining concrete debt records discussed below.

## Goal

Complete one closed-loop technical-debt cleanup:

1. Make technical-debt lifecycle tracking single-source.
2. Re-verify and resolve the curve-reorder duplication debt against current `HEAD`.
3. Split Library browser-preview selection from drawer selection so the two UI concepts no longer share one mutable selection triple.
4. Normalize stale unit-debt documentation/board state to the current Tesla invariant without changing production unit conversion code.

This handoff is an execution instruction, **not** a second technical-debt tracker. Lifecycle status/priority belongs only in `SpinLab-shared/TASK_BOARD.md` (repo entry point: `docs/TASK_BOARD.md`).

## Before editing

1. Read root `CLAUDE.md`, `AGENTS.md`, and `docs/architecture/TESTING_STRATEGY.md`.
2. If the user's global Claude workflow exists at `~/.claude/docs/workflow.md`, add the same technical-debt governance invariant there:
   - `SpinLab-shared/TASK_BOARD.md` is the only lifecycle source of truth for SpinLab technical debt.
   - architecture/audit/roadmap/ADR/handoff docs may describe facts, invariants, rationale, history, and debt IDs, but must not maintain independent lifecycle state.
   - verify every recorded debt against current `HEAD` before implementing it.
   - accepted/deferred debt must have an explicit reconsideration trigger.
   - when code resolves/supersedes/invalidates a debt, update the board and factually stale docs in the same change.
   Do not create another tracker in the global workflow.
3. Open the canonical `SpinLab-shared/TASK_BOARD.md` locally. Use its existing IDs/names; do not invent duplicate entries if the debts are already recorded.
4. Work from current `HEAD`, not from descriptions in this handoff when they conflict with code.

## Task A — normalize debt governance and stale unit documentation

### Canonical tracker rule

The repository-local rule has been added to `CLAUDE.md` / `AGENTS.md`. Preserve it. The shared task board is the only place that owns debt lifecycle state.

Audit technical-debt-related architecture/audit/roadmap prose touched by these three records. Convert it to current-state documentation or references to the canonical debt ID; remove independent Open/Deferred/Resolved/priority/future-migration state.

### Magnetic-field unit record: documentation closeout only

Re-verify current `HEAD`, but the expected invariant from the latest audit is:

- raw instrument/LVM input may be Oe;
- the 3ω ingestion boundary converts Oe -> Tesla;
- runtime/internal `H`, fitting, and derived `Hc` are Tesla;
- new persistence/pack storage is Tesla;
- legacy Oe packs normalize only on restore/load.

Relevant starting points include:

- `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift`
- 3ω pack/restore code under `Sources/SpinLabApp/Features/Workbench/`
- `docs/architecture/workbench/MAGNETIC_FIELD_STORAGE_AUDIT.md`

If the invariant still holds, **do not modify production unit-conversion code**. Update the canonical task-board record to reflect that the old runtime-Gauss/Oe debt is no longer outstanding, and rewrite any stale audit prose that still proposes a future migration as a statement of the current boundary/canonical-unit invariant. Avoid any second Oe->Tesla conversion; that would introduce a 10^4 error.

## Task B — curve reorder duplication: prove before refactoring

The historical debt says 3ω and XY Rotation duplicate curve drag/reorder behavior. Do not assume that statement is still true.

Current `HEAD` already shows both workspaces routing plot controls through shared infrastructure. Starting points:

- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`
- `WorkbenchStandardPlotControls`
- `WorkbenchCartesianXYPlottingStore`
- `TabRenderManager` / per-tab `seriesOrder` ownership

Trace the full path from the draggable series row/drop handler through `onSeriesOrderCommit` to per-tab state mutation.

### Decision gate

- If the drag/drop reorder algorithm or behavioral state machine is still duplicated in two workspace-specific implementations, extract **only the genuinely shared behavior** into the narrowest existing Workbench layer.
- If current shared controls/protocol/default implementation already own the behavior and the old two-copy implementation no longer exists, do **not** create a new abstraction. Treat the debt record as stale and update the canonical board accordingly.

### If extraction is actually needed

Preserve these behaviors exactly:

- stable series identity;
- source/target semantics;
- insertion-index behavior when moving forward/backward;
- self-drop/no-op behavior;
- hidden/renamed series identity mapping;
- per-tab `seriesOrder` ownership;
- rerender/flush semantics already documented in the two workspace views.

Do not introduce a generic drag/drop framework. Prefer a small pure reorder helper or an existing shared Workbench control/store extension. Add focused unit tests for the reorder algorithm where it can be made pure.

## Task C — Library browser vs drawer selection ownership

This debt is about state ownership, not visual redesign.

### Current problem to verify

Browser Preview and the drawer are distinct UI concepts, but current code has historically shared:

- `librarySelectedPrefix`
- `librarySelectedBatchId`
- `librarySelectedSampleId`
- plus `libraryActiveSelectionSource` as an owner/source marker.

`LibrarySelectionSync` already separates browser reconciliation from drawer synchronization (`reconcileBrowser` vs `synchronizeDrawer`), so the state model should match that separation.

Relevant starting points include:

- `Sources/SpinLabApp/Features/Library/LibrarySelectionSync.swift`
- `Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift`
- `Sources/SpinLabApp/Features/Library/LibraryDetailView.swift`
- the type that currently owns `LibraryWorkspaceState`
- the feature/app store containing the `librarySelected*` projections
- Library interaction snapshot capture/restore paths

### Required invariant

Browser and drawer each own an independent **full selection triple**:

```text
browserSelection
  - prefix
  - batchId
  - sampleId

drawerSelection
  - prefix
  - batchId
  - sampleId
```

Splitting only `sampleId` is insufficient because preview synchronization/reconciliation can rewrite prefix and batch as well.

The `.browser` / `.drawer` concept may remain only as explicit **Detail-pane presentation/focus state** — i.e. which independent selection should the right-hand Detail pane display. It must not be an ownership marker for a single shared mutable selection.

### Minimal-risk migration

Prefer preserving existing `librarySelectedPrefix` / `librarySelectedBatchId` / `librarySelectedSampleId` semantics as **drawer selection** if downstream Workbench/edit projections already depend on them. Add a separate browser triple in the correct cross-pane UI owner rather than forcing unrelated downstream migrations.

Choose the exact owner after checking current lifetimes. `LibraryWorkspaceState` is a likely candidate if it is the current cross-pane UI state owner; do not move domain state there just for symmetry.

### Behavior requirements

- `syncPreviewSelection()` changes browser selection only.
- Browser reconciliation/registry refresh changes browser selection only.
- Drawer sample selection/synchronization changes drawer selection only.
- Restoring browser interaction state must not overwrite the current drawer selection.
- Deleting or invalidating a browser-selected sample only reconciles the browser side unless the same entity is independently selected in the drawer and the domain mutation itself requires drawer reconciliation.
- Drawer dirty-edit guards/prompts remain drawer-only; browser navigation must not trigger them.
- Detail-pane displayed sample follows explicit detail focus/source.
- Detail editing/mutations remain drawer-only even when the Detail pane can display browser-preview data.
- No extra browser refresh should occur merely because the drawer selection changed, and vice versa.

### Required tests

Add/adjust focused tests that prove at least:

1. selecting a browser preview does not mutate the drawer selection triple;
2. selecting a drawer sample does not mutate the browser selection triple;
3. browser reconciliation/refresh does not mutate drawer selection;
4. drawer synchronization does not mutate browser selection;
5. Detail focus/source resolves the displayed sample from the correct independent selection;
6. browser interaction snapshot restore does not clobber current drawer selection (including legacy snapshot compatibility if applicable).

Use existing Library test harnesses and test naming conventions rather than creating a parallel harness.

## Canonical task-board closeout

After implementation and verification, update `SpinLab-shared/TASK_BOARD.md` once, using the existing debt entries:

- magnetic-field internal-unit record: close/correct it if current `HEAD` confirms the Tesla invariant above;
- curve reorder record: close it only if current code already has one owner or after the real duplication is removed;
- Library selection-ownership record: close it only after independent browser/drawer triples and focused regression tests are in place.

Do not copy these lifecycle states into architecture docs or this handoff.

## Validation / closeout

Run targeted tests first, then follow repository closeout rules exactly.

Mandatory:

1. targeted tests for any shared reorder helper touched;
2. targeted Library selection/snapshot tests;
3. broader affected Workbench/Library tests as warranted;
4. `swift test` as closeout if required by the testing strategy / change scope;
5. `./scripts/check_required_actions.sh`;
6. if it reports `Required: ./scripts/build_desktop_app.sh debug`, run that build.

Final report must include:

- whether the reorder debt was still real on starting `HEAD`, with the exact old owners if yes or exact shared owner if already stale;
- Library state owner before/after and the resulting invariants;
- exact canonical task-board mutations;
- stale architecture/audit prose updated;
- tests run and results;
- exact `check_required_actions.sh` output and desktop-build/version fields required by root agent instructions;
- any residual risk or intentionally deferred follow-up.

When complete, archive/move this handoff out of `_pending` using the repository's existing handoff convention. Do not leave a completed pending handoff as another pseudo-tracker.
