# Workbench - Workflow Assembly

> Workflow Assembly is the per-workflow integration contract consumed by the Main Board.

## Core Principle

Workflow declares the analysis title / analysis type.
The workflow itself is not the Main Board and not a module.

Workflow Assembly declares the complete content and configuration for one workflow.
Main Board decides and mounts modules.
Modules execute the concrete behavior.

Adding a workflow means adding a new Workflow Assembly.

## What It Defines

| Contract field | Meaning |
|---|---|
| Workflow Identity | Stable workflow registration identity and associated metadata |
| Physics Function | Scientific model, ingestion, calculation, and result contract |
| Workflow Parameters | Workflow-specific parameters exposed through the workspace |
| Plot Defaults | Default plot presentation choices for the workflow |
| Optional Panels / optional contributions | Additional workflow-specific content declared by the workflow |
| Save Metadata Provider | Metadata needed to interpret saved results later |
| Pack Metadata Provider | Metadata needed to restore the workspace later |
| Required Tests | Regression gates that the workflow must satisfy |

## What It Does Not Own

- Main Board layout
- Readiness
- Search logic
- Selection logic
- Analyze lifecycle logic
- Save / Pack implementation
- Plot module internals
- Default module ownership
- Scientific logic belongs inside the workflow's Physics Function contract, not inside the Main Board or default modules.

## Current Implementation Surface

In this repository, the abstract assembly is realized across a small set of files:

- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` and `config/workflow.json` provide workflow display names and condition-field definitions.
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` maps workflow IDs to concrete workspace views.
- `Sources/SpinLabApp/Features/Workbench/*WorkspaceView.swift` composes the shared shell with workflow-specific panels.
- `Sources/SpinLabApp/Features/Workbench/*WorkspaceStore.swift` and related extensions own analysis, rendering, persistence, and pack restore.
- `Sources/SpinLabApp/Workbench/V3/*PackContracts.swift` and `*IngestionContracts.swift` provide typed workflow snapshots and restore payloads.
- `Sources/SpinLabApp/UseCases/*` contains workflow-specific parsing, ingestion, rendering, fitting, and scaling helpers.
- `Tests/SpinLabAppTests/*` carries the workflow-specific regression coverage.

The per-workflow records under `workflows/*/ASSEMBLY.md` map those surfaces to concrete files.

## Assembly Boundary

A Workflow Assembly is the contract the Main Board reads when it configures the active workflow. The Main Board uses the resulting declarations to mount or call modules, and the modules execute the behavior that the assembly describes.
