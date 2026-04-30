# Feature Invariants & Test Status

Status: active
Last updated: v5.1.5

This file records business invariants that are not obvious from code alone.
For full behavior details, see the linked specs.

---

## Inbox

Behavior details: `specs/05_INBOX_DEPOSIT_UI_SPEC.md`, `specs/01_PRODUCT_RULES.md`

### Import Pipeline
- Parse stage must never make routing decisions (strict pipeline boundary)
- Parsed metadata is suggestion-only until user confirms
- Duplicate filenames in queue: append sequence, never silently overwrite
- Test: extensive unit tests on parse/route/match/evaluate stages

### Confirm & Draft
- Drawer matching: token-coverage, exactly one candidate = match, else unresolved (`?`)
- File-level sample info can fill missing channel sample, but channel-to-channel cross-completion is forbidden
- Route unresolved metadata alone does not force Review Required when final drawer mapping is unique and valid
- Save-gated mapping (no live remap on keystroke) is deliberate
- Apply: implemented. Per-file atomic archive with rollback, sidecar generation, and audit logging. Supports single-file and Apply All scopes (Apply All skips review-required items)
- Test: drawer matching unit tests; draft persistence integration tests

### Registry
- Prefix-to-sheet mapping is display metadata only, not the lookup routing key
- Registry lookup rules live in dedicated rulebook layer, not mixed with routing

### Queue Management
- Clear Imports must never touch files already archived into Library drawers
- Clear Imports only affects pending queue and unarchived managed temp files

### Layout
- Right column intentionally blank (reserved for future modules)

---

## Library

Behavior details: `specs/01_PRODUCT_RULES.md`, `specs/04_UI_RULES.md`

### Browse
- All views use AppColumnShell, never raw HSplitView
- Left column width persisted via @AppStorage
- Detail section order is fixed (see `04_UI_RULES.md`)
- Test: library store and index loading tested

### Metadata Editing
- Edits go through LibrarySampleEditService, never direct repository writes from views
- User-defined display names must never be renamed by AI or automated processes

### Registry Sync
- One-way: XLSX registry → Library drawers (tag alignment, not destructive replacement)
- Apply operations are atomic with rollback

### File Sync
- Direction: filesystem → app state, never the reverse

### Archive
- Once archived, records must not be silently modified
- Internal archive (App Support) is canonical source of truth
- Audit log maintained under Library Root and App Support (append-only); if log file exists but cannot be read, write is skipped to prevent overwrite
- Required sidecar fields: version, source_file, sample_key, workflow, conditions, channel_bindings, normalized_tags, raw_tags, applied_at

---

## Workbench

Behavior details: `specs/three_omega_physics.md`

### Shell Architecture (v5.3.4)
- All workflow workspaces use `WorkflowWorkspaceShell` — a single generic two-column container that owns shared UI (search, action bar, results list, plot canvas, trace, warnings)
- Workflow-specific content injected via 4 ViewBuilder slots: `searchExtra`, `plotControls`, `leftExtra`, `rightExtra`
- Workspace stores conform to `WorkbenchWorkspaceProviding` protocol — unified contract for selection, analysis, trace, persistence
- Shell-driven lifecycle: Search → Select → Analyze (sole trace commit point) → Save. Restore/rerender paths never commit trace.
- Pack load restores `ingestionResult` from persisted `PackResult`, then rerenders without re-ingestion
- Invariant: new workflows must use the shell, not standalone views
- Warning panel uses a shell-level `WorkbenchWarningLog` container that coalesces identical (source, message) pairs. Reruns of analyze / load / scaling never stack duplicate entries. New workflows inherit the rule via `WorkbenchWorkspaceProviding`. (v5.3.5)

### Measurement Search
- Workbench fields must use sidecar condition names, never invent new variable names
- Search accepts old ("A"/"B") and new ("ahe"/"3w") IDs as query aliases; persisted data uses new IDs only
- Search returns file list only; no auto-loading of artifacts or auto-analysis on search completion

### Plot Canvas (all workflows)
- Plot canvas is a workflow-independent shell — legend, edit, interaction behaviors apply uniformly
- Stack offset range default: 0...1.6 unless user specifies otherwise
- Series render mode (line/scatter/line+scatter) selectable per workflow, applied uniformly to all series (v5.3.1)
- Chart title is not bold (v5.3.1)
- Axis titles (x/y) centered on plot drawing area, not full image (v5.3.1)
- Font sizes (title, axis, tick, legend) and tick density (x/y) configurable via Chart Style disclosure panel (v5.3.1)
- Right-click → Copy PNG submenu: 1x / 2x / 3x scale options. 2x reuses cached imageData (fast path); 1x/3x re-render via pipeline. (v5.3.5)
- Chart style settings stored in styleParams, parsed via WorkbenchChartStyle (v5.3.1)
- Point labels (scatter series): font size configurable via tap on label; tap on dot toggles label visibility per-point, persists across Pack save/load. (v5.3.5)
- Legend dimension auto-inference: data-driven priority chain resolves which metadata dimension distinguishes series (temperature > substrate = energy = pressure > thickness). Ambiguous or indeterminate cases produce warnings. (v5.3.4)
- Legend-visual consistency: stacked charts guarantee legend top entry = visually highest curve. Controlled by reverseSeriesForLegend flag on payload, applied uniformly in render pipeline. (v5.3.4)
- Test: V531SeriesRenderModeTests — Codable migration, ChartStyle parsing, axis alignment
- Test: V534LegendDimensionResolverTests — resolver priority, tolerance, ambiguity, pipeline reversal, backward decode
- Test: V535PointLabelVisibilityTests, V535TabRenderStatePackTests, V535ScopeGateTests — point label toggle logic, Pack Codable, payload-capability gate
- Test: V535CopyPNGScaleMenuTests — scale array alignment, output pixel dimensions, 2x determinism
- Curve drag-to-reorder (opt-in, 3ω stacked R(1ω)/R(3ω) charts): drag a curve in the legend area pans all curves; drag outside legend hits a specific curve and reorders it. Guide line shows target position during drag. Right-click → Reset Curve Order returns to default. Order persists in AnalysisPack save/load. Canvas capability gated per chart via `seriesReorderable` flag in payload. (v5.3.6)
- Test: V536CurveDragOrderTests — alignSeriesOrder, TabRenderState Codable, pipeline mismatch detection, hitTestSeries hit/miss/nil-id

### 3-Omega AHE
- Fit ranges are part of scaling chart semantic identity — different fit configs produce separate chart entries, not overwrites
- Test: unit tests on fit logic, plot payload construction, data parsing

### AMR/PHE
- Tag normalization: AMR → R_xx, PHE → R_xy
- Same plot canvas shell as 3-Omega

### XY Rotation
- Tag normalization: XY_90shift → workflow=XY + angle_shift=+90deg
- Default y-axis title: Rxx tab → "Rxx (Ω)", Rxy tab → "Rxy (Ω)" — stacked/center info not shown in title (v5.3.1)
- Optional auxiliary line at x=180 (toggle in plot controls) (v5.3.1)
- Test: unit tests on XY data parsing

### Extension System
- Extensions must NOT import Features/ or App/ modules
- Extensions depend only on Domain types and ExtensionPoints protocol contracts
- New measurement types: add to domain enum first, then implement in extension

---

## Rules Panel (v5.1.5)

Architecture details: `docs/history/v515_s5_rules_panel_rewrite.md`

### 5-Section Structure
- Sections: Import Filters / Filename Tokenization / Sample Identification / Workflow / Measuring Condition
- Each section maps 1:1 to a JSON config file under `RulesConfigPaths`
- `RulesPanelSection.allCases` order is the canonical Save All iteration order — never use Set iteration

### Save Behavior
- Save button writes only the active section; Save All iterates allCases filtered by dirtySections
- Hash precondition: file hash captured at open-time; mismatch on save → externalConflict (never silent overwrite)
- After save: RuleLoader cache updated → onRulesSaved callback fires → persistence hook fires (in that order)
- R1 invariant: rules changes are live in RuleLoader.shared *before* onRulesSaved fires — no restart required

### Cross-Section Validation
- Workflow conditionFieldIDs are validated against dirty measuringConditionDraft (if dirty), else disk
- This means Save All works correctly even when workflow saves before measuringCondition

### availableConditionFieldIDs
- Derived from measuringConditionDraft.conditionDefinitions; refreshed on load and every updateMeasuringCondition call
- WorkflowSection reads this to populate conditionFieldIDs multi-select UI

### Test Coverage
- 36 tests across 5 suites: store lifecycle, per-field validation, cross-section contract, R1 gate, SharedSubstrate

---

## Rules Auto-Sync Engine (v5.1.5 s6)

Architecture details: `docs/history/v515_s6_auto_sync_engine.md`

### Dual-Write on Save
- Every rule section save writes runtime first, then mirrors to `repositoryConfigDir` from `.repo_pointer.json`
- Mirror failure is non-fatal: save succeeds, yellow triangle appears on the affected sidebar section
- Mirror write creates parent directories if absent; backs up old mirror content before overwriting
- `DualWriteOutcome`: `.runtimeOnly` / `.mirrored` / `.mirrorFailedRuntimeOk(reason:)`

### Reverse Sync on Startup
- On App launch, compares SHA-256 hashes of each of the 5 rule files between mirror and runtime
- If mirror differs: decode-check first (H5 guard — rejects corrupt or mismatched schema), then backup runtime and write mirror content
- Returns `.healthy` (no diff or all synced) / `.skipped` (no pointer) / `.degraded(failedFiles:reason:)` (one or more files couldn't sync)
- Degraded state shows a dismissable orange banner in the Rules Panel sidebar; reloadCached is called after sync

### Repository Pointer
- `.repo_pointer.json` in runtime config dir; version==1, `repository_config_dir` + `repo_root` fields required
- Identity checks: `repo_root` must exist as a directory containing `.git`; `repository_config_dir` must be under `repo_root`
- Auto-write on first cold dev start: walks up 12 levels from Bundle looking for `Sources/SpinLabApp/config` + `.git`
- Auto-write is skipped in test environments (`RulesConfigPaths.isRunningTests()`)

### Test Coverage
- 20 engine tests: dual-write, mirror failure stubs, backup behavior, pointer parsing edge cases
- 12 startup tests: consistent state, cold start, runtime diff, absent mirror file, H5 decode reject, identity check fail, corrupt JSON

---

## Rules Startup Bootstrap & Registry Retirement (v5.1.5 s7)

### Bootstrapper
- `RulesBootstrapper.seedMissingRuntimeFilesFromBundleIfNeeded()` runs on every App launch
- Per-file atomic seed: only missing files are written; existing files are never touched
- Replaces `RulesMigration` (full migration pipeline retired)

### Workflow Registry Retirement
- `WorkflowRegistryRetirementService.runIfNeeded()` runs once on first launch after upgrade
- Detects outer `workflow_registry.json` (legacy location, one level above `config/`); if absent → no-op
- Merge logic: same ID → update `displayName` + `conditionFieldIDs`, preserve `matchRules`; registry-only ID → append with empty `matchRules`
- Failure safe: decode errors back up registry and leave `workflow.json` unchanged
- After merge the outer registry is retired (deleted)

### Workbench Workflow List (read-only)
- `WorkbenchFeatureStore` reads workflow definitions from `config/workflow.json` via `WorkflowDefinitionStore`
- All CRUD methods for workflows removed; workflow definitions are managed exclusively via the Rules Panel
- `WorkflowRegistryView` is now a read-only list+summary with a jump-to-rules-panel button

### Test Coverage
- 3 bootstrapper tests: seed all, seed partial, idempotent
- 4 retirement tests: same-ID merge, registry-only append, decode-failure backup, second-startup no-op
- 4 workbench read-only tests: load from JSON, route to workflow, empty file no crash, CRUD absence guard

---

## Shared

Behavior details: `specs/04_UI_RULES.md`

### App Shell
- Never use raw HSplitView with hardcoded frames — use AppColumnShell
- Critical workflow actions stay in center column, not right column

### Navigation
- Navigation state is a global concern owned by AppState, not FeatureStores

### Hover Popover (v4.1.19+)
- Must use `.hoverPopover()` modifier, never custom hover/dismiss implementations
- Parameters standardized: showDelay 1s, dismissDelay 500ms

### Button Style Convention (v5.5.0+)
- `.borderedProminent`: primary / commit actions (Analyze, Save, Apply, Confirm)
- `.bordered`: secondary actions (Clear, Revert, Export, Done, navigation-style actions)
- `.borderless`: inline actions within lists or compact panels (toggle, delete, field-level edit)
- `.plain`: icon-only buttons with no visible chrome (chevron sort, close, minimal toggle)
- Default (no explicit style): acceptable for secondary actions in macOS context (equivalent to `.bordered`)
- Destructive actions use `.bordered` with `.foregroundStyle(.red)`, not `.borderedProminent`

### Spacing Scale (v5.5.0+)
- All new layout spacing must use `AppSpacing` constants (defined in `UI/AppSpacing.swift`), never bare numeric literals
- Seven-level scale: `xxs`(2) → `xs`(4) → `sm`(6) → `md`(8) → `lg`(12) → `xl`(16) → `xxl`(24)
- Legacy values outside the scale (3, 10, 14, 20) should be migrated to the nearest scale value when surrounding code is next modified
- Adding a new spacing level requires updating `AppSpacing` first; ad-hoc one-off values are forbidden in new code

### Font Scale (v5.5.0+)
- All structural heading fonts must use `AppFontScale` constants (defined in `UI/AppFontScale.swift`), never inline font literals
- Three-level hierarchy: `sectionTitle` (.title2.bold) → `sectionHeader` (.title3.semibold) → `groupHeader` (.headline)
- Adding a new level requires updating `AppFontScale` first, then using the new constant
- Body/content fonts (.callout, .body, .caption) remain contextual and are not part of the heading scale
- Font minimum readability rule still applies: user-readable content must use `.callout` or larger; `.caption` only for supplementary metadata

### Disclosure Sections (v5.5.0+)
- All collapsible section headers must use `CollapsibleSectionHeader` component (defined in `UI/CollapsibleSectionHeader.swift`)
- Full-width hit area on header row, not just chevron (enforced by component's `.contentShape(Rectangle())`)
- Collapsed visual state must match persisted state
- Do not create new manual chevron+HStack implementations

### Interaction Persistence
- ViewModel syncs with AppState via explicit restoreInteractionState() / persistInteractionState() only
- No property observers or reactive pipelines for auto-sync

### Audit Logging
- Both edit-confirm and archive-apply actions logged
- Append-only, never modified retroactively

---

## Rules Panel (v5.1.5+)

Entry point: "Rules" button in Inbox Operations header row (opens separate Window via `openWindow(id: "spin-rules")`).

### Save Semantics
- Every section has Save + Discard buttons at both top and bottom of the scroll area
- Saving writes atomically to runtime config dir; triggers `RuleLoader.shared.reloadCached()` + routing re-parse
- Hash precondition check on save: if the file was modified externally since panel opened, save fails with `externalConflict` — user must choose Reload or Override
- Closing the window with unsaved edits triggers a three-option alert: Discard Changes / Cancel / Save All

### Section Structure (s10(2) v4 schema)
- 5 sections: Import Filters, Filename Tokenization, Sample Identification, Workflow, Measuring Condition

### Sample Identification — v4 substrate schema (s10(2))
- **Batch prefixes**: plain text prefixes (e.g., "PN", "PT"); replaces v3 regex `sampleId.patterns`
- **Substrate**: three unified lists — Materials, Treatments, Orientations — each an array of `SubstrateEntry {displayName, matches: [{type: equals|contains, value}]}`
  - `displayName` has an implicit `equals(normalize(displayName))` probe injected at compile time; no need to repeat it in `matches`
  - `matches` is OR-based; all probes are token-scoped
  - displayName uniqueness is not hard-enforced at save time; duplicate entries produce undefined matching behavior
- **"b" and "baked" are separate treatment entries**: "b" maps to `equals "b"`; "baked" maps to `contains "bake"`. Not aliases — intentional v4 behavioral separation
- **Origin treatment detection**: compile phase detects treatment entries whose `normalize(displayName)` or any match value normalizes to "o"; stored in `compiledOriginTreatmentDisplayNames`; no longer hardcoded to treatment id == "o"
- **Composite token behavior**: a token like "STO111" can simultaneously match a Material entry (STO) and an Orientation entry (111) via `contains` probes → two substrate tags emitted (["STO", "111"] not ["STO 111"]); this is an accepted behavioral change from v3
- **Runtime migration**: v3 sample_identification.json (with materials/treatments/orientations in old schema + substrateTagRules) is migrated to v4 on first app launch via `RulesBootstrapper`; backup written to `<config_dir>/.backup-<timestamp>/`

### Validation
- Sample ID: displayName uniqueness on substrate entries not enforced at save; user responsibility
- Workflow Match: cross-rule token conflicts detected at save time
- Filename Parse: conditionDefinition ids must be unique
- Workflow conditionFieldIDs: cross-validated against dirty measuringCondition draft (not just disk)

### Match Op Per-Context Restriction
- `starts-with`: only available in Batch ID Prefixes (SampleIdentification section)
- `unit-suffix`: only available in Measuring Condition
- `equals` / `contains`: available in all contexts
- All four ops are case-insensitive at runtime

### Measuring Condition — Unified Rule List (v5.1.8+)
- Each condition has a single flat rule list (`matches: [MapRule]`); no kind field or partition
- All ops (`unit-suffix`, `equals`, `contains`) coexist in one list; evaluation order = list order, first match wins
- `unit-suffix` rows lock the output to `$MATCH` (sentinel); switching to another op clears the output to ""
- JSON schema is version 6; migrator converts legacy `unit_suffix` (MatchSpec) and `token_map` ([MapRule]) from v5 and earlier
- Regression tests: `V518ConditionUnifiedRulesMigrationTests` (7) + `V518ConditionUnifiedRulesRoundTripTests` (5) + `V515ConditionKindSwitchTests` (5)
