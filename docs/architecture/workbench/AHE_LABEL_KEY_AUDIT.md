# AHE Label / Data-Key Coupling Audit (pre-migration, audit-only)

Status: **audit only — no production behavior, schema changes made**. Its recommended Phase A
tests (§6) have since been added; the axis-label migration itself (Phase B) has not been
executed — see the status note below.
Scope: AHE workflow plot labels, metric keys, pack/restore contracts, chart-identity hashing.
Branch: v5.5.6.

> **Status update (v5.5.6).** During the magnetic-field display-policy migration
> (see [PLOT_DISPLAY_SPEC.md](PLOT_DISPLAY_SPEC.md) §3), this audit's **Phase A** recommendation
> (§6) was implemented: `V556AHELabelKeyBoundaryRegressionTests.swift` now locks down
> `AHEAxisDetector.semanticXField`/`.semanticYField` as literal `"H (T)"`/`"R_H (Ω)"`, asserts the
> persisted metric keys `"Hc"`/`"R_AHE"` remain unchanged across a real analysis run, and asserts
> the display strings are textually distinct from the persisted keys. **Phase B (the axis-label
> migration to route through the vocabulary) has not been executed** — AHE's field label is
> deliberately still `"H (T)"`, not `"μ₀H (T)"`, and is out of scope until this audit's
> key/label-coupling question (§3–4) is resolved. Phase C/D remain unstarted.
>
> **Follow-up audit (v5.5.6, second pass).** Re-verified every file:line citation below against
> current source — all still accurate, no drift. Added one more regression test,
> `magneticFieldLabelDoesNotAlterAHEKeys`, proving
> `WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, unit: .millitesla)` (the
> 3ω-only future-target function) produces a string (`"μ₀Hc (mT)"`) that stays textually distinct
> from AHE's persisted `"Hc"`/`"R_AHE"` keys and from AHE's current display label — closing the
> one specific test gap this pass was asked to confirm. No production code changed; conclusions
> unchanged.
>
> **Decoupling infrastructure (v5.5.6, third pass).** Implemented the naming/typing separation
> this audit recommended, with zero visible-label or persisted-value changes:
> - `AHEAxisDetector.semanticXField`/`.semanticYField` renamed to `.displayXField`/`.displayYField`
>   — same values (`"H (T)"`/`"R_H (Ω)"`), sourced from the vocabulary exactly as before. The old
>   names implied a semantic/lookup role they never actually had; the new names make explicit that
>   these are display-only text, per §3.
> - Added `AHEDataFieldKey` enum (`AHEAxisDetector.swift`): `.hc = "Hc"`, `.rAHE = "R_AHE"`.
>   `AHEWorkspaceStore.buildActiveChartMetrics()` now constructs `PendingMetricEntry.metric` from
>   `AHEDataFieldKey.hc.rawValue`/`.rAHE.rawValue` instead of inline string literals — same
>   persisted values, now with a single named source of truth for the persisted-key role.
> - No change to `AHEAxisDetector`'s actual raw-column lookup functions
>   (`rawMagneticFieldColumn`, `yColumnName`, `pairedValues`) — they already took independent raw
>   PPMS column-name strings, never the display fields. A new test
>   (`rawColumnLookupsAreIndependentOfDisplayVocabulary`) makes this explicit.
> - Phase B (routing the axis-label *values* through `.externalMagneticField`/`.coerciveField`
>   unit-aware display, e.g. `"μ₀H (T)"`) remains **not started** — this pass only decoupled the
>   naming/typing, it did not touch what is displayed.

Purpose: determine which AHE hardcoded strings are safe display-label migration
candidates for `WorkbenchPlotDisplayVocabulary` (the standard already applied to 3ω, RT,
XY Rotation, and IV), and which strings are load-bearing data/identity keys that must not
be touched until a key/label separation is designed. This document does not implement
anything.

---

## 1. Summary

AHE is structurally simpler than the four already-migrated workflows: one tab, one fixed
axis pair (`H (T)` vs `R_H (Ω)`), no per-condition or per-basis branching. All four
`WorkbenchAxisMapping` construction sites already reference a single shared source of
truth — `AHEAxisDetector.displayXField` / `.displayYField` — rather than duplicating
literals per call site (unlike the pre-migration state of 3ω, RT, XY Rotation, and IV).
This makes the *display-label* part of an AHE migration mechanically the easiest of the
five workflows.

The coupling risk the task anticipated is real, but narrower than the axis labels
themselves:

- `AHEAxisDetector.displayXField` (`"H (T)"`) and `.displayYField` (`"R_H (Ω)"`) are
  **display-only** at their point of use (`WorkbenchAxisMapping.xField`/`yField`), and are
  exact byte-for-byte matches to `WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, ...)`
  and `.label(for: .hallResistance, ...)`. They are safe migration candidates.
- However, `axisMapping.xField`/`yField` values are folded into
  `WorkbenchArtifactIdentity`'s chart-identity hash (`WorkbenchArtifactIdentity.swift:53,67-69`),
  which drives library save/overwrite dedup matching. A migration is only safe if it is
  **byte-identical**, which it is here (see §3) — this is a real constraint, not a blocker.
- Separately, AHE persists two **metric identity keys**, `"Hc"` and `"R_AHE"`
  (`AHEWorkspaceStore.swift:421,439`), into the per-sample metric ledger
  (`WorkbenchMetricIdentity.makeIdentityKey`). These are not axis labels — they are
  independent semantic-key strings that happen to describe the same physical quantities.
  `"R_AHE"` has **no exact textual match** to the vocabulary's `raheCombined` case
  (`"math:R_{AHE} (Ω)"` — different markup, different unit suffix). These must **not** be
  migrated or reworded; doing so would silently break persisted per-sample metric identity
  for every existing library entry.
- `AHEPackContracts.swift` has a one-way decode guard that rejects packs written by a
  retired axis-override mechanism, referencing `"H (T)"` / `"R_H (Ω)"` only in a
  human-readable error string (not schema) — safe to reword freely, out of scope for this
  audit's go/no-go decision.
- Raw PPMS column names (`"Magnetic Field (Oe)"`, `"Bridge N Resistance/Resistivity (Ohms)"`)
  are file-format parsing keys, unrelated to display labels, out of scope entirely.

**Go/no-go conclusion**: axis-label migration (§3, item 1) is a **go**, mechanically
identical in shape to the RT migration (single shared constant, single vocabulary call
per side). Everything else touching an "AHE"-adjacent string — metric keys, workflowID,
series-role keys, raw column names — is a **no-go** for this phase.

---

## 2. Inventory table

| # | String | Location | Classification |
|---|---|---|---|
| 1 | `"H (T)"` | `AHEAxisDetector.swift:5` (`displayXField`) | display-only label |
| 2 | `"R_H (Ω)"` | `AHEAxisDetector.swift:6` (`displayYField`) | display-only label |
| 3 | `"Magnetic Field (Oe)"` | `AHEAxisDetector.swift:7` (`rawMagneticFieldColumn`) | data lookup key (raw PPMS column name) |
| 4 | `"Bridge \(n) Resistance (Ohms)"` / `"Bridge \(n) Resistivity"` | `AHEAxisDetector.swift:22,24` | data lookup key (raw PPMS column name) |
| 5 | `"Hc"` | `AHEWorkspaceStore.swift:421` (`PendingMetricEntry.metric`) | saved/restore semantic-key (persisted metric identity) |
| 6 | `"R_AHE"` | `AHEWorkspaceStore.swift:439` (`PendingMetricEntry.metric`) | saved/restore semantic-key (persisted metric identity) |
| 7 | `"T"`, `"Ω"` (`canonicalUnit`) | `AHEWorkspaceStore.swift:422,440` | saved/restore semantic-key (persisted unit tag, paired with #5/#6) |
| 8 | `"AHE"` (`workflowID` / `workflowDisplayName` default) | `BuildAHEPlotPayloadUseCase.swift:7-8` | semantic/identity key (feeds chart + metric identity, not a label) |
| 9 | `"channel-\(bridgeIndex)"` (`seriesRole`) | `IngestAHESelectionsUseCase.swift:114` | semantic quantity key (feeds `WorkbenchSeriesIdentityMetadata.seriesIdentityKey`) |
| 10 | Deprecated-pack decode error text mentioning `"H (T) vs R_H (Ω)"` | `AHEPackContracts.swift:49` | export/diagnostic text only — not schema, not a key |
| 11 | `"H"` / `"R"` test-fixture column names | `V413AHEMultiSeriesExtractionTests.swift:162` | test-only data lookup key, already decoupled from display labels |

Four `WorkbenchAxisMapping` construction sites all reference items #1/#2 via the shared
constants, not independent literals:

- `AHEAxisDetector.swift:11-15` (`defaultAxisMapping()`)
- `BuildAHEPlotPayloadUseCase.swift:16-19`
- `IngestAHESelectionsUseCase.swift:11-14` (empty-selection early return)
- `AHEWorkspaceStore.swift:669-672` (`buildRunTrace()`)

---

## 3. Safe display-only candidates

| Candidate | Current value | Vocabulary target | Exact match? |
|---|---|---|---|
| `AHEAxisDetector.displayXField` | `"H (T)"` | `WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText)` → `"H (T)"` | Yes |
| `AHEAxisDetector.displayYField` | `"R_H (Ω)"` | `WorkbenchPlotDisplayVocabulary.label(for: .hallResistance, context: .manifestPlainText)` → `"R_H (Ω)"` | Yes |

Because both constants are already the single source of truth referenced by all four
construction sites (§2), migrating them requires editing exactly two lines in
`AHEAxisDetector.swift`, with zero call-site changes elsewhere — the smallest-blast-radius
migration of the five workflows. Chart-identity hashing (§1) is unaffected because the
resulting strings are byte-identical before and after.

Not currently used anywhere in AHE code: `.rahe1omega`, `.rahe3omega`, `.raheCombined`,
`.rxx`, `.rxy`, `.sigmaXX`, `.scalingLawX`, `.scalingLawY`, `.temperatureDependenceERatio`.
These vocabulary cases exist for the 3ω workflow's RAHE-vs-device and Scaling Law tabs
(already migrated), not for AHE itself — AHE has no Rxx/Rxy/scaling-law tab of its own.

---

## 4. Blocked key-coupled candidates

| String | Why blocked |
|---|---|
| `"Hc"`, `"R_AHE"` (`AHEWorkspaceStore.swift:421,439`) | Persisted per-sample metric-identity keys (`WorkbenchMetricIdentity.makeIdentityKey`). Not display labels — renaming or rerouting through the vocabulary would change identity for every already-saved library metric entry. `"R_AHE"` also has no exact vocabulary match (`raheCombined` renders `"math:R_{AHE} (Ω)"`), so even a same-meaning substitution would silently change stored data. |
| `"T"`, `"Ω"` canonical units (`AHEWorkspaceStore.swift:422,440`) | Paired with the metric keys above as part of the same persisted record; same risk. |
| `"AHE"` workflowID/displayName default (`BuildAHEPlotPayloadUseCase.swift:7-8`) | Feeds chart-identity and metric-identity hashing, not a display label. |
| `"channel-\(bridgeIndex)"` seriesRole (`IngestAHESelectionsUseCase.swift:114`) | Feeds `WorkbenchSeriesIdentityMetadata.seriesIdentityKey`, a persisted per-series identity string, not a label. |
| `"Magnetic Field (Oe)"`, `"Bridge N Resistance/Resistivity (Ohms)"` (`AHEAxisDetector.swift:7,22,24`) | Raw PPMS input-file column names — data lookup keys, unrelated to display labels; migrating these would break file parsing, not just cosmetics. |
| Deprecated-pack decode error text (`AHEPackContracts.swift:49`) | Not schema-bearing, but also not a genuine display-label migration target — it's a one-off diagnostic string; leave it alone rather than couple it to the vocabulary for no behavioral benefit. |

---

## 5. Tests currently covering AHE labels/keys

| File | What it protects |
|---|---|
| `V321AHEIngestionAxisDetectionTests.swift` | **Primary literal axis-label assertions**: `defaultAxisMapping.xField == "H (T)"` (line 52), `.yField == "R_H (\u{03A9})"` (lines 67, 203). Must stay green through any future migration — this is the regression net for §3. |
| `Stage4BAHEManifestTitleCharacterizationTests.swift` | Manifest title stays template-based and does not leak label overrides; already references `AHEAxisDetector` constants directly rather than duplicating literals — good precedent for the migration. |
| `AHECopyPNGTests.swift` | PNG export rendering; fixture uses `"R_AHE (Ω)"` as a test-local yField value (not `AHEAxisDetector.displayYField`) — a pre-existing test-fixture naming quirk, not a production coupling risk, but worth noting so a future migration doesn't confuse this fixture string with the real metric key `"R_AHE"` (§4). |
| `V413AHEMultiSeriesExtractionTests.swift` | Hc/R_AHE numeric extraction correctness; uses decoupled `"H"`/`"R"` column fixtures, unrelated to display labels. |
| `V5111ExtractAHEMetricsUseCaseTests.swift`, `V5114AHEMetricSourceTests.swift` | Numeric extraction/provenance of Hc and R_AHE metric values — not label assertions, but adjacent to the blocked metric-key strings in §4. |
| `V331AHEWorkspaceViewExtractionTests.swift` | View-extraction smoke test, no label assertions. |
| `V333AHEWorkspaceStoreIsolationTests.swift` | State isolation from other workflow stores, no label assertions. |
| `V537AHESearchSnapshotConsumptionTests.swift` | Search-snapshot consumption correctness, no label assertions. |

`V556AHELabelKeyBoundaryRegressionTests.swift` also includes
`magneticFieldLabelDoesNotAlterAHEKeys`, which asserts
`WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, unit: .millitesla)` and
`.magneticFieldLabel(for: .externalMagneticField, unit: .tesla)` — the functions backing 3ω's
already-migrated μ₀H/μ₀Hc labels — produce strings that stay textually distinct from AHE's
persisted `"Hc"`/`"R_AHE"` keys and from `AHEAxisDetector.displayXField`. This guards against a
future edit to `magneticFieldLabel` silently changing AHE's behavior through shared vocabulary
code, even though AHE does not call that function today.

No existing test currently asserts on the persisted `"Hc"`/`"R_AHE"` metric-key strings
literally by name across a save/restore round trip — a gap worth closing in Phase A below,
before any future work near those keys.

---

## 6. Recommended migration plan

- **Phase A — AHE-specific tests only. Done (v5.5.6).** Added a regression test locking down
  `AHEAxisDetector.semanticXField`/`.semanticYField` literal values (mirroring
  `V5119RTLabelMigrationRegressionTests.swift`), and a second test asserting the persisted
  metric-key strings `"Hc"`/`"R_AHE"` remain literally unchanged across a real analysis run
  (closing the gap noted in §5). See `V556AHELabelKeyBoundaryRegressionTests.swift`. No
  production code changed.
- **Phase B — migrate the two safe display-only labels. Not started.** Replace
  `AHEAxisDetector.semanticXField`/`.semanticYField` with
  `WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText)`
  and `.label(for: .hallResistance, context: .manifestPlainText)`, exactly as the RT and IV
  migrations replaced their single shared axis-label constants. Verify Phase A tests plus
  `V321AHEIngestionAxisDetectionTests.swift` stay green, and confirm chart-identity hash
  output is byte-identical (§1, §3).
- **Phase C — split key/display where needed.** Not required for the axis labels
  themselves (already display-only, §3), but recommended for the metric-key pair: introduce
  a stable internal quantity identity (e.g. an enum case) distinct from the persisted
  string key `"Hc"`/`"R_AHE"`, so a future rename of the *displayed* metric name (if ever
  requested) does not require a migration of *persisted* data. This phase is optional and
  should only be scoped if/when there is an actual product need to change how Hc/R_AHE are
  displayed in the library UI.
- **Phase D — future target labels/units.** No AHE-specific future-target relabeling has
  been proposed to date (unlike, e.g., deviceAngle → Ψ for 3ω/XY). Revisit only if a future
  product decision changes the AHE axis or metric display convention.

---

## 7. Non-goals

- This audit does not migrate, rename, or restructure any AHE code, test, or schema.
- This audit does not touch the `"Hc"`/`"R_AHE"` metric-identity keys, the `"AHE"`
  workflowID/displayName, the `channel-N` seriesRole key, or raw PPMS column names — all
  remain out of scope pending a dedicated key/label separation decision (Phase C).
- This audit does not migrate the deprecated-pack decode error text in
  `AHEPackContracts.swift` — it is not schema-bearing and not a genuine display-label
  migration target.
- This audit does not evaluate or propose new future-target display labels for AHE (no
  equivalent of the deviceAngle → Ψ decision exists for AHE today).
