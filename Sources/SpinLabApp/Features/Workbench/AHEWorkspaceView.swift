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

// MARK: - AHE Plot Controls Panel (axis pickers + title + grid)

private struct AHEPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace
        let candidates = ahe.currentCandidateAxisFields.isEmpty
            ? ["Magnetic Field (Oe)", "Magnetic Field (T)", "Temperature (K)",
               "R_H (\u{03A9})", "Bridge 1 Resistance (Ohms)", "Bridge 2 Resistance (Ohms)", "Bridge 3 Resistance (Ohms)"]
            : ahe.currentCandidateAxisFields

        WorkbenchPlotControlsPanel(
            seriesRenderMode: $ahe.seriesRenderMode,
            chartStyleOverrides: $ahe.chartStyleOverrides,
            onStyleChange: { ahe.rerenderForStyleChange() }
        ) {
            HStack(spacing: 8) {
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
            }
            HStack(alignment: .top, spacing: 12) {
                WorkbenchTitleTemplateField(
                    titleTemplate: $ahe.titleTemplate,
                    numericDisplayCache: ahe.cachedSampleNumericDisplay,
                    onChange: {
                        appState.flushInteractionSnapshotNow()
                    }
                )
                Toggle("Grid", isOn: $ahe.showPlotGrid)
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
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
        let sortedMetrics = ahe.lastExtractedMetrics.values.sorted(by: { $0.sampleKey < $1.sampleKey })

        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
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
