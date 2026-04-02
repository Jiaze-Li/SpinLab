# SpinLab V2 Execution Plan

This document is the implementation handoff plan for a new execution thread.

Rule governance: the routing rules framework must stay integrated in this execution plan and be updated in-place here.

## Engineering principles (must follow in all V2.x)
- No silent fallback logic. If sample routing is not uniquely resolved, move the item into review-required state.
- No cross-layer coupling. Keep `Rule / Parse / Route / Apply / Audit` responsibilities isolated.
- No direct filesystem writes in UI layer.
- All write paths must be auditable; multi-target file apply must be rollback-safe.
- Keep extension seams explicit (future tabs, future workflows, future rule updates).

## Routing framework and rules (integrated)

### Goal
- Import many measurement files from Inbox (`.dat`, `.lvm`).
- Parse filename and folder context safely.
- Route each file to the correct Library sample drawer(s).
- Keep App drawer state and `Library Root` physical files consistent.

### Layered architecture
1. Rule Layer
- Owns JSON configuration only.
- Defines:
  - allowed import extensions
  - ignored extensions
  - tokenization
  - channel aliases
  - sample key regex patterns
  - workflow and measurement tag aliases
  - condition patterns (temperature/current/field)
  - substrate aliases

2. Parse Layer
- Input: `file name + parent folder + grandparent folder`.
- Output: normalized parse result (`ParsedTags`) including:
  - `defaultSampleKey`
  - `channelBindings[]` (`channel`, `sampleKey?`, `tags[]`)
  - `workflow`
  - `measurementTags[]`
  - `conditions` (`temperature`, `current`, `field`)
  - `substrateTags[]`
  - `warnings[]`
- Parse layer does not touch file system routing decisions.

3. Route Layer
- Input: `ParsedTags`.
- Output: `RoutePlan`:
  - `targets[]`: each target contains `sampleKey` and `channels[]`
  - `unresolvedChannels[]`
  - `conflicts[]`
- Unified rule:
  - for each channel: `sampleKey = channel.sampleKey ?? defaultSampleKey ?? folderDerivedSampleKey`
  - if still missing, channel is unresolved
  - group by `sampleKey` to produce route targets
- This naturally handles:
  - one file routed to one sample
  - one file routed to multiple samples

4. Apply Layer
- Executes `RoutePlan` only.
- For each route target:
  - writes/copies measurement file into that sample drawer under `Library Root`
  - writes route metadata (source file, selected channels, parsed tags)
- Must support duplicate guard and atomic rollback contract.

### Routing policy defaults
- Included in import/classification: `.dat`, `.lvm`
- Ignored in classification/routing: `.gph`
- Primary sample key patterns:
  - `PN\d+`
  - `PT\d+`
  - `S\d+`
- Channel aliases:
  - `ch1/c1`
  - `ch2/c2`
  - `ch3/c3`
- Safety contract:
  - never silently route unresolved files
  - conflicting mapping must become warning/error and require manual review

### Reference JSON shape
```json
{
  "version": 2,
  "extensions": {
    "allow": ["dat", "lvm"],
    "ignore": ["gph"]
  },
  "tokenization": {
    "separators": "_- ()",
    "sources": ["file", "parent", "grandparent"]
  },
  "aliases": {
    "workflow": {
      "XY_90shift": "XY",
      "MR": "MR",
      "RT": "RT",
      "AHE": "AHE"
    },
    "channels": {
      "ch1": "ch1",
      "c1": "ch1",
      "ch2": "ch2",
      "c2": "ch2",
      "ch3": "ch3",
      "c3": "ch3"
    },
    "substrate": {
      "origin": "o",
      "original": "o",
      "bake": "baked"
    }
  },
  "patterns": {
    "sampleKey": ["^(PN|PT)\\d+$", "^S\\d+$"],
    "conditions": {
      "temperature": "^\\d+K$",
      "current": "^\\d+(?:\\.\\d+)?mA$",
      "field": "^-?\\d+T$"
    }
  }
}
```

## V2.1
Status: `done` (accepted on 2026-03-23)

**Goal (one line)**
Build the core data pipeline `Parse -> Editable Draft -> Route Plan` without executing library writes.

**Detailed requirements**
1. Import support: include `.dat` and `.lvm`; ignore `.gph` from classification/routing.
2. Parse sources: file name, parent folder, grandparent folder.
3. Parse output must include:
- workflow
- default sample key
- channel bindings (`channel -> sample + tags`)
- conditions (`temperature/current/field`)
- substrate/device-level hints
- warnings/conflicts
4. Editable draft must support file-level and channel-level edits.
5. Route recompute trigger:
- editing draft does not immediately mutate route plan
- route plan recomputes automatically on `Save` using the current draft values
- optional manual `Recompute Route` remains available for batch/recovery flows
6. Unified routing rule:
- `channelSampleKey ?? defaultSampleKey ?? folderDerivedSampleKey`
7. Non-unique/conflicting routes must become `review-required`, not `library-matched`.

**Test scenarios & acceptance criteria**
1. `XY_90shift_80K_PN38_HF_STO111_wafer_ch2_AMR_ch3_PHE_8T_1mA`
- Acceptance: parse captures workflow/conditions/sample/channel tags correctly.
2. `RT_1mA_ch1_PN36_ch2_PN36_HF_STO111_ch3_PN37_wafer`
- Acceptance: route plan contains both `PN36` and `PN37` targets.
3. Filename-missing sample with unique parent-derived sample
- Acceptance: route becomes library-matched.
4. Non-unique parent-derived sample
- Acceptance: route becomes review-required.
5. `.gph` inputs
- Acceptance: not enqueued for route/apply.

**Code structure design**
1. Add/clarify modules:
- `RuleLayer` (JSON rules only)
- `ParseLayer` (parsing only)
- `RouteLayer` (route planning only)
- `DraftState` (editable draft state + dirty tracking)
2. Keep `SpinLabAppState` orchestration-only for these modules.
3. Introduce explicit route status enum (`libraryMatched`, `reviewRequired`).

**V2.1 staged micro versions (execution order)**
1. `V2.1.0` Parse baseline
- Import support only `.dat`/`.lvm`; ignore `.gph`
- Parse sources fixed to file/parent/grandparent
- Produce normalized parse payload: workflow, default sample key, channel bindings, conditions, substrate hints, warnings/conflicts
2. `V2.1.1` Route planner
- Add `RoutePlan`, `RouteTarget`, and `RouteStatus` (`libraryMatched`, `reviewRequired`)
- Implement unified key resolution: `channelSampleKey ?? defaultSampleKey ?? folderDerivedSampleKey`
- Support single-target and multi-target fan-out per file
- Mark unresolved/non-unique/conflicting outcomes as `reviewRequired`
3. `V2.1.2` Editable draft + save-driven recompute
- Status: `done` (accepted on 2026-03-23)
- Add file-level and channel-level editable draft model
- Keep route stable while editing; commit edits on `Save`
- On `Save`, auto-recompute route from saved draft (example: `PN41 -> PN40` updates destination accordingly)
- If saved edits introduce ambiguity/conflict, status automatically becomes `reviewRequired`
4. `V2.1.3` Inbox closed loop + acceptance
- Status: `done` (accepted on 2026-03-23)
- Complete inbox loop: parse baseline -> edit draft -> save -> route update/status refresh
- Keep `Recompute Route` entry point for batch/recovery
- Execute all V2.1 acceptance scenarios (including `.gph` filtering and conflict paths)
- Keep library writes out of scope in V2.1 (no apply/archive execution yet)

## V2.2
**Goal (one line)**
Refactor Inbox UI into the same 3-column interaction model as Library and complete save-driven route recompute workflow.

**Detailed requirements**
1. Keep app-level columns as:
- left: navigation
- middle: operation blocks
- right: reserved extension area (blank in current iteration)
2. Inbox middle operation blocks order:
- Registry
- File
- Selection Workbench (inside `File`)
3. Toolbar action relocation:
- keep and place in operation blocks: `Load Registry`, `Import Files`, `Clear Imports`, `Recompute Route`
- remove from Inbox scope: `Create Project`
4. Right panel remains blank placeholder in V2.2.x; keep extension seam for future tabs/content.
5. `Save Draft` remains the explicit routing refresh gate; no mandatory two-step `Confirm & Recompute Route` action.

**Test scenarios & acceptance criteria**
1. Edit draft without confirm
- Acceptance: route plan unchanged.
2. Save draft and recompute
- Acceptance: route plan updates from edited values.
3. Switch pending items
- Acceptance: selection workbench state is correctly isolated per pending item.
4. `Clear Imports`
- Acceptance: clears pending queue only; no changes to already archived library drawers.

**Code structure design**
1. Split UI composition:
- `InboxOperationPanel`
- `InboxSelectionWorkbenchPanel`
2. Add dedicated view models for operation blocks and selection workbench blocks.
3. UI dispatches actions via explicit intent handlers; no filesystem logic in views.

**V2.2 staged micro versions (execution order)**
1. `V2.2.0` Inbox layout refactor + operation blocks
- Status: `acceptance-ready` (closing preparation)
- Keep global app shell unchanged:
  - left: global navigation (Inbox / Workbench / Library)
  - middle: Inbox operation blocks
  - right: reserved extension area (currently blank placeholder)
- Inbox middle operation blocks (current):
  - Registry
  - File
  - Selection Workbench (inside `File`)
- Operation blocks are collapsible and persisted via interaction memory.
- Keep V2.1 routing semantics:
  - `Save Draft` acts as the explicit refresh gate for mapping/routing display.
  - no mandatory two-step `Confirm & Recompute Route` gate in V2.2.0.
- Relocate Inbox primary actions into operation blocks:
  - `Load Registry`, `Import Files`, `Clear Imports`, `Recompute Route`
- Remove `Create Project` from Inbox primary workflow surface.
- Remove standalone `Routing Review` and standalone `Apply` side blocks; keep single `Apply` placeholder button in Selection Workbench.
- Use drawer-oriented mapping UI:
  - editable sample/channel sample on left
  - mapped drawer on right
  - mapping shown as saved-result view (`Save Draft`/`Revert Draft` refreshes mapping; no per-keystroke remap)
- Drawer display rule:
  - show full matched drawer name only
  - show `?` when unresolved or no existing drawer match
- Drawer match rule:
  - token-set coverage match (`PN39`, `HF`, `STO`, `111` style token sets)
  - unique candidate required for successful match
  - ambiguous or no match -> `?`
- Inbox registry lookup isolation rule:
  - system sheets (`__*`) are excluded from sample lookup indexing
  - only sheets with recognized sample column are indexed
  - lookup path is `sampleID -> indexed rows` (prefix map is display-only metadata)

Acceptance:
- New 3-column Inbox interaction model is functional.
- Operation blocks can collapse/expand and restore after relaunch.
- Save draft/revert remains the explicit mapping refresh gate.
- `Clear Imports` only clears pending queue and unarchived temp scope.
- No library apply/archive write behavior added in this version.

Current checkpoint marker (not final):
- V2.2.0 is in acceptance and document reconciliation stage.
- If acceptance passes, close V2.2.0 and move to V2.2.1.
- Testing framework migration note (2026-03-25):
  - Current development baseline stays on `swift-tools-version: 5.9` + external `swift-testing` dependency, so feature delivery remains stable and test runs stay green.
  - The `@Suite/@Test` deprecation warning is acknowledged and accepted for now (non-blocking).
  - Migration to Swift 6 built-in `Testing` should be executed as a dedicated follow-up track after core app workflow milestones are stable.
  - Do not mix this migration with feature iterations; treat it as a separate technical migration round with its own acceptance gate.
- Queue status contract for current iteration:
  - Root definition: `library-matched` / `review-required` is decided by whether parsed routing can map to required existing Library drawer target(s).
  - File-level delivery: file-level target drawer exists -> `library-matched`; otherwise `review-required`.
  - Channel-level delivery: every reported channel must map to its own drawer target; any channel that cannot be uniquely mapped -> `review-required`.
  - Route unresolved metadata alone does not force `review-required` when final drawer mapping is still unique and valid.
  - Completion boundary: file-level sample info may complete missing channel sample info; channel-to-channel cross-completion is not allowed.
- V2.2.0 development process record:
  - Step A: complete center-column operation layout and button relocation.
  - Step B: stabilize save-gated routing refresh and draft isolation by pending item.
  - Step C: isolate Inbox registry lookup rules into dedicated interfaces and remove sheet-level misrouting risk.

2. `V2.2.1` Stabilization + routing normalization window
- Status: `in-progress` (architecture consolidation window; user-facing feature scope frozen)
- Goal:
  - keep current user behavior unchanged while removing structural debt in routing/matching.
  - separate rule configuration from execution logic.
  - unify Inbox and Library semantic parsing so future features do not add duplicate logic.

Guardrails (must hold in V2.2.1):
- no user-visible behavior change in Inbox/Library workflows.
- no UI contract change: Inspector stays reserved; Apply stays placeholder.
- no silent fallback: unresolved/ambiguous routing still becomes `review-required`.

Workstreams:
1. Behavior baseline lock (before refactor switch)
- build a regression matrix from current real cases:
  - file-level matched
  - channel-level matched
  - unresolved
  - ambiguous
  - conflict warning paths
- freeze expected outputs:
  - matched drawer display
  - queue status (`library-matched` / `review-required`)
  - warnings and unresolved scopes

2. Shared semantic core (Inbox + Library)
- introduce one canonical semantic object (example shape: `batch/treatment/material/orientation/canonicalKey/tokens`).
- make both parse entries emit this shared object:
  - filename/folder parse (Inbox)
  - registry row parse (Library)
- remove duplicate substrate/material/treatment/orientation interpretation logic from split paths.

3. Unified matching engine
- centralize drawer matching into one engine with ordered strategy:
  - stage A: exact canonical key match
  - stage B: unique token-subset fallback
- keep current matching semantics externally equivalent; only internal structure changes.
- add cached indices for match speed:
  - `canonicalKey -> drawer`
  - token-based candidate index

4. Responsibility cleanup in route verdict chain
- `RoutePlanner` produces candidate route data only.
- `SnapshotEvaluator` becomes the single final verdict authority.
- ensure one source of truth for status to simplify debugging and future extension.

5. Rule layer vs logic layer isolation
- consolidate rule-owned data (aliases, tokenization options, substrate normalization hints) into rule-config-facing boundary.
- execution layers consume rule interfaces only; avoid embedding rule literals across app state/services.

6. Module boundary hardening
- isolate by capability (Parse / Route / Match / Evaluate / Store).
- preserve existing UI and app orchestration, but prevent cross-layer leakage.

Implementation snapshot (2026-03-26):
- Added unified warning aggregation + route presentation projection for Inbox (`PendingWarningAggregator`, `PendingRoutePresentation`).
- Inbox queue filter/count/status/warning rendering now reads projection output instead of ad-hoc view logic.
- Added routing rule metadata (`version/source/path/hash/fingerprint`) in `RuleLoader`.
- Added explicit hot-reload boundary: `recompute route` now forces rule cache reload; drawer match index rebinds to current rule fingerprint.

Rollout plan (safe migration):
1. add new semantic/matching components behind non-default path.
2. run old/new paths in parallel for comparison logs on baseline samples.
3. switch default to new path only after parity is proven.
4. remove deprecated duplicate code paths.

Acceptance:
- all baseline scenarios preserve current user-observed outcomes.
- queue status and drawer match outputs are unchanged.
- status authority is single-source (verdict chain no double ownership).
- Sidebar/Inspector/Apply V2.2.1 constraints remain unchanged.
- performance is no worse than current baseline (cross-page switch equal or smoother).
- app version remains `v2.2.1` and desktop package builds cleanly.

Non-goals in V2.2.1:
- finalize inspector business content.
- introduce V2.3 apply write behavior.
- add new user-facing routing features.

## V2.3
**Goal (one line)**
Activate the Apply button in Inbox so files can be physically copied into Library sample drawers.

**Design rationale**
The old "Confirm" flow only created an in-memory record without ever touching the filesystem — it was an incomplete design that never became user-facing. V2.3 replaces it entirely with a filesystem-first approach: write the file first, then let Library Sync derive the app state from what's actually on disk. This is more reliable because the filesystem is the single source of truth; there's no risk of the app state drifting out of sync with reality.

Atomic transactions (prepare → commit / rollback) are required because a single file can fan out to multiple sample drawers. If the write to the second drawer fails after the first already succeeded, the user would end up with an inconsistent state — the file exists in some drawers but not others, with no way to tell which are complete. Rolling back all writes on any failure eliminates this class of bugs entirely.

**User story**
When a measurement file in Inbox shows status "Library Matched", the user can click **Apply** to copy it into the correct Library sample folder. The file lands in the right subfolder (e.g. `tests/XRD/` for XRD data), Library refreshes automatically, and the item disappears from the Inbox queue. **Apply All** does the same for all matched items at once. If anything goes wrong mid-write, no partial files are left behind — the operation either fully succeeds or fully rolls back.

This version also removes the old "Confirm" flow that existed in the codebase but was never user-facing.

**Detailed requirements**
1. `Apply Selected` unit is a file; copies the selected pending file into its matched Library drawer(s).
2. `Apply All` processes `Library Matched` items only; silently skips `Review Required` items.
3. A single file can fan out to multiple sample drawers if it matches more than one sample.
4. Multi-target apply must be atomic per file: if any drawer write fails, all writes for that file roll back (no partial residue).
5. After apply, run `Library Sync Files` to refresh Library UI state.
6. Successfully applied pending imports are removed from the Inbox queue.
7. No sidecar metadata in V2.3 — deferred to V2.5 (after workflow fields are defined in V2.4).

**Destination subfolder rule**
- Channel type `XRD`, `M-H`, `R-H`, `EDS`, or `AFM` → `tests/{channel}/`
- All other channels or file-level delivery → `measurements/`
- Multiple channels on one target: first matching test slot wins; fallback to `measurements/`

**Test scenarios & acceptance criteria**
1. Single-target selected apply
- Acceptance: file appears only in that sample drawer; pending import removed from queue.
2. Multi-target selected apply
- Acceptance: file appears in all target sample drawers; pending import removed from queue.
3. Inject failure for one target in multi-target apply
- Acceptance: no target keeps partial artifact (rollback verified); no temp residue.
4. Mixed queue apply-all (library-matched + review-required)
- Acceptance: library-matched items applied; review-required unchanged.

**New files (3)**

`Sources/SpinLabApp/Library/LibraryWriteTransaction.swift`
- `struct LibraryWriteTransaction`
- Atomic per-file write: `prepare(sourceURL:destinationURL:)` copies to temp; `commit()` moves temp → destination; `rollback()` removes all temp artifacts.

`Sources/SpinLabApp/App/InboxArchiveApplyService.swift`
- `struct InboxArchiveApplyService`
- Single write execution entry. Drives one `LibraryWriteTransaction` per pending file across all its drawer targets.
- `func apply(pending:targets:libraryIndex:libraryStore:libraryRootURL:) throws`
- `enum InboxArchiveApplyError`: `sourceFileNotFound`, `drawerNotFound(sampleKey:)`, `commitFailed(sampleKey:underlying:)`
- All filesystem writes must go through this service; no side writes permitted elsewhere.

`Sources/SpinLabApp/App/ApplyCoordinator.swift`
- `struct ApplyCoordinator`
- Orchestrates Apply Selected and Apply All. Pure value type, no stored state.
- `func applySelected(pendingID:pendingImports:routingState:libraryIndex:libraryStore:libraryRootURL:applyService:) -> InboxApplyOutcome`
- `func applyAll(pendingImports:routingState:libraryIndex:libraryStore:libraryRootURL:applyService:) -> InboxApplyOutcome`
- `enum InboxApplyOutcome`: `nothingToApply`, `success(appliedIDs:)`, `partialSuccess(appliedIDs:failedIDs:)`, `failure(message:)`
- **Placement note**: lives in `App/` rather than `UseCases/` because it drives filesystem side effects through `InboxArchiveApplyService`. Per AGENTS.md, `UseCases/` is reserved for stateless Input→Output transformations with no side effects. A coordinator that causes I/O and updates persistent state belongs in the App orchestration layer.

**Modified files**

`Library/LibraryStore.swift`
- Add `func drawerRootURL(for sample: LibrarySample, rootURL: URL) -> URL` (wraps existing private `sampleDirectoryURL`).

`App/State/InboxFeatureStore.swift`
- Add `var applyErrorMessage: String?` and `var lastApplyOutcome: InboxApplyOutcome?`
- Add `func applyPending(outcome:appliedIDs:)` — updates state and removes applied items from repository.
- Remove `confirmPendingImport(pending:draft:useCase:libraryRepository:makeArchivedRecord:)`.

`App/SpinLabAppState.swift`
- Add `func applySelectedPendingImport()` and `func applyAllPendingImports()`.
- Both call `ApplyCoordinator`, then trigger `librarySyncService.syncIndexFromFilesystem(rootURL:)`.
- Remove `confirmSelectedPendingImport()` overloads and `confirmPendingImportUseCase` property.

`App/InboxFacade.swift`
- Add `applySelected: () -> Void` and `applyAll: () -> Void` closure parameters.
- Add `func applySelectedPending()` and `func applyAllPending()`.

`Features/Inbox/InboxViewModel.swift`
- Add `var applySelected: () -> Void = {}` and `var applyAll: () -> Void = {}`.

`Features/Inbox/InboxView.swift`
- Remove `.disabled(true)` from Apply button; wire to `viewModel.applySelected()`.
- Add `Apply All` button wired to `viewModel.applyAll()`.
- Remove placeholder explanatory text.

`App/AppVersion.swift`
- Bump `AppVersion.library` per AGENTS.md policy.

**Confirm flow removal**

The old `ConfirmPendingImport` path was an earlier design that only created in-memory records without copying files. It was never user-facing and is now fully replaced by Apply.

Files/methods to delete:
- `UseCases/ConfirmPendingImportUseCase.swift` — entire file
- `InboxWorkflowService.confirmPendingImport()` — method + `InboxConfirmPendingImportOutcome` enum
- `InboxFeatureStore.confirmPendingImport()` — method
- `SpinLabAppState.confirmSelectedPendingImport()` — both overloads + `confirmPendingImportUseCase` property
- `AppCoordinator.routeAfterPendingConfirmation()` — method

Keep (used outside confirm flow):
- `PendingImportConfirmationDraft` — used by Inbox UI workspace (File Tags display)
- `ArchivedRecord` — core domain model used by Workbench
- `makeArchivedRecord()` private function in `SpinLabAppState`

**Test file**
`Tests/SpinLabAppTests/V230ApplyTests.swift` — 4 scenarios above.

**Execution order**

> Per AGENTS.md: logic changes and UI changes must be in separate commits.

**Round 1 — Logic & Service Layer** (commit separately before touching UI)
1. `LibraryWriteTransaction.swift`
2. `LibraryStore.swift` — add `drawerRootURL`
3. `InboxArchiveApplyService.swift`
4. `ApplyCoordinator.swift`
5. `InboxFeatureStore.swift` — add apply state, remove confirm method
6. `SpinLabAppState.swift` — wire up, remove confirm methods
7. `InboxFacade.swift` — add apply methods
8. `AppCoordinator.swift` — remove `routeAfterPendingConfirmation`
9. `InboxWorkflowService.swift` — remove confirm method + outcome enum
10. Delete `UseCases/ConfirmPendingImportUseCase.swift`
11. `V230ApplyTests.swift`
12. `AppVersion.swift` — bump version
13. `./scripts/build_desktop_app.sh debug` — verify logic layer builds and tests pass

**Round 2 — UI Layer** (separate commit after Round 1 is verified)
1. `InboxViewModel.swift` + `InboxView.swift` — enable Apply button, add Apply All, remove placeholder text
2. `./scripts/build_desktop_app.sh debug` — verify UI layer builds cleanly

## V2.4 ✓ done
**Goal (one line)**
Build a Workflow Registry in Workbench so the user can define their own workflows and the fields each one requires.

**Design rationale**
V2.4 must come before sidecar writing (V2.5) because the sidecar's content depends on knowing what fields each workflow requires. If sidecar writing were done first with hardcoded fields, those fields would need to be redesigned once the workflow registry exists — wasted work and a format migration.

Storing the registry in App Support (not in the Library folder) is a deliberate choice: workflow definitions describe how the researcher works, not what data they have. They should persist even when the Library folder is changed or moved. Keeping them separate also means the Library folder stays purely about research data.

The existing Workbench content is placeholder code from an earlier design (the old Confirm / ArchivedRecord flow that V2.3 removes). Clearing it avoids confusion and gives V2.4 a clean foundation. The Workbench's real purpose — analysis and visualization — will be built out incrementally in later versions once the workflow schema exists to guide it.

A user-editable registry (rather than hardcoded workflows in Swift) lets the researcher add their own measurement types without requiring a code change. Different labs, different workflows.

**User story**
The Workbench currently has no real content — just placeholder text. V2.4 replaces all of that with a Workflow Registry panel. The user can add workflows they actually use (e.g. XY Rotation, AMR, RT, AHE, 3ω) and for each one specify what conditions need to be recorded (temperature, rotation angle, test current, etc.). This registry becomes the shared source of truth: Inbox will read it in V2.5 to know which fields to collect when applying a file, and Library will read it in V2.6 to display measurement history intelligently.

The registry is stored locally in App Support and persists across sessions, independent of the Library folder location.

**Detailed requirements**
1. User can add, edit, and remove workflow definitions.
2. Each workflow has: an ID (e.g. `XY`), a display name, an optional parent workflow (e.g. `XY` is a child of `rotation`), and a list of condition fields.
3. Each condition field has: a key, a display label, an optional unit, and a required/optional flag.
4. Registry persists to `~/Library/Application Support/SpinLab/workflow_registry.json`.
5. On first launch with an empty registry, seed with example entries so the user can see the structure.
6. Clear existing Workbench placeholder content; Workbench starts fresh with the Workflow Registry as its first real feature.

**Seeded defaults (first launch)**
```
XY Rotation  → fields: Temperature (K), Rotation Angle (deg)
RT           → fields: Test Current (mA)
```

**Test scenarios & acceptance criteria**
1. Empty registry on first launch → seeded defaults are present.
2. Add a workflow → appears in list; persists after app relaunch.
3. Remove a workflow → no longer in list; JSON updated.
4. Edit a condition field → change saved correctly.

**New files**

`Sources/SpinLabApp/Workflow/WorkflowDefinition.swift`
- `struct WorkflowDefinition: Codable, Identifiable, Hashable, Sendable`
  - `id: String`, `displayName: String`, `parentID: String?`, `conditionFields: [WorkflowConditionField]`
- `struct WorkflowConditionField: Codable, Hashable, Sendable`
  - `key: String`, `label: String`, `unit: String?`, `required: Bool`

`Sources/SpinLabApp/Workflow/WorkflowRegistryStore.swift`
- `final class WorkflowRegistryStore`
- `func load()` — reads `workflow_registry.json` from App Support
- `func save()` — writes back to JSON
- `func add(_:)`, `func remove(id:)`, `func update(_:)`, `func definition(for:) -> WorkflowDefinition?`

`Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift`
- Two-panel layout: left = workflow list with Add/Remove; right = selected workflow detail with condition field editor.

**Modified files**

`Features/Workbench/WorkbenchView.swift`
- Remove all existing placeholder content (`ArchivedWorkbenchDetailView`, `PendingWorkbenchPreview`, "Workflow fixed to…" display).
- Replace with top-level section switch: `Workflows` (live) | `Measurements` (placeholder for V2.6).

`App/State/WorkbenchFeatureStore.swift`
- Add `workflowRegistryStore: WorkflowRegistryStore`.
- Expose `workflowDefinitions: [WorkflowDefinition]` for view binding.
- Add CRUD methods delegating to `WorkflowRegistryStore`.

`App/AppEnvironment.swift` (or equivalent)
- Instantiate and inject `WorkflowRegistryStore`.

`App/AppVersion.swift`
- Bump `AppVersion.library`.

**Test file**
`Tests/SpinLabAppTests/V240WorkflowRegistryTests.swift` — 4 scenarios above.

**Execution order**
1. `WorkflowDefinition.swift`
2. `WorkflowRegistryStore.swift`
3. `WorkbenchFeatureStore.swift` — integrate registry store
4. `WorkflowRegistryView.swift`
5. `WorkbenchView.swift` — clear placeholder, add Workflows tab
6. Wire up in AppEnvironment
7. `AppVersion.swift` — bump
8. `V240WorkflowRegistryTests.swift`
9. `./scripts/build_desktop_app.sh debug`

**Delivery record** (2026-04-01)

All 4 acceptance scenarios pass. 100 tests pass total (6 additional tests beyond spec).

Structural deviations from spec — carried forward as design decisions, not defects:

1. `WorkflowConditionField` schema changed.
   Spec defined: `{ key: String, label: String, unit: String?, required: Bool }` — a self-contained field definition.
   Shipped as: `{ definitionID: String }` — a reference to a condition defined in the Rules Handbook (`conditionDefinitions`).
   Reason: Rules Handbook (also v2.4) already owns condition metadata (label, unit). Duplicating it inside every workflow definition would create two sources of truth. `WorkflowConditionField` is now a pointer, not a definition.
   V2.5 impact: when writing sidecar condition fields, resolve label/unit by looking up `definitionID` in the active `conditionDefinitions`, not by reading from `WorkflowConditionField` directly.

2. XY seeded defaults differ from spec.
   Spec: XY Rotation → Temperature (K), Rotation Angle (deg).
   Shipped: XY Rotation → Temperature, Field (mT).
   Reason: "rotation_angle" is not a defined condition in the Rules Handbook at this point. Field (mT) was used as a stand-in. If XY rotation workflows need a rotation angle condition, add `rotation_angle` to `conditionDefinitions` in the handbook first, then update the seeded defaults.

3. `WorkflowDefinition` gained an `aliases: [String]` field not in spec.
   Used by `canonicalWorkflowID()` in `SpinLabAppState` to resolve workflow tokens from parsed filenames via alternate names. No impact on V2.5.

## V2.5
**Goal (one line)**
When applying a file, automatically write a tag record alongside it capturing workflow and conditions.

**Prerequisites from V2.4 delivery**
- `WorkflowConditionField` stores only `definitionID`, not label/unit. When populating sidecar condition fields, resolve display metadata by looking up each `definitionID` in the `conditionDefinitions` array from the active `FilenameRuleSet` (via `ConditionFieldCatalog`).
- The example sidecar in this spec uses `"rotation_angle"` as a condition key. That condition does not exist in the Rules Handbook yet. Before implementing that example, either update the spec to use conditions that are already defined (temperature, current, field, device), or add `rotation_angle` to `conditionDefinitions` in the handbook.
- Condition values at apply time come from `PendingImportConfirmationDraft.conditionValues: [String: String]`, keyed by `definitionID`. This replaced the old `temperature: String` / `deviceName: String` fields as of v2.4.

**Design rationale**
The sidecar is a separate file (not merged into `sample.json`) because `sample.json` is owned by the Library registry sync — it reflects what's in the XLSX spreadsheet. Mixing apply-time measurement conditions into that file would conflate two different data sources and make registry sync logic more fragile. Keeping sidecar files separate means each data source stays clean and independently updatable.

One sidecar per file per destination drawer (rather than one shared sidecar) is correct for fan-out scenarios. When a file routes to multiple samples, each sample may only be relevant for a subset of channels. Having a per-drawer sidecar makes each drawer self-contained — it describes exactly what was deposited there and why, with no cross-sample data leakage.

The sidecar and data file must be atomic (both succeed or both roll back) because a sidecar without its data file is misleading, and a data file without its sidecar would silently lose the measurement conditions. There's no useful partial state.

**User story**
After V2.4 is in place and the user has defined their workflows, the Apply action gains a new behavior: alongside each copied data file, the app writes a small companion tag file (e.g. `mydata.spinlab.json`) in the same folder. This file records the conditions of the measurement — workflow, temperature, and any other fields defined for that workflow in the registry. The user doesn't need to do anything extra; it happens automatically on Apply. These tag files are what V2.6 will read to build the "Measurements Done" history per sample.

If the file's workflow isn't found in the registry, the app records whatever condition values are available from the Inbox draft as a fallback.

**Sidecar format** (example for workflow `XY`):
```json
{
  "version": 1,
  "workflow": "XY",
  "conditions": { "temperature": "80K", "rotation_angle": "45deg" },
  "channels": ["XRD"],
  "sourceFilePath": "/original/path/myfile.dat",
  "appliedAt": "2026-03-28T10:00:00Z"
}
```

**Detailed requirements**
1. For every file written by Apply, write `{filename}.spinlab.json` in the same destination subfolder.
2. Sidecar content is determined by the matching `WorkflowDefinition` from the V2.4 registry.
3. Condition field values are read from the Inbox draft (the values the user filled in before Apply).
4. Sidecar and data file are one atomic unit: if either write fails, both roll back.
5. Each target drawer in a fan-out gets its own sidecar.
6. Fallback for unknown workflow: record `workflow`, available `conditions`, `channels`, `sourceFilePath`, `appliedAt` from available data.

**Test scenarios & acceptance criteria**
1. Apply with known workflow → sidecar written with correct condition fields.
2. Apply with unknown workflow → sidecar written with fallback fields only.
3. Multi-target fan-out → each drawer gets its own sidecar.
4. Sidecar write failure → data file and sidecar both rolled back; no residue.
5. Sidecar content survives app relaunch (stable JSON encoding).

**New files**

`Sources/SpinLabApp/Library/SpinLabFileSidecar.swift`
- `struct SpinLabFileSidecar: Codable, Hashable, Sendable`
- Fields: `version`, `workflow`, `conditions: [String: String]`, `channels`, `sourceFilePath`, `appliedAt`

**Modified files**

`Library/LibraryWriteTransaction.swift`
- Add `mutating func prepareSidecar(_ sidecar: SpinLabFileSidecar, destinationURL: URL) throws`
- Sidecar temp file is JSON-encoded and committed/rolled back together with the data file.

`App/InboxArchiveApplyService.swift`
- Add `draft: PendingImportConfirmationDraft` parameter to `apply(...)`.
- Build `SpinLabFileSidecar` from draft + workflow registry lookup + route target channels.
- Call `transaction.prepareSidecar(...)` alongside `transaction.prepare(...)`.

`App/ApplyCoordinator.swift`
- Pass `draftFor: (PendingImport) -> PendingImportConfirmationDraft` closure through to `InboxArchiveApplyService`.

`App/SpinLabAppState.swift`
- Read current workspace draft when calling `applySelectedPendingImport()` / `applyAllPendingImports()` and pass through.

**Test file**
`Tests/SpinLabAppTests/V250SidecarTests.swift` — 5 scenarios above.

## V2.6
**Goal (one line)**
Show a "Measurements Done" history per sample in Library, built from the sidecar tag files.

**Design rationale**
Sidecar reading is done during the existing `Library Sync Files` pass rather than as a separate operation, because Library Sync already walks the entire drawer filesystem. Piggybacking on that pass avoids duplicating the filesystem traversal and ensures the displayed measurement history is always in sync with what's actually on disk — no separate "refresh history" action needed.

The display is added as a new collapsible section in the existing sample detail panel (alongside Sample, Numeric Tags, Metadata) rather than as a separate screen, because it's sample-scoped information. The user is already looking at a sample when they want to know what tests it has had — no navigation needed.

**User story**
After files have been applied with V2.5 sidecars, the Library sample detail panel (right column) gains a new collapsible section: **Measurements Done**. It lists every measurement that has been applied to this sample — workflow and conditions — so the user can see at a glance what tests have been run and under what conditions.

```
▾ Measurements Done
  XY  |  80K
  AMR |  RT
```

The section can be collapsed with a chevron, same as the existing Sample / Numeric Tags / Metadata sections.

**Detailed requirements**
1. During `Library Sync Files`, scan each sample drawer's subfolders for `*.spinlab.json` files.
2. Decode each sidecar into an `AppliedMeasurement` record.
3. Aggregate all records per sample; attach to `LibrarySample`.
4. Display in a new collapsible "Measurements Done" section in the sample detail panel.
5. Each row shows: workflow + condition values (ordered by workflow condition definitions).
6. `workflow` is the canonical test classification in V2.6 UI; no separate `testType` field is required.
7. `appliedAt` remains stored in sidecar/model for sorting and auditability, but date display in the detail row is optional and deferred.

**New model**
```swift
struct AppliedMeasurement: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var workflow: String
    var workflowDisplayName: String
    var conditions: [String: String]   // e.g. {"temperature": "80K"}
    var appliedAt: Date
    var sourceFileName: String
}
```

**Modified files**

`Library/LibraryStore.swift`
- In `buildIndexFromFilesystem`, scan drawer subfolders for `*.spinlab.json`; decode into `[AppliedMeasurement]`.

`Library/LibraryModels.swift`
- Add `appliedMeasurements: [AppliedMeasurement]` to `LibrarySample` (default empty, backward-compatible).

`Features/Library/LibraryDetailSections.swift` (or `LibraryViewComputationService.swift`)
- Add "Measurements Done" collapsible section after existing Metadata section.

**Test file**
`Tests/SpinLabAppTests/V260MeasurementsDisplayTests.swift`

## V2.7
**Goal (one line)**
Finalize auditability and safety with dual logs, strict duplicate guard, and safe pending cleanup.

**User story**
Every Apply action writes a timestamped entry to an import log (both in the Library folder and in App Support), so the user can always trace when a file was archived and to which drawers. Duplicate files are rejected before they reach the queue. Clearing the Inbox only removes pending items — it never touches files already in Library.

**Detailed requirements**
1. Import log: records each apply action with timestamp, source file, target drawers, result.
2. Dual log sinks: one under `Library Root`, one under App Support.
3. Duplicate import guard: reject duplicate by `fileName + contentHash`.
4. `Clear Imports`: clears pending queue only; never touches archived Library files.
5. Apply path unification: remove the dual apply execution paths in `SpinLabAppState` and converge selected/apply-all onto one async per-file engine with shared progress and error handling semantics.
6. Rule migration canonicalization unification: remove duplicated legacy-to-canonical migration logic by introducing one shared canonicalization routine used by both `RuleLoader` and `ConditionRulesHandbookStore`.
7. Legacy consumer cleanup (safe scope): remove low-risk legacy consumer traces that are no longer needed in active V2.x flows, while preserving required snapshot/config compatibility boundaries.
8. Keep deprecated rule fields (`temperaturePattern/currentPattern/fieldPattern`, `deviceRules`) under observation and do not delete in V2.7 unless production telemetry confirms migration path is no longer used.

**Test scenarios & acceptance criteria**
1. Apply action → import log written to both sinks with consistent target summary.
2. Duplicate import attempt → file rejected; no new pending route item.
3. Clear imports → pending queue cleared; archived library files unchanged.

**Code structure**
1. Add `AuditEvent` model and `AuditLogger` with two sinks.
2. Add `DuplicateGuard` for hash-based rejection.
3. Add `PendingCleanupService` to isolate pending purge side effects.
4. Refactor `SpinLabAppState` apply flow:
   - Extract reusable async apply loop.
   - Route both selected-apply and apply-all through the same loop.
   - Remove `performApply(resolver:)` and `ApplyContext` once migration is complete.
5. Extract rule canonicalization helper under `Import/Rules` and make both migration call sites delegate to it.
6. Perform targeted legacy-consumer cleanup in app/view/domain call sites where compatibility is no longer required.
7. Keep deprecated rule fields + migration branches intact for one more release window; decide deletion after telemetry validation.

## Out-of-scope for this execution thread
- Auto-apply without manual user action.
- Plot preview in Inbox right panel (extension seam retained for future).
- Workbench analysis tools (separate roadmap after V2.4 workflow registry is established).
