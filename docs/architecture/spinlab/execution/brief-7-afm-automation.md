# 任务 7 — AFM 自动出图

状态：设计 PR #242 已合并（设计 HEAD `0c368d12`，最终 Deliver 裁决 READY）；2026-11-27 用户明确授权另开实施 Draft PR，实施基线 main `34cc2629`（任务 6 #241 已合并）。D1–D7 已确认（见 [design-7](design-7-afm-automation.md) §4 及 #242 授权评论），不重新选择产品路线。继承 D6-B T05 和 D5 的已确认方向；共同合同：[SKELETON](SKELETON.md) K4–K10、K12–K13；复用 [任务 5](brief-5-afm-standard-assets.md)、[任务 6](brief-6-afm-workbench.md) 与 [正式 Plot 设计](design-6-afm-workbench.md)。

## 用户要什么

新 AFM 数据完成标准化、正式进入 Library 后，按用户预先启用的 Workflow 预设自动处理、出图并保存到所属 Sample。自动化与人工 Workbench 共享分析/绘图/正式保存能力，但不依赖 Workbench 页面、选中行或上次临时控件。用户可编辑并明确应用默认预设、开关自动执行；启用后匹配的输入无需逐次审批。先做一个 AFM 闭环，不提前搭建通用编排器。

## 已确认边界

- 只消费正式 ready 的 V2 Standard Dataset；原始 IBW 仍由任务 5 的入口标准化，自动化不解析原始文件、不改标准矩阵、Source 或 Sample Result。归属经 Dataset → Source → Sample 推导。
- 处理顺序、算法、科学配置与显示配置沿任务 6；自动调用共享无页面分析、正式 Plot codec 与资产发布服务；图包含 PNG、处理矩阵、坐标/单位、诊断和实际有效配置/输入修订，不以临时截图代替成果。
- 正式保存遵守同一写许可、提交边界、修订和归属复核、恢复及删除保护；不能借自动化绕开人工 Plot 的正式提交约束。仅支持 V2；V1 的人工 Analyze/Pack/Restore 不变。
- 不做 Snapshot、V2 Pack、Result 自动写入、旧库迁移、其他 Workflow、Spin Cat、跨机器调度或自由组合 DAG。不让 Library 存储层承担分析编排。

## 首期范围（含 2026-11-27 PR 评论中用户确认的决定）

1. **触发范围**：每个新正式入库 AFM Dataset，按一个已启用的 AFM 预设生成一张图；只在正式 ingest 提交成功后判断，不在 Inbox 识别时运行。自动化消费 **Dataset**：重放同一入库操作、同一 Dataset 重投不重复出图；复用已有 Source 但真正创建了新 Dataset 时也触发（用户已确认）。不开启历史全库补跑，但允许用户对 Library 中**单个已有 Dataset**手动触发自动出图（用已应用预设、遵守回执幂等）；不开启批量历史补跑，不因 Dataset 更正、预设更新、打开 Workbench 自动重画既有图。更正沿 K10 标 stale。
2. **预设与匹配**：首期一个 AFM 默认预设，默认关闭。保存/Apply 后才生效，包含 channel 选择规则、surface level、line flatten、zero reference 及 Heatmap 显示/scale bar/style 的实际参数；WorkBench 手动调参不反写预设。建议自动选有明确 Height 语义的唯一目标（包括用户显式选择的 trace/retrace 规则），缺失或不明确就跳过并报告，不默认把 Phase/未知通道当 Height。具体科研参数由用户在使用时设置，不硬编码、不替用户猜。预设与启用状态随当前 Library 保存；提供独立、用户可见可编辑的自动化预设入口，支持从 Workbench 当前配置生成预设，明确 Apply 后才生效（均已确认）。
3. **保存语义**：建议自动出图只 New Plot，一次自动意图至多成功发布一张；不复用人工 Save 的最近匹配替换推荐，不静默覆盖人工或已有图。人工仍可通过任务 6 的公共动作替换/删除自动图。删除后重复通知不得复活它。手动图和自动图都使用同一正式资产类型，需能辨认自动来源及实际预设；不复制资产权威。
4. **失败与控制**：导入成功不因自动处理失败而回滚；显示成功/跳过/失败及原因，失败可针对本次操作重试，避免静默跳过。建议关闭自动化、改已应用预设或切换 Library 后使旧未发布意图失效；已保存图不因此重写。是否需要退出/崩溃后补跑未完成意图属于设计选择：至少保留可识别的未完成状态与明确的恢复/重试方式，不扫描全库猜测哪些应当运行；不承诺常驻后台服务。

## 静态证据与待收敛设计

- `App/InboxArchiveApplyService.swift` 的 `applyV2` 已调用 `LibraryAssetService.ingestAsset` 并拿到 sourceID/datasetIDs/reusedSource，写入导入审计；返回的 InboxArchiveApplyResult 目前只给计数。设计须定位全部真正新 ready Dataset 的路径与成功后通知/可恢复交接点；不能把复用或回执重放误作新数据，不能让分析阻塞或回滚已完成归档。
- `Library/Assets/LibraryAssetService+Analysis.swift` 的 `loadDatasetForAnalysis` 返回 revision、通道、活跃归属、Source 可用性；`AFM/AFMPlotComputation.swift` 的 `run` 接受显式配置，严格选择 channel，返回 candidate。复用这些接口，不复用带 UI 状态的 WorkspaceStore。
- `AFM/AFMPlotCodec.swift` 与 `Library/Assets/LibraryAssetService+Plot.swift` 已实现正式内容与 publishPlot/updatePlot、operationID 请求校验、commitLock 及恢复；`Features/Workbench/AFMWorkspaceStore+FormalPlot.swift` 为人工调用者。设计须说明自动化如何复用同一服务，捕获真实 root/lease、Dataset revision、有效预设版本 ID 与启用状态，和提交串行复核；不能仅在计算开始时检查。manifest 当前未记录完整 globalPlotDefaults 或自动来源；只在确有需要时最小向后兼容补充并验证旧图仍可读，不预设格式迁移。
- 需证明重复事件/重试在重启前后不产生重复图；现有 operationID 绑定请求 hash，重新渲染或重取 savedAt 可能改变内容，不能只用固定 ID 假称幂等。设计明确稳定意图身份、输入/配置快照、已有回执查询或冻结请求重放、提交前复核及中断恢复；必要时用最小持久交接记录，不新增第二套资产库或通用任务引擎。若无足够证据复用已有机制，说明具体缺口并让用户选取最小方案。

## 验收

| ID | 必验内容 |
|---|---|
| AC1 | 默认关闭不出图；显式保存预设后启用，真实 Inbox → V2 标准化 → 自动执行 → 所属 Sample Plots 可读；两个独立 Dataset 分别产生正确成果；导入失败、非 AFM、V1、同一入库操作重放/同一 Dataset 重投不重复出图（复用 Source 产生的新 Dataset 会触发）；无 Workbench 页面也运行。 |
| AC2 | 同一标准矩阵/revision/实际科学与显示配置，自动与人工共用 Task 6 入口并取得相同矩阵、坐标、单位、诊断和对应显示结果。覆盖真实 IBW 副本、合成多通道/多 Dataset、缺失或歧义通道；显示配置变化不改科学数值，无 raw parser 调用。 |
| AC3 | 正式自动图重启可读，记录输入修订、实际配置与自动来源；图、矩阵、依赖与 Sample 归属一致。已有人工图不被覆盖；人工仍可按公共保存/打开/删除操作管理；Source、Dataset 和 Sample Result 不变。 |
| AC4 | 同一 ingest 的重复回执/事件/并发投递、保存回执丢失重试、重启与人工删除后的重投递均不产生重复图或复活成果；新独立输入不被误去重。计算或发布失败不撤销已成功导入，状态和重试结果可见；故障注入覆盖正式提交和设计选定的交接/恢复边界。 |
| AC5 | 确定性竞态：计算开始后 Dataset revision 变化/样品回收/Library 切换或丢失 lease/预设变更与禁用，旧候选不得越权或误发布；A→B→A 不绕过变更标记。已发布 Live 图的 stale/删除行为沿任务 6；损坏数据/配置 fail-closed，不吞错误。 |
| AC6 | 当前交付 HEAD 隔离桌面 GUI：实际设置/Apply/开关、导入、关闭 Workbench 页面运行、Library 看到图与失败反馈、重启读回；V1/其他 Workflow 既有行为不变。合成 fixture 与经授权真实 IBW 副本、自动化服务测试及全套 required actions；生产数据哈希不变。 |

## 开工

按已合并的 [design-7](design-7-afm-automation.md) §2–§5 和本 brief AC1–AC6 实施。独立审查与交付流程由 Deliver 管理，本文件不定义。实施中将以下已确认的合同落实为可验证代码，而不是重新设计：

- 入库事务中的可选意图与正式 Dataset 同时提交；重放只返回原持久化意图（包括原本为 nil 的旧记录），绝不以调用者新读到的配置补写。自动化只消费符合当前预设版本、输入修订和归属的 V2 Dataset。
- 预设版本用随机 `presetVersionID`；每次 Apply 或启用状态变化换新 ID。会话 ID 与当前 Library 写租约的获取、释放及切换在同一串行边界内更新，防止 A→B→A 后旧任务发布。恢复只为当前有效配置重新评估持久意图，不按时间截断，不额外记录删除日志。
- 恢复查询用 SQL 过滤可从现有资产/操作记录直接得到的条件（版本、ready/revision、归属关系、发布回执等），在后台执行；Sample 活跃及废纸篓状态以现有 sample.json 为权威，候选缩小后核查，不为 SQL 查询新增冗余持久字段。正式发布仍在现有提交边界复核全部必要条件。设计中的合成性能数字不是实测 Swift 性能。
- 保留自动图实际有效的科学和显示配置及自动来源，读回和导出使用保存值；旧图缺新字段仍可读。自动发布仅 New，人工删除后沿既有发布回执防止复活，先测试证明，不新增墓碑系统。显式单 Dataset 补跑仍遵守回执幂等。
- 已接受的限制：导入期间 Apply 可使原意图过期，用户可手动补跑；确定性跳过在重开时可再次报告；撤销回收后仍有效的未完成意图可以重新评估；不支持只回退预设文件而不回退数据库的非一致恢复。

实际功能与 AC1–AC6 验收完成后才勾选 Roadmap Task 7。按 AGENTS.md 完成代码测试、UI 规范及隔离 GUI 验收、required-actions 和正式版本收尾（当前 v6.10.0，普通新增用户能力预计 minor v6.11.0，无迁移授权）；本实施交接提交不 bump。若出现实质合同冲突、需要改变持久数据合同或无法完成验收，报告证据并保持 Draft，不擅自扩大范围或降低验收。不触碰真实 Library，不开始 Task 11/12。
