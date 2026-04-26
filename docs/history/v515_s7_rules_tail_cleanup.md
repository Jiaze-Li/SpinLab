# v5.1.5 s7 — Rules-Tail Cleanup (tasks 2 / 3 / 4)

**Completed**: 2026-04-26
**Commits**: 08c7f8a (s7-c1) → f6452e2 (s7-c2) → a486cec (s7-c3) → 05522a5 (s7-c4) → f7939c4 (s7-c5)
**Tests**: 79/79 V515 suite green (11 new across 3 suites; `V240WorkflowRegistryTests` archived)

---

## What was built

### s7-c1 — `WorkflowDefinitionStore` (read-only)

New `Workflow/WorkflowDefinitionStore.swift` reads the canonical workflow list directly from `config/workflow.json` via the existing `WorkflowFileDraft` decode path. `WorkbenchFeatureStore` now sources its workflow array from this store instead of the runtime outer `WorkflowRegistryStore`. AppEnvironment exposes the new store; AppState wires it during init.

### s7-c2 — `WorkflowRegistryRetirementService` + AppEnvironment cleanup

New `Import/Rules/WorkflowRegistryRetirementService.swift` runs once at startup. If `~/Library/Application Support/SpinLab/workflow_registry.json` exists:

1. Decode `[WorkflowDefinition]`. Failure → log + skip merge (no overwrite).
2. Merge into `WorkflowFileDraft` of `config/workflow.json`:
   - **Same ID (case-insensitive)**: overwrite `displayName` + `conditionFieldIDs` only; preserve `matchRules` + `measurementTagRules`.
   - **Registry-only ID**: append entry with `matchRules = []`, `measurementTagRules = []`; `displayName` + `conditionFieldIDs` taken from outer registry.
3. Write `config/workflow.json.backup-<ts>` then atomic-write merged content.
4. Rename outer registry → `workflow_registry.json.backup-<ts>` and log retirement.
5. Any step failure → leave both files untouched, log error, app continues.

`AppEnvironment.workflowRegistryStore` removed. `SpinLabAppState` no longer references the old store.

### s7-c3 — Read-only Workbench config page + `parentID` removal

`WorkflowRegistryView` rewritten as a read-only form (direction 1, per K1 decision):

- Left column: workflow list (sourced from `WorkflowDefinitionStore`), click-to-switch routes to that workflow's workspace.
- Right column: read-only summary — id / displayName / conditionFieldIDs / matchRules / measurementTagRules.
- Bottom button: "在规则面板编辑此工作流" — switches the main area to Inbox + RulesPanel + Workflow section (row-level focus deferred per K1 fallback).
- Removed: Add Workflow / Remove / displayName field / Parent ID field / FlowLayout-based conditionFieldIDs editor / WorkbenchFeatureStore CRUD methods (212 lines deleted).

`WorkflowRegistryStore.swift` removed in full (132 lines). `WorkflowDefinition.parentID` field + Codable keys + decode tolerance removed (48 lines deleted from the model). Three V33x test files updated to drop `parentID` arguments at construction sites.

### s7-c4 — `RulesBootstrapper` replaces `RulesMigration`

`Import/Rules/RulesBootstrapper.swift` (33 lines) — single function `seedMissingRuntimeFilesFromBundleIfNeeded()` walks the 5 schema URLs; for each missing runtime file, copy the bundle counterpart via atomic write. No state machine, no v1/v2/v3 enrichment, no parentID stripping, no oldFilenames sweep.

`RulesMigration.swift` (279 lines) deleted in full. `RulesMigrationState.swift` (7 lines) deleted. `RulesConfigPaths.oldFilenames` + `defaultWorkflowIDPolicyData` (26 lines) deleted. `SpinLabApp.init` calls `RulesBootstrapper` instead of `RulesMigration`.

### s7-c5 — Tests

| Suite | Count | Covers |
|---|---|---|
| V515WorkflowRegistryRetirementTests | 5 | same-ID merge preserves matchRules/measurementTagRules; registry-only append with empty rules; decode failure no-op; idempotent re-run; backup naming |
| V515WorkbenchRegistryReadOnlyTests | 3 | list rendering from WorkflowDefinitionStore; click-to-switch routes correctly; edit-button dispatches to RulesPanel + Workflow section |
| V515RulesBootstrapperTests | 3 | all-5-missing seeds all; partial-missing seeds only the gap; bundle resource missing logs warn without crash |

`V240WorkflowRegistryTests.swift` (402 lines) archived — covered the deleted `WorkflowRegistryStore` write-path. `V223AppEnvironmentIntegrationTests` updated to drop `workflowRegistryStore` ref. `V250SidecarTests` + `V320WorkflowSearchAcrossDrawersTests` minor signature touch-ups.

---

## Startup sequence (hard constraint)

```
SpinLabApp.init()
  ├─ RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()
  ├─ WorkflowRegistryRetirementService.runIfNeeded()
  ├─ RulesSyncEngine.reverseSyncOnStartup()  (existing s6)
  ├─ RuleLoader.shared.reloadCached()
  └─ stores init (WorkbenchFeatureStore consumes WorkflowDefinitionStore)
```

Order rationale:
- bootstrap before reverseSync — otherwise reverse-sync may write empty files.
- retirement before RuleLoader — otherwise the cached `workflow.json` is the pre-merge view and would need invalidation.

---

## Key design decisions

**K1 — Direction 1 for Workbench config page**: read-only list + jump-to-rules-panel button, not "delete the page and land on first workspace". Reason: keeping a single place where every workflow is visible is a legitimate Workbench function; the user-facing jump chain otherwise gets too long.

**K2 — Partial migration retirement, not full**: kept the bootstrapper for the cold-start case (config/ empty → seed from bundle); removed the state machine, version migration, and enrichment paths. The schema is now stable enough that one-time conversion code no longer pulls weight.

**K3 — Registry merge preserves matchRules**: same-ID rows overwrite `displayName` + `conditionFieldIDs` only. Reason: outer registry never carried matchRules (those live exclusively in `config/workflow.json` post-s4); blindly overwriting would zero them out for users who already saved match rules between s4 and s7. Registry-only IDs are appended with empty matchRules to avoid silent routing side-effects — user must add matchRules in the rules panel before new files identify against the appended workflow.

**M7 (rejected, carried over from s6)**: backup naming uses `<file>.backup-<ts>` only for one-shot retirement events (workflow_registry.json, config/workflow.json pre-merge); steady-state writes still use single `.json.backup` (overwrite previous).

---

## Files deleted

- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` — 212 lines (CRUD methods for the old registry)
- `Sources/SpinLabApp/Workflow/WorkflowRegistryStore.swift` — 132 lines (entire file)
- `Sources/SpinLabApp/Import/Rules/RulesMigration.swift` — 279 lines (entire file)
- `Sources/SpinLabApp/Import/Rules/RulesMigrationState.swift` — 7 lines (entire file)
- `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` — 48 lines (parentID field + Codable keys + decode tolerance)
- `Sources/SpinLabApp/Import/Rules/RulesConfigPaths.swift` — 26 lines (oldFilenames + defaultWorkflowIDPolicyData)
- `Tests/SpinLabAppTests/V240WorkflowRegistryTests.swift` — 402 lines (archived; covered deleted code)

Total: ~1106 lines deleted, 392 lines added (mostly tests).

---

## Acceptance gate

- [x] swift build clean
- [x] swift test --filter V515 → 79/79 green (10 suites)
- [x] git diff contains no `WorkflowRegistryStore` / `RulesMigration` / `parentID` strings outside deletion diffs
- [x] Workbench config page: left list + read-only right summary, no Add/Remove/Parent ID controls
- [x] "在规则面板编辑此工作流" button routes to RulesPanel + Workflow section
- [x] cold-start (empty config/) → bootstrap seeds 5 files → rules panel editable
- [x] runtime with outer `workflow_registry.json` first launch → merged + renamed `.backup-<ts>`
