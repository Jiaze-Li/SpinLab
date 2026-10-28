# Workbench Controls UI Specification

Status: active (single source of truth for Workbench controls organisation and layout).
Scope: the left-column **Controls Surface** of every Workbench workflow.
Inheritance: this document inherits `04_UI_RULES.md` (typography, text colour, spacing scale,
button styles, accessibility basics, information rules, and the Control Visual Contract VC-1…VC-11:
text roles, minimum control sizes, baseline alignment, spacing relations, operability-first density, non-redundant labelling).
It defines only control organisation, ownership, layout and responsive behaviour, and never
redefines a global visual rule; a global rule is cited by ID, not restated.

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
Common            ← identical for every workflow and every Plot Mode
Plot              ← Shared + Plot-Specific modules, chosen by the Plot Mode's capabilities
Workflow Specific ← supplied by the workflow, laid out by shared primitives
```

### 1.1 Four ownership classes

Ownership is decided by functional semantics and reuse scope, not by which workflow first
implemented a control. Every control belongs to exactly one class.

| Class | Definition | UI region |
|---|---|---|
| **Common** | Used by every Plot Mode with the same control set and semantics | Common |
| **Shared** | Same functional semantics in ≥2 Plot Modes; the parameter set (axis count, available options) may differ per mode | Plot |
| **Plot-Specific** | Meaningful for exactly one Plot Mode | Plot |
| **Workflow-Specific** | Business capability of specific workflow(s) | Specific |

- **CS-1a** There are three UI regions only. Shared and Plot-Specific modules are arranged together in
  the Plot region with **no** ownership heading, border or divider between them.
- **CS-1b** A *module* is the unit of ownership; a *logical group* is the unit of layout (§6). One
  logical row may hold several modules, and a module may span several rows.
- **CS-1c** Differences between Plot Modes are expressed as explicit, typed **capability
  parameters** of the shared module (e.g. the list of axis roles). Shared modules never branch on a
  workflow id/kind (CS-6) and never read a workflow store. Parameters that merely share a name but
  differ in semantics are not merged into one module.

### 1.2 Plot Capability Matrix

Which module each Plot Mode renders. "—" = not rendered (the control would have no effect).

| Module | Class | `cartesianXY` | `dualAxis` | `heatmap` |
|---|---|---|---|---|
| Plot title · Show Title · Transparent · Title Template (+Available) | Common | ✓ | ✓ | ✓ |
| Typography (Font row) | Shared | Title · Axis · Ticks · Legend · Point | Title · Axis · Ticks · Legend | Title always; Axis · Ticks iff the mode has spatial axes |
| Axes: labels · ranges · tick counts | Shared | X, Y · labels + ranges + ticks | X, L-Y, R-Y · labels + ranges + ticks | X, Y · labels + ticks (no range, not yet implemented); none for axis-free figures |
| Curve Appearance: Draw · Line · Scatter/Marker · Grid | Shared | Draw, Line, Scatter, Grid (whole-group + per-series) | Left/Right series line/marker style; Draw/Grid only if the renderer supports them (today: —) | — |
| Point Tags | Plot-Specific | capability, default off | — | — |
| Gap (stacking) | Plot-Specific | ✓ | — (renderer does not consume it) | — |
| Series order / visibility / rename | Plot-Specific | iff payload has series | — | — |
| Axis colour policy | Plot-Specific | — | ✓ | — |
| Color scale · Interpolation · Colorbar · Z range | Plot-Specific | — | — | ✓ (Z range is Color Mapping, never a spatial axis range) |

Per workflow (Common is identical for all; Specific groups are listed in CS-19):

| Workflow | Plot Mode (capability configuration) | Shared modules rendered | Plot-Specific modules rendered |
|---|---|---|---|
| AHE, IV, RT, XY Rotation | `cartesianXY` | Typography (5 roles) · Axes X, Y · Curve Appearance | Gap · Series order/visibility · Point Tags (where enabled) |
| 3ω — Scaling, RAHE and other tabs | `cartesianXY` | as above | as above |
| 3ω — Temperature Dependence | `dualAxis` | Typography (4 roles) · Axes X, L-Y, R-Y · Curve Appearance (L/R series) | Axis colour policy |
| RSM | `heatmap`, with spatial axes | Typography (Title, Axis, Ticks) · Axes X, Y (labels, ticks) | Color Scale · Interpolation · Colorbar · Z Range |
| AFM | `heatmap`, axis-free | Typography (Title) | Color Scale · Interpolation · Colorbar · Z Range |

Heatmap has two typed capability configurations, chosen by the workflow adapter through the model
(not by a workflow id): **with spatial axes** (RSM: X/Y) and **axis-free** (AFM: none).
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

## 3. Common section (all workflows, all Plot Modes)

Component: `WorkbenchCommonControls`. Exactly these controls, in this order, for every
workflow and Plot Mode:

1. **Plot title** override field (label "Plot title"; placeholder shows the rendered title)
2. **Show Title** (checkbox) and **Transparent** background (checkbox) — the right-hand logical group
3. **Title template** field with its **Available** token hint

- **CS-8** Same control set, labels, order and interaction semantics for all seven workflows and all
  three Plot Modes. Values and the Available tokens may differ with the data. (Title Size is not Common:
  it is a Shared Typography control, CS-38.)
- **CS-9** *Title Template is Common.* One template field, one resolver (`WorkbenchTitleResolver`, one
  `#token` syntax) for every Plot Mode; no second parser. Available lists only the tokens the active data
  actually supports; a token that the data does not provide is never offered.
- **CS-9a** *Title priority:* manual Plot title > Title Template result > source-data default title.
  Show Title controls visibility only and never clears the title or template. Clearing the manual
  override restores the template result; an empty or unresolvable template falls back to the default
  title. The title drawn in the figure equals the title in the saved chart metadata (PNG/PDF included).
  Template tokens bind to the data source that was actually analyzed (for single-file workflows, the analyzed hit, restored with the Pack), never to the first search result, and the Available list shows only the tokens that workflow's renderer and the current data provide. Title edits never change scientific data. Saved manual overrides and existing Analysis Packs remain
  readable; new template state persists and restores (CS-30).
- **CS-10** Common takes state as plain values/closures (`WorkbenchCommonControlsModel`); it has no
  knowledge of Plot Mode. `pointTags` remains a `cartesianXY` Plot-Specific capability.

## 4. Plot section (per Plot Mode)

The Plot region is assembled from Shared modules and Plot-Specific modules per the Capability Matrix
(§1.2), selected only by the adapter's `WorkbenchPlotMode` and typed capability parameters. Shared
modules are implemented once (Typography, Axes, Curve Appearance) and reused by the mode components.

| Plot Mode | Component | Modules (reading order is a layout result, CS-39) |
|---|---|---|
| `cartesianXY` | `CartesianXYPlotControls` | Curve Appearance (Draw/Line/Scatter + Grid) · Axes (X, Y: labels, ranges + Reset, ticks) · Typography · Gap · Series Appearance · Series Order/Visibility/Rename, arranged as three logical rows (CS-38c) |
| `dualAxis` | `DualAxisPlotControls` | Axes (X, L-Y, R-Y: labels, ranges + Reset, ticks) · Axis Colour Policy · Typography · Left/Right Series Appearance |
| `heatmap` | `HeatmapPlotControls` | three logical rows (CS-38d): Colorbar + Linear/Log · Interpolation · Typography; Z Range; Axes (X, Y labels + ticks; only with spatial axes) |

- **CS-11** The mode's component alone decides which modules appear and how they flow. No
  workflow-specific branch inside a mode component or a Shared module.
- **CS-12** *Fixed per capability configuration.* For a given Plot Mode **and capability
  configuration**, the control list is fixed and always present. Data-dependent availability (no
  data, no override to reset, nothing to reorder) only changes `enabled`, never presence. Required
  callbacks are non-optional model parameters, so a workflow cannot remove a control by passing `nil`.
  The configuration itself (e.g. the axis roles) is a typed model parameter and is the only way
  presence varies.
- **CS-12a** Conditional content is limited to **typed capabilities**, declared here and decided by
  the mode component / shared module alone:

  | Scope | Capability | Rule |
  |---|---|---|
  | `cartesianXY` | `.pointTags` (OptionSet member, default off) | Adds a Point Tags checkbox beside the Title Template |
  | `cartesianXY` | Series panel | Rendered iff the active payload has series, identical for every workflow |
  | Shared Axes | axis roles (`X`, `Y`, `L-Y`, `R-Y`) | One control set per declared role; an empty role list renders no Axes module |
  | Shared Typography | font roles (`Title`, `Axis`, `Ticks`, `Legend`, `Point`) | One picker per declared role; `Title` always present |
  | `heatmap` | spatial axes (with / without) | Declared through the Axes and Typography role lists |

  Adding a capability requires editing this table, the shared module and its contract test.
- **CS-13** Common's controls (title, title visibility, template, transparent) are **not** rendered by
  Plot components. Title Size is rendered by Shared Typography only.
- **CS-14** A new Plot Mode must add its own shared Plot component, extend `WorkbenchPlotMode`/adapter,
  and ship its controls-contract tests before any workflow uses it.
- **CS-38** *Shared Typography.* One Font row for every mode, one picker per declared font role
  (including Title Size). It adds no section title. New font roles (e.g. colorbar, scale bar) are not
  added by this contract; existing workflow-specific font settings whose semantics are not unified stay
  in Specific.
- **CS-38a** *Shared Axes.* Per declared axis role: label override, tick count and (where the mode
  supports it) range with Reset. Shared Axes is configured by roles only. The label overrides show
  one shared caption and per-axis markers: `Label  X [field]  Y [field]` (DualAxis:
  `Label  X [field]  L-Y [field]  R-Y [field]`), applying VC-11 (no repeated "label" word). Each
  marker stays glued to its field and wraps with it as a whole; each field keeps its own
  accessibility name (`X axis label`, `Y axis label`, `Left Y axis label`, `Right Y axis label`). Heatmap Z Range belongs to
  Color Mapping, never to Axes. RSM has no spatial range control (not implemented, not added).
- **CS-38c** *Cartesian XY rows.* The `cartesianXY` Plot region is three logical rows, each its own
  justified flow so a row wraps by whole groups at narrow widths and aligns to the same right edge when
  it fits: (1) Draw · Line · Scatter · Label (X · Y); (2) Range X/Y · Reset ranges · Ticks X/Y;
  (3) Font (Title · Axis · Ticks · Legend · Point) · Gap · Grid (· Point Tags where enabled); Grid stays
  part of Shared Curve Appearance and only sits in row 3 for layout. In-row
  spacing is `WorkbenchControlMetrics.planeRowSpacing`; control widths are shared tokens in
  `WorkbenchInputWidth`. Tightening spacing is the only lever for fitting a row — fonts, hit areas and
  VC-4 minimums are never reduced, and a row that cannot fit wraps by whole groups.
- **CS-38b** *Shared Curve Appearance.* `cartesianXY` and `dualAxis` use the same Draw/Line/Marker
  semantics and primitives. `cartesianXY` applies them to the whole group; `dualAxis` keeps separate
  Left/Right series styles. Field lists need not match. A control whose effect the renderer does not
  implement is not shown. Heatmap does not use Curve Appearance.

- **CS-38d** *Heatmap rows* (applies CS-41, VC-8, VC-10, VC-11; AFM and RSM share it). The `heatmap`
  Plot region is three logical rows, each its own justified flow that wraps by whole groups:
  (1) **Colorbar checkbox + Linear/Log segmented control** (one visual group, no visible "Color scale"
  title; the segmented control keeps the accessibility name `Color scale`, and the two stay independent:
  Colorbar off never disables or changes Linear/Log) · **Interpolation** · **Font** (last in the row;
  AFM: Title; RSM: Title, Axis, Ticks); (2) **Z range** + its companion; (3) **Spatial Axes**
  `Label X/Y · Ticks X/Y` through Shared Axes (CS-38a), present only when the capability declares axes:
  AFM has no row 3 and no placeholder. Interpolation shows the visible label `Interp.` (accessibility
  name `Interpolation`), and the Interpolation and Preset menus take their native intrinsic width
  (`workbenchContentFitMenu`, VC-8), so each shows its longest option in full whichever option is
  selected; their rows are atomic, so a row too narrow for label and menu moves the label above the menu
  instead of squeezing it. The Interpolation menu shows the short title of each mode; the full scientific
  name is the tooltip and the accessibility value. Z range starts at the same place in Auto, Manual and
  Percentile; only the companion to its right changes: Auto adds nothing, Percentile adds Preset (which
  wraps whole to the next line when it does not fit), Manual adds one `Min / Max [min] – [max]` row (the
  row label is the only visible caption, the fields are joined by a decorative connector hidden from
  accessibility, their accessibility labels are `HeatmapZRangeAccessibility.minimum` / `.maximum`, the pair
  stays on one line and each field keeps its own VC-4 minimum). Switching mode moves neither row 1 nor row
  3 sideways, leaves no empty placeholder and loses no value, draft or validation message.
  *Manual validation:* an empty Min or Max is an unfinished draft, not an error banner: the empty field
  gets an outline, a tooltip and an accessibility hint ("Enter both Min and Max; the Auto range is used
  until then."), no text row is added, and the render still falls back to Auto. A value that is present
  but invalid or inverted keeps the red message under the Z range row.
  *Measured fit:* AFM row 1 fits one line from 667pt; the full RSM row 1 (with Title/Axis/Ticks) needs
  720pt on one line, so at 667pt it wraps by whole groups (a 53pt shortfall); fonts and pickers are never
  shrunk to close it.
- **CS-41** *Plot Mode layout consistency.* Within one Plot Mode, the same control has the same logical
  row, relative order and layout role in every workflow; workflows do not rearrange it. A capability
  configuration (CS-1c) may add or remove controls, but never changes where the other shared controls
  sit (e.g. RSM adds Axis/Ticks fonts at the end of the Font group and a Spatial Axes row below Z range;
  AFM keeps every shared control in the same place and shows no placeholder). Ownership (CS-1, Shared /
  Plot-Specific / Specific) and visual row position are independent: Shared Axes stays Shared even when
  only one configuration enables it, and no row position makes a control change class. The rule applies
  to every Plot Mode and does not require different Plot Modes to share a layout. Narrow windows may wrap
  responsively by whole groups (CS-39) but never compress a control, truncate text or change the
  semantic order. It reuses the ownership classes of CS-1b and CS-1c and the shared modules of
  CS-38/CS-39; it adds no new classification.
- **CS-38e** *DualAxis Left / Right rows* (applies VC-9). The two rows are one aligned table
  (`WorkbenchAlignedRows`) of the same five cells — Line, W, Marker, Size, Fill — behind a row label.
  The label column and each cell column take the larger width of the two rows, so the Left and Right
  pickers share their left edge column by column whatever is selected. Menu widths are the series
  tokens in `WorkbenchInputWidth`. When the width is short the table wraps by column bands and both
  rows break at the same column; text is never shrunk and nothing is clipped. The alignment does not
  extend to other controls.

### 4.1 Special cases

- **AFM and RSM** use the identical Common and the same `heatmap` Plot-Specific modules (Color Scale,
  Interpolation, Colorbar, Z Range) and Typography/Axes **differ only by their declared capability
  configuration** (CS-15):

  | Control | AFM | RSM | Owner |
  |---|---|---|---|
  | Title · Show Title · Transparent · Title Template | yes | yes | Common |
  | Title Size | yes | yes | Shared Typography |
  | Axis / Ticks font sizes | no (no spatial axes) | yes | Shared Typography |
  | X / Y axis labels, X / Y tick counts | no | yes | Shared Axes |
  | X / Y ranges | no | no (not implemented) | — |
  | Color Scale / Interpolation / Colorbar / Z Range | yes | yes | Heatmap Plot-Specific |
  | Z (colorbar) label override | no (no Z title drawn) | yes | RSM Specific |

  Both configurations are produced by the adapter through typed model parameters; neither the Shared
  modules nor the Heatmap component test a workflow id (CS-6, CS-16). AFM receives no axis controls.
- **3ω** chooses the Plot Mode from the *rendered* output of the active tab:
  Temperature Dependence → `dualAxis`; every other tab → `cartesianXY`. The
  adapter returns the mode; the Surface swaps the Plot component (CS-17).

## 5. Workflow Specific section

Specific content is grouped by function into **Specific groups**, each containing responsive rows.

- **CS-18a** *Group titles are not drawn.* A Specific group keeps its logical identity, stable
  identifiers and accessibility container title (CS-25a), but its title is never shown. Every input
  still carries a visible label that is unambiguous on its own: a row label, or a label drawn by the
  input itself (e.g. the two channel pickers sit under the row label "Channels"). Removing a title must never leave an
  unlabeled or ambiguous control. Only Specific content is Workflow-Specific; anything with Shared
  semantics (title, axes, fonts, curve style) is not placed here.

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
| RSM | heatmap | View Selection · Z Label |
| AFM | heatmap | Data Channel · Processing · Plot Decoration (Scale Bar) |

The group names above are logical identities (identifiers, accessibility); they are not drawn as visible titles (CS-18a).

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
  action, no font shrinking to fit, required actions reachable, and every
  interactive control at or above its VC-4 minimum (measured on the control itself).
- **CS-23** Logical pairs (Min/Max range, X/L-Y/R-Y bound groups, Gap label + field) are never split
  across lines of the Surface. A compound input wider than the
  offered width wraps *internally* through `WorkbenchControlFlow` (pair members stay
  adjacent: Min with Max, Gap label with its field) instead of compressing a control (VC-4, VC-7).
- **CS-23a** *Flexible widths and Justify (Plot region).* Wrapping is decided on ideal widths, so extra
  width never changes where a flow wraps. Leftover width on a line is then spent in this order:
  (1) inputs that declare themselves flexible (`workbenchFlowFill(maxGrowth:)`: text fields,
  X/Y label fields) grow evenly, each to its own bound; (2) only when the flow opts in
  (`WorkbenchControlFlow(justified: true)`, used by the Plot region and the Font / Draw rows) the rest is
  spread over the gaps between the groups of that line, each gap gaining at most `justifyMaxExtraGap`;
  (3) anything still left stays at the trailing edge. A line with one group, and the last line of a flow
  that wrapped, stay leading. Pickers, steppers and checkboxes never grow. Flexible inputs never go
  below their VC-4 minimum and never above their bound, so a single field cannot take the whole line.
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
  independent of width; icon-only buttons follow the accessibility rule in
  `04_UI_RULES.md`.
- **CS-26** The Surface sizes to its content; the result list below remains
  reachable (the left column scrolls vertically when controls grow).
- **CS-27** Controls take all text, size and spacing values from the token files named in
  `04_UI_RULES.md` (`WorkbenchUIStyle`, `WorkbenchControlMetrics`, `WorkbenchInputWidth`,
  `AppSpacing`); this document and individual views add no visual values of their own.
- **CS-33** *Line alignment.* Groups on the same line of `WorkbenchControlFlow` align on the
  first text baseline (VC-5), not on top edges. Common therefore reads as one baseline:
  Plot title · Show Title · Transparent · Title template, at any width where they share a line;
  where they wrap, each line is baseline-aligned and the order never changes (CS-8).
- **CS-34** *Common typography.* Show Title and Transparent checkboxes use the label role
  exactly like the Plot title and Title template labels (VC-2); the Plot title and Title template
  fields use the value role.
- **CS-35** *Gap control.* Stacking has one input, **Gap label + number field** (CS-23); there is no
  Stack slider, read-out or checkbox. Gap is any non-negative finite decimal and is stored exactly as
  typed (no step quantizing); an empty, negative, non-numeric or non-finite entry is rejected and the
  saved value stays. Gap = 0 leaves every curve at its measured position. Gap > 0 stacks the visible
  curves in series order (the existing order-enforcing bottom-to-top placement) so the net gap between
  the vertical envelopes of neighbouring curves is the same for every pair: **max peak-to-peak over the
  stacked curves × Gap**; when that is 0 (all curves flat) nothing moves. Stacking shifts display
  copies only — measured data and scientific results are never changed. IV with Zero at Current Origin
  on shows no stacking; the saved Gap is kept and applies again when it is turned off.
- **CS-35a** *Saved files.* Packs and session snapshots written before Gap-only stacking hold a
  Stack number and (in some versions) a mode flag. They load directly, with no prompt: the saved
  minimum-Gap fraction is read as the Gap, and Stack and the mode flag are ignored — Stack never
  takes part in drawing, whatever its value (0, 0.5, 1.2, …). A missing Gap restores the default of
  that file's version (0.15 for Packs; 0.15 for an XY Rotation session written before its Gap was
  saved), never silently 0. Loading never rewrites the original Pack file; saving writes only the
  Gap (no Stack, no mode flag). Historic charts may therefore space differently from before; measured
  data is unchanged. New sessions start with Gap 0 (not stacked) except 3ω, which starts at 0.15 so
  its field sweeps stay separated.
- **CS-39** *Logical rows.* Layout units are logical groups, not modules (CS-1b). Several modules may
  share a row when their relationship is clear and every control has its VC-4 size (e.g. Draw · Line ·
  Scatter; X label · Y label; Range X · Y with Ticks X · Y; the Font row). Shared and
  Plot-Specific modules mix freely in the Plot region. There are no cross-row fixed column grids. Rules:
  a control and its label, a slider and its read-out, an axis Min/Max never split; the controls of related
  axes (X/Y or X/L-Y/R-Y) are kept adjacent; a Ticks X / Ticks Y pair is wrapped as a whole, never one
  hanging at a line end and the other alone below; text inputs keep a comfortable width and wrap instead of
  being compressed; narrow widths wrap, never shrink fonts or controls (VC-7). A tick strip
  (Ticks X · Y, or X · L-Y · R-Y) is one unbreakable unit: its Row is `atomic`, so when the strip does
  not fit beside the "Ticks" label the label moves above it instead of a stepper wrapping away.
- **CS-40** *Common layout.* Plot title sits on the left; Show Title and Transparent form one right-hand
  group. Title template follows, with Available to its right when wide and wrapped whole below (multi-line
  allowed) when narrow; the template input is never compressed to make Available fit (CS-36). The input
  is bounded, not line-filling: it sits at `WorkbenchInputWidth.templateIdeal` and flexes up by at most
  `WorkbenchInputWidth.templateMaxGrowth` only with leftover room, so Available
  (e.g. `#tab #device`) gets its whole natural width beside it first; an Available that does not fit
  beside even an ideal-width input wraps whole below at its normal size.
- **CS-36** *Hints.* Helper text (e.g. Available title tokens) uses the hint role and wraps to
  as many lines as needed; it is never truncated, dimmed or set below the readable size (VC-1, VC-3).
- **CS-37** *Specific parity.* Specific typed inputs (`.toggle`, `.menu`, `.number`, `.text`,
  `.readout`) obey VC-1…VC-5 through the same primitives as Common and Plot; a workflow
  leaf input obeys them too but keeps its own internal arrangement (CS-18).

## 7. State and event interface

- **CS-28** Shared components receive immutable values plus closures/bindings. A
  workflow adapter builds the model:
  `WorkbenchCommonControlsModel`, and a `WorkbenchControlsPlotAdapter` case
  (`.cartesianXY(CartesianXYControlsModel)`, `.dualAxis(DualAxisControlsModel)`,
  `.heatmap(HeatmapControlsModel)`).
- **CS-29** Re-render and snapshot-flush policy stays in the adapter closures
  (`onChange` vs `onTransientChange` semantics are preserved).
- **CS-30** Pack/Restore and persisted keys are unchanged by layout. New persisted state (heatmap title template) is additive, decodes from old Packs with defaults, and never rewrites existing override values.

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
| I5 | Same Plot Mode **and capability configuration** ⇒ identical control inventory & order for different adapters | `ControlsSurfaceLayoutTests` (real SwiftUI host) |
| I6 | At 300/364/420/520/720 pt: no overlap, no clipping, in-bounds | `ControlsSurfaceLayoutTests` |
| I7 | Negative samples (violations) are rejected by the check | `scripts/test_controls_contract.sh` |
| I8 | AFM and RSM have identical Common and Heatmap Plot-Specific inventory; their Typography/Axes inventory equals exactly the declared capability configuration (AFM: Title font only, no axes; RSM: Title/Axis/Ticks fonts, X/Y labels and ticks) | `ControlsSurfaceLayoutTests` |
| I9 | Common inventory/order/labels (incl. Title Template) identical across all seven workflows' surfaces (IV vs AFM included) | `ControlsSurfaceLayoutTests` |
| I10 | Edit drafts, focus and saved values survive width changes | `ControlsSurfaceLayoutTests` (resize same host) |
| I11 | Results list stays reachable: left column scrolls vertically when controls grow | `ControlsSurfaceLayoutTests` |
| I12 | Real SwiftUI hosting covers **all seven** full surfaces (and every 3ω tab); source-text checks never substitute | `ControlsSurfaceLayoutTests` |
| I13 | No-clipping is proven against each group's required minimum size from the shared Layout, not a fixed parent's `fittingSize` | `ControlsSurfaceLayoutTests` + planner unit tests |
| I14 | No drag oscillation: layout of a given width is deterministic and a width sweep produces monotone row counts; surface body evaluation count is bounded | `ControlsSurfaceLayoutTests` + manual drag record (E7) |
| I15 | Every input in every surface has a non-empty accessibility label, a stable identifier of the CS-25a form, and identifiers/focus order are identical at all five widths | `ControlsSurfaceLayoutTests` (accessibility tree walk) |
| I16 | The Controls Contract CI check is a required status check on protected `main` (AC9). Verified by reading the live ruleset; if it is not configured the state is reported as HUMAN REQUIRED, never as enforced | `scripts/check_main_required_checks.sh` (read-only) |
| I17 | Every interactive control (slider, text field, picker, stepper, icon button) is at or above its VC-4 minimum at all five widths, measured on that control; a deliberately squeezed slider is reported; a compound input wraps internally without shrinking a member | `ControlsSurfaceLayoutTests` (control probe + negative sample) |
| I18 | Sibling labels (checkbox, field, picker, slider labels) share one text role; Common labels in all seven workflows' surfaces match the shared role; a deliberately mis-styled label is reported | `ControlsSurfaceLayoutTests` + AST rule `controls-literal-text-style` (`scripts/test_controls_contract.sh`) |
| I19 | Groups on one line share a first-baseline; a deliberately offset group is reported | `ControlsSurfaceLayoutTests` |
| I20 | Logical pairs (Gap label + field) stay on one line as a unit when the compound input wraps internally; a pair split across lines is reported | `ControlsSurfaceLayoutTests` |
| I21 | Common layout (CS-40): Plot title left of the checkbox group, template on its own line, Available beside the input when wide and wrapped whole below when narrow, template input never below its comfortable width | `ControlsSurfaceLayoutTests` |
| I22a | Cartesian XY at 677pt is exactly three rows (CS-38c), right edges aligned, nothing undersized or clipped; Gap-only stacking: uniform net gap = max peak-to-peak × Gap, Gap 0 = in place, non-quantized Gaps, flat curves, old Pack/session restore (Stack ignored, Gap kept), re-save and reopen for all five workflows (CS-35, CS-35a) | `ControlsSurfaceLayoutTests`, `GapOnlyStackingTests` |
| I22 | Tick strips of every mode with axes never split at any width; a deliberately wrapped strip is reported; related axis labels wrap as whole fields | `ControlsSurfaceLayoutTests` |
| I23 | No Specific group title is drawn in any workflow; a visible title is reported; unlabeled Specific rows are limited to a reviewed self-labelled list | `ControlsSurfaceLayoutTests` + `ControlsSurfaceWorkflowTests` |
| I24 | Title Template reaches the rendered AFM and RSM figures (override > template > default), restores from Packs, and old Packs decode | `ControlsRestoreTests` + `ControlsWorkflowAdapterTests` |
| I25a | Heatmap rows (CS-38d, CS-41): AFM and RSM at 300/364/420/520/667/720pt share the order Colorbar + Linear/Log · Interpolation · Font; Z range keeps its start and row 1 / row 3 do not move when Auto / Manual / Percentile switches; AFM has no axes row; RSM full row 1 single-line threshold is measured and wraps by whole groups below it; empty Manual draft is a field cue, invalid/inverted keeps the red message | `HeatmapSharedRowsLayoutTests` |
| I25 | Heatmap (AFM and RSM; Auto / Manual / Percentile; every interpolation option and visible preset; narrow to wide representative widths): menu width equals the intrinsic width a real SwiftUI menu Picker needs in the same environment (including environments a separate measurement could not predict), is identical for every selection, and a row too narrow wraps instead of squeezing it; nothing overflows or is clipped; Preset shares Z range's line when it fits; Manual Z range fields sit on one line in order min, connector, max inside the row; their accessibility labels are the shared constants. DualAxis Left/Right cells share X and width per column at every tested width for any selection | `ControlsRepeatedRowAndCompactMenuTests` |

Visual-layout rules → implementation → check (token values stay in code, see CS-27):

| Rule | Implementation | Check |
|---|---|---|
| CS-22/23/35 (+VC-4, VC-7) | `WorkbenchControlFlow`, `WorkbenchFlowPlanner`, `WorkbenchPlotSpacingInlineControls`, `WorkbenchInputWidth` | I17, I20 |
| CS-33 (+VC-5) | `WorkbenchFlowLayout` baseline placement, `WorkbenchControlRow` | I19 |
| CS-34/37 (+VC-1, VC-2) | `WorkbenchCheckbox`, `WorkbenchCommonControls`, `WorkbenchSpecificInput`, `WorkbenchUIStyle` | I18 |
| CS-36 (+VC-1, VC-3) | `WorkbenchAvailableTokensHint`, `WorkbenchUIStyle` | I18 |

Source-text checks strip comments and string literals first; they are secondary to
the type-level and real-layout checks above.

## 10. Migration status

All seven workflows mount through the Surface. The temporary legacy allow-list and the
legacy mount path no longer exist, and the Controls Contract check runs over the whole
source tree with no exceptions. A deleted assembler (`WorkbenchStandardPlotControls`,
`WorkbenchPlotControlsPanel`, `DualAxisPlotControlsPanel`, `HeatmapPlotControlsPanel`) that
reappears is rejected by the checker.

## 11. Ownership map of controls (E1) and the legacy structures removed

Every control below has exactly one owner.

| Control | Rendered by before migration | Owner |
|---|---|---|
| Show Title checkbox | Draw row of `WorkbenchPlotControlsPanel` (Cartesian); `CompactTypographyRow` (DualAxis); top row of `HeatmapPlotControlsPanel` | Common |
| Plot title override | `SharedPlotTextControls` (Cartesian); label row (DualAxis); `LabelOverrideField` (Heatmap) | Common |
| Title font size | `CompactTypographyRow`, `SharedPlotFontSizeControls`, `titleOnlyControls` | Shared Typography (all modes) |
| Transparent background | `CompactTypographyRow`; Heatmap top row | Common |
| Title Template | `WorkbenchTitleTemplateSection` | Common (all modes, one resolver) |
| Gap (stacking) | per-workflow `…SpacingInlineControls` (AHE, IV, RT, XY, 3ω) | Plot-Specific (`cartesianXY` only). The 3ω Temperature Dependence tab showed it, but the DualAxis renderer does not consume stack/gap (inert control), so it is intentionally not part of `dualAxis`; the 3ω store keeps the values for its Cartesian tabs |
| Draw / Line / Scatter, Grid | `CompactPlotStyleRow` + `gridToggle` | Shared Curve Appearance (cartesianXY; dualAxis series styles) |
| X/Y labels, ranges, ticks, reset | `SharedPlotTextControls`, `CompactAxisRangeRow`, `CompactAxisTickCountRow` | Shared Axes (cartesianXY) |
| X/L-Y/R-Y labels, ranges, ticks | `DualAxisPlotControlsPanel` | Shared Axes (dualAxis) |
| Axis colour policy | `DualAxisPlotControlsPanel` | Plot-Specific (dualAxis) |
| Left/right series style | `DualAxisPlotControlsPanel` | Shared Curve Appearance (dualAxis) |
| Axis/Ticks/Legend/Point font sizes | `CompactTypographyRow` | Shared Typography |
| Series appearance | `WorkbenchSeriesAppearanceControls` | Shared Curve Appearance (cartesianXY) |
| Series order, visibility, rename | `WorkbenchSeriesOrderPanel` | Plot-Specific (cartesianXY) |
| Color scale, interpolation, colorbar, Z range | `HeatmapPlotControlsPanel`, `HeatmapZRangeControl` | Plot-Specific (heatmap) |
| AHE Hc / R_AHE overrides | `AHEOverridesControls` | AHE Specific · Metric Overrides |
| IV current basis, channel, fit mode, zero-at-origin, angular toggle/fit mode/fold | `IVSpecificPlotControls` | IV Specific · Input / Channel / Fitting / Angular |
| XY Center, Detrend, x=180 | inline `HStack` in `XYRotationWorkspaceView` | XY Specific · Data Correction / Plot Annotation |
| XY φ offset per file | `XYRotationPhiOffsetPanel` (left extra) | XY Specific · Per-file Calibration |
| 3ω geometry, fit ranges | `ThreeOmegaGeometryPanel`, `ThreeOmegaTransportGeometryFields` | 3ω Specific · Transport Geometry / Fit Range |
| 3ω RAHE method | inline `Picker` | 3ω Specific · RAHE Method |
| 3ω RT selection field | `ThreeOmegaRTSearchField` (search extra) | 3ω Specific · Auxiliary Input |
| RSM view selector | `RSMViewSelector` (plugin section) | RSM Specific · View Selection |
| RSM X/Y labels, X/Y ticks | inside `HeatmapPlotControlsPanel` (`showsAxisControls`) | Shared Axes (heatmap with spatial axes) |
| RSM axis/tick font sizes | inside `HeatmapPlotControlsPanel` | Shared Typography |
| RSM Z (colorbar) label | inside `HeatmapPlotControlsPanel` | RSM Specific · Z Label |
| AFM channel, surface level, line flatten, zero reference, scale bar | `AFMPlotControls` | AFM Specific · Data Channel / Processing / Plot Decoration |
| Tab pickers (3ω, IV, XY), search, Load, Analyze | action bar / search section | Workspace Navigation (unchanged) |

**Legacy structures the migration removed or folded into shared primitives**

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
- Reused: the store-driven state adaptation for AHE/IV/RT/XY (now the
  `CartesianXYControlsModel` builder in `WorkbenchStandardControlsAdapter`), the typed
  `WorkbenchWorkflowKind` + `WorkflowWorkspaceRegistry` dispatch, and the shared
  field primitives (`LabelOverrideField`, `PlotAxisBoundField`, `SharedPlot*`).
- Tests that assert on source text (`V78*`, `V710*`, `V557*` structural tests)
  must be rewritten to the symbol/real-layout checks in §9 where they contradict
  this spec; comment-matching checks are removed.
