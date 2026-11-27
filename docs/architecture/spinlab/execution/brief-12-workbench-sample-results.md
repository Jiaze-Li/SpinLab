# 任务 12 — Workbench → Sample Result 显式赋值（AHE 首个消费者）

状态：初始 Design Draft。2026-11-27 用户授权开启 Task 12 设计；基线 main `79cd971a`（Task 7 #244 已合并，前置 Task 4 #225 已完成）。不授权功能实施。共同合同：[SKELETON](SKELETON.md) K1–K4、K8–K10、K12–K13；[Task 4 Result 合同](brief-4-parameters.md)、[执行包](README.md)。

## 用户要什么

在 AHE Workbench 中得到 Hc 或 R_AHE 后，不必手动复制数值到 Library。用户主动选择一个计算结果，明确目标 Sample 与已有 Result Definition，看到实际数值和单位（以及目标槽位原值、限定文字和必要的测量条件），确认后写入同一 Sample 当前值。手填和 Workbench 写入不是两种 Result；Library 仍只有一个当前值权威。以后 RT、3ω 等 workflow 按真实需求逐个接入。

## 已确认边界

- 首期只接入 AHE 已有 Hc、R_AHE 的有效计算结果，不新增提取算法、自动拟合、物理量表、单位体系或批量赋值。共享入口按可复用的数值候选与确认合同设计，不提前构建通用科研依赖图或为未接入的 workflow 搭空架子。
- 用户主动选目标 Definition、确认新值或覆盖旧值才写入；Analyze、Save Plot、Save Analysis、导入、重新计算、改控件均不能自动赋值。已确认 Result 是独立当前值；不因上游图、文件、算法或条件变化而过期、重算、清空。零是有效数值；无结果不能补零。取消不写。
- 复用 Task 4 的 Catalog 和 Sample Result 写入权威：`_spinlab/result_definitions.json` 只存定义；各 Sample 的正式 `sample.json.results` 只存当前值及既有校验信息。不得把当前值另外写进 SQLite、Registry/XLSX、numericTags、measurement_data.json 或分析 Pack，不反向修改 Source/Dataset/Plot/Sidecar；不引入结果历史或持久来源关系。
- 核对 V1/V2 的正式记录路由和 Task 3 单写者合同；首期从实际可用的 AHE 输入路径实现。当前 V2 标准数据消费者是 AFM，不能凭 Task 6/7 的完成宣称 AHE 已支持 V2 标准输入，不为此提前迁移所有运输数据。保持 V1 的 AHE Analyze/Plot/Pack 等原行为；V2 的 Sample Result 服务可独立验证；未适配的 AHE 路径不得绕过 V2 写保护或回退读取旧目录。真实库迁移属于 Task 11。

## 初始产品建议（待设计确认，非新增审批门槛）

- 在 AHE 已完成的结果区域提供“写入 Sample Result”动作；确认面板明确展示计算指标、输入测量/通道、样品和实际条件、候选值及单位，选择已有 Definition 并展示目标当前值。建议每次确认一个指标和槽位；没有 Definition 时提示去 Library 的 Result Definitions 创建，不自动创建，也不默选最相似名称。
- 优先支持来源可唯一确定的单次分析结果（同一 Sample 有多测量或多通道不等于单一结果）。多输入若已有真实可区分指标，则设计明确如何选；现有计算输出若已合并/覆盖而无法追溯具体来源，则拒绝含混赋值、引导用户单独 Analyze，不扩大为 AHE 算法重构。Sample 默认可推荐来源对应的唯一正式 Sample，但须明确显示并由用户确认；不静默跨 Sample 或凭 Batch/衬底/名称猜测。跨样品赋值是否有真实需求留为待决问题，不预建功能。
- Hc 的现有 canonical unit 为 T，R_AHE 为 Ω。目标 Definition 的单位、限定文字及实际测量条件必须可见；条件未知保留未知，不能把用户的限定文字当作已证实测量条件。设计确定已知同量纲换算的最小处理、不可解释单位及不匹配提示；不静默换算、重标单位或用无证据的文本匹配，用户看见拟写入的实际数值后明确确认。对于科研意义不匹配保留 Task 4 的人工最终判断，不代替用户制定实验物理规则。
- 已有 Hc/R_AHE 手动 override 与旧图/指标保存逻辑不同于 Sample Result 赋值。设计需明确原计算值与人工修正值如何标识、选择及确认，避免隐式使用尚未应用的编辑草稿；不自动触发旧 Plot/metric 保存。

## 静态代码证据与设计任务

1. `Library/LibraryResultService.swift` 已有唯一 Catalog 和 `setValue(sample:definitionID:newValue:expectedCurrent:now:rootURL:)`，重读 Catalog/正式 sample.json、校验 ID/有限值和 expectedCurrent，再写当前值；`App/SpinLabAppState+Results.swift` 暴露上下文与刷新索引；`Features/Library/SampleResultsSection.swift` 有手填/覆盖确认。核实这些接口在当前 V1/V2 的路由、单写许可与 stale 语义。现有 setValue 仅核对 Definition 存在和数值相等，不足以直接保证 Workbench 长时间打开确认窗口时的定义语义、会话、目标样品及状态未变；设计最小适配或增强共同服务，不新增第二写入权威。确认时复核正式目标、有效 Definition、旧值/必要的更新校验及当前 root/实际 lease；与相关写路径串行，过期拒绝并要求重新确认，不把索引缓存当权威，不擅自拓展到全局事务框架。
2. `Features/Workbench/AHEWorkspaceStore.swift` 的 `lastExtractedMetrics` 按 sampleKey 保存；`lastExtractedHc/RAHE` 使用 values.first（现有单样品 UI 便利属性），`buildActiveChartMetrics()` 产生 `PendingMetricEntry`（T/Ω、conditions、可选 override）；`AHESpecificPlotControls.swift` 有 pre-persist override。核对实际 `ExtractAHEMetricsUseCase` 的输入/输出、同 Sample 多次测量及多通道的覆盖/聚合语义、计算失败/取消/重算、旧 Pack restore。不得把 values.first、当前选中项或旧图缓存误当已确认候选；选择/结果变化时取消或重新确认旧草稿。候选绑定实际计算结果与输入，不从新的控件拼旧数值。
3. `Domain/WorkflowSearchModels.swift` 的旧 hit 使用 sampleKey/path；V2 `inputRef` 带稳定 Sample/Dataset ID；`UseCases/SearchWorkflowMeasurementsUseCase.swift` 当前标准 Dataset 查询仅 AFM。核实 V1 历史样品无 UID、同名/归属歧义时如何安全定位，V2 正式样品通过 UID/路径路由（`LibraryStore+Drawers.swift`）。不自动补发 UID、不从旧 key 盲猜，不为 Task 12 先迁移 AHE。复用现行身份和单写会话保护。
4. 输出设计说明：实际用户路径、候选契约（含科学语义）、最小读写适配与失效/权限边界、V1/V2 支持矩阵、明确的产品待决项及下列验收证据方案。优先使用已有组件和接口；技术选择在已确认范围内由执行者收敛，真正需要用户选择的产品/科研语义再提出推荐和影响。

## 验收（实施阶段；本 Design Draft 不宣称已运行）

| ID | 必验内容 |
|---|---|
| AC1 | 隔离 Library：已有 Hc、R_AHE Definition，实际 AHE Analyze → 选择一个有效计算指标 → 明确 Sample/Definition → 确认 → Library 对应槽位可见、重启仍在。两个指标分别赋值；手填与 Workbench 操作同一槽位，未填写/0 正确，其他样品和值不变。 |
| AC2 | 赋值数值与实际 AHE 输出一致（既有科研算法不变），核对单位与条件、可解释的换算和不匹配提示；缺失指标、非有限值、未知或多输入含混来源不得伪成功；人工 override、Pack 恢复、重复测量/多通道按设计明确选择或拒绝。 |
| AC3 | 未确认、取消、Analyze/重绘/Save Plot/Save Analysis 不写 Sample Result；旧值→新值可见，覆盖仅经一次明确确认；重试不重复产生其他副作用；写入后上游变更不自动修改当前值。Source/Dataset/Plot/旧 metric、Registry/XLSX、其他 Sample 字段无赋值副作用。 |
| AC4 | 过期确认（目标当前值变化、Definition 编辑/删除、分析/选择变化、Sample 回收/删除、Library 切换 A→B→A 或 lease 丢失）、损坏 Catalog/sample.json、写入失败、无权限均安全拒绝且反馈清楚；同一正常确认不覆盖新的人工值。复用现有服务及必要最小保护，故障/竞态测试可复查。 |
| AC5 | V1 正式 AHE 用户路径及旧手填/Plot/Pack/metric 回归；验证旧无 UID Sample 的受支持行为、不误选同名样品；V2 正式 Sample Result 读写与唯一权威不受损，未适配 AHE 输入清楚不可用，不静默写 V1 结构；不触碰旧库迁移。 |
| AC6 | 当前交付代码的隔离桌面 GUI：实际 AHE 输入、分析、赋值、旧→新确认、取消、错误反馈、Library 读回与重启；真实文件副本仅在已授权时使用，合成 fixture 可验证路径和故障场景。遵守 AGENTS、UI/controls、Code Map 与 required-actions；生产数据不变。 |

## 开工与范围

本 PR 只完成设计合同及必要源码核查；独立审查与交付由 Deliver 管理。未确定的科研/产品语义标为待决，可条件化的独立设计继续。设计收口合并后另开实施 PR；实施验收通过才勾选 Roadmap Task 12。无 Swift 实现、版本 bump、生产 Library 操作；不开始 Task 11 或 RT/3ω 接入，不混入 Cua 弹窗排查。
