# Task 9 — 废纸篓与分级删除 Design v1.0

- **policy_sha**: `7f01e5a3ff53ed13ba763d684a098c0989425ec4`（`Jiaze-Li/personal-skills` `main`）
- **Plan**: [`Plan.md`](Plan.md)（分支 `docs/task-9-trash-brief`，PR #219）
- **核查基线**: `docs/task-9-trash-brief@b57808f3`（基于 `origin/main@3ae29312`）
- **目标 / 范围 / 非目标**: 见 `Plan.md` §1–§4。本设计仅覆盖样品（Sample）级 Zotero 式软删除废纸篓、分级确认、还原、手动彻底删除/清空废纸篓及同步/视图隔离；Batch 级删除继续保持禁用。

---

## 1. 已核实事实（`docs/task-9-trash-brief@b57808f3`）

- **F-1 删除入口当前整体禁用：**
  - `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift:6-10`：`enum LibraryDrawerError ... case deletionDisabled ... static let deletionDisabledMessage = "删除功能暂未开放"`；`:191-194` `deleteSampleDrawer` 与 `:259-262` `deleteBatchDrawer` 均直接 `throw LibraryDrawerError.deletionDisabled`。
  - `Sources/SpinLabApp/App/LibraryMutationService.swift:314-322`：`deleteExistingDrawer` 直接返回 `.failure(message: LibraryDrawerError.deletionDisabledMessage)`。
  - `Sources/SpinLabApp/App/RootSplitView.swift:186-200`：侧边栏 Batch 右键菜单调用 `appState.library.deleteExistingDrawer(batchId: batchID)`。
- **F-2 样品模型与磁盘持久化位置：**
  - `Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift:153-283`：`struct LibrarySample` 存在各样品目录 `sample.json` 中，当前无软删除字段；`init(from decoder:)` 使用 `decodeIfPresent` 读取可选字段（`:268-281`）。
  - `Sources/SpinLabApp/Library/LibraryStore+RootAndIndex.swift:268-278`：`scanIndexFromFilesystem` 遍历 `batches/<batch>/samples/<sampleKey>/sample.json` 解码 `LibrarySample`，任一 `sample.json` 损坏即记入 `issues` 并 fail-closed 中止写入（`:134-144`）。
- **F-3 新建空样品字段与目录结构：**
  - `Sources/SpinLabApp/Library/NativeSampleCreationService.swift:197-217`：新建空样品时 `metadata`、`orderedMetadata`、`numericTags`、`numericDisplay`、`appliedMeasurements`、`measurementSets` 均为空集合，`origin = "native"`，`sampleUID` 为随机 UUID，`displayName` / `batchId` / `substrate*` 为建档基础信息。
  - `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift:68-79`：创建样品抽屉时建立 `tests/{XRD,M-H,R-H,EDS,AFM}`、`plots/`、`analysis/`、`measurements/` 空目录。
- **F-4 测量与图表产物布局：**
  - `Sources/SpinLabApp/Library/LibraryArtifactLayout.swift:23-41`：`samples/<sampleKey>/_spinlab/{results_index.json, measurement_plot_index.json, measurement_data.json}`、`samples/<sampleKey>/charts/`（单样品图）、`_spinlab/multi-sample/charts/`（多样品共享图）。
  - `Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift:52-53,95-98`：多样品共享图实体放在 `_spinlab/multi-sample/charts/`，同时在每个参与样品的 `samples/<sk>/_spinlab/results_index.json` 写入引用。
  - `Sources/SpinLabApp/Library/LibraryChartIndexStore.swift:7-11`：`LibraryIndexReadStatus` 区分 `.ok` / `.missing` / `.corrupt`。`LibraryMeasurementDataStore.swift:45-56`：`loadStrict` 缺失返回 `nil`，损坏或不支持的 schema 抛出错误。
- **F-5 视图、搜索与 Workbench 消费者：**
  - `Sources/SpinLabApp/App/LibraryPreviewComputationService.swift:4-17`：`buildPreviewGroups(from: index)` 直接按 `index.samples` 构建 `libraryExistingGroups`。
  - `Sources/SpinLabApp/App/SpinLabAppState+LibraryCoordination.swift:232-233`：`applyExistingIndex` 用 `index` 构建 `libraryExistingGroups` 并调用 `inboxFeatureStore.rebuildDrawerMatchCandidates(from: index.samples)`。
  - `Sources/SpinLabApp/Features/Library/LibraryWorkspaceState+Search.swift:45-59`：Library 普通搜索读取 `appState.library.libraryExistingGroups`。
  - `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift:62-88`：Workbench 选样通过 `sidecarBulkReader.enumerateSidecars(rootURL:)` 扫描磁盘上的 `.spinlab.json` sidecar 生成命中结果，不经 `libraryExistingGroups`。
  - `Sources/SpinLabApp/Library/WorkflowGalleryQueryService.swift:28-30,50-65`：Workflow Gallery 扫描 `samples/<sampleKey>/` 下的索引文件。
- **F-6 Registry 同步与任务 2 安全护栏：**
  - `Sources/SpinLabApp/Library/LibraryDiffEngine.swift:14-49`：`diff(current:updated:)` 将存在于 `current` 但不在 `updated` 的非 native 样品放入 `removedSamples`，仍在 `updated` 中的非 native 样品比较字段变更放入 `changedSamples`。
  - `Sources/SpinLabApp/Library/LibrarySyncService.swift:255,280,399,425`：写前调用 `LibraryMutationSafetyGuard.validateRegistryDiffSafety` 与 `validateNoRegistryRemovalAfterPreparation`；一旦 `removedSamples` 非空即整批/全库拒绝写入。
  - `Sources/SpinLabApp/Library/LibraryMutationSafetyGuard.swift:34-57`：`detectOrphanArtifact` 检查物理样品抽屉目录是否存在；只要 `batches/<batch>/samples/<sampleKey>/` 存在即不判定为孤儿产物。
- **F-7 路由与侧边栏：**
  - `Sources/SpinLabApp/App/SidebarMenuModel.swift:3-13`、`Sources/SpinLabApp/App/SpinLabSidebarMenuProvider.swift:83-93`、`Sources/SpinLabApp/App/State/AppRouter.swift:3-21,41-67`：Library 固定节点（如 `.librarySearch`）通过 `SidebarMenuNodeKind` + `AppRoutePath` 路由。

---

## 2. Options（路线比较）

### 2.1 废纸篓标记存储方式

| 选项 | 做法 | 结论与理由 |
|---|---|---|
| **A（采用）：`LibrarySample.deletedAt: Date? = nil` 存入 `sample.json`** | 在 `LibrarySample` 增加可选 `deletedAt` 字段，向后兼容解码（缺失即 `nil`，表示正常样品）；软删除写 `deletedAt = Date()`，还原写 `deletedAt = nil`。物理目录原地保留。 | **采用**。`sample.json` 已是样品唯一权威来源；无第二份状态文件可漂移；`LibraryStore.scanIndexFromFilesystem` 天然读入索引；旧库零迁移；物理目录不搬动，还原零冲突。 |
| **B（否决）：独立 `trash_index.json` 或 `.trashed` 标记文件** | 在 Library 根目录或样品目录旁维护单独废纸篓清单。 | **否决**。引入第二权威，容易与 `sample.json` / `library_index.json` 状态不一致，增加 fail-closed 扫描复杂度。 |
| **C（否决）：软删除时把目录搬到 `_spinlab/trash/`** | 移动 `batches/<batch>/samples/<sampleKey>/` 到隐藏废纸篓目录。 | **否决**。直接违反 `Plan.md` §3“软删除不得移动或删除磁盘上的物理文件”，且会导致还原路径冲突及破坏 `samples/<sampleKey>/` 引用。 |

### 2.2 彻底删除时对多样品共享图表的处理

| 选项 | 做法 | 结论与理由 |
|---|---|---|
| **A（采用）：仅删除样品自身目录，不删除 `_spinlab/multi-sample/charts/`** | 彻底删除样品 `S` 时，删除 `batches/<batch>/samples/<S>/`、更新对应 `batch.json` 的 `sampleKeys`，并删除 `samples/<S>/`（仅含 `S` 自己的 `_spinlab/`、单样品 `charts/`、`deleted-charts/`）；`_spinlab/multi-sample/charts/` 保持不动。 | **采用**。Plan §4 明确不引入链接表或 SQLite；多样品图存放在 `_spinlab/multi-sample/charts/` 供多个样品共享（F-4），不触碰该目录可 100% 保证不误删其他正常样品引用的共享图，且不破坏其他样品的 `results_index.json`。 |
| **B（否决）：遍历全库所有 `results_index.json` 做引用计数 GC 并删共享图** | 彻底删除前扫描全库 `samples/*/_spinlab/results_index.json` 统计引用数，归零时删除共享 PNG/manifest。 | **否决**。在无链接表阶段提前实现隐式 GC，若任一非目标样品索引暂时异常会阻塞单个废纸篓样品的彻底删除，且属于任务 5 链接表之后的职责范围。 |

---

## 3. Assumptions（默认前提）

1. **A-1 单写者与串行操作**：SpinLab 为单人桌面应用，所有 Library 写操作（软删除、还原、彻底删除、Registry 同步、样本编辑）均在 `@MainActor` 串行发起，且每次磁盘写后通过 `LibraryStore.syncIndexFromFilesystem` 原子重建 `library_index.json`，不会出现并发双写竞争。
2. **A-2 批量“清空废纸篓”的局部失败语义**：清空废纸篓逐个执行单个样品的彻底删除；若某个样品因磁盘权限或目录异常失败，停止或跳过失败项并向用户明确报错，已删除的样品不回滚，未删除的样品仍留在废纸篓中。
3. **A-3 废纸篓内样品不可编辑与不可同步**：样品处于废纸篓期间，普通编辑、Inbox 匹配、Workbench 选样均不可见/不可用；仅支持在废纸篓视图中“还原”或“彻底删除”。
4. **A-4 Batch 右键删除保持禁用**：`Plan.md` §4 明确不做批次级一键物理清空，因此 `RootSplitView` 的 Batch 右键菜单“Delete Drawer…”及 `LibraryStore.deleteBatchDrawer` 继续保持禁用语义（不开启批次删除）。
5. **A-5 多样品共享图表文件保留**：彻底删除参与过多样品图的样品时，该样品自身的 `samples/<sampleKey>/` 目录被物理删除，但 `_spinlab/multi-sample/charts/` 下的共享图文件保留在原处，确保其他正常样品引用不受损。

---

## 4. 核心设计

### 4.1 数据模型与持久化

- 在 `LibrarySample`（`LibraryDomainModels.swift`）新增：
  - `var deletedAt: Date? = nil`
  - `var isTrashed: Bool { deletedAt != nil }`
  - `CodingKeys` 增加 `case deletedAt`；`init(from decoder:)` 使用 `decodeIfPresent(Date.self, forKey: .deletedAt)`（旧文件缺该字段时默认为 `nil`）。
- 在 `LibraryStore+Drawers.swift` 的 `updateSample` 与 `createDrawer` 中，像保留 `sampleUID`/`legacySampleKey`/`origin` 一样保留已有 `sample.json` 上的 `deletedAt`（除非调用方是显式的软删除/还原接口），防止任何常规更新意外覆盖废纸篓状态。
- 提供显式领域操作（经 `LibraryMutationService` -> `LibraryStore`）：
  1. `moveSampleToTrash(sample:rootURL:)`: 读取磁盘当前 `sample.json`（fail-closed：不可读则报错停止），设置 `deletedAt = Date()`、`updatedAt = Date()`，原子写入 `sample.json`，随后 `syncIndexFromFilesystem(rootURL:)`。
  2. `restoreSampleFromTrash(sample:rootURL:)`: 读取磁盘当前 `sample.json`（fail-closed），设置 `deletedAt = nil`、`updatedAt = Date()`，原子写入 `sample.json`，随后 `syncIndexFromFilesystem(rootURL:)`。
  3. `permanentlyDeleteTrashedSample(sample:rootURL:)`: 仅允许 `sample.isTrashed == true` 的样品（防止误删正常样品）；先校验路径在 `rootURL` 内（防路径逃逸/符号链接），然后：
     - 删除 `batches/<batch>/samples/<sampleKey>/`；
     - 更新对应 `batch.json` 的 `sampleKeys`（移除该 `sampleKey`；若 `batch.json` 更新失败则抛出 `batchUpdateFailedAfterSampleDeletion` 并记录）；
     - 若 `samples/<sampleKey>/` 存在，删除 `samples/<sampleKey>/`（含其私有的 `_spinlab/`、`charts/`、`deleted-charts/`）；不触碰 `_spinlab/multi-sample/charts/`；
     - 调用 `syncIndexFromFilesystem(rootURL:)` 刷新 `library_index.json`（若 `syncIndexFromFilesystem` 失败则报错提示）。

### 4.2 “空样品”判定口径（Fail-Closed）

定义统一只读检查函数（如 `LibrarySampleEmptyCheck`），返回 `.empty`、`.nonEmpty(reasons: [String])` 或 `.unreadable(reason: String)`；**只有明确为 `.empty` 时才免二次确认直接进废纸篓**，`.nonEmpty` 与 `.unreadable` 均触发确认弹窗（或提示不可读原因并要求确认/中止）：
1. **建档/手填参数**（来自 `LibrarySample`）：`metadata` 去掉空白后全空、`orderedMetadata` 无非空值、`numericTags.isEmpty`、`numericDisplay.isEmpty`。
2. **已应用测量与测量集**：`appliedMeasurements.isEmpty`、`measurementSets.isEmpty`，且样品目录下不存在 `measurement_sets.json`（或存在但解码为空数组；损坏则判 `.unreadable`）。
3. **样品抽屉目录文件**（`batches/<batch>/samples/<sampleKey>/`）：除 `sample.json`、`measurement_sets.json` 及隐藏文件（如 `.DS_Store`）外，`tests/`、`plots/`、`analysis/`、`measurements/` 及任意子目录下没有任何普通文件（含 `.spinlab.json` sidecar）。若目录不可枚举，判 `.unreadable`。
4. **Workbench 产物目录**（`samples/<sampleKey>/`）：
   - `samples/<sampleKey>/_spinlab/measurement_data.json`：不存在，或 `loadStrict` 返回 `records.isEmpty && latestIndex.isEmpty`；若损坏/不可读判 `.unreadable`。
   - `samples/<sampleKey>/_spinlab/results_index.json`：使用 `loadResultsIndexForAudit`，`.missing` 或 `.ok(references.isEmpty)` 视为空；`.corrupt` 判 `.unreadable`。
   - `samples/<sampleKey>/_spinlab/measurement_plot_index.json`：使用 `loadPlotIndexForAudit`，`.missing` 或 `.ok(entries.isEmpty)` 视为空；`.corrupt` 判 `.unreadable`。
   - `samples/<sampleKey>/charts/`：不存在或无非隐藏文件；若不可枚举判 `.unreadable`。

### 4.3 视图、搜索与 Workbench 隔离

- **常规 Library 列表与侧边栏**：`LibraryPreviewComputationService.buildPreviewGroups(from: index)` 过滤 `index.samples.filter { !$0.isTrashed }`。`LibraryFeatureStore` 同步维护 `libraryTrashedSamples: [LibrarySample]`（来自 `index.samples.filter(\.isTrashed)`，按 `deletedAt` 倒序）。
- **Library 普通搜索**：`LibraryWorkspaceState+Search.swift` 读取 `libraryExistingGroups`，自动排除废纸篓样品。
- **Inbox 匹配**：`SpinLabAppState+LibraryCoordination.swift:233` 改为传入 `index.samples.filter { !$0.isTrashed }` 给 `rebuildDrawerMatchCandidates`。
- **Workbench 选样搜索**：`SearchWorkflowMeasurementsUseCase.execute` 读取 `libraryAccess.loadIndex(from: resolvedLibraryRootURL)`（或基于 `trashedSampleKeys` 集合，同时匹配原始 `id` 与 sanitized disk key），在构建/过滤命中结果时跳过所有属于废纸篓样品的 sidecar。
- **Workflow Gallery**：`WorkflowGalleryQueryService.execute` 过滤掉 `trashedSampleKeys` 对应的单样品结果；多样品图仅在全部关联样品均为废纸篓样品（或无活跃样品引用）时隐藏，若仍有正常样品引用则继续展示。
- **UI 入口**：
  - 在样品详情页头部（`LibrarySampleDetailHeaderView`）增加“Delete”按钮（非编辑态可用）；点击时执行空样品检查：空样品直接进废纸篓，非空样品弹出二次确认（确认“Move to Trash”/取消）。若当前选中的样品被移入废纸篓，自动清空或切换当前选中态，不留在已隐藏样品详情页。
  - 在 `SidebarMenuNodeKind`、`AppRoutePath`、`SpinLabSidebarMenuProvider`、`AppRouter` 增加固定节点 `.libraryTrash`（标题 `"Trash"`，图标 `"trash"`，显示废纸篓样品数量 badge）。
  - 废纸篓视图展示所有 `libraryTrashedSamples`（样品名、批次、衬底、删除时间），每行提供 **Restore（还原）** 与 **Delete Permanently（彻底删除）**；顶部提供 **Empty Trash（清空废纸篓）**。彻底删除与清空废纸篓均弹出不可逆二次确认弹窗（含样品名/数量警示）。UI 遵守 `specs/04_UI_RULES.md`（使用 `AppSpacing` 与 `AppFontScale`）。

### 4.4 Registry 同步隔离

- 在 `LibraryDiffEngine.diff(current:updated:)` 中：
  - 若 `existing.isTrashed`：跳过字段比较与更新（不加入 `changedSamples`），防止 Registry 同步用无 `deletedAt` 的表格记录覆盖 `sample.json` 导致复活；同时向 `warnings` 或日志记录保留跳过信息（不影响正常同步结果）。
  - 在遍历 `current.samples where updatedSamples[sample.id] == nil` 时：若 `sample.isTrashed`，跳过不加入 `removedSamples`。原因：废纸篓样品已被用户软删除，不应被视作“Registry 缺行导致的未授权删除”而阻断同批次其他正常样品的同步，同时也不应触发物理删除。**活跃样品（`!sample.isTrashed`）仍严格保持原样进入 `removedSamples`，继续受 `LibraryMutationSafetyGuard` 拦截保护**。
  - 若 `updated` 中出现一个与 `current` 某废纸篓样品同 `id` 的记录：因为 `currentSamples[sample.id]` 存在且 `existing.isTrashed == true`，在首个 `for sample in updated.samples` 循环中即被跳过，既不会进入 `newSamples` 也不会覆盖现有 `sample.json`。

---

## 5. 不变量（Invariants）

- **I1（编号与目录不变）**：软删除与还原绝不修改 `sample.id`、`sampleUID`、`legacySampleKey` 或物理目录路径。
- **I2（软删除零删盘）**：`moveSampleToTrash` 只修改 `sample.json` 的 `deletedAt`/`updatedAt` 并刷新 `library_index.json`，不移动、不删除任何测量或图表文件。
- **I3（Fail-Closed 判定）**：任何 `sample.json`、`measurement_data.json`、`results_index.json` 或 `measurement_plot_index.json` 损坏/不可读时，不得被判为空样品免确认删除，也不得被隐式覆盖。
- **I4（同步不复活、不误删）**：Registry 同步对 `isTrashed == true` 的样品既不清除 `deletedAt`，也不执行物理删除；对活跃样品继续维持任务 2 的缺行/改键保护。
- **I5（彻底删除边界）**：`permanentlyDeleteTrashedSample` 仅可删除 `isTrashed == true` 的样品自身目录，绝不删除 `_spinlab/multi-sample/charts/` 下的共享图表文件。
- **I6（批次删除保持关闭）**：`deleteBatchDrawer` 继续抛出 `LibraryDrawerError.deletionDisabled`。

---

## 6. 验证矩阵（声明 → 失效方式 → 检出证据）

| 声明 | 可能的失效方式 | 检出证据（测试） |
|---|---|---|
| 空样品免确认直接进废纸篓，且全视图隐藏 | 误判非空样品为空；或 Workbench sidecar 搜索 / Inbox / Library 搜索仍能查到已软删除样品 | 单测 + 集成测试：新建空样品→判定为 `.empty`→`moveSampleToTrash`→`libraryExistingGroups`、Library 搜索、`SearchWorkflowMeasurementsUseCase`、`rebuildDrawerMatchCandidates` 均不包含该样品，`libraryTrashedSamples` 包含它 |
| 有数据/图/手填参数的样品需二次确认，软删除不删盘 | 有 `metadata`/`numericTags`/`measurement_data`/`results_index`/文件时被误判为空；或软删除删掉了磁盘文件 | 单测：分别构造含 `metadata`、含 `numericTags`、含 `appliedMeasurements`/sidecar、含 `results_index`/PNG、含损坏 JSON 的样品→均不返回 `.empty`；软删除后断言磁盘所有测量与图文件字节级完好 |
| Registry 同步不复活、不物理删除废纸篓样品 | `LibraryDiffEngine` 把废纸篓样品当 `changedSamples` 覆盖清空 `deletedAt`，或当 `removedSamples` 触发安全拒绝阻断同批正常样品 | 单测 + 同步测试：(1) 废纸篓样品仍在 Registry 表格中→sync 后仍为 `isTrashed` 且不被修改；(2) 废纸篓样品从 Registry 表格移除→sync 不报错且不删盘，同批次活跃样品正常更新；(3) 活跃样品从 Registry 移除→仍被 `LibraryMutationSafetyGuard` 拒绝 |
| 一键还原恢复原样 | `deletedAt` 未清零，或 `batch.json` / `library_index.json` 未同步导致还原后列表或测量/图不可用 | 集成测试：有测量与图的样品进废纸篓→`restoreSampleFromTrash`→回到 `libraryExistingGroups` 原批次，`deletedAt == nil`，sidecar 与图表读取完整 |
| 彻底删除仅删样品自身目录，不误删共享图 | 未进废纸篓样品被直接彻底删除；或删除样品 A 时误删 `_spinlab/multi-sample/charts/` 导致正常样品 B 图表丢失 | 单测：(1) 对未进废纸篓样品调用 `permanentlyDeleteTrashedSample` 失败拒绝；(2) 样品 A（废纸篓）与正常样品 B 共享 `_spinlab/multi-sample/charts/shared.png`→彻底删除 A 后，`batches/.../A` 与 `samples/A` 消失，`batch.json` 移除 A，而 `shared.png` 与样品 B 的 `results_index.json` 完好 |
| 旧版无 `deletedAt` 的 `sample.json` 向后兼容 | 解码旧 JSON 失败导致整库不可读 | 单测：解码不含 `deletedAt` 键的旧格式 `sample.json`→`deletedAt == nil`、`isTrashed == false` |

---

## 7. 最小实现顺序与授权草案

1. **阶段 1（领域模型与存储核心）**：`LibrarySample.deletedAt` 解码兼容；`LibrarySampleEmptyCheck`；`LibraryStore` 软删除/还原/彻底删除实现；`LibraryDiffEngine` 废纸篓隔离；对应单元测试。
2. **阶段 2（消费者过滤与服务接入）**：`LibraryPreviewComputationService`、`SpinLabAppState+LibraryCoordination`、`SearchWorkflowMeasurementsUseCase`、`WorkflowGalleryQueryService`、`LibraryMutationService`、`LibraryFeatureStore` 状态与方法接入；对应测试。
3. **阶段 3（UI 与路由）**：`.libraryTrash` 路由与侧边栏入口、废纸篓视图（还原/彻底删除/清空废纸篓+不可逆弹窗）、样品详情页“Delete”按钮与分级确认弹窗；UI 规则检查与全量测试。

- **当前需要用户确认的授权（Code 阶段前）**：
  - 修改代码与测试（本仓库 `docs/task-9-trash-brief` 或新建实现分支）
  - Commit & Push
  - 更新 `docs/V5_ROADMAP.md` 5.6.x 任务 9 勾选状态（PR 合并前由用户决定是否合并）

---

## 8. Work Contract（Code 阶段直接执行）

### 目标与范围
在 SpinLab 中实现任务 9（Zotero 式废纸篓软删除、分级确认、还原、手动彻底删除/清空废纸篓及视图/Registry 同步隔离）。严格遵守 `Plan.md` §3–§4、`SKELETON.md` K1–K13 与任务 2 安全护栏：不做定时清空、不做 Batch 级删除、不做还原重定位到新批次、不引入 SQLite 或链接表。

### 必需不变量与边界
- 软删除仅设置 `LibrarySample.deletedAt = Date()`（写入 `sample.json` 并同步 `library_index.json`），严禁移动或删除物理目录及测量/图表文件。
- 空样品判定（无手填/额外 `metadata`/`numericTags`/`numericDisplay`、无测量/测量集/sidecar、无图/结果索引、无非隐藏文件）必须 fail-closed：任何不可读或损坏文件不得判为空样品。
- 废纸篓样品在 `libraryExistingGroups`、Library 搜索、Inbox 匹配、Workbench sidecar 搜索（`SearchWorkflowMeasurementsUseCase`）中不可见。
- `LibraryDiffEngine` 跳过 `isTrashed == true` 的样品（不更新、不复活、不列入 `removedSamples`）；活跃样品缺失仍由 `LibraryMutationSafetyGuard` 阻断。
- 彻底删除仅允许针对 `isTrashed == true` 的样品，删除 `batches/<batch>/samples/<sampleKey>/`、`samples/<sampleKey>/` 并更新 `batch.json` 与 `library_index.json`，严禁删除 `_spinlab/multi-sample/charts/` 下的共享文件。
- `deleteBatchDrawer` 继续抛出 `LibraryDrawerError.deletionDisabled`。

### 全局验收标准（AC）
1. 空样品点删除：无二次确认直接进废纸篓；常规 Library 列表、Library 搜索、Workbench 选样均不可见，仅废纸篓视图可见。
2. 有测量、图或手填参数的样品点删除：弹出二次确认；取消则无任何变更；确认后进废纸篓且磁盘文件保留在原处。
3. 废纸篓期间执行 Registry 同步：废纸篓样品既不复活也不被物理删除。
4. 废纸篓点“还原”：样品回到原批次与常规视图，原有测量与图完整可用。
5. 废纸篓点“彻底删除”或“清空废纸篓”：弹出不可逆二次确认；确认后物理删除样品自身目录，不误删其他正常样品引用的共享文件。

### 验证与收尾要求
- 定向运行新增及受影响的 `Library*` / `Search*` / `Registry*` 单元测试，随后运行 `swift test`。
- UI 改动遵守 `specs/04_UI_RULES.md`，运行 `./scripts/check_ui_rules.sh`（只允许违规数下降，禁止调高基线）。
- 遵循 `AGENTS.md` Change closeout：运行 `./scripts/check_required_actions.sh`，若要求则运行 `./scripts/build_desktop_app.sh debug` 并报告完整输出。
- 在 PR 中勾选 `docs/V5_ROADMAP.md` 5.6.x 任务 9。

### 停止条件
- 实现全部 AC 并通过全部本地测试与门禁检查后停止，向用户报告测试结果与验收步骤，等待用户亲手验收及决定合并。
