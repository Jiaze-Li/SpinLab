# Workbench PowerLawFit Module

> **Module Type**: Optional, reusable Workbench analysis module.

## Purpose

PowerLawFit is a pure numeric fit engine for workflows that need a generic power-law regression. It is intentionally workflow-agnostic and Plot System-agnostic.

## Ownership

PowerLawFit owns:

- fit mode selection with `none` / `1` / `2` / `3`
- typed configuration
- typed input points
- typed result payload
- typed diagnostics
- typed line-geometry result
- snapshot/restore of its own module state
- pure computation use case

PowerLawFit must not own:

- IV workflow semantics
- harmonics, channels, or current/voltage interpretation
- units or display labels
- workflow titles, tab names, or render state
- Plot System rendering or layout
- measurement-series identity rules

## Computational Contract

The current use case fits a straight line against transformed `x^n` values:

- `none` disables fitting and returns a safe disabled result
- `1`, `2`, `3` select `x^1`, `x^2`, or `x^3`
- the fit may subtract the intercept from the rendered line when requested
- the result includes slope, intercept, `rSquared`, fit-line geometry, and diagnostics
- invalid or insufficient data returns a safe failure result instead of throwing

## State Snapshot

The module snapshot is a pure state container:

- `configuration`
- optional `input`
- optional `result`

It is designed so a Workflow Assembly can persist or restore its own copy without transferring ownership of the workflow pack format into this module.

## Boundary Rules

- Do not embed IV- or 3ω-specific fit semantics here.
- Do not move display or rendering logic into the fit engine.
- Do not reinterpret series identity or workflow metadata in order to feed the fit.
- Do not use the module as a general-purpose save/restore owner.

## Implementation Files

- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitMode.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitDiagnostic.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitConfiguration.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitInput.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitLineGeometry.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitResult.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitStateSnapshot.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitUseCase.swift`
- `Sources/SpinLabApp/Workbench/Modules/PowerLawFit/PowerLawFitRuntime.swift`

## Risk Notes

- If a workflow starts baking its own units or labels into the module, the module stops being reusable.
- If fit-line rendering becomes a Plot System concern, the module boundary has failed.
- If the module is later wired into IV, that migration must be explicit and separate from this gate.
