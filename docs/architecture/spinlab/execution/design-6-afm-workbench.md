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

建议直接物化正式 Plot 的处理矩阵与坐标、单位和诊断，附有效科学/显示配置、方法/应用版本、输入 Dataset ID/revision 及图像；利用现有 binary/manifest 编码与 hash primitives，不把 processed matrix 登记为标准 Dataset，也不把 PNG/Pack 当唯一正式数值。若设计改为可验证重建，必须说明如何在旧 revision 被清理、算法变化后仍能保证固定内容；优先物化避免该假设。图像可复用现有 renderer，正式 Plot 不存 PDF，导出时重绘（§2.6）。

### 2.3 正式发布与回读

先确定用户 Save 语义：预览保持临时；Save to Library 创建或更新 Live Plot（plt_）。固定 Snapshot 本任务不支持，由后续小任务设计（见 §2.5）。不要默认每次参数拖动写 Library；更新目标应为明确身份，不靠标题、路径、全局 mutable config 猜测覆盖。单次 operationID 重试必须核对请求与既有回执相符；独立用户保存与重试区分。明确重复保存、更新和独立删除的行为；保留已验证的旧 V1 Save 语义。

复用 LibraryAssetService 的单写许可、commitLock、SQLite/asset_operations、路径验证、hash/staging/恢复原语；在同一不可交错正式提交点检查 captured root、所有直接/实际间接依赖（本阶段单 Dataset、其 Source/活跃 Sample 归属）、Dataset 单调 revision、目标 Plot identity/revision/state 与所声明定义标记、有效请求/取消状态。配置或归属有可能 A→B→A 的消费者必须共享单调变更标记/串行提交次序，不能只比值或把 UI renderRevision 当持久版本。设计审计软删除/恢复和其他归属写路径是否同受保护；若不共享边界，补最小协调，不加跨进程新锁。检查、文件正式发布、数据库 ready/current 状态和依赖登记不可在不同不受控时序中完成；候选计算可在锁外。失败或崩溃在现有操作表内完成/回滚，正式 ready 不得指向未校验或不存在文件。重复/恢复不得复活已删除成果。

Plot 只通过 Dataset 依赖查询所属 Sample；用户能从 Library 读图、数值和状态，经 §2.6-E 新增的 Plots 行读回，不另做独立结果系统。更新 Dataset 使依赖它的 Live stale，未保存预览清楚失效，不清空用户确认的 Sample Result。已有直接依赖足以覆盖本阶段，不为未存在 DAG 预建传递计算框架。后续 Snapshot 约束（本任务不实现）：应固定当时所使用的输入数值（至少完整选中 channel 的矩阵、坐标、单位/必要 provenance、有效配置和输入身份/修订）及输出矩阵、图、诊断，不依赖已被清理旧 revision 或重新解析；与 Live 分开身份、状态、恢复。已保存快照之后不可随更正改变。引用保护继续适用，不能借新接口隐式删除被保护数据；用户能明确删除不再需要的正式产物（具体入口、计划与权限沿现有删除合同设计）。

### 2.4 兼容与实现分段

- V1 保持现有原始读取、旧 Save、Pack/restore。V2 不开放旧 artifact 写入保护；旧 Pack 的历史数据只能作为兼容输入，不得登记成新标准 Dataset 或绕过 V2 发布。审计 Pack Vault、restore/search cache、Save/update、copy/export、Library 结果展示和删除调用链，V2 下 Pack 按 §2.6-F 明确禁用；不得默默降低 V1 功能。
- 建议先在隔离测试库接通 V2 搜索和共享分析（AC1–AC3），再交付真实资产保存/回读/删除与恢复（AC4–AC6），最后执行完整 GUI/V1 回归（AC7）。Snapshot 已按 §2.5 拆为后续任务；K11 的 Snapshot 首次消费者在后续任务落地，本任务不得把 PNG 命名为 Snapshot。Task 7 不得依赖 Snapshot。
- 用现有 Assets/AssetIngestAndReadTests、AssetReviseTests、AssetDeletionTests、AFM processing/real-file acceptance 及 Workbench search mirror 测试作为基线。实际比较同一输入的有限数值（先验证原/标准 codec 无损；明确同进程/同算法确定性或容差与 NaN/Inf 规则），不仅比 PNG。使用同步 barrier 确定性测试竞态；故障注入验证 staging、正式目录、DB commit 前后、重复回执和重启恢复，禁止修改测试预期掩盖失败。真实 GUI 按 AGENTS 的 Cua 隔离合同使用交付 HEAD。

## 2.5 用户已确认的产品决定（2026-11-26）

1. **保存语义**：Live 为常规保存；固定 Snapshot 是用户显式的独立操作（本任务不做）。预览/拖参数不写 Library。Save 的默认行为由 Library 记录决定、不看会话记忆：见 §2.6 “Save 匹配规则”。
2. **首期范围**：任务 6 先交付 Live 正式 Plot（选择 → 处理 → 保存 → 回读 → 独立永久删除；无 Plot 回收站，崩溃恢复仍保证）。Snapshot 拆为紧随的小任务，本任务内明确标注“暂不支持”，不用 PNG/Pack 冒充。V2 Pack 同样标注暂不支持（V1 Pack/Restore 保持不变），不得绕过正式资产机制。
3. 据此，AC5/AC6 中“若实现 Snapshot”的条目本任务不适用；Snapshot 的固定输入与恢复验收移入后续任务。

## 2.6 收敛规格（2026-11-26，已纳入独立 reviewer 第 1–3 轮意见及用户后续决定）

**用户追加确认**：更新已有 Plot 时旧版本直接替换，不留历史；独立删除仅永久删除（需确认，无回收站，删后不可恢复；崩溃自动恢复仍保证）；正式 Plot 只存 PNG + 处理矩阵 + 清单，PDF 在导出时由同一矩阵重绘。**Save 匹配规则（以记录为准，不依赖会话记忆）**：每张 Plot 已登记其 `live_input` 上游 Dataset 集合。Save 时用现有索引 `idx_deps_upstream` 取出依赖当前输入 Dataset 的 Plot（通常几张，不扫全库），再比较上游集合是否与当前输入集合**完全相同**（按 Dataset ID；Dataset 内容更正即 revision 变化仍是同一 Dataset，故仍算同一张图）。集合相同 → 默认“替换”（同集合多张时默认最近保存的那张，并在按钮旁标明）；无匹配 → 默认“新建”。界面始终提供“替换”和“新建”两个按钮；用户也可手动选一张任意 Plot 来替换，若所选 Plot 的上游集合与当前输入不同，替换前须确认提示（“此图将由 A 的数据改为 B 的数据”），提交时 `plot_update` 在同一事务内替换其 `live_input` 依赖行并复核新旧两侧（新 Dataset 的 revision/归属/Sample 未回收、旧集合无需再保护），Plot 的 Sample 归属随之改变。数据模型与接口按“Dataset 集合”设计；本任务 AFM 只会出现单 Dataset，多 Dataset 合画的界面与流程留待后续，不推翻本设计。目标 Plot 已被删除或 `expectedPlotRevision` 不符（被别处更新）时，Save 失败并提示，提供“新建”，绝不静默新建。载入 V1 Pack 无需清除目标（无会话目标）。**一张 Plot 的上游集合不因普通 Save 改变；仅用户明确手动替换到不同集合时才改变。**

**打开**：Library 图列表中“打开”一张 Plot，即从 manifest 恢复 `inputRef`（由批量查询构造 `WorkflowMeasurementSearchHit`，保持单选、`analyzedHit`、标题一致）、科学/显示配置，按 Dataset 当前 revision 重新运行 `AFMPlotComputation`；之后 Save 按匹配规则默认替换这张图；Dataset 已更正则显示过期标记，Save 即把 Plot 更新到新 revision。存储的矩阵用于读回和数值核对，不用于重新渲染；PDF 导出走 `AFMPlotComputation.render(processed, display, style) -> Data`，不需要 Dataset。Candidate 在内存中仍可渲染 PDF 供现有预览/导出，持久只存 PNG+矩阵+manifest。

**A. 搜索/选择**：`WorkflowMeasurementSearchHit` 增加可选 `inputRef: WorkbenchInputRef?`（`.datasetV2(datasetID, sourceID, sampleUID, originalFileName, channelIDs)`）；`id = inputRef?.stableID ?? sidecarPath`（计算属性，旧 Pack/快照经 `decodeIfPresent` 仍可解码）。V2 hit 的 `sidecarPath`/`measurementFilePath` 为空，且 `HeatmapTitleResolution`、`WorkbenchSelectionRuntime`、`WorkflowHitRow` 及 AFM `_runAnalysis` 中按路径匹配/显示/加载的分支改按 `inputRef`，避免空路径误匹配首个 V2 hit。V2 列表用一次批量查询（ready AFM Dataset + Source 原文件名 + 活跃归属 + 通道列表，通道取自 `signal_locator`，不解码矩阵），不得对每个 Sample 反复 `listSampleSourceGroups`（每次 open 都 quick_check）。回收站 Sample 在搜索与捕获两处过滤。恢复的 Pack/搜索缓存中的 V2 hit 仅是 datasetID 定位符，revision/归属/通道在 Analyze 时重读。

**B. 受控读点**：新增 `loadDatasetForAnalysis`，在同一 `commitLock` 内返回 datasetID、revision、sourceID、活跃 Sample UID/状态/是否回收、通道及数据；`dataset_source` 缺失单独报 `ownershipViolation`，与来源 payload 缺失（Task 5 `sourceAvailability`）区分。V2 分支不得调用 `AFMInputAdapter.load`；AC1 用可注入 loader/spy 断言。

**C. 共享分析入口**：单一纯函数 `AFMPlotComputation.run(dataset, channelID, ProcessingConfiguration, DisplayState, StyleDefaults) -> Candidate`（矩阵、坐标、单位、诊断、有效配置、PNG），`_runAnalysis`、`reprocessAndRerender`、`restoreFromPack` 与 Task 7 都调用它，AC2 以此对比。V2 显式 channel 缺失必须拒绝，不沿用 `_runAnalysis` 的默认通道回退；新选择时的默认通道仍按 AFMChannelResolver 并报告 fallback。

**D. Plot 存储与提交状态机**（模板：ingest / revise，均在 `commitLock` + `BEGIN IMMEDIATE` 下；不泛化现有 op）：
- 格式 `afm_plot_v1`；目录 `storage/<plt>/rev_N`，含 PNG、处理矩阵与坐标/单位/诊断、manifest（有效科学/显示配置、方法与应用版本、输入 Dataset ID 与 revision）。`registerDerivedAsset`（`relation_only_v1`）仅留作测试夹具，Library 列表须过滤。
- 新 op_type `plot_publish`（新建）、`plot_update`（新 revision，旧 revision 提交后清理）。Tx1 写 op=pending；新建时插入 `status='staging'` 且 `live_state=NULL` 的行（staging 不得有 live_state；无依赖行；仅 `plot_publish` 有 staging 行，`plot_update` 没有）。锁内写文件到 `rev_N`（更新用 `.staging_<op>`）并 `verifyFiles`。Tx2 在事务内复核：Dataset `current_revision` 等于捕获值且 ready、`dataset_source` 存在且归属 active、Sample 未回收、lease 可写；更新还须 Plot `current_revision == expectedPlotRevision` 且 ready；通过后：`plot_publish` 置 `ready`/`live_state='current'` 并插入 `live_input`；`plot_update` 在集合不变时不改依赖行（`asset_dependencies` 主键为 consumer+upstream+kind，重复插入会失败）；仅用户手动替换到不同集合时在同一事务内删除旧行、插入新行；其余只置 `live_state='current'`（stale 的 Plot 更新成功后变 current）、递增 `current_revision`、换 `storage_rel_path`/`files_json`；op=committed。
- 恢复：pending 且未提交 → 删除 staging 行与已登记文件，仅当 Plot revision 仍为期望值才删目标目录（沿用 Revise.swift:175 做法；`plot_update` 无 staging 行，只清理 `.staging_<op>`）；committed 且 cleanupPending → 完成旧 revision 清理（扩展 Deletion.swift:537 的扫描到 `plot_update`）；`recoverPending` 增加两种 op 分支。读取方只看 `status='ready'`，故崩溃后在恢复前 Plot 不可见（加测试）。
- operationID 重放：仅当请求哈希与既有回执一致才返回原结果，否则拒绝（现有 ingest/revise 仅按 ID 返回，新增比对属本任务工作）。新增 `AssetFaultPoint`：`plotAfterStaging`、`plotBeforeCommit`、`plotAfterCommit`。
- 变更标记审计：Dataset `current_revision` 单调；Dataset ID 不复用；Source 归属只会 active→historical；**Plot 新增 `current_revision`**（每次更新递增，作 `expectedPlotRevision`；不得用 `live_state`，其可 current→stale→current）；Sample 回收/恢复只改 sample.json、不带标记，发布仅在锁内复核“当前未回收”，窗口可接受，且永久删除需先回收并带计划指纹（Deletion.swift:204-207、153），期间发布会令计划 `planChanged`。Dataset revision 仅记录于 Plot manifest（SQLite 依赖表无 revision 列，不新增）；方法/算法版本变化的自动 stale 本任务只记录不自动失效。
- Save 在 lease 非可写时返回错误，不得像 AnalysisVault 那样静默只存内存。同步 `loadDataset`/`loadPlot` 在 SwiftUI 调用时放到后台线程，或明确可接受短暂阻塞。

**A′. V2 hit 的其余消费者**：V2 匹配一律只用 `inputRef.stableID`，不得回退到 `sampleKey` 或 `sourceFilePath`（`HeatmapTitleResolution.swift:34` 的 sampleKey 回退会让同 Sample 的两个 Dataset 命中第一个）。搜索用例 `matches(hit:resolvedWorkflowID:…)` 对 V2 hit：`workflowID="afm"`、`conditions` 为空、文本匹配只用 sampleKey 与原文件名。V2 的 `cachedInputFiles` 存 datasetID 定位符，`buildRunTrace` 不得因路径为空而返回 nil（增加 V2 分支），`packInputFiles` 对 V2 不填充。

**E. 读回与删除**：`LibraryV2AssetsSection` 在每个 Sample 下新增 Plots 行（图、current/stale 状态、删除入口）；新增 `loadPlot(plotID)`（锁内校验文件与 hash）。`AssetDeletionTarget` 增加 `.plot(String)`：候选仅该 Plot，删除其依赖行，Dataset 保留；`finishDeletion` 已通用。Dataset/Source 被 Plot 依赖时仍 `assetInUse`；Sample 永久删除按现有规则处理（输入全部删除则一并删，否则保留并标 stale）。Dataset 更正使 Plot 变 stale：保留显示并标“已过期”，提供更新入口，不自动重算也不隐藏。

**F0. Save 入口**：静态核查显示 AFM 的 `activeChartManifestPayload` 恒为 nil（AFMWorkspaceStore.swift:592），共享 `WorkbenchResultHeaderShell.swift:54` 因 `!hasActiveManifestPayload` 禁用 Save to Library，`persistToLibrary` 除该按钮外无 UI 调用方——V1 AFM 的 Save 按钮很可能本就不可达（需 GUI 确认基线）。**用户已确认**：本任务只在 V2 `inputRef` 下启用 AFM Save，V1 库行为保持原样（验收为“V1 状态不变”），V1 数据在任务 11 迁移到 V2 后自然走 V2 Save。壳层增加按 store 的 `canSaveToLibrary`，其余五个 workflow 默认保持原判据。“另存为新图”改为与“替换”并列的“新建”按钮，放在 Save 旁（遵守 `specs/04_UI_RULES.md`，运行 `./scripts/check_ui_rules.sh`）；“打开”在 Library 的 Plots 行。

**F. Pack 与 V1 兼容**：协议 `AnalysisPackProviding` 增加默认 `packSupported: Bool { true }`（其余五个 workflow 不变）；AFM 在 V2 `inputRef` 下返回 false：`saveAnalysis` 拒绝并提示“标准 Dataset 暂不支持”，`hasUnsavedAnalysis` 为 false，Save Pack 按钮（与 `matchingVaultPack != nil` 时的 “Update Analysis”，均在 `WorkbenchResultHeaderShell`）经新增的 `packSupported` 透传禁用并给同提示，`matchingVaultPack` 在 V2 返回 nil（`packSupported` 对其他 workflow 默认 true），不写 `_spinlab/analysis_packs`。载入 V1 Pack 时清除 V2 `inputRef`。`persistToLibrary` 按 `inputRef` 路由：V2 走新 Save，V1 维持旧路径及 `requireV1ArtifactWriteAllowed`。测试：V1 Pack 存取回归不变、V2 Pack 保存被拒且无 vault 文件。

## 2.7 验收补充

AC1 增加 loader/spy 断言 V2 不触达 raw parser；AC5 的“定义变更”针对带 `expectedPlotRevision` 的更新，并增加“A、B 同读 rev1，B 先更新到 rev2，A 被拒”“Dataset 被删或归属变 historical 时发布被拒”；F0 并入 AC7（V1 Save 状态不变）；AC4/AC5 增加“集合相同默认替换、无匹配默认新建、手动替换到不同集合需确认且依赖行与归属原子切换、目标被删或 revision 不符时 Save 失败并提供新建、打开 Plot 按当前 Dataset revision 重算并显示过期”。AC6 采用 §2.6-D 的故障点，并覆盖 lease 只读时 Save 报错及永久删除 Plot。

## 3. 收敛状态

产品语义（Live 先行、Snapshot 与 V2 Pack 暂不支持、替换不留历史、仅永久删除、不存 PDF）已由用户确认。调用链（搜索、读点、提交/恢复、删除、Pack）已在 §2.6 给出规格，第 1–3 轮独立 reviewer 意见已纳入；第 4 轮核验用户后续改动（以记录匹配、手动跨集合替换）。仍不使用真实生产库；不推进 Task 7/11/12；仅静态审查，未构建/运行 GUI。
