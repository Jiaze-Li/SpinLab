# Workbench IVAngleDependence Module

> **Module Type**: IV-owned analysis module (not a shared/reusable Workbench module — angle-dependence slope extraction is IV-specific).

## Purpose

Computes the free-intercept PowerLawFit slope `a_n(Ψ) = V^{nω}/(I^ω)^n` for each sweep in the active IV tab, one point per sweep angle, for the "Angular plot" view. First version is points-only — no angular sinusoidal/Fourier fit.

## Ownership

IVAngleDependence owns:

- grouping/sorting sweeps by resolved angle
- duplicate-angle handling (points are never merged/averaged; each valid sweep keeps its own point)
- per-sweep slope extraction via the shared `PowerLawFitUseCase` (free intercept — `subtractIntercept: false`)
- sufficiency/diagnostic reporting (distinct-angle count, excluded sweeps, fit failures)
- IV-specific axis-label/unit text for the angle view (`IVAngleDependenceProjection`) and its own `WorkbenchPlotSeries` mapping

IVAngleDependence must not own:

- how a sweep's angle is resolved from raw metadata (workflow-owned; see below)
- tab/channel/component selection, Fit mode, or which harmonic/basis is active
- pack/restore, UI state, or the Angular-plot toggle itself
- Plot System rendering, stacking, or series identity

The IV workflow (`IVWorkspaceStore`, `IVPlotRenderer`, `IVSpecificPlotControls`) owns:

- resolving `angleDeg: Double?` per sweep by parsing `IVSweep.sampleMetadata?["device"]` with the existing `ThreeOmegaDeviceAngleParser` (same free-text convention 3ω already relies on — no ingestion/parser change)
- building `currentMA`/`voltageMV` per sweep from the active tab/channel/component/basis selection (identical inputs the V-vs-I^n view already computes)
- the `angularPlotEnabled` toggle, its pack persistence, and its UI gating
- choosing when to route the renderer to the angle payload instead of the harmonic payload

## Computational Contract

- Requires `fitMode != .none`; returns an empty, insufficient result with a diagnostic otherwise.
- A sweep with no resolvable angle is excluded (diagnostic, not a crash).
- Angles are not deduplicated — a genuine duplicate angle produces two plotted points and a diagnostic.
- Sufficiency requires at least 2 *distinct* angle values (not sweep count) — see `IVAngleDependenceUseCase.minimumDistinctAngles`.
- `IVAngleDependenceUseCase.countDistinctValidAngles` is a cheap, fit-free helper the workflow uses to gate the toggle's enabled state without running per-sweep regressions.

## Boundary Rules

- Do not move angle-string parsing into this module — it stays IV-workflow-owned so the module never depends on `sampleMetadata` conventions.
- Do not average/merge duplicate-angle points here; if aggregation is ever wanted, that is a new, explicit product decision, not a silent default.
- Do not reimplement linear regression — always go through `PowerLawFitUseCase`.
- Do not add "Angular plot" as a new IV tab; it replaces the current tab's payload in place.

## Implementation Files

- `Sources/SpinLabApp/Workbench/Modules/IVAngleDependence/IVAngleDependenceContracts.swift`
- `Sources/SpinLabApp/Workbench/Modules/IVAngleDependence/IVAngleDependenceUseCase.swift`
- `Sources/SpinLabApp/Workbench/Modules/IVAngleDependence/IVAngleDependenceProjection.swift`

## Risk Notes

- Angle resolution depends on `sampleMetadata["device"]` already containing an angle-shaped token. If the ingested "device" condition is a literal device name unrelated to rotation angle, that sweep's angle silently fails to resolve (diagnostic, no crash) — this is a known limitation of reusing the existing free-text convention rather than adding a dedicated ingestion field.
- If a future version needs Fourier/sinusoidal fitting over these points, that belongs in this module as a new, explicit computation — not bolted onto the workflow layer.
