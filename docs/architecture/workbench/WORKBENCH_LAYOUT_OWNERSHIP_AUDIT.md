# Workbench Layout Ownership Audit

**Date:** 2026-08-12
**Scope:** `AppColumnShell`, `WorkbenchWorkflowSplitView`, `WorkflowWorkspaceRegistry`, `WorkflowWorkspaceShell`, the six workflow workspace views
**Purpose:** Record why `AppColumnShell` (and its `HSplitView`) must have exactly one stable call site on the Workbench workflow route, and what broke when it didn't. No further refactoring is scoped by this document.

> **Superseded (2026-08-12, same day):** everything below describes the
> intermediate, Workbench-only fix — one `AppColumnShell` per *area*
> (Inbox/Library/Workbench each had their own). That has since been replaced
> by a single **app-wide** three-pane shell (Navigation | Primary | Detail)
> shared by all three areas. `AppColumnShell`, `SplitWidthState`,
> `AppNativeSplitView` (two-pane), and `WorkbenchWorkflowSplitView` no longer
> exist in the tree — they were superseded by `AppWorkspaceShell` /
> `AppWorkspaceSplitView` / `WorkspaceLayoutState` (`Sources/SpinLabApp/UI/`).
> The state-contract *principles* recorded below (four-concept model, single
> writer, commit only on genuine user drag) still hold and were carried
> forward unchanged into `WorkspaceLayoutState`; only the two-pane-per-area
> mechanics are obsolete. See the chat/report from that rewrite for the full
> before/after.

---

## The bug

Each workflow workspace view (`AHEWorkspaceView`, `IVWorkspaceView`, `ThreeOmegaWorkspaceView`, `XYRotationWorkspaceView`, `RTWorkspaceView`, `RSMWorkspaceView`) used to build its own `AppColumnShell` inside `WorkflowWorkspaceShell.body`. Because `WorkflowWorkspaceRegistry` dispatched to a different workflow view per route, switching workflows swapped in a structurally different `View` tree — which SwiftUI treats as tearing down and reconstructing the `AppColumnShell`, and with it the underlying AppKit `NSSplitView`/`HSplitView`.

A freshly constructed `HSplitView`'s first real layout pass does not honor the `idealWidth` hint `AppColumnShell` passes it. It settles on whatever width AppKit's initial layout produces, and that measured width is what gets written back into the persisted `@AppStorage("splitView.workbench.leftWidth")` value — silently overwriting the user's last chosen divider position on every workflow switch.

## The fix

Ownership of the split is lifted one level, out of the per-workflow views and into a single stable parent:

- `WorkbenchWorkflowSplitView` is the sole `AppColumnShell(...)` call site on the Workbench workflow route. It is constructed once by `WorkbenchView` for the `.workflow(id)` case and its identity does not change as `workflowID` changes — only the content inside its `left`/`right` closures changes.
- `WorkflowWorkspaceRegistry.leftContent(for:)` / `.rightContent(for:)` branch on `workflowID` *inside* those closures (an `if/else` chain, not a fresh view-per-branch that recreates the shell).
- `WorkflowWorkspaceShell` no longer owns `AppColumnShell` or the right column at all — it only composes the left-column content (search, action bar, plot controls, results) that gets embedded inside `WorkbenchWorkflowSplitView`'s `left` slot. It intentionally is not a `View`; callers read its `leftColumn` property.
- Each workflow's right-column content is a small dedicated `View` (`AHEWorkspaceRightView`, `IVWorkspaceRightView`, etc.) that wraps `WorkflowWorkspaceRightColumn`, keeping the split's `right` slot swap confined to content, not shell identity.

## Invariant going forward

`AppColumnShell` / `HSplitView` must not be constructed anywhere else on the Workbench workflow route. In particular, workflow-specific workspace views must not instantiate `AppColumnShell(` or `HSplitView(` directly — regression coverage lives in `Tests/SpinLabAppTests/V330WorkbenchShellContractTests.swift` (`WorkbenchSplitOwnershipRegressionTests`).

## Out of scope

`AppColumnShell`'s width measurement → persistence algorithm itself (debounce, drag detection, first-layout suppression, etc.) is not touched here. See the `TODO`-style note on `AppColumnShell` for the still-open question of distinguishing layout-driven width changes from user drag-driven ones.

---

## Divider width state contract (B2 design / B3 implementation)

The question left open above — distinguishing layout-driven width changes from user-driven ones — was root-caused (B1) and closed with a structural state contract (B2 design, B3 implementation). This section is the durable record of that contract; treat it as the source of truth for how divider width state works, not the narrative above.

### State model

Four distinct concepts, only two of which may ever be persisted:

- **`userPreferredWidth`** — the width the user explicitly chose via divider drag. Canonical user intent for the session. Owned by `SplitWidthState`.
- **`persistedPreferredWidth`** — cross-launch mirror of `userPreferredWidth`, written to `UserDefaults` under `splitView.\(columnKey).leftWidth`.
- **`requestedWidth`** — derived, per-frame: `clamp(userPreferredWidth, currentConstraints)`. Never mutates `userPreferredWidth`; a tightened constraint (small window, reduced `leftMax`) never truncates the stored preference, only the effective request.
- **`actualRenderedWidth`** — what AppKit/SwiftUI actually rendered this frame. Pure observation. Structurally has no write path into `userPreferredWidth`.

### Source of truth

`SplitWidthState` (`Sources/SpinLabApp/UI/SplitWidthState.swift`) is the sole owner of `userPreferredWidth`/`persistedPreferredWidth`. Its only mutating entry point is `commitUserWidth(_:)`. There is no other API on the type that can change stored state — this is enforced by the type's shape, not by convention.

### Event ownership

Only a completed divider drag (`UserDragEnded`) may call `commitUserWidth(_:)`. Workflow switch, window resize, native relayout, initial mount, and view lifecycle (`onAppear`/`onDisappear`) may all change `actualRenderedWidth` transiently but must never reach `commitUserWidth(_:)`. `AppColumnShell` no longer has an `onDisappear` persistence write at all — it was the second, redundant path into the old bug and had no legitimate role once `commitUserWidth(_:)` existed as the single drag-end write path.

### Native drag detection (`NativeSplitCoordinator`)

`Sources/SpinLabApp/UI/NativeSplitCoordinator.swift` bridges real AppKit signals into the drag-end event, without installing an `NSSplitViewDelegate` — runtime inspection during B3 confirmed SwiftUI's `HSplitView` already installs its own delegate (`SwiftUI.SplitViewController`) on the backing `NSSplitView`; overwriting it was never attempted. Instead:

- `NSSplitView.didResizeSubviewsNotification` (public, delegate-free) observes every relayout.
- A local `NSEvent` monitor on `leftMouseDown`/`leftMouseUp`, hit-tested against a divider rect computed from the left subview's frame and `dividerThickness` (there is no public divider-rect getter), determines whether a resize in flight originated from the user grabbing the divider — a real mouse-event signal, not a width-delta/timing heuristic.

Only `mouseUp` while a drag was in progress commits the final width via `commitUserWidth(_:)`.

### Reconciliation, and a bounded-loop bug found during B3

When a relayout drifts `actualRenderedWidth` away from `requestedWidth` outside of an active drag (e.g. the transient measurement swing during workflow content replacement), the coordinator issues one corrective `NSSplitView.setPosition(_:ofDividerAt:)` call. An early version of this correction was **unconditional and unbounded**: during B3 runtime diagnostics it produced a tight `didResizeSubviewsNotification → setPosition → didResizeSubviewsNotification → …` cycle when the left subview reported a degenerate `0`-width reading mid-transition, and crashed the app (`EXC_BAD_ACCESS` / "Thread stack size exceeded due to excessive recursion" — confirmed from the `.ips` crash report). The fix, now in place:

- Correction is skipped entirely when `actualRenderedWidth` is non-finite, `<= 0`, or the split view has no window (mid-transition/detached states — not legal states to reconcile against).
- A hard cap (`maxCorrectionAttempts = 3`) bounds consecutive corrective `setPosition` calls; the coordinator gives up (and logs once, in `DEBUG`) rather than looping if the gap never closes.
- The attempt counter resets on drag start and whenever `actualRenderedWidth` settles within tolerance of `requestedWidth`.

Any future change to this reconciliation logic must preserve boundedness — this is not an optional hardening detail, it is what stands between a transient layout hiccup and a crash.

### Window resize and constraint semantics

A window shrink (or a tightened `leftMax`, e.g. across app versions) may reduce `requestedWidth`/`actualRenderedWidth` below `userPreferredWidth`, but never mutates `userPreferredWidth` or `persistedPreferredWidth`. When the window/constraint relaxes again, `requestedWidth` returns to the original preference automatically — there is no explicit "restore" step, because the preference was never touched. See `SplitWidthStateContractTests` (TEST 5/6) for the regression coverage.

### Files

- `Sources/SpinLabApp/UI/SplitWidthState.swift` — state + persistence.
- `Sources/SpinLabApp/UI/NativeSplitCoordinator.swift` — native drag detection + reconciliation.
- `Sources/SpinLabApp/UI/AppColumnShell.swift` — visual composition only; consumes `requestedWidth`, never writes preference.
- `Tests/SpinLabAppTests/SplitWidthStateContractTests.swift` — behavioral regression guards (state-model level; real user-drag detection can only be verified by runtime/manual acceptance, not unit tests).

### Still open

`[DEBUG]`-only instrumentation (`[SplitTrace]`, `SplitViewIdentityProbe`, `debugWorkflowLabel`) remains in place pending real-mouse acceptance (see B3 closeout report). It is diagnostic only and does not participate in the state contract above; remove it once acceptance passes.
