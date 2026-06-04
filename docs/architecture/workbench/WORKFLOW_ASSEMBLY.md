# Workbench - Workflow Assembly

> Workflow Assembly is the workflow-owned semantic contract consumed by the Main Board and implemented across workflow code.

## Core Principle

Workflow declares the analysis title / analysis type.
The workflow itself is not the Main Board and not a module.

Workflow Assembly declares workflow-specific semantic differences, overrides, contracts, and ownership.
Main Board stays generic and mounts common modules.
Common modules execute default shell/module behavior and should not be repeated in every Assembly record.

Adding a workflow means adding a new Workflow Assembly.

## What It Defines

| Contract field | Meaning |
|---|---|
| Workflow Identity / Search Hints | Stable workflow identity plus workflow-specific search aliases, prefixes, or extra search slots |
| Data / Physics Mapping | Raw-file formats, parser entry points, required fields, column/index mapping, unit conversion, derived quantities, and invalid-data behavior |
| Analysis Pipeline | Workflow-specific parse, ingest, transform/fit/scale, render-payload, metric, warning, and failure stages |
| Optional Contributions | Workflow-specific panels or module contributions mounted by the shell |
| Plot Semantics / Overrides | Plot meanings that differ from common plot shell behavior: default axes, units, tabs, stacking, normalization, annotations, metrics, titles, and legends |
| Validation / Warning Policy | Workflow-specific warnings/errors for missing input, skipped series, ambiguous units, and data-quality failures |
| Persistence / Pack-Restore | Workflow-specific state required to interpret restored workspaces and saved results |
| Required Behavior Tests | Behavior classes that protect the workflow contract |

## What It Does Not Own

- Main Board layout
- Readiness
- Common search logic
- Selection logic
- Analyze lifecycle logic
- Save / Pack implementation
- Plot module internals
- Default module ownership
- Common module behavior and default shell behavior
- Scientific logic belongs inside the workflow's Physics Function contract, not inside the Main Board or default modules.

## Contract Reality

The contract below is idealized. The current repository implementation splits that contract across registry dispatch, workflow views, workflow stores, typed contracts, use cases, and regression tests.

| Layer | What it means |
|---|---|
| Ideal assembly contract | The abstract per-workflow fields listed above. |
| Current implementation surface | The concrete files that currently realize the workflow: registry, view, store, contracts, use cases, and tests. |
| Implicit current behavior | Fields that exist only as conventions or distributed behavior, not as a dedicated provider object or single contract type. |

## Current Implementation Surface

In this repository, the current implementation surface is realized across a small set of files:

- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` and `config/workflow.json` provide workflow display names and condition-field definitions.
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` maps workflow IDs to concrete workspace views.
- `Sources/SpinLabApp/Features/Workbench/*WorkspaceView.swift` composes the shared shell with workflow-specific panels.
- `Sources/SpinLabApp/Features/Workbench/*WorkspaceStore.swift` and related extensions own analysis, rendering, persistence, and pack restore.
- `Sources/SpinLabApp/Workbench/V3/*PackContracts.swift` and `*IngestionContracts.swift` provide typed workflow snapshots and restore payloads.
- `Sources/SpinLabApp/UseCases/*` contains workflow-specific parsing, ingestion, rendering, fitting, and scaling helpers.
- `Tests/SpinLabAppTests/*` carries the workflow-specific regression coverage.

The per-workflow records under `workflows/*/ASSEMBLY.md` map those surfaces to concrete files and call out where the contract is explicit versus implicit.

## Assembly Boundary

A Workflow Assembly is the workflow-owned semantic contract for the active workflow. The Main Board uses workflow declarations to mount or call modules, but common module behavior remains outside Assembly. Assembly should name only workflow-specific identity/search hints, data mapping, analysis behavior, optional contributions, plot overrides, persistence metadata, validation policy, and required behavior tests.

The current implementation does not have runtime Assembly objects. A valid Assembly record may therefore point to distributed implementation files instead of a single provider type. If code contradicts the ideal model, the record should state the contradiction rather than inventing a framework.
