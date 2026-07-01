# Plot Controls Boundary Audit

**Date:** 2026-07-01  
**Scope:** Cartesian XY, DualAxis, Heatmap, shared Common control primitives  
**Purpose:** Lock the ownership boundary between plot-specific control surfaces and shared UI utilities. No refactoring is performed here.

---

## Current Architecture

The workbench left column exposes a `plotControls` slot (injected via `WorkflowWorkspaceLeftColumn`). Each workflow view owns this slot and decides which panel to render. The three plot types in scope use three distinct panels:

| Plot type | Controls panel | Container |
|---|---|---|
| Cartesian XY | `WorkbenchStandardPlotControls` → wraps `WorkbenchPlotControlsPanel` | `GroupBox("Plot Controls")` |
| DualAxis (Temperature Dependence) | `DualAxisPlotControlsPanel` | standalone `VStack` of `GroupBox` sections |
| Heatmap | `HeatmapPlotControlsPanel` | `GroupBox("Plot Controls")` |

For 3ω, the active tab determines which panel is rendered: all non-TD tabs use `WorkbenchStandardPlotControls`; the `temperatureDependence` tab switches to `DualAxisPlotControlsPanel`. This switch is implemented inside the 3ω workflow view (`ThreeOmegaWorkspaceView`), not in any shared shell.

---

## Ownership Table

| Layer | Owns | Must not own |
|---|---|---|
| Common shared controls | common row chrome, shared text rows, shared font-size pickers, shared tick-count row, label override primitives | axis/range logic, series style logic, colorbar logic, render payload state, plot-type-specific panel composition |
| Cartesian XY | XY title template behavior, Cartesian axis/range behavior, Cartesian series/order controls, `WorkbenchPlotPayload` render path | DualAxis display state, DualAxis render pipeline, Heatmap colorbar / Z-range / colormap controls |
| DualAxis | left/right axis labels, left/right manual ranges, left/right series family styles, `DualAxisDisplayState` / snapshot, `DualAxisRenderPipeline` | Cartesian title-template behavior, Cartesian axis range / series-order controls, Heatmap colorbar / Z-range / colormap controls |
| Heatmap | colorbar, Z range, colormap, heatmap payload/render path | Cartesian series-order controls, DualAxis label/range/style controls, `WorkbenchPlotPayload` render path |

---

## Per-Plot-Mode Breakdown

### Cartesian XY

**Current control modules:**

| Control | Module | Physical location |
|---|---|---|
| Tab picker | `WorkbenchStandardPlotControls` (Row 1) | Top of left column controls |
| Stack offset slider + gap field | `WorkbenchStandardPlotControls` (Row 1) | Adjacent to tab picker |
| Title template field | `WorkbenchTitleTemplateField` (Row 2) | Second row |
| Grid toggle | `WorkbenchStandardPlotControls` (Row 2) | Second row |
| Point tags toggle | `WorkbenchStandardPlotControls` (Row 2, optional) | Second row |
| Label overrides (title/X/Y) | `SharedPlotTextControls` (Row 3, conditional) | Third row |
| Extra slot | `WorkbenchStandardPlotControls.extraContent()` | Below Row 3 |
| Draw mode + tick count steppers | `WorkbenchPlotControlsPanel` | Below extra content |
| Series appearance (line width, scatter radius) | `WorkbenchSeriesAppearanceControls` | Below draw mode |
| Axis range (X/Y min/max) | `WorkbenchAxisRangeControls` (optional) | Below series appearance |
| Font sizes | `SharedPlotFontSizePicker` via `WorkbenchPlotControlsPanel` | Below axis range |
| Series order panel | `WorkbenchSeriesOrderPanel` (supplemental slot) | Bottom |

**Ownership classification:**

| Control | Correct level | Currently placed |
|---|---|---|
| Tab picker | workspace-level | Cartesian XY — **MISPLACED** |
| Stack offset + gap | workspace-level | Cartesian XY — **MISPLACED** |
| Title template | plot-common | Cartesian XY |
| Grid toggle | plot-common | Cartesian XY |
| Label overrides | plot-common | Cartesian XY (via `SharedPlotTextControls`) |
| Draw mode + tick count | Cartesian XY-specific | `WorkbenchPlotControlsPanel` |
| Series appearance | Cartesian XY-specific | `WorkbenchPlotControlsPanel` |
| Axis range | Cartesian XY-specific | `WorkbenchPlotControlsPanel` |
| Font sizes | plot-common | `WorkbenchPlotControlsPanel` |
| Series order | Cartesian XY-specific | `WorkbenchPlotControlsPanel` (supplemental) |

---

### DualAxis

**Current control modules:**

| Control | Module | Physical location |
|---|---|---|
| Title override | `DualAxisPlotControlsPanel` — Labels GroupBox | Top |
| X / Left Y / Right Y label overrides | `DualAxisPlotControlsPanel` — Labels GroupBox | Top |
| X / Left Y / Right Y range bounds | `DualAxisPlotControlsPanel` — Ranges GroupBox + `DualAxisRangeBoundField` | Middle |
| Range reset button | `DualAxisPlotControlsPanel` — Ranges GroupBox | Middle |
| Left series style (line pattern, marker shape, fill) | `DualAxisPlotControlsPanel` — Left Series GroupBox | Middle |
| Right series style | `DualAxisPlotControlsPanel` — Right Series GroupBox | Middle |
| Axis color policy | `DualAxisPlotControlsPanel` — Axis Colors GroupBox | Bottom |

**No tab picker is present in `DualAxisPlotControlsPanel`.**  
Tab navigation for 3ω while on the `temperatureDependence` tab is therefore absent — the panel provides no way to switch to another tab without going back to a non-TD tab first.

**Ownership classification:**

| Control | Correct level | Currently placed |
|---|---|---|
| Label overrides | plot-common | DualAxis-specific |
| Title override | plot-common | DualAxis-specific |
| Axis range bounds | DualAxis-specific | DualAxis-specific ✓ |
| Series styles | DualAxis-specific | DualAxis-specific ✓ |
| Axis color policy | DualAxis-specific | DualAxis-specific ✓ |
| **Tab picker** | **workspace-level** | **ABSENT from DualAxis panel** |

---

### Heatmap

**Current control modules:**

| Control | Module | Physical location |
|---|---|---|
| Host controls (workflow-injected) | `HeatmapPlotControlsPanel.hostControls` slot | Row 1 |
| Color scale toggle + colormap picker | `HeatmapColorScaleControls` | Row 1 |
| Tick count | `SharedPlotTickCountControls` | Row 1 |
| Label overrides (title/X/Y) | `SharedPlotTextControls` | Row 2 |
| Colorbar toggle + Z label override | `HeatmapZLabelControl` | Row 3 |
| Font sizes | `SharedPlotFontSizeControls` | Row 3 |
| Z range control | `HeatmapZRangeControl` (conditional) | Row 4 |

**No tab picker is present in `HeatmapPlotControlsPanel`.**  
RSM is currently the only heatmap workflow and it has no tab switching, so the absence is not yet a user-visible gap. It becomes one if a future workflow uses `HeatmapPlotControlsPanel` with multiple tabs.

**Ownership classification:**

| Control | Correct level | Currently placed |
|---|---|---|
| Label overrides | plot-common | Heatmap (via `SharedPlotTextControls`) |
| Font sizes | plot-common | Heatmap (via `SharedPlotFontSizeControls`) |
| Tick count | heatmap-specific | Heatmap ✓ |
| Color scale / colormap | heatmap-specific | Heatmap ✓ |
| Colorbar / Z label | heatmap-specific | Heatmap ✓ |
| Z range | heatmap-specific | Heatmap ✓ |
| Host controls slot | workflow-specific | Heatmap (injected) ✓ |

---

## Allowed Shared Control Imports

Only the following files are allowed to import or use the shared Common controls listed below:

| Shared control | Allowed consumers |
|---|---|
| `SharedPlotTextFieldRow` | `WorkbenchTitleTemplateField`, `SharedPlotLabelOverrideField`, `DualAxisPlotControlsPanel`, `HeatmapZLabelControl` |
| `SharedPlotTextControls` | `WorkbenchStandardPlotControls`, `HeatmapPlotControlsPanel` |
| `SharedPlotFontSizePicker` | `WorkbenchPlotControlsPanel` |
| `SharedPlotFontSizeControls` | `HeatmapPlotControlsPanel` |
| `SharedPlotTickCountControls` | `HeatmapPlotControlsPanel` |

These shared controls remain utility-only. They may own row chrome, binding plumbing, and local layout, but not plot-type ownership or render-path semantics.

---

## Forbidden Cross-Imports

The following import/use paths are explicitly forbidden:

- Cartesian XY controls must not import or reference `DualAxisPlotControlsPanel`, `DualAxisDisplayState`, `DualAxisRenderPipeline`, `HeatmapPlotControlsPanel`, `HeatmapColorScaleControls`, `HeatmapZLabelControl`, or `HeatmapZRangeControl`.
- DualAxis controls must not import or reference `WorkbenchStandardPlotControls`, `WorkbenchPlotControlsPanel`, `WorkbenchSeriesAppearanceControls`, `WorkbenchAxisRangeControls`, `HeatmapPlotControlsPanel`, `HeatmapColorScaleControls`, `HeatmapZLabelControl`, or `HeatmapZRangeControl`.
- Heatmap controls must not import or reference `WorkbenchStandardPlotControls`, `WorkbenchPlotControlsPanel`, `WorkbenchSeriesAppearanceControls`, `WorkbenchAxisRangeControls`, `DualAxisPlotControlsPanel`, `DualAxisDisplayState`, or `DualAxisRenderPipeline`.
- Common shared controls must not import or reference plot-type-specific modules.
- `WorkbenchPlotActionStrip` remains in the shared result shell and must not move into any plot-type-specific control surface.

---

## Identified Misplacements

### P1 — Tab picker is workspace-level but owned by Cartesian XY controls

**Problem:** `WorkbenchStandardPlotControls` embeds a SwiftUI `Picker` that drives the active tab for the whole workspace. This picker is the primary navigation control — it is used across all non-DualAxis 3ω tabs, and for any multi-tab Cartesian XY workflow. However, because it lives inside a Cartesian XY-specific panel, non-Cartesian plot types (DualAxis, Heatmap) have no access to it via the shared shell.

For 3ω specifically, the `temperatureDependence` tab switches the entire controls panel to `DualAxisPlotControlsPanel`, which has no tab picker. The user cannot navigate away from the TD tab using the controls panel; they must use a different mechanism or the tab must not be activated via the panel at all. This is architecturally wrong: tab navigation is workspace-level state and must be accessible from all plot views.

**Current location:** `WorkbenchStandardPlotControls` — Row 1, inside the Cartesian XY panel.  
**Correct location:** workspace-level, outside any plot-type-specific panel.

### Minor — Stack offset and gap are workspace-level but co-located with Cartesian XY controls

Stack offset multiplier and gap fraction are workspace-level stacking parameters, not Cartesian XY-specific. They appear in Row 1 of `WorkbenchStandardPlotControls` next to the tab picker. Their placement is a consequence of the tab picker being there. They should move together with the tab picker when that refactor is done.

---

## Candidate Control Classification

| Control | Classification | Refactor risk |
|---|---|---|
| Tab picker | workspace-level — **must move** | Medium: needs a workspace-level shell slot to inject into |
| Stack offset + gap | workspace-level — move with tab picker | Low: pure bindings, no layout complexity |
| Title override / template | plot-common — shared via `SharedPlotTextFieldRow` | Low |
| Label overrides (X/Y/Z) | plot-common — shared via `SharedPlotTextControls` + `LabelOverrideField` | Low |
| Font sizes | plot-common — shared via `SharedPlotFontSizeControls` + `SharedPlotFontSizePicker` | Low |
| Axis controls (Cartesian XY range) | Cartesian XY-specific — do not generalize | — |
| Axis controls (DualAxis range) | DualAxis-specific — do not generalize | — |
| Series controls (Cartesian XY) | Cartesian XY-specific — do not create a universal SeriesControl | — |
| Series controls (DualAxis) | DualAxis-specific — left/right styles are not the same as XY series | — |
| Legend placement anchor | plot-common candidate; series legend internals are plot-type-specific | Medium: legend internals diverge |
| Heatmap colorbar / color scale | heatmap-specific | — |
| Heatmap Z range | heatmap-specific | — |

### Shared primitive boundary

The following views are shared UI utilities only. They own row chrome and binding plumbing, but not panel ownership or plot semantics:

- `SharedPlotTextFieldRow`
- `SharedPlotTextControls`
- `SharedPlotLabelOverrideField` / `LabelOverrideField`
- `SharedPlotFontSizePicker`
- `SharedPlotFontSizeControls`

Their callers keep plot-type ownership of labels, ranges, styles, and payload mutation. In practice:

- Cartesian XY standard controls use `SharedPlotTextControls` for title/X/Y overrides and `SharedPlotFontSizePicker` for legend/point font sizes.
- DualAxis controls use `SharedPlotTextFieldRow` for its four label overrides, but keep range and series-style groups local.
- Heatmap controls use `SharedPlotTextControls`, `HeatmapZLabelControl`, and `SharedPlotFontSizeControls`; the Z/colorbar and Z-range controls remain heatmap-owned.

---

## Future Extraction Rules

Allowed future extraction:

- Move additional common row chrome into shared utility views when the code only formats labels, text fields, or pickers.
- Extract local helper subviews within an existing plot-type panel when the helper remains bound to that plot type's state.
- Split a plot-type panel into smaller plot-type-specific subviews without changing ownership.

Explicitly forbidden future extraction:

- Do not merge Cartesian XY, DualAxis, and Heatmap controls into one generic panel.
- Do not create a universal axis control, series control, or range editor that erases plot-type-specific ownership.
- Do not move axis controls, series controls, colorbar controls, range controls, or render payload ownership across plot types.
- Do not move `WorkbenchPlotActionStrip` into any plot-type-specific panel.
- Do not change pack/export semantics or physics formulas as part of control-boundary extraction.

---

## Recommended First Move (Minimal Safe Change)

Move **only the tab picker and stack offset/gap row** out of `WorkbenchStandardPlotControls` into a workspace-level slot above the plot controls panel. This:

1. Fixes the P1 gap (DualAxis TD tab has no tab navigation).
2. Does not require touching `WorkbenchPlotControlsPanel`, `DualAxisPlotControlsPanel`, or `HeatmapPlotControlsPanel`.
3. Is purely additive to the shell slots in `WorkflowWorkspaceLeftColumn`.
4. The Cartesian XY panel (`WorkbenchStandardPlotControls`) becomes thinner by one row; DualAxis and Heatmap gain tab navigation for free.

No other controls should move in this first pass. Title, labels, font sizes, and legend are plot-common candidates but carry cross-workflow risk — defer until the tab picker move is stable.
