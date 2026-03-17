# SpinLab UI Rules

This document defines the baseline UI design rules for SpinLab.

All future UI changes must follow this document unless the product direction is explicitly revised.

## Core Principles

- UI should prioritize scientific workflow clarity over visual decoration
- UI should remain simple, local-first, and efficient for desktop use
- UI should favor fast review, confirmation, and browsing of structured metadata
- UI should support V1 manual testing without hiding important file or object details

## Layout Rules

### Three Column Layout

- SpinLab should use a three column layout whenever the workflow supports it
- Preferred structure:
  - left column for navigation or item list
  - center column for primary working content
  - right column for structured metadata, confirmation fields, or detail panels
- Avoid collapsing everything into a single long form when a three column layout improves scanning
- Each column should have a defined minimum width so the UI does not collapse into unusable blank or clipped states
- When the user resizes one divider between two adjacent columns, the non-adjacent side should remain stable whenever practical
- Column resizing behavior should feel local and predictable, not global and disruptive
- Small window sizes must remain usable
- When space becomes limited, UI must not cover, overlap, or collapse into blank content areas
- If content cannot fit, text should wrap first, then horizontal and vertical scroll behavior should preserve access to the content
- Content must never render under the macOS title bar or traffic lights
- Sidebar and detail areas must keep explicit top safe area spacing so the window remains usable at any size
- When the window height is reduced, the layout should compress from bottom space first while preserving top controls and labels
- Inbox working areas must provide vertical scroll access in small windows instead of overlapping or clipping

### Pending Import As Primary Workspace

- In V1, pending import review and confirmation is the primary workspace
- Inbox should emphasize pending import selection and confirmation over secondary controls
- The active pending import should always have enough visible context for confirmation work
- Inbox top actions (`Load Sample Registry`, `Import Measurement Files`, `Create Project`) should live in the native macOS toolbar to avoid overlapping content in narrow windows

## Information Presentation

### Full Filename Visibility

- Full filenames should be visible wherever filenames are important to confirmation or traceability
- Do not aggressively truncate filenames in primary workflow surfaces
- If space is limited, provide a layout that still allows the full filename to be read or selected
- If text cannot fit on one line, it should wrap instead of being silently cut off
- File paths and important metadata values should remain readable, selectable, and traceable
- Small-window behavior must preserve full readability through wrapping and scroll access rather than clipping

### High Information Density

- SpinLab should prefer high information density over large decorative spacing
- Important metadata should be visible with minimal scrolling where practical
- Dense layouts are acceptable if they remain readable and logically grouped
- Avoid oversized cards, excessive whitespace, or presentation patterns that hide scientific details

### Label/Value Metadata Layout

- Metadata should primarily use a label/value presentation style
- Labels should be stable and easy to scan
- Values should be visually distinct from labels
- This rule applies to:
  - file metadata
  - sample metadata
  - registry metadata
  - archived measurement metadata

### Registry Compact Display

- Registry information should be displayed compactly
- Prefix to sheet mappings should be visible in a concise form
- Registry-related details should support confirmation without dominating the main workspace
- Compact registry display is preferred over large tables unless a later workflow truly requires expansion

## Workflow Guidance

- Inbox should foreground pending imports and their metadata
- Confirmation UI should make edits efficient and explicit
- Library and Workbench should preserve the same metadata clarity patterns established in Inbox
- Comparison remains model-only until the product requires visible UI
