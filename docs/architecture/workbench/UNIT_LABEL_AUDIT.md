# Workbench Plot Unit / Label Audit (pre-migration, audit-only)

Status: **audit only — no behavior, schema, or label changes made**. This document is a frozen
historical record of the **v5.5.5** pre-migration state; it is not updated to track later
implementation. Do not read any "not yet implemented" statement below as still true today.
Scope: all Workbench plot-producing code (payload builders, renderers, axis mapping, label/legend constants, numeric unit conversions).
Branch: v5.5.5.

Purpose: baseline the current state before a future centralized SI/publication-style
display standard is designed. This document intentionally does not implement anything.

> **Status update (v5.5.6) — read this first.** The centralized display standard this audit
> called for has since been designed and partially implemented. See
> [PLOT_DISPLAY_SPEC.md](PLOT_DISPLAY_SPEC.md) for the current, implemented architecture:
> - Magnetic field (H/Hc) display policy (§5 item 7, §7 canonical-standard draft below) —
>   **implemented**, see PLOT_DISPLAY_SPEC.md §3.
> - 3ω Temperature Dependence dual-axis convention (§5 item 6 below) — **implemented**, see
>   PLOT_DISPLAY_SPEC.md §4.
> - Device angle vs XY Rotation `φ` (§5 item 8 below) — **implemented**, see
>   PLOT_DISPLAY_SPEC.md §4.
> - Scaling Law (§5 items 1–2 below) — **unchanged**, exactly as this audit recorded it.
> - AHE's `"H (T)"`/`"R_H (Ω)"` labels (§2 row 2, §5 item 3 below) — **still not migrated**;
>   deliberately out of scope, see PLOT_DISPLAY_SPEC.md §3/§8 and
>   [AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md).
> - `math:` markup rendering on the dual-axis path — was missing at audit time, now fixed; see
>   PLOT_DISPLAY_SPEC.md §6.

---

## 1. Summary

- **~14 distinct physical quantities** appear in Workbench plot axis/legend/title strings
  (field, coercive field, temperature, device angle, R¹ω, R³ω, R_AHE¹ω, R_AHE³ω, R_AHE (combined),
  Rxx, Rxy, R_H, σxx, σxx² scaling quantity, E_AHE³ω/E_xx³ ratio, scaling-law y quantity,
  current, voltage).
- **Labels are defined locally in the renderer/use-case layer**, not centrally. The main
  concentration is `ThreeOmegaPlotRenderer.swift:16-39` (23 static string constants), but
  `RTPlotRenderer.swift`, `XYRotationPlotRenderer.swift`, `IVPlotRenderer.swift`,
  `AHEAxisDetector.swift`, and `ThreeOmegaWorkspaceStore+ManifestCache.swift` each also
  hardcode their own axis-label string literals independently. There is no shared
  label-vocabulary module today.
- **A real duplication/drift risk exists today**: the 3ω display path
  (`ThreeOmegaPlotRenderer.swift`) uses `math:`-prefixed styled labels
  (e.g. `math:R^{1ω} (Ω)`), while the manifest/provenance path
  (`ThreeOmegaWorkspaceStore+ManifestCache.swift`) independently hardcodes plain-text
  equivalents (e.g. `"R(1ω) (Ω)"`). These are two separate string literals with no shared
  source of truth, except for the Scaling Law pair, which the manifest path correctly
  references by symbol.
- **Unit conversion is hardcoded at point of use**, mostly in
  `ThreeOmegaPlotRenderer.swift` (Oe→T via `/10000`, and the Scaling Law SI→display
  factors `1e-11`, `1e20`, `1e31`), `IngestAHESelectionsUseCase.swift` (Oe→T via `*1e-4`),
  and `IVIngestionContracts.swift` (A→mA, and RMS/peak scaling). No conversion is centralized
  or policy-driven (e.g. no magnitude-based T-vs-mT switch exists anywhere in the codebase
  today — confirmed by search, this is a genuinely new proposal, not a partial
  implementation).
- **Special cases that must not change in the first migration**: the Scaling Law x-axis
  (`σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})`) and y-axis
  (`E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})`) labels and their SI→display
  conversion factors (`1e-11`, `1e20`, `1e31` for the fit slope). These are literature-matching,
  formula-specific conventions, not generic SI display and are explicitly excluded from this
  migration's early phases.
- **A second special display convention has since been approved (2026-07-03, documentation-only,
  not yet implemented)**: the 3ω Temperature Dependence tab's dual axes. See §5 item 6 for the
  approved target labels and transforms. As with Scaling Law, this is excluded from the generic
  SI display standard — but unlike Scaling Law, the code has not yet been changed to match; the
  table in §2 below still reflects the as-implemented (unscaled) state.
- **Two further product decisions have since been confirmed (2026-07-03, documentation-only, not
  yet implemented)**: Coercive field (Hc) migrates to the same magnitude-based field-display
  policy as external magnetic field (target `μ₀Hc (T)`/`(mT)`); and Device angle vs XY Rotation's
  `φ` are confirmed as two distinct physical-quantity identities (`deviceAngle` → `Ψ (deg)`; the
  XY Rotation quantity is a separate identity → `Angle offset (deg)`, suggested). See §5 items 7-8
  and [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md). Neither has been implemented — code still
  renders Hc in Oe and XY Rotation's angle in `φ (deg)` exactly as before.

---

## 2. Physical quantity table

| Quantity | Current label(s) | Workflow / plot | File(s) | Raw unit assumption | Display unit | Numeric conversion | Recommended canonical label | Migration priority | Risk |
|---|---|---|---|---|---|---|---|---|---|
| Magnetic field (H) | `"H (T)"` | 3ω R¹ω/R³ω vs H | `ThreeOmegaPlotRenderer.swift:16` | Oe (raw PPMS column) | T | `/10000` at `ThreeOmegaPlotRenderer.swift:403`, `ThreeOmegaWorkspaceStore+ManifestCache.swift:24` | `μ₀H (T)` / `μ₀H (mT)` (range-dependent) | P2 | Medium — label rename only if conversion policy also changes; touches 2 files kept in sync manually today |
| Magnetic field (H) | `"H (T)"` | AHE Hall resistance | `AHEAxisDetector.swift:5` (`semanticXField`) | Oe (`rawMagneticFieldColumn`, line 7) | T | `*1e-4` at `IngestAHESelectionsUseCase.swift:75` | `μ₀H (T)` / `μ₀H (mT)` | P2 | Medium — this label is also used as a **semantic field-name key**, not just display text (see §5) |
| Magnetic field (H) | `"H (Oe)"` | 3ω run-trace/provenance mapping | `ThreeOmegaWorkspaceStore+Plotting.swift:289` | Oe | Oe (no conversion — provenance, not display) | none | leave as-is (provenance record, not a display axis) | — | Low |
| Coercive field (Hc) | `math:H_{c} (Oe)"` | 3ω Hc vs T | `ThreeOmegaPlotRenderer.swift:24`, `:591-593` | Oe (`ThreeOmegaFieldSweepResult.swift:39-40`, stored as Oe) | Oe (as-implemented, unconverted) | none (as-implemented) | **Confirmed target (not yet implemented):** `μ₀Hc (T)` / `μ₀Hc (mT)` (magnitude-based, same policy as external field H), transform Oe→T `×1e-4`, Oe→mT `×0.1` — see [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md) | Special case (confirmed 2026-07-03, docs-only) | Medium-high if implemented — currently Oe end-to-end, unlike H-field which already has partial Oe→T conversion to reuse |
| Coercive field (Hc), manifest path | `"Hc (Oe)"` | 3ω Hc tab manifest | `ThreeOmegaWorkspaceStore+ManifestCache.swift:176` | Oe | Oe (as-implemented) | none (as-implemented) | same target as above | Special case (confirmed 2026-07-03, docs-only) | Low (plain-text duplicate of above) |
| Temperature | `"T (K)"` | 3ω, RT, IV point labels | `ThreeOmegaPlotRenderer.swift:17`, `RTPlotRenderer.swift:59`, `RTWorkspaceStore.swift:442`, `ThreeOmegaWorkspaceStore+ManifestCache.swift:176,179` | K | K | none | `Temperature (K)` | P1 (label text only, no unit change) | Low |
| Device angle (`deviceAngle` identity) | `"Device angle (deg)"` | 3ω RAHE vs angle | `ThreeOmegaPlotRenderer.swift:18`, `ThreeOmegaWorkspaceStore+ManifestCache.swift:163,171` | deg | deg (as-implemented) | none | **Confirmed target (not yet implemented):** `Ψ (deg)` — see [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md) | Resolved 2026-07-03, docs-only | Low |
| XY rotation shift / angle offset (separate identity from `deviceAngle`) | `"φ (deg)"` | XY Rotation | `XYRotationPlotRenderer.swift:263,273`, `XYRotationWorkspaceStore.swift:579` | deg | deg (as-implemented) | none | **Confirmed target (not yet implemented):** `Angle offset (deg)` (suggested, may change per existing product text) — same `deg` unit as `deviceAngle` but a **distinct physical-quantity identity**; must not inherit the `Ψ (deg)` label | Resolved 2026-07-03, docs-only | Low — resolved naming, previously flagged as a product decision |
| R¹ω | `math:R^{1ω} (Ω)"` | 3ω R(1ω) tab | `ThreeOmegaPlotRenderer.swift:20,238-239` | Ω | Ω | none | `R¹ω (Ω)` | P1 | Low |
| R¹ω, manifest path | `"R(1ω) (Ω)"` | 3ω R(1ω) manifest | `ThreeOmegaWorkspaceStore+ManifestCache.swift:134-135` | Ω | Ω | none | same, reconcile with display-path constant | P1 | Low — plain-text duplicate, drift risk if renderer constant changes without updating this |
| R³ω | `math:R^{3ω} (Ω)"` | 3ω R(3ω) tab | `ThreeOmegaPlotRenderer.swift:21,256-257` | Ω | Ω | none | `R³ω (Ω)` | P1 | Low |
| R³ω, manifest path | `"R(3ω) (Ω)"` | 3ω R(3ω) manifest | `ThreeOmegaWorkspaceStore+ManifestCache.swift:149-150` | Ω | Ω | none | same | P1 | Low — duplicate |
| R_AHE¹ω | `math:R_{AHE}^{1ω} (Ω)"` | 3ω RAHE vs device angle | `ThreeOmegaPlotRenderer.swift:22,33,529-530,536` | Ω | Ω | none | `R_AHE¹ω (Ω)` | P1 | Low |
| R_AHE¹ω, manifest path | `"RAHE(1ω) (Ω)"` | 3ω RAHE(1ω) manifest | `ThreeOmegaWorkspaceStore+ManifestCache.swift:161-166` | Ω | Ω | none | same | P1 | Low — duplicate |
| R_AHE³ω | `math:R_{AHE}^{3ω} (Ω)"` | 3ω RAHE vs device angle | `ThreeOmegaPlotRenderer.swift:23,34,529-530,536` | Ω | Ω | none | `R_AHE³ω (Ω)` | P1 | Low |
| R_AHE³ω, manifest path | `"RAHE(3ω) (Ω)"` | 3ω RAHE(3ω) manifest | `ThreeOmegaWorkspaceStore+ManifestCache.swift:169-174` | Ω | Ω | none | same | P1 | Low — duplicate |
| R_AHE (combined vs T) | `math:R_{AHE} (Ω)"` | 3ω combined RAHE vs T | `ThreeOmegaPlotRenderer.swift:28,316,326` | Ω | Ω | none | `R_AHE (Ω)` | P1 | Low |
| Rxx | `math:R_{xx} (Ω)"` | 3ω Rxx vs T | `ThreeOmegaPlotRenderer.swift:25,37,615-619` | Ω | Ω | none | `Rxx (Ω)` | P1 | Low |
| Rxx | `"Rxx (Ω)"` | RT workflow | `RTPlotRenderer.swift:59`, `RTWorkspaceStore.swift:442`, `ThreeOmegaWorkspaceStore+ManifestCache.swift:179` | Ω | Ω | none | `Rxx (Ω)` (already matches) | P1 | Low |
| Rxx | `"Rxx (Ω)"` | XY Rotation | `XYRotationPlotRenderer.swift:165` | Ω | Ω | none | same | P1 | Low |
| Rxy | `"Rxy (Ω)"` | XY Rotation | `XYRotationPlotRenderer.swift:181` | Ω | Ω | none | `Rxy (Ω)` (not explicitly requested but same family) | P1 | Low |
| R_H (Hall) | `"R_H (Ω)"` | AHE | `AHEAxisDetector.swift:6` (`semanticYField`) | Ω | Ω | none | `R_H (Ω)` — used as semantic field-name key, see §5 | P1 (flag — key vs label conflation) | Medium |
| σxx | `math:σ_{xx} (S/m)"` | 3ω Temperature Dependence (dual-axis right) | `ThreeOmegaPlotRenderer.swift:26,39,709,719` | computed SI (`ThreeOmegaScalingUseCase.swift:64`, `σ_xx = 1/ρ_xx`) | S/m (as-implemented, unscaled) | none (as-implemented) | **Approved target (not yet implemented):** `σxx × 10³ (S cm⁻¹)`, transform `×10` from SI — see [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md) | Special case (confirmed 2026-07-03, docs-only) | Low as audited today; migration risk is in implementing the new `×10` transform, not in this row |
| σxx² (Scaling Law x) | `math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"` | 3ω Scaling Law | `ThreeOmegaPlotRenderer.swift:30,734,766,770-771,804-807`, `ThreeOmegaScalingUseCase.swift:87-88` | (S/m)² SI | S²·cm⁻² ×10⁷ | `*1e-11` at 3 call sites | **do not change** — preserve exactly | Special case (excluded) | High if touched — literature-matching convention |
| E_AHE³ω/(E_xx³·σxx) (Scaling Law y) | `math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"` | 3ω Scaling Law | `ThreeOmegaPlotRenderer.swift:31,735,755-756,767,804-807` | Ω·m³·V⁻² SI | Ω·μm³·V⁻² ×10² | `*1e20` (values), `*1e31`/`*1e20` (fit α/β) | **do not change** — preserve exactly | Special case (excluded) | High if touched |
| E_AHE³ω / E_xx³ (Temperature Dependence, left axis) | `math:E_{AHE}^{3ω} / E_{xx}^{3}"` | 3ω Temperature Dependence (dual-axis left) | `ThreeOmegaPlotRenderer.swift:27,38,708,712` | m² V⁻² SI (as-implemented display: unitless/unscaled) | unitless (as-implemented) | none (as-implemented) | **Approved target (not yet implemented):** `E_AHE³ω / E_xx³ × 10² (μm² V⁻²)`, transform `×10¹⁴` from SI (m²→μm² is `×10¹²`, plus displayed `×10²`) — see [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md). Confirmed as a **distinct physical-quantity identity** from the Scaling Law y-quantity (`E_AHE³ω/(E_xx³·σxx)`) — do not conflate. | Special case (confirmed 2026-07-03, docs-only) | Medium — naming collision risk with Scaling Law y remains the thing to guard against when implementing |
| Current (IV, mA display) | `"Current (mA, peak)"` / `"Current (mA, RMS)"` | IV workflow | `IVIngestionContracts.swift:33-34` | A | mA | `*1000.0` (peak, line 26), `*1000.0/√2` (RMS, line 27), applied at `IVPlotRenderer.swift:159-162` | `Current (mA)` family, peak/RMS as sub-label | P3 | Low-medium — two scale factors already policy-driven via an enum, good existing pattern to reuse |
| Current (IV, legacy A display) | `"Current (A, peak)"` / `"Current (A, RMS)"` | IV workflow (legacy) | `IVIngestionContracts.swift:40-41` | A | A | none (RMS peak/√2 only) | keep as legacy-compat option | P3 | Low |
| Voltage | `"V (V)"` | IV workflow, 1st/2nd harmonic | `IVPlotRenderer.swift:56,113`, `IVWorkspaceStore.swift:573` | V | V | none | `V (V)` (already matches) | P1 | Low |

---

## 3. Hardcoded label inventory

**`Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`** (lines 16–39, canonical 3ω display-path constants):
- `"H (T)"` → magnetic field axis (`fieldAxisLabel`)
- `"T (K)"` → temperature axis (`temperatureAxisLabel`)
- `"Device angle (deg)"` → device angle axis (`deviceAngleAxisLabel`)
- `math:R^{1ω} (Ω)` → R¹ω axis (`r1AxisLabel`)
- `math:R^{3ω} (Ω)` → R³ω axis (`r3AxisLabel`)
- `math:R_{AHE}^{1ω} (Ω)` → R_AHE¹ω axis (`rAHE1AxisLabel`)
- `math:R_{AHE}^{3ω} (Ω)` → R_AHE³ω axis (`rAHE3AxisLabel`)
- `math:H_{c} (Oe)` → coercive field axis (`hcAxisLabel`)
- `math:R_{xx} (Ω)` → Rxx axis (`rxxAxisLabel`)
- `math:σ_{xx} (S/m)` → σxx axis (`sigmaXXAxisLabel`)
- `math:E_{AHE}^{3ω} / E_{xx}^{3}` → E ratio axis (`eAHEOverE3AxisLabel`)
- `math:R_{AHE} (Ω)` → combined R_AHE axis (`rAHEAxisLabel`)
- `math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})` → **Scaling Law x-axis** (`scalingXAxisLabel`)
- `math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})` → **Scaling Law y-axis** (`scalingYAxisLabel`)
- `math:R_{AHE}^{1ω}` → R_AHE¹ω legend (`rAHE1LegendLabel`)
- `math:R_{AHE}^{3ω}` → R_AHE³ω legend (`rAHE3LegendLabel`)
- `math:H_{c}^{1ω}` → Hc¹ω legend (`hc1LegendLabel`)
- `math:H_{c}^{3ω}` → Hc³ω legend (`hc3LegendLabel`)
- `math:R_{xx}` → Rxx legend (`rxxLegendLabel`)
- `math:E_{AHE}^{3ω} / E_{xx}^{3}` → E ratio legend (`eAHEOverE3LegendLabel`)
- `math:σ_{xx}` → σxx legend (`sigmaXXLegendLabel`)
- Titles: `"R(1ω)"` (line 239), `"R(3ω)"` (line 257), `"H_c"` (line 592), `"R_xx(T)"` (line 615), `"R_AHE(\(hLabel)) (\(methodTag))"` (line 535, composed)

**`Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift`** (plain-text duplicate set):
- `"H (T)"` → field axis, lines 135, 150
- `"H (Oe)"` → run-trace field axis (not display), `ThreeOmegaWorkspaceStore+Plotting.swift:289`
- `"R(1ω) (Ω)"` → R¹ω axis, line 135
- `"R(3ω) (Ω)"` → R³ω axis, line 150
- `"RAHE(1ω) (Ω)"` → R_AHE¹ω axis, line 163
- `"RAHE(3ω) (Ω)"` → R_AHE³ω axis, line 171
- `"T (K)"` → temperature axis, lines 176, 179
- `"Hc (Oe)"` → coercive field axis, line 176
- `"Device angle (deg)"` → device angle axis, lines 163, 171
- `"Rxx (Ω)"` → Rxx axis, line 179
- Titles composed via `resolveTitle("R(1ω)")` etc. (lines 134, 149, 161, 169, 176)

**`Sources/SpinLabApp/UseCases/RTPlotRenderer.swift`**:
- `"T (K)"` → temperature axis, line 59
- `"Rxx (Ω)"` → Rxx axis, line 59

**`Sources/SpinLabApp/Features/Workbench/RTWorkspaceStore.swift`**:
- `"T (K)"` / `"Rxx (Ω)"` → run-trace mapping, line 442

**`Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`**:
- `"φ (deg)"` → device angle axis, lines 263, 273
- `"Rxx (Ω)"` → Rxx axis, line 165
- `"Rxy (Ω)"` → Rxy axis, line 181

**`Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`**:
- `"φ (deg)"` / `"R (Ω)"` → run-trace mapping, line 579

**`Sources/SpinLabApp/UseCases/AHEAxisDetector.swift`**:
- `"H (T)"` → AHE field axis / semantic field key, line 5
- `"R_H (Ω)"` → AHE Hall resistance axis / semantic field key, line 6
- `"Magnetic Field (Oe)"` → raw PPMS column name (input side, not display), line 7

**`Sources/SpinLabApp/UseCases/IVPlotRenderer.swift`**:
- `"V (V)"` → voltage axis, lines 56, 113

**`Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift`**:
- `"V (V)"` → voltage axis, line 573

**`Sources/SpinLabApp/Workbench/V3/IVIngestionContracts.swift`**:
- `"Current (mA, peak)"` / `"Current (mA, RMS)"` → current axis, lines 33-34
- `"Current (A, peak)"` / `"Current (A, RMS)"` → legacy current axis, lines 40-41

Point-label / tick-formatting strings (not axis labels, but hardcoded unit text on plotted points):
- `"\(Int(t.rounded())) K"` → `ThreeOmegaPlotRenderer.swift:910-912`, `ThreeOmegaWorkspaceStore+ManifestCache.swift:289-291`, `:736`
- `"\(Int(t)) K"` / `"%.1f K"` → `IVPlotRenderer.swift:153-157`, `XYRotationPlotRenderer.swift:310-314`
- `"\(Int($0.angle.rounded()))°"` → `ThreeOmegaPlotRenderer.swift:528`

---

## 4. Numeric conversion inventory

| # | Conversion | Source unit | Target unit | Location | Axis label matches? | Preserve as special case? |
|---|---|---|---|---|---|---|
| 1 | `/10000` | Oe | T | `ThreeOmegaPlotRenderer.swift:403` | Yes (`"H (T)"`) | No — candidate for centralized μ₀H policy |
| 2 | `/10000` | Oe | T | `ThreeOmegaWorkspaceStore+ManifestCache.swift:24` | Yes | No — duplicate of #1, should collapse to one implementation |
| 3 | `*1e-4` | Oe | T | `IngestAHESelectionsUseCase.swift:75` | Yes (`semanticXField = "H (T)"`) | No — same Oe→T conversion as #1/#2, third independent implementation |
| 4 | `*1e-11` | (S/m)² | S²·cm⁻² ×10⁷ | `ThreeOmegaPlotRenderer.swift:734,766,770-771` | Yes, matches `scalingXAxisLabel` | **Yes — Scaling Law special case** |
| 5 | `*1e20` | Ω·m³·V⁻² | Ω·μm³·V⁻² ×10² | `ThreeOmegaPlotRenderer.swift:735,756,767` | Yes, matches `scalingYAxisLabel` | **Yes — Scaling Law special case** |
| 6 | `*1e31` | SI (fit slope α) | Ω·μm³·cm²·V⁻²·S⁻² | `ThreeOmegaPlotRenderer.swift:755`, `ThreeOmegaWorkspaceStore+Plotting.swift:271` | Yes (fit-line rendering, comment-documented) | **Yes — Scaling Law special case** |
| 7 | `*1e20` (β) | SI (fit intercept β) | Ω·μm³·V⁻² | `ThreeOmegaWorkspaceStore+Plotting.swift:272` | Yes | **Yes — Scaling Law special case** |
| 8 | `*1000.0` | A | mA (peak) | `IVIngestionContracts.swift:26`, applied `IVPlotRenderer.swift:159-162` | Yes (`"Current (mA, peak)"`) | No — but already policy-driven via enum, good pattern to reuse |
| 9 | `*1000.0/√2` | A (peak) | mA (RMS) | `IVIngestionContracts.swift:27` | Yes (`"Current (mA, RMS)"`) | No |
| 10 | `*1e-9` | nm | m | `ThreeOmegaScalingUseCase.swift:38` | N/A — upstream geometry input, not a display axis | Feeds Scaling Law special case indirectly |
| 11 | `*1e-6` | μm | m | `ThreeOmegaScalingUseCase.swift:39-40` | N/A — upstream geometry input | Feeds Scaling Law special case indirectly |

No conversion found for: coercive field (Hc stays in Oe end-to-end, no T conversion exists today —
this is a gap relative to the proposed μ₀H_c policy, not a bug); temperature, device angle,
resistance quantities, σxx (all already in target display unit with no conversion needed).

---

## 5. Special cases / do-not-change list

1. **Scaling Law x-axis**: `math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})` and its `1e-11` conversion
   factor — `ThreeOmegaPlotRenderer.swift:30,734,766,770-771`. Preserve unchanged.
2. **Scaling Law y-axis**: `math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})` and
   its `1e20`/`1e31` conversion factors — `ThreeOmegaPlotRenderer.swift:31,735,755-756,767`,
   `ThreeOmegaWorkspaceStore+Plotting.swift:271-272`. Preserve unchanged.
3. **AHE semantic field-name keys**: `AHEAxisDetector.semanticXField` (`"H (T)"`) and
   `semanticYField` (`"R_H (Ω)"`) are used elsewhere in the codebase as **lookup keys**, not
   purely as display text — per the existing project rule "no self-named variables," Workbench
   fields are looked up by these exact sidecar condition-name strings. Renaming these strings
   is not a pure label change; it risks breaking field lookups unless all call sites are
   migrated together. Flag for Phase 2/3 design, not Phase 1.
4. **`E_AHE³ω / E_xx³` (Temperature Dependence left axis)** vs the Scaling Law y-quantity: these
   are visually similar names but different plotted quantities
   (`ThreeOmegaPlotRenderer.swift:27` vs `:31`). Do not merge or rename by pattern-matching the
   string; treat as two separate quantities. **Resolved 2026-07-03**: confirmed as two distinct
   physical-quantity identities — see item 6 below for the approved display convention. This does
   not change the fact that they remain separate quantities requiring separate handling wherever
   a future migration touches either one.
5. **IV current unit families** (mA vs legacy A, peak vs RMS) already use a policy-driven scale
   factor via an enum (`IVIngestionContracts.swift:26-27`) rather than ad-hoc literals — this is
   arguably the pattern the future centralized policy should generalize, not a case needing
   correction.
6. **3ω Temperature Dependence tab (dual-axis) — user-approved special display convention
   (confirmed 2026-07-03, documentation-only, not yet implemented)**, permanently excluded from
   the generic Display Standard the same way Scaling Law is:
   - Left axis — `E_AHE³ω / E_xx³`, SI unit m² V⁻², approved display label
     `E_AHE³ω / E_xx³ × 10² (μm² V⁻²)`, approved transform from SI `×10¹⁴` (m²→μm² is `×10¹²`,
     plus the displayed `×10²` is another `×10²`).
   - Right axis — `σxx`, SI unit S/m, approved display label `σxx × 10³ (S cm⁻¹)`, approved
     transform from SI `×10` (S/m→S/cm is `×10⁻²`, plus the displayed `×10³` is `×10³`).
   - As-implemented today, per §2 above, neither axis has this scaling — σxx is shown unscaled in
     S/m and the left-axis ratio is shown unitless/unscaled. This entry records the approved
     target only; no renderer, label constant, or numeric conversion has changed. See
     [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md) for the full spec-level record.
7. **Coercive field (Hc) — confirmed target migration decision (confirmed 2026-07-03,
   documentation-only, not yet implemented)**: Hc migrates away from Oe and follows the same
   magnitude-based field-display policy as external magnetic field (H), rather than remaining a
   permanent Oe-only exception. Target label `μ₀Hc (T)` / `μ₀Hc (mT)` (below the field-policy
   magnitude threshold); target transform from the raw stored Oe value is `×1e-4` (T) or `×0.1`
   (mT). As-implemented today Hc is still Oe end-to-end with no conversion
   (`ThreeOmegaPlotRenderer.swift:24,591-593`; `ThreeOmegaWorkspaceStore+ManifestCache.swift:176`)
   — this item records the approved target only. See
   [PLOT_DISPLAY_SPEC.md §4](PLOT_DISPLAY_SPEC.md).
8. **Device angle vs XY Rotation `φ` — resolved (confirmed 2026-07-03, documentation-only, not yet
   implemented)**: these are two distinct physical-quantity identities that happen to share the
   `deg` unit, not one quantity with two label conventions. Per the identity-not-unit resolution
   rule ([PLOT_DISPLAY_SPEC.md §2](PLOT_DISPLAY_SPEC.md)):
   - `deviceAngle` (3ω RAHE vs angle, `ThreeOmegaPlotRenderer.swift:18`) → canonical label
     `Ψ (deg)`.
   - The XY Rotation quantity (currently hardcoded `"φ (deg)"`,
     `XYRotationPlotRenderer.swift:263,273`, `XYRotationWorkspaceStore.swift:579`) is a **separate**
     identity (e.g. `rotationAngleShift` / `angleOffset`) → suggested label `Angle offset (deg)`,
     subject to change if existing product text requires otherwise. It must not inherit
     `deviceAngle`'s `Ψ (deg)` label.
   - As-implemented today, neither renderer has changed — 3ω still shows `"Device angle (deg)"`
     and XY Rotation still shows `"φ (deg)"`, exactly as before.

---

## 6. Recommended first migration plan (proposed, not implemented)

**Phase 1 — centralize label vocabulary only, no numeric changes.**
Introduce one shared label-constant source (e.g. a `WorkbenchUnitLabels` namespace) and have
every renderer/use-case reference it instead of hardcoding literals. Start with the quantities
that already agree on unit and value across all their duplicate sites (Rxx, Rxy, R¹ω/R³ω/R_AHE
family, T (K), Device angle (deg), V (V)) — these are zero-risk renames since the string content
doesn't change, only where it's defined. Explicitly resolve the `math:`-prefixed vs plain-text
duplication between `ThreeOmegaPlotRenderer.swift` and `ThreeOmegaWorkspaceStore+ManifestCache.swift`
by making the manifest path reference the renderer's constants (as it already correctly does for
the two Scaling Law labels).

**Phase 2 — centralize magnetic field display policy.**
Design (not yet implement) the μ₀H (T)/(mT) magnitude-based switch. Coercive field (Hc) is
**confirmed (2026-07-03)** to adopt the same magnitude-based μ₀Hc (T)/(mT) policy as H-field — see
§5 item 7 — rather than remaining a separate Oe-only case; Hc has no existing T conversion today,
unlike H-field which already has three independent Oe→T implementations that should first be
collapsed to one. Also resolve whether `AHEAxisDetector.semanticXField`/`semanticYField` (used as
lookup keys, not just labels) can be safely renamed under this policy.

> **v5.5.6 update:** implemented with a **fixed per-quantity unit** instead of the magnitude-based
> switch this phase proposed — H always displays in T, Hc always in mT (see
> PLOT_DISPLAY_SPEC.md §3). The magnitude-based T/mT auto-switch remains unimplemented; revisit
> only if a future product decision needs it. `AHEAxisDetector.semanticXField`/`semanticYField`
> were **not** renamed — the key/label coupling question this phase raised is still open, see
> [AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md).

**Phase 3 — centralize remaining SI unit display policies.**
Bring σxx, current/voltage, and any other SI-native quantities under the same centralized display
module. Scaling Law stays permanently excluded (long-term-only or never, per product direction),
its labels/conversions untouched.

**Phase 4 — add tests preventing hardcoded label regression.**
Add a lint-style test that fails if a new axis/legend/title string literal containing a known unit
suffix (e.g. `(Ω)`, `(T)`, `(K)`, `(Oe)`, `(S/m)`) is introduced outside the centralized label
module. Add a golden-output test asserting Scaling Law's two axis label strings and its three
conversion factors are byte-for-byte unchanged, so the special case is enforced mechanically, not
just by convention.

---

## 7. Proposed canonical standard draft (not implemented)

| Quantity | Proposed canonical label |
|---|---|
| External magnetic field | `μ₀H (T)` if max\|μ₀H\| ≥ 0.1 T, else `μ₀H (mT)` — **v5.5.6: implemented as a fixed `μ₀H (T)`** (no magnitude switch), see PLOT_DISPLAY_SPEC.md §3 |
| Coercive field | `μ₀Hc (T)` / `μ₀Hc (mT)`, same range rule — **confirmed 2026-07-03** (transform `×1e-4` T / `×0.1` mT from raw Oe); today Hc has no T conversion at all, so this is a bigger implementation change than the H-field case — **v5.5.6: implemented as a fixed `μ₀Hc (mT)`** (no magnitude switch), see PLOT_DISPLAY_SPEC.md §3 |
| Temperature | `Temperature (K)` |
| Device angle | `Ψ (deg)` — **confirmed 2026-07-03, implemented** as the `deviceAngle` identity's canonical label; XY Rotation's `φ` is a separate identity — **implemented label is `φ (deg)`**, not the `Angle offset (deg)` this draft had suggested; not an alias of `Ψ` |
| Resistance | `R (Ω)`, `R¹ω (Ω)`, `R³ω (Ω)`, `R_AHE¹ω (Ω)`, `R_AHE³ω (Ω)`, `Rxx (Ω)`, `Rxy (Ω)`, `R_H (Ω)` |
| Conductivity | `σxx (S/m)` (already matches current display) |
| Current | `Current (mA)`, peak/RMS as sub-label or series metadata |
| Voltage | `V (V)` (already matches) |
| Scaling Law (x, y) | **unchanged** — `σ_{xx}^{2} × 10^{7} (S² cm⁻²)`, `E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm³·V⁻²)` |

All entries above are proposed starting points for design discussion, not decisions.

---

## 8. Test recommendations (not written)

- Golden-string test asserting all 23 `ThreeOmegaPlotRenderer` label constants (lines 16-39)
  match expected values — catches accidental edits during the Phase 1 refactor.
- Golden-string test specifically isolating the two Scaling Law labels and three conversion
  factors (`1e-11`, `1e20`, `1e31`) as an explicit "do not change" regression guard.
- Cross-file consistency test comparing `ThreeOmegaPlotRenderer`'s R¹ω/R³ω/R_AHE¹ω/R_AHE³ω
  constants against the plain-text literals in `ThreeOmegaWorkspaceStore+ManifestCache.swift` —
  fails today would be informative (documents current drift risk) and should pass once Phase 1
  makes the manifest path reference the shared constants.
- Static/lint test scanning `Sources/SpinLabApp` for string literals matching a unit-suffix
  pattern (`\(T\)`, `\(Oe\)`, `\(K\)`, `\(Ω\)`, `\(mT\)`, `\(S/m\)`, `\(deg\)`) outside an
  allow-listed set of files (the centralized label module) — prevents new hardcoded labels
  after Phase 1.
- Snapshot/characterization test on Oe→T conversion output (values, not just labels) for the
  three independent implementations found in §4 (#1-3), to confirm they're numerically identical
  before consolidating them into one function in Phase 2.
