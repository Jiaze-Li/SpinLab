# SpinLab V4 总路线图

状态：进行中
更新：2026-04-05（4.1.1 完成）

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
4.1  🔲  3ω AHE workflow（4.1.0–4.1.7）
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
4.1.2 🔲  FitUseCase 验证 + 第一次真实数据可视化 (Tabs 1–2)
4.1.3 🔲  V^(3ω)_AHE 提取方法决策 + Tabs 3–5
4.1.4 🔲  Fig 5b Scaling 完整流程 (Tab 6)
4.1.5 🔲  Import/Inbox 集成 — LVM 文件入库
4.1.6 🔲  多角度支持 (30deg / 60deg) + 健壮性
4.1.7 🔲  验收测试 + 文档
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

### 4.1.2 🔲 — Tabs 1–2 真实数据可视化 + 交互模式

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

### 4.1.3 🔲 — V^(3ω)_AHE 提取方法决策 + Tabs 3–5

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

---

### 4.1.4 🔲 — Fig 5b Scaling 完整流程

**目标：** Tab 6 显示散点 + 线性拟合，β (Q_xxz) 数值物理合理。

**验收条件：**
- [ ] 输入 L_xx=26μm, L_xy=21μm, d=30nm → Run Scaling
- [ ] Tab 6 显示 ≤17 个散点（高温点可能因 RT 插值范围被裁掉）
- [ ] 线性拟合线叠加在散点上，R² 显示
- [ ] β 和 α 显示在 Fit Results panel
- [ ] `scalingResult.warnings` 中提示被跳过的温度点（若有）
- [ ] 几何参数改变后点击 "Run Scaling" 立即更新图，不重跑 parser

**可能需修改：**
- 确认 `E_xx³` 使用 `I_amp`（= `I_rms × √2`）不是 `I_rms`（当前代码已正确）
- 确认温度插值在 RT 范围边界的 extrapolation guard（±5K）不会丢掉过多点

---

### 4.1.5 🔲 — Import/Inbox 集成

**目标：** 用户可从 Inbox 正常导入 `.lvm` 文件，而不只是从文件系统直接读路径。

**验收条件：**
- [ ] 拖入 `.lvm` 文件到 Inbox → 文件被正确路由到 `MeasurementType.threeOmegaAHE`
- [ ] Inbox 显示正确的 sampleKey / conditionSummary（温度、角度、电流）
- [ ] Workbench → Search "3ω" → 结果中出现已导入文件
- [ ] 导入的文件在 Library 中有正确的 `workflowID = "3W"`

**修改范围：**
- `ThreeOmegaAHEMetadataExtension.parseFilename` — 验证 sampleKey / conditionSummary 生成逻辑
- Import pipeline 的 routing 规则 — 确认 `.lvm` 不被其他规则拦截

---

### 4.1.6 🔲 — 多角度支持 + 健壮性

**目标：** 30deg / 60deg 文件夹各自独立分析正确；边界情况不崩溃。

**验收条件：**
- [ ] 分别选 30deg 文件夹的文件 → Analyze → 图 title 显示 "30deg"
- [ ] 混选 0deg + 30deg → `analysisMessage` 有警告
- [ ] 少于 2 个 field-sweep 文件时 RAHE / Hc 图为空但不崩溃
- [ ] 无 RT 文件时 Tab 5 显示占位符，"Run Scaling" 按钮被禁用

**策略（混角度）：** 只取第一个 `angleLabel`，不同角度混选时给警告。多角度对比是 V4.1+ 的功能。

---

### 4.1.7 🔲 — 验收测试 + 文档

**目标：** 所有单元测试 ≥20 个并全绿；功能对照原始计划完整验收。

**验收条件：**
- [ ] `swift test` 全绿，`V400ThreeOmegaTests` ≥ 20 个测试
- [ ] 按 `V4_0_3W_AHE_ITERATION_PLAN_2026-04-05.md` §Verification 人工测试清单全部通过（6 步，含 30deg/60deg）
- [ ] Open Questions 1–3 全部有记录结论
- [ ] 本文档 4.1 节状态栏全部更新为 ✅

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
```

### 当前阻塞项 / 决策

1. **Open Q1 — V^(3ω)_AHE 提取方法**：决策时机在 4.1.2 完成后，看 Tab 2 的 5K 曲线形状
2. **Open Q2 — 多 RT 文件**：选 `|H|` 最小的 RT 文件（实现在 4.1.3）
3. **Open Q3 — 温度插值精度**：±5K guard；若 4.1.4 丢点 >3 个则放宽到 ±10K

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
