# SpinLab Object Model

## Core Objects

### Project

- Logical research grouping
- Suggested from existing links during confirmation, or selected manually
- A `Sample` can belong to multiple projects

### Batch

- Administrative or preparation grouping
- Distinct from the physical sample identity
- Primary filename parser target in V1

### Sample

- Core physical specimen identity
- Can belong to multiple projects
- Can have multiple measurements over time

### Device

- Optional refinement of a physical sample
- Represents a specific tested device or patterned structure on a sample
- Examples include angle-specific Hall bars or numbered devices
- A `Measurement` may attach to a `Device` when device-level identity is known

### Measurement

- Primary experiment event record
- Required core fields include:
  - `measurement_type`
  - source/import identity
  - confirmed sample linkage
  - acquisition metadata
- `measurement_type` is an explicit core field
- In V1, `measurement_type` is fixed to `AMR/PHE`
- Owns one default dataset in V1

### Dataset

- Raw imported data payload
- Parsed data structure used for plotting
- Maps to one `Measurement` by default in V1

### Result

- User-reviewed or system-derived outcome attached to a `Measurement`
- Created or updated from `Workbench`
- Supports rating
- Rating exists in the model, but is not a primary V1 `Library` filter

### Comparison

- Forward-compatible relationship object for comparing results or measurements
- Present in the model for future use
- No visible V1 UI is required

## Recommended Relationships

- `Project <-> Sample` is many-to-many
- `Sample -> Device` is one-to-many
- `Measurement -> Sample` is required
- `Measurement -> Device` is optional
- `Measurement -> Dataset` is one-to-one by default
- `Measurement -> Result` is one-to-many over time

## V1 Modeling Rules

- `Batch` is not the same as `Sample`
- `Project` should not be assumed directly from filename
- Filename parsing should prioritize:
  - `Batch`
  - `Sample`
  - `Measurement`
  - optional `Device`
- `Dataset` maps to one `Measurement` by default
- `Result` is attached to `Measurement`, not stored as a flat top-level archive field
