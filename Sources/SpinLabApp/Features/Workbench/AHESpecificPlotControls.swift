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
    /// Raw user-typed override text. Empty means "no manual edit yet" — the value/reason
    /// fields then display the auto-detected value / "Auto" as ordinary text (not a
    /// placeholder) via the computed bindings below. Auto display never writes into these
    /// or into the persisted override — only an actual edit does.
    @State private var hcValueText: String = ""
    @State private var hcReasonText: String = ""
    @State private var rAHEValueText: String = ""
    @State private var rAHEReasonText: String = ""

    private var ahe: AHEWorkspaceStore { appState.workbench.aheWorkspace }

    private var isMultiSample: Bool {
        ahe.lastExtractedMetrics.count > 1
    }

    private func formatAuto(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%g", value)
    }

    // MARK: - Hc bindings (auto-detected Tesla value shown until the user edits)

    private var hcValueBinding: Binding<String> {
        Binding(
            get: { hcValueText.isEmpty ? formatAuto(ahe.lastExtractedHc) : hcValueText },
            set: { newValue in
                hcValueText = newValue
                ahe.updateHcCandidate(rawValue: newValue, rawReason: hcReasonText)
            }
        )
    }

    private var hcReasonBinding: Binding<String> {
        Binding(
            get: { hcReasonText.isEmpty ? (ahe.lastExtractedHc != nil ? "Auto" : "") : hcReasonText },
            set: { newValue in
                hcReasonText = newValue
                ahe.updateHcCandidate(rawValue: hcValueText, rawReason: newValue)
            }
        )
    }

    // MARK: - R_AHE bindings (auto-detected value shown until the user edits)

    private var rAHEValueBinding: Binding<String> {
        Binding(
            get: { rAHEValueText.isEmpty ? formatAuto(ahe.lastExtractedRAHE) : rAHEValueText },
            set: { newValue in
                rAHEValueText = newValue
                ahe.updateRAHECandidate(rawValue: newValue, rawReason: rAHEReasonText)
            }
        )
    }

    private var rAHEReasonBinding: Binding<String> {
        Binding(
            get: { rAHEReasonText.isEmpty ? (ahe.lastExtractedRAHE != nil ? "Auto" : "") : rAHEReasonText },
            set: { newValue in
                rAHEReasonText = newValue
                ahe.updateRAHECandidate(rawValue: rAHEValueText, rawReason: newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isMultiSample {
                Text("多样本模式不支持统一 Hc/R_AHE override，请绘制单一样本后再修正。")
                    .font(.body)
                    .foregroundStyle(.orange)
            } else {
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
            if let o = ahe.pendingMetricOverride {
                hcValueText = String(o.proposedValue)
                hcReasonText = o.reason
            }
            if let o = ahe.pendingRAHEOverride {
                rAHEValueText = String(o.proposedValue)
                rAHEReasonText = o.reason
            }
        }
        .onChange(of: ahe.pendingMetricOverride) { _, new in
            if new == nil { hcValueText = ""; hcReasonText = "" }
        }
        .onChange(of: ahe.pendingRAHEOverride) { _, new in
            if new == nil { rAHEValueText = ""; rAHEReasonText = "" }
        }
    }

    private var hcFields: some View {
        HStack(spacing: 6) {
            Text("Hc")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("T", text: hcValueBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 56, idealWidth: 64, maxWidth: 72)

            TextField("Reason", text: hcReasonBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, idealWidth: 120, maxWidth: .infinity)

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
        HStack(spacing: 6) {
            Text("R_AHE")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Ω", text: rAHEValueBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 68, idealWidth: 78, maxWidth: 88)

            TextField("Reason", text: rAHEReasonBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 90, idealWidth: 120, maxWidth: .infinity)

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
