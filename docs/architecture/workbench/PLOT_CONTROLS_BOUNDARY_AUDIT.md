# Plot Controls Boundary Audit

**Date:** 2026-07-01  
**Scope:** XY/Standard Cartesian, DualAxis, Heatmap  
**Purpose:** Identify control ownership mismatches before any P1 refactor. No refactoring is performed here.

---

## Current Architecture

The workbench left column exposes a `plotControls` slot (injected via `WorkflowWorkspaceLeftColumn`). Each workflow view owns this slot and decides which panel to render. The three plot types in scope use three distinct panels:

| Plot type | Controls panel | Container |
|---|---|---|
| XY / Standard Cartesian | `WorkbenchStandardPlotControls` → wraps `WorkbenchPlotControlsPanel` | `GroupBox("Plot Controls")` |
| DualAxis (Temperature Dependence) | `DualAxisPlotControlsPanel` | standalone `VStack` of `GroupBox` sections |
| Heatmap | `HeatmapPlotControlsPanel` | `GroupBox("Plot Controls")` |

For 3ω, the active tab determines which panel is rendered: all non-TD tabs use `WorkbenchStandardPlotControls`; the `temperatureDependence` tab switches to `DualAxisPlotControlsPanel`. This switch is implemented inside the 3ω workflow view (`ThreeOmegaWorkspaceView`), not in any shared shell.

---

## Per-Plot-Mode Breakdown

### XY / Standard Cartesian

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
| Font sizes | `SharedPlotFontSizeControls` | Below axis range |
| Series order panel | `WorkbenchSeriesOrderPanel` (supplemental slot) | Bottom |

**Ownership classification:**

| Control | Correct level | Currently placed |
|---|---|---|
| Tab picker | workspace-level | XY/Standard — **MISPLACED** |
| Stack offset + gap | workspace-level | XY/Standard — **MISPLACED** |
| Title template | plot-common | XY/Standard |
| Grid toggle | plot-common | XY/Standard |
| Label overrides | plot-common | XY/Standard (via `SharedPlotTextControls`) |
| Draw mode + tick count | plot-type-specific (XY) | `WorkbenchPlotControlsPanel` |
| Series appearance | plot-type-specific (XY) | `WorkbenchPlotControlsPanel` |
| Axis range | plot-type-specific (XY) | `WorkbenchPlotControlsPanel` |
| Font sizes | plot-common | `WorkbenchPlotControlsPanel` |
| Series order | plot-type-specific (XY) | `WorkbenchPlotControlsPanel` (supplemental) |

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
| Axis range bounds | plot-type-specific (DualAxis) | DualAxis-specific ✓ |
| Series styles | plot-type-specific (DualAxis) | DualAxis-specific ✓ |
| Axis color policy | plot-type-specific (DualAxis) | DualAxis-specific ✓ |
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
| Tick count | plot-type-specific (Heatmap) | Heatmap ✓ |
| Color scale / colormap | plot-type-specific (Heatmap) | Heatmap ✓ |
| Colorbar / Z label | heatmap-specific | Heatmap ✓ |
| Z range | heatmap-specific | Heatmap ✓ |
| Host controls slot | workflow-specific | Heatmap (injected) ✓ |

---

## Identified Misplacements

### P1 — Tab picker is workspace-level but owned by XY controls

**Problem:** `WorkbenchStandardPlotControls` embeds a SwiftUI `Picker` that drives the active tab for the whole workspace. This picker is the primary navigation control — it is used across all non-DualAxis 3ω tabs, and for any multi-tab XY/standard workflow. However, because it lives inside an XY-specific panel, non-XY plot types (DualAxis, Heatmap) have no access to it via the shared shell.

For 3ω specifically, the `temperatureDependence` tab switches the entire controls panel to `DualAxisPlotControlsPanel`, which has no tab picker. The user cannot navigate away from the TD tab using the controls panel; they must use a different mechanism or the tab must not be activated via the panel at all. This is architecturally wrong: tab navigation is workspace-level state and must be accessible from all plot views.

**Current location:** `WorkbenchStandardPlotControls` — Row 1, inside the XY panel.  
**Correct location:** workspace-level, outside any plot-type-specific panel.

### Minor — Stack offset and gap are workspace-level but co-located with XY controls

Stack offset multiplier and gap fraction are workspace-level stacking parameters, not XY-specific. They appear in Row 1 of `WorkbenchStandardPlotControls` next to the tab picker. Their placement is a consequence of the tab picker being there. They should move together with the tab picker when that refactor is done.

---

## Candidate Control Classification

| Control | Classification | Refactor risk |
|---|---|---|
| Tab picker | workspace-level — **must move** | Medium: needs a workspace-level shell slot to inject into |
| Stack offset + gap | workspace-level — move with tab picker | Low: pure bindings, no layout complexity |
| Title override / template | plot-common — can be extracted later | Low |
| Label overrides (X/Y/Z) | plot-common — already uses `SharedPlotTextControls` | Low |
| Font sizes | plot-common — already uses `SharedPlotFontSizeControls` | Low |
| Axis controls (XY range) | XY-specific — do not generalize | — |
| Axis controls (DualAxis range) | DualAxis-specific — do not generalize | — |
| Series controls (XY) | XY-specific — do not create universal SeriesControl | — |
| Series controls (DualAxis) | DualAxis-specific — left/right styles are not the same as XY series | — |
| Legend placement anchor | plot-common candidate; series legend internals are plot-type-specific | Medium: legend internals diverge |
| Heatmap colorbar / color scale | heatmap-specific | — |
| Heatmap Z range | heatmap-specific | — |

---

## Recommended First Move (Minimal Safe Change)

Move **only the tab picker and stack offset/gap row** out of `WorkbenchStandardPlotControls` into a workspace-level slot above the plot controls panel. This:

1. Fixes the P1 gap (DualAxis TD tab has no tab navigation).
2. Does not require touching `WorkbenchPlotControlsPanel`, `DualAxisPlotControlsPanel`, or `HeatmapPlotControlsPanel`.
3. Is purely additive to the shell slots in `WorkflowWorkspaceLeftColumn`.
4. The XY panel (`WorkbenchStandardPlotControls`) becomes thinner by one row; DualAxis and Heatmap gain tab navigation for free.

No other controls should move in this first pass. Title, labels, font sizes, and legend are plot-common candidates but carry cross-workflow risk — defer until the tab picker move is stable.