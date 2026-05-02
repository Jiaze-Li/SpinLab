# Workbench 边界合规审计 — 产出表

> **执行 handoff**: `docs/handoff/2026-05-02-5.1.11a-s1-design.md`
> **Step 0 完成**: 2026-05-02（Claude 方）
> **当前状态**: §0 已封闭（Codex challenge adopt-with-fixes，证据格式修正后封闭）；§1–§5 待批次审计填入

---

## 0. 抽样池

### 基线统计

| 层 | 文档 | Code Map 条目（grep -c 计） | 唯一文件数 |
|---|---|---:|---:|
| Shell | SHELL_AND_LIFECYCLE.md | 37 | 37 |
| Workflow | WORKFLOW_CONTRACTS.md | 45 | 29 ¹ |
| Render | PLOT_CANVAS.md | 11 | 11 |
| Persistence | ARTIFACT_PERSISTENCE.md | 13 | 13 |
| Search | MEASUREMENT_SEARCH.md | 4 | 4 |
| Extension | EXTENSION_BOUNDARIES.md | 5 | 5 |
| **合计** | | **115** | **99** |

¹ WORKFLOW_CONTRACTS.md "Core files" 节与 Code Map 节重复 16 条；唯一文件 29，grep -c 计 45。下表以唯一文件计（99 条）。

### Candidate Pool（99 条唯一文件）

> 每条格式：`code_map:<arch_doc>` 为基础信号；SP-*/G-*/churn/layer_rep 为叠加信号。
> `In Sample` = ✅ / ❌（out-of-sample reason 见最后一列）。

#### Shell 层（37 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| S-01 | `WorkflowWorkspaceShell.swift` | `g:G-008@REGION_MAP.md:L687`, `churn:11`, `layer_rep:Shell` | ✅ | — |
| S-02 | `WorkflowWorkspaceProvider.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-03 | `WorkflowWorkspaceRegistry.swift` | `layer_rep:Extension(per-handoff-§1.3)` | ✅ | — |
| S-04 | `WorkbenchView.swift` | `churn:14` | ✅ | — |
| S-05 | `WorkflowRegistryView.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-06 | `WorkbenchFeatureStore.swift` | `sp:SP-002@workbench/INDEX.md:L45`, `churn:56`, `layer_rep:FeatureStore` | ✅ | — |
| S-07 | `WorkbenchState.swift` | `code_map:SHELL_AND_LIFECYCLE.md`, `quota-fill:Shell` | ✅ | — |
| S-08 | `AppEnvironment.swift` | `code_map:SHELL_AND_LIFECYCLE.md`, `quota-fill:Shell` | ✅ | — |
| S-09 | `AppError.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-10 | `AppLogger.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-11 | `AppVersion.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-12 | `InteractionMemoryStore.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-13 | `InteractionSnapshotCoordinator.swift` | `code_map:SHELL_AND_LIFECYCLE.md`, `quota-fill:Shell` | ✅ | — |
| S-14 | `InteractionSnapshotKeyCodec.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-15 | `RootSplitView.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-16 | `SidebarMenuModel.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-17 | `SidebarTreeView.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-18 | `SpinLabAppState.swift` | `g:G-002@REGION_MAP.md:L681`, `churn:78`, `scope:Workbench-methods-only` | ✅ | — |
| S-19 | `SpinLabDataActor.swift` | `churn:14`, `quota-fill:Shell` | ✅ | — |
| S-20 | `SpinLabSidebarMenuProvider.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-21 | `AppCoordinator.swift` | `code_map:SHELL_AND_LIFECYCLE.md`, `quota-fill:Shell` | ✅ | — |
| S-22 | `AppRouter.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-23 | `InteractionStateModels.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-24 | `Models.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-25 | `WorkbenchStatusArea.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-26 | `WorkbenchTitleTemplateField.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |
| S-27 | `WorkbenchTracePanel.swift` | `code_map:SHELL_AND_LIFECYCLE.md`, `quota-fill:Shell` | ✅ | — |
| S-28 | `Persistence.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-29 | `SpinLabApp.swift` | `churn:14`, `quota-fill:Shell` | ✅ | — |
| S-30 | `AppColumnShell.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-31 | `AppFontScale.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-32 | `AppSpacing.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-33 | `CollapsibleSectionHeader.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-34 | `FlowLayout.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-35 | `HoverPopoverModifier.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `cross-cutting-low-priority` |
| S-36 | `BuildRunTraceProjectionUseCase.swift` | `code_map:SHELL_AND_LIFECYCLE.md`, `quota-fill:Shell` | ✅ | — |
| S-37 | `WorkbenchTitleResolver.swift` | `code_map:SHELL_AND_LIFECYCLE.md` | ❌ | `low-churn-non-sp-non-g` |

Shell 入样：13 条（S-01,03,04,06,07,08,13,18,19,21,27,29,36）

#### Workflow 层（29 条唯一）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| W-01 | `ThreeOmegaWorkspaceStore.swift` | `g:G-006@REGION_MAP.md:L685`, `churn:40` | ✅ | — |
| W-02 | `ThreeOmegaWorkspaceView.swift` | `churn:31` | ✅ | — |
| W-03 | `ThreeOmegaFitUseCase.swift` | `code_map:WORKFLOW_CONTRACTS.md`, `quota-fill:Workflow` | ✅ | — |
| W-04 | `ThreeOmegaPlotRenderer.swift` | `g:G-015@REGION_MAP.md:L694`, `churn:26`, `layer_rep:Render` | ✅ | — |
| W-05 | `ThreeOmegaPackContracts.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-06 | `ThreeOmegaLVMParser.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-07 | `ThreeOmegaScalingUseCase.swift` | `churn:6`, `quota-fill:Workflow` | ✅ | — |
| W-08 | `ThreeOmegaStackOffsetUseCase.swift` | `code_map:WORKFLOW_CONTRACTS.md`, `quota-fill:Workflow` | ✅ | — |
| W-09 | `IngestThreeOmegaSelectionsUseCase.swift` | `churn:12` | ✅ | — |
| W-10 | `ThreeOmegaIngestionContracts.swift` | `churn:12` | ✅ | — |
| W-11 | `AHEWorkspaceStore.swift` | `g:G-006@REGION_MAP.md:L685`, `churn:17` | ✅ | — |
| W-12 | `AHEWorkspaceView.swift` | `churn:18` | ✅ | — |
| W-13 | `AHEDataParser.swift` | `code_map:WORKFLOW_CONTRACTS.md`, `quota-fill:Workflow` | ✅ | — |
| W-14 | `AHEAxisDetector.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-15 | `BuildAHEPlotPayloadUseCase.swift` | `g:G-015@REGION_MAP.md:L694` | ✅ | — |
| W-16 | `AHEPackContracts.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-17 | `IngestAHESelectionsUseCase.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-18 | `AHEIngestionContracts.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-19 | `XYRotationWorkspaceStore.swift` | `g:G-006@REGION_MAP.md:L685`, `churn:9` | ✅ | — |
| W-20 | `XYRotationWorkspaceView.swift` | `churn:9`, `quota-fill:Workflow` | ✅ | — |
| W-21 | `XYRotationDATParser.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-22 | `XYRotationPlotRenderer.swift` | `g:G-015@REGION_MAP.md:L694`, `churn:8` | ✅ | — |
| W-23 | `XYRotationPackContracts.swift` | `churn:5` | ❌ | `crowded-out-by-quota` |
| W-24 | `XYRotationLVMParser.swift` | `churn:6` | ❌ | `crowded-out-by-quota` |
| W-25 | `IngestXYRotationSelectionsUseCase.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-26 | `XYRotationIngestionContracts.swift` | `churn:6` | ❌ | `crowded-out-by-quota` |
| W-27 | `UnitTagEditor.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-28 | `ConditionAliasConfig.swift` | `code_map:WORKFLOW_CONTRACTS.md` | ❌ | `low-churn-non-sp-non-g` |
| W-29 | `SeriesOrderAlignHelper.swift` | `code_map:WORKFLOW_CONTRACTS.md`, `quota-fill:Workflow` | ✅ | — |

Workflow 入样：16 条（W-01,02,03,04,07,08,09,10,11,12,13,15,19,20,22,29）

#### Render 层（11 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| R-01 | `WorkbenchPlotCanvas.swift` | `g:G-007@REGION_MAP.md:L686`, `churn:8` | ✅ | — |
| R-02 | `PlotCanvasMouseTracker.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-03 | `WorkbenchPlotControlsPanel.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-04 | `WorkbenchStandardPlotControls.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-05 | `WorkbenchPlottingStore.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-06 | `WorkbenchChartRenderer.swift` | `churn:14` | ✅ | — |
| R-07 | `LegendDimensionResolver.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-08 | `TabRenderManager.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-09 | `WorkbenchChartStyle.swift` | `code_map:PLOT_CANVAS.md` | ❌ | `low-churn-non-sp-non-g` |
| R-10 | `WorkbenchPlotLayout.swift` | `churn:10` | ✅ | — |
| R-11 | `WorkbenchRenderPipeline.swift` | `churn:6`, `quota-fill:Render` | ✅ | — |

Render 入样：4 条（R-01,06,10,11）

#### Persistence 层（13 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| P-01 | `SaveActiveChartToLibraryUseCase.swift` | `sp:SP-007@workbench/INDEX.md:L47`, `sp:SP-008@workbench/INDEX.md:L48`, `layer_rep:Persistence` | ✅ | — |
| P-02 | `PersistChartArtifactUseCase.swift` | `sp:SP-007@workbench/INDEX.md:L47`, `sp:SP-008@workbench/INDEX.md:L48` | ✅ | — |
| P-03 | `PersistMeasurementDataUseCase.swift` | `sp:SP-007@workbench/INDEX.md:L47`, `sp:SP-008@workbench/INDEX.md:L48` | ✅ | — |
| P-04 | `BackfillMeasurementPlotIndexUseCase.swift` | `sp:SP-008@workbench/INDEX.md:L48` | ✅ | — |
| P-05 | `WorkbenchResultContracts.swift` | `churn:13` | ✅ | — |
| P-06 | `AnalysisVault.swift` | `code_map:ARTIFACT_PERSISTENCE.md` | ❌ | `low-churn-non-sp-non-g` |
| P-07 | `AnalysisPack.swift` | `code_map:ARTIFACT_PERSISTENCE.md` | ❌ | `low-churn-non-sp-non-g` |
| P-08 | `RecomputePreviewItem.swift` | `code_map:ARTIFACT_PERSISTENCE.md` | ❌ | `low-churn-non-sp-non-g` |
| P-09 | `LoadLatestChartArtifactUseCase.swift` | `sp:SP-008@workbench/INDEX.md:L48` | ✅ | — |
| P-10 | `LoadMeasurementDataUseCase.swift` | `sp:SP-008@workbench/INDEX.md:L48` | ✅ | — |
| P-11 | `LoadWorkbenchResultsUseCase.swift` | `sp:SP-008@workbench/INDEX.md:L48` | ✅ | — |
| P-12 | `AnalysisPackProviding.swift` | `code_map:ARTIFACT_PERSISTENCE.md` | ❌ | `low-churn-non-sp-non-g` |
| P-13 | `WorkbenchArtifactIdentity.swift` | `code_map:ARTIFACT_PERSISTENCE.md` | ❌ | `low-churn-non-sp-non-g` |

Persistence 入样：8 条（P-01,02,03,04,05,09,10,11）

#### Search 层（4 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| SE-01 | `SearchWorkflowMeasurementsUseCase.swift` | `sp:SP-009@workbench/INDEX.md:L46`, `layer_rep:Search` | ✅ | — |
| SE-02 | `WorkflowSearchModels.swift` | `code_map:MEASUREMENT_SEARCH.md` | ❌ | `low-churn-non-sp-non-g` |
| SE-03 | `WorkflowHitRow.swift` | `code_map:MEASUREMENT_SEARCH.md` | ❌ | `low-churn-non-sp-non-g` |
| SE-04 | `WorkbenchSharedComponents.swift` | `churn:15` | ✅ | — |

Search 入样：2 条（SE-01,04）

#### Extension 层（5 条）

| # | 文件名 | 信号 | In Sample? | Out-of-Sample Reason |
|---|---|---|---|---|
| E-01 | `WorkflowID.swift` | `code_map:EXTENSION_BOUNDARIES.md`, `quota-fill:Extension` | ✅ | — |
| E-02 | `WorkflowDefinition.swift` | `code_map:EXTENSION_BOUNDARIES.md` | ❌ | `crowded-out-by-quota` |
| E-03 | `ExtensionPoints.swift` | `code_map:EXTENSION_BOUNDARIES.md` | ❌ | `crowded-out-by-quota` |
| E-04 | `WorkflowDefinitionStore.swift` | `code_map:EXTENSION_BOUNDARIES.md` | ❌ | `crowded-out-by-quota` |
| E-05 | `WorkflowRegistry.swift` | `code_map:EXTENSION_BOUNDARIES.md` | ❌ | `crowded-out-by-quota` |

Extension 入样：1 条（E-01）

---

### Audit Sample（44 条，封闭）

> 封闭后不允许扩；Codex challenge 后如有调整在封闭前执行。

| Sample ID | 文件名（Short） | Layer | 强制纳入信号 / 纳入理由 | Batch |
|---|---|---|---|---|
| AS-01 | `SpinLabAppState.swift` | Shell | `g:G-002@REGION_MAP.md:L681`, churn:78; 仅审 Workbench 方法 | Batch 1 |
| AS-02 | `WorkbenchFeatureStore.swift` | Shell/FeatureStore | `sp:SP-002@workbench/INDEX.md:L45`, churn:56, layer_rep | Batch 1 |
| AS-03 | `WorkflowWorkspaceShell.swift` | Shell | `g:G-008@REGION_MAP.md:L687`, churn:11, layer_rep:Shell | Batch 1 |
| AS-04 | `WorkflowWorkspaceRegistry.swift` | Shell | layer_rep:Extension (per handoff §1.3) | Batch 1 |
| AS-05 | `WorkbenchView.swift` | Shell | churn:14 | Batch 1 |
| AS-06 | `SpinLabApp.swift` | Shell | churn:14 | Batch 1 |
| AS-07 | `AppEnvironment.swift` | Shell | quota-fill:Shell (DI boundary) | Batch 1 |
| AS-08 | `AppCoordinator.swift` | Shell | quota-fill:Shell (cross-store coordination) | Batch 1 |
| AS-09 | `SpinLabDataActor.swift` | Shell | churn:14, quota-fill:Shell | Batch 1 |
| AS-10 | `WorkbenchState.swift` | Shell | quota-fill:Shell | Batch 1 |
| AS-11 | `InteractionSnapshotCoordinator.swift` | Shell | quota-fill:Shell | Batch 1 |
| AS-12 | `WorkbenchTracePanel.swift` | Shell | quota-fill:Shell | Batch 1 |
| AS-13 | `BuildRunTraceProjectionUseCase.swift` | Shell | quota-fill:Shell | Batch 1 |
| AS-14 | `WorkbenchPlotCanvas.swift` | Render | `g:G-007@REGION_MAP.md:L686` | Batch 1 |
| AS-15 | `WorkbenchChartRenderer.swift` | Render | churn:14 | Batch 1 |
| AS-16 | `WorkbenchPlotLayout.swift` | Render | churn:10 | Batch 1 |
| AS-17 | `WorkbenchRenderPipeline.swift` | Render | churn:6, quota-fill:Render | Batch 1 |
| AS-18 | `ThreeOmegaWorkspaceStore.swift` | Workflow | `g:G-006@REGION_MAP.md:L685`, churn:40 | Batch 2 |
| AS-19 | `ThreeOmegaWorkspaceView.swift` | Workflow | churn:31 | Batch 2 |
| AS-20 | `ThreeOmegaFitUseCase.swift` | Workflow | quota-fill:Workflow | Batch 2 |
| AS-21 | `ThreeOmegaPlotRenderer.swift` | Workflow | `g:G-015@REGION_MAP.md:L694`, churn:26, layer_rep:Render | Batch 2 |
| AS-22 | `ThreeOmegaScalingUseCase.swift` | Workflow | churn:6, quota-fill:Workflow | Batch 2 |
| AS-23 | `ThreeOmegaStackOffsetUseCase.swift` | Workflow | quota-fill:Workflow | Batch 2 |
| AS-24 | `IngestThreeOmegaSelectionsUseCase.swift` | Workflow | churn:12 | Batch 2 |
| AS-25 | `ThreeOmegaIngestionContracts.swift` | Workflow | churn:12 | Batch 2 |
| AS-26 | `AHEWorkspaceStore.swift` | Workflow | `g:G-006@REGION_MAP.md:L685`, churn:17 | Batch 2 |
| AS-27 | `AHEWorkspaceView.swift` | Workflow | churn:18 | Batch 2 |
| AS-28 | `AHEDataParser.swift` | Workflow | quota-fill:Workflow | Batch 2 |
| AS-29 | `BuildAHEPlotPayloadUseCase.swift` | Workflow | `g:G-015@REGION_MAP.md:L694` | Batch 2 |
| AS-30 | `XYRotationWorkspaceStore.swift` | Workflow | `g:G-006@REGION_MAP.md:L685`, churn:9 | Batch 2 |
| AS-31 | `XYRotationWorkspaceView.swift` | Workflow | churn:9, quota-fill:Workflow | Batch 2 |
| AS-32 | `XYRotationPlotRenderer.swift` | Workflow | `g:G-015@REGION_MAP.md:L694`, churn:8 | Batch 2 |
| AS-33 | `SeriesOrderAlignHelper.swift` | Workflow | cross-workflow helper, quota-fill:Workflow | Batch 2 |
| AS-34 | `SaveActiveChartToLibraryUseCase.swift` | Persistence | `sp:SP-007@workbench/INDEX.md:L47`, `sp:SP-008@workbench/INDEX.md:L48`, layer_rep:Persistence | Batch 3 |
| AS-35 | `PersistChartArtifactUseCase.swift` | Persistence | `sp:SP-007@workbench/INDEX.md:L47`, `sp:SP-008@workbench/INDEX.md:L48` | Batch 3 |
| AS-36 | `PersistMeasurementDataUseCase.swift` | Persistence | `sp:SP-007@workbench/INDEX.md:L47`, `sp:SP-008@workbench/INDEX.md:L48` | Batch 3 |
| AS-37 | `BackfillMeasurementPlotIndexUseCase.swift` | Persistence | `sp:SP-008@workbench/INDEX.md:L48` | Batch 3 |
| AS-38 | `LoadLatestChartArtifactUseCase.swift` | Persistence | `sp:SP-008@workbench/INDEX.md:L48` | Batch 3 |
| AS-39 | `LoadWorkbenchResultsUseCase.swift` | Persistence | `sp:SP-008@workbench/INDEX.md:L48` | Batch 3 |
| AS-40 | `LoadMeasurementDataUseCase.swift` | Persistence | `sp:SP-008@workbench/INDEX.md:L48` | Batch 3 |
| AS-41 | `WorkbenchResultContracts.swift` | Persistence | churn:13 | Batch 3 |
| AS-42 | `SearchWorkflowMeasurementsUseCase.swift` | Search | `sp:SP-009@workbench/INDEX.md:L46`, layer_rep:Search | Batch 3 |
| AS-43 | `WorkbenchSharedComponents.swift` | Search | churn:15 | Batch 3 |
| AS-44 | `WorkflowID.swift` | Extension | quota-fill:Extension | Batch 3 |

**样本统计**: 44 条，Shell 13 / Workflow 16 / Render 4 / Persistence 8 / Search 2 / Extension 1
**层占比**: Shell 29.5% / Workflow 36.4% / Render 9.1% / Persistence 18.2% / Search 4.5% / Extension 2.3%
（Persistence 超配额因 SP-008 强制纳入 7 条；其余层接近 §1.4 配额）

---

## 1. Violations（入 5.1.11b 修复清单）

| AS-ID | File | Layer | #N | caller→callee→行为 | High/Med/Low | next_action / 修复粒度 / 依赖 |
|---|---|---|---|---|---|---|
| AS-18 | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | Workflow Store | #1 | `ThreeOmegaWorkspaceStore.rtQuery` setter → `UserDefaults.standard.set` → @Observable setter 含 UserDefaults 写副作用 | Med | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-18 | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | Workflow Store | #15 | `ThreeOmegaWorkspaceStore` → `UserDefaults`/`FileManager`/`LibraryStore()` direct instantiation → 运行时副作用依赖未经 AppEnvironment 注入 | Med | next_action=14a / 修复粒度=multi / 依赖=无 |
| AS-19 | `Features/Workbench/ThreeOmegaWorkspaceView.swift` | Workflow View | #2 | `ThreeOmegaAddOverlayButton.body` → `vault.packs(forWorkflow:).filter` → View 内含业务过滤逻辑 | Low | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-21 | `UseCases/ThreeOmegaPlotRenderer.swift` | Workflow Renderer | #6 | `ThreeOmegaPlotRenderer._render` → `try? WorkbenchRenderPipeline.render` → render 失败返回 `(nil, nil)` 静默丢弃 error | Med | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-21 | `UseCases/ThreeOmegaPlotRenderer.swift` | Workflow Renderer | #16 | Store → `ThreeOmegaPlotRenderer` → 持有 `showGrid`/label/style 可变配置状态 → UseCase 非 stateless struct | Low | next_action=no-fix-accepted / 修复粒度=single / 依赖=无 |
| AS-24 | `UseCases/IngestThreeOmegaSelectionsUseCase.swift` | Workflow UseCase | #16 | Store → `IngestThreeOmegaSelectionsUseCase` → 持有 parser/fitter 实例属性 → UseCase 非 stateless struct | Low | next_action=no-fix-accepted / 修复粒度=single / 依赖=无 |
| AS-25 | `Workbench/V3/ThreeOmegaIngestionContracts.swift` | Workflow Contracts | #17 | Workflow 层 → 定义 `ThreeOmegaFieldSweepResult`/`ThreeOmegaGeometry`/scaling/tab 类型 → domain model 在 Workbench/V3 而非 Domain/ | High | next_action=11b / 修复粒度=multi / 依赖=无 |
| AS-26 | `Features/Workbench/AHEWorkspaceStore.swift` | Workflow Store | #5 | `runAnalysis` → `extractAHEMetricsPerSeries`/`extractSingleSeriesMetrics` → Store 含 Hc/R_AHE 提取策略和 label 解析业务规则 | High | next_action=14a / 修复粒度=multi / 依赖=无 |
| AS-26 | `Features/Workbench/AHEWorkspaceStore.swift` | Workflow Store | #15 | `AHEWorkspaceStore.refreshRelatedCharts` → `FileManager.default.fileExists` → filesystem capability 未经 AppEnvironment 注入 | Med | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-27 | `Features/Workbench/AHEWorkspaceView.swift` | Workflow View | #2 | `AHEMetricOverridePanel.body` → `lastExtractedMetrics.values.sorted` → View 含显示排序逻辑 | Med | next_action=14a / 修复粒度=single / 依赖=AS-26 |
| AS-27 | `Features/Workbench/AHEWorkspaceView.swift` | Workflow View | #2 | `updateCandidate(value:reason:)` → `trim` + `Double(...)` 转换 + 默认 reason 填写 → View 含输入归一化/解析和 fallback 策略 | Med | next_action=14a / 修复粒度=single / 依赖=AS-26 |
| AS-28 | `UseCases/AHEDataParser.swift` | Parser | #17 | `AHEDataParser.parse` → 返回 `PPMSParsedFile` → raw domain model 定义在 UseCases/ 而非 Domain/ | High | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-30 | `Features/Workbench/XYRotationWorkspaceStore.swift` | Workflow Store | #5 | `runAnalysis`/`_snapshotRenderer`/`_applySeriesOrder` → Store 含 selected-hit ordering、legend reverse mapping 和 persisted series-order merge 策略 | Med | next_action=14a / 修复粒度=multi / 依赖=AS-33 |
| AS-30 | `Features/Workbench/XYRotationWorkspaceStore.swift` | Workflow Store | #15 | `XYRotationWorkspaceStore.refreshRelatedCharts` → `FileManager.default.fileExists` → filesystem capability 未经 AppEnvironment 注入 | Med | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-32 | `UseCases/XYRotationPlotRenderer.swift` | Workflow Renderer | #6 | `renderRxxVsPhi`/`renderRxyVsPhi` → `_render` → `try? WorkbenchRenderPipeline.render` 返回 `(nil, nil)` 丢弃 render error | High | next_action=14a / 修复粒度=single / 依赖=无 |
| AS-32 | `UseCases/XYRotationPlotRenderer.swift` | Workflow Renderer | #16 | `XYRotationPlotRenderer` → 含 `collectedWarnings`/config 可变字段 → UseCase 非 stateless struct | Med | next_action=14a / 修复粒度=multi / 依赖=无 |

| AS-42 | `UseCases/SearchWorkflowMeasurementsUseCase.swift` | Search UseCase | #16 | `SearchWorkflowMeasurementsUseCase` → `private let sampleKeyNormalizer = SampleKeyNormalizer()` → UseCase 内部自建 helper 实例而非接受 function 参数 | Low | next_action=no-fix-accepted / 修复粒度=single / 依赖=无 |

**Violation 汇总**: 17 条（High: 4 / Med: 8 / Low: 5）。Batch 1 (Shell/Render) 0 条；Batch 3 1 条。

---

## 2. Doc Drift（建议 Code Map 注释修订方向）

> 审计轮不直接 commit；修订方向供 Claude 方在 5.1.11b 执行。

| File | 旧注释 | 建议新注释方向 | 偏离原因 |
|---|---|---|---|
| `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | 3ω workflow store; ingestion state, fit results, scaling output, series order | 3ω workflow store; coordinates search selection, RT selection, analysis/render state, scaling, overlays, pack restore, and chart persistence | 实现已包含 RT 独立搜索、overlay、pack restore、manifest/persistence，旧注释偏窄 |
| `UseCases/ThreeOmegaPlotRenderer.swift` | renders 3ω fit and raw data as chart series for the plot canvas | renders all 3ω chart tabs from ingestion/scaling outputs through the shared render pipeline | 实现覆盖 RAHE/Hc/RT/Scaling/overlay multi-group 与 pipeline warning collection |
| `Workbench/V3/ThreeOmegaIngestionContracts.swift` | ingestion input contracts and result types for the 3ω workflow | defines 3ω parsed-file, processed-result, scaling, geometry, and tab contracts | 文件承载 workflow domain/result/tab 类型，不只是 ingestion input/result |
| `Features/Workbench/AHEWorkspaceStore.swift` | AHE workflow store; ingestion state, axis-detected results, plot series | AHE workflow store; coordinates ingestion, plot render state, metrics, persistence, packs, and related charts | 实现包含 persistence outcome、metric override/extraction cache、analysis pack restore、related-chart loading |
| `Features/Workbench/AHEWorkspaceView.swift` | AHE workspace view; assembles axis-detection results and plot panels | AHE workspace view; assembles plot controls, metric override panels, and workflow shell content | 主体是 shell composition 加 Hc/R_AHE override panels |
| `Features/Workbench/XYRotationWorkspaceStore.swift` | XY Rotation workflow store; ingestion state, series data, plot configuration | XY Rotation workflow store; coordinates ingestion, tab render state, persistence, packs, related charts, and series ordering | 实现包含 save-to-library、pack restore、related-chart lookup、reorder/rerender 协调 |
| `Workbench/V3/SeriesOrderAlignHelper.swift` | aligns series display order between workspace store and plot canvas | aligns persisted series order with the current sweep identifiers after re-analysis | 是纯 persisted-order reconciliation helper，不直接桥接 store 与 canvas |
| `Features/Workbench/WorkbenchSharedComponents.swift` | shared search bar and filter UI components used across Workbench views | placeholder stub; formerly consolidated shared workbench UI; contents split into dedicated files | 文件已拆分为 7 个独立文件，现只剩 redirect 注释，Code Map 注释描述的代码已不在此处 |

---

## 3. Accepted Boundaries（跨区是有意为之）

| File | 跨区现象 | 接受理由 | Final Disposition |
|---|---|---|---|
| `App/SpinLabAppState.swift` | G-002: 1816-line app coordinator；Workbench 方法内无 violation；try? 全在 Inbox/Library 作用域方法 | 仅审 Workbench 方法范围；大文件 G-002 归入 5.1.14a meta 收敛 | Accepted Boundary |
| `Features/Workbench/WorkbenchFeatureStore.swift` | SP-002: Inbox Rules 条件投影穿越 region 边界落在 WorkbenchFeatureStore | 条件投影设计意图在 workbench/INDEX.md SP-002 明文记录；@MainActor @Observable final class 形态合规 | Accepted Boundary |
| `Shell/WorkflowWorkspaceShell.swift` | G-008: 567-line 泛型 View shell 承担所有 workflow 的容器 | generic View shell pattern；@Environment 接收 AppState；无直接 service 调用 | Accepted Boundary |
| `Shell/WorkflowWorkspaceRegistry.swift` | enum @ViewBuilder factory 映射 WorkflowID → 视图 | Extension 层 registry 设计；无 state 无 service 调用 | Accepted Boundary |
| `Shell/WorkbenchView.swift` | View 聚合 trace panel + workflow registry | @Environment 接收 AppState；无 filter/sort/normalize | Accepted Boundary |
| `App/SpinLabApp.swift` | App entry point | 无 Workbench-specific state 违规 | Accepted Boundary |
| `Shell/AppEnvironment.swift` | DI 边界：struct 纯容器 | Foundation only；纯 struct；正确 DI pattern | Accepted Boundary |
| `Shell/AppCoordinator.swift` | WorkbenchRouteResolution 路由逻辑 | Foundation only；无 SwiftUI；无 service 直调 | Accepted Boundary |
| `Data/SpinLabDataActor.swift` | actor 承载重 I/O | actor 类型合规；无 @Observable 违规 | Accepted Boundary |
| `Shell/WorkbenchState.swift` | struct value type | 纯 value type；无 violation | Accepted Boundary |
| `Shell/InteractionSnapshotCoordinator.swift` | @MainActor final class 不含 @Observable | coordinator 非 observable store，不暴露给 View 订阅；signal #10 不适用 | Accepted Boundary |
| `Shell/WorkbenchTracePanel.swift` | pure View，value 参数 | 无 service 直调；无 filter/sort | Accepted Boundary |
| `Shell/BuildRunTraceProjectionUseCase.swift` | stateless struct UseCase | Foundation only；无 state；符合 UseCase pattern | Accepted Boundary |
| `Shell/WorkbenchPlotCanvas.swift` | G-007: 728-line 共享 plot shell View | @Environment 接收 AppState；无 business logic violation；G-007 known shared shell pattern | Accepted Boundary |
| `Shell/WorkbenchChartRenderer.swift` | pure CoreGraphics PNG renderer | Foundation+CoreGraphics only；无 SwiftUI；无 side effect | Accepted Boundary |
| `Shell/WorkbenchPlotLayout.swift` | struct Sendable layout calculator | CoreGraphics+CoreText only；无 violation | Accepted Boundary |
| `Shell/WorkbenchRenderPipeline.swift` | enum render pipeline | Foundation+CoreGraphics；无 violation | Accepted Boundary |
| `UseCases/ThreeOmegaFitUseCase.swift` | UseCase consumes parsed LVM contracts and returns processed sweep results | 无 SwiftUI；无 storage 细节；无 async/AppState 越界；物理拟合算法属于 workflow logic | Accepted Boundary |
| `UseCases/ThreeOmegaScalingUseCase.swift` | UseCase consumes field sweeps, RT result, geometry, fit ranges | 无 SwiftUI；无 storage 细节；fit range normalization and warnings are deterministic computation | Accepted Boundary |
| `UseCases/ThreeOmegaStackOffsetUseCase.swift` | Renderer calls stack offset use case for per-curve offsets | Stateless deterministic computation；caller owns sorting and presentation state | Accepted Boundary |
| `UseCases/BuildAHEPlotPayloadUseCase.swift` | Workflow payload builder depends on Workbench plot domain contracts | Stateless struct；无 SwiftUI；无 storage 细节；纯 ingestion result → plot payload 映射 | Accepted Boundary |
| `Features/Workbench/XYRotationWorkspaceView.swift` | View reads workflow ingestion result and binds phi offset controls to store | @Environment AppState；mutation 通过 store 方法；无 sorting/filtering/normalization | Accepted Boundary |
| `UseCases/SaveActiveChartToLibraryUseCase.swift` | SP-007/SP-008: orchestrates chart + metric persist to Library | Foundation only；无 stored 依赖；validates input + delegates to sub-UseCases；local writer/resolver creation 视为 factory pattern | Accepted Boundary |
| `UseCases/PersistChartArtifactUseCase.swift` | SP-007/SP-008: writes chart image + manifest to Library | Foundation only；injected `writer: AtomicFileWritingCapability` + `pathResolver`；使用 throws 正确上报 error | Accepted Boundary |
| `UseCases/PersistMeasurementDataUseCase.swift` | SP-007/SP-008: appends metric record to Library measurement_data.json | Foundation only；injected capabilities；uses throws ✓ | Accepted Boundary |
| `UseCases/BackfillMeasurementPlotIndexUseCase.swift` | SP-008: one-time backfill rebuilds MeasurementPlotIndex from manifests | Adj-10 approved fail-soft with stderr logging；跳过不可读 manifest 是设计意图 | Accepted Boundary |
| `UseCases/LoadLatestChartArtifactUseCase.swift` | SP-008: loads most recent chart artifact | graceful nil-on-failure load；file-not-found 是预期场景 | Accepted Boundary |
| `UseCases/LoadWorkbenchResultsUseCase.swift` | SP-008: loads WorkbenchResultsIndex | Adj-10 fail-soft；non-missing-file errors logged to stderr | Accepted Boundary |
| `UseCases/LoadMeasurementDataUseCase.swift` | SP-008: loads WorkbenchMeasurementDataStore | same pattern as AS-39 | Accepted Boundary |
| `Workbench/V3/WorkbenchResultContracts.swift` | Workbench-internal persistence contracts | Workbench-specific data types (plot series, run manifest, results index)；Foundation only；不是跨区 domain entity | Accepted Boundary |
| `UseCases/SearchWorkflowMeasurementsUseCase.swift` | SP-009: searches Library sidecars for workflow measurements | Foundation only；uses throws；SP-009 cross-boundary by design；Low #16 `no-fix-accepted` | Accepted Boundary |
| `Features/Workbench/WorkbenchSharedComponents.swift` | redirect stub (see Drift) | 文件内无可审代码；drift 注释单独处理 | Accepted Boundary |
| `Workflow/WorkflowID.swift` | workflow ID enum with alias matching | Foundation only；clean enum；Extension 层 ✓ | Accepted Boundary |

---

## 4. Cross-Region Doubts For 5.1.14

| 现象 | 涉及文件 | 一句猜测 |
|---|---|---|
| Store 直接解码 analysis packs 并在 restore/overlay 流程中读取 library indices | `ThreeOmegaWorkspaceStore.swift` | 历史上为 pack restore 快速接入而把 vault/library I/O 留在 workflow store 内 |
| `ThreeOmegaIngestionContracts.swift` 同时承载 domain-like models 和 UI tab enum | `ThreeOmegaIngestionContracts.swift` | V3 workflow 初期为减少文件数而把 contracts 与 domain projection 合并 |
| AHE metric extraction 从 rendered series label 读取 sampleKey | `AHEWorkspaceStore.swift` | 可能在 render labels 与 metric persistence 之间造成脆性合约，应移至 typed ingestion metadata |
| AHE parser 对 Latin-1 fallback 使用 `try?` | `UseCases/AHEDataParser.swift` | 是刻意的 alternate-decoding fallback（failure 已 remap 到 AppError.io），不属于 #6 |
| XY view 在 `Binding.get` 闭包外部计算 `currentValue` | `Features/Workbench/XYRotationWorkspaceView.swift` | SwiftUI body refresh 下应无害，但 phi offset editing 出现 stale 时需关注 |

---

## 5. Fix-Round Draft（5.1.11b 派工预案）

*待 §4.3 收尾对账后填入*

---

## Batch Review Log

### Batch 1 主审完成（Claude，2026-05-02）

审计范围：AS-01–AS-17（Shell 13 + Render 4）。双 lens 全通过，0 Violation，0 Drift，17 Accepted。

### Batch 2a 主审完成（Codex，2026-05-02）

审计范围：AS-18–AS-25（3Omega Workflow 8 文件）。Violation 7 条（High 1 / Med 3 / Low 3），Drift 3 条，Accepted 3 条。

### Batch 2b 主审完成（Codex，2026-05-02）

审计范围：AS-26–AS-33（AHE + XY Rotation + cross-workflow 8 文件）。Violation 9 条（High 3 / Med 5 / Low 1），Drift 4 条，Accepted 2 条。

### Batch 3 主审完成（Claude，2026-05-02）

审计范围：AS-34–AS-44（Persistence 8 + Search 2 + Extension 1）。Violation 1 条（Low #16 SearchUseCase 内建 helper），Drift 1 条（WorkbenchSharedComponents redirect stub），Accepted 11 条。

*Batch 1+3 评审（Codex 评 Claude 方）+ Batch 2 评审（Claude 评 Codex 方）+ §4.3 收尾对账 待完成*
