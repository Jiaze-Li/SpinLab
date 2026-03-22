# SpinLab Filename Rules

Status: historical

SpinLab filename parsing is keyword-driven and path-aware.

It does not depend on token position.

## Parse Sources

SpinLab reads metadata from:

1. file name
2. parent folder
3. grandparent folder

When a field is missing in the file name, parent folders can fill it in.

## Batch And Sample

In SpinLab, batch identity is the sample ID itself.

Examples:

- `PN40`
- `PT24`

Physical sample identity must include substrate information.

Examples:

- `PN40 HF STO(111)`
- `PN31 o STO(111)`
- `PT24 STO(001)`
- `PN27 baked STO(111)`

This means:

- `batch = sample ID`
- `sample = sample ID + complete substrate`

Display format should be normalized to:

- `batch ID + o/HF/baked + substrate orientation`

Where:

- `origin/original` displays as `o`
- `HF` displays as `HF`
- `baked` displays as `baked`
- substrate orientation displays in compact form such as `STO(111)`, `STO(001)`, `NGO(110)`

If a file contains a bare batch token with no explicit substrate variant, SpinLab defaults it to the `origin` substrate variant when multiple variants exist.

If the registry only has one substrate variant for that batch, SpinLab uses that single substrate directly.

## Sample IDs

Recognized primary sample IDs:

- `PN\d+`
- `PT\d+`

Legacy support:

- `S\d+`

Channel labels are not sample IDs:

- `C1`
- `C2`
- `C3`
- `ch1`
- `ch2`
- `ch3`

## Workflow Detection

Recognized workflow keywords:

- `MR`
- `RT`
- `AHE`
- `XY`
- `XY_90shift`
- `Rotation`

Normalization:

- `XY` and `XY_90shift` map to `Rotation`

## Rotation Hint

`90shift` is not a workflow name.

It means plotting should apply a `+90deg` angle shift so the curve corresponds to `I parallel B`.

## Measurement Labels

Recognized measurement-channel labels:

- `AMR`
- `PHE`
- `Rxx`
- `Rxy`

These are stored as measurement tags, not as the top-level workflow.

## Conditions

Recognized condition patterns:

- temperature: `\d+K`
- current: `\d+(\.\d+)?mA`
- field: `-?\d+T`

Temperature fields are split:

- measurement temperature comes from the file name
- growth temperature comes from the registry XLSX

## Substrate Tags

Recognized substrate or substrate-treatment tags:

- `HF`
- `bake`
- `baked`
- `o`
- `origin`
- `original`
- `STO`
- `STO111`
- `STO001`
- `NGO`

Normalization:

- `o`, `origin`, `original` -> `origin`
- `bake`, `baked` -> `baked`

If a file only says `HF`, `baked`, or `origin`, SpinLab should use the registry row for that batch to expand the substrate into a complete physical-sample substrate string.

## Device Detection

`wafer` means the test was done on wafer rather than on a fabricated device.

SpinLab stores this as:

- `device = wafer`

## Channel Mapping

If a filename contains multiple channels with different samples, SpinLab should keep channel-level assignments instead of forcing one sample ID.

Examples:

- `ch1 -> PN38`
- `ch2 -> PN40 + STO111`
- `ch3 -> PN40 + HF + STO111`

## Conflict Handling

If file-name sample IDs and folder-derived sample IDs conflict, SpinLab should not silently choose one.

It should emit a warning so the user can confirm the import.
