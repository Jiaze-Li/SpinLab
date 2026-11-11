# SpinLab D1 — 科研语义决策稿

**版本**：v0.3（首份可交接决策稿；不代表全部设计冻结）  
**日期**：2026-11-07  
**状态**：产品与架构语义设计；不实施代码、不修改正式数据、不创建 PR。

## 0. 核心结论

SpinLab 以 **Sample 为科研知识中心**。Inbox、Workbench、Sample/Library 可以采用不同的操作方式，却必须共享科研对象身份、物理量、单位、实验角色、条件、来源与人工裁决的含义。

**共同语义不等于一个大而全的 ontology，也不等于把所有信息存成同一种格式。** 应区分“研究谁”“证据是什么”“观测到了什么”“如何标准化与解释”“经过什么分析得到了什么”“用户现在使用哪个 Parameter 值”“什么规则可在何种范围复用”。

**特别确认：** 一个 Parameter 在明确对象与适用语境下有当前有效值。用户直接编辑并确认（Enter、Save、Adopt 等具体交互可由 UI 决定）后，新值就是当前值；可以通过明确采用分析结果来更新它。仅产生或保存新的分析结果，不自动改写已经明确设置的 Parameter。前台不应强迫用户为普通编辑分别做“记录”与“采用”两次决策。

## 1. 范围与不做的事

**D1 负责**：科研对象及其关系的语义边界；来源、观测、标准数据、分析结果、Parameter 当前值与规则的区别；“同一信息”与“可比较信息”的判定原则；物理量、单位、实验角色与条件的共同语言；持久身份的性质；用户明确科研判断及其背景的语义。

**D1 不负责**：重定义已确认的 Batch/Sample/Device/Measurement 实验管理规则；枚举完整 entry/字段表或所有物理量；选择 machineUID、UUID、数据库或文件格式；决定旧 Domain 与 Library 哪一套为最终权威；设计数据迁移、清理算法、自动化执行器、AI 后训练或完整 UI。

## 2. 已确认的要求与决定

| ID | 内容 | 状态与来源 |
|---|---|---|
| D1-01 | Sample 是科研知识中心，Inbox、Workbench、Sample/Library 共享科研含义，不重复定义同一科研事实。 | 已确认：V2 总纲及专题委托 |
| D1-02 | Batch 是生长和处理批次；同 Batch 同衬底身份为同一 Sample，切块不另建 Sample；Device 是 Sample 上独立加工器件；Measurement 可针对 Sample 或 Device，包含多个信号。 | 已确认：专题委托；不再设计 |
| D1-03 | 固定器件角度、扫描角度与旋转平面具有不同科研含义。 | 已确认：专题委托 |
| D1-04 | 可手工录入独立的结构化单值记录；不必先创建完整 Measurement，需要时可关联 Measurement。 | 已确认：本专题用户决定 |
| D1-05 | 同 Sample 切块的几何信息是否进一步分开管理，目前不定；必须避免在语义上封死未来扩展。 | 已确认的开放边界：本专题用户决定；**未确认要建立 Piece 实体** |
| D1-06 | 一次观测、标准数据、分析结果、用户采用值、规则具有不同意义；含义不明的信息允许先存在，不得伪造物理解释。 | 已确认：V2 总纲 |
| D1-07 | Parameter 修改并明确确认后，当前值直接生效；具体是 Enter、Save 还是 Adopt 不由 D1 规定。分析生成的新结果不自动替换明确设置的当前值；主动选择结果可以更新 Parameter。 | 已确认：本专题用户纠正及确认 |
| D1-08 | 人工明确裁决优先；可追溯且可清理；不将普通浏览、删除、反复查看等行为擅自推断为科研判断。 | 已确认：V2 总纲及专题委托 |
| D1-09 | 显示名称、外部编号、路径与持久身份承担不同职责；身份须可承受合理重命名、移动与对账。具体机制未定。 | 已确认的性质：V2 总纲；实现交 D3 |

上表的“已确认”并不表示每一个字段、状态机或持久化机制均已决定。

## 3. 已核查的事实、推断与限制

**只读源码核查基线**：GitHub 仓库 `Jiaze-Li/SpinLab`；提交 `86cd5c6ea707bf882fc415a4e8f4d1f1af2425af`。在 2026-11-07 的定点查询中，`main` 与该提交比较为 `identical`。审计本身基于同一提交。未构建、运行、执行测试或触碰真实 Library/Registry。

**已由源码支持：**

1. `Domain/Measurement/LoadedMeasurement.swift` 明确为 loader → workflow 的内存传递对象；`MeasurementColumn.swift` 保存来源列标识、原标签、单位、数值等，物理量标签需具备依据，谐波、Rxx/Rxy 等角色不属于 loader 的无依据判断。
2. `Library/Domain/LibraryDomainModels.swift` 的 `LibrarySample` 已有字符串 metadata、numericTags/numericDisplay、Registry 行来源等表达；这不等于它已经支持完整科研语义。
3. `Domain/Models.swift` 的 `SpinLabDomain.ArchivedRecord` 包含可选 Device；`Persistence/Persistence.swift` 对 ArchivedRecord 实际提供 JSON 读写；`Repositories/DomainRepositories.swift` 的 `LibraryRepository` 加载并保存该记录。**旧 Domain 不是仅存在于内存。**
4. `AFM/CanonicalAFMDataset.swift` 已分辨 AFM 多通道的来源索引、标签、类型、数值矩阵、单位和来源信息。
5. `Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift` 的 `WorkbenchMeasurementDataStore.append` 会追加指标记录并更新 `latestIndex`。这是静态实现事实，**不是已经观察到自动化推翻人工值的运行事故**。
6. `Domain/Sidecar/SpinLabFileSidecar.swift` 区分规则快照与人工条件覆盖，提供已有的语义和追溯先例。

**尚未核实**：真实数据中的冲突规模、各旧模型在全部运行路径上的实际消费者、现有所有物理量词汇覆盖范围、相关测试结果、完整恢复和删除行为。不能从静态事实推出应直接淘汰某个旧模型。

**源码证据入口**（固定到上述提交）：

- [MeasurementColumn](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Domain/Measurement/MeasurementColumn.swift)
- [LibraryDomainModels](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift)
- [Domain Models](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Domain/Models.swift)
- [Persistence](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Persistence/Persistence.swift)
- [Repositories](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Repositories/DomainRepositories.swift)
- [AFM Canonical Dataset](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/AFM/CanonicalAFMDataset.swift)
- [Result Contracts](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift)

## 4. 最小概念与关系

这里的词汇是**科研语义概念**，并非要求建立同名的代码结构或数据表。

| 概念 | 定义与边界 |
|---|---|
| **Research Entity（科研对象）** | 有持续科研身份的 Batch、Sample、Device、Measurement 等；名称和路径不能替代身份。 |
| **Source（来源）** | 产生、承载或证明信息的依据，包括仪器文件、人工录入、照片和外部记录；保留其原始表达及必要位置/时间信息。 |
| **Observation（观测）** | 在特定对象及实验背景下得到的观测信息，可为标量、曲线、矩阵、图像或多通道信号；不天然证明其解释正确。 |
| **Property/Assertion（属性声明）** | 关于对象的有来源陈述，如标称厚度、衬底类型；不必虚构一次测量。**术语及最终数据表达尚为建议。** |
| **Standard Data（标准数据）** | 对来源内容按照有依据的单位、结构和实验含义进行可复用表达；是来源观测的表示/解释，不因此凭空增加一项独立实验。 |
| **Analysis/Result（分析及结果）** | 在明确输入、解释、方法及有效配置下产生的数值、曲线、矩阵或其他成果；结果与展示 PNG 不能等同。 |
| **Parameter（参数）** | 在**明确对象和适用语境**中用户关注、可以设置当前有效值的科研量。手工编辑确认即可生效；可明确从结果更新，不能被新结果静默覆盖。 |
| **Adoption（采用）** | 对某个用途范围明确使用某值/结果的决定。对普通 Parameter 编辑，用户确认更新本身即表达采用，不要求单独弹出第二次流程。 |
| **Rule（规则）** | 在具体适用范围和依据下可复用的信息解释或处理约定；一次人工确认不自动成为所有未来数据的规则。 |

**推荐的关系，而非固定 schema**：对象具有属性声明；来源支持声明或观测；一次 Measurement 可产生多个通道/观测；标准数据指向其依据及解释；分析消费确定的输入与方法生成结果；Parameter 可引用手工记录或明确选定的结果作为当前值；规则可帮助解释新数据，但应记录适用范围与版本。

一个手工 Parameter 值**可以先作为独立的结构化记录存在**，不必有虚假的 Measurement。未来若发现它来自某次真实测量，可建立关系，不把同一数值复制成两个可以独立修改的权威值。

## 5. 同一事实、独立事实与可比较信息

建议对“相同”至少做三个独立判断：

1. **对象是否相同**：是否为同一 Sample/Device，而非显示名称恰好一致。
2. **证据或观测事件是否相同**：是否引用同一次采集、同一手工声明或同一明确来源。多个界面读取相同记录不应生成多个独立观测。
3. **科研含义是否可比较**：量、角色、单位、条件、几何、方法等是否允许转换或比较。“可比较”不代表“同一个事实”。

**反例**：同一 Device、5 K 下重复测得两次 500 Ω，是两次独立观测；同一结果显示为 500 Ω 和 0.5 kΩ，通常只是不同单位表达；把来源温度写错后纠正，属于原记录的修订，而在 300 K 新测一次属于新观测；换算法重算属于新结果，不是原测量被重新发生了一次。

如何在具体存储层识别等价副本、管理必要历史与物理删除由 D3 决定；D1 不主张无边界永久留存全部缓存和中间成果。

## 6. 跨界面共享的科研语言

至少在语义上分开：

- **物理量（Quantity）**：如 Voltage、Resistance、Length、Magnetic Field。量纲、单位兼容性及合法转换应明确。
- **实验角色（Role）**：如 1ω/2ω/3ω、X/Y、Rxx/Rxy、Trace/Retrace、横纵向几何；角色不能从物理量或单位自动推出。
- **仪器来源标识**：如 Bridge 3、原列号、通道名；这不是 Rxx/Rxy 的充分证明。
- **实验条件与几何语境**：如温度、磁场、固定器件角度、扫描变量、旋转平面及参考坐标系；条件可能是单点、扫描轴或适用范围。
- **解释状态及依据**：已知、未知、候选、存在冲突；不能将缺失当成 0 或无证据转换成确定结论。具体状态字段仍待 D2 设计。

**重要边界**：并非任何单位相同的量都是同一个量。Ω 不能仅凭单位换算成 Ω·m；标称厚度与 XRR 测厚也不是同一证据。不同 Workbench 可用各自算法，但不能重新定义上述科研含义。

## 7. 案例与反例检验

| 案例 | 必须正确表达 | 不允许发生 |
|---|---|---|
| **同一 Sample 尺寸** | 标称/手工测量/分析推导等有不同依据。Parameter 当前值可直接编辑。切块仍属同一 Sample，未来可表达局部范围。 | 切块自动创建 Sample；同数值就误判为同一证据；现在强推 Piece 类型。 |
| **不同 Device 或温度下电阻** | Device A/B、5 K/300 K、测量方法与重复测量事件可以区分。 | 以 `Resistance` 这个名称为唯一键，互相覆盖。 |
| **含义不明的 Bridge** | 保留 Bridge 通道标签、原数值、已知单位、未知的物理角色；之后由证据或用户确认解释。 | 仅凭 Bridge 3 自动定为 Rxx/Rxy；未知被填成 0 或臆测角色。 |
| **AFM 多通道图像** | 同 Measurement 可有 Height Trace、Retrace、Phase 等通道；源矩阵、flatten 后结果及热图显示属于不同层次。 | 将同文件全部通道解释为 Height；把 PNG 当作完整科研数据。 |
| **采用后新分析** | 原结果已被用户用于 Parameter；另一方法产生新 Result，可比较、可主动采用；仅生成/保存不会自动更新当前 Parameter。 | 自动重算或“最新时间戳”静默推翻人工明确设置的值。 |

## 8. 重要选项与选择理由

| 取舍 | 当前判断 | 实际确认情况 |
|---|---|---|
| 所有定量记录强制 Measurement，还是允许独立手工结构化记录？ | **选择后者**：低成本记录科研量，必要时补充关联。 | **用户已确认**。 |
| Parameter 编辑是否再经历独立 Adoption 步骤？ | **不需要两次语义确认**：用户修改并明确提交即更新当前值；界面可以有 Enter、Save 或 Adopt。 | **用户已确认**。 |
| 新分析是否自动改写现有 Parameter？ | **不自动**；需要用户明确选择或符合事先授权的规则，且不得越权覆盖人工裁决。 | **与已确认的人工优先原则一致；自动化权限细节归 D3/D5**。 |
| 全面结构化还是完全自由文字？ | 少量可复用科研量结构化，其余笔记保留自然文本并关联对象/证据。 | **V2 已确认的方向**；具体入门字段未定。 |
| 用同值/同名去重还是保留证据身份？ | 以来源、对象与事件区分；清理真正重复表达，不抹除独立实验。 | **建议的具体判定准则，待 D3 操作化**。 |
| 先建立完整 ontology 还是有限共同词汇？ | **有限共同词汇**；以跨入口一致性和五个案例为检验。 | **符合 V2 已确认的总体取向**，具体术语表未冻结。 |

## 9. 对下游的语义承诺

**对 D2（接入与含义确认）**：仪器文件和手工输入都必须有共同语义入口；来源标签不等于确认后的物理角色；规则、人工确认与未决解释可区分；不能伪造未知条件。

**对 D3（事实与成果生命周期）**：持久对象身份独立于显示名/路径/外部编号；来源、观测、结果与 Parameter 当前值有可追溯关系；用户确认修改即可更新当前值，不能要求二次“采用”；结果追加不得无授权改写人工当前值；清理与恢复不制造另一份独立权威；旧 Domain 与 Library 的实际持久化职责需对账后再决定收敛方式。

**对 D4（共享能力与 Workbench）**：能力明确消费哪些输入、语义解释、条件和方法配置；生成 Result 不等于发布为当前 Parameter；数值结果与图片展示可分开。

**对 D5（自动化与 Spin Cat）**：新规则和正式变更需在授权范围内生效；候选解释不等于事实；用户明确科研判断比点击行为更可靠；不记录所有点击，不预设训练方式。

## 10. 未决问题、是否阻塞与主架构协调

| 事项 | 是否阻塞 D2/D3 讨论 | 归属/协调 |
|---|---|---|
| Sample 内局部切块/区域何时需要独立语境或类型 | 否；先允许保留未来关联能力 | D1 后续有真实场景时与 D3 协调 |
| Parameter 的具体 entry、必填信息、UI 交互与默认适用范围 | 不阻塞概念讨论；会影响最终产品验收 | D1 后续细化、D2/D3/D4 分担 |
| 科研属性声明、观测、Parameter 的正式命名及持久化映射 | 不阻塞语义讨论；阻塞新增正式写入方案定稿 | D3；语义冲突返回 D1 |
| `SpinLabDomain.*`、Library 文件模型、Registry、sidecar 和恢复包的具体权威关系 | 阻塞跨源正式写入设计 | D3，主架构跟踪 |
| 参数当前值及旧 `latestIndex` 如何保护人工决定、避免等价记录膨胀 | 阻塞自动化正式写入指标/参数 | D3/D4/D5，主架构设前置条件 |
| 物理量、谐波角色、通道含义、坐标语境的最小词汇集 | 不阻塞 D2 方案讨论；需要在验证前收敛 | D1/D2/D4 |
| 具体机器身份/数据库/文件格式 | 不由 D1 选择 | D3 与主架构 |

## 11. 建议送回主架构的事项

1. 将 **“Parameter 用户修改并确认即为当前值”** 作为已确认的全局产品约束写入当前 V2 基线，而不是要求普通编辑另走一套 Adoption 操作。
2. 明确 **“手工结构化记录可以独立于 Measurement”**，作为 D2 手工接入和 D3 生命周期设计的共同前提。
3. 将 **旧 Domain `ArchivedRecord` 的真实持久化** 及其与 Library/Registry 的权威映射作为 D3 必须核查的事项，禁止直接依据旧审计中“只在内存”的错误结论淘汰。
4. 将 **“新分析结果不可无授权更新人工 Parameter；修订与新观测不等同”** 转化为 D3/D4/D5 的接口和正式写入验证约束。
5. 保留 **“同 Sample 内切块局部语境”** 为开放设计空间，不提前生成全量 entry 或 Piece 对象。

**交付性质**：D1 的语义层面已达到可以供 D2、D3 开始讨论的程度；但具体物理量词汇、参数字段、权威映射和存储规则尚未冻结。本稿不得被当作立即编码任务或数据库规范。
