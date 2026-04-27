# 5.7.1 — TASK_BOARD 引入 + 文档治理重构

> 设计思路从 `docs/V5_ROADMAP.md v5.7.1` 段迁入（归档于 2026-04-27）。

## 动机

跨版本任务态散落在 V5_ROADMAP / handoff/README / TECH_DEBT_BACKLOG 三份文档，每份只看流水线一段切片，回到项目无法一眼判断"当下在做哪些版本任务、各自卡在哪一阶段"。同时 TECH_DEBT_BACKLOG 长期只装一两条 raw 捕获、handoff/README 内容职责分裂（待消费索引 + 已归档 audit + tmp protocol + 分工样板 + 命名指针 5 类内容混塞），都已退化为低维护价值文档。

**顶层原则**：每份文档只装一种内容；横切总览只装"一句话 + 状态 + 指针"，不复刻设计思路 / 实施方案 / 验收摘要。

## 拍板方案

**A. 新建 `docs/TASK_BOARD.md` 作为跨版本任务总览**

两段：「进行中」表（版本 / 一句话 / 状态 / 指针 4 列）+「待拍板」表（来源 / 描述 / code pointer 3 列）。状态机 3 态 + 完成：

| 触发事件 | 状态 |
|---|---|
| ROADMAP 新加一条（无 handoff）| `需求提出` |
| handoff 落盘 | `方案完成 (s<n>)` |
| 接手会话第一次 commit 落地 | `方案执行中 (s<n>)` |
| handoff archive | 整行删 + history/INDEX 加一行 |

多会话拆分：「一句话」列括号显示已完成 s 进度（`s1-s5 已完成`），「状态」+「指针」反映当前 active s。重做由 Jack 显式指挥触发，AI 不自行回退状态。

**B. 新建 `docs/history/INDEX.md` 作为永久全量 history 索引**

按完成时间倒序，含「完成日 / 版本 / 一句话 / history 文件 / handoff archive / commits」6 列。一份索引同时服务 history/v*_*.md 详细历史 + handoff/archive/*.md 执行存档。替代 `docs/README.md`「Development Log」表。

**C. 整删 `docs/handoff/README.md`**

原内容拆解去向：「待消费」段 → TASK_BOARD；「已归档」表 → history/INDEX；tmp 三选一 protocol → workflow.md §9.d；执行分工表样板 → workflow.md §9.a；文件命名指针 + historical note → 删（workflow.md 自有命名规范，historical note 无独立保留价值）。`docs/handoff/` + `docs/handoff/archive/` 目录保留。

**D. 退役 `docs/history/TECH_DEBT_BACKLOG.md`**

现存 1 条（LibraryStore try? audit 剩余项）迁入 TASK_BOARD「待拍板」段，文件 `git rm`。「待拍板」段直接吸收 raw 捕获池职责。

**E. 全局 workflow.md 配套改动**

- §9.a「指针登记」段：去掉硬编码 handoff/README 例子，改为"项目 CLAUDE.md 指定的索引落点"中性表述
- §9.a 末尾追加「执行分工表样板」子段
- §9.c 第 2 步「索引更新」改为按项目侧约定迁移
- §9.d 段尾追加 14 天提示规则
- 新增 §9.f「TASK_BOARD-style 任务总览维护触发表」（项目可选）

**F. 项目 CLAUDE.md 同步改 4 处**：Handoff Pointer Registry / Session Startup tmp 处置指针 / Session Closeout 加第 6 步 / Roadmap Reference debt 入口。

## 否决方案及理由（不要后续 agent 推翻）

**否决 1：8 阶段标签（Codex 原方案）**

Codex 原稿用 8 个细分标签（captured / pending_board_decision / planned / handoff_ready / in_execution / review_loop / done / archived）。Jack 拍板用 3 状态 + 完成（需求提出 / 方案完成 / 方案执行中 / 删行）。理由：done ↔ archived / captured ↔ pending_board_decision 中间态停留时间极短或边界模糊，只增维护负担、不增信息密度。review_loop 等执行内部子状态不应进 TASK_BOARD（执行细节归 handoff / 评审记录归 commit）。

**否决 2：Recently Closed 滚动归档段（Codex 原方案）**

Codex 原稿在 TASK_BOARD 底部加「最近 30 天 / 10 条已完成滚动表」。Jack 拍板：完成即整行删，已完成走 history/INDEX 永久全量索引。理由：Recently Closed 段实质是 ROADMAP `[x]` 内容复读 30 天，触发"双账本"反模式（同一份信息两处存）。history/INDEX 永久全量 + 倒序解决可见性需求且无窗口期遗忘。

**否决 3：tmp/ protocol 迁项目 CLAUDE.md（Codex 原方案）**

Codex 原稿建议把 tmp 三选一 protocol 正文塞进项目 CLAUDE.md Session Startup 段。Jack 拍板：上提全局 workflow.md §9.d。理由：违反 §3.d「CLAUDE.md 工作流条款逐步瘦身为'详见 workflow.md'」精神——CLAUDE.md 应是短规则 + 指针，不装 protocol 正文。

**否决 4：handoff/README 保留作为 handoff 专属索引（Codex 原方案）**

Codex 原稿主张"待消费"段保留（项目 CLAUDE.md [HARD] 已绑定该落点）。Jack 拍板：原子改 CLAUDE.md 指针 + 删 README。理由：保留会造成 TASK_BOARD「方案完成」状态 + handoff/README「待消费」表两处登记同一 handoff = 真双账本。Codex 自承靠 closeout 检查缓解是把规则成本转嫁给执行者。原子提交（CLAUDE.md 改动 + README 删除同一 commit）消除中间态。

**否决 5：稳定 Capture ID 体系 TD-NNN（Codex 原方案）**

Codex 原稿建议给每条 raw 捕获分配 TD-001 / TD-002 稳定 ID。Jack 拍板：放弃 ID 体系，仅用「来源 + 描述」识别。理由：ID 分配发生在"新债捕获时"，该时刻没有 [HARD] 检查机制保证不冲突；ID 体系无机器化执行点会乱编号或重复。

**否决 6：Active Version Streams 段 + Owner 列（Codex 原方案）**

Codex 原稿在「Version Tasks」上加一层「Active Version Streams」汇总（按 5.1.x / 5.3.x 版本流聚合）+ 每条任务加 Owner 列。Jack 拍板：删，只保留「进行中」单层 +「待拍板」单层。理由：项目 CLAUDE.md「一次只针对一条需求」决定每个版本流当前通常 0-1 个 active 任务，Stream-level 汇总段实际是 Version Tasks 一对一映射；Owner 信息粗粒度（Joint）丢失原始分工，与 §9.a「执行分工表」职责重叠。

## 双 AI 对抗收敛记录

- 双方独立 design 草稿：`tmp/claude-plan-task-board.md` + `tmp/codex-plan-task-board.md`
- 互审 findings：`tmp/claude-review-codex-plan.md`（7 findings，0 blocker / 3 major / 4 nit）+ `tmp/codex-review-claude-plan.md`（4 findings，1 blocker / 2 major / 1 minor）
- 收敛稿：`tmp/converged-plan-task-board.md`
- Codex 终审：`tmp/codex-review-converged.md`（1 major / 0 blocker，裁决 `adopt-with-fixes`，F1 已吸收为 commit 拆分调整）

## 实施摘要

- **完成日**：2026-04-27
- **执行会话**：5.7.1 接手会话（Claude Sonnet 4.6）
- **commits**：
  - `9f5dc7d` — Commit 1（项目原子）：建 TASK_BOARD + history/INDEX，退役 TECH_DEBT_BACKLOG + handoff/README，改 docs/README.md + 项目 CLAUDE.md 4 处
  - dotfiles `719bb81` — Commit 2：workflow.md §9.a/§9.c/§9.d/§9.f 5 处 + settings.json model=sonnet
  - dotfiles `40c4fec` — §9.a 命名规范段残留 handoff/README 引用清理
- **验收口径**：§7 checklist 全勾；grep 验证现役文档无 TECH_DEBT_BACKLOG / handoff/README 残留；dotfiles push 成功
- **与设计思路的偏差**：无
