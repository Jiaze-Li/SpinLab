# Feature Invariants & Test Status

Status: active
Last updated: v5.0.0

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
- Apply: currently disabled. Target contract in `01_PRODUCT_RULES.md` (per-file, atomic rollback)
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

### Measurement Search
- Workbench fields must use sidecar condition names, never invent new variable names
- Search accepts old ("A"/"B") and new ("ahe"/"3w") IDs as query aliases; persisted data uses new IDs only

### Plot Canvas (all workflows)
- Plot canvas is a workflow-independent shell — legend, edit, interaction behaviors apply uniformly
- Stack offset range default: 0...1.6 unless user specifies otherwise

### 3-Omega AHE
- Fit ranges are part of scaling chart semantic identity — different fit configs produce separate chart entries, not overwrites
- Test: unit tests on fit logic, plot payload construction, data parsing

### AMR/PHE
- Tag normalization: AMR → R_xx, PHE → R_xy
- Same plot canvas shell as 3-Omega

### XY Rotation
- Tag normalization: XY_90shift → workflow=XY + angle_shift=+90deg
- Test: unit tests on XY data parsing

### Extension System
- Extensions must NOT import Features/ or App/ modules
- Extensions depend only on Domain types and ExtensionPoints protocol contracts
- New measurement types: add to domain enum first, then implement in extension

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

### Disclosure Sections
- Full-width hit area on header row, not just chevron
- Collapsed visual state must match persisted state

### Interaction Persistence
- ViewModel syncs with AppState via explicit restoreInteractionState() / persistInteractionState() only
- No property observers or reactive pipelines for auto-sync

### Audit Logging
- Both edit-confirm and archive-apply actions logged
- Append-only, never modified retroactively
