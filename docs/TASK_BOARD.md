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
| 5.1.5 | 规则管理统一 + 自动同步基础设施 (s1-s9 已完成；s10 重开：Sample Identification 面板二次简化) | 方案完成 (s10(2)) | [s10(2) handoff](handoff/2026-04-27-5.1.5-s10-substrate-redesign.md) |
| 5.1.6 | Codex 派发提速基建（杠杆 A/B/C + 重构方案设计） | 需求提出 | [V5_ROADMAP §5.1.6](V5_ROADMAP.md) |

## 待拍板

| 来源 | 描述 | code pointer |
|---|---|---|
| Round E | LibraryStore try? audit 剩余项（createDirectory + read paths 仍 try? 静默吞错；目标态：stderr 落日志或 throw；effort: low）| `Sources/SpinLabApp/Library/LibraryStore.swift` |
