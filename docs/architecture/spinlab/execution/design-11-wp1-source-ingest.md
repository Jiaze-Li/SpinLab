# Task 11 WP1–WP4 — 公共数据架构与 Workbench 接入（统一设计入口）

基线：`main@5f8831a43589c7211a29f33c042beecccc0636b2`，总体设计 [PR #247](https://github.com/Jiaze-Li/SpinLab/pull/247) 已合并。2026-11-28 用户授权基于 #247 开启设计 Draft，随后明确要求避免将工作包机械拆成约 20 个 PR；本 PR #248 扩展为 WP1–WP4 统一设计，按 [design-11 §4.3](design-11-v2-migration-readiness.md#43-pr-交付计划2026-11-28-用户确认) 的八 PR 目标组织交付。

**阶段：设计，不实施。** 以 [design-11 §4.2 WP1–WP4、§5.1–5.1c](design-11-v2-migration-readiness.md)、[brief-11](brief-11-v2-migration.md)、[SKELETON K5/K7/K12/K13](SKELETON.md) （同时适用 K8–K11）与 [AGENTS](../../../../AGENTS.md) 为合同；不重做 Task 11 总体设计。本页是 WP1–WP4 的统一设计（2026-11-28；已按用户 P1–P4 与「入库/标准化/分析互不调用」决定修订，见 §3.0、§6；独立审查状态见 §8）；不是已实现功能。

## 1. 统一设计目标与边界（WP1–WP4）

一次确定原始文件入库 → 忠实标准 Dataset → 公共查询/读取 → Workflow 科研处理 → 绘图组织/渲染 → 正式成果保存的公共合同。WP1–WP4 的技术依赖仍保留，统一设计、分两批实施：WP1–2 数据基础，WP3–4 公共消费与 AHE 首个真实闭环。先复用已有模块，再补足真实缺口；不为形式统一而增加框架。WP1 原有三个原则全部保留：

- 测量上下文随 Source 同一提交点持久化，记录用户确认的 workflow、通道与物理角色、条件及来源（rule/manual/fallback）、测量时间、原始文件名、源文件 mtime、旧路径（仅记录，不作身份）及必要规则/解释来源；可批量查询，唯一权威，不写进 Dataset 本体。未知不猜；有效通道属于 Source–Sample 直接关系，SQLite 为权威。
- 一份多通道文件涉及多个样品时，每个目标 Sample 各保存一份完整 Source 字节并登记各自有效通道；不共享跨样品所有权，不为节省少量磁盘空间跨样品去重。原始文件不改写，不将其他样品的信号暴露为本样品可分析通道。
- 合法且可保存的原始文件**永远先作为 Source 入库**；是否有适配器、能否标准化与能否分析，是入库之后各自独立步骤的结果。无 Dataset 的 Source（Source-only）仍受通用身份、归属、完整性、查询及删除/恢复机制管理，原因与可分析性明确，不伪造 Dataset。MR 只保留数据分类，不另建 MR Workbench、解析器或兼容逻辑；旧 Measurement Set 不迁移、不新增集合字段。

**WP2–WP4 本次纳入详细设计，不实施。** WP2 复用 PPMS DAT、Zurich LVM、RSM TXT loaders 与现有 AFM 矩阵能力；WP3 统一检索、读取和列/通道定位；WP4 用 AHE 验证公共 Workbench 来源入口、正式手工 Plot 保存和 Sample Result 显式赋值。各 Workflow 的物理处理独立，科研配置变更与纯显示重绘分开。后续 RT/XY/3ω/IV/RSM 适配不在本 PR 实施范围；仅用现有消费者的真实差异验证公共合同是否成立，不能预造未来接口。

WP0/WP8 合并安排为后续迁移安全设计与实施，技术上 WP0 独立；WP9 真实库预演/切换另行授权。保留 V1 正常使用、AFM 标准化/自动出图现有功能。只有实际共同合同变化才调整 SKELETON，不另设并行权威或任务看板。

## 2. 基线源码事实（静态读码，未运行）

| 事实 | 位置 | 对设计的含义 |
|---|---|---|
| `ingestAsset` 一次提交 = 事务 1（operation=pending + Source/Dataset `staging` 行）→ 写文件并回读校验 → 事务 2（`ready`、`dataset_source` 依赖、`sample_asset_links`、operation=committed）。pending 崩溃一律 `abortIngest` 回滚。已 committed 的同 operationID 重放返回原回执并校验目标 Sample。 | `LibraryAssetService.swift:257–426`；`+Deletion.swift:519–598` | 现状把 Source 与 Dataset 绑在**同一事务**里（耦合点）：设计把它拆成两个独立的两段式事务，各自复用同一套 pending/回滚/重放机制；恢复机制复用，但 `recoverPending` 需新增一个 `standardize` 操作类型分支（现对未知类型抛 `databaseCorrupt`，`+Deletion.swift:545`）：其中止只回滚该操作的 Dataset `staging` 行/文件，**不触碰 Source**。 |
| 入口拒绝：`guard !payload.datasets.isEmpty`（`:293`）。`standardize` 的任何错误都直接抛出，没有“适配器拒绝”与“I/O/哈希失败”的区分。 | 同上 | 现状是入库被标准化异常牵连。设计改为：入库不接触适配器；标准化的“拒绝”（类型化）与“技术错误”（I/O、租约等）在标准化步骤内区分，均不影响已提交的 Source。 |
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

### 3.0 职责边界（用户 2026-11-28 确认：入库是入库，分析是分析，步骤之间不互相调用）

| 步骤 | 只负责 | 输入 / 输出 | 不得 |
|---|---|---|---|
| ① **Source 入库** `ingestSource`（及补录 `amendSourceContext`） | 持久化原始字节、身份、Sample 归属、已确认/未知的上下文与有效通道、完整性（哈希/大小/回读校验） | 输入：文件字节、目标 Sample、operationID、上下文。输出：**自足的入库回执** `SourceReceipt{sourceID, sampleUID, sha256, byteSize}` | 选择/调用适配器；引用 Dataset 类型；知道 Workbench、分析、自动出图意图；因“无法解析/无适配器/通道未知”而拒绝 |
| ② **标准化** `standardizeSource` | 通过只读数据合同 `readSource(sourceID)`（已提交 Source、校验哈希）取得原字节，生成 Dataset，或记录“未生成”及原因 | 输入：已提交的 sourceID + 由调用方给定的适配器（可为空）。输出：`standardized(datasetIDs)` 或 `notStandardized(code, detail)` | 回头调用入库补写/修改 Source、上下文或归属；做科研分析；决定要不要出图 |
| ③ **分析 / 绘图** | 消费标准 Dataset 与上下文（`resolveMeasurementInput`、Plot 保存） | 输入：Dataset ID。 | 解析 Source；调用入库或标准化 |
| ④ **协调** `ApplyCoordinator` / `InboxArchiveApplyService`（现有） | 按需**顺序**调用 ①→选适配器→②→（需要时）③，合并各步结果、决定出队。自动处理与人工操作调用同一批能力 | 同步执行；不新增线程、事件总线、任务引擎、仓库或大规模重构 | 把一步的知识塞进另一步的接口 |

- **共用下层**（SQLite、写租约、事务/崩溃恢复、依赖保护）可被各步共同使用，这不等于业务步骤互调。
- **三个“成立”分开**：“原始文件已保存”（①回执）≠“Dataset 已生成”（②结果 `standardized`）≠“可分析”（Dataset 存在、上下文/通道满足该 workflow 的需要，由③在读取时判定）。任何界面文案、回执类型和测试都不得混用。
- **各自独立的提交与恢复边界**：①一个两段式事务，只涉及 Source；②自己的两段式事务，只涉及 Dataset、`dataset_source` 与标准化结果行；③沿用现有 Plot 事务。②失败、重试或进程在 ①→② 之间中断，**都不得回滚或重复登记已提交的 Source**。

### 3.1 数据与权威（最小集合）

| 信息 | 唯一权威 | 说明 |
|---|---|---|
| Source 字节、哈希、原始文件名 | 现有 `assets` + `storage/<src>/payload.bin` | 不变。 |
| Source→Sample 归属 | `sample_asset_links`（不变） | K5。 |
| **有效通道（Source–Sample 关系的属性）** | `sample_asset_links.effective_channels_json`（新增可空列） | 元素为 `{id, role?}`；`NULL` = 未确认，不是“全部”（K12）。 |
| **其余测量上下文** | 新表 `source_context(source_id PK→assets, workflow_id?, workflow_origin, conditions_json, measured_at?, measured_at_origin, source_mtime?, legacy_path?, interpretation_json, recorded_at)` | `origin ∈ rule/manual/fallback/unknown`；原始文件名不重复存（用 `assets.original_filename`）。**不含任何标准化状态**——上下文属于入库步骤。 |
| **标准化结果** | 新表 `standardization_outcome(source_id PK→assets, adapter_id?, state, code?, detail?, attempted_at)` | `state ∈ standardized/not_standardized`；**无行 = 尚未处理（待标准化）**。只由标准化步骤写，入库步骤既不读也不写；重试只覆盖本行。Source-only 的权威定义仍是“无 `dataset_source` 依赖”，本行只给原因。 |
| **上下文补录审计** | 新表 `context_amendment(id, source_id→assets, operation_id UNIQUE, request_hash, changes_json, recorded_at)` | 追加式；`changes_json` 记补录的字段、旧值（未知/NULL）与新值（origin=manual）。见 §3.2 补录。 |
| Dataset 列、单位、诊断 | Dataset 自身文件（`columns.json` + `values.bin`） | 上下文不写进 Dataset（K7 与 WP1 原则）。 |

- `source_context` 在 Source 的事务 2 中与 `ready`、归属、通道**同一事务**写入。已确认的值登记后不可变；唯一例外是 §3.2 的**受审计补录**（只把未知/`NULL` 变为已确认，不覆盖已确认值）。补生成 Dataset **不触碰** `source_context`：它只是对已有 Source 再次调用标准化。
- `manifest.json` 仍写入（含 `originalSourcePath`）；它是写入后不再改动的文件侧自述，**查询只读 SQLite**。两处值在同一入库操作内由同一输入生成，不可能分叉。
- 没有 `source_context` 行的旧 V2 Source（仅测试/开发库可能存在，Audit A：真实库无 V2 数据）按“上下文未知”处理：AFM 凭 Dataset 格式识别（现行行为）；其他一律未知，不推测。
- **删除闭包**：库开启 `PRAGMA foreign_keys = ON`，而 `finishDeletion` 在删依赖与链接后才 `DELETE FROM assets`（`+Deletion.swift:458–467`）。因此 `source_context`、`standardization_outcome`、`context_amendment`、`coordinator_followup` 必须在**同一删除事务内、先于 `assets` 行**被删除（实施时在 `finishDeletion` 中与 `sample_asset_links` 同处删除；Dataset 的单独删除只可能发生在 Source 仍有其他 Dataset 时（最后一个被 `lastDatasetDeletionRejected` 拒绝），此时 `standardization_outcome` 保持 `standardized` 不变，不留悬空；以删除故障注入验证）；`computePlan` 不需改动，上下文随所属 Source 的删除闭包处理，Sample 永久删除后保留的 Source 其上下文随之保留。
- Source-only 不是新资产类型或新入库状态：**= 无 `dataset_source` 依赖的 Source**，其原因在 `standardization_outcome`（无行则显示“待标准化”）。现有删除/恢复计划（`computePlan` 以 Source 为起点收集消费者）对零 Dataset 自然成立；最后一个 Dataset 的单独删除仍被拒绝（`lastDatasetDeletionRejected`）。

**Schema 升级（代理技术决定，可推翻）**：`schema_version` 2→3，仅增加上述一列与四表（`source_context`、`standardization_outcome`、`context_amendment`、`coordinator_followup`）。可写实例打开版本 2 时，在写租约下于一个事务内执行加法升级并更新 `schema_meta`；只读实例遇到版本 2 沿用 K13，拒绝并提示“需由可写实例升级”，不读半成品。版本高于 3 仍拒绝。实现上 `LibraryAssetDatabase.open` 目前没有读/写模式而被众多读路径调用，须增加一个显式的“可写打开并升级”单一入口，其余入口只校验；升级单向（旧版本 App 打开版本 3 库会得到 `databaseUnknownVersion`），因此首次升级前必须已有 WP0 备份——对仅有测试/开发 V2 库的现状，批次 A 实施时以明确提示替代自动升级前备份的缺失。`IngestOpPayload`（及标准化/补录操作载荷）新增的 `requestHash` 等字段必须可选，旧 committed 载荷仍可解码。WP8 的迁移工具直接以版本 3 为目标；WP0 备份须覆盖版本 3。

### 3.2 WP1 — Source 入库、补录、协调与多目标

**① 入库入口**。不新增服务：把 `ingestAsset` 的**入库部分**提炼为 `ingestSource(request)`，`request = {sourceFileURL, targetSampleUID, operationID, context, effectiveChannels?, reuseSourceID?}`——**没有 adapter、没有自动出图意图**，模块内不引用 `AssetStandardizationAdapter`、Dataset 编码或 Workbench 类型（实施时以依赖检查验证，见 §4.1 AC3）。返回 `SourceReceipt`，不含 Dataset 信息。

1. **读字节一次**，计算 SHA；`source_mtime` 与 `measured_at` 在读取文件时采集（mtime 来自该次文件属性读取；`measured_at` 沿用 Inbox 已有 `MeasurementTimestampResolver` 的结果及其 origin）。采集失败 → 对应字段置空并记 origin=`unknown`，不阻止入库。
1a. **Source 格式字段**：`assets.format` 为 `NOT NULL` 且现由适配器的 `payload.sourceFormat` 提供。入库步骤自己赋值，**不经适配器**：新 Source 统一写通用值 `source_file_v1`，容器类型由原始文件名后缀（仅作容器提示，不决定科学语义，K12）保存在 `assets.original_filename`/`source_context` 中，标准化侧的容器识别在协调层/适配器登记表里做。**这是用户可见的行为变化**：Library 对新 Source 的仪器/容器标签（现由 `friendlyWorkflowLabel` 按 `assets.format` 映射）改由 `source_context.workflow_id`（已确认时）、文件后缀与 `standardization_outcome.adapter_id` 派生显示，未知时显示原始文件名与“未分类”，不得因此隐藏文件；既有 `ibw_v5` Source 保持原值不改；凡读取 `assets.format`/`manifest.format` 的现有调用方须在实施首步逐一核对（§7）。
2. **只有这些才是入库失败**：原始字节不可读/无法保存或回读校验失败；空文件（代理技术决定：空文件不是可保存的测量原始文件）；Sample 归属无效；完整性/事务/写租约问题。**未知 workflow、未知通道（`NULL`）、无适配器、无法解析、AFM 解析失败都不是入库失败**——入库步骤根本不知道这些。
3. 两段式事务沿用现有：事务 1（operation=pending + Source `staging` 行）→ 写文件并回读 → 事务 2（`ready`、`sample_asset_links`、`source_context`、operation=committed）。**不再有 Dataset 行与 `dataset_source`**；pending 崩溃仍一律 `abortIngest` 回滚。
4. **请求绑定与重放**：operation 的 pending 载荷保存 `requestHash`（Sample UID、**入库时提交的**上下文与有效通道）与 `sha256`（分开存）。同 operationID 重放：已 committed → 只比较**不需要读文件的部分**（Sample UID、上下文、有效通道的哈希），一致即返回**原回执，在读取外部文件之前就返回**——重试不依赖原始外部文件；不一致 → `operationRequestMismatch`（复用 Plot 已有语义）。尚未 committed（pending/新请求）的操作才读取文件并比较/计算 SHA；因此“同 operationID 换了一个文件”只在未提交前能被 SHA 发现，已提交后该 operationID 恒返回原回执（文件内容变化由新 operationID + 重复文件提示处理）。目标 Sample 不一致仍拒绝。哈希取自原载荷，不按当前库内上下文重算，事后补录不会让重放变成冲突。
5. **同 Sample 重复文件**：不自动去重。Inbox 入库前按 `idx_assets_sha256` 查同 Sample 同哈希的 ready Source，提示“已有相同文件”，用户可选复用（`reuseSourceID`，返回已有 Source 回执）或仍新建。复用时：请求中**已确认**的值必须与已记录的已确认值一致，不一致 → `contextConflict`，不覆盖；请求里为“未知”的字段视为**不限定**（不比较），因此补录之后的复用不会误报冲突；想把未知值补上，走补录而不是复用。

**① 补录** `amendSourceContext(sourceID, operationID, changes)`（用户 P4：允许对未知 workflow / 未确认有效通道做受审计补录，不必删除重入库）：
- 只允许把**未知/`NULL`** 字段变为已确认（origin=`manual`）：`workflow_id`、`conditions`、有效通道等；**已确认的值不得改**（冲突 → `contextConflict`）。**Source ID、字节、哈希、Sample 归属不变。**
- 一个事务内写 `source_context`/`sample_asset_links.effective_channels_json` 与一条 `context_amendment`；走写租约、operationID + requestHash 重放语义。
- 补录**只改上下文，不触发标准化**；之后是否重新标准化/分析由协调层或用户在需要时调用。未知科研语义不是拒绝保管原始文件的理由；它只在后续步骤确实需要该语义时阻止该步骤，**不默认猜测、不默认全选**。

**② 标准化** `standardizeSource(sourceID, adapter?, operationID)`：
1. 经 `readSource(sourceID)`（已提交 Source 的只读数据合同：校验哈希，返回字节与 `SourceAvailability`）取字节；**适配器由调用方传入**，标准化模块自己不按 workflow 选适配器，也不读 `source_context`（需要的上下文由调用方随适配器给出）。
2. `adapter == nil` → 写 `standardization_outcome(not_standardized, no_adapter)`，零 Dataset。适配器抛类型化 `StandardizationRejected(code, detail)`（`rows_dropped`、`unsupported_layout`、`parse_error`、AFM 的解析失败等）→ 写 `not_standardized(code, detail)`，**不生成 Dataset、不出图**。
3. 成功 → 自己的两段式事务：新操作类型 `standardize`（operation=pending + Dataset `staging`）→ 写文件并回读 → `ready`、`dataset_source`、`standardization_outcome(standardized)`、operation=committed。pending 崩溃 → 回滚 Dataset，**Source 与上下文不受影响**，重试即可。`not_standardized` 同样记在 `standardize` 操作下（一个小事务写 outcome + operation=committed），因此重放得同一结果；同 operationID 不同请求 → `operationRequestMismatch`。
4. **其余错误**（I/O、哈希、租约丢失、持久化）原样抛出、**不写 `not_standardized`**，状态保持“待标准化”以便重试；只有适配器明确拒绝才是“未生成”。
5. **重试/补生成**：同一 Source 可再次标准化；已有 Dataset 且同适配器 → 返回现有结果，幂等；`standardization_outcome` 由 `not_standardized` 变 `standardized` 只发生在本步骤内。适配器按容器格式选择，补录 workflow 主要影响分析/出图，不是“补录后才有适配器”；仅当已确认分类变为 MR 等明确无适配器，协调层不再自动标准化，**已生成的 Dataset 保留**（忠实表格，无科研语义，不删除）。请求哈希 = (sourceID, adapter 标识与版本)。
6. 现有 `standardize`/`AssetStandardizationAdapter` 接口改为接受 `readSource` 给出的字节，不再由入库同时读取。

**④ 协调**（`InboxArchiveApplyService` + `ApplyCoordinator`，现有；可同步执行）。对每个目标顺序做：`ingestSource` → 按**容器格式**选适配器（`standardizationAdapter(forWorkflowID:)` 改为按容器格式登记：PPMS DAT、Zurich LVM、RSM TXT、AFM；**已确认的 workflow 为 MR 或其他明确无适配器的分类 → nil**；workflow 未知不阻止选择——标准化只做格式忠实转换，不需要科研语义）→ `standardizeSource` → **（仅当该 workflow 的现有自动处理设置要求，且标准化成功时）** 由协调层发起自动出图。自动出图的触发归协调层：入库、标准化模块都不含该意图。**意图与崩溃恢复**：现状把意图存在已提交的 ingest 操作里，重启时由 `pendingAutoPlotIntents` 扫描 `$.result.autoPlotIntent`/`datasetIDs`（`LibraryAssetService+AutoPlot.swift:247–273`，`AFMAutoPlotRunner.recover`）。拆分后，协调层在**调用标准化之前**于自己的小表 `coordinator_followup(standardize_operation_id PK, source_id→assets, kind, request_json, state pending/done/failed)` 写一行（属协调层，入库/标准化模块不读不写），恢复查询改为：`followup.state=pending` 且该 Source 的 `standardization_outcome=standardized` → 重新发起出图；outcome 为 `not_standardized` → 记 done（不出图）；无 outcome → 保持 pending 等待重试。该表在删除闭包中随 Source 删除（与另三表同处）。**自动出图范围明确：本设计只保留现有 AFM 自动出图；批次 A/B 中 AHE 与其他非 AFM 容器/workflow 不进入 `coordinator_followup`，也不存在通用自动出图触发（非 AFM 自动出图不在范围，需另行授权）**，协调层对非 AFM 目标不写 followup 行；**自动出图仍沿用现有 `AFMAutoPlotRunner`（异步）**，协调层只负责“何时触发、何时恢复”，因此“同步顺序调用”指入库→标准化的先后与结果汇总，不要求出图同步完成。出图走公共 Plot 保存路径，**出图失败只报告，不回滚 Dataset 或 Source，也不阻止出队**（用户可手工以同一能力重试；代理技术决定，见 §7 对现有 AFM 失败处理的核对项）。
- **AFM 正常成功路径**对用户不变：入库 → 标准化 → 自动出图，三步之间只有短暂的 Source 已存/Dataset 尚无状态；现有 AFM 测试须全绿（AC5）。AFM 解析失败改为 Source 保留 + `not_standardized`，不生成伪 Dataset、不出图（P2）。
- `ingestAsset` 现有调用方迁到协调层；若保留同名包装，它位于协调层，**不在入库模块内**。

**多目标与出队**。Inbox draft 的 `v2TargetSampleUID/v2OperationID/v2ReuseSourceID` 泛化为 `v2Targets:[{sampleUID, ingestOperationID, standardizeOperationID, effectiveChannels?, reuseSourceID?}]`，每个目标在加入 draft 时生成并持久稳定的 operationID（旧单目标 draft 解码为一个目标，不带通道）。应用时逐目标顺序执行上述流水线，**不做跨目标或跨步骤大事务**：原子性单位为“一个 Source”“一个 Dataset”。每个目标返回分阶段结果 `{ingest: applied(sourceID)|failed, standardize: standardized|notStandardized(code)|pending, plot: none|done|failed}`。

- **重试不依赖外部文件**：Source 入库成功后，协调层只持有 `sourceID`（来自回执）；标准化、重新标准化、补录及出图重试一律经 `readSource(sourceID)` 读取 Library 内副本，**外部原文件被移动/删除不影响**。只有尚未入库成功的目标重试才需要外部文件，缺失时报告入库失败。
- **未知上下文不阻止标准化**：有效通道为 `NULL`、workflow 未知都不阻止标准化（Dataset 保存完整列，通道只在读取/Plot 校验时用，§3.3）；只有分析/出图真正需要该信息时才要求补录。
- **无出口的重试**：若 `readSource` 校验哈希失败（Library 副本损坏，`SourceAvailability` 非可用），该目标报“Source 不可用”，不再无限重试；用户可明确“移出队列”（Source 保留，其状态在 Library 如实显示不可用）。
- **出队判定**：条目只有在**所有目标的入库已 applied，且每个目标的标准化已到终态（`standardized` 或 `notStandardized`）**时才出队；`notStandardized` 是终态（该 Source 成为 Source-only，界面如实报告原因），不留在队列。入库失败或标准化因技术错误处于 `pending` 的目标保持在队列，界面列出各目标状态；重试只重放未完成的阶段（已提交的 ingest 重放回执，已完成的 standardize 幂等），**不重复登记 Source**。
- 审计事件按目标、按阶段各写一条。
- **可应用判定**集中为单一函数，替换 `ApplyCoordinator`、`SpinLabAppState+V2Assets`、`SpinLabAppState+ApplyPipeline` 三处各自的“有适配器+单目标”条件；**新判定不依赖适配器是否存在，也不要求通道已确认**：只要求目标 Sample 有效、文件可读。通道为 `NULL` 时照常入库；需要通道的 workflow 在**读取分析输入时**才返回“通道未确认”（§3.3），并提示用户补录。
- **已提交目标的锁定与编辑**：目标一旦入库 `applied`，其 ingestOperationID、通道与上下文在 draft 中只读（要改走补录）；Inbox 面板现有“目标变化即重置 operationID”的逻辑（`InboxSelectionWorkbenchPanel.swift:376–382`）对已提交目标不得触发，不得移除已提交目标（只能在 Library 中对其 Source 做常规删除）；对未提交目标的编辑照常重新生成请求。旧 draft 中多于一个元素的 `v2TargetSampleUIDs`（`InteractionStateModels.swift:103–108` 现被丢弃）不迁入，作为未选目标处理并提示重新选择，不猜测。同步改动的位置还含 `InboxSelectionWorkbenchPanel.swift:128,343–382`。

**界面（最小，P3）**。沿用 Inbox 确认面板与 `AdaptiveSheet`/`AppSpacing`（`specs/04_UI_RULES.md`）：目标 Sample 多选 + 每目标通道选择（可不选）；应用结果以现有失败/成功反馈分阶段呈现每目标状态。**Source-only 作为普通 Source 的状态，显示在现有 Sample 资产列表**：文件名、状态（待标准化 / 未标准化 + 原因 / 已标准化）、定位/查看入口，不显示“分析”操作；不新建页面。对“待标准化”与可重试的 Source，提供一个调用同一协调函数的“重新标准化”入口；对未知 workflow/通道的 Source，提供“补录”入口（P4）。不复制 Library 管理逻辑。

### 3.3 WP2 — 表格 Dataset

- **形态**：新 codec `measurement_table_v1`（单一 Dataset 格式，容器类型作为内容字段），文件 `columns.json` 与 `values.bin`。`columns.json`：`loaderFormat`（`ppmsDAT/zurichLVM/rsmText`）、`rowCount`、列数组（`stableSourceKey`、`sourceColumnIndex`、`rawLabel`、`unit`、`physicalQuantityID?`、`instrumentChannelLabel?`）、`diagnostics`（code/message/columnKey/rowIndex）、`codecVersion`。`values.bin`：列主序 IEEE754 Float64 小端，NaN 位型保持。哈希由 `AssetFileEntry` 逐文件记录（现有机制）。
- **解码**得到 `LoadedMeasurement`（`sourceFilePath` 不持久，解码时置为 Dataset 标识）。`PhysicalQuantityUnitTag` 是枚举，需显式稳定字符串映射并对未知值失败（不静默当“无单位”）；映射表由 `V3fPPMSDATLoaderMigrationTests` 现有分类覆盖验证。
- **适配器**只包装现有加载器，不重写解析。PPMS：补空/截断已有诊断 → 作为诊断随 Dataset 保存并在界面可见；RSM：加载器本就在异常行抛错 → 转 `StandardizationRejected(parse_error)`（Source 已先入库，保留）。**LVM**：为加载器增加诊断（`malformedRow.dropped` 丢行、`malformedRow.truncated` 截断、`field.nonNumeric` 非数字转 NaN，均含行号/列键），不改变其返回的数值；标准化时 **任何被丢弃的数据行都拒绝生成 Dataset，原始 Source 照常保留**（`not_standardized: rows_dropped` + 数量；P1 已由用户确认）；截断与非数字转 NaN 仅记入诊断、不拒绝（与 PPMS 补空/截断同级；代理技术决定，沿用既定诊断处理，用户可推翻）。空行与标记行前内容不算数据行。零容忍默认已由用户在 P1 确认；真实 LVM 文件的丢行分布仍未验证（不读取真实库，不擅自放宽）。
- **LVM 位置列与通道号**：Dataset 只保存 `col<N>`、原始表头与 `instrumentChannelLabel`；col0 的科学含义与通道号≠谐波均留在 workflow 解释层，由 `source_context.workflow_id` 决定（K12）。`I_rms`、Rxy、拟合、平滑不入标准化层。
- **有效通道与列定位的衔接**：Dataset 保存**完整**列（含其他样品的信号）；“哪些通道属于这个 Sample”只由 `effective_channels_json` 决定，Dataset 不重复保存。**强制点在读取与保存两处，而不是靠 workflow 自觉**：①来源缝 `resolveMeasurementInput` 返回的 `LoadedMeasurement` 已按有效通道过滤——对 PPMS 桥类 workflow，未列入有效通道的桥对应列（经 `PPMSBridgeChannelMapping` 的通道→列映射）不出现在 `signals` 中，公共列（场、温度、时间）保留；`NULL` 的输入对需通道的 workflow 返回“通道未确认”，不进入分析；②Plot 发布/更新校验每个输入的 `channelID` ∈ 该 Dataset 所属 Source 的有效通道，否则拒绝。**该约束只适用于登记了“通道→列映射”的 workflow（现仅 AHE）**：AFM 及未登记映射的 workflow 不适用——AFM 的通道来自矩阵自身的 `signal_locator`，其 `effective_channels_json` 恒为 `NULL` 且不参与读取过滤与 Plot 校验，行为与现状一致；对登记了映射的 workflow，`NULL` 则拒绝（通道未确认），用户通过 §3.2 补录确认通道后再读取，Source/Dataset 不需重建。旧的单目标 draft 迁移为 `v2Targets` 时不带 `effectiveChannels`（即未确认）。通道→列的映射由各 workflow 声明（AHE 用现有桥映射），批次 A/B 只实现 AHE 所需的一份。
- AFM 不变：保持 `afm_dataset` 与自己的矩阵 payload。

### 3.4 WP3 — 公共查询与读取

- **目录查询**：新增 `listMeasurementCatalog(rootURL:)`，一次 SQL 联结 `assets/sample_asset_links/source_context/dataset_source`，返回两类行：①Dataset 行（`datasetID, datasetFormat, sourceID, sampleUID, workflowID?, conditions, effectiveChannels?, measuredAt?, originalFileName, sample/batch/substrate 显示信息`）；②Source-only 行（供 Library 使用，**不进入 Workbench 命中**）。`listAnalysisDatasets(format:)` 由它实现或保留给 AFM 到 WP3 实施时再合并（以 AFM 回归全绿为准）。
- **命中**：`standardDatasetHits` 改为遍历目录中**当前 Workbench 已适配的 workflow**（登记表决定；WP4 起含 AHE）；`workflowID/conditions/channels/appliedAt` 来自上下文。数字检索对 V2 命中启用：条件值在入库时已规范化存入 `conditions_json`，复用现有条件解析工具比较；`NULL`/缺失条件不匹配数字查询。身份仍是 Dataset ID；路径不作身份。
- **分析只消费 Dataset**：目录查询、命中、`resolveMeasurementInput` 与 Plot 保存只经 Dataset ID 与 `loadDataset`，**不解析 Source 字节，也不调用入库/标准化**；Source-only 或“待标准化”的 Source 不会成为命中，需要时只能由协调层先标准化。
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

- `LibraryAssetService`（入库事务、恢复、删除、Plot 提交）：仍是唯一的持久化服务，只扩展、不新增并行服务；其中 `ingestSource`/`amendSourceContext`、`standardizeSource`、Plot 提交是三组**互不调用**的入口，共用下层事务/租约/依赖保护。
- 新增小模块：`MeasurementContext`（值类型 + 校验，入库侧）、`MeasurementTableCodec`（WP2，标准化侧）、`MeasurementCatalog`（WP3 查询）、`MeasurementInputResolver`（来源缝）、`PlotFormatRegistry`（WP4）。各自只有上述实际消费者。
- 允许的依赖方向：协调层 → 入库 / 标准化 / 分析；标准化 → `readSource`（只读合同）；分析 → Dataset 读取。**禁止**：入库 → 标准化/Dataset/Workbench；标准化 → 入库写入/分析；分析 → Source 解析/入库/标准化。
- Workbench 层：AHE 之外的 workflow 此时**不改**；它们在 V2 下的“拒绝/不可用”行为保持（切换时只能 Source-only，见 design-11 §4.2 脚注）。

## 4. 设计交付与实施验收合同（含夹具入口）

以下是后续实施必须证明的验收；具体夹具与入口见 §4.1。本 Draft 不宣称功能已实现。

| 验收 | 后续实施必须证明 |
|---|---|
| AC1 上下文 | 确认的 workflow、有效通道/角色、条件及来源、时间、mtime、原名、旧路径按值往返；未知不猜；批量查询可用，单一权威，无重复存储；旧 AFM 记录处理明确；未知字段可受审计补录（只补未知、不覆盖已确认、Source ID/字节/归属不变，重放幂等）。 |
| AC2 多目标 | 同一多通道文件归两个样品，两个 Source ID、完整字节相同，各自有效通道与归属正确；无跨样品共享/误读；部分失败与重试不会重复、错写或遗失待处理目标。 |
| AC3 入库独立与 Source-only | 入库模块不依赖适配器/Dataset/Workbench/自动出图（接口与依赖检查证明）；MR/无适配器、标准化被拒（含 AFM 失败）、未知 workflow/通道的可保存原始文件都先成功入库，零 Dataset，原因由标准化结果报告；重启后归属/内容/状态可读；不可分析、不出图；原始字节不可读/不可保存、Sample 无效、完整性/租约失败仍是入库失败且不报告成功。 |
| AC4 生命周期与恢复 | 入库与标准化各有独立提交/恢复边界：Source 已提交后标准化失败/崩溃/重试，不回滚、不重复登记 Source；沿用资产事务、写保护、删除/恢复与依赖规则；故障注入覆盖两步各自的提交中断、重放、重复请求与请求冲突，无半状态或孤立关系；跨库/只读拒写；补生成 Dataset 保持同一 Source 身份。 |
| AC5 回归与交互 | V1 日常路径和 AFM 入库→标准化→自动出图的成功路径不回归（AFM 失败改为保留 Source，见 AC3）；多目标部分成功与出队判定；隔离 V2 库 GUI 验证多目标确认、Source-only 显示/查看、失败反馈、重启读回及删除/恢复；不新增旧分组机制，不为 MR 建专项分析。 |
| AC6 标准 Dataset（WP2） | PPMS DAT、LVM、RSM TXT 代表性合成夹具按原始列值/顺序/单位/NaN/诊断往返；解析异常不静默丢行；DAT 列重排仍可正确映射；确认 MR 不因容器是 DAT 而生成可分析 Dataset；LVM 丢行不生成 Dataset 且 Source 保留；对已有 Source 重新标准化的身份/重试合同可验证。 |
| AC7 查询与数据消费（WP3） | V2 命中带正确 workflow/条件/有效通道/时间；按 UID/Dataset ID 读取；Source-only 与未适配 Workbench 不冒充可分析输入；列/条件公共工具收敛后 V1 回归及现有 AHE/RT/XY 结果逐值不变。 |
| AC8 AHE 闭环（WP4） | 隔离 V2 库：新文件多目标正确入库→重启查询→使用标准 Dataset 分析→正式 Plot 保存/替换/列出/重开/导出→用户明确确认后按 UID 写 Sample Result→删除/恢复与依赖保护；同一夹具 V1 科研计算结果与日常行为不回归。 |
| AC9 设计收口 | 一次按 Deliver 完成 WP1–WP4 统一设计的独立审查；明确实际源码事实、未验证项、两批实施范围和验收归属，后续代码 PR 另行授权，按 AGENTS 验收。Task 11 仍未完成，设计不改版本。 |

所有开发/运行证据只使用隔离合成夹具；真实 Library 不读取、不修改、不迁移。设计 PR 不修改 Swift、schema 或 AppVersion，不自动合并。WP0 技术上不依赖本包，计划与 WP8 作为后续迁移安全交付；不阻塞公共架构设计。
### 4.1 夹具与测试入口（后续实施使用；均为合成数据，隔离临时库）

| 验收 | 夹具 / 入口 | 预期 |
|---|---|---|
| AC1 | 合成 PPMS DAT（3 桥）+ 合成上下文（workflow=AHE、条件 T=10K 来源 manual、mtime=固定值、旧路径=任意字符串）；`LibraryAssetService` 层单元测试，沿用 `Tests/.../Assets` 的临时 V2 库助手 | 重开库后逐值读回；批量目录查询一次返回；`source_context` 之外无第二份；旧 V2 Source（无上下文行）读为“未知”且不报错 |
| AC2 | 同一 3 桥 DAT 入库 Sample A（ch1）与 Sample B（ch2,ch3）；故障钩子 `ingestBeforeCommit` 注入于第二目标 | 两个不同 Source ID、`payload.bin` 哈希相同；A 看不到 ch2/ch3；第二目标失败后 Inbox 条目仍在、A 不重复；重试只补 B；已提交目标重放得原回执 |
| AC3 | ①无适配器（MR 的 DAT）②RSM 异常行 ③LVM 丢行 ④AFM 损坏 IBW ⑤未知 workflow/`NULL` 通道的 PPMS DAT（预期**标准化成功**、读取分析输入时才报“通道/workflow 未确认”），⑥Source 入库后删除外部原文件再触发标准化/重试，六份经协调层；“不可读/空文件”“Sample 无效”“租约丢失”三份入库失败夹具（租约丢失用 `LibraryAssetService.writeLease` 注入点模拟）；**结构检查**：`ingestSource`/`amendSourceContext` 的请求类型与所在文件不含 adapter/Dataset/Workbench/AutoPlot 符号，标准化与分析模块不引用入库写入入口（grep/依赖测试） | ①–④入库成功、零 Dataset，重启后可读，`standardization_outcome` 原因码正确，Workbench 命中为空且无自动出图；⑤入库与标准化均成功，但分析输入被拒绝直至补录；⑥标准化/重试成功，不读外部文件；后三者入库失败且库无残留 |
| AC4 | 在 `ingestAfterSourceWritten`、`ingestBeforeCommit` 与事务 2 之后重放注入崩溃；**标准化独立注入**：Source 已提交后在 Dataset 写入后/提交前崩溃、适配器技术错误、适配器拒绝，各自重试；同 operationID 不同内容；只读实例写入；跨库回执 | 无半状态/孤立 `source_context` 或链接行；请求冲突报 `operationRequestMismatch`；只读拒写；Source-only 的删除/恢复/Sample 永久删除计划与普通 Source 一致；标准化失败/崩溃后 Source 仍在且未重复，重试得同一 Source ID 的 Dataset，重放幂等；版本 2→3 升级中断后可重试 |
| AC5 | 现有 AFM 入库、自动出图、`V213InboxClosedLoopTests`、`V5112InboxArchiveRollbackFailSoftTests`；`spinlab-gui-validation` 对隔离 V2 库 | 全部不回归；GUI：多目标确认、Source-only 显示与定位、失败反馈、重启读回、删除/恢复（GUI 证据须来自交付 HEAD） |
| AC6 | 现有 `V3fPPMSDATLoaderMigrationTests`、`V3cZurichLVMLoaderTests`、`PR148*`、`V3iRSMTextLoaderMigrationTests` 的夹具生成逐格式 round-trip；DAT 列重排夹具；MR 的 DAT 夹具 | 解码值与加载器输出逐值（含 NaN 位型、列序号、表头、单位、诊断）一致；列重排只改映射；MR 不生成 Dataset；LVM 丢行夹具 → `rows_dropped` |
| AC7 | V1 路径旧测试（`V537AHESearchSnapshotConsumptionTests` 等）+ V2 混合库夹具 | V1 全绿；V2 命中带 workflow/条件/通道/时间；Source-only 与未登记 workflow 不出现；列/条件工具收敛前后同夹具 AHE/RT/XY 结果逐值相同 |
| AC8 | 合成 V2 库：多目标 AHE DAT → 重启 → `IngestAHESelectionsUseCase`（V2 来源缝）→ 保存 `xy_curves_plot_v1` → 替换/列出/重开/导出 → 确认写 Sample Result → 删除/恢复/依赖保护；同一夹具 V1 对照 | V2 与 V1 的曲线与 AHE 指标逐值相同；重开后曲线来自 `curves.bin`；未确认不写 Result；被 Plot 引用的 Dataset 删除被保护；其他 workflow 在 V2 下行为不变 |
| AC4+ | 删除闭包与编辑锁定 | 永久删除含 `source_context`/`standardization_outcome`/`context_amendment` 的 Source（含 Source-only）在 `foreign_keys=ON` 下成功且不留行；注入删除中断后恢复；已提交目标的通道/上下文直接改动被拒绝或被界面锁定；复用时上下文不一致 → `contextConflict` |
| AC1++ | 重放与复用 | 已提交 ingest 以同 operationID 重放，外部文件已删/已换 → 返回原回执（不读文件）；未提交时换文件 → SHA 不一致被发现；补录后以“未知”值复用 → 不冲突；以与已确认值不同的值复用 → `contextConflict`；新 Source 的 `assets.format` 为 `source_file_v1`，既有 `ibw_v5` 不变 |
| AC1+ | 补录（P4） | 对未知 workflow / `NULL` 通道的 Source 补录 → 值变为 manual 已确认、`context_amendment` 有记录、Source ID/哈希/归属不变；再改已确认值 → `contextConflict`；补录请求同 operationID 重放幂等、不同内容 → `operationRequestMismatch`；补录后原入库 operationID 重放仍返回原回执；补录后重新标准化/读取通道才可用 |
| AC5++ | 自动出图恢复与不可用副本 | 多目标 AHE/PPMS 入库后不产生 followup 行也不自动出图；AFM：在标准化提交后、出图发布前崩溃重启 → `coordinator_followup` 触发恢复出图且只出一份；标准化被拒 → followup 记 done、不出图；破坏 Library 副本使哈希失败 → 报“Source 不可用”，可移出队列且 Source 保留；`coordinator_followup` 随 Source 删除不留行 |
| AC5+ | 多目标分阶段 | 两目标：A 入库+标准化成功、B 入库成功但标准化技术错误 → 条目留队列，重试只补 B 的标准化；B 标准化被拒 → 终态，条目出队，B 为 Source-only；任一目标入库失败 → 留队列、已提交目标不重复 |
| AC2+ | 通道隔离负向夹具 | Sample A 的读取结果不含 ch2/ch3 列；以 ch2 为 A 发布 AHE Plot 被拒绝；AFM Plot 在 `effective_channels_json=NULL` 时仍可发布（AC5 回归） |
| AC9 | 本页 §8 | 独立审查结论与处置已记录；Swift/schema/版本零改动 |

## 5. 两批实施顺序与归属

1. **批次 A（WP1–2，PR 2）**：schema 2→3 与 `source_context`/`standardization_outcome`/`context_amendment`；`ingestSource` 与 `amendSourceContext`（请求哈希、上下文不可变与补录）；`standardizeSource`（类型化拒绝、独立提交/恢复、重试）；协调层串联与分阶段出队；多目标 draft 与统一“可应用”判定；Source 状态显示、补录与重新标准化的最小 UI；`measurement_table_v1` codec 与三适配器；LVM 丢行诊断。验收 AC1–AC6，GUI 用隔离 V2 库。
2. **批次 B（WP3–4，PR 3）**：目录查询与命中泛化；来源缝；AHE 接入；`PlotFormatRegistry` 与 `xy_curves_plot_v1`；V2 Sample Result 目标解析；列/条件工具按差异表有证据地收敛。验收 AC7–AC8。
3. 批次间依赖：B 只依赖 A 的 `source_context` 与表格 Dataset；AHE 之前不改 RT/XY/3ω/IV/RSM（它们在 WP5–7 继承本合同直接适配；只有出现实质合同缺陷或新的科研选择才补设计）。
4. WP0/WP8（备份/迁移）按 design-11 §4.3 另行设计：WP0 备份范围须包含 `source_context` 与 schema 3；WP8 的 Source 登记必须经 `ingestSource`（标准化另经 `standardizeSource`，不与入库合并）并带 `legacy_path`、mtime 与原始文件名。

## 6. 决策分类

**用户已确认（继承 #247 与 #248 评论）**：一库升级；Source 字节/文件名/mtime 无损；每目标 Sample 各存完整 Source，不跨样品去重；Source-only 合法；MR 仅数据分类与 Source-only，不建 Workbench/解析器；Measurement Set 不迁移；统一生命周期不统一数据形态；复用优先；非 AFM 手工 Plot 保存必须有；Result 赋值需用户明确确认。**2026-11-28（本 PR 评论，基线 `6ab6238b`）**：
- **P1** LVM 有数据行被丢弃 → 默认拒绝生成 Dataset，保留原始 Source 并记录原因；PPMS 补空/截断带诊断沿用。真实文件分布未验证，不授权读真实库、不擅自放宽。
- **P2** 包括 AFM 在内，合法可保存的原始文件不因解析/标准化/分析失败而被拒绝入库；失败由对应阶段如实报告，不生成伪 Dataset、不出图。真正的入库失败 = 原始字节不可读/不可保存、Sample 归属无效、完整性/事务/写租约问题。
- **P3** Source-only 作为普通 Source 状态显示在现有 Sample 资产列表（文件、状态/原因、定位/查看），不新建页面。
- **P4** 允许受审计补录未知 workflow / 未确认通道，不必删除重入库；不覆盖已确认值，不改 Source ID/字节/归属；仅在后续步骤确实需要该语义时阻止该步骤，不默认猜测或全选。
- **职责隔离**：入库只管入库，不知适配器/分析/出图；标准化经已提交 Source 的只读合同取字节；分析/绘图只消费 Dataset；协调层同步顺序调用，不引入新线程、事件总线、任务引擎或大重构（§3.0）。

**代理技术决定（本设计采用，用户可推翻，均不改变产品语义）**：schema 2→3 加法升级与只读拒绝策略；有效通道落 `sample_asset_links`、其余上下文落 `source_context`、标准化结果落独立 `standardization_outcome`、补录审计落 `context_amendment`；Source-only = 无 Dataset 的 Source（不新增资产类型）；标准化的类型化拒绝与“技术错误不写未生成、保持待标准化”；每步各自事务、出队需入库已提交且标准化到终态；自动出图由协调层触发，出图失败只报告、不阻止出队；空文件按入库失败；适配器按容器格式选择，仅已确认的 MR 等明确无适配器分类不生成 Dataset，未知 workflow/通道不阻止标准化；同 Sample 重复文件由用户选择复用，上下文冲突拒绝（补未知走补录）；`measurement_table_v1` 的列主序 Float64 编码；LVM 截断/非数字转 NaN 仅诊断不拒绝；`WorkbenchInputRef` 不携带上下文；新 Source 的 `assets.format` 用通用值 `source_file_v1`；协调层自有 `coordinator_followup` 保存自动出图意图；标准化新增 `standardize` 操作类型；哈希损坏的 Source 可由用户移出队列；`xy_curves_plot_v1` 与登记表。

**仍需用户决定**：无新增产品决定。P1–P4 已全部确认，不再作为待决项。

## 7. 未验证项（均为实施首步核对，不作为已证事实）

- 未运行 App、测试或构建；本设计与代码事实均来自静态读码。
- `ApplyCoordinator` 如何据 `InboxArchiveApplyResult` 将条目出队、V2 多目标是否需要新的结果类型，未逐行核对。
- Inbox 确认面板是否已有可复用的“按 workflow 声明通道列表”的数据源（`WorkflowDefinition` 是否声明桥/通道），未核对；若无，通道候选先来自该 workflow 现有的通道映射（如 `PPMSBridgeChannelMapping`）。
- `PhysicalQuantityUnitTag`/`PhysicalQuantityID` 的完整取值与可逆字符串映射；`MeasurementDiagnostic` 在 LVM 新增诊断后各 LVM 消费者（3ω/IV/XY/RT）是否把诊断当警告显示。
- 现有 Cartesian XY 渲染器在不依赖 Workbench 状态下由 `curves.bin` 重绘的最小入口；`AHEWorkspaceStore` 中保存按钮的现有位置与 `usesFormalPlotSave` 切换点。
- `MeasurementTimestampResolver` 的 origin 语义与 `source_mtime` 采集是否与 Inbox 现有读取重复。
- 现有 AFM 自动出图失败时的处理与触发位置（是否在 `ApplyCoordinator`/`InboxArchiveApplyService` 内、失败是否已不回滚入库）；`ingestAsset` 在 Inbox 之外的调用方（测试、WP8 前的工具）；`readSource` 是否可复用现有 Source 读取/可用性代码（`SourceAvailability`）。
- 现有读取 `assets.format`/`manifest.format` 的调用方（含 AFM 查询、Plot 摘要、删除/备份）对 `source_file_v1` 的兼容；`pendingAutoPlotIntents` 改读 `coordinator_followup` 的最小改动；`AFMAutoPlotRunner` 异步与协调层的衔接。
- 两个独立事务之间的 `ready` Source 在现有 Library 列表/删除/备份路径中是否被误当“不完整”；`standardization_outcome` 与 Dataset 单独删除/最后一个 Dataset 保护的交互。
- 多目标 GUI 的实际控件尺寸与响应式布局须按 `specs/04_UI_RULES.md`、`./scripts/check_ui_rules.sh` 在实施时验证。

## 8. 独立审查记录

**基线 `52bd0aef`→`6ab6238b` 的设计（旧版）**——独立只读审查（fresh-context 子代理，对照源码，三轮，已用满上限并收敛）：
- **第 1 轮（NOT CONVERGED，4 major）**：M1 Plot 输入要求 `datasetID` 互异，与“同 Dataset 多通道”冲突；M2 有效通道未被强制；M3 `source_context` 删除闭包缺失（`foreign_keys=ON`）；M4 多目标重试/上下文生命周期缺口。另有若干 minor。**处置**：全部采纳。
- **第 2 轮（NOT CONVERGED，1 major）**：通道校验未豁免 AFM。**处置**：采纳，校验仅适用于登记了通道→列映射的 workflow（现仅 AHE）。
- **第 3 轮（CONVERGED）**：无新 blocker/major；遗留提示：Plot 校验经 `source_context.workflow_id` 判定，无上下文行的旧 Source 按未知归入豁免分支。
- 审查者仅提供意见，决策与修改由交付代理完成。

**本次修订（用户 P1–P4 + 职责隔离，2026-11-28）**：重写 §3.0–§3.2，并同步 §2、§3.1、§3.3–§3.6、§4、§4.1、§5、§6、§7。对入库/标准化/出图接口与事务边界属实质修改，旧三轮不覆盖。用户随后明确批准**最后一次聚焦复审**（数据安全与恢复，第 4 轮）：
- **第 4 轮（NOT CONVERGED，3 major + 6 minor，对照源码）**：M1 拆分后自动出图意图/崩溃恢复丢失（现存于 ingest 操作，`LibraryAssetService+AutoPlot.swift:247–273`）；M2 重放规则自相矛盾（SHA 需读外部文件）；M3 `assets.format` 现由适配器提供，入库缺格式来源；m1 `recoverPending` 需新增 `standardize` 类型；m2 补录 MR 与按容器选适配器的矛盾；m3 补录后复用误报冲突；m4 哈希损坏的队列项无出口；m5 `not_standardized` 重放语义；m6 Dataset 删除与 outcome 行。已确认无问题：删除闭包顺序与 `foreign_keys=ON`、`abortIngest` 只删 staging、归属触发器兼容、无重复 Source。
- **处置**：全部采纳并写入 §2、§3.1、§3.2、§4.1、§6、§7（新增 `coordinator_followup` 表、`source_file_v1`、`standardize` 操作类型、重放比较规则、复用“未知不限定”、移出队列）。**这些修订没有再次复审**：用户批准的最后一轮已用完，故不宣称收敛；修订均为对复审意见的直接落实，剩余风险在实施首步核对（§7）。如要再审，需用户另行授权。
