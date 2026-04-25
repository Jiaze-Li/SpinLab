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

- **v5.1.5 first-launch migration**: On first run after upgrade, `RulesMigration.runIfNeeded()` converts the old monolithic `filename_rules.json` to 7 canonical schema files. Runtime config dir may still show the old file until app launches. Migration is one-shot and idempotent (guarded by `migration_state.json` sentinel). If migration fails, app falls back to bundle defaults.

## Deliberately Deferred

- ~~Deprecated condition pattern fields~~: removed in v5.1.4 (confirmed zero usage).
- ~~Legacy CodingKeys in `PendingImportConfirmationDraft`~~: removed in v5.1.0 (release cycle condition met).
- ~~`condition_aliases.json` scope~~: removed in v5.2.0 (bundled file unused).
