# Workbench Plot Parameter / Display Spec (design draft, no behavior change)

Status: **design draft — documentation only, no code, schema, label, or numeric-scaling changes made**.
Scope: all Workbench plot-producing code (payload builders, renderers, axis mapping, label/legend
constants, numeric unit conversions).
Branch: v5.5.5.
Baseline: [UNIT_LABEL_AUDIT.md](UNIT_LABEL_AUDIT.md) (pre-migration audit of current hardcoded
label/conversion state — read that first for what exists today).

Purpose: define the target single-direction architecture that a future migration will move the
codebase toward. This document is the destination, not the migration plan — it says what the
system should look like once centralized, not how to get there step by step.

---

## 1. Core principle

Three things are conflated today (per the audit) and must be separated:

1. **Workflow-specific physics mapping** defines what the data *means* — which raw file column
   is field, which is resistance, what the raw unit is. This is owned per-workflow (3ω, AHE, RT,
   XY, IV, Scaling Law each have their own column layouts and semantics).
2. **Workbench Plot Parameters** define what a given plot *draws* — which quantity is on which
   axis, what display unit and scale apply, what label is shown. This is a per-plot, per-instance
   spec, populated by the workflow's physics mapping and editable by the control panel.
3. **Workbench Display Standard** defines the *default* labels, units, and scales for each known
   physical quantity, shared across workflows. This is where "Rxx is always `Rxx (Ω)` unless the
   user overrides it" lives, so RT, XY Rotation, and 3ω don't each invent their own string.

Control panels edit Plot Parameters. Renderers only ever read Plot Parameters — never the
workflow's raw physics mapping, and never a hardcoded label constant. This is the "single
direction" the flow name refers to: data meaning flows into parameters, parameters flow into
rendering, and nothing flows backward.

---

## 2. The eight things that must stay distinct

The audit found these conflated in various ways today (e.g. `AHEAxisDetector`'s
`semanticXField`/`semanticYField` used simultaneously as both a lookup key and a display label —
§5.3 of the audit). The target architecture keeps them as eight distinct concepts, even where one
workflow's current code collapses several into one string:

| # | Concept | Question it answers | Owner | Example |
|---|---|---|---|---|
| 1 | Workflow data lookup key | Which column/field in the raw or sidecar data does this come from? | Workflow adapter | `rawMagneticFieldColumn`, a sidecar condition name |
| 2 | Physical quantity identity | What physical quantity is this, independent of file format or workflow? | Shared vocabulary (Display Standard) | "external magnetic field", "longitudinal resistance" |
| 3 | Raw unit | What unit is the value in as it comes out of the file/parser? | Workflow adapter | Oe, A, raw ADC counts |
| 4 | Display unit | What unit should a human see it in? | Display Standard (default) or Plot Parameter (override) | T, mT, Ω |
| 5 | Numeric display scale | What multiply/divide/branch converts raw unit → display unit? | Display Standard (default policy) or Plot Parameter (special case) | `/10000` Oe→T, magnitude-based T/mT switch |
| 6 | Default display label | What string is shown when nobody has customized anything? | Display Standard | `Rxx (Ω)`, `Temperature (K)` |
| 7 | User display-label override | What did the user type into a label field for this specific plot? | Plot Parameter | a custom axis title typed in a control panel |
| 8 | Special-case policy | Does this quantity opt out of the generic Display Standard entirely? | Display Standard's exception list | Scaling Law axes (§4) |

A workflow adapter is only ever responsible for #1 and #3 (it knows its own file format). It looks
up #2 from the shared vocabulary. Everything from #4 onward is Display Standard territory unless a
Plot Parameter override (#7) or special-case policy (#8) says otherwise.

Keeping #1 separate from #2 specifically fixes the AHE issue in the audit: the sidecar lookup key
and the physical-quantity identity can be the same string by coincidence, but they must not be
*required* to be the same string, or renaming a display label risks silently breaking a data
lookup.

**Resolution rule: the Display Standard resolves defaults by physical-quantity identity (#2), never
by unit (#4).** Two quantities can share a display unit and still be different quantities requiring
different labels — sharing a unit is not evidence of sharing an identity. Confirmed example: device
angle (`deviceAngle`) and the XY Rotation angle offset both use `deg`, but they are two distinct
physical-quantity identities with two distinct labels (§4). A lookup keyed on unit instead of
identity would wrongly merge them.

---

## 3. Workflow responsibilities

Each workflow owns steps that produce a **Typed analysis result** carrying physical-quantity
identities (concept #2 above), not display strings. None of them own the Display Standard, and
none of them should hardcode a label or conversion factor that duplicates what another workflow
already defines for the same quantity.

- **3ω**: parser/assembly maps raw columns to `H (Oe)`, `V1ω`, `V3ω`, `R_H`, run-trace `T (K)`,
  `Rxx`. This workflow currently has the largest surface (23 label constants across the renderer,
  plus a second independent set in the manifest cache — audit §3) and is the primary migration
  target for collapsing duplicate Oe→T conversions (audit §4, items #1/#2) into a single Display
  Standard policy. Its Temperature Dependence tab carries its own confirmed special-case display
  convention (§4) that stays outside this general migration, the same way Scaling Law does.
- **AHE**: owns its own data-column/semantic lookup mapping (its own version of concept #1), but
  its plots' display labels must resolve through the same Workbench Display Standard as every
  other workflow — not a locally hardcoded `"H (T)"` / `"R_H (Ω)"` pair that also happens to serve
  as a lookup key (audit §5.3). Decoupling the lookup key from the label is this workflow's
  specific migration risk, flagged for a dedicated design pass before touching it.
- **RT / XY / IV**: same pattern — each parses its own raw columns into typed quantities (Rxx,
  device angle/φ, current, voltage), then defers to the shared Display Standard for label/unit/
  scale. IV's existing mA/A, peak/RMS scale-factor enum (audit §5.5) is the closest thing in the
  codebase today to what a Plot Parameter's numeric-display-scale field should look like, and is a
  reasonable reference pattern rather than something to discard.
- **Scaling Law**: the user-approved special display convention (σxx² ×10⁷ S²·cm⁻² on x;
  E_AHE³ω/(E_xx³·σxx) ×10² Ω·μm³·V⁻² on y, with the associated `1e-11`/`1e20`/`1e31` factors) is
  preserved exactly as a named special-case policy (concept #8), not as an implicit exception
  nobody documented. See the audit's §5 do-not-change list for the literal values.

---

## 4. Special-case policy

A special-case policy is a first-class, named entry — not a silent carve-out buried in renderer
code. The known entries at design time are the ones already identified by the audit:

- **Scaling Law x/y axes** (§3 above) — literature-matching convention, permanently excluded from
  the generic Display Standard, not a temporary gap to close later.
- **3ω Temperature Dependence tab (dual-axis)** — **confirmed, user-approved special display
  convention** (approved 2026-07-03), permanently excluded from the generic Display Standard the
  same way Scaling Law is. This tab plots two distinct quantities that are each their own
  physical-quantity identity (concept #2) and must never be conflated with the visually similar
  Scaling Law y-quantity (audit §5.4) — the left-axis quantity here is `E_AHE³ω / E_xx³` alone;
  the Scaling Law y-quantity is `E_AHE³ω / (E_xx³·σxx)`, a different ratio entirely.

  | Axis | Physical quantity identity | Source/SI unit | Display label | Display transform from SI |
  |---|---|---|---|---|
  | Left | `E_AHE³ω / E_xx³` | m² V⁻² | `E_AHE³ω / E_xx³ × 10² (μm² V⁻²)` | `×10¹⁴` (m²→μm² is `×10¹²`, plus the displayed `×10²` is another `×10²`) |
  | Right | `σxx` | S/m | `σxx × 10³ (S cm⁻¹)` | `×10` (S/m→S/cm is `×10⁻²`, plus the displayed `×10³` is `×10³`) |

  This is a documentation-only record of the approved target convention. No renderer, label
  constant, or numeric scaling has been changed to implement it yet — see
  [UNIT_LABEL_AUDIT.md §2/§5](UNIT_LABEL_AUDIT.md) for the current as-implemented state
  (`σxx (S/m)` unscaled, `E_AHE³ω / E_xx³` unitless/unscaled).
- **Coercive field (Hc)** — **confirmed target migration decision** (approved 2026-07-03),
  documentation-only, not yet implemented. Hc migrates away from Oe and follows the same
  magnitude-based field-display policy as external magnetic field (H), rather than staying a
  permanent Oe-only special case:

  | Physical quantity identity | Source/SI unit (as stored) | Target display label | Target transform |
  |---|---|---|---|
  | Coercive field (`Hc`) | Oe | `μ₀Hc (T)`, or `μ₀Hc (mT)` when the displayed magnitude is below the field-policy threshold | Oe→T: `×1e-4`; Oe→mT: `×0.1` |

  As-implemented today, per audit §2, Hc is still shown unconverted in Oe end-to-end
  (`math:H_{c} (Oe)`, `ThreeOmegaPlotRenderer.swift:24,591-593`; `"Hc (Oe)"` in the manifest path,
  `ThreeOmegaWorkspaceStore+ManifestCache.swift:176`). This entry records the approved target
  only — no renderer, label constant, or conversion has changed, and current plots still render
  Hc in Oe exactly as before.
- **Device angle vs φ** (3ω vs XY Rotation) — **resolved** (approved 2026-07-03),
  documentation-only, not yet implemented. What the audit previously flagged as "same physical
  quantity, two labels" is now confirmed to be **two distinct physical-quantity identities** that
  happen to share the `deg` unit (see the resolution rule above):

  | Physical quantity identity | Where it appears today | Canonical label |
  |---|---|---|
  | `deviceAngle` | 3ω RAHE vs device angle (`ThreeOmegaPlotRenderer.swift:18`) | `Ψ (deg)` |
  | XY rotation shift / angle offset (e.g. `rotationAngleShift` / `angleOffset`) | XY Rotation (currently labeled `"φ (deg)"`, `XYRotationPlotRenderer.swift:263,273`) | `Angle offset (deg)` (suggested; may change if existing product text requires a different label) |

  The XY Rotation quantity must not inherit the `deviceAngle` label `Ψ (deg)` — it is a separate
  identity, not an alias. This entry records the approved target labels only; the current `"φ
  (deg)"` string in `XYRotationPlotRenderer.swift`/`XYRotationWorkspaceStore.swift:579` has not
  been changed and current plots still render exactly as before.

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
spec never writes back into the workflow's physics mapping. This is what closes the drift risk
the audit documented between `ThreeOmegaPlotRenderer` (the display path) and
`ThreeOmegaWorkspaceStore+ManifestCache` (the manifest path) independently hardcoding the same
quantity's label — under this architecture there is exactly one Plot Parameter Spec per plot, and
both the on-screen render and the manifest/export read the same spec instance instead of each
maintaining their own string literal.

---

## 6. Non-goals of this document

- No label text changes. No renderer, schema, or code of any kind has changed as a result of this
  document — current plots (including Hc and device-angle/φ axes) still render exactly as before.
- No numeric conversion changes — the Hc Oe→T/mT transform and the deviceAngle/angle-offset label
  split recorded in §4 are target decisions only, not yet implemented.
- No schema or type introduced yet — this is the conceptual model the schema will be designed
  against next.
- All product decisions previously open in this document (Hc field-display policy, Device angle vs
  φ) are now resolved as of 2026-07-03 — see §4. Remaining open items, if any arise, will be called
  out the same way so they are not silently decided.
