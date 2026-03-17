# SpinLab V1 Scope

## Product Focus

SpinLab V1 is a local-first macOS app for magnetic experiment workflow management.

V1 supports one workflow only:

- `AMR/PHE`

The V1 app structure is:

- `Inbox`
- `Workbench`
- `Library`

The V1 workflow is:

- `Import -> Confirm -> Visualize -> Analyze -> Save -> Archive`

## In Scope

- Import local `AMR/PHE` measurement files into `Inbox`
- Parse filename-derived hints with priority on:
  - `Batch`
  - `Sample`
  - `Measurement`
  - optional `Device`
- Keep `Project` out of first-class filename inference
- Suggest `Project` from existing links during confirmation, or let the user select/create one
- Require explicit confirmation before archival
- Visualize raw `AMR/PHE` data in `Workbench`
- Support only the default raw plotting path for `AMR/PHE`
- Create or update a `Result` attached to a `Measurement`
- Archive confirmed measurements into `Library`
- Provide basic `Library` browsing with primary filters:
  - `Project`
  - `Sample`
  - `Batch`
  - `measurement_type`
  - date
- Keep `Dataset -> Measurement` as one-to-one by default
- Keep `Comparison` in the model without requiring visible V1 UI

## V1 Workflow Boundaries

- `measurement_type` is an explicit core field on `Measurement`
- In V1, `measurement_type` is fixed to `AMR/PHE`
- `Workbench` handles one measurement at a time
- `Inbox` is a staging area, not the permanent source of truth
- Archived measurements are the canonical persisted records
- Rating may exist on `Result`, but it is not a primary V1 `Library` filter

## Postponed After V1

- Additional workflows beyond `AMR/PHE`
- `MR`
- `RT`
- `AHE`
- `Harmonic`
- Project inference from filename
- Automatic archival without explicit confirmation
- Advanced analysis pipelines and batch automation
- Rich comparison workflows or visible `Comparison` UI
- Complex device hierarchies beyond sample-level tested structures
- Multi-dataset measurements or non-default dataset mapping rules
- Rating-based primary discovery in `Library`
- Collaboration, sync, cloud storage, or multi-user features
- External plugin packaging or extension distribution
