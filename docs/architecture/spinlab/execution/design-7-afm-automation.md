# 任务 7 设计 — AFM 自动出图

状态：Design Draft；D1–D7 已由用户在 PR #242 评论（2026-11-27）确认；**不授权实施**。基线 main `4d5fd129`+（任务 6 #241 已合并）。合同来源：[brief-7](brief-7-afm-automation.md)、[SKELETON](SKELETON.md) K4–K10、K12–K13、[任务 6 设计](design-6-afm-workbench.md)。本文只补代码证据、最小实现边界与恢复合同；产品取舍保持“待用户确认”，不当作已批准。

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

1. **稳定意图身份只由 Dataset 决定**：`intentKey = "auto-afm|" + datasetID + "|rev" + datasetRevision`（datasetID 为入库时生成的 UUID，天然唯一）。**预设版本不进入身份**，它只用作“能否发布”的取消条件（2.3）。因此预设 Apply/开关变化之后的重投、补跑命中同一回执，不会产生第二张，也不会复活已删除的图。operationID 固定格式 `"auto-afm-" + 64 位小写 hex(SHA-256(intentKey))`（<100 字节，无 `/`、`..`，满足 `validateOperationID`）。
2. **回执查询**：新增只读 `plotPublishReceipt(operationID:rootURL:) -> PlotPublishReceipt?`，在 `commitLock` 内读取 `asset_operations`；仅当 `op_type == "plot_publish"` 且 `state == "committed"` 且含 `result` 时返回回执，`pending`/`aborted`/类型不符一律视为“无回执”（交由 `publishPlot` 的 `recoverPending` 处理）。有回执 → 不渲染、不 publish，终态记为 `alreadyPublished`（**不是** `published(plotID)`：该图可能已被人工删除，不得显示悬空 ID，也不复活）。
   - 回执查询在锁外是“提示优化”，**权威判定在 `publishPlot` 内**（见下 2a），以免两次并发的同意图运行都未命中回执、各自渲染出不同 `savedAt` 后第二个撞上 `operationRequestMismatch`。
2a. **在 `publishPlot` 内、哈希比较之前判定（N1）**：`publishPlot` 已在 `commitLock` 下运行，且对同 operationID 的已提交行先于事务 1 处理（`LibraryAssetService+Plot.swift:~93-100`）。自动意图的入口（新增 `publishAutoPlot` 薄封装或 `publishPlot` 的 `onExistingCommit: .returnReceipt` 选项）在该处：若存在 committed `plot_publish` 行，**不比较文件摘要**，直接返回 `alreadyCommitted(PlotCommitResult)`，不进入事务 1，故不会插入 staging 行，也不会走 `abortPlotPublish`。这样同意图并发运行中后到者必得 `alreadyPublished` 而非 `operationRequestMismatch`。`commitGuard`（2.3-7）**只检查预设版本与启用状态，永不对已存在的 committed 行运行**；并要求：guard 抛错的 abort 路径不得覆盖 committed 行（事务 1 前已排除）。进程内对同一 `intentKey` 再做单飞以减少重复渲染。人工保存路径保持原行为。
3. 无回执 → 渲染 → `publishPlot`。若 publish 在“提交成功但回执丢失”处被打断，下一次进入第 2 步即得回执。仅当 `aborted/pending`（均已被 F9 恢复清理）才重新渲染，此时不存在已提交结果，新内容不会与旧 hash 冲突（aborted 行在 F7 的事务 1 被删除）。
4. 人工删除自动图后：operation 行仍为 committed（F8），回执命中 → **不复活**。需测试证明 F8（含 Plot 删除、Sample 回收与永久清理路径均不删 `plot_publish` 行）；若不成立，改动属 Library 存储层，须经 D7 由用户决定，不在设计阶段预设。
5. 不新增 operation 类型；复用 `plot_publish` 与现有恢复。

### 2.2 触发点与“真正新入库”

- F2 说明返回值不能区分首次与重放（已提交结果存于 op payload 并在重放时原样解码返回）。因此**不靠返回值或 `reusedSource` 判定“新”**；自动出图意图改为**随入库事务持久化**（见 2.5），意图属于该次入库操作本身。重放同一已提交入库只会取回同一份意图，由 datasetID 身份、回执查询与版本比较保证幂等，不会把历史数据变成新任务。
- **复用 Source 的情形（D6，用户倾向：触发）**：按内容复用 Source（`reuseSourceID`）时，代码仍生成新的 ready Dataset 并返回新 `datasetIDs`。自动化消费的是 **Dataset**，不是 Source；因此**不因 Source 被复用而禁止**新 Dataset 自动出图。真正的重复操作（同一入库操作重放、同一 Dataset 重投）由 datasetID 身份与回执查询挡住；新的科研数据（新 Dataset）则出新图。代价（需用户知情）：对同一原始文件再次入库并复用 Source，会因产生新 Dataset 而再出一张自动图，人工可删。
- 通知位置：`applyV2` 在审计成功后产生 `AutomationTrigger{datasetIDs, sampleUID, rootURL}`，经 `InboxArchiveApplyResult` 带出，由 `ApplyCoordinator` 汇总后交给自动化服务；**导入先完成并返回成功**，自动出图在其后异步运行，失败不回滚导入（brief 要求）。
- 仅处理 AFM Dataset（workflow 为 afm，且 format 为任务 5 的 AFM 标准格式）；V1、其他 Workflow、非 ready 不触发。

### 2.3 执行路径（复用，不复制）

对每个 trigger 的每个 datasetID，在后台任务内：

1. 取得意图：入库前由调用方**一次读取**已应用预设，得到 `enabled` 与 `presetVersionID`（唯一配置版本身份，见 2.4）；`enabled` 为真则该 ID 随入库事务持久化为该次入库的 `autoPlotIntent`（2.5），否则不记录意图。执行时任务**重新原子读取**预设文件得到 (内容, `presetVersionID`)，仅当与意图记录的 ID 一致且 gate 当前也为该 ID、`sessionID` 未变（2.3-7）才执行，否则 `cancelled`（文件只保存当前版本，无法按旧版本取内容）；预设文件写入必须原子（临时文件+rename）。显式“补跑”在关闭状态下直接拒绝并提示先启用。trigger 带 `{datasetID, datasetRevision, sampleUID, rootURL(触发时)}`。
2. 回执查询（2.1-2）。
3. `loadDatasetForAnalysis` 取 context 与 revision；revision≠trigger 的 revision、Sample 已回收、归属无效 → 跳过并报告（不发布）。`PlotInputRef.revision` 即此步读到的 revision，不再另读。
4. 通道选择：按预设规则**严格**解析唯一目标通道；零个或多个 → 跳过并报告原因（F5：不回退）。规则→通道的匹配是**新增逻辑**（F5 只保证显式通道缺失时不回退），放在 AFM 层的无 UI 纯函数中，由单元测试覆盖；人工 Workbench 不使用它，AC2 的“共用入口”仅指 `AFMPlotComputation.run` 之后的计算/渲染。
5. `AFMPlotComputation.run(dataset:configuration:display:)`，其中 `AFMProcessingConfiguration` 与 display 全来自预设，**不读取 WorkspaceStore**。
6. `AFMPlotCodec.encode(...)` 与 `publishPlot`（`capturedRootURL` 为触发时的 root；`rootURL` 为当前 root）。提交点的复核由 F7 的 `requirePlotWriteContext/validatePlotInputs` 承担（root/lease、Dataset revision、归属、回收状态）。
7. **预设版本与启用状态的提交前复核**：F7 的事务不认识预设。设计要求在调用 `publishPlot` 前后各校验一次预设版本，但这并不能关闭“校验后到提交前”的窗口。**最小方案（待实施阶段证明）**：在 `publishPlot` 增加可选的 `commitGuard`，在事务 2 内（`commitLock` 持有时）调用，抛错即沿现有 catch 走 `abortPlotPublish`（留下 aborted 行，可同 ID 重试；因 2a 已排除 committed 行，不会覆盖回执）。**版本权威与生命周期（N3）**：权威是预设文件的 `presetVersionID`。进程内状态 `AutoPlotGate{sessionID, enabled, presetVersionID}`：每次 Library 打开（含 A→B→A 的再次打开）生成**新的 `sessionID`**，并由**同一次文件读取**播种 enabled/presetVersionID；Apply/开关的顺序为：先在 `commitLock` 内更新 gate，再写文件，写文件失败则回滚 gate 并报错。由于 gate 的更新持有 `commitLock`（`commitLock` 为递归锁，且 guard 只读 gate、不取其他锁、不做 IO，无死锁），**Apply/关闭返回之后不会再有新的自动发布提交成功**，该保证精确成立；崩溃发生在 gate 更新与写文件之间时，gate 为进程内状态随进程消失，重启重新以文件为准。**会话语义（单一规则）**：进程内正在执行的自动任务绑定其启动时的 `sessionID`，切换/关闭 Library 即使该任务所属库稍后又被重新打开（A→B→A），旧 `sessionID` 也不再等于当前，任务 `cancelled`；**不会**因路径与预设版本“碰巧相同”而复活。被取消或因崩溃中断的**持久意图**不丢失：重新打开 Library 后由 2.5 的恢复流程在新会话下重新评估（预设版本一致才执行）。即“进程内任务随会话取消，持久意图随库数据恢复”，两者不矛盾。guard 同时比较任务的 `sessionID` 与 `capturedRootURL`。调用 `publishPlot` 前的预检只是快速失败优化，不构成保证；预检读取 gate 使用其自带的轻量同步（不取 `commitLock`）。**线程**：gate 更新入口位于 `LibraryAssetService`（`commitLock` 为其静态成员）；`commitLock` 在 publish 文件 IO 期间被持有，故 Apply/开关必须在 main actor 之外异步执行，UI 显示“正在应用”的等待态，不得在主线程上阻塞等锁。

### 2.4 预设的权威与保存

- **已确认（D2/D3）**：预设与启用状态保存在**当前 Library 内**一个小 JSON（例如 `automation/afm_auto_plot.json`），含 `enabled`、**`presetVersionID`（随机 UUID，每次 Apply 或 enabled 变化都重新生成）**、通道选择规则、`AFMProcessingConfiguration` 的科学字段、Heatmap 显示/scale bar/style 的实际参数。**唯一配置版本身份只用这一个 UUID**，不用计数器、不用 epoch+generation 组合：计数可回退，而随机 UUID 只会在内容确实是同一次 Apply 的产物时出现。**实际保证与受支持边界**：UUID 在每次 Apply 时唯一，故“新 Apply 之后旧意图必不匹配”；文件被删除后重建会得到新 UUID（旧意图全部作废，可手动补跑）；若用户**整体恢复了 Library 的旧备份**（预设文件与入库/回执所在 SQLite 一并回到同一时刻，状态自洽）（文件与其 UUID 一并回到过去），则该版本下尚未完成的意图与当时的预设内容一致，按“该预设仍是已应用预设”继续评估是正确的，不视为误发布。**仅回退预设文件而不回退 SQLite 不受支持**（旧版本下已取消/跳过的意图可能晚发布）；设计不尝试检测备份回退，不为此建设新机制。随库迁移/备份，切库自然隔离；代价是新的小文件格式与读写入口。备选：App 级偏好（跨库共享、不随库）。
- 只能通过明确 “Apply” 写入；Workbench 手动调参不反写。读写走既有写许可（单写者租约），只读实例不能 Apply。
- 损坏/版本未知 → fail-closed：视为关闭并报告，不尝试修复。
- `AFMPlotComputation.DisplayInput` 当前含 `globalPlotDefaults: [String:String]`；实施时须把**实际用到的值**冻结进预设（避免“全局样式后来变了，旧图无法复现”）。manifest 是否需要记录 `presetVersionID`/自动来源见 2.6。

### 2.5 未完成意图与崩溃恢复（意图随入库事务持久化）

- 现有机制能恢复的是 **publish 中途崩溃**（F9）；“入库已提交、自动出图尚未发布”的间隙需要持久意图。**不再建立独立 JSON journal**（避免与入库事务两套持久状态的协调窗口）。
- **方案（建议，D4）**：`ingestAsset` 新增可选参数 `autoPlotIntent: AutoPlotIntent?{presetVersionID}`，由调用方在**入库前**读取预设后传入（预设关闭则为 nil）。该字段作为可选值写入同一 `IngestOpPayload`，与 Dataset 置 ready 的**同一个提交事务**一并持久化（旧 payload 缺字段按 nil 解码）。因此：
  1. 入库成功 ⇔ 意图已持久；不存在“入库成功但意图未写入”的窗口，也不存在“入库前已写 journal 而入库未发生”的孤儿。
  2. 预设版本在入库**前**捕获并随入库持久，不存在“入库成功、尚未捕获预设时崩溃”的歧义；恢复时只有意图的 `presetVersionID` 等于当前文件的版本才执行，否则 `cancelled`。
  3. 重放同一已提交入库**返回已持久化的原意图**：现有重放分支只返回 `result`（`LibraryAssetService.swift:~280-287`），`AssetIngestResult` 无意图字段，因此入库返回值须携带**从已提交 payload 读出的意图**（返回类型增补，或另读 payload），重放时**忽略调用方传入的新意图参数**；否则重试的 apply 会用新版本预设给历史 Dataset 误出图。它不会变成新任务：同一 datasetID 的回执查询与版本比较决定是否实际发布（历史重放要么命中回执，要么因版本不匹配而取消）。因此不需要 `firstCommit` 标志，`IngestDisposition` 取消。
- **恢复（后台执行，不阻塞 UI）**：Library 打开且持有写租约时，新增只读查询 `pendingAutoPlotIntents(presetVersionID:rootURL:)`：解码 committed `ingest` 行，筛选 `autoPlotIntent.presetVersionID == 当前版本`、其 Dataset 当前仍为 ready（且 revision 与意图一致）、所属 Sample 活跃未回收、且尚无 `plot_publish` 回执。**不设任意时间期限**；筛选依据是现有事实而非猜测。已永久删除/回收的 Sample 或不存在的 Dataset 因条件不满足而不被执行，且**不作为噪声重复报告**（只静默过滤，不新增状态）；确定性跳过（如通道歧义）可在重开时再次报告，可接受。撤销回收后符合当前预设的意图可重新评估，仍受回执与正式提交保护；已成功图、人工删除的图不会复活。**锁与实现要求**：过滤必须在 SQL 内完成（`json_extract` 等），`commitLock` 只覆盖该查询本身，不覆盖 Swift 侧逐行解码，避免长时间阻塞 Apply/Save 等写入。**复杂度证据**：该查询为一次顺序扫描 committed ingest 行并读取 payload 的 JSON 字段，复杂度 O(入库操作数)。设计阶段的合成证据（SQLite 内存库、10 万行含 JSON payload 的 ingest 行、`json_extract` 筛选）耗时约 0.07 s，仅说明量级，**不是 Swift 运行时性能**；真实性能留实施验收，若实施期间有证据表明开销不可接受，再凭证据提出最小选择（例如在已有表上加索引列），本设计不预设。
- 已知边界（R3，用户已接受）：入库前读取预设与入库提交之间若发生 Apply，意图的 `presetVersionID` 已过期，恢复时 `cancelled`，该次导入不出自动图且无持久痕迹（安全：旧意图绝不发布）；用户可显式“补跑”。
- 其余旧选项：A（不持久）不满足 brief“可识别的未完成状态”；独立 JSON journal 引入第二处持久状态，均不建议。显式“补跑自动出图”仍保留给用户对单个已有 Dataset 的主动操作。
- 旧意图失效：执行前核对 `enabled`/`presetVersionID`/`sessionID`（2.3-1、7）；失效记为 `cancelled`，不发布。进程内任务随会话取消；持久意图在新会话按有效版本恢复（见 2.3-7 会话语义）。

### 2.6 保存语义与图的标识

- 自动意图只 `publishPlot`（New），**不使用** `updatePlot`，不匹配/替换既有图；人工 Replace/删除沿任务 6。
- brief 要求自动图能辨认来源及实际预设（AC3）。Plot 包内已含实际配置与输入修订，但**不含自动来源标记**，且 manifest 未记录完整 `globalPlotDefaults`（brief 已指出）。因此**该缺口已确认**：向 `AFMPlotCodec` manifest 增加可选 `origin:"auto"`、`presetVersionID`、冻结的实际显示默认值；旧图缺字段按 manual 读取、不迁移、不改既有字段，实施时须证明旧图仍可读。不新增资产类型。
- 预设 Apply 后再次导入的**新 Dataset** 才会出新图；对既有 Dataset 不重画（brief §首期建议 1）。显式“补跑自动出图”是用户对**单个 Dataset**的主动操作，使用补跑时刻的已应用预设，命中回执则不重复；这是 D1 的受控例外，须用户在 D1 中确认。

### 2.7 状态与反馈

每个意图结果有明确终态：`published(plotID)`（本次提交）、`alreadyPublished`（回执命中，不含悬空 plotID）、`skipped(reason)`、`failed(reason, retryable)`、`cancelled(reason)`。内存态由自动化服务持有，导入汇总/Library 视图只读展示；失败可按 intentKey 重试（走回执查询）。不新增后台常驻服务，不改 Library 存储布局（仅 §3 所列 `LibraryAssetService` 小型 API 增补）。

## 3. 最小实现边界

新增：`AFMAutoPlotService`（无 UI，调用既有 F4/F5/F7 接口）、预设文件读写与 `AutoPlotGate`、`plotPublishReceipt` 查询、`ingestAsset` 的可选 `autoPlotIntent`（随入库事务持久、旧 payload 兼容）、`pendingAutoPlotIntents` 只读查询、显式“补跑自动出图”动作、`AFMPlotCodec` manifest 的可选字段扩展（D5）、`publishPlot` 的 `onExistingCommit` 选项与可选 `commitGuard`（均为 `LibraryAssetService` 的小型 API 增补，不改变既有存储布局与人工路径行为）、设置/Apply UI（遵守 `specs/04_UI_RULES.md`，用 `AppSpacing` 等 token）。不新增：通用调度/DAG、第二套分析/资产管线、V1 支持、Result 写入、迁移。

## 4. 决定（D1–D7 已由用户于 2026-11-27 在 PR #242 评论确认；下表“建议”列即采纳结论）

D3 补充：提供独立、用户可见可编辑的自动化预设入口，支持“从 Workbench 当前配置生成预设”，Apply 后才生效；具体科研参数由用户使用时设置，不硬编码；通道不明确时跳过并说明原因。D7 补充：先测试复用既有已提交回执；不新增删除日志/墓碑/历史系统，回执不足则最小修复，只有改变产品或持久数据合同才升级决策。D4/D5 为已采纳的技术方案。

| # | 决定 | 建议 | 影响 |
|---|---|---|---|
| D1 | 触发范围：仅新入库，不补历史、不因更正/预设变更重画；例外：用户对单个已有 Dataset 显式“补跑”（用补跑时刻预设，命中回执不重复） | 同 brief + 该受控例外 | 无历史批量补跑 |
| D2 | 预设保存位置：随 Library（建议）或 App 偏好 | 随 Library | 新小文件格式 vs 跨库共享 |
| D3 | Height 通道规则与实际科研参数（surface level/line flatten/zero reference/显示） | 由用户启用前确认，不替猜 | 科研语义，必须用户定 |
| D4 | 崩溃恢复：意图随入库事务持久（建议）/不持久 A（不满足 brief）/独立 journal（两套持久状态） | 随入库事务持久 | 为 `IngestOpPayload` 增加一个可选字段并新增只读查询；确定性跳过可能在重开后再次报告 |
| D5 | 自动图 manifest 记录来源、预设版本 ID 与实际显示默认值（可选字段，旧图兼容） | 增加（缺口已确认） | 向后兼容的小扩展，需证明旧图可读 |
| D6 | 复用 Source 产生的新 Dataset 是否自动出图 | 触发（用户倾向；自动化消费 Dataset） | 同一原始文件再入库会再出一张自动图，人工可删 |
| D7 | 若 F8 不成立，是否接受删除时保留最小墓碑 | 仅在测试证明 F8 不成立后再议 | 属 Library 存储层改动，须用户确认 |

## 5. 验收证据方案（对应 brief AC1–AC6，实施阶段执行；本 PR 未运行）

- **AC1/AC2**：真实 Inbox→V2 标准化→自动出图；对同一 dataset/revision/配置，自动与人工经 `AFMPlotComputation.run` 得到逐值相同的矩阵、坐标、单位、诊断（测试直接比对两条路径输出），raw parser 调用计数为 0。覆盖缺失/歧义通道（跳过且有原因）、V1/非 AFM/导入失败不触发；同一入库操作重放与同一 Dataset 重投不触发新图；复用 Source 产生的新 Dataset 会触发（D6）。另覆盖 A→B→A 重开 Library：旧进程内任务取消，持久意图在新会话按预设版本恢复且不重复。
- **AC3**：自动图重启可读；manifest 与依赖行一致；既有人工图未被改动（revision/文件摘要不变）；Source/Dataset/Sample Result 摘要不变。
- **AC4**：并发同意图、预设变更后重投/补跑、`ingestAsset` 重放、入库事务提交前后崩溃（意图随入库原子出现/消失）的故障注入；另故障注入覆盖 `plotAfterStaging/plotBeforeCommit/plotAfterCommit` 及“提交成功但回执丢失”；重复触发/并发触发/重启后重投/人工删除后重投均 ≤1 张且不复活；两个独立 Dataset 不被误去重；publish 失败不影响导入成功。
- **AC5**：确定性竞态测试用 `commitGuard`/fault 点：计算后 Dataset revision 变化、Sample 回收、切库/lease 丢失、预设 Apply 或禁用，均不发布；A→B→A 靠每次打开的新 sessionID 与随机配置版本 ID，而非路径或数值比较。
- **AC6**：当前交付 HEAD 的隔离桌面 GUI（Apply/开关/导入/关闭 Workbench/Library 见图与失败反馈/重启读回）及全套 `check_required_actions.sh`；生产 Library 哈希不变。

## 6. 本 PR 未验证的事项

- F8（Plot 删除后 committed operation 行保留）与 F9 的恢复边界为静态阅读，需实施阶段用测试证明。
- 未运行 Swift 构建/测试/GUI；未宣称任何未来实施 AC 已通过。

## 7. 独立审查记录

- 方法：Deliver 默认设计审查，3 轮只读独立审查（新鲜上下文子 Agent），审查者不修改文件。
- 第 1 轮：发现 H1–H4（意图身份含代际、`isNewCommit` 被持久化、复用 Source 被当作事实、回执检查非原子）及 M1–M6；已修订。
- 第 2 轮：确认 H1–H3、M1–M6 已解，发现 N1（`alreadyCommitted` 守卫不可达且会覆盖回执）与 N2–N6；已修订。
- 第 3 轮（上限）：确认 N1–N6 已解，另指出 4 项：journal 恢复路径、代际捕获时刻、Apply 阻塞主线程、范围清单与 D1 不一致；**已按建议修订（§2.3、§2.5、§3、§4），但该修订未再经独立复审**。
- 结论（第 3 轮后）：**审查未收敛至“已复审通过”**——最后一轮的修订为 material revision 且已达 3 轮上限。如需继续，建议一次聚焦复审（journal 恢复 + 代际捕获）或由用户明确延长轮次。
- 第 3 轮后补充（用户转述的 3 项 P2，已核对代码事实并修订，**未再经独立复审**）：① journal 与入库衔接 → 改为意图随入库事务持久（§2.5）；② A→B→A → 引入每次打开的 `sessionID`，进程内任务随会话取消、持久意图随库数据恢复（§2.3-7）；③ D6 → 按 Dataset 中心架构改为“复用 Source 产生的新 Dataset 也触发”（§2.2）。这些均为 material revision，需要一次聚焦复审或用户明确延长轮次。

### 第 4 轮（用户在 PR 评论中额外授权的一次聚焦复审，被审版本 `1e033133`）

- 结论：**not converged**。确认：入库事务内意图原子性成立；已提交入库的重放不产生新任务；提交守卫与 `commitLock` 顺序成立；A→B→A 仅靠每次打开新 `sessionID`（需与写租约获取同处铸造）防护。
- 发现并已在文档修订：R1 代际计数可因文件删除/回滚而回退致旧意图碰撞 → 改用 (presetEpoch, generation)；R2 恢复查询无界且死条目永不终结 → 改为有界集合（ready + 活跃 Sample + 时间窗口）并如实写明限制；R3 入库前预设与提交间 Apply 的丢失边界；R4 “按 G 读取”不可实现 → 改为原子重读并比较 (epoch,G)。
- **上述修订未再经独立复审**（授权已用尽，不擅自增加轮次）。设计阶段结论：存在实质修订未复审，不宣称设计审查通过；若需通过证明，需用户授权再一轮聚焦复审。

### 第 5 轮（用户在 PR 评论 2026-11-27 11:01 授权的一次聚焦复审，被审起点 `d5042924`）

- 修订：以单一随机 `presetVersionID` 取代 (epoch, generation)；撤销 30 天任意期限，恢复筛选改用现有事实（ready Dataset/revision、活跃 Sample、有效预设版本、无回执）；增加合成复杂度证据；接受导入期间 Apply 的边界；明确备份回退的受支持边界。
- 复审结果见下一条。

- 第 5 轮结论（被审 HEAD `e9a994da`）：**not converged（窄）**。确认：单一随机 `presetVersionID` 防止旧意图碰撞，整库备份回退边界诚实；恢复查询无需时间窗口，回执在删除路径中不被移除，手动删除的图不复活；并发由 `publishPlot` 内 committed 行判定与单飞覆盖。指出 2 项文字/合同缺陷：① §2.5 仍有旧接口 `{presetEpoch, presetGeneration}` 与少量“代际”残留；② 重放必须返回已持久化的原意图而非调用方新读取的意图（现有 `AssetIngestResult` 无意图字段）。另记 3 项可接受限制：仅回退预设文件不受支持；确定性跳过重开时再报告；恢复查询须在 SQL 内过滤、锁只覆盖查询。
- 处置：以上 2 项缺陷与 3 项限制已在正文修订/记录（HEAD 之后），**该修订未再经独立复审**（授权的一轮已用尽，不擅自增加轮次）。设计审查因此**未取得“复审通过”**；保持 Draft。
