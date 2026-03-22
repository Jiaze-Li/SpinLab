# SpinLab UI Rules

Status: active

This file supersedes legacy `UI_RULES.md` and is the active UI rule contract.

## Layout rule
- Prefer stable three-column shell:
  - left: navigation
  - center: operations/workspace
  - right: inspector/output

## Inbox V2 interaction rule
- Center column uses functional blocks in order:
  - Import Source
  - Pending Queue
  - Routing Review
  - Apply
- Right column shows details/inspector for selected pending item.
- Parsed values must be editable in inspector before manual route confirm.
- `Create Project` is not part of Inbox primary workflow controls.
- `Clear Imports` must require explicit confirmation and must indicate it only clears pending/unarchived temporary items.

## Readability and density
- Preserve full filename/path readability on primary workflow surfaces.
- Favor structured metadata inspection over decorative spacing.
- In small windows, use wrapping and scroll access instead of clipping.

## Safety and interaction clarity
- Major destructive actions require explicit confirmation.
- UI should clearly separate apply-ready and review-required states.
- UI-only tasks must not alter parser/state/store behavior.
