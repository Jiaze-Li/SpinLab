# 任务 5 设计：AFM 标准数据入库、SQLite 资产存储与引用安全

对应需求合同：[brief-5-afm-standard-assets.md](brief-5-afm-standard-assets.md)；共同语义参照：[SKELETON.md](SKELETON.md) K1–K13。本文为 Design Review 交付，不含 Swift 实现代码或真实 Library 迁移；静态核查基线为 `main` `56fa6d21`。

---

## 一、AFM 支持范围、忠实标准化与落盘编码

### 1.1 真实代码支持边界（复用现有解析链路）

直接复用 `Sources/SpinLabApp/AFM/IBW/IBWReader.swift`、`AFMInputAdapter.swift`、`AFMLengthUnit.swift`、`AFMNoteFields.swift` 与 `CanonicalAFMDataset.swift`，不另起炉灶：

| 维度 | 首批支持范围（以 `IBWReader` / `AFMInputAdapter` 实况为准） | 超出范围/损坏处理 |
|---|---|---|
| 格式与字节序 | Igor Binary Wave **v5**、**little-endian（Intel）**、header 384B 校验和为 0 | 拒绝（`unsupportedVersion` / `bigEndianUnsupported` / `checksumMismatch` / `truncatedFile`） |
| 数值类型 | **Float32（`NT_FP32 = 2`）** | 拒绝（`unsupportedNumericType`） |
| 维度与通道 | 2D/3D（`nDim[0] > 0`, `nDim[1] > 0`, `nDim[2] >= 0`, `nDim[3] == 0`），`dimLabels[2]` 缺省或为 `channelCount + 1` | 拒绝（`malformedDimensions` / `channelLabelCountMismatch`） |
| X/Y 坐标单位 | `dimUnits[0]/[1]` 空值按仪器约定视为 `"m"`，经 `AFMLengthUnit` 换算为 **`µm`** | 非长度单位明确拒绝，不猜单位 |
| 通道数据单位 | `dataUnit` 经 `AFMLengthUnit` 识别为长度（`m/cm/mm/µm/um/nm/Å/angstrom`）时换算为 **`nm`**；空串或非长度单位保持原值与原单位 | **不冒充 `nm` 或 `Height`**，保留 `sourceUnit` 与 `canonicalUnit` |
| 通道身份 | `sourceIndex` + `sourceLabel`（`id = "ch\(c)-\(sourceLabel)"`），保留 `semanticTypeRaw` 与 `AFMChannelProvenance` | `AFMChannelResolver` 默认选中仅用于展示，不写入科研身份 |
| 缺失/非有限值 | 保留原始 `Float32` 转为 `Double` 后的 `NaN` / `+Inf` / `-Inf` | **不填零、不裁剪**；通过下方二进制编码无损回读 |

### 1.2 落盘编码与精度合同

现有 `CanonicalAFMDataset` 虽已标 `Codable`，但 `values: [[Double]]` 含 `NaN`/`±Inf` 时标准 `JSONEncoder` 会直接抛错，且大矩阵存 JSON 体积膨胀明显。本任务采用**元数据 JSON + 原始 IEEE-754 二进制矩阵**的双文件编码：

- **Source 目录**：`storage/<src_ID>/`
  - `payload.bin`：原始 `.ibw` 的逐字节副本（不改写，不使用原始文件名作为磁盘路径，彻底规避路径穿越与非法字符）。
  - `manifest.json`：`format = "ibw_v5"`、`originalFileName`、`originalSourcePath`（仅历史 provenance）、`byteSize`、`sha256`、`ingestedAt`。
- **Dataset 目录**：`storage/<dst_ID>/rev_<N>/`（`<N>` 为单调递增正整数修订号，见第四节）
  - `manifest.json`：`schemaVersion = 1`、`format = "afm_canonical_v1"`、`datasetID`、`sourceID`、`revision`、`title`、`xUnit = "µm"`、`yUnit = "µm"`、`nX`、`nY`、`xCoordinates`、`yCoordinates`（非有限坐标值在入库前校验拒绝）、`sourceMetadata`（`waveName`、`sourceWidth`、`sourceHeight`、`rawNote`、`historicalSourceRef`）、以及各通道元信息（`id`、`sourceIndex`、`sourceLabel`、`semanticTypeRaw`、`displayLabel`、`canonicalUnit`、`sourceUnit`、`provenance`、`byteOffset`、`byteLength`、`dtype = "float64_le"`、`nonFiniteCount`）。
  - `matrices.bin`：按通道顺序、`values[y][x]` 行主序紧密排列的 IEEE-754 little-endian `Float64` 原始位（`bitPattern.littleEndian`）。
- **回读精度与校验**：
  - 编码回读 **bit-exact**（`Double.bitPattern` 逐位相等，`NaN`/`±Inf` 完整保留），零额外精度损失。
  - 与 `IBWReader` 源数据对照容差：`0`（`Double(rawFloat32) * scale` 与回读值逐位相等，`isNaN` 对 `isNaN`）。
  - `manifest.json` 记录 `matrices.bin` 的 `sha256` 与精确字节数（`channelCount * nY * nX * 8`），读取时校验长度与哈希，不匹配则 fail-closed 报损坏。
- **独立可读与来源诊断分离**：
  - 读取标准数据时只访问 `storage/<dst_ID>/rev_<current_revision>/`，**不读取** `storage/<src_ID>/` 也不依赖任何历史绝对路径。
  - `loadAFMDataset(datasetID:)` 同时返回独立的 `sourceAvailability`（`.available` / `.missing` / `.corrupt(reason)`），即使隔离测试中临时移走或损坏 Source，标准数值仍可正常读出，同时清晰报告来源不可用。
- **损坏/未支持文件边界**：
  - Inbox 正常导入损坏或未支持的 `.ibw` 时，标准化阶段即失败并报告 `IBWReadError`，**不生成 `ready` 的 Dataset**。
  - 若未来需要“仅保留原始 Source、稍后重试标准化”，数据模型支持 `src_` 为 `ready` 而 `dst_` 尚未创建或为 `failed`（附错误原因），重试标准化复用同一 `src_ID` 而不产生半就绪 Dataset。

---

## 二、真实 Inbox 入口、`.ibw` 识别与多 Sample 归属

### 2.1 代码核查发现的两处现状落差

1. **`.ibw` 扩展名与 `workflow=afm` 识别**：
   - 本机规则本 `import_filters.json` 已含 `"ibw"`，但仓库默认 `Sources/SpinLabApp/config/import_filters.json`、`library_import_rules.json` 与 `FilenameRuleSet.fallback()` 仅含 `csv/txt/dat/lvm`。
   - `Sources/SpinLabApp/Import/Parse/FilenameRuleParser.swift`（L37–L49）在分词前调用 `fileURL.deletingPathExtension()` 剥掉了扩展名，导致规则本 `workflow.json` 中已配置的 `{ "type": "equals", "value": "ibw" }` **对不含 `AFM` 字样的文件名（如 `LSMO13_CONTACT_0000.ibw`）完全不生效**。
2. **V2 Inbox 写入与多 Sample 确认**：
   - `InboxArchiveApplyService.swift`（L55）入口直接调用 `LibraryLayoutRouter.requireV1ArtifactWriteAllowed`，当前对 V2 全量拒写。
   - `PendingImportConfirmationDraft` 目前仅支持单个 `sampleName`，尚未提供 V2 AFM 的多 Sample 确认目标与 `sampleUID`（`smp_`）校验。

### 2.2 最小改造设计

- **扩展名识别修复**：
  - 在 `FilenameRuleParser.parse(from:)` 中提取小写 `pathExtension`（非空时），在 `measurementNameMatch` 未从 `fileScopeTokens` 和 `folderContextTokens` 命中时，允许用 `[pathExtension]` 作为回退 token 匹配 `measurementNameRules`（并记录 `hintSources["workflowID"]`）。这样既有 `workflow.json` 里的 `equals: "ibw"` 立即生效，且不破坏现有文件名/目录优先语义和规则 Schema。
  - 仓库默认 `config/import_filters.json` 补入 `"ibw"`（并同步校验规则漂移守卫）。
- **V2 Inbox 路由切换**：
  - `InboxArchiveApplyService.apply` 先检查 `LibraryLayoutRouter.resolve(rootURL:)`：
    - `.v1` / `.uninitialized`：保持现有 V1 逻辑零改动。
    - `.invalid(err)`：fail-closed 抛出。
    - `.v2`：仅当文件为 `.ibw` 且解析/确认的工作流为 `afm` 时，分流至 `LibraryAssetService.ingestAFM(...)`；**其余所有非 AFM 工作流继续抛出 `LibraryLayoutError.v2UnsupportedOperation`**，不扩大迁移范围。
- **多 Sample 归属确认与身份校验**：
  - V2 AFM 确认面板允许用户显式勾选 1 个或多个目标 Sample（列表来自非废纸篓 Sample，按 Batch → Sample 展示），不凭文件名猜归属（K12）；空选禁止提交。
  - 每个目标 Sample 在入库前必须校验具有合法非空 `sampleUID`（`smp_` 前缀）且磁盘 `records/samples/<sampleUID>/sample.json` 存在且未在废纸篓；缺失则 fail-closed 拒绝。
- **幂等与重复内容策略（K1–K4）**：
  - 每次用户点击提交生成一个 `operationID`（UUID），重入/卡顿重试命中 `asset_operations(operation_id)` 直接返回已提交结果，不重复创建资产（K4）。
  - 若是**新的明确导入**且 `sha256` 命中库中已有 `ready` 的 `src_`：在确认阶段明确提示已有相同字节的 Source（展示其 `src_ID` 与原文件名），由用户选择**“复用已有资产并关联所选 Sample”**或**“作为新资产导入”**，程序不自动合并（K2/K3）。

---

## 三、SQLite Schema、接入方式与公共读写入口

### 3.1 零依赖 SQLite 接入与初始化矩阵

- **接入方式**：使用 macOS 14+ 系统自带 `import SQLite3`（`Package.swift` 不新增外部依赖、不引入 ORM），编写轻量 `LibraryAssetDatabase`：
  - 统一启用 `PRAGMA journal_mode = WAL;`、`PRAGMA synchronous = FULL;`、`PRAGMA foreign_keys = ON;`、`PRAGMA busy_timeout = 5000;`。
  - 所有写操作前强制经过 `LibraryWriteLease.shared.ensureWritable(dbURL)`。
- **开启与 K13 fail-closed 矩阵**：

| 磁盘状态（已确认为合法 V2 库） | 判定与行为 |
|---|---|
| `_spinlab/library.sqlite` 不存在，且 `storage/` 不存在（或为空） | 视为“尚未启用资产库”：只读查询返回空列表；首次资产写入时创建数据库并初始化 `schema_version = 1` |
| `_spinlab/library.sqlite` 不存在，但 `storage/` 非空 | **异常/关系丢失（K13）**：fail-closed 报错停止，**禁止静默重建空库** |
| `_spinlab/library.sqlite` 存在但损坏、缺核心表或 `PRAGMA quick_check` 失败 | **损坏（K13）**：fail-closed 报错停止 |
| `schema_meta.schema_version > 1` 或不可解析 | **未知版本（K13）**：fail-closed 报错停止 |

### 3.2 最小 SQLite Schema（v1）

SQLite **仅管理资产登记、关系、位置、校验与操作恢复状态**；不复制 `ResultDefinition`、`SampleResultValue`、`batch.json` 或 `sample.json` 科研字段。

```sql
CREATE TABLE schema_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
); -- schema_version = '1', layout_version = '2'

CREATE TABLE assets (
    asset_id          TEXT PRIMARY KEY,          -- src_<uuid> / dst_<uuid> / plt_<uuid> / snp_<uuid>
    kind              TEXT NOT NULL,             -- 'source' | 'dataset' | 'plot' | 'snapshot'
    format            TEXT NOT NULL,             -- 'ibw_v5' | 'afm_canonical_v1' | ...
    status            TEXT NOT NULL,             -- 'staging' | 'ready' | 'deleting' | 'failed'
    storage_rel_path  TEXT NOT NULL,             -- e.g. 'storage/src_xxx' or 'storage/dst_xxx/rev_1'
    current_revision  INTEGER NOT NULL DEFAULT 1,-- 单调递增内容标记（独立于 sha256，防 ABA）
    sha256            TEXT,
    byte_size         INTEGER,
    original_filename TEXT,
    live_state        TEXT,                      -- 仅对 Live 产物：'current' | 'stale' | NULL
    error_message     TEXT,
    created_at        TEXT NOT NULL,             -- ISO-8601 UTC
    updated_at        TEXT NOT NULL
);
CREATE INDEX idx_assets_sha256 ON assets(sha256) WHERE sha256 IS NOT NULL;
CREATE INDEX idx_assets_status ON assets(status);

CREATE TABLE sample_asset_links (
    sample_uid TEXT NOT NULL,
    asset_id   TEXT NOT NULL REFERENCES assets(asset_id),
    role       TEXT NOT NULL DEFAULT 'primary',
    linked_at  TEXT NOT NULL,
    PRIMARY KEY (sample_uid, asset_id)
);
CREATE INDEX idx_links_asset ON sample_asset_links(asset_id);

CREATE TABLE asset_dependencies (
    consumer_asset_id TEXT NOT NULL REFERENCES assets(asset_id),
    upstream_asset_id TEXT NOT NULL REFERENCES assets(asset_id),
    dependency_kind   TEXT NOT NULL,             -- 'dataset_source' | 'live_input' | 'snapshot_input'
    signal_locator    TEXT,                      -- 可选：源内通道/信号定位
    PRIMARY KEY (consumer_asset_id, upstream_asset_id, dependency_kind)
);
CREATE INDEX idx_deps_upstream ON asset_dependencies(upstream_asset_id);

CREATE TABLE asset_operations (
    operation_id TEXT PRIMARY KEY,
    op_type      TEXT NOT NULL,                  -- 'ingest' | 'revise' | 'delete_sample'
    state        TEXT NOT NULL,                  -- 'pending' | 'committed' | 'aborted'
    payload_json TEXT NOT NULL,                  -- 待操作/已提交摘要（含幂等返回结果）
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);
```

- **编号规则（K1/K2）**：ID 为 `<prefix>_` + 随机 32 位小写 hex UUID（如 `src_...`、`dst_...`），不从文件名、路径、内容哈希或 Sample UID 推导。
- **公共读写入口**：`Sources/SpinLabApp/Library/Assets/LibraryAssetService.swift` 作为唯一 V2 资产读写权威，封装：
  - `ingestAFM(sourceFileURL:targetSampleUIDs:operationID:reuseSourceID:rootURL:)`
  - `loadAFMDataset(datasetID:rootURL:)`（返回 `CanonicalAFMDataset` + 独立 `SourceAvailability`）
  - `listAssets(forSampleUID:rootURL:)`、`linkAsset(assetID:toSampleUID:rootURL:)`、`unlinkAsset(assetID:fromSampleUID:rootURL:)`
  - `reviseAFMDataset(datasetID:expectedRevision:newDataset:operationID:rootURL:)`
  - `planPermanentSampleDeletion(sampleUID:rootURL:)` / `commitPermanentSampleDeletion(plan:sample:operationID:rootURL:)`
  - `recoverPendingOperations(rootURL:)`（打开可写 V2 库时调用）

---

## 四、跨文件与 SQLite 的提交、更正、删除、恢复与备份

### 4.1 导入提交与崩溃恢复（Write-Ahead Staging）

1. **校验**：确认写租约、V2 布局、数据库健康、全部目标 `sampleUID` 有效且未在废纸篓；解析并生成 `CanonicalAFMDataset`。
2. **准备阶段（SQLite 事务 1）**：在 `BEGIN IMMEDIATE` 中检查 `operation_id`：
   - 若已 `committed`，直接反序列化并返回原结果（幂等）。
   - 否则插入 `asset_operations(op_id, 'ingest', 'pending', ...)` 与 `assets(src_ID, status='staging')`、`assets(dst_ID, status='staging')`。
3. **写文件**：复用 `AtomicFileWriter`（写临时文件 → `fsync` → 原子重命名 → 目录 `fsync`）写入 `storage/<src_ID>/{payload.bin, manifest.json}` 与 `storage/<dst_ID>/rev_1/{manifest.json, matrices.bin}`，并回读校验字节数与 SHA-256。
4. **正式提交点（SQLite 事务 2）**：`BEGIN IMMEDIATE` 内将 `src_ID`/`dst_ID` 状态置为 `ready`，写入 `asset_dependencies(dst_ID → src_ID, 'dataset_source')` 与全部 `sample_asset_links`，更新 `asset_operations.state = 'committed'`（写入结果 JSON）并 `COMMIT`。
5. **中断恢复**：
   - 步骤 3 前后或步骤 4 提交前崩溃：重开库执行 `recoverPendingOperations()`，发现 `ingest` 处于 `pending` → 删除关联 `staging` 目录与 `staging` 行，将操作标为 `aborted`。外部消费者永远看不到 `staging` 资产，不会出现空壳或半就绪记录。

### 4.2 同 Dataset 更正与防 ABA（K10/K11）

- **稳定 ID 规则**：对同一 `src_` 的同一信号做忠实解析或有依据的单位/角色解释更正 → **保留同一 `dst_ID`**；更换独立信号 → **新建 `dst_ID`**。已有 `src_` 字节永不改写。
- **单调内容标记**：`assets.current_revision` 每次提交严格 `+1`（`1 → 2 → 3`），**独立于内容哈希**。即使内容发生 `A → B → A`，版本号仍不同，无法绕过校验。
- **提交流程**：
  1. 更正任务启动时记录 `expectedRevision = asset.current_revision`。
  2. 写入新目录 `storage/<dst_ID>/rev_<expectedRevision + 1>/`（使用 `AtomicFileWriter`）。
  3. 在 `BEGIN IMMEDIATE` 正式提交点校验：
     - 若 `operation_id` 已 `committed` → 幂等返回；
     - 若当前 `current_revision != expectedRevision` → **拒绝过期提交（`staleRevision`）**，清理未发布的 `rev_<expectedRevision + 1>/`；
     - 校验通过 → 更新 `current_revision = current_revision + 1`、`storage_rel_path`、`sha256`、`byte_size`、`updated_at`；同时将 `asset_dependencies` 中以该 `dst_ID` 为上游且 `dependency_kind = 'live_input'` 的下游资产标为 `live_state = 'stale'`（`snapshot_input` 及 `sample.json.results` 不动）→ 标记 `asset_operations = 'committed'` → `COMMIT`。
  4. 提交成功后清理旧目录 `rev_<expectedRevision>/`（即使此处崩溃，当前版本已指向新目录，旧目录由后续恢复安全清理）。

### 4.3 彻底删除、引用闭包与中断恢复

- **软删除与恢复**：`moveSampleToTrash` / `restoreSampleFromTrash` 仅改写 `sample.json.deletedAt`，**不解除 `sample_asset_links`，不删任何资产文件**；废纸篓中的样品视为有效引用方。
- **取消链接（Unlink）**：仅删除 `sample_asset_links` 对应行，不删除资产或文件（K6）。
- **永久删除引用闭包计算（`planPermanentSampleDeletion`）**：
  1. 校验目标 Sample 已在废纸篓且 `library.sqlite` 可读；若不可读或引用状态不确定 → **fail-closed 拒绝**。
  2. 从该 Sample 关联的 `asset_id` 集合出发，先找出仍被以下任一条件保护的**保留集**：
     - 存在其他 Sample（含仍在废纸篓中的其他 Sample）的 `sample_asset_links`；
     - 属于仍需保留的 `snapshot` 资产；
     - 在 `asset_dependencies` 中作为任一保留资产的上游（迭代求闭包，确保保留的 Dataset/Plot/Snapshot 所依赖的 Source/Dataset 均保留）。
  3. 仅在该次删除涉及的候选集中、且不在保留集内的已登记 `ready` 资产，才进入 `assetsToDelete`；**不扫描、不清理未登记文件或无关孤儿**。
  4. 统计 `assetsToDelete` 在 `storage/<id>/` 下实际存在的已登记文件数 `N`，以及被保留的相关资产文件数 `M`；同时找出多样品 Live Plot（关联本 Sample 且还关联其他 Sample，将保留并标 `live_state = 'stale'`）。
  5. 计算 `planFingerprint`（对相关 links/deps 快照哈希），供确认弹窗展示并在提交前复核。
- **永久删除提交与崩溃恢复**：
  1. `BEGIN IMMEDIATE` 内重新计算并比对 `planFingerprint`：若期间链接或依赖已变化，拒绝提交并提示重新确认。
  2. 同一事务内：写入 `asset_operations(op_id, 'delete_sample', 'pending', planJSON)` → 删除该 Sample 的 `sample_asset_links` → 将多样品 Live Plot 置为 `live_state = 'stale'` → 将 `assetsToDelete` 置为 `status = 'deleting'` → `COMMIT`。
  3. 磁盘清理：严格路径包含校验（`isStrictChildPath`）后删除 `records/samples/<uid>/` 及 `assetsToDelete` 对应的 `storage/<id>/` 目录。
  4. 收尾事务：删除 `status = 'deleting'` 的资产行（含相关依赖行），将 `asset_operations.state = 'committed'`，重建 `library_index.json`。
  5. **中断恢复**：若在步骤 2 提交后、步骤 4 完成前崩溃，重开库时 `recoverPendingOperations()` 发现 `delete_sample` 为 `pending` → 幂等续做步骤 3–4；若遇文件权限错误无法删除，明确报错停住并保留 `pending` 供重试，不静默忽略。

### 4.4 空样品检查与一致备份

- **`LibrarySampleEmptyCheck.swift` 修复**：
  - 当前 L49 硬编码了 V1 路径 `sampleDirectoryURL(...)`，在 V2 下会误判不可读。改为按 `resolveLayout` 使用 `drawerRootURL(for:rootURL:)`；V2 下不再扫描旧 `samples/<key>/` 目录，而是查询 `library.sqlite` 中该 `sampleUID` 是否存在 `sample_asset_links`（数据库损坏/异常时返回 `.unreadable`，fail-closed）。
- **`LibraryStore+Backup.swift` 一致备份**：
  - 现有 `mergeBackupContents` 逐文件覆盖拷贝，既不清理已删文件、也不支持 WAL 模式 SQLite，在 V2 下会产生损坏或不一致备份。
  - **V2 策略**：在 `syncBackup` 中检测 `layout.isV2` 时走专用 V2 一致快照备份：
    1. 创建备份目标旁的临时 staging 目录；
    2. 拷贝 `records/`、`storage/` 及 `_spinlab/` 下非 SQLite 文件（`layout_version.json`、`result_definitions.json` 等）；
    3. 若存在 `_spinlab/library.sqlite`，通过 `sqlite3_backup_init/step/finish` 导出独立一致的单文件快照到 staging 目录（不直接拷贝 `-wal`/`-shm`）；
    4. 校验导出库的 `PRAGMA quick_check` 与关键布局文件完整后，原子替换目标备份目录；任一步失败则清理 staging 并返回失败，**绝不报告伪成功，也绝不把 V1 与 V2 目录混写在一起**。

---

## 五、测试精度、验收路径与实施拆分

### 5.1 故障注入点与测试样例

- **测试样例**：
  - CI 受控样例（`IBWFixtureBuilder`）：非方形矩阵（如 5×3）、多通道（Height + Deflection + Phase）、正负值、X/Y 不同长度单位（`m`/`µm`）、非长度数据单位（`V`/空串）、含 `NaN`/`±Inf` 的通道矩阵、损坏 checksum/截断/大端/非 Float32 负例。
  - 本机隔离验收样例：复制一份真实 `.ibw` 到临时目录，不依赖或修改真实 Library。
- **故障注入点**（在 `LibraryAssetService` 通过可注入 hook 在测试中触发）：
  1. 导入写完 `storage/<src_ID>` 后、写 `dst_` 前中断；
  2. 导入写完全部文件后、SQLite 正式提交前中断；
  3. 更正写完 `rev_<N+1>` 后、SQLite 提交前中断；以及并发/迟到 A、重复提交、A→B→A 校验；
  4. 彻底删除 SQLite 标记 `deleting` 提交后、删 `sample.json` 前中断；以及删部分 `storage/` 后中断。

### 5.2 实施拆分（2 个 PR，全部通过后才勾选任务 5）

| 阶段 | 范围与交付 | 覆盖验收 |
|---|---|---|
| **PR-5A：资产存储内核与安全底线** | `LibraryAssetDatabase`（系统 `SQLite3` + schema v1 + K13 校验）、`AFMDatasetCodec`（`manifest.json` + `matrices.bin` 无损编解码）、`LibraryAssetService`（导入/读回/链接/取消链接/更正防 ABA/引用闭包删除/崩溃恢复）、修复 V2 `LibrarySampleEmptyCheck`、V2 一致备份（`sqlite3_backup`）、最小多样品 Live Plot/Snapshot 关系测试夹具及全套故障注入单测。 | AC2、AC3、AC4、AC5、AC6、AC7、AC8、AC9（后端与 V1 回归） |
| **PR-5B：Inbox 入口与 GUI 闭环** | `FilenameRuleParser` 支持 `.ibw` 扩展名回退匹配 + 默认 `import_filters.json` 补齐 `"ibw"`、`InboxArchiveApplyService` 开放 V2 AFM 分支（保持非 AFM 拒写）、V2 AFM Inbox 多 Sample 确认 UI、`LibraryDetailView` 展示 Sample 下 Source/Dataset/通道列表与共享/Unlink 入口、`LibraryTrashView` 永久删除弹窗接入真实文件计数（删 N / 留 M）与提交前复核、隔离测试库 GUI 现场验收。 | AC1、AC9（端到端入口）、AC10 |

- **边界声明**：PR-5A 合并时 V2 AFM Inbox 入口尚未开放，不提前勾选 `docs/V5_ROADMAP.md` 中的任务 5；仅在 PR-5A 与 PR-5B 全部验收（含隔离库 AC10）通过后勾选任务 5。本设计不涉及任务 6（Workbench 处理与出图改造）、任务 7（自动化）或任务 11（真实 V1 库迁移）。
