# Workbench - Main Board Readiness

> Readiness is a derived board-level projection, not stored source-of-truth state.

## What Readiness Means

Readiness is a Main Board concern. The Main Board does not keep a separate lifecycle state; it derives a readiness view from module-owned state and uses that derived view for shell decisions.

Readiness is read-only, derived, and non-persistent. It must not become a second canonical state variable.

## Readiness Ladder

| Level | Derived meaning |
|---|---|
| Empty | No usable workflow search result or analysis output is present. |
| Found Data | Search has produced at least one usable hit list. |
| Selected Data | The user has selected one or more search hits. |
| Running | Search or analysis/render work is in flight. |
| Result Ready | The workflow has active render output available for display or save. |
| Saved | The current analysis has an associated save outcome or active saved pack reference. |

## `WorkbenchReadinessProjection`

`WorkbenchReadinessProjection` is the read-only derived projection that represents the ladder above. It is a board-facing view of module-owned state, not a persisted record and not a replacement for any module's canonical state.

## Intended Consumers

- Button gating
- Status display
- Preflight checks
- Future tests

## Current Implementation Status

- `WorkbenchReadinessProjection` is implemented.
- Shell consumption is implemented in the action bar for Select All, Analyze, and progress gating.
- The action bar keeps library-root search preflight and the direct search-running check explicit.
- Result-header gating keeps `store.hasAnalysisResult` explicit for pack-analysis availability while `matchingVaultPack`, `activePackID`, and analysis-vault saved-state logic remain separate.
- Load Pack availability and unsaved-analysis prompts remain direct workflow-local vault behavior.
- Readiness remains derived from module-owned state rather than stored as canonical board state.
