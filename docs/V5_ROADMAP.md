# SpinLab 5.x Roadmap

> 版本号是分类标签，不是时间线。版本段之间可交叉推进。
> 每个版本段是收集箱——发现问题按分类归入，做的时候再排优先级。
> 具体迭代只在每个路线内部推进。

## 版本段索引

| 段 | 主题 | 状态 |
|---|---|---|
| 5.0.x | 设计和规划 | 进行中 |
| 5.1.x | 跨区域技术债 + 基础设施 | 收集中 |
| 5.2.x | Import 管线 + Inbox 逻辑/架构 | 收集中 |
| 5.3.x | Workbench 逻辑/架构 | 收集中 |
| 5.4.x | Library 逻辑/架构 | 收集中 |
| 5.5.x | 全区域 UI 统一优化 | 收集中 |
| 5.6.x | Sample 中心数据骨架 | 进行中 |
| 5.7.x | Docs 专项 | 进行中 |

---

## 5.0.x — 设计和规划

### 5.0.0
- [x] 建立知识积累系统（philosophy / features / known_issues / devlog）
- [x] 建立版本路线图

---

## 5.1.x — 跨区域技术债 + 基础设施

### 5.1.0 — Assessment + 低风险速清
- [x] AppState 分解 scope assessment：清点 Library 域属性/方法、依赖图、迁移边界和顺序
- [x] try? audit 剩余项：LibraryStore createDirectory 和 read paths `[来源: TECH_DEBT_EXECUTION_LOG Round E]`
- [x] 旧 CodingKeys 发布周期确认：PendingImportConfirmationDraft + RoutePlan.status decode path
- [x] 同步更新 TECH_DEBT_EXECUTION_LOG

### 5.1.1 — AppState 分解（主体）
- [x] LibraryFacade + LibraryCommandCoordinator 折叠进 LibraryFeatureStore
- [x] 13 个 AppState 转发方法删除，调用方迁移到 appState.library.xxx()
- [x] 选择代理属性迁移：4 个属性移入 LibraryFeatureStore，didSet 回调持久化
- [x] 验收：CLAUDE.md temporary exceptions 的 Library 条目已缩减，无 Library 域透传残留

### 5.1.2 — 废弃代码清理 + 错误处理
- [x] 旧 CodingKeys 迁移码清理（已在 5.1.0 完成：PendingImportConfirmationDraft + RoutePlan.status）
- [x] 错误处理体系统一审查：无新 violation，LibraryStore/XLSXSyncService 已有日志+fail-soft 模式，关键写入路径使用原子事务

### 5.1.3 — 测试基础设施
- [x] 覆盖率基线建立：506 tests, 1.98% line coverage (4.17% logic-only). Workbench render pipeline well-covered; App/State layer at 0%.
- [x] 关键路径测试补全（优先补分解后的 FeatureStore facade 方法，需 fixture 基础设施）

### 5.1.4 — Workflow alias 数据驱动 + FeatureStore 测试补全
- [x] Workflow ID alias 硬编码清理：SearchWorkflowMeasurementsUseCase if-else 链改为枚举 aliases computed property，统一 canonical 逻辑 `[来源: TECH_DEBT_BACKLOG]`
- [x] RegistryFeatureStore 关键路径测试：初始化、applyPresentation、状态清除（3 cases）
- [x] InboxFeatureStore 关键路径测试：初始化/选择、导入分发、apply 移除、workspace 裁剪、选择自动调整（15 cases）
- [x] 文档状态同步：TECH_DEBT_BACKLOG 完成度与 roadmap 对齐

### 5.1.5 — 规则管理统一 + 自动同步基础设施（历史已完成）
- [x] 2026-04-28 完成 s1–s12：规则分类与 schema 收敛、规则编辑界面、启动迁移与自动同步，相关回归测试已纳入当期收尾。
- **现行实现与规则**：从 [Inbox 规则维护架构](architecture/inbox/RULES_AUTHORING.md)、[路由管线](architecture/inbox/ROUTING_PIPELINE.md) 和实际源码定位；本节不再指导新开发。
- **历史证据**：当期分步实施记录见本地共享 `docs/history/v515_*.md`，本仓库的 Git/PR 历史保留原讨论；已完成的 handoff 不再作为执行需求。

### 5.1.6 — 架构梳理 + 索引文档（区块 / 层级 / 共享点）

- [x] 架构梳理 + 索引文档完成：218 个 Swift 文件完成区块 / 层级 / 共享点扫描，现行派发入口为 [architecture/INDEX.md](architecture/INDEX.md)，设计与实施摘要见 [history/v516_architecture_index.md](history/v516_architecture_index.md)。

### 5.1.7 — 规则产物可演化层（Rule Provenance + Sidecar v2 + Recompute）

- [x] 双层 sidecar（`ruleSnapshot` 可重算 / `userOverrides` 永不动）+ rule provenance + Recompute UI（stale banner + dry-run preview + condition edit + source tooltip）。设计纪要：[history/v517_rule_provenance.md](history/v517_rule_provenance.md)。

### 5.1.8 — Condition 统一规则列表（首条结构债清理）

- [x] Condition 不再 `unit_suffix` / `token_map` 二选一，统一为单一 `matches: [MapRule]` + schema v5→v6 一次性迁移；UI 删 segmented control，编辑器收敛到 `MatchRulesEditor`；`$MATCH` 输出锁定到 unit-suffix op（PR #61 Codex 评审守住）。设计与实施摘要：[history/v518_condition_unified_rules.md](history/v518_condition_unified_rules.md)。遗留 `NewRuleEntrySheet.RuleEntryKind` 死路径移交 5.1.9 收编。

### 5.1.9 — Measuring Condition 单位标准化 + NewRuleEntrySheet 死路径收编

- [x] Measuring Condition 单位标准化（标准单位 + 换算 + 精度清洗）+ NewRuleEntrySheet 死路径收编；v6→v7 schema 迁移；旧隐式归一化完全删除；47 tests 全绿。设计与实施摘要：[history/v519_condition_standardization.md](history/v519_condition_standardization.md)

### 5.1.10 — 架构合规审计多版本流水线规划

- [x] 5.1.11–5.1.14 多版本架构合规审计流水线规划入 ROADMAP（流水线总段 + 4 子段）+ TASK_BOARD（8 行进行中）；双 AI 协作收敛 14 条决策 + "不做"清单；AUDIT_PLAYBOOK 推迟到 5.1.11a 跑通后落地；纯文档零代码。设计与协作过程纪要：[history/v5110_audit_pipeline_planning.md](history/v5110_audit_pipeline_planning.md)

## 5.1.11–5.1.14 — 历史架构合规审计
- [x] Workbench、Inbox、Library 和跨区域的架构合规审计已开展，问题分类、修复与例外结论保存在对应历史记录中；个别按需溢出任务仍按下方原勾选状态记录。
- **现行资料**：[架构入口](architecture/INDEX.md)。历史审计方法可从该阶段的 Git/PR 记录回溯，不再是今天必须执行的周期性审查门禁。
- **历史证据**：本地共享 `docs/history/v5111*–v5114*.md`，对应 Git/PR。

### 5.1.11 — Workbench 边界合规审计 + 修复（架构审计流水线第 1 轮）

> 流水线起点。本版本同时承担"跑通方法 + 审 Workbench"双任务。

- [x] 5.1.11a 审计：按上述抽样策略 + 判定口径在 Workbench 区扫一轮；产出五段表；纯文档零代码（Drift 改 Code Map 注释除外）。44 样本；21 Violation / 8 Drift / 34 Accepted；§5 Fix-Round Draft 分 5 批。设计与审计纪要：[history/v5111a_workbench_audit.md](history/v5111a_workbench_audit.md)
- [x] 5.1.11a 收尾：从 battle-tested 方法落 `docs/architecture/AUDIT_PLAYBOOK.md`
- [x] 5.1.11b 修复：Renderer do-catch pipeline + Persistence fail-soft + Setter/View 副作用搬位（AS-18/19/21/32/35/36/38）
- [x] 5.1.11c/d 修复溢出：AHE metric + XY series order → UseCase；3ω physics models + PPMSParsedFile → Domain/；附加修复 NavigationSplitView columnVisibility。纪要：[history/v5111bcd_workbench_compliance_fixes.md](history/v5111bcd_workbench_compliance_fixes.md)

### 5.1.12 — Inbox 边界合规审计 + 修复（架构审计流水线第 2 轮）

> 套用 `AUDIT_PLAYBOOK.md`；针对 5.1.7-9 三轮重构后的 Inbox 区。

- [x] 5.1.12a 审计
- [x] 5.1.12b 修复
- [ ] 5.1.12c/d 修复溢出（按需启用）

### 5.1.13 — Library 边界合规审计 + 修复（架构审计流水线第 3 轮）

> 套用 `AUDIT_PLAYBOOK.md`；Library 相对稳定，预计违规密度低于 11/12。

- [x] 5.1.13a 审计 — 套 AUDIT_PLAYBOOK Library 5 层 29 条 AS-ID；Codex 综合评审 adopt-with-fixes；产出 9 V + 4 D + 16 A + 3 CR。设计与执行纪要：[history/v5113a_library_audit.md](history/v5113a_library_audit.md)
- [x] 5.1.13b 修复 — 8 V 全清 (C1–C8)；含 [high] V-003 applyBatch/All `try?` 收口 + V-009 抽 LibraryMeasurementDataPresenter；commit `a134b31`
- [x] 5.1.13c V-005 完整结案 + AS-19 收口 — 抽 LibraryRegistrySyncService (C9 Phase 2) + stale/override 全归 LibrarySidecarService (C10 Phase 3) + LibraryRegistryParser CoreXLSX try? Adj-10 (C11)；commit `ab0f9e5`。**5.1.13d 未启用**（V-005 已完整结案，无溢出修复需要）。设计与执行纪要：[history/v5113bc_library_compliance_fixes.md](history/v5113bc_library_compliance_fixes.md)

### 5.1.14 — 跨区 meta 修订（链级一致性 + 边界不清）

- [x] 5.1.14a 收敛：三根因收敛（DI 三档 + Domain 三 Tier + UseCase stateless）+ 17 INV 防回归不变式；定稿 handoff 第 3 稿。设计与执行纪要：[history/v5114_cross_region_meta_convergence.md](history/v5114_cross_region_meta_convergence.md)
- [x] 5.1.14b 落地：14b/14c/14d 三批 20 commit；DI 基础设施 + workspace 注入 + service 拆分 + Domain Tier 1/2 物理迁移；17 INV 全绿；244/244 coverage。**14c/d 溢出未触发**。

### 5.1.15 — God file 拆分（5 份 >1000 行 Swift 文件）✅ 2026-05-04 — B 节奏 3 轮全绿；5 文件共 6834 行 → 1+11ext/1+9ext/1+11ext/1+7ext/1+11ext+3类型；characterization tests 全绿；295/295 coverage。设计思路见 [history/v5115_godfile_split.md](history/v5115_godfile_split.md)。

- [x] Round 1 — RulesBootstrapper 拆分（Claude）：1203 行 → 1 主 + 7 extension + 1 verification model；characterization tests 覆盖 v1→v7 + s12 完整 migration 链
- [x] Round 1 — LibraryStore 拆分（Codex）：1112 行 → 1 主 + 9 extension；characterization tests 覆盖 ensureRoot / drawer CRUD / change log / measurement sets / backup
- [x] Round 2 — ThreeOmegaWorkspaceStore 拆分（Codex）：1534 行 → 1 主 + 11 extension；characterization tests 覆盖 runAnalysis / runScaling / pack restore / series order；trace commit point 不变式守护
- [x] Round 2 — LibraryFeatureStore 拆分（Claude）：1167 行 → 1 主 + 7 extension + 1 outcomes 文件；characterization tests 覆盖 dirty selection guard / facade callback 顺序 / sync review；严禁动 configureFacade 接口形态
- [x] Round 3 — SpinLabAppState 拆分（Claude 主拆 + Codex acceptance review）：1822 行 → 1 主 + 11 extension + 3 外提类型；characterization tests 覆盖 startup 顺序 / Apply pipeline / ContextProvider capture / duplicate guard / interaction snapshot

### 5.1.15h — 测试隔离 + 配置安全网（hotfix）✅ 2026-05-04 — LibrarySettingsStore 双 init（生产无参 + 测试 `init(settingsURL: URL)`）+ save() 写 `.backup` 显式 do/catch 安全网 + load() rootPath 不存在 warning + characterization 13 case 改 closure-based isolated fixture + 新增持久化隔离 regression test；测试前后 sha256 sentinel 一字不差；UI 路径 .backup 自动写入已生产验证。设计思路见 [history/v5115h_test_isolation.md](history/v5115h_test_isolation.md)。

- [x] 实施 + Codex 评审 adopt-with-fixes（5 must-fix 全并入），commit `4b6e052`

### 5.1.16 — 5.1.15 残债清扫（测试跟进 + Library 横幅假阳性）

- [x] A 包：4 项测试同步债跟进源码（G1 typed sampleID / G2 condition unification / G3 explicit selection action / G4 substrate short-code）—— history `v5116_test_sync_and_recompute_banner.md`
- [x] B 包：Library 蓝色横幅假阳性 — H/H2/H3 三阶段修复（口径与 Apply 按钮可点条件统一为 group0 only）—— 同 history

---

## 5.2.x — Import 管线 + Inbox 逻辑/架构

### 5.2.0
- [x] 废弃 condition pattern 字段清理：temperaturePattern/currentPattern/fieldPattern 从 ConditionRules struct 删除，保留 JSON decode 迁移；Canonicalizer 迁移码精简；Handbook save 不再写入废弃 key
- [x] condition_aliases.json 定位厘清：bundled 文件未被引用（运行时从 Library sidecar 加载），已删除
- [x] Override 文件删除时静默复活修复：ensureUserFileExists() 从读路径移除，仅在用户保存时调用
- [x] Override 加载逻辑去重（RuleLoader + ConditionRulesHandbookStore）`[来源: TECH_DEBT_BACKLOG]` — 提取 SeparatedOverrideReader 统一读取层，消除 5 个 override 文件的重复解析

---

## 5.3.x — Workbench 逻辑/架构

### 5.3.0
_(预留)_

### 5.3.3 — 通用 Multi-Tab 渲染状态框架
- [x] 引入 `TabRenderState`：per-tab 显示覆写（图例位置、标题/轴标签覆写、图例标签覆写）统一为一个值类型
- [x] 引入 `TabRenderOutput`：per-tab 渲染结果（PNG + layout + manifestPayload）统一缓存
- [x] Pipeline Input 桥接构造器：`TabRenderState` + 共享设置 → Input
- [x] 3ω store 状态重组：5 个散落字典 + 7 个散落 Data → `[Tab: TabRenderState]` + `[Tab: TabRenderOutput]`
- [x] XY store 状态重组：同上模式
- [x] AHE store 适配：单实例 `TabRenderState` + `TabRenderOutput`
- [x] [Bug] 3ω 批量重绘丢失 per-tab 覆写（#1）— 结构性消除：覆写存于 per-tab state，重绘时从对应 tab 读取
- [x] [Bug] Legend 热区不跟随覆写后标签宽度（#4）— 结构性消除：layout 和 label 覆写来自同一 tab state
- [x] [Bug] 3ω 重绘后 manifest 缓存过期（#7）— 修复：style 重绘保留现有 manifest，不覆盖为 nil

### 5.3.2 — Plot Render Pipeline 统一
- [x] 提取 WorkbenchRenderPipeline：三 workflow 共用一条出图管线
- [x] 原始轴列名由 pipeline 统一保留，manifest 不泄漏显示覆写
- [x] AHE 内联渲染逻辑迁移至 pipeline
- [x] 3ω / XY renderer `_render()` 改为调 pipeline

### 5.3.1 — Plot Shell 能力扩展
- [x] 绘图模式扩展：支持多种渲染模式（连线、散点、点线等），用户可选择 fit 数据的绘图模式
- [x] 图表右键菜单 Copy PNG：analyze 出图后可右键复制图片到剪贴板
- [x] 图表字号可调：title、x/y axis title、x/y tick label、legend 的 font size 可通过 Chart Style disclosure panel 选择
- [x] Tick 密度可调：Chart Style panel 内 x/y stepper 控制
- [x] 图表 title 取消加粗（当前硬编码 bold）
- [x] [XY Rotation] 可选辅助线：tickbox 控制在 x=180 处绘制灰色虚线
- [x] [Bug] x/y axis title 对齐修正：应居中于 tick 区域（画板），而非整个 plot 视图
- [x] [Bug] y axis title 缺少括号内容：XY y title 固定为 Rxx (Ω) / Rxy (Ω)，stacked/center 信息不再放在 y title
- [x] [XY Rotation] 默认 y title 修改：Rxy tab → "Rxy (Ω)"，Rxx tab → "Rxx (Ω)"
- [x] Legend 默认值动态化：legend 内容根据 input sample 动态生成，取代当前硬编码 → 移至 5.3.4

### 5.3.4 — Legend 维度自动推断 + 视觉一致性
- [x] LegendDimensionResolver：数据驱动优先级链（temperature > substrate=energy=pressure > thickness），支持数值容差、自定义 chain
- [x] WorkbenchPlotPayload 扩展：legendDimension + reverseSeriesForLegend 字段（Codable 向后兼容）
- [x] Pipeline 统一 series 反转：stacked tab opt-in，非 stacked 不受影响
- [x] 删除 ThreeOmegaPlotRenderer / XYRotationPlotRenderer 分散的 .reversed()
- [x] 测试：16 cases 覆盖 resolver + pipeline + backward decode

### 5.3.5 — 数据点标签可调（字号 + 显隐）+ Copy PNG 分辨率档位
- [x] 全图点标签字号统一可调：点击图里任一点标签弹出已有 title/legend 那套字号选项面板（复用 `WorkbenchPlotCanvas` 的 editFontSizeKey + onFontSizeChange 通道，新增一个 key）；改动同步影响所有图的点标签
- [x] 点击数据点切换该点的标签显隐：复用现有 hit-test 机制扩展数据点命中；记录用结果中的位置 index，不绑温度（保持通用，未来其他场景也能用）
- [x] 持久化复用现有 Update Analysis：把"隐藏的点列表 + 标签字号"塞进现有 ThreeOmega Scaling pack 配置字段，Load Analysis 时按既有重画路径恢复，不新增存储入口
- [x] 触发范围：先 3ω Scaling Law（当前唯一使用点标签的 tab），其他 workflow 后续接入零成本
- [x] Copy PNG 分辨率档位 shell：右键菜单原 "Copy PNG" 拆为子菜单 "Copy PNG 1x / 2x / 3x"。1x = 渲染器原始像素（基线），2x = 当前默认（与 5.3.4 行为一致），3x 新增。机制做成通用倍率参数（scale factor 接到既有 PNG 输出管道一处入口），未来加 4x/任意倍率零改动；默认仍 2x，菜单不破坏既有快捷路径

### 5.3.6 — Plot Shell 曲线拖拽排序 _(已完成 2026-04-27)_
- [x] Shell 级能力：曲线拖拽排序属于通用 `WorkbenchPlotCanvas` / render pipeline 能力，不做成 3ω 或 XY Rotation 私有交互；workflow 只提供稳定 series identity 和当前结果数据
- [x] 唯一排序真相：每个可排序图维护一个 `seriesOrder`，语义固定为 bottom → top；初始值由 workflow 默认顺序生成（当前 stacked 图为温度升序），用户拖动后该数组成为唯一排序源，不再同时维护”温度排序”和”手动排序”
- [x] 拖动判定规则：用户拖动线条后，shell 根据每条曲线在 x=0 的截距判定上下位置；释放时以拖动后的截距位置重排 `seriesOrder`
- [x] Legend 跟随曲线顺序：legend 不保存独立顺序；渲染仍按 bottom → top 构建曲线，pipeline 统一投影成 legend top = visual top
- [x] 持久化：Save Analysis / Load Analysis / Pack restore 必须保存并恢复 `seriesOrder`；重新 Analyze 时先按已有 series identity 对齐旧顺序，新增曲线按 workflow 默认顺序补入，消失曲线剔除
- [x] 适用范围：先接入已有 stacked curve 图，机制必须保留为 shell 能力，后续 workflow 接入只需暴露稳定 series identity 与 opt-in 能力

### 5.3.7 — _(范围并入 5.3.6，2026-04-27)_

原计划将曲线身份存储从 5.3.6 拆分为独立版本，Jack 决策合并执行。
历史实施方案见 [归档交接](handoff/archive/2026-04-27-5.3.6-series-identity-storage.md)。

---

## 5.4.x — Library 逻辑/架构

### 5.4.0
- [x] P1: 删除 LibraryCommandCoordinator，折叠 LibraryFacade `[来源: LIBRARY_ARCHITECTURE_AUDIT]` _(已在 5.1.1 完成)_
- [x] P2: 合并 LibraryMutationOrchestrator 到 LibrarySyncService，统一 diff 入口 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [x] P3: 从 FeatureStore 提取 workbench/measurement 投影、日志管理、编辑状态 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [x] P4: 简化 ViewModel，View 直接读 appState.library `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [x] P5: 拆分 LibraryView（1252行）为 4-5 个聚焦组件 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`

### 5.4.2 — Typed Sidecar Reader Result ✅ 2026-08-10 — sidecar 读取失败原因从统一 nil 改为三分类 typed Result（损坏 JSON / schema 不匹配 / 其他），核心读取点 + 6 个调用点（bulk reader、enumeration、recompute、stale count、条件与工作流覆写写回、3ω RT 选择恢复）全部改用可区分结果；bulk reader / recompute 的失败日志附上具体分类原因；新增 4 个针对三分类的单测 + 更新既有测试替身；2885/2885 测试全绿；desktop rebuild 已验证。设计思路见 [history/v542_typed_sidecar_result.md](history/v542_typed_sidecar_result.md)。

---

## 5.5.x — 全区域 UI 统一优化

### 5.5.0 — 跨区域一致性 + 设计基础设施
- [x] 字体可读性违规修复：9 处 `.footnote` 用于用户需读内容（Inbox 5 处、Library 1 处、Workbench 3 处），提升至 `.callout`+；3ω 缩放结果 alpha/beta/R² 从 `.caption` 提升
- [x] 折叠区块点击热区修复：Inbox/Library 的折叠箭头改为整行可点（对齐 features.md Disclosure Sections 规则）
- [x] 提取统一折叠区块组件：替代三区域各自的手动 chevron+HStack 实现
- [x] 统一字体梯度：提取 app 级字体常量，替代三区域各自内联/局部定义的标题字号
- [x] 统一间距常量：建立 AppSpacing 七级梯度，关键结构位置已替换，规则已记录
- [x] 按钮风格上下文统一：审查确认三区域已一致，四级规则（prominent/bordered/borderless/plain）已记录

### 5.5.1 — 大文件拆分
- [x] InboxView（~1250行）拆分：1237→64行 + 5 个独立文件
- [x] LibraryDetailSections（~990行）拆分：删除原文件，拆为 5 个聚焦组件
- [x] RulesHandbookView（~1072行）拆分：1072→764行 + 4 个独立文件
- [x] WorkbenchSharedComponents（~940行）拆分：897→10行（索引注释）+ 8 个独立文件

### 5.5.2 — 共享组件补全
- [x] Flow/Wrap 布局去重：FlowLayout 合并到 UI/FlowLayout.swift，删除 WorkflowRegistryView 中的重复实现
- [x] 纯图标按钮补 accessibilityLabel：13 处跨 7 个文件
- [x] 状态指示颜色冗余：审查确认现有实现已有文字/图标冗余，无需额外改动
- [x] MetadataViews 审查：MetadataValueRow 已被 22 处采用，无明显重复需合并
- [ ] 行/列表选中态统一：Inbox 用 List、Library/Workbench 用自定义卡片，选中态视觉和信息密度对齐（留待 UX 需求驱动）

### 5.5.3 — 文档补齐 + CLAUDE.md 瘦身
- [x] 创建 specs/04_UI_RULES.md：字体/间距/按钮/折叠/无障碍视觉规则
- [x] 创建 specs/06_PROJECT_ARCHITECTURE.md：代码放置、模块架构、管线、检查清单
- [x] 历史阶段曾将 SpinLab 专有内容下沉到 specs；当前工程规则已统一到 `AGENTS.md`（#199），`CLAUDE.md` 为兼容入口。


---

## 5.6.x — Sample 中心数据骨架

> 需求、数据骨架和每个任务怎么走见 [`architecture/spinlab/execution/`](architecture/spinlab/execution/README.md)。这里只记顺序和状态；任务合并时在同一个 PR 里勾选并写上 PR 编号。

### 5.6.0 — 样品编号与数据安全
- [ ] 任务 1：新建样品，编号永久不变（PR #194）→ [`brief-1`](architecture/spinlab/execution/brief-1-create-sample.md)
- [ ] 任务 2：Registry 少一行不再删样品，删除暂时关闭（PR #195，前置：任务 1）→ [`brief-2`](architecture/spinlab/execution/brief-2-safety-guard.md)
- [ ] 任务 3：同一个 Library 只允许一个 SpinLab 可写 → [`brief-3`](architecture/spinlab/execution/brief-3-single-writer.md)

### 5.6.1 — 手填参数
- [ ] 任务 4：手填参数，确认后直接覆盖（前置：任务 1）→ [`brief-4`](architecture/spinlab/execution/brief-4-parameters.md)

### 5.6.2 — AFM 标准数据与自动出图
- [ ] 任务 5：AFM 文件入库成标准数据，引入链接表（前置：任务 1；需求待写）
- [ ] 任务 6：AFM 处理与出图改读标准数据（前置：任务 5；需求待写）
- [ ] 任务 7：AFM 自动出图（前置：任务 6；需求待写）

---

## 5.7.x — Docs 专项

### 5.7.0 — 历史文档收敛
- [x] 历史性 `CLAUDE.md` 瘦身已完成；现行公共 Agent 规则由 [AGENTS.md](../AGENTS.md) 维护，`CLAUDE.md` 仅引用它（PR #199）。

### 5.7.1 — TASK_BOARD 与技术债记录
- [x] 形成共享 `docs/TASK_BOARD.md` 入口；现在由共享看板唯一维护技术债生命周期，短期交接遵循 [handoff 规则](handoff/README.md)。历史实施见 `docs/history/v571_task_board.md`。

### 5.7.2 — 文档按模块归属
- [x] 按 Inbox / Library / Workbench 功能区整理架构文档；当年的 Code Map 数量属历史数据，当前范围以 [架构索引](architecture/INDEX.md) 和校验脚本为准。历史实施见 `docs/history/v572_s3_workbench_architecture.md`。

### 5.7.3 — Swift Code Map 登记与 Hook（历史已完成）
- [x] 当期完成 Code Map 登记、脚本和本地 hook 相关工作；设计及验收过程保留在共享 `docs/history/v573_swift_code_registration.md` 与 Git 历史中。
- **当前权威**：[AGENTS.md](../AGENTS.md) 的「Adding Swift code」与 [架构入口](architecture/INDEX.md)；`CLAUDE.md` 仅作为入口指向 `AGENTS.md`。
- **当前校验边界**：`scripts/verify_architecture_code_coverage.sh` 仅覆盖 Workbench Feature Swift 文件（见 `AGENTS.md`）；旧文档中的「218/218 全仓覆盖」及旧 CLAUDE.md SOP 是历史状态，不再作为现行要求。
