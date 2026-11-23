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
2. **Growth Parameter 只有 Batch 权威，且只有一份定义**：以“新建样品”表单为准——日期、实验室、生长材料，以及生长温度、氧压、样品高度、前端能量、激光电压、激光输出能量、衰减器、预打/生长脉冲数、生长脉冲频率、RHEED，都是同一次生长的共同事实，由 `batch.json` 持有；Sample 通过 `batchId` 读取，不另存拷贝。衬底（处理/材料/取向）属于 Sample：每个 Sample 记录自己的 `batchId` 和衬底，`batch.json` 不记录“衬底—样品”对应表；界面上“批次 → 各衬底及其样品”的视图由查询得出。一次生长多块衬底时，各自是一个 Sample，共用同一个 Batch。
   - **唯一定义**：实施时以这一份定义取代现有按 Registry Excel 列名确定的 Batch 字段名单（`LibraryFieldOwnershipRuleBook`）以及 `config/library_import_rules.json` 中另行定义的数值别名，不保留两套；旧 Registry 列名仅作为读取旧库的映射，映射到这份定义上。**清理是验收项**：实施完成后，代码和配置里不得残留第二份“哪些字段归 Batch”的名单、别名或过时注释；旧的 Excel 名单、`numericKeyAliases` 中已被取代的条目一并删除或改为指向这份定义。**“厚度”暂不考虑**：把“厚度”映射到预打/生长次数的旧别名，以及样品过滤里的厚度条件，一并去掉，不留半截定义。
   - **命名区分**：表单中的“温度”“frequency”是生长条件，在 V2 须明确命名为生长温度、生长脉冲频率；测量温度、测量 frequency 是每次测量的条件，不属于 Batch 或 Sample 记录，本任务不触碰。裸的“温度”“temperature”不再默认归入 Batch，无依据的字段保持未知。
   - **修改入口**：生长参数只在 Batch 上修改；样品页对这些值只读显示。新建样品并同时新建 Batch 时，所填生长参数写入该 Batch；所属 Batch 已存在时直接显示 Batch 的值，不重复填写。
   - 旧值冲突先报告，不自动选边。
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

- **新版继续支持 V1 旧库**（含两种 Batch 路径）。V2 需要明确的布局版本标记及统一路由；不靠某目录存在就猜版本。混合布局、冲突身份、未知标记、缺损索引须 fail-closed（K13）；任务 3 的同 Library 单写者许可照常适用。
- 用户承诺访问同一 Library 的所有电脑都升级到兼容版，**不支持旧版 App 对 V2 库降级写入**，不要求为此构建旧版拦截层；也不能声称旧版打开 V2 安全。
- 仅在独立测试 Library 验证新路径。未完成的 V2 消费者必须限制写入或继续使用完整 V1 流程，不能半开通。**不迁移、不改写、不删除用户真实旧库**；任务 11 才另行授权备份、UID/旧 Key 校验、生长字段冲突比对、Result 保全、迁移和恢复。

## 设计交付和验收

1. **路径与版本合同**：V1 两种 Batch 形式、V2 唯一目录、布局标记/失败处理、统一读写接口、切换边界。
2. **字段与消费者清单**：Growth 字段 Batch 唯一权威、Unknown 留存、`sampleKeys` 读写点、Result Catalog/Values 保全；对各旧路径消费者说明本任务/任务 5 的分工。
3. **测试库验收计划**：V1 读写/新建/Registry/Result/废纸篓/重启无回归；V2 UID/Batch 归属/生长字段、两种 V1 路径、混合/损坏拒绝写、无双重正式记录、无真实数据变更。不要把“目录能创建”当成“V2 已可全面投入使用”。

**实施拆分（已知必拆）**：审计显示 `sampleKeys` 读写点、直接拼 `batches/` 路径或按路径位置解析批次的消费者（导入去重、测量搜索、安全守卫、图表审计、旧样品回填等）数量较多，一个 PR 做不完。建议先做“布局版本标记 + 统一路径路由 + V2 写保护”，再做“生长参数单权威 + 过滤/搜索改读 Batch”。旧库打开时现有的批次目录前缀整理行为保持不变，V2 库不得触发它。不增设第二套权威。首次涉及实际需迁移的 Library 主版本变更，遵守 `AGENTS.md` 的逐次明确 major approval；本设计 PR 不代表授权。
