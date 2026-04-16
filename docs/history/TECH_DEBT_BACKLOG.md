# Technical Debt Backlog

Pending improvements that have been identified but not yet executed.
Each item includes a code pointer, the motivation, the target state, and a rough effort estimate.

Items are ordered by impact, not urgency. See `TECH_DEBT_EXECUTION_LOG.md` for completed rounds.

---

## High Impact

### Library layer consolidation

**Audit:** `docs/architecture/library/LIBRARY_ARCHITECTURE_AUDIT.md` (v4.2.5)

**Problem:**
Library feature has 12-layer call depth for a single action, 3 passthrough layers (ViewModel, Facade, CommandCoordinator), 3 overlapping mutation services, and a 1661-line FeatureStore mixing 5+ concerns.

**Phases:**

| Phase | Action | Effort |
|-------|--------|--------|
| P1 | Delete `LibraryCommandCoordinator` (pure passthrough); collapse `LibraryFacade` into AppState helpers | Small |
| P2 | ~~Merge `LibraryMutationOrchestrator` into `LibrarySyncService`; unify diff computation to one entry point~~ ✅ Done (v5.4.0) | Small-Medium |
| P3 | Extract from FeatureStore: workbench/measurement projections, log management, sample editing state | Medium |
| P4 | Simplify ViewModel — View reads `appState.library` directly, remove viewState mapping layer | Medium |
| P5 | Split LibraryView (1252 lines) into 4-5 focused components | Small |

**Dependencies:** P1 first (removes indirection before restructuring internals). P2-P5 can be done independently.

---

### Workflow ID alias hardcoding in SearchWorkflowMeasurementsUseCase

**Code:**
- `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift` — `canonicalWorkflowID(from:displayName:)` (line 168) and `workflowAliases(canonicalID:workflowID:workflowDisplayName:)` (line 155)

**Problem:**
Workflow ID canonicalization and alias generation are hardcoded if-else chains (`"a"/"ahe"` → `"ahe"`, `"3w"/"3omega"` → `"3w"`, etc.). Every new workflow either needs a new branch or falls through to the `default` case which only does `normalizeToken`. This creates maintenance burden and inconsistency — some workflows get explicit aliases while others don't.

**Target state:**
- `WorkbenchWorkflowID` (or a shared `WorkflowIDCatalog`) owns the canonical ID → alias mapping as data, not code.
- Each workflow declares its own aliases: e.g., `case xyRotation = "xy"` declares `aliases: ["xy", "xyrotation", "xy rotation"]`.
- `SearchWorkflowMeasurementsUseCase` reads the alias table instead of hardcoding branches.
- New workflows get search support by adding their enum case + aliases, zero changes to the search UseCase.

**Migration steps:**
1. Add `var aliases: [String]` computed property to `WorkbenchWorkflowID`.
2. Add a static lookup: `WorkbenchWorkflowID.canonical(from: String) -> WorkbenchWorkflowID?`.
3. Replace `canonicalWorkflowID()` and `workflowAliases()` in SearchUseCase with calls to the lookup.
4. Remove all hardcoded if-else branches.

**Effort:** Small (~1h). No persistence migration needed — only runtime search matching logic.

---

### ~~Rule kind type ownership cleanup~~ ✅ Done 2026-04-05 (Round E)
**Code:**
- `Sources/SpinLabApp/Import/Rules/RuleCanonicalizer.swift` — `migrateUserRuleJSONToCanonical`
- `Sources/SpinLabApp/Import/Rules/ConditionRulesHandbookStore.swift` — `RuleEntryKind`

**Problem:**
`RuleCanonicalizer` (Import/Rules layer) currently references `RuleEntryKind`, whose ownership is in
`ConditionRulesHandbookStore` (app-facing handbook layer). The module compiles because both files are
in one target, but the dependency direction is inverted and will complicate future layer separation.

**Target state:**
Move rule-kind type ownership to the Import/Rules layer (or unify on
`FilenameRuleSet.ConditionDefinitionKind`) so both canonicalization and handbook code depend on the
same lower-level type.

**Migration steps:**
1. Introduce/import a rule-kind enum in Import/Rules.
2. Replace `ConditionRulesHandbookStore.RuleEntryKind` usage with the lower-level type.
3. Keep serialized `kind` values stable (`unit_suffix` / `token_map`) and behavior unchanged.

**Effort:** Low (mechanical refactor, no product behavior change)

---

### ~~ParsedFilenameHints unification~~ ✅ Done 2026-04-05 (Round E)
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

## Rules Architecture Cleanup (post-4.1.7)

### Override 加载逻辑去重
**Code:**
- `Sources/SpinLabApp/Import/Rules/RuleLoader.swift` — `applySeparatedOverrides()`
- `Sources/SpinLabApp/Import/Rules/ConditionRulesHandbookStore.swift` — `loadSeparated*()` 系列方法

**Problem:**
RuleLoader 和 ConditionRulesHandbookStore 各自有一套 separated override 文件的加载/解码逻辑，代码重复。

**Target state:**
抽取统一的 `SeparatedOverrideLoader`，两处调用同一实现。

**Effort:** Low

---

### Override 文件删除时静默复活问题
**Problem:**
5 个 separated override 文件是整段替换（conditions_rules.json 除外）。如果 override 文件被删除，主文件中的旧规则会悄悄"复活"，用户无感知。

**Target state:**
RuleLoader 加载后检测：如果某个 override 曾经存在但现在缺失，发出 warning（可通过 `loadWarnings` 传递到 UI）。

**Effort:** Low

---

### condition_aliases.json 定位明确化
**Problem:**
`condition_aliases.json` 当前只有 `angle → device` 一条映射，使用范围窄，像是半成品。

**Target state:**
评估是否需要保留。若保留，补充文档说明用途和扩展方式；若不需要，移除并将 `angle → device` 映射硬编码或移入 `filename_rules.json`。

**Effort:** Trivial

---

## From previous backlog (TECH_DEBT_EXECUTION_LOG.md § Next Planned Steps)

These items predated v2.4 and remain open:

### SpinLabAppState decomposition
Continue splitting `SpinLabAppState` by extracting feature-owned mutable state and actions into
focused `@Observable` stores.

### try? audit in LibraryStore
~~Audit high-impact `try?` usage in `LibraryStore` and convert selected write/read paths to explicit
error propagation with structured error types.~~

✅ Partial done 2026-04-05 (Round E): `writeJSON` now logs encode/write failures to stderr. Remaining `try?` on `createDirectory` and read paths are lower risk; full audit deferred to future round.
