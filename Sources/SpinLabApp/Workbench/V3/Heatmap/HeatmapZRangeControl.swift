import SwiftUI

struct HeatmapZRangeControl: View {
    let zDomainState: HeatmapZDomainState
    let onZDomainStateChange: (HeatmapZDomainState) -> Void

    private var validationIssue: HeatmapZDomainValidationIssue? {
        zDomainState.validationIssue()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Z Range")
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                    .fixedSize()

                Picker("", selection: Binding<HeatmapZDomainMode>(
                    get: { zDomainState.mode },
                    set: { newMode in
                        var next = zDomainState
                        next.mode = newMode
                        onZDomainStateChange(next)
                    }
                )) {
                    Text("Auto").tag(HeatmapZDomainMode.auto)
                    Text("Manual").tag(HeatmapZDomainMode.manual)
                    Text("Percentile").tag(HeatmapZDomainMode.percentile)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            switch zDomainState.mode {
            case .auto:
                EmptyView()

            case .manual:
                manualControls

            case .percentile:
                percentileControls
            }

            if let validationIssue {
                Text(validationIssue.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: normalizeCustomPercentilePresetIfNeeded)
        .onChange(of: zDomainState.mode) { _, _ in
            normalizeCustomPercentilePresetIfNeeded()
        }
        .onChange(of: zDomainState.percentilePreset) { _, _ in
            normalizeCustomPercentilePresetIfNeeded()
        }
    }

    private var manualControls: some View {
        HStack(spacing: 8) {
            labeledField(label: "Min", text: Binding(
                get: { zDomainState.manualRange.minText },
                set: { newValue in
                    var next = zDomainState
                    next.manualRange.minText = newValue
                    onZDomainStateChange(next)
                }
            ))

            labeledField(label: "Max", text: Binding(
                get: { zDomainState.manualRange.maxText },
                set: { newValue in
                    var next = zDomainState
                    next.manualRange.maxText = newValue
                    onZDomainStateChange(next)
                }
            ))
        }
    }

    private var percentileControls: some View {
        HStack(spacing: 8) {
            Text("Preset")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()

            Picker("", selection: Binding<HeatmapPercentilePreset>(
                get: { zDomainState.percentilePreset == .custom ? .p1_99 : zDomainState.percentilePreset },
                set: { newPreset in
                    var next = zDomainState
                    next.percentilePreset = newPreset
                    onZDomainStateChange(next)
                }
            )) {
                ForEach(HeatmapPercentilePreset.visiblePresets, id: \.self) { preset in
                    Text(preset.displayTitle).tag(preset)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        }
    }

    private func normalizeCustomPercentilePresetIfNeeded() {
        guard zDomainState.mode == .percentile, zDomainState.percentilePreset == .custom else {
            return
        }
        var next = zDomainState
        next.percentilePreset = .p1_99
        onZDomainStateChange(next)
    }

    private func labeledField(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
        }
    }
}
