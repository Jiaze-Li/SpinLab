# 任务 11A 设计：旧 Library → Storage V2 迁移准备度与兼容性审计

对应需求合同：[brief-11-v2-migration.md](brief-11-v2-migration.md)；共同语义：[SKELETON.md](SKELETON.md) K1–K13；前置：[design-10](design-10-storage-v2.md)、[design-5](design-5-afm-standard-assets.md)、[design-12](design-12-workbench-sample-results.md)。

基线：main `03033959`（v6.12.0）+ 本分支 brief 提交。2026-11-28 收口修订：依据 Audit A/B 与 #247 评论中的用户决策，§0、§3.2、§4、§5、§6.5、§8 已改写为最终路线；其余章节为证据与细则。**本文只含设计与静态审计**：没有改 Swift，没有运行 App，本文自身没有读取真实 Library（真实库只读审计另见 Audit A，且无写入），没有任何迁移。除 Audit A（经授权的真实库只读检查，脱敏汇总见 audit-11-real-library-summary.md）外，所有“代码证据”均为静态读码（文件/符号），证据类型已逐项标明；凡未运行验证的都列在 §8。

---

## 0. 最终路线（2026-11-28 收口）

本节是本文的权威结论；§2 矩阵与 §3 清单是证据和细则。路线依据：Audit A（真实库只读数据可再生性，本地完整报告 + 脱敏汇总 [`audit-11-real-library-summary.md`](audit-11-real-library-summary.md)）、Audit B（[`audit-11-cross-workflow-architecture.md`](audit-11-cross-workflow-architecture.md)）和 #247 评论中 Jack 的产品决策。

### 0.1 已确认的产品方向（Jack 的决策，不再作为待选项）

1. **一个正式库**：V2 是同一 Library 的升级。V1 只作完整、静态的升级安全备份，不长期并行；单机、单库、单写者，不预建多设备协调。
2. **数据取舍**：不可替代的科研信息无损保全；可重算的旧 Plot、Analysis Pack、历史指标不建历史兼容层、不强制恢复。切换前 V1 仍须正常使用，不提前拆 V1 日常支持。
3. **统一逻辑生命周期，不统一数据形态**：读取标准 Dataset → 科研语义与处理 → 绘图数据组织/坐标映射 → 公共渲染与交互 → 成果保存。各 Workflow 保留自己的物理逻辑；公共能力先复用已有的，共享工具必须有真实消费者；改科研配置须重算相关数据，纯显示配置只重绘。
4. **MR**：明确清理旧半成品，而非保留旧 Workflow（Jack 的最终补充决策，#247，2026-11-28；落实见 §5.1c）。**RSM** 纳入正常接入（与 AFM 共享 Heatmap，与表格型工作流共享标准数据机制）；非 AFM 自动出图暂缓，**非 AFM 的手工 Plot 保存是既有能力，新图保存不省略**。
4b. **Measurement Set 默认不迁移旧 UI 分组机制**（同一补充决策；只读复核结论见 §5.1c）。
5. 正式迁移、真实库读取/复制/预演、版本号（major）各自仍需独立授权。

### 0.2 审计结论（证据见 §2、§3 与两份审计报告）

1. 真实库是纯 V1，无 V2 数据。Source 约 1390 个，约 79% 的原始外部路径已不存在，库内副本基本是唯一副本；测量条件只存在于文件名；没有内容哈希。**Source 字节、文件名和 mtime 是最不可替代的数据。**
2. 真正的人工信息很少（63 条条件覆盖、4 个真实 workflow 改派、3 条手工数值修正、1 个 Result 值 + 2 个定义、84 个测量集经只读复核全是显示分组（§5.1c）、约 17 个原生样品/9 个原生 Batch、全部样品的永久 UID（约 360 个，总数）、软删状态），可迁移且体量小。条件、substrate、测量时间戳重算 100% 一致，属可再生。
3. 公共缺口集中在**测量上下文**（工作流、通道、条件及来源、测量时间）没有 V2 落点，和**一维表格标准 Dataset**；解析器与资产事务层不缺。AFM 的入库事务、多 Dataset、修订、删除、泛型读取、Plot 存储与工作流无关，可直接复用。
4. 旧版“一个文件复制进每个归属样品”的做法真实库已有约 85 组，天然对应 K5 的“每个 Source 恰一个 Sample”，因此**每个目标样品各存完整 Source + 有效通道**是延续而不是新负担。
5. V2 未被 App 当前版本识别的缺口（§2.1–§2.4）仍成立；**V2 目前没有一致备份**；非 AFM 在 V2 无法入库。这些由 §4 的工作包解决。

### 0.3 路线

- **切换形态**：在新位置构建完整 V2 副本，对账后切换根位置；源库不改，仅在验收后写入一次迁移墓碑（§6）；冻结锁、迁移进行中哨兵、租约交接方向保持（91c65c38）。
- **迁移范围**：§3.2 的最小必迁清单；旧 Plot/Pack/指标/旧索引不迁，只随完整静态备份保存。
- **实施拆分**：§4 的工作包 WP0–WP9，AHE 入库→分析→正式 Plot/Result 闭环是第一个真实消费者；公共 Plot 能力随它建设后复用。
- **本阶段不做**：不改 Swift、不动真实库、不迁移、不改版本号；Roadmap Task 11 保持未完成，no-release。

---

---

## 1. 方法与证据口径

- 审计对象是 main 当前源码；已有 PR 文档/验收报告只作线索，不当作本轮验证。
- 证据类型：**S** = 静态读码（本文）；**D** = 已有设计文档声明；**T** = 已有测试存在（未在本轮运行，仅核对文件存在，如 `StorageV2LayoutRoutingTests.swift`）；**?** = 未知，须 11B 夹具验证。
- “支持”只在读码确认完整读/写/删除路径存在时才写；入口存在不等于可用。
- 不使用真实 Library；所有后续验证用合成夹具（见 §7）。

---

## 2. V1/V2 消费者兼容矩阵（AC1）

状态：✔ 支持 / ◐ 部分（说明）/ ✖ V2 明确拒绝 / ? 未知。“迁移后影响”指真实旧库切到 V2 后用户可见的结果。

### 2.1 布局、身份与记录

| 消费者 | 用户行为 / 读写对象与权威 | 代码证据（S） | V1 | V2 | 迁移后影响 | 最小修复 / 备注 |
|---|---|---|---|---|---|---|
| 布局识别 | 版本标记、混合/损坏 fail-closed | `LibraryLayoutRouter.resolve`；V2 要求 `_spinlab/layout_version.json` 且不得存在顶层 `batches/`；仅检查 `batches/`、`records/`、`index/`，**不检查顶层 `samples/`** | ✔（无标记合法） | ✔ | 源库的 `batches/` 不能与 V2 并存 ⇒ 不能原地转换，须副本 | 顶层 `samples/` 在 V2 下既不被拒也不被读（见 2.4），预检断言副本不得含顶层 `samples/`（§4.1） |
| Batch/Sample 记录读写 | `batch.json`、`sample.json` | `LibraryStore+PathsAndCache`（`sampleDirectoryURL` 按布局路由，V2 取 `records/samples/<uid>`）、`+Drawers`、`+RootAndIndex`（V2 扫描 `records/samples/*`，重复 UID、缺 UID 记 issue） | ✔ | ✔（T：`StorageV2LayoutRoutingTests`） | 目录名由 sampleKey 变 UID | 前提：全部 Sample 有合法唯一 `sampleUID`（见 §3） |
| 新建样品（桌面/手机） | `NativeSampleCreationService`、`PhoneSamplePickup` | `NativeSampleCreationService`（`resolveLayout().isV2` 分支）；手机 UID 由提交号确定性生成 | ✔ | ✔(S，D) | 无退化 | 夹具回归即可 |
| Growth 权威 | V2 在 Batch 上唯一权威，Sample 页只读 | design-10 §2.2（D）；实际落地状态：10B 已合并（#229，2026-11-24，经 GitHub 核实）；其代码行为是否与 design-10 完全一致仍 **?**，11B 起点按代码核对 | 兼容保留 | ✔(D) | 旧库重复/冲突须报告 | §3 |
| Result Definitions / 当前值 | `_spinlab/result_definitions.json` + `sample.json.results` | `LibraryResultService`（按布局路由，V2 用 UID）；Task 12 设计 F7（D） | ✔ | ✔ | 原样保留 | 迁移：忠实复制，对账精确值/单位/空 |

### 2.2 Inbox、原始文件与标准化

| 消费者 | 证据（S） | V1 | V2 | 迁移后影响 | 最小修复 |
|---|---|---|---|---|---|
| Inbox 路由/确认 | `InboxSelectionWorkbenchPanel`（`isV2LibraryLayout` 分支，非 AFM 时不可确认） | ✔ 全部工作流 | ◐ 仅 AFM | **非 AFM 新测量无法入库** | 类①，见 WP1–WP7 |
| Inbox Apply | `InboxArchiveApplyService.standardizationAdapter(forWorkflowID:)` 只返回 `AFMIBWStandardizationAdapter`（`"afm"`），其余 `nil` → `applyV2` 抛 `LibraryLayoutError.v2UnsupportedOperation`（S） | ✔ | ◐ 仅 AFM | 同上 | WP1–WP7（逐工作流） |
| 原始文件复制 | `LibraryStore.copyMeasurementFile`：V2 或布局无效直接 `nil`；V1 复制到 `<sample>/measurements/` | ✔ | ✖（不复制） | 同上 | 随 WP1–WP7 |
| 侧车 / `measurement_sets.json` 写入 | `LibraryStore.saveMeasurementSets` 经 `requireV1ArtifactWriteAllowed`，V2 抛 `v2UnsupportedOperation`；`LibrarySidecarWriter.saveSidecar` 自身无布局守卫，V2 下由上游 Apply 入口拦截（S） | ✔ | ✖ | 同上 | 随 WP1–WP7 |
| 导入去重 | `SpinLabAppState+ImportDeduplication`：非 V1 直接返回 `[]`（V2 无 V1 去重）；AFM 由资产库 `findSources(sha256:ownedBySampleUID:)` 去重 | ✔ | AFM ✔；其他工作流无入口所以无需 | 随 WP1/WP3 | 与 WP1 同步 |
| 原始文件字节不变 / 哈希 | `ContentFingerprintService`、`LibraryAssetService.ingestAsset`（登记 sha256，写入 `storage/`） | ✔（原样） | ✔（AFM） | AFM 重新入库可对账哈希 | §4 |

### 2.3 Workbench

| 工作流 | 读取 | 写入（Pack/图/指标） | V2 实际 | 迁移后影响 | 备注 |
|---|---|---|---|---|---|
| AFM | 标准 Dataset（`standardDatasetHits`，`inputRef == .datasetV2`） | 正式 Plot（`FormalPlotSaveBar`/`AFMWorkspaceStore+FormalPlot`）、自动出图（Task 7） | ✔(D、T) | AFM 历史须经标准 Dataset 重新入库后才在 V2 可见 | §4 |
| AHE | 旧侧车命中（`inputRef == nil`），身份为 `sampleKey`（Task 12 F9，D） | `PersistMeasurementData`、`PersistChartArtifact`、Pack：V2 抛不支持 | ✖ | 同类①，含 Result 赋值禁用 | 随 WP4（赋值恢复含在 WP4） |
| RT / 3ω / XY / IV / MR | 同 AHE（旧侧车 + 路径推导身份）；Workbench Store 中无 V2 分支（S：对这些 `*WorkspaceStore` 检索 `v2/V2` 无命中） | 同上 | ✖ | 同上 | RT/3ω 新增 Result 赋值是**新功能**，非阻塞 |
| RSM | 同上；`SaveRSMChartToLibraryUseCase` V2 返回 failure | ✖ | ✖ | 同上 | 按实际使用决定是否纳入 |
| 历史图 / Analysis Pack 打开 | 路径 `samples/<sampleKey>/charts`、`samples/<sampleKey>/_spinlab/*.json`（`LibraryArtifactLayout`）；Analysis Pack 在 `_spinlab/analysis_packs/<workflowID>/<packID>.json`（`AnalysisVault`，库级而非样品级） | — | **无 V2 读取方**（V2 样品目录无这些文件） | 历史成果在 V2 不可见 | 不迁移，随静态备份（§3.2） |
| 跨样品图 | `_spinlab/multi-sample/charts/`，manifest 记录**绝对原始路径**（SKELETON，D） | — | 无 V2 落点 | 绝对路径迁移后失效 | 只报告，不改写（§4） |
| 搜索 | `SearchWorkflowMeasurementsUseCase`：先扫全库侧车（根目录递归 `LibrarySidecarBulkReader`），V2 再追加 AFM 标准 Dataset 命中；`parsePathInfo` 用路径中的 `batches/…/samples/<key>/measurements/<workflow>` 推 batchID/sampleKey（S） | ✔ | AFM ✔；旧侧车命中在 V2 下**无物理来源** | 同上 | 路径即身份是迁移不能“搬目录”的直接证据 |

### 2.4 其它

| 消费者 | 证据（S） | V1 | V2 | 迁移后影响 | 备注 |
|---|---|---|---|---|---|
| 备份 | `LibraryStore.syncBackup`：V2 → `return false`（不一致拷贝风险，注释说明） | ✔ | ✖ 无备份 | 切换后没有自动备份，**也无法用现有机制做迁移前后备份对照** | **WP0，类①** |
| 废纸篓/恢复/永久删除 | V1：`LibraryStore+Drawers` 目录删除；V2：`LibraryAssetService+Deletion` + `LibraryTrashView` V2 分支；`LibrarySampleEmptyCheck` V2 分支 | ✔ | ✔(S，D：Task 9/5) | 无退化；迁移须保留废纸篓状态 | 恢复/删除对账进 §3 |
| 孤儿产物守卫 | `LibraryMutationSafetyGuard.detectOrphanArtifact`：V2 直接 `(false, nil)` | ✔ | ✔（V2 无旧目录） | 无 | 合法的跳过 |
| 旧 UID 补发 | `LegacySampleBackfillService`：V2 抛 `v2UnsupportedOperation`；V1 先预演、备份再原位补写 | ✔ | ✖（合理） | **必须在 V1 阶段先完成** | §3 前提 |
| Recompute 侧车 | `LibrarySidecarService.recomputeAllMeasurementSidecars`：V2/无效布局显式返回全零结果（静默空操作，S） | ✔ | ✖（空操作，无报错） | V2 下 Recompute 什么都不做；V2 无旧侧车，故无实际损失，但 UI 不应暗示已重算 | 随 WP1–WP7 一并处理提示 |
| Registry/XLSX 同步 | `LibrarySyncService`/`LibraryRegistrySyncService`/`LibraryXLSXSyncService` 对布局无显式分支，经 `LibraryStore` 路由（S）；V2 下是否全程正确 | ✔ | **?** | 未验证 | 11B 合成夹具回归（不预设为阻塞） |
| 旧产物审计/清理/图库 | `ChartAssetAuditService`、`LibraryDiskCleanupService`、`SamplePlotsOverviewService`、`WorkflowGalleryQueryService` 经 `LibraryArtifactLayout.samplesRootURL()` 直接操作顶层 `samples/`；`LibraryStore+Drawers` 永久删除 V1 分支删除 `samples/<key>`；均无布局守卫（S） | ✔ | **未定义**：V2 根下若存在顶层 `samples/`，这些服务会扫描甚至修改它 | 迁移副本**不得**含顶层 `samples/`（预检断言）；V2 无该目录时它们读到空 | 11B 夹具验证并考虑补守卫；强化 §4.1 ② |
| 手机提交 / Publish / 网页投影 | `PhoneSamplePickup`（经 `NativeSampleCreationService`）；`WebLibraryPublishService`（读索引/快照） | ✔ | ◐/？：手机新建 ✔（S，D）；Publish 读 V2 **?** | 未验证 | 11B 夹具回归 |
| 索引 | `index/library_index.json`（可重建）；V2 由 `records/` 扫描重建 | ✔ | ✔ | 重建而非迁移 | §4 |
| 单写者 | `LibraryWriteLease.shared` 是进程级单例：`acquire(rootURL:)` 先释放旧锁再锁新根；`ensureWritable` 只认当前持有的根；`flock` 锁文件在库外、按规范化路径命名（S） | ✔ | ✔ | **同一进程同时只能持有一个根的写租约**：构建副本时租约在副本上，源库不再被冻结；切换换根时旧库锁被释放 | §6.2 步骤 0/7、§6.4 |
| 入库服务前置 | `LibraryAssetService.requireV2`：`.v1`/`.uninitialized` 抛 `v2Required`；`ingestAsset` 等需根已解析为 V2（S） | — | ✔ 仅 V2 | 副本构建必须先被识别为 V2 才能复用入库服务 | §6.2 步骤 4 |

### 2.5 V1 必须保留

当前 App 对合法 V1 旧库继续完整读写，直到真实库正式切换并验收。11A/11B 都不得削弱 V1（AGENTS 与 SKELETON 已规定）。

---

## 3. 数据清单、语义映射与对账（AC2）

### 3.1 迁移前提（预检，全部通过才允许构建副本；任一失败只报告）

| # | 预检项 | 规则 | 失败处理 |
|---|---|---|---|
| P1 | 每个 Sample（活跃 + 废纸篓）有合法 `sampleUID`，全库唯一 | `SampleIdentityRule.isValidUID` | 报告；需先用现有 PR #220 补发流程在 V1 完成（会备份、原位写 `sample.json` 并重建索引，须先于预检基线；补发后重新预检） |
| P2 | 历史样品 `legacySampleKey` 映射 | 历史样品必有且与目录键一致；手工/手机新建样品可无（合法） | 不一致报告 |
| P3 | Batch 归属 | `sample.batchId` 指向存在的 Batch；`batch.sampleKeys` 与按 `batchId` 聚合的成员不一致 | 报告（V1 下不阻断使用，但迁移前须人工确认） |
| P4 | Growth 重复/冲突 | `batch.numericTags` 与 `sample.numericTags` 同名不同值；按 `LibraryFieldOwnershipRuleBook`，未知保持未知 | 冲突阻止该样品迁移，**不自动选边**；一致重复不是冲突 |
| P5 | 未知 JSON 字段 | 现有模型用显式 `CodingKeys`，经 Codable 重编码会**丢失未知字段**（S，`LibrarySample` CodingKeys） | 设计规则：`sample.json`/`batch.json` 用 JSON 层“补充/重映射结构字段”，其余字段逐字节保留；不用模型往返 |
| P6 | Result Definitions / 当前值 | 目录完整可解码；每个值的 `definitionID` 存在；空值保持空 | 孤立值报告，不删不补零 |
| P7 | 原始文件 | 每个侧车/测量集引用的原始文件存在且可读，登记 sha256 | 缺失/不可读报告，不猜 |
| P8 | 重复 Source | 同内容多个登记、同一文件被两个样品引用 | 报告；K5：同一 Source 不得有两个科研归属，不自动合并 |
| P9 | 绝对/外部路径引用 | 侧车 `sourceFilePath`、多样品图 manifest 等 | 报告，不改写 |
| P10 | 未登记文件 | 样品目录中不属于任何已知对象的文件 | 报告并**保留**（不当垃圾删除） |
| P11 | 归属权威一致性 | 旧侧车记录的 sampleKey/通道 与 Source 所在路径、文件名推断不一致（Audit A：约 9% 不可由文件名推出；Recompute 曾造成约 84 个 sampleID 差异） | 以侧车路由为权威；不一致只报告；**不调用 Recompute、不以文件名覆盖** |
| P12 | 外部依赖清单 | 列出 Library 之外且切换后仍需有效的位置：Registry xlsx、规则书、`LibrarySettings`（备份路径、Obsidian、Web Library、Registry 路径）、待导入队列 | 报告缺失；列入备份/恢复清单（§6.2 步骤 7） |
| P13 | 内容重复 | 同内容多拷贝（约 86 组，约 85 组为多通道拷贝）与同内容不同文件名 | 按归属各存一份 Source；不合并、不去重；仅报告 |
| P14 | 标准化可行性 | 对每个 Source 用目标适配器做内存级试标准化（含 LVM 丢行诊断）；失败/拒绝的列入 Source-only 清单 | 只报告；决定 Source-only 的原因逐文件记录 |

### 3.2 数据类别与迁移策略（依据 Audit A 分类 A–E 与 §0.1）

策略词：**保全**（字节/内容不变）、**转写**（只做结构变换，内容不变）、**再生**（规则重算，差异只报告）、**重建**（索引）、**归档**（仅留在静态备份）。

| 类别（Audit A 类） | 策略 | 对账标准 |
|---|---|---|
| Source 原始文件，含文件名、mtime（A） | **保全**。每个 V1 副本按其归属样品入库为一个 Source（沿用旧库已有的每样品副本；不合并去重，K5）；Source 字节 sha256 在迁移时计算并写入报告 | 每个 V1 Source 恰有一个 V2 Source；sha256 与源字节一致；文件名与 mtime 作为上下文记录；**不声称证明过去从未被修改**（旧库无哈希基线，仅证明“迁移时刻起”一致） |
| Source→Sample 归属与有效通道（A） | **保全**用户路由：以旧侧车记录的 sampleKey/通道为权威，**绝不用文件名推断覆盖**；约 9% 本来不可由文件名推出 | 归属映射表逐项对账；冲突只报告，不自选 |
| 测量上下文：确认的 workflow、通道、条件、测量时间（A/B 混合） | **规则可再生的字段用当前规则书重算并与旧值比对**，差异报告、默认保留旧值；**人工覆盖/改派原样转写并标记“人工”**；“真实改派/覆盖”的判据：与当前规则对该文件的输出不同（Audit A：195 条 workflow override 中 4 条属此类；63 条条件覆盖约 94% 与当前规则输出相同，其余约 6% 为规则缺值时补的；与规则一致者仍按“人工”保留标记但不构成额外决定）；不因规则重跑覆盖人工决定；**重算用只读重解析（内存中，不写任何 sidecar），迁移流程不调用 Recompute**（Audit A：Recompute 用库内副本路径会丢失文件夹上下文，造成约 84 个 sampleID 误差） | 人工项逐项一致；再生字段差异清单为零或已决 |
| `General` 中约 40 个 IBW（B，规则版本演进） | 在 AFM 适配器确认可有效标准化且不覆盖人工分类时，按当前规则归 AFM，**样品归属不变**；否则保留为 Source-only | 逐文件报告“重新分类/保留”原因 |
| 其他 workflow 的 Source（PPMS DAT、Zurich LVM、RSM 文本） | 经 WP2 适配器生成标准 Dataset；适配器缺失或标准化失败 → **Source-only**（保存 Source 与上下文，不伪装可分析） | 每个 Source 要么有 Dataset，要么有明确的 Source-only 原因 |
| MR（真实库有约 147 个 DAT Source，无图/无 Pack）及其他无适配器的合法原始文件（A） | **Source-only**（保全完整原始文件与既有归属，只保留 MR 数据分类；不迁 MR 专属 Workbench/占位/解析器/兼容逻辑，不建 MR 专用入库路径；任何情况不删原始文件）。MR 在 V1 切换前继续按现状使用，不提前拆 | 同上；MR 的 Source 数、归属、哈希前后一致 |
| Batch、Sample 记录、样品 UID、软删状态、原生创建字段（A） | **转写**（JSON 层最小结构变换，P5；不经模型往返，未知字段保留） | UID 集合相等；除结构字段外字节一致；废纸篓集合相等 |
| Result Definitions、Sample 当前值、数值手工修正（A） | **保全**（逐字节复制 + 新位置）；空值保持空 | Definition 集合与每个值（精确数值、单位、空值）一致 |
| Growth（Batch/Sample 重复） | 一致则保留；冲突则不迁该样品并报告，不自选边 | 冲突清单为零或已决 |
| Registry xlsx（外部源已不存在）、规则书（库外）、Registry/提交/笔记/变更日志（A） | **保全**（Registry 内部副本与规则书都在 Library 之外：原位保留，不复制进 V2 库，**列入迁移前备份与恢复清单**并核对哈希；V2 库内的 Registry/提交/笔记/变更日志原样复制） | 文件哈希一致 |
| Measurement Sets（84 个，只读复核均为显示分组，§5.1c） | **不迁移**：随 V1 静态备份保全旧记录；V2 不加集合标签字段、不新增 Measurement 实体、不维护旧分组 CRUD/兼容；常规按 Device 分组由测量上下文动态组织 | 迁移报告列“未迁移 Measurement Set 数”，且备份清单含 `measurement_sets.json` 全部文件 |
| 待确认导入队列、仅存于 sidecar 的回退时间戳（A 过渡） | 队列位于 Library 之外（应用支持目录），根位置切换不改它；其中以 sampleKey 指向的归属目标，迁移时用 `legacySampleKey→sampleUID` 映射重映射，无法映射或原件缺失的逐项报告、不删除；回退时间戳写入上下文（origin=fallback） | 队列项逐项“原件在/缺”报告 |
| 审计日志、原始路径、旧占位归档记录、项目分组（D/E） | **归档**：随静态备份保存；不迁入 V2；不当垃圾删除 | 备份清单含它们 |
| 旧 Plot 图片/manifest、`measurement_data.json` 指标、Analysis Pack、跨样品图、旧索引与投影、回填前备份、日志（C/D） | **归档/重建**：不迁、不建兼容层、不自动重算；索引由 V2 记录重建。真实库中的悬空引用（约 14 张图丢 PNG、5 个 Pack 引用悬空）仅在报告中列出，不阻塞 | 报告含“不迁移清单”并经用户确认；索引重建的样品/批次集合与源库一致 |

不迁移的清单即 Audit A 的 C/D/E 类；它们保留在**迁移前的完整静态备份**中，需要时从备份取回。

### 3.3 身份映射

输入键 `sampleKey`（V1，路径身份）→ 输出 `sampleUID`（V2，稳定）；映射表来自 `sample.json`（`sampleUID` + `legacySampleKey`），**迁移报告留存**该表；PR #220 的补发备份保留到验收完成（SKELETON）。Batch ID 不变。Asset ID 由 `ingestAsset` 生成并记录“旧原始文件路径 → Source ID → sha256”。

### 3.4 冲突原则

只报告：无法解释的冲突、孤儿、未知；不猜测、不合并、不删除、不补零、不覆盖、不重算、不标准化科研内容。冲突清单为空，或每项均有用户决定，才放行。

---

## 4. 阻塞项与实施拆分（AC3）

### 4.1 分类

**① 迁移前必须解决（既有必要能力丢失或数据不安全）：** V2 无一致备份；非 AFM 工作流无法在 V2 入库且 V2 无测量上下文/Source-only/多通道归属；非 AFM 的手工 Plot/Result 在 V2 不可用（AHE Result 赋值随 AHE 入库一起恢复）；迁移守卫（哨兵、墓碑）与对账工具。

**② 不建设的兼容：** V2 库内读取旧 `samples/`/`batches/`；旧 Plot/Analysis Pack/`measurement_data` 的读取与重算；sidecar v1 解码等（Audit A §可省略机制）。源库只作静态备份。顶层 `samples/` 不得出现在 V2 副本中（预检断言）。

**③ 不阻塞：** RT/3ω 新增 Result 赋值（新功能）；非 AFM 自动出图；MR 专项分析（V2 不再提供，未来确需时按公共架构重新接入）；旧 Measurement Set 机制的迁移；旧库重复样品合并。

### 4.2 工作包（逻辑依赖与独立验收；PR 交付分组见 §4.3）

依赖：WP0 独立并行；WP1→WP2→WP3→WP4→{WP5, WP6, WP7}；WP8 依赖 WP0（备份/回退演练）、WP1、WP2，可与 WP4–WP7 并行；WP8 即 brief 中的 11B；WP9 依赖全部且需单独授权。

| 包 | 范围（最小） | 模块边界与要点 | 验收（可执行，合成夹具） |
|---|---|---|---|
| **WP0** V2 一致备份（原 R0） | `LibraryStore.syncBackup` 对 V2 现返回 `false`；为 V2 提供与 SQLite（WAL）一致的备份并可还原，覆盖 `records/`、`storage/`、`_spinlab/` | 租约（Task 3）；不依赖其他包 | 合成 V2 库备份→还原→对账全一致；备份中途中断不留下被当成完整的备份 |
| **WP1** 测量上下文 + 归属 + Source-only | ① **测量上下文**：随 Source 在入库同一提交点落盘的唯一权威（已确认 workflow、通道及物理角色、条件及来源 rule/manual/fallback、测量时间、**源文件 mtime、原始文件名、旧库路径（只作记录，不作身份）**、必要规则版本/解释来源）；**有效通道属于 Source—Sample 直接关系，落 SQLite（K5 唯一权威），其余上下文在同一事务提交**；可批量查询 ② **多通道归属**：同一文件对每个目标 Sample 各入库一次，记录该 Source 的有效通道；Inbox 对同一操作重试幂等（沿用 `operationID`）③ **Source-only**：无适配器或标准化失败的合法原始文件，在明确状态下只保存 Source+上下文+完整性，不冒充 Dataset，可后续补生成 Dataset；成功/失败/重试/删除/查询边界清晰，复用 `LibraryAssetService` 事务，不另建仓库 | 解除 `ingestAsset` 现要求至少一个 Dataset 的限制（`LibraryAssetService.swift:293-294`，Audit B）；SQLite `schema_version` 当前严格要求等于 `"2"`（`LibraryAssetDatabase.swift:131/239`），故上下文落点需要明确升级策略——真实库无 V2 数据（Audit A），仅测试/开发库受影响，策略在包设计中定；Source→Sample 唯一归属不变（K5）；LVM 的 col0 等依赖实际测试语义的位置列，由用户确认的 workflow 决定，未知保留未知（K12） | 同一多通道文件入库两个样品得到两个 Source、各自通道范围，且一个样品的分析看不到另一个样品的通道；重复提交同一操作只产生一个结果；Source-only 的删除/恢复/查询与普通 Source 一致；上下文随删除闭包处理；崩溃注入后无半状态；mtime、原始文件名、旧路径往返读回逐值一致 |
| **WP2** 表格 Dataset + 容器适配器 | 一维表格标准 Dataset 的忠实编码（列的稳定键、原始表头、源列序号、原始单位、已知物理量或保持未知、诊断；数值块无损含 NaN、带 SHA-256），以及 `ppms_dat`、`zurich_lvm`、`rsm_text` 三个适配器；**只包装现有加载器，不重写解析**；适配器按容器格式选择，工作流写在上下文里 | AFM 矩阵保持自己的形态；LVM loader 静默丢短行（`ZurichLVMLoader.swift:100/117`）在标准化合同中明确：诊断记录丢弃的行数与位置，**不可静默改科研数据**；若数据行被丢弃，默认拒绝生成 Dataset 并转 Source-only，拒绝阈值由包设计用夹具证据定；`I_rms`、Rxy 等推导属分析，不进标准化层 | 三种格式各夹具 round-trip：解码后与加载器输出逐值一致；NaN/空列/诊断保留；丢行夹具得到拒绝或带诊断的明确结果；DAT 列位置变化只改映射不改存储 |
| **WP3** 公共查询与列/通道定位 | ① `standardDatasetHits` 不再固定 AFM 格式，命中的 `workflowID`、`conditions`、`channels`、测量时间取自上下文（现为写死 `afm`/空，`SearchWorkflowMeasurementsUseCase.swift:107-118`）；② 列/通道定位的唯一函数，**仅在有实际重复且有回归证据时收敛**（AHE/RT/XY 的列选择、4 份条件字符串解析、2 份 `I_rms`、现有但无调用方的 `SidecarConditionNormalizer`） | 不先造框架；来源缝由 WP4 作为第一份实现建设；V1 路径结果不变（现有 V3f/V3g/V3c/PR148 回归保持绿） | V1 既有搜索、图例、数字检索回归全绿；V2 命中带出上下文；列选择收敛后 AHE/RT/XY 在同一夹具上输出与改前逐值一致 |
| **WP4** AHE 闭环（第一个真实消费者） | **来源缝（首份实现）**：统一“命中 → 工作流读入内存数据（`LoadedMeasurement`）”（V1 走路径加载器，V2 解码 Dataset），之后推广到 WP5–WP7。AHE 在 V2：Inbox 入库（`ppms_dat`）→ Workbench 分析（经来源缝）→ **正式手工 Plot 保存（公共非 AFM Plot 格式在此建设：放开 `supportedPlotFormats`（现仅 `afm_plot_v1`）、`validatePlotRequest` 的格式校验，并让 `FormalPlotLibrary.summaries` 按格式路由（现固定 AFM codec 与标签，`FormalPlotCandidates.swift:119-146`）；一维序列图的数值不依赖 PNG，参考 AFM 的 Plot 保存）**→ Result 赋值恢复（Task 12 现在 V2 禁用，目标 Sample 用 UID） | 复用 Cartesian XY/Dual Axis 渲染与 `FormalPlotLibrary`，不为 AHE 另造渲染；Plot 保存边界与 K10/K11 一致；非 AFM 自动出图不在本包 | 合成 V2 库：AHE 新文件入库→重启可见→分析→保存 Plot→经 `FormalPlotLibrary` 列出并重新打开→赋值 Result→删除/恢复；同一夹具 V1 行为不回归；其余工作流在 V2 下的拒绝行为不变 |
| **WP5** PPMS 族 | RT（DAT）、XY-DAT 适配（上下文消费 + 来源缝），XY 的桥 2/3 固定等工作流语义留在各自解释层 | 不改科学算法；`workflow` 语义由上下文确认，不凭通道号猜 | 每个工作流同 WP4 的闭环，V1 回归 |
| **WP6** LVM 族 | 3ω → IV → XY-LVM → RT-LVM（RT 与 3ω 有跨工作流引用，故 3ω 先） | col0 含义由已确认 workflow 决定；IV 的多路回退在 V2 只用上下文条件，行为差异经夹具比对并披露 | 同上；IV 回退差异清单 |
| **WP7** RSM | `rsm_text` 适配、热图 Plot 保存（与 AFM 共享 Heatmap payload/渲染和公共 Plot 保存）；先核对实际规则本中 RSM 的启用与分类，不凭 `.txt` 猜 | RSM 原始 HKL/Intensity 表格不同于 AFM 二维通道矩阵，仅共享渲染与 Plot 保存 | 同上，含热图 Plot 保存/重开 |
| **WP8** 迁移工具（11B） | 预检 P1–P14、哨兵与墓碑守卫、冻结锁与租约交接、副本构建（只经现有入库服务）、对账、故障注入与回退；**顺序：先建立并验证 Batch、Sample 记录与身份，再登记其 Source**（`ingestAsset` 需要已验证的目标 Sample，不是先入库再建正式 Sample；“Source 先于记录”只指字节与哈希先于分析/派生记录）；旧索引重建；**不调用 Recompute** | §6；不新建迁移引擎或第二套库；报告不含敏感原始数据 | §7 |
| **WP9** 真实库预演与切换 | 经授权先在真实库**副本**预演，再对真实库迁移 | 每一步单独授权；major 版本另行确认 | 对账零差异、人工项逐项一致、回退演练 |

> WP4 之前不为 RT/3ω/IV/XY/RSM 另做存储管线；各工作流只做“上下文消费 + 来源缝 + 标准化接入”（Audit B §7）。**切换时若某个仍在使用的工作流尚未适配，其新文件只能 Source-only 入库（不丢文件，但无法分析）；该取舍由用户在放行时明确。**

---

### 4.3 PR 交付计划（2026-11-28 用户确认）

用户明确要求控制交付数量，不将十个工作包机械拆成约二十个设计/实施 PR。**工作包是逻辑依赖与验收单元，不等于 PR。** 已确认的科研语义、数据安全、各包验收及正式迁移放行条件均不降低。统一设计后按完整可验收能力交付；计划剩余 8 个 PR（含 #248，后续编号由 GitHub 分配）：

| 顺序 | 交付阶段 | 覆盖工作包 | 边界 |
|---|---|---|---|
| 1（#248） | 公共架构统一设计 | WP1–WP4 | [设计入口](design-11-wp1-source-ingest.md)；一次确定公共入库、Dataset、查询/读取、AHE 首个闭环及 Plot/Result 合同；不实施 |
| 2 | 数据基础实施 | WP1–WP2 | 测量上下文、通道归属、Source-only、表格 Dataset 与既有 loader 适配；可独立验收入库/重启/读回/恢复 |
| 3 | 公共消费与 AHE 闭环实施 | WP3–WP4 | 公共查询、列定位、Workbench 数据入口、AHE 分析、正式 Plot 保存与 Result；验证共同合同 |
| 4 | 输运工作流适配实施 | WP5–WP6 | 按内部依赖分批接入 RT、XY、3ω、IV（DAT/LVM），各工作流独立验收，复用共同能力；不重开全套设计 |
| 5 | RSM 适配实施 | WP7 | 复用表格 Dataset、公共读取、Heatmap 渲染和 Plot 保存；确认导入规则 |
| 6 | 迁移安全统一设计 | WP0、WP8 | 一致备份、恢复、迁移预检/对账、冻结/切换/回退与故障测试合同 |
| 7 | 备份和迁移工具实施 | WP0、WP8 | 在同一交付内先完成 WP0 再验证 WP8，合成夹具/隔离副本验收；不自动迁移生产库 |
| 8 | 正式升级交付 | WP9 | 真实库副本预演和正式迁移必须分别明确授权并通过放行条件；版本号另行批准。需要代码/正式文档交付时使用 PR，纯本地操作不为凑数量新开 PR |

WP0 技术上独立可并行，计划中与 WP8 安全交付合组；其依赖和先备份后迁移的顺序不变。WP5–7 默认继承已验收共同合同直接适配，只有实际出现未决科研语义、共同合同冲突或重大安全风险才增设必要设计/拆分。若同类工作适合更少 PR 可合并；若风险确实无法在同一 PR 分批独立验收才拆分并说明理由。8 是计划目标，不是硬指标；不为凑数量降验收，不为形式整齐扩大架构。

---

## 5. 决策记录与待决

### 5.1 已由用户确认（Jack，#247 评论“一、已确认的产品方向”，2026-11-28）

| 事项 | 结论 |
|---|---|
| 正式库与 V1 | 唯一正式库；V1 仅作完整静态升级备份；单机、单库、单写者，不预建多设备协调 |
| 可重算旧成果 | Plot/Analysis Pack/指标不建历史兼容层、不强制恢复；不可再生人工信息无损保全；切换前 V1 日常支持不拆 |
| 架构方向 | 统一逻辑生命周期、不统一数据形态；公共能力先行、复用已有；MR 只保全原始文件；RSM 正常接入并共享 Heatmap；非 AFM 自动出图暂缓，手工 Plot 保存不省略 |
| 迁移守卫与回退 | 保留迁移哨兵、源库冻结、唯一正式库防误写方向（91c65c38）；回退时完整保留 V2 新写入，不开发自动反向回灌（§6.4） |
| 授权 | 真实库读取/复制/预演/切换及 major 版本各自单独授权 |

### 5.1b Worker 在授权范围内采纳的技术决定（来自评论“二、Reviewer 技术建议”，细节由 Worker 定；用户可推翻）

| 原 Audit 选项 | 采纳的做法 |
|---|---|
| Audit B D-B1 多通道归属 | 每个目标 Sample 各存完整 Source 副本 + 有效通道，不做跨样品共享所有权/去重（延续 K5）；用户路由权威优先于文件名推断 |
| D-B2 无适配器数据 | Source-only，明确状态，不冒充 Dataset |
| D-B3 非 AFM 自动出图 | 暂缓（与 5.1 一致） |
| 测量上下文 | 先确立唯一权威，再建表格 Dataset；LVM 位置列依赖用户确认的 workflow，未知保留未知 |
| Audit A：General 中约 40 个 IBW | 在确认有效 AFM 且不覆盖人工分类时，按当前规则归 AFM，样品归属不变；否则 Source-only |
| Audit A：Plot/Pack | 默认仅随静态备份，不建兼容、不自动重算 |
| 条件等规则可再生字段 | 以只读重解析与旧值比对，差异报告；人工决定不被规则覆盖 |

### 5.1c 最终补充决策（Jack，#247，2026-11-28，基线 `55e89da8`）

| 事项 | 结论与依据 |
|---|---|
| MR | 本机 Audit A 与只读复核确认**实际有 MR Source**（约 147 个 DAT，无图/无 Pack）。故：V2 仅保留 MR 数据分类，经通用 Source-only 保存完整原始文件与既有归属；不保留 MR 专属 Workbench、占位分析界面、解析器或兼容逻辑，不另建 MR 入库路径；不删任何原始文件。静态核对当前源码：除 `WorkflowKey` 的 MR 枚举/分类规则与搜索别名表外，未发现 MR 专属 Workbench/占位/解析器引用，故无需单独的代码清理工作包；这些分类项在 WP1/WP8 适配时随“只保留分类”核对，不新建实现。未来确需 MR 分析按公共架构重新接入 |
| Measurement Set（P-1） | 只读复核本机 84 个集合：83 个只是按 Device（角度）分组，其中 78 个与 Device 同名、5 个仅写法不同（如多一个空格）；1 个混放（一个 0° 文件同时出现在 30° 与 0° 两个集合，疑似误放）。成员文件全部存在；代码上集合仅服务 Library 显示与清理（不参与搜索、分析、绘图，与原设计 ef5742eb 一致）。**结论：纯显示分组，无不可再生科研语义**——不迁移，随 V1 静态备份保全；V2 不加集合标签字段、不新增 Measurement 实体、不维护旧分组 CRUD/兼容；报告只列“未迁移数量”。完整名称与成员只留本机，不入仓库 |
| WP8 顺序更正 | “Source 先于记录”不得理解为先 `ingestAsset` 再建 Sample：入库服务需要已验证的目标 Sample，故先建立/验证 Batch、Sample 记录与身份，再登记 Source（§4.2 WP8） |
| 其余 | P-2/P-3 保留至 WP9；其他实施路线不变；Draft、纯文档、no-release、Task 11 未勾选 |

### 5.2 仍需用户决定（保持未批准）

- ~~P-1 非平凡 Measurement Sets~~：**已决**，见 §5.1c（不迁移，随静态备份保全）。
- **P-2 版本号。** Library 格式迁移属 major；真实迁移 PR 前由 Jack 明确一句话描述并加 `major-approved`（AGENTS）。
- **P-3 真实库预演与切换授权。** WP9 每步单独授权；本 PR 不含。
- **P-4 切换放行名单。** 切换前由用户确认“仍在使用的工作流”名单和“未适配者仅 Source-only”是否可接受（见 §4.2 末注）。

---

## 6. 迁移、备份、恢复方案（AC4 的设计部分，不写实现）

### 6.1 比较

| 方案 | 做法 | 风险 | 评价 |
|---|---|---|---|
| A 原地转换 | 在源库目录里改布局 | 违反“源库保持完整”；V2 Router 禁止与 `batches/` 并存；中断难回退 | ✖ 不采用 |
| **B 副本构建 + 切换根位置（推荐）** | 只读预检源库 → 备份源库 → 在新目录构建 V2 副本 → 对账 → 切换根位置设置 | 需额外磁盘；切换后新写入在副本（回退见 §5.1）；单机，无多机设置同步 | ✔ |
| C 副本构建 + 目录交换 | 重命名目录互换 | 中间时刻“根”不存在；Sandbox/书签易失效；无法保证原子 | 备选，不推荐 |

### 6.2 推荐流程（B）

0. **冻结源库**：迁移由**独立的离线流程**执行（App 已退出）。流程先对源库取排他写锁（同一 `flock` 锁文件机制）并**持有到切换验收结束**；取不到即拒绝开始（说明另有实例在写）。持锁期间源库只可能被本流程读取，因此没有 App 后台任务（手机拾取、同步、备份、自动出图、Publish）能写源库。预检基线哈希、构建、对账、切换前复核都在锁内完成。**由于 `LibraryWriteLease.shared` 单例同一时间只持一个根，冻结锁使用单独的 `LibraryWriteLease` 实例（构造器可注入锁目录，S）持有源库，`shared` 留给副本根供入库服务使用**——这一点须在 11B 先用夹具证实可行；若不可行，退而用独立进程各持一把。
1. **只读预检**（§3.1）：生成冲突/孤儿/未知报告，不写源库。有未解冲突 → 停止。
2. **备份源库**：独立位置整库复制并校验（哈希清单）；校验失败即停止。
3. **隔离副本预演（先合成夹具；经授权后才用真实库副本）**：先在合成库完整走通；对真实库只经授权后对其**副本**进行，不对真实库本体操作。
4. **构建**：区分“V2 格式已初始化”与“迁移已完成”两个状态。`LibraryAssetService.requireV2` 要求根先被识别为 V2，所以**初始化时就写 `_spinlab/layout_version.json` 并创建 `records/batches`、`records/samples`**（即现有 `initializeV2Library(at:)` 的效果），之后才能复用 `ingestAsset` 等入库服务；**不能**依赖“版本标记最后写”来防止半成品。防半成品改由独立的**迁移进行中哨兵** `_spinlab/migration_in_progress.json`（初始化时与标记一起写入、对账全部通过后才删除）承担：App 打开含该哨兵的库一律 fail-closed 为只读并提示“迁移未完成”，**不得**把它设为可写根，也不得对它做入库之外的操作。这是 11B 需要新增的一个最小守卫（技术性决定，已在此记录）；在守卫实现前，构建目录不得被配置为 Library 根。构建阶段 `shared` 租约持有副本根；构建只由迁移流程写入。11B 故障注入覆盖“初始化后中断（有标记有哨兵）”“有标记无记录”“仅 `index/`/`storage/`/`_spinlab/`”“删哨兵前中断”等状态，断言均不会被当成完成的库。
5. **对账**：§3.2 全部类别；样品/批次/Result/哈希/关系（SQLite：每 Source 恰一个 Sample 归属，每 Dataset 恰一个 Source）；索引重建一致。
6. **切换前重新校验源库**：在仍持有冻结锁的前提下重新计算源库清单哈希，与预检基线一致才继续。因锁从步骤 0 起不放，预检与切换之间不存在合法写入窗口；若哈希仍变化，说明有绕过 App 的外部修改（违反使用前提），中止并报告。
7. **切换**：由 App（用户在界面中指向新根）执行，迁移流程保持存活并继续持有源库冻结锁，直到步骤 8 验收通过并写入墓碑。若迁移流程在写墓碑前崩溃，锁释放、源库短暂无保护：重新运行迁移流程会先取源库锁并补写墓碑（或按回退流程回退），11B 故障注入覆盖该状态。切换以设置更新（新根位置）作为提交边界。现有 `updateLibraryRoot` 依次写 `rootPath`、刷新写租约、`try?` 生成安全作用域书签、保存设置，**书签失败是静默的**，沙盒下新根会变成 `missingBookmark` 不可用（S）。因此切换必须：由用户授权新目录并**确认书签已生成**；检查与根相关的其它设置（`backupPath`、Registry 路径、Workbench 缓存的 `lastLibraryRootPath`、`_spinlab/analysis_packs` 随根变化）；回退 = 恢复**切换前整份 `LibrarySettings`**，并重置 Workbench 工作区缓存的 `lastLibraryRootPath`；写租约的交接见 §6.4。
8. **切换后验收**：新 App 打开 V2、列出全部样品、逐类抽检工作流；失败则恢复设置指向源库（源库未被改动）。
9. **源库保留**为只读归档，直至用户确认验收并过回退窗口。只读的保证见 §6.4。

### 6.3 中断与故障恢复

- 构建中断：**Router 并不可靠地 fail-closed**（无 `records/` 时判为未初始化，仅有 `index/` 时判为 V1，S）。安全来自三点：构建目录在对账通过且迁移进行中哨兵删除前从不被设为 Library 根（并由 §6.2 步骤 4 的哨兵守卫兜底）；构建先初始化 V2 布局；切换以设置更新为唯一提交点。可删除重建，源库无变化。11B 故障注入须覆盖“仅 `storage/`/`_spinlab/`”“仅 `index/`”“有 `records/` 无标记”三种中断状态。
- 对账失败：不切换；报告差异。
- 切换后发现问题：回退，完整保留 V2 新写入，不自动回灌（§5.1、§6.4）。
- 不做：半迁移、双写、静默回退 V1 路径、旧 App 写 V2（SKELETON 已声明不支持）。
- 复用现有机制：`LibraryWriteLease`、`AtomicFileWriter`、`LibraryAssetService` 的 `asset_operations` 与幂等 `operationID`、`ContentFingerprintService`；不新建迁移引擎或第二套数据库。

### 6.4 租约交接与源库只读保证

现有机制（S）：`updateLibraryRoot` 调 `refreshLibraryWriteLease()` → `LibraryWriteLease.shared.acquire` 先释放旧根锁再锁新根；之后源库没有任何锁。若仅靠“用户不再打开”，源库可被再次配置为根并写入，形成两个各自演化的 Library。设计要求：

1. **交接顺序**：迁移流程持有源库冻结锁（步骤 0），App 在副本上取得写租约并通过切换后验收之后，才允许释放冻结锁；释放前先完成下一条。
2. **源库墓碑**：验收通过后在源库写入 `_spinlab/migrated_to.json`（目标位置、迁移时间、映射表与哈希清单的指引）。11B 新增最小守卫：App 打开带墓碑的库一律只读并提示“此库已迁移到 …”，**不提供在界面里一键解除**。墓碑是对源库唯一的一次写入（内容不触及任何科研数据），须在迁移授权说明中单列。
3. **回退**：回退 = 在显式用户操作下（重新取得源库写锁后）移除墓碑 + 恢复切换前 `LibrarySettings`（§6.2 步骤 7）；回退前先生成副本上“切换后新写入清单”（§5.1）。回退后副本同样须写墓碑，避免两库同时可写。
4. **纵深**：可选再把源库目录设为文件系统只读（权限位），但这是辅助，不是保证（可被改回）；以墓碑守卫为准。
5. **适用范围**：不含这两个守卫的 App 版本（11B 之前的构建）不会识别哨兵和墓碑；按 SKELETON 约定所有电脑只运行当前兼容版本，不为旧版提供互操作。
6. **后台任务**：墓碑与锁只覆盖 App；不由 App 管理的外部写者（云同步、手工改文件）属使用前提（“用户不绕过 SpinLab 改库”），不在设计保证范围，需在迁移前向用户说明。

### 6.5 放行条件（实际迁移）

全部满足才可向用户申请真实库迁移授权：WP0 完成；WP1–WP3 完成；WP4 完成并验收，且 P-4 名单内的工作流已适配或已确认仅 Source-only；WP8 的迁移进行中哨兵与墓碑守卫已实现并验证、预检冲突清零或逐项已决、合成夹具全流程 + 故障注入 + 回退演练通过；P-1 已决（§5.1c）；**§8 中“阻塞放行”的验证项通过**；真实库副本预演（经授权）对账通过；P-2 已答；用户明确授权。

---

## 7. 11B（WP8）验收计划（AC4）

1. 合成夹具：覆盖两种 V1 Batch 路径、含/不含 `sampleUID`、`legacySampleKey`、废纸篓样品、Growth 重复一致/冲突、未知 JSON 字段、重复/缺失原始文件、AFM 与（已纳入的）其它工作流、历史图/Pack、绝对路径 manifest、手机新建样品。
2. 预检：每类冲突各一个夹具，断言只报告、不修改源库（源库目录哈希前后不变）。
3. 构建与对账：UID/Batch/Result/哈希/SQLite 基数/索引一致；字节级保留 `sample.json` 未知字段（P5）。
4. 故障注入：构建中途、对账中途、写标记前后、切换设置前后中断；断言源库不变、无半成品被识别为可用 V2。
5. 切换后工作流回归：Library 浏览/搜索/编辑、Inbox（所选工作流）、Workbench、废纸篓/恢复/永久删除、备份（WP0）、Publish/手机、单写者只读实例。
6. 哨兵守卫仅对 App 打开路径生效，迁移构建器通过服务层直接写入、不经打开路径（夹具须验证二者）。
7. 回退：切换后无新写入的回退；有新写入的回退（新写入清单；V2 数据完整保留，不覆盖）。
8. 授权边界：真实库的读取/复制/预演/迁移每一步单独授权，报告留存映射表与哈希清单。

---

## 8. 审计未确认项对放行的影响与最小验证

不再开展泛化审计；下表每项只给“是否阻塞放行”和最小验证。**所有结论目前都是静态读码或只读审计，未运行 Swift 测试或 GUI；不得以静态结论代替夹具实测。**

| 未确认项 | 阻塞放行？ | 最小验证（归属包） |
|---|---|---|
| 悬空引用（约 14 张图缺 PNG、约 5 个 Pack 引用悬空） | 否（旧 Plot/Pack 不迁） | 迁移报告列出，随静态备份保存（WP8） |
| `measurement_data` 指标是否可重算一致 | 否（不迁） | 报告披露“未验证一致”，不宣称等价（WP8） |
| 待导入队列的外部原件是否仍在 | 仅影响该队列项 | P12/WP8：逐项报告原件在/缺；队列文件在库外，夹具验证根切换不改它 |
| Library 之外的 Registry xlsx、规则书、Obsidian/Web Library/备份路径在切换后是否有效 | **是** | WP8 夹具：`updateLibraryRoot` 切换后这些设置保持有效、书签已生成；真实库预演（经授权）读设置核对；恢复演练含它们 |
| 归属冲突（路由不可由文件名推出、Recompute 造成的差异） | **是（按项）** | P11：以旧侧车路由为权威；夹具含不一致样例；真实库副本预演产出冲突清单，每项已决后放行 |
| 同批多变体归属可恢复比例 | 否（迁移用旧侧车路由，不做推断） | 无 |
| 旧库无哈希基线 | 否，但约束表述 | 迁移时计算基线并记录；不声称证明过去未被修改（§3.2） |
| 用户是否另有原始数据备份 | 否 | 向用户说明建议保留 WP9 前的完整静态备份 |
| Publish/网页投影、手机提交、Registry/XLSX 同步、Recompute 在 V2 的实际行为 | **是** | WP8 夹具回归（§2.4 的 `?` 项） |
| RSM 在实际规则本中的启用与分类 | 否（仅 WP7） | WP7 读取实际规则核对 |
| LVM 静默丢行 / RSM 整体拒绝对已有数据的影响 | **是（按文件）** | P14 试标准化清单；丢行文件默认走 Source-only，仅经用户逐文件明确接受才保留带诊断的 Dataset |
| IV 多路回退在 V2 无路径时的差异 | 否（仅 WP6） | WP6 夹具比对并披露 |
| 一维表格 Dataset 大文件性能 | 否 | WP2 基准夹具 |
| SQLite `schema_version` 升级 | 否（真实库无 V2 数据） | WP1 包设计中定升级策略；仅测试/开发库受影响 |
| design-12 对 Result 目标 Sample 在 V2 的 UID 解析 | 否（仅 WP4） | WP4 复核 design-12 §5 并以夹具验证 |

其余未验证事项（§2 中带 `?` 的行：顶层 `samples/` 在 V2 下的实际行为、V2 废纸篓恢复、`LibrarySettingsStore` 根位置切换对书签/沙盒的影响、10B 实际行为与 design-10 是否一致）并入 WP8 夹具范围。

风险：非 AFM 能力缺口可能使切换推迟（缓解：Source-only 保证文件不丢，名单由 P-4 裁剪）；副本期间源库被写（缓解：步骤 0 冻结锁 + 步骤 6 复核；外部绕过 App 不在保证内）；切换后两库分叉（缓解：墓碑守卫）；构建目录被误当可用库（缓解：哨兵守卫）；`sample.json` 未知字段丢失（缓解：P5）；条件由规则重算与旧值冲突（缓解：差异报告、人工项优先）。

---

## 9. 独立设计审查记录

- 方式：只读 fresh-context 子代理（无编辑权限），逐条对照源码核验；审查者只提意见，处置由本文作者决定。
- 第 1 轮（被审：初稿）：needs revision。已采纳并修订：Recompute 在 V2 是静默空操作（原误列为未知）；漏列直接操作顶层 `samples/` 的审计/清理/图库/删除消费者；“源库不改”与 P1 补发 UID 的矛盾；切换提交点忽略书签静默失败、关联设置与设置回退；AFM 重新入库被写成已决（改为推荐、该推荐现已由 §0 路线确认）；中断构建 fail-closed 说法过强；Pack 路径、工作量估算不实。
- 第 2 轮（被审：第 1 轮修订版）：第 1 轮各项修订经源码核验属实；发现 §6.3 与 §6.2 步骤 4 及 Router 行为矛盾（实质）以及两处小问题，均已按文字对齐修订，未改变设计结论。审查者预期无需再轮。
- 第 3 轮（被审：纳入用户补充意见后的版本）：逻辑成立，源码事实 (a)(b)(d) 核实无误，(c) 函数名更正为 `initializeV2Library(at:)`；提出墓碑写入披露不一致（实质）及切换执行者、旧构建适用范围、哨兵绕过路径三处小问题，均已作文字补充。已达 Deliver 默认审查上限（3 轮），第 3 轮后的修订只是披露与措辞，未再复审；若用户要求，可经明确授权追加一轮。
- 用户补充审查（2026-11-28，来源为用户贴入的审查意见，我已逐条对源码核实）：P1 “V2 标记最后写”与 `LibraryAssetService.requireV2` 冲突——属实，已改为初始化即写标记 + 迁移进行中哨兵（§6.2 步骤 4）；P1 源库哈希复核与切换之间可写、切换时旧库锁被释放——属实（`shared` 单例，`acquire` 先释放旧锁），已加冻结锁（步骤 0）与租约交接（§6.4）；P2 源库只读归档无保证——属实，已加墓碑守卫（§6.4）；另纠正事实：Task 10B（#229）已合并。
- 结论（第一轮设计）：实质问题均已处置；运行验证为零（§8）。收口修订见下。

- **收口修订（2026-11-28）**：依据 Audit A/B 与 #247 评论重写 §0/§3.2/§4/§5/§6.5/§8；该修订的独立审查记录见下方“收口审查”。

### 收口审查（2026-11-28）

- 方式：只读 fresh-context 子代理，对工作树逐条核对引用的代码符号（`LibraryAssetService.swift:293-294`、`LibraryAssetDatabase.swift:131/239`、`ZurichLVMLoader.swift:100/117`、`SearchWorkflowMeasurementsUseCase.swift:107-118`、`supportedPlotFormats` 等均属实）与脱敏性（设计文档无用户路径/样品 ID）。
- 第 1 轮：needs revision，无阻塞项。已采纳并修订：§9 悬空引用（本节补齐）；mtime/原始文件名/旧路径漏入 WP1 上下文；§5.1 把评论“二、技术建议”误写成用户已确认（拆为 5.1 用户确认与 5.1b Worker 技术决定）；WP4 漏掉 `FormalPlotLibrary.summaries`/`validatePlotRequest` 路由；WP3/WP4 循环依赖（来源缝并入 WP4）；“重算”与“不调用 Recompute”的措辞矛盾及“真实改派”判据；待导入队列的 sampleKey 重映射；Registry/规则书不复制进库的说明；有效通道落 SQLite；WP8 依赖补 WP0；LVM 丢行默认值；旧标签残留。
- 处置后状态：以上均为文字/范围补充，不改变路线结论；按 Deliver 默认上限（3 轮）。
- 第 2 轮：上述 6 项实质问题已解决；另提出 WP3 标题/brief 仍写“来源缝”、一个数字缺来源、§0.2 的 UID 总数标注、本节末行悬空，均已修正；审查者判断收敛，无需第 3 轮。

### 最终补充决策修订（2026-11-28，基线 `55e89da8`）

- 范围：仅 §0.1、§3、§4（WP8 顺序）、§5.1c/5.2 与 Audit A 脱敏汇总；MR 与 Measurement Set 的结论来自本机只读复核（未写入任何文件，完整名称/成员只留本机）。
- 检查：作者自查——旧引用（P-1、“约 6 个非平凡”）已同步、文档不含样品 ID/用户路径。**本次未另开独立审查子代理**（按 #247 补充决策“不再开启反复总体设计审查”；改动只是把已决范围写入文档）。
