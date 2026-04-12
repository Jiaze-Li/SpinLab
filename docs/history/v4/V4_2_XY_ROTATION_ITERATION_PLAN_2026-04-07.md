# XY Rotation Workflow (v4.2) — Implementation Plan

状态：4.2.0–4.2.5 已完成（可视化 + 持久化 + bugfix）；4.2.5–4.2.7 Fourier 分析部分延后，未来再做
创建：2026-04-07
更新：2026-04-12（4.2.0–4.2.5 完成，Fourier 相关迭代 4.2.5–4.2.7 标记为 deferred）

---

## Context

SpinLab 需要新增第三个 workbench workflow：**XY Rotation**。该 workflow 测量角度依赖的电阻 R(φ)，用于提取 AMR 和 PHE 系数。数据来自两种设备（LVM 和 DAT 格式），测量内容相同。

关键特殊需求：不同设备/文件的 φ=0 定义不同，需要 per-file 的 angle offset。Offset 默认值来自 **sidecar condition**（`conditions["shift"]`），用户可在 workbench 中逐文件微调。

运行时 `filename_rules.json` 已有 `shift` condition definition（id: `"shift"`, regex: `^-?\d+(?:\.\d+)?(?:shift)$`, binding: `conditions.extraConditions.shift`），`workflow_registry.json` 中 XY Rotation 的 conditionFields 也已包含 `shift`。**无需新增 condition 定义，现有系统已完整支持。**

---

## Architecture — XY Rotation 如何接入

```
┌─────────────────────────────────────────────────────────┐
│  Domain (Models.swift)                                   │
│  + WorkflowKind.xyRotation  + MeasurementType.xyRotation│
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  Extension Points (ExtensionPoints.swift)                │
│  4 structs: XYRotation{Workflow,Metadata,Analysis,View}  │
│  → registered in WorkflowRegistry.registerBuiltins()     │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  WorkbenchFeatureStore                                   │
│  + WorkbenchWorkflowID.xyRotation = "xy"                 │
│  + let xyRotationWorkspace = XYRotationWorkspaceStore()  │
│  + search result routing (case .xyRotation)              │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  WorkflowWorkspaceRegistry  case "xy": → View            │
│  XYRotationWorkspaceView (WorkflowWorkspaceShell)        │
│  XYRotationWorkspaceStore (WorkbenchPlottingStore)        │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  UseCases + Contracts                                    │
│  XYRotationDATParser (reuses AHEDataParser internally)   │
│  XYRotationLVMParser (Tableau: marker skeleton from 3ω)  │
│  IngestXYRotationSelectionsUseCase                       │
│  XYRotationFourierFitUseCase (Accelerate)                │
│  XYRotationPlotRenderer                                  │
│  XYRotationIngestionContracts.swift (data models)        │
└─────────────────────────────────────────────────────────┘
```

---

## 迭代计划

### 4.2.0 ✅ — Pure Scaffold（swift build 通过，零运行时逻辑）

**修改的文件：**

| 文件 | 改动 |
|------|------|
| `Sources/SpinLabApp/Domain/Models.swift:248-261` | 在 `WorkflowKind` 和 `MeasurementType` 中加 `case xyRotation` |
| `Sources/SpinLabApp/Extensions/ExtensionPoints.swift` | 加 4 个 stub struct（复制 ThreeOmegaAHE* 模式）|
| `Sources/SpinLabApp/Workflow/WorkflowRegistry.swift:65-90` | `registerBuiltins()` 注册 XY Rotation bundle |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift:13` | 加 `case "xy"` |
| `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` | (a) `WorkbenchWorkflowID` 加 `case xyRotation = "xy"` (b) 加 `let xyRotationWorkspace = XYRotationWorkspaceStore()` (c) search result routing 加 `.xyRotation` 分支 |

**新建的文件：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` | ~60 | Minimal `@MainActor @Observable final class`，`WorkbenchPlottingStore` conformance stubs |
| `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` | ~40 | `WorkflowWorkspaceShell` + placeholder |
| `Sources/SpinLabApp/Workbench/V3/XYRotationIngestionContracts.swift` | ~50 | Stub data models：`XYRotationFileKind`, `XYRotationAngleSweep`, `XYRotationIngestionResult`, `XYRotationWorkbenchTab` |
| `Tests/SpinLabAppTests/V420XYRotationTests.swift` | ~30 | 测试骨架 |

**验收：** `swift build` 通过。App 侧栏显示 XY Rotation，点击后看到 placeholder workspace。

---

### 4.2.1 ✅ — Data Model + Dual Parsers + φ Offset 机制

**数据模型（完善 `XYRotationIngestionContracts.swift`）：**
```swift
struct XYRotationAngleSweep: Codable, Hashable, Sendable, Identifiable {
    var temperatureK: Double
    var stem: String
    var sourceKind: XYRotationFileKind
    var angleDeg: [Double]       // 原始角度
    var resistance: [Double]     // R(φ) in Ohms
    var resistanceXY: [Double]?  // 可选 Rxy 通道
    var defaultPhiOffset: Double // 从 conditions["shift"] 解析的默认 offset（度）
}
```

**φ Offset 机制（来自 sidecar condition）：**
- 数据源：`WorkflowMeasurementSearchHit.conditions["shift"]`（sidecar 持久化，在 Inbox confirm 时由用户填写，如 `"90"`）
- Ingestion 阶段：`IngestXYRotationSelectionsUseCase` 从 `hit.conditions["shift"]` 解析为 `Double`，存入 `XYRotationAngleSweep.defaultPhiOffset`
- Store 维护 `phiOffsetOverrides: [String: Double]`（sweep.id → 用户在 workbench 中的微调值）
- 画图时：`effectiveAngle = angleDeg + (override ?? defaultPhiOffset)`

**新建的文件：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift` | ~80 | 内部用 `AHEDataParser` 获取 `PPMSParsedFile`，从中提取 angle/resistance 列 |
| `Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift` | ~120 | 复用 3ω 的 "Tableau: marker" 骨架，映射 XY Rotation 的列语义 |

**测试：** 真实 LVM + DAT fixture 解析验证，offset 提取验证

---

### 4.2.2 ✅ — Ingestion UseCase + Search 集成 + Workspace UI

> **状态：** 全部完成。UI shell 和 sidecar backfill 在本迭代完成；IngestUseCase 和 runAnalysis 接线在 4.2.3 中完成。

**已完成：**
- `XYRotationWorkspaceView` — 完整双栏 UI（search section、file list、Analyze 按钮 shell、status area、PlotControls、右列 Result shell）
- Backfill：已有 sidecar 的 conditions re-parse

**未完成（移入 4.2.3）：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` | ~100 | 按文件扩展名分发到 LVM/DAT parser，汇总 sweeps，按温度排序 |

- `XYRotationWorkspaceStore.runAnalysis()` — spawn Task 调用 IngestUseCase
- `XYRotationWorkspaceView` Analyze 按钮接线

**验收：** 搜索 XY Rotation 文件 → 选择 → Analyze → 看到 "Analyzed N angle-sweep file(s)"

---

### 4.2.3 ✅ — Ingest UseCase + R(φ) Plot + φ Offset UI（可视化里程碑）

> **承接 4.2.2 未完成项：** `IngestXYRotationSelectionsUseCase` + `runAnalysis()` + Analyze 按钮接线。
>
> **目标：** 端到端跑通 Search → Analyze → 看到 R(φ) 曲线。本迭代只做可视化和交互，不涉及持久化。

#### 新建的文件

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` | ~100 | 按文件扩展名分发到 LVM/DAT parser，汇总 sweeps，按温度排序。从 `hit.conditions["shift"]` 解析 `defaultPhiOffset` |
| `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` | ~150 | 构建 `WorkbenchPlotPayload`，每个温度一条 series，X=angle（已加 offset），Y=R。支持 stack offset。调用 `WorkbenchChartRenderer.resolvedOptions()` 确保 Y 轴动态 padding |

#### 修改 `WorkbenchFeatureStore`（2 项连线）

| 位置 | 改动 | 原因 |
|------|------|------|
| search handler `.xyRotation` case (~L825) | 加 numericDisplay cache 逻辑（同 3ω/AHE 模式） | Title template token 展开 |
| `clearWorkflowMeasurementSearch` `.xyRotation` case (~L920) | 加 `xyRotationWorkspace.cachedSampleNumericDisplay = [:]` | 切库后清理残留数据 |

#### 修改 `XYRotationWorkspaceStore`（~+200 行）

*Ingest（承接 4.2.2）：*
- `runAnalysis(hits:libraryRootPath:dataActor:)` — spawn Task 调用 `IngestXYRotationSelectionsUseCase`
- Analysis 完成时冻结 `cachedInputFiles: [String]` + `cachedSampleKeys: [String]`
- `@ObservationIgnored private var analysisTask: Task<Void, Never>?`

*新增状态字段：*
- `cachedSampleNumericDisplay: [String: [String: String]]` — title template
- `cachedInputFiles: [String]` + `cachedSampleKeys: [String]` — 供 4.2.4 vault/persist 使用，本迭代先冻结
- Per-tab plot PNG: `plotRVsPhi: Data?`（4.2.6 后扩展为多个）
- Per-tab layout: `plotLayouts: [XYRotationWorkbenchTab: WorkbenchPlotLayout]`
- Per-tab legend point: `plotLegendPoints: [XYRotationWorkbenchTab: CGPoint]`
- `plotSeriesLabelOverrides: [Int: String]`
- `plotTitleOverride: String?`, `plotXLabelOverride: String?`, `plotYLabelOverride: String?`
- `titleTemplate: String = "#tab #device #sample"`
- `stackOffsetMultiplier: Double = 0.0`
- `phiOffsetOverrides: [String: Double]` — per-sweep 用户微调 offset
- `@ObservationIgnored private var _renderRevision: UInt64 = 0`

*Plot 渲染 + 交互：*
- `_rerenderActiveTab()` — 递增 `_renderRevision`，detached Task 调用 `XYRotationPlotRenderer`，完成后 guard revision 匹配（v4.1.17 竞态守卫模式）
- `WorkbenchPlottingStore` 交互回调实装（legend drag, title/axis/series label edit → 存 override + rerender）
- Title template 接入 `WorkbenchTitleResolver`（复用共享 `#tab #device #sample` token 系统）

*清理方法：*
- `clearPlot()` — 重置所有 plot state + overrides
- `clearAll()` 扩展 — 同时清理 numericDisplay + cachedInputFiles + cachedSampleKeys

#### 修改 `XYRotationWorkspaceView`（~+150 行）

*左栏：*
- Analyze 按钮接线 → `store.runAnalysis(...)`
- `XYRotationPlotControlsPanel` 扩展 — Stack offset slider + Title template field（复用 `WorkbenchTitleTemplateField`）
- `XYRotationPhiOffsetPanel` — 每个已分析文件的 stem + offset TextField，修改 → 即时 rerender（不重跑 parser）

*右栏：*
- `WorkbenchPlotCanvas`（全交互：legend drag, title/axis/series 行内编辑）替换 TODO 占位
- 暂无 Save / Vault 按钮（4.2.4 加入）

#### 已完成（实施记录）

- IngestUseCase + PlotRenderer + Store 扩展 + View 接线 + WFS numericDisplay 连线
- 路径修复：Ingest 使用 `measurementFilePath`（library 内绝对路径），非 `sourceFilePath`
- 字段重命名：`resistance` → `resistanceXX`，语义清晰
- 双 Tab 拆分：`.rxxVsPhi`（Rxx vs φ）+ `.rxyVsPhi`（Rxy vs φ），Rxy tab 自动过滤无 Rxy 数据的 sweep
- `WorkbenchStandardPlotControls` 共享组件：Row 1（Tab + Stack slider + Gap 输入）、Row 2（Title template + Grid），3ω 和 XY Rotation 均已迁移
- `minGapFraction` 字段暴露到 UI（与 3ω 对齐）
- Stack offset 范围统一为 `0...1.6`

#### 待完成

**Center 模式（基线减除）：**

物理背景：Rxx(φ) = R₀(T) + R_AMR·cos(2φ)，其中 R₀ 是各向同性电阻，随温度变化量级远大于角度依赖部分。Rxy 类似：R_AHE(T) + R_PHE·sin(2φ)。不同温度的曲线直接画在一起时，R₀ 的差异淹没振荡细节。

方案：Plot Controls 加 "Center" 开关。打开后，渲染时每条曲线减去自身均值（mean），等价于去掉 R₀(T) / R_AHE(T)，只保留角度依赖的振荡部分。

选择均值（而非中值或极值对称）的理由：cos(2φ) / sin(2φ) 在完整周期上均值严格为零，减均值在物理上精确等价于去掉各向同性背底。中值无额外优势，极值对称对噪声敏感。

实现要点：
- 只在渲染时做，不改原始数据（Fourier fit 仍用原始值，fit 本身会拟合 R₀）
- Store 加 `centerBaseline: Bool = false`
- Renderer 在构建 series 时，若 center=true，对每条曲线 Y 值减去 mean(Y)
- Y 轴标签自动加 "(centered)" 后缀

#### 验收

- 搜索 XY Rotation 文件 → 选择 → Analyze → 看到 "Analyzed N angle-sweep file(s)"
- Rxx vs φ 和 Rxy vs φ 两个 Tab 各自显示多温度曲线
- Center 开关打开后，曲线围绕零点振荡，不同温度的振荡形状直接可对比
- Stack offset slider + Gap 输入 控制曲线垂直间距
- φ Offset 面板修改偏移后曲线水平移动
- Title template `#tab #device #sample` 正确展开
- 交互模式：拖拽图例、行内编辑标题/轴标签/系列标签
- `swift build` + `swift test` 通过

---

### 4.2.4 ✅ — Save to Library + Vault + InteractionSnapshot（持久化里程碑）

> **对齐 4.1 基础设施：** 本迭代整合 4.1.11 的 `ActiveChartProviding` + `SaveActiveChartToLibraryUseCase`、4.1.17 的 AnalysisPack/Vault save/load、4.1.18 的 related charts popover、4.1.11/19 的 InteractionSnapshot 持久化。

#### 新建的文件

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` | ~50 | `XYRotationPackConfig`（phiOffsetOverrides, activeTab, titleTemplate, stackOffset, searchQueryText）+ `XYRotationPackResult`（`XYRotationIngestionResult`） |

#### 修改 `WorkbenchFeatureStore`（2 项连线）

| 位置 | 改动 | 原因 |
|------|------|------|
| `init()` (~L251) | 加 `self.xyRotationWorkspace.vault = analysisVault` | Vault save/load 需要引用 |
| search handler `.xyRotation` case (~L825) | 加 `xyRotationWorkspace.lastLibraryRootPath = libraryRootPath` | Save to Library 时需要 libraryRootPath |

可选：搜索完成后调用 `xyRotationWorkspace.loadPersistedArtifact(sampleKey:)` 自动加载上次保存的图（AHE 模式，L832–834）。

#### 修改 `XYRotationWorkspaceStore`（~+150 行）

*Save to Library（搬运 3ω/AHE 通用模式，~30 行）：*
- Conform `ActiveChartProviding`（`activeChartPNG`, `activeChartManifestPayload`, `activeChartSampleKeys`, `buildActiveChartMetrics()` → 暂返回空数组，4.2.5 Fourier fit 后实装）
- `cachedManifestPayloads: [XYRotationWorkbenchTab: WorkbenchPlotPayload]` — 渲染时冻结 payload
- `persistenceOutcome: PersistenceOutcome?`
- `persistToLibrary(onComplete:)` — 搬运自 `AHEWorkspaceStore.persistToLibrary()`，调用 `SaveActiveChartToLibraryUseCase`
- Library 自动刷新（`onComplete` 触发 `loadWorkbenchResultsForCurrentSelection` + `loadMeasurementDataForCurrentSelection`）

*Vault save/load（搬运 3ω 模式，~80 行）：*
- `@ObservationIgnored var vault: AnalysisVault?`
- `sourceFingerprint` = `AnalysisPack.makeFingerprint(inputFiles: cachedInputFiles)`（XY Rotation 无 RT 文件）
- `matchingVaultPack` 计算属性 + `hasUnsavedAnalysis` — 逻辑与 3ω 相同
- `saveAnalysis(searchQueryText:)` — fingerprint 匹配 → update / create，workflowID = `"xy"`
- `loadPack(id:, restoreSearchState:)` — 解码 `XYRotationPackConfig/Result`，恢复 phiOffsets + tabs + display state，cancel in-flight tasks
- 不含 overlay 系统（XY Rotation 无多组叠加需求，如需要在 4.2.7 补充）

*Related Charts（接入 v4.1.18 popover，~20 行）：*
- `relatedChartsGrouped` 缓存 + analysis/persist/pack-load 后刷新（调用 `LoadRelatedChartsUseCase`）
- `WorkbenchPlotCanvas` 传入 `relatedCharts` + `libraryRootURL`

*clearAll() 扩展：*
- 清理 vault active pack + persistenceOutcome

#### 修改 InteractionSnapshot

- 新增字段：`xyRotationPhiOffsets: [String: Double]?`, `xyRotationActiveTab: String?`, `xyRotationTitleTemplate: String?`, `xyRotationStackOffset: Double?`, `xyRotationLegendPoints: [String: [Double]]?`
- `WorkbenchFeatureStore.captureInteraction()` — 从 xyRotationWorkspace 读取上述状态
- `WorkbenchFeatureStore.restoreInteraction()` — 写回 xyRotationWorkspace

#### 修改 `XYRotationWorkspaceView`（~+50 行）

*右栏新增按钮：*
- "Save to Library" 按钮（`store.persistToLibrary { ... }`，disabled 当无图时）
- "Save Analysis" / "Update Analysis" 按钮（vault save，bordered/prominent 随 `matchingVaultPack` 变化）
- "Load" 按钮（popover 选择 pack 加载，未保存分析有 alert 确认）
- "Analyses" 管理入口（左列标题栏，popover 列表/重命名/删除）

*PlotCanvas 扩展参数：*
- 传入 `relatedCharts` + `libraryRootURL`（启用 hover popover）

#### 验收

- "Save to Library" → Library Measurements Done hover 预览可见
- "Save Analysis" → vault 存储到 `_spinlab/analysis_packs/xy/<id>.json`
- "Load" → 从 vault 恢复全部状态（phiOffsets, tabs, display, plot）
- "Update Analysis" → 同源文件更新而非创建新 pack
- Related charts hover popover 显示历史图
- InteractionSnapshot：切换 area 再切回来，phiOffsets/tab/titleTemplate/stackOffset 保留
- `swift build` + `swift test` 通过

---

### 4.2.5 ⏸️ DEFERRED — Fourier Fitting（AMR + PHE 提取）+ Metric Persistence

> **延后原因：** Fourier 分解分析功能（4.2.5–4.2.7）暂不实现，未来有需要时再继续。当前 4.2.0–4.2.4 已完成 XY Rotation 的完整可视化和持久化流程。
>
> **注意：** 当前版本号 v4.2.5 包含的是 4.2.3/4.2.4 阶段的 bugfix 和文档整理，不包含下述 Fourier 功能。

**新建：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/XYRotationFourierFitUseCase.swift` | ~180 | Least-squares fit: R(φ) = R₀ + R_AMR·cos(2φ) + R_PHE·sin(2φ)。用 Accelerate 向量化。返回 `XYRotationFourierResult` |

**修改：**
- `XYRotationIngestionContracts.swift` — 加 `XYRotationFourierResult` struct（temperatureK, r0, rAMR, rPHE, rSquared）
- `IngestXYRotationSelectionsUseCase` — 分析后自动调用 fit
- `XYRotationWorkspaceStore` — 存储 fourierResults + metric persistence：
  - `buildActiveChartMetrics()` 实装：Fourier tab 时返回 AMR/PHE metric entries
  - 每个 sweep 提取两个 metric record：`AMR`（R_AMR 值）和 `PHE`（R_PHE 值）
  - Conditions 用 canonical keys（temperature 等小写 trimmed）
  - 同一 `runID` 贯穿 chart + metric（Adj-2 traceability）
  - Library Measurement Data section 自动显示 AMR/PHE 值
- `XYRotationPackResult` — 加 `fourierResults: [XYRotationFourierResult]`（Vault save 自动包含）

---

### 4.2.6 ⏸️ DEFERRED — AMR/PHE vs T Plots（Tabs 2-3）

**修改：**
- `XYRotationPlotRenderer` (+80 行) — `renderAMRvsT()`, `renderPHEvsT()`
- `XYRotationIngestionContracts` — 加 `.amrVsT`, `.pheVsT` tab cases + `stableKeyRank` mapping（接入 `WorkbenchResultReference.sortedByTabRank()` 排序系统）
- `XYRotationWorkspaceStore` (+50 行) — 新 tab 的 plot 存储 + `cachedManifestPayloads` 扩展
- `XYRotationWorkspaceView` (+20 行) — tab bar 加两个 tab

---

### 4.2.7 ⏸️ DEFERRED — Fourier Spectrum Tab + Polish

**修改：**
- `XYRotationPlotRenderer` (+60 行) — `renderFourierSpectrum()` 柱状图
- `XYRotationWorkspaceStore` (+60 行) — 温度选择器（选哪个 sweep 显示频谱）+ warning log
- `XYRotationWorkspaceView` (+80 行) — Tab 4 + 温度 dropdown + warning panel

---

## 依赖关系

```
4.2.0 ✅ Scaffold (compile, sidebar visible)
  └─ 4.2.1 ✅ Data models + dual parsers + offset mechanism
       └─ 4.2.2 ✅ Workspace UI + sidecar backfill (IngestUseCase 移入 4.2.3 完成)
            └─ 4.2.3 ✅ Ingest + R(φ) plot + offset UI + 交互  ← 可视化里程碑
                 └─ 4.2.4 ✅ Save to Library + Vault + InteractionSnapshot  ← 持久化里程碑
                      └─ 4.2.5 ⏸️ Fourier fit + metric persist  ← DEFERRED
                           └─ 4.2.6 ⏸️ AMR/PHE vs T tabs + stableKeyRank  ← DEFERRED
                                └─ 4.2.7 ⏸️ Spectrum tab + polish  ← DEFERRED
```

---

## 4.1 基础设施对齐清单

4.1.11–4.1.19 引入了多项跨 workflow 基础设施，4.2 必须对齐：

| 基础设施 | 来源版本 | 接入迭代 | 方式 |
|----------|---------|---------|------|
| `_renderRevision` 竞态守卫 | 4.1.17/18 | **4.2.3** | 搬运 pattern |
| `WorkbenchTitleResolver` + title template | 4.1.6.1/11 | **4.2.3** | 复用共享组件 |
| `WorkbenchChartRenderer.resolvedOptions()` Y 轴动态 padding | 4.1.14/16 | **4.2.3** | 渲染前调用 |
| numericDisplay 缓存 | 4.1.6.1 | **4.2.3** | WFS 连线 + Store 字段 |
| `ActiveChartProviding` + `SaveActiveChartToLibraryUseCase` | 4.1.11 | **4.2.4** | conform 协议 + 搬运 `persistToLibrary()` |
| `AnalysisPack` / `AnalysisVault` save/load | 4.1.17 | **4.2.4** | 搬运 3ω 模式，新建 `XYRotationPackConfig/Result` |
| Related charts hover popover (`relatedCharts` param) | 4.1.18 | **4.2.4** | 传参即可 |
| `HoverPopoverModifier` 统一 hover 交互 | 4.1.19 | **4.2.4** | 自动通过 `WorkbenchPlotCanvas` 生效 |
| InteractionSnapshot 状态持久化 | 4.1.11/19 | **4.2.4** | 新增 `xyRotation*` 字段 |
| `AppColumnShell` 统一列布局 | 4.1.19 | 4.2.0 ✅ | 已通过 `WorkflowWorkspaceShell` 接入 |
| `stableKeyRank` tab 排序 | 4.1.18 | **4.2.6** | 扩展 `XYRotationWorkbenchTab` |

---

## 总量估算

| 版本 | 新文件 | 估计新增行数 | 关键交付物 |
|------|--------|-------------|-----------|
| 4.2.0 ✅ | 4 | ~180 | 编译通过，sidebar 显示 XY Rotation |
| 4.2.1 ✅ | 2 | ~250 | 双 parser + offset 解析 |
| 4.2.2 ✅ | 0 | ~200 | Workspace UI shell + sidecar backfill |
| 4.2.3 ✅ | 2 | ~500 | Ingest UseCase + R(φ) 交互图 + offset UI + Center/Detrend + title template |
| 4.2.4 ✅ | 1 | ~350 | Save to Library + Vault save/load + Related Charts + InteractionSnapshot |
| 4.2.5 ⏸️ | 1 | ~280 | Fourier fit AMR/PHE + metric persist（**DEFERRED — 未来再做**） |
| 4.2.6 ⏸️ | 0 | ~170 | AMR/PHE vs T tabs + stableKeyRank（**DEFERRED**） |
| 4.2.7 ⏸️ | 0 | ~200 | Spectrum tab + polish（**DEFERRED**） |
| **已完成** | **9** | **~1,480** | 2-tab XY Rotation workflow（Rxx/Rxy vs φ），完整可视化 + 持久化 |

---

## 关键复用（零修改共享代码）

| 组件 | 位置 | 复用方式 |
|------|------|---------|
| `WorkbenchChartRenderer` + `resolvedOptions()` | `Workbench/V3/WorkbenchChartRenderer.swift` | 直接调用，渲染前先 resolvedOptions() |
| `WorkbenchPlotCanvas` + related charts popover | `Features/Workbench/WorkbenchSharedComponents.swift` | 嵌入 View，传 relatedCharts + libraryRootURL |
| `WorkflowWorkspaceShell` → `AppColumnShell` | `Features/Workbench/WorkflowWorkspaceShell.swift` | 双栏容器，列宽自动持久化 |
| `WorkbenchPlottingStore` protocol | `Features/Workbench/WorkbenchSharedComponents.swift:9` | Store conform |
| `ActiveChartProviding` protocol | `Features/Workbench/WorkflowWorkspaceProvider.swift:31` | Store conform（4 属性 + 1 方法）|
| `SaveActiveChartToLibraryUseCase` | `UseCases/SaveActiveChartToLibraryUseCase.swift` | 通用 UseCase，直接调用 |
| `AnalysisPack` + `AnalysisVault` | `Domain/AnalysisPack.swift` + `App/State/AnalysisVault.swift` | 跨 workflow，workflowID="xy" |
| `WorkbenchTitleResolver` + `WorkbenchTitleTemplateField` | 共享 UI | 复用 title template 系统 |
| `HoverPopoverModifier` | `UI/HoverPopoverModifier.swift` | 通过 WorkbenchPlotCanvas 自动生效 |
| `AHEDataParser` | `UseCases/AHEDataParser.swift` | DAT parser 内部调用 |
| `PersistChartArtifactUseCase` | `UseCases/PersistChartArtifactUseCase.swift` | 被 SaveActiveChartToLibraryUseCase 内部调用 |
| `PersistMeasurementDataUseCase` | `UseCases/PersistMeasurementDataUseCase.swift` | 被 SaveActiveChartToLibraryUseCase 内部调用 |
| `LoadLatestChartArtifactUseCase` | `UseCases/` | Artifact loading |
| `LoadRelatedChartsUseCase` | `UseCases/LoadRelatedChartsUseCase.swift` | analysis/persist 后刷新 related charts |
| `BuildRunTraceProjectionUseCase` | `UseCases/` | Run trace display |
| `WorkflowHitRow` / `StatusArea` / `TracePanel` | 共享 UI | 直接嵌入 |
| `MeasurementPlotIndex` + Library hover 预览 | Library 层 | persist 后自动显示 |

---

## 验证方式

每个迭代完成后：
1. `swift build` 通过
2. `swift test` 全绿（`V420XYRotationTests.swift` 逐步扩充）
3. 4.2.3 起：用真实数据手动验证可视化
4. 4.2.5 起：Fourier fit 结果与已知值对比
5. 版本号 bump `AppVersion.swift` + `./scripts/build_desktop_app.sh debug` 重建桌面 app
