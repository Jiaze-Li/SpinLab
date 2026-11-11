# SpinLab — 产品架构、路线图与合同资料索引（2026-11-11 外部审核快照）

> 本文件是**原始资料目录和时间点快照**，不是第二份产品权威、技术债看板、任务状态板或新的实施合同。
> **当前指令：外部审核前冻结代码实施、合同重设计、PR 合并及生产数据操作。** 本次只归档现有原文，不代替外部审查。
> 资料整理时采用的 Engineering Lead policy SHA：`490d7c4e88196b3ea60b376041c496488bf8e1ed`（仅本次归档任务）；既有 G0/G1 任务继续沿用自己的冻结 policy SHA，不被此值重写。

## 应从哪里开始

1. **产品和科研含义**：阅读下方 D1–D5；它们是来源决策材料，不各自成为竞争的现行上位合同。
2. **总体目标和执行顺序**：阅读 [D6-A v1.3](planning/SpinLab_D6-A_统一架构基线_v1.3_二审候审稿.md) 与 [D6-B v1.4](planning/SpinLab_D6-B_分阶段实施路线图_v1.4_二审候审稿.md)。两份为二审候审原文，不把候审稿误标为实施通过。
3. **身份与关联基础**：阅读 [G0 v1.4](../library/contracts/spinlab-g0-identity-association-v1.4.md)。原文标题/头部仍写 PENDING，而后续 [G1 handoff](../../handoff/2026-11-11-g1-01-design-review-v0.2.md) 声称其取得历史 DESIGN PASS；**这个出处与文面状态差异需要外部审核独立核实**，本目录不自行签 PASS。
4. **G1 数据安全**：原任务是 [冻结 G1-01 Worker v1.0](../library/contracts/spinlab-g1-01-frozen-worker-v1.0.txt)；[补充设计 v0.4](../library/contracts/spinlab-g1-01-shared-write-delete-design-v0.4.md) 有多轮设计返工，**不是已批准的实施方案**。
5. **进度只以代码与实际证据为准**：参考 GitHub PR #194/#195/#197，不把开放 PR、文字报告、通过的设计审查等同于合并、部署或用户验收。

## A. D1–D5 专题输入（原文字节保留）

| 编号 | 文件 | 科研/产品关注点 | 地位 |
|---|---|---|---|
| D1 | [科研语义 v0.3](decisions/SpinLab_D1_科研语义决策稿_v0.3.md) | Sample、物理量、条件与统一语义 | 专题决策输入；非独立代码授权 |
| D2 | [数据接入 v0.1](decisions/SpinLab_D2_数据接入决策稿_v0.1.md) | Inbox、解析器、通道解释、未知信息 | 专题决策输入；非独立代码授权 |
| D3 | [数据生命周期 v0.1](decisions/SpinLab_D3_数据生命周期决策稿_v0.1.md) | 身份、正式记录、修订和当前采用 | 专题决策输入；非独立代码授权 |
| D4 | [共享分析能力 v0.1](decisions/SpinLab_D4_共享分析能力决策稿_v0.1.md) | Workbench / 可重用科研能力 / 输出 | 专题决策输入；非独立代码授权 |
| D5 | [自动化与 Spin Cat v0.2](decisions/SpinLab_D5_自动化与_Spin_Cat_决策稿_v0.2.md) | 前台自动化、候选与正式隔离 | 专题决策输入；非独立代码授权 |

## B. 三份总体规划 / 基础合同

| 资料 | 版本及原文证据 | 性质 / 审查注意事项 |
|---|---|---|
| [D6-A 统一架构基线](planning/SpinLab_D6-A_统一架构基线_v1.3_二审候审稿.md) | v1.3，38,520 UTF-8 bytes，SHA-256 `b76c4c1ecd8e0ec07c3bd1cf98b9cfb34d03324426f7ea3956001b1dd1cf394e` | 二审候审稿，原始 ZIP 取回；不能替代确切独立批准证据 |
| [D6-B 实施路线图](planning/SpinLab_D6-B_分阶段实施路线图_v1.4_二审候审稿.md) | v1.4，71,843 UTF-8 bytes，SHA-256 `5b533eca8000d6eab0141772ad9d2298c20df6d3bff8027bf5125ee06a6c934e` | 二审候审稿；G0–G5 / T01–T13 与 PR 不是相同层级 |
| [G0 统一身份与数据关联合同](../library/contracts/spinlab-g0-identity-association-v1.4.md) | v1.4，46,620 UTF-8 bytes，SHA-256 `d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8` | 正式候审原文已存于文档分支，历史 Gate 证据需外审核对 |

**重要修订**：D6-A v1.3 / D6-B v1.4 / G0 v1.4 引用了用户较新的 Sample 创建意图原则。旧 D6-A v1.0 / 早期 G0 草案有不同的“科研属性去重”设想，**绝不可直接作为现行要求**。

## C. G1 当前设计、冻结合同及实际代码

| 对象 | 精确引用 | 快照界限 |
|---|---|---|
| G1-01 原冻结实施合同 | [Worker v1.0](../library/contracts/spinlab-g1-01-frozen-worker-v1.0.txt) | AC1–AC6 / S1–S6 不得由补充设计暗改 |
| 最新候审补充设计 | [v0.4](../library/contracts/spinlab-g1-01-shared-write-delete-design-v0.4.md)，`design_ref=sha256:d186e372ab74badb1d873ab510fe555253096626a163557b3c4359ba44250f51` | 最近一次对话内独立 Review 报 DESIGN REWORK（F4-01 / F4-02）；未在本文视为已核准 |
| 前次设计版本 | [v0.2](../library/contracts/spinlab-g1-01-shared-write-delete-design-v0.2.md)、[v0.3](../library/contracts/spinlab-g1-01-shared-write-delete-design-v0.3.md) | 历史返工依据，非候审最新版 |
| G1 交接材料 | [2026-11-11 handoff](../../handoff/2026-11-11-g1-01-design-review-v0.2.md) | 文件名旧后缀、文内候审版 v0.4；记录早于最新 REWORK 反馈 |
| PR #194 — T01 | [代码 PR](https://github.com/Jiaze-Li/SpinLab/pull/194)，HEAD `d29d914b7a19824d822361ed67ea67b322705786` | OPEN，非合并或 T01 验收 |
| PR #195 — G1-01 | [代码 PR](https://github.com/Jiaze-Li/SpinLab/pull/195)，HEAD `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`，base T01 | OPEN，未实现 v0.4 新协议，bot 曾给 REWORK |
| PR #197 — G0/G1 原始文档传输 | [Draft PR](https://github.com/Jiaze-Li/SpinLab/pull/197)，HEAD `975e3677fc180a323331ad22225d43f578d5cb10` | 仅文档；本归档在**新分支**上，不修改 #197 |

## D. 旧版及历史提案（不应误读为最新版）

- [总体架构与专题研究路线 v2](history/SpinLab_总体架构与专题研究路线_v2.md)：D1–D6 前期研究路线，非最新 D6 约束。
- [D6-A v1.0](history/SpinLab_D6-A_统一架构基线_v1.0.md) 和 [D6-B v1.0](history/SpinLab_D6-B_分阶段实施路线图_v1.0.md)：已保留历史原文，用于解释演化原因；不代表当前批准要求。
- 早期 G0 v1.0/v1.1 与 D6-B v1.1 等原始版本仍可在历史文件记录检索，本次未把所有中间编辑稿复制进 GitHub；本索引优先保管**最新完整候审组合与关键起始版本**。

## E. 给外部独立审核者的任务

请先验证上面每份材料的原文 SHA / Git commit，区分用户确认、设计建议、冻结合同与后续实施证据。然后独立裁决：

1. D6-A、D6-B 与 G0 的分层、冲突和权威是否一致，Sample 新建语义是否前后一致？
2. G0→G1→G2→T01 的依赖是否过重或缺失？当前规划是否有可缩减的真实基础？
3. #194/#195 的代码事实、可复用工作与真实验收义务分别是什么？
4. G1 v0.4 的共享写入/恢复设计是否必要，若重设计哪部分可安全简化而不降低原 AC？
5. 工程管理为何多次 DESIGN REWORK 仍无可依赖的基础交付，如何减少合同与 PR 的治理摩擦？

**外部审查应提出自己的判断，不应将既有 ChatGPT / bot 意见当成权威。** PR 状态、HEAD、policy 与 Gate 在实际授权实施前均须重新读取。

## F. 权限与使用方法

本批次只有原文材料归档与目录整理的授权：允许建立独立 GitHub 文档分支、commit、push；**未授权合并、修改已有 PR、修改 Swift 代码或测试、正式数据操作、仓库设置与权限修改**。冻结期间不得以此索引自行启动 G1 或 #194。

文档只保存既有事实/原文与快照，工程技术债仍由仓库唯一 TASK_BOARD 负责，不在此另建生命周期。
