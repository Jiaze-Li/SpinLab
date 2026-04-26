# v5.1.5 s5 — RulesPanel 5-Section Rewrite

Session date: 2026-04-26  
Commit: ea09161  
Tests: 36 new tests across 5 suites, all green

---

## What Changed

Replaced the legacy 7-file / 5-section v2 rules panel with a new 5-section
implementation matched to the 5-book v3 schema:

| Section | File |
|---|---|
| Import Filters | `import_filters.json` |
| Filename Tokenization | `filename_tokenization.json` |
| Sample Identification | `sample_identification.json` |
| Workflow | `workflow.json` |
| Measuring Condition | `measuring_condition.json` |

---

## Architecture Decisions

**Single store, 5 drafts.** `RulesManagementStore` holds one draft per section as
`private(set)` properties. Each `updateX(draft:)` call marks the section dirty.
`saveCurrent()` dispatches to the active section's save function.

**SHA-256 hash precondition.** On `present()`, each file's hash is cached. Before
writing, the current file hash is compared; a mismatch returns `.externalConflict`
rather than silently overwriting external edits.

**Cross-section validation.** When saving `workflow`, conditionFieldIDs are
validated against the *dirty* `measuringConditionDraft` if `.measuringCondition`
is in `dirtySections`, otherwise against the disk file. This allows Save All
(which iterates `RulesPanelSection.allCases` — workflow before measuringCondition)
to see a newly-added condition that exists only in the dirty draft.

**Save All order is allCases, not Set.** `RulesPanelView` iterates `allCases`
filtered by `dirtySections` so save order is always deterministic:
importFilters < filenameTokenization < sampleIdentification < workflow < measuringCondition.

**R1 gate (immediate effect).** On every successful `persist()`, the sequence is:
1. `RuleLoader.shared.reloadCached()` — cache updated atomically
2. `onRulesSaved()` — caller callback (wired in SpinLabAppState to call
   `WorkbenchFeatureStore.reloadWorkflowDefinitionsAfterRulesChange()`)
3. `persistenceHook?.didPersist?(...)` — test hook (fires after cache + callback)

This guarantees that by the time any downstream observer acts on `onRulesSaved`,
the new rules are already live in `RuleLoader.shared`.

**availableConditionFieldIDs.** Derived from `measuringConditionDraft.conditionDefinitions`,
refreshed on load and on every `updateMeasuringCondition` call. Used by
`WorkflowSection` to populate the conditionFieldIDs multi-select.

---

## Files Deleted

- `FilenameParseRulesSection.swift`
- `SampleIDRulesSection.swift`
- `WorkflowMatchRulesSection.swift`
- `SubstrateRulesSection.swift`
- `MeasurementTagRulesSection.swift`
- `V515RulesManagementStoreTests.swift` (referenced old API)

---

## Test Suites

| Suite | Count | Covers |
|---|---|---|
| V515RulesPanelStoreTests | 8 | Store lifecycle, hash conflict, override, persistence hook, Save All order |
| V515RulesPanelSaveValidationTests | 13 | Per-field validation for all 5 sections |
| V515RulesPanelCrossSectionTests | 4 | Cross-section conditionFieldID validation, dirty draft visibility |
| V515RulesSaveImmediateEffectTests | 4 | R1 gate: RuleLoader cache + conditionDefinitions updated before onRulesSaved fires |
| V515SharedSubstrateTests | 4 | SharedSubstrate: orientationAlias unknown target, nil shared, valid materialAlias, invalid regex |
