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

### 5.1.0
- [ ] 各大项开始前做 scope assessment（属性数量、调用点、迁移策略）
- [ ] AppState 分解：Library 域行为迁移到 LibraryFeatureStore `[来源: TECH_DEBT_BACKLOG]`
- [ ] Workflow ID 别名硬编码消除：SearchWorkflowMeasurementsUseCase if-else → 数据驱动 `[来源: TECH_DEBT_BACKLOG]`
- [ ] 废弃 condition pattern 字段移除（temperaturePattern/currentPattern/fieldPattern） `[来源: TECH_DEBT_BACKLOG]`
- [ ] 旧 CodingKeys 迁移码清理（PendingImportConfirmationDraft） `[来源: TECH_DEBT_BACKLOG]`
- [ ] 错误处理体系统一审查
- [ ] 测试基础设施：覆盖率基线、关键路径测试补全

---

## 5.2.x — Import 管线 + Inbox 逻辑/架构

### 5.2.0
- [ ] condition_aliases.json 定位厘清 `[来源: TECH_DEBT_BACKLOG]`
- [ ] Override 加载逻辑去重（RuleLoader + ConditionRulesHandbookStore） `[来源: TECH_DEBT_BACKLOG]`
- [ ] Override 文件删除时静默复活问题 `[来源: TECH_DEBT_BACKLOG]`

---

## 5.3.x — Workbench 逻辑/架构

### 5.3.0
_(待收集)_

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
