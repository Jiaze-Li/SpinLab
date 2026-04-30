# Inbox Output Contracts

Defines what gets written to disk when an Inbox item is applied: the sidecar schema, tag normalization mapping, registry lookup rules, and the Inbox→Library write boundary.

---

## Sidecar Ownership

- Archive metadata sidecar in sample drawers is the primary metadata source for archived measurement file tagging.
- App index/state may mirror sidecar metadata for fast lookup but must not silently diverge.
- Schema changes to the sidecar require migration and tests — not local UI-only edits.
- `SpinLabFileSidecar` is a cross-cutting file contract shared by Library, Inbox, and Workbench.

---

## Minimum Sidecar Fields

Sidecar generated at apply time must include all of the following:

| Field | Description |
|---|---|
| `version` | Sidecar schema version |
| `source_file` | Original filename as imported |
| `sample_key` | Resolved sample key |
| `workflow` | Workflow identifier |
| `conditions` | `temperature`, `current`, `field` |
| `channel_bindings` | Per-channel sample key assignments |
| `normalized_tags` | Normalized measurement tags |
| `raw_tags` | Raw source tag values (for traceability) |
| `applied_at` | ISO timestamp of archive apply |

---

## Tag Normalization

| Raw tag | Normalized value |
|---|---|
| `AMR` | `R_xx` |
| `PHE` | `R_xy` |
| `XY_90shift` | `workflow = XY` + `angle_shift = +90deg` |

Raw source values are persisted alongside normalized values for traceability.

---

## Registry Lookup Runtime Rules

The registry lookup is handled by a dedicated rulebook layer, not mixed with routing:

- `RegistryLookupRuleBook` implements the lookup policy interface.
- Sheet indexing rules:
  - Sheets prefixed with `__` are not indexed for sample lookup.
  - Sheets without a recognized sample-ID column are not indexed.
- Query path: `sampleID → indexed row(s)` direct lookup.
- Prefix-to-sheet mapping is display metadata only — it is informational and is not a routing dependency for lookup.

---

## Inbox→Library Write Boundary

- All writes go through `LibraryWriteTransaction`. Bypassing it for paired file + sidecar writes is forbidden.
- Inbox is the workflow owner for apply; Library is the storage owner.
- Write sequence per file: file archive → sidecar write → both are rolled back together on any failure.

---

## Code Map

- `Sources/SpinLabApp/Library/SpinLabFileSidecar.swift` — sidecar schema, Codable model, field contracts
- `Sources/SpinLabApp/Registry/SampleRegistry.swift` — registry lookup entry point
- `Sources/SpinLabApp/Registry/RegistryLookupRuleBook.swift` — lookup policy: sheet indexing, query path
- `Sources/SpinLabApp/Registry/RegistrySheetFilter.swift` — sheet inclusion/exclusion rules (__ prefix, column check)
- `Sources/SpinLabApp/Import/RegistrySubstrateRuleBook.swift` — substrate-level registry rule book consumed by Inbox routing
- `Sources/SpinLabApp/App/State/RegistryFeatureStore.swift` — registry feature state; wires registry lookup into App layer
