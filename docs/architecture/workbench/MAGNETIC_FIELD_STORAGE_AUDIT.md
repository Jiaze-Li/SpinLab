# Magnetic Field Canonical Storage Unit Audit

Status: **implemented — Tesla is the canonical internal/storage unit for both 3ω and AHE**. This
document originated as a v5.5.6 audit-only survey of where magnetic-field-related values (external
field H, coercive field Hc) are *stored* — in-memory analysis results, saved packs,
sample-library entries, and manual overrides — as distinct from where they are *displayed*.
Display-unit architecture is documented separately; see [PLOT_DISPLAY_SPEC.md](PLOT_DISPLAY_SPEC.md)
and [AHE_LABEL_KEY_AUDIT.md](AHE_LABEL_KEY_AUDIT.md). Both confirm display conversions happen only
at payload-construction time and never mutate stored data. Since the original v5.5.6 audit, 3ω was
migrated to match AHE's Tesla-canonical behavior (see §4); this document now records the resulting
invariant plus the original audit's findings as historical baseline.

Original audit branch: v5.5.6. Migration landed subsequently (`ThreeOmegaIngestionDomain.swift`
`magneticFieldStorageUnit` marker + `ThreeOmegaFitUseCase.swift` ingestion-boundary conversion).

---

## 1. Current invariant (verify against `HEAD` before relying on this section)

- **Raw instrument/LVM input may be Oe.** The PPMS raw field column is still read as Oe.
- **The 3ω ingestion boundary converts Oe → Tesla.** `ThreeOmegaFitUseCase.swift` converts
  `file.col0` via `WorkbenchMagneticFieldUnitConverter.convert(_:from: .oersted, to: .tesla)`
  immediately at ingestion — no Oe value flows into `ThreeOmegaFieldSweepResult` from this path.
- **Runtime `H`, fitting, and derived `Hc` are Tesla.** `ThreeOmegaFieldSweepResult.hField` /
  `.hc1omega` / `.hc3omega` are documented as Tesla ("canonical internal unit as of the Oe→Tesla
  migration") and are computed from the already-Tesla `H`, matching AHE's existing behavior
  end-to-end (ingestion series, extracted Hc, library metric, manual override).
- **New persistence/pack storage is Tesla.** `ThreeOmegaIngestionDomain.swift` adds an explicit
  `magneticFieldStorageUnit` marker (`teslaStorageUnit = "T"`, the default for new writes) plus a
  `normalizedForPackSave()` defensive no-op backstop called from `ThreeOmegaWorkspaceStore+Pack.swift`
  before every pack write.
- **Legacy Oe packs normalize only on restore/load, never on save.** `normalizedToInternalTesla()`
  converts only when the decoded marker is `"Oe"` (defaulted for packs written before the marker
  existed), invoked at both 3ω pack-restore call sites in `ThreeOmegaWorkspaceStore+Pack.swift`.
- **AHE needs no numeric migration** — it was already Tesla end-to-end before this migration. Its
  only migration-shaped risk is the persisted metric key names `"Hc"` / `"R_AHE"` (identity
  strings, not units) — protected per `PLOT_DISPLAY_SPEC.md` §7 and out of scope here.
- **Conversion factor**: Oe → T is `oe * 1e-4` (`MagneticFieldUnit.swift`), applied identically by
  3ω's ingestion boundary and AHE's `IngestAHESelectionsUseCase.swift`. There is exactly one
  conversion boundary per workflow; no double-conversion exists anywhere in the render/manifest
  paths (those consume already-Tesla values).

If a future `HEAD` no longer matches every bullet above, correct this section (and the canonical
task-board debt record, if one references it) rather than trusting this snapshot.

---

## 2. Field-by-field table (original v5.5.6 audit baseline, annotated with post-migration state)

| # | Field | File:Line (v5.5.6) | Unit at v5.5.6 audit | Unit as of migration | Notes |
|---|---|---|---|---|---|
| 1 | Raw field column (`file.col0`) | `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift:24` | Oe | Oe (unchanged — still the raw instrument boundary) | PPMS raw column; converted to Tesla immediately after this read, at ingestion. |
| 2 | `ThreeOmegaFieldSweepResult.hField: [Double]` | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift:24` | Oe (saved pack) | **Tesla** | Now documented as canonical-Tesla; conversion happens upstream at ingestion, not via a struct-level transform. |
| 3 | `ThreeOmegaFieldSweepResult.hc1omega: Double?` | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift:39` | Oe (saved pack) | **Tesla** | Same as #2. |
| 4 | `ThreeOmegaFieldSweepResult.hc3omega: Double?` | `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift:40` | Oe (saved pack) | **Tesla** | Same as #2. |
| 5 | `ThreeOmegaWorkspaceStore+ManifestCache.swift` H/Hc conversions | `ThreeOmegaWorkspaceStore+ManifestCache.swift:25,133,154,194` | Oe→T/mT derived, not stored | Sources already-Tesla values (`from: .tesla`) | No longer a live Oe→T conversion; converts Tesla to display units only. Verify no double-conversion if touched again. |
| 6 | `ThreeOmegaPlotRenderer` H/Hc payload conversions | `ThreeOmegaPlotRenderer.swift:319,466,468` | display-only T/mT | Unchanged — sources Tesla (`from: .tesla`) | Ephemeral, per `PLOT_DISPLAY_SPEC.md` §3. |
| 7 | 3ω run-trace provenance `xField: "H (Oe)"` | `ThreeOmegaWorkspaceStore+Plotting.swift:289` | provenance label, no numeric value | n/a (text label) | Out of scope per `PLOT_DISPLAY_SPEC.md` §8; not a stored magnitude. Label text itself may now be misleading post-migration — worth a separate check if touched. |
| 8 | `IngestAHESelectionsUseCase` Oe→T conversion | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift:75` (bare `* 1e-4` literal at audit time) | conversion boundary | Now routed through `WorkbenchMagneticFieldUnitConverter.convert(...)` (line 77) | Replaced the bare literal with the shared converter in a 2026-08-08 refactor; same factor, now shared code path with 3ω. |
| 9 | `AHEIngestionResult.series[].x` | `Sources/SpinLabApp/Workbench/V3/AHEIngestionContracts.swift:44` | Tesla | Tesla (unchanged) | Already canonical at audit time. |
| 10 | `ExtractAHEMetricsUseCase` Hc extraction | `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift:32-88` | Tesla | Tesla (unchanged) | Derived purely from already-Tesla `series.x`. |
| 11 | `AHEWorkspaceStore` `PendingMetricEntry` for `"Hc"` | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift:428-430` | Tesla (key-protected) | Tesla (unchanged) | Key name protected per `PLOT_DISPLAY_SPEC.md` §7. |
| 12 | `AHEWorkspaceStore` `PendingMetricEntry` for `"R_AHE"` | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift:446-448` | Ω (not a field) | Ω (unchanged) | Not magnetic-field; included for completeness. |
| 13 | AHE "Corrected Hc" manual override input | `AHEWorkspaceView.swift:154`; `AHEWorkspaceStore.swift` `updateHcCandidate` | Tesla | Tesla (unchanged) | User types Tesla directly; unconverted into `pendingMetricOverride`. |
| 14 | `AHEPackResult.ingestionResult` | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift:71-83` | Tesla | Tesla (unchanged) | Already canonical. |
| 15 | `ThreeOmegaPackResult.ingestionResult.fieldSweeps` | `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift:97-100`; struct `ThreeOmegaIngestionDomain.swift:90-91+` | Oe (highest-risk migration target at audit time) | **Tesla**, with `magneticFieldStorageUnit` marker + `normalizedToInternalTesla()` legacy-pack converter | Migration implemented — see §4. |
| 16 | AHEPackContracts deprecated-decode error text | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift:49` | diagnostic text only | n/a | Not schema-bearing. |

---

## 3. Canonical storage unit

**Tesla (T)**, matching AHE's original behavior — now implemented for 3ω as well:

- AHE required zero storage changes (already Tesla end-to-end).
- 3ω's ingestion boundary (`ThreeOmegaFitUseCase.swift`) now converts Oe → Tesla the same way AHE
  does, via the shared `WorkbenchMagneticFieldUnitConverter`.
- T is also the unit both workflows converge on for **display** (`PLOT_DISPLAY_SPEC.md` §3), so
  storage and display units are now aligned for both workflows; manifest-cache/renderer call sites
  consume already-Tesla values instead of converting Oe on every render.

---

## 4. How the migration was implemented (for historical/future-reference purposes)

The original audit (§4 in prior revisions of this document) enumerated requirements for a future
migration. Recording what was actually built, for anyone auditing pack-compatibility behavior:

1. **Pack schema marker, not a version bump.** `ThreeOmegaIngestionDomain.swift` adds a
   `magneticFieldStorageUnit` field (`"T"` default for new writes, `"Oe"` recognized for legacy
   decode, absent-marker packs treated as legacy `"Oe"`). This distinguishes old vs. new packs
   without a structural version bump.
2. **Decode-side converter for legacy packs.** `normalizedToInternalTesla()` converts only when the
   decoded marker is `"Oe"` (or absent), invoked at both 3ω pack-restore call sites in
   `ThreeOmegaWorkspaceStore+Pack.swift`. New-format (`"T"`) packs pass through unconverted.
3. **No AHE-side schema change was needed** — confirmed still true; only 3ω's pack contracts were
   touched.
4. **Manifest-cache and renderer conversion call sites updated** to source `from: .tesla` instead of
   converting Oe on every read (`ThreeOmegaWorkspaceStore+ManifestCache.swift`,
   `ThreeOmegaPlotRenderer.swift`) — converting a value that is already Tesla again would introduce
   a `1e4` magnitude error, so these sites must never be pointed back at a bare Oe-conversion path.
5. **Save path never re-converts.** `normalizedForPackSave()` is a defensive no-op backstop, not an
   active conversion step — an in-memory `ThreeOmegaFieldSweepResult` is Tesla by construction
   (ingested via the boundary in §1), so save-time conversion would double-convert if ever added.

**If re-verifying this invariant**: do not add a second Oe→Tesla conversion anywhere in the 3ω
read/save/render path — the ingestion boundary (§1) is the only place that conversion belongs.

---

## 5. Legacy-pack compatibility (formerly "no-go / breakage list")

| Field | Legacy-pack handling |
|---|---|
| `ThreeOmegaFieldSweepResult.hField` | Packs missing `magneticFieldStorageUnit` (or tagged `"Oe"`) are converted via `normalizedToInternalTesla()` on restore; packs tagged `"T"` pass through unconverted. |
| `ThreeOmegaFieldSweepResult.hc1omega` / `.hc3omega` | Same restore-time handling as `hField`. |
| AHE persisted metric keys `"Hc"` / `"R_AHE"` | Not a unit concern (already Tesla/Ohm); key names remain protected identity strings per `PLOT_DISPLAY_SPEC.md` §7 — unaffected by this migration. |

Regression coverage: `V564ThreeOmegaMagneticFieldStorageUnitTests.swift` and
`V556MagneticFieldUnitConversionTests.swift` cover the conversion factor and legacy-pack restore
behavior (verify these still exist and pass before treating this invariant as current).

---

## 6. Non-goals of this document

- Does not re-derive or re-justify the Tesla-canonical decision beyond §3 — see the original v5.5.6
  audit history in version control for the full comparative analysis.
- Does not document display-label architecture, covered by `PLOT_DISPLAY_SPEC.md` /
  `AHE_LABEL_KEY_AUDIT.md`.
- Lifecycle status (open/resolved/deferred) for any debt this document references belongs solely in
  the canonical task board, not in this file.
