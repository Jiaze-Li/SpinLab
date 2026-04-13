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

### 5.3.1 — Plot Shell 能力扩展
- [ ] 绘图模式扩展：支持多种渲染模式（连线、散点、点线等），用户可选择 fit 数据的绘图模式
- [ ] 图表右键菜单 Copy PNG：analyze 出图后可右键复制图片到剪贴板
- [ ] 图表字号可调：title、x/y axis title、x/y tick label、legend 的 font size 可通过右键或点击交互选择（当前硬编码）
- [ ] Tick 密度可调：点击 tick 区域可选择 x/y 轴 tick 密度
- [ ] 图表 title 取消加粗（当前硬编码 bold）
- [ ] [XY Rotation] 可选辅助线：tickbox 控制在 x=180 处绘制灰色虚线
- [ ] [Bug] x/y axis title 对齐修正：应居中于 tick 区域（画板），而非整个 plot 视图
- [ ] [Bug] y axis title 缺少括号内容：stacked 模式下 y title 应显示完整标注（含括号内的 "stacked" 等信息）
- [ ] [XY Rotation] 默认 y title 修改：Rxy tab → "Rxy (Ω)"，Rxx tab → "Rxx (Ω)"（当前 Rxy tab 显示为 "Rxy − R_AHE (Ω, stacked)"）
- [ ] Legend 默认值动态化：legend 内容根据 input sample 动态生成，取代当前硬编码（具体规则待定）

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
