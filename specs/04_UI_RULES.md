# UI Visual & Interaction Rules

Status: active
Last updated: v5.5.2

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

## App Shell Layout

- Use a stable three-column app shell as default:
  - left: navigation (with room for future secondary menu)
  - center: workspace/actions (primary operations)
  - right: inspector/output (details, plots, metadata, previews)
- Keep critical workflow actions in the center workspace column; avoid making the right column the primary action surface.
- Never use raw HSplitView with hardcoded frames — use AppColumnShell.

## Hover Popover (v4.1.19+)

- Must use `.hoverPopover()` modifier, never custom hover/dismiss implementations.
- Parameters standardized: showDelay 1s, dismissDelay 500ms.

## Accessibility

- `[HARD][must]` Icon-only buttons must have `.accessibilityLabel()` describing the action.
- Status indicators should not rely solely on color; pair with text or distinct icon shapes.

## Shared Components

| Component | Location | Purpose |
|---|---|---|
| `AppColumnShell` | `UI/AppColumnShell.swift` | Two-column layout shell |
| `CollapsibleSectionHeader` | `UI/CollapsibleSectionHeader.swift` | Unified collapsible header |
| `AppFontScale` | `UI/AppFontScale.swift` | Heading font constants |
| `AppSpacing` | `UI/AppSpacing.swift` | Spacing scale constants |
| `FlowLayout` | `UI/FlowLayout.swift` | Flow/wrap layout for tag chips |
| `MetadataViews` | `UI/MetadataViews.swift` | MetadataValueRow, EditableMetadataField, WrappingValueText |
| `HoverPopoverModifier` | `UI/HoverPopoverModifier.swift` | Standardized hover popover |
