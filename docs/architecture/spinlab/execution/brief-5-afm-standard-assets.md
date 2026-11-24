# 任务 5：AFM 标准数据入库与共享资产关系（Design Draft）

前置：任务 1、3、4、9、10 已合并（#228 / #229 完成 V2 记录与路由）。共同语义：[SKELETON.md](SKELETON.md) K1–K13。以本合同及后续经审查的具体设计为准；旧 D6-B T03 / G4 只供参考，不重复设置开工门槛。当前仅做设计（taskType: "design"），不实施代码、不迁移真实 Library。

## 一、要实现的用户工作流

Inbox 选择明确支持的 AFM .ibw 来源 → 用户确认目标 Sample（可多个）→ 复用现有解析器完成忠实标准化 → Library 保存 Source、Dataset 与资产关联 → Sample 下可查看、识别和直接读回标准数据；关闭并重开 App 后仍可用。后续任务 6 的 Workbench 与任务 7 自动化只读同一标准数据入口，不再各自解析原始文件。

- Source 是原始仪器文件的不可变副本；原始字节不更改。Dataset 是标准化后可直接消费的科研数据，不是处理结果。标准化不做 flatten、level、zero reference、滤波、裁剪、异常值删除、拟合、粗糙度或出图（K7）。
- Library 管理资产与关系；Parser 负责格式/单位/信号解释；Workbench 负责科学分析。暂不需要独立 Measurement、Device 实体或通用插件框架。
- 同一资产可关联多个 Sample；不是一个 Sample 一份文件。用户确认归属，机器不猜（K5、K12）。Unlink 只移除关联，不删除资产（K6）。
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
| Sample—Asset link | Sample UID 与 Asset ID 的多对多关系；唯一链接、可独立取消 |
| Dataset—Source dependency | Dataset 的明确来源及必要信号定位；引用关系纳入删除判断 |
| Dataset current content marker | 同一 Dataset 更正时单调变化的提交标记；独立于内容哈希，防止 ABA/迟到旧更新 |
| Operation/recovery state | 仅保留提交、重试、跨文件与 SQLite 删除/中断恢复实际需要的信息；不做通用审计或历史数据库 |

编号不可由文件名、路径、哈希或其他对象的 ID 推导（K1/K2）。内容哈希可用来验证/提示重复，不能作为科研对象身份。重复点击/重试必须幂等（K4）；同内容的再次明确导入是提示复用还是新建，设计需给出清楚行为，不把去重扩大为机器判定两个实验相同。无依据的单位、通道、关系保持未知；无明确归属时不得猜 Sample。

**推荐路线**：先复用现有 CanonicalAFMDataset 的多通道表示，优先选择一个 .ibw Source 对应一份可独立读回的多通道 Dataset（不机械地每通道拆一文件）；其中通道有稳定的源内定位。设计审查应确认同一信号的更正如何保留 dst_ ID，改变独立信号时如何新建 ID。文件编码（如版本化 JSON 或二进制）及 SQLite 具体封装由设计比较后选择最小可维护方案，不提前引入 HDF5/通用 ORM/复杂数据湖。标准内容独立可读，不能仅存源路径、解析器参数或依赖已打开 Workbench。

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
| AC5 身份/共享 | 同次操作重复提交仅一次；一个资产链接两个样品；Unlink/软删除/恢复不删除文件；再次关联和重启后 ID 不变。 |
| AC6 提交恢复 | 在文件准备、发布、SQLite 提交等边界注入失败/中断；重开后完整提交或明确可恢复/拒绝，不能产生半就绪记录或隐藏丢失。 |
| AC7 更正 | 同一信号稳定 ID，换独立信号新 ID；迟到 A、重复提交、ABA 均验证；已确认 Sample Result / Snapshot 保持，明确 Live 依赖过期。 |
| AC8 彻底删除 | 单独拥有、两 Sample 共享、仅被其他 Dataset/对象引用、保留 Snapshot、多样品 Plot、未登记文件及中断恢复；正确文件计数和保留状态；不能删其他样品数据。 |
| AC9 入口/备份/兼容 | 实际用户路径复用同一资产服务，未迁移 V2 入口继续拒写；备份完整一致或明确拒绝；现有 V1 全量回归、Result/UID/批次生长条件保全，无真实数据操作。 |
| AC10 现场验收 | 隔离测试库 GUI：导入 AFM、查看 Sample 下 Source/Dataset 和通道、重启读取、共享/取消链接、删除提示；不使用真实 Library。不以 Workbench 原来能画图代替验收。 |

不做：AFM 科学处理与图保存（任务 6）、自动化（任务 7）、手工或计算 Result 的新体系（任务 4/12）、真实库迁移（任务 11）、所有旧资产消费者迁移、所有仪器格式、跨进程多写者或无实际消费者的大型抽象。设计合并不是实施授权之外的 major 批准，也不表示任务 5 已完成。
