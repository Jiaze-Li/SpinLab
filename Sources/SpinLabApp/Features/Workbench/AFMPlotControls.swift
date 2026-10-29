import SwiftUI

// MARK: - AFM-specific controls
//
// Specific content for the shared Controls Surface (spec 06 §5): Data Channel · Processing ·
// Plot Decoration (Scale Bar), shared over two logical regions (CS-18b). AFM draws no axes, so it
// gets no axis controls (CS-16). Edge Crop has no algorithm yet and is not shown. The leaf
// inputs take plain values and closures; the adapter below is the only place that reads the store.

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
        guard let value = WorkbenchNumericFieldText.parseFinite(text), value > 0 else {
            text = Self.format(lengthMicrometers)
            return
        }
        onCommit(value)
    }

    private static func format(_ value: Double) -> String {
        WorkbenchNumericFieldText.formatIntegerIfExact(value)
    }
}

extension AFMSurfaceLevel {
    /// Complete name behind the short menu title (tooltip and accessibility value, VC-8).
    var fullName: String {
        switch self {
        case .off: return "Off"
        case .plane: return "Plane Leveling"
        case .robustPlane: return "Robust Plane Leveling"
        }
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
                WorkbenchSpecificRow("channel", label: "Channel", line: "selection", atomic: true) {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.activeChannelID }, set: { self.updateActiveChannel($0) }),
                        options: channels.map { (title: $0.displayLabel, value: $0.id) }, contentFit: true,
                        placeholder: channels.isEmpty ? "No channel" : "Select channel")
                }
            }
            WorkbenchSpecificGroup("processing", title: "Processing") {
                WorkbenchSpecificRow("surfaceLevel", label: "Leveling", line: "selection", atomic: true) {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.surfaceLevel }, set: { self.updateSurfaceLevel($0) }),
                        options: [("Off", AFMSurfaceLevel.off), ("Plane", .plane), ("Robust", .robustPlane)],
                        contentFit: true,
                        fullName: { $0.fullName })
                }
                WorkbenchSpecificRow("lineFlatten", label: "Line Flatten", line: "selection", cluster: "flatten", atomic: true) {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.lineFlattenOrder }, set: { self.updateLineFlattenOrder($0) }),
                        options: [("Off", AFMLineFlattenOrder.off), ("0", .order0), ("1", .order1), ("2", .order2)],
                        contentFit: true)
                }
                WorkbenchSpecificRow("zero", label: "Zero", line: "selection", cluster: "flatten", atomic: true) {
                    WorkbenchSpecificInput.menu(
                        "picker",
                        selection: Binding(get: { configuration.zeroReference }, set: { self.updateZeroReference($0) }),
                        options: [("None", AFMZeroReference.none), ("Mean", .mean), ("Minimum", .minimum)],
                        contentFit: true)
                }
            }
            WorkbenchSpecificGroup("plotDecoration", title: "Plot Decoration") {
                WorkbenchSpecificRow("scaleBar", label: "Scale Bar", line: "decoration", atomic: true) {
                    WorkbenchSpecificInput.menu(
                        "mode",
                        selection: Binding(get: { bar.mode }, set: { mode in
                            var next = bar
                            next.mode = mode
                            setBar(next)
                        }),
                        options: [("Off", AFMScaleBarSetting.Mode.off), ("Auto", .auto), ("Manual", .manual)],
                        contentFit: true)
                }
                // Scale-bar details are shown only while a bar is drawn.
                if bar.mode != .off {
                    WorkbenchSpecificRow("barText", label: "Bar text", line: "decoration", accessory: true, atomic: true) {
                        WorkbenchSpecificInput.menu(
                            "color",
                            selection: Binding(get: { bar.color }, set: { color in
                                var next = bar
                                next.color = color
                                setBar(next)
                            }),
                            options: [("White", HeatmapScaleBarColor.white), ("Black", .black)],
                            contentFit: true)
                    }
                }
                if bar.mode == .manual {
                    WorkbenchSpecificRow("barLength", label: "Length", line: "decoration", accessory: true) {
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
            defaultTitle: parsedDataset?.title ?? "",
            sourceResetToken: "\(cachedInputFiles.first ?? "")|\(configuration.activeChannelID)",
            // AFM draws no spatial axes: Title font only, no Axes module (CS-15).
            axes: PlotAxesModel(sourceResetToken: ""),
            fontRoles: [.title],
            specific: specific)
    }
}
