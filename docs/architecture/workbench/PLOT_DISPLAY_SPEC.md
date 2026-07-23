# Workbench Plot Parameter / Display Spec

Status: **implemented (v5.5.6)**. This document describes the display-label/unit
architecture as it exists in the codebase today — not a future target. Where an item
remains partially implemented, that gap is named explicitly rather than implied (§8).
Scope: all Workbench plot-producing code (payload builders, renderers, axis mapping, label/legend
constants, numeric unit conversions).
Baseline: [UNIT_LABEL_AUDIT.md](UNIT_LABEL_AUDIT.md) documents the pre-migration hardcoded
label/conversion state this architecture replaced — read it for history, not current behavior.

Purpose: record the single-direction display architecture the codebase now implements — what
the system looks like once centralized, which pieces are done, and which are intentionally
deferred.

---

## 1. Core principles

1. **Display labels are derived from physical quantity identity + display policy, never invented
   per call site.** `WorkbenchPlotDisplayVocabulary.label(for:context:)` — and, for the
   magnetic-field unit dimension specifically, `WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for:context:unit:)`
   — is the single source of truth every workflow calls into. No renderer or use case hardcodes
   an axis/legend string that duplicates what the vocabulary already defines for the same
   quantity.
2. **Display labels must not be used as persisted data keys or lookup keys.** Where a label
   string is also reused as a lookup/identity key, that coupling is a documented, tracked risk,
   not something silently accepted. Two concrete instances:
   - AHE's `AHEAxisDetector.semanticXField`/`.semanticYField` are display-only strings that also
     serve as `WorkbenchAxisMapping` field-name keys (see [AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md)).
   - The persisted per-sample metric-identity keys `"Hc"` and `"R_AHE"`
     (`AHEWorkspaceStore.swift`) are **not** display labels and must never be sourced from, or
     rewritten to match, the vocabulary's output (§7).
3. **Unit conversion is explicit at payload construction, never hidden inside a label string.** A
   label communicates the unit of an *already-converted* number; it does not perform the
   conversion itself. Every numeric transform (Oe→T, Oe→mT, the Temperature Dependence
   ×1e14/×1e-5 factors, Scaling Law's ×1e-11/×1e20/×1e31 factors) is a named value at its payload
   call site, not an implicit side effect of choosing a label.
4. **Special literature conventions are display transforms, not just label text.** Scaling Law
   and 3ω Temperature Dependence both apply named, literature-matching scale factors on top of SI
   values. The factor and the label are defined and tested together (§4) so the two can never
   silently drift apart.

---

## 2. Physical quantity identity vs. unit dimension

The Display Standard resolves defaults by **physical-quantity identity**, never by unit alone.
Two quantities can share a unit and still be different quantities requiring different labels —
sharing a unit is not evidence of sharing an identity. The codebase has two concrete pairs that
make this concrete:

- **Magnetic field unit dimension** (`MagneticFieldUnit`: `.oersted` / `.tesla` / `.millitesla`,
  `WorkbenchMagneticFieldUnitConverter`) is shared by two distinct physical-quantity identities:
  - `externalMagneticField` → displayed as `μ₀H`
  - `coerciveField` → displayed as `μ₀Hc`

  They convert through the same helper and the same canonical raw unit (Oe), but are never
  treated as the same identity — see §4 for their distinct display policy and target labels.
- **Angle unit** (`deg`) is shared by two distinct physical-quantity identities:
  - `deviceAngle` → displayed as `Ψ (deg)`
  - `angleOffset` → displayed as `φ (deg)` (the XY Rotation quantity)

  A lookup keyed on unit instead of identity would wrongly merge them; both stay as separate
  `WorkbenchPhysicalQuantity` cases with independent label entries.

The eight-concept model this codebase separates (workflow data lookup key, physical quantity
identity, raw unit, display unit, numeric display scale, default display label, user
display-label override, special-case policy) is unchanged from the original design and remains
the mental model for any future quantity added to the vocabulary:

| # | Concept | Question it answers | Owner | Example |
|---|---|---|---|---|
| 1 | Workflow data lookup key | Which column/field in the raw or sidecar data does this come from? | Workflow adapter | `rawMagneticFieldColumn`, a sidecar condition name |
| 2 | Physical quantity identity | What physical quantity is this, independent of file format or workflow? | Shared vocabulary (Display Standard) | `externalMagneticField`, `coerciveField` |
| 3 | Raw unit | What unit is the value in as it comes out of the file/parser? | Workflow adapter | Oe, A, raw ADC counts |
| 4 | Display unit | What unit should a human see it in? | Display Standard (default) or Plot Parameter (override) | T, mT, Ω |
| 5 | Numeric display scale | What multiply/divide/branch converts raw unit → display unit? | Display Standard (default policy) or Plot Parameter (special case) | Oe→T `×1e-4`, Oe→mT `×0.1` |
| 6 | Default display label | What string is shown when nobody has customized anything? | Display Standard | `μ₀H (T)`, `Temperature (K)` |
| 7 | User display-label override | What did the user type into a label field for this specific plot? | Plot Parameter | a custom axis title typed in a control panel |
| 8 | Special-case policy | Does this quantity opt out of the generic Display Standard entirely? | Display Standard's exception list | Scaling Law axes, Temperature Dependence axes (§4) |

A workflow adapter is only ever responsible for #1 and #3. It looks up #2 from the shared
vocabulary. Everything from #4 onward is Display Standard territory unless a Plot Parameter
override (#7) or special-case policy (#8) says otherwise.

---

## 3. Magnetic field display policy (implemented, v5.5.6)

`WorkbenchMagneticFieldUnitConverter.convert(_:from:to:)` (canonical raw unit: Oe) and
`WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for:context:unit:)` implement the approved
target from the original design draft:

| Physical quantity identity | Raw unit | Display unit (this phase) | Display label | Transform |
|---|---|---|---|---|
| `externalMagneticField` | Oe | T | `μ₀H (T)` | Oe→T `×1e-4` |
| `coerciveField` | Oe | mT | `μ₀Hc (mT)` | Oe→mT `×0.1` |

Applied at:
- **Conversion boundary (v5.6.4+, supersedes the "at payload construction" note this section
  originally shipped with):** `hField`/`hc1omega`/`hc3omega` are converted Oe→Tesla once, at
  ingestion (`ThreeOmegaFitUseCase.process()`) or at legacy-pack restore
  (`ThreeOmegaIngestionResult.normalizedToInternalTesla()`) — see
  [MAGNETIC_FIELD_STORAGE_AUDIT.md](MAGNETIC_FIELD_STORAGE_AUDIT.md) and
  `V564ThreeOmegaMagneticFieldStorageUnitTests.swift`, which owns the Oe→Tesla numeric
  assertions. `ThreeOmegaFieldSweepResult.hField`/`.hc1omega`/`.hc3omega` are canonical Tesla by
  the time any renderer sees them.
- 3ω field-sweep x-axis (`ThreeOmegaPlotRenderer.makeR1omegaPayload`): passes `hField` through
  unconverted (already T); only the display *label* is computed here.
- 3ω Hc-vs-T y-axis (`ThreeOmegaPlotRenderer.makeHcPayload`): converts `hc1omega`/`hc3omega`
  T→mT (display-unit scaling only, not the Oe→T unit-of-record migration) —
  `V556MagneticFieldUnitConversionTests.swift` locks this T→mT display scaling and the axis
  labels; it does not own the Oe→Tesla boundary.

**Deliberately not migrated in this phase — AHE.** `AHEAxisDetector.semanticXField` (currently
`"H (T)"`, unconverted-style plain label) is **not** routed through `magneticFieldLabel`, because
that string is also a `WorkbenchAxisMapping` lookup key consumed elsewhere in AHE (see
[AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md) and §7 below). Changing AHE's field label to
`μ₀H (T)` is a distinct, not-yet-scheduled migration that requires a key/label decoupling design
pass first — regression tests (`V556AHELabelKeyBoundaryRegressionTests.swift`) lock this
boundary so a future edit cannot silently cross it.

The persisted metric-identity key `"Hc"` (`AHEWorkspaceStore.swift`) is unaffected by this
policy — it is a data key, not a display label (§7).

A magnitude-based T/mT auto-switch (`μ₀H (T)` if `max|μ₀H| ≥ 0.1 T` else `μ₀H (mT)`, as sketched
in the original [UNIT_LABEL_AUDIT.md](UNIT_LABEL_AUDIT.md) §7 canonical-standard draft) is **not
implemented**. This phase uses a fixed per-quantity target unit instead (H always displays in T;
Hc always displays in mT) — simpler, and sufficient for the current product need. Revisit only if
a future product decision asks for magnitude-adaptive units.

---

## 4. Special-case policy

A special-case policy is a first-class, named entry — not a silent carve-out buried in renderer
code.

- **Scaling Law x/y axes** — literature-matching convention, permanently excluded from the
  generic Display Standard, unchanged by any later migration in this document:
  - x: `σ_{xx}^{2} × 10^{7} (S² cm⁻²)`, transform `×1e-11` from SI (S/m)².
  - y: `E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm³·V⁻²)`, transform `×1e20` (values),
    `×1e31`/`×1e20` (fit slope/intercept).
  - Implemented in `ThreeOmegaPlotRenderer.makeScalingPayload` and untouched by the Temperature
    Dependence work below — see [UNIT_LABEL_AUDIT.md](UNIT_LABEL_AUDIT.md) §4/§5 for the
    do-not-change literal values, and `V556TemperatureDependenceDisplayConventionTests.swift` for
    the regression proof that Scaling Law's labels/values are unaffected.

- **3ω Temperature Dependence tab (dual-axis) — implemented (v5.5.6).** This tab plots two
  distinct quantities, each its own physical-quantity identity (§2), permanently excluded from
  the generic Display Standard the same way Scaling Law is. It must never be conflated with the
  visually similar Scaling Law y-quantity — the left-axis quantity here is `E_AHE³ω / E_xx³`
  alone; the Scaling Law y-quantity is `E_AHE³ω / (E_xx³·σxx)`, a different ratio entirely.

  | Axis | Physical quantity identity | Source/SI unit | Display label | Display transform from SI |
  |---|---|---|---|---|
  | Left | `E_AHE³ω / E_xx³` | m² V⁻² | `E_AHE^{3ω} / E_xx^3 × 10² (μm² V⁻²)` | `×1e14` (m²→μm² is `×1e12`, plus the displayed `×10²` is another `×1e2`) |
  | Right | `σxx` | S/m | `σxx × 10³ (S cm⁻¹)` | `×1e-5` (S/m→S/cm is `×1e-2`, further divided by the displayed `×10³`) |

  Implemented in `ThreeOmegaPlotRenderer.makeTemperatureDependencePayload` via two named
  constants, `ThreeOmegaPlotRenderer.temperatureDependenceLeftYDisplayScale` (`1e14`) and
  `.temperatureDependenceRightYDisplayScale` (`1e-5`), applied to `leftY`/`rightY` at payload
  construction — not hidden inside the label. Labels are sourced from
  `WorkbenchPlotDisplayVocabulary.label(for: .temperatureDependenceERatio, ...)` and
  `.label(for: .sigmaXX, ...)`; both quantities are consumed *only* by this tab, so no other plot
  is affected by their label/transform. Regression-tested in
  `V556TemperatureDependenceDisplayConventionTests.swift`.

- **Coercive field (Hc) — implemented (v5.5.6).** See §3.

- **Device angle vs φ (3ω vs XY Rotation) — partially implemented.** Two distinct
  physical-quantity identities that happen to share the `deg` unit (§2), resolved as separate
  `WorkbenchPhysicalQuantity` cases so neither can silently inherit the other's label:

  | Physical quantity identity | Where it appears | Current label |
  |---|---|---|
  | `deviceAngle` | 3ω RAHE vs device angle | `Ψ (deg)` — renamed from the legacy `Device angle (deg)`; done |
  | `angleOffset` | XY Rotation | `φ (deg)` — this is the **legacy label, unchanged**; the vocabulary source still carries a `// Future target label: "Angle offset (deg)"` comment that has not been acted on (§8) |

  Do not read `angleOffset`'s current `φ (deg)` output as a deliberate final decision — it is
  simply not yet migrated, distinct from `deviceAngle`'s `Ψ (deg)` which is a completed rename.

---

## 5. Dataflow

```
Raw file
  → Workflow adapter / physics mapping   (owns: lookup key, raw unit)
  → Typed analysis result                (carries: physical quantity identity + raw values)
  → Plot Parameter Spec                  (resolves: display unit, scale, label —
                                           from Display Standard defaults, special-case
                                           policy, or a stored user override)
  → Control panel edits                  (writes: user display-label override, and any
                                           other user-editable field on the spec)
  → Renderer reads spec                  (reads-only: never re-derives a label or scale
                                           itself, never reaches back into the workflow's
                                           raw physics mapping)
  → Plot / manifest / export
```

The direction is one-way: a renderer never writes back into the Plot Parameter Spec, and the
spec never writes back into the workflow's physics mapping. Both the on-screen render and the
manifest/export path read the same label constants (`ThreeOmegaPlotRenderer` static labels,
sourced from `WorkbenchPlotDisplayVocabulary`) instead of each maintaining an independent string
literal — this is what closed the drift risk [UNIT_LABEL_AUDIT.md](UNIT_LABEL_AUDIT.md) §1
documented between the 3ω display path and its manifest-cache path.

---

## 6. Renderer markup convention: `math:` labels

`"math:"` is the existing semantic display-markup convention (`MathMarkupRenderer`), not a
workaround or a rendering hack: a label prefixed with `math:` carries markup
(`_{...}`/`^{...}` subscript/superscript groups) that a renderer must parse and strip before
drawing — the prefix and raw braces must never reach the screen.

- **Single-axis Workbench plots** (`WorkbenchChartRenderer`) have always consumed `math:` labels
  correctly, via `drawLeftAlignedMarkup`/`drawCenteredMarkup`/`drawRotated90Markup`, each checking
  `MathMarkupRenderer.isMathLabel` before drawing.
- **Dual-axis plots** (`DualAxisChartRenderer`, used by 3ω Temperature Dependence) did **not**
  consume this convention until v5.5.6 — its private `makeLine` built a `CTLine` directly from
  the raw label string, so the Temperature Dependence axis/legend labels (which are
  `math:`-prefixed, per §4) showed the literal `"math:E_{AHE}^{3ω} / ..."` text. Fixed by routing
  `DualAxisChartRenderer.makeLine` through `MathMarkupRenderer.isMathLabel` /
  `.extractMathMarkup` / `.makeLine`, the same three calls `WorkbenchChartRenderer` and
  `HeatmapRenderer` already use — one shared parser, not a second incompatible one. All four
  dual-axis draw primitives (`drawCentered`, `drawLeftAligned`, `drawRightAligned`,
  `drawRotated`) funnel through this single `makeLine`, so x-label, left/right y-labels, and
  legend labels are fixed together. Regression-tested via source-scan assertion
  (`V556DualAxisMathMarkupRenderingTests.swift`, mirroring the existing
  `V820HeatmapRenderPathTests` pattern — there is no pixel/glyph introspection surface in this
  codebase to assert on rendered output directly).

Vocabulary labels **retain** the `math:` prefix where they carry markup — the renderer
interprets it, the vocabulary does not strip it as a workaround. Plain labels
(`Temperature (K)`, `μ₀H (T)`, `φ (deg)`, …) are unaffected either way, since
`MathMarkupRenderer.isMathLabel` only matches the `math:` prefix.

---

## 7. Protected boundaries

- **AHE persisted/sample-library keys `"Hc"` and `"R_AHE"`** (`AHEWorkspaceStore.swift`) must
  never be renamed or sourced from `WorkbenchPlotDisplayVocabulary` output — they are per-sample
  metric-identity keys, not display labels, and renaming them would change identity for every
  already-saved library metric entry. Locked by
  `V556AHELabelKeyBoundaryRegressionTests.persistedMetricKeysRemainLiteral` (asserts the
  persisted metric names are exactly `"Hc"`/`"R_AHE"` after a real AHE analysis run) and by
  `displayLabelsAreDistinctFromPersistedMetricKeys` (asserts the *display* strings are textually
  distinct from the *persisted* keys, so a future label change cannot accidentally collide with
  them).
- **Pack/schema/user overrides must not be rewritten by display migrations.** A migration that
  changes a default label must not touch what is already stored in a pack, and must not silently
  convert an existing user override to the new default. `V556PhaseA7PackRestoreLabelDefaultTests`
  and the `_refreshManifestPayloads`/`renderTemperatureDependence` override-preservation tests
  (`V563WorkflowStateBoundaryTests`) verify both directions:
  - **Explicit legacy user label overrides continue to win** — e.g.
    `ThreeOmegaPlotRenderer.yLabelOverride` still overrides the new Temperature Dependence default
    label when set (`V556TemperatureDependenceDisplayConventionTests.explicitOverrideStillWins`).
  - **Old-pack default/empty overrides pick up the current vocabulary defaults** — a pack saved
    before a label migration, with no explicit override recorded, renders with today's default
    label (not the stale one baked into the old pack), because the renderer always re-resolves
    the default from the vocabulary at render time rather than persisting a resolved string.
- **Schema and persisted-key stability**: none of the migrations recorded in this document
  changed pack schema, restore contracts, or any persisted key. Every change was display-layer
  only (label string + numeric display transform), applied at payload-construction time.

---

## 8. Remaining architecture debt

- **AHE display/key decoupling is not complete.** `AHEAxisDetector.semanticXField`/
  `.semanticYField` remain both a display label and a `WorkbenchAxisMapping` lookup key
  simultaneously (see [AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md) §3–4 for the full
  go/no-go breakdown). The axis-label migration itself is a mechanically safe "go"; it has not
  been scheduled/executed. Do not migrate AHE's field label to `μ₀H (T)` (§3) without first
  resolving this key/label coupling.
- **Run-trace/provenance labels still contain hardcoded strings.** e.g.
  `ThreeOmegaWorkspaceStore+Plotting.swift`'s `"H (Oe)"` run-trace/provenance mapping is a raw
  provenance record, not a display axis, and was intentionally left outside this migration's
  scope (see [UNIT_LABEL_AUDIT.md](UNIT_LABEL_AUDIT.md) §2, row 3).
- **`angleOffset`'s "Angle offset (deg)" rename is still pending.** The vocabulary source carries
  a `// Future target label: "Angle offset (deg)"` comment on `.angleOffset` that has not been
  acted on — XY Rotation still displays the legacy `φ (deg)` (§4). This is unrelated to, and must
  not be confused with, `deviceAngle`'s completed `Ψ (deg)` rename.
- **The generic `WorkbenchPlotDisplayVocabulary.label(for:context:)` entry point still has
  legacy lookup-key sensitivity for `.externalMagneticField`/`.coerciveField`.** Its output for
  those two quantities cannot be changed without also affecting AHE's lookup keys (§3, §7) — this
  is why `magneticFieldLabel(for:context:unit:)` exists as a **separate** entry point rather than
  a change to `label(for:context:)` itself. Any future workflow that needs the new magnetic-field
  policy should call `magneticFieldLabel`, not `label`, for these two quantities. Display labels
  and semantic lookup keys need a proper decoupling design (AHE_LABEL_KEY_AUDIT.md §6 Phase C)
  before this dual-API situation can be collapsed back into one function.

---

## 9. Non-goals of this document

- This document does not propose new, unimplemented target labels beyond what §3/§4/§8 already
  records as deferred.
- This document does not change or authorize changes to Scaling Law, AHE, RT, XY Rotation, pack
  schema, or persisted keys — see §7 for the explicit protected-boundary list.
