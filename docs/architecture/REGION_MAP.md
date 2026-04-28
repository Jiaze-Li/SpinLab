# Region Map (Working File — 5.1.6 s1)

> **状态**：s1 进行中。本文件是工作产物，含 scan checklist + 6 列文件信息表 + 4 份附录。
>
> s1 完成后「Scan Progress」段删除，附录 A–D 拆出独立文档；本文件留作 s2 输入；最终 s4 收敛产出 `INDEX.md`。

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

## 6 列填表规范（s1 主产出）

每文件一行，6 个字段：

| 字段 | 写什么 | 取值范围 / 例子 |
|---|---|---|
| **文件** | 相对 `Sources/SpinLabApp/` 的路径 | `App/State/InboxFeatureStore.swift` |
| **区块** | 5 区块之一或暧昧 | Inbox / Library / Workbench / Rules / 跨区 / `[暧昧]` |
| **行数** | swift 文件行数 | 整数（先扫 `wc -l` 一次出全表） |
| **共享候选** | 是否疑似跨区共享 | ⭐ 标记（依据：import 多区块类型 / 文件名含 Coordinator・Orchestrator・Bridge・Facade / `extension AppState` 等）；不是留空 |
| **TODO 数** | 文件内 TODO/FIXME/XXX 注释数 | 整数（无则 0）；具体内容写入附录 C |
| **测试** | 是否存在对应测试 | ✅ / ❌（按文件名约定 `Tests/SpinLabAppTests/` 下查 `*FileNameTests.swift` 或同主题前缀测试） |

附加注释（一句话职责）写在表格行后或附注里，不挤进 6 列。

---

## Scan Progress

> 每扫完一个目录，把 `[ ]` 翻 `[x]` 并把该目录文件填入下方对应区块段。会话中断后下次继续从未翻的项开始。

### 预备步骤（s1 起手必做）

- [ ] 一次性跑 `wc -l` 全 swift 文件，落表得「行数」列底数
- [ ] 一次性 grep `TODO|FIXME|XXX` 全 swift 文件，得 TODO 行数 + 具体行写入附录 C
- [ ] 列出 `Tests/SpinLabAppTests/` 现存测试文件清单，作为「测试」列查询底数

这三步前置完成后，扫每文件时只剩"区块判断 + 共享候选嗅探"，每文件 30–60 秒。

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
| 共享候选 | 0 |
| 死代码可疑 | 0 |

---

## File Region Assignments

> 6 列宽表。每段一个区块。暧昧 / 未确定单独段。

### Inbox

| 文件 | 行数 | 共享 | TODO | 测试 |
|---|---|---|---|---|

_(待填)_

### Library

| 文件 | 行数 | 共享 | TODO | 测试 |
|---|---|---|---|---|

_(待填)_

### Workbench

| 文件 | 行数 | 共享 | TODO | 测试 |
|---|---|---|---|---|

_(待填)_

### Rules

| 文件 | 行数 | 共享 | TODO | 测试 |
|---|---|---|---|---|

_(待填)_

### 跨区共享

| 文件 | 行数 | 共享 | TODO | 测试 |
|---|---|---|---|---|

_(待填)_

### `[暧昧]` 清单（s2 第二轮判断）

| 文件 | 候选区块 | 行数 | 暧昧原因 |
|---|---|---|---|

_(待填)_

### `[未确定]` 清单（s2 后入中期债条目候选）

_(s2 后填)_

---

## 附录 A — 大文件清单（行数 > 500）

> s1 起手前置步骤产出。s4 收敛时拆出独立文档，作为中期拆文件立项依据。

| 文件 | 行数 | 区块 | 备注 |
|---|---|---|---|

_(待填)_

## 附录 B — 共享候选清单

> 跨区共享疑似项。s3 起步直接从此清单扫。

| 文件 | 嗅探信号 | s3 实证状态 |
|---|---|---|

_(待填)_

## 附录 C — TODO / FIXME / XXX 收割

> 一次性 grep 全 swift 文件产出。中期债条目候选库。

| 文件 | 行号 | 类别 | 内容 |
|---|---|---|---|

_(待填)_

## 附录 D — 测试覆盖盲区清单

> s1 顺手记录"无对应测试"的关键文件。5.1.3 测试基础设施的延续输入。

| 文件 | 区块 | 行数 | 优先级 |
|---|---|---|---|

_(待填)_

## 附录 E — 死代码可疑清单

> 读 s1 时遇到"看不出谁在用"的类型 / 文件，标记后用 `grep -r` 一行验证。

| 文件 / 类型 | 验证状态 | 中期处理建议 |
|---|---|---|

_(待填)_
