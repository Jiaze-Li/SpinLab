# SpinLab G1-01 — 共享写入一致性与删除安全补充设计 v0.4（独立 DESIGN Gate 候审）

**任务归属：** 原 `SPINLAB-G1-01-SAFETY v1.0` 的补充架构约束；不是新任务、不替换原 Worker 合同、不是代码实施授权。  
**状态：** `DESIGN GATE = PENDING`；v0.1、v0.2、v0.3 均已独立 `DESIGN REWORK`；本 v0.4 未经独立审查、不可实施。  
**风险 / Architect / 独立 Gate：** `Tier 3 / REQUIRED / REQUIRED`。  
**固定 `policy_sha`：** `2304f2e93185fca3b50fb1f076b2e1801797492d`。  
**原 G0 v1.4 设计原文：** `sha256:d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8`（46,620 bytes，UTF-8/LF；历史 DESIGN PASS）。  
**原冻结 Worker 合同：** `05_G1-01_冻结Worker任务合同_v1.0.txt`（12,397 bytes，SHA-256 `24521827f5fe06712f37430ed42d7aeecdd0337df705f12581bb84e8fdbbb1d9`）。原 **AC1–AC6、S1–S6 不变**。  
**历史补充审查：** v0.1 `sha256:ecd6bef69ff3cb340c5780653aa8857718cfc5f585f3bf618f5359937f1ea857` 已 `DESIGN REWORK`（D-01～D-05）；v0.2 `sha256:bc4e4e39598144630e48c056e89a80647507da67806a7380eaf7554b21ad6c7a` 已 `DESIGN REWORK`（R2-01～R2-03）。v0.3 `sha256:b5772dfa84c7678340113c50d613d599997d785c0d03b4fbd297922f9fe8c81e` 已独立 `DESIGN REWORK`（F3-01、F3-02）。本 v0.4 仅闭合持久 Root 身份及全 Root pending 恢复栅栏；继续沿用 C1–C6、P0–P2、V1–V9，不改变原 G0 和冻结 G1。  
**代码证据快照：** `Jiaze-Li/SpinLab` PR #195 `G1-01 → T01`，HEAD `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`；基线 T01 `d29d914b7a19824d822361ed67ea67b322705786`。在本文件形成时 PR #195 OPEN、未合并，机器人 `REWORK`、F001 P2 OPEN、最近审查 PARTIAL。  
**不可变 `design_ref`：** 交审时按本文件**全部原始 UTF-8/LF 字节（包含末尾换行）**独立计算 SHA-256，引用置于交审说明与随附清单，**不写入文件自身**以避免循环。若字节不匹配，停止审查。  
**证据属性：** A/B 故障由原 Worker 在隔离合成 Library 上确定性复现，主控已只读核查可达调用链；未宣称真实多进程/真实用户 Library 已动态验证。

## 0. 本轮裁决与明确非目标

**v0.2 审查反馈闭环（v0.3 已修订）：** R2-01＝R5 持久幂等凭据及重试语义（§5.3）；R2-02＝正式数据、索引、结案证据的可靠落盘顺序（§5.1、§5.4）；R2-03＝被重写 `sample.json`／`batch.json` 的原文未知字段保护（§3.1a）。**本 v0.4 的集中修正：** F3-01（会话级 st_dev/st_ino 不可充当永久 operationId 域）见 §2.2a；F3-02（R3/R4 pending 未结案前不得让其他 Batch 写入把部分状态纳入全局索引）见 §5.3a；V5/V7/V9 增加所需反例与正向恢复测试。两者均待独立复审，不宣称 DESIGN PASS。

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

1. 对**已存在且为目录**的 Root，`realpath` 解析用户给定路径与符号链接并取得 `fstat` 的 `st_dev + st_ino`，作为当前系统会话的**物理根锁定位**（`lockScopeKey`），不是永久 Root 身份；不可参与跨重启的幂等摘要。校验 root 及访问权限；根被替换、文件身份变化、无法确定 root 或路径逃逸时拒绝 K 写入。两个不同别名（真实路径与符号链接）指向同一目录时必须映射到**同一** K 键；不以输入的字符串路径为锁键。一个操作实际访问统一的已解析 root。
2. 锁文件规范位置：同一 macOS 用户的共享 Application Support 区域 `~/Library/Application Support/SpinLab/LibraryCoordination/v1/<SHA256(st_dev:st_ino)>.lock`，**在 Library Root 外**。不得使用每进程临时目录或每 App 实例不同沙盒容器。若进程不能访问同一协调目录（包括沙盒实例、不同 Unix 用户）则**不声称它们已协调**：相关 K 写入拒绝或另行设计；不能静默降级。
3. 使用 Darwin/POSIX `open(O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW)` + `flock(LOCK_EX | LOCK_NB)` 对稳定锁文件的**打开描述符**持锁。先核查父目录无不受信任符号链接、锁文件为普通文件，打开后 `fstat` 再校验；锁文件持久保留，绝不在解锁时 unlink。锁由**关闭持锁 fd**或进程退出释放；单文件 `.atomic` 不提供互斥。协调目录的建立仅在**准备实际写入且只读外层预检已通过后**允许；纯只读路径零写入。
4. 获取顺序：当前任务只允许**一个 Root K**；同一调用链内通过明确的 `WriteContext(lockScopeKey, durableRootIdentity, ownerToken, fd, phase)` 向下传递，嵌套 Store/Service 复用这一持锁上下文，**不得二次 `flock`**；跨根嵌套写入直接拒绝并要求拆分。不同任务/线程使用进程内按 root key 串行队列，再获得进程间 `flock`。最长等待 **5 秒**，按有限间隔非阻塞重试；锁被占用、IO 失败或不支持时返回 `LOCK_BUSY/LOCK_UNAVAILABLE`，任何正式文件不变，不在 UI 主线程自旋等待。
5. 持锁后**再次校验 root `st_dev/st_ino`**及规范化路径，完全重新获取实际提交所需的当前文件/引用/索引状态。预检 → 持锁再次核验 → 记录提交意图 → 正式写入 → 核实提交/标记阶段 → 释放。`try/finally`（Swift `defer` 等价）关闭 fd；异常不得悄悄放锁后继续写。代码不得依赖 inode/mtime 单独证明用户内容未变，仍须检查原始字节或对应强校验。
6. **协调安全边界：** K 仅串行化遵守同一个协议的写入者。外部编辑器、Finder、同步软件不参与 `flock`；检测到未协调状态变化时不能自动猜测合并，索引覆盖之前须比对原始索引版本与受影响文件/清单。非合作写入者可能在最后比较后再次写入，因此不宣称“锁能保证任意第三方操作安全”；对任何无法建立排他的 Sample/Batch 递归物理删除，直接保持禁止。

**零修改语义：** 首次危险计划**纯只读**预检失败时，无文件（包括锁文件）被创建/修改。持锁后的拒绝不能写任何 Library Root 下正式文件、索引或提交意图；锁元数据仅位于 Root 外，不计入 Library 文件树的 AC1/AC3 mtime 比对，但须单独检查无异常锁泄漏。锁持有本身不意味着业务提交。

### 2.2a 永久 Library 身份与会话锁身份的分离（F3-01，规范性）

**身份定义。** `lockScopeKey` 仅用于当前单机用户会话中 `flock` 排他，来源是经 `realpath/fstat` 核验的 `st_dev:st_ino`（§2.2），允许随系统重启、卷重挂载而改变。永久 `durableRootIdentity` 独立于文件系统设备编号：每个已受管 Library Root 在 `/.spinlab/coordination/root-identity.json` 保存一次性安全随机生成的 `rootUUID`、格式版本、初次登记时间及校验元数据；成功登记后合法移动、路径别名、同一 Library 重启均保持同一 rootUUID。`operationId` 的持久定位与请求语义摘要使用 `(rootUUID, operationId)` 及业务请求内容，**严禁纳入 st_dev、st_ino、当前绝对路径、会话 lockScopeKey 或后续可能变化的源文件 hash**。同一 operationId 在设备编号变化后重试必须找到原 completed，不能返回伪 `OPERATION_ID_CONFLICT` 或再次创建对象。

**首次登记是独立的受控写入，不是隐式浏览。** 对没有 root-identity 的存量 Root 报 `ROOT_UNREGISTERED`，只读访问可用，正常 G1 K 业务写入须先成功进行明确授权的 `REGISTER_ROOT`；可由首次合法写入流程提供一次可见的前置登记步骤，但不得让只读预览、自动重算或失败的危险操作隐式写入标识。REGISTER_ROOT 在先行无写扫描通过后，基于现存物理 Root 获取会话 K 锁；严格枚举现有隐藏协调目录、检测历史 pending/completed、Root 替换、symlink 与身份冲突。若旧式/未知协调状态不能判断则拒绝而非创建第二身份。标识仅在不存在且校验完毕时以独占创建+必要文件/目录同步落盘，并在**同一用户共享 Application Support** 记录可信的 rootUUID、既有规范路径、上次可核验物理对象及初始化状态（仅作本机防复制/绑定佐证，不是第二个科研权威）。这两个登记载体的部分失败必须报 `ROOT_REGISTRATION_PARTIAL` 并保留已落盘 rootUUID；后续受控登记恢复只可复用它，不得重新随机分配，也不得开始普通写入。新建 Root 须先通过等价初始化。登记有独立明确的变更报告，不得声称这是 AC1/AC3 的只读拒绝或 R0/R1 的零修改步骤。**正常已登记业务的 R0/R1 仍维持零 Library 正式文件修改；在它们执行前根身份必须已可核验。**

**别名、重启、移动与复制。** 在既有受信规范路径仍指向同一 rootUUID，且本机登记、源内容及可达 Root 不显示克隆冲突时，即使重新启动后的 `st_dev` 改变，也应在本次会话计算新 lockScopeKey，继续访问**原永久身份及其 pending/completed**，无须为设备号变化创建新的 receipt。symlink 等价路径必须映射同一物理 K 与同一 rootUUID。路径移动但仍有可信相同文件身份及可验证连续性时，可在 K 内受控更新**本机绑定登记**，保留 rootUUID；路径和卷均变化、旧路径不可核验、沙盒/用户不共享登记、身份标识损坏或出现歧义时停止正式写入，要求用户确认并经过 `ROOT_REBIND` 只读核对原身份、pending/completed 与新位置之后，才能受控提交新的本机绑定。不能靠旧字符串路径、元数据相似或设备编号自动推定是同一 Library。

两个可达 Root 具有同一 rootUUID 时视为**复制冲突**，双方均不得自动正式写入（`ROOT_IDENTITY_CONFLICT`），只读和明确受控比对仍可继续。ROOT_REBIND 仅允许证据充分的**同一 Library 迁移**延续身份；把复制库 fork 为第二个独立可写 Library、修改其身份或迁移历史幂等记录不在本 G1 授权范围。脱机拷贝或跨机器镜像无法仅凭本机 K/登记证明唯一性，无法判别时保持 fail-closed 并提示用户，而非承诺全局复制检测。Root 原文标识与 completed 中的 rootUUID 不一致、或本机可信登记状态丢失而又无法再核验时，不能静默以新 ID 重开旧库。

**状态与正向兼容。** `ROOT_UNREGISTERED` 和 `ROOT_REGISTRATION_PARTIAL` 均允许只读，但禁止普通 K 业务提交；必须提供一次性合法登记/受控恢复的真实成功路径，不得以全库写入永久禁用冒充安全。Root 初始化不改 Sample/Batch/Source/Result 的任何身份。所有 pending/receipt 的 Root 字段均采用 durableRootIdentity；对旧 receipt 的复用不得仅因设备号、inode 或路径重命名而失败。P0 必须核验同用户多进程能够访问同一绑定登记，否则该 Root 的 K 写入拒绝，不能暗改权限。

### 2.3 提交版本比对

K 入口在通过 §5.3a 强制恢复栅栏后于临界区读取 `(indexRawBytes, indexExists, durableRootIdentity, lockScopeKey, affectedRecordsManifest)`；`indexRawBytes` 用原字节 SHA-256 标识当前文件版本，读取失败不得当作空索引。锁内执行正式写入前，比较受影响的 `batch.json`/`sample.json`/测量及被治理引用与此次预览的预期版本。**索引最终覆盖之前重新读取原始索引字节并与本次在锁内建立的预期版本比较**；任何非本操作造成的变化都报 `CONFLICT`，不覆盖其更新。所有合作写入持同一 K，故此比较可用于发现非合作修改，但不宣称消除其所有 TOCTOU。`updatedAt`/目录 mtime 仅诊断，不能作为唯一版本条件。冲突时依第 5 节明确 `NO_COMMIT/PARTIAL/UNKNOWN`，不得盲目重试、覆盖旧文件或生成新 Sample。

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

**嵌套字段与未知 JSON 键：** 表中把 `batches/samples` 作为集合，并**不**宣称它们的所有既有/历史嵌套字段都可从文件重建。普通索引提交前，须将原始索引 JSON 按对象 ID 和字段逐项对照权威 `batch.json`/`sample.json`：能够明确映射且一致的投影才可重建；索引中多出的非空字段、未知顶层或嵌套键、旧格式字段、尚未归类的来源/人工数据，一律标记 `INDEX_FIELD_UNKNOWN` 并**拒绝普通索引覆写**。未经实现独立验证的“JSON decode→encode”不能用于未知字段保留。允许以后做有损失保护的透明透传实现，但本 v0.3 **不批准** Worker 在识别未知字段时自行猜测合并或删除它们。

**已知冲突处理：** 同一个未触碰 Batch/Sample 的合法现存信息与重新扫描结果不一致时，除可证明仅属派生的 `sampleKeys` 等字段外，不能用任一边直接覆盖另一边；返回 `CONFLICT/INCOMPLETE`，对受影响写入安全拒绝并保留原始字节。损坏 `batch.json`/`sample.json` 或索引缺失却存在历史记录，不得当作空库。

### 3.1a 即将重写的正式原文完整性（R2-03，规范性）

**保护对象：** 每一次 K 写入若会新建或重写现有 `sample.json`、`batch.json`，均须读取相关**原始文件字节**（不依赖 `LibraryIndex` 的投影）并做严格 JSON 结构核对。覆盖普通 Sample/Batch 更新、Registry Apply、选中创建时改写既有 Batch、`reconcileBatchSampleKeys`、Native 创建与条件恢复/回滚中的正式记录恢复。对**新建文件**须验证不会覆盖已存在文件；文件在验证后被非合作写入者改变时按冲突处理，不得盲目覆盖。历史文件即使不在索引中，仍属于必须保护的正式原文。

**字段与版本判断：** 对既有原文按 schema 的明确已知字段、明确允许的动态字典（例如 metadata 项）以及内部嵌套结构逐层核对；未知字段、旧版本兼容字段、嵌套未知键及不能分类的信息，不得由 `Codable decode → encode` 静默抹除。若实现能证明其**原值、类型与完整子树**在本次写入后不变，可以透明保留；本 G1 默认采用更保守的 `SOURCE_FIELD_UNKNOWN` **写前拒绝**，不要求 Worker 开发通用透传 JSON 引擎。动态字典中的已知合法用户键不是无条件的“未知字段”，但其未被明确授权修改的键和值必须原样保持。重复 JSON 键、无法严格解码、文件类型/位置异常、无合法 schema 版本映射或读失败均视为歧义，拒绝相关正式写入；不得用空对象/索引投影替代原文。

**强制检查点：** R0 只读外层检查、取得 K 后 R1 **重新按原始文件字节校验**，必须在写入 intent（R2）及任何 `batch.json`/`sample.json` 正式文件（R3）之前完成所有本次已知受影响源文件的字段识别与版本比对。若 R1 发现 `SOURCE_FIELD_UNKNOWN`／冲突，则拒绝、保持 Library Root 内容与 mtime 不变。R3 前新发现的写入目标先停止并重新核对；不能先写已知文件再发现下一文件未知字段并声称安全拒绝。持锁时发现未协调源文件变化，后续写入必须依 R2–R5 的阶段状态如实报告，不能覆写。

**特殊路径：** 原本批准的损坏索引恢复也不得擅改、修复或丢弃源文件未知字段；它只恢复索引，不授权源文件内容迁移。经另行明确授权的历史格式转换或有证据的透明保留机制不属于本次 G1 默认写入权限。P0 必须查明全部原文字节整文件写回者，并对每个写入者提供写前检查或 fail-closed 的真实接线证据。

### 3.2 正常提交例程

在 K 内：①严格读取当前原始索引及版本、枚举权威 Batch/Sample；②同时按 §3.1a 检查**将被改写的各个权威源文件**的原始字节、嵌套未知字段与版本，校验原索引独有信息；任一冲突/歧义须在 R2 前拒绝；③先可靠持久化 R2 intent，再执行已获准的最小正式写入（可能多文件）；④遵守 §5.4 的文件与目录持久化顺序，再从写后完整磁盘状态重算派生集合，加入经本次明确授权修改的字段，其余保留；⑤索引最终写盘前再次比对原始索引及受影响源文件版本，冲突则不覆盖；⑥索引可靠落盘并回读核验，随后可靠提交终态凭据，最后才清除 pending。**同一次提交禁止“先写一次派生索引、后用陈旧预览二次整体覆盖”。** 完成凭据不能丢失；任一阶段失败按 §5 真实返回 PARTIAL/UNKNOWN/RECOVERY_REQUIRED，不可报告未实际达到的 COMMITTED；重试先按原 operationId 查询前次结果。

### 3.3 损坏索引的**明确例外**

已批准的 `recoverIndexFromFilesystem` 保持“用户明确确认的独立恢复操作”，不能隐式从同步/创建分支调用。恢复在 K 内**先备份损坏索引原始字节、验证备份完整性**，同时完整扫描来源与列出**无法从磁盘证明恢复的字段**。来源不完整直接停止；无法确定的独有字段必须如实列为 `POTENTIAL_LOSS`，未经原有明确授权及用户确认不得宣布“无损恢复”。备份和新索引分别报告，不能把丢失未知事实称为自动重建成功；文件冲突/备份失败一律拒绝，保留原损坏字节。重复执行要识别已有恢复/备份，避免覆盖原始证据。此例外不得用于绕开未知字段的普通写入拒绝。

## 4. C2/C4 — 删除授权集合与递归边界（修 D-02）

### 4.1 授权快照的规范格式（用于未来启用删除的先决约束）

用户在显式删除影响预览确认时固定不可变 `DeleteAuthorization`，至少包含：`operationId`；规范化 root 身份；操作种类与目标 Batch/Sample **机器 ID/当前 legacy key 映射**；用户明确确认的 Batch ID 与 Sample ID 集合；每个受影响 Sample/Batch `sample.json`/`batch.json` 的原始字节 hash/文件身份；受影响目录下**完整递归枚举**的所有文件、子目录及必要内容版本/大小，至少包括 `measurements/` 原始数据、sidecar、附属照片、未知文件及隐藏文件；独立 Workbench 的 `_spinlab`/`charts`/shared 图、其他 Sample 共享引用与受影响关系摘要；本次确认时间/授权范围。损坏、权限错误、目录无法枚举或关系歧义不得生成可提交授权。

**比较规则：** 执行时针对同一个 root 与全部受影响命名空间重新严格枚举并比较授权集合、身份、文件版本和共享关系。新增、移走、修改、未解析、符号链接变化、跨命名空间依赖改变或旧 key 被新对象复用，都不是同一授权；任何差异一律 `DELETE_SCOPE_CHANGED`，**在首次正式写入前**停止。`sampleKeys`、仅 UI 数量、文件名和 `mtime` 都不够；一份 Batch 快照不会授权之后加入的 `X_NEW`。重新生成预览或要求重新确认，不可在失败后自动扩大授权集合。

### 4.2 G1-01 **当前实际执行策略：递归物理删除禁用**

**本 v0.4 不批准通过 K 锁重新开放 Sample/Batch/Drawer 的递归物理删除**，因为不合作写入方可在校验与递归调用之间放入未授权文件。受禁范围：`deleteExistingDrawer`、`deleteSampleDrawer`、`deleteBatchDrawer`、Registry 缺行/改键导致的任何删除、直接 Store 入口，以及 `NativeSampleCreationService` 等回滚中对**可能已由其他写入方使用**的 Sample/Batch 目录递归清理。服务层必须在进入递归物理删除前统一 `fail-closed`；UI 只展示不可用原因与影响预览，不能只隐藏按钮、留底层 API 可达。

**有限允许的清理：** 仅当操作拥有**可证明属于本次提交的临时文件/精确文件路径**，且内容版本、所有权及路径下的全部内容可严格验证时，才允许条件清理该文件；空目录使用不会递归吞噬新内容的非递归 `rmdir`，并在竞争导致非空时停止。不得以“已创建目标目录”证明整个目录可递归清理。回滚失败时保留现场并 `PARTIAL`，不试图“清理到看起来成功”。

**外部不合作写入者：** K 无法挡住 Finder、同步器或其他不获取 K 的进程。由于当前不实现目录句柄隔离/保证性排他，G1 的合法结果就是**安全拒绝所有 Sample/Batch/Drawer 递归硬删除**；要重新开放须单独确认 O-ID3、证明真实排他/版本隔离，并重新进行适用设计审查及用户授权。单纯加入二次扫描或 K 锁，不是开放条件。

## 5. C5 — 提交状态、条件回滚与崩溃恢复（修 D-04）

### 5.1 提交/失败状态表（规范性）

| 阶段 | 可见已修改对象 | 返回/崩溃后的判断 | 恢复原则 |
|---|---|---|---|
| `R0 PREFLIGHT` 外层只读判断 | 无；不创建 K 文件 | 拒绝为 `NO_COMMIT`，Library 与 mtime 零变化 | 修正输入，再重新预览 |
| `R1 LOCKED_REVALIDATED` 获取 K 后再校验 | 仅 Root 外协调锁文件可能存在；Library Root 无修改 | 竞争/范围变化为 `NO_COMMIT` | 释放 K；可重新预览，不能报文件树被改变 |
| `R2 INTENT_DURABLE` 记录本次操作意图、语义摘要及预期版本 | Library 内隐藏协调记录 `/.spinlab/coordination/pending/<operationId>.json` 已可靠落盘；尚无科研正式变更 | 普通失败 `NO_DATA_COMMIT_WITH_RECOVERY_MARKER`；进程退出后仍有 pending | 重启**只读**检测 pending；按同一 operationId 核对阶段与结果后方可处理标记 |
| `R3 FILE_MUTATION` 写经 §3.1a 预检的 `sample.json`/`batch.json` 或本次拥有的精确正式文件 | 可以已有部分对象已修改，新旧对象混合；每一文件及所需目录持久化须按 §5.4 完成 | 任一写入/同步失败：`PARTIAL`，若无法核对为 `UNKNOWN`，不得转 R4 | 留下 durable intent 和可判定阶段；**不**自动回滚其他写入者的文件 |
| `R4 INDEX_COMMIT` 从最新状态构建索引，原子替换、同步索引文件和目录，再回读验证 | 正式文件和索引可能已修改；R2 intent 必须仍可用 | 文件和索引**可靠落盘且核验一致**仅为内部 `DATA_COMMITTED_AWAITING_RECEIPT`，**不得对外报告 COMMITTED**；任何不确定为 `UNKNOWN/RECOVERY_REQUIRED` | 未产生 durable 终态凭据时从 pending 识别既有结果并补结案，禁止重新应用 |
| `R5 FINALIZED` 可靠写入不可丢的终态凭据 `completed/<operationId>.json` 后才清理 pending | 正式数据、索引及 completed 凭据均已可靠落盘；pending 可能尚未成功清理 | **凭据持久化成功**才可对外报 `COMMITTED`；若 pending 清理失败，报 `COMMITTED` 并附清理待办，不重新执行业务 | 同一 operationId 永远返回原终态/结果定位；允许随后合法修改资产，不撤销历史提交 |

`R2` intent 含本次业务提交的稳定 operationId、永久 durableRootIdentity（rootUUID）、明确请求语义摘要、受影响对象/路径、操作前及预计的版本摘要、可核查的结果对象身份、阶段与必要核对证据；它**不是科研事实的第二权威**，不缓存可独立编辑的 Parameter/Measurement。正式文件写入前必须可靠持久化 intent（具体顺序见 §5.4）。R3/R4 崩溃或同步失败不得清除唯一 pending。R5 的 completed 凭据可靠保存之前不得清除 pending；如 completed 已成功持久化但 pending 清理失败，保留两份标记并以相同 opId 关联识别，不能把重复 pending 视为新创建授权。若 pending 或 completed 损坏/互相冲突，受影响写入停止，返回 `UNKNOWN/RECOVERY_REQUIRED`，保留原始证据。

**`NO_COMMIT` 的准确定义：** Library Root 下没有任何正式数据/索引写入。R2 已写协调标记时只能说“科研数据未提交，但协调标记存在”，不能说“整个文件树未修改”。原 AC1/AC3 对只读审计及被阻止的危险删除仍要求根目录字节/mtime 完全不变；因此此类拒绝必须停在 R0/R1，不允许先创建 intent 再发现删除危险。R3/R4 不能报告 `Nothing was modified`。

### 5.2 条件回滚的**所有权与版本**

回滚仅可操作当前 `operationId` 在 intent 中登记并由本次提交创建/改写的**精确路径**。对每个文件要求在持锁状态下当前文件的原始字节 SHA-256（必要时文件身份与清单）**等于本次操作最后成功写入的版本**，且不存在未登记的子文件/关系变化；两项不满足就**禁止回滚该项**，保留现场并报 `PARTIAL/UNKNOWN`。绝不因旧快照存在而恢复完整 `library_index.json` 的原始字节。

索引回滚先核对当前索引原始字节版本仍为本操作自己的已提交版本；若其他写入方更新过索引，即使恢复看似更方便，也不得覆盖——优先按照第 3 节在 K 内基于最新数据重建受影响派生信息、保留独有字段，或保持 PARTIAL 等待受控恢复。若本次操作没有写入索引，回滚根本不触碰它。Batch 文件恢复同理。仅对明确由本操作创建、仍无其他内容的临时文件按版本清理；原生 Sample 新建回滚不得递归删除被外部新文件占据的目录。需至少有一例“回滚遇其他写入者提交→拒绝覆盖他人的改动”的确定性注入测试。

### 5.3 启动、重启、重试与并发恢复

启动/只读打开仅检查 root-identity、pending/completed 与索引一致性，在需要时显示 `ROOT_UNREGISTERED`／`RECOVERY_REQUIRED`，**不自动创建锁、不修改文件、不中断正常只读浏览**。按 §5.3a，所有新的 K 域正式写入在存在未结案 pending 时必须被全 Root 栅栏拒绝；恢复在用户明确批准的范围内，获取 K、重新核对 rootUUID/intent/receipt/当前磁盘/原始索引，选择“已完成可核验→确认或补写结案；部分写入→保留并对账；未知或损坏→人工恢复”之一，不伪造完整撤销。

**同一业务提交的全部重试**（客户端超时、回执丢失、App 重启、跨进程同时发送）必须复用在初次提交前分配且可恢复的同一 `operationId` 和同一请求语义摘要。独立执行尝试可有不同 `attemptId`，但不能用它替换 operationId；两次用户明确的**不同**新建意图才分配不同 operationId。语义摘要包括操作类型、永久 durableRootIdentity（rootUUID）、目标身份/映射、用户授权的修改内容及作用范围；严禁使用 st_dev/st_ino、当前绝对路径或会话 lockScopeKey 充当幂等依据；同 ID 不同摘要为 `OPERATION_ID_CONFLICT`，在写前拒绝。没有能力重现旧 operationId 的调用者不得默认为新请求重试；必须提示核对或明确要求一次**新的**用户意图。

**终态凭据**在该 Library Root 的 `/.spinlab/coordination/completed/<operationId>.json` 下不可覆盖地持久保存：至少包含协议版本、operationId、durableRootIdentity（rootUUID）、请求语义摘要、结果类型（成功/有证据的最终拒绝）、最终状态、创建/更新对象的稳定身份与定位、提交时结果版本/必要 hash、完成时间及所需映射。它只是提交与幂等证据，**不产生第二份可编辑科研事实**。同 ID 并发请求在 K 内只允许首个提交，后续检查 completed 或 pending：completed 且摘要一致直接返回原结果；pending 则按阶段恢复/阻断，绝不重新创建。**R5 清除 pending 之前必须持久化 completed 凭据**；本 G1 不删除、不按时间自动淘汰该最小凭据，未来若要归档/压缩，须证明可在全部受支持的重试范围内等效查询并另审。对象随后经合法更新、改名或已有明确删除决定而变化时，旧凭据仍只证明**当次提交的历史终态和对象身份**，不能仅因当前文件 hash 改变而重新执行旧命令；必要时返回“历史已提交，当前对象已变化”的准确结果。

索引可靠写入但回执/receipt 尚未完成时，必须以 durable pending 中的 operationId、对象身份及原操作预期核对真实正式文件，能够确定已提交则**先补写并同步终态凭据**，再结案；不能以当前文件名/属性相似自动新建第二 Sample。若 pending 与当前记录不能确认，保留 `UNKNOWN`，不执行新业务。同一次提交绝不使用新的 operationId 来“恢复”旧意图。K 的内核锁在进程崩溃后释放，但 pending 不会自行消失；业务恢复是新的受控恢复动作（可有新的恢复 attemptId），不能把它视为新的原业务提交。

### 5.3a 未完成事务的全 Root 发布与写入栅栏（F3-02，规范性）

**必须先于任何副作用。** 所有 K 域正式写入入口在完成锁外纯只读预检、取得 K、确认 durableRootIdentity 后，必须**严格枚举并核验该 Root 的 pending/completed 原始记录及阶段**，在这项全局栅栏通过前不得创建新的业务 intent、写 `library_index.json`、`batch.json`、`sample.json`、提交源目录/子目录、移动旧 Batch 或写登记的修改日志。特别包括现有 `ensureRoot → migrateLegacyBatchLayoutIfNeeded`、`syncIndexFromFilesystem[Checked]`、`reconcileBatchSampleKeys`、`updateSample` 的 change log、受控索引恢复和直接 Store API。既有扫描可能有目录迁移副作用，因此“读取前调用 ensureRoot”不是可接受的栅栏实现。未枚举完毕、未知/损坏的协调文件、缺失终态证据不得当空 pending。只读打开/预览仍只能使用纯读取流程，不创建锁或写文件。

**默认全局保守规则。** 只要存在 R2/R3/R4 未结案 pending（含阶段不明、completed 不存在/无法严格匹配），进入 `RECOVERY_REQUIRED`：拒绝**所有新的 K 域业务写入及会扫描并持久化全局索引的入口**，即使目标是完全不同的 Batch。不能让操作 B 扫到 A 崩溃后 R3 留下的部分 Sample/Batch 数据，并将其发布为 B 的已成功索引。拒绝须在 B 的首次正式写入、迁移目录和变更日志之前完成，且不另建 B 的 intent；不得靠 Batch ID 不同放行。本 G1 不支持部分 pending 的细粒度隔离例外；将来要开放必须有独立设计和证据。

**completed + 尚存 pending 的区别。** 已可靠持久化的 completed receipt（rootUUID、operationId、请求摘要、终态与 pending 严格相符）代表 R5 已结案；对应未清理的 pending 标记为 `COMPLETED_PENDING_CLEANUP`，**不形成未结案栅栏**，允许后续合法业务。清理只在经过授权的维护操作中进行，不得借只读打开自动清理，亦不得在开始下一业务时把它重当新意图执行。任何冲突、乱码、不可解析标记均保持 `RECOVERY_REQUIRED`。

**唯一安全恢复路径。** 存在未结案 pending 时，只允许已获授权的 `RECOVER_OPERATION(originalOperationId)` 使用相同 durableRootIdentity、原始请求摘要、当前真实文件与索引证据在 K 下识别原操作；不得用新的 operationId 伪装恢复。R2 尚未改正式数据且有完整字节/目录证据时，可按可靠终态规则安全中止/标记；R3/R4 只有证明全部原意图对象及依赖已达到可持久核验的目标时，才可可靠补齐索引、完成凭据并解除栅栏。无法确认、发现新文件/未知字段/其他写入方更新时保留 `PARTIAL/UNKNOWN/RECOVERY_REQUIRED` 与现场，禁止盲目恢复旧索引或递归删除。恢复完毕后，先以同一 K 重新检查全 Root pending/completed 与索引，再允许正常写入；锁因崩溃释放不代表 A 已结案。

**状态转换闭包。** Root 的业务写入许可状态为 `CLEAN`（无未结案 pending）或 `COMPLETED_PENDING_CLEANUP`（completed 已结案）；前者进入 R2 后在原 K 内变为 `ACTIVE_PENDING`，只有当前持锁原操作可继续 R3/R4/R5。进程失效后重新访问见到未结案 pending，即 `RECOVERY_REQUIRED`，另一个操作不能继承它、也不能利用另一个 Batch 的不同 ID 放行。只有按原 operationId 完成受控恢复并取得可靠终态凭据才返回 CLEAN/COMPLETED_PENDING_CLEANUP；无法证明已结案必须保持阻断，纯只读访问不受影响。原 §5.4 持久化与 §5.2 条件回滚均适用；全局栅栏不是新的业务权限或数据库实体。

### 5.4 可靠持久化提交顺序（R2-02，规范性）

**不变的先决条件：** 仅用 `Data.write(.atomic)`、单文件 rename、同进程回读或 `flock` **都不足以证明跨文件断电持久性**。P0 必须验证受支持的目标 macOS/APFS 及其他实际卷类型能提供并成功执行必要文件和父目录同步（例如写临时文件后对文件描述符 `fsync`／经平台验证的等效强制落盘操作、同卷原子 rename，再同步承载目录）；对需要稳定介质缓存刷新的平台须按已证实的 `F_FULLFSYNC` 或等效机制处理。不能预设所有文件系统都允许目录 `fsync`、支持跨卷原子 rename 或具有同等断电保证。任一必需同步原语失败/不支持时不得声称达到该阶段的 durable 条件或 `COMMITTED`；如写入已发生，应保留证据并报告 `PARTIAL/UNKNOWN`，不能退回显示 `NO_COMMIT`。测试可用受控 I/O 抽象记录调用、模拟失败与次序；进程退出验证并不等价于实测掉电安全。

**单一受协调提交的顺序与栅栏：**
1. **R0/R1：** 在任何 Library Root 文件写入前完成安全判断，包括 §3.1a 的被重写源文件原始 JSON 未知字段核对；持锁后重检，遇危险/冲突直接 `NO_COMMIT`。
2. **R2 durable intent：** 在同卷或具备同等持久化语义的协调目录内创建暂存 intent，写入、同步文件、原子安装为 `pending/<operationId>.json`、同步所有影响可达性的必要父目录；完成并核实之后才允许改正式数据。若还未安装 intent 即失败，验证无正式写入；若安装/同步状态不确定，报告 `UNKNOWN` 并保留现场，不继续写正式数据。
3. **R3 正式记录：** 对每个获准 `sample.json`、`batch.json` 及本次精确路径，执行内容写入、必要文件与目录同步，记录可核查版本；**全部必要正式文件持久化成功**且与 intent 的已完成阶段相符后才进入索引阶段。部分文件写成功或其同步失败即停止、保留 pending，报 `PARTIAL/UNKNOWN`；不得将未同步文件伪称可靠提交。
4. **R4 index：** 从经验证的最新正式文件建立索引，重核原索引版本与源文件版本；索引临时文件同步→同卷原子替换→父目录同步→重新读取验证；以上步骤全部成功才进入 `DATA_COMMITTED_AWAITING_RECEIPT`，尚不得向调用者返回最终 `COMMITTED`。任一失败保留 pending，报 `UNKNOWN/RECOVERY_REQUIRED`（若可确定哪些记录已提交则同时报告实际部分状态）。
5. **R5 durable receipt：** 不可覆盖地写入 `completed/<operationId>.json` 的终态凭据，逐一完成文件与目录同步，并与本次语义、结果身份及原始 intent 对照；**只有这份凭据可靠持久化后**才能向调用者承诺 `COMMITTED`。在此之前响应丢失/进程终止，重启必须用 pending 核对已经可靠写入的结果，再补齐完成凭据，而不是第二次执行。
6. **pending 清理/归档：** completed durable 后，允许删除 pending，删除及必要目录同步成功则已结案；清理失败则保留 pending 并在成功返回中注明 `CLEANUP_PENDING`（仍可据 completed 凭据确认已提交），后续受控清理不得重新做业务写入。不得先清除 pending、再写 receipt，亦不得在只有“索引回读成功”时删除唯一恢复证据。

**阶段差错和崩溃判定：** 所有上述同步失败需记录**确实抵达的阶段与文件路径**；R2 以后不可自动声称原树未改变。重启只读观察仅提示已存在的 pending/completed/正式文件状态，受控恢复获取 K 后核对原意图与结果；无法证明 durable 已完成时 `UNKNOWN`，不能自动压缩为 `COMMITTED`。完成凭据永久保留与所有权/条件回滚规则适用；即使将来有外部修改使最终源文件 hash 改变，也不得重放已结案的 operationId。

## 6. C6 — 兼容、实施顺序与真实边界

**P0（只读必要清单/先决核实）：** 先只读核实永久 Root 身份登记、移动与复制、跨重启身份的可执行性；列出 K 全域 pending 栅栏的所有受影响写入入口及其先于 ensureRoot/migrate/change-log 的实际拦截点。在工作基线枚举全部 `saveIndex`、`library_index.json` 直接写/原字节回滚、`batch.json`/`sample.json` 正式写、递归删除与调用者；同时清点实际 App/Store 的 operationId 分配和跨重试传递路径、可持久保存的最小 completed 凭据及目标卷持久化同步能力。交付逐入口表：`K 已接入 / G1 安全拒绝 / 不参与 K 且不会触及 K 域 / 未知需先审`。核实同一用户多个 app 进程可访问统一 Application Support 锁目录、macOS POSIX `flock` 行为、App Sandbox/权限差异；不可证明共享就阻断相关 K 写入，不暗改权限。对历史字段包括嵌套未知 JSON 做保留/拒绝检查，不能拿仅存在的一套 fixture 当全量清点。

**P1（最小共同提交接缝）：** 实现一次性可恢复的永久 Root 身份登记、单 Root K 的可传递上下文、锁外只读预检、锁内全 Root pending 恢复栅栏和复检；禁止无上下文的索引直接提交与旧快照回滚；建立第 3 节索引及权威 JSON 原文字段核对、最小 intent/completed 幂等凭据与第 5 节 R0–R5 持久化阶段语义。覆盖所有相关正式索引/Batch/Sample 创建、更新和批准恢复入口。普通合法功能必须实际成功，不能把“全拒绝”充作通过。

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
| **V5 锁与永久 Root 双身份（F3-01）** | 两进程经真实路径与 symlink 别名操作，必须争用同一 K；锁超时、杀进程释放、重入、不同进程无死锁。**模拟系统重启后 st_dev 变化、rootUUID 保持、旧 completed 仍可用同一 operationId 找到，不能错误冲突或再次创建 Sample。** 验证旧 Root REGISTER_ROOT 首次登记与局部失败受控补登记正向成功，合法移动/路径别名保留 rootUUID；同机两个可达复制 Root 同 UUID 必须拒绝写入，跨卷/脱机来源不明时要求 rebind；只读路径不写标识或锁文件，不能以所有登记永久拒绝作为通过。 | AC1、AC5、AC6 |
| **V6 版本冲突/独有字段（R2-03）** | 在索引最终提交前注入**非合作**索引字节更新，必须 `CONFLICT` 且不覆盖新增独有字段。旧索引顶层与其嵌套未知键必须原样保留或写前拒绝；**另在源文件独有、索引完全没有的未知键**（含 Sample/Batch 嵌套字段）分别注入 `sample.json` 与 `batch.json`：验证普通数值/字段更新、选中创建改写既有 Batch、`reconcileBatchSampleKeys` 及恢复相关写回都在**首次正式写入前**保留原值或抛 `SOURCE_FIELD_UNKNOWN`，确认源文件字节/mtime 未变；合法已知字段更新应成功。索引损坏仍走单独受控恢复。 | AC1、AC5、AC6 |
| **V7 按阶段中断/幂等/全 Root pending 栅栏（R2-01/R2-02/F3-02）** | 在 R0/R1/R2、R3 各正式文件写入及同步、R4 index 写入及目录同步、R5 receipt 写入及同步、completed durable 后 pending 删除/目录同步分别注入明确的 I/O 同步失败与真实进程终止；验证调用日志的**先后次序**、实际到达点、磁盘原始字节、pending/completed、索引、重启只读判定与 PARTIAL/UNKNOWN/COMMITTED，不把进程退出试验冒充断电安全。**必须覆盖 R5 完成凭据已持久化、pending 已清理、回执丢失后用同一 operationId 重试；完成后另有合法更新导致源文件 hash 变化仍不可重做旧请求；同 ID 不同请求摘要拒绝；两真实进程同 ID 并发重试只产生一个结果。** completed 同步失败不得清掉唯一 pending，也不得报已最终提交；pending 清理失败则保留证据且不重复业务。**必须执行两个不同 PID 的定点交错：A 在 R3（另测 R4）部分正式文件写入后崩溃，B 获得 K 后拟更新另一个 Batch；B 必须在任何 ensureRoot/目录迁移、变更日志、索引写入前被 RECOVERY_REQUIRED 拒绝且不能把 A 的部分状态发布为 B 的已提交索引。A 通过受控恢复完成并落盘 completed 后，B 的相同合法操作必须成功。若 A 已 completed durable 但 pending 未清理，B 也必须可正常成功且不得重复 A。** | AC5、AC6 |
| **V8 条件回滚对抗** | Native 创建后触发失败，同时另写入者更新 index/Batch 或在新 Sample 目录增加文件；旧索引原字节不能回写覆盖外部提交，目录不能递归删新文件；必要时 PARTIAL/UNKNOWN 并保留现场。还要有无人介入的合法条件回滚成功路径。 | AC3、AC5 |
| **V9 旧合同全量回归（R2-01/R2-03）** | `applyBatch/applyAll` 缺行/rekey 在首写前拒绝；读/预览无写、损坏文件 fail-closed、孤立 Workbench 资源不误绑、共享图不误删。合法 Registry 更新、Native 创建、选中创建、reconciliation 与受控索引恢复要正向成功；合法旧源文件动态 metadata 不被错误归为未知，不接受以全面拒绝代替兼容。核对新建/更新从 App 至 Store 的 operationId 传递、重试复用与完成凭据；**核对 ensureRoot → migrateLegacyBatchLayoutIfNeeded 的目录移动与 updateSample 的日志写入均只能在 K 且 pending 栅栏通过后发生；从旧 Root 的受控登记到合法创建、更新及受控恢复都必须有真实成功证据。**兼容性依据为冻结 AC1–AC6、S1–S6 和 V1/V2 真双进程成功测试。 | AC1–AC6 |

**验收约束：** 真实两进程 V1/V2 是必须结果；其他可依故障注入，但必须到达指定阶段且提供完整可核验输出。`V3/V4` 的 fail-closed 正确只证明危险删除封闭，不证明普通双进程提交正确；`V6` 非合作写入在最后一次比对之后仍可能继续写入，不能因此宣称保护任意外部程序。

## 8. 设计审查、授权和变更控制

- **本设计 v0.4 当前没有独立 DESIGN PASS，Gate = PENDING。** 独立 Reviewer 应从固定 `policy_sha` 读取 `engineering-reviewer/skill.md`，先核对原始 UTF-8 文本及随附 `design_ref`，再核查 D-01～D-05 的闭环。独立审查结论只能为 `DESIGN PASS / DESIGN REWORK / DESIGN BLOCKED`，并绑定实际 SHA；本设计作者不得自签 PASS。
- 新版设计对原 G0 §5/§6 与冻结 G1-01 S1–S6、AC1–AC6 **加安全约束、不改验收指标**。对应用支持目录锁文件、新的最小 pending 协调标记和协作锁属于本补充设计新增实现范围：**即使审查 PASS，也仍需用户显式授权该确切补充范围的代码修改、commit/push/PR 操作**。原 G1-01 已授权的普通代码修改不等于批准新增这组跨模块协议。
- 不得触碰真实 Library、用户设置、正式删除/迁移；合成测试仅用隔离临时根/锁目录，不得用真实 Mac 设置或账户路径测试。不得更改 #194/T01，不擅自更改 #195 base、推送新代码、合并、改仓库权限或跳过 ReviewLoop/PR bot；后续实施需先核实最新 HEAD、loop、bot、有无 HUMAN_REQUIRED。
- **保留的风险/后续入口：** O-ID3 Trash/Unlink/Purge 产品选择、非合作外部写入者（尤其跨主机文件同步）、未来恢复硬删除、Workbench 内部成果索引的多写入一致性若未触及 K 域。上述内容**不是 G1 安全失效的豁免**；当前通过关闭对这些资产有破坏性影响的 Sample/Batch 递归删除来形成明确边界。若未来启用硬删除或扩大事务域，必须新设计/审批。

**设计审查须确认：** 当前方案是否在不建立全局事务数据库前，以可验证的**正常写入成功**、危险递归删除封闭、已知索引独有信息保留、阶段化失败恢复，满足原合同及 D-01～D-05；不得因文档存在就给代码 PASS。
