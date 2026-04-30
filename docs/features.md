# Feature Invariants & Test Status

Status: active
Last updated: v5.5.2

This file records business invariants that are not obvious from code alone.
For full behavior details, see the linked specs.

---

## Inbox

Behavior details: `specs/01_PRODUCT_RULES.md`, `docs/architecture/inbox/`

### Import Pipeline
- Parse stage must never make routing decisions (strict pipeline boundary)
- Parsed metadata is suggestion-only until user confirms
- Duplicate filenames in queue: append sequence, never silently overwrite
- Test: extensive unit tests on parse/route/match/evaluate stages

### Confirm & Apply
- Apply: per-file atomic archive with rollback, sidecar generation, and audit logging
- Apply All: skips review-required items, processes only library-matched
- Save-gated mapping (no live remap on keystroke) is deliberate
- Test: drawer matching unit tests; draft persistence integration tests; see `docs/architecture/inbox/CONFIRM_AND_APPLY.md`

### Registry
- Prefix-to-sheet mapping is display metadata only, not the lookup routing key
- Registry lookup rules live in dedicated rulebook layer, not mixed with routing

### Queue Management
- Clear Imports must never touch files already archived into Library drawers
- Clear Imports only affects pending queue and unarchived managed temp files

---

## Library

Behavior details: `specs/01_PRODUCT_RULES.md`, `docs/architecture/library/`

### Browse
- All views use AppColumnShell, never raw HSplitView
- Detail section order is fixed; see `docs/architecture/library/BROWSE_AND_SELECTION.md`

### Metadata Editing
- Edits go through LibrarySampleEditService, never direct repository writes from views
- User-defined display names must never be renamed by AI or automated processes
- Edit transaction model and registry sync details: `docs/architecture/library/SAMPLE_METADATA_EDITING.md`

### Registry Sync
- One-way: XLSX registry → Library drawers (tag alignment, not destructive replacement)
- Apply operations are atomic with rollback

### Storage
- Filesystem sync direction: filesystem → app state, never the reverse
- Once archived, records must not be silently modified; App Support is canonical source of truth
- Audit log: append-only; unreadable existing log blocks write (no overwrite)
- Sidecar schema (canonical): `docs/architecture/inbox/OUTPUT_CONTRACTS.md`; Library reading behavior: `docs/architecture/library/SIDECAR_AND_CONDITIONS.md`
- Storage and sync details: `docs/architecture/library/ARCHIVE_STORAGE.md`

---

## Workbench

Behavior details: `docs/architecture/workbench/INDEX.md`

### Shell Architecture
- Shell-driven lifecycle: Search → Select → Analyze (sole trace commit point) → Save. Restore/rerender paths never commit trace.
- `PackResult` must include `ingestionResult` so restore can rerender without re-ingestion.
- New workflows must use the shell, not standalone views.
- Warning log coalesces identical (source, message) pairs — reruns never stack duplicates.
- Details: [`SHELL_AND_LIFECYCLE.md`](architecture/workbench/SHELL_AND_LIFECYCLE.md)

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

## Rules Panel

Architecture details: `docs/architecture/inbox/RULES_AUTHORING.md`

### Key Invariants
- Entry: "Rules" button in Inbox Operations header → opens separate window via `openWindow(id: "spin-rules")`
- 5 sections: Import Filters / Filename Tokenization / Sample Identification / Workflow / Measuring Condition
- **R1**: rules changes are live in `RuleLoader.shared` before `onRulesSaved` fires — no restart needed
- Hash precondition on save: external file modification → `externalConflict`; user must Reload or Override
- Closing with unsaved edits → 3-option alert: Discard Changes / Cancel / Save All
- Dual-write on save mirrors to repo config dir; reverse sync on startup restores from mirror when they differ
- Bootstrapper: seeds only missing files; idempotent; never touches existing files
- `WorkflowRegistryView`: read-only; all workflow CRUD managed via Rules Panel only
- Match op per-context: `starts-with` only in Batch ID Prefixes; `unit-suffix` only in Measuring Condition
- Measuring Condition unified rule list (v5.1.8+): flat `matches: [MapRule]`, no `kind` partition, schema v6
- Test coverage: 36 + 20 + 12 + 3 + 4 + 4 tests across suites — see `RULES_AUTHORING.md`

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

