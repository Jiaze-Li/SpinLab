# 任务 10：Library Storage v2 路径与 Batch 生长条件权威（Design）

前置：任务 3 单写者（PR #224）已完成；任务 4 Result Definition/Values（PR #225）已完成。本任务按 `taskType: "design"` 先确认方案和验收，再另行实施。以 `SKELETON.md` K1–K13 为共同约束。

## 目标与既定路线

**科研组织与文件位置分离**：界面继续 Batch → Sample；V2 的正式记录按类型平级存放，Sample 以稳定 `sampleUID` 作为存储定位，`sample.batchId` 表达所属批次。

```text
Library/
  records/
    batches/<batchID>/batch.json
    samples/<sampleUID>/sample.json
  storage/<assetID>/...                  # 任务 5 起承接独立资产
  _spinlab/                              # 布局版本标记 / 现有 result_definitions.json
    library.sqlite                      # 任务 5 起才引入资产关联
```

- **唯一权威**：`sample.json` 是一个 Sample 的唯一正式记录，Batch 的 Sample 成员由归属查询获得；V2 不让 `batch.json.sampleKeys` 成为第二套写入权威。Batch 是一次 PLD 生长的科研分组，以已有 Batch ID 定位，不增造机器 Batch UID。
- **Growth Parameters**：仅对已确认属于整次生长的字段（生长温度、氧压、激光能量等），由 Batch 正式持有，Sample 通过 `batchId` 读取。Numeric Tag 是现有旧字段容器，不是科研类别。未分类字段不猜测，不把 Sample 独有科研事实移到 Batch。
- **保护已落地数据**：`_spinlab/result_definitions.json` 仍是全库 Definition 的唯一权威，`sample.json.results` 仍是每个 Sample 的当前值；空槽位不落盘。不复制到 SQLite / Batch / 第二个 Sample 文件，不重新解释或重写这些值。
- **资产边界**：本任务只建立路径/版本/Batch-Sample 记录与旧库兼容基础；Source/Dataset/Plot 的独立 `storage/` 与 SQLite 关联交给任务 5。不可提前移动共享资产或拆改 Workbench 分析算法。

## 首轮设计必须核对的现有代码

1. **V1 布局**：`LibraryStore+PathsAndCache.swift` 中 `batches/<prefix>/<batchID>` 与 `batches/<batchID>` 两种路径、`resolvedBatchDirectoryURL` 按存在性选择、`sampleDirectoryURL`；`LibraryArtifactLayout.swift` 顶层 `samples/<sampleKey>/` 是旧产物目录而不是 Sample 正式记录，另有 `_spinlab/multi-sample/`。
2. **扫描与索引**：`LibraryStore+RootAndIndex.swift` 的 `scanIndexFromFilesystem`、`syncIndexFromFilesystem`、`decodeSamples` 及索引重建；`LibraryStore+Drawers.swift` 中样品创建、更新、回收站、永久删除、`reconcileBatchSampleKeys` 的读写点。列出全部 `batch.sampleKeys` 消费者及新写入/派生策略。
3. **Batch 字段**：`LibraryRegistryParser.swift` 同时生成 Batch/Sample `numericTags` 和 `numericDisplay` 的路径；`LibraryFieldOwnershipRuleBook` 的 Batch / Sample / Unknown 分类；`NativeSampleCreationService`、Registry Apply、Sample 编辑、列表/Workbench 搜索、Publish 和手机拾取使用这些字段的入口。设计须明确只动已确认生长字段的权威，V1 现存值不被静默删改。
4. **科研文件消费者**：逐一识别 Sidecar、`measurement_sets.json`、`measurement_data.json`、Results/Plot 索引、图表、AFM、备份、删除/恢复与 Publish 等直接拼装 V1 路径的代码；对 V2 明确由路由处理、阶段内维持 V1，或明确禁止 V2 写入，不能漏到旧目录造成分裂。
5. **写权限**：复用任务 3 已实现的 `LibraryWriteLease`；V2 版式标记必须先辨识，不能因为 Library 中同时存在旧目录或残留目录就猜写入位置，遇到未知/损坏/混合结构时 fail-closed。

## 兼容与部署约定

- **必须支持**：当前新版 App 继续完整读写既有 V1 Library（含两种 Batch 路径），不因引入路径基础改变真实库；新的 V2 在独立测试 Library 中验证。V2 使用明确的布局版本标记与单一路由，不让同一个 Sample 同时成为 V1/V2 的两个可写实体。
- **不要求支持**：合并前旧版 SpinLab 修改或写入 V2 Library。用户单人使用，保证访问同一 Library 的设备升级到当前兼容版本，不支持降级回写；因此不建旧版互操作/拦截兼容层，也不以“旧版写 V2”作为本任务验收。不过不能声称旧版操作安全。
- **尚不启用全库迁移**：任务 10 不把真实 Library 自动升级为 V2，不自动重命名旧 Sample Key、移动原始测量/图片或清理 V1。若部分 V2 消费者需任务 5 才可正确运行，在本阶段限制 V2 仅为测试/明确受控入口，并对未支持写入 fail-closed。
- **正式迁移另做**：任务 11 在任务 10、5 与相关消费者验收后，另行授权预演、备份、UID/旧 Key 核对、Growth Parameters 冲突报告、Result Catalog/Values 核验、切换与恢复。任务 10 的设计不预先授权改用户数据。

## 设计交付与验收要求

1. 提交最短可落地的 **V1/V2 路径与版本合同**：版本标记位置/读取时机、两个 V1 Batch 形态的显式分辨、权威文件位置、禁止混写条件、读写接口和迁移隔离；区分当前已验证的代码事实与目标设计。
2. 提交 **Batch/Sample 属性归属表**：已确认 Growth Parameters 的读写权威、Unknown 的保留策略、Registry 原字段投影兼容、`sampleKeys` 全部读写点清单；不编造不存在的生长字段，不默认旧值一致。
3. 提交 **旧路径消费者清单及最小阶段切换顺序**：索引/新建/编辑/Result/测量/图/回收站/Publish/备份，标注哪些在任务 10 改、哪些保持 V1、哪些必须等待任务 5；不可将“新建路径能写”误当作全部新库可用。
4. 测试库覆盖：V1 新建、读取、编辑、Registry 同步、Result 保存、回收站/还原、重启完全不回归；V2 记录身份/Batch 归属与 Growth 字段唯一性；两类旧 Batch 路径；混合/损坏/无法读写时阻止写入；同一样品不能两处同时写；测试无真实用户数据移动、清理或批量重写。
5. 如果目标实现超出一个可审 PR，则依据消费者边界拆子 PR，但仍只有一份任务 10 合同与同一套最终验收，不引入多种竞争的正式存储权威。

## 不做

不做用户真实旧库迁移、一次性全工作流资产搬迁、SQLite Sample—Asset 关系、人工参数/Result 概念重做、旧版 App 向前兼容、多电脑互斥或自动恢复系统。

## 开工

本 PR #227 是 **Design Draft**，只提交上述合同及 Roadmap/执行说明。实现 Agent 从最新主线核对代码，以 `taskType: "design"` 走设计审查；设计通过、用户确认关键假设后，才在独立实现 PR 或后续阶段提交 Swift/测试。若实施内容改变 `SKELETON.md`，同 PR 同步更新。仅真实实现合并时勾选任务 10；任何 Library 格式版本号重大升级遵守 `AGENTS.md` 的显式 major approval 规则。
