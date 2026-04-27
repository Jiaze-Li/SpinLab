# Task Board — 全局任务总览

> **职责**：跨版本展示当前所有进行中 / 待规划任务的流水线状态。一句话 + 状态 + 指针，仅此而已。
>
> **不装**：
> - 设计思路 → `V5_ROADMAP.md`（进行中条目）/ `history/v*_*.md`（已归档）
> - 实施方案 → `handoff/<file>.md`（待消费）/ `handoff/archive/<file>.md`（已执行）
> - 验收摘要 + commit 哈希 → `history/v*_*.md` 实施摘要段 + `history/INDEX.md` 索引
>
> **维护规则**：见 `~/.claude/docs/workflow.md §9.f` 触发表。

## 进行中

| 版本 | 一句话 | 状态 | 指针 |
|---|---|---|---|
| 5.1.5 | 规则管理统一 + 自动同步基础设施 (s1-s7 已完成) | 需求提出 (s8) | [V5_ROADMAP §5.1.5](V5_ROADMAP.md) |
| 5.1.6 | Codex 派发提速基建（杠杆 A/B/C + 重构方案设计） | 需求提出 | [V5_ROADMAP §5.1.6](V5_ROADMAP.md) |
| 5.7.1 | TASK_BOARD 引入 + 文档治理重构 | 方案执行中 (5.7.1) | [handoff/2026-04-26-5.7.1-task-board-introduction.md](handoff/2026-04-26-5.7.1-task-board-introduction.md) |

## 待拍板

| 来源 | 描述 | code pointer |
|---|---|---|
| Round E | LibraryStore try? audit 剩余项（createDirectory + read paths 仍 try? 静默吞错；目标态：stderr 落日志或 throw；effort: low）| `Sources/SpinLabApp/Library/LibraryStore.swift` |
