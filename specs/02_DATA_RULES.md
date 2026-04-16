# SpinLab Data Rules

Status: active

## Canonical domain entities
- `Project`
- `Batch`
- `Sample`
- `Device`
- `Measurement`
- `Dataset`
- `Result`
- `Comparison`

## Relationship rules
- `Project <-> Sample`: many-to-many.
- `Measurement -> Sample`: required.
- `Measurement -> Device`: optional.
- `Measurement -> Dataset`: one-to-one by default.
- `Measurement -> Result`: one-to-many over time.

## Sample-centered rule
- `Sample` is the physical anchor for experiment records.
- Archive and retrieval should preserve sample-level provenance.

## Metadata and sidecar ownership
- Archive metadata sidecar in sample drawers is the primary metadata source for archived measurement file tagging.
- App index/state may mirror sidecar metadata for fast lookup, but should not silently diverge.
- Minimum sidecar fields for archived measurement files:
  - `version`
  - `source_file`
  - `sample_key`
  - `workflow`
  - `conditions` (`temperature`, `current`, `field`)
  - `channel_bindings`
  - `normalized_tags`
  - `raw_tags`
  - `applied_at`

## Tag normalization rules
- `AMR -> R_xx`
- `PHE -> R_xy`
- `XY_90shift -> workflow = XY` plus `angle_shift = +90deg`
- Keep raw source values alongside normalized values for traceability.
