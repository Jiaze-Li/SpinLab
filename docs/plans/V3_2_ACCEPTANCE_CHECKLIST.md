# SpinLab V3.2 Acceptance Checklist

Status: draft (gate not yet executed)  
Owner: implementation + QA shared gate

This checklist is the acceptance gate for V3.2 only.

## Scope Boundary (must pass)

- [ ] V3.2 includes `V3.2.0` through `V3.2.8` from `V3_2_ITERATION_ADDENDUM_2026-04-03.md`.
- [ ] V3.2 does not include V3.4 (Library writeback/read models) scope items.
- [ ] V3.2 does not include V3.5 reliability hardening scope items.

## Generic Search Layer (must pass)

- [ ] `V3.2.0` broad workflow `type` query works across drawers.
- [ ] AHE lookup does not require preconfigured `id=AHE`.
- [ ] Search returns unified `WorkflowMeasurementSearchHit`-style results.
- [ ] Search remains independent from workflow-specific parsing and plotting.

## AHE Pipeline + Plot Path (must pass)

- [ ] AHE `.dat` / `.lvm` ingestion works (`V3.2.1`).
- [ ] Axis detection provides default `x/y` and candidate fields.
- [ ] Unified plot entry renders PNG from standardized payload (`V3.2.2`).
- [ ] Manual axis/style adjustments are reflected in render (`V3.2.3`).

## Identity + Trace + Persistence (must pass)

- [ ] Chart identity is semantic-based and deterministic (`V3.2.4`).
- [ ] Style-only changes overwrite; semantic changes produce new artifacts.
- [ ] Run manifest provenance is emitted and visible (`V3.2.6`).
- [ ] V3.2 writes use `AtomicFileWriter` + `LibraryPathResolver` (`V3.2.7`).
- [ ] App restart can rediscover/open persisted V3.2 artifacts.

## Plot UX Freeze (must pass)

- [ ] Plot UX freeze is completed after persistence closure (`V3.2.8`).
- [ ] Legend drag/reposition works.
- [ ] In-plot title editing works.
- [ ] Plot interaction model is workflow-agnostic and reusable.

## Early Integration Risk Control (must pass)

- [ ] Atomic write-path smoke test passes immediately after default render (`V3.2.2`).
- [ ] No late-discovered write-path incompatibility blocks V3.2 final gate.

## Build and Runtime Gate (must pass)

- [ ] `swift test` passes.
- [ ] Desktop app build/overwrite completes for QA target.
- [ ] App version is bumped to the accepted V3.2 iteration.

## MR/RT Onboarding Readiness Check (must pass before starting MR/RT)

- [ ] Unified plot API has been used by at least one real AHE batch end-to-end.
- [ ] Atomic write-path works on real library paths (not test-only temp paths).
- [ ] V3.2 architecture boundaries remain intact (workflow compute vs unified plot).
- [ ] Decision recorded: MR/RT can onboard without changing unified plot main flow.
