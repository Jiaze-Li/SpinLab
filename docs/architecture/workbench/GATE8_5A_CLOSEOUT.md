# Gate 8.5A Closeout — PlotControl Correctness, Pack Persistence, and Test Baseline

Clean point: `195f952` — test(heatmap): use realistic large-font spacing fixture

## Completed Work

### Plot text commit idempotency

`SharedPlotLabelOverrideField` / `LabelOverrideFieldSync.commitIfDirty` was not
idempotent. A repeated Enter on a committed non-empty value would clear the committed
display status. An empty or whitespace commit did not write the fallback text into
committed status.

Fixed: non-empty commit is stable across repeated Enter. Empty/whitespace commit now
writes the rendered default into committed status.

### 3ω hidden point label propagation

`rerenderFieldSweepTabs` and `_renderRAHEWithOverlays` already forwarded `showPointTags`
but omitted `hiddenPointLabelIndicesBySeries` when constructing special-render inputs.
Hidden point labels would reappear on special re-renders.

Fixed: both paths now forward the full hidden-label set from active display overrides.

### Pack persistence coverage gaps

Shared PlotControl status had workflow-specific coverage gaps in AnalysisPack save/load.
After a pack restore, controls such as `seriesRenderMode`, `showPlotGrid`,
`chartStyleOverrides`, `legendAnchor`, and `TabRenderState` could revert to defaults in
some workflows.

Persisted / verified fields per workflow:

| Workflow | Persisted / verified fields |
|---|---|
| ThreeOmega | plotLegendAnchor, seriesRenderMode, chartStyleOverrides, showPlotGrid, TabRenderState per tab |
| AHE | legendAnchor, seriesRenderMode, chartStyleOverrides, showPlotGrid |
| IV | legendAnchor, seriesRenderMode, chartStyleOverrides, showPlotGrid, TabRenderState per tab |
| RT | legendAnchor, seriesRenderMode, chartStyleOverrides, showPlotGrid, TabRenderState per tab |
| XYRotation | legendAnchor, seriesRenderMode, chartStyleOverrides, showPlotGrid, titleTemplate, stackOffsetMultiplier, minGapFraction, showAuxiliaryLine180 |

Heatmap (RSM) is out of scope — its PlotControl path differs.

### V78C test baseline restoration

**IV pipeline expectation:** `applyPipelineOutput` in IVWorkspaceStore was extended with
`displayPayload:` by the WorkbenchPlotExportService refactor. The test expected the old
no-payload form. Updated to match the current call. Production code not modified.

**Heatmap large-font fixture:** Fixture used integer y-values `[0.0, 1.0]` whose tick
labels (`"0"`, `"1"`) are too narrow to drive layout expansion with the current
text-measurement-based `PlotAxisSpacingCalculator.yAxisLane`. Magic-padding thresholds
were calibrated to the old heuristic formula. Replaced fixture with fractional RSM-style
y-values `[-0.125, 0.250, 0.625, 1.000]` and replaced thresholds with direct geometry
assertions (`paddingLeft > 80`, `titleRightEdge < paddingLeft - 8`). Production layout
code not modified.

## Architecture Conclusion

| Layer | Responsibility |
|---|---|
| `WorkbenchStandardPlotControls` | UI shell only — binds to state, owns none |
| `TabRenderManager` / `TabRenderState` | Committed shared PlotControl status per tab |
| Render pipeline | Consumes committed status; does not mutate it |
| Export service | Reads committed status from `TabRenderState` |
| Pack save/load | Persists committed status across sessions |
| Workflow-specific controls | Stay workflow-owned where intentional |

`WorkbenchStandardPlotControls` is a UI composition helper, not a data source. Render
and persistence layers must read shared PlotControl state from `TabRenderState`.

## Non-Blocking Debt

- V4: manifest/display-label semantics
- V5: IV x-axis migration policy
- V9: `displayPayload` / `manifestPayload` asymmetry in `TabRenderOutput`
- PointTag file physical location (deferred to workflow grouping pass)
- `plotLegendAnchor` (ThreeOmega) vs `legendAnchor` naming inconsistency
- 3ω special render paths: long-term replacement with shared pipeline path deferred

## Validation

Validated at `195f952`:

| Suite | Result |
|---|---|
| V78CPlotControlsSpecializationTests | 82/82 |
| V85APackPersistenceGapTests | 20/20 |
| V710PlotControlsMigrationTests | 56/56 |
| PlotSystemAppearanceAndRangeTests | 40/40 |
| `swift build` | clean |
| `check_required_actions.sh` | no rebuild or publish required |

## Related Documents

- `GATE8_4_CLOSEOUT.md` — PlotSystem physical layout alignment (prerequisite)
- `GATE8_5A_STALE_PLOTSYSTEM_PATH_AUDIT.md` — stale path audit scope of this gate
- `modules/PLOT_CONTROLS_SPLIT_PLAN.md` — PlotControl ownership split this gate validates
- `TECH_DEBT_DYNAMIC_WORKSPACE_STORE_OWNERSHIP.md` — V9 debt context
