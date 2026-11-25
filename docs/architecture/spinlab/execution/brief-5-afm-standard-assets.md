# 任务 5：AFM 标准数据入库与共享资产关系（Design Draft）

前置：任务 1、3、4、9、10 已合并（#228 / #229 完成 V2 记录与路由）。共同语义：[SKELETON.md](SKELETON.md) K1–K13。以本合同及后续经审查的具体设计为准；旧 D6-B T03 / G4 只供参考，不重复设置开工门槛。当前仅做设计（taskType: "design"），不实施代码、不迁移真实 Library。

## 一、要实现的用户工作流

Inbox 选择明确支持的 AFM .ibw 来源 → 用户确认目标 Sample（恰好一个）→ 复用现有解析器完成忠实标准化 → Library 保存 Source、Dataset 与资产关联 → Sample 下可查看、识别和直接读回标准数据；关闭并重开 App 后仍可用。后续任务 6 的 Workbench 与任务 7 自动化只读同一标准数据入口，不再各自解析原始文件。

- Source 是原始仪器文件的不可变副本；原始字节不更改。Dataset 是标准化后可直接消费的科研数据，不是处理结果。标准化不做 flatten、level、zero reference、滤波、裁剪、异常值删除、拟合、粗糙度或出图（K7）。
- Library 管理资产与关系；Parser 负责格式/单位/信号解释；Workbench 负责科学分析。暂不需要独立 Measurement、Device 实体或通用插件框架。
- Measurement/Source 的科研归属恰为一个 Sample，由用户确认，不凭匹配规则自动提交；一个 Source 可以产生多个 Dataset，Dataset 只关联其唯一 Source。Sample 下的 Dataset 和未来 Plot 通过来源/依赖链推导，不复制直接 Sample 归属。跨 Sample 共享测量入口取消；普通引用的解除与删除仍遵守 K5、K6、K12。
- Sample Result 当前值和 Result Definition Catalog 继续原有 JSON 单一权威，不能复制到 SQLite。Sample 的正式身份与 Batch 生长条件保持任务 10 合同。
- 全部 V2 实施、测试与故障注入在隔离测试 Library。V1 日常 AFM、Registry、Publish 等保持可用；真实 V1 数据迁移仅由任务 11 另行设计与授权。非 AFM V2 旧消费者仍明确拒绝，不扩大为全部 Workbench 迁移。

## 二、建议的数据组织（待 Design Review 收敛）

沿用已确认的 Storage v2 路径：

```text
Library/
  records/batches/<batchID>/batch.json
  records/samples/<sampleUID>/sample.json
  storage/<src_ID>/...          # 原始文件内容
  storage/<dst_ID>/...          # 独立标准数据内容
  _spinlab/
    layout_version.json
    result_definitions.json
    library.sqlite             # 资产登记、关系、位置、校验、当前修订
```

SQLite 是资产关系权威，文件系统是大数据内容权威；不在 sample.json、sidecar 或另一套 assets.json 中重复维护关系。以下是最小逻辑模型，不是冻结的 DDL：

| 实体/关系 | 本任务需要的含义 |
|---|---|
| Asset | 稳定、不含语义的 src_/dst_ ID；类型、库内相对位置、完整性信息、格式/版本及必要可用状态 |
| Sample—Source ownership | 每个 Source 恰有一个 Sample UID 归属；Sample 可有多个 Source。SQLite 唯一权威；Dataset/Plot 的 Sample 由依赖推导 |
| Dataset—Source dependency | 每个 Dataset 恰有一个 Source 及必要源内信号定位；一个 Source 可有多个 Dataset；依赖纳入删除判断 |
| Dataset current content marker | 同一 Dataset 更正时单调变化的提交标记；独立于内容哈希，防止 ABA/迟到旧更新 |
| Operation/recovery state | 仅保留提交、重试、跨文件与 SQLite 删除/中断恢复实际需要的信息；不做通用审计或历史数据库 |

编号不可由文件名、路径、哈希或其他对象的 ID 推导（K1/K2）。内容哈希可用来验证/提示重复，不能作为科研对象身份。重复点击/重试必须幂等（K4）；同内容的再次明确导入是提示复用还是新建，设计需给出清楚行为，不把去重扩大为机器判定两个实验相同。无依据的单位、通道、关系保持未知；无明确归属时不得猜 Sample。

**标准化路线**：公共 Adapter 一次返回一份 Source 与一组（一个或多个）独立 Dataset，每个 Dataset 有自己的格式载荷和源内信号定位。AFM 首个 IBW Adapter 继续返回一份现有多通道 CanonicalAFMDataset（不机械拆分通道）；多 Dataset 路径以受控测试 Adapter 验证，未来 DAT/LVM 接入时按真实测量条件和独立扫描拆分。连续扫描（如 RT）保留完整扫描轴。Source 原始字节只保存一次，各 Dataset 独立读回；同一信号更正保持 ID，改变独立信号新建 ID。继续复用 #232/#233 的编码、SQLite、事务和恢复机制，不引入通用 ORM、复杂插件框架或全量历史库。

## 三、AFM 标准化必须忠实

参照 [现有 AFM Dataset Contract](../../workbench/datasets/AFMDatasetContract.md)，以真实代码支持范围为准，设计确认首批 IBW v5 的字节序、数值类型、维度与通道边界；不宣称支持未验证格式。

- 现有 CanonicalAFMDataset 包含 xCoordinates、yCoordinates、channels、sourceMetadata；通道包含 sourceIndex、sourceLabel、semanticTypeRaw、矩阵、源/规范单位及 provenance。保留原始矩阵形状、顺序、正负、坐标校准和已知 Trace/Retrace；行列映射不变。
- 支持有依据的长度单位转换：X/Y 使用 µm，长度类信号使用 nm；非长度信号保留实际单位和数值。空/未知单位遵循经过验证的仪器约定或明确未知，保留源证据，不凭标签、默认 active channel 推断物理量。默认显示选择不是信号的科研身份。缺失/非有限数值须有显式、可无损回读的表示或明确拒绝，不能填零、截断后宣称完整。
- Source 保存原始字节及必要的原始文件名、来源、校验；Dataset 保存标准数值与必要解释依据/格式版本。sourceRef 等现有绝对路径仅作为历史来源信息，正式关系靠 Source ID，移动 Library 后不依赖旧绝对路径。
- 写后重启由 Dataset ID 直接读取内容，即使原始 Source 在隔离测试中暂时不可访问也能读回标准数值；来源不可用诊断与 Dataset 可读状态分开。损坏/未支持内容不能成为 Ready；设计明确原始 Source 单独保留的状态及重试入口。

## 四、提交、更正与删除的安全底线

不引入多用户协调；复用任务 3 的单写者。单写者、文件 atomic rename 和 SQLite transaction 各自并不能自动保证跨文件/数据库的提交完整。设计须选定最小可恢复方案，明确正式提交点、未完成数据的可见性和重启恢复。仅在必要文件、元数据及关系全部可用后报告 Ready；不能留下被当作有效的数据空壳。

**更正（K10/K11）**：忠实解析或有证据的单位/角色解释更正保持同一 Dataset ID；换独立信号新建 ID。启动记录当前内容标记，正式提交点再次核对；A 先开始、B 先提交、A 后完成必须拒绝 A；A→B→A 也不能绕过，同一次操作重试不重复提交。已有 Source 原样保留。不建立全量版本历史。已明确依赖该 Dataset 的 Live 产物过期，Snapshot 与用户确认的 Sample Result 不自动改变；任务 5 只提供必要的关系、失效合同及最小可测试支撑，不提前实现整个 Plot/计算系统。真正的 Live 发布合同由任务 6/首个消费者落实。

**彻底删除（继承任务 9 和 Skeleton）**：
- 软删除和恢复不删除文件或解除现有关联。取消链接只删该关系。
- 永久删除前计算该 Sample 的引用闭包：其他 Sample（包括仍在废纸篓且可恢复的 Sample）、Dataset 来源、其他有效对象/依赖及需要保留的 Snapshot。零 Sample 链接不代表可删，未知/不可读/不完整引用不得猜为零。只清理该次明确删除涉及且确认无其他有效引用的已登记资产，不顺手清理未知文件或无关孤儿。
- 确认界面给出真实将删除和保留的文件数量，正式提交前复核仍是同一删除计划。删除一个多样品 Plot 的关联 Sample 后，Plot 保留并有“输入已变化/需要更新”状态；不能继续当作 current；本任务用最小关系模型/夹具验证此合同，不实现全套 Plot 写入界面。
- 设计确定 SQLite 与文件系统（含 Sample 正式记录）间的最小删除提交/中断恢复方案，说明失败或崩溃时如何恢复或明确停住。不得把目录递归删除当作共享资产安全。V1 现行删除行为保持不变。新资产纳入非空样品判断与二次确认。
- 备份必须覆盖一致的 SQLite 和实际资产、Sample 记录；检查当前备份逻辑是否会遗漏 WAL 或混合 V1/V2，若未能提供一致备份则明确拒绝 V2 备份，不能报告伪成功。

## 五、当前代码基线与设计盘点要求

静态核查基线：main 56fa6d212ee2d5b1c3d91c3a038873d6f6f399b5（#229 已合并）。以下为已核对的入口，不等同运行验收。

| 代码位置（Sources/SpinLabApp 下） | 当前事实 / 需要设计的切换 |
|---|---|
| AFM/IBW/IBWReader.swift；AFM/AFMInputAdapter.swift；AFM/CanonicalAFMDataset.swift | 已有 IBW v5 reader、坐标校准/单位解释、多通道 Codable 数据类型。优先复用，不重复实现标准化；核对 reader 实际支持边界和特殊值编码。 |
| Features/Workbench/AFMWorkspaceStore.swift；Workbench/V3/Heatmap/AFM/AFMPackState.swift | 当前 Workbench 从文件路径解析并在 Pack 携带 canonical dataset；任务 5 不改其 V1 行为，不能把 Pack 缓存当正式资产。任务 6 改接公共读取。 |
| App/InboxArchiveApplyService.swift | 当前显式 requireV1ArtifactWriteAllowed，逐个 target 抄写到 drawer 和 sidecar；仅开放 V2 AFM 分支走共同资产登记，不取消其他拒写。 |
| Library/LibraryLayoutRouter.swift；Library/LibraryStore+RootAndIndex.swift；Storage/LibraryWriteLease.swift | 已有 V1/V2 路由与测试初始化。明确首次启用资产数据库、缺失/损坏/未知版本的区分；不能静默重建丢失的 SQLite 关系。 |
| Library/LibraryStore+Drawers.swift；Library/LibrarySampleEmptyCheck.swift；Library/LibraryStore+Backup.swift | V2 永久删除当前只处理 sample 记录；空样品和备份仍需纳入新资产关系。 |
| Library/LibraryResultService.swift；Library/LibraryArtifactLayout.swift；Library/LibrarySidecarService.swift | 现有 Result、旧产物、Sidecar 路径边界不能被新关系覆盖；未迁移消费者仍拒写。 |
| Storage/AtomicFileWriter.swift；Package.swift | 已有文件写工具；Swift package 当前依赖 CoreXLSX。设计核对现有工具能否复用以及最小 SQLite 接入、事务和恢复能力，避免两套资产写入权威。 |
| Tests/SpinLabAppTests/AFM/IBWFixtureBuilder.swift；AFMInputAdapterTests.swift；AFMEndToEndRealFileTests.swift | 已有受控 fixture 与条件性真实文件测试。用隔离副本做实际源—标准对照，不能因真实样例缺失而把跳过计为通过。 |

设计交付应补充真实 Inbox 路由/识别/确认路径、资产写读与删除消费者的代码定位；当前 AFM 的特殊导入行为、重复识别、备份及显示入口须核查。具体实现设计可以独立成一份 design-5 文档，但不要复制 Skeleton 或建立额外任务状态表。

## 六、设计交付与测试库验收

Design Review 先收敛：真实支持格式和比较精度；最小 SQLite schema/关系与文件编码；明确的导入/读取/修订/删除/恢复/备份状态转换；接口及实际调用者；实施范围、测试计划与合理拆分。技术选择以最小可工作方案为准，不因要通用就实现尚无消费者的类型。若需要拆分，先做可用资产持久化边界与引用保护，再接真实 AFM Inbox 和 Library 查看；每个阶段不开放不完整的生产能力，全部通过才勾选任务 5。

| 验收 | 可验证结果 |
|---|---|
| AC1 实际入库 | 通过 Inbox 在测试 V2 库选择真实 Sample 并导入受支持 IBW；SQLite 登记 Source、Dataset、关系；原始字节校验；重启按 ID 读取。 |
| AC2 忠实数据 | 至少一份实际仪器样例加非方形、多通道、含正负/校准/单位的 fixture；与源对照全部数值、形状、顺序、通道和单位；设计明确容差，编码回读不引入额外精度损失。 |
| AC3 未知/损坏 | 未知单位/信号不冒充 Height；缺失值不造零；损坏与未支持格式不伪 Ready，错误可见。 |
| AC4 独立读取 | 重启、移动隔离库、临时令 Source 不可访问，标准数值仍读得出且来源错误独立报告；Dataset/数据库损坏不当空库。 |
| AC5 身份/归属 | 一个 Source 恰有一个 Sample；同次操作重复提交仅一次；同一 Source 产生多 Dataset（公共测试 Adapter），每个 Dataset 恰有一个 Source，均由来源推导同一 Sample；跨样品复用/关联拒绝，软删除/恢复和重启保持身份 |
| AC6 提交恢复 | 在文件准备、发布、SQLite 提交等边界注入失败/中断；重开后完整提交或明确可恢复/拒绝，不能产生半就绪记录或隐藏丢失。 |
| AC7 更正 | 同一信号稳定 ID，换独立信号新 ID；迟到 A、重复提交、ABA 均验证；已确认 Sample Result / Snapshot 保持，明确 Live 依赖过期。 |
| AC8 彻底删除 | 单个与批量 Sample 删除共用引用闭包；两个独立样品的测量不互相删除；同 Source 多 Dataset 与跨样品 Plot 依赖夹具、保留 Snapshot、未知文件及中断恢复；确认计数去重且真实、保留和过期状态正确 |
| AC9 入口/备份/兼容 | 实际用户路径复用同一资产服务，未迁移 V2 入口继续拒写；备份完整一致或明确拒绝；现有 V1 全量回归、Result/UID/批次生长条件保全，无真实数据操作。 |
| AC10 现场验收 | 使用隔离启动与全新 V2 测试 Library、独立 Rule Book 和真实 IBW 副本：A 导入两份独立测量、B 导入另一份；现有 Deposit Mapping 明确确认单个 Sample、无多选/跨样品 Share，Source/Dataset、通道、条件与单位可见；重启仍可读且 ID/归属不变；软删除/恢复、单个永久删除、独立样品批量清空和计数验证，不影响范围外样品。未确认 AC10 不勾选任务 5；不以 Workbench 能画图或跳过真实样例代替验收 |

不做：AFM 科学处理与图保存（任务 6）、自动化（任务 7）、手工或计算 Result 的新体系（任务 4/12）、真实库迁移（任务 11）、所有旧资产消费者迁移、所有仪器格式、跨进程多写者或无实际消费者的大型抽象。设计合并不是实施授权之外的 major 批准，也不表示任务 5 已完成。

### 任务 5B 实施交接（历史记录；科研归属、接口及验收以 K5–K7 和下方 5C 为准）

前置实施 PR #232（5A 公共资产内核、AFM Adapter/Codec、安全底线）合并后，先同步最新 main，再核对实际公共接口与后端验收结果，按 [design-5](design-5-afm-standard-assets.md) §三、§六接入。5B 不是再开发一套 AFM 数据库或生命周期服务。

- Rule Book 增加通用 `fileExtension` 规则类型（匹配小写扩展名、不含前导点），保留既有 equals/contains 等原义；优先沿用现有文件名/目录匹配，未命中时使用明确配置的扩展名规则，避免改变旧工作流分类。更新 Rule Book 编辑器、解析/校验及相关默认配置。已有外部规则本通过现有配置入口迁移或由用户编辑，保留原有自定义规则，不静默重写用户规则；为 `afm` 配置 `fileExtension: ibw`。支持规则与 Adapter 真实支持范围分离，后缀不等于内容已合法解析。
- 通过实际 Inbox 接收 IBW、确认非废纸篓 Sample（一个或多个，使用正式 UID）、调用 5A 公共服务完成正式入库，重复确认/重试复用同一 operationID；同内容的新导入由用户选择复用或新建。接入后的成功状态必须来自正式资产提交，而非临时 UI 数据。
- Sample 页面展示 Source/Dataset 与必要通道信息、共享/Unlink；Trash 确认使用 5A 删除计划和实际文件数量，提交前复核；所有写入沿统一服务，保留 V1 与未适配 V2 拒写边界。
- 完成 AC1、AC9 实际入口及 AC10 隔离库 GUI 现场验收，重跑 5A 合同回归。两个阶段验收全部完成才勾选任务 5；不进入任务 6/7，不迁移真实旧库，不实施完整 V2 备份。

### 任务 5C：科研数据归属与关联规范化（2026-11-25 用户确认）

#231 设计、#232（5A）及 #233（5B）已合并；原有多 Sample 测量归属、直接 Sample—Dataset/Plot 链接以及只返回一个 Dataset 的标准化接口需要收口。本节与 K5–K7 是本次实施依据，取代早期合同/设计中与之冲突的多 Sample 导入、测量 Share/Unlink 和直接 Sample—Plot 关联描述。AC10 延至本 PR 一并完成。当前不进入任务 6。

1. **单一科研归属与关系约束。** 复用 SQLite 资产登记和依赖体系；唯一 Source—Sample 归属，每个 Dataset 恰有一个 Source（`dataset_source`），Plot 仅引用其 Dataset 并推导 Sample。写入和 ready 读取/校验不能只靠 UI，必须在公共服务及适当的 SQLite 约束中强制类型和数量。现有 `sample_asset_links` 可收敛为 Source 唯一归属表，避免建立第二权威；具体约束方式由实施者决定。Dataset 或 Plot 的 Sample 查询由关系链推导，不保存冗余关联。已有 Source 只可在同一所属 Sample 下复用，跨 Sample 复用必须拒绝；相同 hash 不自动合并独立测量，不自动复制已有 Source 绕过归属约束。
2. **公共一对多标准化合同。** 将 `StandardizedDatasetPayload` 从单个 dataset/全局 signalLocators 收敛为一组独立 Dataset 载荷，每项含自身源内定位；公共 ingest 接收唯一目标 Sample UID，生成一个 Source 和一组 Dataset ID，整组持久化、链接、幂等提交和恢复，不能部分 Ready。AFM Adapter 返回一份多通道 Dataset；仅用受控多 Dataset Adapter/fixture 验证公共路径，不实现 PPMS、Zurich 或真实多温度解析。原始文件、单位和信号身份、更正防 ABA、独立读取与原始字节保全继续按已确认合同。
3. **简化实际用户入口。** 复用 Inbox 的 Deposit Mapping/现有 Sample 匹配与用户确认；AFM 每次只选择一个合法、非废纸篓 Sample UID，移除新增多选面板和测量跨样品 Share/Unlink。Apply / Apply All / 底层 archive/service 都不能绕过显式单样品确认。Library 按 Source 及其 Dataset 展示，正确显示通道、条件和单位；不重复为 Dataset 保存 Sample 归属，不再提供跨样品共享测量的操作。不新增错误归属转移 UI。
4. **引用保护适配新关系。** 保留 #233 单/批量共同计划和已有操作恢复；从 Sample 的 Source 推导 Dataset 和相关产物，保护删除范围外 Sample 仍涉及的 Plot 及其所需输入，保留 Snapshot 固定内容，Live 输入归属变化标记过期。仅使用最小关系夹具验证未来 Plot；不实现实际 Workbench 分析、图保存或自动化。保留受依赖保护的 Source 原属 UID，明确历史归属，不能把已删除样品当作活动 Sample 或把未知损坏当空。实际资产文件计数及计划复核、故障恢复、未知文件保护继续复用。
5. **版本边界。** V1 日常库保持兼容；V2 尚未用于正式旧库迁移。若收紧 SQLite schema 需要内部版本变化，明确识别并拒绝不兼容的旧试验库或经明确授权处理测试副本；本次用新建隔离 V2 测试库验收。不自动删除、改归属、迁移或覆盖任何既有正式 Library；不建设正式 V2 迁移/备份系统。Sample Result/Definition 及 Batch 参数权威完全保持任务 4/10。
6. **交付。** 本次修改 SKELETON、任务 5 合同、实际代码和测试，非新架构专题。先完成自动化回归和真实 IBW 验收，再由用户完成 AC10。按 AGENTS.md 完成 GUI 规则、版本与 closeout；合并前明确记录实际验收证据、更新 Roadmap 将任务 5 标记完成，之后才开始任务 6。真实测量样例不上传仓库，不假定 skipped 等于通过。若 GUI 未完成，保持 Draft/进行中并明确阻塞。
