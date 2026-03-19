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
  - Incremental refresh only; add new drawers and update metadata in-place.
  - Review sheet shows new/changed items; numeric changes require confirmation.
- V1.5: Edit + Search
  - Edit metadata/tags in UI.
  - Search by substrate tokens and numeric tags.
- V1.6: Pending Visibility (Preview vs Created)
  - Read both registry preview (XLSX) and existing created drawers (index/root).
  - Compute pending items as `preview - created` by stable sampleKey.
  - Library browser defaults to pending-only view to avoid duplicate/redundant rows.
  - After `Create Selected`, refresh created set and remove newly created item(s) from pending immediately.
  - Show per-batch pending/total counts for quick review.
- V1.7: Drawer Management UI + Performance Cache
  - Add `Pending / Created / All` switch in Library UI.
  - Add created-drawer browser in app (`prefix -> batch -> sample`) and sample detail panel.
  - Show folder entry points for `measurements/tests/plots/analysis`.
  - Use in-memory directory-level cache (path tree + counts + mtime) for fast selection.
  - Load concrete file lists lazily only when a folder is expanded.
  - Invalidate cache at node level when directory mtime changes; avoid full cache reset.
  - Keep file I/O out of normal row selection path (selection reads from memory model first).

## V2 (Inbox → Library + Backup)
- V2.1: Inbox → Library
  - Match status red/green in Inbox.
  - Confirm archive into Library drawer.
  - Library drawer shows copied measurement file.
- V2.2: Backup Sync
  - Manual backup sync to a user-selected location.

## Verification (UI-only)
- All verification is done via UI interactions, not internal logs.

## Done Markers
- v1.3-done
