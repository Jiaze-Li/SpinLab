# Inbox Architecture — Dispatch Entry

> **Status**: 5.7.2 首发。Inbox 功能区文档结构从「文档类型」维度切换到「功能区 × 层」维度，本目录包含 Inbox 所有层。
> **Source**: `docs/architecture/INDEX.md` 负责 region 级派发；本文件负责 Inbox region 内层级派发。

## Directory Layout

| File | Layer | Scope |
|---|---|---|
| `INDEX.md` | — | Dispatch entry (this file) |
| `ROUTING_PIPELINE.md` | Consume | Parse → Route → Match → Evaluate → Presentation; layer boundaries; algorithm rules |
| `RULES_AUTHORING.md` | Edit | Rules Panel 5-section structure, Save semantics, Auto-Sync engine, Bootstrap |
| `CONFIRM_AND_APPLY.md` | Workflow | Pending queue, draft confirm, Apply/Apply All, Clear Imports, audit timing |
| `OUTPUT_CONTRACTS.md` | Contract | Sidecar fields, tag normalization, registry lookup, Inbox→Library write boundary |

## Reading Order

1. **ROUTING_PIPELINE.md** — how a file becomes a pending item with routing metadata
2. **RULES_AUTHORING.md** — how routing rules are configured and persisted
3. **CONFIRM_AND_APPLY.md** — how the user commits or discards pending items
4. **OUTPUT_CONTRACTS.md** — what gets written to disk when apply completes

## Cross-Domain Boundaries

This directory describes Inbox-internal behavior only. Cross-domain contracts live in:

- `specs/01_PRODUCT_RULES.md` — PO promises (staged processing, manual confirmation, atomicity, audit, Clear Imports safety)
- `specs/02_DATA_RULES.md` — Canonical domain entities and Sample-centered data model
- `specs/04_UI_RULES.md` — Design tokens (fonts, spacing, buttons) consumed by Inbox UI
