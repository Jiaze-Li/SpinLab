# Inbox Rules Authoring Layer

Rules Panel is the user-facing configuration surface for Inbox routing. It owns five required JSON config files that collectively govern how filenames are parsed, samples identified, channels mapped to workflows, and measurement conditions extracted. A sixth optional file governs Library registry parsing.

---

## 5+1 Section Structure

Required sections: Import Filters / Filename Tokenization / Sample Identification / Workflow / Measuring Condition.

Optional section: **Registry Import** — backed by `library_import_rules.json`. Absent when the file is not present; editing produces the file. Does not affect `.ready` / `.incompleteBook` panel state.

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

## Rules Book Single Source of Truth (rules-book-single-source-of-truth branch)

### Architecture

- One external Rules Book directory configured by the user is the sole source of truth. No Application Support auto-resolution, no bundle fallback in normal operation, no dual-write mirror to `Sources/SpinLabApp/config/`.
- `RulesBookSettings` persists the chosen book URL to `~/Library/Application Support/SpinLab/rules_book.json`.
- `RulesManagementStore` receives `rulesBookPaths: RulesConfigPaths?` at init; nil → `.notConfigured` state.
- `RuleLoader.configure(bookPaths:internalPaths:)` must be called at startup after `RulesBookSettings` is ready.

### Panel States

- `.notConfigured`: panel shows "Select Rules Book Folder" button; editing is blocked.
- `.incompleteBook([String])`: configured but missing required files; panel lists them; editing blocked.
- `.ready`: all 5 required files present; full editor shown. Registry Import section shows "not configured" state independently when `library_import_rules.json` is absent.

---

## Startup Bootstrap & Registry Retirement (v5.1.5 s7)

### Bootstrapper

- `RulesBootstrapper.migrateRulesBookIfNeeded(paths:internalPaths:)` runs on first launch with a configured Rules Book.
- Migration state (`.migration_state.json`, `.migration_failed.json`) stored in `AppInternalPaths` (Application Support), not in the book directory itself.
- Seed step (`seedMissingRuntimeFilesFromBundleIfNeeded`) deleted for the 5 required files; the user is expected to seed from the existing `Sources/SpinLabApp/config/` manually or via the first-run flow.
- `RulesBootstrapper.seedLibraryImportRulesIfNeeded(paths:)` seeds `library_import_rules.json` from the bundle on each startup: copies if absent, merges missing fields if partial, skips if corrupt (no fallback).

### Workflow Registry Retirement

- `WorkflowRegistryRetirementService.runIfNeeded()` runs once on first launch after upgrade.
- Detects outer `workflow_registry.json` (legacy location, one level above `config/`); if absent → no-op.
- Merge logic: same ID → update `displayName` + `conditionFieldIDs`, preserve `matchRules`; registry-only ID → append with empty `matchRules`.
- Failure safe: decode errors back up registry and leave `workflow.json` unchanged.
- After merge the outer registry is retired (deleted).

### Workbench Workflow List (Read-Only)

- `WorkbenchFeatureStore` reads workflow definitions from `config/workflow.json` via `WorkflowDefinitionStore`.
- All CRUD methods for workflows removed; workflow definitions are managed exclusively via the Rules Panel.

### Test Coverage

- 4 retirement tests: same-ID merge, registry-only append, decode-failure backup, second-startup no-op.
- 4 workbench read-only tests: load from JSON, route to workflow, empty file no crash, CRUD absence guard.

---

## Rules Panel Tests (v5.1.5)

36 tests across 5 suites: `V515RulesPanelStoreTests`, `V515RulesPanelSaveValidationTests`, `V515RulesPanelCrossSectionTests`, `V515RulesSaveImmediateEffectTests`, `V515RulesEngineRegressionTests`. Also: `V515RulesBootstrapperMigrationTests`.

## Registry Import Tests (v5.4.1)

29 tests across 3 suites: `V541LibraryRegistryBootstrapperTests` (seed/repair), `V541LibraryRegistryFallbackRemovalTests` (no-fallback invariant), `V541LibraryRegistryRulesPanelTests` (load/edit/save round-trip). No-fallback invariant: when `library_import_rules.json` is absent, all registry alias lookups return empty — no hardcoded fallback values anywhere in the runtime path.

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
- `Sources/SpinLabApp/Features/RulesPanel/Sections/LibraryRegistrySection.swift` — Registry Import section UI; alias list editors + numeric/metadata key map editors
- `Sources/SpinLabApp/Import/Rules/LegacyRegistryImportRulesDefaults.swift` — seed/repair helper for `library_import_rules.json`; never used in runtime lookup
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+LibraryRegistrySeed.swift` — seeds/merges `library_import_rules.json` on startup
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper.swift` — type declaration shell for the migration and seed namespace
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+MigrationOrchestration.swift` — coordinates full schema migration: reads runtime JSONs, applies all migration steps, atomic-writes results
- `Sources/SpinLabApp/Storage/AppInternalPaths.swift` — resolves Application Support paths for internal state files (migration state, rules book pointer, rule set version)
- `Sources/SpinLabApp/Storage/RulesBookSettings.swift` — persists the user-configured Rules Book URL; exposes `rulesBookPaths` and `rulesBookState`
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+MeasuringConditionMigration.swift` — migrates measuring_condition.json from v1 through v7
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+SampleIdentificationMigration.swift` — migrates sample_identification.json from v1 through v5
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+WorkflowMigration.swift` — migrates workflow.json from v1 through v3
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+MigrationFiles.swift` — writes migration state, failure, and SHA files to disk
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapper+MigrationHelpers.swift` — shared legacy match-spec expansion used by measuring_condition and workflow migrations
- `Sources/SpinLabApp/Import/Rules/RulesBootstrapperVerificationModels.swift` — decodable verification structs for post-migration decode-verify step
- `Sources/SpinLabApp/Import/Rules/WorkflowRegistryRetirementService.swift` — one-time legacy registry retirement
- `Sources/SpinLabApp/Import/Rules/RulesConfigPaths.swift` — config file path resolution; test environment detection
- `Sources/SpinLabApp/Import/Rules/SpinLabRuleProvider.swift` — rule loading abstraction backing RuleLoader
- `Sources/SpinLabApp/Import/Rules/RuleCanonicalizer.swift` — rule normalization and compilation
- `Sources/SpinLabApp/Import/Rules/RulesPersistenceHook.swift` — post-save persistence hook wiring
- `Sources/SpinLabApp/Import/Rules/RuleRef.swift` — rule reference model
- `Sources/SpinLabApp/Domain/Capabilities/RuleProviding.swift` — capability protocol abstracting RuleLoader cache-reload and version-bump operations across regions <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Domain/Capabilities/AuditLogging.swift` — capability protocol abstracting AuditLogger import and rule-write event logging <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Domain/Capabilities/AppLogging.swift` — general-purpose injectable logging capability abstracting AppLogger info/warning/error <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Features/RulesPanel/MeasuringConditionRuleProjection.swift` — pure stateless projections for measuring condition rules: normalize rules with standardUnit handling and derive unit picker options
- `Sources/SpinLabApp/Features/RulesPanel/Components/MatchRulesEditor.swift` — interactive rule match condition editor component
- `Sources/SpinLabApp/Features/RulesPanel/Components/RuleExpandableRow.swift` — expandable row shell shared by all five rule sections (collapse/expand, header click area, dead-zone fix)
- `Sources/SpinLabApp/Features/RulesPanel/Components/RegexField.swift` — regex pattern input field with live validation feedback
- `Sources/SpinLabApp/Features/RulesPanel/Components/RulesPanelErrorMatching.swift` — visualizes rule error matching state in the rules panel
- `Sources/SpinLabApp/Features/RulesPanel/Components/SaveErrorsBadge.swift` — badge displaying count of unsaved rule errors
