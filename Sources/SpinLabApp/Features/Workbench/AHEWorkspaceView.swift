import SwiftUI
import AppKit

/// AHE workflow workspace — shell-based layout.
struct AHEWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace

        WorkflowWorkspaceShell(
            workflowID: ahe.workflowID,
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
        @Bindable var workbench = appState.workbench
        @Bindable var bindableAhe = appState.workbench.aheWorkspace

        WorkbenchPlotControlsPanel(
            seriesRenderMode: $bindableAhe.seriesRenderMode,
            globalPlotDefaults: $workbench.globalPlotDefaults,
            chartStyleOverrides: $bindableAhe.chartStyleOverrides,
            onStyleChange: { ahe.rerenderForStyleChange() },
            activeLayout: ahe.tabs.activeLayout,
            axisRangeOverride: ahe.tabs.activeState.axisRangeOverride,
            onAxisBoundUpdate: { bound, value in
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate BEFORE updateAxisBound bound=\(bound) value=\(value.map { String(format: "%g", $0) } ?? "nil") | axisRangeOverride=\(String(describing: ahe.tabs.activeState.axisRangeOverride))")
                ahe.tabs.updateAxisBound(bound, value: value)
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate AFTER updateAxisBound | axisRangeOverride=\(String(describing: ahe.tabs.activeState.axisRangeOverride))")
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate BEFORE rerenderForStyleChange")
                ahe.rerenderForStyleChange()
                AxisRangeDebug.log("AHEWorkspaceView onAxisBoundUpdate AFTER rerenderForStyleChange")
            },
            sourceResetToken: ahe.tabs.activeSourceIdentityKey
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
            SharedPlotTextControls(
                titleOverride: ahe.tabs.activeState.titleOverride,
                xLabelOverride: ahe.tabs.activeState.xLabelOverride,
                yLabelOverride: ahe.tabs.activeState.yLabelOverride,
                renderedTitle: ahe.tabs.activeLayout?.chartTitle ?? "",
                renderedXLabel: ahe.tabs.activeLayout?.xAxisLabel ?? "",
                renderedYLabel: ahe.tabs.activeLayout?.yAxisLabel ?? "",
                sourceResetToken: ahe.tabs.activeSourceIdentityKey,
                onTitleOverride: { ahe.updatePlotTitle($0) },
                onXLabelOverride: { ahe.updateXAxisLabel($0) },
                onYLabelOverride: { ahe.updateYAxisLabel($0) }
            )
            WorkbenchSeriesOrderPanel(
                seriesControlModel: ahe.tabs.activeOutput.seriesControlModel,
                payload: ahe.tabs.activeManifestPayload,
                currentSeriesOrder: ahe.tabs.activeState.seriesOrder,
                hiddenSeriesKeys: ahe.tabs.activeState.hiddenSeriesKeys,
                isVisible: ahe.tabs.activeManifestPayload != nil,
                onCommit: { _ in },
                allowsReordering: false,
                seriesLabelOverrides: ahe.tabs.activeSeriesLabelOverrides,
                onVisibilityChange: { key, isVisible in
                    ahe.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                    appState.flushInteractionSnapshotNow()
                },
                onRenameLabel: { key, label in
                    ahe.updateSeriesLabel(identityKey: key, newLabel: label)
                }
            )
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
