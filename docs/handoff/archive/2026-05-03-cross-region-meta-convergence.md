# 5.1.14a Cross-Region Meta 收敛 —— 第 3 稿（定稿候选）

> **流水线**：第 1 稿（Claude）→ Codex 第 1 轮 adopt-with-fixes → Jack 拍板方案 A + 防回归 → 第 2 稿 → Codex 收敛轮 adopt-with-fixes → 第 3 稿（本文件）。
>
> **第 3 稿吸收 Codex 收敛轮 10 项修订**：
> 1. §3 修订表写全（owner / 输入 / 输出 / INV / 禁止事项 5 列）
> 2. INV-8 去「5 个替身」计数 → 「所有 side-effect dep 可注入并被实际使用」
> 3. 补 INV-15 / INV-16 / INV-17（共 **17 条**）
> 4. INV-11/12/13 形态升级：architecture verification test wrapper（不裸 grep）
> 5. L-3/L-4/L-5/B-4/NEW-1 政策补「Tier 1 仅含 contract/schema，loader/evaluator/parser/service **不**得随搬」
> 6. L-2 派轮次复核：确认不依赖 14c LibraryAccess → 留 14b（14b-c4 不读 Library，仅改 metric 数据源）
> 7. 14c-c8 / 14d-c5 跨轮依赖明确：c8 必须排 c5/c6 后；d-c5 依赖 c6 切线
> 8. 14b-c0 政策文本补「Tier 1 Domain 仅装 contract，legitimate_cross_cutting 标记保留作 collaborator 注释 + 不预承诺路径，先写判据」段
> 9. §8 风险补「Tier 1 搬时强制 Codable/Hashable/Sendable conformance」+「Code Map 登记规则：主 owner 一处」
> 10. §9 增 `docs/features.md` 同步决策（INV 作长期不变式则同步）

---

## §0 防回归测试不变式（17 条）

| INV | 不变式 | 守护 | 轮次 | 测试形态 |
|---|---|---|---|---|
| INV-1 | RuleLoader save → cache 更新 → onRulesSaved 三步顺序不变；保存后立即重算读到新规则 | D-6 | 14b-c1 | `V5114RulesLiveReloadOrderTests` mock callback 记录顺序 |
| INV-2 | pack restore 不重新提交 trace；vault 写幂等 | L-1 | 14b-c2 | `V5114PackRestoreNoTraceCommitTests` fixture vault + restore 后 trace count 不变 |
| INV-3 | sidecar fail-soft 三种失败必分型 logger.error | B-3 | 14b-c3 | `V5114SidecarFailSoftLoggingTests` 三失败注入 + assert log entry |
| INV-4 | AHE metric 仅从 typed ingestion metadata 读 sampleKey | L-2 | 14b-c4 | `V5114AHEMetricSourceTests` label="X" + metadata="Y"，assert 读 Y |
| INV-5 | renderer stateless：连续两次 `_render` 无 state 残留 | D-4 | 14b-c5 | `V5114RendererStatelessTests` 两轮 warning count 独立 |
| INV-6 | sidecar contract 三 region round-trip JSON 不丢字段 | L-3 | 14d-c5 | `V5114SidecarContractRoundTripTests` 三 region 序列化往返 |
| INV-7 | search UseCase 接受 capability 即工作，不依赖 `LibraryStore()` 直构 | D-5 | 14c-c2 | `V5114SearchUseCaseCapabilityInjectionTests` fake capability |
| INV-8 | LibraryFeatureStore 所有 side-effect dep 可经 init 替身注入并被实际使用（不计数具体条目） | D-1 | 14c-c4 | `V5114LibraryFeatureStoreSideEffectInjectionTests` fake 注入 + assert 调用打到 fake |
| INV-9 | ManagedStorage 拆三后三路径互不共享缓存 state | B-1 | 14c-c5 | `V5114ManagedStorageSplitIsolationTests` |
| INV-10 | LibrarySidecarService 拆 Reader/Writer/Policy 后独立可替身；policy 持双 capability 不直 file I/O | B-3 | 14c-c6 | `V5114SidecarServiceSplitTests` |
| INV-11 | `ThreeOmegaIngestionContracts` 拆分后 UI tab 与 domain models 不 cross-import | NEW-1 | 14d-c1 | `V5114ArchitectureImportDirectionTests`（test wrapper，非裸 grep；明确失败原因） |
| INV-12 | LibraryModels 三 Tier 拆分后 UI projection 不被 UseCase 层 import | L-5 | 14d-c2 | 同上 wrapper |
| INV-13 | WorkflowID 搬 Domain 后三 region 引用同一 enum 实例（无 region-local 复制） | B-4 | 14d-c3 | 编译时 typealias 检查 + test wrapper assert unique definition |
| INV-14 | FilenameRuleSet schema 搬 Domain 后 loader/evaluator 仍在 Inbox/Rules | L-4 | 14d-c4 | `V5114FilenameRuleSchemaLocationTests` |
| **INV-15** | **`RestoreAnalysisPackUseCase` 不持有 repository/store/logger 成员；capability 全部由 func 参数传入** | **L-1 stateless** | **14c-c8** | `V5114RestoreUseCaseStatelessTests` reflect 检查无 stored property + 调用契约 |
| **INV-16** | **D-6 替换后规则保存链路 + audit 链路不直接引用 `RuleLoader.shared` / `AuditLogger.shared` / `SpinLabRuleProvider.shared`** | **D-6 replace** | **14c-c7** | `V5114SharedSingletonAbsenceTests` test wrapper grep `*.shared` in target files |
| **INV-17** | **Tier 1 Domain 仅含 `Codable/Hashable/Sendable` contract；不含 parser/loader/evaluator/repository/service I/O** | **Tier 1 边界** | **14d-c1...c5** | `V5114Tier1DomainPurityTests` test wrapper：`Sources/Domain/**` import 不含 `Foundation.FileManager`/`URLSession`/region-specific service |

**14b 5 INV / 14c 5 INV / 14d 5 INV / 14b-or-14c 横跨 2 INV（INV-15 在 14c-c8 / INV-16 在 14c-c7）= 17 条**。

---

## §1 输入清单（16 条 + E-1 defer）

L-1 / L-2 / L-3 / L-4 / L-5 / **NEW-1** / B-1 / B-2 / B-3 / B-4 / D-1 / D-2 / D-3 / D-4 / D-5 / D-6 / E-1。NEW-1 = `ThreeOmegaIngestionContracts.swift` domain + UI tab enum 混杂（11a CR 漏抽补回）。

---

## §2 三根因（终稿）

### 根因 1：DI 三档严格分级

| dep 类型 | 替身机制 |
|---|---|
| 纯值 helper / pure function | 直 instantiate |
| 无副作用 service | init 默认参数 + `@ObservationIgnored` + init 替身 |
| 有副作用 repository / logger / storage / file system / network / `.shared` singleton | **必经 AppEnvironment / capability protocol** |

### 根因 2：Domain 三 Tier 物理统一

| Tier | 定义 | 物理位置 | 内容边界（强制） | 守护 INV |
|---|---|---|---|---|
| Tier 1 跨区 contract | ≥ 2 region 消费 | `Sources/Domain/<topic>/` | **仅 Codable/Hashable/Sendable contract**；**不**含 parser/loader/evaluator/repository/service I/O | INV-6/13/14/17 |
| Tier 2 region domain entity | 单 region 持久化+UseCase 共用 | `Sources/<Region>/Domain/` | 同上纯值约束 | INV-12 |
| Tier 3 UI projection | 仅 View+ViewModel | 留 `Features/<Region>/` | 不被 UseCase 层 import | INV-12 |

**搬迁判据（不预承诺具体路径）**：
- 「这个 type 是 Codable/Hashable/Sendable 纯值 contract 吗？」是 → 搬；否 → 留 owner region
- 「这个文件是否同时含 contract + 行为（loader/evaluator/parser）？」是 → 拆分后**仅搬 contract 部分**
- legitimate_cross_cutting 标记：物理搬到 Domain/ 后保留作 collaborator region 的 Code Map 注释（标识跨区消费身份）

### 根因 3：Workspace Store 业务边界 → UseCase + capability

- L-1：`RestoreAnalysisPackUseCase` stateless，capability 作 func 参数（INV-15 守）
- L-2：metric source 改 typed metadata（INV-4 守，不依赖 LibraryAccess capability，故留 14b）
- NEW-1：拆 contracts，UI tab enum 留 Features
- D-4：renderer stateless（INV-5 守）

---

## §3 16 条修订表（5 列：owner / 输入 / 输出 / INV / 禁止事项）

| ID | owner | 输入 | 输出 | 守护 INV | 禁止事项 | 派发轮次 |
|---|---|---|---|---|---|---|
| **L-1** | `Sources/Workbench/UseCases/RestoreAnalysisPackUseCase.swift`（新增） | analysis pack URL + vault capability + library capability | restore 结果（pack 元数据 + diff 结果） | INV-2 + INV-15 | 不得持有 stored repository/store/logger；不得在 UseCase 内创建 Library/Vault 实例 | 14c-c8（必须排 c5/c6 后） |
| **L-2** | `Sources/Workbench/AHEWorkspaceStore.swift` | typed ingestion metadata | metric extraction 改读 sampleKey from typed metadata | INV-4 | 不得从 rendered series label 反解 sampleKey | 14b-c4（确认无 Library capability 依赖） |
| **L-3** | `Sources/Domain/Sidecar/SpinLabFileSidecar.swift`（搬入） | 现 sidecar contract struct | Domain 位置的 contract；三 region import 调整 | INV-6 + INV-17 | 不得把 sidecar reader/writer/policy service 一起搬入 Domain | 14d-c5（依赖 14c-c6 sidecar service 拆分边界） |
| **L-4** | `Sources/Domain/Routing/FilenameRuleSet.swift`（仅 schema 搬） | 现 schema struct | Domain 位置的 schema；loader/evaluator 留 Inbox/Rules | INV-14 + INV-17 | 不得搬 RuleLoader / FilenameRuleEvaluator / 任何 runtime 行为 | 14d-c4 |
| **L-5** | `Sources/Library/LibraryModels.swift` 拆分 | 现 god-file | Tier 2 entity → `Sources/Library/Domain/`；Tier 3 UI projection 留 Features/ | INV-12 + INV-17 | 不得把 UI projection 与 entity 混在同一文件；不得让 UseCase 层 import UI projection | 14d-c2 |
| **NEW-1** | `Sources/Workbench/V3/ThreeOmegaIngestionContracts.swift` 拆分 | 现混杂文件 | domain models → `Sources/Workbench/Domain/`；UI tab enum 留 Features | INV-11 + INV-17 | 不得让 UI tab enum 与 domain models cross-import | 14d-c1 |
| **B-1** | `Sources/Storage/ManagedStorage.swift` 拆三 | 现 god-storage | `InboxImportFilterService` (Inbox) / `LibraryArchiveScanService` (Library) / `ContentFingerprintService` (共用 Storage 或 Domain) | INV-9 | 不得保留任何 cross-region 共享缓存 state；入场前 grep 共享缓存判断粒度 | 14c-c5（fallback：拆二，policy 单独留） |
| **B-2** | `CLAUDE.md` + `docs/architecture/ARCHITECTURE_OVERVIEW.md` | 现 Domain placement 政策 | 三 Tier 政策 + DI 三档分级 + 物理搬迁判据 + legitimate_cross_cutting 标记规则 | — | 不得在政策中预承诺具体文件路径；先写判据和反例 | 14b-c0（先行政策 commit） |
| **B-3** | `Sources/Library/LibrarySidecarService.swift` 拆三 | 现 god-service | `LibrarySidecarReader`(capability) + `LibrarySidecarWriter`(capability) + `LibrarySidecarPolicyService`（持双 capability，不直 I/O） | INV-3 + INV-10 | Policy 不得直接 file I/O；fail-soft 不得静默 try?；Reader/Writer 共享 path resolution 占比 > 80% 时回退拆二 | 14c-c6 |
| **B-4** | `Sources/Domain/Workflow/WorkflowID.swift`（搬入）+ `Sources/Domain/Workflow/WorkflowDefinitionProviding.swift`（接口） | 现 enum + Store | enum 在 Domain；接口在 Domain；实现留 Workbench | INV-13 + INV-17 | 接口仅暴露查询，不承载 workflow 实现策略；不得把 Store 实现搬入 Domain | 14d-c3 |
| **D-1** | `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift` | 现 5 deps 默认构造 | side-effect dep 走 AppEnvironment；service `@ObservationIgnored` + init 替身参数；含 13c F-1 修复 | INV-8 | 不得让 side-effect dep（storage/logger/sample edit）保留默认构造 | 14b-c0(政策) + 14c-c4(实现) |
| **D-2** | `Sources/Workbench/ThreeOmegaWorkspaceStore.swift` | 现直构 UserDefaults/FileManager/LibraryStore() | 接 `WorkbenchEnvironment` capability bag | INV-7（LibraryAccess 部分） | 不得保留任何直构 cross-region storage | 14c-c3（依赖 14c-c1 LibraryAccessCapability） |
| **D-3** | `Sources/Workbench/AHEWorkspaceStore.swift` + `XYRotationWorkspaceStore.swift` | 同 D-2 | FileManager 改注入 | INV-7 扩展 | 不得保留 FileManager.default 直调 | 14c-c3（与 D-2 同 commit） |
| **D-4** | `Sources/UseCases/ThreeOmegaPlotRenderer.swift` + `XYRotationPlotRenderer.swift` | 现 stateful renderer | `collectedWarnings` 改 return value | INV-5 | 不得保留任何 stored mutable state（仅 stateless 函数） | 14b-c5 |
| **D-5** | `AppEnvironment` + `Sources/Workbench/UseCases/SearchUseCase.swift` | 现 LibraryStore() 直构 | `LibraryAccessCapability` 协议 + 默认实现；UseCase 接 capability 参数 | INV-7 | 不得在 UseCase 层 instantiate Library/Storage 类型 | 14c-c1 (capability) + 14c-c2 (UseCase) |
| **D-6** | `Sources/Domain/Capabilities/RuleProviding.swift` 等（capability 协议）+ `Sources/Inbox/RulesManagementStore.swift` + `Sources/Inbox/InboxArchiveApplyService.swift` | 现三个 `.shared` 直调 | capability 协议（14b-c1）+ 调用点替换（14c-c7） | INV-1 + INV-16 | 替换后链路不得再引用 `RuleLoader.shared` / `AuditLogger.shared` / `SpinLabRuleProvider.shared` | 14b-c1(contract+test) + 14c-c7(replace) |
| E-1 | — | — | 不进 14；G-track 观察项 | — | 不写「过渡 API」到 Code Map（违反体例） | defer-to-G-track |

---

## §4 派发轮次分布

| 轮次 | 性质 | items | INV |
|---|---|---|---|
| **14b** (6 commit) | 政策 + 测试网 + capability contract + 最小代码 | B-2 / D-1(政策段) / D-6(contract) / L-2 / D-4 + 提前落 INV-2/3 测试网 | INV-1/2/3/4/5 |
| **14c** (8 commit) | DI 基础设施 + workspace 注入 + service 拆分 + UseCase 抽离 + D-6 替换 | D-5 / D-2 / D-3 / D-1(实现) / B-1 / B-3 / D-6(replace) / L-1 | INV-7/8/9/10/15/16 |
| **14d** (5 commit) | 物理 Domain 迁移 | NEW-1 / L-5 / B-4 / L-4 / L-3 | INV-6/11/12/13/14/17 |
| defer | E-1 | — | — |

---

## §5 14b 派工预案（6 commit）

| commit | 内容 | INV |
|---|---|---|
| **14b-c0** | 政策 docs：CLAUDE.md Domain 三 Tier + DI 三档 + Tier 1 contract-only 边界 + legitimate_cross_cutting 标记规则 + **「不预承诺路径，先写判据」段**；ARCHITECTURE_OVERVIEW.md 同步 | — |
| **14b-c1** | D-6 capability contract：`RuleProviding` / `AuditLogging` / `SpinLabRuleProviding` 协议（不替换调用点）+ INV-1 顺序不变式测试 | INV-1 |
| **14b-c2** | 提前落 INV-2 pack restore trace 测试（守 14c-c8 L-1） | INV-2 |
| **14b-c3** | 提前落 INV-3 sidecar fail-soft 测试（守 14c-c6 B-3） | INV-3 |
| **14b-c4** | L-2 AHE metric 改读 typed sampleKey + INV-4（确认不依赖 14c LibraryAccess） | INV-4 |
| **14b-c5** | D-4 renderer stateless + INV-5 | INV-5 |

## §6 14c 派工预案（8 commit）

| commit | 内容 | 跨轮依赖 | INV |
|---|---|---|---|
| **14c-c1** | AppEnvironment 增 `LibraryAccessCapability` + 默认实现 | — | (INV-7 部分) |
| **14c-c2** | search UseCase 改 capability 参数 + INV-7 测试 | 依赖 c1 | INV-7 |
| **14c-c3** | `WorkbenchEnvironment` 增 capability + 3 个 Workspace Store init 注入（D-2 + D-3） | 依赖 c1 | INV-7 扩展 |
| **14c-c4** | LibraryFeatureStore side-effect dep AppEnvironment + service `@ObservationIgnored` + init 替身（含 13c F-1）+ INV-8 | 依赖 14b-c0 政策 | INV-8 |
| **14c-c5** | `ManagedStorage` 拆三 service（入场前 grep 共享缓存）+ INV-9 | 独立 | INV-9 |
| **14c-c6** | `LibrarySidecarService` 拆 Reader/Writer/Policy + fail-soft 分型 + INV-10 | 独立（建议先于 c5；如 c5 涉及 path 抽象冲突则后置） | INV-10 |
| **14c-c7** | D-6 调用点替换：`RulesManagementStore` + `InboxArchiveApplyService` 改 init 注入 + INV-16 | 依赖 14b-c1 capability | INV-1（仍 pass）+ INV-16 |
| **14c-c8** | L-1 `RestoreAnalysisPackUseCase` 抽离（stateless）+ INV-15 | **必须排 c5 + c6 后**（restore 可能依赖 sidecar reader/writer + storage split） | INV-2（仍 pass）+ INV-15 |

## §7 14d 派工预案（5 commit，物理迁移，churn 从小到大）

| commit | 内容 | 跨轮依赖 | INV |
|---|---|---|---|
| **14d-c1** | NEW-1 `ThreeOmegaIngestionContracts.swift` 拆 domain + UI tab + INV-11 + 强制 Codable/Hashable/Sendable conformance | — | INV-11 + INV-17 |
| **14d-c2** | L-5 `LibraryModels.swift` 三 Tier 拆分 + INV-12 + 强制 Codable/Hashable/Sendable | — | INV-12 + INV-17 |
| **14d-c3** | B-4 `WorkflowID` → `Sources/Domain/Workflow/` + `WorkflowDefinitionProviding` 抽接口 + INV-13 | — | INV-13 + INV-17 |
| **14d-c4** | L-4 `FilenameRuleSet` schema → `Sources/Domain/Routing/`（仅 schema）+ INV-14 | — | INV-14 + INV-17 |
| **14d-c5** | L-3 `SpinLabFileSidecar` → `Sources/Domain/Sidecar/` + 三 region import 调整 + INV-6 | **依赖 14c-c6**（sidecar service Reader/Writer/Policy 边界已定）| INV-6 + INV-17 |

---

## §8 风险清单（13 条，吸收 Codex 全部修订）

1. CLAUDE.md / ARCHITECTURE_OVERVIEW.md 修订风险（B-2）→ 14b-c0 锁定全局
2. R1 顺序不变式破坏（D-6）→ INV-1 守
3. Code Map 登记义务 → pre-commit hook 兜底；**跨区 contract 主 owner 一处登记，collaborator region 默认不重复登记**
4. 合法跨区契约误判 → Tier 1 物理搬迁后保留 `legitimate_cross_cutting` 标记作 collaborator 注释
5. D-6 三链路同 commit → 拆 14b-c1 + 14c-c7；INV-1 + INV-16 双守
6. 测试不变式覆盖：17 INV 绑定具体 commit；提前落 INV-2/3 做防回归网
7. 物理迁移 import churn → 14d 集中 5 commit；每 commit 后 `swift build` pass；不跨 commit 半搬状态
8. capability 协议化连锁 → 14c-c2/c3 后 grep `Store()` 确认无新暴露
9. ManagedStorage 拆分粒度 → 14c-c5 入场前判断；预留拆二 fallback
10. LibrarySidecarService 拆分粒度 → 14c-c6 入场判断 Reader/Writer 共享 path 比例 > 80% 回退拆二
11. swift test runner 16GB 限制 → `--filter V5114` 定向；不全量
12. **Tier 1 文件搬时强制 `Codable/Hashable/Sendable` conformance**；只移文件不补 conformance 视为不合格 commit（INV-17 兜底）
13. 不做的事：不改 WorkflowID 实现层（仅升 Domain 接口）；不动 5.3.6 G-001；不动 5.1.6 G-002/G-008/G-010；E-1 不进 14；不写「过渡 API」到 Code Map

---

## §9 文档授权清单

| 文档 | 修改 | 段落 |
|---|---|---|
| `CLAUDE.md`（项目） | Domain Models 三 Tier + Tier 1 contract-only 边界 + legitimate_cross_cutting 规则 | Domain Models |
| `CLAUDE.md`（项目） | DI 三档分级 | Dependency Injection |
| `CLAUDE.md`（项目） | FeatureStore owns repository exception 边界（仅 side-effect-free service） | Architecture Patterns - Feature Store |
| `docs/architecture/ARCHITECTURE_OVERVIEW.md` | 同步三 Tier + DI 三档 + 物理搬迁判据 + 不预承诺路径 | Domain placement / DI |
| 各 region `## Code Map` | 14b/14c/14d 新增/迁移 swift 全部登记（**主 owner 一处，collaborator 不重复**） | Code Map |
| `docs/features.md` | **如 INV-1/INV-2/INV-3 作为长期 feature invariant 入档则同步**（决策点：14b-c0 入场时确认）；若仅作为执行方案的回归测试则不改 | Invariants |

---

## §10 元数据

- 流水线：第 1 稿（Claude）→ Codex 第 1 轮 adopt-with-fixes → Jack 拍板方案 A + 防回归 → 第 2 稿（Claude，吸收 Codex 修订 + 加 14 条 INV）→ Codex 收敛轮 adopt-with-fixes → 第 3 稿（本文件，吸收收敛轮 10 项修订 + 17 条 INV + 5 列修订表）
- 派发：14b 6 commit / 14c 8 commit / 14d 5 commit；INV 17 条分布三轮
- 状态：**第 3 稿（定稿候选）**；Jack 确认或 Codex 第 3 轮通过即移 `docs/handoff/2026-05-03-cross-region-meta-convergence.md`
