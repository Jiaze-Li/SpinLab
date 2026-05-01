# Inbox Confirm & Apply Workflow

The confirm-and-apply layer covers the period from when a parsed item enters the pending queue to when the user commits it into the Library. It governs user-facing state transitions, draft edits, apply atomicity, and audit logging.

---

## Staged Processing Model

Inbox follows a staged model: parse → edit → review → manual apply.

- Every item starts in pending state after parse. No archiving happens at parse time.
- Parsed metadata is suggestion-only until the user explicitly confirms. The user may override any field before applying.
- User confirmation is the authority before archive/apply — `specs/01_PRODUCT_RULES.md` owns this contract.

---

## Draft Confirmation

### Metadata Fields

- Parsed fields (workflow, sample key, channel bindings, conditions) are pre-populated as suggestions.
- File-level sample info can fill a missing channel-level sample key — this is the only cross-field completion allowed.
- Channel-to-channel cross-completion is forbidden — a channel's sample key must come from itself or file-level fallback, never from another channel.
- Save-gated mapping: field edits do not trigger live re-routing. A deliberate Save action commits the edited draft.

### Drawer Matching Display

- Drawer matching uses token-coverage semantics. Matched drawer shown when exactly one candidate found; `?` shown when zero or multiple.
- Route unresolved metadata alone does not force Review Required when final drawer mapping is still unique and valid.

---

## Apply Semantics

### Apply Selected

- Applies a single pending item.
- Multi-target (one file → multiple samples/drawers): all targets must succeed or the entire apply rolls back.

### Apply All

- Iterates all library-matched items.
- Skips review-required items silently — they remain in the pending queue.
- Each file is processed independently; a failure on one file does not roll back already-applied files.

### Per-File Atomicity

For each file apply:
1. Archive source file to Library drawer.
2. Generate sidecar with all metadata fields.
3. Write audit log entry for the archive-apply action.
4. On any step failure: roll back file + sidecar together before returning error.

### Sidecar Generation

- Sidecar is generated at apply time from the confirmed draft state.
- Fields written: `version`, `source_file`, `sample_key`, `workflow`, `conditions`, `channel_bindings`, `normalized_tags`, `raw_tags`, `applied_at`.
- Full field schema: `docs/architecture/inbox/OUTPUT_CONTRACTS.md`.

---

## Clear Imports

- Affects only the pending queue and unarchived managed temp files.
- Must never touch files already archived into Library drawers.
- Scope is strictly pre-apply state — no destructive effect on completed archives.

---

## Audit Logging

Two audit events are logged per confirmed item:

1. **Edit-confirm**: logged when the user confirms draft edits before apply.
2. **Archive-apply**: logged when the file is successfully archived into the Library drawer.

Both logs are:
- Written under Library Root (user-visible) and App Support (structured mirror).
- Append-only; never modified retroactively.
- If the log file exists but cannot be read, the write is skipped to prevent overwrite.

Full audit invariants: `specs/01_PRODUCT_RULES.md`.

---

## UI Layout (Current State)

Inbox uses a two-column shell:
- **Left column**: pending queue list + operation panel (Apply, Apply All, Clear Imports, etc.).
- **Right column**: inspector/output panel — shows detail, plot preview, and route information for the selected pending item.

The right column is no longer blank/reserved — it is actively used for inspector and output display. See `specs/04_UI_RULES.md` App Shell Layout section for the column shell contract.

---

## Code Map

- `Sources/SpinLabApp/App/State/InboxFeatureStore.swift` — pending queue state; selection; queue lifecycle
- `Sources/SpinLabApp/App/ApplyCoordinator.swift` — coordinates Apply/Apply All across InboxArchiveApplyService and Library
- `Sources/SpinLabApp/App/InboxArchiveApplyService.swift` — per-file atomic archive: file copy + sidecar write + audit log
- `Sources/SpinLabApp/App/InboxWorkflowService.swift` — workflow-level Inbox service orchestration
- `Sources/SpinLabApp/App/InboxFacade.swift` — App-level Inbox capability facade
- `Sources/SpinLabApp/Features/Inbox/InboxView.swift` — Inbox two-column root view
- `Sources/SpinLabApp/Features/Inbox/InboxViewModel.swift` — transient UI state: selection, filter, expansion
- `Sources/SpinLabApp/Features/Inbox/InboxOperationPanel.swift` — Apply / Apply All / Clear Imports button bar
- `Sources/SpinLabApp/Features/Inbox/InboxInspectorPanel.swift` — right-column inspector/output panel
- `Sources/SpinLabApp/Features/Inbox/InboxSelectionWorkbenchPanel.swift` — route edit panel for selected pending item
- `Sources/SpinLabApp/Features/Inbox/InboxProgressOverlays.swift` — progress overlay during apply operations
- `Sources/SpinLabApp/App/AuditEvent.swift` — domain model for an auditable archive operation event
- `Sources/SpinLabApp/App/AuditLogger.swift` — append-only audit log writer for Library archive operations
- `Sources/SpinLabApp/App/DuplicateGuard.swift` — guards against duplicate file imports by tracking known content hashes
- `Sources/SpinLabApp/App/PendingCleanupService.swift` — removes temp files for cancelled or expired pending import items
- `Sources/SpinLabApp/App/ServiceOutcome.swift` — result type for service operations (success/skip/failure with reason)
