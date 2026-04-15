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
| 5.6.x | 预留 | — |
| 5.7.x | Docs 专项 | 收集中 |

---

## 5.0.x — 设计和规划

### 5.0.0
- [x] 建立知识积累系统（philosophy / features / known_issues / devlog）
- [x] 建立版本路线图

---

## 5.1.x — 跨区域技术债 + 基础设施

### 5.1.0 — Assessment + 低风险速清
- [ ] AppState 分解 scope assessment：清点 Library 域属性/方法、依赖图、迁移边界和顺序
- [ ] Workflow ID 别名硬编码消除：SearchWorkflowMeasurementsUseCase if-else → 数据驱动 `[来源: TECH_DEBT_BACKLOG]` `[~1h]`
- [ ] try? audit 剩余项：LibraryStore createDirectory 和 read paths `[来源: TECH_DEBT_EXECUTION_LOG Round E]`
- [ ] 废弃字段零使用确认（grep + 运行时验证，不删代码）：temperaturePattern/currentPattern/fieldPattern `[来源: TECH_DEBT_BACKLOG]`
- [ ] 旧 CodingKeys 发布周期确认：PendingImportConfirmationDraft + RoutePlan.status decode path
- [ ] 同步更新 TECH_DEBT_EXECUTION_LOG

### 5.1.1 — AppState 分解（主体）
- [ ] Library 域行为从 AppState 迁移到 LibraryFeatureStore `[来源: TECH_DEBT_BACKLOG]`
- [ ] 按 assessment 分步执行，每步独立验证
- [ ] 验收：CLAUDE.md temporary exceptions 的 Library 条目可缩减或移除

### 5.1.2 — 废弃代码清理 + 错误处理
- [ ] 废弃 condition pattern 字段移除（如 5.1.0 确认零使用） `[来源: TECH_DEBT_BACKLOG]`
- [ ] 旧 CodingKeys 迁移码清理（如发布周期条件满足） `[来源: TECH_DEBT_BACKLOG]`
- [ ] RoutePlan.status decode path 清理（同上条件）
- [ ] 错误处理体系统一审查（在 AppState 分解完成后做更准确）

### 5.1.3 — 测试基础设施
- [ ] 覆盖率基线建立
- [ ] 关键路径测试补全（优先补分解后的 FeatureStore 测试）

---

## 5.2.x — Import 管线 + Inbox 逻辑/架构

### 5.2.0
- [ ] condition_aliases.json 定位厘清 `[来源: TECH_DEBT_BACKLOG]`
- [ ] Override 加载逻辑去重（RuleLoader + ConditionRulesHandbookStore） `[来源: TECH_DEBT_BACKLOG]`
- [ ] Override 文件删除时静默复活问题 `[来源: TECH_DEBT_BACKLOG]`

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

---

## 5.4.x — Library 逻辑/架构

### 5.4.0
- [ ] P1: 删除 LibraryCommandCoordinator，折叠 LibraryFacade `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [ ] P2: 合并 LibraryMutationOrchestrator 到 LibrarySyncService，统一 diff 入口 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [ ] P3: 从 FeatureStore 提取 workbench/measurement 投影、日志管理、编辑状态 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [ ] P4: 简化 ViewModel，View 直接读 appState.library `[来源: LIBRARY_ARCHITECTURE_AUDIT]`
- [ ] P5: 拆分 LibraryView（1252行）为 4-5 个聚焦组件 `[来源: LIBRARY_ARCHITECTURE_AUDIT]`

---

## 5.5.x — 全区域 UI 统一优化

### 5.5.0
_(待收集)_

---

## 5.6.x — 预留

_(未分配)_

---

## 5.7.x — Docs 专项

### 5.7.0
- [ ] CLAUDE.md 瘦身：把稳定规则下沉到 specs，CLAUDE.md 只保留高频约束
