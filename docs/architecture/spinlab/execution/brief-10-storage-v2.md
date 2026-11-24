# 任务 10：Storage v2 路径与 Batch 生长参数权威（Design）

前置：任务 3（#224）、4（#225）已合并。先用 `taskType: "design"` 审查本合同和 `SKELETON.md` K1–K13，再实施。**本 PR #227 只做设计，不修改 Swift 或真实 Library。**

## 目标与已定规则

```text
Library/
  records/
    batches/<batchID>/batch.json
    samples/<sampleUID>/sample.json
  storage/<assetID>/...      # 任务 5 开始实现
  _spinlab/                  # 布局版本标记；现有 Result Definition Catalog
    library.sqlite          # 任务 5 开始实现资产关系
```

1. **科研逻辑不变**：Batch 是一次 PLD 生长、沿用 Batch ID；Sample 永久 UID 不含批次语义，以 `sample.batchId` 归属 Batch。目录平级，UI 仍按 Batch → Sample 展示。一个 Sample 只能有一个可写 `sample.json`，`batch.json.sampleKeys` 不再是第二份成员权威。
2. **Growth Parameter 只有 Batch 权威，且只有一份定义**：以“新建样品”表单为准——日期、实验室、生长材料，以及生长温度、氧压、样品高度、前端能量、激光电压、激光输出能量、衰减器、预打/生长脉冲数、生长脉冲频率、RHEED，都是同一次生长的共同事实，由 `batch.json` 持有；Sample 通过 `batchId` 读取，不另存拷贝。衬底（处理/材料/取向）属于 Sample：每个 Sample 记录自己的 `batchId` 和衬底，`batch.json` 不记录“衬底—样品”对应表；界面上“批次 → 各衬底及其样品”的视图由查询得出。一次提交的每个明确创建的 Sample 拥有独立 UID，共用同一个 Batch；同一 Batch、同类衬底允许由用户决定是否分别建档，程序不强制物理衬底与 Sample 一一对应（见 K3）。
   - **唯一定义与兼容映射**：只保留一份物理字段定义（以新建样品表单的规范 Growth Parameter 定义为唯一权威）；`LibraryFieldOwnershipRuleBook` 与 `config/library_import_rules.json` 中的旧 Registry Excel 列名/数值别名不再作为独立的一套物理字段定义，而是收口为**指向该规范定义的兼容映射**，确保旧 Excel 列名和历史 V1 库数据仍能正确读取与归属，不因清理配置而丢失旧数据。**清理是验收项**：实施完成后，代码和配置里不得残留第二套独立维护的“Batch 物理字段定义”，过时注释一并清理；已废弃的错误条目（如把“厚度”映射到预打/生长次数的旧别名，以及样品过滤里的厚度条件）一并去掉，不留半截定义。
   - **命名区分**：表单中的“温度”“frequency”是生长条件，在 V2 须明确命名为生长温度、生长脉冲频率；测量温度、测量 frequency 是每次测量的条件，不属于 Batch 或 Sample 记录，本任务不触碰。裸的“温度”“temperature”不再默认归入 Batch，无依据的字段保持未知。
   - **修改入口**：生长参数只在 Batch 上修改；样品页对这些值只读显示。新建样品并同时新建 Batch 时，所填生长参数写入该 Batch；所属 Batch 已存在时直接显示 Batch 的值，不重复填写。
   - 旧值冲突先报告、不自动选边；冲突可阻止向 V2 合并或迁移，但不应阻止原本合法的 V1 Library 正常读取与使用。
   - 样品过滤和测量搜索目前读取 Sample 上的数值，实施时须改为读取 Batch 的生长参数。
   - **目的、备注**不是归一化参数，只是写给自己看的文字：从新建样品表单去掉。每个 Sample 须提供可用的自由文本备注入口（样品页直接查看和编辑，随 `sample.json` 保存，不进 Batch、不进归一化字段），用于写给自己看的任何说明，目的也写在这里；既有的目的/备注数据保留不动，不丢失。该入口须在实施 PR 中实际可用并经测试库验证，不能只存在于代码里。
3. **保留任务 4 Result 模型**：`_spinlab/result_definitions.json` 仍定义全库格子；Sample 的 `sample.json.results` 是各自当前数值唯一权威，未填的格子不落盘。V2 不额外复制进 SQLite、Batch 或另一份 Sample。
4. **资产留给任务 5**：本任务仅负责版本、路径、Batch/Sample 记录与新旧路由；Source/Dataset/Plot 的 `storage/` 与 SQLite 多对多关联、共享文件删除留给任务 5。不能在任务 10 搬旧资产或改 Workbench 算法。

## 设计前必须核对的代码

- **V1 路径和索引**：`LibraryStore+PathsAndCache.swift` 同时支持 `batches/<prefix>/<batchID>`、`batches/<batchID>`；`LibraryStore+RootAndIndex.swift` 通过 Batch 目录扫描 Sample。顶层 `samples/<sampleKey>/` 属于旧 Workbench 产物，不是新的正式 Sample。
- **读写与成员关系**：盘点 `LibraryStore+Drawers.swift`、`NativeSampleCreationService`、`LibraryMutationService`、索引及 `reconcileBatchSampleKeys` 的所有 `sampleKeys` 读写点；不能保留两个可写正式目录。
- **字段归属**：`LibraryRegistryParser.swift` 同时将 Numeric Tags 放入 Batch 和 Sample；结合 `LibraryFieldOwnershipRuleBook` 审核 Registry Apply、Sample 创建/编辑、展示与查询对这些字段的使用。未知保持未知。
- **旧路径消费者**：核对 Sidecar、`measurement_sets.json`、`measurement_data.json`、Result/Plot 索引、图表、回收站/永久删除、备份、Publish/手机拾取等直接拼路径的入口，标明在本任务改、继续仅支持 V1，或等任务 5。不能让 V2 请求悄悄写进 V1 目录。

## 兼容、安全和范围

- **新版继续支持 V1 旧库**（含两种 Batch 路径，**V1 旧库无版本标记**）。V2 需要明确的布局版本标记及统一路由；不靠某目录存在就猜版本。缺失标记时须区分：**可识别的合法 V1 旧库**（存在 `batches/` 或 `index/`，且无 `records/` 与 V2 标记）允许按 V1 读写；**疑似 V2 或混合/异常目录但缺失标记**（如存在 `records/`、或 `batches/` 与 `records/` 混放、或非空未知目录）、未知版本标记、标记与目录不符、冲突身份、缺损索引，一律 fail-closed（K13）；任务 3 的同 Library 单写者许可照常适用。
- 用户承诺访问同一 Library 的所有电脑都升级到兼容版，**不支持旧版 App 对 V2 库降级写入**，不要求为此构建旧版拦截层；也不能声称旧版打开 V2 安全。
- 仅在独立测试 Library 验证新路径。未完成的 V2 消费者必须限制写入或继续使用完整 V1 流程，不能半开通。**不迁移、不改写、不删除用户真实旧库**；任务 11 才另行授权备份、UID/旧 Key 校验、生长字段冲突比对、Result 保全、迁移和恢复。

## 设计交付和验收

1. **路径与版本合同**：V1 两种 Batch 形式、V2 唯一目录、布局标记/失败处理、统一读写接口、切换边界。
2. **字段与消费者清单**：Growth 字段 Batch 唯一权威、Unknown 留存、`sampleKeys` 读写点、Result Catalog/Values 保全；对各旧路径消费者说明本任务/任务 5 的分工。
3. **测试库验收计划**：V1 读写/新建/Registry/Result/废纸篓/重启无回归；V2 UID/Batch 归属/生长字段、两种 V1 路径、混合/损坏拒绝写、无双重正式记录、无真实数据变更。不要把“目录能创建”当成“V2 已可全面投入使用”。

## 测试库验收计划

全部在独立的临时测试 Library 中进行，测试配置不得指向真实 Library。准备五种样本库：V1（`batches/<前缀>/<批次>`）、V1（`batches/<批次>`）、两种 V1 形式混放、V2、损坏的 V2（存在 `records/` 但标记缺失、未知版本、记录重复）。

1. **V1 不回归（两种路径形式都测）**：打开与索引；新建样品（含一次多块衬底）；编辑；Registry 同步与 Apply；Result 定义与数值；移入废纸篓、恢复、永久删除；重启后内容一致；打开时批次目录前缀整理的行为与改动前一致。
2. **版本识别与拒写**：无版本标记的合法 V1 旧库（含两种 Batch 路径及混放）可正常读写；疑似 V2 但标记缺失（如存在 `records/` 而无版本标记）、未知版本、标记与实际目录不符、V1 与 V2 混合，一律拒绝写入并给出明确提示，不当作空库，也不按目录是否存在猜 V2。
3. **V2 记录唯一**：新建样品后，只在 `records/samples/<sampleUID>/` 出现一个 `sample.json`；`batches/` 和旧 `samples/` 下不产生任何文件；**V2 不再维护 `batch.json.sampleKeys`**（新建 V2 Batch 不写该字段，读取时忽略），Batch 成员关系只按 Sample 的 `batchId` 查询得出；同一 UID 出现两处时拒绝，不自动选边。V1 旧库的 `sampleKeys` 在兼容层继续处理，其与 `batchId` 的历史冲突留待任务 11 迁移预检报告。
4. **生长参数**：新建 Batch 同时新建样品，生长参数写入 Batch；所属 Batch 已存在时样品页显示 Batch 的值；`sample.json` 中不存生长参数；修改只能在 Batch 上进行，改后该 Batch 下所有样品显示同步变化；样品过滤与测量搜索读取 Batch 的值；旧 Registry 列名映射到统一定义，裸“温度”保持未知；测量温度与测量 frequency 不受影响；旧库中 Batch 与 Sample 值冲突时报告并阻止向 V2 合并/迁移，不自动选边，但不阻止合法 V1 Library 的正常读取与使用。
5. **备注**：新建样品表单不再出现目的和备注；样品备注框输入、保存、重启后仍在；旧的目的/备注首次显示时拼接、未保存前不写盘，保存后旧数据仍保留。
6. **Result 保全**：Result 定义与各样品数值在 V2 创建、读取后与 V1 一致，未填格子不落盘，SQLite 中无副本。
7. **未迁移的消费者**：对 Sidecar、测量数据文件、图表、废纸篓、备份、Publish/手机新建逐一在 V2 库上触发，断言要么正常工作，要么明确拒绝；任何情况下都不得在 V1 路径下产生文件。
8. **不变量扫描**：每个用例结束后扫描目录树，确认无重复 `sampleUID`、无同一样品的第二份 `sample.json`；测试前后对真实 Library 路径不做任何读写（以路径隔离与测试配置断言证明）。
9. **界面验证**：新建样品表单和样品备注框，按 `spinlab-gui-validation` 在隔离虚拟机里用测试库验证；不用真实 Library。

通过标准：以上全部通过，且“目录能创建”不被当作“V2 可全面使用”。

**实施拆分（已知必拆）**：审计显示 `sampleKeys` 读写点、直接拼 `batches/` 路径或按路径位置解析批次的消费者（导入去重、测量搜索、安全守卫、图表审计、旧样品回填等）数量较多，一个 PR 做不完。建议先做“布局版本标记 + 统一路径路由 + V2 写保护”，再做“生长参数单权威 + 过滤/搜索改读 Batch”。旧库打开时现有的批次目录前缀整理行为保持不变，V2 库不得触发它。不增设第二套权威。首次涉及实际需迁移的 Library 主版本变更，遵守 `AGENTS.md` 的逐次明确 major approval；本设计 PR 不代表授权。
