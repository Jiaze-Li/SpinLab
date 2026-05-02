# Inbox 边界合规审计 — 产出表

> **执行 handoff**: `docs/handoff/2026-05-02-5.1.12a-s1-design.md`
> **Step 0 完成**: 2026-05-02（Claude 方）
> **Batch 1 完成**: 2026-05-02（Claude 主审，0 Violation）
> **Batch 2 完成**: 2026-05-02（Codex 主审 / Claude 评审，9 Violation，2 challenge 驳回）
> **当前状态**: 审计完成，待 §4.3 收尾对账

---

## 0. 抽样池 / Audit Sample

### 基线统计

| 层 | 文档 | Code Map 条目（awk 口径） |
|---|---|---:|
| Routing | ROUTING_PIPELINE.md | 19 |
| Rules | RULES_AUTHORING.md | 23 |
| ConfirmApply | CONFIRM_AND_APPLY.md | 16 |
| Output | OUTPUT_CONTRACTS.md | 10 |
| **合计** | | **68** |

### Step 0 复算结果

| 复算项 | 结果 | 与 s1 设计比对 |
|---|---|---|
| Code Map 基线（awk 口径） | 19+23+16+10 = **68** | ✓ 一致 |
| G-* 候选（≥800L） | `RulesBootstrapper.swift` 1203L（**G-001**）、`FilenameRuleSet.swift` 919L（**G-002**） | s1 估 0–2 ✓ |
| 高 churn ≥5（AM，`1409782..HEAD`） | FilenameRuleSet:14 / MeasuringConditionSection:10 / SampleIdentificationSection:7 / MatchRulesEditor:7 / WorkflowSection:6 / RulesSectionShell:6 / RuleRef:5 | ✓ 与 §1.3 完全一致 |
| AR 新增/重命名（`--diff-filter=AR`） | `RuleExpandableRow.swift`、`ConditionTransformExpressionEvaluator.swift` | s1 未预列（新发现）|
| SP 强制项（§1.2.1） | 8 个 SP → ≈10 唯一文件 | ✓ 一致 |
| Audit Sample 总数 | **26 条**（target 22–29） | ✓ 在范围内 |

### Candidate Pool

> `signal` 列格式：`code_map:<arch_doc>` 为基础信号；SP-*/G-*/churn/layer_rep/ar 为叠加信号。
> `In Sample` = ✅ AS-ID / ❌ out-of-sample reason。

#### Routing 层（19 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| RT-01 | `ImportPipeline.swift` | `layer_rep:Routing-orchestrator`, `code_map:ROUTING_PIPELINE.md` | ✅ **AS-01** | — |
| RT-02 | `FilenameRuleParser.swift` | `churn:3`, `code_map:ROUTING_PIPELINE.md`, `quota-fill:Routing` | ✅ **AS-02** | — |
| RT-03 | `SampleKeyNormalizer.swift` | `sp:SP-013`, `code_map:ROUTING_PIPELINE.md` | ✅ **AS-03** | — |
| RT-04 | `SampleSemanticDescriptor.swift` | `sp:SP-014`, `code_map:ROUTING_PIPELINE.md` | ✅ **AS-04** | — |
| RT-05 | `SampleTokenization.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-06 | `RoutePlanner.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-07 | `FileRoutingRuleBook.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-08 | `RoutingCapabilities.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-09 | `DrawerMatchEngine.swift` | `sp:SP-012`, `code_map:ROUTING_PIPELINE.md` | ✅ **AS-05** | — |
| RT-10 | `PendingRoutingSnapshotEvaluator.swift` | `code_map:ROUTING_PIPELINE.md`, `quota-fill:Routing` | ✅ **AS-06** | — |
| RT-11 | `PendingRoutingRuleBook.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-12 | `RoutingExplanationBook.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-13 | `PendingRoutePresentation.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-14 | `InboxRoutingState.swift` | `layer_rep:Routing-AppState-facade`, `code_map:ROUTING_PIPELINE.md`, `quota-fill:Routing` | ✅ **AS-07** | — |
| RT-15 | `RuleLoader.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-16 | `FilenameRuleSet.swift` | `sp:SP-001`, `g:G-002@919L`, `churn:14`, `code_map:ROUTING_PIPELINE.md` | ✅ **AS-08** | — |
| RT-17 | `FileRoutingSemanticRules.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-18 | `ConditionFieldCatalog.swift` | `code_map:ROUTING_PIPELINE.md` | ❌ | `low-churn-non-sp-non-g` |
| RT-19 | `ConditionTransformExpressionEvaluator.swift` | `ar:new`, `code_map:ROUTING_PIPELINE.md` | ✅ **AS-09** | — |

Routing 入样：**9 条**（AS-01,02,03,04,05,06,07,08,09；target 7–8，AR 强制项溢出 +1，§1.4.1 自动扩）

#### Rules 层（23 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| RL-01 | `RulesManagementStore.swift` | `sp:SP-003`, `layer_rep:Rules-FeatureStore`, `churn:2`, `code_map:RULES_AUTHORING.md` | ✅ **AS-10** | — |
| RL-02 | `RulesPanelView.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-03 | `RulesPanelSection.swift` | `churn:1`, `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-04 | `RulesSectionShell.swift` | `churn:6`, `code_map:RULES_AUTHORING.md` | ✅ **AS-11** | — |
| RL-05 | `SectionPersistenceStrategy.swift` | `churn:1`, `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-06 | `WorkflowSection.swift` | `churn:6`, `code_map:RULES_AUTHORING.md` | ✅ **AS-12** | — |
| RL-07 | `MeasuringConditionSection.swift` | `churn:10`, `code_map:RULES_AUTHORING.md` | ✅ **AS-13** | — |
| RL-08 | `SampleIdentificationSection.swift` | `churn:7`, `code_map:RULES_AUTHORING.md` | ✅ **AS-14** | — |
| RL-09 | `ImportFiltersSection.swift` | `churn:2`, `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-below-quota-cutoff` |
| RL-10 | `FilenameTokenizationSection.swift` | `churn:2`, `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-below-quota-cutoff` |
| RL-11 | `RulesBootstrapper.swift` | `g:G-001@1203L`, `churn:2`, `code_map:RULES_AUTHORING.md` | ✅ **AS-15** | — |
| RL-12 | `WorkflowRegistryRetirementService.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-13 | `RulesConfigPaths.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-14 | `SpinLabRuleProvider.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-15 | `RuleCanonicalizer.swift` | `churn:4`, `code_map:RULES_AUTHORING.md`, `quota-fill:Rules` | ✅ **AS-16** | — |
| RL-16 | `RulesPersistenceHook.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-17 | `RuleRef.swift` | `churn:5`, `code_map:RULES_AUTHORING.md` | ✅ **AS-17** | — |
| RL-18 | `RulesSyncEngine.swift` | `sp:SP-003`, `code_map:RULES_AUTHORING.md` | ✅ **AS-18** | — |
| RL-19 | `MatchRulesEditor.swift` | `churn:7`, `code_map:RULES_AUTHORING.md` | ✅ **AS-19** | — |
| RL-20 | `RuleExpandableRow.swift` | `ar:new`, `code_map:RULES_AUTHORING.md` | ✅ **AS-20** | — |
| RL-21 | `RegexField.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-22 | `RulesPanelErrorMatching.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |
| RL-23 | `SaveErrorsBadge.swift` | `code_map:RULES_AUTHORING.md` | ❌ | `low-churn-non-sp-non-g` |

Rules 入样：**11 条**（AS-10..AS-20；target 9–11 ✓）

#### ConfirmApply 层（16 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| CA-01 | `InboxFeatureStore.swift` | `layer_rep:ConfirmApply-FeatureStore`, `code_map:CONFIRM_AND_APPLY.md` | ✅ **AS-21** | — |
| CA-02 | `ApplyCoordinator.swift` | `sp:SP-010`, `sp:SP-011`, `code_map:CONFIRM_AND_APPLY.md` | ✅ **AS-22** | — |
| CA-03 | `InboxArchiveApplyService.swift` | `sp:SP-010`, `sp:SP-011`, `code_map:CONFIRM_AND_APPLY.md` | ✅ **AS-23** | — |
| CA-04 | `InboxWorkflowService.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-05 | `InboxFacade.swift` | `scope:cross-cutting-Inbox-facade`, `code_map:CONFIRM_AND_APPLY.md` | ❌ | `cross-cutting-low-churn` |
| CA-06 | `InboxView.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-07 | `InboxViewModel.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-08 | `InboxOperationPanel.swift` | `churn:3`, `code_map:CONFIRM_AND_APPLY.md`, `quota-fill:ConfirmApply` | ✅ **AS-24** | — |
| CA-09 | `InboxInspectorPanel.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-10 | `InboxSelectionWorkbenchPanel.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-11 | `InboxProgressOverlays.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-12 | `AuditEvent.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-13 | `AuditLogger.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-14 | `DuplicateGuard.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-15 | `PendingCleanupService.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |
| CA-16 | `ServiceOutcome.swift` | `code_map:CONFIRM_AND_APPLY.md` | ❌ | `low-churn-non-sp-non-g` |

ConfirmApply 入样：**4 条**（AS-21..AS-24；target 4–6，达下限 ✓）

#### Output 层（10 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| OT-01 | `SampleRegistry.swift` | `sp:SP-005`, `layer_rep:Output-lookup-entry`, `code_map:OUTPUT_CONTRACTS.md` | ✅ **AS-25** | — |
| OT-02 | `RegistryLookupRuleBook.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| OT-03 | `RegistrySheetFilter.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| OT-04 | `RegistrySubstrateRuleBook.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| OT-05 | `RegistryFeatureStore.swift` | `layer_rep:Output-FeatureStore`, `code_map:OUTPUT_CONTRACTS.md` | ✅ **AS-26** | — |
| OT-06 | `RegistryCoordinator.swift` | `sp:SP-005`, `code_map:OUTPUT_CONTRACTS.md` | ✅ **AS-27** | — |
| OT-07 | `RegistryFacade.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| OT-08 | `RegistryLifecycleService.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| OT-09 | `XLSXSheetValueReader.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| OT-10 | `SidecarCompositionUseCase.swift` | `code_map:OUTPUT_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |

Output 入样：**3 条**（AS-25..AS-27；target 3–4，达下限 ✓）

### Audit Sample 汇总（27 条，target 22–29 ✓）

> target 自动扩至 27（原 s1 上限 29 内；Routing AR 强制项 +1 → 9 条超原配额上限 8；§1.4.1 自动扩，不剔强制项）

| Batch | AS-ID | 文件名（short） | Layer | 主要信号 |
|---|---|---|---|---|
| 1 | AS-01 | `ImportPipeline.swift` | Routing | layer_rep |
| 1 | AS-02 | `FilenameRuleParser.swift` | Routing | churn:3, quota-fill |
| 1 | AS-03 | `SampleKeyNormalizer.swift` | Routing | sp:SP-013 |
| 1 | AS-04 | `SampleSemanticDescriptor.swift` | Routing | sp:SP-014 |
| 1 | AS-05 | `DrawerMatchEngine.swift` | Routing | sp:SP-012 |
| 1 | AS-06 | `PendingRoutingSnapshotEvaluator.swift` | Routing | quota-fill |
| 1 | AS-07 | `InboxRoutingState.swift` | Routing | layer_rep(AppState facade) |
| 1 | AS-08 | `FilenameRuleSet.swift` | Routing | sp:SP-001, g:G-002(919L), churn:14 |
| 1 | AS-09 | `ConditionTransformExpressionEvaluator.swift` | Routing | ar:new |
| 1 | AS-25 | `SampleRegistry.swift` | Output | sp:SP-005, layer_rep |
| 1 | AS-26 | `RegistryFeatureStore.swift` | Output | layer_rep |
| 1 | AS-27 | `RegistryCoordinator.swift` | Output | sp:SP-005 |
| 2 | AS-10 | `RulesManagementStore.swift` | Rules | sp:SP-003, layer_rep, churn:2 |
| 2 | AS-11 | `RulesSectionShell.swift` | Rules | churn:6 |
| 2 | AS-12 | `WorkflowSection.swift` | Rules | churn:6 |
| 2 | AS-13 | `MeasuringConditionSection.swift` | Rules | churn:10 |
| 2 | AS-14 | `SampleIdentificationSection.swift` | Rules | churn:7 |
| 2 | AS-15 | `RulesBootstrapper.swift` | Rules | g:G-001(1203L) |
| 2 | AS-16 | `RuleCanonicalizer.swift` | Rules | churn:4, quota-fill |
| 2 | AS-17 | `RuleRef.swift` | Rules | churn:5 |
| 2 | AS-18 | `RulesSyncEngine.swift` | Rules | sp:SP-003 |
| 2 | AS-19 | `MatchRulesEditor.swift` | Rules | churn:7 |
| 2 | AS-20 | `RuleExpandableRow.swift` | Rules | ar:new |
| 2 | AS-21 | `InboxFeatureStore.swift` | ConfirmApply | layer_rep |
| 2 | AS-22 | `ApplyCoordinator.swift` | ConfirmApply | sp:SP-010, sp:SP-011 |
| 2 | AS-23 | `InboxArchiveApplyService.swift` | ConfirmApply | sp:SP-010, sp:SP-011 |
| 2 | AS-24 | `InboxOperationPanel.swift` | ConfirmApply | churn:3, quota-fill |

---

## 1. Violations

> 格式：`AS-ID | 文件名 | 信号 #N (base) | overlay_signal | 严重度 | 行为描述 | next_action`

**Batch 1 结果（Claude 主审，2026-05-02）：0 条 Violation**

### Batch 2（Rules + ConfirmApply，Codex 主审 / Claude 评审，2026-05-02）

| V-ID | AS-ID | 文件名 | 信号 | overlay | 严重度 | 行为描述 | next_action |
|---|---|---|---|---|---|---|---|
| V-001 | AS-10 | `RulesManagementStore.swift` | #6 | — | M | `loadAndCacheHash`/`loadFromDiskOnly`/`fileHash` 的 `try?` 折叠 read/decode error 为 nil 且无日志；`fileExists` guard 不覆盖 corrupt/decode fail，违反 Adj-10 | 11b |
| V-002 | AS-10 | `RulesManagementStore.swift` | #15 | — | M | `persist()` 直接调用 `RuleLoader.shared.reloadCached()` + `bumpRuleSetVersion()`，运行时副作用未经 AppEnvironment 注入（L511-512） | 14a |
| V-003 | AS-13 | `MeasuringConditionSection.swift` | #2 | — | M | `rulesBinding` setter 执行 `normalizeConditionRuleForUI`（`$MATCH`/`*1` 赋值 + standardUnit 可用性过滤）at L135/L183-199，View 承载归一化和过滤逻辑 | 11b |
| V-004 | AS-14 | `SampleIdentificationSection.swift` | #2 | — | L | `batchSpecsBinding` setter 过滤非 `.startsWith` spec 后写回 `batchPrefixes`（L65），规则过滤逻辑在 View binding setter 中 | 11b |
| V-005 | AS-15 | `RulesBootstrapper.swift` | #15 | — | M | 静态启动迁移工具直接使用 `FileManager`/`Data.write` 执行运行时副作用，未经 AppEnvironment capability 注入（AppLogger.shared 属 logging 豁免；G-001 大文件） | defer-to-G-track |
| V-006 | AS-19 | `MatchRulesEditor.swift` | #2 | — | L | `unitSuffixOptions()`（L261-274）在 View 方法中过滤 rule ops 并去重生成 standardUnit picker 选项，规则语义派生列表应由非 View 层提供 | 11b |
| V-007 | AS-23 | `InboxArchiveApplyService.swift` | #6 | — | H | `try? transaction.rollback()` at L133/L151 静默丢弃 rollback error；事务清理失败无日志，可能掩盖部分写入残留 | 11b |
| V-008 | AS-23 | `InboxArchiveApplyService.swift` | #15 | — | H | `AuditLogger.shared` 作为 stored property（L13）；`SpinLabRuleProvider.shared.loadResult()` 直接调用（L242）；运行时副作用均未注入 | 14a |
| V-009 | AS-24 | `InboxOperationPanel.swift` | #2 | — | M | View body 计算 `libraryMatchedCount`/`reviewRequiredCount`（L22-27）并调用 `filteredPendingImports(using:)`（L28, L194-204）按 route verdict 过滤域对象 | 11b |

---

## 2. Drift

> 格式：`AS-ID | 文件名 | Code Map 现注释 | 实现偏离描述 | commit_id`

**Batch 1 结果：0 条 Drift**（Code Map 注释与实现对齐）

**Batch 2 结果：0 条 Drift**（Code Map 注释与实现对齐）

---

## 3. Accepted Boundaries

> 格式：`AS-ID | 文件名 | 信号检查结论 | 判断依据`

### Batch 1（Routing + Output，Claude 主审，2026-05-02）

| AS-ID | 文件名 | 信号 | 判断依据 |
|---|---|---|---|
| AS-01 | `ImportPipeline.swift` | 全通过 | `ruleProvider` 参数可注入（默认 singleton 为 read-only exception） |
| AS-02 | `FilenameRuleParser.swift` | 全通过 | 纯 parser struct，无 SwiftUI / 无 storage 调用 |
| AS-03 | `SampleKeyNormalizer.swift` | 全通过 | 纯归一化 struct；`FileRoutingRuleBook()` 值类型 inline 实例 |
| AS-04 | `SampleSemanticDescriptor.swift` | 全通过 | static `ruleProvider.ruleSet()` 为 read-only exception；struct 不含 side-effecting 写操作 |
| AS-05 | `DrawerMatchEngine.swift` | 全通过 | 纯 token-coverage matching，无副作用 |
| AS-06 | `PendingRoutingSnapshotEvaluator.swift` | 全通过 | 纯 snapshot builder；`PendingRoutingRuleBook()` 值类型 inline 实例 |
| AS-07 | `InboxRoutingState.swift` | 全通过 | `final class`（非 @Observable）设计为 routing 内部缓存，由 AppState 以 `@ObservationIgnored` 持有；Layer boundary 注释明确；无 SwiftUI 可观察接口 |
| AS-08 | `FilenameRuleSet.swift` | 全通过 | rule schema + 编译/评估，大文件（919L G-002）；`ConditionTransformExpressionEvaluator()` inline 值类型实例合法；`applyStandardization` 抛出 transform 错误进 warning list 而非 `try?` 丢弃 |
| AS-09 | `ConditionTransformExpressionEvaluator.swift` | 全通过 | 完全无状态 recursive descent parser，AR 新文件；无信号命中 |
| AS-25 | `SampleRegistry.swift` | 全通过 | `buildIndex` 通过 `RegistryLookupRuleBook` 协议注入策略；`try? parseSharedStrings()` 符合 Adj-10（XLSX shared strings 缺失为正常 format 变体）；env var 读取 read-only；`SampleIDParser` singleton read-only exception |
| AS-26 | `RegistryFeatureStore.swift` | 全通过 | 13L 纯展示态 struct；CLAUDE.md "small presentation-only state containers may be struct" exception 成立 |
| AS-27 | `RegistryCoordinator.swift` | 全通过 | `@MainActor` coordinator struct；async methods 合法（非 AppState 直接方法）；`refreshRoutingRuleMetadata(inboxStore:)` 跨区调用通过 AppState 参数注入，编排方仍是 AppState |

### Batch 2（Rules + ConfirmApply，Codex 主审 / Claude 评审，2026-05-02）

| AS-ID | 文件名 | 信号 | 判断依据 |
|---|---|---|---|
| AS-10 | `RulesManagementStore.swift` | #13 challenge → 驳回 | `persist()` I/O 为小型 config JSON（~few KB），同步写入是 save outcome 准确报告的必要设计；@Observable no-async 规则排除异步化选项；不属于"重 I/O" |
| AS-11 | `RulesSectionShell.swift` | 全通过 | `@Environment` 获取 AppState；仅编排保存/冲突 UI，无 18-signal 命中 |
| AS-12 | `WorkflowSection.swift` | 全通过 | 本地 draft 为 transient UI 态；binding 映射为 UI 编辑适配，无 sort/filter/normalize |
| AS-16 | `RuleCanonicalizer.swift` | 全通过 | 纯 canonicalization helper，返回 warnings，无副作用 |
| AS-17 | `RuleRef.swift` | 全通过 | 纯 ruleRef 字符串工厂，无 I/O / 状态流 / UI 逻辑 |
| AS-18 | `RulesSyncEngine.swift` | 全通过 | 依赖全部注入；`try?` 满足 Adj-10（mirror absent = first boot 预期）；`RuleLoader.shared.load()` 为 reverse sync 后只读校验边界 |
| AS-20 | `RuleExpandableRow.swift` | 全通过 | 通用展开行 UI，仅接收标题/错误态/回调，无业务逻辑 |
| AS-21 | `InboxFeatureStore.swift` | 全通过 | `@MainActor @Observable final class`；长任务通过内部 Task 编排；routing cache 以 `@ObservationIgnored` 持有 |
| AS-22 | `ApplyCoordinator.swift` | 全通过 | 纯 struct coordinator；依赖全部参数注入；apply service 注入不持有 |
| AS-23 | `InboxArchiveApplyService.swift` | #20 challenge → 驳回 | `LibraryWriteTransaction` 是 Library FS 指定事务写 API；`libraryStore` 用于路径解析和元数据读取；write path 未绕过 LibraryStore 接口 |

---

## 4. Cross-Region Doubts For 5.1.14

> §1.2.1 排除的 4 个 SP seed + 审计中发现的跨区现象。

| Seed | 来源 | 描述 | 关联 SP |
|---|---|---|---|
| SP-002 | §1.2.1 排除 | Workbench 消费侧 SP；Inbox 仅通过 Rules 层生产 FilenameRuleSet，跨区消费边界待 14a 收敛 | SP-002 |
| SP-004 | §1.2.1 排除 | WorkflowDefinitionStore 不在 Inbox Code Map；跨区 workflow 定义依赖边界待 14a 收敛 | SP-004 |
| SP-006 | §1.2.1 排除 | SpinLabFileSidecar 不在 Inbox Code Map；Inbox 仅消费侧，sidecar contract 跨区边界待 14a 收敛 | SP-006 |
| SP-015 | §1.2.1 排除 | WorkflowID 不在 Inbox Code Map；跨区 WorkflowID 枚举依赖边界待 14a 收敛 | SP-015 |

（审计中如发现新跨区现象，追加到本段；字段须含文件名 + 信号 + 跨区描述）

---

## 5. Fix-Round Draft

> 格式：`V-ID | AS-ID | next_action | 修复描述（一行）`

### next_action 分布（9 条，两批合计）

| next_action | 条数 | V-ID |
|---|---|---|
| 11b | 6 | V-001, V-003, V-004, V-006, V-007, V-009 |
| 14a | 2 | V-002, V-008 |
| defer-to-G-track | 1 | V-005 |

### 修复明细

| V-ID | AS-ID | next_action | 修复描述 |
|---|---|---|---|
| V-001 | AS-10 | 11b | `loadAndCacheHash`/`loadFromDiskOnly`/`fileHash`：file-not-found 仍返回 nil；corrupt/decode/read failure 补 `logger.error` |
| V-002 | AS-10 | 14a | `RuleLoader` 作为 AppEnvironment capability 注入 `RulesManagementStore`；`persist()` 通过注入实例触发 `reloadCached`/`bumpRuleSetVersion` |
| V-003 | AS-13 | 11b | `normalizeConditionRuleForUI` 及 standardUnit 可用性过滤下沉到 `RulesManagementStore` 或专用 UseCase；View binding setter 只传值 |
| V-004 | AS-14 | 11b | `batchSpecsBinding` setter 的 `.startsWith` filter 移至 `store.updateSampleIdentification` 或 editor contract |
| V-005 | AS-15 | defer-to-G-track | `RulesBootstrapper` DI bypass 留 G-001 大文件拆分轮收敛 |
| V-006 | AS-19 | 11b | `unitSuffixOptions()` 迁移到调用方（`MeasuringConditionSection`）或通过 binding 由调用方传入；不在 `MatchRulesEditor` 内部计算 |
| V-007 | AS-23 | 11b | `try? transaction.rollback()` 改为 `do { try transaction.rollback() } catch { logger.error(...) }` |
| V-008 | AS-23 | 14a | `AuditLogger` 和 `SpinLabRuleProvider` 作为 init 参数注入 `InboxArchiveApplyService` |
| V-009 | AS-24 | 11b | `libraryMatchedCount`/`filteredPendingImports` 计算迁移到 `InboxViewModel`；View 只消费展示态属性 |
