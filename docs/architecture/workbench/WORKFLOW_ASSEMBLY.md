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
- Scientific workflow logic outside the workflow's own contract

## Assembly Boundary

A Workflow Assembly is the contract the Main Board reads when it configures the active workflow. The Main Board uses the resulting declarations to mount or call modules, and the modules execute the behavior that the assembly describes.
