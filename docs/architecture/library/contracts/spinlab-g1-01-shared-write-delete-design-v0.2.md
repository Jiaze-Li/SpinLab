# SpinLab G1-01 — 共享写入一致性与删除安全补充设计 v0.2（独立 DESIGN Gate 候审）

**任务归属：** 原 `SPINLAB-G1-01-SAFETY v1.0` 的补充架构约束；不是新任务、不替换原 Worker 合同、不是代码实施授权。  
**状态：** `DESIGN GATE = PENDING`；v0.1 `DESIGN REWORK`，本 v0.2 尚未审查。  
**风险 / Architect / 独立 Gate：** `Tier 3 / REQUIRED / REQUIRED`。  
**固定 `policy_sha`：** `2304f2e93185fca3b50fb1f076b2e1801797492d`。  
**原 G0 v1.4 设计原文：** `sha256:d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8`（46,620 bytes，UTF-8/LF；历史 DESIGN PASS）。  
**原冻结 Worker 合同：** `05_G1-01_冻结Worker任务合同_v1.0.txt`（12,397 bytes，SHA-256 `24521827f5fe06712f37430ed42d7aeecdd0337df705f12581bb84e8fdbbb1d9`）。原 **AC1–AC6、S1–S6 不变**。  
**替换的补充设计：** v0.1，`sha256:ecd6bef69ff3cb340c5780653aa8857718cfc5f585f3bf618f5359937f1ea857`，已获独立 DESIGN REWORK（D-01～D-05）。v0.2 仅修补补充设计，不追溯改变原 G0 与 G1 合同。  
**代码证据快照：** `Jiaze-Li/SpinLab` PR #195 `G1-01 → T01`，HEAD `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`；基线 T01 `d29d914b7a19824d822361ed67ea67b322705786`。在本文件形成时 PR #195 OPEN、未合并，机器人 `REWORK`、F001 P2 OPEN、最近审查 PARTIAL。  
**不可变 `design_ref`：** 交审时按本文件**全部原始 UTF-8/LF 字节（包含末尾换行）**独立计算 SHA-256，引用置于交审说明与随附清单，**不写入文件自身**以避免循环。若字节不匹配，停止审查。  
**证据属性：** A/B 故障由原 Worker 在隔离合成 Library 上确定性复现，主控已只读核查可达调用链；未宣称真实多进程/真实用户 Library 已动态验证。

## 0. 本轮裁决与明确非目标

- **A：** `deleteExistingDrawer` 使用旧 `baselineIndex` 覆盖别的 Batch 新提交的索引项，已复现；即使磁盘 Sample 仍在，也不准以“下次同步可恢复”为理由丢弃可能独有的索引信息。
- **B：** 删除 Batch 时同目录内新增 `X_NEW` + 测量文件被递归删除，已复现；这是超出授权集合的物理删除，**任何同类入口未被有效保护前必须 fail-closed**。
- **本轮最小交付：** 统一 `library_index.json` 及 Sample/Batch 正式写入的进程间协调与索引提交；暂时关闭无法保证物理删除边界的 Sample/Batch/Drawer 递归删除（包含底层入口和回滚）；正常合法创建、更新、索引同步与原已批准恢复能力必须保留或明确报有限阻塞。
- **不在本轮开放：** Sample/Batch/Drawer 硬删除、Trash/Restore/Purge、跨机器不合作文件同步的强制互斥、通用跨全部 Workbench/Sidecar 的数据库事务、SQLite、数据迁移、UID/Source/Result/Plot 模型变更、#194 验收和 PR merge。G0 O-ID3 删除策略仍待未来受影响入口正式开放前裁定。

## 1. 真实权威、实现参考与合同适用面

| 项/固定代码基线 | 已核实事实或必须维持的边界 |
|---|---|
| `LibraryIndex`，`Library/Domain/LibraryDomainModels.swift` | 顶层有 `version`、`createdAt`、`updatedAt`、`registryInternalPath`、`registrySourcePath`、`metadataColumnOrder`、`batches`、`samples`。现有 `Codable` 重新编码**不能推定保留未知 JSON 键**。 |
| `scanIndexFromFilesystem`，`LibraryStore+RootAndIndex.swift` | 读取 Batch 的 `batch.json` 与物理 `sample.json` 构造 `batches/samples`；现有索引的版本、创建时间、Registry 来源等作为部分输入。`syncIndexFromFilesystem` 最终会 `saveIndex`；这是复合读写操作，不是单纯只读。 |
| `LibraryMutationService.swift` | `deleteExistingDrawer` 先取快照、删除目录、再写旧索引；`createDrawersForSelection`、`confirmNumericRefreshChanges` 也存在“读旧索引→处理→整体写回”路径。 |
| `LibrarySyncService.swift` | `applyBatch/applyAll` 有前后两次安全差异检查，之间会整理 Batch、刷新索引；末尾另有索引写入。已有 S5 状态提示修复不构成事务保护。 |
| `LibraryStore+Drawers.swift` | `deleteSampleDrawer`、`deleteBatchDrawer` 可执行目录物理删除。检查依赖不等于授权扩大至并发新建的文件。 |
| `NativeSampleCreationService.swift` | 创建流程及失败回滚可能把创建前的原始 `library_index.json` 字节写回；还可能恢复旧 `batch.json`、清理新目录。 |
| `LibraryWriteTransaction.swift` | 是有限文件暂存/移动/回滚工具，**没有**建立整个 Library 的跨写入者协调。 |
| Workbench/Measurement/Sidecar 独立产物 | 原始测量、结果、图、引用与必要独有信息不是随意可丢的缓存；但不能把所有这些独立服务的每一处写入都不加区分地纳入新的 G1 索引事务。详见第 2 节明确范围。 |

**G0 §5 不变量：** 索引可能保存不能从别处重建的来源/兼容信息；未经验证的重建/解码不能抹掉它。**G0 §6 不变量：** Registry 缺行/改键不授权删除，共享资产保护，改名/同名重建不允许旧产物误绑；未批准完整 Trash/Purge 政策时，只能预览、拒绝和安全保护。

## 2. C1 — Coordination Protocol v1（修 D-01）

### 2.1 协调域与各类写入者的**确定分类**

**域 K：Library 目录登记与共享索引。** 同一已存在的物理 Library Root 对应一把 `K` 独占锁。任何会读取后重写 `library_index.json`、`batch.json` 或 `sample.json`，或会创建/删除 `batches/**` 正式 Sample/Batch 目录的 SpinLab 写入者，必须由同一 K 协议进入；包含直接 Store API。不能只在 UI 调用处加锁。

| 入口 | v0.2 处理方式 | 锁内必要条件 |
|---|---|---|
| `LibraryStore.saveIndex`、原字节回写、`syncIndexFromFilesystem[Checked]`、已批准 `recoverIndexFromFilesystem` | **K 必须**。禁止未持有提交上下文直接写索引；只读扫描仍不加锁 | 第 3 节字段级归属；最新原始索引及磁盘复核；损坏恢复另走第 3.3 节 |
| `LibraryMutationService` 的整库/选中创建、`rebuildIndexFromDisk`、`confirmNumericRefreshChanges` | **K 必须**；旧快照整体覆盖不可用 | 同次提交的 Sample/Batch 与索引更新；保留未触碰项与独有元数据 |
| `LibrarySyncService.applyBatch/applyAll` 与末尾索引提交 | **K 必须**；原 S1 预检保持 | 在 K 内重新核对预览、Registry diff、实际状态；先拒绝危险计划，后写入 |
| `NativeSampleCreationService` 创建及任何回滚清理/索引恢复 | **K 必须** | 操作所有权、条件回滚、第 5 节阶段状态 |
| `LibraryStore.createDrawer/updateSample/updateBatch` 及会触及相同对象的间接入口 | **K 必须**；不得由绕过的 Store 调用直接提交 | 共享同一个提交上下文、受影响关系与路径再次验证 |
| `deleteExistingDrawer`、`deleteSampleDrawer`、`deleteBatchDrawer`，以及内部递归清理现有 Sample/Batch 目录 | **G1-01 一律 FAIL-CLOSED**，含直接 Store/回滚入口 | 返回“该类物理删除暂未启用”的可执行理由；不得执行任何删除或试图靠 K 后恢复递归删除 |
| 只读搜索、打开、审计、预览、索引完整性只读扫描 | **不申请锁，不创建元数据，不写文件** | AC1 的完整内容及 mtime 零修改 |
| Workbench Plot/Result、`results_index.json`、图像及独立 Measurement/sidecar 写入，**且不写** `library_index.json`/`batch.json`/`sample.json` | **不属于 K 的索引事务**，现有独立写入路径继续运行；不宣称它们与 K 是全局原子事务 | Sample/Batch 递归删除禁止，不能删除其目录；如果发现该入口也会写 K 域，则必须纳入 K 或 fail-closed；原有单资产引用删除仍须遵守 G0/原 S3，不由此文新增删除许可 |

**判定规则：** 入口是否受 K 约束由实际写入的**路径和操作范围**决定，而非类名；生产代码若存在未列出的直接 `saveIndex`、直接写索引字节、`removeItem(directory)` 或绕过 K 的 Batch/Sample 正式写入，P0 必须补入清单并接入或封闭。无条件“所有 Library 写操作都支持并发”的宣传不成立。锁外的图/测量写入者不被视为受 K 保护的事务参与者。

### 2.2 根身份、锁位置与实际原语

目标平台首先是**同一 macOS 用户、同一台机器上的多个 SpinLab 进程**；不能将本协议宣称为多台主机/SMB/iCloud/不合作外部文件同步的全局互斥。

1. 对**已存在且为目录**的 Root，`realpath` 解析用户给定路径与符号链接并取得 `fstat` 的 `st_dev + st_ino`，作为当前系统会话的**物理根标识**。校验 root 及访问权限；根被替换、文件身份变化、无法确定 root 或路径逃逸时拒绝 K 写入。两个不同别名（真实路径与符号链接）指向同一目录时必须映射到**同一** K 键；不以输入的字符串路径为锁键。一个操作实际访问统一的已解析 root。
2. 锁文件规范位置：同一 macOS 用户的共享 Application Support 区域 `~/Library/Application Support/SpinLab/LibraryCoordination/v1/<SHA256(st_dev:st_ino)>.lock`，**在 Library Root 外**。不得使用每进程临时目录或每 App 实例不同沙盒容器。若进程不能访问同一协调目录（包括沙盒实例、不同 Unix 用户）则**不声称它们已协调**：相关 K 写入拒绝或另行设计；不能静默降级。
3. 使用 Darwin/POSIX `open(O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW)` + `flock(LOCK_EX | LOCK_NB)` 对稳定锁文件的**打开描述符**持锁。先核查父目录无不受信任符号链接、锁文件为普通文件，打开后 `fstat` 再校验；锁文件持久保留，绝不在解锁时 unlink。锁由**关闭持锁 fd**或进程退出释放；单文件 `.atomic` 不提供互斥。协调目录的建立仅在**准备实际写入且只读外层预检已通过后**允许；纯只读路径零写入。
4. 获取顺序：当前任务只允许**一个 Root K**；同一调用链内通过明确的 `WriteContext(rootIdentity, ownerToken, fd, phase)` 向下传递，嵌套 Store/Service 复用这一持锁上下文，**不得二次 `flock`**；跨根嵌套写入直接拒绝并要求拆分。不同任务/线程使用进程内按 root key 串行队列，再获得进程间 `flock`。最长等待 **5 秒**，按有限间隔非阻塞重试；锁被占用、IO 失败或不支持时返回 `LOCK_BUSY/LOCK_UNAVAILABLE`，任何正式文件不变，不在 UI 主线程自旋等待。
5. 持锁后**再次校验 root `st_dev/st_ino`**及规范化路径，完全重新获取实际提交所需的当前文件/引用/索引状态。预检 → 持锁再次核验 → 记录提交意图 → 正式写入 → 核实提交/标记阶段 → 释放。`try/finally`（Swift `defer` 等价）关闭 fd；异常不得悄悄放锁后继续写。代码不得依赖 inode/mtime 单独证明用户内容未变，仍须检查原始字节或对应强校验。
6. **协调安全边界：** K 仅串行化遵守同一个协议的写入者。外部编辑器、Finder、同步软件不参与 `flock`；检测到未协调状态变化时不能自动猜测合并，索引覆盖之前须比对原始索引版本与受影响文件/清单。非合作写入者可能在最后比较后再次写入，因此不宣称“锁能保证任意第三方操作安全”；对任何无法建立排他的 Sample/Batch 递归物理删除，直接保持禁止。

**零修改语义：** 首次危险计划**纯只读**预检失败时，无文件（包括锁文件）被创建/修改。持锁后的拒绝不能写任何 Library Root 下正式文件、索引或提交意图；锁元数据仅位于 Root 外，不计入 Library 文件树的 AC1/AC3 mtime 比对，但须单独检查无异常锁泄漏。锁持有本身不意味着业务提交。

### 2.3 提交版本比对

K 入口在临界区读取 `(indexRawBytes, indexExists, rootIdentity, affectedRecordsManifest)`；`indexRawBytes` 用原字节 SHA-256 标识当前文件版本，读取失败不得当作空索引。锁内执行正式写入前，比较受影响的 `batch.json`/`sample.json`/测量及被治理引用与此次预览的预期版本。**索引最终覆盖之前重新读取原始索引字节并与本次在锁内建立的预期版本比较**；任何非本操作造成的变化都报 `CONFLICT`，不覆盖其更新。所有合作写入持同一 K，故此比较可用于发现非合作修改，但不宣称消除其所有 TOCTOU。`updatedAt`/目录 mtime 仅诊断，不能作为唯一版本条件。冲突时依第 5 节明确 `NO_COMMIT/PARTIAL/UNKNOWN`，不得盲目重试、覆盖旧文件或生成新 Sample。

## 3. C3 — 索引字段权威与丢失保护（修 D-03）

### 3.1 `LibraryIndex` 顶层字段所有权表（固定 HEAD 的**准确名称**）

| 字段 | 权威/生成规则 | 普通 K 写入时的约束 |
|---|---|---|
| `version` | **旧索引独有**兼容版本；不是从 Batch/Sample 扫描生成 | 原样保留；版本超过当前实现已知可写版本时拒绝普通写入，不静默降级 |
| `createdAt` | **旧索引独有**创建时间 | 原样保留；仅明确初始化全新空库时生成一次 |
| `updatedAt` | 当前 K **提交的索引时间戳** | 只在真实索引提交时更新；不能用它作并发仲裁或事实权威 |
| `registryInternalPath` | **旧索引独有**来源/兼容信息；经用户明确改变来源设置时可更新 | 原值保留，除非本提交明确提供新来源值，且持锁校验该意图与最新状态；不得因预览缺项覆盖为 nil |
| `registrySourcePath` | 同上 | 同上 |
| `metadataColumnOrder` | **旧索引独有**合法显示/导入顺序；允许明确 Registry 操作更新 | 未明确更新时原样保留；来自旧预览的更新若与已提交的新顺序冲突则拒绝，不盲目取后写者 |
| `batches` | 原则上以各 Batch 的权威 `batch.json` 为对象内容来源，Sample 集合由物理有效 Sample 的实际登记计算 | 从完整、严格校验的最新磁盘状态生成；不能用旧 `baselineIndex.batches` 覆盖新 Batch；若发现索引中存在磁盘无对应来源的**独有**字段/关系，先拒绝并报告 |
| `samples` | 原则上以权威 `sample.json` 为科研对象记录来源 | 与 `batches` 同；保留正式 Sample 唯一 ID、历史映射及 provenance；缺失/冲突不能作删除/重建授权 |

**嵌套字段与未知 JSON 键：** 表中把 `batches/samples` 作为集合，并**不**宣称它们的所有既有/历史嵌套字段都可从文件重建。普通索引提交前，须将原始索引 JSON 按对象 ID 和字段逐项对照权威 `batch.json`/`sample.json`：能够明确映射且一致的投影才可重建；索引中多出的非空字段、未知顶层或嵌套键、旧格式字段、尚未归类的来源/人工数据，一律标记 `INDEX_FIELD_UNKNOWN` 并**拒绝普通索引覆写**。未经实现独立验证的“JSON decode→encode”不能用于未知字段保留。允许以后做有损失保护的透明透传实现，但本 v0.2 **不批准** Worker 在识别未知字段时自行猜测合并或删除它们。

**已知冲突处理：** 同一个未触碰 Batch/Sample 的合法现存信息与重新扫描结果不一致时，除可证明仅属派生的 `sampleKeys` 等字段外，不能用任一边直接覆盖另一边；返回 `CONFLICT/INCOMPLETE`，对受影响写入安全拒绝并保留原始字节。损坏 `batch.json`/`sample.json` 或索引缺失却存在历史记录，不得当作空库。

### 3.2 正常提交例程

在 K 内：①严格读取当前原始索引及版本、枚举权威 Batch/Sample；②核对已知/未知字段与冲突，保留原索引特有字段；③执行已预检的最小正式写入（可能多文件）；④从写后完整磁盘状态重算派生集合，加入经本次明确授权修改的源字段，其余保留；⑤最终写盘前再次核对原始索引版本、受影响文件与预期，冲突则不覆盖；⑥使用原子替换持久化索引并读回核验。**同一次提交禁止“先写一次派生索引、后用陈旧预览二次整体覆盖”。** 若出现部分写入，按第 5 节返回 PARTIAL/UNKNOWN，不可报告成功；重试先识别前次操作。

### 3.3 损坏索引的**明确例外**

已批准的 `recoverIndexFromFilesystem` 保持“用户明确确认的独立恢复操作”，不能隐式从同步/创建分支调用。恢复在 K 内**先备份损坏索引原始字节、验证备份完整性**，同时完整扫描来源与列出**无法从磁盘证明恢复的字段**。来源不完整直接停止；无法确定的独有字段必须如实列为 `POTENTIAL_LOSS`，未经原有明确授权及用户确认不得宣布“无损恢复”。备份和新索引分别报告，不能把丢失未知事实称为自动重建成功；文件冲突/备份失败一律拒绝，保留原损坏字节。重复执行要识别已有恢复/备份，避免覆盖原始证据。此例外不得用于绕开未知字段的普通写入拒绝。

## 4. C2/C4 — 删除授权集合与递归边界（修 D-02）

### 4.1 授权快照的规范格式（用于未来启用删除的先决约束）

用户在显式删除影响预览确认时固定不可变 `DeleteAuthorization`，至少包含：`operationId`；规范化 root 身份；操作种类与目标 Batch/Sample **机器 ID/当前 legacy key 映射**；用户明确确认的 Batch ID 与 Sample ID 集合；每个受影响 Sample/Batch `sample.json`/`batch.json` 的原始字节 hash/文件身份；受影响目录下**完整递归枚举**的所有文件、子目录及必要内容版本/大小，至少包括 `measurements/` 原始数据、sidecar、附属照片、未知文件及隐藏文件；独立 Workbench 的 `_spinlab`/`charts`/shared 图、其他 Sample 共享引用与受影响关系摘要；本次确认时间/授权范围。损坏、权限错误、目录无法枚举或关系歧义不得生成可提交授权。

**比较规则：** 执行时针对同一个 root 与全部受影响命名空间重新严格枚举并比较授权集合、身份、文件版本和共享关系。新增、移走、修改、未解析、符号链接变化、跨命名空间依赖改变或旧 key 被新对象复用，都不是同一授权；任何差异一律 `DELETE_SCOPE_CHANGED`，**在首次正式写入前**停止。`sampleKeys`、仅 UI 数量、文件名和 `mtime` 都不够；一份 Batch 快照不会授权之后加入的 `X_NEW`。重新生成预览或要求重新确认，不可在失败后自动扩大授权集合。

### 4.2 G1-01 **当前实际执行策略：递归物理删除禁用**

**本 v0.2 不批准通过 K 锁重新开放 Sample/Batch/Drawer 的递归物理删除**，因为不合作写入方可在校验与递归调用之间放入未授权文件。受禁范围：`deleteExistingDrawer`、`deleteSampleDrawer`、`deleteBatchDrawer`、Registry 缺行/改键导致的任何删除、直接 Store 入口，以及 `NativeSampleCreationService` 等回滚中对**可能已由其他写入方使用**的 Sample/Batch 目录递归清理。服务层必须在进入递归物理删除前统一 `fail-closed`；UI 只展示不可用原因与影响预览，不能只隐藏按钮、留底层 API 可达。

**有限允许的清理：** 仅当操作拥有**可证明属于本次提交的临时文件/精确文件路径**，且内容版本、所有权及路径下的全部内容可严格验证时，才允许条件清理该文件；空目录使用不会递归吞噬新内容的非递归 `rmdir`，并在竞争导致非空时停止。不得以“已创建目标目录”证明整个目录可递归清理。回滚失败时保留现场并 `PARTIAL`，不试图“清理到看起来成功”。

**外部不合作写入者：** K 无法挡住 Finder、同步器或其他不获取 K 的进程。由于当前不实现目录句柄隔离/保证性排他，G1 的合法结果就是**安全拒绝所有 Sample/Batch/Drawer 递归硬删除**；要重新开放须单独确认 O-ID3、证明真实排他/版本隔离，并重新进行适用设计审查及用户授权。单纯加入二次扫描或 K 锁，不是开放条件。

## 5. C5 — 提交状态、条件回滚与崩溃恢复（修 D-04）

### 5.1 提交/失败状态表（规范性）

| 阶段 | 可见已修改对象 | 返回/崩溃后的判断 | 恢复原则 |
|---|---|---|---|
| `R0 PREFLIGHT` 外层只读判断 | 无；不创建 K 文件 | 拒绝为 `NO_COMMIT`，Library 与 mtime 零变化 | 修正输入，再重新预览 |
| `R1 LOCKED_REVALIDATED` 获取 K 后再校验 | 仅 Root 外协调锁文件可能存在；Library Root 无修改 | 竞争/范围变化为 `NO_COMMIT` | 释放 K；可重新预览，不能报文件树被改变 |
| `R2 INTENT_DURABLE` 记录本次操作意图及计划写入文件版本 | Library 内隐藏协调记录 `/.spinlab/coordination/pending/<operationId>.json`；尚无科研正式变更 | 普通失败 `NO_DATA_COMMIT_WITH_RECOVERY_MARKER`；进程退出后有 pending | 重启**只读**检测 pending；锁内核查后方可关闭标记 |
| `R3 FILE_MUTATION` 写 `sample.json`/`batch.json` 或本次拥有的精确正式文件 | 可以已有部分对象已修改，新旧对象混合 | 失败/异常：`PARTIAL`，若无法核对为 `UNKNOWN` | 留下记录；**不**自动回滚其他写入者的文件 |
| `R4 INDEX_COMMIT` 从最新状态构建并原子提交 `library_index.json`，回读验证 | 已有正式文件及索引修改；可能还留 pending | 若核验一致为 `COMMITTED`；未核验/回执丢失为 `UNKNOWN` | 重启比较真实文件与记录的 opID/预期 hash，识别已经提交的操作 |
| `R5 FINALIZED` 结果核对完成，清除/归档 pending | 正式数据与索引提交；仅必要的协调审计记录 | 报 `COMMITTED` | 相同 `operationId` 重试只回读既有成果，不重复创建或删除 |

`R2` 的 intent 只包含操作 ID、规范 root 标识、受影响对象与路径、操作前/预计版本摘要、已完成阶段和必要核对证据；它**不是科研事实的第二权威**，不缓存可被独立编辑的 Parameter/Measurement。写入正式文件之前，必须先使 intent 可靠落盘（临时文件+原子提交，并对写入文件/必要目录同步；若平台不支持可靠持久化，不能声称崩溃后可恢复，拒绝该多文件提交）。操作成功结束才可清除/结案；任一中途崩溃留下可读 pending。若 pending 本身损坏，停止受影响正式写入、报 `UNKNOWN`，不得猜测已提交与否。

**`NO_COMMIT` 的准确定义：** Library Root 下没有任何正式数据/索引写入。R2 已写协调标记时只能说“科研数据未提交，但协调标记存在”，不能说“整个文件树未修改”。原 AC1/AC3 对只读审计及被阻止的危险删除仍要求根目录字节/mtime 完全不变；因此此类拒绝必须停在 R0/R1，不允许先创建 intent 再发现删除危险。R3/R4 不能报告 `Nothing was modified`。

### 5.2 条件回滚的**所有权与版本**

回滚仅可操作当前 `operationId` 在 intent 中登记并由本次提交创建/改写的**精确路径**。对每个文件要求在持锁状态下当前文件的原始字节 SHA-256（必要时文件身份与清单）**等于本次操作最后成功写入的版本**，且不存在未登记的子文件/关系变化；两项不满足就**禁止回滚该项**，保留现场并报 `PARTIAL/UNKNOWN`。绝不因旧快照存在而恢复完整 `library_index.json` 的原始字节。

索引回滚先核对当前索引原始字节版本仍为本操作自己的已提交版本；若其他写入方更新过索引，即使恢复看似更方便，也不得覆盖——优先按照第 3 节在 K 内基于最新数据重建受影响派生信息、保留独有字段，或保持 PARTIAL 等待受控恢复。若本次操作没有写入索引，回滚根本不触碰它。Batch 文件恢复同理。仅对明确由本操作创建、仍无其他内容的临时文件按版本清理；原生 Sample 新建回滚不得递归删除被外部新文件占据的目录。需至少有一例“回滚遇其他写入者提交→拒绝覆盖他人的改动”的确定性注入测试。

### 5.3 启动、重启、重试与并发恢复

启动/只读打开仅检查 pending/索引一致性并显示 `RECOVERY_REQUIRED`，**不自动创建锁、不修改文件、不中断正常只读浏览**。新的冲突性写入必须受阻；恢复在用户明确批准的范围内，获取 K、重新核对 intent/当前磁盘/原始索引，选择“已完成可核验→确认结案；部分写入→保留并对账；未知或损坏→人工恢复”之一，不伪造完整撤销。重试有独立 `operationId`；相同 ID 必须通过 intent/已提交证据幂等，不能重复新建。写索引成功但响应丢失，凭真实索引与操作标记识别已完成，不得新造第二 Sample。K 的内核锁在进程崩溃后释放，**pending 并不会自动消失**；业务恢复是新一次明确动作，不能因锁可获取就认定无未完成事务。

## 6. C6 — 兼容、实施顺序与真实边界

**P0（只读必要清单/先决核实）：** 在工作基线枚举全部 `saveIndex`、`library_index.json` 直接写/原字节回滚、`batch.json`/`sample.json` 正式写、递归删除与调用者。交付逐入口表：`K 已接入 / G1 安全拒绝 / 不参与 K 且不会触及 K 域 / 未知需先审`。核实同一用户多个 app 进程可访问统一 Application Support 锁目录、macOS POSIX `flock` 行为、App Sandbox/权限差异；不可证明共享就阻断相关 K 写入，不暗改权限。对历史字段包括嵌套未知 JSON 做保留/拒绝检查，不能拿仅存在的一套 fixture 当全量清点。

**P1（最小共同提交接缝）：** 实现单 Root K 的可传递上下文、锁外只读预检和锁内复检；禁止无上下文的索引直接提交与旧快照回滚；建立第 3 节的字段核对、最小 intent 与 R0–R5 状态语义。覆盖所有相关正式索引/Batch/Sample 创建、更新和批准恢复入口。普通合法功能必须实际成功，不能把“全拒绝”充作通过。

**P2（删除收口与回归）：** 对 Sample/Batch/Drawer 递归物理删除及不具归属证据的回滚路径统一 fail-closed，包含直接 Store API；保留影响预览、合法 Unlink 的既有独立安全路径（若已存在且经证实）、普通读/更新与受控恢复，不凭本设计新增 Trash/Purge。对冲突后数据安全、启动提示、日志与恢复证据做一次集中集成验证。G1 不依赖 #194/T01 的功能验收；#195 仍为 stacked PR，未经明确许可不得改 base/merge。

**不得声称 implemented-ready：** 只有本补充 `DESIGN PASS` 并不完成原 AC1–AC6；仍需实际受影响消费者、全范围测试、ReviewLoop/PR bot 当前 HEAD 审查与真实集成边界。G0 v1.4 设计通过不自动批准新版协议。

## 7. V1–V9 验证矩阵（修 D-05；不得以全拒绝冒充并发保护）

**所有测试均在隔离合成 Library、隔离 App Support/测试账户与安全临时卷进行。** 使用可确认到达的 barrier/hook，在两个独立 `Process`（真实不同 PID，不同 `LibraryStore` 实例）之间建立事件顺序；断言进程确实在期望点相遇。按实际可用 Mac/APFS 环境运行，不把 root 权限下 chmod 当可靠故障注入。每个用例必须记录：两方 PID、操作/失败点、实际返回状态、文件原始字节/mtime、索引列表及独有字段、重启后读取、恢复结果。无法触发预定失效点的测试不得计入 PASS。

| ID | 必须真的执行的场景和**结果断言** | 原冻结 AC |
|---|---|---|
| **V1 两进程合法创建** | 进程 P1/P2 同 Root 分别创建不同 Batch/Sample，重叠启动但经 K 串行化；**两边最终都成功提交**，索引与磁盘包含两份 Sample、Registry 独有字段/历史 `createdAt`/列顺序不丢；重启回读相同。只让一边拒绝不能算通过。 | AC5、AC6 |
| **V2 两进程合法更新+创建** | P1 更新已有 Sample/其合法数值或非破坏性字段，P2 同时新增不同 Sample/Batch；两进程交错执行，最终**两项都成功**，被更新原始 Sample 字节与新增 Sample 均可读、索引包含双方结果且未知字段保护规则未绕过；重启无 lost update。 | AC5、AC6 |
| **V3 A 丢失索引交错** | 重演删除 X/并发新增 Y_NEW。由于本版本删除被禁，验证 `deleteExistingDrawer`/直接 Store 删除在**没有任何正式写入**前拒绝，而独立合法 Y_NEW 创建能成功；索引/磁盘仍含 X 与 Y_NEW；不准把“删除被禁”当成 V1/V2 的替代。 | AC3、AC5 |
| **V4 B 未授权新建+测量** | 对 `deleteBatchDrawer`、`deleteSampleDrawer`、外层删除及 Native 回滚尝试 `X_NEW` 与测量/sidecar 插入；所有可能扩大删除范围的递归删除均在首写之前拒绝。被保护对象/测量/Workbench 内容和 mtime 不变；验证底层 API，不只 UI。 | AC1、AC3、AC5 |
| **V5 锁及根等价** | 两进程通过根实际路径与 symlink 别名操作，必须争用同一 K；锁超时、进程被杀后锁释放、重入传递、两个无关进程写入不得死锁；不受支持容器/路径识别失败必须停止相关写入；检查 Library 树无额外锁文件及预检零 mtime。 | AC1、AC5、AC6 |
| **V6 版本冲突/独有字段** | 在索引最终提交前注入另一个**非合作**索引字节更新；版本不符必须 `CONFLICT`，不覆盖其合法新增独有字段。旧索引顶层与 `batches/samples` 内嵌未知键、合法来源路径与列序均有样例：普通写入必须**原样保留或安全拒绝**，不能无声丢失；腐坏索引走单独受控恢复。 | AC1、AC5、AC6 |
| **V7 按阶段中断/启动** | R0、R1、R2、R3（Batch/Sample 已写一部分）、R4（index 已写但 ACK 未回）分别注入失败/真实进程终止；核对 pending、文件、index、重启只读识别、LOCK 释放与 PARTIAL/UNKNOWN/COMMITTED 报告。R3/R4 不得显示 Nothing was modified；恢复不靠清理意外科研文件。 | AC5、AC6 |
| **V8 条件回滚对抗** | Native 创建后触发失败，同时另写入者更新 index/Batch 或在新 Sample 目录增加文件；旧索引原字节不能回写覆盖外部提交，目录不能递归删新文件；必要时 PARTIAL/UNKNOWN 并保留现场。还要有无人介入的合法条件回滚成功路径。 | AC3、AC5 |
| **V9 旧合同全量回归** | `applyBatch/applyAll` 的缺行/rekey 在首次正式写前拒绝；读/预览无写，损坏文件 fail-closed、孤立 Workbench 资源不误绑、共享图不误删；合法 Registry 更新、Native 创建、选中创建、索引恢复都按授权正向成功/准确失败。覆盖 AC1–AC6 已有测试与新增 V1/V2，不接受只验证拒绝。 | AC1–AC6 |

**验收约束：** 真实两进程 V1/V2 是必须结果；其他可依故障注入，但必须到达指定阶段且提供完整可核验输出。`V3/V4` 的 fail-closed 正确只证明危险删除封闭，不证明普通双进程提交正确；`V6` 非合作写入在最后一次比对之后仍可能继续写入，不能因此宣称保护任意外部程序。

## 8. 设计审查、授权和变更控制

- **本设计 v0.2 当前没有独立 DESIGN PASS，Gate = PENDING。** 独立 Reviewer 应从固定 `policy_sha` 读取 `engineering-reviewer/skill.md`，先核对原始 UTF-8 文本及随附 `design_ref`，再核查 D-01～D-05 的闭环。独立审查结论只能为 `DESIGN PASS / DESIGN REWORK / DESIGN BLOCKED`，并绑定实际 SHA；本设计作者不得自签 PASS。
- 新版设计对原 G0 §5/§6 与冻结 G1-01 S1–S6、AC1–AC6 **加安全约束、不改验收指标**。对应用支持目录锁文件、新的最小 pending 协调标记和协作锁属于本补充设计新增实现范围：**即使审查 PASS，也仍需用户显式授权该确切补充范围的代码修改、commit/push/PR 操作**。原 G1-01 已授权的普通代码修改不等于批准新增这组跨模块协议。
- 不得触碰真实 Library、用户设置、正式删除/迁移；合成测试仅用隔离临时根/锁目录，不得用真实 Mac 设置或账户路径测试。不得更改 #194/T01，不擅自更改 #195 base、推送新代码、合并、改仓库权限或跳过 ReviewLoop/PR bot；后续实施需先核实最新 HEAD、loop、bot、有无 HUMAN_REQUIRED。
- **保留的风险/后续入口：** O-ID3 Trash/Unlink/Purge 产品选择、非合作外部写入者（尤其跨主机文件同步）、未来恢复硬删除、Workbench 内部成果索引的多写入一致性若未触及 K 域。上述内容**不是 G1 安全失效的豁免**；当前通过关闭对这些资产有破坏性影响的 Sample/Batch 递归删除来形成明确边界。若未来启用硬删除或扩大事务域，必须新设计/审批。

**设计审查须确认：** 当前方案是否在不建立全局事务数据库前，以可验证的**正常写入成功**、危险递归删除封闭、已知索引独有信息保留、阶段化失败恢复，满足原合同及 D-01～D-05；不得因文档存在就给代码 PASS。
