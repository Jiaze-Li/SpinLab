# Magnetic Field Canonical Storage Unit Audit (audit-only)

Status: **audit only — no schema, storage, or display changes made**. This document maps where
magnetic-field-related values (external field H, coercive field Hc) are *stored* — in-memory
analysis results, saved packs, sample-library entries, and manual overrides — as distinct from
where they are *displayed*. Display-unit architecture is already implemented and documented
separately; see [PLOT_DISPLAY_SPEC.md](PLOT_DISPLAY_SPEC.md) and
[AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md). Both confirm display conversions happen only at
payload-construction time and never mutate stored data — this document verifies that claim from
the storage side and catalogs exactly what a future canonical-storage migration would touch.

Branch: v5.5.6.

---

## 1. Summary

- **3ω and AHE already disagree on canonical storage unit today.** 3ω stores raw field values in
  Oe, unconverted, all the way into the saved pack. AHE converts Oe → Tesla once, at ingestion,
  before anything is stored — its pack, extracted metrics, and library entries are already Tesla
  end-to-end.
- **AHE needs no numeric migration.** Its only migration-shaped risk is the persisted metric key
  names `"Hc"` / `"R_AHE"` (identity strings, not units) — already flagged as protected in
  `PLOT_DISPLAY_SPEC.md` §7 and out of scope here.
- **3ω is the actual migration target.** `ThreeOmegaFieldSweepResult.hField` / `.hc1omega` /
  `.hc3omega` are Oe, persisted verbatim (no custom `Codable` transform) inside every existing
  `.spinlabpack` file. A naive in-place conversion to Tesla would silently corrupt the physical
  magnitude of every historical 3ω pack on next load (factor of `1e4` for H, effectively `1e-1`
  mismatch if compared against Hc's mT display).
- **No standalone CSV export path exists** for these quantities. The only export/persistence
  surfaces are the pack files themselves and AHE's library JSON metric manifest.

---

## 2. Field-by-field table

| # | Field | File:Line | Classification | Unit stored | Notes |
|---|---|---|---|---|---|
| 1 | Raw field column (`file.col0`) | `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift:24` | raw instrument Oe | Oe | PPMS raw column, no conversion at parse time. Transient — not itself persisted, but everything downstream (#2-4) inherits Oe from here. |
| 2 | `ThreeOmegaFieldSweepResult.hField: [Double]` | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift:24` (comment-annotated `// Oe`) | saved pack Oe | Oe | Persisted verbatim in `ThreeOmegaPackResult.ingestionResult.fieldSweeps`; no custom decode-time unit converter exists. |
| 3 | `ThreeOmegaFieldSweepResult.hc1omega: Double?` | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift:39` (`// Oe`) | saved pack Oe | Oe | Same struct/risk as #2. |
| 4 | `ThreeOmegaFieldSweepResult.hc3omega: Double?` | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift:40` (`// Oe`) | saved pack Oe | Oe | Same struct/risk as #2. |
| 5 | `ThreeOmegaWorkspaceStore+ManifestCache.swift` H/Hc conversions | `ThreeOmegaWorkspaceStore+ManifestCache.swift:25,133,154,194` | internal analysis T/mT (derived, not stored) | Recomputed from #2-4's Oe on every manifest rebuild via `WorkbenchMagneticFieldUnitConverter` | No persistence — reads Oe as canonical every time. No migration risk in itself. |
| 6 | `ThreeOmegaPlotRenderer` H/Hc payload conversions | `ThreeOmegaPlotRenderer.swift:404,418,572,578,580` | display-only T/mT | Converted at payload construction only | Ephemeral, per `PLOT_DISPLAY_SPEC.md` §3. |
| 7 | 3ω run-trace provenance `xField: "H (Oe)"` | `ThreeOmegaWorkspaceStore+Plotting.swift:289` | provenance label, no numeric value | n/a (text label) | Out of scope per `PLOT_DISPLAY_SPEC.md` §8; not a stored magnitude. |
| 8 | `IngestAHESelectionsUseCase` Oe→T conversion | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift:75` (`let xs = rawXs.map { $0 * 1e-4 }`) | conversion boundary: raw Oe → internal/saved T | Converts Oe→T immediately at ingestion | This is AHE's single unit-conversion point. Everything downstream is Tesla. |
| 9 | `AHEIngestionResult.series[].x` | `Sources/SpinLabApp/Workbench/V3/AHEIngestionContracts.swift:44`; series struct `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift:15-17` | saved pack T | Tesla | Already canonical — encoded/decoded verbatim, no transform needed. Persisted via `AHEPackResult.ingestionResult`. |
| 10 | `ExtractAHEMetricsUseCase` Hc extraction | `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift:32-88` (Hc computed ~53-70) | internal analysis T | Tesla | Derived purely from already-Tesla `series.x` (#9). No unit ambiguity. |
| 11 | `AHEWorkspaceStore` `PendingMetricEntry` for `"Hc"` | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift:428-430` (`canonicalUnit: "T"`) | saved library metric, T (key-protected) | Tesla | Unit is already correct; the `"Hc"` key name itself is protected identity (see `PLOT_DISPLAY_SPEC.md` §7) — do not touch regardless of unit work. |
| 12 | `AHEWorkspaceStore` `PendingMetricEntry` for `"R_AHE"` | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift:446-448` (`canonicalUnit: "Ω"`) | saved library metric, Ω (not a field) | Ω | Not magnetic-field; included for completeness, same protected-key caveat. |
| 13 | AHE "Corrected Hc" manual override input | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift:154`; write path `AHEWorkspaceStore.swift` `updateHcCandidate` (~237-243) | user input T | Tesla | User types Tesla directly; value flows unconverted into `pendingMetricOverride` → `PendingMetricEntry.value` (`canonicalUnit: "T"`). No conversion boundary exists here — already Tesla end-to-end. |
| 14 | `AHEPackResult.ingestionResult` | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift:71-83` | saved pack T (wrapper) | Tesla (inherits #9) | Actual Codable container written to disk for AHE packs. Already canonical. |
| 15 | `ThreeOmegaPackResult.ingestionResult.fieldSweeps` | `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift:97-100`; struct `Sources/SpinLabApp/Workbench/Domain/ThreeOmegaIngestionDomain.swift:90-91` | saved pack Oe (wrapper) | Oe (inherits #2-4) | **Highest-risk migration target** — see §4. |
| 16 | AHEPackContracts deprecated-decode error text | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift:49` | diagnostic text only | n/a | Not schema-bearing; mentions `"H (T)"` in a human-readable error string only. |

---

## 3. Recommended canonical storage unit

**Tesla (T)**, matching AHE's existing behavior, for the following reasons:

- AHE already stores Tesla end-to-end (ingestion series, extracted Hc, library metric, manual
  override) — adopting T as canonical means AHE requires **zero storage changes**.
- 3ω is the only workflow storing Oe today, and it stores Oe **only because no conversion was ever
  added at ingestion** (`ThreeOmegaFitUseCase.swift:24` reads the raw PPMS column directly into
  `hField` with a comment noting the unit, not a deliberate Oe-forever design decision).
- T is also the unit both workflows already converge on for **display** (`PLOT_DISPLAY_SPEC.md`
  §3), so a Tesla canonical-storage decision aligns storage and display units for the first time,
  removing the need for `WorkbenchMagneticFieldUnitConverter` to run on every render.

---

## 4. Compatibility / migration requirements

A future migration to Tesla-canonical storage would need, at minimum:

1. **A pack schema version bump for 3ω packs.** `ThreeOmegaFieldSweepResult` has no custom
   `Codable` encode/decode — `hField`/`hc1omega`/`hc3omega` decode as raw `Double`/`[Double]` with
   no unit tag anywhere in the struct. There is no way to distinguish an old (Oe) pack from a new
   (T) pack by inspecting the decoded value alone; the version/format marker must be added
   explicitly before any numeric change, or old packs will silently decode as if already in Tesla
   (a ~1e4x magnitude error for H, ~10x for Hc).
2. **A one-time decode-side converter** (or a new field name with the old Oe field retained
   read-only for legacy decode) so that packs written before the migration continue to load with
   correct physical magnitudes.
3. **No AHE-side schema change required** — AHE's pack (`AHEPackResult.ingestionResult`) is
   already Tesla; only 3ω's pack contracts need touching.
4. **Manifest-cache and renderer conversion call sites** (`ThreeOmegaWorkspaceStore+ManifestCache.swift`,
   `ThreeOmegaPlotRenderer.swift`) that currently do Oe→T/mT conversion at read time would need
   their conversion removed (input would already be Tesla), not just re-pointed — leaving the
   conversion in place after storage becomes Tesla would double-convert.
5. **Regression coverage before touching anything**: a golden-value test loading a *real, current*
   `.spinlabpack` fixture and asserting its decoded `hField`/`hc1omega`/`hc3omega` values match
   today's Oe magnitudes exactly, so any future migration has a concrete "before" baseline to diff
   against.

---

## 5. No-go / breakage list (would corrupt old packs if converted carelessly)

| Field | Why it's no-go without a version/converter |
|---|---|
| `ThreeOmegaFieldSweepResult.hField` | No unit tag in the struct; existing packs are Oe. In-place Tesla conversion breaks every historical 3ω pack's field-axis magnitude by ~1e4x on next load. |
| `ThreeOmegaFieldSweepResult.hc1omega` / `.hc3omega` | Same struct, same risk — no unit tag, existing packs are Oe. |
| AHE persisted metric keys `"Hc"` / `"R_AHE"` | Not a unit problem (already Tesla/Ohm) but the **key names** are protected identity strings per `PLOT_DISPLAY_SPEC.md` §7 — do not rename or re-key even while doing unit-canonicalization work elsewhere. |

Fields **not** on this list (already Tesla, safe as-is, no migration action needed): AHE
`ingestionResult.series[].x`, AHE extracted Hc, AHE library `"Hc"` metric value, AHE manual Hc
override input/storage.

---

## 6. Forbidden-by-task items confirmed untouched

Per task scope, this audit made no code changes. Confirmed as of this audit:

- No pack/schema field was renamed, retyped, or given a version bump.
- No saved/persisted value was converted.
- No display label was changed (`"H (T)"`, `"μ₀H (T)"`, `"μ₀Hc (mT)"`, etc. are all unmodified).
- AHE keys `"Hc"` / `"R_AHE"` are unmodified and remain exactly as documented in
  `PLOT_DISPLAY_SPEC.md` §7.

---

## 7. Non-goals of this document

- Does not implement Tesla-canonical storage — recommendation only (§3).
- Does not design the pack schema version/converter mechanics beyond naming the requirement (§4).
- Does not propose new display labels or touch the display architecture already recorded in
  `PLOT_DISPLAY_SPEC.md` / `AHE_LABEL_KEY_AUDIT.md`.
