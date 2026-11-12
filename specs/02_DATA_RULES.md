# SpinLab Data Rules

Status: active **authority routing**, not a parallel domain-model contract.

## Approved Sample-centred target (new work)

The single maintained definition of planned entities, identifiers, links, Source/Dataset/Result/Plot/Snapshot distinctions, storage choices, and K1–K13 safeguards is [the execution data skeleton](../docs/architecture/spinlab/execution/SKELETON.md).

- Read the relevant [task brief](../docs/architecture/spinlab/execution/README.md) for exact implementation scope and acceptance.
- A design target is **not** evidence of implemented runtime behavior: do not treat planned SQLite links, identifiers or result invalidation as shipped.
- Earlier conceptual entity lists (including independent Project, Batch, Device, Measurement or Comparison) do **not** require those new persistent entities. No implicit legacy Library migration follows from this document.

## Existing formats and boundaries

- Before modifying legacy records, inspect actual Swift models and the [Library architecture](../docs/architecture/library/INDEX.md); do not silently reinterpret existing formats as the target model.
- Existing Inbox sidecar fields, tag normalization and Inbox-to-Library output are in [OUTPUT_CONTRACTS.md](../docs/architecture/inbox/OUTPUT_CONTRACTS.md).
- Existing import confirmation and archive safety constraints remain in [01_PRODUCT_RULES.md](01_PRODUCT_RULES.md).

Where actual implementation and the target differ, state that difference in the task and implement only the agreed scope.
