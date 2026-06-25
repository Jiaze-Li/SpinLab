# Region Map (Working File — 5.1.6)

> **状态**：s4 收敛输入。s1 已完成 218 / 218 swift 文件归属扫描；s2 已完成层级规范族映射 + 消费者关系二轮判断；s3 已完成首轮字段级共享点实证。
>
> 现行派发入口见 [`INDEX.md`](INDEX.md)。本文件保留为扫描证据底稿。

## 相关文档索引（5.1.6 完整规划链路）

| 文档 | 用途 |
|---|---|
| [`docs/V5_ROADMAP.md` §5.1.6](../V5_ROADMAP.md) | 立项依据、动机、顶层原则、实施方案入口 |
| [`docs/handoff/archive/2026-04-28-5.1.6-architecture-index.md`](../handoff/archive/2026-04-28-5.1.6-architecture-index.md) | 已归档实施方案：拍板要点、s1–s4 任务拆分、7 AG、否决方案 |
| [`docs/V5_ROADMAP.md` §5.1.8](../V5_ROADMAP.md) | 5.1.6 完成后首条结构债清理（条件解耦）|
| [`docs/TASK_BOARD.md`](../TASK_BOARD.md) | 5.1.6 / 5.1.8 进行中状态 |
| [`docs/philosophy.md` Shell & Composition](../philosophy.md) | 通用 shell 优先 + 内部分层哲学（顶层原则 #4 来源）|
| [`docs/architecture/INDEX.md`](INDEX.md) | 现行架构派发入口：区域 → 首读文件 → 共享风险 → 测试入口 |
| 本文件 (REGION_MAP.md) | 5.1.6 证据底稿：区块归属表 + s2 层级规范 + s3 共享点实证 + 附录 |
| [`docs/handoff/_pending/5.1.8-condition-kind-decoupling-design-seed.md`](../handoff/_pending/5.1.8-condition-kind-decoupling-design-seed.md) | 5.1.8 派发种子（待 s4 收尾后启动）|
| [`docs/history/v516_design_review_codex.md`](../history/v516_design_review_codex.md) | Codex 对本期方案的独立评审报告（驱动多处 AG 收紧）|
| [`docs/history/v515_s12_deep_match_unification.md`](../history/v515_s12_deep_match_unification.md) | Shell & Composition 横向样板诞生案例 |

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

## 锚点归属判例（s1.a）

1. `Domain/*.swift`：即使被 Inbox / Library / Workbench 同时消费，也归「跨区共享 / Domain」。它们是领域契约，不按当前消费者改归属。
2. `SpinLabAppState.swift`：归「跨区共享 / AppShell」。它暴露 feature stores 并做跨 store 协调，不是单一业务 FeatureStore。
3. `InboxFeatureStore.swift`：归「Inbox / Store」。它拥有 pending imports、routing state、import task 和 Inbox interaction restore。
4. `LibraryFeatureStore.swift` 及其扩展：归「Library / Store」。扩展文件跟随主 store，不因在 `App/State` 目录下改归跨区。
5. `WorkbenchFeatureStore.swift`：归「Workbench / Store」，但标共享候选。它包含 condition/rule draft 类型，后续 s3 需确认是否存在 Rules↔Workbench 协调面迁移。
6. `AnalysisVault.swift`：归「Workbench / Store」。文件注释明确由 WorkbenchFeatureStore owning，persistence 也是 analysis pack 语义。
7. `AppRouter.swift` / `RootSplitView.swift` / sidebar 相关文件：归「跨区共享 / UI or Navigation」。导航和根 shell 是全局 concerns。
8. `App/` 下 service 不按目录归属：`Inbox*` / `ApplyCoordinator` / `PendingCleanupService` 归 Inbox；`Library*` 归 Library；`Registry*` 暂归跨区共享（Inbox routing + Library registry preview 双消费）。

---

## 文件表字段规范（s1 主产出，s2 审核）

每文件一行，区块由段落标题表达，表内 8 个字段：

| 字段 | 写什么 | 取值范围 / 例子 |
|---|---|---|
| **文件** | 相对 `Sources/SpinLabApp/` 的路径 | `App/State/InboxFeatureStore.swift` |
| **区块** | 5 区块之一或暧昧 | Inbox / Library / Workbench / Rules / 跨区 / `[暧昧]` |
| **归属依据** | 为什么归到这个区块（s2 回扫的审计字段）| 短标签：`consumer: Inbox+Rules` / `appstate extension` / `filename-only` / `inline-doc` / `[猜测]` |
| **层级归属 (s2)** | 文件主要层级；允许保留细分标签，但必须可映射到下方 s2 层级族 | UI / State / Logic / Persistence / Domain / Infrastructure / AppShell |
| **行数** | swift 文件行数 | 整数（先扫 `wc -l` 一次出全表）|
| **共享候选** | 是否疑似跨区共享 | ⭐ + 短标签（如 `⭐ consumer:I+L+W`）；不是留空 |
| **平行候选** | 是否疑似平行实现 / shell 内部肥大（写入附录 G）| ⭐G + 短标签（如 `⭐G H:与 ThreeOmegaXxx 平行` / `⭐G V:疑似 1500 行多职责`）；不是留空 |
| **TODO 数** | 文件内 TODO/FIXME/XXX 注释数 | 整数（无则 0）；具体内容写入附录 C |
| **测试** | 直接测试线索 | `direct` / `behavioral` / `none`（按文件名约定查 Tests/ 直接测试 → direct；只有同主题行为测试 → behavioral；查不到 → none，s2/s4 再补行为映射）|

附加注释（一句话职责）写在表格行后或附注里，不挤进表格列。

## s2 层级归属规范

> s2 不追求把每行改成单词级统一标签；优先保留派发有用的细分层级，再用本段规范解释其归一化族。后续 `INDEX.md` 可同时展示「规范族 + 细分标签」。

| 规范族 | 覆盖现有细分标签 | 派发含义 |
|---|---|---|
| UI | `UI` / `UI shell` / `UI component` / `UI extension` / `UI helper` / `UI model` / `UI service` / `UI registry` / `UI layout` / `UI modifier` / `UI token` / `UI bridge` / `ViewModel` / `Navigation` | 视图、局部交互、展示模型、导航和可复用 UI 壳 |
| State | `Store` / `Store extension` / `Store helper` / `Store/Persistence` / `Facade/Orchestrator` / `Coordinator` / `Service/Orchestrator` / `AppShell/Coordinator` / `Data actor` | 长生命周期状态、跨 store 协调、状态恢复、任务编排 |
| Logic | `UseCase` / `UseCase helper` / `UseCase/Service` / `Service` / `Pipeline` / `Strategy/UseCase helper` / `Parser` / `Parser helper` / `Presentation` / `Presentation helper` / `Renderer` / `Renderer helper` / `Renderer pipeline` / `Rule helper` | 可测试业务逻辑、计算、解析后处理、规则求值、渲染计算 |
| Persistence | `Repository` / `Repository/Loader` / `Repository/Index` / `Persistence` / `Storage service` / `Storage helper` / `Storage model` / `Storage/Sync service` / `Persistence hook` / `Migration service` / `Config paths` | 文件、索引、运行时配置、迁移、存储同步、仓储抽象 |
| Domain | `Domain` / `Domain/Model` / `Domain/Contract` / `Domain/Config` / `Domain/Config model` / `Domain/Search model` / `Domain/Projection` / `Domain/Rule model` / `Domain/Persistence model` / `Rule model` / `Config model` / `Interaction model` / `Audit model` / `Error model` | 领域契约、配置模型、规则 schema、投影模型 |
| Infrastructure | `Infrastructure` / `Utility` / `Capability protocol` / `Capability protocols` / `Capability protocol/provider` / `Extension contract` / `Shared rulebook` / `Shared parser/helper` / `Shared domain/parser model` | 横切基础设施、协议能力、共享 helper、插件扩展点 |
| AppShell | `AppShell` / `AppShell/DI` / `App entry` | 应用入口、依赖注入、根壳 |

### s2 二轮判断结果

| 项目 | 结果 |
|---|---|
| s1 暧昧条目 | 0；无需回收 `[暧昧]` 到具体区块 |
| s2 未确定条目 | 0；当前没有需要进入 `[未确定]` 的文件 |
| 层级覆盖 | 218 / 218 已有层级标签；本轮新增规范族映射，不做无价值的全表同义词重写 |
| 后续输入 | s3 从「共享候选」「平行候选」和附录 B/G 进入字段级实证 |

## s3 共享点实证

> s3 只做证据分级，不改代码。结构债清单最终只收 `suspect_coupling` 与需迁移的 `coordination_surface`；`legitimate_cross_cutting` 和 `migration_candidate` 保留为背景证据。

| ID | 分类 | 共享点 | 证据文件 | 结论 / 后续 |
|---|---|---|---|---|
| SP-001 | `suspect_coupling` | `MeasuringConditionFileDraft.ConditionDefinition.tokenMap` 同时承载 `unit_suffix` 和 `token_map` 两种 UI/规则语义 | `Features/RulesPanel/RulesManagementStore.swift`; `Features/RulesPanel/Sections/MeasuringConditionSection.swift`; `Features/RulesPanel/SectionPersistenceStrategy.swift`; `Tests/SpinLabAppTests/V515ConditionKindSwitchTests.swift`; `docs/handoff/_pending/5.1.8-condition-kind-decoupling-design-seed.md` | 已有 5.1.8 种子；这是字段级错误耦合，不应作为合法共享抽象保留 |
| SP-002 | `coordination_surface` | Workbench condition projection 从 Rules rule set 派生，但缓存/展示在 `WorkbenchFeatureStore` | `App/State/WorkbenchFeatureStore.swift`; `Import/Rules/RuleLoader.swift`; `Import/Rules/ConditionFieldCatalog.swift`; `App/InboxFacade.swift` | Workbench 消费 Rules 配置是合理关系；需确认 projection 是否应迁到 Rules-facing facade 或明确为 Workbench coordination surface |
| SP-003 | `coordination_surface` | RulesPanel 保存后立即影响 runtime rule cache、Inbox routing、Registry lookup、Workbench condition options | `Features/RulesPanel/RulesManagementStore.swift`; `Import/Rules/RulesPersistenceHook.swift`; `Import/Rules/RuleLoader.swift`; `Import/Rules/SpinLabRuleProvider.swift`; `App/SpinLabAppState.swift` | 保存路径是跨区状态刷新点；s4 结构债应要求明确 reload/notification 边界 |
| SP-004 | `coordination_surface` | `workflow.json` 是 Rules-owned config，但 Workbench 通过 `WorkflowDefinitionStore` / registry UI 消费 workflow 定义 | `Workflow/WorkflowDefinitionStore.swift`; `Workflow/WorkflowDefinition.swift`; `Features/Workbench/WorkflowRegistryView.swift`; `Features/RulesPanel/Sections/WorkflowSection.swift`; `Import/Rules/WorkflowRegistryRetirementService.swift` | 配置所有权与展示消费分离合理；需要在 INDEX 标出首读 Rules config + Workbench consumer |
| SP-005 | `coordination_surface` | Registry lookup aliases and sheet filtering come from Rules config while registry index serves Inbox + Library | `Registry/RegistryLookupRuleBook.swift`; `Registry/RegistrySheetFilter.swift`; `Registry/SampleRegistry.swift`; `Import/RegistrySubstrateRuleBook.swift`; `App/RegistryCoordinator.swift` | Registry 不是独立产品区块；s4 INDEX 应作为跨区共享入口，避免误派给 Inbox 或 Library 单区 |
| SP-006 | `legitimate_cross_cutting` | `SpinLabFileSidecar` 是 Library 持久化、Inbox apply、Workbench search 的稳定文件契约 | `Library/SpinLabFileSidecar.swift`; `App/InboxArchiveApplyService.swift`; `Library/LibraryWriteTransaction.swift`; `UseCases/SearchWorkflowMeasurementsUseCase.swift`; `Features/Library/MeasurementConditionDetailView.swift` | 合法共享 Domain/Persistence contract；s4 INDEX 应把它列为 Library file contract，不作为拆分债 |
| SP-007 | `coordination_surface` | Workbench chart/metric 写入 Library `_spinlab` 目录并维护 `results_index.json` / `measurement_plot_index.json` | `UseCases/SaveActiveChartToLibraryUseCase.swift`; `UseCases/PersistChartArtifactUseCase.swift`; `UseCases/PersistMeasurementDataUseCase.swift`; `UseCases/LoadMeasurementPlotIndexUseCase.swift`; `App/LibraryDiskCleanupService.swift`; `Tests/SpinLabAppTests/V41217MeasurementPlotIndexTests.swift` | Workbench→Library 写入边界需要在 INDEX 明确：Workbench owns generation，Library owns storage namespace and cleanup invariants |
| SP-008 | `legitimate_cross_cutting` | `LibraryPathResolver` 是 Library-root-relative path boundary，供 Library cleanup / Workbench artifact use cases / Library preview 共同使用 | `Library/LibraryPathResolver.swift`; `UseCases/PersistChartArtifactUseCase.swift`; `UseCases/LoadMeasurementDataUseCase.swift`; `App/LibraryDiskCleanupService.swift`; `Features/Library/MeasurementPlotPreviewPanel.swift` | 合法基础设施共享；保留为 cross-cutting path capability，风险是调用者绕开 resolver |
| SP-009 | `coordination_surface` | Workbench 搜索直接枚举 Library sidecars 并复用 Import sample semantics / Workflow aliases | `UseCases/SearchWorkflowMeasurementsUseCase.swift`; `Import/Parse/SampleKeyNormalizer.swift`; `Import/Parse/SampleSemanticDescriptor.swift`; `Workflow/WorkflowID.swift`; `App/SpinLabDataActor.swift`; `Tests/SpinLabAppTests/V320WorkflowSearchAcrossDrawersTests.swift` | 功能合理但横跨 Workbench+Library+Import semantics；s4 需标为 Workbench search read model，后续 s3 继续判断 Import helper 是否应迁出 |
| SP-010 | `coordination_surface` | Inbox apply writes files and sidecars into Library drawers using Library index/sample paths | `App/ApplyCoordinator.swift`; `App/InboxArchiveApplyService.swift`; `Library/LibraryStore.swift`; `Library/SpinLabFileSidecar.swift`; `Tests/SpinLabAppTests/V230ApplyTests.swift`; `Tests/SpinLabAppTests/V250SidecarTests.swift` | 清晰的 Inbox→Library write workflow；INDEX 应从 Inbox apply 入口开始，并显式列 Library write/read invariants |
| SP-011 | `legitimate_cross_cutting` | `LibraryWriteTransaction` provides atomic paired measurement+sidecar writes for Inbox apply | `Library/LibraryWriteTransaction.swift`; `App/InboxArchiveApplyService.swift`; `Library/SpinLabFileSidecar.swift`; `Tests/SpinLabAppTests/V250SidecarTests.swift` | 合法 Library write infrastructure；不是业务耦合，后续只需防止非事务写入绕开它 |
| SP-012 | `coordination_surface` | Drawer matching normalizes Import sample input against Library sample IDs/tags | `Import/Match/DrawerMatchEngine.swift`; `Import/Parse/SampleKeyNormalizer.swift`; `Import/Parse/SampleTokenization.swift`; `Library/LibraryModels.swift`; `Tests/SpinLabAppTests/V221DrawerMatchEngineTests.swift` | 匹配职责在 Inbox pipeline 中合理，但 Import helper 依赖 Library sample shape；后续与 SP-009 一起判断 helper 是否迁到共享 parser/domain |
| SP-013 | `migration_candidate` | `SampleSemanticDescriptor` lives under Import/Parse but is consumed by Workbench ingestion/search, Library parser, Domain search model and Inbox UI | `Import/Parse/SampleSemanticDescriptor.swift`; `UseCases/SearchWorkflowMeasurementsUseCase.swift`; `UseCases/IngestThreeOmegaSelectionsUseCase.swift`; `UseCases/IngestAHESelectionsUseCase.swift`; `Library/LibraryRegistryParser.swift`; `Domain/WorkflowSearchModels.swift`; `Features/Inbox/InboxSelectionWorkbenchPanel.swift` | Domain-like semantic model should likely move out of Import during a future structure cleanup; not urgent code change in 5.1.6 |
| SP-014 | `migration_candidate` | `SampleTokenization` and `SampleKeyNormalizer` are parser helpers used outside import routing | `Import/Parse/SampleTokenization.swift`; `Import/Parse/SampleKeyNormalizer.swift`; `Import/Match/DrawerMatchEngine.swift`; `UseCases/SearchWorkflowMeasurementsUseCase.swift`; `App/State/InboxRoutingState.swift`; `Import/Route/FileRoutingRuleBook.swift` | Current placement understates cross-feature role; s4 debt list should propose shared parser/domain utility placement |
| SP-015 | `legitimate_cross_cutting` | `WorkflowID` aliases normalize search and display across Workbench search and workflow registry | `Workflow/WorkflowID.swift`; `UseCases/SearchWorkflowMeasurementsUseCase.swift`; `Workflow/WorkflowDefinitionStore.swift`; `Features/Workbench/WorkflowRegistryView.swift` | Legitimate workflow identity contract; keep as cross-cutting Workflow domain config |

### s3 当前覆盖

| 项目 | 数值 |
|---|---|
| 已实证共享点 | 15 |
| `suspect_coupling` | 1 |
| `coordination_surface` | 8 |
| `legitimate_cross_cutting` | 4 |
| `migration_candidate` | 2 |

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

- [x] 一次性跑 `wc -l` 全 swift 文件，落表得「行数」列底数（2026-04-29：218 swift / 43,220 total lines）
- [x] 一次性 grep `TODO|FIXME|XXX` 全 swift 文件，得 TODO 行数 + 具体行写入附录 C（2026-04-29：3 个真实 TODO + 1 个 `XXX` 误匹配）
- [x] 列出 `Tests/SpinLabAppTests/` 现存测试文件清单，作为「测试」列查询底数（2026-04-29：后续按 `direct` / `behavioral` / `none` 填测试列）

这三步前置完成后，扫每文件时只剩"区块判断 + 共享候选嗅探"，每文件 30–60 秒。

### Top-level（Sources/SpinLabApp 下）

- [x] `App/` (29 swift)
- [x] `App/State/` (14)
- [x] `Domain/` (4)
- [x] `UseCases/` (30)
- [x] `UI/` (7)
- [x] `Extensions/` (1)
- [x] `Repositories/` (1)
- [x] `Storage/` (4)
- [x] `Persistence/` (1)
- [x] `Registry/` (4)
- [x] `Workflow/` (4)
- [x] `Library/` (13)
- [x] `Workbench/` (0 顶层 + V3 子目录)
- [x] `Workbench/V3/` (16)
- [x] `Import/` (2 顶层)
- [x] `Import/Parse/` (4)
- [x] `Import/Route/` (3)
- [x] `Import/Match/` (1)
- [x] `Import/Evaluate/` (3)
- [x] `Import/Presentation/` (1)
- [x] `Import/Rules/` (12)
- [x] `Features/Inbox/` (6)
- [x] `Features/Library/` (19)
- [x] `Features/Workbench/` (24)
- [x] `Features/RulesPanel/` (5)
- [x] `Features/RulesPanel/Sections/` (5)
- [x] `Features/RulesPanel/Components/` (4)
- [x] 顶层 `SpinLabApp.swift`（入口）

**总计**：218 swift 文件 / 27 目录条目（含顶层入口）。

### 进度统计（每会话末尾更新）

| 维度 | 数值 |
|---|---|
| 已扫目录 | 27 / 27 |
| 已填文件 | 218 / 218 |
| 暧昧条目 | 0（全表 0%；任一区块 > 20–25% 触发停下校准）|
| 共享候选 | 105（含合法 cross-cutting；s3 再按 4 分类实证收敛） |
| 平行候选（附录 G） | 16（横向 H + 纵向 V 合计；目标 ≥ 5）|
| 死代码可疑 | 0 |

---

## File Region Assignments

> 按区块分段的 8 字段表。区块由段落标题表达；暧昧 / 未确定单独段。

### Inbox

| 文件 | 归属依据 | 层级归属 (s2) | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|
| `App/ApplyCoordinator.swift` | consumer: Inbox apply + Library write | Service/Orchestrator | 176 | ⭐ coordination_surface: Inbox→Library |  | 0 | direct |
| `App/ArchivedRecordResolverService.swift` | consumer: Inbox archive apply + registry lookup | Service | 98 | ⭐ consumer: Inbox+Registry |  | 0 | behavioral |
| `App/DuplicateGuard.swift` | consumer: Inbox import dedupe | Service | 58 |  |  | 0 | direct |
| `App/InboxArchiveApplyService.swift` | consumer: Inbox apply to Library drawers | Service | 350 | ⭐ coordination_surface: Inbox→Library |  | 0 | direct |
| `App/InboxFacade.swift` | consumer: AppState delegates Inbox workflows | Facade/Orchestrator | 157 | ⭐ coordination_surface: Inbox+Rules+Workbench condition options |  | 0 | behavioral |
| `App/InboxWorkflowService.swift` | consumer: Inbox recompute + pending hints | Service | 107 | ⭐ consumer: Inbox+Rules |  | 0 | behavioral |
| `App/PendingCleanupService.swift` | consumer: Inbox clear imports | Service | 17 |  |  | 0 | direct |
| `App/State/InboxFeatureStore.swift` | consumer: InboxView/AppState; owns pending imports | Store | 428 |  |  | 0 | direct |
| `App/State/InboxRoutingState.swift` | consumer: InboxFeatureStore; owns routing drafts/snapshots | Store | 301 |  |  | 0 | behavioral |
| `Features/Inbox/InboxInspectorPanel.swift` | consumer: Inbox right-column reserved/inspector UI | UI | 102 |  |  | 0 | none |
| `Features/Inbox/InboxOperationPanel.swift` | consumer: Inbox operations UI | UI | 258 |  |  | 0 | behavioral |
| `Features/Inbox/InboxProgressOverlays.swift` | consumer: Inbox import/apply progress UI | UI | 85 |  |  | 0 | none |
| `Features/Inbox/InboxSelectionWorkbenchPanel.swift` | consumer: selected pending review/edit UI | UI | 482 | ⭐ coordination_surface: Inbox UI edits route/workflow/condition drafts |  | 0 | behavioral |
| `Features/Inbox/InboxView.swift` | consumer: RootSplitView Inbox area | UI | 64 |  |  | 0 | behavioral |
| `Features/Inbox/InboxViewModel.swift` | consumer: InboxView local UI state | ViewModel | 58 |  |  | 0 | behavioral |
| `Import/Evaluate/PendingRoutingRuleBook.swift` | consumer: PendingRoutingSnapshotEvaluator constants | UseCase helper | 7 |  |  | 0 | behavioral |
| `Import/Evaluate/PendingRoutingSnapshotEvaluator.swift` | consumer: Inbox route verdict evaluation | UseCase | 113 |  |  | 0 | direct |
| `Import/Evaluate/RoutingExplanationBook.swift` | consumer: Inbox routing explanation UI/tests | Presentation helper | 41 |  |  | 0 | direct |
| `Import/ImportPipeline.swift` | consumer: Inbox import parse pipeline | Pipeline | 47 | ⭐ consumer: Inbox+Rules ruleProvider |  | 0 | behavioral |
| `Import/Match/DrawerMatchEngine.swift` | consumer: Inbox drawer matching | UseCase | 96 | ⭐ consumer: Inbox+Library samples |  | 0 | direct |
| `Import/Parse/FilenameRuleParser.swift` | consumer: import filename parsing | Parser | 441 | ⭐ consumer: Inbox+Rules ruleSet |  | 0 | direct |
| `Import/Presentation/PendingRoutePresentation.swift` | consumer: Inbox route presentation/warnings | Presentation | 150 |  |  | 0 | direct |
| `Import/Route/FileRoutingRuleBook.swift` | consumer: RoutePlanner sample token semantics | UseCase helper | 265 | ⭐ consumer: Inbox+Rules semantic rules |  | 0 | direct |
| `Import/Route/RoutePlanner.swift` | consumer: Inbox route candidate planning | UseCase | 183 |  |  | 0 | direct |
| `Import/Route/RoutingCapabilities.swift` | consumer: InboxRoutingState DI protocols | Capability protocols | 54 | ⭐ legitimate_cross_cutting within Inbox pipeline |  | 0 | behavioral |

### Library

| 文件 | 归属依据 | 层级归属 (s2) | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|
| `App/LibraryDiskCleanupService.swift` | consumer: Library deletion cleanup | Service | 327 |  |  | 0 | behavioral |
| `App/LibraryMutationService.swift` | consumer: LibraryFeatureStore mutations | Service | 402 |  |  | 0 | behavioral |
| `App/LibraryPreviewComputationService.swift` | consumer: Library preview projection | Service | 58 |  |  | 0 | behavioral |
| `App/State/LibraryFeatureStore.swift` | consumer: LibraryView/AppState; owns library state | Store | 1145 |  | ⭐G V: >1000 lines, projection/mutation/selection responsibilities | 0 | direct |
| `App/State/LibraryFeatureStore+Logs.swift` | extension of LibraryFeatureStore | Store extension | 97 |  |  | 0 | direct |
| `App/State/LibraryFeatureStore+Projection.swift` | extension of LibraryFeatureStore | Store extension | 244 |  |  | 0 | direct |
| `App/State/LibraryFeatureStore+SampleEdit.swift` | extension of LibraryFeatureStore | Store extension | 184 |  |  | 0 | direct |
| `App/State/LibraryState.swift` | consumer: LibraryFeatureStore legacy/simple observable state | Store | 9 |  |  | 0 | behavioral |
| `Features/Library/LibraryExistingDrawerSampleSectionView.swift` | consumer: Library detail existing-drawer sample UI | UI | 72 |  |  | 0 | none |
| `Features/Library/LibraryMeasurementsDoneSection.swift` | consumer: Library measurement list/detail UI | UI | 470 |  |  | 0 | behavioral |
| `Features/Library/LibrarySampleDetailHeaderView.swift` | consumer: Library sample detail header UI | UI | 56 |  |  | 0 | none |
| `Features/Library/LibrarySelectionSync.swift` | consumer: Library selection restore/sync | UI helper | 83 |  |  | 0 | direct |
| `Features/Library/LibrarySheets.swift` | consumer: Library modal/log sheets | UI | 289 |  |  | 0 | none |
| `Features/Library/LibraryView+DetailColumn.swift` | extension of LibraryView detail column | UI extension | 477 |  |  | 0 | behavioral |
| `Features/Library/LibraryView+Panels.swift` | extension of LibraryView panels/file pickers | UI extension | 73 |  |  | 0 | none |
| `Features/Library/LibraryView+Search.swift` | extension of LibraryView search helpers | UI extension | 186 |  |  | 0 | behavioral |
| `Features/Library/LibraryView+State.swift` | extension of LibraryView state/sheets | UI extension | 231 |  |  | 0 | behavioral |
| `Features/Library/LibraryView.swift` | consumer: RootSplitView Library area | UI | 309 |  |  | 0 | behavioral |
| `Features/Library/LibraryViewComputationService.swift` | consumer: LibraryView filtering/projection | UI service | 296 |  |  | 0 | behavioral |
| `Features/Library/LibraryViewModel.swift` | consumer: LibraryView local UI state | ViewModel | 72 |  |  | 0 | behavioral |
| `Features/Library/LibraryViewSupport.swift` | consumer: Library UI support models/rows | UI model | 64 |  |  | 0 | none |
| `Features/Library/LibraryWorkspaceSections.swift` | consumer: Library workspace sections | UI | 587 |  | ⭐G V: large multi-section UI | 0 | none |
| `Features/Library/MeasurementConditionDetailView.swift` | consumer: Library measurement condition detail UI | UI | 277 |  |  | 0 | behavioral |
| `Features/Library/MeasurementDataSectionView.swift` | consumer: Library measurement data section UI | UI | 271 | ⭐ consumer: Library+Workbench measurement data models |  | 0 | behavioral |
| `Features/Library/MeasurementPlotPreviewPanel.swift` | consumer: Library chart preview UI | UI | 129 | ⭐ consumer: Library+Workbench chart artifacts |  | 0 | behavioral |
| `Features/Library/RecomputePreviewPanel.swift` | consumer: Library recompute preview UI | UI | 238 | ⭐ consumer: Library+Rules recompute projections |  | 0 | direct |
| `Features/Library/RecomputeStaleBannerView.swift` | consumer: Library stale recompute banner | UI | 33 |  |  | 0 | direct |
| `UseCases/LibraryDestinationSubpath.swift` | consumer: Library/workbench destination subpaths | UseCase helper | 14 | ⭐ consumer: Library+Workbench persistence |  | 0 | behavioral |
| `UseCases/SaveLibrarySampleEditsUseCase.swift` | consumer: Library sample edit save + registry source sync | UseCase | 86 | ⭐ consumer: Library+Registry sync |  | 0 | direct |
| `Library/LibraryDiffEngine.swift` | consumer: Library sync diff | UseCase/Service | 183 |  |  | 0 | direct |
| `Library/LibraryLogger.swift` | consumer: Library append-only logs | Infrastructure | 47 | ⭐ consumer: Library+Audit semantics |  | 0 | behavioral |
| `Library/LibraryModels.swift` | consumer: Library store/UI + Inbox apply + Workbench persistence | Domain/Model | 394 | ⭐ legitimate_cross_cutting: Library models used across features |  | 0 | behavioral |
| `Library/LibraryPathResolver.swift` | consumer: Workbench artifact/read/write paths under Library root | Infrastructure | 45 | ⭐ consumer: Library+Workbench |  | 0 | direct |
| `Library/LibraryRegistryParser.swift` | consumer: Library registry XLSX parse | Parser | 545 | ⭐ consumer: Library+Import sample semantics |  | 0 | behavioral |
| `Library/LibrarySampleEditService.swift` | consumer: Library sample metadata edits | Service | 193 |  |  | 0 | behavioral |
| `Library/LibrarySettingsStore.swift` | consumer: Library settings persistence | Repository | 55 |  |  | 0 | behavioral |
| `Library/LibrarySort.swift` | consumer: Library UI/store sorting | Utility | 40 |  |  | 0 | behavioral |
| `Library/LibraryStore.swift` | consumer: Library persistence + Inbox apply + Workbench read paths | Repository | 1537 | ⭐ coordination_surface: Library storage used by Inbox/Workbench | ⭐G V: 1500+ line repository | 0 | behavioral |
| `Library/LibrarySyncService.swift` | consumer: Library registry/filesystem sync | Service | 311 |  |  | 0 | behavioral |
| `Library/LibraryWriteTransaction.swift` | consumer: Inbox apply + Library writes | Infrastructure | 87 | ⭐ consumer: Inbox+Library write transaction |  | 0 | behavioral |
| `Library/LibraryXLSXSyncService.swift` | consumer: Library XLSX sync | Service | 663 |  | ⭐G V: 600+ line sync service | 0 | behavioral |
| `Library/SpinLabFileSidecar.swift` | consumer: Library sidecars + Inbox apply + Workbench search | Domain/Persistence model | 155 | ⭐ legitimate_cross_cutting: sidecar contract |  | 0 | direct |

### Workbench

| 文件 | 归属依据 | 层级归属 (s2) | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|
| `App/State/AnalysisVault.swift` | inline-doc: owned by WorkbenchFeatureStore | Store/Persistence | 135 |  |  | 0 | direct |
| `App/State/WorkbenchFeatureStore.swift` | consumer: WorkbenchView + workflow stores | Store | 877 | ⭐ coordination_surface: Workbench+Rules condition/rule draft types | ⭐G V: large store + embedded rule projection structs | 0 | direct |
| `App/State/WorkbenchState.swift` | consumer: WorkbenchFeatureStore state container | Store | 11 |  |  | 0 | behavioral |
| `Features/Workbench/AHEWorkspaceStore.swift` | consumer: AHE workspace state/orchestration | Store | 763 |  | ⭐G H: parallel workspace store protocols | 0 | direct |
| `Features/Workbench/AHEWorkspaceView.swift` | consumer: AHE workspace UI provider | UI | 276 |  |  | 0 | behavioral |
| `Features/Workbench/NewRuleEntrySheet.swift` | consumer: Workbench rule-entry sheet | UI | 137 | ⭐ consumer: Workbench+Rules rule entry |  | 0 | none |
| `Workbench/Modules/PlotSystem/Canvas/PlotCanvasMouseTracker.swift` | consumer: WorkbenchPlotCanvas mouse bridge | UI bridge | 88 |  |  | 0 | behavioral |
| `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | consumer: 3ω workspace state/orchestration | Store | 1517 |  | ⭐G H/V: largest workflow store + parallel protocols | 0 | direct |
| `Features/Workbench/ThreeOmegaWorkspaceView.swift` | consumer: 3ω workspace UI provider | UI | 447 |  |  | 0 | behavioral |
| `Features/Workbench/TokenMapEditor.swift` | consumer: Workbench condition/rule token map UI | UI | 62 | ⭐ consumer: Workbench+Rules condition editing |  | 0 | none |
| `Features/Workbench/UnitTagEditor.swift` | consumer: Workbench condition unit tag UI | UI | 70 | ⭐ consumer: Workbench+Rules condition editing |  | 0 | none |
| `Workbench/Modules/PlotSystem/Canvas/WorkbenchPlotCanvas.swift` | consumer: shared plot canvas | UI shell | 728 | ⭐ legitimate_cross_cutting within Workbench workflows | ⭐G H/V: plot shell + internal responsibilities | 1 | behavioral |
| `Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift` | consumer: Workbench plot controls wrapper | UI shell | 37 |  |  | 0 | none |
| `Features/Workbench/WorkbenchPlottingStore.swift` | consumer: plot-capability protocol | Capability protocol | 36 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | behavioral |
| `Features/Workbench/WorkbenchSharedComponents.swift` | consumer: shared Workbench UI components | UI helper | 10 |  |  | 0 | none |
| `Workbench/Modules/PlotSystem/Controls/Common/SharedPlotTextControls.swift` | consumer: shared title/X/Y override row | UI helper | 135 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | none |
| `Workbench/Modules/PlotSystem/Controls/Common/SharedPlotLabelOverrideField.swift` | consumer: shared inline label override field | UI helper | 60 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | none |
| `Features/Workbench/RSMViewSelector.swift` | consumer: RSM workflow-specific plot-control selector | UI helper | 28 |  |  | 0 | none |
| `Workbench/Modules/PlotSystem/Controls/Common/SharedPlotFontSizeControls.swift` | consumer: shared plot font-size pickers | UI helper | 46 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | none |
| `Workbench/V3/Heatmap/HeatmapColorScaleControls.swift` | consumer: heatmap color-scale UI control | UI helper | 27 |  |  | 0 | none |
| `Workbench/V3/Heatmap/HeatmapZLabelControl.swift` | consumer: heatmap optional Z/colorbar label control | UI helper | 21 |  |  | 0 | none |
| `Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchStandardPlotControls.swift` | consumer: shared plot controls | UI shell | 107 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | behavioral |
| `Features/Workbench/WorkbenchStatusArea.swift` | consumer: Workbench warnings/status UI | UI | 29 |  |  | 1 | none |
| `Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchTitleTemplateField.swift` | consumer: Workbench title template editor | UI | 38 |  |  | 0 | none |
| `Features/Workbench/WorkbenchTracePanel.swift` | consumer: Workbench trace UI | UI | 52 |  |  | 1 | none |
| `Features/Workbench/WorkbenchView.swift` | consumer: RootSplitView Workbench area | UI | 64 |  |  | 0 | behavioral |
| `Features/Workbench/WorkflowHitRow.swift` | consumer: Workbench search hit row | UI | 80 |  |  | 0 | none |
| `Features/Workbench/WorkflowRegistryView.swift` | consumer: Workbench read-only workflow list | UI | 125 | ⭐ consumer: Workbench+Rules workflow definitions |  | 0 | behavioral |
| `Features/Workbench/WorkflowWorkspaceProvider.swift` | consumer: workflow workspace protocols + warning log | Capability protocol | 177 | ⭐ legitimate_cross_cutting within Workbench workflows | ⭐G H: default hooks candidate | 0 | behavioral |
| `Features/Workbench/WorkflowWorkspaceRegistry.swift` | consumer: Workbench workflow view dispatch | UI registry | 39 |  |  | 0 | direct |
| `Features/Workbench/WorkflowWorkspaceShell.swift` | consumer: shared workflow workspace shell | UI shell | 567 | ⭐ legitimate_cross_cutting within Workbench workflows | ⭐G H/V: cross-workflow shell | 0 | direct |
| `Features/Workbench/XYRotationWorkspaceStore.swift` | consumer: XY Rotation workspace state/orchestration | Store | 623 |  | ⭐G H: parallel workspace store protocols | 0 | direct |
| `Features/Workbench/XYRotationWorkspaceView.swift` | consumer: XY Rotation workspace UI provider | UI | 101 |  |  | 0 | behavioral |
| `UseCases/AHEAxisDetector.swift` | consumer: AHE ingestion axis detection | UseCase helper | 111 |  |  | 0 | direct |
| `UseCases/AHEDataParser.swift` | consumer: AHE PPMS data parser | Parser | 70 |  |  | 0 | direct |
| `UseCases/BackfillMeasurementPlotIndexUseCase.swift` | consumer: Workbench legacy chart index backfill | UseCase | 55 | ⭐ consumer: Workbench+Library artifact index |  | 0 | behavioral |
| `UseCases/BuildAHEPlotPayloadUseCase.swift` | consumer: AHE plot payload assembly | UseCase | 23 |  |  | 0 | behavioral |
| `UseCases/BuildRunTraceProjectionUseCase.swift` | consumer: Workbench run trace presentation | UseCase | 32 |  |  | 0 | behavioral |
| `UseCases/IngestAHESelectionsUseCase.swift` | consumer: AHE selection ingestion | UseCase | 149 |  |  | 0 | direct |
| `UseCases/IngestThreeOmegaSelectionsUseCase.swift` | consumer: 3ω selection ingestion | UseCase | 234 |  |  | 0 | direct |
| `UseCases/IngestXYRotationSelectionsUseCase.swift` | consumer: XY Rotation selection ingestion | UseCase | 111 |  |  | 0 | direct |
| `UseCases/LegendDimensionResolver.swift` | consumer: Workbench chart legend dimension inference | UseCase helper | 141 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | behavioral |
| `UseCases/LoadLatestChartArtifactUseCase.swift` | consumer: Workbench latest chart artifact loading | UseCase | 48 | ⭐ consumer: Workbench+Library artifact paths |  | 0 | behavioral |
| `UseCases/LoadMeasurementDataUseCase.swift` | consumer: Workbench measurement data loading | UseCase | 40 | ⭐ consumer: Workbench+Library sidecars |  | 0 | behavioral |
| `UseCases/LoadMeasurementPlotIndexUseCase.swift` | consumer: Workbench chart index loading | UseCase | 40 | ⭐ consumer: Workbench+Library artifact index |  | 0 | behavioral |
| `UseCases/LoadRelatedChartsUseCase.swift` | consumer: Workbench related chart discovery | UseCase | 55 | ⭐ consumer: Workbench+Library artifact index |  | 0 | behavioral |
| `UseCases/LoadWorkbenchResultsUseCase.swift` | consumer: Workbench result loading | UseCase | 40 |  |  | 0 | behavioral |
| `UseCases/PersistChartArtifactUseCase.swift` | consumer: Workbench chart artifact persistence | UseCase | 206 | ⭐ consumer: Workbench+Library artifact paths |  | 0 | behavioral |
| `UseCases/PersistMeasurementDataUseCase.swift` | consumer: Workbench measurement data sidecar persistence | UseCase | 94 | ⭐ consumer: Workbench+Library sidecars |  | 0 | behavioral |
| `UseCases/SaveActiveChartToLibraryUseCase.swift` | consumer: Workbench save chart to Library | UseCase | 135 | ⭐ coordination_surface: Workbench→Library artifact save |  | 0 | direct |
| `UseCases/SearchWorkflowMeasurementsUseCase.swift` | consumer: Workbench search over Library measurements | UseCase | 371 | ⭐ coordination_surface: Workbench search over Library sidecars |  | 0 | direct |
| `UseCases/SidecarCompositionUseCase.swift` | consumer: Workbench sidecar metadata composition | UseCase | 70 | ⭐ consumer: Workbench+Library sidecar contract |  | 0 | behavioral |
| `UseCases/ThreeOmegaFitUseCase.swift` | consumer: 3ω fit computation | UseCase | 272 |  |  | 0 | direct |
| `UseCases/ThreeOmegaLVMParser.swift` | consumer: 3ω LVM parser | Parser | 215 |  |  | 0 | direct |
| `UseCases/ThreeOmegaPlotRenderer.swift` | consumer: 3ω plot payload/render helper | Renderer | 429 |  | ⭐G H: workflow-specific renderer parallel to XY/AHE render path | 0 | behavioral |
| `UseCases/ThreeOmegaScalingUseCase.swift` | consumer: 3ω chart scaling | UseCase | 276 |  |  | 0 | direct |
| `UseCases/ThreeOmegaStackOffsetUseCase.swift` | consumer: 3ω stack offset | UseCase | 51 |  |  | 0 | direct |
| `UseCases/WorkbenchTitleResolver.swift` | consumer: Workbench title template resolution | UseCase helper | 18 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | behavioral |
| `UseCases/XYRotationDATParser.swift` | consumer: XY Rotation DAT parser | Parser | 133 |  |  | 0 | direct |
| `UseCases/XYRotationLVMParser.swift` | consumer: XY Rotation LVM parser | Parser | 170 |  |  | 0 | direct |
| `UseCases/XYRotationPlotRenderer.swift` | consumer: XY Rotation plot payload/render helper | Renderer | 244 |  | ⭐G H: workflow-specific renderer parallel to 3ω/AHE render path | 0 | behavioral |
| `Workbench/V3/AHEIngestionContracts.swift` | consumer: AHE ingestion/result contracts | Domain/Contract | 48 |  |  | 0 | direct |
| `Workbench/V3/AHEPackContracts.swift` | consumer: AHE analysis pack Codable contracts | Domain/Contract | 64 |  |  | 0 | behavioral |
| `Workbench/V3/AnalysisPackProviding.swift` | consumer: workflow stores pack save/load | Capability protocol | 194 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/V3/ConditionAliasConfig.swift` | consumer: Workbench condition alias config | Config model | 92 | ⭐ consumer: Workbench+Library sidecar conditions |  | 0 | behavioral |
| `Workbench/V3/SeriesOrderAlignHelper.swift` | consumer: curve reorder alignment | UseCase helper | 22 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/Modules/PlotSystem/Preservation/TabRenderManager.swift` | consumer: workflow tab render state | Store helper | 381 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/V3/ThreeOmegaIngestionContracts.swift` | consumer: 3ω ingestion/result contracts | Domain/Contract | 258 |  |  | 0 | direct |
| `Workbench/V3/ThreeOmegaPackContracts.swift` | consumer: 3ω analysis pack Codable contracts | Domain/Contract | 93 |  |  | 0 | behavioral |
| `Workbench/V3/WorkbenchArtifactIdentity.swift` | consumer: chart/metric identity | UseCase helper | 96 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/V3/WorkbenchChartRenderer.swift` | consumer: render payload to PNG | Renderer | 604 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/V3/WorkbenchChartStyle.swift` | consumer: chart style params | Domain/Config | 38 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/V3/WorkbenchPlotLayout.swift` | consumer: chart layout/hit testing | Renderer helper | 429 | ⭐ legitimate_cross_cutting within Workbench workflows |  | 0 | direct |
| `Workbench/Modules/PlotSystem/Pipeline/WorkbenchRenderPipeline.swift` | consumer: shared chart render pipeline | Renderer pipeline | 191 | ⭐ legitimate_cross_cutting within Workbench workflows | ⭐G H: established shared render shell | 0 | direct |
| `Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift` | consumer: Workbench result/chart/metric contracts | Domain/Contract | 459 | ⭐ consumer: Workbench+Library artifact indexes |  | 0 | direct |
| `Workbench/V3/XYRotationIngestionContracts.swift` | consumer: XY Rotation ingestion/result contracts | Domain/Contract | 53 |  |  | 0 | direct |
| `Workbench/V3/XYRotationPackContracts.swift` | consumer: XY analysis pack Codable contracts | Domain/Contract | 66 |  |  | 0 | behavioral |

### Rules

| 文件 | 归属依据 | 层级归属 (s2) | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|
| `Features/RulesPanel/Components/MatchRulesEditor.swift` | consumer: RulesPanel match rule UI | UI component | 112 | ⭐ legitimate_cross_cutting within RulesPanel sections | ⭐G H: repeated match editor shell | 0 | behavioral |
| `Features/RulesPanel/Components/RegexField.swift` | consumer: RulesPanel regex input | UI component | 41 |  |  | 0 | none |
| `Features/RulesPanel/Components/RulesPanelErrorMatching.swift` | consumer: RulesPanel save error filtering | UI helper | 30 |  |  | 0 | behavioral |
| `Features/RulesPanel/Components/SaveErrorsBadge.swift` | consumer: RulesPanel save error badge | UI component | 38 |  |  | 0 | none |
| `Features/RulesPanel/RulesManagementStore.swift` | consumer: RulesPanel drafts/save/load + runtime rules files | Store | 580 | ⭐ coordination_surface: Rules config writes affect Inbox/Workbench/Registry | ⭐G V: draft schemas + store in one file | 0 | direct |
| `Features/RulesPanel/RulesPanelSection.swift` | consumer: RulesPanel section identity/order | UI model | 21 |  |  | 0 | behavioral |
| `Features/RulesPanel/RulesPanelView.swift` | consumer: rules management root UI | UI | 212 |  |  | 0 | behavioral |
| `Features/RulesPanel/RulesSectionShell.swift` | consumer: shared RulesPanel section save shell | UI shell | 112 | ⭐ legitimate_cross_cutting within RulesPanel sections | ⭐G H: section shell reused across config books | 0 | behavioral |
| `Features/RulesPanel/SectionPersistenceStrategy.swift` | consumer: RulesPanel section validation/persist hooks | Strategy/UseCase helper | 219 | ⭐ coordination_surface: cross-section workflow/condition validation | ⭐G H: section strategy protocol | 0 | direct |
| `Features/RulesPanel/Sections/FilenameTokenizationSection.swift` | consumer: filename tokenization config UI | UI | 275 | ⭐ consumer: Rules+Inbox parser behavior |  | 0 | behavioral |
| `Features/RulesPanel/Sections/ImportFiltersSection.swift` | consumer: import filter config UI | UI | 185 | ⭐ consumer: Rules+Inbox import pipeline |  | 0 | behavioral |
| `Features/RulesPanel/Sections/MeasuringConditionSection.swift` | consumer: measuring condition config UI | UI | 319 | ⭐ consumer: Rules+Workbench condition fields |  | 0 | behavioral |
| `Features/RulesPanel/Sections/SampleIdentificationSection.swift` | consumer: sample/substrate identification config UI | UI | 266 | ⭐ consumer: Rules+Registry+Inbox substrate semantics |  | 0 | behavioral |
| `Features/RulesPanel/Sections/WorkflowSection.swift` | consumer: workflow config UI | UI | 364 | ⭐ consumer: Rules+Workbench workflow definitions |  | 0 | behavioral |
| `Import/Rules/ConditionFieldCatalog.swift` | consumer: Workbench condition field options | Rule helper | 54 | ⭐ consumer: Rules+Workbench |  | 0 | behavioral |
| `Import/Rules/FileRoutingSemanticRules.swift` | consumer: Inbox route semantic rules from rule set | Rule helper | 67 | ⭐ consumer: Rules+Inbox routing |  | 0 | direct |
| `Import/Rules/FilenameRuleSet.swift` | consumer: parser/routing/RulesPanel/Workbench rule semantics | Domain/Rule model | 956 | ⭐ legitimate_cross_cutting: canonical rule contract | ⭐G V: schema + compile + evaluate | 0 | direct |
| `Import/Rules/RuleCanonicalizer.swift` | consumer: RulesPanel save canonicalization | UseCase helper | 144 |  |  | 0 | behavioral |
| `Import/Rules/RuleEntryKind.swift` | consumer: rule-entry UI/validation | Rule model | 11 | ⭐ consumer: RulesPanel+Workbench entry UI |  | 0 | behavioral |
| `Import/Rules/RuleLoader.swift` | consumer: app-wide runtime/bundle rule loading | Repository/Loader | 608 | ⭐ coordination_surface: runtime rules feed Inbox/Workbench/Registry | ⭐G V: cache + load + assemble + hash | 0 | direct |
| `Import/Rules/RuleRef.swift` | consumer: explainable route/rule references | Rule model | 86 | ⭐ consumer: Rules+Inbox presentation |  | 0 | behavioral |
| `Import/Rules/RulesBootstrapper.swift` | consumer: startup migration of runtime rule files | Migration service | 1117 | ⭐ migration_candidate: legacy runtime config migration | ⭐G V: multi-version JSON migration monolith | 0 | direct |
| `Import/Rules/RulesConfigPaths.swift` | consumer: runtime rules file layout | Config paths | 73 | ⭐ legitimate_cross_cutting: runtime config paths |  | 0 | direct |
| `Import/Rules/RulesPersistenceHook.swift` | consumer: immediate rule reload after save | Persistence hook | 5 | ⭐ coordination_surface: RulesPanel save affects runtime rule cache |  | 0 | behavioral |
| `Import/Rules/SpinLabRuleProvider.swift` | consumer: injectable rules capability | Capability protocol/provider | 78 | ⭐ legitimate_cross_cutting: rules DI for Inbox/Registry |  | 0 | direct |
| `Import/Rules/WorkflowRegistryRetirementService.swift` | consumer: migrate retired outer workflow registry into workflow.json | Migration service | 109 | ⭐ migration_candidate: old workflow registry cleanup |  | 0 | direct |

### 跨区共享

| 文件 | 归属依据 | 层级归属 (s2) | 行数 | 共享 | 平行 | TODO | 测试 |
|---|---|---|---|---|---|---|---|
| `App/AppEnvironment.swift` | consumer: SpinLabAppState dependency injection | AppShell/DI | 25 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `App/AppError.swift` | consumer: app-wide error surface | Error model | 39 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `App/AppLogger.swift` | consumer: app-wide logging | Infrastructure | 180 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `App/AppVersion.swift` | consumer: RootSplitView display | AppShell | 5 |  |  | 0 | none |
| `SpinLabApp.swift` | consumer: app entry + AppState/environment install | App entry | 48 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `App/AuditEvent.swift` | consumer: AuditLogger + Inbox/Library writes | Audit model | 12 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `App/AuditLogger.swift` | consumer: Inbox/Library audit writes | Infrastructure | 116 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `App/InteractionMemoryStore.swift` | consumer: interaction snapshot persistence | Infrastructure | 98 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `App/InteractionSnapshotCoordinator.swift` | consumer: AppState interaction snapshot load/save | Coordinator | 106 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `App/InteractionSnapshotKeyCodec.swift` | consumer: Inbox/interaction dictionary keys | Utility | 7 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `App/RegistryCoordinator.swift` | consumer: AppState/RegistryFacade; registry drives Inbox routing + Library preview | Coordinator | 103 | ⭐ coordination_surface: Inbox+Library registry |  | 0 | behavioral |
| `App/RegistryFacade.swift` | consumer: AppState registry facade; async registry workflow | Facade/Orchestrator | 103 | ⭐ coordination_surface: Inbox+Library registry |  | 0 | behavioral |
| `App/RegistryLifecycleService.swift` | consumer: RegistryCoordinator lifecycle helper | Service | 43 | ⭐ coordination_surface: Inbox+Library registry |  | 0 | behavioral |
| `App/RootSplitView.swift` | consumer: app root UI + navigation | UI shell | 259 | ⭐ legitimate_cross_cutting |  | 0 | none |
| `App/ServiceOutcome.swift` | consumer: app workflow outcome wrappers | Utility | 13 | ⭐ legitimate_cross_cutting |  | 0 | none |
| `App/SidebarMenuModel.swift` | consumer: RootSplitView/SidebarTreeView | UI model | 70 | ⭐ legitimate_cross_cutting |  | 0 | none |
| `App/SidebarTreeView.swift` | consumer: RootSplitView sidebar | UI shell | 123 | ⭐ legitimate_cross_cutting |  | 0 | none |
| `App/SpinLabAppState.swift` | consumer: root environment; coordinates all stores | AppShell/Coordinator | 1816 | ⭐ coordination_surface: all stores | ⭐G V: 1800+ line app coordinator | 0 | behavioral |
| `App/SpinLabDataActor.swift` | consumer: AppState/Registry/Library/Workbench async I/O | Data actor | 61 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `App/SpinLabSidebarMenuProvider.swift` | consumer: RootSplitView sidebar model assembly | UI shell | 155 | ⭐ legitimate_cross_cutting |  | 0 | none |
| `App/State/AppCoordinator.swift` | consumer: AppState cross-area route resolution | Coordinator | 28 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `App/State/AppRouter.swift` | consumer: RootSplitView navigation/deep-link | Navigation | 92 | ⭐ legitimate_cross_cutting |  | 0 | none |
| `App/State/InteractionStateModels.swift` | consumer: interaction snapshots across Inbox/Library/sidebar | Interaction model | 376 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `App/State/RegistryFeatureStore.swift` | consumer: registry presentation used by Inbox/Library flows | Store | 13 | ⭐ coordination_surface: Registry not standalone region |  | 0 | direct |
| `Domain/AnalysisPack.swift` | consumer: Workbench packs + tests; domain envelope | Domain | 84 | ⭐ legitimate_cross_cutting |  | 0 | direct |
| `Domain/Models.swift` | consumer: Inbox/Library/Workbench shared domain | Domain | 474 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `Domain/RecomputePreviewItem.swift` | consumer: Library recompute UI/logic | Domain/Projection | 43 |  |  | 0 | behavioral |
| `Domain/WorkflowSearchModels.swift` | consumer: Workbench search + Library sidecar index | Domain/Search model | 102 | ⭐ legitimate_cross_cutting |  | 0 | behavioral |
| `Extensions/ExtensionPoints.swift` | consumer: workflow extension contracts + built-in extension descriptors | Extension contract | 473 | ⭐ legitimate_cross_cutting: workflow extension architecture | ⭐G H: extension descriptors repeat workflow/module/view shape | 0 | behavioral |
| `Import/Parse/SampleKeyNormalizer.swift` | consumer: Inbox routing + Workbench search + drawer matching | Shared parser/helper | 71 | ⭐ migration_candidate: Import helper consumed outside Inbox |  | 0 | behavioral |
| `Import/Parse/SampleSemanticDescriptor.swift` | consumer: Inbox route + Workbench search/ingestion + Library parser | Shared domain/parser model | 130 | ⭐ migration_candidate: Domain-like type under Import |  | 0 | behavioral |
| `Import/Parse/SampleTokenization.swift` | consumer: Inbox matching + Workbench search | Shared parser/helper | 56 | ⭐ migration_candidate: Import helper consumed outside Inbox |  | 0 | behavioral |
| `Import/RegistrySubstrateRuleBook.swift` | consumer: AppEnvironment/ArchivedRecordResolver + registry substrate tests | Shared rulebook | 264 | ⭐ coordination_surface: Registry+Inbox+Rules |  | 0 | direct |
| `Registry/RegistryLookupRuleBook.swift` | consumer: SampleRegistry lookup aliases from Rules | Shared rulebook | 85 | ⭐ coordination_surface: Registry+Rules |  | 0 | direct |
| `Registry/RegistrySheetFilter.swift` | consumer: registry sheet exclusion | Utility | 14 | ⭐ consumer: Registry+Rules excludedSheetNames |  | 0 | behavioral |
| `Registry/SampleRegistry.swift` | consumer: Registry index for Inbox routing + Library workspace | Repository/Index | 334 | ⭐ coordination_surface: Registry+Inbox+Library |  | 0 | behavioral |
| `Registry/XLSXSheetValueReader.swift` | consumer: Registry XLSX cell parsing | Parser helper | 81 |  |  | 0 | behavioral |
| `Persistence/Persistence.swift` | consumer: legacy/local JSON persistence protocol + sample data | Persistence | 252 | ⭐ legitimate_cross_cutting: generic persistence abstraction |  | 0 | behavioral |
| `Repositories/DomainRepositories.swift` | consumer: Inbox/Library in-memory repositories | Repository | 223 | ⭐ legitimate_cross_cutting: repo abstraction for multiple domains |  | 0 | behavioral |
| `Storage/AtomicFileWriter.swift` | consumer: RulesSyncEngine atomic writes | Storage helper | 85 | ⭐ legitimate_cross_cutting: atomic write capability |  | 0 | direct |
| `Storage/ManagedStorage.swift` | consumer: managed import/library file storage | Storage service | 256 | ⭐ consumer: Inbox+Library file lifecycle |  | 0 | behavioral |
| `Storage/RepositoryPointer.swift` | consumer: library/repository root pointers | Storage model | 130 | ⭐ legitimate_cross_cutting: repository pointer contract |  | 0 | behavioral |
| `Storage/RulesSyncEngine.swift` | consumer: runtime/bundle rules dual-write/startup sync | Storage/Sync service | 216 | ⭐ coordination_surface: Rules runtime state + startup sync |  | 0 | direct |
| `UI/AppColumnShell.swift` | consumer: shared column shell layout | UI shell | 64 | ⭐ legitimate_cross_cutting UI | ⭐G H: shared app column shell | 0 | none |
| `UI/AppFontScale.swift` | consumer: shared font scale constants | UI token | 16 | ⭐ legitimate_cross_cutting UI |  | 0 | none |
| `UI/AppSpacing.swift` | consumer: shared spacing constants | UI token | 25 | ⭐ legitimate_cross_cutting UI |  | 0 | none |
| `UI/CollapsibleSectionHeader.swift` | consumer: shared collapsible section header | UI component | 29 | ⭐ legitimate_cross_cutting UI |  | 0 | none |
| `UI/FlowLayout.swift` | consumer: shared wrapping flow layout | UI layout | 51 | ⭐ legitimate_cross_cutting UI |  | 0 | none |
| `UI/HoverPopoverModifier.swift` | consumer: shared hover popover behavior | UI modifier | 101 | ⭐ legitimate_cross_cutting UI |  | 0 | none |
| `UI/MetadataViews.swift` | consumer: shared metadata rows/fields | UI component | 59 | ⭐ legitimate_cross_cutting UI |  | 0 | none |
| `Workflow/WorkflowDefinition.swift` | consumer: Rules config + Workbench/Inbox workflow display | Domain/Config model | 37 | ⭐ legitimate_cross_cutting: workflow config contract |  | 0 | behavioral |
| `Workflow/WorkflowDefinitionStore.swift` | consumer: Workbench store reads workflow.json definitions | Repository | 28 | ⭐ coordination_surface: Rules-owned config consumed by Workbench |  | 0 | direct |
| `Workflow/WorkflowID.swift` | consumer: workflow canonical IDs/aliases | Domain/Config model | 70 | ⭐ legitimate_cross_cutting: workflow identity contract |  | 0 | behavioral |
| `Workflow/WorkflowRegistry.swift` | consumer: extension bundle registry | Infrastructure | 105 | ⭐ legitimate_cross_cutting: workflow extensions |  | 0 | behavioral |

### `[暧昧]` 清单（s2 第二轮判断）

| 文件 | 候选区块 | 行数 | 暧昧原因 |
|---|---|---|---|

无。s1 全量扫描后没有留下 `[暧昧]` 文件；s2 无需回收。

### `[未确定]` 清单（s2 后入中期债条目候选）

无。s2 层级归属可通过上方规范族解释，当前没有需要升级为 `[未确定]` 的文件。

---

## 附录 A — 大文件清单（行数 > 500）

> s1 起手前置步骤产出。s4 收敛时拆出独立文档，作为中期拆文件立项依据。

| 文件 | 行数 | 区块 | 备注 |
|---|---|---|---|
| `App/SpinLabAppState.swift` | 1816 | 跨区共享 | App coordinator，已入附录 G |
| `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | 1517 | Workbench | workflow store + pack/render/provider protocols，已入附录 G |
| `Library/LibraryStore.swift` | 1537 | Library | repository + filesystem/index/archive helpers，已入附录 G |
| `App/State/LibraryFeatureStore.swift` | 1145 | Library | Store 主体，已入附录 G |
| `Import/Rules/RulesBootstrapper.swift` | 1117 | Rules | multi-version runtime JSON migration，已入附录 G |
| `Import/Rules/FilenameRuleSet.swift` | 956 | Rules | rule schema + compile/evaluate，已入附录 G |
| `App/State/WorkbenchFeatureStore.swift` | 877 | Workbench | Store 主体，已入附录 G |
| `Features/Workbench/AHEWorkspaceStore.swift` | 763 | Workbench | workflow store + shared protocols，已入附录 G |
| `Workbench/Modules/PlotSystem/Canvas/WorkbenchPlotCanvas.swift` | 728 | Workbench | 共享 plot shell，已入附录 G |
| `Library/LibraryXLSXSyncService.swift` | 663 | Library | XLSX sync service，已入附录 G |
| `Features/Workbench/XYRotationWorkspaceStore.swift` | 623 | Workbench | workflow store + shared protocols，已入附录 G |
| `Import/Rules/RuleLoader.swift` | 608 | Rules | runtime/bundle loader + cache + assembly，已入附录 G |
| `Workbench/V3/WorkbenchChartRenderer.swift` | 604 | Workbench | shared chart renderer |
| `Features/Library/LibraryWorkspaceSections.swift` | 587 | Library | multi-section Library UI，已入附录 G |
| `Features/RulesPanel/RulesManagementStore.swift` | 580 | Rules | draft schemas + save/load store，已入附录 G |
| `Features/Workbench/WorkflowWorkspaceShell.swift` | 567 | Workbench | shared workflow shell，已入附录 G |
| `Library/LibraryRegistryParser.swift` | 545 | Library | registry parser + substrate parser |

## 附录 B — 共享候选清单

> 跨区共享疑似项。s3 起步直接从此清单扫。

| 文件 | 嗅探信号 | s3 实证状态 |
|---|---|---|
| `App/ApplyCoordinator.swift` | Inbox apply 调用 LibraryStore + InboxArchiveApplyService | pending |
| `App/ArchivedRecordResolverService.swift` | Inbox archive 需要 registry lookup / substrate rules | pending |
| `App/InboxArchiveApplyService.swift` | Inbox pending → Library drawer write + audit | pending |
| `App/InboxFacade.swift` | Inbox facade 读 Rules/Workbench condition options 并回写 interaction state | pending |
| `App/InboxWorkflowService.swift` | Inbox recompute 依赖 rules-derived hints | pending |
| `App/RegistryCoordinator.swift` | Registry 同时服务 Inbox routing metadata 与 Library preview/reload | pending |
| `App/RegistryFacade.swift` | Registry async workflow 跨 AppState / Inbox / Library | pending |
| `App/RegistryLifecycleService.swift` | Registry lifecycle helper 跨 registry install/load/reload | pending |
| `App/SpinLabAppState.swift` | all stores + global coordination | pending |
| `App/State/RegistryFeatureStore.swift` | Registry 没有独立区块，当前作为 Inbox+Library 协调面 | pending |
| `App/State/WorkbenchFeatureStore.swift` | Workbench store 内含 condition/rule draft projection | pending |
| `Features/Inbox/InboxSelectionWorkbenchPanel.swift` | Inbox UI writes route/workflow/condition drafts in one panel | pending |
| `Import/ImportPipeline.swift` | Import filtering uses Rules provider at pipeline construction | pending |
| `Import/Match/DrawerMatchEngine.swift` | Inbox matching consumes Library sample models | pending |
| `Import/Parse/FilenameRuleParser.swift` | Parser consumes Rules ruleSet directly | pending |
| `Import/Parse/SampleKeyNormalizer.swift` | Import helper consumed by Workbench search / matching | pending |
| `Import/Parse/SampleSemanticDescriptor.swift` | Domain-like sample semantics live under Import but used by Workbench/Library | pending |
| `Import/Parse/SampleTokenization.swift` | Import tokenization helper consumed by Workbench search | pending |
| `Import/RegistrySubstrateRuleBook.swift` | Registry substrate resolution depends on Rules and feeds Inbox archive warnings | pending |
| `Import/Route/FileRoutingRuleBook.swift` | Routing rulebook depends on semantic rules from Rules layer | pending |
| `Features/Library/MeasurementDataSectionView.swift` | Library UI displays Workbench measurement data contracts | pending |
| `Features/Library/MeasurementPlotPreviewPanel.swift` | Library preview reads Workbench chart artifacts | pending |
| `Features/Library/RecomputePreviewPanel.swift` | Library recompute UI presents rules-derived changes | pending |
| `Library/LibraryLogger.swift` | Library logging overlaps app-wide audit semantics | pending |
| `Library/LibraryModels.swift` | Library models consumed by Inbox apply and Workbench persistence paths | pending |
| `Library/LibraryPathResolver.swift` | Workbench artifact paths live under Library root | pending |
| `Library/LibraryRegistryParser.swift` | Library parser consumes shared sample semantic descriptor | pending |
| `Library/LibraryStore.swift` | Library repository called from Inbox apply and Workbench reads | pending |
| `Library/LibraryWriteTransaction.swift` | Inbox apply uses Library write transaction | pending |
| `Library/SpinLabFileSidecar.swift` | Sidecar contract feeds Inbox apply, Library archive, Workbench search | pending |
| `Features/Workbench/NewRuleEntrySheet.swift` | Workbench UI creates rule-like entries | pending |
| `Features/Workbench/TokenMapEditor.swift` | Workbench UI edits condition/rule token maps | pending |
| `Features/Workbench/UnitTagEditor.swift` | Workbench UI edits condition/rule units | pending |
| `Features/Workbench/WorkflowRegistryView.swift` | Workbench displays Rules-owned workflow definitions | pending |
| `Workflow/WorkflowDefinitionStore.swift` | Rules-owned workflow config consumed by Workbench | pending |
| `Features/RulesPanel/RulesManagementStore.swift` | RulesPanel runtime config save immediately affects Inbox/Workbench/Registry behavior | pending |
| `Features/RulesPanel/RulesSectionShell.swift` | Shared save/reload shell used by RulesPanel sections | pending |
| `Features/RulesPanel/SectionPersistenceStrategy.swift` | Cross-section validation couples workflow condition IDs to measuring condition definitions | pending |
| `Features/RulesPanel/Sections/FilenameTokenizationSection.swift` | Rules UI edits parser behavior consumed by Inbox route planning | pending |
| `Features/RulesPanel/Sections/ImportFiltersSection.swift` | Rules UI edits import filter behavior consumed by Inbox pipeline | pending |
| `Features/RulesPanel/Sections/MeasuringConditionSection.swift` | Rules UI edits Workbench condition field semantics | pending |
| `Features/RulesPanel/Sections/SampleIdentificationSection.swift` | Rules UI edits substrate semantics consumed by Registry/Inbox | pending |
| `Features/RulesPanel/Sections/WorkflowSection.swift` | Rules UI edits workflow definitions consumed by Workbench | pending |
| `Import/Rules/ConditionFieldCatalog.swift` | Workbench condition options derive from Rules definitions | pending |
| `Import/Rules/FileRoutingSemanticRules.swift` | Inbox routing semantic rules derive from rule set | pending |
| `Import/Rules/FilenameRuleSet.swift` | Canonical rule contract feeds parser/routing/RulesPanel/Workbench | pending |
| `Import/Rules/RuleEntryKind.swift` | Rule-entry UI is shared by RulesPanel and Workbench entry points | pending |
| `Import/Rules/RuleLoader.swift` | Runtime rules loader feeds app-wide routing/search/registry semantics | pending |
| `Import/Rules/RuleRef.swift` | Rule references surface in Inbox explanations | pending |
| `Import/Rules/RulesConfigPaths.swift` | Runtime config paths used by loader, bootstrapper, RulesPanel save | pending |
| `Import/Rules/RulesPersistenceHook.swift` | RulesPanel save invalidates/reloads runtime rule cache | pending |
| `Import/Rules/SpinLabRuleProvider.swift` | Rules capability injected into Inbox/Registry rule consumers | pending |
| `Registry/RegistryLookupRuleBook.swift` | Registry lookup aliases come from Rules registry config | pending |
| `Registry/RegistrySheetFilter.swift` | Registry sheet filtering comes from Rules excluded-sheet config | pending |
| `Registry/SampleRegistry.swift` | Registry index feeds Inbox routing metadata and Library workspace | pending |
| `UseCases/BackfillMeasurementPlotIndexUseCase.swift` | Workbench backfill touches Library chart artifact index | pending |
| `UseCases/LibraryDestinationSubpath.swift` | Library destination subpath shared by Library and Workbench persistence | pending |
| `UseCases/LoadLatestChartArtifactUseCase.swift` | Workbench loads chart artifacts from Library-managed paths | pending |
| `UseCases/LoadMeasurementDataUseCase.swift` | Workbench loads Library sidecar measurement data | pending |
| `UseCases/LoadMeasurementPlotIndexUseCase.swift` | Workbench reads Library chart index sidecars | pending |
| `UseCases/LoadRelatedChartsUseCase.swift` | Workbench related chart discovery reads Library artifact index | pending |
| `UseCases/PersistChartArtifactUseCase.swift` | Workbench writes chart artifacts under Library paths | pending |
| `UseCases/PersistMeasurementDataUseCase.swift` | Workbench writes measurement sidecars under Library paths | pending |
| `UseCases/SaveActiveChartToLibraryUseCase.swift` | Workbench command persists active chart into Library | pending |
| `UseCases/SaveLibrarySampleEditsUseCase.swift` | Library sample edits optionally sync registry source | pending |
| `UseCases/SearchWorkflowMeasurementsUseCase.swift` | Workbench search scans Library sidecars | pending |
| `UseCases/SidecarCompositionUseCase.swift` | Workbench composes Library sidecar metadata contract | pending |
| `Extensions/ExtensionPoints.swift` | Workflow extension architecture repeats workflow/module/view descriptor shape | pending |
| `Storage/ManagedStorage.swift` | Managed storage spans import files and library files | pending |
| `Storage/RulesSyncEngine.swift` | Startup/rules sync owns runtime rule state used by RulesPanel/RuleLoader | pending |
| `UI/AppColumnShell.swift` | Shared column shell should remain generic UI shell | pending |

## 附录 C — TODO / FIXME / XXX 收割

> 一次性 grep 全 swift 文件产出。中期债条目候选库。

| 文件 | 行号 | 类别 | 内容 |
|---|---|---|---|
| `Features/Workbench/WorkbenchTracePanel.swift` | 14 | TODO(用户设计) | 调整 label 列宽、字号、是否折叠显示 |
| `Features/Workbench/WorkbenchStatusArea.swift` | 15 | TODO(用户设计) | 考虑是否合并为单条消息、是否加图标前缀 |
| `Workbench/Modules/PlotSystem/Canvas/WorkbenchPlotCanvas.swift` | 55 | TODO(用户设计) | 调整最小高度、背景样式、空状态文字 |
| `Import/Rules/RulesBootstrapper.swift` | 1059 | false-positive | `dateFormat` 字符串含 `XXX`，不是 TODO / FIXME / XXX 注释 |

## 附录 D — 测试覆盖盲区清单

> s1 顺手记录"无对应测试"的关键文件。5.1.3 测试基础设施的延续输入。

| 文件 | 区块 | 行数 | 优先级 |
|---|---|---|---|
| `App/RootSplitView.swift` | 跨区共享 | 259 | Medium：根 UI 无 direct test，行为多靠集成 |
| `App/State/AppRouter.swift` | 跨区共享 | 92 | Medium：deep-link / route stack 当前无 direct test |
| `App/SidebarTreeView.swift` | 跨区共享 | 123 | Low：UI shell，无 direct test |
| `App/SpinLabSidebarMenuProvider.swift` | 跨区共享 | 155 | Low：sidebar model assembly 无 direct test |
| `Features/Inbox/InboxInspectorPanel.swift` | Inbox | 102 | Low：reserved/inspector UI 无 direct test |
| `Features/Inbox/InboxProgressOverlays.swift` | Inbox | 85 | Low：progress overlay UI 无 direct test |
| `Features/Library/LibraryExistingDrawerSampleSectionView.swift` | Library | 72 | Low：detail UI 无 direct test |
| `Features/Library/LibrarySheets.swift` | Library | 289 | Low：sheet UI 无 direct test |
| `Features/Library/LibraryViewSupport.swift` | Library | 64 | Low：UI support rows/models 无 direct test |
| `Features/Library/LibraryWorkspaceSections.swift` | Library | 587 | Medium：大 UI section 文件无 direct test |
| `Features/Workbench/NewRuleEntrySheet.swift` | Workbench | 137 | Low：sheet UI 无 direct test |
| `Features/Workbench/TokenMapEditor.swift` | Workbench | 62 | Low：rule editor UI 无 direct test |
| `Features/Workbench/UnitTagEditor.swift` | Workbench | 70 | Low：unit editor UI 无 direct test |
| `Features/Workbench/WorkbenchStatusArea.swift` | Workbench | 29 | Low：status UI 无 direct test |
| `Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchTitleTemplateField.swift` | Workbench | 38 | Low：title field UI 无 direct test |
| `Features/Workbench/WorkbenchTracePanel.swift` | Workbench | 52 | Low：trace UI 无 direct test |
| `Features/Workbench/WorkflowHitRow.swift` | Workbench | 80 | Low：search-hit UI 无 direct test |
| `Features/RulesPanel/Components/RegexField.swift` | Rules | 41 | Low：regex input UI 无 direct test |
| `Features/RulesPanel/Components/SaveErrorsBadge.swift` | Rules | 38 | Low：save error badge UI 无 direct test |
| `UI/AppColumnShell.swift` | 跨区共享 | 64 | Low：shared layout shell 无 direct test |
| `UI/AppFontScale.swift` | 跨区共享 | 16 | Low：UI token 无 direct test |
| `UI/AppSpacing.swift` | 跨区共享 | 25 | Low：UI token 无 direct test |
| `UI/CollapsibleSectionHeader.swift` | 跨区共享 | 29 | Low：shared UI component 无 direct test |
| `UI/FlowLayout.swift` | 跨区共享 | 51 | Low：custom layout 无 direct test |
| `UI/HoverPopoverModifier.swift` | 跨区共享 | 101 | Low：hover UI behavior 无 direct test |
| `UI/MetadataViews.swift` | 跨区共享 | 59 | Low：metadata UI component 无 direct test |

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
| G-002 | V | `SpinLabAppState.swift` 1816 行 app coordinator | 维持 App shell，但继续迁出单域 workflow 到 FeatureStore/facade | all-store coordination + persistence + registry + inbox hooks | s1.a 锚点；只记录，不立即拆 |
| G-003 | V | `LibraryFeatureStore.swift` 1145 行主 store + 多 extension | 评估是否继续垂直拆 projection / mutation / selection 子模块 | Library projection/mutation/selection responsibilities | s1.a 锚点；已有 partial extensions |
| G-004 | V | `WorkbenchFeatureStore.swift` 877 行且嵌入 condition/rule draft structs | 评估 Rules projection 是否迁出或收敛为明确 coordination surface | Workbench + Rules condition/rule projection | 关联 5.1.8 后续结构债 |
| G-005 | V | `LibraryStore.swift` 1537 行 repository | 评估 filesystem index / drawer ops / archive helpers 是否继续垂直拆 | repository + filesystem + archive responsibilities | s1.b 记录；不立即拆 |
| G-006 | H | `ThreeOmegaWorkspaceStore` / `XYRotationWorkspaceStore` / `AHEWorkspaceStore` 都实现同组 workspace protocols | 抽取更强 default extension 或 shared helper where semantics identical | workflow store protocol boilerplate | 与 G-001 相关，需等 s3 实证重复度 |
| G-007 | H+V | `WorkbenchPlotCanvas.swift` 728 行 shared plot shell | 保持 cross-workflow shell，评估内部按 title/grid/legend/font/copy PNG 再拆 | plot canvas shell 已横向共享但内部职责多 | 哲学样板点名对象 |
| G-008 | H+V | `WorkflowWorkspaceShell.swift` 567 行 shared workflow shell | 保持 shell，评估 warning/search/action/plot slots 内部分层 | shell 横向共享；内部 UI responsibilities 多 | s1.b 记录；不立即拆 |
| G-009 | V | `LibraryWorkspaceSections.swift` 587 行多 section UI | 评估按 settings / registry / search sections 垂直拆 | Library workspace section responsibilities | s1.b 记录；不立即拆 |
| G-010 | V | `RulesBootstrapper.swift` 1117 行 migration service | 评估按 schema migration step / atomic write / state tracking 拆分 | 多版本 JSON 迁移集中在单文件 | s1.c 记录；不立即拆 |
| G-011 | V | `FilenameRuleSet.swift` 956 行 rule contract | 评估 schema structs / compile / evaluation 是否分文件 | canonical rule model 同时承载编译与求值 | s1.c 记录；不立即拆 |
| G-012 | V | `RuleLoader.swift` 608 行 loader | 评估 runtime/bundle loading、cache、assembly/hash 分层 | loader 同时做 cache invalidation、schema assembly、hash | s1.c 记录；不立即拆 |
| G-013 | V | `RulesManagementStore.swift` 580 行 store + draft schema | 评估 draft Codable schemas 与 observable store 拆分 | 多个 config book draft + save/load 状态同文件 | s1.c 记录；不立即拆 |
| G-014 | H | `RulesSectionShell` + `SectionPersistenceStrategy` + 5 section views | 保持 section shell，评估策略协议是否成为规则配置编辑统一壳 | 5 个 config book 共用 save/reload/validate/persist 形态 | 与 v5.1.5-s12 match editor 样板同类 |
| G-015 | H | `ThreeOmegaPlotRenderer` / `XYRotationPlotRenderer` / AHE payload builder | 评估 workflow plot payload/render helper 是否可共享抽壳 | workflow-specific renderer 形态相似但语义不同 | s1.d 记录；s3 需实证重复度 |
| G-016 | H | `ExtensionPoints.swift` 内 built-in workflow extension descriptors | 评估扩展 descriptor 注册/metadata/module/view 是否拆为 per-workflow 文件或 registry shell | 多 workflow extension descriptors 同文件重复结构 | s1.d 记录；不立即拆 |

_(s1 扫描时持续追加。每条 ID 编号，类型 H / V，候选形态精简描述。)_

### 样板参照

- **横向 H 样板**：v5.1.5-s12 `UnifiedMatchRuleEditor` —— 5 处匹配 UI + 4 操作集封闭单壳化
- **横向 + 纵向（H+V）样板**：`WorkbenchPlotCanvas` —— 提供画图能力给 3 workflow（H）；intent 是内部按 title / grid / legend / font / copy-PNG 分层（V，需 s1 实地验证）
