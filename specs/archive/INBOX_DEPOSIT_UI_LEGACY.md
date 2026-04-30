# Inbox Deposit UI Spec

Status: historical (archived v5.5.2 — Inbox behavior rules now live in `specs/01_PRODUCT_RULES.md` + `specs/03_PARSER_ROUTING_RULES.md`; UI structure in `specs/04_UI_RULES.md` + `docs/features.md`. UI structural details should be read from code rather than maintained here.)

This document originally recorded the current Inbox design logic, UI flow, button semantics, and mapping behavior for deposit-to-drawer preparation. Reference-only.

## Design intent
- Keep Inbox primary operations in the center column.
- Use one continuous workflow: select pending file -> confirm mapping/tags -> save draft -> (future) apply.
- Minimize repeated information.
- Use explicit save-gate behavior for mapping refresh (no live remap while typing).

## Current shell behavior
- Left app shell column: global navigation.
- Center app shell column: Inbox active workspace (all current Inbox operations).
- Right app shell column: intentionally blank placeholder for future extension modules.

## Center column structure
### 1) Registry block
- `Registry Path`: current registry source path.
- `Load Registry`: open file panel and install/select registry.

### 2) File block
Contains three subareas:

1. `Actions`
- `Import Files`: import measurement files/folders into pending queue.
- `Recompute Route`: recompute parse/routing for all pending imports.
- `Clear Imports`: destructive clear for pending queue only (with confirm dialog).
- `Clear Imports` does not mutate archived/library drawer records.

2. `Pending Queue`
- Status cards (click-to-filter):
  - `Pending`
  - `Library Matched`
  - `Review Required`
- `File Path`: path for currently selected pending file.
- Pending list:
  - file name
  - pending status
  - route status text
  - routing draft saved indicator

3. `Selection Workbench`
- `Deposit Mapping`
- `File Tags`
- Draft action row: `Save Draft`, `Revert Draft`, `Apply`, `Apply All`.

## Selection Workbench details
### Deposit Mapping
Two modes:

1. File-level mapping
- One mapping row:
  - left: editable `Sample`
  - middle: arrow (`->`) for deposit direction
  - right: resolved `Drawer`
- `Channel Info` summary line below.

2. Channel-level mapping
- One mapping row per channel (`ch1`, `ch2`, ...):
  - left: editable `<channel> Sample`
  - middle: arrow (`->`)
  - right: resolved `Drawer`
- `Unresolved` summary shown when unresolved channels exist.

### File Tags
- Compact 2-column layout:
  - row 1: `Workflow` (editable), `Device` (editable)
  - row 2: `Temperature` (editable), `Warnings` text (read-only, hidden when empty)

### Draft actions
- `Save Draft`:
  - saves routing draft
  - persists workbench draft snapshot
  - refreshes mapping display based on saved values
- `Revert Draft`:
  - restore default parsed draft values
  - restore routing baseline
  - refreshes mapping display
- `Apply`:
  - per-file atomic archive into the matched Library drawer
  - generates sidecar metadata and writes the audit log
  - rolls back on failure (no partial state)
- `Apply All`:
  - applies all `library-matched` items, skipping `review-required` items

## Mapping behavior contract
### Sample source and edit flow
- Baseline `Sample` is parsed from filename/path rules.
- User can manually edit `Sample` and channel sample values.
- Drawer mapping does not live-update on every keystroke.
- Drawer mapping refreshes when user clicks `Save Draft` or `Revert Draft`.

### Drawer display rule
- Drawer shows only the resolved target drawer value (full display name), or `?` when unresolved.
- No extra suffix/debug explanation is shown in drawer field.

### Drawer matching strategy
Given saved sample input:
1. Token-based matching (current implementation):
  - normalize input to uppercase token set
  - split alpha-numeric components (`PN41` -> `PN`, `41`)
  - all input tokens must be covered by candidate drawer tokens
2. Unique-match contract:
  - exactly one candidate -> that drawer
  - zero or multiple candidates -> unresolved
3. If unresolved:
  - show `?`

Note:
- Current implementation does not enforce a separate explicit exact-match-first phase.
- The unique token coverage rule is the effective runtime behavior.

### Queue status strategy (`Library Matched` / `Review Required`)
- Root definition:
  - Status is based on whether the parsed routing result can be accurately mapped to required existing Library drawer target(s).
- File-level delivery:
  - If the file-level target drawer exists, status is `Library Matched`.
  - Otherwise, status is `Review Required`.
- Channel-level delivery:
  - All reported channels must resolve and map to their corresponding existing drawer targets.
  - If any channel cannot be uniquely mapped to a drawer target, status is `Review Required`.
  - Route unresolved metadata alone does not force `Review Required` when final drawer mapping is still unique and valid.
- Scope boundary:
  - File-level sample info can fill missing channel sample info.
  - Channel-to-channel cross-completion is not allowed.

## Terminology
- `Sample`: user-facing sample identity used for drawer matching.
- `Drawer`: existing Library sample drawer target.
- `Library Matched`: pending item has a resolved drawer target.
- `Review Required`: drawer target unresolved or requires manual confirmation.

## Inbox Registry Lookup Rules (Current)
- Purpose:
  - support Inbox draft auto-fill and warning generation.
- Rule isolation:
  - lookup rules are defined in a dedicated registry rulebook layer.
- Sheet scope:
  - system sheets prefixed with `__` are excluded from sample indexing.
  - only sheets with a recognized sample column are indexed.
- Query path:
  - lookup uses `sampleID -> indexed rows` direct query.
  - prefix-to-sheet mapping is display metadata only, not the lookup routing key.

