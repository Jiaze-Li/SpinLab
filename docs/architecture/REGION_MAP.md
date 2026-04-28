# Region Map (Working File — 5.1.6 s1)

> **状态**：s1 进行中。本文件是工作产物，含 scan checklist + 文件归属表。
>
> s1 完成后「Scan Progress」段删除，本文件成为 s2 输入；最终 s4 收敛产出 `INDEX.md`。

---

## Region Definitions

| 区块 | 定义 |
|---|---|
| **Inbox** | 文件导入 + 解析 + 路由 + 用户审核 + 归档动作。包含 Import 5 阶段管线、Confirm 流程、Inbox UI、Apply 归档。 |
| **Library** | 已归档 measurement 的浏览 / 编辑 / 持久化。包含 Library UI、measurement detail / metadata 编辑、registry 同步、Library 下文件持久化。 |
| **Workbench** | 单一 measurement 的可视化与分析。包含 Workbench UI、3ω / XY rotation / AHE workflow、Plot Shell、render pipeline、analysis pack 保存。 |
| **Rules** | 规则数据 + 规则管理面板。5 本子 schema、RuleLoader、RulesBootstrapper、RulesSyncEngine、RulesPanel UI。 |
| **跨区共享** | 被 2+ 区块重度消费的文件（删掉多区块同时坏）。包含 AppState、AppEnvironment、UI shell（AppColumnShell / HoverPopoverModifier）、cross-feature service / use case、Domain types、Persistence 基础设施。 |
| **`[暧昧]`** | s1 单凭文件名 + 顶部内容判断不出归属，留待 s2 第二轮按消费者关系收敛 |
| **`[未确定]`** | s2 仍判断不出，进入未来债条目候选 |

## 判断默认动作

1. 看消费者归属，不看代码物理目录（消费侧多归多消费区块）
2. 双消费 → 跨区共享
3. 判断不出 → `[暧昧]`，**不停下纠结**，继续走
4. 一律先填一行，留痕优先于精确

---

## Scan Progress

> 每扫完一个目录，把 `[ ]` 翻 `[x]` 并把该目录文件填入下方对应区块段。会话中断后下次继续从未翻的项开始。

### Top-level（Sources/SpinLabApp 下）

- [ ] `App/` (29 swift)
- [ ] `App/State/` (14)
- [ ] `Domain/` (4)
- [ ] `UseCases/` (30)
- [ ] `UI/` (7)
- [ ] `Extensions/` (1)
- [ ] `Repositories/` (1)
- [ ] `Storage/` (4)
- [ ] `Persistence/` (1)
- [ ] `Registry/` (4)
- [ ] `Workflow/` (4)
- [ ] `Library/` (13)
- [ ] `Workbench/` (0 顶层 + V3 子目录)
- [ ] `Workbench/V3/` (16)
- [ ] `Import/` (2 顶层)
- [ ] `Import/Parse/` (4)
- [ ] `Import/Route/` (3)
- [ ] `Import/Match/` (1)
- [ ] `Import/Evaluate/` (3)
- [ ] `Import/Presentation/` (1)
- [ ] `Import/Rules/` (12)
- [ ] `Features/Inbox/` (6)
- [ ] `Features/Library/` (19)
- [ ] `Features/Workbench/` (24)
- [ ] `Features/RulesPanel/` (5)
- [ ] `Features/RulesPanel/Sections/` (5)
- [ ] `Features/RulesPanel/Components/` (4)
- [ ] 顶层 `SpinLabApp.swift`（入口）

**总计**：217 swift 文件 / 27 目录条目（含顶层入口）。

### 进度统计（每会话末尾更新）

| 维度 | 数值 |
|---|---|
| 已扫目录 | 0 / 27 |
| 已填文件 | 0 / 217 |
| 暧昧条目 | 0 |

---

## File Region Assignments

> 每文件一行：`- 文件名 — 一句话职责`。暧昧条目放最后段。

### Inbox

_(待填)_

### Library

_(待填)_

### Workbench

_(待填)_

### Rules

_(待填)_

### 跨区共享

_(待填)_

### `[暧昧]` 清单（s2 第二轮判断）

_(待填，每行格式：`- 文件名 — 候选区块: A / B — 暧昧原因`)_

### `[未确定]` 清单（待入中期债条目候选）

_(s2 后填)_
