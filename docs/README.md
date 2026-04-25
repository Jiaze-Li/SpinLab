# Docs Index

## 三类文档分工（权威，跨项目可参考）

| 文档 | 回答的问题 | 内容形态 | 不该有什么 |
|---|---|---|---|
| `V5_ROADMAP.md` | **要做什么 / 在哪个版本段 / 做没做** | 版本段索引 + 一句话条目 + `[x]/[ ]` 状态 | ❌ 设计细节 ❌ 实现说明 ❌ 用户可见结果描述 ❌ 决策动机 |
| `history/vX.Y.Z_*.md` | **做了什么 / 为什么这么做** | 完成事件流水 + 决策记录 + 验收 | ❌ 计划态 ❌ 进度跟踪（那是 ROADMAP 的事） |
| `handoff/<file>.md` | **跨会话接手怎么照做** | 完整执行包：方案 / 约束 / 不可动文件 / 启动指令 | ❌ 长期保存（消费完即归档）❌ 非跨会话任务（同会话连贯做完不需要 handoff） |

### 互相引用方向（单向，不互灌内容）

- ROADMAP 条目 **不指向** handoff/history，只承担索引职责
- history 条目 **指向** handoff（"完整方案见 docs/handoff/archive/..."）
- handoff 内部 **可指向** history（"决策上下文：见 history/vX.Y.Z_*.md"）

### 反模式（禁止）

- 把 handoff 的设计抄进 ROADMAP → ROADMAP 会膨胀成第二份设计文档
- 把 history 的"为什么"塞进 ROADMAP → 同上
- 任务完成后保留 handoff 在「待消费」段 → 必须归档，否则索引失真
- 同会话能做完的任务也写 handoff → handoff 是跨会话工具，不是设计模板

### 配套位置

- Tech Debt Inbox（未分版本段的 raw 捕获池）→ `history/TECH_DEBT_BACKLOG.md`，Jack 拍板后剪到 ROADMAP 对应版本段
- Handoff 三态生命周期 + tmp 清理约定 → `handoff/README.md`

---

## Root-level (知识积累 & 路线图)

| Document | Purpose | Status |
|---|---|---|
| `V5_ROADMAP.md` | Active 5.x roadmap — version segments as collection bins. | active |
| `philosophy.md` | Developer philosophy, habits, collaboration preferences. | active |
| `known_issues.md` | Intentional behaviors, documentation inconsistencies, deferred items. | active |
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
| `history/V4_ROADMAP.md` | V4 roadmap and current development direction. | active |
| `history/TECH_DEBT_BACKLOG.md` | Tech Debt Inbox — raw 捕获池，Jack 拍板后归入 V5_ROADMAP 版本段并从此处删除。 | active |
| `history/TECH_DEBT_EXECUTION_LOG.md` | Round A–G 历史记录。已 sunset，新完成事件进 `history/vX.Y.Z_*.md`。 | sunset |
| `handoff/README.md` | Handoff 三态生命周期（草稿 / 待消费 / 已归档）+ tmp 清理约定 + 索引。 | active |
| `history/v1/` | V1 execution plan. | done |
| `history/v2/` | V2 execution plan. | done |
| `history/v3/` | V3 execution plans, acceptance checklists, iteration addendums. | done |
| `history/v4/` | V4 iteration plans (3Omega/AHE, XY Rotation). | active |

### Development Log (事件驱动开发日志)

Entries added on version bumps, feature changes, or architecture adjustments.

| Version | Event | File |
|---------|-------|------|
| v5.0.0 | Knowledge accumulation system setup | `history/v5.0.0_doc_system.md` |
| v5.3.1 | Plot Shell capability expansion | `history/v5.3.1_plot_shell.md` |
| v5.3.2 | Plot Render Pipeline unification | `history/v5.3.2_render_pipeline.md` |
| v5.3.3 | Multi-Tab Render State Manager | `history/v5.3.3_multi_tab_render_manager.md` |
| v5.3.4 | Legend Dimension Auto-Inference + Visual Consistency | `history/v534_legend_dimension_resolver.md` |
| v5.5.0 | Cross-Area UI Unification | `history/v550_ui_unification.md` |

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
