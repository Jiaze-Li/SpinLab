# UI Visual & Interaction Rules

Status: active
Last updated: v5.7.5

Scope: global visual and interaction standards for the whole app (typography, text colour, control roles/sizing/alignment, spacing scale, button styles, disclosure, information rules, shell, hover, accessibility). Surface-specific specs inherit these rules and must not redefine them; the Workbench controls surface (organisation, layout, responsive behaviour) is owned by `specs/06_WORKBENCH_CONTROLS_UI.md`.

Concrete values for any rule live only in the token files named below (and the Shared Components table), never in a surface spec.

---

## Font Readability (v5.5.0+)

- `[HARD][must]` All text intended for user reading (status messages, list items, labels, panel content) must use `.callout` or larger.
- `.caption` is acceptable only for supplementary metadata (timestamps, tolerances, icon badges).
- `.caption2` is reserved for non-essential decorative hints only.
- Do not use `.footnote` for content the user needs to read.

## Readable Text Color (v5.5.2+)

- `[HARD][must]` Text that carries information the user needs to read (body copy, labels, values, helper/status text, provenance, metadata) must not be dimmed to gray. Forbidden on readable content: `.foregroundStyle(.secondary)`, `Color.secondary`, `.gray`, `Color.gray`, or any equivalent gray foreground.
- Normal body/label/value text uses `.primary` (or omits `foregroundStyle`, which defaults to primary).
- Semantic states — error, warning, success, selected — may use the existing semantic colors (red / orange / green / accent).
- Express hierarchy through size, weight, spacing, and layout grouping, not by lowering text contrast.

## Font Family Consistency (v5.5.2+)

- `[HARD][must]` All user-readable text within a given UI uses the app/system font family consistently.
- Do not switch to `.monospaced()` or another font family for paths, keys, sample identifiers, or other raw values.
- Hierarchy is expressed through size/weight within the shared font family, not through a different font family.
- A genuine future need for a special font family requires an explicit exemption recorded in this spec first; it may not be decided locally in a single view.

## Control Visual Contract (v5.7.5+)

Applies to every interactive control group in the app; the Workbench Controls Surface is the first consumer and adds only organisation/layout (see `06`). Rules state constraints and name the token source; values live only in code. Tokens: `WorkbenchUIStyle` (text roles), `WorkbenchControlMetrics` + `WorkbenchInputWidth` (sizes, spacing relations), `AppSpacing` (scale).

- **VC-1 Text roles** `[HARD][must]` Control text has exactly three roles, all at the readable size above and in primary colour: *label* (semibold; names a control), *value* (regular; typed/selected/read-out value), *hint* (regular; helper or availability text). Hierarchy is weight and layout, never gray or a smaller size. A disabled control uses the system disabled style.
- **VC-2 One role per level** `[HARD][must]` Sibling labels use the label role whatever the native control is: checkbox titles, picker/field/slider/stepper labels. Native default `Toggle`/`Picker`/`Stepper` title styling is not allowed to differ; the shared control primitives apply the role. Numeric read-outs beside a control use the value role.
- **VC-3 No literal control text styles** `[HARD][must]` Control code takes fonts and text colours only from `WorkbenchUIStyle`; inline `.font(.system(size:))`, `.caption*`/`.footnote`/`.subheadline` and gray/`.secondary` foregrounds are forbidden (icon-only glyphs and the system placeholder style of an unset input are exempt). Readable hints wrap or are fully accessible; they are not truncated to one line.
- **VC-4 Minimum usable size** `[HARD][must]` Every interactive control keeps its own minimum, measured on the control itself (never its parent group): Slider ≥ slider minimum, text field ≥ compact field width, menu picker ≥ picker minimum, stepper (arrows + value) ≥ stepper minimum, icon-only button hit area ≥ hit-target minimum. A control that would fall below its minimum moves to a new line instead of shrinking. `.mini` control size is not used for interactive targets.
- **VC-5 Baseline alignment** `[HARD][must]` Controls sharing a visual line align on the first text baseline of their label/title; native control heights are not forced equal. A label column keeps one leading edge; labels are never centred.
- **VC-6 Spacing relations** `[HARD][must]` Spacing is chosen by relation, from `AppSpacing` via `WorkbenchControlMetrics`: label↔input (label gap), items within one row, rows within a group, lines of wrapped groups, group↔group. Spacing is never reduced to make something fit; wrapping is used instead. No extra nested `GroupBox`.
- **VC-7 Operability before density** `[HARD][must]` Compactness never outranks VC-1…VC-5: when width is short the order is wrap → stack label above input → grow height (scroll). Never shrink fonts or compress a control below VC-4. Logically paired controls stay whole (Min with Max; Gap label with its field).

- **VC-8 Content-fit sizing** `[HARD][must]` A selector is as wide as its longest complete, readable option needs (`WorkbenchInputWidth` token), never a meaninglessly wide input area. Display text may be shortened, but only when the scientific meaning stays recognisable and the full name remains available in the tooltip and the accessibility value; the stored value and the algorithm never change with the display text.
- **VC-9 Repeated-row alignment** `[HARD][must]` Structurally identical rows (same ordered controls, differing only in a row label or in values) share semantic column edges: each column is as wide as its widest cell over all rows, so a short label or the current selection never shifts the controls after it, and a wrapped table breaks at the same column in every row. This applies only to such repeated rows — it is not a fixed column grid for the Workbench.
- **VC-10 Semantic proximity** `[HARD][must]` A main setting and the setting that only qualifies it stay adjacent and share a line while they fit; only when the width is short does the pair wrap, as a whole and after the main setting (VC-7).

| Rule | Implementation | Check |
|---|---|---|
| VC-1/2 | `WorkbenchUIStyle` roles; `WorkbenchCheckbox` shared primitive (`Controls/Common`) | `ControlsSurfaceLayoutTests` role probe; AST rule `controls-literal-text-style` |
| VC-3 | same tokens; `scripts/controls_contract_ast.py` | `scripts/test_controls_contract.sh` negative fixture |
| VC-4 | size tokens in `WorkbenchInputWidth`; per-control probe in `WorkbenchControlLayout.swift` | `ControlsSurfaceLayoutTests` minimum-size problems |
| VC-5 | `WorkbenchFlowLayout` / `WorkbenchControlRow` baseline placement | `ControlsSurfaceLayoutTests` baseline problems |
| VC-6/7 | `WorkbenchControlMetrics`, `WorkbenchFlowPlanner` | `WorkbenchFlowPlannerTests`, `ControlsSurfaceLayoutTests` |
| VC-8 | menu width tokens in `WorkbenchInputWidth` | `ControlsRepeatedRowAndCompactMenuTests` |
| VC-9 | `WorkbenchAlignedRows` | `ControlsRepeatedRowAndCompactMenuTests` |
| VC-10 | nested `WorkbenchControlFlow` inside the group | `ControlsRepeatedRowAndCompactMenuTests` |

## Font Scale (v5.5.0+)

- `[HARD][must]` Structural heading fonts must use `AppFontScale` constants (defined in `UI/AppFontScale.swift`), never inline font literals.
- Three-level hierarchy:
  - `sectionTitle` = `.title2.bold()` — top-level area titles
  - `sectionHeader` = `.title3.weight(.semibold)` — collapsible section headers
  - `groupHeader` = `.headline` — GroupBox labels, subsection headers
- Adding a new heading level requires updating `AppFontScale` first, then using the new constant.
- Body/content fonts (.callout, .body, .caption) remain contextual and are not part of the heading scale.

## Spacing Scale (v5.5.0+)

- `[HARD][must]` All new layout spacing must use `AppSpacing` constants (defined in `UI/AppSpacing.swift`), never bare numeric literals.
- Seven-level scale:
  - `xxs` = 2 — tight inline elements
  - `xs` = 4 — compact groups, small padding
  - `sm` = 6 — icon+text gaps, related items
  - `md` = 8 — standard stack spacing, standard padding
  - `lg` = 12 — section body spacing, GroupBox internals
  - `xl` = 16 — between major sections
  - `xxl` = 24 — outer margins, dialog padding
- Legacy values outside the scale (3, 10, 14, 20) should be migrated to the nearest scale value when surrounding code is next modified.

## Button Style Convention (v5.5.0+)

- `[HARD][must]` Button styles follow a four-tier convention:
  - `.borderedProminent` — primary / commit actions (Analyze, Save, Apply, Confirm)
  - `.bordered` — secondary actions (Clear, Revert, Export, Done, navigation-style)
  - `.borderless` — inline actions within lists or compact panels (toggle, delete, field-level edit)
  - `.plain` — icon-only buttons with no visible chrome (chevron sort, close, minimal toggle)
- Default (no explicit style) is acceptable for secondary actions in macOS context (equivalent to `.bordered`).
- Destructive actions use `.bordered` with `.foregroundStyle(.red)`, not `.borderedProminent`.

## Disclosure Sections (v5.5.0+)

- `[HARD][must]` All collapsible section headers must use `CollapsibleSectionHeader` component (defined in `UI/CollapsibleSectionHeader.swift`).
- Full-width hit area on header row, not just chevron (enforced by component's `.contentShape(Rectangle())`).
- Collapsed visual state must match persisted state.
- Do not create new manual chevron+HStack implementations.

## Human-Readable Information (v5.5.8+)

- `[HARD][must]` Normal workflow UI must not directly display parser raw keys, enum raw values, serialization syntax, canonical machine identifiers, internal storage keys, or debug-only field names. Internal canonical/raw values may continue to exist in the data model, audit records, and debug logs, but must not be rendered in normal workflow UI.
- Allowed: user-defined identifiers (e.g. Batch ID), human-readable sample identity, human-readable source note paths, Registry field names (column headers), human-readable values.

## Information Non-Redundancy (v5.5.8+)

- `[HARD][must]` Within one inspector or confirmation surface, a fact already clearly shown in one section must not be repeated verbatim in another; every secondary/detail section must answer a new question rather than restating an answered one.
- `[HARD][must]` Sibling readable content within one inspection surface must share a consistent leading alignment/leading edge. Do not introduce unmotivated left-to-indented or centered-to-left jumps between sibling sections; indentation is only allowed when it expresses real parent/child hierarchy. Centered text is reserved for empty, loading, or standalone-status states — never normal metadata/detail content.

## App Shell Layout

- Use a stable three-column app shell as default:
  - left: navigation (with room for future secondary menu)
  - center: workspace/actions (primary operations)
  - right: inspector/output (details, plots, metadata, previews)
- Keep critical workflow actions in the center workspace column; avoid making the right column the primary action surface.
- Never use raw HSplitView with hardcoded frames — use `AppWorkspaceShell`.
- Workbench controls (Common / Plot / Workflow Specific) are governed by `specs/06_WORKBENCH_CONTROLS_UI.md`, which inherits this document; controls layout rules are not defined here.

## Hover Popover (v4.1.19+)

- Must use `.hoverPopover()` modifier, never custom hover/dismiss implementations.
- Parameters standardized: showDelay 1s, dismissDelay 500ms.

## Accessibility

- `[HARD][must]` Icon-only buttons must have `.accessibilityLabel()` describing the action.
- Status indicators should not rely solely on color; pair with text or distinct icon shapes.

## Shared Components

| Component | Location | Purpose |
|---|---|---|
| `AppWorkspaceShell` | `UI/AppWorkspaceShell.swift` | Two-column workspace shell |
| `CollapsibleSectionHeader` | `UI/CollapsibleSectionHeader.swift` | Unified collapsible header |
| `AppFontScale` | `UI/AppFontScale.swift` | Heading font constants |
| `AppSpacing` | `UI/AppSpacing.swift` | Spacing scale constants |
| `FlowLayout` | `UI/FlowLayout.swift` | Flow/wrap layout for tag chips |
| `MetadataViews` | `UI/MetadataViews.swift` | MetadataValueRow, EditableMetadataField, WrappingValueText |
| `HoverPopoverModifier` | `UI/HoverPopoverModifier.swift` | Standardized hover popover |
| `WorkbenchUIStyle` | `UI/WorkbenchUIStyle.swift` | Control text-role/colour tokens; composes `AppFontScale` + `AppSpacing`, must obey the rules above |
| `WorkbenchControlMetrics`, `WorkbenchInputWidth` | `ControlsSurface/WorkbenchControlLayout.swift` | Control sizing and spacing-relation tokens (VC-4, VC-6) |
