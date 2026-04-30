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

Sidecar schema, minimum fields, and tag normalization: `docs/architecture/inbox/OUTPUT_CONTRACTS.md`

- Archive metadata sidecar in sample drawers is the primary metadata source for archived measurement file tagging.
- App index/state may mirror sidecar metadata for fast lookup, but should not silently diverge.
