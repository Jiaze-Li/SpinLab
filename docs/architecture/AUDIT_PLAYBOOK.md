# Workbench 边界合规审计 Playbook

> 首次执行：5.1.11a（2026-05-02）。本文记录可复用流程，下次审计照此走。

## 1. 审计触发条件

每个 Workbench 大版本（x.y.0 或专项重构轮）结束后触发一次。触发信号：
- Workbench region 有 ≥3 个文件净新增/重命名，或
- 任一 SP-* boundary rule 涉及文件有 commit

## 2. Step 0 — 抽样池构造

1. 对每层 Code Map 文件 `grep -c "^- \`" <file>` 统计条目数
2. 去重（WORKFLOW_CONTRACTS.md Core files 节重复）得唯一文件数
3. 按层配额（Shell≤13, Workflow≤16, Render≤4, Persistence≤8, Search≤2, Ext≤1）构造入样表
4. 强制纳入信号：SP-*/G-* 命中文件、churn top-5（`git log --oneline <branch> -- Sources/SpinLabApp/` 计）、层代表性
5. 封闭后锁定 Sample ID（AS-01..N），不再扩展

Codex challenge §0 产出表（建议 24h 内完成）；Codex 若有异议须含代码证据；采纳后重发 commit。

## 3. 审计双 Lens

每个 AS-ID 走两步：

**Step B — call-chain lens**  
从 AS-ID 文件找 public API / init / stored properties，向外追一跳（谁调它 / 它调谁），写下 caller→callee→行为描述。

**Step C — 18 信号逐一过滤**  
| # | 信号 | 违反规则 |
|---|---|---|
| 1 | @Observable setter 含副作用（写文件/触发 task/UserDefaults） | setter 无副作用 |
| 2 | UI 文件含排序/过滤/归一化逻辑 | View 不含 sort/filter/normalize |
| 3 | Parser 调 Service/Repository | Parser 不调 Service/Repository |
| 4 | Service/UseCase 含 import SwiftUI | Services/UseCases 无 SwiftUI |
| 5 | Repository/Store 含业务策略分支 | Repository 只 CRUD |
| 6 | 静默 try? 在 service/repository/storage 层 | 不静默丢弃 error |
| 7 | AppState 方法含 async/await | AppState 方法同步 |
| 8 | ViewModel 拥有 canonical domain model | ViewModel 只 transient UI state |
| 9 | feature state 直挂 AppState raw property（非 FeatureStore） | 经 FeatureStore |
| 10 | observable store 不是 @MainActor @Observable final class | 必须此形态 |
| 11 | ObservableObject/@Published/Combine 状态流 | 只用 @Observable |
| 12 | Repository 用非 AsyncStream 推送变更 | AsyncStream+Continuation |
| 13 | 重 I/O 直接在 @Observable 类方法体内 | 重 I/O 在 data actor |
| 14 | @Observable 类方法标 async | @Observable methods 不 async |
| 15 | 运行时副作用依赖未经 AppEnvironment 注入 | 经 AppEnvironment |
| 16 | UseCase 持有 storage 细节/state | UseCase stateless struct |
| 17 | Domain model 定义在 Features/ 而非 Domain/ | Domain models 在 Domain/ |
| 18 | View 接收 AppState 通过 init 参数 | @Environment 接收 AppState |

命中 → Violation（附信号编号 + High/Med/Low + 行为描述）  
未命中 → Accepted Boundary 或 Drift（Code Map 注释过时）

## 4. 三分类产出

| 分类 | 定义 | 产出段 |
|---|---|---|
| Violation | 信号命中，代码须改 | §1 |
| Drift | Code Map 注释与实现偏离 | §2（立即 commit 修正）|
| Accepted Boundary | 跨区但有意为之（architecture decision） | §3 |

## 5. 双 AI 分批结构

| 批次 | 层 | 主审方 | 评审方 |
|---|---|---|---|
| Batch 1 | Shell + Render | Claude | Codex |
| Batch 2 | Workflow（可拆 2a/2b）| Codex | Claude |
| Batch 3 | Persistence + Search + Extension | Claude | Codex |

评审方规则：100% Violation challenge + 100% SP-*/G-* 复核 + 非 SP-G 样本 ≥30% 随机抽查。

## 6. next_action 分类准则

| 值 | 含义 | 典型场景 |
|---|---|---|
| `11b` | 进当前 fix 轮（Workbench 内 single/multi commit）| try? 修正、View filter 移至 store、domain model 归位 |
| `14a` | 跨区 meta，留 5.1.14a 收敛 | DI bypass（需 AppEnvironment capability protocol）、跨 region storage 注入 |
| `no-fix-accepted` | 违规形态轻微或有正当理由，不修 | 纯计算 helper 内建实例、已建立的 renderer config 持有模式 |
| `defer-to-G-track` | G-* 大文件，留 G-track 拆分轮 | G-002/G-007/G-008 等 |

**判定规则**：fix 仅涉及一个 Workbench 层且 commit scope 可控 → `11b`；需新增 capability protocol 或跨 region storage 接口 → `14a`。

## 7. §4.3 收尾对账（4 项）

1. 所有 N 条 AS-ID 有分类结论
2. Drift §2 每条有 commit_id
3. Cross-Region Doubts §4 字段完整
4. Fix-Round Draft §5 填入（next_action 分布已校对）

全部通过后：审计轮封闭 → 归档 → ROADMAP checkbox。

## 8. 归档步骤

```
git mv docs/handoff/YYYY-MM-DD-workbench-audit.md docs/handoff/archive/
# 在 docs/history/INDEX.md 加一行
# 在 V5_ROADMAP.md 对应 checkbox 改 [x]
# 在 docs/TASK_BOARD.md 删行（Jack 验收后）
```

## 9. Adj-10（Persistence fail-soft 批准模式）

Persistence layer 允许 fail-soft（collapse error → nil + stderr log），只要：
1. file-not-found 是预期场景（返回 nil 不记日志）
2. 其他 error（corrupt/decode fail）须 stderr 记录
3. 不静默覆盖可恢复数据（AS-36 反例）

`try?` 折叠所有 error 为 nil 且无日志 → 违反 Adj-10 → Violation #6。
