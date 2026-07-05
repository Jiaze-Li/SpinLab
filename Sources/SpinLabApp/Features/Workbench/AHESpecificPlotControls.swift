import SwiftUI

// MARK: - AHE-specific Plot Controls (Hc / R_AHE pre-persist overrides)
//
// These render inside `AHEPlotControlsPanel`'s `WorkbenchPlotControlsPanel.extraContent`,
// wrapped in a `WorkbenchPlotControlsPluginSection` — they are AHE's plugin-section
// controls, not workspace side panels.

// MARK: - Pre-persist Metric Override Controls (Hc)

struct AHEMetricOverrideControls: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var valueText: String = ""
    @State private var reasonText: String = ""

    private var isMultiSample: Bool {
        appState.workbench.aheWorkspace.lastExtractedMetrics.count > 1
    }

    /// Read-only auto-detected Hc, in the same magnitude-selected unit as the chart (Hc is
    /// extracted from the H-axis series — see `AHEWorkspaceStore.fieldDisplayUnit`). The
    /// editable override input below stays Tesla-only regardless — it feeds directly into the
    /// persisted metric override, which is always stored under `canonicalUnit: "T"`.
    private func autoDetectedHcText(_ hcTesla: Double, unit: MagneticFieldUnit) -> String {
        let converted = WorkbenchMagneticFieldUnitConverter.convert(hcTesla, from: .tesla, to: unit)
        let label = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .uiText, unit: unit)
        return "\(String(format: "%g", converted)) \(label)"
    }

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace
        let unit = ahe.fieldDisplayUnit

        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
                Text("Hc (auto-detected per sample)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ahe.sortedExtractedMetrics, id: \.sampleKey) { m in
                    Text("\(m.sampleKey): \(autoDetectedHcText(m.hc, unit: unit))")
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
                        Text("Auto-detected: \(autoDetectedHcText(hc, unit: unit))")
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

// MARK: - Pre-persist R_AHE Override Controls

struct AHERAHEOverrideControls: View {
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
