# 任务 7 设计 — AFM 自动出图

状态：Design Draft，待独立设计审查与用户确认；**不授权实施**。基线 main `4d5fd129`+（任务 6 #241 已合并）。合同来源：[brief-7](brief-7-afm-automation.md)、[SKELETON](SKELETON.md) K4–K10、K12–K13、[任务 6 设计](design-6-afm-workbench.md)。本文只补代码证据、最小实现边界与恢复合同；产品取舍保持“待用户确认”，不当作已批准。

## 1. 已核对的代码事实（HEAD 静态阅读，未运行）

| # | 事实 | 位置 |
|---|---|---|
| F1 | V2 入库唯一入口：`InboxArchiveApplyService.applyV2` → `LibraryAssetService.ingestAsset`；`apply` 返回的 `InboxArchiveApplyResult` 只有 copied/skipped 计数，不含 datasetID。 | `App/InboxArchiveApplyService.swift:470-540`, `:3` |
| F2 | `AssetIngestResult{sourceID,datasetIDs,sampleUID,datasetRevision,reusedSource}`。`ingestAsset` 对**已提交的同 operationID 重放直接返回原结果**（`reusedSource` 取原值），所以“返回值”**无法区分首次提交与重放**；`reusedSource` 仅表示按内容哈希复用 Source。 | `Library/Assets/LibraryAssetService.swift:257-321`, `Models:121` |
| F3 | 调用链：`ApplyCoordinator.apply` 逐个 pending 调 `applyService.apply`，成功/跳过/失败计入 appliedIDs 等；这是唯一能拿到“本次真正新入库”的汇合点之一，但目前不向上传 datasetIDs。 | `App/ApplyCoordinator.swift:90-125` |
| F4 | `loadDatasetForAnalysis` 在 `commitLock` 内一次返回 datasetID/revision/sourceID/活跃 Sample/是否回收/channelIDs/Dataset/Source 可用性；归属 Dataset→Source→Sample。 | `LibraryAssetService+Analysis.swift:38-72` |
| F5 | `AFMPlotComputation.run(dataset:configuration:display:)` 为纯函数、无 UI 状态；`process` 对缺失通道抛 `channelNotFound`，**不替换**；`resolveChannelID`/默认解析器才会回退，自动化不使用回退。 | `AFM/AFMPlotComputation.swift:66-105` |
| F6 | 人工保存 `AFMWorkspaceStore.saveFormalPlot` 构造 `PlotInputRef(datasetID,channelID,revision)`，经 `AFMPlotCodec.encode(... savedAt: Date() ...)` 得 `content`，再调 `publishPlot(content:inputs:operationID:capturedRootURL:rootURL:)`；operationID 为 `plot-save-<UUID>`，仅同指纹重试复用。 | `Features/Workbench/AFMWorkspaceStore+FormalPlot.swift` |
| F7 | `publishPlot` 在 `commitLock` 内：恢复 pending → 计算 `requestHash`（含 inputs、**文件内容摘要**、root）→ 若同 operationID 已 committed，则 hash 一致返回原结果，**不一致抛 `operationRequestMismatch`** → 事务 1 写 staging 行与 pending 记录 → 写文件校验 → 事务 2 重新校验 `requirePlotWriteContext`/`validatePlotInputs` 后置 ready 并写依赖。 | `LibraryAssetService+Plot.swift:69-160, 544-556` |
| F8 | `asset_operations` 行在 committed 后保留；仅 `aborted` 行会在同 ID 重试时被删除。Plot 被删除不删除其 operation 行（此处未见 committed 行的删除；设计要求用测试证明）。 | `LibraryAssetService*.swift` 中各 `DELETE FROM asset_operations`（均限 `state='aborted'`） |
| F9 | `recoverPending` 在每次写操作开始与 `recoverPendingOperations` 时中止未完成的 `plot_publish`，Plot staging 行与文件被清理；已 committed 的不动。 | `LibraryAssetService+Deletion.swift:507-545` |

## 2. 核心设计问题与结论

### 2.1 幂等不能靠“固定 operationID + 重新渲染”（brief 指出的风险，已确认）

F6/F7 表明：内容含 `savedAt` 等，重新渲染后文件摘要不同，同 operationID 再 publish 会抛 `operationRequestMismatch`，既不会重复出图也不会成功，反而把一次成功的发布伪装成“冲突”。

**结论（需求依据：AC4）：**

1. **稳定意图身份只由 Dataset 决定**：`intentKey = "auto-afm|" + datasetID + "|rev" + datasetRevision`（datasetID 为入库时生成的 UUID，天然唯一）。**预设代际不进入身份**，它只用作“能否发布”的取消条件（2.3）。因此预设 Apply/开关变化之后的重投、补跑命中同一回执，不会产生第二张，也不会复活已删除的图。operationID 固定格式 `"auto-afm-" + 64 位小写 hex(SHA-256(intentKey))`（<100 字节，无 `/`、`..`，满足 `validateOperationID`）。
2. **回执查询**：新增只读 `plotPublishReceipt(operationID:rootURL:) -> PlotPublishReceipt?`，在 `commitLock` 内读取 `asset_operations`；仅当 `op_type == "plot_publish"` 且 `state == "committed"` 且含 `result` 时返回回执，`pending`/`aborted`/类型不符一律视为“无回执”（交由 `publishPlot` 的 `recoverPending` 处理）。有回执 → 不渲染、不 publish，终态记为 `alreadyPublished`（**不是** `published(plotID)`：该图可能已被人工删除，不得显示悬空 ID，也不复活）。
   - 回执查询在锁外是“提示优化”，**权威判定在 `publishPlot` 内**（见下 2a），以免两次并发的同意图运行都未命中回执、各自渲染出不同 `savedAt` 后第二个撞上 `operationRequestMismatch`。
2a. **在 `publishPlot` 内、哈希比较之前判定（N1）**：`publishPlot` 已在 `commitLock` 下运行，且对同 operationID 的已提交行先于事务 1 处理（`LibraryAssetService+Plot.swift:~93-100`）。自动意图的入口（新增 `publishAutoPlot` 薄封装或 `publishPlot` 的 `onExistingCommit: .returnReceipt` 选项）在该处：若存在 committed `plot_publish` 行，**不比较文件摘要**，直接返回 `alreadyCommitted(PlotCommitResult)`，不进入事务 1，故不会插入 staging 行，也不会走 `abortPlotPublish`。这样同意图并发运行中后到者必得 `alreadyPublished` 而非 `operationRequestMismatch`。`commitGuard`（2.3-7）**只检查代际与启用状态，永不对已存在的 committed 行运行**；并要求：guard 抛错的 abort 路径不得覆盖 committed 行（事务 1 前已排除）。进程内对同一 `intentKey` 再做单飞以减少重复渲染。人工保存路径保持原行为。
3. 无回执 → 渲染 → `publishPlot`。若 publish 在“提交成功但回执丢失”处被打断，下一次进入第 2 步即得回执。仅当 `aborted/pending`（均已被 F9 恢复清理）才重新渲染，此时不存在已提交结果，新内容不会与旧 hash 冲突（aborted 行在 F7 的事务 1 被删除）。
4. 人工删除自动图后：operation 行仍为 committed（F8），回执命中 → **不复活**。需测试证明 F8（含 Plot 删除、Sample 回收与永久清理路径均不删 `plot_publish` 行）；若不成立，改动属 Library 存储层，须经 D7 由用户决定，不在设计阶段预设。
5. 不新增 operation 类型；复用 `plot_publish` 与现有恢复。

### 2.2 触发点与“真正新入库”

- F2 说明返回值不能区分首次与重放（已提交结果存于 op payload 并在重放时原样解码返回）。**`isNewCommit` 不能作为 `AssetIngestResult` 的持久字段**（否则 `true` 会随 payload 存档并在重放时回传）。改为：`ingestAsset` 另返回非持久的包装/出参 `IngestDisposition{firstCommit: Bool}`，仅在本次调用实际完成首次提交时为 true；重放路径恒为 false；不写入 payload。测试：首次→true，重放→false，旧 payload 仍可解码。
- **复用 Source 的情形（待用户确认 D6）**：按内容复用 Source（`reuseSourceID`）时，代码仍会生成新的 ready Dataset 并返回新 `datasetIDs`。是否对这类“同一原始文件再次入库产生的新 Dataset”自动出图是产品决定：建议**不触发**（与 brief“复用 Source 不等于新 Dataset”及 AC1“已复用不触发”一致，避免对同一原始文件重复出图）；这不是代码事实，须用户确认。无论选哪种，都由 `firstCommit` 与 `reuseSourceID == nil` 两个显式条件表达，不靠 `reusedSource` 推断。
- 通知位置：`applyV2` 在审计成功后产生 `AutomationTrigger{datasetIDs, sampleUID, rootURL}`，经 `InboxArchiveApplyResult` 带出，由 `ApplyCoordinator` 汇总后交给自动化服务；**导入先完成并返回成功**，自动出图在其后异步运行，失败不回滚导入（brief 要求）。
- 仅处理 AFM Dataset（workflow 为 afm，且 format 为任务 5 的 AFM 标准格式）；V1、其他 Workflow、非 ready 不触发。

### 2.3 执行路径（复用，不复制）

对每个 trigger 的每个 datasetID，在后台任务内：

1. 读当前**已应用预设**、启用状态与代际（见 2.4）并**G 在 trigger 产生时（入库成功、导入汇总返回前）从同一次预设文件读取中与预设内容一并捕获并写入 trigger/journal**，不在执行时重读；执行时仅与 gate 的当前代际比较，Apply/关闭/切库发生在其间则 `cancelled`（与 brief“Apply 或变更使旧未发布意图失效”一致）。预设内容与 G 必须来自同一次原子读取，gate 仅用于比较、不作内容来源。关闭则结束；显式“补跑”在关闭状态下直接拒绝并提示先启用。trigger 带 `{datasetID, datasetRevision, sampleUID, rootURL(触发时)}`。
2. 回执查询（2.1-2）。
3. `loadDatasetForAnalysis` 取 context 与 revision；revision≠trigger 的 revision、Sample 已回收、归属无效 → 跳过并报告（不发布）。`PlotInputRef.revision` 即此步读到的 revision，不再另读。
4. 通道选择：按预设规则**严格**解析唯一目标通道；零个或多个 → 跳过并报告原因（F5：不回退）。规则→通道的匹配是**新增逻辑**（F5 只保证显式通道缺失时不回退），放在 AFM 层的无 UI 纯函数中，由单元测试覆盖；人工 Workbench 不使用它，AC2 的“共用入口”仅指 `AFMPlotComputation.run` 之后的计算/渲染。
5. `AFMPlotComputation.run(dataset:configuration:display:)`，其中 `AFMProcessingConfiguration` 与 display 全来自预设，**不读取 WorkspaceStore**。
6. `AFMPlotCodec.encode(...)` 与 `publishPlot`（`capturedRootURL` 为触发时的 root；`rootURL` 为当前 root）。提交点的复核由 F7 的 `requirePlotWriteContext/validatePlotInputs` 承担（root/lease、Dataset revision、归属、回收状态）。
7. **预设代际与启用状态的提交前复核**：F7 的事务不认识预设。设计要求在调用 `publishPlot` 前后各校验一次代际，但这并不能关闭“校验后到提交前”的窗口。**最小方案（待实施阶段证明）**：在 `publishPlot` 增加可选的 `commitGuard`，在事务 2 内（`commitLock` 持有时）调用，抛错即沿现有 catch 走 `abortPlotPublish`（留下 aborted 行，可同 ID 重试；因 2a 已排除 committed 行，不会覆盖回执）。**代际权威与生命周期（N3）**：权威是预设文件的 `generation`。进程内按 libraryRoot 键控的状态 `AutoPlotGate{enabled, generation}`，在 Library 打开/切换时由**同一次文件读取**播种（预设值与 G 来自同一读取）；Apply/开关的顺序为：先在 `commitLock` 内更新 gate，再写文件，写文件失败则回滚 gate 并报错。由于 gate 的更新持有 `commitLock`（`commitLock` 为递归锁，且 guard 只读 gate、不取其他锁、不做 IO，无死锁），**Apply/关闭返回之后不会再有新的自动发布提交成功**，该保证精确成立；崩溃发生在 gate 更新与写文件之间时，gate 为进程内状态随进程消失，重启重新以文件为准。guard 同时比较触发时的 root 与当前 root。重启后 journal（选项 B）里旧进程的代际 G 与文件当前代际比较：不一致即 `cancelled`。调用 `publishPlot` 前的预检只是快速失败优化，不构成保证；预检读取 gate 使用其自带的轻量同步（不取 `commitLock`）。**线程**：gate 更新入口位于 `LibraryAssetService`（`commitLock` 为其静态成员）；`commitLock` 在 publish 文件 IO 期间被持有，故 Apply/开关必须在 main actor 之外异步执行，UI 显示“正在应用”的等待态，不得在主线程上阻塞等锁。

### 2.4 预设的权威与保存

- **待用户确认（建议）**：预设与启用状态保存在**当前 Library 内**一个小 JSON（例如 `automation/afm_auto_plot.json`），含 `enabled`、`generation`（每次 Apply 或 enabled 变化单调递增）、通道选择规则、`AFMProcessingConfiguration` 的科学字段、Heatmap 显示/scale bar/style 的实际参数。随库迁移/备份，切库自然隔离；代价是需要一个新的小文件格式与读写入口。备选：App 级偏好（简单，但跨库共享、不随库）。
- 只能通过明确 “Apply” 写入；Workbench 手动调参不反写。读写走既有写许可（单写者租约），只读实例不能 Apply。
- 损坏/版本未知 → fail-closed：视为关闭并报告，不尝试修复。
- `AFMPlotComputation.DisplayInput` 当前含 `globalPlotDefaults: [String:String]`；实施时须把**实际用到的值**冻结进预设（避免“全局样式后来变了，旧图无法复现”）。manifest 是否需要记录 `presetGeneration`/自动来源见 2.6。

### 2.5 未完成意图与崩溃恢复

- 现有机制能恢复的是 **publish 中途崩溃**（F9）；它**不能**恢复“导入已提交、trigger 尚未执行”的间隙，因为意图没有持久化。
- **另一个缺口（M2）**：若 `ingestAsset` 已提交但 trigger 未能交出（崩溃，或 `apply` 抛错后 Inbox 条目仍在），再次 Apply 同一 pending 会命中 ingest 回执重放，`firstCommit=false`，**永不触发**。这需要显式的补救动作，不能靠重投。
- **待用户确认（选项 D4）**：
  - **A（最小，不持久）**：意图只在内存；应用在导入后立即执行。崩溃/退出会丢失，且**重启后没有可识别的未完成状态**——这**不满足** brief“至少保留可识别的未完成状态”，只满足“明确的恢复方式”：显式“补跑自动出图”动作（用户对某 Dataset 触发，走同一路径，按 datasetID+revision 命中回执，天然幂等）。需用户明确接受这一偏离。
  - **B**：在预设同目录写 `automation/afm_auto_plot_pending.json`（每个意图 `intentKey`、datasetID、revision、generation，入库成功后、执行前追加，committed/跳过后删除），启动且持有写租约时逐条重放（仍走 2.1 回执查询）。覆盖崩溃，但新增一个持久文件与清理规则；同样存在“`ingestAsset` 提交成功→写意图”之间的极小窗口，不能声称零丢失。
  - 因 A 不满足 brief 的“可识别未完成状态”，**建议改为 B**（最小持久 journal，复用现有写租约；每条意图只含 datasetID/revision/trigger 时的 root 与代际）。**为缩小 M2 窗口**，journal 在调用 `ingestAsset` **之前**按 pending ID 写入意图（datasetIDs 待填），入库成功后补全，失败则删除；journal 只在自动化已启用时写入。新增只读 `ingestReceipt(operationID:rootURL:) -> AssetIngestResult?`（`commitLock` 内读 committed `ingest` 行）：重启且持有写租约时，对每条 journal 条目——有 ingest 回执 → 用回执的 datasetIDs/`reuseSourceID` 条件（D6）补全并按 2.1 执行（回执查询保证幂等）；无回执（入库未提交）→ 丢弃条目。因此用户**无需知道 datasetID、无需扫描全库**；“补跑”动作只面向 Library 中已有 Dataset（用户在列表里选择）。仍残留的窗口（journal 写入失败/损坏）按 fail-closed 报告，由“补跑”覆盖，该残留需用户在 D4 接受。两者都不扫描全库、不承诺常驻服务；最终由用户在 D4 选定。
- 旧意图失效：执行前核对 `enabled`/`generation`/当前 root（2.3-1、7）；失效的意图记为“已取消”，不发布，也不重试。

### 2.6 保存语义与图的标识

- 自动意图只 `publishPlot`（New），**不使用** `updatePlot`，不匹配/替换既有图；人工 Replace/删除沿任务 6。
- brief 要求自动图能辨认来源及实际预设（AC3）。Plot 包内已含实际配置与输入修订，但**不含自动来源标记**，且 manifest 未记录完整 `globalPlotDefaults`（brief 已指出）。因此**该缺口已确认**：向 `AFMPlotCodec` manifest 增加可选 `origin:"auto"`、`presetGeneration`、冻结的实际显示默认值；旧图缺字段按 manual 读取、不迁移、不改既有字段，实施时须证明旧图仍可读。不新增资产类型。
- 同一 Dataset 因预设代际变化、用户另行 Apply 后再次导入的**新 Dataset** 才会出新图；对既有 Dataset 不重画（brief §首期建议 1）。显式“补跑自动出图”是用户对**单个 Dataset**的主动操作，使用补跑时刻的已应用预设，命中回执则不重复；这是 D1 的受控例外，须用户在 D1 中确认。

### 2.7 状态与反馈

每个意图结果有明确终态：`published(plotID)`（本次提交）、`alreadyPublished`（回执命中，不含悬空 plotID）、`skipped(reason)`、`failed(reason, retryable)`、`cancelled(reason)`。内存态由自动化服务持有，导入汇总/Library 视图只读展示；失败可按 intentKey 重试（走回执查询）。不新增后台常驻服务，不改 Library 存储布局（仅 §3 所列 `LibraryAssetService` 小型 API 增补）。

## 3. 最小实现边界

新增：`AFMAutoPlotService`（无 UI，调用既有 F4/F5/F7 接口）、预设文件读写与 `AutoPlotGate`、`plotPublishReceipt` 查询、`ingestAsset` 的非持久 `IngestDisposition`、`ingestReceipt` 只读查询、意图 journal 文件（仅选 D4-B）、显式“补跑自动出图”动作、`AFMPlotCodec` manifest 的可选字段扩展（D5）、`publishPlot` 的 `onExistingCommit` 选项与可选 `commitGuard`（均为 `LibraryAssetService` 的小型 API 增补，不改变既有存储布局与人工路径行为）、设置/Apply UI（遵守 `specs/04_UI_RULES.md`，用 `AppSpacing` 等 token）。不新增：通用调度/DAG、第二套分析/资产管线、V1 支持、Result 写入、迁移。

## 4. 待用户确认的决定（建议已写明，均未批准）

| # | 决定 | 建议 | 影响 |
|---|---|---|---|
| D1 | 触发范围：仅新入库，不补历史、不因更正/预设变更重画；例外：用户对单个已有 Dataset 显式“补跑”（用补跑时刻预设，命中回执不重复） | 同 brief + 该受控例外 | 无历史批量补跑 |
| D2 | 预设保存位置：随 Library（建议）或 App 偏好 | 随 Library | 新小文件格式 vs 跨库共享 |
| D3 | Height 通道规则与实际科研参数（surface level/line flatten/zero reference/显示） | 由用户启用前确认，不替猜 | 科研语义，必须用户定 |
| D4 | 崩溃恢复：A 不持久（不满足 brief 的“可识别未完成状态”）/B 持久 journal | B | 新增一个小持久文件 vs 重启后不可识别 |
| D5 | 自动图 manifest 记录来源、代际与实际显示默认值（可选字段，旧图兼容） | 增加（缺口已确认） | 向后兼容的小扩展，需证明旧图可读 |
| D6 | 复用 Source 产生的新 Dataset 是否自动出图 | 不触发 | 避免同一原始文件重复出图 |
| D7 | 若 F8 不成立，是否接受删除时保留最小墓碑 | 仅在测试证明 F8 不成立后再议 | 属 Library 存储层改动，须用户确认 |

## 5. 验收证据方案（对应 brief AC1–AC6，实施阶段执行；本 PR 未运行）

- **AC1/AC2**：真实 Inbox→V2 标准化→自动出图；对同一 dataset/revision/配置，自动与人工经 `AFMPlotComputation.run` 得到逐值相同的矩阵、坐标、单位、诊断（测试直接比对两条路径输出），raw parser 调用计数为 0。覆盖缺失/歧义通道（跳过且有原因）、V1/非 AFM/复用 Source/导入失败不触发。
- **AC3**：自动图重启可读；manifest 与依赖行一致；既有人工图未被改动（revision/文件摘要不变）；Source/Dataset/Sample Result 摘要不变。
- **AC4**：并发同意图、预设变更后重投/补跑、`ingestAsset` 重放（`firstCommit=false`）、ingest 提交→trigger 交接边界的故障注入；另故障注入覆盖 `plotAfterStaging/plotBeforeCommit/plotAfterCommit` 及“提交成功但回执丢失”；重复触发/并发触发/重启后重投/人工删除后重投均 ≤1 张且不复活；两个独立 Dataset 不被误去重；publish 失败不影响导入成功。
- **AC5**：确定性竞态测试用 `commitGuard`/fault 点：计算后 Dataset revision 变化、Sample 回收、切库/lease 丢失、预设 Apply 或禁用，均不发布；A→B→A 靠单调代际而非值比较。
- **AC6**：当前交付 HEAD 的隔离桌面 GUI（Apply/开关/导入/关闭 Workbench/Library 见图与失败反馈/重启读回）及全套 `check_required_actions.sh`；生产 Library 哈希不变。

## 6. 本 PR 未验证的事项

- F8（Plot 删除后 committed operation 行保留）与 F9 的恢复边界为静态阅读，需实施阶段用测试证明。
- 未运行 Swift 构建/测试/GUI；未宣称任何未来实施 AC 已通过。

## 7. 独立审查记录

- 方法：Deliver 默认设计审查，3 轮只读独立审查（新鲜上下文子 Agent），审查者不修改文件。
- 第 1 轮：发现 H1–H4（意图身份含代际、`isNewCommit` 被持久化、复用 Source 被当作事实、回执检查非原子）及 M1–M6；已修订。
- 第 2 轮：确认 H1–H3、M1–M6 已解，发现 N1（`alreadyCommitted` 守卫不可达且会覆盖回执）与 N2–N6；已修订。
- 第 3 轮（上限）：确认 N1–N6 已解，另指出 4 项：journal 恢复路径、代际捕获时刻、Apply 阻塞主线程、范围清单与 D1 不一致；**已按建议修订（§2.3、§2.5、§3、§4），但该修订未再经独立复审**。
- 结论：**审查未收敛至“已复审通过”**——最后一轮的修订为 material revision 且已达 3 轮上限。如需继续，建议一次聚焦复审（journal 恢复 + 代际捕获）或由用户明确延长轮次。
