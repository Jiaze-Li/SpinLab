# 任务 12 设计 — Workbench → Sample Result 显式赋值（AHE 首个消费者）

状态：Design Draft；独立设计审查已收敛（见 §9），P1–P4 待 Jack 确认。基线 main `79cd971a`。本文只含设计与源码核查，不含 Swift 实现，也不声称任何验收已运行。需求与边界见 [brief-12](brief-12-workbench-sample-results.md)，共同合同见 [SKELETON](SKELETON.md) K8–K10、[Task 4](brief-4-parameters.md)。

## 1. 源码核查结论（2026-11-27，HEAD `79cd971a`）

| # | 事实 | 位置 | 对设计的影响 |
|---|---|---|---|
| F1 | `extractAHEMetricsPerSeries` 以 `series.sampleID`（= `selection.sampleKey`）为键，`guard result[key] == nil else { continue }`：同一 Sample 的多条曲线（多文件、多通道 ch1/ch2）**只保留第一条**，其余静默丢弃 | `UseCases/ExtractAHEMetricsUseCase.swift` | 现有输出对“同 Sample 多输入”是有损聚合，来源不可追溯，不能当无歧义候选 |
| F2 | `extractSingleSeriesMetrics` 在 `x.count <= 1` 时返回 `(0.0, 0.0)`，调用方无法区分“真实零”与“无结果” | 同上 | 必须在候选层把“点数不足”识别为无结果，不得写 0（K8：无结果不能补零） |
| F3 | `lastExtractedHc/RAHE` 取 `values.first`（字典无序）；`lastExtractedMetrics` 在 `clearPlot()` 清空、在渲染成功后整体替换 | `AHEWorkspaceStore.swift` | 便利属性不得用于赋值 |
| F4 | 指标只在 `_runAnalysisWithPreparedSelections` 成功时更新；`restoreFromPack` 有缓存 ingestion 时只重绘，**不重算也不清空** `lastExtractedMetrics`，旧运行的指标可残留到恢复后的图上 | 同上 | 候选必须绑定产生它的那次运行；恢复 Pack 视为候选失效 |
| F5 | 指标取自 `AHEBackgroundCorrectionUseCase` 校正后的序列；`conditions` 取该 Sample 第一条 selection 的 conditions（`snapshotConditions`） | 同上 | 条件展示只能是“第一条输入的条件”，多输入条件不同时不能代表指标 |
| F6 | 手动 override：`pendingMetricOverride`/`pendingRAHEOverride` 仅在单样品时由 `buildActiveChartMetrics()` 应用，且随 Save Plot 成功清空 | 同上 | override 是 Save Plot 路径的草稿，不是已应用结果 |
| F7 | `LibraryResultService.setValue` 重读 Catalog 与正式 `sample.json`，校验有限值、Definition 存在、`id` 一致、`expectedCurrent` 相等后经 `LibraryWriteLease.ensureWritable` 写入；`LibraryStore.drawerRootURL` 已按 V1/V2 路由（V2 用 `sampleUID ?? id`） | `Library/LibraryResultService.swift`、`LibraryStore+Drawers.swift` | 写入权威已唯一；缺口见 §4 |
| F8 | `setValue` 不校验：Definition 的 unit/qualifier 自用户看到后是否变化；Sample 是否已进废纸篓（`deletedAt`）；当前 Library root 是否仍是用户确认时的 root；仅在 read-only 时拒绝而不核对本进程确实持有该 root 的写租约（`holdsWritableLease(for:)` 存在） | 同上、`Storage/LibraryWriteLease.swift` | 需最小增强 |
| F9 | AHE 搜索命中为旧 sidecar 命中（`inputRef == nil`），身份是 `sampleKey`（V1 下等于 `LibrarySample.id`）；V2 标准 Dataset 命中目前只有 AFM（`standardDatasetHits`，`workflowID: "afm"`） | `Domain/WorkflowSearchModels.swift`、`UseCases/SearchWorkflowMeasurementsUseCase.swift` | AHE 在 V2 库没有稳定 Sample/Dataset 身份 |
| F10 | `SampleResultsSection` 的手填路径：单次 `setValue`，旧值存在时二次确认，`expected` 为用户所见值 | `Features/Library/SampleResultsSection.swift` | 确认语义可直接复用，Workbench 不另造一套 |
| F11 | `updateHcCandidate/updateRAHECandidate` 只要文本能解析为 `Double` 就立即设置 override（无“应用”动作；`Double("nan")`/`Double("inf")` 也能解析）；override 仅在 `clearPlot()` 与 Save Plot 成功后清空，**重新 Analyze 不清空** | `AHEWorkspaceStore.swift` | override 草稿与已应用无法区分，且会跨运行残留；见 §3 与 P4 |
| F12 | 运行开始不清 `lastExtractedMetrics`；失败路径只 `tabs.clearOutputs()`；取消不动状态。重新 Analyze 进行中或失败后，旧指标与已清空的图并存 | 同上 | 失效必须覆盖运行开始/失败/取消 |
| F13 | Ingestion 对无数据/无有效行的 selection 静默跳过（仅警告），所以 selection 数不等于最终 series 数；指标取自背景校正后的序列 | `IngestAHESelectionsUseCase.swift`、`AHEWorkspaceStore.swift` | 可赋值判定必须看最终序列，而非 selection 数 |

## 2. 用户路径

1. 用户在 AHE Workbench 正常 Analyze，得到图与 Hc / R_AHE。
2. 结果区每个指标旁有“写入 Sample Result…”（仅当该指标是**可赋值候选**时可用，见 §3；否则显示不可用原因，例如“该样品有多条曲线，请只选一个测量后重新 Analyze”）。
3. 点击后打开确认面板，只处理**一个指标、一个 Sample、一个 Definition**，展示：
   - 指标名与实际数值（含单位 T / Ω）；来源：Sample 名、输入文件名、通道；输入的测量条件（原样展示，未知则写“未知”）。
   - Sample（默认为来源对应的唯一正式 Sample，只读展示，不提供下拉改选；见待决项 P1）。
   - Definition 选择器：只列已有 Definition（名称、单位、限定文字）；**不默选**。无 Definition 时显示“请先在 Library → Result Definitions 创建”，不自动创建。
   - 目标 Sample 在该 Definition 下的当前值（空槽位显示“—”）；选中后显示“当前值 → 新值”。
   - 单位提示：Definition 单位与指标单位相同 → 无提示；不同 → 醒目提示“Definition 单位为 X，将写入的数值单位为 T，数值不会被换算”，用户仍可确认（K9：人工最终判断）。限定文字与输入条件只并列显示，不做文本匹配判断。
4. 用户点“确认写入”：写入同一当前值槽位（若原值存在，面板本身即覆盖确认，不再叠第二个弹窗）。取消或关闭面板不写。
5. 成功：面板关闭，Library 索引刷新（沿用 `refreshLibraryAfterResultChange`）；失败：面板保留并显示原因，不写、不重试。

写入后不产生任何其它副作用：不触发 Save Plot / Save Analysis / metric 保存；不改 Source、Dataset、Plot、Registry/XLSX、`numericTags`、`measurement_data.json`、Analysis Pack。

## 3. 候选契约（最小共享）

```swift
struct SampleResultCandidate: Equatable, Sendable {
    let metricName: String        // "Hc" / "R_AHE"，仅展示
    let value: Double             // 必须有限
    let unit: String              // 指标的 canonical 单位："T" / "Ω"
    let sourceSampleKey: String   // 产生该值的输入所属 Sample 标识
    let sourceBatchID: String     // 来源命中的 batchID，用于确认时重新解析目标
    let inputSummary: String      // 文件名 + 通道，仅展示
    let conditions: [String: String]  // 原样来自输入；空表示未知
    let origin: Origin            // .computed 或 .manualOverride(reason)
    let runToken: UInt64          // 产生它的那次分析运行
    let overrideRevision: UInt64? // 仅 .manualOverride：override 的修订号
}
```

- 它是**内存中的一次性对象**：不持久化、不进 Pack、不写 SQLite；`runToken` 仅用于判断是否过期。共享的只有这个值类型与确认面板（接受 `[SampleResultCandidate]` + 目标 Sample 解析器）；RT/3ω 后续各自提供“如何产生候选”，不预建依赖图。
- **可赋值**当且仅当（在运行成功的主线程回调里一次性判定并随 `runToken` 保存，不事后拼装）：
  1. 该运行成功且当前 `!isPlotRendering`；
  2. 背景校正后的 `correctedSeries` 中，`sampleID == sourceSampleKey` 的序列**恰好一条**（用最终序列判定，F13；不数 selection）；
  3. 该序列 `x.count >= 2` 且 Hc/R_AHE 有限（运行时把序列数与点数随候选保存，因 `lastExtractedMetrics` 只含 `(hc, rAHE)`）。
  多条序列（多文件/多通道，F1）→ 拒绝并给原因（待决 P2）；点数不足（F2）→ 不产生候选，提示“数据点不足”。不修改 `ExtractAHEMetricsUseCase` 的科研算法。
- 零是有效值：点数足够的真实 0 可赋值；点数不足的 (0,0) 不是结果。
- **override（F11）**：`.manualOverride` 候选只在 override **有限、非空且 `runToken` 与当前运行一致** 时提供（建议“应用”定义见 P4）；非有限（nan/inf）或不属于当前运行的 override 不产生候选。面板同时显示“计算值 a / 人工修正值 b”，用户**明确选一个**，默认不选。赋值不清空 override，也不触发 Save Plot。实施时 override 记录其产生时的 `runToken`；新运行开始时旧 override 视为不属于当前运行（是否同时清除其文本框内容属 UI 细节，由实施者按 Workbench 控件规范决定，不得让旧 override 与新计算值并列出现为候选）。
- **失效（F4/F12）**：`runToken` 在以下时刻递增，候选与已打开的面板立即作废、确认按钮禁用：运行**开始**、运行**失败或取消**、运行成功提交、`clearPlot()`、Pack 恢复、`lastRenderedSampleKeys` 变化、override 变化（override 变化只递增 `overrideRevision` 并使面板失效，**不**递增 `runToken`；`.manualOverride` 候选同时记录 `runToken` 与 `overrideRevision`，二者须与当前值一致）。Pack 恢复两个分支分别处理：带缓存 ingestion 的分支只重绘、不重算，**不产生候选**（且不得保留旧指标作候选）；legacy 分支调用 `runAnalysis`，运行成功后才有候选。
- 不借用 `lastExtractedHc/RAHE`（F3）。

## 4. 共同写入服务的最小增强（仍是唯一写入权威）

在 `LibraryResultService` 上新增一个确认级入口，手填和 Workbench 都走它；`setValue` 保持签名兼容：

```swift
struct ResultWriteGuard: Equatable {
    var rootURL: URL                 // 用户确认时的 Library root
    var definition: ResultDefinition // 用户确认时看到的 Definition（含 unit/qualifier）
    var targetBatchID: String        // 目标 Sample 身份：与 sample.id 一起由服务在确认时重核
}
func setValue(..., guard: ResultWriteGuard?) throws -> LibrarySample
```

当 `guard` 非空时，在**现有重读磁盘**之后、写入之前额外校验，任一失败抛明确错误、不写：

1. `LibraryWriteLease.shared.holdsWritableLease(for: guard.rootURL)`——当前进程确实持有**该 root** 的写租约（覆盖切到别的库、租约丢失、只读；它比 `ensureWritable` 严格，后者在无租约时也放行）。它只比较 root 路径，不区分会话：同一 root 的 A→B→A 切换后检查仍通过，这是可接受的，因为确认时目标 Sample、Definition 与旧值都从磁盘重读并校验（第 2–4 项），不依赖会话相等。
2. 磁盘上该 Definition 的 `unit`、`qualifier` 与 `guard.definition` 相同（Definition 被改语义则拒绝，要求重新确认；仅改名称不影响）。Definition 已删除沿用 `unknownDefinition`。
3. 磁盘上该 Sample 的 `deletedAt == nil`（已进废纸篓则拒绝）；`id` 一致沿用现有检查。
4. 当前 root 的布局不是 V2（`resolveLayout(at:).isV2 == false`）；确认时由 App 层解析器**从磁盘重新解析目标 Sample**（按 §5 规则，用候选的 `sourceBatchID` + `sourceSampleKey`；做法是读取该 V1 路径 `batches/<batchID>/samples/<sampleKey>/sample.json` 单文件并核对 `id`/`batchId`，而非全库扫描；仅当 `batchID` 为空时才用索引按 `id` 查唯一再读盘核对），把得到的 `LibrarySample` 与 `targetBatchID` 交给服务；服务再核对 `disk.batchId == guard.targetBatchID` 与 `disk.id == sample.id`。不使用打开面板时捕获的快照，避免布局或 root 变化后把 V1 解析出的 Sample 写到 V2 路径。
新增错误：`definitionChanged`、`sampleInTrash`、`libraryChanged`（均给出“请重新确认”类提示）；`libraryChanged` 同时覆盖第 1、4 项。
5. `expectedCurrent` 沿用现有语义（目标值被他处更新则 `staleValue`）。

说明与取舍：
- 手填路径可传 `guard: nil` 保持行为；Workbench 路径必传（确认窗口长，需要这些保护）。该参数是对现有唯一服务的增强，不新增服务、不新增存储字段。
- 串行性：确认动作从 SwiftUI 按钮在主线程调用 `setValue`（同步、无 `await`），手填路径同样如此；Workbench 的 `Task.detached` 只做分析与渲染，不写 Library。实施时须核对并保持 `setValue`/`saveSample` 不在后台线程被调用；跨进程由单写者租约保证。单人使用，不引入锁或事务框架（AGENTS.md 使用假设）。
- 面板中的“目标当前值”在选择 Definition 时**从磁盘重读**（不取 `LibraryStore` 索引缓存，brief 要求索引不是权威）；`expectedCurrent` 只比较数值，若磁盘值被他处改动后又恰好改回同一数值则不视为冲突，这是无害的。
- 写入仍只改该 Sample 的 `results`，不写 Registry/XLSX；沿用 `invalidateNodeCache`；失败时磁盘不变。
- 重复点击确认：第一次成功后 `expectedCurrent` 失配，第二次得到 `staleValue`，不会产生第二份副作用。

## 5. 目标 Sample 解析与 V1/V2 支持矩阵

| 场景 | 行为 |
|---|---|
| V1 库，来源命中的 `(batchID, sampleKey)` 在磁盘上**恰好匹配一个**未删除 `LibrarySample`（`batchId == hit.batchID` 且 `id == sampleKey`；`hit.batchID` 为空时仅按 `id`，仍须唯一） | 默认目标，显示后由用户确认。`id == sampleKey` 的前提在实施时以 `drawerRootURL`/V1 目录结构核对并加测试 |
| V1，无匹配 / 多个匹配 / 仅在废纸篓 | 不可赋值，显示原因；不凭名称、Batch、衬底猜测；不补发 UID |
| V1 旧无 UID Sample | 与手填同一路径（`drawerRootURL` 用 `batchId + id`），行为同现有手填 |
| V2 库，AHE 输入（旧 sidecar 命中，无 `inputRef`，F9） | **首期不可用**，提示“该 Library 的 AHE 输入尚未迁移到标准数据，请在 Library 中手填”；不静默写 V1 结构，不回退读取旧目录 |
| V2 库，手填 Result | 不变（服务已按 UID 路由） |
| V2 AFM / 其它标准 Dataset | 与本任务无关，不触碰 |

不迁移 AHE 到 V2（Task 11 范围）；若未来 AHE 产出带 `sampleUID` 的 `inputRef`，目标解析器直接按 UID 查找即可，无需改候选契约。

**Sample 默认值与跨样品**：目标由来源 `sampleKey` 唯一确定并只读展示；首期不提供改选目标 Sample（待决项 P1，建议不做）。

## 6. 待决项（需要 Jack 决定的只有产品/科研语义）

- **P1 跨样品赋值**：是否允许把 A 样品图上的 Hc 写给另一个 Sample？建议**不做**（首期只写来源 Sample），没有真实需求前不预建。
- **P2 同 Sample 多输入**：多文件/多通道时是否需要“选哪一条”？建议首期**拒绝并提示单独 Analyze**；有真实场景再加逐曲线选择（需把 F1 的聚合改成保留逐曲线结果，属算法输出结构变化，不在本任务内）。
- **P3 单位不匹配**：建议只提示不阻止，不换算（已写入 §2）。如希望“已知同量纲（如 T↔mT）自动换算”需另行决定；建议首期不做，避免替用户做科研判断。

- **P4 override 何时算“已应用”**：现状只要文本可解析就生效（F11）。建议：首期仅在 override **有限且属当前运行**时才作为备选候选，不新增“应用”按钮；用户总要在面板里明确选择并确认该值，输入到一半的值不会被自动写入。若希望把半输入也排除在候选之外，需要加显式“应用”动作（产品交互变化，需要决定）。

以上均已给出推荐；未确认前设计按推荐写，不当作已批准。

## 7. 代理决策与理由（按现行 L1 默认自主度，仅技术项）

- 候选为内存值类型 + `runToken` 失效，不引入持久来源关系：满足 K10（Sample Result 独立）且最小。
- `ResultWriteGuard` 加在现有服务而非新增服务：保持唯一写入权威（Task 4）。
- 点数不足 / 多输入在候选层拒绝，不改 `ExtractAHEMetricsUseCase`：满足“不新增或改变科研算法”。

## 8. AC 验证方案（实施 PR 才运行；此处仅规定证据）

| AC | 自动化 | GUI（隔离合成库） |
|---|---|---|
| AC1 | `LibraryResultService` + 候选单测：Hc、R_AHE 分别写入，0 与未填区分，其他 Sample/槽位不变；手填与 Workbench 写同槽位；重启后重读磁盘仍在 | 真实 Analyze → 选指标 → 选 Definition → 确认；Library 读回；重启后仍在 |
| AC2 | 候选数值等于 `extractSingleSeriesMetrics` 输出（固定合成曲线）；点数不足、非有限、多输入、Pack 恢复后无候选；override 候选与计算候选分离；nan/inf、空值、上一运行遗留的 override 不产生候选（半输入的有限值按 P4 视为候选，须经用户在面板明确选择）；多序列/点数不足/ingestion 跳过 selection 的最终序列判定；单位提示分支 | 面板显示数值/单位/条件；多输入显示不可用原因 |
| AC3 | 取消/Analyze/重绘/Save Plot/Save Analysis 前后 `sample.json`、`result_definitions.json`、Registry、`measurement_data.json` 逐字节不变；覆盖仅一次确认；上游重算后值不变；Analyze/Save Plot（含其清 override）不改动已确认的 `results`；双击确认只写一次 | 取消不写；旧→新可见 |
| AC4 | 每项独立测试：目标值被改（`staleValue`）、Definition unit/qualifier 被改、Definition 删除、Sample 进废纸篓、切到其它库后确认（同 root A→B→A 靠磁盘重读校验，不靠会话）、租约丢失/只读、确认时布局变为 V2、索引显示值与磁盘不一致、运行开始/失败/取消使面板失效、损坏 Catalog、损坏 `sample.json`、写入失败后磁盘不变；运行变化使候选失效 | 过期面板确认后给出清楚提示且不覆盖新的人工值 |
| AC5 | V1 AHE 路径回归（Analyze/Plot/Pack/metric/手填）；无 UID 样品；同名/多匹配拒绝；V2 手填不变；V2 + AHE 输入不可用（含确认时再校验）且不写 V1 结构 | V1 库与 V2 库各走一次入口，V2 显示不可用提示 |
| AC6 | — | 按 `spinlab-gui-validation`，隔离合成数据、当前 HEAD 构建；实际 AHE 输入→赋值→旧→新确认→取消→错误→Library 读回→重启；真实数据副本仅在已授权时使用 |

实施时同步：`docs/architecture/workbench/SHELL_BLOCKS.md` Code Map、`./scripts/check_controls_contract.sh`、`./scripts/check_ui_rules.sh`、`./scripts/check_required_actions.sh`；版本按 AGENTS.md（新增用户可见能力 → minor）。

## 9. 独立审查记录

- 第 1 轮（2026-11-27，只读 fresh-context 子代理，被审版本：初稿）：结论 needs revision。接受并已修订：A→B→A 表述不实（§4）；override 无“应用”概念且跨运行残留（F11、§3、P4）；失效未覆盖运行开始/失败/取消（F12、§3）；可赋值应按最终序列判定并保存点数（F13、§3）；Pack 恢复两分支（§3）；确认时 V2 布局与目标重新解析（§4 第 4 项、§5）；`(batchID, id)` 解析规则（§5）；面板当前值读磁盘、新增错误类型、串行性依据（§4）；AC 补充（§8）。
- 第 2 轮（同一子代理，被审版本：第 1 轮修订）：1–9 项已解决；新增 4 点并已修订：候选/Guard 缺目标身份与解析方式（`sourceBatchID`、`targetBatchID`、单文件读盘）；P4 与 AC2 矛盾；`overrideRevision` 与 `runToken` 分离；编号。
- 第 3 轮（同一子代理，被审版本：第 2 轮修订，内容即本文）：**converged**，无实质问题。实施 PR 备注（不阻塞）：解析目标路径须调用 `sampleDirectoryURL`/`resolvedBatchDirectoryURL`（含路径清洗与批次目录名），不手拼；`guard.targetBatchID` 必须填入解析得到的实际 `batchId`，不得为空串；废纸篓 Sample 路径不变，由 `deletedAt` 检查拒绝。
- 审查为任务级设计审查（3 轮上限已用完，已收敛）；它是建议性的，不代表对 P1–P4 的产品批准。
