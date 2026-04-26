# SpinLab Product Rules

Status: active

## Core workflow contract
- SpinLab follows: `Import -> Confirm -> Visualize -> Analyze -> Save -> Archive`.
- Parsed metadata is suggestion-only until user confirmation.
- User confirmation is the authority before archive/apply.

## V2 Inbox -> Library contract
- Inbox supports staged processing: parse, edit, review, then manual apply.
- `Apply Selected` is per file.
- `Apply All` processes library-matched items only and skips review-required items.
- Multi-target apply for one file must be atomic with rollback.

## Safety contract
- No silent fallback when sample route is unresolved or conflicting.
- Unresolved/conflicting items must enter review-required state.
- `Clear Imports` only affects pending queue and unarchived managed temp files.
- `Clear Imports` must never touch files already archived into Library drawers.

## Audit and traceability
- Keep a full audit log under Library Root.
- Keep a structured mirror audit log under App Support.
- Log both edit-confirm actions and archive-apply actions.

## Build and QA gate
- Functional iterations must be buildable.
- Desktop QA app overwrite is required unless explicitly waived by user instruction.
- Definition of Done (default gate for each functional change):
  - `swift build` passes.
  - Desktop app is rebuilt and overwritten for QA.
  - Core acceptance checks for the changed scope are executed and pass.
