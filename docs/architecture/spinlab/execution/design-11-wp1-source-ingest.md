# Task 11 WP1–WP4 — 公共数据架构与 Workbench 接入（统一设计入口）

基线：`main@5f8831a43589c7211a29f33c042beecccc0636b2`，总体设计 [PR #247](https://github.com/Jiaze-Li/SpinLab/pull/247) 已合并。2026-11-28 用户授权基于 #247 开启设计 Draft，随后明确要求避免将工作包机械拆成约 20 个 PR；本 PR #248 扩展为 WP1–WP4 统一设计，按 [design-11 §4.3](design-11-v2-migration-readiness.md#43-pr-交付计划2026-11-28-用户确认) 的八 PR 目标组织交付。

**阶段：设计，不实施。** 以 [design-11 §4.2 WP1–WP4、§5.1–5.1c](design-11-v2-migration-readiness.md)、[brief-11](brief-11-v2-migration.md)、[SKELETON K5/K7/K12/K13](SKELETON.md) （同时适用 K8–K11）与 [AGENTS](../../../../AGENTS.md) 为合同；不重做 Task 11 总体设计。本页是 WP1–WP4 的统一设计（2026-11-28 基线 `52bd0aef`，待独立审查，见 §8）；不是已实现功能。

## 1. 统一设计目标与边界（WP1–WP4）

一次确定原始文件入库 → 忠实标准 Dataset → 公共查询/读取 → Workflow 科研处理 → 绘图组织/渲染 → 正式成果保存的公共合同。WP1–WP4 的技术依赖仍保留，统一设计、分两批实施：WP1–2 数据基础，WP3–4 公共消费与 AHE 首个真实闭环。先复用已有模块，再补足真实缺口；不为形式统一而增加框架。WP1 原有三个原则全部保留：

- 测量上下文随 Source 同一提交点持久化，记录用户确认的 workflow、通道与物理角色、条件及来源（rule/manual/fallback）、测量时间、原始文件名、源文件 mtime、旧路径（仅记录，不作身份）及必要规则/解释来源；可批量查询，唯一权威，不写进 Dataset 本体。未知不猜；有效通道属于 Source–Sample 直接关系，SQLite 为权威。
- 一份多通道文件涉及多个样品时，每个目标 Sample 各保存一份完整 Source 字节并登记各自有效通道；不共享跨样品所有权，不为节省少量磁盘空间跨样品去重。原始文件不改写，不将其他样品的信号暴露为本样品可分析通道。
- 合法原始文件在无适配器或标准化失败时可明确地 Source-only 入库（零 Dataset），仍受通用身份、归属、完整性、查询及删除/恢复机制管理。失败原因与可分析性明确，不伪造 Dataset。MR 只保留数据分类，不另建 MR Workbench、解析器或兼容逻辑；旧 Measurement Set 不迁移、不新增集合字段。

**WP2–WP4 本次纳入详细设计，不实施。** WP2 复用 PPMS DAT、Zurich LVM、RSM TXT loaders 与现有 AFM 矩阵能力；WP3 统一检索、读取和列/通道定位；WP4 用 AHE 验证公共 Workbench 来源入口、正式手工 Plot 保存和 Sample Result 显式赋值。各 Workflow 的物理处理独立，科研配置变更与纯显示重绘分开。后续 RT/XY/3ω/IV/RSM 适配不在本 PR 实施范围；仅用现有消费者的真实差异验证公共合同是否成立，不能预造未来接口。

WP0/WP8 合并安排为后续迁移安全设计与实施，技术上 WP0 独立；WP9 真实库预演/切换另行授权。保留 V1 正常使用、AFM 标准化/自动出图现有功能。只有实际共同合同变化才调整 SKELETON，不另设并行权威或任务看板。

## 2. 基线源码事实（静态读码，未运行）

| 事实 | 位置 | 对设计的含义 |
|---|---|---|
| `ingestAsset` 一次提交 = 事务 1（operation=pending + Source/Dataset `staging` 行）→ 写文件并回读校验 → 事务 2（`ready`、`dataset_source` 依赖、`sample_asset_links`、operation=committed）。pending 崩溃一律 `abortIngest` 回滚。已 committed 的同 operationID 重放返回原回执并校验目标 Sample。 | `LibraryAssetService.swift:257–426`；`+Deletion.swift:519–598` | Source-only 与上下文可直接放进同一两段式事务，恢复语义不变；不需要新的恢复器。 |
| 入口拒绝：`guard !payload.datasets.isEmpty`（`:293`）。`standardize` 的任何错误都直接抛出，没有“适配器拒绝”与“I/O/哈希失败”的区分。 | 同上 | 须引入类型化的“标准化拒绝”，其余错误继续中止入库。 |
| Source 持久字段：`assets`（含 `original_filename`、`sha256`、`byte_size`），文件侧 `manifest.json` 含 `originalSourcePath`、`ingestedAt`；**没有 mtime、workflow、条件、通道**。`sample_asset_links(asset_id PK, sample_uid, ownership_status)` 保证每个 Source 唯一归属；Dataset→Source 为 `dataset_source` 依赖，`signal_locator` 存通道 ID JSON。 | `LibraryAssetDatabase.swift:215–280`；`AssetStandardizationAdapter` 在 `LibraryAssetModels.swift` | 上下文需要新落点；`signal_locator` 是 Dataset 侧所读通道，不是 Source–Sample 的“有效通道”权威。 |
| `schema_version` 必须严格等于 `"2"`，否则 `databaseUnknownVersion`；`open(createIfMissing:)` 先建后验。 | `LibraryAssetDatabase.swift:131,239` | 增加上下文必须有显式升级策略。 |
| Inbox V2：`standardizationAdapter(forWorkflowID:)` 只认 `afm`（`InboxArchiveApplyService.swift:57–68`）；`applyV2` 无适配器即 `v2UnsupportedOperation`；只读 `draft.v2TargetSampleUID`（单个）、`v2OperationID`、`v2ReuseSourceID`。`ApplyCoordinator.isEligible`、`SpinLabAppState+V2Assets/ApplyPipeline` 三处各自以“有适配器且有单目标”判定可应用，另有 `InboxSelectionWorkbenchPanel.swift:128,343–382` 的 draft 界面逻辑。 | `InboxArchiveApplyService.swift:481–580`；`ApplyCoordinator.swift:158`；`InteractionStateModels.swift:34–111`（旧 `v2TargetSampleUIDs` 仅在恰好一个时迁入） | 多目标与 Source-only 都要改这些位置；可应用判定应集中为一个函数，避免三份漂移。 |
| 读取：`loadDataset(datasetID:codec:)` 校验文件哈希、解码，并返回 `SourceAvailability`。 | `LibraryAssetService.swift:~470` | 表格 Dataset 只需新增 codec，不改读取框架。 |
| 列表：`listAnalysisDatasets(format:)` 经 SQL 联结 Dataset→Source→active 链接，**每个 Dataset 一行**；只被 AFM 使用。`standardDatasetHits` 固定 `workflowID:"afm"`、`conditions:[:]`、`appliedAt:.distantPast`，数字检索一律不命中。`WorkbenchInputRef` 仅有 `.datasetV2(datasetID, sourceID, sampleUID, originalFileName, channelIDs)`。 | `+Analysis.swift:75–113`；`SearchWorkflowMeasurementsUseCase.swift:107–145`；`WorkflowSearchModels.swift:66` | WP3 的真实缺口；`WorkbenchInputRef` 已持久，不宜放入上下文副本。 |
| 加载器：`PPMSDATLoader`（短行补空/长行截断，**均有诊断**）、`ZurichLVMLoader`（`guard parts.count >= columnCount else { continue }` 静默丢行，`diagnostics: []`，`:100–117,145`）、`RSMTextLoader`（异常行直接抛错，不丢行）。统一输出 `LoadedMeasurement{signals:[MeasurementColumn], rowCount, diagnostics}`，列有 `stableSourceKey`、`sourceColumnIndex`、`rawLabel`、`sourceUnit`、`physicalQuantityID`、`instrumentChannelLabel`；注释明确“从不原样持久化”。非数字字段在加载器里已转 NaN。 | `UseCases/*Loader.swift`；`Domain/Measurement/*` | `LoadedMeasurement` 恰是 Dataset 的内存形态；LVM 是需要补诊断的加载器：除丢行外，字段数多于列数时也静默截断、非数字字段静默转 NaN（均无诊断，`ZurichLVMLoader.swift:100–117`）。 |
| AHE：`IngestAHESelectionsUseCase.execute(selections:numericDisplayBySample:parseFile:)` 已有注入缝 `parseFile:(URL)->LoadedMeasurement`；但系列身份与 `sourceRef` 都用 `selection.sourceFilePath`，通道经 `PPMSBridgeChannelMapping` 取桥号再由 `AHEAxisDetector.yColumnName` 在列名中定位。AHE 的 Workbench 保存走旧图表路径；`FormalPlotSaveBar` 目前只被 AFM 使用。 | `IngestAHESelectionsUseCase.swift:1–128`；`AHEWorkspaceStore.swift:738`；`FormalPlotSaveBar.swift` | 来源缝要解决的是“身份不再是路径”，不是“能不能注入加载器”。 |
| 正式 Plot：`supportedPlotFormats = ["afm_plot_v1"]`；`validatePlotRequest` 校验格式并要求每个输入有 `channelID`；`PlotInputRef(datasetID, channelID, revision)`；`FormalPlotLibrary.summaries` 固定 `AFMDatasetCodec`/`AFMPlotCodec`、`workflowLabel:"AFM"`。Plot 发布/更新已有 operationID、请求哈希、写租约、`live_input` 依赖与 stale 标记。 | `+Plot.swift:11–60,469–480`；`FormalPlotCandidates.swift:119–146` | 发布/回执/删除保护全部复用；只有格式登记和摘要路由要泛化。 |
| Sample Result：`resolveV1AssignmentTarget` 对 V2 直接返回“尚未迁移”并拒绝；V1 目标由 `(batchID, sampleKey)` 解析。 | `LibraryResultService.swift:~327` | WP4 增加按 Sample UID 的目标解析，写入仍走同一显式确认路径。 |

## 3. 统一设计

### 3.1 数据与权威（最小集合）

| 信息 | 唯一权威 | 说明 |
|---|---|---|
| Source 字节、哈希、原始文件名 | 现有 `assets` + `storage/<src>/payload.bin` | 不变。 |
| Source→Sample 归属 | `sample_asset_links`（不变） | K5。 |
| **有效通道（Source–Sample 关系的属性）** | `sample_asset_links.effective_channels_json`（新增可空列） | 元素为 `{id, role?}`；`NULL` = 未确认，不是“全部”（K12）。 |
| **其余测量上下文** | 新表 `source_context(source_id PK→assets, workflow_id?, workflow_origin, conditions_json, measured_at?, measured_at_origin, source_mtime?, legacy_path?, interpretation_json, standardization_state, standardization_code?, standardization_detail?, recorded_at)` | `origin ∈ rule/manual/fallback/unknown`；`standardization_state ∈ standardized/source_only`；原始文件名不重复存（用 `assets.original_filename`）。 |
| Dataset 列、单位、诊断 | Dataset 自身文件（`columns.json` + `values.bin`） | 上下文不写进 Dataset（K7 与 WP1 原则）。 |

- `source_context` 在 Source 的事务 2 中与 `ready`、归属、通道**同一事务**写入。登记后整行不可变，唯一例外：补生成 Dataset 的提交把 `standardization_state` 由 `source_only` 改为 `standardized`（同一事务内同时写 `dataset_source`）。
- `manifest.json` 仍写入（含 `originalSourcePath`）；它是写入后不再改动的文件侧自述，**查询只读 SQLite**。两处值在同一入库操作内由同一输入生成，不可能分叉。
- 没有 `source_context` 行的旧 V2 Source（仅测试/开发库可能存在，Audit A：真实库无 V2 数据）按“上下文未知”处理：AFM 凭 Dataset 格式识别（现行行为）；其他一律未知，不推测。
- **删除闭包**：库开启 `PRAGMA foreign_keys = ON`，而 `finishDeletion` 在删依赖与链接后才 `DELETE FROM assets`（`+Deletion.swift:458–467`）。因此 `source_context` 必须在**同一删除事务内、先于 `assets` 行**被删除（实施时在 `finishDeletion` 中与 `sample_asset_links` 同处删除，并以删除故障注入验证）；`computePlan` 不需改动，上下文随所属 Source 的删除闭包处理，Sample 永久删除后保留的 Source 其上下文随之保留。
- Source-only 不是新资产类型或新状态值：**= 无 `dataset_source` 依赖的 Source**，其原因在 `standardization_code/detail`。现有删除/恢复计划（`computePlan` 以 Source 为起点收集消费者）对零 Dataset 自然成立；最后一个 Dataset 的单独删除仍被拒绝（`lastDatasetDeletionRejected`）。

**Schema 升级（代理技术决定，可推翻）**：`schema_version` 2→3，仅增加上述一列与一表。可写实例打开版本 2 时，在写租约下于一个事务内执行加法升级并更新 `schema_meta`；只读实例遇到版本 2 沿用 K13，拒绝并提示“需由可写实例升级”，不读半成品。版本高于 3 仍拒绝。实现上 `LibraryAssetDatabase.open` 目前没有读/写模式而被众多读路径调用，须增加一个显式的“可写打开并升级”单一入口，其余入口只校验；升级单向（旧版本 App 打开版本 3 库会得到 `databaseUnknownVersion`），因此首次升级前必须已有 WP0 备份——对仅有测试/开发 V2 库的现状，批次 A 实施时以明确提示替代自动升级前备份的缺失。`IngestOpPayload` 新增的 `requestHash` 等字段必须可选，旧 committed 载荷仍可解码。WP8 的迁移工具直接以版本 3 为目标；WP0 备份须覆盖版本 3。

### 3.2 WP1 — 入库请求、多目标、Source-only

**入库入口**。不新增服务：把 `ingestAsset` 的核心提炼为同一事务体，新增 `ingestSource(request)`，`request = {sourceFileURL, targetSampleUID, operationID, context, effectiveChannels, adapter?, reuseSourceID?, autoPlotIntent?}`；`ingestAsset` 作为包装保持 AFM 现行签名与行为。

1. **读字节**一次，计算 SHA；`source_mtime` 与 `measured_at` 在读取文件时采集（mtime 来自该次文件属性读取；`measured_at` 沿用 Inbox 已有 `MeasurementTimestampResolver` 的结果及其 origin）。采集失败 → 对应字段置空并记 origin=`unknown`，不阻止入库；字节不可读/空文件 → 入库失败（不是 Source-only）。
2. **标准化**：`adapter == nil` → Source-only，代码 `no_adapter`。有适配器 → 调用；抛出类型化 `StandardizationRejected(code, detail)`（如 `rows_dropped`、`unsupported_layout`）→ Source-only；**其他任何错误（I/O、哈希、归属、持久化、租约丢失）原样失败，不降级**。
3. AFM 适配器的现有失败行为保持不变（AC5）；是否让 AFM 解析失败也转 Source-only 属产品选择，见 §6 待决 P2。
4. **请求绑定**：operation 的 pending 载荷增加 `requestHash`（Sample UID、SHA、context、有效通道、适配器标识）。同 operationID 重放：已 committed 且请求哈希一致 → 返回原回执；哈希不同 → `operationRequestMismatch`（沿用 Plot 的同名语义，`+Plot.swift` 已有实现可复用）；目标 Sample 不一致仍拒绝。
4a. **字节只读一次**：入库读取的字节同时用于哈希、`standardize` 与写入；适配器接口改为接受已读入的字节（或由请求入口传入），避免哈希、mtime 与 Dataset 来自两次读取。
5. **同 Sample 重复文件**：不自动去重。Inbox 在入库前按 `idx_assets_sha256` 查同 Sample 同哈希的 ready Source，提示“已有相同文件”，用户可选复用（走既有 `reuseSourceID`）或仍新建。复用时上下文与有效通道**必须与已记录一致**，不一致 → `contextConflict`，不覆盖（`effective_channels_json` 与 `source_context` 登记后同样不可变）；已有 Source-only 且本次标准化成功 → 这就是“补生成 Dataset”：同一事务写 `dataset_source`、把状态改为 `standardized`、保留 Source ID。无消费者的通用转换引擎不建；入口只在首个真实需求出现时接入 UI（见 §5）。

**多目标**。Inbox draft 的 `v2TargetSampleUID/v2OperationID/v2ReuseSourceID` 泛化为 `v2Targets:[{sampleUID, operationID, effectiveChannels, reuseSourceID?}]`，每个目标在加入 draft 时生成并持久稳定的 operationID（旧单目标 draft 解码为一个目标）。应用时逐目标顺序调用 `ingestSource`，**不做跨目标大事务**：每个目标自己就是 K5 下独立的 Source，原子性单位为“一个 Source”。结果按目标返回 `applied(sourceID)` / `failed(code,message)`；Inbox 条目只有在**全部目标 applied** 时才视为完成并出队，部分成功保持在队列，界面列出各目标状态，重试只对未完成目标重放（已提交的重放回执，不重复登记）。审计事件按目标各写一条。每个目标的有效通道在确认面板中选择，**未选择则为 `NULL`（未确认）**，并对需要通道的 workflow 阻止应用，不默认全选。可应用判定集中为单一函数，替换 `ApplyCoordinator`、`SpinLabAppState+V2Assets`、`SpinLabAppState+ApplyPipeline` 三处各自的“有适配器+单目标”条件。

**适配器选择**。`standardizationAdapter(forWorkflowID:)` 扩展为按**确认的 workflow + 容器格式**登记（PPMS DAT、Zurich LVM、RSM TXT）；没有登记项（含 MR）→ nil → Source-only。文件后缀不决定科学语义（K12）。

**已提交目标的锁定与编辑**：目标一旦 `applied`，其 operationID、通道与上下文在 draft 中只读；Inbox 面板现有“目标变化即重置 operationID”的逻辑（`InboxSelectionWorkbenchPanel.swift:376–382`）对已提交目标不得触发，不得移除已提交目标（只能在 Library 中对其 Source 做常规删除）；对未提交目标的编辑照常重新生成请求。旧 draft 中多于一个元素的 `v2TargetSampleUIDs`（`InteractionStateModels.swift:103–108` 现被丢弃）不迁入，作为未选目标处理并提示重新选择，不猜测。需要同步改动的位置还含 `InboxSelectionWorkbenchPanel.swift:128,343–382` 的 draft 界面逻辑。

**“未确认”的出路（待决 P4）**：登记后上下文不可变意味着以未知 workflow/通道保存的 Source 只能删除后重新入库；是否允许一次“未知→确认”的受审计补录，是产品选择，见 §6。

**界面（最小）**。沿用 Inbox 确认面板与 `AdaptiveSheet`/`AppSpacing`（`specs/04_UI_RULES.md`）：目标 Sample 多选 + 每目标通道选择；应用结果以现有失败/成功反馈呈现每目标状态；Library 的 Sample 资产列表中 Source-only 条目显示“原始文件已保存，尚无标准数据（原因）”，提供现有的查看/定位入口，不显示“分析”操作。不新建页面，不复制 Library 管理逻辑。

### 3.3 WP2 — 表格 Dataset

- **形态**：新 codec `measurement_table_v1`（单一 Dataset 格式，容器类型作为内容字段），文件 `columns.json` 与 `values.bin`。`columns.json`：`loaderFormat`（`ppmsDAT/zurichLVM/rsmText`）、`rowCount`、列数组（`stableSourceKey`、`sourceColumnIndex`、`rawLabel`、`unit`、`physicalQuantityID?`、`instrumentChannelLabel?`）、`diagnostics`（code/message/columnKey/rowIndex）、`codecVersion`。`values.bin`：列主序 IEEE754 Float64 小端，NaN 位型保持。哈希由 `AssetFileEntry` 逐文件记录（现有机制）。
- **解码**得到 `LoadedMeasurement`（`sourceFilePath` 不持久，解码时置为 Dataset 标识）。`PhysicalQuantityUnitTag` 是枚举，需显式稳定字符串映射并对未知值失败（不静默当“无单位”）；映射表由 `V3fPPMSDATLoaderMigrationTests` 现有分类覆盖验证。
- **适配器**只包装现有加载器，不重写解析。PPMS：补空/截断已有诊断 → 作为诊断随 Dataset 保存并在界面可见；RSM：加载器本就在异常行抛错 → 转 `StandardizationRejected(parse_error)`。**LVM**：为加载器增加诊断（`malformedRow.dropped` 丢行、`malformedRow.truncated` 截断、`field.nonNumeric` 非数字转 NaN，均含行号/列键），不改变其返回的数值；标准化时 **任何被丢弃的数据行都拒绝生成 Dataset 并转 Source-only**（`rows_dropped` + 数量）；截断与非数字转 NaN 仅记入诊断、不拒绝（与 PPMS 补空/截断同级，仍属 P1 的容忍度判断）。空行与标记行前内容不算数据行。该零容忍默认来自 #247 的“默认拒绝”，它改变哪些文件可分析，属 §6 P1，不是纯技术决定。
- **LVM 位置列与通道号**：Dataset 只保存 `col<N>`、原始表头与 `instrumentChannelLabel`；col0 的科学含义与通道号≠谐波均留在 workflow 解释层，由 `source_context.workflow_id` 决定（K12）。`I_rms`、Rxy、拟合、平滑不入标准化层。
- **有效通道与列定位的衔接**：Dataset 保存**完整**列（含其他样品的信号）；“哪些通道属于这个 Sample”只由 `effective_channels_json` 决定，Dataset 不重复保存。**强制点在读取与保存两处，而不是靠 workflow 自觉**：①来源缝 `resolveMeasurementInput` 返回的 `LoadedMeasurement` 已按有效通道过滤——对 PPMS 桥类 workflow，未列入有效通道的桥对应列（经 `PPMSBridgeChannelMapping` 的通道→列映射）不出现在 `signals` 中，公共列（场、温度、时间）保留；`NULL` 的输入对需通道的 workflow 返回“通道未确认”，不进入分析；②Plot 发布/更新校验每个输入的 `channelID` ∈ 该 Dataset 所属 Source 的有效通道，否则拒绝。**该约束只适用于登记了“通道→列映射”的 workflow（现仅 AHE）**：AFM 及未登记映射的 workflow 不适用——AFM 的通道来自矩阵自身的 `signal_locator`，其 `effective_channels_json` 恒为 `NULL` 且不参与读取过滤与 Plot 校验，行为与现状一致；对登记了映射的 workflow，`NULL` 则拒绝（通道未确认）。旧的单目标 draft 迁移为 `v2Targets` 时不带 `effectiveChannels`（即未确认）。通道→列的映射由各 workflow 声明（AHE 用现有桥映射），批次 A/B 只实现 AHE 所需的一份。
- AFM 不变：保持 `afm_dataset` 与自己的矩阵 payload。

### 3.4 WP3 — 公共查询与读取

- **目录查询**：新增 `listMeasurementCatalog(rootURL:)`，一次 SQL 联结 `assets/sample_asset_links/source_context/dataset_source`，返回两类行：①Dataset 行（`datasetID, datasetFormat, sourceID, sampleUID, workflowID?, conditions, effectiveChannels?, measuredAt?, originalFileName, sample/batch/substrate 显示信息`）；②Source-only 行（供 Library 使用，**不进入 Workbench 命中**）。`listAnalysisDatasets(format:)` 由它实现或保留给 AFM 到 WP3 实施时再合并（以 AFM 回归全绿为准）。
- **命中**：`standardDatasetHits` 改为遍历目录中**当前 Workbench 已适配的 workflow**（登记表决定；WP4 起含 AHE）；`workflowID/conditions/channels/appliedAt` 来自上下文。数字检索对 V2 命中启用：条件值在入库时已规范化存入 `conditions_json`，复用现有条件解析工具比较；`NULL`/缺失条件不匹配数字查询。身份仍是 Dataset ID；路径不作身份。
- **持久引用不放上下文**：`WorkbenchInputRef.datasetV2` 保持仅含身份（避免已持久快照解码破坏与第二份上下文副本）；需要上下文时按 `datasetID` 从目录取。
- **读取（来源缝，WP4 首个实现）**：单一函数 `resolveMeasurementInput(hit) -> ResolvedMeasurement{loaded: LoadedMeasurement, effectiveChannels, conditions, identity}`。V1 命中走路径加载器；V2 命中走 `loadDataset` + 表格 codec；Source 不可用/损坏经现有 `SourceAvailability` 报告。**不为未适配的 Workbench 提供输入**：目录命中表按 workflow 登记，未登记 workflow 的 Dataset 不出现在其搜索里。
- **列/通道定位与条件解析**：仅收敛有真实重复且已有回归的部分。实施时先做**行为差异表**（AHE/RT/XY 列选择、四份条件字符串解析、两份 `I_rms`、无调用方的 `SidecarConditionNormalizer`），差异不明的不合并，并保证 V1 现有 V3f/V3g/V3c/PR148 测试全绿、同夹具输出逐值一致。AHE 的桥通道→Y 列定位保持其 workflow 内逻辑（`PPMSBridgeChannelMapping` + `AHEAxisDetector`），只把“从哪里得到 `LoadedMeasurement`”换成来源缝。

### 3.5 WP4 — AHE 首个闭环

**来源缝接入 AHE**：`AHEPlotSelectionItem` 增加可选 `inputRef`；V2 选择用 `datasetID` 作系列身份（`seriesIdentityKey` 的 `stableSemanticID`）、用原始文件名作显示名；`IngestAHESelectionsUseCase` 取数处改为“按选择解析 `LoadedMeasurement`”（V1 保持 `parseFile` 路径行为，V2 走来源缝）。其余科研算法（桥通道映射、Oe→T、Hall 背景校正、AHE 指标提取）**零改动**。通道选项只列 `effectiveChannels` 与 PPMS 桥映射的交集。

**生命周期与归属**：读取（来源缝）→ AHE 科研语义/处理（`IngestAHESelectionsUseCase`、`AHEBackgroundCorrectionUseCase`、`ExtractAHEMetricsUseCase`，现有）→ Plot payload/坐标映射（`BuildAHEPlotPayloadUseCase`，现有）→ 渲染（现有 Cartesian XY）→ 交互调整 → 保存。改变通道/条件/背景校正等**科研配置** → 重新读取并重算；仅改标题/配色/范围/图例/系列顺序等**显示配置** → 只用已有 payload 重绘（现有 `AHEWorkspaceStore` 已区分，保持）。

**正式 Plot 保存**（公共，AHE 是首个非 AFM 消费者）：
- 新格式 `xy_curves_plot_v1`：文件 `curves.bin`（各曲线 x/y Float64）、`manifest.json`（标题、保存时间、workflow、通道摘要、系列标签/顺序、显示配置、**科研处理参数**与来源 Dataset 修订）、`plot.png`（缩略/导出，**数值不依赖 PNG**）。重开时由 `curves.bin` + 当前渲染器重绘；若输入 Dataset 修订已变，沿用现有 `live_input` stale 机制，用户重开后选择重算。
- `supportedPlotFormats` 由写死集合改为小型登记表 `{format → PlotFormatDescriptor(manifestName, summaryDecoder, workflowLabel)}`；`validatePlotRequest` 查表；`FormalPlotLibrary.summaries` 按资产 `format` 路由到描述符，Dataset 显示信息改用目录查询而非 AFM 专用列表。AFM 登记项保持原行为。
- `PlotInputRef.channelID` = 有效通道 ID（如 `ch1`）。**现有 `validatePlotRequest` 要求输入的 `datasetID` 互不相同（`+Plot.swift:471`）**，而一个 PPMS 文件的多个桥属于同一 Dataset；AHE 多桥图因此需要把唯一性改为 `(datasetID, channelID)`。这是对既有 Plot 合同的显式修改（`asset_dependencies` 主键含 consumer/upstream/kind，同一 Dataset 的多通道需另行承载 channel——实施首步核对 `signal_locator` 与主键能否表达，必要时把同一 Dataset 的多个通道合并为一条依赖、`signal_locator` 存通道列表），并须覆盖 `validateUpdateInputs` 的 same-set 逻辑、`PlotInputKey` 与 stale/删除保护的回归测试；AFM 单通道行为不变。
- 保存/替换/列出/重开/导出、写租约、请求哈希、故障注入、删除保护全部使用 `publishPlotCore` / `updatePlot` 现有路径，不新建保存体系。保存入口复用 `FormalPlotSaveBar` 与 `FormalPlotSelectorSheet`（AHE 页 `usesFormalPlotSave = true`，其旧保存不再显示，与 AFM 一致）；V1 库保持旧图表保存不变。非 AFM 自动出图不在范围。

**Sample Result 赋值**：保留 Task 12 的“用户明确确认”与候选/过期值保护；新增按 **Sample UID** 解析目标（`resolveV2AssignmentTarget`，要求 Sample 有效、未在回收站、与输入归属一致），替换 V2 下“尚未迁移”的拒绝；写入仍落 Sample 记录（唯一数值权威），**不**自动同步、不存第二份数值。

### 3.6 模块职责（防止重复实现）

- `LibraryAssetService`（入库事务、恢复、删除、Plot 提交）：只扩展，不新增并行服务。
- 新增小模块：`MeasurementContext`（值类型 + 校验）、`MeasurementTableCodec`（WP2）、`MeasurementCatalog`（WP3 查询）、`MeasurementInputResolver`（来源缝）、`PlotFormatRegistry`（WP4）。各自只有上述实际消费者。
- Workbench 层：AHE 之外的 workflow 此时**不改**；它们在 V2 下的“拒绝/不可用”行为保持（切换时只能 Source-only，见 design-11 §4.2 脚注）。

## 4. 设计交付与实施验收合同（含夹具入口）

以下是后续实施必须证明的验收；具体夹具与入口见 §4.1。本 Draft 不宣称功能已实现。

| 验收 | 后续实施必须证明 |
|---|---|
| AC1 上下文 | 确认的 workflow、有效通道/角色、条件及来源、时间、mtime、原名、旧路径按值往返；未知不猜；批量查询可用，单一权威，无重复存储；旧 AFM 记录处理明确。 |
| AC2 多目标 | 同一多通道文件归两个样品，两个 Source ID、完整字节相同，各自有效通道与归属正确；无跨样品共享/误读；部分失败与重试不会重复、错写或遗失待处理目标。 |
| AC3 Source-only | MR/其他无适配器、适配器明确失败的可读原始文件可保存且有原因、零 Dataset；重启后归属/内容/状态可读；不可分析、不自动出图；真正持久化失败不报告成功。 |
| AC4 生命周期与恢复 | 沿用资产事务、写保护、删除/恢复与依赖规则；上下文随 Source 处理。故障注入覆盖提交中断、重放、重复请求与请求冲突，不能留下半状态或孤立关系；跨库/只读拒写；为后续生成 Dataset 保持同一 Source 身份。 |
| AC5 回归与交互 | V1 日常路径和 AFM 入库/自动图不回归；隔离 V2 库 GUI 验证多目标确认、Source-only 显示/查看、失败反馈、重启读回及删除/恢复；不新增旧分组机制，不为 MR 建专项分析。 |
| AC6 标准 Dataset（WP2） | PPMS DAT、LVM、RSM TXT 代表性合成夹具按原始列值/顺序/单位/NaN/诊断往返；解析异常不静默丢行；DAT 列重排仍可正确映射；确认 MR 不因容器是 DAT 而生成可分析 Dataset；Source-only 补生成路径的身份/重试合同可验证。 |
| AC7 查询与数据消费（WP3） | V2 命中带正确 workflow/条件/有效通道/时间；按 UID/Dataset ID 读取；Source-only 与未适配 Workbench 不冒充可分析输入；列/条件公共工具收敛后 V1 回归及现有 AHE/RT/XY 结果逐值不变。 |
| AC8 AHE 闭环（WP4） | 隔离 V2 库：新文件多目标正确入库→重启查询→使用标准 Dataset 分析→正式 Plot 保存/替换/列出/重开/导出→用户明确确认后按 UID 写 Sample Result→删除/恢复与依赖保护；同一夹具 V1 科研计算结果与日常行为不回归。 |
| AC9 设计收口 | 一次按 Deliver 完成 WP1–WP4 统一设计的独立审查；明确实际源码事实、未验证项、两批实施范围和验收归属，后续代码 PR 另行授权，按 AGENTS 验收。Task 11 仍未完成，设计不改版本。 |

所有开发/运行证据只使用隔离合成夹具；真实 Library 不读取、不修改、不迁移。设计 PR 不修改 Swift、schema 或 AppVersion，不自动合并。WP0 技术上不依赖本包，计划与 WP8 作为后续迁移安全交付；不阻塞公共架构设计。
### 4.1 夹具与测试入口（后续实施使用；均为合成数据，隔离临时库）

| 验收 | 夹具 / 入口 | 预期 |
|---|---|---|
| AC1 | 合成 PPMS DAT（3 桥）+ 合成上下文（workflow=AHE、条件 T=10K 来源 manual、mtime=固定值、旧路径=任意字符串）；`LibraryAssetService` 层单元测试，沿用 `Tests/.../Assets` 的临时 V2 库助手 | 重开库后逐值读回；批量目录查询一次返回；`source_context` 之外无第二份；旧 V2 Source（无上下文行）读为“未知”且不报错 |
| AC2 | 同一 3 桥 DAT 入库 Sample A（ch1）与 Sample B（ch2,ch3）；故障钩子 `ingestBeforeCommit` 注入于第二目标 | 两个不同 Source ID、`payload.bin` 哈希相同；A 看不到 ch2/ch3；第二目标失败后 Inbox 条目仍在、A 不重复；重试只补 B；已提交目标重放得原回执 |
| AC3 | 无适配器（MR 的 DAT）、RSM 异常行、LVM 丢行三份夹具；以及“不可读/空文件”“租约丢失”两份失败夹具（租约丢失用 `LibraryAssetService.writeLease` 注入点模拟） | 前三者 Source-only，零 Dataset，原因码正确，重启后可读，Workbench 命中为空且无自动出图；后两者入库失败且库无残留 |
| AC4 | 在 `ingestAfterSourceWritten`、`ingestBeforeCommit` 与事务 2 之后重放注入崩溃；同 operationID 不同内容；只读实例写入；跨库回执 | 无半状态/孤立 `source_context` 或链接行；请求冲突报 `operationRequestMismatch`；只读拒写；Source-only 的删除/恢复/Sample 永久删除计划与普通 Source 一致；补生成 Dataset 保持 Source ID 不变且重放幂等；版本 2→3 升级中断后可重试 |
| AC5 | 现有 AFM 入库、自动出图、`V213InboxClosedLoopTests`、`V5112InboxArchiveRollbackFailSoftTests`；`spinlab-gui-validation` 对隔离 V2 库 | 全部不回归；GUI：多目标确认、Source-only 显示与定位、失败反馈、重启读回、删除/恢复（GUI 证据须来自交付 HEAD） |
| AC6 | 现有 `V3fPPMSDATLoaderMigrationTests`、`V3cZurichLVMLoaderTests`、`PR148*`、`V3iRSMTextLoaderMigrationTests` 的夹具生成逐格式 round-trip；DAT 列重排夹具；MR 的 DAT 夹具 | 解码值与加载器输出逐值（含 NaN 位型、列序号、表头、单位、诊断）一致；列重排只改映射；MR 不生成 Dataset；LVM 丢行夹具 → `rows_dropped` |
| AC7 | V1 路径旧测试（`V537AHESearchSnapshotConsumptionTests` 等）+ V2 混合库夹具 | V1 全绿；V2 命中带 workflow/条件/通道/时间；Source-only 与未登记 workflow 不出现；列/条件工具收敛前后同夹具 AHE/RT/XY 结果逐值相同 |
| AC8 | 合成 V2 库：多目标 AHE DAT → 重启 → `IngestAHESelectionsUseCase`（V2 来源缝）→ 保存 `xy_curves_plot_v1` → 替换/列出/重开/导出 → 确认写 Sample Result → 删除/恢复/依赖保护；同一夹具 V1 对照 | V2 与 V1 的曲线与 AHE 指标逐值相同；重开后曲线来自 `curves.bin`；未确认不写 Result；被 Plot 引用的 Dataset 删除被保护；其他 workflow 在 V2 下行为不变 |
| AC4+ | 删除闭包与编辑锁定 | 永久删除含 `source_context` 的 Source（含 Source-only）在 `foreign_keys=ON` 下成功且不留行；注入删除中断后恢复；已提交目标的通道/上下文改动被拒绝或被界面锁定；复用时通道不一致 → `contextConflict` |
| AC2+ | 通道隔离负向夹具 | Sample A 的读取结果不含 ch2/ch3 列；以 ch2 为 A 发布 AHE Plot 被拒绝；AFM Plot 在 `effective_channels_json=NULL` 时仍可发布（AC5 回归） |
| AC9 | 本页 §8 | 独立审查结论与处置已记录；Swift/schema/版本零改动 |

## 5. 两批实施顺序与归属

1. **批次 A（WP1–2，PR 2）**：schema 2→3 与 `source_context`；`ingestSource`（含类型化拒绝、请求哈希、补生成路径）；多目标 draft 与统一“可应用”判定；Source-only 与通道确认的最小 UI；`measurement_table_v1` codec 与三适配器；LVM 丢行诊断。验收 AC1–AC6，GUI 用隔离 V2 库。
2. **批次 B（WP3–4，PR 3）**：目录查询与命中泛化；来源缝；AHE 接入；`PlotFormatRegistry` 与 `xy_curves_plot_v1`；V2 Sample Result 目标解析；列/条件工具按差异表有证据地收敛。验收 AC7–AC8。
3. 批次间依赖：B 只依赖 A 的 `source_context` 与表格 Dataset；AHE 之前不改 RT/XY/3ω/IV/RSM（它们在 WP5–7 继承本合同直接适配；只有出现实质合同缺陷或新的科研选择才补设计）。
4. WP0/WP8（备份/迁移）按 design-11 §4.3 另行设计：WP0 备份范围须包含 `source_context` 与 schema 3；WP8 的 Source 登记必须经 `ingestSource` 并带 `legacy_path`、mtime 与原始文件名。

## 6. 决策分类

**用户已确认（继承 #247 与 #248 评论）**：一库升级；Source 字节/文件名/mtime 无损；每目标 Sample 各存完整 Source，不跨样品去重；Source-only 合法；MR 仅数据分类与 Source-only，不建 Workbench/解析器；Measurement Set 不迁移；统一生命周期不统一数据形态；复用优先；非 AFM 手工 Plot 保存必须有；Result 赋值需用户明确确认。

**代理技术决定（本设计采用，用户可推翻，均不改变产品语义）**：schema 2→3 加法升级与只读拒绝策略；有效通道落 `sample_asset_links`、其余上下文落 `source_context`；Source-only = 无 Dataset 的 Source（不新增资产类型）；类型化标准化拒绝与“其余错误不降级”；每目标独立事务、部分成功保持队列；同 Sample 重复文件由用户选择复用，上下文冲突拒绝；`measurement_table_v1` 的列主序 Float64 编码；`WorkbenchInputRef` 不携带上下文；`xy_curves_plot_v1` 与登记表；

**仍需用户决定（保持未批准；均不阻塞本设计与批次 A 的大部分实施）**：
- **P1 LVM/DAT 丢行或补空的容忍度**：推荐默认“LVM 任何被丢弃数据行 → 仅保存原始文件（Source-only）”，PPMS 补空/截断带诊断仍生成 Dataset。产品影响：若真实 LVM 常因仪器中断而有残缺末行，这些文件将暂时无法分析。该判断需要真实文件证据，而真实库未读取（需另行授权的只读抽样，或你提供样例）；在此之前按推荐默认实施。
- **P2 AFM 解析失败是否也保存为 Source-only**：推荐维持现状（拒绝入库并报错），因 #247 未授权改变 AFM 行为；如希望“任何可读文件都先保全”，则需你明确。
- **P4 Source-only/未确认上下文的补录**：推荐允许对“未知 workflow/未确认通道”做一次受审计的补录（已确认值不可改）；若不允许，则唯一出路是删除后重新入库。需要你选择。
- **P3 Source-only 文件的 Library 展示强度**：推荐只在 Sample 资产列表显示一行说明与“定位/查看”，不新增页面；若你希望在 Inbox 完成后弹出提示，需另行说明。

## 7. 未验证项（均为实施首步核对，不作为已证事实）

- 未运行 App、测试或构建；本设计与代码事实均来自静态读码。
- `ApplyCoordinator` 如何据 `InboxArchiveApplyResult` 将条目出队、V2 多目标是否需要新的结果类型，未逐行核对。
- Inbox 确认面板是否已有可复用的“按 workflow 声明通道列表”的数据源（`WorkflowDefinition` 是否声明桥/通道），未核对；若无，通道候选先来自该 workflow 现有的通道映射（如 `PPMSBridgeChannelMapping`）。
- `PhysicalQuantityUnitTag`/`PhysicalQuantityID` 的完整取值与可逆字符串映射；`MeasurementDiagnostic` 在 LVM 新增诊断后各 LVM 消费者（3ω/IV/XY/RT）是否把诊断当警告显示。
- 现有 Cartesian XY 渲染器在不依赖 Workbench 状态下由 `curves.bin` 重绘的最小入口；`AHEWorkspaceStore` 中保存按钮的现有位置与 `usesFormalPlotSave` 切换点。
- `MeasurementTimestampResolver` 的 origin 语义与 `source_mtime` 采集是否与 Inbox 现有读取重复。
- 多目标 GUI 的实际控件尺寸与响应式布局须按 `specs/04_UI_RULES.md`、`./scripts/check_ui_rules.sh` 在实施时验证。

## 8. 独立审查记录

独立只读审查（fresh-context 子代理，对照源码，三轮，已用满上限但已收敛）：
- **第 1 轮（NOT CONVERGED，4 major）**：M1 Plot 输入要求 `datasetID` 互异，与“同 Dataset 多通道”冲突；M2 有效通道未被强制；M3 `source_context` 删除闭包缺失（`foreign_keys=ON`）；M4 多目标重试/上下文生命周期缺口。另有若干 minor（升级入口、LVM 截断/NaN 诊断、P1 归类、旧 draft、`requestHash` 可选等）。**处置**：全部采纳，已写入 §3.1–§3.5、新增待决 P4 与夹具 AC2+/AC4+。
- **第 2 轮（NOT CONVERGED，1 major）**：M1–M4 已解决；新问题——通道校验未豁免 AFM（其 `effective_channels_json` 恒为 NULL）。**处置**：采纳，校验仅适用于登记了通道→列映射的 workflow（现仅 AHE）。
- **第 3 轮（CONVERGED）**：无新 blocker/major。遗留非阻塞提示：实施时 Plot 校验须经 `source_context.workflow_id` 判定 workflow，无上下文行的旧 Source 按未知归入豁免分支；实施首步明确写出。
- 审查对象为本页当前内容；审查者仅提供意见，决策与修改由交付代理完成。
