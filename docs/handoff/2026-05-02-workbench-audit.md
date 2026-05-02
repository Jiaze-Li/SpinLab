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

| ID | File | Layer | 违规信号编号 (§2 Step C #N) | caller→callee→行为 | 风险等级 | Final Disposition |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

*待批次审计填入*

---

## 2. Doc Drift Fixed（已当场改 Code Map 注释）

| File | 旧注释 | 新注释 | 修订理由 | commit_id |
|---|---|---|---|---|
| — | — | — | — | — |

*待批次审计填入*

---

## 3. Accepted Boundaries（跨区是有意为之）

| File | 跨区现象 | 接受理由 | Final Disposition |
|---|---|---|---|
| — | — | — | — |

*待批次审计填入*

---

## 4. Cross-Region Doubts For 5.1.14

| 现象 | 涉及文件 | 一句猜测 |
|---|---|---|
| — | — | — |

*待批次审计填入*

---

## 5. Fix-Round Draft（5.1.11b 派工预案）

*待 §4.3 收尾对账后填入*

---

## Batch Review Log

*待各批次主审完成后，评审方追加子段*
