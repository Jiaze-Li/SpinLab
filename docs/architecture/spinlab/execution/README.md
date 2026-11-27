# SpinLab 执行包

这里是给 Agent 派 **Sample 中心新模型任务**时直接用的材料。旧设计（D6-A、D6-B、G0、新数据库 v0.2）只作这些任务的参考；当新模型规则冲突时，本目录的骨架与任务 brief 优先。现有 Swift 的实际行为仍需核实，其他功能区的 UI/Plot 等规范不因此失效。

## 里面有什么

- [`SKELETON.md`](SKELETON.md)：数据骨架。一页，每次派任务都附上。
- `brief-N-*.md`：每个任务一份需求。写的是"我要什么、不要什么、怎么验收"，以及 Agent 需要知道的代码现状。任务 PR 与 brief 决定本次工作的阶段与范围；Deliver 负责执行与交付，不把所有任务解释成写代码。

## 任务顺序

| 顺序 | 任务 | 需求 | 流程 | 前置 |
|---|---|---|---|---|
| 1 | 新建样品，编号永久不变 | [`brief-1`](brief-1-create-sample.md) | 直接实现 | 无 |
| 2 | Registry 少一行不再删样品，删除暂时关闭 | [`brief-2`](brief-2-safety-guard.md) | 直接实现 | 任务 1 已合并 |
| 3 | 同一个 Library 只允许一个 SpinLab 可写 | [`brief-3`](brief-3-single-writer.md) | 直接实现 | 无 |
| 4 | 全库 Result Definition Catalog + Sample 当前数值 | [`brief-4`](brief-4-parameters.md) | 直接实现（按更新后合同） | 任务 1、3 已合并 |
| 插队 | 手机网页新建样品，电脑自动收进 Library | [`brief-8`](brief-8-phone-new-sample.md) | 直接实现 | 任务 1 已合并 |
| 9 | 废纸篓与分级删除（Zotero 软删除模式） | [`brief-9`](brief-9-trash-and-delete.md) | 先设计 | 任务 2 已合并 |
| 10 | Storage v2：平级 Batch/Sample、Growth 权威、V1 兼容 | [`brief-10`](brief-10-storage-v2.md) | Design Draft PR #227 | 任务 3 已合并 |
| 5 | AFM 文件入库成标准数据（引入链接表） | [`brief-5`](brief-5-afm-standard-assets.md) | 先设计 | 任务 1、10 已合并 |
| 6 | AFM 处理与出图改读标准数据 | [`brief-6`](brief-6-afm-workbench.md) / [初始设计](design-6-afm-workbench.md) | 先设计 | 任务 5 |
| 7 | AFM 自动出图 | D6-B 的 T05 任务卡，同上 | 先设计 | 任务 6 |
| 12 | Workbench → Sample Result 显式写入（首个 AHE 消费者，后续 RT/3ω 分步接入） | 需求待写；复用任务 4 的数值写入入口 | 先设计 | 任务 4 |
| 11 | 旧 Library 受控迁移到 V2 | 需求待写，独立迁移与回退验收 | 先设计 | 任务 10、5 及相关旧消费者兼容验证 |

**进度不记在这里。** 哪个任务做完了、下一个是什么，看 [`docs/V5_ROADMAP.md`](../../../V5_ROADMAP.md) 的 5.6.x 段，用的是仓库原有的勾选方式（`[ ]` 未开始、`[~]` 进行中、`[x]` 已完成）。任务合并时在同一个 PR 里勾选。

任务 11、12 的需求在轮到它们之前再写，写法照 `brief-1` 到 `brief-4`，写好后把表里的“需求”一栏改成指向新文件。

### Result Definition 与 Sample Result 边界（任务 4、12）

- **任务 4**：Library 级的 Result Definitions 管理工作区（新增/查看/语义编辑提醒）+ 每个 Sample 的当前数值填写/确认/清空。已定义但没填写只显示空格，不在每个 Sample 生成一行空记录。全库 JSON Catalog + `sample.json` 单一数值权威；不建 SQLite 表、不改旧 Sidecar 和 Workbench 计算历史。
- **任务 12**：由 Workbench 明确选 Sample + 目标 Definition，将计算数值带入确认界面；首个真实消费者优先 AHE 的 Hc/R_AHE，RT 和 3ω 的 alpha/beta 在各自后续小范围任务里适配。工作台可提醒条件、单位或用户定义的限定文字不匹配，但人工确认决定是否赋值；不自动同步、不改变 Source/Dataset/Plot。
- **保留已有计算能力**：历史 `measurement_data.json`、分析 Pack/Plot 与内部指标提取暂按旧逻辑运行；它们不因用户新建 Result 定义就自动迁移到当前 Sample Result。需要正式双向链接、持续依赖、自动过期时另做设计，不给任务 4 增加机制。
- **软删除兼容**：Result Value 属于 Sample 的实际数据，纳入已有“非空样品”的二次确认；空 Definition 槽位不计数，避免所有新样品一创建都变成“非空”。

### Storage v2 实施边界

- **任务 10（Design Draft #227；以 [`brief-10`](brief-10-storage-v2.md) 为合同）**：同时收敛 Batch Growth Parameters 的唯一权威：盘点 `LibraryRegistryParser` 对 Batch/Sample `numericTags` 的重复投影、`LibraryFieldOwnershipRuleBook` 对生长字段和 Unknown 字段的分类、Registry Apply、Native Sample 新建/编辑、展示/索引的读写路径。V2 统一由 Batch 提供已确认的共同生长条件，Sample 通过 `batchId` 读取；不能把全部 Numeric Tag 都当作生长字段，也不能此时自动删除或修改真实 V1 数据。保留任务 4 新 Result Catalog/数值的唯一路径与身份。随后在测试 Library 中定义并验证存储布局版本、统一路径解析和 V1 兼容读取；建立新 Sample 记录的唯一落点（顶层 `records/`，不复用 V1 的 `batches/`、`samples/` 名字）及写入保护；用户约定单人受控升级、所有设备运行兼容新版，不支持旧版 App 对 V2 Library 降级写入，因此**不以旧版写 V2 的互操作/拦截机制作为验收**；不能凭目录改名宣称旧版安全。必须验证当前新版对既有 V1 Library 的读写兼容、V2 明确布局版本及混合/损坏 fail-closed；盘点 `batch.json.sampleKeys` 的全部读写点，并把 V1 已有的两种 Batch 路径形态（`batches/<前缀>/<批次>` 与 `batches/<批次>`）收进显式版本，不靠探测目录是否存在来决定。不移动既有用户库，不附带 SQLite 资产关系实现；其验收须覆盖新版对 V1 Library 的新建/读取、重启、Registry 同步、废纸篓和路径冲突的安全拒绝。
- **任务 5（先设计；以 [`brief-5`](brief-5-afm-standard-assets.md) 为合同）**：不把任务 4 的 Result Definitions / 当前 Sample Result 值另存进 SQLite；须同时设计彻底删除的完整引用保护、删除提交和中断恢复（见 SKELETON“彻底删除”的安全不变量；不预设删除顺序），并定义多样品 Plot 在其中一个样品被删后的 K10 过期标记；仍只做 AFM Source → Dataset 标准入库及首个 SQLite Sample—Asset 关联消费者，并把新资产写入 V2 `storage/`；不能把所有旧图、旧数据与跨工作流消费者迁移都塞进 AFM 任务。
- **任务 11（先设计、另行授权）**：前提含全部 Sample 有合法且唯一的 `sampleUID`、历史样品旧 Key 映射已校验；还须核对 Batch/Sample 旧生长字段重复及冲突、Result Definitions/各 Sample 当前值的完整性与空值语义，在所有相关旧路径消费者、共享资产关系、删除/恢复与备份策略核验后，才考虑真实 Library 的预演、备份、可验证迁移、原子切换和恢复。未验收之前 V1 保持原位，禁止自动迁移、批量重写或删除旧目录。
- **不增加第四套权威**：`sample.json` 管 Sample 属性、Batch 归属和当前 Result Value；全库 Result Definition Catalog 只定义格子，不存具体 Sample 值；Batch 持有共用生长条件；SQLite 管 Source/Dataset/Plot 等资产登记和关联，大文件由 `storage/` 保管。UI 分组是查询结果，不是磁盘父子关系；不因目录整理而暗改现有生长数值。

**任务 5 的必验项：** 同一 Dataset 若只是更正忠实解析或有证据的单位/角色解释，保留 datasetID；改变独立信号则新建。测试「旧更正 A 开始处理 → 新更正 B 先提交 → A 后完成」：A 必须因当前标记已变化而被拒绝，B 仍是当前内容，不能只凭主线程同步写入就省略校验。相同操作重试不得再次更新；成功更正须使**确实依赖该 Dataset 的 Live 分析产物/Plot** 过期，已保存的 Snapshot 不受影响；不得自动清空或改写任务 4 由人确认的 Sample Result 当前值。此条约束首次 Dataset 消费者的提交结果与验收，任务 5 设计时再选最小实现，不要求给任务 1–4 加机制。

**任务 6（首个 Live Result/Plot 消费者）的必验项：** 后台计算 A 读取输入/定义标记 v1 并完成初步校验；随后某个**被该 Live 明确依赖**的 Dataset、输入数值或分析配置 B 更新并使相关 Live 过期；A 再尝试发布时，必须在不可交错的提交点重新核对全部直接/间接依赖和 Live 自身标记，拒绝旧输出，不能重新标为 `current`。反向顺序 A 先发布、B 后更新时，B 必须使该输出过期；输入值 A→B→A 也不得绕过单调标记检查。首次 Snapshot 消费者须同样测试「保存准备完毕、正式提交前依赖或归属被修改」，不得宣布 `saved` 或固定错误内容，已成功保存的快照在之后变更时保持不变。这些要求在对应任务的设计与验收中落地；不为任务 1–5 新建事务框架。

任务 3（PR #224）已合并：同一台机器、同一 Library 的单写者保护现在由程序保障。任务 4 的新 Definition Catalog 与 Sample Result 写入也必须经过该写许可；不用再为它引入另一把锁。

任务 2 已合并（PR #195）；旧 Registry 删除护栏继续有效，不因任务 4 新增 Result 字段或任务 10 的路径设计而取消。

## 原来的 G0–G5 去哪了

不再作为单独的关卡。每块基础由第一个需要它的任务带着做：

| 原关卡 | 现在 |
|---|---|
| G0 设计准备 | 由 `SKELETON.md` 和需要先设计的任务的设计审查替代 |
| G1 数据安全 | 任务 2、任务 3 |
| G2 样品编号 | 任务 1 |
| G3 样品当前科研数值 | 任务 4 的 Result Definitions/Values；照片和笔记之后另开 |
| G4 标准数据 | 任务 5 |
| G5 结果与自动执行 | 任务 6、任务 7 |

## 每个任务怎么走

对 Agent 说一句话就够：**"做 `docs/V5_ROADMAP.md` 5.6.x 段里下一个没打勾的任务。"** 它会找到对应的 brief，brief 末尾的"开工"一节写了分支、PR 和步骤。

**任务 1–4：直接实现。** 任务 4 已因用户确定 Result Definition/Value 模型而更新 brief，按新合同直接实施，不再使用旧 Manual Parameter 设计；brief 本身是合同，无须另开架构阶段。

**任务 5–7、10–12：先设计。** 任务 10 的正式设计合同见 [`brief-10`](brief-10-storage-v2.md)，先收敛文件布局、Batch 字段权威与当前新版对 V1 的兼容路径，任务 5 引入 SQLite/链接表/标准数据格式，任务 11 涉及真实数据迁移，任务 12 才把 Workbench 数值接到任务 4 的 Sample Result；均需要针对当前代码和测试库先确定验收。轮到时：

1. Agent 读取 PR、brief、SKELETON 与相关现行代码，区分已确认的需求、待用户决定的产品/科研语义和可自主决定的技术问题。对已有设计 Draft 发出 `deliver 做 PR<n>` 即要求完成当前授权的设计工作；不授权功能实施。待决项列出选项、推荐、依据与影响，能在明确假设下继续的设计、证据核查和审查照做；不得将假设写成已批准决定。仅在真实的用户决策使相关工作不能继续时阻塞该部分，其他工作继续。
2. Agent 补齐可实施的设计合同、代码证据、边界与验收方案，使用当前 harness 可用且获准的独立只读 Reviewer 审查（例如原生 fresh-context subagent）。Reviewer 读取本轮设计、brief、SKELETON 和相关源码，检查需求覆盖、架构/数据权威、安全/恢复、最小实现及验收能否发现错误，并给出具体证据和结论。Builder 独自判断意见、修改设计并对实质修订或未解决的阻塞问题发起独立复审，直到实质问题收敛或触发下方止损规则。保留简明的审查对象版本、结论、问题处置和假设；不增加独立文档或新状态机的强制要求。不得用自审、一次普通技术咨询、PR Bot 或文档检查冒充规定的独立设计审查。Reviewer 不可用则先完成其他可做工作，诚实报告审查未完成。
3. 当前设计完成后自主 commit、执行适用的文档/合同检查、push 到同一个 Draft PR，交付最多五行摘要和待确认的假设/产品取舍及审查结论。明确区分设计阶段的证据与未来实施阶段的测试（不在设计 PR 编写功能代码或把未来 AC 宣称已验证）。只在用户明确授权后转 Ready；设计确认并合并后，另行授权/开启实施 PR。未解决的实质问题或必须确认的决策如实列为未完成，不虚报设计通过。

**流程权威与历史兼容：** 本节是执行包当前流程规则。旧 brief 中的 `reviewloop_begin`、`taskType`、`contractText` 等历史命令只是原流程记录，不再要求调用 ReviewLoop MCP，也不要求给 Deliver 添加任务类型。对当前任务，按 PR/brief 中实际工作要求和本节执行；普通列表顺序或旧工具命令不构成新增人工审批点。仍遵守用户明确要求的真实审批边界、产品/科研决定和设计与实施隔离。正式 PR Bot 审查仍按 Deliver 的 Ready 后流程，与 Draft 前独立设计审查是不同职责。

## 三条止损规则

- 合同超过两页，说明任务太大。停下来拆任务，不要继续加内容。
- 保留设计审查三轮止损：三轮后仍有实质阻塞则停止并列明阻塞、已完成部分及缩小范围/继续审查的建议；不虚报通过。若已收敛则结束，不追求零意见。不得为消除低价值意见不断补机制。
- 合同里出现 brief 和 `SKELETON.md` 都没提到的机制（锁、日志、重试、新的状态），要求 Agent 说明是哪条需求需要它；说不出来就删掉。

## 你要做的只有三件事

1. 对目标、范围及真实产品/科研取舍作决定；可在设计交付时审阅假设，不必在 Agent 开始所有设计工作前逐项批准。
2. 合并前按本阶段的验收要求亲自验收，明确授权 Ready；不把设计验收等同于未来实施验收。
3. 先设计的任务在独立审查后核对假设与结论，确认设计并合并后再授权实施。
