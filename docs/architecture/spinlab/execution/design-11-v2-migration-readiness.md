# 任务 11A 设计：旧 Library → Storage V2 迁移准备度与兼容性审计

对应需求合同：[brief-11-v2-migration.md](brief-11-v2-migration.md)；共同语义：[SKELETON.md](SKELETON.md) K1–K13；前置：[design-10](design-10-storage-v2.md)、[design-5](design-5-afm-standard-assets.md)、[design-12](design-12-workbench-sample-results.md)。

基线：main `03033959`（v6.12.0）+ 本分支 brief 提交。**本文只含设计与静态审计**：没有改 Swift，没有运行 App，没有读取真实 Library，没有任何迁移。所有“代码证据”均为静态读码（文件/符号），证据类型已逐项标明；凡未运行验证的都列在 §8。

---

## 0. 结论（先看这里）

1. **今天把真实旧库切到 V2，会丢失除 AFM 以外所有工作流的日常能力。** V2 Inbox 只有 `afm` 一个标准化适配器，其余工作流（MR、AHE、3w、RT、XY、IV 以及 RSM 图保存）在 V2 下写入一律被明确拒绝，新测量无法入库。这是“既有必要能力丢失”，属 **类①：迁移前必须解决**；但具体解决到什么程度取决于用户实际在用哪些工作流（§5 决策 D1），不应默认把所有工作流一次性重写。
2. **V2 目前没有一致备份**：`LibraryStore.syncBackup` 对 V2 直接返回 `false`。没有备份就没有切换后的回退与保护，属类①，且范围小、可独立做（R0）。
3. **旧数据的历史产物（侧车、测量集、`measurement_data.json`、历史图、Analysis Pack）在 V2 下没有落点，也没有读取方。** 它们的身份依赖路径（`batches/…/samples/<sampleKey>/…`、`samples/<sampleKey>/…`），不是稳定 ID；盲目搬目录会使身份消失（违反 K1）。这需要用户决定 D2。
4. **AFM 是唯一有 V2 正式路径的工作流**。**推荐（待 D2 确认）**：旧库里的 AFM 原始文件通过现有 AFM 适配器从字节不变的原始文件重新入库，而不是复制旧产物；这会产生新的 Source/Dataset 记录且不带入旧 AFM 侧车/图历史，该取舍与 D2 一并由用户确认；可行性须在 11B 用合成夹具证实。
5. **RT/3ω 的“Result 赋值”在 V2 不可用不是迁移阻塞**（它们在 V1 也没有该能力，Task 12 只做了 AHE）。**AHE 的 Result 赋值**在 V2 被禁用，其前提是 AHE 输入可在 V2 使用，随 D1/R1 一起处理，不单列为阻塞。
6. 推荐切换形态：**在新位置构建完整 V2 副本，经完整对账后通过切换 Library 根位置（而非原地改写）生效；迁移构建本身不改源库。**（例外：P1 若发现缺 `sampleUID`，须先在 V1 用现有 PR #220 补发流程——它会备份后原位写 `sample.json`——这是迁移前独立、已授权类型的 V1 写入，必须在预检与“源库基线哈希”之前完成；也可另行决定改为副本内签发，属待定。） 切换后新写入无法自动回灌旧库，须明确选择（D3）。
7. 真实库的任何读取、复制、迁移都需用户另行授权；major 版本（Library 数据格式迁移）需 Jack 逐次确认（AGENTS Versioning）。

---

## 1. 方法与证据口径

- 审计对象是 main 当前源码；已有 PR 文档/验收报告只作线索，不当作本轮验证。
- 证据类型：**S** = 静态读码（本文）；**D** = 已有设计文档声明；**T** = 已有测试存在（未在本轮运行，仅核对文件存在，如 `StorageV2LayoutRoutingTests.swift`）；**?** = 未知，须 11B 夹具验证。
- “支持”只在读码确认完整读/写/删除路径存在时才写；入口存在不等于可用。
- 不使用真实 Library；所有后续验证用合成夹具（见 §7）。

---

## 2. V1/V2 消费者兼容矩阵（AC1）

状态：✔ 支持 / ◐ 部分（说明）/ ✖ V2 明确拒绝 / ? 未知。“迁移后影响”指真实旧库切到 V2 后用户可见的结果。

### 2.1 布局、身份与记录

| 消费者 | 用户行为 / 读写对象与权威 | 代码证据（S） | V1 | V2 | 迁移后影响 | 最小修复 / 备注 |
|---|---|---|---|---|---|---|
| 布局识别 | 版本标记、混合/损坏 fail-closed | `LibraryLayoutRouter.resolve`；V2 要求 `_spinlab/layout_version.json` 且不得存在顶层 `batches/`；仅检查 `batches/`、`records/`、`index/`，**不检查顶层 `samples/`** | ✔（无标记合法） | ✔ | 源库的 `batches/` 不能与 V2 并存 ⇒ 不能原地转换，须副本 | 顶层 `samples/` 在 V2 下既不被拒也不被读（见 2.4），需明确处理（D2） |
| Batch/Sample 记录读写 | `batch.json`、`sample.json` | `LibraryStore+PathsAndCache`（`sampleDirectoryURL` 按布局路由，V2 取 `records/samples/<uid>`）、`+Drawers`、`+RootAndIndex`（V2 扫描 `records/samples/*`，重复 UID、缺 UID 记 issue） | ✔ | ✔（T：`StorageV2LayoutRoutingTests`） | 目录名由 sampleKey 变 UID | 前提：全部 Sample 有合法唯一 `sampleUID`（见 §3） |
| 新建样品（桌面/手机） | `NativeSampleCreationService`、`PhoneSamplePickup` | `NativeSampleCreationService`（`resolveLayout().isV2` 分支）；手机 UID 由提交号确定性生成 | ✔ | ✔(S，D) | 无退化 | 夹具回归即可 |
| Growth 权威 | V2 在 Batch 上唯一权威，Sample 页只读 | design-10 §2.2（D）；实际落地状态：10B 是否全部合并 **?**（须在 11B 起点按代码核对） | 兼容保留 | ✔(D) | 旧库重复/冲突须报告 | §3 |
| Result Definitions / 当前值 | `_spinlab/result_definitions.json` + `sample.json.results` | `LibraryResultService`（按布局路由，V2 用 UID）；Task 12 设计 F7（D） | ✔ | ✔ | 原样保留 | 迁移：忠实复制，对账精确值/单位/空 |

### 2.2 Inbox、原始文件与标准化

| 消费者 | 证据（S） | V1 | V2 | 迁移后影响 | 最小修复 |
|---|---|---|---|---|---|
| Inbox 路由/确认 | `InboxSelectionWorkbenchPanel`（`isV2LibraryLayout` 分支，非 AFM 时不可确认） | ✔ 全部工作流 | ◐ 仅 AFM | **非 AFM 新测量无法入库** | 类①，见 R1 |
| Inbox Apply | `InboxArchiveApplyService.standardizationAdapter(forWorkflowID:)` 只返回 `AFMIBWStandardizationAdapter`（`"afm"`），其余 `nil` → `applyV2` 抛 `LibraryLayoutError.v2UnsupportedOperation`（S） | ✔ | ◐ 仅 AFM | 同上 | R1（逐工作流） |
| 原始文件复制 | `LibraryStore.copyMeasurementFile`：V2 或布局无效直接 `nil`；V1 复制到 `<sample>/measurements/` | ✔ | ✖（不复制） | 同上 | 随 R1 |
| 侧车 / `measurement_sets.json` 写入 | `LibraryStore.saveMeasurementSets` 经 `requireV1ArtifactWriteAllowed`，V2 抛 `v2UnsupportedOperation`；`LibrarySidecarWriter.saveSidecar` 自身无布局守卫，V2 下由上游 Apply 入口拦截（S） | ✔ | ✖ | 同上 | 随 R1 |
| 导入去重 | `SpinLabAppState+ImportDeduplication`：非 V1 直接返回 `[]`（V2 无 V1 去重）；AFM 由资产库 `findSources(sha256:ownedBySampleUID:)` 去重 | ✔ | AFM ✔；其他工作流无入口所以无需 | 随 R1 补充 | 与 R1 同步 |
| 原始文件字节不变 / 哈希 | `ContentFingerprintService`、`LibraryAssetService.ingestAsset`（登记 sha256，写入 `storage/`） | ✔（原样） | ✔（AFM） | AFM 重新入库可对账哈希 | §4 |

### 2.3 Workbench

| 工作流 | 读取 | 写入（Pack/图/指标） | V2 实际 | 迁移后影响 | 备注 |
|---|---|---|---|---|---|
| AFM | 标准 Dataset（`standardDatasetHits`，`inputRef == .datasetV2`） | 正式 Plot（`FormalPlotSaveBar`/`AFMWorkspaceStore+FormalPlot`）、自动出图（Task 7） | ✔(D、T) | AFM 历史须经标准 Dataset 重新入库后才在 V2 可见 | §4 |
| AHE | 旧侧车命中（`inputRef == nil`），身份为 `sampleKey`（Task 12 F9，D） | `PersistMeasurementData`、`PersistChartArtifact`、Pack：V2 抛不支持 | ✖ | 同类①，含 Result 赋值禁用 | 随 R1；赋值恢复为 R1 的后继小项 |
| RT / 3ω / XY / IV / MR | 同 AHE（旧侧车 + 路径推导身份）；Workbench Store 中无 V2 分支（S：对这些 `*WorkspaceStore` 检索 `v2/V2` 无命中） | 同上 | ✖ | 同上 | RT/3ω 新增 Result 赋值是**新功能**，非阻塞 |
| RSM | 同上；`SaveRSMChartToLibraryUseCase` V2 返回 failure | ✖ | ✖ | 同上 | 按实际使用决定是否纳入 |
| 历史图 / Analysis Pack 打开 | 路径 `samples/<sampleKey>/charts`、`samples/<sampleKey>/_spinlab/*.json`（`LibraryArtifactLayout`）；Analysis Pack 在 `_spinlab/analysis_packs/<workflowID>/<packID>.json`（`AnalysisVault`，库级而非样品级） | — | **无 V2 读取方**（V2 样品目录无这些文件） | 历史成果在 V2 不可见 | D2 |
| 跨样品图 | `_spinlab/multi-sample/charts/`，manifest 记录**绝对原始路径**（SKELETON，D） | — | 无 V2 落点 | 绝对路径迁移后失效 | 只报告，不改写（§4） |
| 搜索 | `SearchWorkflowMeasurementsUseCase`：先扫全库侧车（根目录递归 `LibrarySidecarBulkReader`），V2 再追加 AFM 标准 Dataset 命中；`parsePathInfo` 用路径中的 `batches/…/samples/<key>/measurements/<workflow>` 推 batchID/sampleKey（S） | ✔ | AFM ✔；旧侧车命中在 V2 下**无物理来源** | 同上 | 路径即身份是迁移不能“搬目录”的直接证据 |

### 2.4 其它

| 消费者 | 证据（S） | V1 | V2 | 迁移后影响 | 备注 |
|---|---|---|---|---|---|
| 备份 | `LibraryStore.syncBackup`：V2 → `return false`（不一致拷贝风险，注释说明） | ✔ | ✖ 无备份 | 切换后没有自动备份，**也无法用现有机制做迁移前后备份对照** | **R0，类①** |
| 废纸篓/恢复/永久删除 | V1：`LibraryStore+Drawers` 目录删除；V2：`LibraryAssetService+Deletion` + `LibraryTrashView` V2 分支；`LibrarySampleEmptyCheck` V2 分支 | ✔ | ✔(S，D：Task 9/5) | 无退化；迁移须保留废纸篓状态 | 恢复/删除对账进 §3 |
| 孤儿产物守卫 | `LibraryMutationSafetyGuard.detectOrphanArtifact`：V2 直接 `(false, nil)` | ✔ | ✔（V2 无旧目录） | 无 | 合法的跳过 |
| 旧 UID 补发 | `LegacySampleBackfillService`：V2 抛 `v2UnsupportedOperation`；V1 先预演、备份再原位补写 | ✔ | ✖（合理） | **必须在 V1 阶段先完成** | §3 前提 |
| Recompute 侧车 | `LibrarySidecarService.recomputeAllMeasurementSidecars`：V2/无效布局显式返回全零结果（静默空操作，S） | ✔ | ✖（空操作，无报错） | V2 下 Recompute 什么都不做；V2 无旧侧车，故无实际损失，但 UI 不应暗示已重算 | 随 R1/D2 一并处理提示 |
| Registry/XLSX 同步 | `LibrarySyncService`/`LibraryRegistrySyncService`/`LibraryXLSXSyncService` 对布局无显式分支，经 `LibraryStore` 路由（S）；V2 下是否全程正确 | ✔ | **?** | 未验证 | 11B 合成夹具回归（不预设为阻塞） |
| 旧产物审计/清理/图库 | `ChartAssetAuditService`、`LibraryDiskCleanupService`、`SamplePlotsOverviewService`、`WorkflowGalleryQueryService` 经 `LibraryArtifactLayout.samplesRootURL()` 直接操作顶层 `samples/`；`LibraryStore+Drawers` 永久删除 V1 分支删除 `samples/<key>`；均无布局守卫（S） | ✔ | **未定义**：V2 根下若存在顶层 `samples/`，这些服务会扫描甚至修改它 | 迁移副本**不得**含顶层 `samples/`（预检断言）；V2 无该目录时它们读到空 | 11B 夹具验证并考虑补守卫；强化 D2 (c) |
| 手机提交 / Publish / 网页投影 | `PhoneSamplePickup`（经 `NativeSampleCreationService`）；`WebLibraryPublishService`（读索引/快照） | ✔ | ◐/？：手机新建 ✔（S，D）；Publish 读 V2 **?** | 未验证 | 11B 夹具回归 |
| 索引 | `index/library_index.json`（可重建）；V2 由 `records/` 扫描重建 | ✔ | ✔ | 重建而非迁移 | §4 |
| 单写者 | `LibraryWriteLease`（Task 3） | ✔ | ✔ | 副本构建/切换须经租约 | §6 |

### 2.5 V1 必须保留

当前 App 对合法 V1 旧库继续完整读写，直到真实库正式切换并验收。11A/11B 都不得削弱 V1（AGENTS 与 SKELETON 已规定）。

---

## 3. 数据清单、语义映射与对账（AC2）

### 3.1 迁移前提（预检，全部通过才允许构建副本；任一失败只报告）

| # | 预检项 | 规则 | 失败处理 |
|---|---|---|---|
| P1 | 每个 Sample（活跃 + 废纸篓）有合法 `sampleUID`，全库唯一 | `SampleIdentityRule.isValidUID` | 报告；需先用现有 PR #220 补发流程在 V1 完成（会备份、原位写 `sample.json` 并重建索引，须先于预检基线；补发后重新预检） |
| P2 | 历史样品 `legacySampleKey` 映射 | 历史样品必有且与目录键一致；手工/手机新建样品可无（合法） | 不一致报告 |
| P3 | Batch 归属 | `sample.batchId` 指向存在的 Batch；`batch.sampleKeys` 与按 `batchId` 聚合的成员不一致 | 报告（V1 下不阻断使用，但迁移前须人工确认） |
| P4 | Growth 重复/冲突 | `batch.numericTags` 与 `sample.numericTags` 同名不同值；按 `LibraryFieldOwnershipRuleBook`，未知保持未知 | 冲突阻止该样品迁移，**不自动选边**；一致重复不是冲突 |
| P5 | 未知 JSON 字段 | 现有模型用显式 `CodingKeys`，经 Codable 重编码会**丢失未知字段**（S，`LibrarySample` CodingKeys） | 设计规则：`sample.json`/`batch.json` 用 JSON 层“补充/重映射结构字段”，其余字段逐字节保留；不用模型往返 |
| P6 | Result Definitions / 当前值 | 目录完整可解码；每个值的 `definitionID` 存在；空值保持空 | 孤立值报告，不删不补零 |
| P7 | 原始文件 | 每个侧车/测量集引用的原始文件存在且可读，登记 sha256 | 缺失/不可读报告，不猜 |
| P8 | 重复 Source | 同内容多个登记、同一文件被两个样品引用 | 报告；K5：同一 Source 不得有两个科研归属，不自动合并 |
| P9 | 绝对/外部路径引用 | 侧车 `sourceFilePath`、多样品图 manifest 等 | 报告，不改写 |
| P10 | 未登记文件 | 样品目录中不属于任何已知对象的文件 | 报告并**保留**（不当垃圾删除） |

### 3.2 数据类别与迁移策略

| 类别 | 策略 | 对账标准 |
|---|---|---|
| Batch、Sample 记录（含废纸篓状态） | 保留（JSON 层最小结构变换，P5） | UID 集合相等；每样品除结构字段外字节一致；废纸篓集合相等 |
| Result Definitions、当前值 | 保留（逐字节复制 + 新位置） | Definition 集合与每个值（精确数值、单位、空值）一致 |
| Growth（Batch/Sample 重复） | 需人工决定（冲突时）/保留（一致时） | 逐字段对账，冲突清单为零或已决 |
| Registry/提交/笔记/变更日志 | 保留（原样复制其所在文件） | 文件哈希一致 |
| `index/library_index.json` 等索引 | **可验证重建**（不复制） | 重建结果与源库的样品/批次集合一致 |
| AFM 原始文件 | **推荐方案（待 D2 确认）忠实转换**：从原字节经现有 AFM 适配器登记 Source→Dataset（K7），Source 唯一 Sample 归属取旧库所在样品 | 每个 AFM 原文件有一个 Source；sha256 与源字节一致；Dataset 数量与通道有可解释对应（K12：无依据不创建关系） |
| AFM 旧侧车/旧 Plot/旧图 | 需人工决定（D2）；无可信 Source→Dataset→Plot 关系则**不虚构** Plot | 仅对账“已保留/未迁移”清单 |
| 非 AFM 原始文件、侧车、测量集 | **受 D1/D2 约束**（无 V2 落点） | — |
| `measurement_data.json`、`results_index`、`measurement_plot_index` | 受 D2 约束 | — |
| 历史图、Analysis Pack、跨样品图 | 受 D2 约束；绝对路径只报告 | — |
| 废纸篓里的样品与其依赖 | 保留状态；永久删除不在迁移中执行 | 废纸篓集合相等 |

### 3.3 身份映射

输入键 `sampleKey`（V1，路径身份）→ 输出 `sampleUID`（V2，稳定）；映射表来自 `sample.json`（`sampleUID` + `legacySampleKey`），**迁移报告留存**该表；PR #220 的补发备份保留到验收完成（SKELETON）。Batch ID 不变。Asset ID 由 `ingestAsset` 生成并记录“旧原始文件路径 → Source ID → sha256”。

### 3.4 冲突原则

只报告：无法解释的冲突、孤儿、未知；不猜测、不合并、不删除、不补零、不覆盖、不重算、不标准化科研内容。冲突清单为空，或每项均有用户决定，才放行。

---

## 4. 阻塞项分类与最小适配任务（AC3）

### ① 迁移前必须解决

| ID | 缺口 | 最小范围 | 依赖 | 独立验收 |
|---|---|---|---|---|
| **R0** | V2 无一致备份 | 为 V2 提供与 SQLite（WAL）一致的备份（SQLite 在线备份/检查点后复制 + 文件树），或明确的“冻结备份”；覆盖 `records/`、`storage/`、`_spinlab/` | Task 3 租约；不依赖其它 R | 合成 V2 库备份→还原→对账全一致；故障注入（备份中途中断不留下被当成完整的备份） |
| **R1** | 非 AFM 工作流无法在 V2 入库（含 AHE 输入可用于 Result 赋值） | **按 D1 选定的工作流**，逐个独立任务，各自选择“标准 Dataset 化”（AFM 方式）或 D2 的受控兼容路径；不一次重写全部 | R0 之外无依赖；各工作流互不依赖，可并行 | 每个工作流：V2 库上新文件导入→重启后可见→Workbench 分析→（如适用）保存→删除/恢复；V1 回归不变 |
| **R2** | 历史成果（侧车/图/Pack/`measurement_data`）在 V2 无落点与读取方 | 按 D2 的选项 | D2 | 迁移副本中历史项可打开且与源一致；或明确记录“未迁移”清单经用户确认 |

### ② 可以保留的明确兼容路径（须满足：有唯一权威、读写与删除边界、符合 V2 版本合同、无双写、不静默回退 V1）

- 源库作为只读归档（切换后保留，不再被 App 写入）。**不是**在 V2 库内回退读取 V1 路径。
- V1 旧库本身继续受新版完整支持，直至切换。

任何“V2 库内读取旧 `samples/`/`batches/`”的方案都属 D2，不得默认纳入（现有 Router 不检查顶层 `samples/`，若放任存在将形成未定义的混合状态，S）。

### ③ 不阻塞、后续按需

- RT/3ω 的新增 Result 赋值；AHE 之外的 Result 候选；RSM 等低使用度工作流的 V2 化（若 D1 未选中）；V2 下尚未出现需求的跨样品图新功能；旧 Library 的重复样品合并（SKELETON 明确延后）。

> 修正：#246 已知“V2 AHE 输入未迁移、赋值禁用”已核实属实（Task 12 设计 §5，D；`InboxArchiveApplyService` 无 AHE 适配器，S）。它是 R1 的一部分，不是 Result 赋值功能的回归。

---

## 5. 需用户决定的选项（保持未批准）

**D1 — 哪些工作流必须在切换前能在 V2 入库？**
推荐：先做只读盘点（用户授权后，只统计各工作流文件数、最近使用时间，不读内容），把“最近仍在持续使用的工作流”列为 R1 必做；其余可晚于切换，但要明确：切换后这些工作流暂时无法入库，期间新测量暂存 Inbox。
影响：决定切换日期与 R1 工作量（每个工作流需要自己的标准化与 Workbench 适配；工作量未估算，需单独设计后评估）。

**D2 — 非 AFM 旧历史（侧车、图、Pack、`measurement_data`）切换后怎么处理？**
- (a) 标准化：对每个工作流做 Source/Dataset，历史图/Pack 视为不迁移的“旧产物”仅保留清单；工作量最大、最干净。
- (b) 受控兼容：在 V2 内建一个**只读归档区**（含文件原样 + 迁移前路径→UID 映射），并让旧消费者只读该区；需先改 SKELETON/V2 合同，增加读取方适配。
- (c) 源库作只读归档，V2 不含这些历史，用户需要时用旧数据库另开。
推荐：(c) 作为默认下限（零丢失、零新权威），其中 AFM 与已完成 R1 的工作流走标准化；(b) 仅当用户必须在同一 Library 内浏览旧图时才做。**此选项改变科研数据可见性，须用户确认。**

**D3 — 切换后若已有新写入，是否允许回退？**
推荐：回退窗口内保持源库不动；回退 = 重新指向源库，**切换后的新写入不自动回灌**，仅在回退前生成“新写入清单”供人工处理；超过窗口后回退不再支持。不提供静默覆盖。

**D4 — Library 是否被多台电脑共用（云同步/网络位置）？** 影响“切换根位置”的做法（每台机器的设置、书签/沙盒授权）。**未知，须用户回答。**

**D5 — 迁移版本号：** Library 格式迁移属 major；设计不决定，真实迁移 PR 前由 Jack 明确（AGENTS Versioning）。

---

## 6. 迁移、备份、恢复方案（AC4 的设计部分，不写实现）

### 6.1 比较

| 方案 | 做法 | 风险 | 评价 |
|---|---|---|---|
| A 原地转换 | 在源库目录里改布局 | 违反“源库保持完整”；V2 Router 禁止与 `batches/` 并存；中断难回退 | ✖ 不采用 |
| **B 副本构建 + 切换根位置（推荐）** | 只读预检源库 → 备份源库 → 在新目录构建 V2 副本 → 对账 → 切换根位置设置 | 需额外磁盘；切换后新写入在副本（D3）；多机需同步设置（D4） | ✔ |
| C 副本构建 + 目录交换 | 重命名目录互换 | 中间时刻“根”不存在；Sandbox/书签易失效；无法保证原子 | 备选，不推荐 |

### 6.2 推荐流程（B）

1. **只读预检**（§3.1）：生成冲突/孤儿/未知报告，不写源库。有未解冲突 → 停止。
2. **备份源库**：独立位置整库复制并校验（哈希清单）；校验失败即停止。
3. **隔离副本预演（先合成夹具；经授权后才用真实库副本）**：先在合成库完整走通；对真实库只经授权后对其**副本**进行，不对真实库本体操作。
4. **构建**：在新目录写 V2 布局；构建期间不写版本标记；**最后一步**写 `_spinlab/layout_version.json`。构建顺序须**先创建 `records/`**：Router 仅在“有 `records/` 无标记”时 fail-closed（`missingVersionMarkerForRecords`）；仅有 `storage/`、`_spinlab/` 的半成品会被判为未初始化并可能被当空库使用（S），所以此外还依赖“只有标记写入且对账通过后才切换设置”。11B 须有对应故障注入。构建全程经单写者租约。
5. **对账**：§3.2 全部类别；样品/批次/Result/哈希/关系（SQLite：每 Source 恰一个 Sample 归属，每 Dataset 恰一个 Source）；索引重建一致。
6. **切换前重新校验源库**：重新计算源库清单哈希，与预检时一致才继续（防止预检后源库被改）。
7. **切换**：以设置更新（新根位置）作为提交边界。现有 `updateLibraryRoot` 依次写 `rootPath`、刷新写租约、`try?` 生成安全作用域书签、保存设置，**书签失败是静默的**，沙盒下新根会变成 `missingBookmark` 不可用（S）。因此切换必须：由用户授权新目录并**确认书签已生成**；检查与根相关的其它设置（`backupPath`、Registry 路径、Workbench 缓存的 `lastLibraryRootPath`、`_spinlab/analysis_packs` 随根变化）；回退 = 恢复**切换前整份 `LibrarySettings`**，并重置 Workbench 工作区缓存的 `lastLibraryRootPath`；并核实写租约能否对尚未配置的副本根（构建阶段）生效（**?**，11B 验证）。
8. **切换后验收**：新 App 打开 V2、列出全部样品、逐类抽检工作流；失败则恢复设置指向源库（源库未被改动）。
9. **源库保留**为只读归档，直至用户确认验收并过回退窗口。

### 6.3 中断与故障恢复

- 构建中断：**Router 并不可靠地 fail-closed**（无 `records/` 时判为未初始化，仅有 `index/` 时判为 V1，S）。安全来自三点：构建目录在标记写入且对账通过前从不被设为 Library 根；构建先创建 `records/`；切换以设置更新为唯一提交点。可删除重建，源库无变化。11B 故障注入须覆盖“仅 `storage/`/`_spinlab/`”“仅 `index/`”“有 `records/` 无标记”三种中断状态。
- 对账失败：不切换；报告差异。
- 切换后发现问题：D3。
- 不做：半迁移、双写、静默回退 V1 路径、旧 App 写 V2（SKELETON 已声明不支持）。
- 复用现有机制：`LibraryWriteLease`、`AtomicFileWriter`、`LibraryAssetService` 的 `asset_operations` 与幂等 `operationID`、`ContentFingerprintService`；不新建迁移引擎或第二套数据库。

### 6.4 放行条件（实际迁移）

全部满足才可向用户申请真实库迁移授权：R0 完成；D1 所选 R1 完成；D2 已决且对应适配完成或已确认不迁移清单；预检冲突清零或逐项已决；合成夹具全流程 + 故障注入通过；真实库副本预演（经授权）对账通过；D3、D4、D5 已答；用户明确授权。

---

## 7. 11B 验收计划（AC4）

1. 合成夹具：覆盖两种 V1 Batch 路径、含/不含 `sampleUID`、`legacySampleKey`、废纸篓样品、Growth 重复一致/冲突、未知 JSON 字段、重复/缺失原始文件、AFM 与（已纳入的）其它工作流、历史图/Pack、绝对路径 manifest、手机新建样品。
2. 预检：每类冲突各一个夹具，断言只报告、不修改源库（源库目录哈希前后不变）。
3. 构建与对账：UID/Batch/Result/哈希/SQLite 基数/索引一致；字节级保留 `sample.json` 未知字段（P5）。
4. 故障注入：构建中途、对账中途、写标记前后、切换设置前后中断；断言源库不变、无半成品被识别为可用 V2。
5. 切换后工作流回归：Library 浏览/搜索/编辑、Inbox（所选工作流）、Workbench、废纸篓/恢复/永久删除、备份（R0）、Publish/手机、单写者只读实例。
6. 回退：切换后无新写入的回退；有新写入的回退（D3 清单，不覆盖）。
7. 授权边界：真实库的读取/复制/预演/迁移每一步单独授权，报告留存映射表与哈希清单。

---

## 8. 未验证事项与风险

未验证（须 11B 夹具或用户信息）：Registry/XLSX 同步与 Recompute 在 V2 的实际行为；Publish 读 V2；手机提交在 V2 的端到端；V2 废纸篓恢复；10B（Growth 单权威）是否已全部合并及其实际行为；`LibrarySettingsStore` 根位置切换对书签/沙盒的影响；顶层 `samples/` 在 V2 下的实际行为；真实库的规模、工作流分布、AFM 原文件是否仍在、冲突情况（无真实清单）；本轮**没有**运行任何测试或 App。

风险：非 AFM 能力缺口可能使切换无限期推迟（缓解：D1 按实际使用裁剪）；副本期间源库被写（缓解：步骤 6 重新校验 + 租约）；`sample.json` 未知字段丢失（缓解：P5 JSON 层变换）；绝对路径引用失效（缓解：只报告并保留）。

---

## 9. 独立设计审查记录

- 方式：只读 fresh-context 子代理（无编辑权限），逐条对照源码核验；审查者只提意见，处置由本文作者决定。
- 第 1 轮（被审：初稿）：needs revision。已采纳并修订：Recompute 在 V2 是静默空操作（原误列为未知）；漏列直接操作顶层 `samples/` 的审计/清理/图库/删除消费者；“源库不改”与 P1 补发 UID 的矛盾；切换提交点忽略书签静默失败、关联设置与设置回退；AFM 重新入库被写成已决（改为推荐、待 D2）；中断构建 fail-closed 说法过强；Pack 路径、工作量估算不实。
- 第 2 轮（被审：第 1 轮修订版）：第 1 轮各项修订经源码核验属实；发现 §6.3 与 §6.2 步骤 4 及 Router 行为矛盾（实质）以及两处小问题，均已按文字对齐修订，未改变设计结论。审查者预期无需再轮。
- 本文作者说明：第 2 轮后的修订仅为文字对齐，未再做第 3 轮复审；若用户要求，可追加一轮。
- 结论：实质问题均已处置；D1–D5 保持待用户决定；运行验证为零（§8）。
