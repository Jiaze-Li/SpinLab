# Web Library Design Principles

These principles govern the SpinLab Web Library UI (`Resources/WebLibraryTemplate/`).
Any future change to this UI should be checked against this list before merging.

## 1. Product identity

SpinLab Web Library is a scientific sample library, not a dashboard or figure gallery.

## 2. Three-panel responsibility

- **Left**: Which sample?
- **Center**: What charts belong to it?
- **Right**: What is it? (metadata + note)

## 3. One fact, one place

Do not repeat the same information across panels.

## 4. Reduce visual noise, not information

Preserve useful scientific information; simplify presentation instead.

## 5. Typography

- One font family across the entire published site.
- No monospace font.
- Minimum readable font size: 12px (CSS pixels).
- Use tabular numerals when useful.

## 6. Color

- Primary readable information uses high-contrast text.
- Gray is reserved for genuinely secondary, contextual, timestamp, hint, or note-like information.
- Do not use gray simply to create hierarchy.

## 7. Search

- Only one search box, located in the Samples panel.
- It remains the existing global sample/metadata/numeric-tag search.

## 8. Header

- Keep only global library identity and useful global counts.
- Do not duplicate search, sample metadata, schema, or routine OK-state information there.
- Warnings/errors should appear only when actionable.

## 9. Metadata

- Right panel is the canonical home for sample metadata, numeric tags, and notes.
- Present metadata as clean label/value rows rather than many small cards.
- Do not repeat metadata already visible elsewhere unless required for identification.

## 10. Charts

- Center panel is permanently the chart workspace.
- No Charts/Notes tabs.
- Notes belong in Metadata.
- Keep chart controls quiet and subordinate to the chart itself.

## 11. Consistency

Use one spacing scale, one border language, one radius system, one button language,
and one label/value component system.
