# Technical Debt Backlog

Pending improvements that have been identified but not yet executed.
Each item includes a code pointer, the motivation, the target state, and a rough effort estimate.

Items are ordered by impact, not urgency. See `TECH_DEBT_EXECUTION_LOG.md` for completed rounds.

---

## High Impact

### ParsedFilenameHints unification
**Code:** `Sources/SpinLabApp/Domain/Models.swift` — `ParsedFilenameHints`
**Also see:** `Sources/SpinLabApp/Import/Rules/ConditionFieldCatalog.swift`

**Problem:**
The condition unification introduced in v2.4 is complete at the compilation and storage layers, but
`ParsedFilenameHints` still carries two parallel structures:

```swift
var temperature: String?    // named built-in field
var current: String?
var field: String?
var deviceName: String?
var extraConditionValues: [String: String]   // generic dict for custom conditions
```

`ConditionFieldCatalog.conditionValues()` merges them at the consumer boundary, but the split means:
- Adding a new "built-in" condition requires changes in `FilenameRuleParser`, `ParsedFilenameHints`,
  `ConditionFieldCatalog`, and all test fixtures that construct hints directly.
- Adding a custom condition requires only a `conditionDefinition` entry.
- The asymmetry will confuse contributors who read the data model and assume `temperature` is special.

**Target state:**
```swift
// ParsedFilenameHints
var conditionValues: [String: String]   // all conditions, keyed by definition ID

// Named accessors as computed properties for callsite convenience
var temperature: String? { conditionValues[ConditionFieldCatalog.temperatureID] }
var current: String?     { conditionValues[ConditionFieldCatalog.currentID] }
var field: String?       { conditionValues[ConditionFieldCatalog.fieldID] }
var deviceName: String?  { conditionValues[ConditionFieldCatalog.deviceID] }
```

**Migration steps:**
1. Change `ParsedFilenameHints` storage to `conditionValues: [String: String]`.
2. Add computed accessors for the four built-in IDs (keeps existing callsites working).
3. Change `FilenameRuleParser` to write all condition results into `conditionValues` directly,
   removing the separate named assignments.
4. Change `ConditionFieldCatalog.conditionValues(from:)` to return `hints.conditionValues` directly
   (the merge step disappears).
5. Update any tests that construct `ParsedFilenameHints` with named fields to use `conditionValues:`.
6. Remove the named stored properties once all callsites use the accessors.

**Effort:** Medium (widespread but mechanical; mostly find-replace + test update)

---

### Apply pattern unification
**Code:** `Sources/SpinLabApp/App/SpinLabAppState.swift` — `performApply(resolver:)` and `performApplyAllPendingImports()`

**Problem:**
Two apply patterns coexist:

| Path | Style | Progress tracking |
|------|-------|-------------------|
| `performApplyAllPendingImports()` | async Task, per-file loop | Yes (`applyProgressState`) |
| `performApply(resolver:)` | sync closure, batch result | No |

`performApplySelectedPendingImport()` still calls the sync helper. This means "apply selected" has
no progress state and a different error-handling path than "apply all". The `ApplyContext` typealias
(a 4-tuple) was introduced to share context between the two, which is a sign the abstraction is
incomplete.

**Target state:**
Merge into a single async apply engine. Both "apply selected" and "apply all" call the same
per-file async loop, differing only in the input slice. `performApply(resolver:)` and the
`ApplyContext` typealias are removed.

**Migration steps:**
1. Extract the per-file loop body in `performApplyAllPendingImports` into a reusable
   `applyPendingImports(_ pending: [PendingImport]) async` method.
2. Rewrite `performApplySelectedPendingImport` to call it with a single-element slice.
3. Delete `performApply(resolver:)` and `ApplyContext`.

**Effort:** Low-Medium (contained within `SpinLabAppState`; no domain model changes)

---

## Low Impact / Housekeeping

### Remove deprecated fields from ConditionRules and FilenameRuleSet

**Code:**
- `Sources/SpinLabApp/Import/Rules/FilenameRuleSet.swift`
  - `ConditionRules.temperaturePattern / currentPattern / fieldPattern`
  - `FilenameRuleSet.deviceRules`

**Condition to remove:** All user rule files have been migrated to v2.4+ format (i.e., contain
`conditionDefinitions` and `conditions.extraConditions`). The migration guard in
`RuleLoader.normalizeConditionDefinitionBindings()` can be checked: once no "synthesized canonical
definitions" warning is ever emitted in production, the fields and their migration branches are safe
to delete.

**Steps:**
1. Add a telemetry counter or log line tracking how often the synthesis path is hit in production.
2. After one release cycle with zero hits, delete the three pattern fields from `ConditionRules`,
   the `deviceRules` field from `FilenameRuleSet`, and the corresponding decode/migration branches
   in `RuleLoader`.
3. Remove the `Deprecated` comments added in v2.4.

**Effort:** Low (straightforward deletion once the condition is met)

---

### Remove legacy CodingKeys from PendingImportConfirmationDraft

**Code:** `Sources/SpinLabApp/App/State/InteractionStateModels.swift`
- `CodingKeys.workflowTag`, `.deviceName`, `.temperature`
- The corresponding `init(from:)` migration branches

**Condition to remove:** No active user has an interaction snapshot written by a version predating
v2.4 (i.e., after one full release cycle where v2.4 is the minimum supported version and old
snapshots have been naturally overwritten).

**Steps:** Delete the three legacy cases from `CodingKeys` and the `else` branch in `init(from:)`.

**Effort:** Trivial

---

## From previous backlog (TECH_DEBT_EXECUTION_LOG.md § Next Planned Steps)

These items predated v2.4 and remain open:

### SpinLabAppState decomposition
Continue splitting `SpinLabAppState` by extracting feature-owned mutable state and actions into
focused `@Observable` stores. The apply-pattern unification above is a prerequisite for extracting
the inbox apply surface cleanly.

### try? audit in LibraryStore
Audit high-impact `try?` usage in `LibraryStore` and convert selected write/read paths to explicit
error propagation with structured error types.
