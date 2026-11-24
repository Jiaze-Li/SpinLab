# 任务 10 设计：Storage v2 路径合同、代码盘点与消费者边界

对应需求合同：[brief-10-storage-v2.md](brief-10-storage-v2.md)；共同语义参照：[SKELETON.md](SKELETON.md) K1–K13。本文只出设计交付，不含 Swift 代码实现或真实 Library 迁移。

---

## 一、路径与布局版本合同

### 1.1 两种受支持的库布局

| 版本 | 布局特征 | 版本标记 |
|---|---|---|
| **V1（现行）** | `batches/<prefix>/<batchID>/batch.json` 或 `batches/<batchID>/batch.json`（含两式混放）；Sample 位于 `<batchDir>/samples/<sampleKey>/sample.json`；索引在 `index/library_index.json` | **无版本标记**（现有真实 V1 库均无标记） |
| **V2（目标）** | `records/batches/<batchID>/batch.json`、`records/samples/<sampleUID>/sample.json`；`_spinlab/result_definitions.json`；预留 `storage/` 与 `_spinlab/library.sqlite`（任务 5 启用） | **必须有显式布局版本标记** `_spinlab/layout_version.json`（`{ "version": 2 }`） |

### 1.2 版本识别与 fail-closed 矩阵

统一由 `LibraryLayoutRouter`（在 `LibraryStore+PathsAndCache.swift` / `LibraryStore+RootAndIndex.swift` 入口调用）按以下规则判定，**不靠“某个目录存在就猜 V2”**：

| 磁盘状态 | 判定结果 | 读写行为 |
|---|---|---|
| 存在 `_spinlab/layout_version.json` 且 `version == 2`，无顶层 `batches/` 混入，目录结构合法 | **V2** | 走 V2 `records/` 路由；**禁止触发** `migrateLegacyBatchLayoutIfNeeded` |
| 无版本标记，存在 `batches/` 或 `index/`，且**无** `records/` | **V1（合法旧库）** | 按现有 V1 路径逻辑正常读写（支持两种 Batch 路径及前缀整理） |
| 无版本标记，但存在 `records/`（疑似未标记 V2） | **损坏/异常** | **fail-closed 拒绝写入**，明确提示缺少布局版本标记 |
| 存在版本标记，但 `version` 未知（如 `> 2` 或不可解析/损坏 JSON） | **未知版本** | **fail-closed 拒绝写入**，不降级、不当空库 |
| V1 与 V2 目录混存（同时存在 `batches/` 与 `records/`），或版本标记与实际目录矛盾 | **混合/冲突** | **fail-closed 拒绝写入** |
| 全新空目录 | **未初始化** | 由创建入口显式指定初始化版本（V1 或 V2），不静默猜测 |
| V2 扫描发现重复 `sampleUID`（多份 `sample.json` 声明同一 UID） | **身份冲突** | **fail-closed 拒绝写入**，不自动选边 |

### 1.3 未支持写入的拒绝边界

- 任何 V2 库上的操作，绝不允许在顶层 `batches/` 或旧 `samples/` 下创建文件或目录。
- 尚未迁移到 V2 的写入路径（如旧 Workbench/Sidecar 产物直写），在 V2 库上必须显式返回不支持错误（fail-closed），不得悄悄回退到 V1 路径。

---

## 二、代码盘点与权威收敛

### 2.1 `batch.json.sampleKeys` 读写点盘点

当前代码中维护或读取 `LibraryBatch.sampleKeys` 的核心位置：

| 文件 | 现有职责 | 任务 10 处理方式 |
|---|---|---|
| `Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift` | 定义 `LibraryBatch.sampleKeys: [String]` | 保留模型字段以兼容 V1 解码；V2 编码/写入时不再作为成员权威维护（可为空或省略） |
| `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift` | 创建/更新/删除 Sample 时同步修改 `batch.json.sampleKeys`；`reconcileBatchSampleKeys` | **V1 保留**；**V2 跳过** `sampleKeys` 同步与 `reconcileBatchSampleKeys` |
| `Sources/SpinLabApp/Library/LibraryStore+RootAndIndex.swift` | 扫描重建索引时重写 `normalizedBatch.sampleKeys` | **V1 保留**；**V2** 按 `records/samples/*/sample.json` 的 `batchId` 聚合 Batch 成员 |
| `Sources/SpinLabApp/Library/NativeSampleCreationService.swift` | 新建样品时向 `sampleKeys` 追加 `sampleId` | **V1 保留**；**V2** 仅写 `sample.batchId`，不写 `sampleKeys` |
| `Sources/SpinLabApp/Library/LibrarySyncService.swift` / `LibraryDiffEngine.swift` / `LibraryRegistryParser.swift` | Registry 解析与 Diff/Apply 时计算与更新 `sampleKeys` | **V1 保留**；**V2** 成员对比按 `sample.batchId` 计算，不以 `sampleKeys` 差异阻断或选边 |
| `Sources/SpinLabApp/App/LibraryMutationService.swift` / `LibraryPreviewComputationService.swift` | 批量合并与预览过滤使用 `batch.sampleKeys` | V2 下改为通过索引中 `sample.batchId == batch.id` 查询成员 |
| `Sources/SpinLabApp/Registry/RegistryGrowthMutationService.swift` | Growth Apply 校验 `batch.sampleKeys` | V1 兼容保留；V2 改按 `batchId` 成员查询 |

> **V1 历史冲突**：若 V1 旧库存在 `batch.sampleKeys` 与 `sample.batchId` 不一致，保留在任务 11 迁移预检中报告，不阻断 V1 正常使用。

### 2.2 Growth Parameter 唯一定义与兼容映射

1. **唯一物理字段定义**：以 `NewSampleFormSchema` / `NewSampleFields`（新建样品表单）的规范 Growth Parameter 集合为唯一物理定义（日期、实验室、生长材料、生长温度、氧压、样品高度、前端能量、激光电压、激光输出能量、衰减器、预打脉冲数、生长脉冲数、生长脉冲频率、RHEED）。
2. **兼容映射层（非第二套定义）**：
   - `Sources/SpinLabApp/Library/LibraryFieldOwnership.swift`（`LibraryFieldOwnershipRuleBook`）与 `Sources/SpinLabApp/config/library_import_rules.json`（`numericKeyAliases`）保留旧 Registry Excel 列名（如 `靶机距`、`预打`、`生长次数`、`氧压`、`能量`、`生长温度`）到规范 Growth Parameter 的**单向兼容映射**，保障旧 Excel 与 V1 旧库可读。
   - **清理项**：移除把 `"厚度"` 映射到 `"预打"`/`"生长次数"` 的错误别名、`LibraryViewComputationService.swift` 中的厚度过滤条件，以及裸 `"温度"` / `"temperature"` 默认归入 Batch 的规则（无依据保持 `.unknown`）。
3. **读写与搜索路径改造**：
   - `LibraryRegistryParser.swift`：不再将 Batch 生长参数同时复制写入 `LibrarySample.numericTags`。
   - `LibrarySampleEditService.swift` / `LibraryViewComputationService.swift`（样品过滤与详情展示）：V2 下从关联 Batch 读取生长参数；Sample 页只读显示，修改只在 Batch 上进行。
   - `Sources/SpinLabApp/App/SpinLabDataActor.swift` / `App/State/WorkbenchMainSearchRuntime.swift`：测量搜索与预览的 `numericDisplay` 查询改由 Sample 通过 `batchId` 读取 Batch 的生长参数。
   - `CreateNativeSampleSheetView.swift` / `NewSampleFields.swift`：移除新建表单中的“目的”“备注”，在 Sample 详情页提供随 `sample.json` 保存的自由文本备注入口（保留旧库已有目的/备注数据）。
4. **旧值冲突处理**：V1 旧库中若 `batch.numericTags` 与 `sample.numericTags` 存在冲突，报告并阻止向 V2 合并/迁移，不自动选边，但不阻止合法 V1 Library 的正常读取与使用。

---

## 三、旧路径消费者边界清单（Task 10 vs Task 5）

对所有直接拼接 `batches/`、`samples/<sampleKey>/` 或依赖物理路径解析批次/样品的模块划分职责：

| 模块 / 文件 | 现行路径依赖 | 任务 10 边界 | 任务 5 边界 |
|---|---|---|---|
| `LibraryStore+PathsAndCache.swift`、`LibraryStore+RootAndIndex.swift`、`LibraryStore+Drawers.swift`、`NativeSampleCreationService.swift` | 读写 `batches/<prefix>/<batchID>/` 与 `<batch>/samples/<key>/` | **本任务改造**：增加 V1/V2 路由，V2 读写 `records/batches/` 与 `records/samples/<sampleUID>/` | — |
| `LibraryStore+Drawers.swift`（废纸篓/永久删除）、`LibrarySampleEmptyCheck.swift` | 基于 V1 `batches/.../samples/<key>/` 目录检查空样品与删除 | **本任务改造**：V2 下基于 `records/samples/<sampleUID>/` 软删除状态与内容检查；不碰共享资产 | 共享资产引用检查与 unlink 删除 |
| `LibraryMutationSafetyGuard.swift`、`LegacySampleBackfillService.swift` | 检查 `samples/<sampleKey>/_spinlab` 孤儿产物、回填旧目录 | **本任务改造**：V2 下禁止向旧 `samples/` 或 `batches/` 回填/写入；仅在 V1 启用旧目录守卫 | — |
| `SpinLabAppState+ImportDeduplication.swift` | 直接拼接 `rootURL/batches/...` 查找重复导入 | **本任务改造**：改走统一索引/路由查询，不硬拼 `batches/` | 随资产去重接入 SQLite |
| `LibraryResultService.swift` | `_spinlab/result_definitions.json` + `sample.json.results` | **本任务保全**：路径与唯一权威不变，V2 下随 `records/samples/<sampleUID>/sample.json` 保存 | 不进 SQLite，保持不变 |
| `LibraryStore+Backup.swift` | 备份 V1 目录树 | **本任务适配或显式保护**：V2 下覆盖 `records/` 与 `_spinlab/`（或未就绪时明确拒绝），不漏备份、不误写 V1 | 纳入 `storage/` 与 `library.sqlite` |
| `WebLibraryPublishService.swift`、`PhoneSamplePickup.swift` | 发布快照读取与手机新建入库 | **本任务验证/适配**：手机新建走 `NativeSampleCreationService` 统一 V1/V2 路由；Publish 读取经统一索引 | 资产链接随任务 5 更新 |
| `LibraryArtifactLayout.swift`、`LibraryStore+Measurements.swift`、`LibraryStore+MeasurementSets.swift`、`LibraryMeasurementDataStore.swift`、`LibraryChartIndexStore.swift`、`LibraryStore+SidecarEnumeration.swift`、`LibrarySidecarService.swift` / `Reader` / `Writer`、`SearchWorkflowMeasurementsUseCase.swift`、`PersistMeasurementDataUseCase.swift`、`PersistChartArtifactUseCase.swift`、`SamplePlotsOverviewService.swift`、`WorkflowGalleryQueryService.swift`、`ChartAssetAuditService.swift` | 读写 `samples/<sampleKey>/_spinlab/*.json`、`samples/<sampleKey>/charts/`、从 Sidecar 路径解析 `batchID`/`sampleKey` | **本任务不搬迁旧资产**：V2 库上对仍直写 V1 `samples/` 或 `batches/` 的入口采取**明确拒绝（fail-closed）**，确保不在 V1 路径下产生文件 | **任务 5 仅接首个 AFM Source/Dataset 消费者与 SQLite 资产关联**；其余旧资产消费者后续逐个适配，未适配的 V2 操作继续明确拒绝，不能把全部旧 Workbench 迁移塞进任务 5 |

---

## 四、实施拆分（#227 已合并）

按“先路由与写保护、后数据权威收敛”拆为两个独立实施 PR：

1. **任务 10A（版本标记 + 统一路由 + V2 写保护）**：
   - 实现 `_spinlab/layout_version.json` 读写、V1 无标记识别与 fail-closed 校验矩阵。
   - 实现 `records/batches/` 与 `records/samples/<sampleUID>/` 读写、`sampleKeys` 在 V2 退场、废纸篓/导入去重/安全守卫适配、未迁移消费者在 V2 下的写保护。
   - 完成验收计划第 1、2、3、6、7、8 项。
2. **任务 10B（Growth Parameter 单权威 + 备注入口 + 查询切换）**：必须在 10A 合并后，基于更新后的 `main` 实施。
   - 收口 `LibraryFieldOwnershipRuleBook` 与 `library_import_rules.json` 为规范定义的兼容映射，清理“厚度”与裸“温度”规则。
   - V2 下生长参数只写 Batch、Sample 页只读显示、过滤与测量搜索改读 Batch；新建表单去掉目的/备注，Sample 页补齐自由文本备注入口。
   - 完成验收计划第 4、5、9 项及全量回归。

**10A 阶段交付边界**：只在独立测试 Library 建立 V2 的显式创建、读写与拒写能力；不将 V2 作为真实 Library 的默认初始化布局，不开放尚未就绪的生产 V2 写入，不迁移任何真实数据。10A 合并不表示任务 10 已完成，Growth Parameter 权威收敛仍由 10B 完成。V2 记录的 `sampleKeys` 在磁盘省略，在需要兼容现有内存调用时可从 Sample 的 `batchId` 派生；不得再独立写回。对未适配的 V2 写入口，包括初始化、导入和删除等副作用，须在产生文件或改动索引前明确拒绝。任务 10B 完成后仍按任务 11 的独立授权条件处理真实旧库迁移。
