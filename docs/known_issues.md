# Known Issues & Intentional Behaviors

Status: active

Check this file before "fixing" anything that might be intentional.
For tech debt details, see `history/TECH_DEBT_BACKLOG.md`.

---

## Intentional Behaviors (Not Bugs)

- **Right column blank in Inbox**: Intentionally empty placeholder for future modules.
- **Parse stage makes no routing decisions**: Strict pipeline boundary, not a missing feature.
- **Apply All skips review-required items**: By design. Only library-matched items are auto-applied.
- **Save-gated mapping in Inbox**: Drawer mapping refreshes on Save Draft / Revert Draft, not on keystroke.
- **Pre-v4.1.3 workflow IDs ("A", "B") in persisted data**: Replace with "ahe"/"3w" during write/migration. Search inputs still accept old IDs as aliases.

## Deliberately Deferred

- Deprecated condition pattern fields: waiting for zero-usage telemetry.
- ~~Legacy CodingKeys in `PendingImportConfirmationDraft`~~: removed in v5.1.0 (release cycle condition met).
- `condition_aliases.json` scope: only one mapping, needs evaluation.
