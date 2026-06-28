# Stage 5 — Cleanup Closeout

## Closed point

- Branch: `gate8.5A`
- Commit: `5f220da refactor(plotsystem): relocate point tag files`
- Scope: original Stage 3 folder/name cleanup follow-up

## Stage 5A — `plotLegendAnchor` naming audit

**Result: document and defer.**

- `plotLegendAnchor` is confined to `ThreeOmegaPackConfig`.
- It is persisted JSON schema, not a safe internal rename.
- A naive rename would be a migration hazard for existing packs.
- Decision: keep the current schema key, document the inconsistency, and defer rename work until a dual-decode or versioned migration plan exists.

## Stage 5B — PointTag file relocation

**Result: moved.**

- Moved `WorkbenchPointTagState.swift`
- Moved `TabRenderManager+PointTags.swift`
- Source path: `Workbench/V3`
- Target path: `Workbench/Modules/PlotSystem/Preservation`
- Outcome: 100% file rename, no source behavior changes

## Explicit non-changes

- No pack schema changes.
- No render/export logic changes.
- No workflow logic changes.
- No `PointTag` symbol rename.
- No broader `V3` -> `PlotSystem` relocation batch.

## Validation

- architecture-coverage: PASS
- Relevant point-tag and boundary tests: PASS, except the known unrelated `V712` baseline failure
- `swift build`: PASS
- App rebuilt: `/Applications/SpinLab.app`
- Version: `v5.5.4`
- `CFBundleVersion`: `202606281404`
- `check_required_actions.sh`: No rebuild or publish required

## Known unrelated issue

- `V712PointLabelGeometryParityTests.testLayoutHitRectMatchesSharedGeometry` fails on clean `HEAD` and on the relocation state.
- This failure is unrelated to the PointTag file move.

## Remaining backlog

- ThreeOmega `plotLegendAnchor` schema migration, only with a dual-decode or versioned plan.
- Broader `V3` -> `PlotSystem` relocation.
- 3ω special render path optional deeper refactor.
- RSM export path standardization.
- `WorkbenchRenderPipeline.Output` API hardening if justified later.
