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
Refactor Inbox UI into the same 3-column interaction model as Library and complete manual confirm/recompute workflow.

**Detailed requirements**
1. Keep app-level columns as:
- left: navigation
- middle: operation blocks
- right: inspector/details
2. Inbox middle operation blocks order:
- Import Source
- Pending Queue
- Routing Review
- Apply
3. Toolbar action relocation:
- keep and place in operation blocks: `Load Registry`, `Import Files`, `Clear Imports`, `Recompute Route`
- remove from Inbox scope: `Create Project`
4. Right inspector shows:
- file metadata
- parsed baseline (read-only)
- editable draft (file-level + channel-level)
- parse-vs-edit diffs
- warnings
- `Confirm & Recompute Route` action
5. Preserve extension seam for future right-panel tabs, but enable details tab only now.

**Test scenarios & acceptance criteria**
1. Edit draft without confirm
- Acceptance: route plan unchanged.
2. Confirm and recompute
- Acceptance: route plan updates from edited values.
3. Switch pending items
- Acceptance: inspector state is correctly isolated per pending item.
4. `Clear Imports`
- Acceptance: clears pending queue only; no changes to already archived library drawers.

**Code structure design**
1. Split UI composition:
- `InboxOperationPanel`
- `InboxInspectorPanel`
2. Add dedicated view models for inspector and route review blocks.
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
Implement transactional `Apply Selected` and `Apply All` from Inbox route plans to Library sample drawers.

**Detailed requirements**
1. `Apply Selected` unit is a file.
2. `Apply All` processes library-matched items only; skips review-required items.
3. Single file can fan out to multiple sample drawers.
4. Multi-target apply must be atomic per file (rollback all targets if one fails).
5. File body must be copied into each target sample drawer for immediate access.
6. After apply, refresh library filesystem index and UI state.

**Test scenarios & acceptance criteria**
1. Single-target selected apply
- Acceptance: file appears only in that sample drawer.
2. Multi-target selected apply
- Acceptance: file appears in all target sample drawers.
3. Inject failure for one target in multi-target apply
- Acceptance: no target keeps partial artifact (rollback verified).
4. Mixed queue apply-all (library-matched + review-required)
- Acceptance: library-matched items applied; review-required unchanged.

**Code structure design**
1. Introduce `InboxArchiveApplyService` as single write execution entry.
2. Introduce `LibraryWriteTransaction` (`prepare/commit/rollback`).
3. Centralize apply orchestration in `ApplyCoordinator`.
4. Disallow side writes outside apply service.

## V2.4
**Goal (one line)**
Add normalized test-tag metadata sidecar at archive time and make metadata query-ready.

**Detailed requirements**
1. Metadata primary source: sidecar JSON in sample drawer.
2. Normalize tags on write, including:
- `AMR -> R_xx`
- `PHE -> R_xy`
- `XY_90shift -> workflow=XY + angle_shift=+90deg`
3. Persist conditions and level tags (`temperature/current/field`, `wafer/device`).
4. Multi-sample fan-out metadata policy:
- each sample drawer stores only channels relevant to that sample
- file body still exists in each target drawer
5. Keep original raw parse values alongside normalized values for traceability.

**Test scenarios & acceptance criteria**
1. XY_90shift sample case
- Acceptance: sidecar contains normalized workflow, angle shift, conditions, level, and normalized channel tags.
2. Multi-sample RT case
- Acceptance: PN36 sidecar does not carry PN37-only channel binding and vice versa.
3. Query/load integrity
- Acceptance: metadata reads are stable after app relaunch and filesystem rescan.

**Code structure design**
1. Add `TagNormalizer` (single normalization authority).
2. Add `ArchiveMetadataBuilder` (composes sidecar payload).
3. Add `SidecarWriter` with versioned schema field.
4. Keep metadata serialization decoupled from apply transaction core.

## V2.5
**Goal (one line)**
Finalize auditability and safety with dual logs, strict duplicate guard, and safe pending cleanup.

**Detailed requirements**
1. Edit log:
- records pre/post field values for manual confirm/recompute actions.
2. Import log:
- records archive actions with timestamp, source, targets, result.
3. Dual log sinks:
- one full audit under `Library Root`
- one structured mirror under `App Support`
4. Duplicate import guard:
- reject duplicate by `fileName + contentHash`.
5. `Clear Imports` behavior:
- clear pending records
- delete unarchived managed temp copies
- never touch archived files in library drawers.

**Test scenarios & acceptance criteria**
1. Confirm/recompute action
- Acceptance: edit log written to both sinks with consistent event identity.
2. Apply action
- Acceptance: import log written to both sinks with consistent target summary.
3. Duplicate import attempt
- Acceptance: file rejected, no new pending route item.
4. Clear imports
- Acceptance: pending queue cleared; archived library files unchanged.

**Code structure design**
1. Add unified `AuditEvent` model.
2. Add `AuditLogger` with two concrete sinks and stable event IDs.
3. Add `DuplicateGuard` module for hash and lookup.
4. Add `PendingCleanupService` to isolate pending purge side effects.

## Out-of-scope for this execution thread
- Auto-apply without manual confirmation.
- Plot preview in Inbox right panel (only extension seam retained).
- New workflow families beyond the current naming/tag normalization scope.
