# Task 6 初始设计与静态审计

基线：`e85cb2d5aa13dccff7410957b7f3d51a4036fc66`。2026-11-26 静态核查 GitHub 源码；未构建、未运行 GUI、未访问真实 Library。本文是 [brief-6](brief-6-afm-workbench.md) 的设计讨论材料，不是已批准接口或执行完成报告。

## 1. 当前代码证据：已有能力与断点

下列路径以仓库根为准，行号对应该基线。

| 位置 | 事实与任务 6 缺口 |
|---|---|
| `Sources/SpinLabApp/Domain/WorkflowSearchModels.swift`、`UseCases/SearchWorkflowMeasurementsUseCase.swift`（61–132）、`App/State/WorkbenchMainSearchRuntime.swift` | 现有搜索枚举 sidecar；hit.id 为 sidecarPath，measurementFilePath 用于分析。V2 Dataset 不能伪造 sidecar/path 才能进 Workbench；应在现有搜索/选中链路显式区分 legacy 文件和标准 Dataset，保留其他 workflow。 |
| `Library/Assets/LibraryAssetService.swift`（452–482）、`App/SpinLabAppState+V2Assets.swift`（51–77）、`AFM/AFMDatasetCodec.swift` | loadDataset 已在 commitLock 下校验文件 hash、codec format、ready 状态，返回 datasetID/revision/dataset/sourceAvailability；Library 已有读取入口。标准格式 afm_canonical_v1 含 manifest 与无损矩阵。缺口是 Workbench 选择及同一读点完整的来源/活跃归属标记，不另建 parser。 |
| `Features/Workbench/AFMWorkspaceStore.swift`（438–551、326–382、640–731） | Analyze 仍调用 AFMInputAdapter.load(fileURL:)，缓存 path/sampleKey；后续处理从 immutable dataset；_renderRevision 仅保 UI 异步结果，不能证明 Library revision/正式发布有效。Pack 目前内含 canonicalDataset 及文件路径，restore 重绘历史内容。 |
| `AFM/Processing/AFMProcessingConfiguration.swift`、`AFM/Processing/AFMProcessingPipeline.swift`、`Workbench/V3/Heatmap/AFM/AFMHeatmapPayloadBuilder.swift` | 已有显式科学配置、可独立调用的纯处理 pipeline、ProcessedAFMChannel 与 Heatmap payload；保持 Off/Plane/Robust Plane → Off/0/1/2 Line Flatten → None/Mean/Minimum Zero 顺序及已有默认值。无需重写算法；统一现有 Analyze、reprocess、restore 的适当调用，明确有效配置。 |
| `Features/Workbench/AFMWorkspaceStore.swift`（276–321）、`UseCases/SaveAFMChartToLibraryUseCase.swift` | 旧 Save 用 PNG、当前控件投影、cachedSampleKeys/文件路径构造 manifest，明确 requireV1ArtifactWriteAllowed；不是 V2 保存。须让候选输出携带其真实配置及修订，不从保存时的新控件拼装旧图。 |
| `Library/Assets/LibraryAssetService.swift`（553–615、639–739）、`LibraryAssetDatabase.swift`（schemaStatements） | listAssets 已能查询衍生资产；derivedSampleUIDs 已通过 Dataset → Source → Sample 推导。registerDerivedAsset 仅 relation_only_v1 无文件夹具，直接 ready/current，不核对期望 revision/正式内容；不能直接作为产品发布 API。现有五表与 live_input/snapshot_input 可承载本阶段关系。 |
| `Library/Assets/LibraryAssetService+Revise.swift`、`LibraryAssetService+Deletion.swift` | revise 使用 expectedRevision、单调版本、commitLock、持久操作记录；按直接 live_input 标 stale，清理旧 revision；删除会核验引用计划、保护有效依赖。recoverPending 目前处理 ingest/revise/delete_sample/delete_assets，需要为真实衍生物提交补对应恢复。不能假设有通用传递失效或已存在 Snapshot 内容。 |

## 2. 推荐最小方案（待确认）

### 2.1 选择与读取

用显式带类型的输入引用区分 V1 legacy 与 V2 datasetID；V2 列表由正式资产与 Sample 查询派生，复用现有 Workbench 搜索/选择 UI，禁止把显示名当身份。保留 single selection 的语义：单 Dataset 可含多个通道。选择时只显示必要原文件名/通道/条件；Analyze 在受控读点捕获 root 身份、datasetID、revision、sourceID、有效 Sample UID/状态及 channel 所需数据。不得从当前全局 Library 或可变 hit 缓存事后补归属。有效标准数据遇来源 payload 缺失/损坏应按 Task 5 独立诊断；归属关系非法、数据库或 Dataset 损坏则停止。设计评估读取所有矩阵的成本，列表查询不解码所有数据。

### 2.2 独立能力与候选

复用 AFMProcessingPipeline、AFMHeatmapPayloadBuilder 和 HeatmapRenderPipeline；仅抽出实际重复的非 UI 编排，不要求新通用协议/插件。请求捕获数据 revision、稳定 channel、全部实际有效的 AFMProcessingConfiguration、科学方法标识/版本和有效显示参数（含 scale bar、resolved title 和 global style defaults）；默认策略在调用边界明确解析，缺失用户指定 channel 不能悄悄换成其他 channel；新选择的默认 channel 仍遵守 AFMChannelResolver 并报告 fallback。处理结果携带矩阵、坐标、单位、诊断和 provenance；显示配置/渲染图与之分开，换样品/改配置或异步取消后不得使用不匹配的候选。显示只改变映射，不重新定义科学矩阵；是否缓存不属于合同。

建议直接物化正式 Plot 的处理矩阵与坐标、单位和诊断，附有效科学/显示配置、方法/应用版本、输入 Dataset ID/revision 及图像；利用现有 binary/manifest 编码与 hash primitives，不把 processed matrix 登记为标准 Dataset，也不把 PNG/Pack 当唯一正式数值。若设计改为可验证重建，必须说明如何在旧 revision 被清理、算法变化后仍能保证固定内容；优先物化避免该假设。图像可复用现有 renderer，PDF 是否作为正式持久文件须核查既有用户功能。

### 2.3 正式发布与回读

先确定用户 Save 语义：建议预览保持临时；Save to Library 创建或显式更新 Live Plot（plt_），固定快照为用户主动的独立操作（snp_）。不要默认每次参数拖动写 Library；更新目标应为明确身份，不靠标题、路径、全局 mutable config 猜测覆盖。用户若选择固定保存而不是 Live 默认，则按已确认语义调整现有入口。单次 operationID 重试必须核对请求与既有回执相符；独立用户保存与重试区分。明确重复保存、更新和独立删除的行为；保留已验证的旧 V1 Save 语义。

复用 LibraryAssetService 的单写许可、commitLock、SQLite/asset_operations、路径验证、hash/staging/恢复原语；在同一不可交错正式提交点检查 captured root、所有直接/实际间接依赖（本阶段单 Dataset、其 Source/活跃 Sample 归属）、Dataset 单调 revision、目标 Plot identity/revision/state 与所声明定义标记、有效请求/取消状态。配置或归属有可能 A→B→A 的消费者必须共享单调变更标记/串行提交次序，不能只比值或把 UI renderRevision 当持久版本。设计审计软删除/恢复和其他归属写路径是否同受保护；若不共享边界，补最小协调，不加跨进程新锁。检查、文件正式发布、数据库 ready/current 状态和依赖登记不可在不同不受控时序中完成；候选计算可在锁外。失败或崩溃在现有操作表内完成/回滚，正式 ready 不得指向未校验或不存在文件。重复/恢复不得复活已删除成果。

Plot 只通过 Dataset 依赖查询所属 Sample；用户能从 Library 读图、数值和状态，使用现有展示面/控件而非另做独立结果系统。更新 Dataset 使依赖它的 Live stale，未保存预览清楚失效，不清空用户确认的 Sample Result。已有直接依赖足以覆盖本阶段，不为未存在 DAG 预建传递计算框架。首次 Snapshot 若实现，应固定当时所使用的输入数值（至少完整选中 channel 的矩阵、坐标、单位/必要 provenance、有效配置和输入身份/修订）及输出矩阵、图、诊断，不依赖已被清理旧 revision 或重新解析；与 Live 分开身份、状态、恢复。已保存快照之后不可随更正改变。引用保护继续适用，不能借新接口隐式删除被保护数据；用户能明确删除不再需要的正式产物（具体入口、计划与权限沿现有删除合同设计）。

### 2.4 兼容与实现分段

- V1 保持现有原始读取、旧 Save、Pack/restore。V2 不开放旧 artifact 写入保护；旧 Pack 的历史数据只能作为兼容输入，不得登记成新标准 Dataset 或绕过 V2 发布。审计 Pack Vault、restore/search cache、Save/update、copy/export、Library 结果展示和删除调用链，确定 V2 Pack 是否仅恢复工作区配置，或本阶段明确禁用未迁移功能；不得默默降低 V1 功能。
- 建议先在隔离测试库接通 V2 搜索和共享分析（AC1–AC3），再交付真实资产保存/回读/删除与恢复（AC4–AC6），最后执行完整 GUI/V1 回归（AC7）。如果首个 Snapshot 使第二阶段过大，先与用户确认拆分，保留 K11 首次消费者约束；不要把一份 PNG 命名为 Snapshot 代替交付。
- 用现有 Assets/AssetIngestAndReadTests、AssetReviseTests、AssetDeletionTests、AFM processing/real-file acceptance 及 Workbench search mirror 测试作为基线。实际比较同一输入的有限数值（先验证原/标准 codec 无损；明确同进程/同算法确定性或容差与 NaN/Inf 规则），不仅比 PNG。使用同步 barrier 确定性测试竞态；故障注入验证 staging、正式目录、DB commit 前后、重复回执和重启恢复，禁止修改测试预期掩盖失败。真实 GUI 按 AGENTS 的 Cua 隔离合同使用交付 HEAD。

## 2.5 用户已确认的产品决定（2026-11-26）

1. **保存语义**：Live 为常规保存；固定 Snapshot 是用户显式的独立操作。预览/拖参数不写 Library。再次 Save 更新用户明确选中的 Plot（身份来自 Plot ID，不靠标题/路径猜测）；要新图须明确选择“另存为新图”。
2. **首期范围**：任务 6 先交付 Live 正式 Plot（选择 → 处理 → 保存 → 回读 → 独立删除/恢复）。Snapshot 拆为紧随的小任务，本任务内明确标注“暂不支持”，不用 PNG/Pack 冒充。V2 Pack 同样标注暂不支持（V1 Pack/Restore 保持不变），不得绕过正式资产机制。
3. 据此，AC5/AC6 中“若实现 Snapshot”的条目本任务不适用；Snapshot 的固定输入与恢复验收移入后续任务。

## 3. 尚待独立审查的决策（第 1、2 项产品语义已按 2.5 确认）

1. **保存模型及入口**：Live 为常规保存、Snapshot 显式固定是否符合真实使用？同一图重复 Save 是否更新明确选中的 Plot，还是新建；从何处打开/重算/独立删除。不要把每次试画变成正式写入。
2. **首期范围**：正式矩阵物化优先；Snapshot 同期交付还是独立小任务；V2 Pack 的保留范围和旧库行为。用户不必先懂内部存储术语，应按实际使用场景确认。
3. **实际调用链**：对 search/basket、root lease/soft delete、pack、结果展示/删除、恢复逐条验证；给出最小文件格式及提交状态机、具体失败行为和测试证据。若缺少某种稳定变更标记，只为真实消费者补足。不要为此引入新权威、无证据迁移或改动科研算法。

设计审查尚未运行；本 Draft 只给出证据和待收敛的推荐方案。通过独立 reviewer、用户确认和所需合同更新后才实施。不得使用真实生产库作为验收对象；不推进 Task 7/11/12。
