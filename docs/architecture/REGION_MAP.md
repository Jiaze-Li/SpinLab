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
5. 看到平行实现疑似（不同 workflow / 区块写同一件事）或 shell 内部疑似肥大（单文件多职责） → 标 ⭐G + 简短说明，**不立即抽象**，候选只入附录 G。哲学条款见 [`docs/philosophy.md` Shell & Composition Philosophy](../philosophy.md)

## 暧昧比例预警

每会话结束统计每区块的 `[暧昧]` 比例（含未归属未填）：
- 任一区块 `[暧昧]` 比例 > 20–25% → **必须停下补一轮抽样校准定义**，不要继续扩大误差
- 全表 `[暧昧]` 比例 > 15% → 检查区块定义本身是否粒度不对

---

## 9 列填表规范（s1 主产出）

每文件一行，9 个字段：

| 字段 | 写什么 | 取值范围 / 例子 |
|---|---|---|
| **文件** | 相对 `Sources/SpinLabApp/` 的路径 | `App/State/InboxFeatureStore.swift` |
| **区块** | 5 区块之一或暧昧 | Inbox / Library / Workbench / Rules / 跨区 / `[暧昧]` |
| **归属依据** | 为什么归到这个区块（s2 回扫的审计字段）| 短标签：`consumer: Inbox+Rules` / `appstate extension` / `filename-only` / `inline-doc` / `[猜测]` |
| **层级预判** | 显然层级（s1 不要求精确，捕捉到就填）| UI / Store / UseCase / Repository / Domain / Parser / `[待 s2]` |
| **行数** | swift 文件行数 | 整数（先扫 `wc -l` 一次出全表）|
| **共享候选** | 是否疑似跨区共享 | ⭐ + 短标签（如 `⭐ consumer:I+L+W`）；不是留空 |
| **平行候选** | 是否疑似平行实现 / shell 内部肥大（写入附录 G）| ⭐G + 短标签（如 `⭐G H:与 ThreeOmegaXxx 平行` / `⭐G V:疑似 1500 行多职责`）；不是留空 |
| **TODO 数** | 文件内 TODO/FIXME/XXX 注释数 | 整数（无则 0）；具体内容写入附录 C |
| **测试** | 直接测试线索 | `direct` / `behavioral` / `none`（按文件名约定查 Tests/ 直接测试 → direct；只有同主题行为测试 → behavioral；查不到 → none，s2/s4 再补行为映射）|

附加注释（一句话职责）写在表格行后或附注里，不挤进 9 列。

---

## Session Plan（s1 三会话拆分）

> 总工时估 7–8.5 h，分 3 会话。每会话独立可交付，断点不留半成品。

| 会话 | 范围 | 文件数 | 估时 | 交付里程碑 |
|---|---|---|---|---|
| **s1.a** | 锚点（先停） → Inbox 全栈 | 67 | 2.5–3 h | **两个检查点**：(1) Domain / App / App/State 锚点完成 + 写 5–8 条归属判例（"为什么这个文件归 X 区块"的范例）→ 确认锚点稳；(2) 进入 Inbox 全栈。锚点不稳就停 s1.a，回头校准区块定义 |
| **s1.b** | Library + Workbench | 76 | 2.5–3 h | Library + Workbench 区块完成；Workflow 顺手处理 |
| **s1.c** | Rules + 基础设施 + 收尾 | 75 + 暧昧回扫 | 2–2.5 h | Rules 全栈完成；UseCases / UI / Extensions / Repositories / Storage / Persistence / Registry 完成；暧昧条目第二轮收敛；s1 验收 |

### s1.a 范围（按目录）

`Domain/` (4) + `App/` (29) + `App/State/` (14) + `Import/` 顶层 (2) + `Import/Parse/` (4) + `Import/Route/` (3) + `Import/Match/` (1) + `Import/Evaluate/` (3) + `Import/Presentation/` (1) + `Features/Inbox/` (6) = **67 文件**

### s1.b 范围（按目录）

`Library/` (13) + `Features/Library/` (19) + `Workbench/V3/` (16) + `Features/Workbench/` (24) + `Workflow/` (4) = **76 文件**

### s1.c 范围（按目录）

`Import/Rules/` (12) + `Features/RulesPanel/` (5) + `Features/RulesPanel/Sections/` (5) + `Features/RulesPanel/Components/` (4) + `UseCases/` (30) + `UI/` (7) + `Extensions/` (1) + `Repositories/` (1) + `Storage/` (4) + `Persistence/` (1) + `Registry/` (4) + 顶层 `SpinLabApp.swift` (1) = **75 文件** + 暧昧回扫

### 跨会话承接规则

每会话结束前：
1. Scan Progress 已扫目录的 `[ ]` 翻 `[x]`
2. 更新「进度统计」表
3. 没扫完的目录标"部分完成 (X/Y)"，记断点

下次会话开始：
- 全 `[x]` 跳过；`[ ]` 从头开始；"部分完成"从断点续

### 每会话结束的 commit 模板

```
docs(s1.x): REGION_MAP <主题> 扫描完成

- N 文件归属表填毕（含 <批次范围>）
- 暧昧条目 X / 共享候选 Y / 死代码可疑 Z
```

---

## Scan Progress

> 每扫完一个目录，把 `[ ]` 翻 `[x]` 并把该目录文件填入下方对应区块段。会话中断后下次继续从未翻的项开始。

### 预备步骤（s1.a 起手必做，仅一次）

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
| 暧昧条目 | 0（全表 0%；任一区块 > 20–25% 触发停下校准）|
| 共享候选 | 0 |
| 平行候选（附录 G） | 0（横向 H + 纵向 V 合计；目标 ≥ 5）|
| 死代码可疑 | 0 |

---

## File Region Assignments

> 6 列宽表。每段一个区块。暧昧 / 未确定单独段。

### Inbox

| 文件 | 归属依据 | 层级预判 | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|

_(待填)_

### Library

| 文件 | 归属依据 | 层级预判 | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|

_(待填)_

### Workbench

| 文件 | 归属依据 | 层级预判 | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|

_(待填)_

### Rules

| 文件 | 归属依据 | 层级预判 | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|

_(待填)_

### 跨区共享

| 文件 | 归属依据 | 层级预判 | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|

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

## 附录 F — 近期变更热点（可选，s4 补，不阻塞 s1）

> 中期债项排序需要同时考虑结构风险（共享 / 行数 / TODO）和变更概率。
>
> 数据来源：`git log --since=<3-6 months ago> --name-only -- Sources/SpinLabApp` 统计文件触达次数。
>
> s1 期间不做（s1 禁止读 git）；s4 收尾时若时间允许补上。

| 文件 | 近 N 月触达次数 | 区块 | 与"高风险共享"重合度 |
|---|---|---|---|

_(s4 可选填)_

## 附录 G — Shell 化候选清单（横向 H + 纵向 V）

> 对应 [`docs/philosophy.md` Shell & Composition Philosophy](../philosophy.md) 的产出落点。
> 对应 ROADMAP §5.1.6 顶层原则 #4 + AG7。
>
> 两类候选并列：
> - **横向 H**：平行实现未抽 shell（不同 workflow / 区块各自写同一件事）→ 候选抽出共享 shell
> - **纵向 V**：shell 已存在但内部肥大（单文件多职责）→ 候选拆内部模块
>
> s1 期间只识别 + 简短说明，**不立即抽象**。中期版本独立立项评估。

| ID | 类型 | 当前形态 | 建议形态 | 平行 / 肥大点 | 风险 / 备注 |
|---|---|---|---|---|---|
| G-001 | H | 三 workflow 各写 `_applySeriesOrder` 等 4 个 protocol 方法 | 抽到 `WorkbenchWorkspaceProviding` default extension | 3ω / XY / AHE store | 5.3.6 观察已记录，等第三 workflow opt-in（TASK_BOARD 待拍板段）|

_(s1 扫描时持续追加。每条 ID 编号，类型 H / V，候选形态精简描述。)_

### 样板参照

- **横向 H 样板**：v5.1.5-s12 `UnifiedMatchRuleEditor` —— 5 处匹配 UI + 4 操作集封闭单壳化
- **横向 + 纵向（H+V）样板**：`WorkbenchPlotCanvas` —— 提供画图能力给 3 workflow（H）；intent 是内部按 title / grid / legend / font / copy-PNG 分层（V，需 s1 实地验证）
