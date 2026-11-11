# SpinLab D3 — 数据生命周期决策稿

**版本**：v0.1（首份可交接设计稿，非实现规范）  
**日期**：2026-11-08  
**范围**：科研事实、来源权威、身份、成果生命周期及旧体系兼容。  
**状态**：产品原则已逐轮确认；具体存储格式、UID 编码、同步协议、迁移步骤和事务机制未冻结。未修改代码、迁移/清理真实数据或创建 PR。

## 0. 核心结论

**Sample 是稳定的科研知识实体；Notebook 是它的统一视图，而非第二份科研真相。** 手机在生长阶段创建 Batch/Sample、录入 Recipe；桌面在测量与分析阶段接入 Measurement、生成结果。两端共用正式记录和身份。用户只主动录入一次，其余渠道被动同步。XLSX 保留历史导入能力，未来主要承担可选导出/备份职责。

**标准数据以独立、可复用的科研信号为最小默认物化单位**：一份原始文件赋予一个稳定 Source ID，按 Sample、测试段和独立信号拆成真实标准数据文件；标准数据拥有自身身份，并记录 `source_id`、原始段位置、信号/通道、条件与解释版本。不同文件可重复保存共同的温度或磁场列，以换取低耦合；不能因为拆分文件而丢失共同来源和采样关系。当前不强制引入 Acquisition/Session ID。

**人工明确修改优先，较新的有效人工修改更新同一范围的当前值；自动结果不得擅自推翻人工决定。** 分析产生、正式保存、当前采用是可区分的语义，但一次明确的用户操作（例如 AHE 的 Save to Library）可以同时保存结果并按规则采用。异常、歧义、涉及旧成果的破坏性变化，暂定发生时提示用户裁决，而不是提前穷举审批规则。

## 1. 范围及边界

D3 负责：对象/来源/标准数据/结果的稳定身份性质，正式记录与可重建投影的区别，各数据入口的权威与修改规则，当前采用关系，纠正和重算、去重/删除/恢复、必要历史、旧模型兼容。D3 不决定完整 Quantity/Role 字典（D1/D2），也不决定具体分析算法（D4）、在线创建 UI 与自动化执行器（D5）、存储引擎和完整迁移计划（D6/实施）。

### 确认状态说明

- **已确认**：来自本轮用户明确接受的产品规则和原有 D1/V2 约束。
- **建议**：为满足确认目标提出的操作化解释，尚需在实施合同或其他专题验证。
- **依赖/开放**：D1/D2/D4/D5/D6 尚未冻结的约定，不擅自确定。

## 2. 事实、证据与限制

**源代码只读基线**：`Jiaze-Li/SpinLab`，`main`，提交 `86cd5c6ea707bf882fc415a4e8f4d1f1af2425af`；`Jiaze-Li/SpinLab-Web-Library`，`main`，提交 `4c4312770c749cbfa82bea029cfcec756fe561af`。本轮定点检查了指定读写路径；未运行构建、测试、应用或线上写入；未触碰真实 Library/Registry。

1. Library 有独立本地 `sample.json` 写入（`LibraryStore+Drawers.swift`），`SaveLibrarySampleEditsUseCase` 先写 Library 再尝试同步 XLSX；同步失败可为非致命。**Registry 并非所有 Sample 内容的唯一权威。** 参见：[Sample 本地写入](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Library/LibraryStore%2BDrawers.swift)、[编辑和同步](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/UseCases/SaveLibrarySampleEditsUseCase.swift)。
2. `SpinLabDomain.ArchivedRecord` 存在 `LocalJSONPersistence` 的 `archived_records.json` 读写及 `LibraryRepository` 的实际保存/加载。**旧 Domain 不是纯内存结构。** 参见：[持久化](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Persistence/Persistence.swift)、[Repository](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Repositories/DomainRepositories.swift)。
3. AHE 当前从背景校正后的数值序列提取 Hc 和 R_AHE，支持保存前人工修正；Save 时将图表与指标送到独立持久化用例。追加指标时 `WorkbenchMeasurementDataStore.append` 同时更新 `latestIndex`，Library Presenter 以该指针显示数值。**当前的最新指针不是经过定义的采用制度。** 参见：[AHE Store](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift)、[ResultContracts](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift)、[Library Presenter](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Features/Library/LibraryMeasurementDataPresenter.swift)。
4. 旧 `LibrarySample.id`/`sampleKey` 参与目录、测量、指标、图表关联；sidecar 保存规则快照及人工覆盖；索引有扫描重建路径，但不是已证明全部信息都能无损重建。图表存在共享多 Sample 的保存范式。参见：[旧模型](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift)、[sidecar](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/Domain/Sidecar/SpinLabFileSidecar.swift)、[图表保存](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift)。
5. Web 仓库已能浏览 Sample、图片和元数据；Cloudflare Pages Function `/api/note` 可向 D1 的 `sample_notes` 写/读自由文本，但 Sample 主列表由静态导出的 `library.json` 提供。**尚无已核实的云端创建 Sample、结构化 Recipe 或双向同步**。参见：[Web Note API](https://github.com/Jiaze-Li/SpinLab-Web-Library/blob/4c4312770c749cbfa82bea029cfcec756fe561af/functions/api/note.js)、[Web 页面](https://github.com/Jiaze-Li/SpinLab-Web-Library/blob/4c4312770c749cbfa82bea029cfcec756fe561af/public/index.html)。旧导出流程会重写部分生成的 Web 文件；属于实施注意点，不改变产品语义。[导出脚本](https://github.com/Jiaze-Li/SpinLab/blob/86cd5c6ea707bf882fc415a4e8f4d1f1af2425af/scripts/export_static_library.py)。
6. D2 的 DAT/LVM 专项审计与用户提供样例说明：来源可能多 Sample、多 Channel，甚至同文件多温度段；原始名称、列号、同名数值不够构成物理身份。D2 目前不冻结每一种文件或通道的实验解释。用户提供的《SpinLab D2 — 数据接入与含义确认决策稿 v0.1》（上游文档）。

## 3. 主要决定及确认状态

| 编号 | 规则 | 状态 |
|---|---|---|
| D3-01 | 一份原始文件可包含多个 Sample 的测量信息；每个 Sample 取得自身信号，保留共同文件来源与采集关系 | **已确认** |
| D3-02 | 人工直接修改 Parameter 并确认即更新当前值；后台记旧值→新值、时间等必要修订信息，前台不强制复杂流程 | **已确认** |
| D3-03 | Sample Notebook 自动汇集身份、Recipe/Parameters、Measurement、分析结果、照片和笔记；Notebook 是视图，不是另一份独立权威 | **已确认** |
| D3-04 | 标准数据按 Sample、测试段、独立科研信号可拆成真实文件；每份包含自身信号及必要 H/T/条件，允许公共列重复；同一信号必要分量可保留在一起 | **已确认的方向**；哪些信号可独立拆由 D1/D2/D4 验证 |
| D3-05 | 手工电阻、尺寸等无需制造仪器文件或强制生成 Measurement；可以先成为独立结构化观测/Parameter | **上游 D1 已确认** |
| D3-06 | AHE 人工点击 Save to Library 可以一次保存 Result 并在合适范围更新当前 Parameter；已有明确人工采用值不被静默覆盖 | **已确认**；自动与手动的默认优先级细节按 D3-11 约束 |
| D3-07 | 机器不得未经用户确认改动已有正式事实/人工采用值；用户直接修改生效；只有未来明确授权规则才能按范围自动操作 | **已确认** |
| D3-08 | 每个原始 Source File 有稳定 Source ID；每个标准数据有独立身份及 `source_id`；暂不强制 Acquisition/Session ID | **已确认** |
| D3-09 | Sample 有独立于名称、旧 `sampleKey` 和目录的永久身份；保留旧标识及映射。多入口有充分且唯一依据时关联已有 Sample，否则由用户确认 | **已确认**；UID 形式和迁移未定 |
| D3-10 | 手机 Web 作为生长录入入口，创建 Batch/Sample、填写结构化 Recipe；桌面管理后续测试分析，XLSX 逐步成为兼容/备份出口 | **产品方向已确认**；云架构/安全/同步技术待 D5/D6 |
| D3-11 | 用户一次主动录入，其余入口被动同步；人工明确修订优先，同一对象/量/适用范围的较新有效修订成为当前值；不凭同步到达时间判新旧 | **已确认原则** |
| D3-12 | 修正导致重算、来源冲突、重复清理、歧义恢复等可能改变已有科研信息的情形，暂定在实际操作时请求用户裁决；正常操作不要求二次确认 | **已确认** |

## 4. 权威关系：入口、事实与当前采用

### 4.1 三个不同的问题

- **创建来源（origin）**：Sample 起初从手机、桌面、历史 XLSX 等哪里创建。用于来源追溯，不自动决定以后谁更有权改。
- **观测来源（evidence）**：某个值由万用表手读、PPMS 原始文件、照片、用户描述、AHE 算法产生；这些应保留区别。历史 XLSX 对历史生长记录是最初证据，导入后人工纠正成为当前有效修订，不能被旧表再次导入推翻。
- **字段裁决与当前采用（decision）**：在明确对象、Quantity/Role、条件和用途范围内，哪个值当前使用。人工确认直接生效；自动新结果与当前采用的替换是不同责任。

### 4.2 形式上的裁决顺序（不是纯时间戳排序）

1. 新的用户明确修改或采用，在**同一字段及同一适用范围**内直接更新当前决定。旧修订仅需按价值保留可追溯信息。
2. 人工主动保存新的 AHE Result，是用户操作，依 D3-06 可顺便更新**未被明确人工保护**的当前 Parameter；原有明确人工采用的值不被默默推翻。
3. 后台解析、同步、重新计算可新增来源证据或候选 Result；未经确认不改已有人工决定。未来已授权的自动规则也必须受作用范围限制。
4. 不同温度、Device、测量事件或用途不是同一当前值，不能用“更新较晚”互相覆盖。
5. 同步晚到的旧版本不是新修订；不确定的并发/版本冲突需用户裁决。默认不静默丢弃人工更改。

**正式保存**指被采纳为 SpinLab 正式科研记录，而非只存在于工作台草稿或试运行；**当前采用**指特定范围内用户实际使用哪个值。一次 Save 可同时表达两者。**可重建投影**（Notebook 展示、查询索引、派生预览、标准化缓存）可以存在，但重建不能改变正式采用决定；不可变恢复快照也不是另一个可独立修改的权威。

## 5. 身份与 Sample Notebook / Measurement 关系

- Sample 以永久内部身份识别科研对象。人类编号、显示名称、Batch/衬底语义编号、Registry 行、旧 `sampleKey` 和磁盘路径分别是属性或兼容映射，不自动等同。
- Batch 代表生长/处理批次；按 D1 已确认的“同 Batch 同衬底身份为同一 Sample”规则组织；一个 Batch 的 Recipe 可供多个 Sample 引用，不需要反复录入。Device 是 Sample 的器件语境（D1）。同 Sample 切块局部几何保持扩展能力，不现在新建 Piece 实体。
- Source ID 标识一份正式登记的原始文件，移动、重命名不改身份。重复导入应先查现有来源关系；名称/路径/哈希只是证据，不能单独等同一次实验。文件可能含不同温度、扫描段或多个对象。
- Standard Dataset 有独立身份，可作为真实文件持久化在相应 Sample 下；内部元数据包含 `source_id`、来源段/行范围、Sample/Device 归属、原通道/信号、已知 Quantity/Role、条件、单位及解释版本。采用哪种文件格式、元数据内嵌或 sidecar 待实施比较。
- **Measurement 是科研测量语境/关系，不是“一个文件 = 一次测量”的死规则**。一个 Source 可以产出多个 Sample/Device、多个温度段、多份独立信号标准文件；同一 Sample 同一次多通道测量的关联得以保留。当前无需额外强制 Acquisition ID。共同 Source ID 仅证明文件同源，不充分证明两个测试点严格同步。
- Notebook 将上述信息自动归集；用户无需手工把来源或结果再粘贴到 Notebook。物理上可以独立保存数据，也可以有引用、重建索引和恢复快照，但前台只有一个可理解的当前科研档案。

### 5.1 按职责而非入口设置正式写入边界

| 组件 | 产生或编辑 | 允许决定什么 | 不允许 |
|---|---|---|---|
| 手机 Web | 创建/编辑 Batch、Sample、Recipe、手工观测 | 用户 Save 提交正式修订；写入成功后供桌面读取 | 创造另一套无法对账的 Sample ID；直接把旧静态 `library.json` 当可写权威 |
| 桌面 Sample/Library | 原生创建、手工 Parameter、附件、观察、关联 | 用户明确修改与采用，维护 Notebook | 独立复制另一份可分别编辑的当前事实 |
| Inbox/D2 统一器 | Source、条件、通道和归属解释、标准数据 | 依据确认的规则/用户解释提交正式数据与未决项 | 擅自决定 Parameter 当前值或推断未知物理角色 |
| Workbench/D4 | 用明确输入和配置产生 Result、PNG、分析证据 | 用户 Save/Adopt 按授权发布成果；图像展示可变 | 将新 Result 无条件当作新事实采用；改变原始观测 |
| 同步/XLSX | 历史来源读入、新记录导出、按需备份 | 同步确认后的记录、报告失败或冲突 | 用旧文件覆盖较新人工修订 |
| 索引/快照 | 提速、展示、恢复 | 重建可推导内容 | 暗中决定身份、采用或新科研事实 |

## 6. 生命周期与默认操作

| 事件 | 结果 | 后台最少保留/保护 |
|---|---|---|
| 用户原生创建 Sample | 立即形成正式 Sample 身份及可编辑 Notebook；没有仪器文件也成立 | 创建来源、身份、基本 Recipe/Batch 关系 |
| 手工万用表读数或长度录入 | 结构化观测或 Parameter；不虚构文件/Measurement | 量、值、单位、已知对象/条件、录入或观测来源 |
| 重新导入原始文件 | 先识别同源/同事件风险，不无声新增等价正式副本 | 原始文件身份、来源证据、已有正式解释和关联 |
| D2 将 DAT/LVM/CSV 拆分 | 按 Sample、测试段和独立信号物化标准数据 | `source_id`、段信息、角色、实际条件、解释版本；扫描方向不能被排序抹掉 |
| AHE 得到指标后 Save | 保存 Result；按范围和已有人工决定更新或保留 Parameter | 计算输入、方法/配置、结果、人工修正与采用关系；图像不代替数值结果 |
| 用户把 520 Ω 改成 500 Ω | 同一范围当前值变 500 Ω，不凭此增加一次测量 | `520→500 Ω`、时间、对象/范围和人工修订身份；理由非必填 |
| 在其他温度新测得 500 Ω | 新的独立观测；不视作纠正旧观测 | 条件和观测事件来源，允许相同数值共存 |
| 修改尺寸/纠正来源解释 | 正式事实更正，基于旧版本的相关衍生结果标记需要复核 | 旧输入/解释版本和依赖；是否重算/删除由用户当时决定 |
| 后台重新计算出新数值 | 允许独立保存 Result，不擅自改变人工当前值 | 确定的输入与计算版本；避免无限追加等价输出 |
| 删除重复图 | 可以移除无价值显示成果，不因此删除被引用的原始证据或有效数值结果 | 依赖检查、必要的清理/恢复线索；不把“删图”理解成否定科学结论 |
| 同步失败或并发版本冲突 | 已成功保存的本地用户修改保持有效；明确显示未同步/冲突状态 | 哪条写入成功、哪条失败、待用户裁决项 |
| 重建索引 / 恢复 | 优先由正式记录恢复查询与 Notebook；不重建已经明确删除的成果 | 采用关系、身份映射、删除决定与来源证据不能只存在于易丢的缓存 |

## 7. 信息洁癖：保留什么、清理什么

**目标不是无限事件溯源，也不是只保留最新数值。** 建议采用按价值分层的保留政策：

- **重要、需可靠追溯**：原始来源及登记身份；正式 Sample/Batch/Device/Measurement 关系；有效的标准数据或其可验证重建依据；被使用的分析结果及方法输入；当前采用关系；用户重要纠错和拒绝/采用决定。保留最低限度的对象、范围、来源、版本、时间。
- **按需保留或删除**：重复图、临时渲染、无意义同参数重复运行、中间缓存、未被采用的等价候选、旧 UI 恢复包。清理后不因后台刷新而静默再生。
- **不能仅凭数值相同去重**：两次真实测量即使都为 500 Ω，仍是独立证据；不同方法得到相同 Hc 也可能有比较价值。相同来源/同一处理输入/同配置的重复产物，才可能是无需重复持久化的同一结果，但具体判据和保护条件交 D4/实施验证。
- **前台**默认显示当前重要内容；历史、来源和修订按需展开，不把每次点击、每次计算中间态和所有删除副本默认堆在 Notebook。用户当时选择删除、保留或恢复；不要求普通操作双重确认。
- **AI 学习证据**只记录可以解释的科研动作与背景：明确修改、采用/否决、解释规则及适用范围、依赖的分析输入与方法。删除一张重复图、未点击、普通浏览不能推导成物理结论；没有提供理由不猜测。候选经验和正式规则必须分离。

## 8. 旧体系兼容约束（本轮不迁移）

1. **Library**：`batch.json`、`sample.json` 和 Sample 文件目录已有独立持久化；旧 `sampleKey` 同时是图表、指标、sidecar、目录等关系的关键。稳定身份必须是**可验证的附加映射**，不允许直接批量替换旧 key/路径造成失联。
2. **Registry XLSX**：历史来源的字段责任受 Batch/Sample Ownership 约束；既有本地 Sample 编辑先写 Library，XLSX 同步失败不等于撤销本地修订。后续从 XLSX 主入口演进为被动备份/兼容时，需要明确外部编辑检测，但不要求回写。
3. **旧 Domain/ArchivedRecord**：本身存在独立 JSON 持久化链及 Repository 读写者。必须在消费者清点、实际数据映射与恢复行为补证后，才能选择保留、桥接、统一或迁移；不能因其被称为 Legacy 而视为内存临时对象。
4. **sidecar**：保留既有来源规则快照、人工覆盖及历史兼容；原始列、Channel、来源路径等旧字段可能不全或语义不一致，不能盲目补为已确认事实。
5. **分析与索引**：`measurement_data.json` 的追加+`latestIndex` 是当前实现事实；新的正式采用模型不能仅凭最新指针、`manual` 标记或数值相同实现。图表共享存储、旧分析包和多条保存路径各有真实消费者；需定点核查读写者再改。
6. **Web**：当前 `library.json` 是静态投影，Note API 写到 Cloudflare D1；桌面 Library 与 Web Note 并未证明已有统一权威同步。不能将当前原型误报为正式双向同步系统。Web 侧正式写入前需 D5/D6 设计身份映射、访问权限、可靠同步/冲突、备份恢复；旧导出覆盖静态资源是实施注意事项。
7. **磁盘可靠性**：已有原子单文件写入、部分批量写入和索引恢复保护，不能据此宣称整个 Library 已具备跨本地/云端/XLSX 的统一事务。可重建缓存及不可变快照合法，关键是权威与引用关系明确。

## 9. 案例走查与验收边界

| 案例 | 必须成立 |
|---|---|
| **多 Sample DAT**：一份 DAT 的 CH1/2/3 分别属于 PN40/41/42 | 一份 Source ID，三个 Sample 各有自己的标准数据文件与正式归属；各文件可重复保存 H/T；不可把共同文件误认成三次互不相关的来源 |
| **单 Sample 多信号 LVM**：CH1 Rxx、CH2 Rxy | 可成为两份真实独立标准数据，保留各自所需轴、分量及同一 `source_id`；只知道同源不代表逐点严格同步，联合计算须核查对齐 |
| **多温度文件**：90/70/50 K × 1ω/2ω/3ω | 当实验含义和段边界得到确认，形成 9 份独立标准数据；共享 1 个 Source ID，每份记录温度、段索引、原始实际条件；不需 3 个 Acquisition ID |
| **人工电阻后导入** | 手工 Parameter 当前值不被新的文件观测无声覆盖；可同时查看两个有来源的量；跨温度/Device 不当成冲突 |
| **同名量不同条件** | 条件是适用范围的一部分，不能依据字段名/写入时间互相覆盖 |
| **已采用 Result 后重算** | 新 Result 可正式保存，当前明确采用值不被后台推翻；用户主动保存可以在授权范围内更新未受人工保护的默认值 |
| **不同方法得到同/不同数值** | 都保留方法和证据身份；不只凭数值去重；当前采用可唯一指向所选择的 Result |
| **修正尺寸影响推导** | 修改立即生效；旧推导标记待复核，不悄悄变成基于新尺寸的结果；用户决定是否重算/清理 |
| **删除重复图** | 不默认删除来源、有效数值或其他 Sample 的引用；支持明确清理且不自动再生成 |
| **外部同步失败** | 成功的正式本地提交仍有效；清楚提示同步状态和必要补救；旧同步版本不覆盖较新人工更改 |
| **手机新建、历史 XLSX 再导入** | 有充分且唯一依据时关联同一 Sample；歧义由用户裁决；不因路径/名称不同制造新物理样品身份 |
| **索引损坏后重建** | 不丢永久身份、明确采用、必要来源/修订，也不复活用户明确删除的成果 |

## 10. 仍未确定的问题及是否阻塞

| 问题 | 状态 | 是否阻塞下一专题 |
|---|---|---|
| 稳定 UID 编码、数据库/JSON/CSV/二进制格式、是否内嵌标准数据元信息 | **技术方案未选** | 不阻塞 D4 设计；阻塞具体持久化实施 |
| 已有 `sampleKey` 与其他旧对象的真实消费者全表，旧 Domain 数据实例与重复映射规模 | **待只读追踪/隔离测试** | 阻塞安全迁移和正式新写入接口细节 |
| Channel 角色、未知单位、单信号边界以及实际时间/扫描对齐 | **D1/D2/D4 依赖** | 不阻塞独立文件的概念；阻塞针对某类信号的自动拆分实施 |
| AHE 的 Result 身份、哪些方法输入需保存、重复分析等价判据、采用范围默认值 | **D4/D3 接口待定** | 阻塞自动发布生产指标 |
| 云端与本地具体同步方式、安全授权、离线草稿、冲突处理协议 | **D5/D6/实施** | 阻塞手机入口正式启用，不阻塞 Sample 语义设计 |
| XLSX 备份频率、跨资产完整备份格式、保留期和硬删除窗口 | **后续技术策略** | 不阻塞 D4/D5 逻辑设计；实施前需定义 |
| Sample 内切块/局部区域语境 | **D1 开放** | 不阻塞当前架构，禁止预先强制 Piece 类型 |

## 11. 送回主架构和下游的接口变化

- **给 D1/D2**：共享 Source ID + 真实独立 Standard Dataset + 来源段/Channel/条件/解释版本；D2 仍负责判断如何拆，D3 管正式身份及生命周期。没有证据的物理角色保持未知。
- **给 D4**：标准数据文件不依赖 Workbench；Result 身份、确定的输入和配置版本、结果与 PNG 分离；AHE Save 作为“保存并在合法范围采用”的显式用户动作；联合分析使用共同来源并核查采样对齐。
- **给 D5**：手机 Web 的原生 Sample/Recipe 写入、前台授权的自动化、候选隔离、只在异常时提示；无需为普通编辑再次 Adopt。
- **给 D6**：按稳定身份和正式记录提供手机/桌面共同权威，XLSX 降为兼容/备份；先核查旧消费者和生产数据，再选择物理格式、实际同步策略和迁移路线。优先验证：手机创建 → 桌面读取 → 手动修改 → 标准数据归属 → AHE 保存/采用 → 同步冲突/恢复。

**交付性质**：本稿是 D3 的首份可交接设计基线。以“已确认”的产品决策约束后续专题；所有建议及未决技术方案不得直接转为冻结的编码任务。本轮没有实际迁移或清理。
