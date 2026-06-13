import SwiftUI
import AppKit

/// AHE workflow workspace — shell-based layout.
struct AHEWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace

        WorkflowWorkspaceShell(
            workflowID: .ahe,
            store: ahe,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                AHEPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: {
                AHEMetricOverridePanel()
                    .environment(appState)
                AHERAHEOverridePanel()
                    .environment(appState)
            },
            rightExtra: { EmptyView() }
        )
    }
}

// MARK: - AHE Plot Controls Panel (title + grid)

private struct AHEPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace
        @Bindable var bindableAhe = appState.workbench.aheWorkspace

        WorkbenchPlotControlsPanel(
            seriesRenderMode: $bindableAhe.seriesRenderMode,
            chartStyleOverrides: $bindableAhe.chartStyleOverrides,
            onStyleChange: { ahe.rerenderForStyleChange() }
        ) {
            HStack(alignment: .top, spacing: 12) {
                WorkbenchTitleTemplateField(
                    titleTemplate: $bindableAhe.titleTemplate,
                    numericDisplayCache: ahe.cachedSampleNumericDisplay,
                    onChange: {
                        appState.flushInteractionSnapshotNow()
                    }
                )
                Toggle("Grid", isOn: $bindableAhe.showPlotGrid)
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
            }
            HStack(spacing: 10) {
                LabelOverrideField(
                    label: "Title",
                    renderedDefault: ahe.tabs.activeLayout?.chartTitle ?? "",
                    currentValue: ahe.tabs.activeState.titleOverride,
                    onCommit: { ahe.updatePlotTitle($0) },
                    fieldMaxWidth: 200
                )
                LabelOverrideField(
                    label: "X",
                    renderedDefault: ahe.tabs.activeLayout?.xAxisLabel ?? "",
                    currentValue: ahe.tabs.activeState.xLabelOverride,
                    onCommit: { ahe.updateXAxisLabel($0) },
                    fieldMaxWidth: 80
                )
                LabelOverrideField(
                    label: "Y",
                    renderedDefault: ahe.tabs.activeLayout?.yAxisLabel ?? "",
                    currentValue: ahe.tabs.activeState.yLabelOverride,
                    onCommit: { ahe.updateYAxisLabel($0) },
                    fieldMaxWidth: 80
                )
            }
        }
    }
}

// MARK: - Pre-persist Metric Override Panel (Hc)

private struct AHEMetricOverridePanel: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var valueText: String = ""
    @State private var reasonText: String = ""

    private var isMultiSample: Bool {
        appState.workbench.aheWorkspace.lastExtractedMetrics.count > 1
    }

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace

        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
                Text("Hc (auto-detected per sample)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ahe.sortedExtractedMetrics, id: \.sampleKey) { m in
                    Text("\(m.sampleKey): \(String(format: "%g", m.hc)) T")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                Text("多样本模式不支持统一 override，请逐个绘制后修正")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
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
                        .onChange(of: valueText) { _, new in ahe.updateHcCandidate(rawValue: new, rawReason: reasonText) }

                    TextField("Reason", text: $reasonText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: reasonText) { _, new in ahe.updateHcCandidate(rawValue: valueText, rawReason: new) }

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
}

// MARK: - Pre-persist R_AHE Override Panel

private struct AHERAHEOverridePanel: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var valueText: String = ""
    @State private var reasonText: String = ""

    private var isMultiSample: Bool {
        appState.workbench.aheWorkspace.lastExtractedMetrics.count > 1
    }

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace

        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
                Text("R_AHE (auto-detected per sample)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ahe.sortedExtractedMetrics, id: \.sampleKey) { m in
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
                        .onChange(of: valueText) { _, new in ahe.updateRAHECandidate(rawValue: new, rawReason: reasonText) }

                    TextField("Reason", text: $reasonText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: reasonText) { _, new in ahe.updateRAHECandidate(rawValue: valueText, rawReason: new) }

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
}
