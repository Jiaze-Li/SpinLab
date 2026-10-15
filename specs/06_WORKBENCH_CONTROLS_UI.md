# Workbench Controls UI Specification

Status: active (single source of truth for Workbench controls layout). §1–§9 describe the target contract; types, scripts and tests named here are introduced by the Enforcement phase and the legacy path in §10 is removed by the Migration phase.
Scope: the left-column **Controls Surface** of every Workbench workflow.

This document is the only normative definition of how Workbench controls are
grouped, owned, laid out and enforced. Other documents (`04_UI_RULES.md`,
`05_PLOT_RULES.md`, `PLOT_SYSTEM.md`, `PLOT_CONTROLS_SPLIT_PLAN.md` (marked superseded),
`ADDING_WORKFLOW.md`, `WORKFLOW_EXTENSION.md`, `AGENTS.md`, `CLAUDE.md`) **link here and
must not restate the rules**. Debt status for any
exception lives only on the shared task board, never here.

Rule IDs (`CS-n`) are stable so checks and tests can cite them.

---

## 1. Three-section contract

Every workflow's controls are rendered by exactly one shared view,
`WorkbenchControlsSurface`, as three sections in a **fixed order**:

```
Common            ← identical for every workflow
Plot              ← identical for every workflow that uses the same Plot Mode
Workflow Specific ← supplied by the workflow, laid out by shared primitives
```

- **CS-1** A workflow mounts controls only through `WorkbenchControlsSurface`.
  It supplies: a `WorkbenchControlsPlotAdapter` (which names the Plot Mode and
  carries state + callbacks), a `WorkbenchCommonControlsModel`, and an optional
  Specific builder. Nothing else about Common or Plot is a workflow decision.
- **CS-2** Section order is Common → Plot → Specific. It never varies.
- **CS-3** A workflow without Specific controls shows no Specific section (no
  divider, no empty box).
- **CS-4** Tab/workflow navigation (tab pickers, search, Load, Analyze) belongs
  to **Workspace Navigation** (`WorkflowWorkspaceLeftColumn` / action bar). It is
  neither Common nor Plot and is not duplicated inside the Surface.
- **CS-5** Result lists, status, traces, fit result panels are **not controls**
  and never live in the Surface (they belong to the result columns).

## 2. Ownership

| Layer | Owns | Must not |
|---|---|---|
| Surface / Common / Plot components | Which controls exist, order, labels, spacing, responsive behaviour, local edit drafts and focus | Read a concrete workflow store, branch on workflow id/kind, trigger analysis, persist, decide re-render policy |
| Workflow adapter (the workflow's `…WorkspaceView`) | Reading its store, building the model (values + callbacks), re-render and snapshot-flush policy, which Plot Mode applies to the active tab | Re-implement or re-arrange Common/Plot controls, add layout containers around them |
| Specific controls | Workflow-specific inputs, expressed as values + `Binding`s + callbacks | Choose shared layout strategy (GeometryReader, width `@State`, `ViewThatFits`, fixed widths that bypass shared primitives), read the store directly |

- **CS-6** Shared components (`ControlsSurface/`, `Controls/Common`,
  `Controls/CartesianXY`, `DualAxis`, `Heatmap` controls) do not import or
  reference any concrete workflow store, tab type, or workflow id.
- **CS-7** UI components may keep editing drafts / focus state locally
  (`LabelOverrideField`, `PlotAxisBoundField`); they never perform scientific
  processing or persistence.

## 3. Common section (all workflows)

Component: `WorkbenchCommonControls`. Controls, in order:

1. **Show Title** (checkbox)
2. **Plot Title** override field (label "Plot title"; placeholder shows the rendered title)
3. **Title Size** (font-size menu; writes shared `titleFontSize`)
4. **Transparent** background (checkbox; writes shared `transparentBackground`)

- **CS-8** Same control set, labels, order, spacing and responsive behaviour for
  all seven workflows. Values (e.g. per-tab show-title) may differ.
- **CS-9** *Plot title override* is not the *title template*. The template
  (Cartesian XY / DualAxis) is a Plot control (§4) and keeps its own semantics.
- **CS-10** Common takes state as plain values/closures
  (`WorkbenchCommonControlsModel`); it has no knowledge of Plot Mode.

## 4. Plot section (per Plot Mode)

Component per mode, selected only by the adapter's `WorkbenchPlotMode`:

| Plot Mode | Component | Standard controls (order) |
|---|---|---|
| `cartesianXY` | `CartesianXYPlotControls` | Title Template (+Point Tags capability) · Stack Offset / Gap · Draw/Line/Scatter + Grid · Axis Labels (X, Y) · Axis Ranges (+Reset) · Tick Counts · Typography (Axis, Ticks, Legend, Point) · Series Appearance (line/marker/colour style) · Series Order/Visibility/Rename |
| `dualAxis` | `DualAxisPlotControls` | Title Template · Axis Labels (X, L-Y, R-Y) · Axis Ranges (X, L-Y, R-Y, +Reset) · Tick Counts (X, L-Y, R-Y) + Axis Color Policy · Typography (Axis, Ticks, Legend, Point) · Left/Right Series Appearance |
| `heatmap` | `HeatmapPlotControls` | Color Scale · Interpolation · Colorbar · Z Range |

- **CS-11** The mode's component alone decides the control list, order and
  responsive layout. No workflow-specific branch inside a mode component.
- **CS-12** The standard control list of a mode is **fixed and always present**.
  Data-dependent availability (no data, no override to reset, nothing to
  reorder) only changes `enabled`, never presence. Required callbacks are
  non-optional parameters of the mode's model, so a workflow cannot remove a
  standard control by passing `nil`.
- **CS-12a** The only conditional content is **typed Plot-Family capabilities**,
  declared per mode and decided by the mode component alone:

  | Mode | Capability | Rule |
  |---|---|---|
  | `cartesianXY` | `.pointTags` (OptionSet member, default off) | Adds a Point Tags checkbox to the Title Template row |
  | `cartesianXY` | Series panel | Rendered iff the active payload has series (content-driven, identical for every workflow). `dualAxis` has no series panel; its Left/Right series appearance is a standard control |
  | `heatmap` | none | — |

  Adding a capability requires editing this table, the mode component and its
  contract test.
- **CS-13** Common's controls (title visibility, title override, title size,
  transparent) are **not** rendered by Plot components.
- **CS-14** A new Plot Mode must add its own shared Plot component, extend
  `WorkbenchPlotMode`/adapter, and ship its controls-contract tests before any
  workflow uses it.

### 4.1 Special cases

- **AFM and RSM** use identical Common and `heatmap` Plot sections (CS-15).
  The `heatmap` Plot section contains exactly the controls that are valid and
  rendered for **both** workflows: Color Scale, Interpolation, Colorbar, Z Range.
  Per-control decision (AFM renders it? → owner):

  | Control | AFM renders | Owner |
  |---|---|---|
  | Color Scale / Interpolation / Colorbar / Z Range | yes | Heatmap Plot |
  | Title visibility / title override / title size / transparent | yes | Common |
  | X / Y axis labels | no (axis-free figure) | RSM Specific |
  | X / Y tick counts | no | RSM Specific |
  | Z (colorbar) label override | no (no Z title drawn) | RSM Specific |
  | Axis-title and tick-label font sizes | no (not exposed for AFM today; adding them would change AFM behaviour) | RSM Specific |

  RSM's axis controls are built from the shared Plot-System primitives
  (`LabelOverrideField`, `SharedPlotTickCountControls`, `SharedPlotFontSizePicker`);
  RSM supplies only state and callbacks. AFM receives no axis controls (CS-16).
- **3ω** chooses the Plot Mode from the *rendered* output of the active tab:
  Temperature Dependence → `dualAxis`; every other tab → `cartesianXY`. The
  adapter returns the mode; the Surface swaps the Plot component (CS-17).

## 5. Workflow Specific section

Specific content is grouped by function into **Specific groups**
(`WorkbenchControlGroup` with a title), each containing responsive rows.

- **CS-18** Specific content is **typed at its entry point**. The Surface's only
  Specific parameter is `WorkbenchSpecificContent`, built with
  `@WorkbenchSpecificBuilder` from `WorkbenchSpecificGroup(title:)` values whose
  rows are `WorkbenchSpecificRow(label:, inputs:)`. Inputs are typed constructors
  (`.toggle`, `.menu`, `.number`, `.text`, `.stepper`, `.button`, `.readout`) or
  `.control(_:)` wrapping a workflow's own view that conforms to
  `WorkbenchLeafInput`. The **shared UI layer owns the outer layout**: how groups
  and rows are placed, wrapped, split into columns, where labels go, and the
  responsive breakpoints. A leaf input **may implement its own internal compound
  interaction and internal arrangement** (e.g. the fit-range add/remove editor,
  per-file φ-offset list, geometry fields with units) using ordinary SwiftUI
  stacks; it receives the width the Surface offers and must fit inside it. Passing
  an arbitrary `View` directly as Specific, or letting a workflow place
  Specific groups/rows itself, does not type-check.
- **CS-19** Target groups (semantic; a group need not be its own file):

| Workflow | Plot Mode | Specific groups |
|---|---|---|
| AHE | cartesianXY | Metric Overrides (Hc, R_AHE) |
| IV | cartesianXY | Input (current basis) · Channel Assignment · Fitting · Angular Analysis |
| RT | cartesianXY | none (no Specific section) |
| XY Rotation | cartesianXY | Data Correction (Center, Detrend) · Plot Annotation (x=180) · Per-file Calibration (φ offset per file) |
| 3ω | dualAxis (Temperature Dependence) / cartesianXY (others) | Transport Geometry · Fit Range (Scaling tab) · RAHE Method (RAHE tabs) · Auxiliary Input (RT selection search) |
| RSM | heatmap | View Selection · RSM Axis Controls |
| AFM | heatmap | Data Channel · Processing · Plot Decoration (Scale Bar) |

  *Auxiliary Input* for 3ω is the RT-selection field; it is a 3ω **Specific**
  group (not Workspace Navigation) and is rendered inside the Specific section.

## 6. Responsive layout (shared, workflow-independent)

Layout depends only on the **actual width offered to the Surface**, measured by
SwiftUI `Layout` containers — never on workflow ids or window width.

- **CS-20** Primitives: `WorkbenchControlFlow` (wraps *groups* onto new lines),
  `WorkbenchControlRow` (label + input; label beside input when it fits, label
  above input when it does not), `WorkbenchControlGroup`.
- **CS-21** Wide: related groups sit on one line. Narrow: whole groups wrap.
  Narrower than a group's minimum: the group's internal rows go single-column
  (label above input).
- **CS-22** Required at every width, including the representative widths
  **300, 364, 420, 520, 720 pt**: no overlap, no clipped required input or
  action, no font shrinking to fit, required actions reachable.
- **CS-23** Logical pairs (Min/Max range, X/L-Y/R-Y bound groups, stack slider +
  gap) are never split across lines.
- **CS-24** Layout changes preserve edit drafts, focus and saved state (views keep
  structural identity across width changes; no `if width < n` view swaps that
  recreate fields).
- **CS-25** Outer layout and responsive policy (group/row placement, wrapping,
  columns, breakpoints, offered width) are owned only by the shared `Layout`
  containers in `ControlsSurface/`. HStack/VStack/Grid inside a leaf input for
  its own internal arrangement are allowed. What Specific code must **not** do is
  *measure or react to the container's width to drive outer layout*, i.e. use
  `GeometryReader`, `ViewThatFits`, `onGeometryChange`,
  `containerRelativeFrame`, width-tracking `@State`, or define its own
  `Layout`/`AnyLayout` for placing groups. The deny-set is data in
  `ControlsSurface/WorkbenchLayoutPolicyIdentifiers.swift`. Scope is **by
  declaration, not by filename**: every Swift file that declares a
  `WorkbenchLeafInput` conformance or references `WorkbenchSpecificBuilder` /
  `WorkbenchSpecificGroup` is scanned (AST identifier scan, comments/strings
  excluded). Behavioural enforcement is I6: real layout of the full surface,
  Specific included, at every representative width.
- **CS-25a** Accessibility (owned by the shared primitives so every workflow gets it):
  every input has an accessibility label equal to its visible row label (inputs
  with a compact or hidden label get one from `WorkbenchControlRow`); keyboard
  focus/tab order follows visual reading order (group order, then row order, then
  input order) and is unchanged when groups wrap; each `WorkbenchControlGroup` is
  exposed as one accessibility container titled with the group title; every
  control gets a stable accessibility identifier
  `controls.<section>.<group>.<row>[.<input>]` (section ∈ common/plot/specific),
  independent of width; icon-only buttons carry accessibility labels (per
  `04_UI_RULES.md`).
- **CS-26** The Surface sizes to its content; the result list below remains
  reachable (the left column scrolls vertically when controls grow).
- **CS-27** Spacing from `AppSpacing`, text from `WorkbenchUIStyle`; no bare
  numeric spacing literals in new code.

## 7. State and event interface

- **CS-28** Shared components receive immutable values plus closures/bindings. A
  workflow adapter builds the model:
  `WorkbenchCommonControlsModel`, and a `WorkbenchControlsPlotAdapter` case
  (`.cartesianXY(CartesianXYControlsModel)`, `.dualAxis(DualAxisControlsModel)`,
  `.heatmap(HeatmapControlsModel)`).
- **CS-29** Re-render and snapshot-flush policy stays in the adapter closures
  (`onChange` vs `onTransientChange` semantics are preserved).
- **CS-30** Pack/Restore, persisted keys and defaults are unchanged by layout.

## 8. Extension rules

Adding a workflow (see `ADDING_WORKFLOW.md`):

1. Declare its Plot Mode(s) — `WorkbenchWorkflowKind.controlsPlotModes`
   (compile-time exhaustive).
2. Provide the adapter (values + callbacks) in its `…WorkspaceView`.
3. Provide Specific controls (optional) with shared primitives.
4. Common and Plot are assembled automatically by `WorkbenchControlsSurface`.
5. Pass the Controls Contract tests (`ControlsContract*Tests`) and
   `scripts/check_controls_contract.sh`.

- **CS-31** `WorkbenchWorkflowKind` is the registry: every case must return a
  non-empty `controlsPlotModes` and a `controlsSurfaceMount` mapping; the contract
  test enumerates `allCases`, so a new case is checked without editing a test list.
- **CS-32** Anything mounting `WorkbenchControlsSurface` is a Workspace view
  registered in `WorkflowWorkspaceRegistry`. Direct use of a mode component
  (`CartesianXYPlotControls`, `DualAxisPlotControls`, `HeatmapPlotControls`) or
  `WorkbenchCommonControls` outside `ControlsSurface/` and the Surface itself is
  a violation.

## 9. Automated invariants (verified by tests + CI)

| ID | Invariant | Verified by |
|---|---|---|
| I1 | Every `WorkbenchWorkflowKind` case declares ≥1 Plot Mode and mounts via the Surface | `ControlsContractRegistryTests` |
| I2 | Workflow adapter files reference only the Surface/adapter types, never a Common/Plot component type (AST identifier scan of the compiler parse tree, `swiftc -dump-parse`: comments and string literals are excluded by construction) | `ControlsContractASTTests` + `check_controls_contract.sh` |
| I3 | Shared controls files reference no concrete workflow store/tab/kind identifier (same AST identifier scan; identifiers come from `WorkbenchWorkflowKind.allCases`' registry, not a hand list) | `ControlsContractASTTests` + `check_controls_contract.sh` |
| I4 | Specific cannot take over outer layout: (a) typing — arbitrary `View`, or placing groups/rows outside the Surface, does not compile (negative typecheck fixtures); (b) AST scan of files that declare `WorkbenchLeafInput` conformances or use `WorkbenchSpecificBuilder`/`WorkbenchSpecificGroup` finds none of the width-measuring identifiers in `WorkbenchLayoutPolicyIdentifiers` (internal HStack/VStack are permitted); (c) Specific content stays in bounds at all representative widths (covered by I6) | `scripts/test_controls_contract.sh` + `ControlsContractASTTests` + `ControlsSurfaceLayoutTests` |
| I5 | Same Plot Mode ⇒ identical control inventory & order for different adapters | `ControlsSurfaceLayoutTests` (real SwiftUI host) |
| I6 | At 300/364/420/520/720 pt: no overlap, no clipping, in-bounds | `ControlsSurfaceLayoutTests` |
| I7 | Negative samples (violations) are rejected by the check | `scripts/test_controls_contract.sh` |
| I8 | AFM and RSM have identical Common and Heatmap Plot inventory | `ControlsSurfaceLayoutTests` |
| I9 | Common inventory/order/labels identical across all seven workflows' surfaces (IV vs AFM included) | `ControlsSurfaceLayoutTests` |
| I10 | Edit drafts, focus and saved values survive width changes | `ControlsSurfaceLayoutTests` (resize same host) |
| I11 | Results list stays reachable: left column scrolls vertically when controls grow | `ControlsSurfaceLayoutTests` |
| I12 | Real SwiftUI hosting covers **all seven** full surfaces (and every 3ω tab); source-text checks never substitute | `ControlsSurfaceLayoutTests` |
| I13 | No-clipping is proven against each group's required minimum size from the shared Layout, not a fixed parent's `fittingSize` | `ControlsSurfaceLayoutTests` + planner unit tests |
| I14 | No drag oscillation: layout of a given width is deterministic and a width sweep produces monotone row counts; surface body evaluation count is bounded | `ControlsSurfaceLayoutTests` + manual drag record (E7) |
| I15 | Every input in every surface has a non-empty accessibility label, a stable identifier of the CS-25a form, and identifiers/focus order are identical at all five widths | `ControlsSurfaceLayoutTests` (accessibility tree walk) |
| I16 | The Controls Contract CI check is a required status check on protected `main` (AC9). Verified by reading the live ruleset; if it is not configured the state is reported as HUMAN REQUIRED, never as enforced | `scripts/check_main_required_checks.sh` (read-only) |

Source-text checks strip comments and string literals first; they are secondary to
the type-level and real-layout checks above.

## 10. Legacy exceptions during migration

A temporary, bounded allow-list (`scripts/controls_contract_legacy_allowlist.txt`)
may name workflow views still on the legacy path. It may only shrink, must not
accept workflows created after the Surface lands, and **is deleted when the last
workflow migrates**. Its status is not tracked in this document.

## 11. Ownership map of current controls (E1) and legacy to migrate

Every existing control below has exactly one owner after migration.

| Control (today) | Today rendered by | Owner after migration |
|---|---|---|
| Show Title checkbox | Draw row of `WorkbenchPlotControlsPanel` (Cartesian); `CompactTypographyRow` (DualAxis); top row of `HeatmapPlotControlsPanel` | Common |
| Plot title override | `SharedPlotTextControls` (Cartesian); label row (DualAxis); `LabelOverrideField` (Heatmap) | Common |
| Title font size | `CompactTypographyRow`, `SharedPlotFontSizeControls`, `titleOnlyControls` | Common |
| Transparent background | `CompactTypographyRow`; Heatmap top row | Common |
| Title Template | `WorkbenchTitleTemplateSection` | Plot (cartesianXY, dualAxis) |
| Stack offset / Gap | per-workflow `…SpacingInlineControls` (AHE, IV, RT, XY, 3ω) | Plot (`cartesianXY` only). The 3ω Temperature Dependence tab showed it, but the DualAxis renderer does not consume stack/gap (inert control), so it is intentionally not part of `dualAxis`; the 3ω store keeps the values for its Cartesian tabs |
| Draw / Line / Scatter, Grid | `CompactPlotStyleRow` + `gridToggle` | Plot (cartesianXY) |
| X/Y labels, ranges, ticks, reset | `SharedPlotTextControls`, `CompactAxisRangeRow`, `CompactAxisTickCountRow` | Plot (cartesianXY) |
| X/L-Y/R-Y labels, ranges, ticks, axis colour, left/right series style | `DualAxisPlotControlsPanel` | Plot (dualAxis) |
| Axis/Ticks/Legend/Point font sizes | `CompactTypographyRow` | Plot (cartesianXY, dualAxis) |
| Series appearance, order, visibility, rename | `WorkbenchSeriesAppearanceControls`, `WorkbenchSeriesOrderPanel` | Plot (cartesianXY) |
| Color scale, interpolation, colorbar, Z range | `HeatmapPlotControlsPanel`, `HeatmapZRangeControl` | Plot (heatmap) |
| AHE Hc / R_AHE overrides | `AHEOverridesControls` | AHE Specific · Metric Overrides |
| IV current basis, channel, fit mode, zero-at-origin, angular toggle/fit mode/fold | `IVSpecificPlotControls` | IV Specific · Input / Channel / Fitting / Angular |
| XY Center, Detrend, x=180 | inline `HStack` in `XYRotationWorkspaceView` | XY Specific · Data Correction / Plot Annotation |
| XY φ offset per file | `XYRotationPhiOffsetPanel` (left extra) | XY Specific · Per-file Calibration |
| 3ω geometry, fit ranges | `ThreeOmegaGeometryPanel`, `ThreeOmegaTransportGeometryFields` | 3ω Specific · Transport Geometry / Fit Range |
| 3ω RAHE method | inline `Picker` | 3ω Specific · RAHE Method |
| 3ω RT selection field | `ThreeOmegaRTSearchField` (search extra) | 3ω Specific · Auxiliary Input |
| RSM view selector | `RSMViewSelector` (plugin section) | RSM Specific · View Selection |
| RSM X/Y/Z labels, X/Y ticks, axis/tick font sizes | inside `HeatmapPlotControlsPanel` (`showsAxisControls`) | RSM Specific · RSM Axis Controls |
| AFM channel, surface level, line flatten, zero reference, scale bar | `AFMPlotControls` | AFM Specific · Data Channel / Processing / Plot Decoration |
| Tab pickers (3ω, IV, XY), search, Load, Analyze | action bar / search section | Workspace Navigation (unchanged) |

**Legacy structures that migration must remove or fold into shared primitives**

- Three independent assemblers: `WorkbenchPlotControlsPanel` + `WorkbenchStandardPlotControls`
  (Cartesian), `DualAxisPlotControlsPanel`, `HeatmapPlotControlsPanel`. Replaced by
  the mode components behind `WorkbenchControlsSurface`.
- Divergent responsive strategies: `WeightedRowLayout` (`SharedPlotTextControls`,
  DualAxis labels), `ViewThatFits` (`AHESpecificPlotControls`,
  `HeatmapZRangeControl`), fixed two-column `LazyVGrid`
  (`WorkbenchPluginControlsGrid`, used by `AFMPlotControls`), fixed `HStack` rows.
  Replaced by `WorkbenchControlFlow`/`Row`/`Group`.
- Views reading concrete stores directly (`AHEOverridesControls`,
  `IVSpecificPlotControls`, inline 3ω panels, per-workflow `…SpacingInlineControls`).
  Moved behind adapters: the workflow view reads the store and passes values/closures.
- Reused as-is: `WorkbenchStandardPlotControls+StoreDriven` state adaptation for
  AHE/IV/RT/XY (it becomes the `CartesianXYControlsModel` builder), the typed
  `WorkbenchWorkflowKind` + `WorkflowWorkspaceRegistry` dispatch, and the shared
  field primitives (`LabelOverrideField`, `PlotAxisBoundField`, `SharedPlot*`).
- Tests that assert on source text (`V78*`, `V710*`, `V557*` structural tests)
  must be rewritten to the symbol/real-layout checks in §9 where they contradict
  this spec; comment-matching checks are removed.
