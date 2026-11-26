# Task 6 初始设计与静态审计

基线：`e85cb2d5aa13dccff7410957b7f3d51a4036fc66`。2026-11-26 静态核查 GitHub 源码；未构建、未运行 GUI、未访问真实 Library。本文是 [brief-6](brief-6-afm-workbench.md) 的设计讨论材料，不是已批准接口或执行完成报告。

## 1. 当前代码证据：已有能力与断点

下列路径以仓库根为准（`Sources/SpinLabApp/` 下的文件省略该前缀），行号对应该基线。2026-11-26 独立 reviewer 已逐项核对源码，表中事实成立，补充见各行末“审查补充”。

| 位置 | 事实与任务 6 缺口 |
|---|---|
| `Sources/SpinLabApp/Domain/WorkflowSearchModels.swift`、`UseCases/SearchWorkflowMeasurementsUseCase.swift`（61–132）、`App/State/WorkbenchMainSearchRuntime.swift` | 现有搜索枚举 sidecar；hit.id 为 sidecarPath，measurementFilePath 用于分析。V2 Dataset 不能伪造 sidecar/path 才能进 Workbench；应在现有搜索/选中链路显式区分 legacy 文件和标准 Dataset，保留其他 workflow。 |
| `Library/Assets/LibraryAssetService.swift`（452–482）、`App/SpinLabAppState+V2Assets.swift`（51–77）、`AFM/AFMDatasetCodec.swift` | loadDataset 已在 commitLock 下校验文件 hash、codec format、ready 状态，返回 datasetID/revision/dataset/sourceAvailability；Library 已有读取入口（审查补充：`loadV2Assets` 目前无调用方，`LibraryV2AssetsSection` 只处理 Source/Dataset，无 Plot 展示）。标准格式 afm_canonical_v1 含 manifest 与无损矩阵。缺口是 Workbench 选择及同一读点完整的来源/活跃归属标记，不另建 parser。 |
| `Features/Workbench/AFMWorkspaceStore.swift`（438–551、326–382、640–731） | Analyze 仍调用 AFMInputAdapter.load(fileURL:)，缓存 path/sampleKey；后续处理从 immutable dataset；_renderRevision 仅保 UI 异步结果，不能证明 Library revision/正式发布有效。Pack 目前内含 canonicalDataset 及文件路径，restore 重绘历史内容。 |
| `AFM/Processing/AFMProcessingConfiguration.swift`、`AFM/Processing/AFMProcessingPipeline.swift`、`Workbench/V3/Heatmap/AFM/AFMHeatmapPayloadBuilder.swift` | 已有显式科学配置、可独立调用的纯处理 pipeline、ProcessedAFMChannel 与 Heatmap payload；保持 Off/Plane/Robust Plane → Off/0/1/2 Line Flatten → None/Mean/Minimum Zero 顺序及已有默认值。无需重写算法；统一现有 Analyze、reprocess、restore 的适当调用，明确有效配置。 |
| `Features/Workbench/AFMWorkspaceStore.swift`（276–321）、`UseCases/SaveAFMChartToLibraryUseCase.swift` | 旧 Save 用 PNG、当前控件投影、cachedSampleKeys/文件路径构造 manifest，明确 requireV1ArtifactWriteAllowed；不是 V2 保存。须让候选输出携带其真实配置及修订，不从保存时的新控件拼装旧图。 |
| `Library/Assets/LibraryAssetService.swift`（553–615、639–739）、`LibraryAssetDatabase.swift`（schemaStatements） | listAssets 已能查询衍生资产；derivedSampleUIDs 已通过 Dataset → Source → Sample 推导。registerDerivedAsset 仅 relation_only_v1 无文件夹具，直接 ready/current，不核对期望 revision/正式内容；不能直接作为产品发布 API。现有五表与 live_input/snapshot_input 可承载本阶段关系。 |
| `Library/Assets/LibraryAssetService+Revise.swift`、`LibraryAssetService+Deletion.swift` | revise 使用 expectedRevision、单调版本、commitLock、持久操作记录；按直接 live_input 标 stale，清理旧 revision；删除会核验引用计划、保护有效依赖。recoverPending 目前处理 ingest/revise/delete_sample/delete_assets，需要为真实衍生物提交补对应恢复。不能假设有通用传递失效或已存在 Snapshot 内容。审查补充：`AssetDeletionTarget` 仅有 `.source`/`.dataset`（Deletion.swift:239-249）；`recoverPending` 遇未知 op_type 抛 `databaseCorrupt`（Deletion.swift:521-533）。 |

## 2. 推荐最小方案（待确认）

### 2.1 选择与读取

用显式带类型的输入引用区分 V1 legacy 与 V2 datasetID；V2 列表由正式资产与 Sample 查询派生，复用现有 Workbench 搜索/选择 UI，禁止把显示名当身份。保留 single selection 的语义：单 Dataset 可含多个通道。选择时只显示必要原文件名/通道/条件；Analyze 在受控读点捕获 root 身份、datasetID、revision、sourceID、有效 Sample UID/状态及 channel 所需数据。不得从当前全局 Library 或可变 hit 缓存事后补归属。有效标准数据遇来源 payload 缺失/损坏应按 Task 5 独立诊断；归属关系非法、数据库或 Dataset 损坏则停止。设计评估读取所有矩阵的成本，列表查询不解码所有数据。

### 2.2 独立能力与候选

复用 AFMProcessingPipeline、AFMHeatmapPayloadBuilder 和 HeatmapRenderPipeline；仅抽出实际重复的非 UI 编排，不要求新通用协议/插件。请求捕获数据 revision、稳定 channel、全部实际有效的 AFMProcessingConfiguration、科学方法标识/版本和有效显示参数（含 scale bar、resolved title 和 global style defaults）；默认策略在调用边界明确解析，缺失用户指定 channel 不能悄悄换成其他 channel；新选择的默认 channel 仍遵守 AFMChannelResolver 并报告 fallback。处理结果携带矩阵、坐标、单位、诊断和 provenance；显示配置/渲染图与之分开，换样品/改配置或异步取消后不得使用不匹配的候选。显示只改变映射，不重新定义科学矩阵；是否缓存不属于合同。

建议直接物化正式 Plot 的处理矩阵与坐标、单位和诊断，附有效科学/显示配置、方法/应用版本、输入 Dataset ID/revision 及图像；利用现有 binary/manifest 编码与 hash primitives，不把 processed matrix 登记为标准 Dataset，也不把 PNG/Pack 当唯一正式数值。若设计改为可验证重建，必须说明如何在旧 revision 被清理、算法变化后仍能保证固定内容；优先物化避免该假设。图像可复用现有 renderer，PDF 是否作为正式持久文件须核查既有用户功能。

### 2.3 正式发布与回读

先确定用户 Save 语义：预览保持临时；Save to Library 创建或更新 Live Plot（plt_）。固定 Snapshot 本任务不支持，由后续小任务设计（见 §2.5）。不要默认每次参数拖动写 Library；更新目标应为明确身份，不靠标题、路径、全局 mutable config 猜测覆盖。单次 operationID 重试必须核对请求与既有回执相符；独立用户保存与重试区分。明确重复保存、更新和独立删除的行为；保留已验证的旧 V1 Save 语义。

复用 LibraryAssetService 的单写许可、commitLock、SQLite/asset_operations、路径验证、hash/staging/恢复原语；在同一不可交错正式提交点检查 captured root、所有直接/实际间接依赖（本阶段单 Dataset、其 Source/活跃 Sample 归属）、Dataset 单调 revision、目标 Plot identity/revision/state 与所声明定义标记、有效请求/取消状态。配置或归属有可能 A→B→A 的消费者必须共享单调变更标记/串行提交次序，不能只比值或把 UI renderRevision 当持久版本。设计审计软删除/恢复和其他归属写路径是否同受保护；若不共享边界，补最小协调，不加跨进程新锁。检查、文件正式发布、数据库 ready/current 状态和依赖登记不可在不同不受控时序中完成；候选计算可在锁外。失败或崩溃在现有操作表内完成/回滚，正式 ready 不得指向未校验或不存在文件。重复/恢复不得复活已删除成果。

Plot 只通过 Dataset 依赖查询所属 Sample；用户能从 Library 读图、数值和状态，使用现有展示面/控件而非另做独立结果系统。更新 Dataset 使依赖它的 Live stale，未保存预览清楚失效，不清空用户确认的 Sample Result。已有直接依赖足以覆盖本阶段，不为未存在 DAG 预建传递计算框架。后续 Snapshot 任务应固定当时所使用的输入数值（本任务不实现，仅记录约束）（至少完整选中 channel 的矩阵、坐标、单位/必要 provenance、有效配置和输入身份/修订）及输出矩阵、图、诊断，不依赖已被清理旧 revision 或重新解析；与 Live 分开身份、状态、恢复。已保存快照之后不可随更正改变。引用保护继续适用，不能借新接口隐式删除被保护数据；用户能明确删除不再需要的正式产物（具体入口、计划与权限沿现有删除合同设计）。

### 2.4 兼容与实现分段

- V1 保持现有原始读取、旧 Save、Pack/restore。V2 不开放旧 artifact 写入保护；旧 Pack 的历史数据只能作为兼容输入，不得登记成新标准 Dataset 或绕过 V2 发布。审计 Pack Vault、restore/search cache、Save/update、copy/export、Library 结果展示和删除调用链，确定 V2 Pack 是否仅恢复工作区配置，或本阶段明确禁用未迁移功能；不得默默降低 V1 功能。
- 建议先在隔离测试库接通 V2 搜索和共享分析（AC1–AC3），再交付真实资产保存/回读/删除与恢复（AC4–AC6），最后执行完整 GUI/V1 回归（AC7）。Snapshot 已按 §2.5 拆为后续任务；K11 的 Snapshot 首次消费者在后续任务落地，本任务不得把 PNG 命名为 Snapshot。Task 7 不得依赖 Snapshot。
- 用现有 Assets/AssetIngestAndReadTests、AssetReviseTests、AssetDeletionTests、AFM processing/real-file acceptance 及 Workbench search mirror 测试作为基线。实际比较同一输入的有限数值（先验证原/标准 codec 无损；明确同进程/同算法确定性或容差与 NaN/Inf 规则），不仅比 PNG。使用同步 barrier 确定性测试竞态；故障注入验证 staging、正式目录、DB commit 前后、重复回执和重启恢复，禁止修改测试预期掩盖失败。真实 GUI 按 AGENTS 的 Cua 隔离合同使用交付 HEAD。

## 2.5 用户已确认的产品决定（2026-11-26）

1. **保存语义**：Live 为常规保存；固定 Snapshot 是用户显式的独立操作。预览/拖参数不写 Library。再次 Save 更新用户明确选中的 Plot（身份来自 Plot ID，不靠标题/路径猜测）；要新图须明确选择“另存为新图”。
2. **首期范围**：任务 6 先交付 Live 正式 Plot（选择 → 处理 → 保存 → 回读 → 独立删除/恢复）。Snapshot 拆为紧随的小任务，本任务内明确标注“暂不支持”，不用 PNG/Pack 冒充。V2 Pack 同样标注暂不支持（V1 Pack/Restore 保持不变），不得绕过正式资产机制。
3. 据此，AC5/AC6 中“若实现 Snapshot”的条目本任务不适用；Snapshot 的固定输入与恢复验收移入后续任务。

## 2.6 设计审查后的收敛规格（2026-11-26，独立 reviewer 第 1 轮）

**用户追加确认**：更新已有 Plot 时旧版本直接替换，不留历史；独立删除仅永久删除（需确认，无回收站，删后不可恢复；崩溃自动恢复仍保证）；正式 Plot 只存 PNG + 处理矩阵 + 清单，PDF 在导出时由同一矩阵重绘。**Save 目标**：Workbench 会话持有“当前目标 Plot”——本会话刚保存或从 Library 打开的那张；有目标时 Save 直接替换它；无目标则新建；另提供“另存为新图”。不按标题/路径猜。一张 Plot 只依赖一个 Dataset。

**A. 搜索/选择**：`WorkflowMeasurementSearchHit` 增加可选 `inputRef: WorkbenchInputRef?`（`.datasetV2(datasetID, sourceID, sampleUID, originalFileName, channelIDs)`）；`id = inputRef?.stableID ?? sidecarPath`（计算属性，旧 Pack/快照经 `decodeIfPresent` 仍可解码）。V2 hit 的 `sidecarPath`/`measurementFilePath` 为空，且 `HeatmapTitleResolution`、`WorkbenchSelectionRuntime`、`WorkflowHitRow` 及 AFM `_runAnalysis` 中按路径匹配/显示/加载的分支改按 `inputRef`，避免空路径误匹配首个 V2 hit。V2 列表用一次批量查询（ready AFM Dataset + Source 原文件名 + 活跃归属 + 通道列表，通道取自 `signal_locator`，不解码矩阵），不得对每个 Sample 反复 `listSampleSourceGroups`（每次 open 都 quick_check）。回收站 Sample 在搜索与捕获两处过滤。恢复的 Pack/搜索缓存中的 V2 hit 仅是 datasetID 定位符，revision/归属/通道在 Analyze 时重读。

**B. 受控读点**：新增 `loadDatasetForAnalysis`，在同一 `commitLock` 内返回 datasetID、revision、sourceID、活跃 Sample UID/状态/是否回收、通道及数据；`dataset_source` 缺失单独报 `ownershipViolation`，与来源 payload 缺失（Task 5 `sourceAvailability`）区分。V2 分支不得调用 `AFMInputAdapter.load`；AC1 用可注入 loader/spy 断言。

**C. 共享分析入口**：单一纯函数 `AFMPlotComputation.run(dataset, channelID, ProcessingConfiguration, DisplayState, StyleDefaults) -> Candidate`（矩阵、坐标、单位、诊断、有效配置、PNG），`_runAnalysis`、`reprocessAndRerender`、`restoreFromPack` 与 Task 7 都调用它，AC2 以此对比。V2 显式 channel 缺失必须拒绝，不沿用 `_runAnalysis` 的默认通道回退；新选择时的默认通道仍按 AFMChannelResolver 并报告 fallback。

**D. Plot 存储与提交状态机**（模板：ingest / revise，均在 `commitLock` + `BEGIN IMMEDIATE` 下；不泛化现有 op）：
- 格式 `afm_plot_v1`；目录 `storage/<plt>/rev_N`，含 PNG、处理矩阵与坐标/单位/诊断、manifest（有效科学/显示配置、方法与应用版本、输入 Dataset ID 与 revision）。`registerDerivedAsset`（`relation_only_v1`）仅留作测试夹具，Library 列表须过滤。
- 新 op_type `plot_publish`（新建）、`plot_update`（新 revision，旧 revision 提交后清理）。Tx1 写 op=pending；新建时插入 `status='staging'` 且 `live_state=NULL` 的行（revise 对 `live_state IS NOT NULL` 做 stale，故 staging 不得有 live_state、无依赖行）。锁内写文件到 `rev_N`（更新用 `.staging_<op>`）并 `verifyFiles`。Tx2 在事务内复核：Dataset `current_revision` 等于捕获值且 ready、`dataset_source` 存在且归属 active、Sample 未回收、lease 可写；更新还须 Plot `current_revision == expectedPlotRevision` 且 ready；通过后置 `ready`/`live_state='current'`，插入 `live_input`，op=committed。
- 恢复：pending 且未提交 → 删除 staging 行与已登记文件，仅当 Plot revision 仍为期望值才删目标目录（沿用 Revise.swift:175 做法）；committed 且 cleanupPending → 完成旧 revision 清理（扩展 Deletion.swift:537 的扫描到 `plot_update`）；`recoverPending` 增加两种 op 分支。读取方只看 `status='ready'`，故崩溃后在恢复前 Plot 不可见（加测试）。
- operationID 重放：仅当请求哈希与既有回执一致才返回原结果，否则拒绝（现有 ingest/revise 仅按 ID 返回，新增比对属本任务工作）。新增 `AssetFaultPoint`：`plotAfterStaging`、`plotBeforeCommit`、`plotAfterCommit`。
- 变更标记审计：Dataset `current_revision` 单调；Dataset ID 不复用；Source 归属只会 active→historical；**Plot 新增 `current_revision`**（每次更新递增，作 `expectedPlotRevision`；不得用 `live_state`，其可 current→stale→current）；Sample 回收/恢复只改 sample.json、不带标记，发布仅在锁内复核“当前未回收”，窗口可接受，且永久删除需先回收并带计划指纹（Deletion.swift:204-207、153），期间发布会令计划 `planChanged`。Dataset revision 仅记录于 Plot manifest（SQLite 依赖表无 revision 列，不新增）；方法/算法版本变化的自动 stale 本任务只记录不自动失效。
- Save 在 lease 非可写时返回错误，不得像 AnalysisVault 那样静默只存内存。同步 `loadDataset`/`loadPlot` 在 SwiftUI 调用时放到后台线程，或明确可接受短暂阻塞。

**E. 读回与删除**：`LibraryV2AssetsSection` 在每个 Sample 下新增 Plots 行（图、current/stale 状态、删除入口）；新增 `loadPlot(plotID)`（锁内校验文件与 hash）。`AssetDeletionTarget` 增加 `.plot(String)`：候选仅该 Plot，删除其依赖行，Dataset 保留；`finishDeletion` 已通用。Dataset/Source 被 Plot 依赖时仍 `assetInUse`；Sample 永久删除按现有规则处理（输入全部删除则一并删，否则保留并标 stale）。Dataset 更正使 Plot 变 stale：保留显示并标“已过期”，提供更新入口，不自动重算也不隐藏。

**F. Pack 与 V1 兼容**：协议 `AnalysisPackProviding` 增加默认 `packSupported: Bool { true }`（其余五个 workflow 不变）；AFM 在 V2 `inputRef` 下返回 false：`saveAnalysis` 拒绝并提示“标准 Dataset 暂不支持”，`hasUnsavedAnalysis` 为 false，Save Pack 按钮禁用同提示，不写 `_spinlab/analysis_packs`。载入 V1 Pack 时清除 V2 `inputRef` 与 Plot 目标。`persistToLibrary` 按 `inputRef` 路由：V2 走新 Save，V1 维持旧路径及 `requireV1ArtifactWriteAllowed`。测试：V1 Pack 存取回归不变、V2 Pack 保存被拒且无 vault 文件。

## 2.7 验收补充

AC1 增加 loader/spy 断言 V2 不触达 raw parser；AC4 增加“有目标则替换、无目标新建、另存为新图”三种行为及 PDF 导出重绘；AC5 的“定义变更”针对带 `expectedPlotRevision` 的更新，并增加“A、B 同读 rev1，B 先更新到 rev2，A 被拒”“Dataset 被删或归属变 historical 时发布被拒”；AC6 采用 §2.6-D 的故障点，并覆盖 lease 只读时 Save 报错及永久删除 Plot。

## 3. 收敛状态

产品语义（Live 先行、Snapshot 与 V2 Pack 暂不支持、替换不留历史、仅永久删除、不存 PDF）已由用户确认。调用链（搜索、读点、提交/恢复、删除、Pack）已在 §2.6 给出规格，待第 2 轮独立 reviewer 核验。仍不使用真实生产库；不推进 Task 7/11/12；仅静态审查，未构建/运行 GUI。
