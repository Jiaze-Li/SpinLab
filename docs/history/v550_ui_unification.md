# v5.5.0 — Cross-Area UI Unification

Date: 2026-04-16

## Summary

Established app-wide UI design infrastructure and performed cross-area consistency fixes across Inbox, Library, and Workbench.

## Design Infrastructure Created

- **AppFontScale** (`UI/AppFontScale.swift`): Three-level heading font hierarchy (sectionTitle / sectionHeader / groupHeader). All structural heading fonts consolidated from per-area inline definitions.
- **AppSpacing** (`UI/AppSpacing.swift`): Seven-level spacing scale (xxs=2 through xxl=24). Key structural positions adopted; legacy values migrate on-touch.
- **CollapsibleSectionHeader** (`UI/CollapsibleSectionHeader.swift`): Unified collapsible section header component with full-width hit area. Replaced 5 manual chevron+HStack implementations.
- **FlowLayout** (`UI/FlowLayout.swift`): Shared flow/wrap layout, deduplicated from WorkflowRegistryView and RulesHandbookView.

## Consistency Fixes

- 12 font readability violations fixed (.footnote/.caption on user-readable content → .callout)
- 13 icon-only buttons received accessibilityLabel
- Button style convention documented (4-tier: prominent/bordered/borderless/plain)
- Color status indicators reviewed — existing implementations already provide text/icon redundancy

## File Splits (5.5.1)

- InboxView: 1237 → 64 lines + 5 new files
- LibraryDetailSections: 990 lines → deleted, replaced by 5 focused components
- RulesHandbookView: 1072 → 764 lines + 4 new files
- WorkbenchSharedComponents: 897 → 10 lines + 8 new files

## Rules Established

4 new `[HARD][must]` rules added to CLAUDE.md:
1. Layout spacing must use AppSpacing constants
2. Structural heading fonts must use AppFontScale constants
3. Collapsible headers must use CollapsibleSectionHeader component
4. Button styles follow 4-tier convention

4 new invariant sections added to features.md:
- Button Style Convention
- Spacing Scale
- Font Scale
- Disclosure Sections (updated)
