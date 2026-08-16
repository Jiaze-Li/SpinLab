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
                // None of IV's current-basis/channel/fit-mode/zero-origin/angular controls
                // below are represented in SpinLabInteractionSnapshot — they are session-only
                // workspace state, so their onChange handlers intentionally do not schedule
                // an interaction-snapshot flush.
                IVCurrentBasisPicker(
                    basis: Binding(
                        get: { store.xCurrentBasis },
                        set: { newValue in
                            let oldValue = store.xCurrentBasis
                            store.updateXCurrentBasis(newValue, previousBasis: oldValue)
                            store.rerenderForStyleChange()
                        }
                    )
                )

                IVChannelPicker(
                    label: "ch1",
                    component: $store.ch1Component,
                    confidence: store.ch1Confidence,
                    onChange: {
                        store.rerenderForStyleChange()
                    }
                )

                IVChannelPicker(
                    label: "ch2",
                    component: $store.ch2Component,
                    confidence: store.ch2Confidence,
                    onChange: {
                        store.rerenderForStyleChange()
                    }
                )

                IVFitModePicker(
                    mode: Binding(
                        get: { store.fitMode },
                        set: { newValue in
                            store.updateFitMode(newValue)
                            store.rerenderForStyleChange()
                        }
                    )
                )

                IVZeroAtOriginToggle(
                    isOn: $store.zeroAtCurrentOrigin,
                    isEnabled: store.fitMode != .none,
                    onChange: {
                        store.rerenderForStyleChange()
                    }
                )
            }

            HStack(spacing: WorkbenchUIStyle.controlRowSpacing) {
                IVAngularPlotToggle(
                    isOn: Binding(
                        get: { store.angularPlotEnabled },
                        set: { store.updateAngularPlotEnabled($0) }
                    ),
                    isEnabled: store.canEnableAngularPlot,
                    onChange: {
                        store.rerenderForStyleChange()
                    }
                )

                IVAngularFitModePicker(
                    mode: $store.angularFitMode,
                    isEnabled: store.angularPlotEnabled,
                    onChange: {
                        store.rerenderForStyleChange()
                    }
                )

                IVAngularFitFoldPicker(
                    fold: $store.angularFitFold,
                    isEnabled: store.angularPlotEnabled,
                    onChange: {
                        store.rerenderForStyleChange()
                    }
                )
            }
        }
    }
}

// MARK: - Power-law Fit Controls

private struct IVFitModePicker: View {
    @Binding var mode: PowerLawFitMode

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
        }
    }
}

private struct IVZeroAtOriginToggle: View {
    @Binding var isOn: Bool
    let isEnabled: Bool
    let onChange: () -> Void

    var body: some View {
        Toggle("Zero at I=0", isOn: $isOn)
            .font(WorkbenchUIStyle.controlLabelFont)
            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            .disabled(!isEnabled)
            .onChange(of: isOn) { _, _ in onChange() }
    }
}

enum IVAngularPlotToggleLogic {
    /// Keeps the toggle turnable off even after the underlying data stops
    /// supporting angular plotting, so an already-on toggle never gets stuck.
    static func isDisabled(isEnabled: Bool, isOn: Bool) -> Bool {
        !isEnabled && !isOn
    }
}

private struct IVAngularPlotToggle: View {
    @Binding var isOn: Bool
    let isEnabled: Bool
    let onChange: () -> Void

    var body: some View {
        Toggle("Angular plot", isOn: $isOn)
            .font(WorkbenchUIStyle.controlLabelFont)
            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            .disabled(IVAngularPlotToggleLogic.isDisabled(isEnabled: isEnabled, isOn: isOn))
            .onChange(of: isOn) { _, _ in onChange() }
    }
}

// MARK: - Angular Fit Controls

private struct IVAngularFitModePicker: View {
    @Binding var mode: AngularFitMode
    let isEnabled: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text("Angular fit")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $mode) {
                ForEach(AngularFitMode.allCases, id: \.self) { fitMode in
                    Text(IVAngularFitAdapter.fitModeDisplayName(fitMode)).tag(fitMode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 88)
            .font(WorkbenchUIStyle.controlValueFont)
            .disabled(!isEnabled)
            .onChange(of: mode) { _, _ in onChange() }
        }
    }
}

private struct IVAngularFitFoldPicker: View {
    @Binding var fold: Int
    let isEnabled: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchUIStyle.controlInlineSpacing) {
            Text("Fold")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

            Picker("", selection: $fold) {
                ForEach(1...4, id: \.self) { m in
                    Text("\(m)").tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 56)
            .font(WorkbenchUIStyle.controlValueFont)
            .disabled(!isEnabled)
            .onChange(of: fold) { _, _ in onChange() }
        }
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
                Text("\(Int(confidence.rounded()))×")
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
