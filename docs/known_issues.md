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

## Transition Notes

- **v5.1.5 first-launch migration**: On first run after upgrade, `RulesMigration.runIfNeeded()` converts old v1/v2 schema files to the new 5-book v3 schema (import_filters / filename_tokenization / sample_identification / workflow / measuring_condition). Migration is one-shot and idempotent (guarded by `migration_state.json`). On failure, writes `migration_failed.json` to block retry and preserves `.backup-<ts>` copies; app falls back to bundle defaults for that session.

## Deliberately Deferred

- ~~Deprecated condition pattern fields~~: removed in v5.1.4 (confirmed zero usage).
- ~~Legacy CodingKeys in `PendingImportConfirmationDraft`~~: removed in v5.1.0 (release cycle condition met).
- ~~`condition_aliases.json` scope~~: removed in v5.2.0 (bundled file unused).
