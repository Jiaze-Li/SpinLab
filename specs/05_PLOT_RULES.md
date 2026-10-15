# Plot (Scientific Figure) Rules

Status: active
Scope: every scientific figure SpinLab renders — Cartesian XY, DualAxis, Heatmap (AFM, RSM) — in the live preview, PNG and PDF.
Sibling of `04_UI_RULES.md`, which governs app chrome. This file governs only text *inside rendered figures*; it does not change the UI font system.

---

## Text Style

- `[HARD][must]` **Arial only.** All figure text — title, axis titles, tick labels, legend, colorbar labels, scale bar, data/point labels, math annotations (sub/superscripts, Greek letters) — uses the Arial family. Regular, Bold and Italic may coexist.
- `[HARD][must]` **Pure black or pure white only.** Text color is opaque `#000000` or `#FFFFFF`. No gray, no series/curve color, no translucent text. Anti-aliasing fringe pixels do not count as a violation.
- `[HARD][must]` **No text stroke, no text shadow.**
- `[HARD][must]` Text outside the plot area is black by default. The in-figure AFM scale bar keeps its black/white choice (white default).
- Font size stays user-adjustable through the existing controls. This spec sets no global size cap.
- Curves, markers, colorbar gradients, axis lines, scale-bar bar and auxiliary grid lines are **not** text and keep their own colors.
- Preview, PNG and PDF share the same text style; no render path may style text on its own.

## Compatibility

- Old Packs and user settings that carry a non-Arial `plotFontName` / `plotBoldFontName` (e.g. Times New Roman) must still decode. They are resolved to Arial at render time; the stored value is never a reason to emit a non-Arial face.
- Old Packs or code that request a colored/gray text color are resolved to black (white only when white is requested).

## Single Entry Points

| Concern | Entry point | Location |
|---|---|---|
| Font family + text color resolution, shared text line factory | `PlotTextPolicy` | `Sources/SpinLabApp/Workbench/V3/PlotTextPolicy.swift` |
| Per-figure style carrier (sizes, font slots, transparent bg) | `WorkbenchChartStyle` (`makeTextLine`, `ctFont`) | `Sources/SpinLabApp/Workbench/V3/WorkbenchChartStyle.swift` |
| Math markup (sub/superscript, Greek) | `MathMarkupRenderer` — uses `PlotTextPolicy` | `Sources/SpinLabApp/Workbench/V3/MathMarkupRenderer.swift` |

Rules for code:

- Plot text code must not call `CTFontCreateWithName` / `CTFontCreate*` / `NSFont` / `UIFont` directly; use `PlotTextPolicy.font` or `WorkbenchChartStyle.makeTextLine`.
- Plot text code must not set `kCTStrokeColorAttributeName`, `kCTStrokeWidthAttributeName`, `setShadow`, or `setTextDrawingMode` to a stroke mode.
- Text color arguments must be `PlotTextPolicy.black` / `PlotTextPolicy.white` (the policy also snaps any other value defensively).

## Enforcement

1. **Plot Style Guard** — `scripts/check_plot_style.sh` scans plot renderer sources for the code rules above. Self-test with a deliberately violating fixture: `scripts/test_plot_style_guard.sh`.
   There is no inline exemption (a `plot-style:allow` comment is ignored and has its own rejecting fixture); the only exempt files are the two owner files, `PlotTextPolicy` and `MathMarkupRenderer`, fixed inside the script.
2. **Behavior tests** — `Tests/SpinLabAppTests/PlotStyleRulesTests.swift` renders real XY, DualAxis and Heatmap output and inspects fonts and pixels (PNG and PDF).
3. **CI** — `.github/workflows/plot-style-guard.yml` runs the guard on every pull request. Making it a *required* status check is a repository-admin setting (Branch protection / ruleset → require check `Plot Style Guard`); the workflow file alone does not enforce merging.
