import SwiftUI
import AppKit

/// AHE 工作流 workspace view。
/// 列结构直接照抄 LibraryView 的两列框架：
///   左列 → librarySettingsColumn 骨架
///   右列 → libraryDetailColumn 骨架
struct AHEWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell {
            aheLeftColumn
        } rightColumn: {
            aheRightColumn
        }
    }

    // MARK: - 左列

    private var aheLeftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 固定控制区（始终可见）────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline) {
                    Text(appState.workbench.selectedWorkflowDefinition?.displayName ?? "Workflow")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.top, 4)

                AHESearchSection()
                    .environment(appState)

                AHEPlotControlsPanel()
                    .environment(appState)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // ── 可滚动结果列表 ──────────────────────────────────────
            AHEResultsList()
                .environment(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 右列（镜像 libraryDetailColumn）

    private var aheRightColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {

                // 列标题（镜像 sampleDetailHeader）
                HStack {
                    Text("Result")
                        .font(.title2.bold())
                    Spacer()
                    Button("Save to Library") {
                        appState.workbench.aheWorkspace.persistToLibrary {
                            appState.library.loadWorkbenchResultsForCurrentSelection()
                            appState.library.loadMeasurementDataForCurrentSelection()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.workbench.aheWorkspace.currentPlotImageData == nil)
                }

                // 内容区
                WorkbenchStatusArea(
                    searchMessage: nil,
                    plotMessage: appState.workbench.aheWorkspace.plotMessage,
                    loadMessage: nil
                )

                WorkbenchPlotCanvas(
                    imageData: appState.workbench.aheWorkspace.currentPlotImageData,
                    layout: appState.workbench.aheWorkspace.currentPlotLayout,
                    seriesLabelOverrides: appState.workbench.aheWorkspace.plotSeriesLabelOverrides,
                    onLegendDrag: { pt in appState.workbench.aheWorkspace.updateLegendPoint(pt) },
                    onEditTitle: { title in appState.workbench.aheWorkspace.updatePlotTitle(title) },
                    onEditXLabel: { label in appState.workbench.aheWorkspace.updateXAxisLabel(label) },
                    onEditYLabel: { label in appState.workbench.aheWorkspace.updateYAxisLabel(label) },
                    onEditLegendLabel: { idx, label in
                        appState.workbench.aheWorkspace.updateSeriesLabel(index: idx, newLabel: label)
                    }
                )

                WorkbenchTracePanel(trace: appState.workbench.aheWorkspace.currentRunTrace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }
}

// MARK: - 左列：搜索 + 操作区

private struct AHESearchSection: View {
    @Environment(SpinLabAppState.self) private var appState

    private let wf: WorkbenchWorkflowID = .ahe

    var body: some View {
        @Bindable var workbench = appState.workbench
        let ahe = appState.workbench.aheWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        let queryBinding = Binding<String>(
            get: { workbench.searchQueryText(for: wf) },
            set: { workbench.setSearchQueryText($0, for: wf) }
        )

        VStack(alignment: .leading, spacing: 8) {
            TextField("ahe PN31, ahe 80K …", text: queryBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    workbench.runWorkflowMeasurementSearch(workflowID: wf, libraryRootPath: libraryRoot)
                }

            HStack(spacing: 4) {
                Text("Library Root:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(libraryRoot ?? "Not configured — set in Library settings")
                    .font(.caption)
                    .foregroundStyle(libraryRoot == nil ? .red : .secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button("Search") {
                    workbench.runWorkflowMeasurementSearch(workflowID: wf, libraryRootPath: libraryRoot)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workbench.isSearchRunning(for: wf) || libraryRoot == nil)

                Button("Clear") {
                    workbench.clearWorkflowMeasurementSearch(workflowID: wf)
                }
                .buttonStyle(.bordered)

                Button("Plot") {
                    ahe.renderAHEPlot()
                }
                .buttonStyle(.bordered)
                .disabled(ahe.selectedSearchResultIDs.isEmpty || ahe.isPlotRendering)

                Button("Clear Plot") {
                    ahe.clearPlot()
                }
                .buttonStyle(.bordered)
                .disabled(ahe.currentPlotImageData == nil && !ahe.isPlotRendering)

                if workbench.isSearchRunning(for: wf) || ahe.isPlotRendering {
                    ProgressView().controlSize(.small)
                }
            }

            AHEMetricOverridePanel()
                .environment(appState)

            AHERAHEOverridePanel()
                .environment(appState)
        }
    }
}

// MARK: - Pre-persist Metric Override Panel

/// Lets the user enter an optional manual correction for the extracted Hc value
/// before clicking "Plot" (which triggers persist). If left empty, no override is applied.
/// Multi-sample mode: shows per-sample auto-detected values read-only; override is disabled.
private struct AHEMetricOverridePanel: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var valueText: String = ""
    @State private var reasonText: String = ""

    private var isMultiSample: Bool {
        appState.workbench.aheWorkspace.lastExtractedMetrics.count > 1
    }

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace
        let sortedMetrics = ahe.lastExtractedMetrics.values.sorted(by: { $0.sampleKey < $1.sampleKey })

        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
                // Multi-sample: read-only per-sample display
                Text("Hc (auto-detected per sample)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sortedMetrics, id: \.sampleKey) { m in
                    Text("\(m.sampleKey): \(String(format: "%g", m.hc)) T")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                Text("多样本模式不支持统一 override，请逐个绘制后修正")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                // Single-sample: editable override
                HStack(spacing: 8) {
                    Text("Hc Override (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let hc = ahe.lastExtractedHc {
                        Text("Auto-detected: \(String(format: "%g", hc)) T")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 6) {
                    TextField("Corrected Hc (T)", text: $valueText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onChange(of: valueText) { _, new in updateCandidate(value: new, reason: reasonText) }

                    TextField("Reason", text: $reasonText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: reasonText) { _, new in updateCandidate(value: valueText, reason: new) }

                    if ahe.pendingMetricOverride != nil {
                        Button("Clear") {
                            valueText = ""
                            reasonText = ""
                            ahe.pendingMetricOverride = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if ahe.pendingMetricOverride != nil {
                    Text("Override will be applied on next Plot.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            if let o = appState.workbench.aheWorkspace.pendingMetricOverride {
                valueText = String(o.proposedValue)
                reasonText = o.reason
            }
        }
        .onChange(of: appState.workbench.aheWorkspace.pendingMetricOverride) { _, new in
            if new == nil { valueText = ""; reasonText = "" }
        }
    }

    private func updateCandidate(value: String, reason: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            appState.workbench.aheWorkspace.pendingMetricOverride = nil
        } else if let parsed = Double(trimmedValue) {
            let effectiveReason = trimmedReason.isEmpty ? "visual check" : trimmedReason
            appState.workbench.aheWorkspace.pendingMetricOverride = WorkbenchMetricOverrideCandidate(
                proposedValue: parsed,
                reason: effectiveReason,
                source: .manual
            )
        } else {
            appState.workbench.aheWorkspace.pendingMetricOverride = nil
        }
    }
}

// MARK: - Pre-persist R_AHE Override Panel

/// Lets the user enter an optional manual correction for the extracted R_AHE value
/// before clicking "Plot". Mirrors `AHEMetricOverridePanel` for the R_AHE metric.
/// Multi-sample mode: shows per-sample auto-detected values read-only; override is disabled.
private struct AHERAHEOverridePanel: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var valueText: String = ""
    @State private var reasonText: String = ""

    private var isMultiSample: Bool {
        appState.workbench.aheWorkspace.lastExtractedMetrics.count > 1
    }

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace
        let sortedMetrics = ahe.lastExtractedMetrics.values.sorted(by: { $0.sampleKey < $1.sampleKey })

        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
                Text("R_AHE (auto-detected per sample)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sortedMetrics, id: \.sampleKey) { m in
                    Text("\(m.sampleKey): \(String(format: "%g", m.rAHE)) Ω")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                Text("多样本模式不支持统一 override，请逐个绘制后修正")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 8) {
                    Text("R_AHE Override (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rAHE = ahe.lastExtractedRAHE {
                        Text("Auto-detected: \(String(format: "%g", rAHE)) Ω")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 6) {
                    TextField("Corrected R_AHE (Ω)", text: $valueText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onChange(of: valueText) { _, new in updateCandidate(value: new, reason: reasonText) }

                    TextField("Reason", text: $reasonText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: reasonText) { _, new in updateCandidate(value: valueText, reason: new) }

                    if ahe.pendingRAHEOverride != nil {
                        Button("Clear") {
                            valueText = ""
                            reasonText = ""
                            ahe.pendingRAHEOverride = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if ahe.pendingRAHEOverride != nil {
                    Text("Override will be applied on next Plot.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            if let o = appState.workbench.aheWorkspace.pendingRAHEOverride {
                valueText = String(o.proposedValue)
                reasonText = o.reason
            }
        }
        .onChange(of: appState.workbench.aheWorkspace.pendingRAHEOverride) { _, new in
            if new == nil { valueText = ""; reasonText = "" }
        }
    }

    private func updateCandidate(value: String, reason: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            appState.workbench.aheWorkspace.pendingRAHEOverride = nil
        } else if let parsed = Double(trimmedValue) {
            let effectiveReason = trimmedReason.isEmpty ? "visual check" : trimmedReason
            appState.workbench.aheWorkspace.pendingRAHEOverride = WorkbenchMetricOverrideCandidate(
                proposedValue: parsed,
                reason: effectiveReason,
                source: .manual
            )
        } else {
            appState.workbench.aheWorkspace.pendingRAHEOverride = nil
        }
    }
}

// MARK: - 左列：可滚动结果列表

private struct AHEResultsList: View {
    @Environment(SpinLabAppState.self) private var appState
    private let wf: WorkbenchWorkflowID = .ahe

    var body: some View {
        let workbench = appState.workbench
        let ahe = appState.workbench.aheWorkspace
        let results = workbench.searchResultsList(for: wf)
        let message = workbench.searchMessage(for: wf)

        if results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let msg = message, !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Run a search to find measurements.")
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if let msg = message, !msg.isEmpty {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { hit in
                        let isSelected = ahe.selectedSearchResultIDs.contains(hit.id)
                        WorkflowHitRow(hit: hit, isSelected: isSelected) {
                            ahe.toggleSearchHitSelection(hit.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - 图表参数面板

private struct AHEPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace
        let candidates = ahe.currentCandidateAxisFields.isEmpty
            ? ["Magnetic Field (Oe)", "Magnetic Field (T)", "Temperature (K)",
               "R_H (\u{03A9})", "Bridge 1 Resistance (Ohms)", "Bridge 2 Resistance (Ohms)", "Bridge 3 Resistance (Ohms)"]
            : ahe.currentCandidateAxisFields

        WorkbenchPlotControlsPanel {
            VStack(alignment: .leading, spacing: 2) {
                Text("X Axis").font(.caption).foregroundStyle(.secondary)
                Picker("X Axis", selection: $ahe.plotAxisXOverride) {
                    Text("Default").tag("")
                    ForEach(candidates, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Y Axis").font(.caption).foregroundStyle(.secondary)
                Picker("Y Axis", selection: $ahe.plotAxisYOverride) {
                    Text("Default").tag("")
                    ForEach(candidates, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Toggle("Grid", isOn: $ahe.showPlotGrid)
                    .toggleStyle(.checkbox)
            }
        }
    }
}

