# Docs Index

## architecture (系统设计 & 模块技术参考)

| Document | Purpose | Status |
|---|---|---|
| `architecture/ARCHITECTURE_OVERVIEW.md` | Global architecture: AppState, FeatureStores, column shell, observation patterns. | active |
| `architecture/APP_FLOW.md` | End-to-end app workflow and page responsibilities. | active |
| `architecture/import/IMPORT_PIPELINE_EVALUATE_FLOW.md` | Import 5-stage evaluate flow: Parse → Route → Match → Evaluate → Presentation. | active |
| `architecture/import/ROUTING_LAYER_BOUNDARIES.md` | Import routing layer boundary contracts and dependency rules. | active |
| `architecture/rules/RULE_BASELINE_MANIFEST.md` | Rule file inventory, loading sequence, override mechanism. | active |
| `architecture/rules/RULE_SCHEMA_VERSIONING.md` | Rule schema version policy and migration strategy. | active |
| `architecture/library/LIBRARY_ARCHITECTURE_AUDIT.md` | Library feature audit: layer map, redundancy analysis, consolidation plan. | active |

## history (开发历史线 & 技术债务)

| Document | Purpose | Status |
|---|---|---|
| `history/V4_ROADMAP.md` | V4 roadmap and current development direction. | active |
| `history/TECH_DEBT_BACKLOG.md` | Pending technical improvements, ordered by impact. | active |
| `history/TECH_DEBT_EXECUTION_LOG.md` | Completed technical debt reduction rounds. | active |
| `history/v1/` | V1 execution plan. | done |
| `history/v2/` | V2 execution plan. | done |
| `history/v3/` | V3 execution plans, acceptance checklists, iteration addendums. | done |
| `history/v4/` | V4 iteration plans (3Omega/AHE, XY Rotation). | active |

## specs (产品/数据/UI 规则)

| Document | Purpose | Status |
|---|---|---|
| `specs/00_RULES_INDEX.md` | Rules entry point and priority order. | active |
| `specs/01_PRODUCT_RULES.md` | Product behavior contract and safety boundaries. | active |
| `specs/02_DATA_RULES.md` | Domain model, metadata ownership, normalization rules. | active |
| `specs/03_PARSER_ROUTING_RULES.md` | Inbox parse/routing rules and conflict behavior. | active |
| `specs/04_UI_RULES.md` | UI layout and interaction rules. | active |
| `specs/05_INBOX_DEPOSIT_UI_SPEC.md` | Inbox deposit UI flow, button semantics, drawer-mapping contract. | active |
| `specs/APP_DESIGN_PRINCIPLES.md` | Long-term architecture and product philosophy. | active |
| `specs/three_omega_physics.md` | 3-Omega measurement physics reference. | reference |

## Notes
- Architecture docs: system design and per-module technical reference.
- History docs: version plans, iteration records, tech debt tracking.
- Specs: product rules, data contracts, UI standards.
- Legacy specs are kept under `specs/archive/`.
