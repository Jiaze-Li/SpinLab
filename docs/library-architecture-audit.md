# Phase 2: Full Library Architecture Audit

Status: **Audit record, not a proposal.** This document reports findings only.
It does not authorize, recommend as urgent, or perform any code change. Per
`docs/experiment-data-contract.md` §10 and the Phase 2 task brief, this audit
must not modify production code, must not implement any Obsidian component,
and must not alter the contract to fit current behavior.

Normative baseline: `docs/experiment-data-contract.md`, in particular §3
(domain model), §4 (identity), §6 (source/index/projection boundaries), §8
(persistence/rebuildability), and §12 (Architecture Invariants 1–16). Every
finding below is checked against those invariants.

---

## 1. Executive Summary

The seven tensions the contract's drafting phase (§13.1–§13.7) flagged as
*candidate* observations are, on full call-chain verification, **all
confirmed as real** — several are more severe than the contract's cautious
phrasing suggested. The single highest-priority finding is **§13.6/Finding
F1**: editing a Sample's metadata from the UI physically writes into a
Registry row shared by every sibling Sample of the same Batch, with **zero**
field-level guard distinguishing Batch-owned from Sample-owned data. This is
a live, reachable data-integrity risk today, independent of any future
Obsidian work.

The second-most consequential finding is that `LibraryIndex` is not, in
practice, "a Registry projection" the way §6.1 of the contract describes it.
On every normal app launch, the *only* index rebuild that runs is a
filesystem walk of `batches/**/batch.json` and `samples/**/sample.json`
(**F2**). The Registry XLSX is read only on an explicit user-triggered
sync/preview action, and its output never touches disk directly — it must be
diffed against the filesystem baseline and explicitly applied before it
becomes part of the persisted index. This does not violate Invariant 4
outright (the filesystem JSON *is* itself reconstructible from the Registry,
transitively, at import time), but it means the persisted `LibraryIndex` is
best described as **"Registry snapshot at last apply, persisted and
independently mutable thereafter,"** not a live Registry projection — the
distinction matters for how an `ObsidianVaultIndex`/Dossier integration
should be designed.

Third, Batch-owned metadata is duplicated verbatim into every Sample with no
type-level scope tag anywhere in the domain model (**F3**, confirms §13.1) —
this is the structural root cause of F1: nothing in the type system
distinguishes "this key belongs to the Batch" from "this key belongs to the
Sample," so the write path has no scope information to guard on even if
someone wanted to add a guard today.

Fourth, sample identity construction has a demonstrated (not merely
theoretical) **drift risk**: the free-text/filename resolution path
(`SampleKeyNormalizer` → `FileRoutingRuleBook`) ignores the `match.type`
(`equals` vs. `contains`) declared in the shared rule JSON and always does
substring containment, while the Registry substrate-cell path
(`LibrarySubstrateParser` → `SampleSemanticDescriptor`) honors it and does
exact matching for `equals` rules (**F4**, confirms and sharpens §13.3). This
means the same rule config can silently produce a different `sampleKey` for
the same conceptual token depending on which import path resolves it.

Fifth, the Web Library's Cloudflare D1 sample-notes store (**F5**, §13.7) is
confirmed to be a genuinely isolated, one-way-clean annotation layer — no
code path anywhere reads it back into SpinLab — so it is *not* a contract
violation today, only a forward-looking design question for whenever
canonical sample notes are defined.

None of these findings required or received a code change. No production
file was modified while producing this report.

## 2. Audit Scope and Method

**Method.** Four parallel read-only research passes traced actual call
chains (not type names or doc comments) across: (a) Registry → Library
persistence and reload lifecycle, (b) all sample-identity construction entry
points, (c) measurement/analysis sidecar persistence and the Sample-edit →
Registry write path, and (d) Web Library export and Cloudflare D1 notes. Each
pass cites concrete `file:line` evidence. This document synthesizes those
four passes against the contract's invariants and the finding taxonomy in
§10 below (A–D).

**Scope covered** (files actually read, not assumed from names):

- `Sources/SpinLabApp/Library/LibraryRegistryParser.swift`
- `Sources/SpinLabApp/Library/LibraryStore+RootAndIndex.swift`,
  `LibraryStore+PathsAndCache.swift`, `LibraryStore+Drawers.swift`,
  `LibraryStore+ChangeLogs.swift`, `LibraryStore+MeasurementSets.swift`,
  `LibraryStore+SidecarEnumeration.swift`
- `Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift`
- `Sources/SpinLabApp/Library/LibraryArtifactLayout.swift`,
  `LibraryPathResolver.swift`
- `Sources/SpinLabApp/Library/LibraryMeasurementDataStore.swift`,
  `LibraryChartIndexStore.swift`
- `Sources/SpinLabApp/Library/LibrarySampleEditService.swift`,
  `LibraryRegistrySyncService.swift`, `LibraryXLSXSyncService.swift`,
  `LibraryDiffEngine.swift`
- `Sources/SpinLabApp/Registry/SampleRegistry.swift`,
  `RegistryLookupRuleBook.swift`
- `Sources/SpinLabApp/App/RegistryFacade.swift`,
  `RegistryCoordinator.swift`, `SpinLabAppState+RoutingPresentation.swift`,
  `SpinLabAppState+LibraryCoordination.swift`
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+SampleEdit.swift`,
  `LibraryFeatureStore+PreviewSync.swift`
- `Sources/SpinLabApp/Import/SampleKeyNormalizer.swift`,
  `FileRoutingRuleBook.swift`, `Import/Rules/FileRoutingSemanticRules.swift`,
  `FilenameRuleSet.swift`
- `Sources/SpinLabApp/Library/SampleSemanticDescriptor.swift`
- `Sources/SpinLabApp/Import/DrawerMatchEngine.swift`
- `Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift`
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift`
- `scripts/export_static_library.py`, `scripts/publish_web_library.sh`,
  `docs/web_library.md`
- `SpinLab-Web-Library` sibling repo: `wrangler.toml`,
  `migrations/0001_sample_notes.sql`, `functions/api/note.js`,
  `Resources/WebLibraryTemplate/app.js`
- `Sources/SpinLabApp/App/RootSplitView.swift`,
  `Sources/SpinLabApp/App/LibraryMutationService.swift`,
  `Sources/SpinLabApp/App/ApplyCoordinator.swift`,
  `Sources/SpinLabApp/App/SpinLabDataActor.swift`

Not separately re-audited beyond the above: pure-visual UI layout code (per
task instruction), and the full Workbench analysis pipeline beyond its
result/manifest persistence and sampleKey-binding behavior.

## 3. Current Domain Model

The type-level model matches the contract's Batch/Sample/Measurement shape
structurally, but **carries no ownership-scope information**:

- `LibraryBatch` (`Library/Domain/LibraryDomainModels.swift:107-117`) and
  `LibrarySample` (`:142-234`) each independently declare their own flat
  `metadata: [String: String]`, `numericTags: [String: Double]`,
  `numericDisplay: [String: String]` dictionaries — same shape, no shared
  value type, no key-scope tag distinguishing "Batch-owned" from
  "Sample-owned."
- Neither `LibraryIndex`, `LibraryBatch`, nor `LibrarySample` carries any
  per-field or per-record provenance/origin tag (no `origin:
  .registry/.filesystem/.userEdit`, no field-level timestamp-of-origin).
  `LibraryIndex.registryInternalPath`/`registrySourcePath` are index-level
  scalars recording "last registry path used," not per-record provenance.
- `LibrarySample.appliedMeasurements` and `LibrarySample.measurementSets` are
  both excluded from `sample.json`'s Codable surface and populated
  post-decode from sidecar scans — but only the former is genuinely
  ephemeral/derived; the latter backs real user-authored data (see F8, §11).

This absence of a scope/provenance tag is the structural root cause behind
F1 and F3 below: the type system gives the write path nothing to guard on.

## 4. Current Identity Model

Canonical identity (`SampleSemanticDescriptor.canonicalKey`,
`batch|processing|material|orientation`) is implemented as a single formula
type, but is fed by **three distinct entry points with independently
implemented normalization**, not the single call site the contract's
"reuse" language implies:

1. **`SampleKeyNormalizer`** (free-text/filename import) →
   `FileRoutingRuleBook.resolvedDescriptor` →
   `FileRoutingSemanticRules`-based matching → `canonicalKey`.
2. **`LibrarySubstrateParser.sampleKey`** (Registry substrate-cell import,
   inside `LibraryRegistryParser.swift`) → own keyword-list parsing →
   `SampleSemanticDescriptor.fromLibrarySubstrate` → re-validated against
   `FilenameRuleSet`'s compiled substrate-treatment entries.
3. **`DrawerMatchEngine`** — on inspection, this is *not* an independent
   third normalization path; it directly calls `SampleKeyNormalizer` (path
   1) and layers token-subset/conflict-resolution logic on top. The
   contract's "at least three" framing overstates independence here — there
   are two independent normalization implementations, not three.

**Confirmed drift risk (see F4, §9):** paths 1 and 2 draw from the same rule
JSON but disagree on how to apply `match.type`. Path 1
(`FileRoutingSemanticRules.load`) flattens every treatment/material/
orientation match value into a needle dict and always tests by substring
containment, ignoring whether the JSON rule declared `equals` or `contains`.
Path 2 (`FilenameRuleSet.compileSubstrateEntry`) honors `match.type`
faithfully — `.equals` compiles to exact-match-only, `.contains` to
substring. A rule authored as `equals: "O"` therefore behaves as intended
only through the Registry substrate-cell path; through the free-text/import
path (used for measurement-filename routing and `DrawerMatchEngine`
matching) it silently degrades to substring matching and can false-positive
on any input containing the letter O.

`SampleRegistry` (`Registry/SampleRegistry.swift`) is **not** part of the
canonical-identity system at all — see F6 (§9) — it is a separate,
batch-row-keyed lookup used only for Inbox filename routing, despite its
"sampleID"-shaped API.

No disk-path collision risk was found: `sampleKey` strings are used directly
as path components with no sanitization beyond root-escape containment
checks, but since fields are alphanumeric and `|` cannot appear inside a
field, two distinct canonical keys cannot collide on disk.

## 5. Registry → Library Read Path

```
Registry XLSX
   → LibraryRegistryParser.parse (LibraryRegistryParser.swift:72-240)
   → in-memory LibraryIndex (never persisted directly)
```

This path runs **only** on an explicit user action (registry preview/sync),
via `LibraryFeatureStore+PreviewSync.swift:278-354` →
`SpinLabDataActor.parseLibraryPreview`. Its output becomes `libraryPreview`
UI state; to reach disk it must be diffed against the filesystem-derived
baseline and explicitly applied by the user
(`createDrawersFromPreview`/`applySelectedRegistryDiff`/`refreshIncremental`
in `LibraryStore+Drawers.swift`), which writes individual
`batch.json`/`sample.json` files.

It is never invoked automatically at app launch. See §6.

## 6. Library Persistence Lifecycle

```
App launch (RootSplitView.onAppear)
   → appState.loadExistingDrawers()
   → libraryStore.syncIndexFromFilesystem(rootURL:)
   → buildIndexFromFilesystem (LibraryStore+RootAndIndex.swift:66-106)
   → walks batches/**/batch.json + samples/**/sample.json
   → rebuilds LibraryIndex.batches / .samples entirely from disk
   → (persist:true) → saveIndex → index/library_index.json
```

This is the **only** rebuild path that runs automatically. It never touches
the Registry XLSX. `library_index.json` is thus a *persisted cache of the
filesystem walk*, not an independent second authoritative source — but
several read call sites (`ApplyCoordinator`, `SpinLabDataActor` numeric
lookup, `LibraryMutationService`, workflow search, 3ω rendering) read the
cached JSON directly without forcing a fresh filesystem walk, guarded only
by a staleness check (`needsIndexRefresh`) that is wired into a single call
site with a 12-second debounce. This produces a narrow but real staleness
window: those consumers can observe stale batch/sample data within a
session if invoked before any refresh.

**When Registry and filesystem disagree:** the filesystem always wins by
construction, because Registry-parsed data never reaches disk except through
the explicit user-applied diff flow described in §5. If a user edits the
XLSX outside SpinLab and never runs a manual sync, the app has no automatic
awareness of the drift — this is expected/by-design (Registry sync is
opt-in), not a bug, but it means "LibraryIndex is a Registry projection"
(contract §6.1) should be read as "projection at last explicit apply,"
consistent with the contract's own §13.4 caveat.

## 7. Measurement / Analysis Data Lifecycle

```
Workbench analysis
   → measurement records + manual overrides → measurement_data.json
   → chart render → chart image + manifest (semanticParams, filters, axisMapping)
   → results_index.json / measurement_plot_index.json (pointer indices)
```

All artifacts are addressed purely by canonical `sampleKey` via
`LibraryArtifactLayout` — no batch-id/sample-id mixing was found in this
path; multi-sample charts fan out into each contributing sample's own
`results_index.json` rather than any batch-level location.

Missing-vs-corrupt handling is **inconsistent across the three sidecar
families** (a more precise finding than the contract's §13.5 blanket
statement — see F7, §11):

- `measurement_data.json`: mutation-load throws on corruption (does not
  silently regenerate empty) — strongest protection.
- `results_index.json`: mutation-load **silently rebuilds empty** on decode
  corruption (does not throw) — weaker than the contract's tension implies.
- `measurement_plot_index.json`: decode corruption also rebuilds empty
  silently; only a non-decode read/IO error throws.
- `measurement_sets.json`: no missing-vs-corrupt distinction at all — any
  load failure returns an empty set, and a subsequent save can overwrite a
  corrupt-but-recoverable file with nothing.

## 8. Registry Write / Edit Lifecycle

```
Sample detail UI edit
   → LibrarySampleEditService.apply (no scope logic)
   → LibraryFeatureStore+SampleEdit.saveLibrarySampleEdits
   → LibraryRegistrySyncService.syncEditedSample
   → LibraryStore.sampleChangeItems (diffs metadata key-by-key, no scope classification)
   → LibraryXLSXSyncService.syncEditedSample
   → writes directly into the shared sheet/row (sourceSheetName/sourceRowNumber)
```

**Confirmed: editing metadata from one Sample's detail page writes into the
XLSX row shared by every sibling Sample of the same Batch**, and on next
Registry re-parse, siblings will read the changed value as their own. See F1
(§9) — this is the audit's highest-severity finding. `numeric.*` edits are
comparatively safer: they are appended to a separate pending-status log
sheet rather than applied directly to the shared row, so they do not exhibit
the same immediate cross-sample leakage. `LibraryDiffEngine` does not detect
or surface this — it only compares a sample against its own prior stored
state, with no cross-sample comparison capability.

## 9. Web Library Data Lifecycle

```
SpinLab Library (library_index.json, results_index.json, measurement_plot_index.json, chart PNGs)
   → export_static_library.py (read-only on source; writes only into output_dir)
   → public/ (library.json, assets/, export_report.json)
   → git push → Cloudflare Pages deploy
```

Confirmed side-effect-free on the source Library (`ensure_inside()` guard
restricts all writes to `output_dir`). Separately, the deployed site's
same-origin Cloudflare Pages Function (`functions/api/note.js`) reads/writes
a D1 table (`sample_notes`) directly from the browser UI
(`Resources/WebLibraryTemplate/app.js`). No code in either repo — the
exporter or the Swift app — reads D1 data back into `library.json` or into
the local Library. This is a clean, isolated one-way boundary today (see F5,
§9 findings table).

## 10. Batch / Sample / Measurement Field Scope Matrix

| Field | Registry row source | Current storage | Scope per contract §3 | Current implementation scope | Notes |
|---|---|---|---|---|---|
| growth date | row cell | `LibraryBatch.metadata` **and** copied into every `LibrarySample.metadata` | Batch-owned | Duplicated flat, unscoped | F3 |
| temperature | row cell | same as above | Batch-owned | Duplicated flat, unscoped | F3 |
| pressure | row cell | same as above | Batch-owned | Duplicated flat, unscoped | F3 |
| laser energy | row cell | same as above | Batch-owned | Duplicated flat, unscoped | F3 |
| pulse | row cell | same as above | Batch-owned | Duplicated flat, unscoped | F3 |
| target-substrate distance | row cell | same as above | Batch-owned | Duplicated flat, unscoped | F3 |
| growth-level RHEED / observations | row cell | same as above | Batch-owned | Duplicated flat, unscoped | F3 |
| substrate material | substrate cell (parsed) | drives `sampleKey`; also copied into `LibrarySample.metadata` | Sample identity component | Correctly identity-bearing, but *also* duplicated as a plain metadata string alongside batch fields with no scope tag | Needs Decision — see below |
| substrate orientation | substrate cell (parsed) | same as above | Sample identity component | Same as material | Needs Decision |
| processing/treatment | substrate cell (parsed) | same as above | Sample identity component | Same as material | Needs Decision |
| any other row metadata not enumerated above | row cell | copied into both Batch and every Sample | Ambiguous per row; contract doesn't enumerate exhaustively | Duplicated flat, unscoped — **write path has no way to tell which of these are safe for a Sample-scoped edit** | **Needs Decision** — this is the field set F1 puts at risk |
| measurement status / conditions | not a Registry field — set via Workbench/measurement ingestion | `WorkbenchMetricRecord.conditions` / measurement-specific sidecars | Sample-owned (measurement belongs to Sample per §3.3) | Correctly Sample/Measurement-scoped — no leakage found here | Contract-compliant |
| manual override value + reason | Workbench edit | `measurement_data.json` (`WorkbenchMetricOverrideInfo`) | Sample-owned, authored | Correctly Sample-scoped and correctly classified as authored (throws on corruption) | Contract-compliant |
| chart fit range / semanticParams | Workbench analysis choice | chart manifest | Sample-owned, derived-but-authored | Correctly Sample-scoped via `sampleKey` | Contract-compliant |
| measurement set grouping | User UI action | `measurement_sets.json` | Sample-owned, authored | Correctly Sample-scoped, but see F8 (mislabeled as "runtime-only" in a code comment) | Contract-compliant in practice, comment is misleading |

**Core conclusion:** identity-bearing substrate fields (material, orientation,
processing) are structurally correct — they drive `sampleKey` and are
Sample-scoped by construction. The **general growth-metadata bucket** (every
other Registry column) is where scope is genuinely ambiguous at the type
level: it is Batch-owned in principle (§3.1), physically duplicated into
Sample records (§13.1/F3), and — critically — the write path in §8 cannot
distinguish it from any hypothetical future Sample-specific field, because
no such distinction exists anywhere in the schema. This is the field-scope
gap that makes F1 possible, not a single specific mislabeled field.

## 11. Persistence Classification Matrix

| Artifact | Writer | Reader | Source | Rebuildable? | Class | Loss if deleted |
|---|---|---|---|---|---|---|
| `index/library_index.json` | `LibraryStore.saveIndex` via `syncIndexFromFilesystem` | Many (`ApplyCoordinator`, `SpinLabDataActor`, `LibraryMutationService`, `PreviewSync`, 3ω rendering, workflow search) | Filesystem walk of `batch.json`/`sample.json` | Yes, trivially | **A — Rebuildable cache** | Transient; some direct-`loadIndex` consumers see stale/empty data until next rebuild (staleness gap, §6) |
| `batches/**/batch.json` | `writeBatch` (create/update/registry-apply) | `decodeBatch` via `buildIndexFromFilesystem` | Registry row at import, then independently hand-editable | Only if never edited since import | **B — Derived-but-authoritative** | Loses post-import batch metadata merges/edits not reflected in XLSX |
| `samples/**/sample.json` | `writeSample` (create/update, change-logged) | `decodeSample` | Registry row at import, then independently editable via Sample-edit flow | Only if never edited | **B — Derived-but-authoritative** | Loses post-import sample edits (change-logged, not re-derivable from XLSX) |
| `_spinlab/measurement_data.json` | `PersistMeasurementDataUseCase` | `LibraryMeasurementDataStore` | Authored measurement records + manual overrides (`oldValue`/`newValue`/`reason`/`source`) | No | **C — Authored data** | Permanent, irreplaceable — includes override justification/audit trail |
| `_spinlab/results_index.json` | `LibraryChartIndexStore`, `PersistChartArtifactUseCase` | Workbench result loaders, `ChartAssetAuditService` | Pointer index into chart manifests | Reconstructible from manifests, not from raw files | **D — Projection** (of manifests, not of raw data) | Index rebuild possible in principle; not currently wired as an automatic rebuild |
| `_spinlab/measurement_plot_index.json` | Same as above | Same as above | Reverse index over manifest `inputFiles` | Same as above | **D — Projection** | Same as above |
| Chart manifests (`*.manifest.json`) | `PersistChartArtifactUseCase`, `SaveRSMChartToLibraryUseCase` | Chart loaders, audit service | User's fit range / filter / axis choices (`semanticParams`) | No | **C — Authored data** | Loses the specific analysis parameters that produced that chart — cannot be regenerated from raw measurement files alone |
| Chart images (`*.png`) | Same as above | Chart display code | Rendered from manifest + measurement data | Yes, if the manifest survives | **D — Projection** | Recoverable only if manifest is intact; image loss alone is low-risk |
| `measurement_sets.json` | `LibraryStore+MeasurementSets.swift` | Same | Pure user-created grouping, documented as "UI organisation" | No | **C — Authored data** | Loses user's manual measurement grouping; comment in `LibraryDomainModels.swift` groups it misleadingly with genuinely-ephemeral state (F8) |
| Web-exported `public/data/library.json` | `export_static_library.py` | Web Library static site | SpinLab Library (read-only projection) | Yes, fully, by re-running export | **D — Projection** | None; safe to delete and regenerate |
| Cloudflare D1 `sample_notes` | Web Library browser UI via `functions/api/note.js` | Same | Directly authored in the Web Library UI, no SpinLab-side source | No — SpinLab has no copy | **C — Authored data (Web-only)** | Total, permanent loss of the note text; no backup/export path exists today |

## 12. Identity Construction Map

| Entry point | Normalization | Reaches canonical key via |
|---|---|---|
| `SampleKeyNormalizer.canonicalKey/descriptor` | `FileRoutingRuleBook.resolvedDescriptor` → `FileRoutingSemanticRules` needle-substring matching, **ignores declared `match.type`** | `SampleSemanticDescriptor.withPrevalidatedTokens(...).canonicalKey` |
| `LibrarySubstrateParser.sampleKey` (inside `LibraryRegistryParser`) | Own keyword-list parse → canonical display name → re-validated via `FilenameRuleSet`'s compiled entries, **honors `match.type`** (`equals` exact / `contains` substring) | `SampleSemanticDescriptor.fromLibrarySubstrate(...).canonicalKey` |
| `DrawerMatchEngine.match`/`makeIndex` | Delegates entirely to `SampleKeyNormalizer` (same as row 1) + adds its own token-subset/conflict resolution on top | Same as row 1 — not an independent normalization path despite the contract's "at least three" framing |
| `SampleSemanticDescriptor.fromSampleKey` | Parses an already-canonical pipe-delimited string; trusts input, no re-validation | Reconstructs descriptor verbatim |
| `SampleRegistry` / `XLSXPrefixSampleRegistryIndex` | Not identity construction — a separate batch-row-keyed lookup (`sampleIDCandidates`) used only for Inbox filename routing | Never produces a `canonicalKey` |
| `LibraryRegistryParser.swift:477` fallback string `"\(batchId)||UNKNOWN|UNKNOWN"` | Manual string construction, bypasses `SampleSemanticDescriptor` normalization | Only reached when `batchId` normalizes to nil/empty — low materiality edge case, but a real bypass of the canonical formula |

**Batch/Sample naming mismatches found:**
`SampleRegistry`, `SampleRegistryLookupResult.sampleID`,
`SnapshotSampleRegistryIndex`, `XLSXPrefixSampleRegistryIndex`,
`loadSampleRegistry`/`reloadSampleRegistry`/`canReloadSampleRegistry` are all
named around "sample" but index/operate on Registry rows, which are Batch
records (confirmed: the shared header alias `"编号"` appears in both
`sampleHeaderAliases` and `batchHeaderAliases` in
`config/library_import_rules.json`, so for that common header the
"sampleID" column and the batch-id column are the literal same cell).

## 13. Contract Compliance Findings

Findings are classified per the audit brief's four-way scheme:
**A** Contract compliant · **B** Historical naming / harmless debt ·
**C** Architecture debt that should be fixed before Obsidian integration ·
**D** Contract violation / data integrity risk.

| # | Finding | Class | Invariant(s) at stake |
|---|---|---|---|
| F1 | Sample-edit metadata writes land in a Registry row shared by sibling Samples; zero field-scope guard exists | **D** | Inv. 1, 16 |
| F2 | `LibraryIndex`'s automatic rebuild path is filesystem-only; Registry parse never runs automatically and never persists directly — "Registry projection" language needs qualification, but no invariant is actually broken (filesystem JSON is itself Registry-derived at import time) | **B** | Inv. 4 (holds, but only transitively) |
| F3 | Batch metadata duplicated verbatim into every Sample with no scope tag in the type system | **C** | Inv. 1, 16 |
| F4 | Identity normalization drift: `equals`/`contains` `match.type` honored by Registry substrate-cell path, ignored by free-text/filename path — same rule config can yield different `sampleKey` results depending on path | **D** | Inv. 2, 14 |
| F5 | Web Library D1 sample notes are an isolated, one-way-clean Web-only annotation layer with no SpinLab read path | **B** (not a violation today; forward-looking design question only) | Inv. 13 (currently holds — D1 is additive, not upstream of anything) |
| F6 | `SampleRegistry` naming implies sample-level indexing; actual behavior is batch-row-keyed | **B** | Inv. 16 (naming-only; no incorrect behavior found) |
| F7 | Missing-vs-corrupt handling is inconsistent across `measurement_data.json` (throws), `results_index.json`/`measurement_plot_index.json` (silently rebuilds empty on decode corruption), and `measurement_sets.json` (no distinction at all) — the two latter families hold Class-C authored data (fit-range manifests, groupings) without the same corruption guard `measurement_data.json` has | **C** | Inv. 12, 15 (data-loss-avoidance principle, not explicitly numbered but underlies §13.5) |
| F8 | `LibrarySample.measurementSets` is documented in-code as "Runtime-only" alongside genuinely-ephemeral `appliedMeasurements`, but actually backs persisted, irreplaceable user-authored groupings | **B** | None directly; misleading comment risk |
| F9 | `library_index.json` staleness: several read call sites bypass the one wired staleness check, risking stale batch/sample reads within a session | **C** | None directly; operational reliability risk adjacent to Inv. 4 |
| F10 | Manual fallback identity string (`"\(batchId)||UNKNOWN|UNKNOWN"`) bypasses `SampleSemanticDescriptor` normalization | **B** (low materiality, narrow edge case) | Inv. 14 |

## 14. Verified Architecture Tensions (Phase 1 §13 cross-check)

| Contract § | Original framing | Verified? | What changed on verification |
|---|---|---|---|
| 13.1 | Batch metadata physically duplicated into every Sample | **Confirmed**, exactly as described, plus extends to `numericTags`/`numericDisplay`, not just `metadata` | See F3 |
| 13.2 | "SampleRegistry" naming conflates Batch and Sample | **Confirmed** with concrete evidence (shared `"编号"` header alias) | See F6 |
| 13.3 | Canonical identity has 3 independent normalization paths | **Partially confirmed, sharpened**: only 2 independent implementations exist (`DrawerMatchEngine` delegates to path 1, not a 3rd); but a genuine, demonstrated `match.type` drift was found between the 2 that do exist | See F4 |
| 13.4 | `LibraryIndex` has two independent rebuild paths | **Confirmed as structurally true, but clarified**: the two paths are not two competing authorities — filesystem always wins because Registry output never persists directly; there is no silent split-brain, only an opt-in sync model with a narrow staleness gap on top | See F2, F9 |
| 13.5 | Derived sidecars aren't freely rebuildable; corrupt ≠ missing | **Confirmed, more nuanced**: protection is strong for `measurement_data.json`, weak for `results_index.json`/`measurement_plot_index.json` under normal save, absent for `measurement_sets.json` | See F7 |
| 13.6 | Sample-triggered edit writes into a row shared with siblings | **Confirmed exactly**, full call chain traced, no guard exists at any hop | See F1 |
| 13.7 | Web Library already holds authored data (D1 notes) with no upstream source | **Confirmed as isolated/clean**, not currently a violation — no read path back into SpinLab exists anywhere in either repo | See F5 |

## 15. Unresolved Architecture Decisions

Per the audit brief, these are surfaced for Phase 3 decision-making, not
resolved here:

1. **`LibraryIndex` persistence semantics.** Evidence supports a description
   closer to Option C (hybrid) than pure Option A or B: the filesystem JSON
   is the automatic-rebuild source of truth in day-to-day operation
   (behaves like Option B, "application persistence layer"), but its
   *content* originates from, and is periodically re-synced with, explicit
   user-applied Registry diffs (behaves like Option A, "Registry as
   semantic source"). A future design should decide whether to formally
   document the filesystem JSON as the real persistence layer with Registry
   sync as an explicit import/refresh operation (making today's de facto
   behavior the documented contract), or to constrain
   `buildIndexFromFilesystem` so Registry remains a stronger single source
   of rebuild truth.

2. **Batch/Sample field scope.** The field-scope matrix (§10) shows the
   general growth-metadata bucket has no type-level scope tag, which is the
   root enabler of F1. A decision is needed on where a Batch-scoped vs.
   Sample-scoped key list should live (schema-level enum, config-driven
   list, or a structural type split) before any write-path guard can be
   built.

3. **Web D1 notes' long-term role.** Currently a clean Web-only annotation
   layer with no integrity conflict. Future options, not decided here: keep
   as Web-only annotation; merge into a future Dossier/canonical note with
   provenance; migrate into Obsidian/SpinLab canonical notes; or retire.

## 16. Recommended Phase 3 Scope

**Must fix before Obsidian integration**

- F1 (shared-row write leakage): introduce an explicit Batch-scoped vs.
  Sample-scoped key classification before any write path — Obsidian-sourced
  writes will hit the exact same `LibraryXLSXSyncService` write path and
  inherit this risk immediately if it isn't closed first.
- F3 (unscoped duplicated metadata): the type-level fix that make F1
  actually fixable — without a scope tag in the schema, no write guard has
  anything to check.
- F4 (identity normalization drift): unify `match.type` handling between
  the free-text/filename path and the Registry substrate-cell path before a
  fourth (Obsidian) input path is added — Invariant 14 requires Obsidian to
  "reuse the existing canonical Sample identity system," and today that
  system itself is not single-valued.

**Should fix but can defer**

- F7 (inconsistent corrupt-vs-missing handling for `results_index.json`,
  `measurement_plot_index.json`, `measurement_sets.json`): bring these up to
  the same throw-on-corruption discipline `measurement_data.json` already
  has, since they hold Class-C authored data too.
- F9 (`library_index.json` staleness gap): wire the existing
  `needsIndexRefresh` check into the other direct-`loadIndex` call sites, or
  document the staleness window as accepted.
- F8 (misleading "runtime-only" comment on `measurementSets`): documentation
  fix only.

**Do not touch now**

- F2 (filesystem-first rebuild behavior itself) — this is a working,
  load-bearing design; only its *documentation* needs updating (§15.1), not
  its mechanics.
- F5 (Web D1 notes) — no integrity issue exists today; changing it now
  would be scope creep into product decisions explicitly deferred to §15.3.
- F6, F10 (naming-only findings) — cosmetic; renaming risks destabilizing
  working call sites for no functional gain and is explicitly out of scope
  per the audit's non-goals.
- Anything not listed above: measurement import, Library browsing, Registry
  sync, Workbench, result/chart persistence, and Web export are all
  functioning as designed and are not touched by any finding in this
  report.

## 17. Explicit Non-Recommendations

This audit does not recommend, and Phase 3 should not treat this document
as license for:

- Renaming `SampleRegistry`/`SnapshotSampleRegistryIndex`/
  `XLSXPrefixSampleRegistryIndex` or any "sample*"-named-but-batch-keyed API
  as an isolated cleanup — any rename must be bundled with real functional
  work, not done for naming purity alone (per CLAUDE.md's no-drive-by-fixes
  discipline).
- Changing the `sampleKey` schema to add replicate identity (§4.1 of the
  contract is explicit this is a separate, future, explicitly-designed
  extension).
- Building any Obsidian component, `SampleDossier`, `ObsidianVaultIndex`, or
  Registry-append logic as a byproduct of closing F1/F3/F4 — those fixes
  should be scoped as standalone Library integrity work, not bundled with
  Obsidian feature work.
- Modifying Web Library or the D1 note schema based on F5 — no violation
  exists today; any change there is a product decision, not an
  audit-triggered fix.
- Modifying `docs/experiment-data-contract.md` to reflect current behavior
  instead of target semantics — the contract is normative and stays as
  written; this audit report is the place where "current reality differs
  from contract" is recorded.

## 18. Files / Components Inspected

See the full list in §2 above. No file outside `docs/` was modified while
producing this report.
