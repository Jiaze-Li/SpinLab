import SwiftUI

// MARK: - IV-specific controls (current basis, channel assignment, fitting, angular analysis)
//
// Specific content for the shared Controls Surface (spec 06 §5). The leaf inputs below take
// bindings and closures only; the store is read here, once, by the adapter (CS-28).

extension IVWorkspaceStore {
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        standardControlsDescriptor(
            appState: appState,
            globalPlotDefaults: globalPlotDefaults,
            flushSource: "ivStyleChange",
            canReorderSeries: canReorderSeries,
            currentSeriesOrder: activeSeriesOrder,
            rendererTitleTokens: ["tab", "device"],
            specific: controlsSpecificContent
        )
    }

    /// IV's Specific content: Input · Channel Assignment · Fitting · Angular Analysis.
    /// None of these values is part of `SpinLabInteractionSnapshot` (session-only workspace
    /// state), so their changes re-render without scheduling a snapshot flush.
    @MainActor
    var controlsSpecificContent: WorkbenchSpecificContent {
        let rerender: () -> Void = { self.rerenderForStyleChange() }
        return WorkbenchSpecificContent {
            WorkbenchSpecificGroup("input", title: "Input") {
                WorkbenchSpecificRow("currentBasis") {
                    WorkbenchSpecificInput.control("picker", IVCurrentBasisPicker(
                        basis: Binding(
                            get: { self.xCurrentBasis },
                            set: { newValue in
                                let oldValue = self.xCurrentBasis
                                self.updateXCurrentBasis(newValue, previousBasis: oldValue)
                                rerender()
                            })))
                }
            }
            WorkbenchSpecificGroup("channels", title: "Channel Assignment") {
                WorkbenchSpecificRow("channels", label: "Channels") {
                    WorkbenchSpecificInput.control("ch1", IVChannelPicker(
                        label: "ch1",
                        component: Binding(get: { self.ch1Component }, set: { self.ch1Component = $0 }),
                        confidence: ch1Confidence,
                        onChange: rerender))
                    WorkbenchSpecificInput.control("ch2", IVChannelPicker(
                        label: "ch2",
                        component: Binding(get: { self.ch2Component }, set: { self.ch2Component = $0 }),
                        confidence: ch2Confidence,
                        onChange: rerender))
                }
            }
            WorkbenchSpecificGroup("fitting", title: "Fitting") {
                WorkbenchSpecificRow("fit") {
                    WorkbenchSpecificInput.control("mode", IVFitModePicker(
                        mode: Binding(
                            get: { self.fitMode },
                            set: { newValue in
                                self.updateFitMode(newValue)
                                rerender()
                            })))
                    WorkbenchSpecificInput.control("zeroAtOrigin", IVZeroAtOriginToggle(
                        isOn: Binding(get: { self.zeroAtCurrentOrigin }, set: { self.zeroAtCurrentOrigin = $0 }),
                        isEnabled: fitMode != .none,
                        onChange: rerender))
                }
            }
            WorkbenchSpecificGroup("angular", title: "Angular Analysis") {
                WorkbenchSpecificRow("angular") {
                    WorkbenchSpecificInput.control("toggle", IVAngularPlotToggle(
                        isOn: Binding(get: { self.angularPlotEnabled }, set: { self.updateAngularPlotEnabled($0) }),
                        isEnabled: canEnableAngularPlot,
                        onChange: rerender))
                    WorkbenchSpecificInput.control("fitMode", IVAngularFitModePicker(
                        mode: Binding(get: { self.angularFitMode }, set: { self.angularFitMode = $0 }),
                        isEnabled: angularPlotEnabled,
                        onChange: rerender))
                    WorkbenchSpecificInput.control("fold", IVAngularFitFoldPicker(
                        fold: Binding(get: { self.angularFitFold }, set: { self.angularFitFold = $0 }),
                        isEnabled: angularPlotEnabled,
                        onChange: rerender))
                }
            }
        }
    }
}

// MARK: - Power-law Fit Controls

private struct IVFitModePicker: WorkbenchLeafInput {
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

private struct IVZeroAtOriginToggle: WorkbenchLeafInput {
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

private struct IVAngularPlotToggle: WorkbenchLeafInput {
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

private struct IVAngularFitModePicker: WorkbenchLeafInput {
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

private struct IVAngularFitFoldPicker: WorkbenchLeafInput {
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

private struct IVCurrentBasisPicker: WorkbenchLeafInput {
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

private struct IVChannelPicker: WorkbenchLeafInput {
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
