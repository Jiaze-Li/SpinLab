# Workbench - Workflow, Assembly, Main Board, Modules

> First-read architecture overview for the Workbench shell.

## Purpose

This document names the stable top-level model. Detailed contracts live in:

- [MAIN_BOARD_READINESS.md](MAIN_BOARD_READINESS.md)
- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)
- [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md)
- [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md)
- [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md)
- [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md) - implementation-level placement notes only
- `modules/`

## Architecture Model

```
Workflow
└── Workflow Assembly
    └── Main Board
        └── Modules
```

## Workflow

A workflow is the analysis title / analysis type. Examples include AHE, XY Rotation, 3ω, and future SOT.
It is not the Main Board and not a module.

## Workflow Assembly

A Workflow Assembly is the complete content and configuration for one workflow. Adding a workflow means adding a new Workflow Assembly under that workflow's own docs.

It declares:

- Workflow Identity
- Physics Function
- Workflow Parameters
- Plot Defaults
- Optional Panels / optional contributions
- Save Metadata Provider
- Pack Metadata Provider
- Required Tests

It does not own:

- Main Board layout
- Readiness
- Search logic
- Selection logic
- Analyze lifecycle logic
- Save / Pack implementation
- Plot module internals

## Modules

A Module is a reusable capability with explicit ownership and read surfaces. Default modules are always present. Optional panels or contributions are declared by the active Workflow Assembly and mounted by the Main Board. Ownership, forbidden mutations, and module-specific boundaries live in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).

## Main Board

The Main Board is the persistent Workbench shell. It owns only readiness, layout, and module mounting. It reads the active Workflow Assembly, mounts or calls modules, and coordinates shell-level decisions across the mounted modules. It does not own scientific workflow logic or workflow assembly content.

## Layout

Layout is pure spatial structure: where things appear. It is implementation-level only. Region, Slot, and Mount Surface are placement names used by the shell implementation, not formal architecture layers.

## Cross-Links

- [Main Board Readiness](MAIN_BOARD_READINESS.md)
- [Module Boundaries](MODULE_BOUNDARIES.md)
- [Workflow Assembly](WORKFLOW_ASSEMBLY.md)
- [Extension Boundaries](EXTENSION_BOUNDARIES.md)
- [Workbench Roadmap](WORKBENCH_ROADMAP.md)
- [Main Board layout notes](MAIN_BOARD_LAYOUT.md)
- `modules/MEASUREMENT_SEARCH.md`
- `modules/SELECTION_DENOMINATOR_AUDIT.md`
- `modules/PLOT_SYSTEM.md`
- `modules/PACK_RESTORE.md`
- `workflows/three-omega/THREE_OMEGA_PHYSICS.md`
