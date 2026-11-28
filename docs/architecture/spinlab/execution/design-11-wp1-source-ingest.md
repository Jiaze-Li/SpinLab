# Task 11 WP1–WP4 — 公共数据架构与 Workbench 接入（统一设计入口）

基线：`main@5f8831a43589c7211a29f33c042beecccc0636b2`，总体设计 [PR #247](https://github.com/Jiaze-Li/SpinLab/pull/247) 已合并。2026-11-28 用户授权基于 #247 开启设计 Draft，随后明确要求避免将工作包机械拆成约 20 个 PR；本 PR #248 扩展为 WP1–WP4 统一设计，按 [design-11 §4.3](design-11-v2-migration-readiness.md#43-pr-交付计划2026-11-28-用户确认) 的八 PR 目标组织交付。

**阶段：设计，不实施。** 以 [design-11 §4.2 WP1–WP4、§5.1–5.1c](design-11-v2-migration-readiness.md)、[brief-11](brief-11-v2-migration.md)、[SKELETON K5/K7/K12/K13](SKELETON.md) （同时适用 K8–K11）与 [AGENTS](../../../../AGENTS.md) 为合同；不重做 Task 11 总体设计。本页为待完善的设计入口，不是已验收的实现方案。

## 1. 统一设计目标与边界（WP1–WP4）

一次确定原始文件入库 → 忠实标准 Dataset → 公共查询/读取 → Workflow 科研处理 → 绘图组织/渲染 → 正式成果保存的公共合同。WP1–WP4 的技术依赖仍保留，统一设计、分两批实施：WP1–2 数据基础，WP3–4 公共消费与 AHE 首个真实闭环。先复用已有模块，再补足真实缺口；不为形式统一而增加框架。WP1 原有三个原则全部保留：

- 测量上下文随 Source 同一提交点持久化，记录用户确认的 workflow、通道与物理角色、条件及来源（rule/manual/fallback）、测量时间、原始文件名、源文件 mtime、旧路径（仅记录，不作身份）及必要规则/解释来源；可批量查询，唯一权威，不写进 Dataset 本体。未知不猜；有效通道属于 Source–Sample 直接关系，SQLite 为权威。
- 一份多通道文件涉及多个样品时，每个目标 Sample 各保存一份完整 Source 字节并登记各自有效通道；不共享跨样品所有权，不为节省少量磁盘空间跨样品去重。原始文件不改写，不将其他样品的信号暴露为本样品可分析通道。
- 合法原始文件在无适配器或标准化失败时可明确地 Source-only 入库（零 Dataset），仍受通用身份、归属、完整性、查询及删除/恢复机制管理。失败原因与可分析性明确，不伪造 Dataset。MR 只保留数据分类，不另建 MR Workbench、解析器或兼容逻辑；旧 Measurement Set 不迁移、不新增集合字段。

**WP2–WP4 本次纳入详细设计，不实施。** WP2 复用 PPMS DAT、Zurich LVM、RSM TXT loaders 与现有 AFM 矩阵能力；WP3 统一检索、读取和列/通道定位；WP4 用 AHE 验证公共 Workbench 来源入口、正式手工 Plot 保存和 Sample Result 显式赋值。各 Workflow 的物理处理独立，科研配置变更与纯显示重绘分开。后续 RT/XY/3ω/IV/RSM 适配不在本 PR 实施范围；仅用现有消费者的真实差异验证公共合同是否成立，不能预造未来接口。

WP0/WP8 合并安排为后续迁移安全设计与实施，技术上 WP0 独立；WP9 真实库预演/切换另行授权。保留 V1 正常使用、AFM 标准化/自动出图现有功能。只有实际共同合同变化才调整 SKELETON，不另设并行权威或任务看板。

## 2. 当前实现与待设计问题（WP1）

以下为基线静态核对，设计者须继续按实际源码确认调用链和所有写入/查询消费者：

- `LibraryAssetService.swift:230–299`：SourceManifest 有原文件名、路径、字节数、哈希、入库时间；`ingestAsset` 需要 adapter、单个目标 UID，拒绝空 Dataset；现有 committed receipt 重放检查目标 UID。须设计零 Dataset 的显式状态、完整请求绑定、上下文与文件/SQLite 的同一提交点，复用已有 pending/committed/recovery 机制。
- `InboxArchiveApplyService.swift:481–580`：V2 无 adapter 即拒绝；只读单个 `v2TargetSampleUID`、一个 operationID，AFM intent 随入库提交。核对确认草稿、ApplyCoordinator、已有去重与 Library 显示，明确多目标/通道路由、每目标稳定重试身份、部分成功/失败后的队列与反馈，不让失败的写入冒充已入库。Source-only 不得触发分析或自动出图。
- `LibraryAssetDatabase.swift`：schemaVersion 当前为 2。真实库无 V2 数据（#247 Audit A 的既有证据），仍需明确测试/开发 V2 库的 schema/旧记录处理：安全升级或明确拒绝，不能把缺失上下文解释为虚构的测量事实。核对实际写租约、commitLock、删除闭包、恢复与批量查询。
- 设计时区分：适配器缺失/标准化本身失败（原始文件仍可保全）与文件不可读、归属非法、哈希失败、持久化失败、写租约丢失等真正入库失败；不能用笼统 catch 降级掩盖后者。原始字节和 mtime 的采集与验证边界需明确。
- 核对同样品复用既有 Source、再次尝试标准化、上下文冲突的处理。现有 Source ID 和原始字节不改变；重试不重复登记；为后续补生成 Dataset 保留必要公共接口/语义，但不提前实现尚无消费者的通用转换引擎。
- 界面只需最小必要变动：确认目标 Sample/有效通道、明确原始文件已保存但无标准 Dataset及原因、Sample 中可查看/定位 Source。不要为 MR 或 Source-only 新造页面、复制 Library 管理逻辑。设计明确用户选择、提示与不可执行的操作；未知科研角色仍未知。

## 3. 衔接合同与首个闭环设计（WP2–WP4）

以 [Audit B](audit-11-cross-workflow-architecture.md) 的静态源码证据为起点，补核实际消费者。以下是设计任务，不是冻结实现细节：

### WP2 — 统一表格 Dataset

- 复用 `LoadedMeasurement` 与已有 PPMS DAT、Zurich LVM、RSM text loader，明确持久编码/解码、稳定列键与原始列序号、原始表头/单位、已知物理量、诊断、NaN 和精度、内容校验。AFM 的矩阵形态不变，不强制所有数据使用同一 payload。
- 按格式复用适配器，同时按用户已确认的 workflow/支持状态决定是否生成 Dataset。MR 即使是 DAT 也保持 Source-only；不能仅凭文件后缀断定科学语义。LVM 位置列的含义由工作流/测量语境解释，通道号不等于谐波。标准化只做忠实结构化和有依据的单位换算；I_rms、Rxy、拟合、平滑等属于科研分析。
- 短行/异常行不得静默丢弃：依据 #247 的默认拒绝/Source-only 与诊断规则明确可接受边界；区分 Source 已保存、Dataset 未生成、真正入库失败。设计从已有 Source 补生成 Dataset 时如何保持身份、归属、内容/版本和幂等，实际随首个真实需求实施，不增加通用编排器。
- 明确 WP1 有效通道记录与 WP2 Dataset 列定位的合同：完整原始文件保留，但数据消费者不可误用其他 Sample 的通道；未知角色不猜、不默认为全部，避免多份独立权限/归属真相。

### WP3 — 公共查询与列/通道定位

- 核查 `SearchWorkflowMeasurementsUseCase.standardDatasetHits` 当前 AFM 专用逻辑、`WorkbenchInputRef`、列/通道映射和已有条件解析工具。统一按上下文/稳定 ID 查询和加载，支持条件/数值检索，避免依赖源路径充当身份。区分 Library 能看见的 Source 与 Workbench 当前可分析的 Dataset；未适配的 Workbench 不能获得伪可用输入。
- 以 AHE/RT/XY-DAT、3ω/IV/XY/RT-LVM、RSM 的实际数据需求校验合同；只提取有真实重复的列选择、条件解析等能力，保留各物理解释。合并同名逻辑前明确行为差异和回归证据，不把已有科研算法改写混入数据适配。WP3 输出的接口须能由 WP4 实际消费，不提前构建空框架。

### WP4 — AHE 首次端到端验证公共架构

- 设计已有 V1 路径加载与 V2 Dataset 解码接入同一 AHE 科研处理逻辑的最小来源入口，保留算法与用户已确认的通道/条件语义。核查实际 `IngestAHESelectionsUseCase`、axis/channel 选择及 AHE 结果候选，按 Sample UID 绑定 V2 目标；保留 Task 12 明确确认写入唯一 Sample Result 的保护，不增加自动同步或第二数值权威。
- 复用已有 Cartesian XY 渲染、公共控件、正式资产保存、查询/删除/恢复及依赖保护；以 AHE 为首个非 AFM 正式 Plot 消费者，设计共享曲线数据、PNG 与 manifest、格式校验、摘要路由、打开/重绘/导出及新建/替换边界。先核查 `supportedPlotFormats`、`validatePlotRequest`、`FormalPlotLibrary.summaries` 与 Task 6 现有合同；只建 AHE 实际使用的公共能力，后续其他 Plot 类型按真实需求扩展，不做整个 Workbench 重构。
- 明确统一生命周期（读取 → 科研语义/数据处理 → Plot payload/坐标映射 → 渲染 → 交互调整 → 保存）的现有模块归属，明确科学配置变更触发重算，显示配置仅重绘。AFM/RSM Heatmap 与输运曲线的区别是 payload/科研处理与绘图类型，不是另一套 Library 或保存体系。
- 下一实施批次 WP1–2 需可独立验收标准数据入库和 Source-only；WP3–4 在其基础上完成 AHE 真实闭环。后续适配只有在发现实质共同合同缺陷或新科研选择时才补设计，不逐 Workflow 重开完整设计 PR。

## 4. 设计交付与实施验收合同

Worker 在本页完善 WP1–WP4 的实际源码证据、最小数据结构/唯一权威、跨包接口与模块职责、状态/事务/恢复、UI 行为和两批实施顺序。区分已确认的产品/科研原则、代理技术决定、真正需要用户确认的事项。设计成果应给出以下可执行验收的具体入口、夹具和预期结果；本 Draft 不宣称功能已实现。

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