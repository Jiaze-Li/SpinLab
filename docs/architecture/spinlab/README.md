# SpinLab — 架构资料单一阅读入口（外部独立审核冻结快照）

> **资料整理，不是新的上位合同。** 本目录固定原文与版本关系；不批准实施、迁移、删除正式数据或合并 PR。当前状态：**FROZEN / EXTERNAL AUDIT PENDING**。
> 本批归档工程治理 policy_sha：`490d7c4e88196b3ea60b376041c496488bf8e1ed`。已有 G0 / G1 / 新数据库任务各自使用原冻结 policy_sha，不因此变更。

> **2026-11-11 审核后续：** 对本目录材料的审核结论、用户当天确认的三项决定和建议顺序见 [收敛计划](planning/SpinLab_收敛计划_2026-11-11.md)。下文各份原文及其状态描述保持冻结时的样子，未改动。

## 1. 真正需要先读的材料

| 顺序 | 材料 | 职责与状态 |
|---|---|---|
| 1 | [D6-A 统一架构基线 v1.3](planning/SpinLab_D6-A_统一架构基线_v1.3_二审候审稿.md) | 产品、领域边界和主要不变量；二审候审原文，38,520 字节，SHA-256 `b76c4c1ecd8e0ec07c3bd1cf98b9cfb34d03324426f7ea3956001b1dd1cf394e` |
| 2 | [D6-B 分阶段路线图 v1.4](planning/SpinLab_D6-B_分阶段实施路线图_v1.4_二审候审稿.md) | G0–G5、T01–T13 的依赖与验收；二审候审原文，71,843 字节，SHA-256 `5b533eca8000d6eab0141772ad9d2298c20df6d3bff8027bf5125ee06a6c934e` |
| 3 | [G0 统一身份与数据关联合同 v1.4](../library/contracts/spinlab-g0-identity-association-v1.4.md) | 永久身份、旧别名、关联、权威和删除保护；SHA-256 `d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8` |
| 4 | [**新数据库简化架构合同 v0.2**](contracts/SpinLab_新数据库简化架构合同_v0.2_设计候审稿.md) | **未来新模型**的当前 Parameter、Live Result/Plot、显式 Snapshot 和必要保留；SHA-256 `e42a25848fa28e25bc7f47d70d0b0624dcbbde7b4d3ae27942c652527cf0a5d8` |

**必须区分：** G0 v1.4 头部依然保留交审前的 PENDING；后续交接和会话记载其历史 DESIGN PASS，但应以独立审查原始证据核对。新数据库 v0.2 的原文也是交审前 PENDING；历史独立复审会话记载 v0.2 **DESIGN PASS**，但本次恢复的二审 ZIP **不包含 Reviewer 原始签署结果**，不能把会话转述当成独立复核的原始证据。以上结论都**不是代码 PASS**。

**两份设计合同不是彼此重复：** G0 保留 Sample、Source、Dataset、Result/Plot 的身份及可靠关联底线；新数据库 v0.2 对**将来显式选择新模型的消费者**提出简化数据生命周期。不追溯修改 G1-01、PR #194/#195、已冻结合同或旧库。新数据库主张的“Parameter 只有当前值、Live 与 Snapshot 分离”与 G0/D6 早期的日常 Observation/Revision/Adopt 模型有明确范围差异；未来任务卡必须先显式按版本修订，不得把冲突规则同时套在一个任务上。

## 2. G1 安全任务：保留一份原合同、一份最新候审补充设计

| 资料 | 用途与证据 |
|---|---|
| [G1-01 冻结 Worker v1.0](../library/contracts/spinlab-g1-01-frozen-worker-v1.0.txt) | 原 S1–S6 / AC1–AC6，不因后续候审设计修改 |
| [G1-01 补充设计 v0.4](../library/contracts/spinlab-g1-01-shared-write-delete-design-v0.4.md) | `design_ref=sha256:d186e372ab74badb1d873ab510fe555253096626a163557b3c4359ba44250f51`；最近一轮独立复审结论为 DESIGN REWORK，**没有实施授权** |
| [G1 先前 v0.2/v0.3](../library/contracts/) | 供追溯历史 Finding，**不是当前候审版** |
| [G1 原交接文件](../../handoff/2026-11-11-g1-01-design-review-v0.2.md) | 已早于最新审核结果；不能把其 PENDING 当最新 Gate 结论 |

## 3. D1–D5：只保留具有独有价值的专题参考

| 保留 | 独有价值 | 使用边界 |
|---|---|---|
| [D2 数据接入 v0.1](decisions/SpinLab_D2_数据接入决策稿_v0.1.md) | PPMS/LVM 通道和实验解释、未知信息与来源规则等具体实验约定 | D6-A/G0 未逐字替代的领域案例，供未来 G4/T06/T09 核对；不是现行总合同 |
| [D4 共享分析能力 v0.1](decisions/SpinLab_D4_共享分析能力决策稿_v0.1.md) | AFM/AHE 科研计算输入、方法、有效配置和 Workbench 边界案例 | 研究依据及建议，不当成已验证算法 |
| [D5 自动化 v0.2](decisions/SpinLab_D5_自动化与_Spin_Cat_决策稿_v0.2.md) | 前台可见流程、标准数据出发点、候选/正式隔离和 Spin Cat 的产品工作流 | 未来自动化消费者的参考，不当成已实现功能 |

**从当前分支移除：** D1 v0.3、D3 v0.1；它们包含与后续 G0 / 新数据库合同不一致或已被承接的早期规则（例如按科研属性强制判定同一 Sample、日常 Parameter 修订历史）。不作为现行依据。**原文保留在此前不可变 Git commit** `3fb69e01139297a39e891d758480238cf5ebedd3`，需要追溯时仍可只读访问；没有抹去 Git 历史。

## 4. 历史材料与当前仓库事实

- [前期总体研究路线 v2](history/SpinLab_总体架构与专题研究路线_v2.md)、[D6-A v1.0](history/SpinLab_D6-A_统一架构基线_v1.0.md)、[D6-B v1.0](history/SpinLab_D6-B_分阶段实施路线图_v1.0.md) 仅作演化和审计参考，**不是现行约束**。
- [PR #194 / T01](https://github.com/Jiaze-Li/SpinLab/pull/194)：Sample 创建代码，冻结 HEAD `d29d914b7a19824d822361ed67ea67b322705786`，仍须原合同/下游验收。
- [PR #195 / G1-01](https://github.com/Jiaze-Li/SpinLab/pull/195)：叠在 T01 上，冻结 HEAD `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`；历史 bot REWORK，不是代码 PASS。
- [PR #197](https://github.com/Jiaze-Li/SpinLab/pull/197)：原 G0/G1 文档 Draft PR；本归档属于**另一个文档分支**，未修改它。
- 本目录不是任务板，现行技术债仅使用仓库的共享 `docs/TASK_BOARD.md` 及其真实权威位置。

## 5. 外部审查应重点裁决什么

请核对每份文件原文和设计 Gate 证据，独立判断：D6-A / D6-B / G0 / 新数据库 v0.2 是否构成一致的**可执行的分层体系**；现行 G1→G2→T01 是否存在不必要的安全基础前置；#194/#195 真实可复用范围；G1 的最小可证安全架构；现行多轮设计审查的成本、停滞原因与下一步**唯一有效交付**。外部评估只读，不得因为该目录已存在便自动恢复开发。

## 6. 权限

本次仅整理已批准的文档分支和目录索引，未更改原始设计正文；不修改 `main`、已有 PR、Swift 代码、测试、正式科研数据或仓库权限，不合并任何 PR。新数据库合同保留原 `policy_sha=3534b1379409f7d076a07de966133b05f1cd3df2`，不以归档过程的新 policy_sha 覆盖。
