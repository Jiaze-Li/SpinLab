# Inbox Rules Authoring Layer

Rules Panel is the user-facing configuration surface for Inbox routing. It owns five JSON config files that collectively govern how filenames are parsed, samples identified, channels mapped to workflows, and measurement conditions extracted.

---

## 5-Section Structure

Sections: Import Filters / Filename Tokenization / Sample Identification / Workflow / Measuring Condition.

Each section maps 1:1 to a JSON config file under `RulesConfigPaths`. `RulesPanelSection.allCases` order is the canonical Save All iteration order — never use Set iteration.

---

## Save Behavior

- Save button writes only the active section; Save All iterates `allCases` filtered by `dirtySections`.
- Hash precondition: file hash captured at open-time. If the file was modified externally since the panel opened, save fails with `externalConflict` — user must choose Reload or Override. Never silent overwrite.
- After save: `RuleLoader` cache updated → `onRulesSaved` callback fires → persistence hook fires (in that order).
- **R1 invariant**: rules changes are live in `RuleLoader.shared` *before* `onRulesSaved` fires — no restart required.
- Every section has Save + Discard buttons at both top and bottom of the scroll area.
- Closing the window with unsaved edits triggers a three-option alert: Discard Changes / Cancel / Save All.

---

## Cross-Section Validation

- Workflow `conditionFieldIDs` are validated against dirty `measuringConditionDraft` (if dirty), else disk.
- This means Save All works correctly even when the Workflow section saves before the Measuring Condition section.

---

## availableConditionFieldIDs

- Derived from `measuringConditionDraft.conditionDefinitions`; refreshed on load and every `updateMeasuringCondition` call.
- `WorkflowSection` reads this to populate the `conditionFieldIDs` multi-select UI.

---

## Sample Identification — v4 Substrate Schema (s10(2))

- **Batch prefixes**: plain text prefixes (e.g., "PN", "PT"); replaces v3 regex `sampleId.patterns`.
- **Substrate**: three unified lists — Materials, Treatments, Orientations — each an array of `SubstrateEntry {displayName, matches: [{type: equals|contains, value}]}`.
  - `displayName` has an implicit `equals(normalize(displayName))` probe injected at compile time; no need to repeat it in `matches`.
  - `matches` is OR-based; all probes are token-scoped.
  - `displayName` uniqueness is not hard-enforced at save time; duplicate entries produce undefined matching behavior.
- **"b" and "baked" are separate treatment entries**: "b" maps to `equals "b"`; "baked" maps to `contains "bake"`. Not aliases — intentional v4 behavioral separation.
- **Origin treatment detection**: compile phase detects treatment entries whose `normalize(displayName)` or any match value normalizes to "o"; stored in `compiledOriginTreatmentDisplayNames`; no longer hardcoded to treatment id == "o".
- **Composite token behavior**: a token like "STO111" can simultaneously match a Material entry (STO) and an Orientation entry (111) via `contains` probes → two substrate tags emitted; accepted behavioral change from v3.
- **Runtime migration**: v3 `sample_identification.json` is migrated to v4 on first app launch via `RulesBootstrapper`; backup written to `<config_dir>/.backup-<timestamp>/`.

---

## Validation Rules

- Sample ID: `displayName` uniqueness on substrate entries not enforced at save; user responsibility.
- Workflow Match: cross-rule token conflicts detected at save time.
- Filename Parse: `conditionDefinition` IDs must be unique.
- Workflow `conditionFieldIDs`: cross-validated against dirty `measuringCondition` draft (not just disk).

---

## Match Op Per-Context Restriction

- `starts-with`: only available in Batch ID Prefixes (SampleIdentification section).
- `unit-suffix`: only available in Measuring Condition.
- `equals` / `contains`: available in all contexts.
- All four ops are case-insensitive at runtime.

---

## Measuring Condition — Unified Rule List (v5.1.8+)

- Each condition has a single flat rule list (`matches: [MapRule]`); no `kind` field or partition.
- All ops (`unit-suffix`, `equals`, `contains`) coexist in one list; evaluation order = list order, first match wins.
- `unit-suffix` rows lock the output to `$MATCH` (sentinel); switching to another op clears the output to `""`.
- JSON schema is version 6; migrator converts legacy `unit_suffix` (MatchSpec) and `token_map` ([MapRule]) from v5 and earlier.
- Regression tests: `V518ConditionUnifiedRulesMigrationTests` (7) + `V518ConditionUnifiedRulesRoundTripTests` (5) + `V515ConditionKindSwitchTests` (5).

---

## Auto-Sync Engine (v5.1.5 s6)

### Dual-Write on Save

- Every rule section save writes runtime first, then mirrors to `repositoryConfigDir` from `.repo_pointer.json`.
- Mirror failure is non-fatal: save succeeds, yellow triangle appears on the affected sidebar section.
- Mirror write creates parent directories if absent; backs up old mirror content before overwriting.
- `DualWriteOutcome`: `.runtimeOnly` / `.mirrored` / `.mirrorFailedRuntimeOk(reason:)`.

### Reverse Sync on Startup

- On app launch, compares SHA-256 hashes of each of the 5 rule files between mirror and runtime.
- If mirror differs: decode-check first (H5 guard — rejects corrupt or mismatched schema), then backup runtime and write mirror content.
- Returns `.healthy` (no diff or all synced) / `.skipped` (no pointer) / `.degraded(failedFiles:reason:)` (one or more files couldn't sync).
- Degraded state shows a dismissable orange banner in the Rules Panel sidebar; `reloadCached` is called after sync.

### Repository Pointer

- `.repo_pointer.json` in runtime config dir; version==1, `repository_config_dir` + `repo_root` fields required.
- Identity checks: `repo_root` must exist as a directory containing `.git`; `repository_config_dir` must be under `repo_root`.
- Auto-write on first cold dev start: walks up 12 levels from Bundle looking for `Sources/SpinLabApp/config` + `.git`.
- Auto-write is skipped in test environments (`RulesConfigPaths.isRunningTests()`).

### Test Coverage

- 20 engine tests: dual-write, mirror failure stubs, backup behavior, pointer parsing edge cases.
- 12 startup tests: consistent state, cold start, runtime diff, absent mirror file, H5 decode reject, identity check fail, corrupt JSON.

---

## Startup Bootstrap & Registry Retirement (v5.1.5 s7)

### Bootstrapper

- `RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()` runs on every app launch.
- Per-file atomic seed: only missing files are written; existing files are never touched.
- Replaces `RulesMigration` (full migration pipeline retired).

### Workflow Registry Retirement

- `WorkflowRegistryRetirementService.runIfNeeded()` runs once on first launch after upgrade.
- Detects outer `workflow_registry.json` (legacy location, one level above `config/`); if absent → no-op.
- Merge logic: same ID → update `displayName` + `conditionFieldIDs`, preserve `matchRules`; registry-only ID → append with empty `matchRules`.
- Failure safe: decode errors back up registry and leave `workflow.json` unchanged.
- After merge the outer registry is retired (deleted).

### Workbench Workflow List (Read-Only)

- `WorkbenchFeatureStore` reads workflow definitions from `config/workflow.json` via `WorkflowDefinitionStore`.
- All CRUD methods for workflows removed; workflow definitions are managed exclusively via the Rules Panel.
- `WorkflowRegistryView` is a read-only list + summary with a jump-to-rules-panel button.

### Test Coverage

- 3 bootstrapper tests: seed all, seed partial, idempotent.
- 4 retirement tests: same-ID merge, registry-only append, decode-failure backup, second-startup no-op.
- 4 workbench read-only tests: load from JSON, route to workflow, empty file no crash, CRUD absence guard.

---

## Rules Panel Tests (v5.1.5)

36 tests across 5 suites: `V515RulesPanelStoreTests`, `V515RulesPanelSaveValidationTests`, `V515RulesPanelCrossSectionTests`, `V515RulesSaveImmediateEffectTests`, `V515RulesEngineRegressionTests`. Also: `V515RulesBootstrapperMigrationTests`, `V515RulesSyncStartupTests`.

---

## Code Map

- `Sources/SpinLabApp/Features/RulesPanel/RulesManagementStore.swift` — Rules Panel state; section lifecycle; save/discard; dirty tracking
- `Sources/SpinLabApp/Features/RulesPanel/RulesPanelView.swift` — top-level Rules Panel window UI
- `Sources/SpinLabApp/Features/RulesPanel/RulesPanelSection.swift` — section enum; allCases canonical iteration order
- `Sources/SpinLabApp/Features/RulesPanel/RulesSectionShell.swift` — per-section shell with save/discard buttons
- `Sources/SpinLabApp/Features/RulesPanel/SectionPersistenceStrategy.swift` — section read/write strategy abstraction
- `Sources/SpinLabApp/Features/RulesPanel/Sections/WorkflowSection.swift` — Workflow section UI; conditionFieldIDs multi-select
- `Sources/SpinLabApp/Features/RulesPanel/Sections/MeasuringConditionSection.swift` — Measuring Condition section UI; unified rule list editor
- `Sources/SpinLabApp/Features/RulesPanel/Sections/SampleIdentificationSection.swift` — Sample Identification section UI; v4 substrate schema editor
- `Sources/SpinLabApp/Features/RulesPanel/Sections/ImportFiltersSection.swift` — Import Filters section UI
- `Sources/SpinLabApp/Features/RulesPanel/Sections/FilenameTokenizationSection.swift` — Filename Tokenization section UI
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper.swift` — seeds missing runtime files from bundle on launch
- `Sources/SpinLabApp/Import/Rules/WorkflowRegistryRetirementService.swift` — one-time legacy registry retirement
- `Sources/SpinLabApp/Import/Rules/RulesConfigPaths.swift` — config file path resolution; test environment detection
- `Sources/SpinLabApp/Import/Rules/SpinLabRuleProvider.swift` — rule loading abstraction backing RuleLoader
- `Sources/SpinLabApp/Import/Rules/RuleCanonicalizer.swift` — rule normalization and compilation
- `Sources/SpinLabApp/Import/Rules/RulesPersistenceHook.swift` — post-save persistence hook wiring
- `Sources/SpinLabApp/Import/Rules/RuleRef.swift` — rule reference model
- `Sources/SpinLabApp/Storage/RulesSyncEngine.swift` — dual-write engine and reverse sync on startup
- `Sources/SpinLabApp/Domain/Capabilities/RuleProviding.swift` — capability protocol abstracting RuleLoader cache-reload and version-bump operations across regions <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Domain/Capabilities/AuditLogging.swift` — capability protocol abstracting AuditLogger import and rule-write event logging <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Features/RulesPanel/MeasuringConditionRuleProjection.swift` — pure stateless projections for measuring condition rules: normalize rules with standardUnit handling and derive unit picker options
- `Sources/SpinLabApp/Features/RulesPanel/Components/MatchRulesEditor.swift` — interactive rule match condition editor component
- `Sources/SpinLabApp/Features/RulesPanel/Components/RuleExpandableRow.swift` — expandable row shell shared by all five rule sections (collapse/expand, header click area, dead-zone fix)
- `Sources/SpinLabApp/Features/RulesPanel/Components/RegexField.swift` — regex pattern input field with live validation feedback
- `Sources/SpinLabApp/Features/RulesPanel/Components/RulesPanelErrorMatching.swift` — visualizes rule error matching state in the rules panel
- `Sources/SpinLabApp/Features/RulesPanel/Components/SaveErrorsBadge.swift` — badge displaying count of unsaved rule errors
