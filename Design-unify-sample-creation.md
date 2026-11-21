# UNIFY-SAMPLE-CREATION — Design v1.0

- **policy_sha:** `7f01e5a3ff53ed13ba763d684a098c0989425ec4`（已读取 `engineering-workflow/README.md` 与 `engineering-architect/skill.md`）
- **Plan:** `Plan.md` v1.1（PR #220 `fix/unify-sample-creation`，包含 `SKELETON.md` 放宽提交 `9671a198`）
- **核查基线：** `fix/unify-sample-creation@9671a198`（本地 worktree `/Users/jack/Downloads/scripts/SpinLab-unify-sample-creation`）
- **目标：** 将桌面手写、手机 HTML、XLSX 三条 Sample 创建路径收口到唯一编号规则、唯一发号入口、独立旧键映射与唯一创建服务；一次性安全补发老样品 `smp_` 并记录与旧 `Sample Key` 的对照；下线旧 key 生成逻辑；Library 界面统一展示 `smp_`。
- **范围：** Sample 编号规则/分发/映射层、XLSX Registry 解析与同步适配、手机端提交单换算收口、老样品补发（预演/备份/原子写入/单次重建索引/全量校验）、Library UI 展示切换、防绕开自动检查及对应测试。
- **非目标：** 不迁移老样品目录/旧索引/测量/出图记录；不修改用户原 `.xlsx`；不拆分或改动 `NativeSampleCreationService.createSample` 内部写入与回滚逻辑；不改测量分析或出图算法；不引入多用户并发锁。

---

## Options（路线比较与取舍）

1. **路线 A（采用）：复用 `NativeSampleCreationService` 与 `LibrarySample.sampleUID / legacySampleKey`，新增薄分层（Rule / Issuer / Mapping / Backfill）**
   - 编号规则、分发、映射各自独立为小模块；`CreateNativeSampleDraft` 增加带默认值的可选字段（`legacySampleKey`、`origin`、`sourceSheetName`、`sourceRowNumber`），`createSample` 内部流程与回滚原样保留。
   - 对照直接存放在每个样品自己的 `sample.json`（`sampleUID` + `legacySampleKey`），不新建独立映射表或 SQLite 文件。
   - **优点：** 改动最小、零额外持久化状态与同步漂移风险；严格满足“现有创建服务内部不拆分、不改行为”和 `SKELETON.md` 放宽边界（仅向 `sample.json` 补写这两项）。
2. **路线 B（否决）：新建独立的 JSON/SQLite 全局映射表文件管理 `smp_ <-> legacySampleKey`**
   - **否决理由：** 已有 `LibrarySample.sampleUID` 和 `legacySampleKey` 两个字段且 `LibraryStore` 已在读写时自动保留它们；另建映射文件会引入第二权威、双写一致性与额外索引重建复杂度，违反“最简复用优先”。
3. **路线 C（否决）：把 XLSX 同步与老样品补发拆成一套全新的 Sample 落盘服务，仅共享编号函数**
   - **否决理由：** 直接违反 Plan §4.2“禁止任何上游入口自行构造样品、自行生成主键或自行落盘”，且会复制路径安全检查、batch 更新和回滚逻辑。

---

## Assumptions（未在 Plan 明说的默认前提）

1. **老样品补发入口形式：** 单人本地工作流通过应用内 Library 设置/维护入口触发“预演 → 确认后执行补发”（同时以独立服务封装，便于测试与命令行调用），无需后台守护进程或自动开机静默改库。
2. **手机多衬底提交的编号规则：** 手机端一份 `submissionId` 含多个衬底时，当前用基础编号加 `-2`、`-3` 后缀区分各衬底草稿；只要该后缀拼接也收口进统一编号规则模块（而非散落在 `NewSampleFields` 与 `PhoneSamplePickup` 两处），即满足“同一编号规则”与重复拉取幂等。
3. **UI 展示 `smp_` 的方式：** Plan §6 AC-6 要求“Library 界面不再展示旧 Sample Key，统一展示 `smp_`”，§7.4 确认“不再展示旧 Sample Key”；对已有 `sampleUID` 的样品，详情/搜索预览/图库页统一展示 `sample.sampleUID`（标签改为 `Sample UID` 或等价无旧 key 展示；若极端情况尚未补发则回退 `sample.persistentIdentity` 或提示未补发，不再把旧 key 原样当 `Sample Key` 展示）。

---

## 已核实事实（代码基线，均为直接读取）

1. **编号生成与校验当前分散在两处：**
   - `Sources/SpinLabApp/Library/NativeSampleCreationService.swift:538-546`：
     `static func makeSampleUID() -> String { "smp_" + UUID().uuidString.lowercased() }`
     `static func isValidSampleUID(_ value: String) -> Bool { guard value.hasPrefix("smp_"), value.count > 4 else { return false }; return value.dropFirst(4).allSatisfy { $0.isNumber || ("a"..."f").contains($0) || $0 == "-" } }`
   - `Sources/SpinLabApp/Library/PhoneSamplePickup.swift:206-208`：
     `static func sampleUID(forSubmission submissionId: String) -> String { "smp_" + submissionId.lowercased() }`
   - `Sources/SpinLabApp/Library/NewSampleFields.swift:156-160`：
     `makeDraft(..., sampleUID: Self.sampleUID(base: sampleUID, index: index), ...)`（内部为多衬底追加 `-2`、`-3`）。
2. **桌面手写与手机端已走 `NativeSampleCreationService.createSample`，内部约 500 行：**
   - `Sources/SpinLabApp/Library/NativeSampleCreationService.swift:4-16`：`CreateNativeSampleDraft` 当前包含 `batchId`, `substrateDescription`, `displayName`, `metadata`, `sampleUID`, `numericTags`, `numericDisplay`。
   - `Sources/SpinLabApp/Library/NativeSampleCreationService.swift:197-217`：构造 `LibrarySample` 时硬编码 `sourceSheetName: nil, sourceRowNumber: nil, ..., sampleUID: sampleUID, legacySampleKey: nil, origin: "native"`。
3. **XLSX 解析与同步当前绕开唯一创建入口且直接用旧 key 作 `id`：**
   - `Sources/SpinLabApp/Library/LibraryRegistryParser.swift:168-192`：
     `let sampleKey = substrateParser.sampleKey(batchId: batchId, substrate: substrate)`
     `let sample = LibrarySample(id: sampleKey, displayName: displayName, ..., sourceSheetName: sheetName, sourceRowNumber: rowIndex + 2, updatedAt: now)`（`sampleUID` 与 `legacySampleKey` 均为 `nil`）。
   - `Sources/SpinLabApp/Library/LibraryRegistryParser.swift:449-462`：`sampleKey(batchId:substrate:)` 调用 `SampleSemanticDescriptor.withPrevalidatedTokens(...).canonicalKey ?? "\(batchId)||UNKNOWN|UNKNOWN"`。
   - `Sources/SpinLabApp/Library/LibrarySyncService.swift:295`（`applyBatch`）与 `435`（`applyAll`）：直接对 `newSamples` 调用 `libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)`。
4. **生长记录导入链路使用 `sampleKey` 作语义签名校验而非创建样品：**
   - `Sources/SpinLabApp/Registry/RegistryGrowthImportPlanner.swift:401,733`：调用 `substrateParser.sampleKey(batchId: batchId, substrate: substrate)` 计算 `registryIdentities` / `obsidianIdentities` 与 `expectedSampleKeys`。
   - `Sources/SpinLabApp/Registry/RegistryGrowthMutationService.swift:571-583`：写入 `.xlsx` 后通过 `LibraryRegistryParser` 回读，并用 `Self.substrateSignature` 比对 `Set(batch.sampleKeys)` 与 `Set(item.expectedSampleKeys)` 的衬底语义集合。
5. **`LibrarySample` 已有 `sampleUID` / `legacySampleKey` 字段，但 `LibraryDiffEngine` 仅按 `id` 匹配：**
   - `Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift:174-197`：`sampleUID: String?`, `legacySampleKey: String?`, `origin: String?`；`isNativeOrManual` 与 `conflictsWithIncomingRegistrySample` 均判断 `origin == "native"`。
   - `Sources/SpinLabApp/Library/LibraryDiffEngine.swift:12-49`：`currentSamples = Dictionary(uniqueKeysWithValues: current.samples.map { ($0.id, $0) })`，仅按 `sample.id` 匹配；更新时保留 `existing.sampleUID`、`existing.legacySampleKey`、`existing.origin`（31-39 行）。
   - `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift:48-61, 126-136`：`createDrawer` 与 `updateSample` 在落盘时保留已有 `sampleUID`、`legacySampleKey`、`origin`。
6. **UI 当前无条件将 `sample.id` 展示为 `Sample Key`：**
   - `Sources/SpinLabApp/Features/Library/LibraryDetailView.swift:216`：`MetadataValueRow(label: "Sample Key", value: sample.id, monospaced: true)`
   - `Sources/SpinLabApp/Features/Library/LibrarySearchViews.swift:112`：`MetadataValueRow(label: "Sample Key", value: sample.id, monospaced: true)`
   - `Sources/SpinLabApp/Features/Library/LibraryViewComputationService.swift:48`：`DetailField(label: "Sample Key", value: sample.id, monospaced: true, fullWidth: true)`
   - `Sources/SpinLabApp/Features/Library/WorkflowGallery/SamplePlotsGallerySheet.swift:187`：`Text("Sample Key: \(sampleKey)")`
7. **原子写入、备份与单次索引重建机制已存在：**
   - `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift:289-294`：`writeJSONChecked` 使用 `.write(to: url, options: .atomic)`。
   - `Sources/SpinLabApp/Library/LibraryStore+Backup.swift:4-19`：`syncBackup(from:to:)` 支持库备份。
   - `Sources/SpinLabApp/Library/LibraryStore+RootAndIndex.swift:109-131`：`syncIndexFromFilesystem(rootURL:)` 从磁盘全量重建索引。

---

## 架构设计：四层职责与数据流

### 1. 四层职责划分
- **L1 编号规则层（`SampleIdentityRule`）：**
  - 唯一定义 `smp_` 前缀、随机生成 `makeRandomUID()`、手机提交单确定性换算 `uid(forSubmissionId:index:)`（支持主衬底与 `-2`/`-3` 多衬底）、以及格式校验 `isValidUID(_:)`。
  - `NativeSampleCreationService.makeSampleUID()` / `isValidSampleUID(_:)`、`PhoneSamplePickup.sampleUID(forSubmission:)`、`NewSampleFields.sampleUID(base:index:)` 全部委托给 `SampleIdentityRule`，全仓不再存在第二套 `smp_` 拼接或校验逻辑。
- **L2 分发层（`SampleIDIssuer`）：**
  - 唯一发号入口：
    - `issueForNewSample(preferredUID:)`：若调用方传入合法 UID（如表单打开时生成或手机提交单换算）则复用校验通过的 UID，否则生成随机 `smp_`；
    - `issueForLegacyBackfill(sample:)`：若 `sample.sampleUID` 已是合法 `smp_` 则跳过（返回 `.alreadyIssued`），否则调用 `SampleIdentityRule.makeRandomUID()` 分配新 `smp_`。
- **L3 映射层（`SampleLegacyKeyMapping`）：**
  - 唯一负责 `smp_ <-> legacySampleKey` 对照记录与按旧 key 查找：
    - **记录：** 在 `LibrarySample` 上写入 `sampleUID` 与 `legacySampleKey`（存放在各自 `sample.json` 中）。
    - **查找：** `findRegistryMatch(forIncomingCue:in index: LibraryIndex) -> LibrarySample?`，**仅匹配 `!sample.isNativeOrManual`（即 `origin != "native"`）的样品**，按 `sample.legacySampleKey == cue || sample.id == cue` 查找。
    - **线索计算：** 将 `LibrarySubstrateParser.sampleKey(batchId:substrate:)` 明确降级/重命名为旧线索计算 helper（例如 `legacySampleCue(batchId:substrate:)`，或保留签名但仅用于解析线索与映射查找，**禁止用于生成样品主键或新建 `id`**）。
- **L4 创建层（`NativeSampleCreationService.createSample`）：**
  - 保持内部 500 行校验、批次解析、路径安全、落盘、索引更新与回滚逻辑**完全不变**。
  - 仅扩展 `CreateNativeSampleDraft` 可选默认值：`legacySampleKey: String? = nil`、`origin: String = "native"`、`sourceSheetName: String? = nil`、`sourceRowNumber: Int? = nil`，`createSample` 构造 `LibrarySample` 时透传这些字段。

### 2. 三条上游路径的收口方式
- **桌面手写：** `CreateNativeSampleSheetView` 通过 `SampleIdentityRule` 预生成 UID -> `NativeSampleCreationService.createSample`（`origin = "native"`, `legacySampleKey = nil`）。
- **手机 HTML：** `PhoneSamplePickup` 与 `NewSampleFields` 通过 `SampleIdentityRule.uid(forSubmissionId:index:)` 换算 -> `NativeSampleCreationService.createSample`（`origin = "native"`, `legacySampleKey = nil`）。重复拉取同一 `submissionId` 命中 `createSample` 的 UID 幂等分支，不重复创建。
- **XLSX Registry 同步：**
  1. `LibraryRegistryParser.parse` 解析每行时计算旧线索 `cue = substrateParser.legacySampleCue(batchId: batchId, substrate: substrate)`，将其写入解析结果 `LibrarySample` 的 `legacySampleKey = cue`（解析预览阶段 `sampleUID = nil`，不产生随机号）。
  2. `LibraryDiffEngine.diff(current:updated:)` 使用 `SampleLegacyKeyMapping` 查找匹配：
     - 忽略 `current` 中 `isNativeOrManual == true` 的样品（保证手写/手机同批次同衬底样品永不冲突、永不被覆盖或删除，满足 AC-3）。
     - 若找到非 native 已有样品（无论是老样品还是之前已生成 `smp_` 的 XLSX 样品），将其视为 `existing`，保留 `existing.id`（文件夹名不变）、`existing.sampleUID`、`existing.legacySampleKey`，计算字段变更进入 `changedSamples`（满足 AC-2）。
     - 若未找到，进入 `newSamples`。
  3. `LibrarySyncService.applyBatch` / `applyAll` 对 `diff.newSamples` **不再直接调用 `libraryStore.createDrawer`**，而是适配为 `CreateNativeSampleDraft`（由 `SampleIDIssuer` 发随机 `smp_`，`origin = "registry"`, `legacySampleKey = cue`, `sourceSheetName`, `sourceRowNumber`）并调用 `NativeSampleCreationService.createSample(...)`（满足 AC-1）。
  4. **关于生长记录导入（`RegistryGrowthImportPlanner` / `RegistryGrowthMutationService`）：** 该链路只修改 `.xlsx` 表格并回读校验，不创建 `LibrarySample` 文件夹；其 `expectedSampleKeys` 与 `RegistryGrowthMutationService` 的回读校验直接消费 `legacySampleCue` / `substrateSignature`，不受 `LibrarySample.id` 改为 `smp_` 的影响（同步更新注释/命名即可）。

### 3. 老样品一次性补发（`LegacySampleBackfillService`）
- **预演（`dryRun: true`）：** 调用 `libraryStore.readOnlyCompleteIndex(rootURL:)`（fail-closed）；列出所有 `!SampleIdentityRule.isValidUID(sample.sampleUID ?? "")` 的样品及将记录的 `legacySampleKey = sample.legacySampleKey ?? sample.id`，**不写任何文件**。
- **执行（`dryRun: false`）：**
  1. **读取前校验与备份：** `readOnlyCompleteIndex` 失败则中止；写入前先将当前 `library_index.json` 与所有待补发 `sample.json`（或通过 `LibraryStore` 备份目录）复制到带时间戳的备份目录并校验拷贝成功，**备份失败立即中止，不写任何样品**。
  2. **逐个发号与原子替换：** 对每个未编号样品，由 `SampleIDIssuer` 分配随机 `smp_`，在内存中构造更新后的副本（设置 `sampleUID = issuedUID`、`legacySampleKey = existing.legacySampleKey ?? existing.id`，**保持 `id` 不变，不重命名文件夹**），通过 `libraryStore.writeSampleChecked`（`.atomic`）整份替换 `sample.json`。
     - **失败语义：** 单个样品写入抛出错误时，记录失败原因并继续/中止（不留半份文件），且**绝不**把未落盘成功的 UID 记作已发出。
  3. **单次重建索引：** 全部样品处理完毕后，调用**一次** `libraryStore.syncIndexFromFilesystem(rootURL:)` 并 `saveIndex`。
  4. **全量完备性检查：** 扫描重建后的 `LibraryIndex`，验证所有样品均具备合法 `smp_` `sampleUID`；若仍有缺失，返回明确告警/失败状态，不静默返回成功。
  5. **幂等性：** 已具备合法 `smp_` `sampleUID` 的样品直接跳过，重复运行绝不重发或覆盖已有 `smp_`。

### 4. UI 展示与防绕开检查
- **Library UI：** `LibraryDetailView`、`LibrarySearchViews`、`LibraryViewComputationService`、`SamplePlotsGallerySheet` 不再显示旧 `Sample Key`（`sample.id`）；展示样品永久标识 `sample.sampleUID`（标签为 `Sample UID`，若尚未补发则显示未补发提示或 `persistentIdentity`，不再把旧 key 原样当 `Sample Key` 展示）。
- **防绕开自动检查（AC-8）：** 新增静态/架构守护测试（`SampleCreationAuthorityGuardTests`），扫描 `Sources/SpinLabApp` 源码，断言除 `NativeSampleCreationService`（与 `LibraryRegistryParser` 仅作只读解析 DTO）外，没有任何业务/Sync/Pickup/UI 代码直接调用 `libraryStore.createDrawer` 或构造新建用 `LibrarySample`。

---

## 核心不变量与兼容边界

- **I-1（唯一身份规则）：** 所有 `smp_` 生成、手机提交单换算、格式校验必须且只能经过 `SampleIdentityRule`。
- **I-2（唯一创建权威）：** 任何持久化新样品（桌面/手机/XLSX）必须经 `NativeSampleCreationService.createSample`；`LibrarySyncService` 不得直接 `createDrawer`。
- **I-3（Native 隔离）：** `SampleLegacyKeyMapping` 查找必须忽略 `origin == "native"` 样品；XLSX 同步永不覆盖、更新或删除手写/手机样品。
- **I-4（老样品不动路径）：** 补发只向 `sample.json` 写入 `sampleUID` 与 `legacySampleKey`；`sample.id`、文件夹路径、测量与出图记录保持不变。
- **I-5（Fail-closed 与原子性）：** 索引不可读或备份失败时，创建与补发均在任何写入前中止；单样品补发采用 `.atomic` 替换，失败不产生半份文件或内存幽灵号。

---

## 验证与证据矩阵

| 验收声明 | 可能的失效方式 | 必须产出的验证证据（测试/检查） |
|---|---|---|
| AC-1 统一创建入口 | XLSX 仍用旧 key 作 `id`；手机端仍自行拼接 `smp_` | 单测验证桌面/手机/XLSX 三路创建均产合法 `smp_` 且经 `NativeSampleCreationService`；手机重复拉取同一 `submissionId` 幂等返回同一样品 |
| AC-2 XLSX 重复同步 | 每次同步新建重复 `smp_` 样品；或更新后 `sampleUID` 丢失 | 同份 XLSX 连续两次 `applyAll` / `applyBatch`：第二次 `newSamples` 为 0，原有 `smp_` 样品被更新且 `sampleUID` 与 `legacySampleKey` 保持不变 |
| AC-3 互不干扰 | XLSX 匹配到同批次同衬底手写样品并覆盖或删除它 | 先手写/手机创建 `BatchA + STO(001)`，再同步含 `BatchA + STO(001)` 的 XLSX：库中共存 2 个样品（1 `native` + 1 `registry`），各自 `smp_` 独立 |
| AC-4 老样品补发 | 预演写盘；重复运行重发新号；文件夹或测量丢失；漏检 | `dryRun: true` 后磁盘零修改；执行补发后老样品获 `smp_` 且 `legacySampleKey` 等于原旧 key，测量/目录名不变；再次运行 `issued == 0`；模拟缺号时后置检查报错 |
| AC-5 补发安全 | 无备份直接改库；单文件写入失败留半份或发幽灵号；多次重建索引 | 注入备份失败错误 -> 中止且零修改；注入单样品写入失败 -> 该样品文件保持原样、未发出 UID；统计执行期间索引重建调用次数 == 1 |
| AC-6 旧 key 下线与 UI | 源码仍有旧 key 生成主键；UI 仍展示旧 `Sample Key` | 断言新建样品不再以旧 key 作 `id`；UI 计算/视图单测断言展示 `sampleUID` 而非旧 `Sample Key` |
| AC-7 老样品兼容 | 老样品无法打开或现有测试回归 | 既有 Library 打开/测量/出图/生长记录导入/全量 `swift test` 通过 |
| AC-8 防绕开 | 未来有人在 Sync/UI 中直接调用 `createDrawer` | 源码静态扫描测试验证无任何非授权 `createDrawer` 或直接造样调用点 |

---

## 实施顺序与授权边界

1. **最小实现顺序（Code 阶段执行）：**
   - Step 1：抽出 L1 `SampleIdentityRule`、L2 `SampleIDIssuer`、L3 `SampleLegacyKeyMapping`；重构 `NativeSampleCreationService`、`PhoneSamplePickup`、`NewSampleFields` 委托之。
   - Step 2：扩展 `CreateNativeSampleDraft` 默认字段（`createSample` 内部不变），改造 `LibraryRegistryParser`（输出线索）、`LibraryDiffEngine`（按 mapping 匹配且隔离 native）与 `LibrarySyncService`（新建走 `createSample`）。
   - Step 3：实现 `LegacySampleBackfillService`（预演/备份/原子写/单次重建索引/全量校验）及 UI 触发入口。
   - Step 4：更新 Library UI 展示 `smp_`、完善生长记录导入命名/校验、补齐 AC-1~AC-8 测试与防绕开检查。
2. **人工关口与授权草案：**
   - 当前仅授权 **Design**；进入 **Code** 前需用户明确授权：**修改代码、运行本地测试、commit 与 push 到 `fix/unify-sample-creation`**（PR 合并仍需单独授权）。
   - `SKELETON.md` 放宽已在 PR #220 提交 `9671a198` 中由用户确认并落盘。

---

## Work Contract（Code 阶段冻结执行合同）

- **Contract Authority:** 本节为 Code 阶段唯一直接执行合同，继承 `Plan.md` v1.1 与 `policy_sha: 7f01e5a3ff53ed13ba763d684a098c0989425ec4`。
- **可观察结果：**
  1. 全局仅 `SampleIdentityRule` 定义 `smp_` 格式、生成、手机提交单换算与校验；`SampleIDIssuer` 统一发号；`SampleLegacyKeyMapping` 负责 `smp_ <-> legacySampleKey` 记录与查找。
  2. 桌面手写、手机 HTML、XLSX 三路新建样品全部经 `NativeSampleCreationService.createSample` 创建并获得 `smp_`；`createSample` 内部逻辑、路径安全与回滚行为保持不变。
  3. XLSX 重复同步通过 `(batchId, substrate)` 线索查 `SampleLegacyKeyMapping` 找回并更新原样品，不重复新建；手写/手机同批次同衬底样品与 XLSX 样品共存，互不覆盖或删除。
  4. `LegacySampleBackfillService` 支持预演（零写入）、写前备份（失败中止）、逐样品 `.atomic` 替换（失败不发号不留残件）、全量写完后单次重建索引、幂等跳过已编号样品、以及全库 `smp_` 完备性校验；不迁移老样品目录、测量或出图记录。
  5. 旧格式 `Sample Key` 生成逻辑下线（仅保留为 Excel 行线索与映射查找）；Library UI（详情、搜索预览、图库页）不再展示旧 `Sample Key`，统一展示 `smp_`。
  6. 自动检查测试在任一上游绕开唯一创建入口直接调用 `createDrawer` 或造样时失败。
- **必需边界与禁止项：**
  - 不迁移老样品文件夹与历史测量/出图；不修改用户原 `.xlsx`；不拆分 `NativeSampleCreationService.createSample` 内部；不改测量/拟合/出图算法；不引入多用户并发锁。
- **验证与证据要求：**
  - 运行受影响测试集及全量 `swift test`（macOS），覆盖 AC-1 至 AC-8 的正向、负向、老数据兼容与故障恢复（备份失败、单样品写失败、预演零写入、重复运行幂等、防绕开守护）用例并全部通过。
- **停止条件：**
  - Code 阶段本地 `reviewloop_review` 返回 `PASS` 后停止，汇报结果并等待用户对 commit/push/PR 验收的下一步指令；遇 `HUMAN_REQUIRED` 或超出授权范围的操作立即停止。
