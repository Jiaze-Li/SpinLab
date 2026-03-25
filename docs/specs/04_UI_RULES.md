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
  - Registry
  - File
  - Selection Workbench (inside File block)
- `File` block includes:
  - Actions (`Import Files`, `Recompute Route`, `Clear Imports`)
  - Pending Queue (status filters + file list + file path)
  - Selection Workbench (deposit mapping + file tags + draft actions)
- Standalone `Routing Review` and standalone `Apply` side blocks are removed.
- Right column is intentionally blank placeholder space for future modules; it is not an active inspector in the current Inbox design.
- Parsed values and manual confirmation actions happen in center-column `Selection Workbench`.
- `Create Project` is not part of Inbox primary workflow controls.
- `Clear Imports` must require explicit confirmation and must indicate it only clears pending/unarchived temporary items.

## Readability and density
- Preserve full filename/path readability on primary workflow surfaces.
- Favor structured metadata inspection over decorative spacing.
- In small windows, use wrapping and scroll access instead of clipping.
- Minimize repeated or low-value information; avoid showing the same facts in multiple blocks unless each placement has a distinct decision-making purpose.

## Safety and interaction clarity
- Major destructive actions require explicit confirmation.
- UI should clearly separate library-matched and review-required states.
- UI-only tasks must not alter parser/state/store behavior.
