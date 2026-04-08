# SpinLab V4 总路线图

状态：进行中
更新：2026-04-07（4.1.4 完成，Scaling 完整流程验收通过）

---

## 版本语义

```
4.0     = 架构 / scaffold 阶段
4.x     = 一个完整的新 workflow（minor 编号 = workflow 序号）
4.x.y   = 该 workflow 内部的迭代步骤（patch = 推进节奏）
```

## 总览

```
4.0  ✅  架构 & 脚手架（AMR/PHE 延续 + 3ω 全部文件就位，swift build 通过）
4.1  🔲  3ω AHE workflow（4.1.0–4.1.8）
4.2  🔲  XY Rotation workflow
4.3  🔲  RT workflow
4.4  🔲  MR workflow
```

---

## 4.0 ✅ — 架构 & 脚手架（已完成，2026-04-05）

所有 3ω AHE 文件骨架到位，Domain enum 注册，WorkflowRegistry / WorkspaceRegistry 接入，编译通过。
详见 `V4_0_3W_AHE_ITERATION_PLAN_2026-04-05.md` §Architecture。

---

## 4.1 — 3ω AHE Workflow

### 进度

```
4.1.0 ✅  Scaffold — 所有文件已创建，编译通过
4.1.1 ✅  LVM Parser 真实文件验证 + 单元测试完整化
4.1.2 ✅  FitUseCase 验证 + 第一次真实数据可视化 (Tabs 1–2)
4.1.3 ✅  V^(3ω)_AHE 提取方法决策 + Tabs 3–5
4.1.4 ✅  Fig 5b Scaling 完整流程 (Tab 6)
4.1.5 ✅  Import/Inbox 集成 — LVM 文件入库
4.1.6 ✅  多角度支持 (30deg / 60deg) + 健壮性
4.1.6.1 ✅ 3ω Workbench 增强（title template, V3 method, RT fix, persist fix）
4.1.7 ✅  验收测试 + 文档
4.1.8 🔲  3ω 图表/指标持久化到 Library
```

---

### 4.1.0 ✅ — Scaffold（已完成，2026-04-05）

**目标：** 所有文件骨架到位，编译通过，无任何运行时路径。

**已完成：**
- `ThreeOmegaIngestionContracts.swift` — 所有 value type 数据合约
- `ThreeOmegaLVMParser.swift` — LVM header 解析 + I_rms 推导逻辑
- `ThreeOmegaFitUseCase.swift` — centering / RAHE / Hc 公式实现
- `ThreeOmegaScalingUseCase.swift` — Fig 5b 公式实现 + OLS 拟合
- `ThreeOmegaPlotRenderer.swift` — 6 个 tab 的 WorkbenchPlotPayload 构建
- `ThreeOmegaWorkspaceStore.swift` — @MainActor @Observable 状态机
- `ThreeOmegaWorkspaceView.swift` — SwiftUI 双栏 UI
- `IngestThreeOmegaSelectionsUseCase.swift` — 多文件编排
- `ExtensionPoints.swift` — 4 个 ThreeOmegaAHE* extension struct 注册
- `WorkflowRegistry.swift` — bundle 已注册
- `WorkflowWorkspaceRegistry.swift` — "3W" case 已启用
- `Domain/Models.swift` — `WorkflowKind.threeOmegaAHE` / `MeasurementType.threeOmegaAHE`
- `V400ThreeOmegaTests.swift` — 单元测试骨架（~465 行，编译通过）
- `swift build` — ✅ Build complete

**遗留问题：**
- 单元测试覆盖了合约 / FitUseCase / ScalingUseCase，但尚未针对真实 LVM 文件验证
- WorkspaceStore 中 `runAnalysis()` 里的 `ThreeOmegaGeometry()` default 永远不完整（geometry check 永远跳过）

---

### 4.1.1 ✅ — LVM Parser 验证 + 单元测试补全（已完成，2026-04-05）

**目标：** 用真实 `20260327_STO111_PN69/0deg/` 文件验证解析器正确性；补齐缺失的单元测试。

**验收条件（全部通过）：**
- [x] 在 swift test 中运行 `V400ThreeOmegaTests`，274 个测试全绿
- [x] `ThreeOmegaLVMParser` 真实文件 round-trip 测试（fixture 放 `Tests/SpinLabAppTests/TestData/ThreeOmega/`）
    - `3w_0deg_T_4.999 K_Iac_0.001000 A.lvm` — 25 数据行（从真实 5K field-sweep 裁剪）
    - `RT_0deg_H_-0.029814 Oe_Iac_0.000200 A.lvm` — 30 数据行（5K→295K RT 曲线）
- [x] `iRms` 与 filename `Iac_0.001000 A` → `0.001/√2` 误差 < 1e-6
- [x] `fileKind == .rtSweep` + `temperatureK.isNaN`（RT 文件无 Tableau: marker）

**已修复的真实数据 bug：**
1. **RT 文件无 `Tableau:` marker** — parser 增加 fallback（找第一行 `Double(col[0])` 可解析的行）
2. **多 RT 文件（1 行 + 30 行）** — `IngestThreeOmegaSelectionsUseCase` 现在收集所有 RT 文件，取行数最多的一个

**4.1.2 前置工作（一并完成）：**
- `ThreeOmegaPlotRenderer` 所有 render 方法返回 `(Data?, WorkbenchPlotLayout?)` 元组
- `ThreeOmegaWorkspaceStore` 新增 per-tab layout 存储 + 5 个交互回调
- `ThreeOmegaWorkspaceView` 完全重构（参照 AHE 模板，含 PlotControlsPanel / GeometryPanel / 全交互 WorkbenchPlotCanvas）
- `swift build` ✅ 通过

---

### 4.1.2 ✅ — Tabs 1–2 真实数据可视化 + 交互模式（已完成，2026-04-06）

**目标：** 在 App 内跑通 Analyze → Tab 1 (R¹ω vs H) + Tab 2 (R³ω vs H) 显示真实曲线，并启用完整交互模式（拖拽图例、行内编辑标题/轴标签）。

**架构决策（已确认）：** 每个 tab 存自己的 `WorkbenchPlotLayout`，用 `[ThreeOmegaWorkbenchTab: WorkbenchPlotLayout]` 字典管理，切 tab 时读对应 layout。

**验收条件：**
- [ ] 手动测试（sample `0deg/`，17 个 field-sweep 文件）：
    - Tab 1 显示 17 条 R¹ω(H) 曲线，按温度分色，曲线形状为磁滞回线（约 ±1Ω 量级）
    - Tab 2 显示 17 条 R³ω(H) 曲线，5K 曲线有明显平台区
    - 曲线已 centering（上下对称）
- [ ] `analysisMessage` 显示 "Analyzed 17 field-sweep file(s), RT curve loaded"
- [ ] 温度排序正确（5K → 160K）
- [ ] 无崩溃，warnings panel 无误报
- [ ] 交互模式：拖拽图例 → 图例位置更新，切 tab 后各 tab 图例位置独立保持
- [ ] 交互模式：点击标题 / 轴标签 → 行内编辑，改完后图立即重渲
- [ ] 交互模式：点击图例标签（如 "5 K"）→ 可重命名，重命名后图立即更新

**代码改动（已在 4.1.1 阶段一并完成）：**
- [x] `ThreeOmegaWorkspaceStore` — per-tab layout 存储 + 5 个交互回调 + `_rerenderActiveTab()`
- [x] `ThreeOmegaPlotRenderer` — render 方法返回 `(Data?, WorkbenchPlotLayout?)` 元组
- [x] `ThreeOmegaWorkspaceView` — 完全重构（PlotControlsPanel / GeometryPanel / 全交互 canvas）
- [x] 路径映射验证 — `IngestThreeOmegaSelectionsUseCase` 用 `hit.sourceFilePath` 直接建 URL ✓
- [x] 搜索路由验证 — `ThreeOmegaAHEMetadataExtension` 注入 `workflowID = "3W"`，canonical "3w" ✓

**待手动测试（需先 Import `.lvm` 文件入库）：**
- [ ] 搜索 "3W PN69"，选 0deg 17 个 field-sweep，点 Analyze
- [ ] Tab 1 显示 17 条 R¹ω(H) 磁滞回线，Tab 2 显示 R³ω(H)
- [ ] `analysisMessage` = "Analyzed 17 field-sweep file(s), RT curve loaded"
- [ ] 图例拖拽、标题行内编辑、轴标签编辑、系列标签重命名 均正常

---

### 4.1.3 ✅ — V^(3ω)_AHE 提取方法决策 + Tabs 3–5

**目标：** 看到 RAHE/Hc vs T 和 Rxx vs T 曲线后，确定 V^(3ω)_AHE 提取方法，并用正确方法填 `v3omegaAtZeroField`。

**决策点（需看 Tab 2 后决定）：**

| 观察 | 选择的方法 |
|------|-----------|
| V³ω 在 Hc 处有可见反对称跳变 | **Method A** — intercept-distance |
| V³ω 平台无跳变（or 低于噪声） | **Method B** — H=0 直读 + T_ref 背底扣除 |

- Method A 修改 `ThreeOmegaFitUseCase`：用 `rahe3omega * iRms` 替换 `v3omegaAtZeroField`
- Method B 修改 `IngestThreeOmegaSelectionsUseCase`：最高温度作为 `T_ref`，逐 T 扣除

**验收条件 (Tabs 3–5)：**
- [ ] Tab 3 (RAHE vs T): R¹ω_AHE 从约 150K 降到接近 0（量级 ~1Ω）；R³ω_AHE 值更小
- [ ] Tab 4 (Hc vs T): Hc 随 T 单调减小，约 5000–15000 Oe 量级
- [ ] Tab 5 (Rxx vs T): 金属-绝缘体转变形状（RT 曲线连续）
- [ ] 多 RT 文件处理决策实现（两个 RT 文件 → 取 |H| 更小的那个）

**Open question 2 的处理：** 0deg 有两个 RT 文件 → `IngestThreeOmegaSelectionsUseCase` 选 `|H|` 最小的一个。

**修改范围：**
- `ThreeOmegaFitUseCase.swift` 或 `IngestThreeOmegaSelectionsUseCase.swift`（取决于方法选择）
- `V400ThreeOmegaTests.swift` 补充对应方法的单元测试

**附带完成：Workflow ID 运行时数据迁移（2026-04-07）**

v4.1.3 将 workflow ID 从单字母改为语义命名（`c3b81e7`），运行时配置文件需同步迁移：

| 旧 ID | 新 ID | 含义 |
|-------|-------|------|
| `A`   | `ahe` | AMR/PHE (Anomalous Hall Effect) workflow |
| `B`   | `3w`  | 3 Omega workflow |

已迁移的运行时文件：
- `~/Library/Application Support/SpinLab/config/workflow_match_rules.json` — workflowID 字段
- `~/Library/Application Support/SpinLab/config/filename_rules.json` — workflowRouteRules value 字段

⚠️ **排查提示：** 如果今后在 sidecar、持久化 JSON、或日志中遇到 workflowID 为 `"A"` 或 `"B"` 的记录，说明该数据是迁移前生成的，需手动将 `"A"` → `"ahe"`、`"B"` → `"3w"`。代码中不保留旧 ID 兼容逻辑。

---

### 4.1.4 ✅ — Fig 5b Scaling 完整流程（已完成，2026-04-07）

**目标：** Tab 6 显示散点 + 线性拟合，β (Q_xxz) 数值物理合理。

**验收条件（全部通过）：**
- [x] 输入 L_xx=26μm, L_xy=21μm, d=30nm → Run Scaling
- [x] Tab 6 显示 ≤17 个散点（高温点可能因 RT 插值范围被裁掉）
- [x] 线性拟合线叠加在散点上，R² 显示
- [x] β 和 α 显示在 Fit Results panel
- [x] `scalingResult.warnings` 中提示被跳过的温度点（若有）
- [x] 几何参数改变后点击 "Run Scaling" 立即更新图，不重跑 parser

**已确认：**
- `E_xx³` 使用 `I_rms`（物理正确；已修正 Contracts 注释与代码一致）
- 温度插值 ±5K extrapolation guard 正常工作

---

### 4.1.5 ✅ — Import/Inbox 集成（已完成，2026-04-07）

**目标：** 用户可从 Inbox 正常导入 `.lvm` 文件，而不只是从文件系统直接读路径。

**验收条件（全部通过）：**
- [x] 拖入 `.lvm` 文件到 Inbox → 文件被正确路由到 `MeasurementType.threeOmegaAHE`
- [x] Inbox 显示正确的 sampleKey / conditionSummary（温度、角度、电流）
- [x] Workbench → Search "3w" → 结果中出现已导入文件
- [x] 导入的文件在 Library 中有正确的 `workflowID = "3w"`

**已确认：**
- Import 全链路无需代码改动：运行时规则手册已覆盖 `.lvm` 路由（`measurementNameRules` 匹配 "3w" token → `workflowID = "3W"`）
- condition 提取：temperature（四舍五入到 0.5K）、current、device(angle)、field(Oe) 全部通过运行时 `filename_rules.json` 的 unit_suffix regex 匹配
- 磁盘验证：59 个 sidecar 全部 `workflow: "3w"`，conditions 完整

**附带完成：**
- Bundle 规则同步脚本 `scripts/sync_runtime_rules_to_bundle.sh`（同步 4 个 separated override 文件到 bundle）
- PostToolUse hook：build_desktop_app 后自动同步 override 到 bundle
- 规则架构审计 → 3 项清理写入 `TECH_DEBT_BACKLOG.md`（post-4.1.7）

---

### 4.1.6 ✅ — 多角度支持 + 健壮性（已完成，2026-04-07）

**目标：** 30deg / 60deg 文件夹各自独立分析正确；边界情况不崩溃。

**验收条件（全部通过）：**
- [x] 分别选 30deg 文件夹的文件 → Analyze → 图 title 显示 "30deg"
- [x] 混选 0deg + 30deg → `analysisMessage` 有警告
- [x] 少于 2 个 field-sweep 文件时 RAHE / Hc 图为空但不崩溃
- [x] 无 RT 文件时 Tab 5 显示占位符，"Run Scaling" 按钮被禁用

**策略（混角度）：** 只取第一个 device，不同 device 混选时给警告。多角度对比是 V4.1+ 的功能。

**重构：`angleLabel` → `device`（全链路重命名）**

Workbench 参数必须来自 sidecar conditions（用户在 Import 时确认的值），不应重新解析文件名/路径。
- `ThreeOmegaIngestionContracts` / `ThreeOmegaLVMParser` / `ThreeOmegaFitUseCase` / `ThreeOmegaPlotRenderer` / `IngestThreeOmegaSelectionsUseCase` / `ThreeOmegaWorkspaceStore` / `ThreeOmegaWorkspaceView` — `angleLabel` → `device`
- `IngestThreeOmegaSelectionsUseCase`：device 值优先从 `hit.conditions["device"]` 读取，parser 仅作 fallback
- `ThreeOmegaFitUseCase`：新增 `deviceOverride` 参数

**修复：撤销未授权的 "3 Omega" display name**

`c3b81e7` 在重命名 workflow ID 时擅自将用户定义的 display name "3w" 改为 "3 Omega"。全部恢复：
- `Domain/Models.swift` rawValue、`SearchWorkflowMeasurementsUseCase`、`ThreeOmegaPlotRenderer`（6处）、`ExtensionPoints`、`WorkspaceView/Store`、测试文件
- 运行时 `workflow_registry.json` + 3 个 sidecar 的 `workflowDisplayName` 修复
- CLAUDE.md 新增硬规则：禁止未经用户指令重命名用户定义的名称/配置值

**规则加载改进：bundle override fallback**

- 4 个 separated override 文件（workflow_match、sample_id、substrate、measurement_tag）复制到 bundle
- `RuleLoader.resolveOverrideURL`：运行时优先，bundle fallback；测试环境默认只走 bundle
- 修复 stop hook 路径：SpinLab-4.0 → SpinLab-4.1

**UI 小改进：** Select All / Deselect All toggle 按钮

---

### 4.1.6.1 ✅ — 3ω Workbench 增强（已完成，2026-04-08）

**目标：** 图表标题信息完整化 + 工作台交互改进 + 技术债清理。

**功能变动：**

1. **默认 chart title** — 6 个 tab 标题包含 tab + device + sample + numeric tags
   - 基于 `#token` 模板系统（`#tab #device #sample #氧压 #能量` 等）
   - 用户可在 Plot Controls 编辑模板，动态 hint 显示当前 sample 可用的 token
   - 模板持久化到 InteractionSnapshot

2. **R(1ω)/R(3ω) 标记法** — 替换 Unicode 上标 R¹ω/R³ω；field-sweep tab 标题去掉 "vs H"

3. **V(3ω) 提取方法选择** — Geometry panel 新增 Picker（高场拟合 / 窗口法）
   - `ThreeOmegaV3Method` enum 传入 `ThreeOmegaScalingUseCase`
   - 选择持久化到 InteractionSnapshot

4. **RT 搜索框 popover 修复** — 增大尺寸（minHeight 120, maxHeight 360, width 320）

5. **RT 选中 bug 修复** — `selectRTHit()` 设置 rtQuery 触发 `onChange` 竞争清除 selectedRTHit

6. **Geometry 持久化修复** — geometry onChange 触发 `flushInteractionSnapshotNow()`

7. **Plot Controls 布局优化** — Tab + stack offset slider + Grid 一行；Title 模板第二行

8. **numericDisplay 查询** — `SpinLabDataActor.lookupSampleNumericDisplay()` 从 library index 读取

**技术债清理：**
- 移除 debug print（IngestThreeOmegaSelectionsUseCase）
- 移除废弃 `plotTitleSuffix` 属性
- 替换硬编码 `["氧压", "能量"]` 为 template 系统

**Commits:** `d472949`, `c39fd8f`

---

### 4.1.7 ✅ — 验收测试 + 文档（已完成，2026-04-08）

**目标：** 所有单元测试 ≥20 个并全绿；功能对照原始计划完整验收。

**验收条件（全部通过）：**
- [x] `swift test` 全绿 — 407 tests in 67 suites passed
- [x] 3ω 相关测试 34 个（12 个 suite），远超 ≥20 要求
- [x] 人工测试清单 6 步全部通过（Import → Analyze → Tabs 1-6 → 30deg/60deg）
- [x] Open Questions 1–3 全部有记录结论（见下）
- [x] 本文档 4.1 节状态栏全部更新为 ✅

**Open Questions 结论：**

| Question | 结论 | 实现版本 |
|----------|------|----------|
| Q1 — V^(3ω)_AHE 提取方法 | 高场拟合为主，窗口法 fallback；4.1.6.1 加用户可选 Picker | 4.1.3 + 4.1.6.1 |
| Q2 — 多 RT 文件 | 自动取行数最多的 RT 文件；4.1.6.1 加独立 RT 搜索框手动指定 | 4.1.3 + 4.1.6.1 |
| Q3 — 温度插值精度 | ±5K guard 正常工作，未丢 >3 个点，无需放宽 | 4.1.4 |

---

### 4.1.8 🔲 — 3ω 图表/指标持久化到 Library

**目标：** 3ω Scaling 分析结果（图表 + alpha/beta 指标）持久化到 Library，与 AHE 的 persist 流程对齐。

**现状：**
- AHE 已通过 `PersistChartArtifactUseCase` + `PersistMeasurementDataUseCase` 保存图表和指标（Hc, R_AHE）
- 3ω 的图表和指标（alpha, beta, r²）仅存在于内存，关闭后丢失
- 基础设施全部就绪，只需在 3ω 侧接入

**实现方案：**

1. **图表持久化**（存入 Measurements Done）
   - `ThreeOmegaWorkspaceStore` 新增 `attemptPersist()` 方法，对标 `AHEWorkspaceStore.attemptPersist()`
   - 调用已有 `PersistChartArtifactUseCase` 保存 Scaling chart PNG + manifest
   - 调用已有 `MeasurementPlotIndex.upsert()` 建立源文件→图表映射
   - 图表自动出现在 Library Measurements Done 的 hover 预览中

2. **指标持久化**（存入 Measurement Data）
   - 调用已有 `PersistMeasurementDataUseCase` 写入 metric records
   - 每个 `ThreeOmegaScalingSegment` 生成 3 条记录：
     - `metric="alpha"`, value=seg.alpha
     - `metric="beta"`, value=seg.beta
     - `metric="r_squared"`, value=seg.rSquared
   - conditions 带上 T_lo/T_hi 标识 segment
   - 值自动出现在 Library Measurement Data section

3. **UI 触发**
   - 在 Scaling Result Panel 加 "Save to Library" 按钮，或在 `runScaling()` 成功后自动 persist

**关键文件：**
- `ThreeOmegaWorkspaceStore.swift` — 新增 `attemptPersist()`（主要改动）
- `ThreeOmegaWorkspaceView.swift` — 加 Save 按钮或自动触发
- `PersistChartArtifactUseCase.swift` — 已有，直接调用
- `PersistMeasurementDataUseCase.swift` — 已有，直接调用

**验收条件：**
- [ ] Scaling 图表出现在 Library Measurements Done 的 hover 预览中
- [ ] alpha, beta, r² 出现在 Library Measurement Data section
- [ ] 退出 app 重开后数据保留
- [ ] 测试文件 `V418ThreeOmegaPersistTests.swift`

---

### 版本间依赖关系（4.1.x 内部）

```
4.1.0 ✅
    └── 4.1.1 (parser 单测)
            └── 4.1.2 (真实曲线 Tabs 1–2)
                    └── 4.1.3 (方法决策 + Tabs 3–5)
                            └── 4.1.4 (Scaling Tab 6)
4.1.5 (Import 集成) ← 可与 4.1.2 并行
4.1.6 (多角度)      ← 依赖 4.1.4
4.1.7 (验收)        ← 依赖全部
4.1.8 (3ω 持久化)   ← 依赖 4.1.4
```

### 当前阻塞项 / 决策

1. **Open Q1 — V^(3ω)_AHE 提取方法** ✅：高场拟合为主，窗口法 fallback（4.1.3）；用户可选 Picker（4.1.6.1）
2. **Open Q2 — 多 RT 文件** ✅：自动取行数最多的 RT；独立 RT 搜索框手动指定（4.1.6.1）
3. **Open Q3 — 温度插值精度** ✅：±5K guard 正常工作，无需放宽（4.1.4 确认）

---

## Library 基础设施改进（跨版本，v4.1.2.17–v4.1.2.18）

以下改动不属于任何 4.1.x workflow 迭代，是 Library 层面的独立改进。

### ✅ 合并 Workbench Results 到 Measurements Done（v4.1.2.17）

**动机：** 用户实际工作流是"找 measurement 文件 → 看它参与过的图"，不需要独立的 Workbench Results 区块。

**改动：**
- 移除 Library detail 中的 `WorkbenchResultsSectionView` 区块
- `LibraryMeasurementsDoneSection` 新增 hover 预览：250ms 后弹出 `MeasurementPlotPreviewPanel`，显示该文件参与过的所有图缩略图
- 点击缩略图用系统默认程序打开 PNG；每张图叠加删除按钮（删 PNG + manifest + index 条目）
- `sourceFileName` 改为始终显示在 footnote

**新增持久化：** `samples/{sampleKey}/_spinlab/measurement_plot_index.json`
- `MeasurementPlotIndex` 反向索引：`sourceFileName → [chartIdentityKey]`
- 在 `PersistChartArtifactUseCase` 中与 `results_index.json` 原子写入
- `LoadMeasurementPlotIndexUseCase`（fail-soft Adj-10）
- `BackfillMeasurementPlotIndexUseCase`：旧图首次加载时从 manifest 回填
- 脏引用过滤在 `LibraryFeatureStore` 中完成（加载后内存过滤，不回写）

**测试：** `V41217MeasurementPlotIndexTests.swift` — 13 个测试覆盖 upsert / persist / load / fail-soft / dirty filtering

### ✅ 3ω 测试 rig 修复（v4.1.2.18）

- `V41216ThreeOmegaScalingUseCaseTests`：`SyntheticScalingRig` Rxx 改为温度依赖 `T/100`，修复 OLS 退化；β 调至可恢复量级
- `V400ThreeOmegaTests`：`makeSyntheticLVMFile` H 扫描改为 desc→asc 双支路（2 次过零），col5 按支路翻转，nRows=40

### ✅ Workbench Result 删除功能修复 + 测试（v4.1.2.18）

- `LibraryFeatureStore.deleteWorkbenchResultOnDisk` 添加 `nonisolated` 标记，修复 MainActor 隔离问题（静态方法不需要 actor 绑定）
- 新增 `V343DeleteWorkbenchResultTests.swift` — Workbench Result 磁盘删除功能的完整测试套件（fixture 基于临时目录，覆盖 results_index 更新 + PNG/manifest 文件清理）

---

## 4.2 🔲 — XY Rotation Workflow

**当前状态：** 仅有 `WorkflowRegistryStore.seededDefaults()` 中的 entry（displayName: "XY Rotation"，condition fields: Temperature, Field(mT)），无代码实现。

工作范围待定，进入 4.1.7 验收后规划。

---

## 4.3 🔲 — RT Workflow

**当前状态：** 仅有 seeded entry（displayName: "RT"，condition: Test Current(mA)），无代码实现。

工作范围待定。

---

## 4.4 🔲 — MR Workflow

**当前状态：** 无代码。架构笔记（`V3_2_ITERATION_ADDENDUM_2026-04-03.md`）记录：只需新增 `IngestMRSelectionsUseCase`，现有 workbench plot pipeline 无需改动。

工作范围待定。
