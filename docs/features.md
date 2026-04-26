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
- Audit log maintained under Library Root and App Support (append-only)
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
- Right-click Copy PNG copies rendered chart to clipboard (v5.3.1)
- Chart style settings stored in styleParams, parsed via WorkbenchChartStyle (v5.3.1)
- Legend dimension auto-inference: data-driven priority chain resolves which metadata dimension distinguishes series (temperature > substrate = energy = pressure > thickness). Ambiguous or indeterminate cases produce warnings. (v5.3.4)
- Legend-visual consistency: stacked charts guarantee legend top entry = visually highest curve. Controlled by reverseSeriesForLegend flag on payload, applied uniformly in render pipeline. (v5.3.4)
- Test: V531SeriesRenderModeTests — Codable migration, ChartStyle parsing, axis alignment
- Test: V534LegendDimensionResolverTests — resolver priority, tolerance, ambiguity, pipeline reversal, backward decode

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

### Section Structure (s4+ schema)
- 5 sections: Import Filters, Filename Tokenization, Sample Identification, Workflow, Measuring Condition
- UI rewrite pending (s5) — current panel still loads from legacy v2 paths until s5 ships

### Validation
- Sample ID: each pattern validated as NSRegularExpression; invalid compile = Save disabled
- Workflow Match: cross-rule token conflicts detected at save time
- Filename Parse: conditionDefinition ids must be unique; binding auto-derived from kind + id
- Substrate: regex field in orientationPattern validated inline
