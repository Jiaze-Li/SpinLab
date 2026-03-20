# Library V1/V2 Plan

## Version Completion Rule
- After each version is accepted, add a completion marker in this document using format: `vX.Y-done`.
- Example markers: `v1.3-done`, `v1.4-done`, `v2.1-done`.
- Keep markers in chronological order at the end of this document.

## App Shell Baseline
- Left column: app navigation (`Inbox / Workbench / Library`), with room for future secondary menu.
- Center column: work column for operations (`Load / Create / Save / Refresh / Review`).
- Right column: display column for details/output (currently `Sample Detail`, later plots and other inspectors).
- Library work in this plan should align to this shell pattern and keep action controls in the center column.
- Registry XLSX is the desired drawer-state source of truth; existing created drawers are the current state.
- Library sync features must compare `registry target` vs `existing drawers` and surface only actionable deltas.

## V1 (Registry → Drawers)
- V1.1: Library Settings UI
  - Registry path comes from Inbox "Load Sample Registry" (no new source input in Library).
  - Library shows current registry path for verification (temporary, can be removed later).
  - Choose Library Root path, then Verify Root creates an empty folder to confirm correct location.
- V1.2: Registry Preview
  - Parse internal registry XLSX and show preview list of batches/samples and substrate tokens.
  - Searchable by substrate tokens (e.g., STO, STO(111)).
- V1.3: Create Drawers (confirmation required)
  - User confirms before creating drawers.
  - Creates batch/sample folders and metadata files.
- V1.4: Refresh + Review
  - Sync from registry (XLSX) with incremental refresh.
  - Compare `registry target` against `existing drawers` from index/root as the review baseline.
  - Show actionable delta classes: `new drawers`, `tag changes`, `numeric changes requiring confirmation`.
  - `Load Preview` is an internal parse step inside sync flow, not a standalone end-user goal.
- V1.5: Existing Drawer Baseline UI (Required Before Full Review)
  - Introduce explicit `Existing Drawers` concept in app.
  - Add created-drawer browser (`prefix -> batch -> sample`) and sample detail panel as review reference.
  - Show drawer tag layer (`metadata`, `numeric tags`) separate from content layer (`measurements/tests/plots/analysis`).
  - Review views must anchor to this baseline, not raw XLSX rows.
  - Finalized interaction contract:
    - `Sync Registry`: detect-only operation; prepares pending delta review and does not auto-apply.
    - `Apply All`: applies all pending registry deltas to existing drawers.
    - `Apply Selected`: applies pending delta only for the selected batch.
    - Pending state semantics in queue:
      - green `+`: add
      - red `-`: remove
      - yellow marker: change
    - `Sample Detail` should expose changed fields with old/new values for review.
    - Existing drawers support explicit manual deletion with confirmation.
  - Functional boundary:
    - `Sync Registry` aligns app state to XLSX target (manual confirmation before apply).
    - `Sync File` aligns app state to actual filesystem drawers.
    - Registry queue represents pending registry operations, not generic file browsing.
- V1.6: Delta Queue + Pending/Created/All + Performance Cache
  - Add `Pending / Created / All` switch in Library UI.
  - Compute pending queue by stable `sampleKey`: `pending = registry target - existing`.
  - After create/update actions, refresh created set and remove resolved items from pending immediately.
  - Show per-batch pending/total counts for quick review.
  - Use in-memory directory-level cache (path tree + counts + mtime) for fast selection.
  - Load concrete file lists lazily only when a folder is expanded.
  - Invalidate cache at node level when directory mtime changes; avoid full cache reset.
  - Keep file I/O out of normal row selection path (selection reads from memory model first).
- V1.7: Edit + Search
  - Edit metadata/tags in UI.
  - Search by substrate tokens and numeric tags.

## V1 Extension (Inbox → Library + Backup)
- V1.8: Inbox → Library
  - Match status red/green in Inbox.
  - Confirm archive into Library drawer.
  - Library drawer shows copied measurement file.
- V1.9: Backup Sync
  - Manual backup sync to a user-selected location.

## Verification (UI-only)
- All verification is done via UI interactions, not internal logs.

## Done Markers
- v1.3-done
- v1.5-done
