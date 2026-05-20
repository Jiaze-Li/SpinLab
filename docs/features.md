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
- Sample IDs may be extracted from glued filename tokens when the token contains a valid `PN/PT/SL` prefix plus digits, e.g. `20260430140313PN80` → `PN80`
- Sample/substrate tokenization preserves whitespace delimiters; spaced numeric units are compacted only for condition parsing
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
- Library publish action is a shell-out trigger only: `public to html` runs `scripts/publish_web_library.sh`, which exports, validates, and then publishes the separate `SpinLab-Web-Library` repo snapshot; the app UI shows only high-level publish status by default and keeps full script logs behind a failure disclosure
- Web Library export summary strip keeps only Batches, Samples, Charts, and Chart size; schema appears as a low-priority title badge, and forced export appears only as a warning badge when enabled
- Source-of-truth details: [`docs/web_library.md`](web_library.md)

### Web Library UI Source of Truth
- Web Library UI source lives in SpinLab, currently inside `Resources/WebLibraryTemplate/`
- Generated output lives in `../SpinLab-Web-Library/public/`
- Never treat `../SpinLab-Web-Library/public/` as the source of truth
- To change Web Library UI, edit `Resources/WebLibraryTemplate/`
- Do not manually edit `../SpinLab-Web-Library/public/app.js` or `styles.css` as the primary fix
- After changing the exporter, run `./scripts/publish_web_library.sh` to regenerate and publish
- `../SpinLab-Web-Library/public/` is disposable generated output and may be replaced on every publish
- If templates later move again, that directory becomes the source of truth; until then, `Resources/WebLibraryTemplate/` remains authoritative

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
- Workbench fields must use sidecar condition names, never invent new variable names.
- Search returns file list only; no auto-loading of artifacts or auto-analysis on search completion.
- Details: [`MEASUREMENT_SEARCH.md`](architecture/workbench/MEASUREMENT_SEARCH.md)

### Plot Canvas (all workflows)
- Plot canvas is a workflow-independent shell — legend, edit, interaction behaviors apply uniformly.
- Stack offset range default: `0...1.6` unless user specifies otherwise.
- Curve drag-to-reorder is opt-in via `seriesReorderable` payload flag (currently: 3ω stacked charts only).
- Tests: `V531SeriesRenderModeTests`, `V534LegendDimensionResolverTests`, `V535PointLabelVisibilityTests`, `V535CopyPNGScaleMenuTests`, `V536CurveDragOrderTests`
- Details: [`PLOT_CANVAS.md`](architecture/workbench/PLOT_CANVAS.md)

### Workflow Contracts (3-Omega AHE / AMR-PHE / XY Rotation)
- 3ω: fit ranges are part of scaling chart semantic identity — different fit configs produce separate chart entries, not overwrites.
- AMR/PHE: tag normalization AMR → R_xx, PHE → R_xy.
- XY Rotation: tag normalization XY_90shift → workflow=XY + angle_shift=+90deg.
- Details: [`WORKFLOW_CONTRACTS.md`](architecture/workbench/WORKFLOW_CONTRACTS.md), [`THREE_OMEGA_PHYSICS.md`](architecture/workbench/THREE_OMEGA_PHYSICS.md)

### Extension System
- Extensions must NOT import Features/ or App/ modules.
- Extensions depend only on Domain types and ExtensionPoints protocol contracts.
- Details: [`EXTENSION_BOUNDARIES.md`](architecture/workbench/EXTENSION_BOUNDARIES.md)

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
- Measuring Condition unified rule list (v5.1.8+): flat `matches: [MapRule]`, no `kind` partition, schema v7
- `$MATCH` output: all ops return raw matched token verbatim — no normalization in any path (v5.1.9+)
- Per-condition standardization (v5.1.9+): optional standard unit + per-row transform expression (implicit-left-value: `*1000` = value×1000, `-273` = value−273) + precision rounding; transform ignored when standard unit is nil
- v6→v7 migration: adds `standardization` object and `transform: null` to all rules; bootstrapper gate at schema v7
- Legacy unit normalization (halfStep / trimNoise) fully deleted in v5.1.9
- Test coverage: 36 + 20 + 12 + 3 + 4 + 4 + 44 tests across suites — see `RULES_AUTHORING.md`

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
