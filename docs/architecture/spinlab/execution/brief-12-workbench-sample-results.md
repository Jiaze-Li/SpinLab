# 任务 12 — Workbench → Sample Result 显式赋值（AHE 首个消费者）

状态：设计 PR #245 已合并（最终设计 HEAD `a2b668ec`，正式 Review Bot READY、无发现）；2026-11-27 用户授权开启独立实施 Draft PR。基线 main `d34a3b3c`，Task 4 #225 与 Task 7 #244 已完成。共同合同：[SKELETON](SKELETON.md) K1–K4、K8–K10、K12–K13；[Task 4 Result 合同](brief-4-parameters.md)、[执行包](README.md)。

设计权威：[design-12](design-12-workbench-sample-results.md) §2–§8，连同[用户确认 P1–P4 及实施取舍](https://github.com/Jiaze-Li/SpinLab/pull/245#issuecomment-7219866165)（后者补充最终设计未同步入正文的 Oe、SI 前缀及换库取舍）。[最终 READY 裁决](https://github.com/Jiaze-Li/SpinLab/pull/245#issuecomment-7219875929)仅代表设计 PR 的静态审查通过，不代替实施验收。实施不重新讨论已确认产品决定。

## 用户要什么

在 AHE Workbench 中得到 Hc 或 R_AHE 后，不必手动复制数值到 Library。用户主动选择一个计算结果，明确目标 Sample 与已有 Result Definition，看到实际数值和单位（以及目标槽位原值、限定文字和必要的测量条件），确认后写入同一 Sample 当前值。手填和 Workbench 写入不是两种 Result；Library 仍只有一个当前值权威。以后 RT、3ω 等 workflow 按真实需求逐个接入。

## 已确认边界

- 首期只接入 AHE 已有 Hc、R_AHE 的有效计算结果，不新增提取算法、自动拟合、物理量表、单位体系或批量赋值。共享入口按可复用的数值候选与确认合同设计，不提前构建通用科研依赖图或为未接入的 workflow 搭空架子。
- 用户主动选目标 Definition、确认新值或覆盖旧值才写入；Analyze、Save Plot、Save Analysis、导入、重新计算、改控件均不能自动赋值。已确认 Result 是独立当前值；不因上游图、文件、算法或条件变化而过期、重算、清空。零是有效数值；无结果不能补零。取消不写。
- 复用 Task 4 的 Catalog 和 Sample Result 写入权威：`_spinlab/result_definitions.json` 只存定义；各 Sample 的正式 `sample.json.results` 只存当前值及既有校验信息。不得把当前值另外写进 SQLite、Registry/XLSX、numericTags、measurement_data.json 或分析 Pack，不反向修改 Source/Dataset/Plot/Sidecar；不引入结果历史或持久来源关系。
- 核对 V1/V2 的正式记录路由和 Task 3 单写者合同；首期从实际可用的 AHE 输入路径实现。当前 V2 标准数据消费者是 AFM，不能凭 Task 6/7 的完成宣称 AHE 已支持 V2 标准输入，不为此提前迁移所有运输数据。保持 V1 的 AHE Analyze/Plot/Pack 等原行为；V2 的 Sample Result 服务可独立验证；未适配的 AHE 路径不得绕过 V2 写保护或回退读取旧目录。真实库迁移属于 Task 11。

## 已确认产品决定与实施补充

- **P1：只写来源 Sample。** 在 AHE 已完成的结果区域提供显式赋值动作，单次确认一个指标与一个已有 Definition；来源 Sample 只读展示，不自动创建 Definition 或默选相似名称。面板显示实际输入文件/通道/条件、计算值/单位、目标 Definition 名称/单位/限定文字、原值→拟写入值。无合法目标或取消时不写。
- **P2：首期不支持同一 Sample 多条有效曲线。** 提示单独 Analyze；按实际出数的最终序列判断，不按 selection 数猜。用该序列的稳定来源身份（实际文件、hit 和通道/series identity）反查唯一输入，条件、归属与数值必须来自同一条序列；无法唯一识别、点数不足或非有限结果拒绝。不得将提取器的不足点数占位零当有效结果，不改既有 AHE 科研算法。
- **P3：单位一致或已知兼容才可赋值。** 复用已有单位能力（T/mT/µT 与 Ω/mΩ/µΩ/kΩ/MΩ；核实现有 AHE Oe↔T 约定并优先复用，明确它属于现有磁场轴约定，不外推到其它物理量）。SI 前缀大小写敏感（mΩ 与 MΩ 不同）；只规范化明确等价别名，换算结果也须有限。面板展示原值和实际换算值，用户确认才写；空单位、未知或不兼容拒绝，仍可 Library 手填。不扩展通用单位框架。限定文字与实际条件并列展示，不擅自断言物理意义一致。
- **P4：不新增 override Apply。** 用户在最终面板明确选择当次运行的计算值或有限人工修正值，旧运行草稿不得变成新候选；Pack 恢复/重算开始、失败、取消及来源变化时失效，遵守已合并设计。赋值不触发旧指标或 Plot 保存。
- **换库优先级低。** 保留现有 root/写租约/面板 `sessionID` 校验；若在分析生命周期中捕获现有 sessionID 即可防止旧结果被新会话消费，直接复用并定向测试。若需要明显跨模块改造，则用现有清除或拒绝路径，暂不支持换库后继续使用旧分析结果，说明限制；不新增生命周期框架或状态机，绝不允许跨库错写。
- **最小安全保护**：复用唯一写入服务，确认时读磁盘核对明确 V1 布局（损坏/混合/未知不是 V1）、目标身份与活跃状态、完整所见 Definition 语义、预期旧值和实际持有的写租约；保证检查和写入不可交错，优先复用已有串行边界。旧有手填与 V2 Result 不回归。重复确认不得额外提交，即使新旧数值恰好相同；不为此新建持久历史系统。

## 静态代码证据与实施核查重点

1. `Library/LibraryResultService.swift` 已有唯一 Catalog 和 `setValue(sample:definitionID:newValue:expectedCurrent:now:rootURL:)`，重读 Catalog/正式 sample.json、校验 ID/有限值和 expectedCurrent，再写当前值；`App/SpinLabAppState+Results.swift` 暴露上下文与刷新索引；`Features/Library/SampleResultsSection.swift` 有手填/覆盖确认。核实这些接口在当前 V1/V2 的路由、单写许可与 stale 语义。现有 setValue 仅核对 Definition 存在和数值相等，不足以直接保证 Workbench 长时间打开确认窗口时的定义语义、会话、目标样品及状态未变；设计最小适配或增强共同服务，不新增第二写入权威。确认时复核正式目标、有效 Definition、旧值/必要的更新校验及当前 root/实际 lease；与相关写路径串行，过期拒绝并要求重新确认，不把索引缓存当权威，不擅自拓展到全局事务框架。
2. `Features/Workbench/AHEWorkspaceStore.swift` 的 `lastExtractedMetrics` 按 sampleKey 保存；`lastExtractedHc/RAHE` 使用 values.first（现有单样品 UI 便利属性），`buildActiveChartMetrics()` 产生 `PendingMetricEntry`（T/Ω、conditions、可选 override）；`AHESpecificPlotControls.swift` 有 pre-persist override。核对实际 `ExtractAHEMetricsUseCase` 的输入/输出、同 Sample 多次测量及多通道的覆盖/聚合语义、计算失败/取消/重算、旧 Pack restore。不得把 values.first、当前选中项或旧图缓存误当已确认候选；选择/结果变化时取消或重新确认旧草稿。候选绑定实际计算结果与输入，不从新的控件拼旧数值。
3. `Domain/WorkflowSearchModels.swift` 的旧 hit 使用 sampleKey/path；V2 `inputRef` 带稳定 Sample/Dataset ID；`UseCases/SearchWorkflowMeasurementsUseCase.swift` 当前标准 Dataset 查询仅 AFM。核实 V1 历史样品无 UID、同名/归属歧义时如何安全定位，V2 正式样品通过 UID/路径路由（`LibraryStore+Drawers.swift`）。不自动补发 UID、不从旧 key 盲猜，不为 Task 12 先迁移 AHE。复用现行身份和单写会话保护。
4. 按已合并设计及上述用户确认补充落实用户路径、候选契约、写入适配、失效与权限边界、V1/V2 支持矩阵及 AC。技术细节在授权范围内由执行者收敛；只有实质合同冲突或真正新的产品/科研取舍才需要用户决定。

## 验收（实施阶段，须提供真实证据）

| ID | 必验内容 |
|---|---|
| AC1 | 隔离 Library：已有 Hc、R_AHE Definition，实际 AHE Analyze → 选择一个有效计算指标 → 明确 Sample/Definition → 确认 → Library 对应槽位可见、重启仍在。两个指标分别赋值；手填与 Workbench 操作同一槽位，未填写/0 正确，其他样品和值不变。 |
| AC2 | 赋值数值与实际 AHE 输出一致（既有科研算法不变），核对单位与条件、可解释的换算和不匹配提示；缺失指标、非有限值、未知或多输入含混来源不得伪成功；人工 override、Pack 恢复、重复测量/多通道按设计明确选择或拒绝。 |
| AC3 | 未确认、取消、Analyze/重绘/Save Plot/Save Analysis 不写 Sample Result；旧值→新值可见，覆盖仅经一次明确确认；重试不重复产生其他副作用；写入后上游变更不自动修改当前值。Source/Dataset/Plot/旧 metric、Registry/XLSX、其他 Sample 字段无赋值副作用。区分赋值的无副作用与旧 Save Plot/Save Analysis 原有的正常持久化；保留旧行为，不要求旧保存动作不写其自身资产。 |
| AC4 | 过期确认（目标当前值变化、Definition 编辑/删除、分析/选择变化、Sample 回收/删除、Library 切换 A→B→A 或 lease 丢失）、损坏 Catalog/sample.json、写入失败、无权限均安全拒绝且反馈清楚；同一正常确认不覆盖新的人工值。复用现有服务及必要最小保护，故障/竞态测试可复查。 |
| AC5 | V1 正式 AHE 用户路径及旧手填/Plot/Pack/metric 回归；验证旧无 UID Sample 的受支持行为、不误选同名样品；V2 正式 Sample Result 读写与唯一权威不受损，未适配 AHE 输入清楚不可用，不静默写 V1 结构；不触碰旧库迁移。 |
| AC6 | 当前交付代码的隔离桌面 GUI：实际 AHE 输入、分析、赋值、旧→新确认、取消、错误反馈、Library 读回与重启；真实文件副本仅在已授权时使用，合成 fixture 可验证路径和故障场景。遵守 AGENTS、UI/controls、Code Map 与 required-actions；生产数据不变。 |

## 开工与范围

本 PR 实现已合并 Task 12 设计，完成 AC1–AC6 和既有行为回归。独立审查、检查与交付由 Deliver 管理。先完成候选/单位与来源绑定、共同写入保护的定向测试，再接入确认面板、跑端到端与隔离 GUI；中间批次不是停顿审批点。真实 AHE 文件仅在已经明确授权时使用副本；否则继续所有合成夹具可完成的工作，不擅自访问生产数据。当前 AppVersion v6.11.0，新增用户能力预计 minor v6.12.0；正式交付按 AGENTS.md 的版本/required-actions 规则收尾，实际实现及验收完成才勾选 Roadmap Task 12。保持 Draft 待人工验收，不自动 Ready 或 merge。不得操作真实 Library，不开始 Task 11、RT/3ω 或 Cua 弹窗改造。若遇到实质合同冲突或真实阻塞，明确证据和剩余工作，继续独立可做的任务，不降验收、不扩大架构。
