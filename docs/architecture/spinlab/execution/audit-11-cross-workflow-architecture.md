# 审计 B：跨 Workflow 架构共性审计（任务 11 的输入材料）

对应任务：[brief-11](brief-11-v2-migration.md) / [design-11](design-11-v2-migration-readiness.md)。本文是只读静态审计，不改 Swift、不运行 App、不读取真实 Library、没有跑测试。

基线：分支 `design/task11-v2-migration-readiness`（PR #247），工作树代码。路径均相对 `Sources/SpinLabApp/`，写作 `文件:行`。

产品前提（审计时作为判断标准）：

- V2 是同一个 Library 的架构升级，不存在两个长期并存的 Library。
- 不可再生的研究数据必须保住；可重算的分析产物（Plot、Analysis Pack）不要求历史兼容。
- 先建跨 Workflow 的公共数据能力，再逐个适配各 Workflow 的科学语义。
- 单机、单库、单写者。

证据口径：

- **E** = 读码确认，附 `文件:行`。
- **C** = 基于 E 的判断，可被反驳。
- **U** = 未确认，需要用户决定、真实数据或后续验证。

---

## 0. 结论速览

1. **原始文件解析层已经基本统一，不是主要问题。** 现有 4 种容器格式各只有 1 份原始读取实现：PPMS DAT、Zurich LVM、RSM 文本、IBW（E，§2.1）。上一轮（Phase 3c–3i）已经做完这件事。重复主要出现在“解析之后的解释层”：`I_rms` 推导、文件名温度正则、条件字符串解析各有 2–4 份拷贝（E，§5.1）。
2. **同一个 PPMS DAT，AHE / RT / XY 在三处各自硬编码列名和轴语义**，没有共享的“按物理量解析列”的一层（E，§3.1）。这就是“应该是一条管线，实际是三份解释”的具体位置。Zurich LVM 更突出：同一容器、无文件内表头，`col0` 在 IV 是电流、在 3ω 是磁场或温度、在 XY 是角度（E，§3.2）。
3. **V2 的资产层（Source / Dataset / Plot 的存储、修订、删除、崩溃恢复）基本与工作流无关**，AFM 之外的工作流可以直接用。写入接口 `ingestAsset(adapter:)` 接受任意 `AssetStandardizationAdapter`，一个 Source 可产出多个 Dataset（E，§4.3）。
4. **阻塞其他工作流复用的关键缺口，不在资产层，而在“测量上下文”：V2 完全没有地方记录用户在 Inbox 确认过的工作流、通道、测试条件和测量时间。**
   - V1 靠 `.spinlab.json` 侧车保存这些信息，Workbench 的所有检索、标题、图例、解析覆盖值（温度、device、shift）都读它。
   - V2 的 `assets` 表和 Source manifest 都没有这些字段，`applyV2` 也没有把它们传下去（E，§4.2）。
   - 结果是 V2 命中的 `conditions` 恒为空、`workflowID` 写死为 `"afm"`（E，`UseCases/SearchWorkflowMeasurementsUseCase.swift:110-112`）。这是各工作流迁移的共同前置，应最先补。
5. **PPMS 多通道文件与 K5 存在真实冲突。** V1 允许一份 PPMS 文件按 ch1/ch2/ch3 分别归属不同 Sample（每个目标一份拷贝加一份侧车，`RouteTarget.channels`）。V2 的 K5 规定一个 Source 恰好一个 Sample，V2 Inbox 现为单 Sample 确认。这需要用户决定（§9 D-B1），不应由实现者自行取舍。
6. **科学算法与 IO 的分离程度不一**。AFM 已是纯函数入口 `AFMPlotComputation.run`。其他工作流的拟合/提取函数多数作用于内存数组（`ThreeOmegaFitUseCase.process(file:)` 等），但上游 `Ingest*UseCase` 以带路径的 `WorkflowMeasurementSearchHit` 为输入，因此在“数据来源可替换”这一缝上还没有缝（C，§6）。AHE 和 3ω 的 Ingest 已有 `parseFile` 注入点，是现成的切入口。
7. **Plot / Analysis Pack 的 V2 能力对非 AFM 不可用**：Plot 资产层通用，但 `supportedPlotFormats` 只含 `afm_plot_v1`（E，`Library/Assets/LibraryAssetService+Plot.swift:46`）；V1 图写入全部被 V2 布局守卫拒绝；`AnalysisVault` 没有 V2 守卫但内容绑定路径（E，§7）。按“可重算不需历史兼容”原则，这些放在公共能力之后。
8. **最小公共能力只需 4 件事**：测量上下文落点、1 维表格标准 Dataset 编码、V2 命中泛化（含上下文）、工作流读入的数据来源缝。AFM 的自动出图、Plot 格式白名单泛化放在后面（§8）。

---

## 1. 现有 Workflow 清单（从代码枚举）

| Workflow | 代码入口 | 是否有 Workbench | 证据 |
|---|---|---|---|
| AFM | `WorkflowKey.afm`，`Features/Workbench/AFMWorkspaceStore.swift` | 有（单选） | `App/State/WorkbenchWorkflowKind.swift:12-35` |
| AHE | `ahe`，`AHEWorkspaceStore.swift` | 有（多选） | 同上 |
| RT | `RT`，`RTWorkspaceStore.swift` | 有 | 同上 |
| 3ω | `3w`，`ThreeOmegaWorkspaceStore*.swift` | 有 | 同上 |
| XY Rotation | `XY`，`XYRotationWorkspaceStore.swift` | 有 | 同上 |
| IV | `IV`，`IVWorkspaceStore.swift` | 有 | 同上 |
| RSM | `rsm`，`RSMWorkspaceStore.swift` | 有（单选） | 同上 |
| MR | `WorkflowKey.mr`，仅 Inbox 规则 | **无**（`workflowKind(for:)` 返回 nil，走 `NotImplementedWorkflowView`） | `App/State/WorkbenchFeatureStore.swift:236-245`、`Features/Workbench/WorkflowWorkspaceRegistry.swift:41` |

补充（E）：

- 默认 `config/workflow.json` 只有 `MR / ahe / 3w / RT / XY / IV / afm`，**没有 `rsm`**。RSM 的默认 workflow.json 缺位，是否在用户真实规则里启用属于 U。
- `WorkflowKey.legacyKind`（`Domain/Workflow/WorkflowKey.swift:34-47`）把 MR、IV、RT 都映射到旧 `.amrPhe`，说明旧领域模型的工作流分类已不能区分这几个。这条路径只在 import 管线边界使用，不影响本审计结论。

---

## 2. 逐层审计

### 2.1 第 1 层：文件格式解析

| 容器格式 | 读取实现（唯一） | 使用者 | 产出 | 编码 | 异常行策略 |
|---|---|---|---|---|---|
| PPMS DAT | `UseCases/PPMSDATLoader.swift:26`（`loadRawTable` :61、`load` :141） | AHE `IngestAHESelectionsUseCase.swift:8`；RT `RTPPMSDatParser.swift:67`；XY-DAT `XYRotationDATParser.swift:68` | `LoadedMeasurement`（`format: .ppmsDAT`）或字符串表 | UTF-8，失败回退 Latin-1（:62-70） | 补齐/截断 + `MeasurementDiagnostic`（:115-131） |
| Zurich LVM | `UseCases/ZurichLVMLoader.swift:25`（`load` :60） | IV `IVLVMParser.swift:64`；3ω `ThreeOmegaLVMParser.swift:101`；XY-LVM `XYRotationLVMParser.swift:77`；RT-LVM 经 3ω 解析器（`AnalyzeRTWorkflowUseCase.swift:~159-175`） | `LoadedMeasurement`（`.zurichLVM`），10 或 11 个位置列，无表头 | **仅 UTF-8**（:61） | 字段不足的行**静默丢弃**，`diagnostics` 恒为 `[]`（:117、:145） |
| RSM 文本 | `UseCases/RSMTextLoader.swift:28`（`load` :51） | `RSMWorkspaceStore.swift:378,558` → `RSMDataParser.interpret` | `LoadedMeasurement`（H/K/L/detector 4 列）→ `CanonicalRSMDataset` | 仅 UTF-8（:51） | 任一异常行**整体抛错** |
| IBW（AFM） | `AFM/IBW/IBWReader.swift:60`；`AFMInputAdapter.swift:25` | AFM Workbench、`AFMIBWStandardizationAdapter`（`AFM/AFMDatasetCodec.swift:200`） | `CanonicalAFMDataset`（**不经过** `LoadedMeasurement`） | 二进制 | 类型化错误，全拒绝 |

判断：

- **C**：解析层没有重复实现，不需要重写。`LoadedMeasurement`（`Domain/Measurement/LoadedMeasurement.swift:22`）已经是三种文本格式共用的一维“列集合”形态，字段包括 `values`、`rawLabel`、`sourceUnit`、`physicalQuantityID`、`diagnostics`。
- **C**：三个文本加载器的容错策略和编码处理彼此不一致（PPMS 容忍并报告，LVM 静默丢弃，RSM 整体拒绝；只有 PPMS 有 Latin-1 回退）。这不阻塞迁移，但标准化时必须明确“忠实记录什么”。K7/K13 要求标准化忠实、损坏不当作不存在：LVM 的静默丢行属于无声改写，进入 V2 前应至少产出诊断（U：是否对已入库的旧数据有行为影响，需 11B 夹具对比）。
- **E**：`MeasurementFileFormat` 的注释写着“只有 `.zurichLVM` 被产出”（`Domain/Measurement/MeasurementFileFormat.swift:4-7`），已过时（PPMS、RSM 加载器已产出对应枚举值）。小问题，不影响结论。
- **E**：`LoadedMeasurement` / `MeasurementColumn` / `PhysicalQuantityUnitTag` 都不是 `Codable`（`Domain/Measurement/*.swift`，`PhysicalQuantityUnitTag.swift:19`），且文档明确“never persisted verbatim”（`LoadedMeasurement.swift:11`）。这是做标准 Dataset 编码时要补的点（§8 C2）。

### 2.2 第 2 层：语义映射（扫描轴、物理量、单位、通道、测量条件）

#### 2.2.1 PPMS DAT：AHE / RT / XY 并排（深度对比）

同一容器、同一表头约定（`Comment,<列名...>`），三处各自决定列含义（E）：

| 维度 | AHE | RT | XY Rotation（.dat） |
|---|---|---|---|
| 扫描轴（x） | `"Magnetic Field (Oe)"`，字面量 `AHEAxisDetector.swift:19`，使用于 `IngestAHESelectionsUseCase.swift:72` | `"Temperature (K)"`，字面量 `RTPPMSDatParser.swift:78` | `"Sample Position (deg)"`，`XYRotationDATParser.swift:81-86` |
| 信号（y） | `"Bridge N Resistance (Ohms)"`，N 来自侧车通道（`AHEAxisDetector.swift:38`；`IngestAHESelectionsUseCase.swift:61`） | 同写法，N 来自侧车通道（`RTPPMSDatParser.swift:84`） | **固定** Bridge 2 = Rxx、Bridge 3 = Rxy（可选）（`XYRotationDATParser.swift:88-97`），不看侧车通道 |
| 通道含义 | `ch1/2/3 → bridge 1/2/3`，共享映射 `Domain/Measurement/PPMSBridgeChannelMapping.swift:11` | 同一共享映射 | 无通道概念，写死 |
| 列匹配 | 精确字符串（`rawLabel ==`，`AHEAxisDetector.swift:50,71`） | 精确（`firstIndex(of:)`） | **大小写不敏感**（`_findColumn`，`XYRotationDATParser.swift:156-162`） |
| 列有效性 | 要求列内至少一个非 NaN（`hasActiveColumn`，:70-73） | 只检查列存在（注释特别声明保留旧行为，`RTPPMSDatParser.swift:12-18`） | 只检查存在；Bridge 3 存在则要求行内可解析 |
| 坏行 | NaN 对剔除（`pairedValues`，:56-62） | 丢行并报警（`RTPPMSDatParser.swift:98-107`） | 丢行（无警告，`XYRotationDATParser.swift:109-124`） |
| 单位处理 | Oe→T，经 `WorkbenchMagneticFieldUnitConverter`（`IngestAHESelectionsUseCase.swift:77`） | 无（K、Ω 原样） | 无 |
| 温度来源 | 不读文件，取侧车条件做图例（:86） | 作 x 轴 | 覆盖值 → 数据列均值 → 文件名正则（:130-140） |
| 产出类型 | `WorkbenchPlotSeries` | `RTAnalysisResult` | `XYRotationAngleSweep` |

共享的部分只有：`PPMSDATLoader` 本体、`classify`（只给 `Temperature (K)` 与 `Magnetic Field (Oe)` 打类型，其余列保留 `.raw(unit)`，`PPMSDATLoader.swift:179-197`）、桥号映射、`MeasurementDiagnostic.asWorkflowWarning`。

**C**：三个工作流的“列选择”本质上是同一个问题：在一份 PPMS 列集合里按物理量选 x 轴、选 y 信号，再按通道选桥号。目前它被写成三份字面量。这一层不需要框架，只需要一处“按物理量/通道从 `LoadedMeasurement` 解析列”的小函数，三者共用。

**U**：用户实际的 PPMS 文件里，扫描轴列是否可靠对应工作流（AHE 文件一定是 Field 扫描，RT 一定是 Temperature 扫描）？目前由用户在 Inbox 确认的工作流决定，而不是由文件自描述。若同一个文件被用户同时当作 AHE 和 RT 使用，标准 Dataset 应该只存一份（K7：连续扫描轴不拆分）。

#### 2.2.2 Zurich LVM：IV / 3ω / XY / RT-LVM 并排（深度对比）

容器：第 2 行 `Tableau:` 标记，之后制表符分隔数值，**无表头**，10 或 11 列（`UseCases/ZurichLVMLoader.swift:10-19,45-50`）。文件自身不提供任何列含义，所以含义完全由“用户确认的工作流”赋予（C）。

| 工作流 | col0 | col1/2 | col5/6 | col9 | col10 | 其他规则 | 证据 |
|---|---|---|---|---|---|---|---|
| IV | 电流（A，峰值） | ch1 X/Y | ch2 X/Y | `1st R_H` 原始参照 | `Frequency_after` | 必须 11 列，缺列判失败；温度取侧车覆盖值否则文件名，二者都无则拒绝 | `UseCases/IVLVMParser.swift:11-23,57-59,100-106` |
| 3ω | **fieldSweep 时是磁场（Oe）；rtSweep 时是温度（K）** | 1ω 电压 | 3ω 电压 | 预计算 `R_H` | `f_ref` | 文件类型由侧车工作流 ID 或文件名 `_RT_` 判定；`I_rms = mean(col1/col9)`（前 20 个有效行） | `ThreeOmegaLVMParser.swift:16-30,61-74,127-139,190-203` |
| XY-LVM | 角度（deg） | 1ω 电压 | 2ω 电压 | `Rxx` | `f_ref` | `Rxy = col5 / I_rms`；`I_rms` 推导与 3ω 相同；温度取覆盖值否则文件名 | `XYRotationLVMParser.swift:12-24,100-106,133-134,155-167,179-188` |
| RT-LVM | 温度 | — | — | `Rxx` | — | 直接复用 3ω 解析器（`kindOverride: .rtSweep`） | `AnalyzeRTWorkflowUseCase.swift:~165-175` |

**C**：

- 同一容器、同一位置，`col0` 在不同工作流里含义不同，加载器按设计从不赋语义（`ZurichLVMLoader.swift:15-19`）。这说明 **LVM 的标准 Dataset 只能忠实存“位置列”，语义必须由入库时用户确认的工作流（或解释方案）一并记录**。否则 V2 的 Dataset 读回时不知道 col0 是什么，只能重新猜，违反 K12。
- 解释层（IV/3ω/XY 的位置→命名映射）本身是工作流的科学语义，应留在各工作流，不应抽象成通用框架。

#### 2.2.3 测量条件的传递（各工作流如何拿到温度、device、角度等）

- 条件来自 Inbox 确认时写入的侧车：`SpinLabFileSidecar.ruleSnapshot.fields.conditions` + `userOverrides`，取有效值用 `effectiveConditions`（`Domain/Sidecar/SpinLabFileSidecar.swift:~190-205`）。条件值是**带单位的自由字符串**（如 `"5K"`、`"90shift"`），键是规则里的 ID（`temperature`、`field`、`current`、`device`、自定义如 `shift`），默认字段见 `Import/Rules/ConditionFieldCatalog.swift`。
- 每个工作流的 Ingest 自己把字符串解析成数值：IV `IngestIVSelectionsUseCase.swift:99-104`，XY `IngestXYRotationSelectionsUseCase.swift:100-106`（另有 `shift` 的前导数字解析 :~110），3ω `IngestThreeOmegaSelectionsUseCase.swift:163-170`，RT `AnalyzeRTWorkflowUseCase.swift:224-231`（E，共 4 份，写法略有差异：有的去掉大小写 K，有的只去掉大写 K）。
- 仓库**已经有**类型化的统一入口：`Domain/Sidecar/SidecarConditionNormalizer.swift:20`（`<数字><单位>` → 规范单位数值）和 `SidecarPhysicalQuantityMapping`（条件 ID → `PhysicalQuantityID`）。在 `Sources` 内除 `Domain/Sidecar` 自身外**没有调用方**（grep 仅命中定义文件）。属于“已有能力未被消费”。

### 2.3 第 3 层：标准 Dataset 形态与公共合同

#### 2.3.1 AFM 已建成的 V2 合同（E）

- 存储记录：SQLite（`Library/Assets/LibraryAssetDatabase.swift:246-326`）四张表：`schema_meta`、`assets`（`asset_id/kind/format/status/storage_rel_path/current_revision/sha256/byte_size/original_filename/live_state/files_json`）、`sample_asset_links`（仅 Source 有 Sample 归属，触发器强制）、`asset_dependencies`（`dataset_source` / `live_input` / `snapshot_input`，带 `signal_locator`）、`asset_operations`。
- 适配器协议（工作流无关）：`AssetStandardizationAdapter.standardize(sourceFileURL:) -> StandardizedDatasetPayload`，`DatasetPayloadCodec.decode(files:)`（`Library/Assets/LibraryAssetModels.swift:36-45`）。一个 Source 可对应多个 `StandardizedDatasetItem`，每项带 `signalLocators`（:18-23）。
- AFM 编码：`manifest.json` + `matrices.bin`（Float64 小端，NaN/Inf 无损，带 SHA-256），格式 `afm_canonical_v1`（`AFM/AFMDatasetCodec.swift:9-65,118-121`）。
- Source 存原字节 `payload.bin` + `manifest.json`（`Library/Assets/LibraryAssetService.swift:230-237,~320-330`；`SourceManifest` 为 `private`，字段固定为 format/原文件名/原路径/大小/SHA/时间）。

#### 2.3.2 V1 遗留形态

| 遗留物 | 内容 | 权威/可重算 | 证据 |
|---|---|---|---|
| 原始文件 | `<sample>/measurements/<workflow>/<文件>`（`measurements/General` 为无工作流） | 不可再生 | `UseCases/LibraryDestinationSubpath.swift:4-13` |
| `<文件>.spinlab.json` 侧车 | 用户确认的工作流、**通道→样品归属**、条件与手动覆盖、`sampleKey`、测量时间戳 | **用户确认类信息，不可由文件内容重建**（C） | `Domain/Sidecar/SpinLabFileSidecar.swift:40-72` |
| `measurement_data.json` | 标量指标账本（`WorkbenchMetricRecord`：sampleKey、metric、value、conditions、`overrideInfo`），目前只有 AHE 写入 | 多数可重算；含手动覆盖 `overrideInfo` 的记录属“用户判断” | `Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift:202-214,415`；`UseCases/SaveActiveChartToLibraryUseCase.swift:95-118`；仅 `AHEWorkspaceStore.swift:746` 产出指标 |
| `measurement_sets.json` | 用户建的文件分组（只存文件名） | UI 组织，可再生成但属用户整理 | `Library/Domain/LibraryDomainModels.swift:188-198`；`LibraryStore+MeasurementSets.swift` |
| 图 + `results_index.json` + `measurement_plot_index.json` | PNG、manifest（`inputFiles` 为路径） | 可重算 | `UseCases/PersistChartArtifactUseCase.swift:~58,106-112` |
| Analysis Pack | 工作流自定义的 config/result JSON 块；`filePaths`、`sampleKeys`、路径指纹 | 可重算 | `Domain/AnalysisPack.swift:6-31`；`App/State/AnalysisVault.swift:8,23-32` |

#### 2.3.3 各工作流解析之后的内存形态（E）

| 工作流 | 内存形态 | 来自 `LoadedMeasurement`？ |
|---|---|---|
| AHE | `WorkbenchPlotSeries`（label/x/y/metadata） | 是（PPMS，解析内联在 Ingest 中） |
| RT | `RTAnalysisResult`（温度、Rxx 数组） | 是（PPMS）/ 否（LVM 走 `ThreeOmegaLVMFile`） |
| 3ω | `ThreeOmegaLVMFile`（col0/col1/col5/col9 + `iRms`） | 是（LVM） |
| XY | `XYRotationAngleSweep` | 是 |
| IV | `IVSweep`（11 个数组） | 是 |
| RSM | `CanonicalRSMDataset`（点列表） | 是 |
| AFM | `CanonicalAFMDataset`（2D 矩阵 + 坐标） | **否** |

**C**：除 AFM 外，6 个工作流的“原始数据”都是一维表格列集合（`LoadedMeasurement` 同构），只是各自在解释阶段再转换成专用结构。**因此一个“1 维表格标准 Dataset”编码就能覆盖其余全部工作流的标准化需求**；各工作流专用结构保持不变，作为解释层的输出。AFM 的 2D 矩阵编码继续保留。

#### 2.3.4 V2 的上下文缺口（E，关键）

- `assets` 表和 `SourceManifest` 均无“条件/通道/测量时间/确认工作流”字段（上文）。
- `applyV2` 只用 `draft.v2TargetSampleUID`、操作 ID、复用 SourceID 调 `ingestAsset`，不传条件与通道（`App/InboxArchiveApplyService.swift:~480-545`）。
- V2 命中：`workflowID: "afm"`、`workflowCanonicalID: "afm"`、`conditions: [:]`、`appliedAt: .distantPast`（`UseCases/SearchWorkflowMeasurementsUseCase.swift:107-118`）。数字检索对 V2 命中被显式关闭（:136）。
- V2 没有测量时间戳记录；V1 靠 `MeasurementTimestampResolver` 写入侧车（`InboxArchiveApplyService.swift:~125`，`Domain/Sidecar/SidecarMeasurementTimestamp.swift`）。

### 2.4 第 4 层：Library 入库、查询、Workbench 读取接口

#### 2.4.1 Inbox 路由与 Apply

| 环节 | V1 | V2 | 证据 |
|---|---|---|---|
| 工作流判定 | 规则本 `workflow.json` / 文件名规则（`Import/Rules/*`、`Import/Parse/FilenameRuleParser.swift`） | 同 | `config/workflow.json` |
| 目标 Sample | `RouteTarget(sampleId, channels)`，**同一文件可按通道分别归属多个 Sample** | **单 Sample 确认**（`v2SingleSampleDepositRows`） | `Domain/Models.swift:90-93`；`Features/Inbox/InboxSelectionWorkbenchPanel.swift:162,357` |
| 复制原文件 | 每个目标复制一份到 `<drawer>/measurements/<workflow>/`，并配一份侧车（成对写入，缺一报错） | 原字节入 `storage/<src>/payload.bin` | `InboxArchiveApplyService.swift:~125-185` / `LibraryAssetService.swift:~320-330` |
| 适配器选择 | 无（V1 不标准化） | `standardizationAdapter(forWorkflowID:)` 仅 `"afm"` 返回 `AFMIBWStandardizationAdapter`，其余 `nil` → `LibraryLayoutError.v2UnsupportedOperation` | `InboxArchiveApplyService.swift:57-66,494-497` |
| 是否可 Apply | 路由裁决 `libraryMatched` | 适配器非空且目标 UID 有效 | `InboxSelectionWorkbenchPanel.swift:125-130`；`App/ApplyCoordinator.swift:148-170` |
| 去重/幂等 | 目标已存在则跳过 | `operationID` 幂等；`reuseSourceID` 仅同 Sample | `LibraryAssetService.swift:257-325` |

**E**：`ingestAsset` 本身不是 AFM 专用：入参是任意适配器；`payload.datasets` 可多个（:293-295、:~345-365）；SHA 不要求全库唯一，同字节第二次可作为新 Source 入库（`reuseSourceID` 只在显式复用时校验，:299-318）。

#### 2.4.2 查询与 Workbench 读取

- V1：`SearchWorkflowMeasurementsUseCase.execute` 递归扫描全库侧车（`LibrarySidecarBulkReader`），由侧车拼出 `WorkflowMeasurementSearchHit`，包含路径、工作流、条件、通道（`:48-104`，`buildHit` :150-）。命中 ID 暂用侧车路径（注释标明“TEMPORARY IDENTITY DEBT”，`Domain/WorkflowSearchModels.swift:~118-122`）。
- V2：在 V1 扫描后追加 AFM 标准 Dataset 命中（`:94-103`），`standardDatasetHits` 固定调用 `listAnalysisDatasets(format: AFMDatasetCodec.format)`（:131）。`WorkbenchInputRef` 只有一个 case `.datasetV2`（`Domain/WorkflowSearchModels.swift:~96-110`）。
- 读取：**只有 AFM Workbench 有 `inputRef` 分支**（`Features/Workbench/AFMWorkspaceStore.swift:504`）。其余工作流的 Ingest 一律读 `hit.measurementFilePath` / `sourceFilePath`（`IngestIVSelectionsUseCase.swift:25`，`IngestXYRotationSelectionsUseCase.swift:~27`，`AnalyzeRTWorkflowUseCase.swift:77`，`IngestAHESelectionsUseCase.swift:34`），在 V2 下 `measurementFilePath` 为空。
- 其他 V2 读侧已就绪：`loadDatasetForAnalysis<Codec>`（泛型，`LibraryAssetService+Analysis.swift:41-72`）、`listAnalysisDatasets(format:)`（参数化，:75-114）、命中行显示 `WorkflowHitRow.swift:112`。

**C**：读侧资产函数已经泛型化，缺的是“命中携带上下文”和“工作流 Ingest 的数据来源缝”。

### 2.5 第 5 层：科学分析算法与 IO/UI 分离

| 工作流 | 纯计算入口（输入） | IO/解释与计算混合处 | 评价 |
|---|---|---|---|
| AFM | `AFMPlotComputation.run(dataset:configuration:display:)`，不读 UI 状态、不读文件（`AFM/AFMPlotComputation.swift:5-9,78-95`）；`AFMProcessingPipeline` | 无 | 已达到“无头可调用”，被自动出图直接使用（`AFM/Automation/AFMAutoPlotService.swift:~22-30`） |
| AHE | `AHEBackgroundCorrectionUseCase.correctedSeries(_:)`、`ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from:)`、`BuildAHEResultCandidatesUseCase`（均作用于内存 series） | `IngestAHESelectionsUseCase` 读文件 + 列解析 + 单位转换；`AHEWorkspaceStore.swift:746` 在 Store 内调度指标提取 | 算法可分离，入口是“series”这一通用 x/y 数组形态，天然适合 |
| 3ω | `ThreeOmegaFitUseCase.process(file:)`（`ThreeOmegaFitUseCase.swift:27`），`ThreeOmegaScalingUseCase` | `ThreeOmegaLVMParser` 内含 `I_rms` 推导（解释层） | 算法与 IO 已分；输入类型是 3ω 专用 `ThreeOmegaLVMFile` |
| RT | `AnalyzeRTWorkflowUseCase`（读文件 + 配对排序 + 结果一体） | 同一函数内做 IO、解析、排序 | 混合度最高；但计算很薄（升序配对） |
| XY / IV | 解析器内含派生（`Rxy = col5/I_rms`），拟合在 `Workbench/Modules/AngularFit`、`PowerLawFit`（`*Input` 结构体入参） | `IngestXY/IVSelectionsUseCase` | 拟合模块已有清晰 Input/Result 结构 |
| RSM | `RSMHeatmapPayloadBuilder.build` + `HeatmapRenderPipeline`（共享热图管线，与 AFM 共用） | `RSMWorkspaceStore` 内读文件 | 渲染共用，数据入口为 `CanonicalRSMDataset` |

**C**：

- 各工作流的**计算核心大多已与 IO 分开**，输入是内存数组类型。要无头复用，需要的是“`Dataset` → 该工作流内存输入”的一层转换，而不是重写算法。
- **U**：各 `*WorkspaceStore`（RT 589 行、IV 766 行、XY 757 行、AHE 868 行）内部的编排是否夹带科学判断，本次未逐行核查。

### 2.6 第 6 层：Plot / Result / Analysis Pack 持久化

| 产物 | V1 路径 | V2 路径 | 工作流相关性 |
|---|---|---|---|
| 通用图（AHE/3ω/RT/IV/XY） | `SaveActiveChartToLibraryUseCase` → `PersistChartArtifactUseCase`（`:33` 起 `requireV1ArtifactWriteAllowed`，V2 抛 `v2UnsupportedOperation`） | **无** | 图清单 `inputFiles` 来自 `series.sourceRef`（路径） |
| RSM / AFM 图（V1） | `SaveRSMChartToLibraryUseCase`（`:67` 守卫）、`SaveAFMChartToLibraryUseCase`（`:72` 守卫） | AFM 有正式 Plot 资产；RSM 无 | 各自专用 |
| 正式 Plot 资产（V2） | — | `LibraryAssetService+Plot.swift`：`publishPlot/updatePlot`，输入 `PlotInputRef(datasetID, channelID, revision)`（:11-15），依赖行 `live_input`；`supportedPlotFormats = ["afm_plot_v1"]`（:46）；`validatePlotRequest`（:469-476） | 存储层通用，**格式白名单与摘要读取按 AFM 写死**：`FormalPlotLibrary.summaries` 固定 `AFMDatasetCodec.format`、`AFMPlotCodec`、`workflowLabel: "AFM"`（`Library/Assets/FormalPlotCandidates.swift:119-146`） |
| Plot 候选排序/选择器 | — | `FormalPlotRanker` 只用 datasetID、sample、`workflowLabel` 字符串（`FormalPlotCandidates.swift:62-98`） | 通用 |
| 自动出图 | — | 持久意图/回执通用（`LibraryAssetService+AutoPlot.swift`），但预设文件 `_spinlab/afm_auto_plot_preset.json`、操作前缀 `auto-afm-`、`AFMAutoPlotPreset` 为 AFM 命名（:19,80） | AFM 专用 |
| 标量指标账本 | `PersistMeasurementDataUseCase`（`:52` 守卫），仅 AHE 写入 | 无；V2 的权威是 Sample Result | AHE |
| Sample Result 候选 | — | `SampleResultCandidate`（`Domain/SampleResultCandidate.swift:6-41`）形态通用，**目前仅 AHE 产出**（`AHEWorkspaceStore+ResultCandidates.swift`），带 `sourceSampleKey`、`sourceBatchID`（V1 身份） | 通用壳，AHE 首个消费者（Task 12） |
| Analysis Pack | `AnalysisVault`：`<root>/_spinlab/analysis_packs/<workflowID>/<uuid>.json`，内含路径/sampleKey/路径指纹；`AnalysisPackProviding` 被全部 7 个 Workbench Store 实现 | `AnalysisVault._writeToDisk` 只检查写租约，**没有 V2 布局守卫**（`AnalysisVault.swift:~95-110`） | 外壳通用（config/result 为工作流自定义 Data 块） |

**C**：

- V2 Plot 的存储层、修订、陈旧标记、依赖闭包、删除保护全部可复用；非 AFM 要用它只缺“格式白名单 + 摘要读取 + 编码”。
- Pack 内容是路径导向（`filePaths`、路径指纹）。按产品原则（可重算，不要求历史兼容），迁移时不迁移 Pack，非 AFM 工作流在 V2 有输入后再按 `datasetID` 重新保存即可（需要在 Pack 层增加输入标识，U，非最小项）。
- **E**：V2 下 Pack 写入没有守卫，但 V2 中非 AFM 无输入可分析，实际无法触发；一旦非 AFM 接入 V2，Pack 里的路径指纹就会失效，须同时处理。

---

## 3. 跨 Workflow 能力矩阵

图例：✔ 已具备且可复用；◐ 部分/需小改；✖ 缺失；— 不适用；? 未确认。

| Workflow | L1 解析 | L2 语义映射（轴/量/单位/通道/条件） | L3 V2 标准 Dataset | L4a V2 Inbox 入库 | L4b V2 命中与读取 | L5 算法与 IO 分离 | L6 Plot/Pack V2 |
|---|---|---|---|---|---|---|---|
| **AFM** | ✔ `IBWReader`（AFM/IBW/IBWReader.swift:60） | ✔ 通道由 IBW 自描述（`AFMInputAdapter.swift:46-82`），`AFMChannelResolver` 仅作默认展示 | ✔ `afm_canonical_v1`（AFMDatasetCodec.swift:12） | ✔ 单 Sample；**不记录条件/时间/确认工作流**（InboxArchiveApplyService.swift:~500-545） | ✔ `inputRef` 分支（AFMWorkspaceStore.swift:504）；命中无条件（Search…:107-118） | ✔ `AFMPlotComputation.run` | ✔ `afm_plot_v1`；自动出图（仅 AFM） |
| **AHE** | ✔ PPMS（IngestAHESelectionsUseCase.swift:8） | ◐ 列名字面量在 `AHEAxisDetector.swift:19,38`；通道→桥由共享映射；条件字符串由侧车提供 | ✖ | ✖ 无适配器（Apply…:57-66） | ✖ 读 `sourceFilePath`（Ingest…:34） | ◐ 纯函数作用于 series；Store 内调度（AHEWorkspaceStore.swift:746） | ✖ 图/账本 V1 守卫；Result 候选已有，目标按 V1 身份 |
| **RT** | ✔ PPMS + LVM（经 3ω 解析器） | ◐ `"Temperature (K)"` 字面量（RTPPMSDatParser.swift:78）；LVM 借 3ω `rtSweep` | ✖ | ✖ | ✖ 读 `measurementFilePath`（AnalyzeRT…:77） | ✖ 读文件与计算同函数（AnalyzeRT…:76-） | ✖ |
| **3ω** | ✔ LVM（ThreeOmegaLVMParser.swift:101） | ◐ 位置映射在解析器；文件类型由侧车/文件名；`I_rms` 解释层重复（:190） | ✖ | ✖ | ✖ | ✔ `ThreeOmegaFitUseCase.process(file:)`；有 `parseFile` 注入点（Ingest…:22-27） | ✖；Pack 含 RT 文件路径（`AnalysisPack.swift:15-19`） |
| **XY** | ✔ PPMS + LVM | ◐ 桥 2/3 写死（XYRotationDATParser.swift:88-97）；`Rxy`/`I_rms` 在解析器；列匹配大小写不敏感与其他不一致 | ✖ | ✖ | ✖ | ◐ 拟合模块有 Input 结构；解析内含派生 | ✖ |
| **IV** | ✔ LVM（IVLVMParser.swift:64） | ◐ 11 列位置映射在解析器；条件解析与 `device/angle/field` 回退在 Ingest（IngestIV…:99-177） | ✖ | ✖ | ✖ | ◐ 拟合模块 Input/Result；渲染含 `IVPlotRenderer` | ✖ |
| **RSM** | ✔ RSM 文本（RSMTextLoader.swift:28） | ✔ 列由文法定义（H/K/L 自识别，RSMTextLoader.swift:14-20） | ✖ | ✖ | ✖ | ✔ 共享热图管线 | ✖（V1 守卫 SaveRSM…:67） |
| **MR** | — 无加载器 | — 无 Workbench | — | ✖（Apply 对 `mr` 无适配器） | — | — | — |

读法：

- L1 全部 ✔，说明“先建公共数据能力”的第一步（统一加载器）已经完成，不需要再改。
- L3 到 L6 的空白几乎对所有非 AFM 工作流相同，这正是“先做公共能力”的依据：缺口集中在同几处，而不是每个工作流各缺一套。
- L2 全是 ◐：语义映射是各工作流的科学语义，应保留在工作流内，只对“列解析”“条件解析”两处小重复做收敛（§5.1）。

---

## 4. AFM 已建能力的复用评估

### 4.1 可直接复用（E）

| 能力 | 证据 | 说明 |
|---|---|---|
| 入库事务（暂存→校验→提交→崩溃恢复） | `LibraryAssetService.swift:257-420` | 接受任意 `AssetStandardizationAdapter` |
| 一个 Source 多个 Dataset | `LibraryAssetModels.swift:18-34`；`LibraryAssetService.swift:293-295` | 为“同文件含多个独立固定条件”预留（K7） |
| Dataset 修订、过期标记、删除闭包、Trash、恢复 | `+Revise.swift`、`+Deletion.swift` | 与格式无关 |
| 泛型读取 | `loadDatasetForAnalysis<Codec>`（`+Analysis.swift:41`）、`listAnalysisDatasets(format:)`（:75） | 格式作参数 |
| Plot 资产存储 | `+Plot.swift` | 仅白名单限制 |
| Plot 选择器/排序 | `FormalPlotCandidates.swift:62-98` | 只用 ID 与字符串标签 |
| 命中引用与行显示 | `WorkbenchInputRef.datasetV2`、`WorkflowHitRow.swift:112`、`WorkbenchSelectionRuntime.swift:42` | 不含 AFM 专有字段 |
| 单写者与租约 | `Storage/LibraryWriteLease.swift`；`requireWritable` | 通用 |

### 4.2 AFM 专用、复用前必须泛化或绕开（E）

| 位置 | 内容 | 阻塞程度 |
|---|---|---|
| `InboxArchiveApplyService.swift:57-66` | 适配器表只有 `"afm"` | 加一项即可，不阻塞设计 |
| `SearchWorkflowMeasurementsUseCase.swift:107-148` | V2 命中写死 `afm`、无条件、仅 AFM 格式 | **高**（§2.3.4） |
| `LibraryAssetService.swift`（`SourceManifest` private，无上下文）+ `assets` 表 | 无测量上下文落点 | **高** |
| `InboxSelectionWorkbenchPanel.swift:162,357` | V2 单 Sample 确认，无通道映射 | **高**（D-B1） |
| `+Plot.swift:46`、`FormalPlotCandidates.swift:119-146` | Plot 格式白名单、摘要读取按 AFM | 中（后置） |
| `PlotInputRef.channelID` 语义 | 对 AFM 是通道 ID；对 1 维表格需定义“信号定位符” | 低（可沿用字符串，约定即可） |
| `+AutoPlot.swift:19,80`、`AFMAutoPlotPreset` | 自动出图预设与前缀 AFM 命名 | 低（非最小项，可不动） |
| `AFMDatasetCodec` | 2D 矩阵编码 | 不阻塞（1 维另建，不改 AFM） |

### 4.3 复用度判断（C）

- **存储/事务层复用度约 90%**：缺的是上下文落点和 1 维编码，不是事务机制。
- **读取/检索层需要泛化一处**（`standardDatasetHits`），并让命中带上下文。
- **Workbench 读入层需逐工作流加一个来源缝**；AFM 的 `_runAnalysis` 分支（`AFMWorkspaceStore.swift:504-522`）就是参照实现。
- **自动出图只对 AFM 有意义**：其触发条件是 Apply 后按预设出图。其他工作流需要产品先决定“自动出什么图”（D-B3），不应预先抽象。

---

## 5. 重复清单与已有能力

### 5.1 重复（E，需收敛或至少不再扩散）

| 重复项 | 位置（文件:行） | 差异 |
|---|---|---|
| `I_rms` 推导（前 N 个有效行 `col1/col9` 均值） | `UseCases/ThreeOmegaLVMParser.swift:190-203`；`UseCases/XYRotationLVMParser.swift:155-167` | 逐行相同 |
| 文件名温度正则（`(?:^|[_\s])(\d+(?:\.\d+)?)\s*K(?:[_\s]|$)`） | `IVLVMParser.swift:165-173`；`XYRotationDATParser.swift:165-173`；`XYRotationLVMParser.swift:179-188` | 相同 |
| 文件名温度正则（`T_<n>\s*K`） | `ThreeOmegaLVMParser.swift:215-223` | 另一种写法（3ω 特有命名约定，U：是否应并入） |
| 条件字符串→温度 K 数值 | `IngestIVSelectionsUseCase.swift:99-104`；`IngestXYRotationSelectionsUseCase.swift:100-106`；`IngestThreeOmegaSelectionsUseCase.swift:163-170`；`AnalyzeRTWorkflowUseCase.swift:224-231` | 4 份；大小写处理略不同 |
| PPMS 列名字面量 `"Bridge N Resistance (Ohms)"` / `"Temperature (K)"` | `AHEAxisDetector.swift:38`；`RTPPMSDatParser.swift:78,84`；`XYRotationDATParser.swift:89,96,100` | 精确 vs 大小写不敏感匹配不一致 |
| 把条件写入标题 token `"测试温度"` | `hit.conditions["temperature"]` 在 AHE/3ω/XY/IV/RT/热图共 14 处（grep 命中于 `Features/Workbench/*Store*.swift`、`HeatmapTitleResolution.swift:21`） | 同形重复，属 UI 标题层，不在本次最小项内 |
| 保存流程三份 | `WorkbenchSaveCoordinating.swift:29-95`（`executeRSMSave/executeAFMSave/executeSave` 三个几乎相同的 Task 体） | 同形，非数据层问题 |
| 单位换算（Oe→T） | 已收敛到 `WorkbenchMagneticFieldUnitConverter`（IngestAHE:77） | 已处理，不重复 |
| 桥号映射 | 已收敛到 `PPMSBridgeChannelMapping`（:11） | 已处理 |

### 5.2 已有但未被消费的能力（E）

| 能力 | 位置 | 现状 |
|---|---|---|
| 条件字符串 → 规范单位数值 | `Domain/Sidecar/SidecarConditionNormalizer.swift:20` | `Sources` 内无调用方（除自身扩展） |
| 条件 ID ↔ 物理量 | `Domain/Sidecar/SidecarPhysicalQuantityMapping.swift:15` | 同上 |
| PPMS 列的类型化（温度、磁场） | `PPMSDATLoader.classify`（:179-197） | 只被 `load()` 路径使用（AHE）；RT/XY 走 `loadRawTable` 绕开 |
| 加载诊断 | `MeasurementDiagnostic`（`Domain/Measurement/MeasurementDiagnostic.swift:11`） | PPMS 使用；LVM 恒空 |
| `PhysicalQuantityID` 注册表 | `Domain/PhysicalQuantity/*` | 含 `deviceAngle`、`current`、`reciprocalH/K/L` 等；LVM 的 `col1/col5` 刻意未标（文档说明无合适枚举） |

### 5.3 真正需要新增的（C）

1. 测量上下文的 V2 落点（工作流、通道、条件、测量时间）。
2. 1 维表格标准 Dataset 的编码与两个容器适配器（PPMS DAT、Zurich LVM），以及 RSM 适配器（4 列表格）。
3. V2 命中的泛化（多格式、携带上下文）。
4. 工作流读入的“Dataset 来源”缝。
5. （后置）非 AFM 的 Plot 格式与摘要读取。

不需要新增：新的解析器、新的通用“Workflow 框架”、新的 Dataset 抽象层级。

---

## 6. 建议的公共能力（按顺序，最小）

### C1 测量上下文记录（最先；所有工作流的共同前置）

- 目的：把 V1 侧车里“用户确认过、文件内容推不出来”的信息在 V2 里保住：确认的工作流 ID、通道、条件有效值（含手动覆盖标记）、测量时间。
- 最小形态（建议，待实现设计确认）：随 Source 在入库提交时一起持久化的一份小 JSON，且可被批量查询（`listAnalysisDatasets` 当前强调“不解码矩阵、一次批量查询”，`+Analysis.swift:70-74`）。具体放 SQLite 列/表还是 Source 目录里的文件，**由实现设计决定**，但必须单一权威、随入库同一提交点落盘、随 Source 一起被删除闭包处理（K5/K6）。
- 为什么不放在 Dataset 格式里：同一 PPMS 文件被 AHE、RT 解释不同；上下文属于“这次入库用户确认了什么”，不属于数据本体。
- 约束：不得把“猜出来”的值当事实（K12）；条件保持用户确认的原字符串，不在入库时静默换算。
- 依赖：无。
- U：现有 V2 库的 `schema_version` 升级方式（`LibraryAssetDatabase.swift:235` 附近有版本检查），以及现实中是否已有 V2 库需要升级，未核实。

### C2 一维表格标准 Dataset 与两个容器适配器

- 编码（建议）：`manifest.json`（列的 `stableSourceKey`、`rawLabel`、`sourceColumnIndex`、`sourceUnit`、`physicalQuantityID`、诊断）+ 一个 Float64 小端二进制块（沿用 AFM 的做法：NaN 无损、带 SHA-256，参考 `AFMDatasetCodec.swift:84-122`）。需要把 `MeasurementColumn`/单位标签做成可编码，或用清单专用 DTO。
- 适配器：`ppms_dat`（包 `PPMSDATLoader.load`）、`zurich_lvm`（包 `ZurichLVMLoader.load`）、`rsm_text`（包 `RSMTextLoader.load`）。**只包现有加载器，不重写解析。**
- 忠实性：LVM 静默丢行、RSM 整体拒绝等既有行为，作为“忠实标准化”的一部分原样保留，并把诊断带入 manifest（避免无声改写）。
- 适配器选择：当前表按工作流 ID 键控（`InboxArchiveApplyService.swift:57`）。LVM 容器无法由文件决定语义，因此建议“按容器格式选适配器，工作流写入 C1 上下文”，而不是为每个工作流各写一个适配器。
- 依赖：C1（上下文需要一起提交）。
- 不要做：不要改 `LoadedMeasurement` 的定位，不要把各工作流的解释结构（`IVSweep` 等）持久化。

### C3 V2 命中泛化

- `standardDatasetHits`（`SearchWorkflowMeasurementsUseCase.swift:123-148`）遍历已注册的数据格式，而不是固定 `AFMDatasetCodec.format`；命中的 `workflowID`、`conditions`、`channels`、`appliedAt`/测量时间取自 C1。
- 这样现有的文本检索、数字检索（当前对 V2 关闭，:136）、标题 token、图例维度（`WorkbenchSeriesMetadataBuilder`，`Workbench/Modules/PlotSystem/Legend/WorkbenchSeriesMetadataBuilder.swift:29-30`）对 V2 数据立刻生效。
- 依赖：C1、C2。

### C4 解释层小收敛（可与 C2 并行；V1 也受益）

- 一处“按物理量/通道在 `LoadedMeasurement` 里选列”的小函数，替代 AHE/RT/XY 的三份字面量（解决 §3.1 的精确/大小写不敏感不一致）。
- 条件字符串解析统一使用现成的 `SidecarConditionNormalizer`；`I_rms` 推导与文件名温度正则各留一份。
- 注意：这不是为了“抽象”，是为了让 V1 路径与 V2 路径经过同一份解释函数，避免两条路径行为分叉。需要回归现有测试（`V3fPPMS…`、`V3gRT…`、`V3cZurich…`、`PR148…`）。
- 依赖：无（但应在各工作流适配前完成，否则会把重复复制到 V2 路径）。

### C5 工作流读入的数据来源缝

- 每个工作流的 Ingest 目前以“路径→解析”为入口；AHE 已有 `parseFile: (URL) throws -> LoadedMeasurement`（`IngestAHESelectionsUseCase.swift:8`），3ω 有 `parseFile`（`IngestThreeOmegaSelectionsUseCase.swift:22-27`）。
- 建议统一成“给定命中，返回 `LoadedMeasurement`”：V1 命中走现有加载器；V2 命中（`inputRef`）从 Dataset 解码得到同样的 `LoadedMeasurement`。其后的解释与算法**零改动**。
- 参照实现：AFM 的 `_runAnalysis`（`AFMWorkspaceStore.swift:504-522`）。
- 依赖：C2、C3。

### C6 非 AFM 的 Plot 与自动出图（后置，可重算，不要求历史兼容）

- 放开 `supportedPlotFormats`，增加 1 维序列图格式（PNG + 曲线数值 + manifest，参考 `AFMPlotCodec` 的“数值不依赖 PNG”做法）。
- `FormalPlotLibrary.summaries` 改为按格式路由。
- 自动出图：需要产品先决定每个工作流是否需要、出什么图（D-B3）；AFM 的预设与前缀命名不要提前泛化。
- 依赖：C5。

---

## 7. 各工作流最小适配范围

假设 C1–C5 已就绪。每个工作流只做“上下文消费 + 来源缝 + 标准化接入”，不改科学算法。

| Workflow | 容器 | 最小适配 | 特殊点 / 风险 |
|---|---|---|---|
| **AHE** | PPMS DAT | ① Inbox 选 `ppms_dat` 适配器，写上下文（通道 ch1–3、条件）② `IngestAHESelectionsUseCase` 经来源缝取 `LoadedMeasurement`③ `AHEPlotSelectionItem.sourceFilePath` 改为可携带 `inputRef`（现状：一个命中按通道扇出多个选择项，`AHEIngestionContracts.swift:19-33`） | 通道→桥号映射不变；Result 候选的目标 Sample 当前按 V1 `sampleKey` 重新解析（`SampleResultCandidate.swift:15-17`，design-12 §5），V2 需用 UID（U：design-12 已有矩阵，本审计未复核） |
| **RT** | PPMS DAT + LVM | ① PPMS：同 AHE ② LVM：同 3ω ③ `AnalyzeRTWorkflowUseCase` 的“读文件”与“排序”拆开 | 混合最重（§2.5）；`RT` 与 `3ω` 之间存在跨工作流引用（3ω 的缩放用到 RT 结果，`IngestThreeOmegaSelectionsUseCase.swift:~100-115`） |
| **3ω** | LVM | ① `zurich_lvm` 适配器 ② 来源缝 ③ 文件类型（fieldSweep/rtSweep）由 C1 里确认的工作流 + 条件决定，替代文件名启发式 `_RT_`（`ThreeOmegaLVMParser.swift:70`） | Pack 含 RT 文件路径与指纹，V2 需另议；`I_rms` 来源缝需保持（解释层） |
| **XY** | PPMS DAT + LVM | 两个适配器都复用；`.dat` 用 `ppms_dat`，`.lvm` 用 `zurich_lvm` | `.dat` 路径桥 2/3 写死、不看通道（与 AHE/RT 不同）；`shift` 条件取自自定义条件字符串 |
| **IV** | LVM | `zurich_lvm`；来源缝；条件取自上下文 | 11 列要求；`device/angle/field` 多路回退目前依赖文件路径（`IngestIVSelectionsUseCase.swift:~140-160` 对路径做正则），V2 无路径，须只用上下文条件，行为会比 V1 少一条回退（U：影响程度需用夹具比对） |
| **RSM** | RSM 文本 | `rsm_text` 适配器；单选；热图管线已共享；需要一种热图 Plot 格式（C6） | 默认 `workflow.json` 无 `rsm`（U）；V1 图保存已被守卫（`SaveRSMChartToLibraryUseCase.swift:67`） |
| **MR** | 无 | 无 Workbench、无加载器；若仍希望 V2 下保住这类原始文件，需“只存 Source、不产出 Dataset”的入库方式（当前 `ingestAsset` 要求至少一个 Dataset，`LibraryAssetService.swift:293-294`） | 属 D-B2；是否有 MR 数据由用户确认（U） |

---

## 8. 实施依赖（DAG）

```
C1 测量上下文落点 ─┬─> C2 1 维表格 Dataset + PPMS/LVM/RSM 适配器 ─> C3 V2 命中泛化 ─> C5 来源缝 ─> 各工作流适配 ─> C6 非 AFM Plot
                   │
C4 解释层小收敛 ──┘（建议在 C5 前完成；与 C1/C2 并行）

D-B1（PPMS 多通道归属）──> 决定 C1 的形态（一个 Source 一个上下文，还是按目标 Sample 分别入库）
D-B2（无适配器工作流的原始文件）──> 决定是否增加“只存 Source”入库
```

推荐的工作流落地顺序：

1. PPMS 一族一起（AHE → RT → XY-dat）：同一个 `ppms_dat` 适配器一次解锁三个工作流，且 Task 12 已让 AHE 有 Sample Result 消费者。
2. LVM 一族（3ω → IV → XY-lvm → RT-lvm）：一个 `zurich_lvm` 适配器解锁全部，但每个工作流的位置映射要逐一对夹具验证。
3. RSM（结构上最接近 AFM：单选、共享热图）。
4. C6（Plot 与自动出图）。

---

## 9. 需要 Jack 决定的事项（先翻译成产品影响，再给推荐）

**D-B1：PPMS 一个文件里有多个通道属于不同样品，V2 怎么存？**

- 现状：V1 里用户可以把 `ch1` 归 A 样品、`ch2` 归 B 样品，系统给每个样品各存一份拷贝加一份说明（`RouteTarget.channels`，`Domain/Models.swift:90-93`）。V2 规则是一个原始文件只属于一个样品，V2 入库界面现在也只能选一个样品。
- 影响：不决定的话，这类文件在 V2 里没法按原来的习惯入库，迁移旧库时也没法对应。
- 推荐方案：仍然“一次入库一个样品”，同一份文件按需对多个样品各入库一次，每次只勾选属于该样品的通道（Dataset 里记录通道范围）。代价是同字节文件会在库里出现多份 Source；好处是不改 K5。
- U：用户日常这种“一文件多样品”的比例未知，需要用户说明。

**D-B2：没有适配器的数据（例如 MR）在 V2 下保不保存原始文件？**

- 现状：V2 入库必须有标准化数据；没有适配器的工作流被直接拒绝。
- 推荐：若确有此类数据，允许“只保存原始文件”的入库方式，不产出可分析数据，保证不可再生的原始文件不丢；是否有 MR 数据请 Jack 确认。

**D-B3：非 AFM 工作流的“自动出图”要不要做？**

- 现状：自动出图只对 AFM 实现，预设与规则按 AFM 命名。
- 推荐：先不做；非 AFM 先完成入库与手动 Plot。若要做，需要用户给出每个工作流“默认出什么图”。

---

## 10. 证据 / 结论 / 未确认 汇总

### 10.1 已读码确认的事实（E）

- 四种容器格式各只有 1 份原始读取实现，分别被 AHE/RT/XY、IV/3ω/XY/RT、RSM、AFM 使用（§2.1）。
- PPMS 的列语义在 AHE、RT、XY 三处各自写死，且精确/大小写不敏感匹配不一致；XY 的 `.dat` 不使用侧车通道（§2.2.1）。
- Zurich LVM 的 `col0` 含义随工作流变化；文件无表头，语义由工作流赋予（§2.2.2）。
- V2 的 `assets` 表、Source manifest、`applyV2`、V2 命中都没有测量上下文；V2 命中的 `workflowID` 写死 `afm`、`conditions` 为空（§2.3.4）。
- V2 Inbox 单 Sample；适配器表只有 `afm`；V1 支持按通道分配多 Sample（§2.4.1）。
- 资产存储层（入库、修订、删除、Plot 存储）与工作流无关；只有 Plot 格式白名单、摘要读取、自动出图为 AFM 专用（§2.6、§4）。
- 只有 AFM Workbench 读取 `inputRef`（§2.4.2）。
- 4 份条件字符串解析、2 份 `I_rms`、3 份文件名温度正则（§5.1）；`SidecarConditionNormalizer` 无外部调用方（§5.2）。
- `measurement_data.json` 目前只有 AHE 写入；V1 图/账本写入全部被 V2 布局守卫拒绝；`AnalysisVault` 无 V2 守卫（§2.6）。

### 10.2 由证据推出的结论（C）

- 公共缺口集中在“上下文落点”和“一维表格标准 Dataset”，不在解析、也不在资产事务层。
- 一个 `ppms_dat` 适配器和一个 `zurich_lvm` 适配器即可覆盖 AHE/RT/XY/IV/3ω 的标准化需求；工作流专用结构不入库。
- LVM 的 Dataset 必须连同确认的工作流/解释方案一起记录，否则无法无猜测地读回。
- 科学算法大多已能与 IO 分开，缺的是“Dataset → 工作流内存输入”的来源缝。
- 非 AFM 的 Plot/Pack 属可重算产物，放在公共能力之后，不要求历史兼容。

### 10.3 未确认（U）

| 编号 | 内容 | 如何确认 |
|---|---|---|
| U1 | “一个 PPMS 文件多通道属于不同样品”在用户真实数据里的比例 | 用户回答（D-B1） |
| U2 | RSM 在用户真实规则本里是否启用（默认 `workflow.json` 无 `rsm`） | 用户确认 |
| U3 | MR 是否有真实数据需要在 V2 保存 | 用户确认（D-B2） |
| U4 | 各 `*WorkspaceStore` 内部编排是否夹带科学判断（RT/IV/XY/AHE 共约 3000 行未逐行读） | 后续逐工作流适配时核查 |
| U5 | 各工作流的 Plot 渲染器（3ω、RT、IV、XY 各有独立渲染器，另有共享 `WorkbenchChartRenderer`）之间的重叠程度 | 本次未审计 |
| U6 | V2 SQLite 的 schema 升级路径，及是否已有真实 V2 库需要升级 | 实现设计时核查 `LibraryAssetDatabase.swift:235` 附近 |
| U7 | LVM 静默丢行、RSM 整体拒绝等行为差异对已有旧数据标准化后的影响 | 11B 合成夹具对比 |
| U8 | IV 的 `device/angle/field` 多路回退在 V2 无路径时的行为变化 | 夹具对比 |
| U9 | 一维表格 Dataset 的体积与读写性能（大文件）；列主序二进制块是否足够 | 夹具/基准 |
| U10 | design-12 对 Result 目标 Sample 在 V2 的解析细节与 `SampleResultCandidate` 的 V1 身份字段 | 复核 design-12 §5 与实现 |
| U11 | 本审计未运行任何测试或 App，所有结论为静态读码 | 实现阶段由测试验证 |

---

## 附录 A：本审计读取的主要文件

文档：`AGENTS.md`、`docs/architecture/INDEX.md`、`execution/README.md`、`SKELETON.md`、`brief-11`、`design-11`、`design-5`、`design-10`、`design-12`。

代码（`Sources/SpinLabApp/`）：`UseCases/PPMSDATLoader.swift`、`ZurichLVMLoader.swift`、`RTPPMSDatParser.swift`、`XYRotationDATParser.swift`、`XYRotationLVMParser.swift`、`ThreeOmegaLVMParser.swift`、`IVLVMParser.swift`、`RSMTextLoader.swift`、`RSMDataParser.swift`、`AHEAxisDetector.swift`、`Ingest*SelectionsUseCase.swift`、`AnalyzeRTWorkflowUseCase.swift`、`SaveActiveChartToLibraryUseCase.swift`、`PersistChartArtifactUseCase.swift`、`PersistMeasurementDataUseCase.swift`、`SearchWorkflowMeasurementsUseCase.swift`；`Domain/Measurement/*`、`Domain/Sidecar/*`、`Domain/AnalysisPack.swift`、`Domain/SampleResultCandidate.swift`、`Domain/WorkflowSearchModels.swift`；`AFM/*`；`Library/Assets/*`、`Library/LibraryLayoutRouter.swift`、`Library/LibraryMeasurementDataStore.swift`；`App/InboxArchiveApplyService.swift`、`App/ApplyCoordinator.swift`、`App/State/AnalysisVault.swift`、`App/State/WorkbenchFeatureStore.swift`、`App/State/WorkbenchWorkflowKind.swift`；`Features/Workbench/AFMWorkspaceStore.swift`、`AHEWorkspaceStore*.swift`、`WorkbenchSaveCoordinating.swift`、`WorkflowWorkspaceRegistry.swift`；`Features/Inbox/InboxSelectionWorkbenchPanel.swift`；`config/workflow.json`、`config/import_filters.json`。
