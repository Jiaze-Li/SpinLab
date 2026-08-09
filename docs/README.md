# Docs Index

> **任务流水线文档职责**（流水线 5 阶段映射 + ROADMAP 三态 + 反模式 + 互相引用方向）= 单一真相在 `~/.claude/docs/workflow.md §3.e`。本文件只列**项目侧具体落点**，不复刻规则。

## 项目侧落点

| 全局角色 | 项目实例 |
|---|---|
| 全局任务总览 | `TASK_BOARD.md`（进行中 / 待拍板；维护规则在文件末尾「维护规则」段） |
| ROADMAP | `V5_ROADMAP.md`（5.x 版本段；单条三态 `[ ]` / `[~]` / `[x]`） |
| handoff 待消费 | `handoff/<YYYY-MM-DD-topic>.md` |
| handoff 已归档 | `handoff/archive/<YYYY-MM-DD-topic>.md` |
| history（设计思路 + 实施摘要）+ 归档索引 | `history/v<版本号>_<topic>.md` + `history/INDEX.md`（永久全量倒序） |
| 双 AI 对抗草稿 | `tmp/<ai>-plan-<topic>.md`（仅对抗期；见 `~/.claude/docs/workflow.md §9.d`） |

---

## Root-level (知识积累 & 路线图)

| Document | Purpose | Status |
|---|---|---|
| `ecosystem.md` | SpinLab / SpinLab-Web-Library / SpinLab-Web-Tools 的职责边界、数据流与长期关系。 | active |
| `TASK_BOARD.md` | Cross-version task overview — in-progress + pending-board tasks with pipeline status. | active |
| `V5_ROADMAP.md` | Active 5.x roadmap — version segments as collection bins. | active |
| `philosophy.md` | Developer philosophy, habits, collaboration preferences. | active |
| `features.md` | Feature invariants and test status for all areas (Inbox/Library/Workbench/Shared). | active |
| `web_library.md` | Web Library UI source-of-truth, generated-output rules, and Cloudflare-side notes. | active |

## architecture (系统设计 & 模块技术参考)

| Document | Purpose | Status |
|---|---|---|
| `architecture/INDEX.md` | Current architecture dispatch index: region → first-read files → shared risks → tests. | active |
| `architecture/REGION_MAP.md` | 5.1.6 全量区块/层级/共享点扫描底稿（INDEX.md 的工作文件）。 | active |
| `architecture/ARCHITECTURE_OVERVIEW.md` | Global architecture: AppState, FeatureStores, column shell, observation patterns. | active |
| `architecture/inbox/` | Inbox subsystem layers: routing pipeline, rules authoring, confirm/apply, output contracts. | active |
| `architecture/library/` | Library subsystem layers: browse/selection, archive storage, metadata editing, sidecar/conditions, artifacts/previews. | active |
| `architecture/workbench/` | Workbench subsystem layers: shell lifecycle, search, plot canvas, workflow contracts, artifact persistence, 3ω physics, extension boundaries. | active |

## history (开发历史线 & 开发日志)

> **Symlink 设计说明**：`docs/history/` 和 `docs/TASK_BOARD.md` 是指向 `../../SpinLab-shared/` 的 symlink，在本机多 worktree 布局下跨分支共享同一份任务板和历史索引。这是单人单机的有意设计，不支持标准 `git clone`——不需要支持。
>
> **与 `docs/archive/` 的分工**：`docs/archive/` 是本仓库（本分支）内的本地归档，装当前分支产出的、已完结但仍值得保留细节的过程性文档（例如某次专题审计的完整记录），随本分支的 git 历史走，可以正常 `git log`/`git diff`。`docs/history/` 走符号链接指向仓库外的共享目录，装跨分支共用的版本历史与开发日志，不受本仓库 git 管理——不要把只属于本分支的过程文档写进 `docs/history/`，否则本仓库的 git 提交范围看不到它。

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
| `../specs/01_PRODUCT_RULES.md` | Product behavior contract and safety boundaries. | active |
| `../specs/02_DATA_RULES.md` | Domain model, metadata ownership, normalization rules. | active |
| `../specs/04_UI_RULES.md` | UI visual & interaction rules (fonts, spacing, buttons, disclosure, accessibility). | active |
| `../specs/06_PROJECT_ARCHITECTURE.md` | Project-specific architecture: code placement, module contracts, checklists. | active |
| `../specs/three_omega_physics.md` | 3-Omega measurement physics reference. | reference |
| `../specs/archive/INBOX_DEPOSIT_UI_LEGACY.md` | Former 05 — Inbox deposit UI flow. Rules folded into 01/03/04 + `features.md`. | archived |
| `../specs/archive/APP_DESIGN_PRINCIPLES_LEGACY.md` | Former design-principles entry. Folded into `philosophy.md` + 01/02/06. | archived |

## Notes
- `ecosystem.md`: 跨 repo 产品边界和数据流；先看它再决定 Web 相关改动应该落在哪个仓库。
- Architecture docs: system design and per-module technical reference.
- History docs: version plans, iteration records, event-driven development logs.
- Specs: product rules, data contracts, UI standards — all under project-root `specs/`.
- Root-level docs: living knowledge accumulation (philosophy, invariants, known issues).
- Legacy specs are kept under `specs/archive/`.
