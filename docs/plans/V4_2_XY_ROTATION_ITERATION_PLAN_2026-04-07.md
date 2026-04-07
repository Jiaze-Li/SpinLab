# XY Rotation Workflow (v4.2) — Implementation Plan

状态：进行中
创建：2026-04-07

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

### 4.2.0 ✅/🔲 — Pure Scaffold（swift build 通过，零运行时逻辑）

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

### 4.2.1 🔲 — Data Model + Dual Parsers + φ Offset 机制

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

### 4.2.2 🔲 — Ingestion UseCase + Search 集成

**新建：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` | ~100 | 按文件扩展名分发到 LVM/DAT parser，汇总 sweeps，按温度排序 |

**修改：**
- `XYRotationWorkspaceStore` — 加 `runAnalysis()`，spawn Task 调用 IngestUseCase
- `XYRotationWorkspaceView` — 加 search section、file list、Analyze 按钮、status area

**验收：** 搜索 XY Rotation 文件 → 选择 → Analyze → 看到 "Analyzed N angle-sweep file(s)"

---

### 4.2.3 🔲 — R(φ) Plot（Tab 1：多温度 overlay + φ offset UI）+ Artifact Persistence

**新建：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` | ~150 | 构建 `WorkbenchPlotPayload`，每个温度一条 series，X=angle（已加 offset），Y=R。支持 stack offset。通过 `WorkbenchChartRenderer` 渲染 |

**修改：**
- `XYRotationWorkspaceStore` (~+180 行) — plot 存储、`WorkbenchPlottingStore` 交互回调、`stackOffsetMultiplier`、`phiOffsetOverrides` dict、artifact persistence（`attemptPersist` 静态方法，参照 `AHEWorkspaceStore.attemptPersist`）、artifact loading（`loadPersistedArtifact`，参照 AHE 模式）
- `XYRotationWorkspaceView` (~+200 行) — 完整双栏 UI：左栏（search + plot controls + PhiOffsetPanel + results list），右栏（tab bar + `WorkbenchPlotCanvas` + status + trace panel）

**PhiOffsetPanel UI：**
- 显示每个已分析文件的 stem + 当前 offset（default 来自 sidecar `conditions["shift"]`）
- 每行一个 TextField 可以覆盖
- 改变 offset → 立即 rerender plot（不重跑 parser）

**Artifact Persistence（接入 Library Measurements Done）：**
- `PersistChartArtifactUseCase` → PNG + manifest + `results_index.json` + `measurement_plot_index.json`
- `LoadLatestChartArtifactUseCase` + `BuildRunTraceProjectionUseCase` 恢复已保存的图
- Library 自动通过 `measurement_plot_index.json` 在 Measurements Done hover 显示缩略图

**验收：** R(φ) 多温度曲线正确显示，修改 offset 后曲线水平移动，图自动保存到 Library 并在 Measurements Done 中可见

---

### 4.2.4 🔲 — Fourier Fitting（AMR + PHE 提取）+ Metric Persistence

**新建：**

| 文件 | ~行数 | 内容 |
|------|-------|------|
| `Sources/SpinLabApp/UseCases/XYRotationFourierFitUseCase.swift` | ~180 | Least-squares fit: R(φ) = R₀ + R_AMR·cos(2φ) + R_PHE·sin(2φ)。用 Accelerate 向量化。返回 `XYRotationFourierResult` |

**修改：**
- `XYRotationIngestionContracts.swift` — 加 `XYRotationFourierResult` struct（temperatureK, r0, rAMR, rPHE, rSquared）
- `IngestXYRotationSelectionsUseCase` — 分析后自动调用 fit
- `XYRotationWorkspaceStore` — 存储 fourierResults + metric persistence：
  - `attemptPersist` 增加 metric 写入：per sampleKey 调用 `PersistMeasurementDataUseCase`
  - 每个 sweep 提取两个 metric record：`AMR`（R_AMR 值）和 `PHE`（R_PHE 值）
  - Conditions 用 canonical keys（temperature, field 等小写 trimmed）
  - 同一 `runID` 贯穿 chart + metric（Adj-2 traceability）
  - Library Measurement Data section 自动显示 AMR/PHE 值

---

### 4.2.5 🔲 — AMR/PHE vs T Plots（Tabs 2-3）

**修改：**
- `XYRotationPlotRenderer` (+80 行) — `renderAMRvsT()`, `renderPHEvsT()`
- `XYRotationIngestionContracts` — 加 `.amrVsT`, `.pheVsT` tab cases
- `XYRotationWorkspaceStore` (+50 行) — 新 tab 的 plot 存储
- `XYRotationWorkspaceView` (+20 行) — tab bar 加两个 tab

---

### 4.2.6 🔲 — Fourier Spectrum Tab + Polish

**修改：**
- `XYRotationPlotRenderer` (+60 行) — `renderFourierSpectrum()` 柱状图
- `XYRotationWorkspaceStore` (+60 行) — 温度选择器（选哪个 sweep 显示频谱）+ warning log
- `XYRotationWorkspaceView` (+80 行) — Tab 4 + 温度 dropdown + warning panel

---

## 依赖关系

```
4.2.0  Scaffold (compile, sidebar visible)
  └─ 4.2.1  Data models + dual parsers + offset mechanism
       └─ 4.2.2  Ingestion UseCase + search integration
            └─ 4.2.3  R(φ) plot + offset UI + persist  ← 第一个可视化里程碑
                 └─ 4.2.4  Fourier fit + metric persist
                      └─ 4.2.5  AMR/PHE vs T tabs
                           └─ 4.2.6  Spectrum tab + polish
```

---

## 总量估算

| 版本 | 新文件 | 估计新增行数 | 关键交付物 |
|------|--------|-------------|-----------|
| 4.2.0 | 4 | ~180 | 编译通过，sidebar 显示 XY Rotation |
| 4.2.1 | 2 | ~250 | 双 parser + offset 解析 |
| 4.2.2 | 1 | ~200 | Analyze 端到端 |
| 4.2.3 | 1 | ~530 | R(φ) 交互图 + offset UI + Library persist |
| 4.2.4 | 1 | ~250 | Fourier fit AMR/PHE + metric persist |
| 4.2.5 | 0 | ~150 | Tabs 2-3 |
| 4.2.6 | 0 | ~200 | Tab 4 + polish |
| **合计** | **9** | **~1,760** | 4-tab XY Rotation workflow |

---

## 关键复用（零修改共享代码）

| 组件 | 位置 | 复用方式 |
|------|------|---------|
| `WorkbenchChartRenderer` | `Workbench/V3/WorkbenchChartRenderer.swift` | 直接调用 |
| `WorkbenchPlotCanvas` | `Features/Workbench/WorkbenchSharedComponents.swift` | 嵌入 View |
| `WorkflowWorkspaceShell` | `Features/Workbench/WorkflowWorkspaceShell.swift` | 双栏容器 |
| `WorkbenchPlottingStore` protocol | `Features/Workbench/WorkbenchSharedComponents.swift:9` | Store conform |
| `AHEDataParser` | `UseCases/AHEDataParser.swift` | DAT parser 内部调用 |
| `PersistChartArtifactUseCase` | `UseCases/PersistChartArtifactUseCase.swift` | Chart + manifest persist |
| `PersistMeasurementDataUseCase` | `UseCases/PersistMeasurementDataUseCase.swift` | Metric records |
| `LoadLatestChartArtifactUseCase` | `UseCases/` | Artifact loading |
| `BuildRunTraceProjectionUseCase` | `UseCases/` | Run trace display |
| `WorkflowHitRow` / `StatusArea` / `TracePanel` | 共享 UI | 直接嵌入 |
| `MeasurementPlotIndex` + Library hover 预览 | Library 层 | persist 后自动显示 |

---

## 验证方式

每个迭代完成后：
1. `swift build` 通过
2. `swift test` 全绿（`V420XYRotationTests.swift` 逐步扩充）
3. 4.2.3 起：用真实数据手动验证可视化
4. 4.2.4 起：Fourier fit 结果与已知值对比
5. 版本号 bump `AppVersion.swift` + `./scripts/build_desktop_app.sh debug` 重建桌面 app
