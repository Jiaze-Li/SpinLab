import SwiftUI

// MARK: - IV-specific Plot Controls (current basis + channel assignment)
//
// These render inside `IVPlotControlsPanel`'s `WorkbenchStandardPlotControls.extraContent`,
// wrapped in a `WorkbenchPlotControlsPluginSection` — they are IV's plugin-section
// controls, not workspace side panels.

struct IVSpecificPlotControls: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.ivWorkspace

        WorkbenchPlotControlsPluginSection {
            HStack(spacing: WorkbenchUIStyle.controlRowSpacing) {
                IVCurrentBasisPicker(
                    basis: Binding(
                        get: { store.xCurrentBasis },
                        set: { newValue in
                            let oldValue = store.xCurrentBasis
                            store.updateXCurrentBasis(newValue, previousBasis: oldValue)
                            store.rerenderForStyleChange()
                            appState.scheduleInteractionSnapshotFlush(source: "ivCurrentBasisChange")
                        }
                    )
                )

                IVChannelPicker(
                    label: "ch1",
                    component: $store.ch1Component,
                    confidence: store.ch1Confidence,
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "ivChannelChange")
                    }
                )

                IVChannelPicker(
                    label: "ch2",
                    component: $store.ch2Component,
                    confidence: store.ch2Confidence,
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "ivChannelChange")
                    }
                )

                IVFitModePicker(
                    mode: $store.fitMode,
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "ivFitModeChange")
                    }
                )

                IVZeroAtOriginToggle(
                    isOn: $store.zeroAtCurrentOrigin,
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "ivFitZeroAtOriginChange")
                    }
                )
            }
        }
    }
}

// MARK: - Power-law Fit Controls

private struct IVFitModePicker: View {
    @Binding var mode: PowerLawFitMode
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text("Fit")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $mode) {
                ForEach(PowerLawFitMode.allCases, id: \.self) { fitMode in
                    Text(IVPowerLawFitAdapter.fitModeDisplayName(fitMode)).tag(fitMode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 72)
            .font(WorkbenchUIStyle.controlValueFont)
            .onChange(of: mode) { _, _ in onChange() }
        }
    }
}

private struct IVZeroAtOriginToggle: View {
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        Toggle("Zero at I=0", isOn: $isOn)
            .font(WorkbenchUIStyle.controlLabelFont)
            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            .onChange(of: isOn) { _, _ in onChange() }
    }
}

// MARK: - Channel Picker

private struct IVCurrentBasisPicker: View {
    @Binding var basis: IVCurrentBasis

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text("X basis")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $basis) {
                ForEach(IVCurrentBasis.allCases, id: \.self) { currentBasis in
                    Text(currentBasis.displayName).tag(currentBasis)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 88)
            .font(WorkbenchUIStyle.controlValueFont)
        }
    }
}

private struct IVChannelPicker: View {
    let label: String
    @Binding var component: IVSignalComponent
    let confidence: Double
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $component) {
                ForEach(IVSignalComponent.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 56)
            .font(WorkbenchUIStyle.controlValueFont)
            .onChange(of: component) { _, _ in onChange() }

            if confidence > 1.01 {
                Text("\(confidence, specifier: "%.1f")×")
                    .font(WorkbenchUIStyle.confidenceBadgeFont)
                    .foregroundStyle(WorkbenchUIStyle.confidenceBadgeForeground)
                    .monospacedDigit()
                    .padding(.horizontal, WorkbenchUIStyle.chipHorizontalPadding)
                    .padding(.vertical, WorkbenchUIStyle.chipVerticalPadding)
                    .background(
                        WorkbenchUIStyle.confidenceBadgeBackground,
                        in: RoundedRectangle(cornerRadius: WorkbenchUIStyle.chipCornerRadius, style: .continuous)
                    )
                    .help(autoConfidenceHelpText)
                    .accessibilityLabel(autoConfidenceHelpText)
            }
        }
    }

    private var autoConfidenceHelpText: String {
        let axis = component.rawValue.uppercased()
        let otherAxis = axis == "X" ? "Y" : "X"
        return String(format: "Auto confidence: %@ is %.1f× stronger than %@", axis, confidence, otherAxis)
    }
}
