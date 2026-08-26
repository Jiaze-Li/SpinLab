# Experiment Data Architecture Contract

Status: **Normative.** This document is a contract, not a proposal. It defines
identity, ownership, and boundary rules that must hold across SpinLab's
experiment-data model as new sources (Obsidian) are introduced alongside the
existing ones (Registry Excel, raw measurement files, SpinLab-generated
results, Web Library).

This contract does not itself grant any exception from
`docs/TASK_BOARD.md` governance (see `CLAUDE.md`, "Technical debt
governance"). It records architecture, invariants, and known tensions; it
does not carry debt lifecycle state.

---

## 1. Purpose

SpinLab's experiment records are moving from a single-source model (Excel
Registry as both entry point and store) to a multi-source model:

- Obsidian becomes the day-to-day human authoring surface for experiment
  records.
- SpinLab remains the central organization and aggregation layer for
  experiment information.
- Registry Excel becomes a tabular *projection* of growth conditions rather
  than the sole authored record.
- Raw measurement files remain the one-and-only source of acquisition facts.
- SpinLab-generated results/charts remain derived analysis artifacts.
- Web Library remains a publication projection of SpinLab data.

This contract fixes the domain model, identity rules, and ownership
boundaries that must hold regardless of how many sources exist, so that
adding Obsidian as a source does not require re-deriving these rules later
and does not silently turn any projection into a second authored store.

## 2. Scope

In scope: the conceptual model of Batch, Sample, and Measurement; canonical
sample identity; data ownership and provenance across sources; the
boundaries between authored sources, rebuildable indices, and join/read
models; read vs. mutation contracts; persistence and rebuildability
guarantees; compatibility requirements against the current implementation;
explicit non-goals; known limitations; architecture invariants; and observed
tensions between this contract and the current implementation.

Out of scope: implementing any Obsidian parser, changing the Registry write
path, changing `sampleKey` schema, refactoring Library code, fixing any
implementation tension recorded here, designing an Obsidian UI, fixing a
Markdown note schema, changing Web Library, or starting the Phase 2 Full
Library Architecture Audit referenced in §13.

## 3. Core Domain Model

### 3.1 Batch

A Batch represents one growth/deposition run (e.g. `PN109`). A Batch owns
growth-level information: growth date, target/material being grown,
temperature, pressure, laser energy, pulse, target-substrate distance,
growth-level RHEED, growth-level observations, and any other condition that
describes the run itself rather than an individual specimen produced by it.

A single Batch can produce multiple Samples.

### 3.2 Sample

A Sample is a specimen produced by a Batch that can be independently
measured, analyzed, and recorded. Example: Batch `PN109` growing both
STO(110) and STO(111) substrates produces two Samples:

```
Batch PN109
├── Sample STO(110)
└── Sample STO(111)
```

Samples belonging to the same Batch share that Batch's growth conditions,
but each Sample owns its own measurements, test status, analysis/results,
charts, sample-specific observations, and conclusions.

Core principle:

> Growth belongs to Batch. Measurements and sample-specific observations
> belong to Sample.

### 3.3 Measurement

A Measurement is a single acquisition/test performed against one Sample. A
Measurement never belongs to a Batch directly — it always resolves to a
Sample, which in turn belongs to a Batch.

## 4. Identity Contract

The canonical sample identity is the existing four-field `sampleKey`,
produced by `SampleSemanticDescriptor.canonicalKey`:

```
batch | processing | substrate material | orientation
```

Example: `PN109|o|STO|110`, `PN109|o|STO|111`.

Rules:

- This contract does not modify the `sampleKey` schema.
- All identity resolution — for Registry rows, imported measurement files,
  routing/matching, and any future Obsidian content — must resolve through
  the existing identity machinery (`SampleSemanticDescriptor`,
  `SampleKeyNormalizer`, `LibrarySubstrateParser`). Obsidian integration must
  not invent a second, parallel sample-ID namespace.
- A Batch identity is the raw batch token (e.g. `PN109`) used as the first
  `sampleKey` field and as `LibraryBatch.id`. It is not itself a composite
  key; Sample identity extends it.

### 4.1 Known limitation (not resolved by this contract)

The four-field key cannot distinguish two physically distinct specimens
within the same Batch that share identical processing, material, and
orientation (a true replicate). This is recorded as a future extension
point. This contract explicitly does **not** modify the `sampleKey` schema
and does **not** introduce a replicate ID now.

## 5. Data Ownership and Provenance

There is no single file or system that is "the one source of truth" for all
experiment data. Ownership is determined per data type and per record by
provenance, not by a blanket rule over an entire source:

- Historical growth records may be authored directly in Registry.
- Under the new SOP, growth information is authored preferentially in
  Obsidian.
- Therefore neither "Registry is always truth" nor "Obsidian is always
  truth" is a valid global rule. Every record must carry (or be resolvable
  to) its provenance.

Reconciliation rules when both Registry and Obsidian carry a value for the
same field:

- Matching values may be treated as confirmed.
- Conflicting values must be surfaced explicitly as a conflict state, never
  resolved silently.
- Silent overwrite is prohibited.
- Silent precedence (e.g. "Obsidian always wins") is prohibited.

Raw measurement files are the source of acquisition facts. SpinLab-generated
analysis/results/charts are derived artifacts and must never become the
source of raw-measurement truth, even when they are the only convenient
place a value appears (e.g. a fitted parameter must not be back-read as if
it were a measured quantity).

## 6. Source / Index / Projection Boundaries

### 6.1 Current shape

```
Registry
   ↓
LibraryRegistryParser
   ↓
LibraryIndex
```

`LibraryIndex` is a rebuildable structured index. Its Registry-derived
content must remain reconstructible from the Registry alone.

### 6.2 Target shape with Obsidian

```
Obsidian
   ↓
ObsidianVaultParser
   ↓
ObsidianVaultIndex
```

`ObsidianVaultIndex`:

- is built only from Obsidian content,
- has no knowledge of the Registry Excel,
- is fully deletable and fully rebuildable from Obsidian alone,
- is never a hand-authored data source itself.

### 6.3 Integration is a separate join layer

The two indices integrate only through a dedicated read model:

```
LibraryIndex
         \
          → SampleDossier / SampleDossierIndex
         /
ObsidianVaultIndex
```

The Dossier layer owns identity join, provenance tracking, conflict state,
and the combined sample view. The Dossier is a read/integration model. It
must not become a new hand-authored source of truth — nothing should be
written directly into a Dossier that isn't traceable back to one of its
upstream sources.

### 6.4 Projections stay projections

- Registry Excel's long-term role is a growth-condition tabular
  projection/operational registry — not a general-purpose measurement/note
  database. Do not grow Registry's responsibility to cover measurement
  status, freeform notes, or analysis results.
- Web Library is a publication projection of SpinLab data, not an authored
  source (see §13.7 for where this already does not hold today).

## 7. Read and Mutation Contracts

Parser, index, and dossier construction must be side-effect-free read
pipelines. In particular:

- An Obsidian parser must never directly modify the Registry XLSX.
- The correct direction for a write that originates from Obsidian content is:

  ```
  Obsidian
  → parsed structured record
  → validation / reconciliation
  → RegistryRowDraft
  → explicit Registry mutation service
  ```

- Registry mutation must remain an independent, explicit, auditable path,
  decoupled from any parser. (Today this is `LibraryXLSXSyncService`,
  invoked only through explicit sample-edit flows — never from
  `LibraryRegistryParser` itself. This separation must be preserved and
  extended, not bypassed, for any Obsidian-originated write.)

## 8. Persistence and Rebuildability

- `LibraryIndex`'s Registry-sourced content must remain reconstructible from
  Registry alone.
- `ObsidianVaultIndex` must remain reconstructible from Obsidian alone.
- Neither index may develop a dependency on the other during construction.
  Cross-source reconciliation happens only in the Dossier join layer (§6.3).
- Derived analysis/chart artifacts (results/plot indices, chart images and
  manifests, measurement data caches) remain attached to a canonical
  `sampleKey` and are addressed through `LibraryArtifactLayout`. Their
  rebuildability guarantee is narrower than the structured indices above:
  see §13.5.

## 9. Compatibility Requirements

The new architecture must preserve and reuse, without unnecessary breakage:

- the existing `LibraryIndex`
- the existing `LibraryBatch`
- the existing `LibrarySample`
- the existing four-part `sampleKey`
- the existing sample-level artifact layout (`LibraryArtifactLayout`)
- the existing measurement/results sidecars
  (`LibraryMeasurementDataStore`, `LibraryChartIndexStore`,
  `SpinLabFileSidecar`)
- the existing Registry read path (`LibraryRegistryParser`,
  `LibrarySubstrateParser`)
- the existing Web Library publication boundary
  (`WebLibraryPublishService` / `scripts/publish_web_library.sh`)

Adding Obsidian as a source is not, by itself, license to break any of the
above interfaces.

## 10. Explicit Non-Goals

This document does not:

- implement an Obsidian parser
- implement Registry append/write logic
- modify the `sampleKey` schema
- refactor Library code
- fix any architecture issue found while reading the current implementation
- design a complete Obsidian UI
- mandate a final Obsidian Markdown note schema
- prescribe Obsidian file/note organization (e.g. one file per Batch vs. one
  file per Sample) — this is product/operational design, not domain
  contract, and the parser architecture must tolerate future changes to
  note layout without changing the domain model in §3–§4
- modify Web Library
- begin the Phase 2 Full Library Architecture Audit (§13 records candidate
  audit targets only)
- modify any production code

## 11. Known Limitations / Extension Points

- **Replicate identity.** See §4.1 — same Batch, same
  processing/material/orientation, physically distinct specimen, is not
  representable today. Any future fix is an explicit, separately-designed
  extension to `SampleSemanticDescriptor`/`sampleKey`, not an incidental
  side effect of Obsidian integration.
- **Obsidian → SpinLab measurement status.** Not built by this contract;
  the join layer (§6.3) is the intended landing point when it is built.
- **Obsidian sample notes → SpinLab sample detail.** Not built by this
  contract; same landing point.
- **Selected Obsidian content → Web Library.** Not built by this contract;
  must flow through the same publication boundary as other SpinLab data
  (§6.4), not bypass it.

## 12. Architecture Invariants

These are written to be checked individually during a future architecture
audit.

1. A growth condition has Batch ownership, not independent Sample ownership.
2. A measurement resolves to a canonical Sample identity.
3. Samples belonging to the same Batch inherit shared Batch growth
   conditions.
4. `LibraryIndex` remains reconstructible from Registry alone.
5. `ObsidianVaultIndex` remains reconstructible from Obsidian alone.
6. Obsidian parsing does not depend on Registry.
7. Registry parsing does not depend on Obsidian.
8. Cross-source reconciliation occurs only in an explicit
   integration/join layer.
9. No projection silently becomes an authored source.
10. Conflicting source values are surfaced, not silently resolved.
11. Registry mutation is never performed by a parser.
12. Derived analysis artifacts do not become raw-measurement truth.
13. Web publication does not become an upstream data source.
14. Obsidian must reuse the existing canonical Sample identity system rather
    than create a parallel identity namespace.
15. Existing sample-level measurement/result artifacts remain attached to
    canonical `sampleKey`.
16. Batch-level and Sample-level ownership must remain distinguishable
    throughout persistence and UI projections.

## 13. Current Implementation Tensions

These are observations from reading the current implementation against the
principles above. They are recorded, not resolved, per §10. A future Phase 2
Full Library Architecture Audit should evaluate Library, Registry, Import,
Persistence/Storage, measurement/results sidecars, App services, relevant
UI, and the Web exporter against these observations and the invariants in
§12.

### 13.1 Batch-level growth metadata is physically duplicated into every Sample

`LibraryRegistryParser.parse` reads one `metadata` dictionary per registry
row and assigns the *same* dictionary both to the row's `LibraryBatch`
(`Sources/SpinLabApp/Library/LibraryRegistryParser.swift:173-192`) and to
every `LibrarySample` derived from that row's substrate cell
(`LibraryRegistryParser.swift:203-218`, `sample.metadata = metadata`). Today
there is no structural separation between "this is a growth-level field
that belongs to the Batch" and "this is a sample-specific field" — every
Sample carries a full copy of its Batch's row metadata. This is the concrete
case Invariant 1 and Invariant 16 are meant to guard against; it currently
does not hold at the storage level, only by convention (nothing prevents a
Sample-level edit path from diverging a copy from its Batch's copy).

### 13.2 The Registry load/reload API is named "SampleRegistry" even though a Registry row is fundamentally a Batch record

`RegistryFacade`, `RegistryCoordinator`, and `SpinLabAppState` all name the
Registry load/reload operations `loadSampleRegistry` /
`reloadSampleRegistry` / `canReloadSampleRegistry`
(`Sources/SpinLabApp/App/RegistryFacade.swift`,
`Sources/SpinLabApp/App/RegistryCoordinator.swift`), while each Registry row
is parsed as one Batch that may fan out into multiple Samples
(`LibraryRegistryParser.swift:147-226`). The naming conflates "the registry
of batches, which happens to expand into samples" with "a registry of
samples." This is a naming-only observation, but it is exactly the kind of
historical Batch/Sample conflation this contract's Batch/Sample split (§3)
is meant to prevent from recurring in Obsidian-facing code.

### 13.3 Canonical-identity construction is centralized in type, but distributed across call sites

`SampleSemanticDescriptor.canonicalKey` is the single formula for
`sampleKey`, but it is independently constructed from at least three
different input paths with three different normalization entry points:
`SampleKeyNormalizer` (free-text/import resolution, via
`FileRoutingRuleBook`), `LibrarySubstrateParser.sampleKey` (Registry cell
parsing, via `SampleSemanticDescriptor.fromLibrarySubstrate`), and
`DrawerMatchEngine` (routing/matching). Each path has its own tokenization
and fallback rules before it reaches the shared descriptor type. Any future
Obsidian parser adds a fourth input path; Invariant 14 requires it to also
route through `SampleSemanticDescriptor`, but the existing three-path
spread means "reuse the canonical identity system" is not a single call
site to reuse — an audit should confirm a new Obsidian path does not
introduce its own drifted normalization the way the existing three paths
have each accreted their own.

### 13.4 `LibraryIndex` has two independent rebuild paths, not one

Invariant 4 states `LibraryIndex` remains reconstructible from Registry
alone. In the current implementation this is true of the *Registry parse*
path (`LibraryRegistryParser.parse`), but `LibraryStore` also rebuilds
`LibraryIndex` from on-disk `batch.json`/sample JSON files under
`samples/**` via `buildIndexFromFilesystem`
(`Sources/SpinLabApp/Library/LibraryStore+RootAndIndex.swift:66-106`), which
does not touch the Registry XLSX at all. This means the persisted
`LibraryIndex` is not purely a live Registry projection today — the
on-disk per-batch/per-sample JSON is itself a second, filesystem-resident
copy of the same information, and it is this filesystem copy (not a fresh
Registry parse) that most rebuild-on-demand flows actually reconstitute
from. Any future statement that "the Library index is a projection of
Registry" should be understood as "projection of Registry *at
import/sync time*, persisted as filesystem JSON thereafter" — the two are
not interchangeable, and an audit should determine whether that gap is
intentional (a durability cache) or an unmanaged second source.

### 13.5 Derived analysis/result sidecars are not freely rebuildable from raw measurement files

`LibraryMeasurementDataStore` and `LibraryChartIndexStore` deliberately do
not treat "corrupt" the same as "missing": a corrupt `measurement_data.json`
or `results_index.json` throws rather than silently regenerating an empty
store, specifically to avoid data loss
(`Sources/SpinLabApp/Library/LibraryMeasurementDataStore.swift:29-41`,
`LibraryChartIndexStore.swift` doc comments). This is correct
data-loss-avoidance behavior, but it also means these sidecars are not
"rebuildable indices" in the same sense as `LibraryIndex`/
`ObsidianVaultIndex` — they can contain user-produced analysis (fits,
selections) that has no other source and genuinely cannot be regenerated
from raw measurement files. §8's rebuildability language should not be read
as implying these sidecars can be deleted and regenerated the way the
structured indices can; an audit should make this distinction explicit
wherever "rebuildable" is used for Library artifacts generally.

### 13.6 A Sample-triggered Registry edit writes into a row shared with sibling Samples

`LibraryRegistrySyncService`/`LibraryXLSXSyncService` write metadata/numeric
edits back to the Registry keyed by `sheet_name`/`row_number`
(`LibraryXLSXSyncService.swift:44-52` header shape), which is the row a
Batch and all of its co-located Samples share (§13.1). Because Batch-level
fields are currently duplicated per-Sample rather than structurally
separated, an edit made from one Sample's detail view, if it targets a field
that is actually Batch-level, is written back to the row that every sibling
Sample in the same Batch also reads from. There is no visible guard today
that distinguishes "this metadata key is Sample-scoped" from "this metadata
key is Batch-scoped" before the write happens. This is the sharpest current
violation risk against Invariant 1/16 and is worth flagging explicitly for
the Phase 2 audit, since it is a live write path, not just a modeling
looseness.

### 13.7 Web Library already holds an authored data type with no upstream source

`docs/web_library.md` and `scripts/publish_web_library.sh` establish that
Web Library's static snapshot (`public/`) is disposable generated output —
consistent with §6.4/Invariant 13. However, `docs/web_library.md` also
specifies that sample notes are edited directly in the web app and stored
in a Cloudflare D1 database, explicitly *not* in `public/`, not in
`library.json`, and not in the local SpinLab Library snapshot. This means
Web Library, as currently specified, already contains one category of data
(sample notes) for which SpinLab/Registry/Obsidian is not the source and
has no read path back — Web Library is the sole store for that data type.
This is a direct exception to "Web publication does not become an upstream
data source" (Invariant 13) that predates this contract. It is recorded
here rather than resolved, per §10; a future decision is needed on whether
sample notes should be pulled into the Dossier/SpinLab side as a first-class
provenance-tracked field, or intentionally remain a Web-Library-only
annotation layer outside this contract's ownership rules.

## 14. Unresolved Architecture Questions

Recorded for the Phase 2 audit; not blocking this contract and not answered
here:

- Whether §13.4's filesystem-JSON rebuild path should be formally documented
  as the real persistence layer (with Registry parse treated as an
  import/refresh operation rather than "the" rebuild path), or whether
  `buildIndexFromFilesystem` should be constrained so Registry remains the
  single rebuild source.
- Whether §13.6's shared-row write risk should be closed by introducing an
  explicit Batch-scoped vs. Sample-scoped metadata key list, and where that
  list should live.
- Whether Web Library sample notes (§13.7) should eventually be surfaced
  back into SpinLab/Dossier with provenance, or are intentionally
  Web-Library-only and should be documented as such in `web_library.md`.
