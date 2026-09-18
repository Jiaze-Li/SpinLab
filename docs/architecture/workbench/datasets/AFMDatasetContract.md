# AFM Dataset Contract

> Defines the AFM Input Adapter boundary and the canonical, workflow-owned representation
> everything downstream of it (processing, Heatmap payload building) is built on. Heatmap
> itself never sees any type defined here.

## Pipeline

```
Raw .ibw
    ↓  (IBWReader — pure byte-level decode, no AFM semantics)
IBWWave
    ↓  (AFMInputAdapter — unit interpretation, channel identity, provenance extraction)
CanonicalAFMDataset
    ↓  (AFM workflow processing — Phase 3)
ProcessedAFMChannel
    ↓  (AFMHeatmapPayloadBuilder — Phase 3)
HeatmapPlotPayload
```

`IBWReader` and `IBWWave` (`Sources/SpinLabApp/AFM/IBW/IBWReader.swift`) know the Igor Binary
Wave v5 binary format and nothing about AFM. `AFMInputAdapter` and `CanonicalAFMDataset`
(`Sources/SpinLabApp/AFM/`) are where IBW's raw bytes become an immutable, unit-explicit AFM
dataset. Everything from `CanonicalAFMDataset` onward is Heatmap-agnostic domain logic; Heatmap
only ever receives a `HeatmapPlotPayload`.

## `CanonicalAFMDataset`

```swift
struct CanonicalAFMDataset: Sendable, Equatable {
    let sourceRef: String            // file path / stable source identity
    let title: String                 // IBW wave name, used as default display title
    let xCoordinates: [Double]        // µm, length == nX, fast-scan axis
    let yCoordinates: [Double]        // µm, length == nY, slow-scan axis
    let channels: [CanonicalAFMChannel]
    let sourceMetadata: AFMSourceProvenance
}
```

Invariants:

- `xCoordinates`/`yCoordinates` are explicit arrays computed once at adapter time from the
  IBW dimension calibration (`sfA`/`sfB`) — never re-derived downstream from array length alone.
- Every `CanonicalAFMChannel.values` matrix is exactly `yCoordinates.count × xCoordinates.count`
  (`values[y][x]`, `y` = slow-scan / row, `x` = fast-scan / column).
- `CanonicalAFMDataset` and `CanonicalAFMChannel` are value types with only `let` fields —
  processing (Phase 3) always starts from a fresh copy of the immutable source channel matrix
  and never mutates a `CanonicalAFMDataset` in place. There is no setter anywhere in this type.
- Coordinate convention: canonical X is always the fast-scan axis (IBW dimension 0), canonical Y
  is always the slow-scan axis (IBW dimension 1), matching the raw IBW row/column order — no
  transpose is applied. Channel (IBW dimension 2) becomes `CanonicalAFMChannel.sourceIndex`.

## `CanonicalAFMChannel`

```swift
struct CanonicalAFMChannel: Sendable, Equatable, Identifiable {
    let id: String                          // stable identity — see below
    let sourceIndex: Int                    // 0-based index into the IBW channel dimension
    let sourceLabel: String                 // raw IBW dimension label, e.g. "HeightRetrace"
    let semanticTypeRaw: String?            // e.g. "Height" / "Deflection" / "ZSensor"; nil if
                                             // absent or explicitly "None" in the source note
    let displayLabel: String                // user-facing label; defaults to sourceLabel
    let values: [[Double]]                  // values[y][x], in canonicalUnit
    let canonicalUnit: String               // e.g. "nm" for length-like channels
    let sourceUnit: String                  // raw IBW data unit, e.g. "m"
    let provenance: AFMChannelProvenance
}
```

- `id` is derived from `sourceIndex` + `sourceLabel` (both source-derived, immutable for the
  file's lifetime) — **never** from `displayLabel`, so identity survives a user renaming the
  channel's display text and survives pack/restore.
- `semanticTypeRaw` carries the *raw* string from the IBW note's `Channel<N>DataType` field
  (1-based `N` in the note maps to 0-based `sourceIndex = N - 1`) so provenance/run-trace can
  show exactly what the instrument reported, distinct from `sourceLabel` (the raw dimension
  label like `HeightRetrace`).

## Units

Unit interpretation happens once, at the `AFMInputAdapter` boundary:

- X/Y dimension units come from the IBW wave's `dimUnits[0]`/`dimUnits[1]` (defaulting to
  meters if blank, since that is the IBW/instrument convention for spatial dimensions).
  `AFMLengthUnit` converts to µm regardless of the source length unit (m, mm, cm, µm, nm, Å).
- The wave's single `dataUnits` field (shared by every channel in the file — IBW does not carry
  a per-channel unit) is interpreted the same way: if it resolves to a known length unit, every
  channel's values are converted to nm and `canonicalUnit = "nm"`. If it is not a recognized
  length unit, values are passed through unchanged and `canonicalUnit == sourceUnit` — AFM never
  falsely labels a non-length channel as nm.
- Unit interpretation never guesses from the filename or from `sourceLabel`/semantic type text —
  only from the IBW unit fields themselves.

## Channel resolution policy (default active channel)

Implemented in `AFMChannelResolver`, applied by the workflow (not by Heatmap):

1. First channel whose `semanticTypeRaw` case-insensitively equals `"height"`.
2. Otherwise, first channel whose `sourceLabel`, lowercased, contains `"height"`.
3. Otherwise, the first channel, with a warning that no Height channel was identified.
4. Zero channels: no default, warning only.

## Provenance

`AFMSourceProvenance` carries the file-level facts worth showing in run trace / pack metadata:
source file path, wave name, source width/height, and the full raw IBW note text (for audit —
Phase 4 run trace surfaces the fields that matter, not the raw blob).

`AFMChannelProvenance` carries the IBW note's per-channel `Planefit <n>` / `PlanefitOrder <n>` /
`FlattenOrder <n>` / `Planefit Offset <n>` / `Planefit X Slope <n>` / `Planefit Y Slope <n>`
fields (`<n>` = 0-based `sourceIndex`, matching the note's own indexing) verbatim, as optional
strings/doubles. This is provenance only — **it must never be read by AFM processing to decide
default Plane Level / Line Flatten state** (see Phase 3 processing defaults: always off,
regardless of what the source note reports).

## What downstream code must not do

- AFM processing (Phase 3) must never mutate a `CanonicalAFMDataset` or any of its channels —
  every reprocess starts a fresh transform from the immutable source matrix.
- Heatmap must never import anything from `Sources/SpinLabApp/AFM/` — the only contact point is
  the `HeatmapPlotPayload` that `AFMHeatmapPayloadBuilder` produces (Phase 3).
- No code may parse IBW units, or decide µm/nm conversions, outside `AFMInputAdapter`/
  `AFMLengthUnit`.
