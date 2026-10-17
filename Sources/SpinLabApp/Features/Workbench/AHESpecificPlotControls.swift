import SwiftUI

// MARK: - AHE-specific controls (Hc / R_AHE pre-persist overrides)
//
// Specific content for the shared Controls Surface (spec 06 §5, "Metric Overrides"). The
// leaf inputs below take plain values and closures; `AHEWorkspaceView` reads the store and
// supplies them (CS-28).

/// Pending override text carried back into the field when the store already holds one.
struct AHEOverrideSeed: Equatable {
    var value: String
    var reason: String
}

/// One metric's override editor: value + reason + Clear. Edit drafts live here; an empty draft
/// shows the auto-detected value / "Auto" as ordinary text and never writes it back.
struct AHEMetricOverrideInput: WorkbenchLeafInput {
    let metricLabel: String
    let valuePrompt: String
    let valueWidth: ClosedRange<CGFloat>
    let autoValue: Double?
    let pending: AHEOverrideSeed?
    let onEdit: (_ value: String, _ reason: String) -> Void
    let onClear: () -> Void

    @State private var valueText: String = ""
    @State private var reasonText: String = ""

    private var valueBinding: Binding<String> {
        Binding(
            get: { valueText.isEmpty ? Self.formatAuto(autoValue) : valueText },
            set: { newValue in
                valueText = newValue
                onEdit(newValue, reasonText)
            }
        )
    }

    private var reasonBinding: Binding<String> {
        Binding(
            get: { reasonText.isEmpty ? (autoValue != nil ? "Auto" : "") : reasonText },
            set: { newValue in
                reasonText = newValue
                onEdit(valueText, newValue)
            }
        )
    }

    private static func formatAuto(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%g", value)
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(metricLabel)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(.secondary)
            TextField(valuePrompt, text: valueBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: valueWidth.lowerBound, idealWidth: (valueWidth.lowerBound + valueWidth.upperBound) / 2, maxWidth: valueWidth.upperBound)
            TextField("Reason", text: reasonBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: WorkbenchInputWidth.compact, idealWidth: WorkbenchInputWidth.standard, maxWidth: .infinity)
            if pending != nil {
                Button("Clear") {
                    valueText = ""
                    reasonText = ""
                    onClear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onAppear {
            if let pending {
                valueText = pending.value
                reasonText = pending.reason
            }
        }
        .onChange(of: pending) { _, new in
            if new == nil { valueText = ""; reasonText = "" }
        }
    }
}

extension AHEWorkspaceStore {
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        standardControlsDescriptor(
            appState: appState,
            globalPlotDefaults: globalPlotDefaults,
            flushSource: "aheStyleChange",
            // AHE's protocol defaults report reorder state as false/nil; its real state lives
            // only in the tab render state and it is always reorderable.
            canReorderSeries: true,
            currentSeriesOrder: tabs.activeState.seriesOrder,
            rendererTitleTokens: ["tab"],
            specific: controlsSpecificContent
        )
    }

    /// AHE's Specific content: Metric Overrides (Hc, R_AHE).
    @MainActor
    var controlsSpecificContent: WorkbenchSpecificContent {
        let hcSeed = pendingMetricOverride.map { AHEOverrideSeed(value: String($0.proposedValue), reason: $0.reason) }
        let rAHESeed = pendingRAHEOverride.map { AHEOverrideSeed(value: String($0.proposedValue), reason: $0.reason) }
        let isMultiSample = lastExtractedMetrics.count > 1
        let hasPending = pendingMetricOverride != nil || pendingRAHEOverride != nil
        return WorkbenchSpecificContent {
            WorkbenchSpecificGroup("metricOverrides", title: "Metric Overrides") {
                if isMultiSample {
                    WorkbenchSpecificRow("unsupported") {
                        WorkbenchSpecificInput.readout("message", text: "多样本模式不支持统一 Hc/R_AHE override，请绘制单一样本后再修正。")
                    }
                } else {
                    WorkbenchSpecificRow("hc") {
                        WorkbenchSpecificInput.control("field", fills: true, AHEMetricOverrideInput(
                            metricLabel: "Hc", valuePrompt: "T", valueWidth: 56...72,
                            autoValue: lastExtractedHc, pending: hcSeed,
                            onEdit: { self.updateHcCandidate(rawValue: $0, rawReason: $1) },
                            onClear: { self.pendingMetricOverride = nil }))
                    }
                    WorkbenchSpecificRow("rahe") {
                        WorkbenchSpecificInput.control("field", fills: true, AHEMetricOverrideInput(
                            metricLabel: "R_AHE", valuePrompt: "Ω", valueWidth: 68...88,
                            autoValue: lastExtractedRAHE, pending: rAHESeed,
                            onEdit: { self.updateRAHECandidate(rawValue: $0, rawReason: $1) },
                            onClear: { self.pendingRAHEOverride = nil }))
                    }
                    if hasPending {
                        WorkbenchSpecificRow("pendingHint") {
                            WorkbenchSpecificInput.readout("message", text: "Override will be applied on next Plot.")
                        }
                    }
                }
            }
        }
    }
}
