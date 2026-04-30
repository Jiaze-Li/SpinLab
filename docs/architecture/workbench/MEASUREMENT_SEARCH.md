# Workbench — Measurement Search

> Search layer: sidecar 字段消费、condition projection、workflow ID alias、search 返回 file list 语义。

## Search Semantics

- Workbench search fields must use sidecar condition names, never invent new variable names.
- Search accepts old (`"A"` / `"B"`) and new (`"ahe"` / `"3w"`) workflow IDs as query aliases; persisted data uses new IDs only.
- Search returns file list only — no auto-loading of artifacts, no auto-analysis on search completion.
- Condition projection from Rules lives in `WorkbenchFeatureStore`; the store reads condition definitions and exposes searchable condition fields (`SP-002`).

## Cross-Domain Dependencies

- **Sidecar schema canonical**: `docs/architecture/inbox/OUTPUT_CONTRACTS.md` — Workbench search reads sidecar fields written by Inbox apply; schema changes must maintain the Inbox → Workbench read contract.
- **Library sidecar display**: `docs/architecture/library/SIDECAR_AND_CONDITIONS.md` — Library presents the same sidecar from the Library storage perspective; Workbench reads it from the filesystem during search.
- **Sample key semantics** (`SP-009`, `SP-012`): changes to `SampleKeyNormalizer` or `SampleSemanticDescriptor` affect Inbox drawer matching, Workbench search, and ingestion together.

## Boundary Rules

| Shared point | Classification | Risk |
|---|---|---|
| Condition projection from Rules lives in Workbench store | `coordination_surface` (`SP-002`) | Verify rule reload path when editing condition definitions or Workbench condition options. |
| Workbench search reads Library sidecars and Import semantics | `coordination_surface` (`SP-009`) | Sample key semantics affect search, ingestion, and drawer matching together. |

## Code Map

- `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift`
- `Sources/SpinLabApp/Domain/WorkflowSearchModels.swift`
- `Sources/SpinLabApp/Workflow/WorkflowID.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkflowHitRow.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSharedComponents.swift` (search bar components)
- `Sources/SpinLabApp/Import/Parse/SampleKeyNormalizer.swift` (cross-cutting; consumed by Workbench search)
- `Sources/SpinLabApp/Import/Parse/SampleSemanticDescriptor.swift` (cross-cutting; domain-like semantics under Import)
