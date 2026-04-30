# Library Architecture — Dispatch Entry

> **Status**: 5.7.2 首发。Library 功能区文档结构从「文档类型」维度切换到「功能区 × 层」维度，本目录包含 Library 所有层。
> **Source**: `docs/architecture/INDEX.md` 负责 region 级派发；本文件负责 Library region 内层级派发。

## Directory Layout

| File | Layer | Scope |
|---|---|---|
| `INDEX.md` | — | Dispatch entry (this file) |
| `BROWSE_AND_SELECTION.md` | Browse | Root view, column shell, selection, search/filter, detail section ordering |
| `ARCHIVE_STORAGE.md` | Storage | Drawer/index/settings, filesystem→app state sync, archive canonical, audit log |
| `SAMPLE_METADATA_EDITING.md` | Edit | Sample edit transaction, registry diff/sync, display name protection |
| `SIDECAR_AND_CONDITIONS.md` | Contract | Sidecar reading/display in Library, conditions/tags, Inbox/Workbench shared boundary |
| `ARTIFACTS_AND_PREVIEWS.md` | Artifacts | `_spinlab` chart/metric artifacts, preview, path resolver, Workbench write boundary |

## Reading Order

1. **BROWSE_AND_SELECTION.md** — how Library presents and navigates archived measurements
2. **ARCHIVE_STORAGE.md** — how the drawer/index is loaded, synced, and written
3. **SAMPLE_METADATA_EDITING.md** — how sample metadata is edited and registry-synced
4. **SIDECAR_AND_CONDITIONS.md** — what sidecar data Library reads and how conditions/tags are displayed
5. **ARTIFACTS_AND_PREVIEWS.md** — how chart/metric artifacts are stored, resolved, and previewed

## Why Layer Names Differ from Inbox

Inbox core verbs: parse/route/review/apply. Library core verbs: browse/select/edit/sync/preview. Applying Inbox layer names to Library would hide its distinct responsibilities: filesystem index maintenance, sample projection, sidecar display, and artifact discovery.

## Cross-Domain Boundaries

This directory describes Library-internal behavior only. Cross-domain contracts live in:

- `specs/01_PRODUCT_RULES.md` — PO promises (audit log, Clear Imports safety, display name protection)
- `specs/02_DATA_RULES.md` — Canonical domain entities and sample-centered data model
- `specs/04_UI_RULES.md` — Design tokens (fonts, spacing, buttons, AppColumnShell) consumed by Library UI
- `docs/architecture/inbox/OUTPUT_CONTRACTS.md` — Sidecar schema canonical source of truth (Library is read-only consumer; see SIDECAR_AND_CONDITIONS.md)
