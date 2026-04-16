# SpinLab Extension Rules

Status: historical

## Principle

SpinLab should grow through extension modules instead of expanding the core app indiscriminately.

The core app owns:

- navigation
- persistence
- object relationships
- lifecycle state

Extensions own:

- parsing logic
- workflow-specific interpretation
- analysis behavior
- specialized views

## Extension Types

### workflow

- Encapsulates alternate measurement workflows
- V1 includes one built-in workflow only:
  - `AMR/PHE`
- Postpone other workflows until after V1:
  - `MR`
  - `RT`
  - `AHE`
  - `Harmonic`

### metadata

- Encapsulates filename parsing rules
- Encapsulates identity matching helpers
- Encapsulates metadata normalization
- V1 parser focuses on:
  - `Batch`
  - `Sample`
  - `Measurement`
  - optional `Device`
- `Project` suggestion can use existing links after sample matching
- Filename should not be treated as project truth

### analysis module

- Encapsulates transforms, metrics, fits, and future scientific analysis paths
- V1 exposes only a minimal `AMR/PHE` result path
- V1 should not include advanced fitting pipelines or automation

### view

- Encapsulates specialized visualizations and inspectors
- V1 exposes one default raw plotting view
- That default plotting view is for `AMR/PHE` measurements only

## Boundary Rules

- New workflows should be added through `workflow` extensions
- New filename conventions should be added through `metadata` extensions
- New analysis pipelines should be added through `analysis module` extensions
- New specialized visualizations should be added through `view` extensions
- V1 should keep these boundaries lightweight and practical, not over-engineered
