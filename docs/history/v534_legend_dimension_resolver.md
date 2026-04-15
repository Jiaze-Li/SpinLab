# v5.3.4 — Legend Dimension Auto-Inference + Visual Consistency

Date: 2026-04-15

## What changed

- New `LegendDimensionResolver` UseCase: data-driven priority chain that determines which metadata dimension (temperature, substrate, energy, etc.) distinguishes a set of plot series. Supports numeric tolerance, partial metadata, and custom chain overrides.
- `WorkbenchPlotPayload` gained `legendDimension` (identifies the distinguishing dimension) and `reverseSeriesForLegend` (controls pipeline series reversal for legend-visual consistency).
- Render pipeline step 4b: unified series reversal so legend top = visual top for stacked charts.
- Removed manual `.reversed()` from ThreeOmegaPlotRenderer (R1w, R3w) and XYRotationPlotRenderer (Rxx, Rxy). Ordering responsibility is now centralized in the pipeline.

## Design decisions

- Priority chain: temperature (tier 0) > substrate/energy/pressure (tier 1) > thickness (tier 2). Same-tier ambiguity produces warning rather than guessing.
- `reverseSeriesForLegend` defaults to `false` — only stacked waterfall tabs opt in with `true`. This prevents unintended reversal for non-stacked charts (Hc, RAHE vs T, Scaling, AHE).
- Resolver is a standalone UseCase not yet wired into existing renderers (which hardcode temperature as dimension). It is ready for Comparison workflows where dimension must be inferred from sample metadata.

## Codex review findings (addressed)

1. Default `true` for reversal flag would regress non-stacked charts → changed to `false`.
2. Pipeline reversal and backward decode needed test coverage → added 4 pipeline tests.
