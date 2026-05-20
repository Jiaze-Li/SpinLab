# 5.1.13a Library 边界合规审计 — WIP

> 起草中。封闭后将搬到 `docs/handoff/2026-05-03-library-audit.md`。
> 本文件按 `docs/architecture/AUDIT_PLAYBOOK.md` §2-§7 组织。

## §0 抽样池

**封闭日期**：2026-05-03（Codex challenge 已重发，含 F-1/F-2/F-3 三条等量替换；裁决见 `tmp/2026-05-03-codex-challenge-library-sample-verdict.md`）

### 0.1 入样原料统计

| 层 | Code Map 文件 | 唯一文件数 |
|---|---|---|
| Browse | BROWSE_AND_SELECTION.md | 14 |
| Storage | ARCHIVE_STORAGE.md | 14 |
| Edit | SAMPLE_METADATA_EDITING.md | 8 |
| Contract | SIDECAR_AND_CONDITIONS.md | 5 |
| Artifacts | ARTIFACTS_AND_PREVIEWS.md | 9 |
| **合计** | | **50** |

跨层重复：0（每个文件只在一个层登记）。

### 0.2 配额（按层）

| 层 | 总数 | 配额 | 覆盖率 |
|---|---|---|---|
| Browse | 14 | 8 | 57% |
| Storage | 14 | 8 | 57% |
| Edit | 8 | 5 | 63% |
| Contract | 5 | 3 | 60% |
| Artifacts | 9 | 5 | 56% |
| **合计** | **50** | **29** | **58%** |

依据：Library 预测违规密度低于 11/12；保留 ≥56% 覆盖。

### 0.3 强制纳入

**SP-* / G-* 命中**（4 文件，全部 MUST）：
- `SpinLabFileSidecar.swift` — SP-006 legitimate_cross_cutting → Contract
- `LibraryPathResolver.swift` — SP-008 shared Library+Workbench → Artifacts
- `LibraryWriteTransaction.swift` — SP-010 sole archive write → Storage
- *SP-007*（Workbench writes Library `_spinlab` artifacts）：契约由 `LibraryPathResolver` + `LibraryStore` + Workbench 侧 `SaveActiveChartToLibraryUseCase` 共同承担。Library 侧落点 = `LibraryPathResolver`（已 SP-008）+ `LibraryStore`（已 churn top）+ `LibraryDiskCleanupService`（artifact 清理 invariant）→ 强制纳入 `LibraryDiskCleanupService.swift`。

**Churn top-5（since 2025-12-01，现存文件）**：
1. `LibraryView.swift` (48) — Browse MUST
2. `LibraryFeatureStore.swift` (28) — Browse MUST
3. `LibraryStore.swift` (15) — Storage MUST
4. `LibraryViewModel.swift` (15) — Browse MUST
5. `LibraryRegistryParser.swift` (13) — Edit MUST

**层代表性**：
- Browse：除 4 个 MUST，再补 4 个覆盖 view 拆分 / projection / selection sync / sample detail header
- Storage：除 LibraryStore + LibraryWriteTransaction + LibraryDiskCleanupService，再补 5 个覆盖 sync / settings / logger / sort / atomic write
- Edit：除 LibraryRegistryParser，再补 4 个覆盖 FeatureStore 拓展 / edit service / diff engine / xlsx sync
- Contract：3 个全在层内（Sidecar + 2 个 view）
- Artifacts：除 LibraryPathResolver，再补 4 个覆盖 preview panel / recompute / sheets / preview computation

### 0.4 入样表（AS-01..AS-29）

#### Browse (8)

| ID | 文件 | 入选理由 |
|---|---|---|
| AS-01 | `App/State/LibraryFeatureStore.swift` | churn #2；store 形态/边界核心 |
| AS-02 | `App/State/LibraryFeatureStore+Projection.swift` | projection 计算；UI vs store 边界 |
| AS-03 | `App/State/LibraryState.swift` | raw state model；@Observable 形态 |
| AS-04 | `Features/Library/LibraryView.swift` | churn #1；root view 业务逻辑下沉风险 |
| AS-05 | `Features/Library/LibraryView+Search.swift` | filter UI；View 不含 sort/filter 检查 |
| AS-06 | `Features/Library/LibraryViewModel.swift` | churn #4；canonical model 持有检查 |
| AS-07 | `Features/Library/LibrarySelectionSync.swift` | FeatureStore↔ViewModel 桥接；同步反模式 |
| AS-08 | `Features/Library/LibraryWorkspaceSections.swift` | Codex F-3：固定 section ordering 是产品 invariant；信号 #2 潜在落点 |

#### Storage (8)

| ID | 文件 | 入选理由 |
|---|---|---|
| AS-09 | `Library/LibraryStore.swift` | churn #3；AsyncStream 形态 + index 持久化 |
| AS-10 | `Library/LibraryWriteTransaction.swift` | SP-010；唯一写入路径 |
| AS-11 | `App/LibraryDiskCleanupService.swift` | SP-007 协作点；artifact cleanup |
| AS-12 | `Library/LibrarySyncService.swift` | filesystem→state 单向；side effect 检查 |
| AS-13 | `Library/LibrarySettingsStore.swift` | UserDefaults 持久化；@Observable 形态 |
| AS-14 | `Library/LibraryLogger.swift` | audit log 写入；fail-soft Adj-10 |
| AS-15 | `Library/LibraryModels.swift` | Codex F-1：Library/ 而非 Domain/；信号 #17 直接潜在落点 |
| AS-16 | `Storage/ManagedStorage.swift` | Codex F-2：跨阶段协调器（import/archive/cleanup）；信号 #5/6/15 三联落点 |

#### Edit (5)

| ID | 文件 | 入选理由 |
|---|---|---|
| AS-17 | `App/State/LibraryFeatureStore+SampleEdit.swift` | edit 入口；FeatureStore 边界 |
| AS-18 | `Library/LibrarySampleEditService.swift` | edit 事务；display name 保护 |
| AS-19 | `Library/LibraryRegistryParser.swift` | churn #5；Parser 不调 Service/Repository |
| AS-20 | `Library/LibraryDiffEngine.swift` | diff 计算；UseCase stateless 检查 |
| AS-21 | `App/LibraryMutationService.swift` | 跨层协调器；DI 注入检查 |

#### Contract (3)

| ID | 文件 | 入选理由 |
|---|---|---|
| AS-22 | `Library/SpinLabFileSidecar.swift` | SP-006；schema canonical |
| AS-23 | `Features/Library/MeasurementConditionDetailView.swift` | 跨区契约消费；View normalize 检查 |
| AS-24 | `Features/Library/MeasurementDataSectionView.swift` | sidecar 标签 derive；View 不含逻辑 |

#### Artifacts (5)

| ID | 文件 | 入选理由 |
|---|---|---|
| AS-25 | `Library/LibraryPathResolver.swift` | SP-008；shared Library+Workbench |
| AS-26 | `Features/Library/MeasurementPlotPreviewPanel.swift` | artifact 渲染；I/O on @Observable 检查 |
| AS-27 | `Features/Library/RecomputePreviewPanel.swift` | recompute 触发 UI；跨区调用边界 |
| AS-28 | `App/LibraryPreviewComputationService.swift` | 后台 preview 协调；async I/O 隔离 |
| AS-29 | `UseCases/LoadMeasurementPlotIndexUseCase.swift` | UseCase stateless；存储细节检查 |

### 0.5 不入样名单（21 文件）+ 理由

| 文件 | 层 | 不入样理由 |
|---|---|---|
| `LibraryView+DetailColumn.swift` | Browse | view 拆分纯 layout；AS-04 已覆盖 root |
| `LibraryView+Panels.swift` | Browse | view 拆分纯 layout |
| `LibraryView+State.swift` | Browse | view-local binding，AS-06 ViewModel 覆盖 |
| `LibrarySampleDetailHeaderView.swift` | Browse | 纯 header view（name/drawer/status badges）；优先级低于 AS-08 替换项 |
| `LibraryViewSupport.swift` | Browse | helper modifier；纯渲染 |
| `MetadataViews.swift` (UI/) | Browse | shared chip 渲染；AS-23/24 间接覆盖 |
| `LibrarySort.swift` | Storage | sort 逻辑；AS-04 root view + AS-05 search UI + AS-09 store 已间接覆盖排序场景 |
| `LibraryDestinationSubpath.swift` | Storage | 纯计算 UseCase；行为单一 |
| `ArchivedRecordResolverService.swift` | Storage | 路径解析；AS-25 PathResolver 覆盖类似形态 |
| `DomainRepositories.swift` | Storage | repository 工厂；AS-09 Store 已覆盖 AsyncStream |
| `AtomicFileWriter.swift` | Storage | 原子写工具；AS-10 LibraryWriteTransaction + AS-14 LibraryLogger + AS-12 LibrarySyncService 已覆盖更高价值调用边界 |
| `RepositoryPointer.swift` | Storage | 纯 value type |
| `LibraryFeatureStore+Logs.swift` | Edit | log 展示；AS-17 SampleEdit 覆盖 store 形态 |
| `LibraryXLSXSyncService.swift` | Edit | xlsx atomic sync；AS-18 EditService 同形态 |
| `SaveLibrarySampleEditsUseCase.swift` | Edit | UseCase 形态；AS-20 DiffEngine 覆盖 stateless |
| `LibraryMeasurementsDoneSection.swift` | Contract | 纯展示；AS-23/24 已覆盖 sidecar view |
| `LibraryExistingDrawerSampleSectionView.swift` | Contract | 纯展示 |
| `RecomputeStaleBannerView.swift` | Artifacts | 纯 banner；AS-27 RecomputePreviewPanel 覆盖触发 |
| `LibrarySheets.swift` | Artifacts | sheet modifier；纯 UI |
| `LibraryViewComputationService.swift` | Artifacts | UI 桥接；AS-28 PreviewComputation 覆盖 async |
| `LoadRelatedChartsUseCase.swift` | Artifacts | UseCase 形态；AS-29 LoadPlotIndex 覆盖 |

### 0.6 Codex challenge 裁决

- 裁决：**adopt-with-fixes** → 修订后 = **adopt**
- F-1 [med] 采纳：AS-15 由 LibrarySort → LibraryModels（信号 #17 直接潜在落点）
- F-2 [high] 采纳：AS-16 由 AtomicFileWriter → ManagedStorage（跨阶段协调器，信号 #5/6/15）
- F-3 [med] 采纳：AS-08 由 LibrarySampleDetailHeaderView → LibraryWorkspaceSections（信号 #2 section ordering）
- F-4 [low] 接受：SP-* 完整，配额起点合理，覆盖率 58% 维持
- 总量 29、层配额不变、AS-ID 编号锁定

---

## §1 Violation

> Batch 1（Browse + Storage）已审，待 Batch 2 + Codex 评审。

### V-001 [med] AS-01 信号 #1 — LibraryFeatureStore selection 属性 didSet 副作用

- **文件**：`Sources/SpinLabApp/App/State/LibraryFeatureStore.swift:77-87`
- **证据**：4 个属性 `librarySelectedPrefix` / `librarySelectedBatchId` / `librarySelectedSampleId` / `libraryActiveSelectionSource` 各自 `didSet { onPersistInteractionSnapshot?() }`，setter 触发持久化回调。
- **违反规则**：CLAUDE.md "Side effects must not occur inside `@Observable` state setters"
- **next_action**：`13b` 抽显式 `commitSelection(...)` 方法 + 在方法内调 persist；移除 didSet。

### V-002 [med] AS-05 信号 #2 — LibraryView+Search 多键排序组合在 UI 层

- **文件**：`Sources/SpinLabApp/Features/Library/LibraryView+Search.swift:49-71`
- **证据**：`allExistingDrawerSamples` 内 `.sorted` 闭包组合 prefix → batch (via LibrarySort) → substrate 三键排序规则。
- **违反规则**：CLAUDE.md "Views must not contain sorting/filtering/normalization logic"
- **next_action**：`13b` 抽 `LibrarySort.sortedExistingDrawerSamples(...)` 静态方法承担多键组合。

### V-003 [high] AS-12 信号 #6 — LibrarySyncService.applyBatch / applyAll 大面积静默 try?

- **文件**：`Sources/SpinLabApp/Library/LibrarySyncService.swift:232,238,242,247,249,275,281,286,298,302`
- **证据**：apply 路径下 `try? libraryStore.createDrawer / updateSample / deleteSampleDrawer / updateBatch / deleteBatchDrawer` 多处折叠 error 为静默忽略。`applyBatch` line 238/242 即使 error 仍 `touched += 1`，UI 显示"已更新 N 条"但实际可能未写入；无 stderr 日志、无 user-facing surface。
- **违反规则**：Adj-10 fail-soft batch 1（必须 stderr 记录非 file-not-found error）+ CLAUDE.md "Never use try? to silently discard errors in service/repository/storage layers"
- **next_action**：`13b` 引入 `LibraryApplyError` 收集器；error 通过 result 传出 + stderr 记录；touched 仅在成功 case 递增。

### V-004 [med] AS-13 信号 #6 — LibrarySettingsStore.load 折叠 corrupt error 无日志

- **文件**：`Sources/SpinLabApp/Library/LibrarySettingsStore.swift:30,33`
- **证据**：`load()` 内 `try? Data(contentsOf: settingsURL)` + `try? decoder.decode(LibrarySettings.self, from: data)` 任一失败折叠为 `.default`，无 stderr。文件存在但 corrupt 时静默吞掉。
- **违反规则**：Adj-10 — file-not-found 路径已通过 `fileExists` guard；下游两个 `try?` 是 corrupt/decode 路径，须记日志。
- **next_action**：`13b` 改为 `do/catch`，corrupt 记 `appLogger.error` 后回 `.default`。

### V-005 [med] AS-09 信号 #5 — LibraryStore 含业务策略方法（修复分阶段）

- **文件**：`Sources/SpinLabApp/Library/LibraryStore.swift`
- **证据按业务策略性质分级**（Codex 评审建议拆细修复）：
  - **明显业务策略（高优先级抽出）**：
    - `recomputeAllMeasurementSidecars` :409 — 调规则 provider + sidecar recompute
    - `backfillMissingMeasurementSidecars` :457 — sidecar 业务规则
    - `computeRecomputeDiff` :1320 — 调 parser/usecase 构造业务 diff
    - `syncRegistrySourceForEditedSample` :244 — 调 XLSX sync service
  - **边界混杂（lower priority，可作 sidecar repository + service 混合保留）**：
    - `computeStaleCount` :1307 — 含 sidecar policy 但接近 sidecar repository 视图
    - `saveConditionOverride` :1373 — 同上
- **违反规则**：CLAUDE.md "Repository/Store: persistence only, no business policy"
- **next_action**：`13b` 拆阶段修复
  - **Phase 1**：抽 `LibrarySidecarService` / `LibraryRecomputeService`（高优先级 4 个方法）
  - **Phase 2**：处理 `syncRegistrySourceForEditedSample` 到 registry sync service
  - **Phase 3**：评估 `computeStaleCount` / `saveConditionOverride` 是否需要进一步拆分（可能 sidecar repository 形态保留）；deprecated wrapper / caller 切换策略单独确认

### V-006 [med] AS-16 信号 #6 — ManagedStorage 多处 try? 静默（mixed cases，按风险分级）

- **文件**：`Sources/SpinLabApp/Storage/ManagedStorage.swift:43-45,116-126,166-181,177-180,250-251`
- **证据按风险分类**（Codex 评审建议细化）：
  - **真违规（permission/corrupt 静默）**：
    - line 43-45 init catch 块只注释 "Keep initialization non-throwing" 不记日志（permission/disk-full 时 startup 静默退化）
    - line 124-126 `clearManagedMeasurementCopies` 用 `try? removeItem` — clear 操作 permission/locked-file 静默
    - line 250-251 `contentFingerprint` `try? Data(contentsOf:.mappedIfSafe)` — permission/读失败静默 nil 影响 dedup
  - **预期 nil（可接受）**：
    - line 166-172 `currentSampleRegistryFileURL` 对 missing managed/registry dir 折叠 nil 是预期场景（首次安装），但 permission case 仍混在内
  - **低风险降级（不应同级）**：
    - line 177-180 `try? resourceValues(...)` ?? `.distantPast` 用于 sort 的 metadata 降级，sort 顺序略乱不影响数据完整性
- **违反规则**：Adj-10 — 真违规两类 case（permission / disk-full / corrupt）必须 stderr 记录；预期 nil + sort fallback 可保留。
- **next_action**：`13b` 按风险分类逐个处理；finding 文案不应把 all try? 等量定性。

### V-008 [med] AS-23 View 边界 — MeasurementConditionDetailView 直接 I/O 读 sidecar

- **文件**：`Sources/SpinLabApp/Features/Library/MeasurementConditionDetailView.swift:263-269`
- **证据**：`loadSidecarDirect()` 在 View 内直接 `Data(contentsOf: URL(fileURLWithPath:))` + `JSONDecoder.decode(SpinLabFileSidecar.self, ...)`；`reloadSidecar()` 由 onAppear / commitEdit / removeOverride 后续调用。
- **违反规则**：CLAUDE.md "Views must not call service/repository/parser/storage directly — go through AppState or ViewModel"。Sidecar 加载是 storage I/O，应经 service / use case / FeatureStore 中转。
- **next_action**：`13b` 抽 `LoadAppliedMeasurementSidecarUseCase` 或经 `LibraryFeatureStore.appliedSidecar(for:)` 路径；View 仅消费 store 提供的 projection。

### V-009 [high] AS-24 信号 #2 — MeasurementDataSectionView 含 3 层 grouping + 业务规则

- **文件**：`Sources/SpinLabApp/Features/Library/MeasurementDataSectionView.swift:54-137`
- **证据**：`deviceGroups` computed property 在 View 内执行：
  - 3 层 grouping (workflowID|device → method → range)
  - 多键 sort (`metric < metric` / `byMethod.keys.sorted()` / `byRange.keys.sorted()`)
  - condition 字段映射（`v3method` / `range` / `device`）
  - metric 别名重命名（`r_squared → r²`）
  - unit legend 字符串构造 + cardMethod 拼接
- **违反规则**：CLAUDE.md "Views must not contain sorting/filtering/normalization logic"。这是 18 信号 #2 最严重命中点（Library 区域）。
- **next_action**：`13b` 抽 `LibraryMeasurementDataPresenter` 或 `BuildMeasurementDataDeviceGroupsUseCase`，View 接收已构造好的 `[DeviceGroup]` 项目仅渲染。

### V-007 [low] AS-15 跨区 meta — Library domain models 不在 Domain/

- **文件**：`Sources/SpinLabApp/Library/LibraryModels.swift`
- **证据**：`LibraryMetadataItem` / `LibrarySettings` / `LibraryIndex` / `LibrarySample` / `LibraryBatch` 等 domain struct 集中在 `Sources/SpinLabApp/Library/`，未在 `Sources/SpinLabApp/Domain/`。
- **违反规则**：CLAUDE.md "Domain models live in Domain/. Do not define inside Features/." 严格字面不命中信号 #17（不在 Features/ 内），但精神违反。其他 region（Inbox / Workbench）可能存在同形态。
- **next_action**：`14a` — 留 5.1.14a 跨区 meta 收敛统一 domain placement 政策。

---

## §2 Drift（Code Map 注释 / 现实偏离；立即 commit 修正）

### D-001 AS-09 LibraryStore Code Map 注释偏离 + AsyncStream 描述不实

- **文件**：`docs/architecture/library/ARCHIVE_STORAGE.md:46`
- **当前注释**：`drawer index persistence, AsyncStream emission, and index loading`
- **现实**：`LibraryStore` 含 sidecar recompute、registry source sync、measurement set CRUD、backup sync、condition override、metadata sync logs、recompute diff、stale 计算等。**且 AsyncStream emission 完全不实**（`grep -rn "AsyncStream\|Continuation" Sources/SpinLabApp/Library/LibraryStore.swift` 0 命中）。
- **建议新注释（过渡性 persistence 描述，Codex 评审建议）**：`drawer index, sample, batch, and sidecar persistence`
  - 不固化将抽走的业务策略（recompute/backfill/registry sync）为长期 Code Map 职责
  - 5.1.13b V-005 修复完成后，注释自然回归 persistence-only 表达
  - 立即 commit 此过渡注释，与 V-005 fix 解耦

### D-002 AS-02 LibraryFeatureStore+Projection Code Map 偏离

- **文件**：`docs/architecture/library/BROWSE_AND_SELECTION.md:39`
- **当前注释**：`projected item list and selected item computation`
- **现实**：含 Workbench results / measurement plot index / measurement data load、metric record / Workbench result / applied measurement cascade delete、measurement set CRUD（create/add/remove/rename/delete/persist）。
- **建议新注释**：`selection-driven projection load + measurement set CRUD + cascade deletion`

### D-003 AS-06 LibraryViewModel Code Map 偏离

- **文件**：`docs/architecture/library/BROWSE_AND_SELECTION.md:46`
- **当前注释**：`transient UI state (filter text, local selection, expansion)`
- **现实**：ViewModel 不持有任何 transient UI state（filter / selection / expansion 全在 `LibraryView` 的 `@State` 字段内）。当前 ViewModel 仅承担：(a) AppState action forwarding，(b) interaction state binding（persist / restore via `\.libraryView` keypath）。
- **建议新注释**：`AppState action forwarder + interaction state binding for LibraryView`

### D-004 AS-28 LibraryPreviewComputationService Code Map 偏离

- **文件**：`docs/architecture/library/ARTIFACTS_AND_PREVIEWS.md:55`
- **当前注释**：`background preview orchestration (App layer; keeps async I/O off FeatureStore)`
- **现实**：实现是 `struct LibraryPreviewComputationService` 同步纯函数（`buildPreviewGroups` + `actionablePreviewIndex`），无 async I/O，无 background orchestration。注释完全错指。
- **建议新注释**：`preview group + actionable preview index pure computation`

---

## §3 Accepted Boundary

- **AS-03** `LibraryState.swift`：raw state holder，3 个 var 无 setter override。@Observable form 正确（不是 interactive store，无须 @MainActor）。
- **AS-07** `LibrarySelectionSync.swift`：纯函数 struct + 静态方法，无副作用，无 SwiftUI。
- **AS-08** `LibraryWorkspaceSections.swift`：3 个 SectionView 纯展示；section "ordering" 实际是 SwiftUI 结构而非排序计算（`grep` sorted/filter 0 命中）。Codex F-3 顾虑实际不命中信号 #2。
- **AS-10** `LibraryWriteTransaction.swift` (SP-010)：rollback 路径 `try?` 是合理 best-effort cleanup（主 error 已抛出）；无业务策略。
- **AS-11** `LibraryDiskCleanupService.swift`：Adj-10 模范实现 — 全程 fail-closed + 结构化 fputs stderr 日志；cascade delete 严格按"先 index 后文件"顺序保证 invariant。
- **AS-14** `LibraryLogger.swift`：双层日志（appLogger 主路径 + plain text 辅路径）；plain text write 路径 try? 不影响主路径记录。
- **AS-04** `LibraryView.swift`：`@Environment(SpinLabAppState.self)` ✓ / `@State viewModel = LibraryViewModel()` ✓ / store 调用经 `appState.library.*` ✓。`let computationService = LibraryViewComputationService()` 是 struct 工具类无 I/O，view 层直接构造可接受。
- **AS-01 部分** `LibraryFeatureStore` 形态：@MainActor @Observable final class ✓；deps 通过 `@ObservationIgnored let` 持有 ✓；方法全同步 ✓；重 I/O 用 `Task.detached` 隔离（line 1075/1104）✓。但 V-001 didSet 副作用单独抽出。
- **AS-17** `LibraryFeatureStore+SampleEdit.swift`：业务逻辑通过 useCase + closure 注入；mutation 通过 method 内显式 var/assign 而非 setter override；result enum 显式表达 outcome；`librarySampleEditIsSaving` defer 重置 ✓。
- **AS-18** `LibrarySampleEditService.swift`：edit 事务 service，`EditError: LocalizedError` enum，`apply(draft:to:)` throws 向上；normalize 工具方法私有化 ✓。
- **AS-19** `LibraryRegistryParser.swift`：rule provider 协议化注入 (`any SpinLabRuleProviding`)；substrate config 缺失走 fallback + logger.error 记录；非 try? 静默；CR-003 跨区 default singleton init 形态另列。
- **AS-20** `LibraryDiffEngine.swift`：纯 diff service，无 I/O，无副作用；normalize 工具方法私有化。
- **AS-21** `LibraryMutationService.swift`：struct 形态 + 通过 method 参数注入 dependency（use-case style DI）；mutation result 用 enum outcome 表达；do/catch 把 storage error 转 `.failure(message:)` ✓。
- **AS-22** `SpinLabFileSidecar.swift` (SP-006)：legitimate cross-cutting domain model；v1→v2 自定义 Codable migration 集中在 `init(from:)`；effective accessor 显式 `manual` source 优先级；`encode(to:)` 不输出 v1Conditions 防 schema 漂移 ✓。
- **AS-25** `LibraryPathResolver.swift` (SP-008)：immutable struct + 严格 path containment guard；`relativePath` / `absoluteURL` throws AppError.validation 不静默 ✓。
- **AS-26** `MeasurementPlotPreviewPanel.swift`：UI panel；NSImage 加载用 Task.detached(priority:.userInitiated) 隔离；resolver 是 SP-008 path utility（struct）允许 view 内构造。
- **AS-27** `RecomputePreviewPanel.swift`：UI；filter by status.groupIndex 是 view-level group display 而非业务逻辑；@AppStorage 用 SwiftUI 原生持久化 ✓。
- **AS-29** `LoadMeasurementPlotIndexUseCase.swift`：UseCase stateless struct + pathResolver 注入；Adj-10 模范实现 — file-not-found 静默 nil，read/decode/schema error 各自 fputs stderr。

---

## §4 Cross-Region Doubts For 5.1.14

### CR-001 ManagedStorage 跨区职责不清

- **文件**：`Sources/SpinLabApp/Storage/ManagedStorage.swift`
- **现实**：含 import filter（Inbox 关注）+ archive scan（Library 关注）+ registry install（Library 关注）+ content fingerprint（共用）。Library Code Map 把它归 Storage 层，但 import 过滤策略实际是 Inbox 边界。
- **5.1.14 收敛建议**：拆分到 region-specific service 或抽 capability protocol；目前 `ManagedStorage` 成了"什么都装"的 storage 协调器。

### CR-002 Domain models 散布在 region/ 而非 Domain/

- **文件**：`Sources/SpinLabApp/Library/LibraryModels.swift`（其他 region 同形态待 5.1.14a 调研）
- **现实**：CLAUDE.md "Domain models live in Domain/" 但 Library domain types 全在 Library/。
- **5.1.14 收敛建议**：是否搬迁所有 region 的 domain types 到 `Sources/SpinLabApp/Domain/<region>/`，或修订 CLAUDE.md 规约接受 region/ 内 domain placement。

### CR-003 LibraryFeatureStore deps 默认参数 init 模式

- **文件**：`Sources/SpinLabApp/App/State/LibraryFeatureStore.swift:206-219`
- **现实**：依赖 `LibrarySettingsStore() / LibraryStore() / LibraryLogger() / LibraryDiffEngine() / LibrarySampleEditService()` 全部默认参数构造，未经 AppEnvironment。CLAUDE.md "All runtime dependencies with side effects declared in AppEnvironment"。
- **5.1.14 收敛建议**：FeatureStore 是否经 AppEnvironment 注入 capabilities，还是已建立"FeatureStore owns repository"模式作为 exception。

---

## §5 Fix-Round Draft（Batch 1 + Batch 2 全审，待 Codex 综合评审收敛）

### next_action 分布

| next_action | count | items |
|---|---|---|
| `13b` | 8 | V-001 / V-002 / V-003 / V-004 / V-005 / V-006 / V-008 / V-009 |
| `14a` | 1 | V-007 + CR-001/002/003 |
| `no-fix-accepted` | 0 | — |
| `defer-to-G-track` | 0 | — |

### 13b 修复轮提案（待 Codex 评审收敛后定 commit 切分）

- **C1** V-001 selection didSet 副作用 → 显式 `commitSelection` 方法
- **C2** V-002 多键排序 → 抽 `LibrarySort.sortedExistingDrawerSamples`
- **C3** V-003 LibrarySyncService.applyBatch / applyAll 大面积静默 try? → result-style error 收集 + stderr 日志（**high severity，应优先**）
- **C4** V-004 LibrarySettingsStore corrupt path 记 logger.error
- **C5** V-005 LibraryStore 业务策略抽到 service 层（**最大 commit，可能拆 13b/13c**）
- **C6** V-006 ManagedStorage try? error 区分 file-not-found vs corrupt
- **C7** V-008 MeasurementConditionDetailView 抽 sidecar load 到 useCase / FeatureStore
- **C8** V-009 MeasurementDataSectionView.deviceGroups 抽 presenter / useCase（**high severity**）
- **D-001/D-002/D-003/D-004** Code Map 注释立即修正（独立 commit，与 fix 解耦）

### 总览

- 29 AS-ID 全审
- **9 Violations**：V-001/002 (Browse) + V-003/004/005/006 (Storage) + V-007 (跨区) + V-008/009 (Contract)
- **4 Drifts**：D-001 LibraryStore + D-002 FeatureStore+Projection + D-003 LibraryViewModel + D-004 LibraryPreviewComputationService
- **16 Accepted**：含 SP-006/008/010 三个 cross-cutting 边界点 + Adj-10 模范实现两个（AS-11 / AS-29）
- **3 Cross-Region Doubts**：CR-001 ManagedStorage 跨区职责 / CR-002 Domain models 散布 / CR-003 FeatureStore deps default singleton

按 SP-* 复核：SP-006 (AS-22) ✓ / SP-008 (AS-25) ✓ / SP-010 (AS-10) ✓ / SP-007 协作点 (AS-11/AS-25) ✓。

### Codex 综合评审裁决（playbook §5）

**裁决：adopt-with-fixes**（详见 `tmp/2026-05-03-codex-library-audit-verdict.md`）

- 100% Violation challenge：V-001..V-009 **9 条全成立 agree**；severity 全部合理
- 100% SP-*/G-* 复核：SP-006/007/008/010 **4 条全 agree**
- 非 SP-G 抽查：AS-07/08/17/18/19/20 **6 条全 accepted 成立**（含 AS-08 上轮替换决策一致性确认）
- Drift 复核：D-001/002/003/004 **4 条全成立**
- Cross-Region Doubts 复核：CR-001/002/003 **3 条全 agree**

**Codex 修订建议（已采纳）**：
- V-006 文案细化：区分 mixed cases（permission/corrupt 真违规 vs 预期 nil vs sort fallback）→ 已更新 V-006 段
- V-005 修复拆阶段：Phase 1 sidecar/recompute → Phase 2 registry sync → Phase 3 stale/override 评估 + deprecated wrapper 策略 → 已更新 V-005 段
- D-001 注释策略：用过渡性 persistence 描述立即 commit，不固化业务策略为长期职责 → 已更新 D-001 段

**Codex 留作 caveat（不算违规但需 5.1.13b 关注）**：
- AS-17 LibraryFeatureStore+SampleEdit 仍暴露 Store 内 registry sync closure；V-005 Phase 2 修复后改善
- AS-19 LibraryRegistryParser CoreXLSX `sharedStrings` / `worksheetPathsAndNames` 也有 `try?`，本轮不在 finding 范围；后续可按 Adj-10 再扫
