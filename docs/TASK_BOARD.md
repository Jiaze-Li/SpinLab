# Task Board — 全局任务总览

> **职责**：跨版本展示当前所有进行中 / 待规划任务的流水线状态。一句话 + 状态 + 指针，仅此而已。
>
> **不装**：
> - 设计思路 → `V5_ROADMAP.md`（进行中条目）/ `history/v*_*.md`（已归档）
> - 实施方案 → `handoff/<file>.md`（待消费）/ `handoff/archive/<file>.md`（已执行）
> - 验收摘要 + commit 哈希 → `history/v*_*.md` 实施摘要段 + `history/INDEX.md` 索引
>
> **维护规则**：见本文件末尾「维护规则」段。

## 进行中

| 版本 | 一句话 | 状态 | 指针 |
|---|---|---|---|
| 5.1.5 | 规则管理统一 + 自动同步基础设施 (s1-s10 已完成；s11 追加：三个匹配本子 UI + 字段命名统一) | 方案完成 (s11-design) | [handoff/2026-04-27-s11-design.md](handoff/2026-04-27-s11-design.md) |
| 5.1.6 | Codex 派发提速基建（杠杆 A/B/C + 重构方案设计） | 需求提出 | [V5_ROADMAP §5.1.6](V5_ROADMAP.md) |
| 5.1.7 | 规则产物可演化层（rule provenance + sidecar v2 双层 + Recompute） | 需求提出 | [V5_ROADMAP §5.1.7](V5_ROADMAP.md) |

## 待拍板

| 来源 | 描述 | code pointer |
|---|---|---|
| Round E | LibraryStore try? audit 剩余项（createDirectory + read paths 仍 try? 静默吞错；目标态：stderr 落日志或 throw；effort: low）| `Sources/SpinLabApp/Library/LibraryStore.swift` |

---

## 维护规则

与全局 `~/.claude/docs/workflow.md §9.a / §9.b / §9.c` 联动维护：

| 触发动作 | 总览文件动作 |
|---|---|
| 新债 / raw 捕获 | 「待拍板」段加行 |
| Jack 拍板归入 ROADMAP 版本段 | 「待拍板」段删行 + 「进行中」段加行（状态 =「需求提出」）|
| handoff 落盘（`workflow.md §9.a`） | 状态翻「方案完成 (s<n>)」+ 指针列改指 handoff 文件 |
| 接手会话第一次 commit 落地（`workflow.md §9.b`） | 状态翻「方案执行中 (s<n>)」 |
| 所有 handoff 归档完成（`workflow.md §9.c`），ROADMAP 标 `[x]`，但 Jack 未给明确验收收尾指令 | 状态翻「验收中 (YYYY-MM-DD)」，日期取 ROADMAP 标 `[x]` 当天 |
| Jack 明确给出验收通过指令 | 整行删 + 永久归档索引加一行（`docs/history/INDEX.md`）|

**重做规则**：执行中冒出 handoff 未覆盖的设计问题 → 按 `workflow.md §9.b` 停下报 Jack → Jack 显式指挥触发重做（作废旧 handoff / 出新 handoff）。AI 不自行回退状态。

**Sanity check（[HARD]，§9.c 收尾后执行）**：归档 5 步完成后必须运行 `ls docs/handoff/` 自检——现役区应只剩刚出未消费的 handoff 文件；如发现 ROADMAP 已 `[x]` 的条目对应 handoff 仍在现役区，说明 §9.c 第 1 步（git mv 到 archive/）遗漏，立即补做。
