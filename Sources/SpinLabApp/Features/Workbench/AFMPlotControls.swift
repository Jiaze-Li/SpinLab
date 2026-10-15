import SwiftUI

// MARK: - AFM-specific controls
//
// Specific content for the shared Controls Surface (spec 06 §5): Data Channel · Processing ·
// Plot Decoration (Scale Bar). AFM draws no axes, so it gets no axis controls (CS-16). The leaf
// inputs take plain values and closures; the adapter below is the only place that reads the store.

/// Reserved slot only: no Edge Crop algorithm exists in V1, so nothing is bound and nothing can
/// change.
struct AFMEdgeCropPlaceholderInput: WorkbenchLeafInput {
    var body: some View {
        Picker("", selection: .constant("unavailable")) {
            Text("Not available").tag("unavailable")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(true)
        .help("Edge Crop is not available yet.")
    }
}

/// Manual scale-bar length in µm; commits on Return and restores the last valid value otherwise.
struct AFMScaleBarLengthInput: WorkbenchLeafInput {
    let lengthMicrometers: Double
    let onCommit: (Double) -> Void

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            TextField("µm", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .onSubmit(commit)
            Text("µm")
                .font(WorkbenchUIStyle.controlLabelFont)
                .fixedSize()
        }
        .onAppear { text = Self.format(lengthMicrometers) }
        .onChange(of: lengthMicrometers) { _, value in text = Self.format(value) }
    }

    private func commit() {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, value > 0 else {
            text = Self.format(lengthMicrometers)
            return
        }
        onCommit(value)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

extension AFMWorkspaceStore {
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        let channels = parsedDataset?.channels ?? []
        let configuration = processingConfiguration
        let bar = scaleBar
        let setBar: (AFMScaleBarSetting) -> Void = { self.updateScaleBar($0) }

        let specific = WorkbenchSpecificContent {
            WorkbenchSpecificGroup("dataChannel", title: "Data Channel") {
                WorkbenchSpecificRow("channel", label: "Channel") {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.activeChannelID }, set: { self.updateActiveChannel($0) }),
                        options: channels.map { (title: $0.displayLabel, value: $0.id) })
                }
                WorkbenchSpecificRow("edgeCrop", label: "Edge Crop") {
                    WorkbenchSpecificInput.control("placeholder", AFMEdgeCropPlaceholderInput())
                }
            }
            WorkbenchSpecificGroup("processing", title: "Processing") {
                WorkbenchSpecificRow("surfaceLevel", label: "Surface Level") {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.surfaceLevel }, set: { self.updateSurfaceLevel($0) }),
                        options: [("Off", AFMSurfaceLevel.off), ("Plane", .plane), ("Robust Plane", .robustPlane)])
                }
                WorkbenchSpecificRow("lineFlatten", label: "Line Flatten") {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.lineFlattenOrder }, set: { self.updateLineFlattenOrder($0) }),
                        options: [("Off", AFMLineFlattenOrder.off), ("0", .order0), ("1", .order1), ("2", .order2)])
                }
                WorkbenchSpecificRow("zero", label: "Zero") {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.zeroReference }, set: { self.updateZeroReference($0) }),
                        options: [("None", AFMZeroReference.none), ("Mean", .mean), ("Minimum", .minimum)])
                }
            }
            WorkbenchSpecificGroup("plotDecoration", title: "Plot Decoration") {
                WorkbenchSpecificRow("scaleBar", label: "Scale Bar") {
                    WorkbenchSpecificInput.menu(
                        "mode",
                        selection: Binding(get: { bar.mode }, set: { mode in
                            var next = bar
                            next.mode = mode
                            setBar(next)
                        }),
                        options: [("Off", AFMScaleBarSetting.Mode.off), ("Auto", .auto), ("Manual", .manual)])
                }
                // Scale-bar details are shown only while a bar is drawn.
                if bar.mode != .off {
                    WorkbenchSpecificRow("barText", label: "Bar text") {
                        WorkbenchSpecificInput.menu(
                            "color",
                            selection: Binding(get: { bar.color }, set: { color in
                                var next = bar
                                next.color = color
                                setBar(next)
                            }),
                            options: [("White", HeatmapScaleBarColor.white), ("Black", .black)])
                    }
                }
                if bar.mode == .manual {
                    WorkbenchSpecificRow("barLength", label: "Length") {
                        WorkbenchSpecificInput.control("value", AFMScaleBarLengthInput(
                            lengthMicrometers: bar.manualLengthMicrometers,
                            onCommit: { value in
                                var next = bar
                                next.manualLengthMicrometers = value
                                setBar(next)
                            }))
                    }
                }
            }
        }
        return heatmapControlsDescriptor(
            appState: appState, globalPlotDefaults: globalPlotDefaults, flushSource: "afmStyleChange",
            renderedTitle: parsedDataset?.title ?? "",
            sourceResetToken: "\(cachedInputFiles.first ?? "")|\(configuration.activeChannelID)",
            specific: specific)
    }
}
