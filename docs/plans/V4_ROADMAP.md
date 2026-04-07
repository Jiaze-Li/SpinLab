# SpinLab V4 总路线图

状态：进行中
更新：2026-04-10（4.1 完成，AnalysisPack/Vault 系统上线，3ω workflow done）

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
4.1  ✅  3ω AHE workflow（4.1.0–4.1.17，done 2026-04-10）
     ✅  架构改进 & UI shell 统一化（4.1.18–4.1.19，done 2026-04-10）
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
4.1.8 ✅  3ω 图表/指标持久化到 Library
4.1.9 ✅  搜索查询持久化
4.1.10 ✅ 自适应 stack offset + minGap
4.1.11 ✅ 持久化完善 + Measurement Data 显示重构
4.1.12 ✅ V3 method selection 回归测试
4.1.13 ✅ Library name conflict warning + filename-based import dedup
4.1.14 ✅ Y 轴 title 动态 padding（长 tick label 不再重叠）
4.1.15 ✅ fitRanges 纳入 scaling chart identity + tolerance-based numeric range search
4.1.16 ✅ RAHE 提取（unified rahe() accessor）+ WA nearest-H=0 重构 + chart thumbnail trash icon
4.1.17 ✅ AnalysisPack/Vault 系统 — 跨 workflow 分析存储、Save/Load/Overlay、render race guard
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

### 4.1.8 ✅ — 3ω 图表/指标持久化到 Library（已完成，2026-04-08）

**目标：** 3ω 分析结果（图表 + alpha/beta 指标）持久化到 Library。

**实现（超出原计划范围）：**

1. **4 张图表持久化**（不只 Scaling，还包括 R(1ω)、R(3ω)、Rxx vs T）
   - R(1ω) / R(3ω)：关联 field-sweep 文件，hover 可见
   - Rxx vs T：关联 RT 文件
   - Scaling Law：关联 field-sweep 文件，标题含方法标记 (HFE)/(WA)
   - HFE 和 WA 的 Scaling 图各自独立存储（`semanticParams["v3method"]` 区分 identity key）

2. **指标持久化**
   - 每个 segment 生成 3 条 metric record：alpha、beta、r²
   - conditions 只含 `range`（如 `90K–130K`）、`v3method`（HFE/WA）、`device`（0deg）
   - 不继承 sidecar conditions（current/field/temperature 是测量级别，不是分析结果级别）
   - alpha 存为 `×1e31` 单位 `Ω·μm³·cm²·V⁻²·S⁻²`，beta 存为 `×1e20` 单位 `Ω·μm³·V⁻²`（与 Scaling Result Panel 一致）

3. **UI**
   - "Save to Library" 按钮在右列 Result 标题旁（Analyze 后即可点，不限 Scaling tab）
   - Export Audit 按钮从 Inbox/Workbench overlay 移除（Library-only）

**验收条件（全部通过）：**
- [x] 4 张图表出现在 Library Measurements Done 的 hover 预览中
- [x] alpha, beta, r² 出现在 Library Measurement Data section
- [x] HFE 和 WA 分别存储，不覆盖
- [x] 退出 app 重开后数据保留

---

### 4.1.9 ✅ — 搜索查询持久化（已完成，2026-04-08，用户实现）

**目标：** Workbench 搜索框文字跨 session 持久化。

**实现：** 搜索 query text 通过 UserDefaults 持久化。

---

### 4.1.10 ✅ — 自适应 stack offset + minGap（已完成，2026-04-08，用户实现）

**目标：** R(1ω)/R(3ω) 瀑布图的 stack offset 自适应，增加 minGap 参数。

**实现：** `ThreeOmegaStackOffsetUseCase` 新增 `minGapFraction` 参数，UI 增加 Gap 输入框。

---

### 4.1.11 ✅ — 持久化完善 + Measurement Data 显示重构（已完成，2026-04-08）

**目标：** 补全所有 workbench 状态持久化缺口 + 重新设计 Measurement Data 显示。

**1. 持久化完善**

| 状态项 | 持久化方式 | 说明 |
|--------|-----------|------|
| RT 选中文件 | InteractionSnapshot (`threeOmegaRTSidecarPath`) | 首次 3w 搜索后从 sidecar 重建 hit |
| Fit ranges | InteractionSnapshot (`threeOmegaFitRanges`) | 直接存 Codable 数组 |
| V3 method | InteractionSnapshot (`threeOmegaV3Method`) | 存 rawValue |
| Title template | InteractionSnapshot (`threeOmegaTitleTemplate`) | 用户可编辑模板 |
| Stack offset | InteractionSnapshot (`threeOmegaStackOffsetMultiplier`) | 用户实现 |
| Min gap | InteractionSnapshot (`threeOmegaMinGapFraction`) | 用户实现 |

**RT 选中持久化设计要点：**
- 不在启动时全量扫描库，只按持久化的 sidecar 路径读一次文件
- sidecar I/O 在 `nonisolated static func rebuildRTHit()` 中执行，不阻塞 MainActor
- 恢复时机：首次 3w 搜索结果加载完成后
- 失败静默降级：路径不存在 / sidecar 不可解析 / workflow 不匹配 → 清空快照字段
- capture 时保留未消费的 `pendingRTSidecarPath`，避免多次重启覆盖为 nil
- 去掉 `onChange(of: rtQuery)` 的 clearRTSelection（竞争条件导致间歇性失败），改为只在搜索触发时清除

**2. Measurement Data 显示重构**

**设计思路：**
- 旧设计：每个 metric record 一个 cell，conditions 全部平铺显示 → 信息冗余，难以对比
- 新设计：数据驱动分组，无硬编码特定 workflow 逻辑

**分组层级：** workflow → device → method → range
```
3W · 0deg
┌─ HFE (alpha: Ω·μm³·cm²·V⁻²·S⁻², beta: Ω·μm³·V⁻²) ──┐
│ 90K–130K           │ 5K–80K                             │
│   alpha  1.23e+00  │   alpha  2.34e+00                  │
│    beta  4.56e-01  │    beta  5.67e-01                  │
│      r²  0.9987    │      r²  0.9991                    │
└────────────────────┴────────────────────────────────────┘
```

**显示规则（全部数据驱动，非硬编码）：**
- 分组 key 从 record.conditions 的 `v3method`、`range`、`device` 字段读取
- 单位提到 method 卡片标题（从 entries 去重收集），entries 只显示数值
- `r_squared` 显示为 `r²`
- 宽度 ≥400 时同 method 不同 range 自适应两列并排
- 右键 Copy All / Delete 整个 range 组（如 "Delete HFE (5K–80K)"）
- 所有文字 `.textSelection(.enabled)`

**3. 其他改进**

- Scaling 拟合线端点：改为数据点到拟合线的**垂直投影**（perpendicular foot），而非固定 x 延伸，解决视觉不对称问题
- `#method` token 只在 Scaling tab 解析为 `(HFE)`/`(WA)`，其他 tab 自动移除
- RT restore 测试：4 个测试覆盖成功/失败/workflow 不匹配/文件缺失

**4. Save to Library 模块化重构**

- 新增 `SaveActiveChartToLibraryUseCase`：通用 UseCase，入口校验 sourceRef/sampleKeys/libraryRoot，内部 normalize conditions
- 新增 `ActiveChartProviding` 协议：任何 workflow store 实现即可接入 Save to Library
- 3ω：`persistToLibrary()` 改为只存 active tab 的图，Scaling tab 带 metrics
- AHE：删除 `attemptPersist`，render 不再自动存图，新增手动 "Save to Library" 按钮
- 快照一致性：sampleKeys/inputFiles/conditions 在渲染时冻结，Save 不读 UI 当前状态
- Library 自动刷新：Save 完成后触发 `loadWorkbenchResultsForCurrentSelection` + `loadMeasurementDataForCurrentSelection`

**5. Metric 删除**

- `LibraryFeatureStore.deleteMetricRecord(identityKey:)` — 从 `measurement_data.json` 移除 record + latestIndex 条目
- Measurement Data cell 右键菜单：Copy Value / Delete（含确认弹窗）
- 修复 `.textSelection(.enabled)` 抢占右键事件

**6. Sidebar 独立展开状态**

- 移除 `pruneExpandedSidebarStateForSelectedArea`（旧逻辑：切换 area 时强制收起其他 area）
- 一级菜单点击改为 toggle（原来只做 insert，无法收起）
- Library children 在非活跃时返回缓存值（不返回空数组）
- 效果：每个 chevron 只听用户点击，切换 area 不影响其他菜单展开状态

**7. AHE Title Template + 共享组件**

- AHE workspace 新增 `titleTemplate` 支持（与 3ω 对称）
- 抽取 `WorkbenchTitleResolver` 共享工具
- 抽取 `WorkbenchTitleTemplateField` 共享 UI 组件
- AHE title template 持久化到 InteractionSnapshot

**Commits：** `cd147ed` → `ef44685`（12 个 commit）

---

### 4.1.15 ✅ — fitRanges 纳入 Scaling chart identity + tolerance-based numeric search（已完成，2026-04-09）

**改动：**
- Scaling chart 的 `semanticParams` 新增 `fitRanges` 签名（hash），不同 fit 配置不再互相覆盖 library 中的图
- Library 搜索新增 tolerance-based numeric range matching：如 `3w 5K` 会匹配 4.999K 的文件
- Label alignment 修复

---

### 4.1.16 ✅ — RAHE 提取 + WA 重构 + Library UI 改进（已完成，2026-04-09）

**改动：**
- `ThreeOmegaFieldSweepResult` 新增 unified `rahe()` accessor，统一 1ω/3ω 的 RAHE 读取
- WA 方法重构为 nearest-H=0（取距零场最近的点），替代旧的窗口平均
- RAHE 1ω / 3ω tab 各自独立的 method picker（`rahe1omegaMethod` / `rahe3omegaMethod`）
- Library chart thumbnail：移除标题叠加，改为 minimal trash icon
- 版本号 → v4.1.16

---

### 4.1.17 ✅ — AnalysisPack/Vault 系统（已完成，2026-04-10）

**目标：** 引入跨 workflow 的分析保存/加载/叠加系统。

**1. AnalysisPack 领域模型** (`Domain/AnalysisPack.swift`)

- Workflow-agnostic struct：`id`, `label`, `workflowID`, `createdAt`, `filePaths`, `sampleKeys`, `sourceFingerprint`
- `config: Data` / `result: Data` — workflow-specific JSON blob（泛型编码/解码）
- `sourceFingerprint` = sorted input files + RT path，用于判断同源分析

**2. AnalysisVault** (`App/State/AnalysisVault.swift`)

- `@MainActor @Observable final class`，owned by WorkbenchFeatureStore
- 磁盘布局：`<libraryRoot>/_spinlab/analysis_packs/<workflowID>/<packID>.json`
- CRUD + fingerprint 查询 + workflow 列表
- Root 切换时先清空内存再加载（数据隔离）

**3. ThreeOmegaPackContracts** (`Workbench/V3/ThreeOmegaPackContracts.swift`)

- `ThreeOmegaPackConfig`：完整 session 快照（分析参数 + 显示设置 + 搜索状态）
- `ThreeOmegaPackResult`：`ingestionResult` + `scalingResult?`

**4. Save Analysis 逻辑**

- `sourceFingerprint` 匹配已有 pack → update；不存在 → create（auto label = sample + device）
- `matchingVaultPack` 计算属性驱动按钮状态（Save / Update）

**5. Load Pack 逻辑**

- 解码 config/result → 恢复全部状态（geometry, methods, display, search selection）
- 通过 `restoreSearchState` closure 桥接回 WorkbenchFeatureStore
- 清空 overlays → 重新渲染全部 tabs

**6. Overlay 系统**

- `addOverlay(id:)` → 从 vault 取 pack → 创建 `OverlaySnapshot`（label, sweeps, sourceFiles, sampleKeys）
- OverlaySnapshot 与 vault 完全解耦，pack 删除不影响已有 overlay
- `_renderRAHEWithOverlays()` 多组曲线合成渲染
- `activeChartSampleKeys` 从 snapshot 取 sampleKeys（不依赖 vault）

**7. UI 按钮设计**

| 按钮 | 位置 | 功能 |
|------|------|------|
| `Analyses` | 左列标题栏 "3w" 右侧 | Popover 管理 saved packs（列表/重命名/删除/filter） |
| `Load` | 搜索按钮行末尾 | Popover 选择 pack 加载，未保存分析有 alert 确认 |
| `Save Analysis` / `Update Analysis` | 右列 "Result" 右侧 | 有匹配 pack → Update（bordered），无 → Save（prominent） |
| `Add Analysis` | RAHE tab method picker 右侧 | Popover 选择叠加 pack，已叠加的显示为 capsule chip（可移除） |

**8. 已修复问题（Codex adversarial review）**

- Vault root 切换数据隔离：`configurePersistence` 切 root 前先 `packs = [:]`
- Render 竞态：`_renderRevision` token 防止旧渲染覆盖新结果
- Overlay attribution 解耦：`OverlaySnapshot.sampleKeys` 替代 `vault.get(id:)`

**架构意图：** AnalysisPack 和 AnalysisVault 是跨 workflow 的设计。AHE 接入时只需定义 AHEPackConfig/AHEPackResult，复用同一 Vault。

**Tests：** `V4117AnalysisPackVaultTests.swift`

---

### 版本间依赖关系（4.1.x 内部）

```
4.1.0 ✅
    └── 4.1.1 (parser 单测)
            └── 4.1.2 (真实曲线 Tabs 1–2)
                    └── 4.1.3 (方法决策 + Tabs 3–5)
                            └── 4.1.4 (Scaling Tab 6)
4.1.5 (Import 集成)  ← 可与 4.1.2 并行
4.1.6 (多角度)       ← 依赖 4.1.4
4.1.7 (验收)         ← 依赖全部
4.1.8 (3ω 持久化)    ← 依赖 4.1.4
4.1.15 (chart identity) ← 依赖 4.1.8
4.1.16 (RAHE 重构)   ← 依赖 4.1.3
4.1.17 (Vault 系统)  ← 依赖 4.1.8 + 4.1.16
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

**当前状态：** 规划完成，待实施。详见 `V4_2_XY_ROTATION_ITERATION_PLAN_2026-04-07.md`。

**物理：** 角度依赖电阻 R(φ)，多温度，Fourier 拟合提取 AMR/PHE 系数。
**数据：** LVM + DAT 双格式（不同设备，同一物理量）。
**特殊需求：** per-file φ offset（来自 sidecar `conditions["shift"]`）。

```
4.2.0 🔲  Scaffold — 编译通过，sidebar 显示
4.2.1 🔲  Data Model + Dual Parsers + φ Offset
4.2.2 🔲  Ingestion UseCase + Search
4.2.3 🔲  R(φ) Plot + Offset UI + Library Persist
4.2.4 🔲  Fourier Fit + Metric Persist
4.2.5 🔲  AMR/PHE vs T Plots (Tabs 2-3)
4.2.6 🔲  Fourier Spectrum Tab + Polish
```

---

## 4.3 🔲 — RT Workflow

**当前状态：** 仅有 seeded entry（displayName: "RT"，condition: Test Current(mA)），无代码实现。

工作范围待定。

---

## 4.4 🔲 — MR Workflow

**当前状态：** 无代码。架构笔记（`V3_2_ITERATION_ADDENDUM_2026-04-03.md`）记录：只需新增 `IngestMRSelectionsUseCase`，现有 workbench plot pipeline 无需改动。

工作范围待定。

---

## 架构改进 & UI Shell 统一化（v4.1.18–v4.1.19）

### ✅ Related Charts Hover Popover（v4.1.18）

**动机：** Workbench 中分析完成后，用户希望快速查看同一组源文件历史上画过的其他图。

**改动：**
- `LoadRelatedChartsUseCase`：读 results_index + manifest，按 canonical inputFiles 分组
- `InputFilesCanonicalKey`：完整路径排序拼接，稳定 key
- `WorkbenchResultReference.sortedByTabRank()`：统一排序规则，Library 和 Workbench 共用
- `ThreeOmegaWorkspaceStore`：缓存 relatedChartsGrouped，analysis/persist/pack-load 后刷新
- `WorkbenchPlotCanvas`：hover 1s 弹 popover，复用 `MeasurementPlotPreviewPanel`

**测试：** `V4118RelatedChartsTests.swift` — canonical key 逻辑 + UseCase 边界

### ✅ RootSplitView 条件渲染（v4.1.19）

**动机：** ZStack + opacity(0) 隐藏非活跃面板，macOS NSTrackingArea 不受 allowsHitTesting 控制，导致隐藏 Library 面板的 hover popover 泄漏到 Workbench。

**改动：**
- `detailLayers` 从 ZStack + opacity 改为 `switch appState.selectedArea` 条件渲染
- 删除 `hasMounted*` 惰性初始化机制
- 补充状态持久化：`fileFilter`（Inbox）、`expandedWorkflows/Sets/Uncategorized`（Library，Binding 方案）

**测试：** `V4119InteractionStatePersistenceTests.swift` — 旧快照兼容性 + round-trip

### ✅ AppColumnShell 统一化（v4.1.19）

**动机：** 三个 area 各自硬编码 HSplitView + frame(min/ideal/max)，列宽无持久化。

**改动：**
- 新建 `AppColumnShell`（`Sources/SpinLabApp/UI/AppColumnShell.swift`）
- `ColumnDefaults` 集中定义三个 area 的列宽约束
- `@AppStorage("splitView.{area}.leftWidth")` 持久化列宽
- GeometryReader 追踪实际宽度，节流 + clamp 写入
- Library / Inbox 直接使用，WorkflowWorkspaceShell 薄封装转发

### ✅ HoverPopoverModifier 统一化（v4.1.19）

**动机：** Library measurement hover popover 和 Workbench related charts popover 各自实现了一套 hover/dismiss/panel-tracking 逻辑，代码重复。

**改动：**
- 新建 `HoverPopoverModifier`（`Sources/SpinLabApp/UI/HoverPopoverModifier.swift`）
- 统一 show delay（1s）、dismiss delay（500ms）、panel hover tracking、dialog guard
- Library 和 Workbench 均通过 `.hoverPopover()` 调用
- 清理 Library 的 `schedulePopover`/`cancelPopover` 私有方法

### ✅ UI 微调（v4.1.19）

- Library detail: Measurements Done 移到 Metadata 上面
- Metadata 两列转换阈值从 400pt 降至 320pt

---

## Future / Wishlist

以下功能已明确需求，待排期。

### 🔲 Library detail section 拖拽排序

**动机：** 用户希望自定义 Library 右侧 detail 区域的 section 顺序（Sample Primary、Numeric Tags、Measurement Data、Metadata、Measurements Done 等）。

**方案草案：**
- 定义 `LibraryDetailSection` 枚举，用数组控制渲染顺序
- 用 `ForEach` + drag & drop 实现拖拽排序
- 顺序持久化到 `InteractionSnapshot` 或 `@AppStorage`
- 条件显示的 section（如 Pending Changes）需特殊处理
- SwiftUI `onMove` 在 `ScrollView > VStack` 中不直接生效，需要 `List` 或自定义 drag handler

**复杂点：**
- 各 section 间的 Divider 需动态处理
- 拖拽交互方式待定（长按拖拽 / 拖拽手柄）

### 🔲 AppColumnShell sidebar 列宽持久化

**动机：** NavigationSplitView 的 sidebar 列宽目前硬编码（min:180, ideal:220, max:260），API 不支持动态宽度绑定。

**方案：** 待 macOS SDK 提供列宽绑定 API，或用 NSViewRepresentable 包装实现。
