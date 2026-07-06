import SwiftUI

// MARK: - AHE-specific Plot Controls (Hc / R_AHE pre-persist overrides)
//
// These render inside `AHEPlotControlsPanel`'s `WorkbenchPlotControlsPanel.extraContent`,
// wrapped in a `WorkbenchPlotControlsPluginSection` — they are AHE's plugin-section
// controls, not workspace side panels.

private extension Font {
    /// Slightly larger/heavier than `.caption2 + .secondary` so hint and section-label
    /// text stays legible without competing with the primary controls.
    static let ahePlotHint = Font.system(size: 11, weight: .medium)
}

// MARK: - Pre-persist Metric Override Controls (Hc + R_AHE, single compact row)

struct AHEOverridesControls: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var hcValueText: String = ""
    @State private var hcReasonText: String = ""
    @State private var rAHEValueText: String = ""
    @State private var rAHEReasonText: String = ""

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
                    .font(.ahePlotHint)
                    .foregroundStyle(.secondary)
                ForEach(ahe.sortedExtractedMetrics, id: \.sampleKey) { m in
                    Text("\(m.sampleKey): \(autoDetectedHcText(m.hc, unit: unit))")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                Text("R_AHE (auto-detected per sample)")
                    .font(.ahePlotHint)
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
                if ahe.lastExtractedHc != nil || ahe.lastExtractedRAHE != nil {
                    HStack(spacing: 8) {
                        if let hc = ahe.lastExtractedHc {
                            Text("Auto Hc: \(autoDetectedHcText(hc, unit: unit))")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        if let rAHE = ahe.lastExtractedRAHE {
                            Text("Auto R_AHE: \(String(format: "%g", rAHE)) Ω")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Text("Overrides")
                            .font(.ahePlotHint)
                            .foregroundStyle(.secondary)
                        hcFields
                        rAHEFields
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Overrides")
                            .font(.ahePlotHint)
                            .foregroundStyle(.secondary)
                        hcFields
                        rAHEFields
                    }
                }

                if ahe.pendingMetricOverride != nil || ahe.pendingRAHEOverride != nil {
                    Text("Override will be applied on next Plot.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            if let o = appState.workbench.aheWorkspace.pendingMetricOverride {
                hcValueText = String(o.proposedValue)
                hcReasonText = o.reason
            }
            if let o = appState.workbench.aheWorkspace.pendingRAHEOverride {
                rAHEValueText = String(o.proposedValue)
                rAHEReasonText = o.reason
            }
        }
        .onChange(of: appState.workbench.aheWorkspace.pendingMetricOverride) { _, new in
            if new == nil { hcValueText = ""; hcReasonText = "" }
        }
        .onChange(of: appState.workbench.aheWorkspace.pendingRAHEOverride) { _, new in
            if new == nil { rAHEValueText = ""; rAHEReasonText = "" }
        }
    }

    private var hcFields: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace

        return HStack(spacing: 6) {
            Text("Hc")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("T", text: $hcValueText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 56, idealWidth: 64, maxWidth: 72)
                .onChange(of: hcValueText) { _, new in ahe.updateHcCandidate(rawValue: new, rawReason: hcReasonText) }

            TextField("Reason", text: $hcReasonText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, idealWidth: 120, maxWidth: .infinity)
                .onChange(of: hcReasonText) { _, new in ahe.updateHcCandidate(rawValue: hcValueText, rawReason: new) }

            if ahe.pendingMetricOverride != nil {
                Button("Clear") {
                    hcValueText = ""
                    hcReasonText = ""
                    ahe.pendingMetricOverride = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var rAHEFields: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace

        return HStack(spacing: 6) {
            Text("R_AHE")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Ω", text: $rAHEValueText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 68, idealWidth: 78, maxWidth: 88)
                .onChange(of: rAHEValueText) { _, new in ahe.updateRAHECandidate(rawValue: new, rawReason: rAHEReasonText) }

            TextField("Reason", text: $rAHEReasonText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, idealWidth: 120, maxWidth: .infinity)
                .onChange(of: rAHEReasonText) { _, new in ahe.updateRAHECandidate(rawValue: rAHEValueText, rawReason: new) }

            if ahe.pendingRAHEOverride != nil {
                Button("Clear") {
                    rAHEValueText = ""
                    rAHEReasonText = ""
                    ahe.pendingRAHEOverride = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
