# Docs Index

> **任务流水线文档职责**（流水线 5 阶段映射 + ROADMAP 三态 + 反模式 + 互相引用方向）= 单一真相在 `~/.claude/docs/workflow.md §3.e`。本文件只列**项目侧具体落点**，不复刻规则。

## 项目侧落点

| 全局角色 | 项目实例 |
|---|---|
| 跨版本任务总览 | `TASK_BOARD.md`（进行中 / 待拍板；状态机见 `~/.claude/docs/workflow.md §9.f`） |
| ROADMAP | `V5_ROADMAP.md`（5.x 版本段；单条三态 `[ ]` / `[~]` / `[x]`） |
| handoff 待消费 | `handoff/<YYYY-MM-DD-topic>.md` |
| handoff 已归档 | `handoff/archive/<YYYY-MM-DD-topic>.md` |
| history（设计思路 + 实施摘要）+ 归档索引 | `history/v<版本号>_<topic>.md` + `history/INDEX.md`（永久全量倒序） |
| 双 AI 对抗草稿 | `tmp/<ai>-plan-<topic>.md`（仅对抗期；见 `~/.claude/docs/workflow.md §9.d`） |

---

## Root-level (知识积累 & 路线图)

| Document | Purpose | Status |
|---|---|---|
| `TASK_BOARD.md` | Cross-version task overview — in-progress + pending-board tasks with pipeline status. | active |
| `V5_ROADMAP.md` | Active 5.x roadmap — version segments as collection bins. | active |
| `philosophy.md` | Developer philosophy, habits, collaboration preferences. | active |
| `features.md` | Feature invariants and test status for all areas (Inbox/Library/Workbench/Shared). | active |

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

## history (开发历史线 & 开发日志)

| Document | Purpose | Status |
|---|---|---|
| `history/INDEX.md` | 永久全量归档索引（完成日 / 版本 / 一句话 / history 文件 / handoff archive / commits 6 列，倒序）。 | active |
| `history/V4_ROADMAP.md` | V4 roadmap and current development direction. | active |
| `history/TECH_DEBT_EXECUTION_LOG.md` | Round A–G 历史记录。已 sunset，新完成事件进 `history/vX.Y.Z_*.md`。 | sunset |
| `history/v1/` | V1 execution plan. | done |
| `history/v2/` | V2 execution plan. | done |
| `history/v3/` | V3 execution plans, acceptance checklists, iteration addendums. | done |
| `history/v4/` | V4 iteration plans (3Omega/AHE, XY Rotation). | active |

## specs (产品/数据/UI 规则)

All specs have been consolidated under the project-root `specs/` directory.

| Document | Purpose | Status |
|---|---|---|
| `../specs/00_RULES_INDEX.md` | Rules entry point and priority order. | active |
| `../specs/01_PRODUCT_RULES.md` | Product behavior contract and safety boundaries. | active |
| `../specs/02_DATA_RULES.md` | Domain model, metadata ownership, normalization rules. | active |
| `../specs/03_PARSER_ROUTING_RULES.md` | Inbox parse/routing rules and conflict behavior. | active |
| `../specs/04_UI_RULES.md` | UI visual & interaction rules (fonts, spacing, buttons, disclosure, accessibility). | active |
| `../specs/05_INBOX_DEPOSIT_UI_SPEC.md` | Inbox deposit UI flow, button semantics, drawer-mapping contract. | active |
| `../specs/06_PROJECT_ARCHITECTURE.md` | Project-specific architecture: code placement, module contracts, checklists. | active |
| `../specs/APP_DESIGN_PRINCIPLES.md` | Long-term architecture and product philosophy. | active |
| `../specs/three_omega_physics.md` | 3-Omega measurement physics reference. | reference |

## Notes
- Architecture docs: system design and per-module technical reference.
- History docs: version plans, iteration records, event-driven development logs.
- Specs: product rules, data contracts, UI standards — all under project-root `specs/`.
- Root-level docs: living knowledge accumulation (philosophy, invariants, known issues).
- Legacy specs are kept under `specs/archive/`.
