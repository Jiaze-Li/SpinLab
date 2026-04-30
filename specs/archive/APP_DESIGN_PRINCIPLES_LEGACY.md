# SpinLab App Design Principles

Status: historical (archived v5.5.2 — content folded into `docs/philosophy.md`, `specs/01_PRODUCT_RULES.md`, `specs/02_DATA_RULES.md`, `specs/06_PROJECT_ARCHITECTURE.md`)

This document originally defined the long-term architecture and product philosophy of SpinLab. Reference-only — use the active sources above for current rules.

## 1. Core Philosophy

SpinLab is a scientific workflow tool for magnetic materials experiments.

Its primary goals are:

- organize experimental knowledge
- archive measurement data
- allow fast retrieval and comparison
- keep workflow simple and structured

SpinLab should help researchers build a stable, navigable record of experimental work over time.

## 2. Core Workflow

SpinLab follows one primary workflow:

- `Import -> Confirm -> Visualize -> Analyze -> Save -> Archive`

No feature should break, bypass, or undermine this workflow.

New capabilities should fit into this structure instead of replacing it with ad hoc shortcuts.

## 3. Core Entities

SpinLab uses the following canonical object model:

- `Project`
- `Batch`
- `Sample`
- `Device`
- `Measurement`
- `Dataset`
- `Result`
- `Comparison`

All data in SpinLab must belong to this object model.

Features should be designed around these entities instead of introducing parallel or disconnected data structures.

## 4. Sample-Centered System

The physical `Sample` is the core object in SpinLab.

Key relationships:

- `Sample -> Devices`
- `Sample -> Measurements`
- `Sample <-> Projects`

All experimental knowledge accumulates around `Sample`.

`Device` refines the tested structure on a sample, while `Measurement`, `Dataset`, and `Result` describe what was done and what was learned from that sample.

## 5. Metadata Sources

Metadata may come from:

- filename parsing
- sample registry (`.xlsx`)
- manual confirmation

Automatic parsing must always be treated as suggestions.

User confirmation is the final authority.

SpinLab should never treat parsed metadata as unquestionable truth before confirmation.

## 6. File Management Rule

SpinLab manages measurement files internally.

Imported files are copied into:

- `Application Support / SpinLab / measurements`

The archive inside SpinLab is the canonical source of truth.

Original external file paths may be retained as reference metadata, but the internally managed archive copy is the authoritative file location for the app.

## 7. Extension Philosophy

New features must enter through extension modules:

- `workflow`
- `metadata`
- `analysis`
- `view`

The core app must remain simple and stable.

The app shell should own navigation, persistence, object relationships, and workflow state.

Extensions should add capability without destabilizing the core model or the main user workflow.

## 8. UI Philosophy

SpinLab is a research tool.

UI priorities are:

- information density
- complete file names
- clear metadata
- minimal clicks

Avoid decorative UI patterns.

UI should favor structured inspection, confirmation, and retrieval over presentation-heavy layouts.

## 9. Stability Rule

Once archived, experimental records should be stable and traceable.

Changes should not silently modify historical data.

SpinLab should preserve provenance, source references, and clear object relationships so archived records remain understandable over time.
