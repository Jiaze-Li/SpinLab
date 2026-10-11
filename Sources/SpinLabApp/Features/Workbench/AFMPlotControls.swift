import SwiftUI

/// AFM workflow-specific Heatmap plugin controls, laid out as three rows of two columns:
///
///     Channel          Edge Crop (disabled placeholder)
///     Surface Level    Line Flatten
///     Zero             Scale Bar
///
/// Mounted via `HeatmapPlotControlsPanel`'s generic `pluginControls` slot — Heatmap never sees
/// these types.
struct AFMPlotControls: View {
    let channels: [CanonicalAFMChannel]
    let activeChannelID: String
    let surfaceLevel: AFMSurfaceLevel
    let lineFlattenOrder: AFMLineFlattenOrder
    let zeroReference: AFMZeroReference
    let scaleBar: AFMScaleBarSetting
    let onChannelChange: (String) -> Void
    let onSurfaceLevelChange: (AFMSurfaceLevel) -> Void
    let onLineFlattenChange: (AFMLineFlattenOrder) -> Void
    let onZeroReferenceChange: (AFMZeroReference) -> Void
    let onScaleBarChange: (AFMScaleBarSetting) -> Void

    private let rowLabelWidth: CGFloat = 78

    @State private var manualLengthText: String = ""

    var body: some View {
        WorkbenchPlotControlsPluginSection {
            WorkbenchPluginControlsGrid {
                cell("Channel") {
                    Picker("", selection: Binding(get: { activeChannelID }, set: onChannelChange)) {
                        ForEach(channels) { channel in
                            Text(channel.displayLabel).tag(channel.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(channels.isEmpty)
                }

                // Reserved slot only: no Edge Crop algorithm exists in V1, so nothing is bound
                // and nothing can change.
                cell("Edge Crop") {
                    Picker("", selection: .constant("unavailable")) {
                        Text("Not available").tag("unavailable")
                    }
                    .labelsHidden()
                    .disabled(true)
                }
                .help("Edge Crop is not available yet.")

                cell("Surface Level") {
                    Picker("", selection: Binding(get: { surfaceLevel }, set: onSurfaceLevelChange)) {
                        Text("Off").tag(AFMSurfaceLevel.off)
                        Text("Plane").tag(AFMSurfaceLevel.plane)
                    }
                    .labelsHidden()
                }

                cell("Line Flatten") {
                    Picker("", selection: Binding(get: { lineFlattenOrder }, set: onLineFlattenChange)) {
                        Text("Off").tag(AFMLineFlattenOrder.off)
                        Text("0").tag(AFMLineFlattenOrder.order0)
                        Text("1").tag(AFMLineFlattenOrder.order1)
                        Text("2").tag(AFMLineFlattenOrder.order2)
                    }
                    .labelsHidden()
                }

                cell("Zero") {
                    Picker("", selection: Binding(get: { zeroReference }, set: onZeroReferenceChange)) {
                        Text("None").tag(AFMZeroReference.none)
                        Text("Mean").tag(AFMZeroReference.mean)
                        Text("Minimum").tag(AFMZeroReference.minimum)
                    }
                    .labelsHidden()
                }

                cell("Scale Bar") {
                    Picker("", selection: Binding(
                        get: { scaleBar.mode },
                        set: { mode in
                            var next = scaleBar
                            next.mode = mode
                            onScaleBarChange(next)
                        }
                    )) {
                        Text("Off").tag(AFMScaleBarSetting.Mode.off)
                        Text("Auto").tag(AFMScaleBarSetting.Mode.auto)
                        Text("Manual").tag(AFMScaleBarSetting.Mode.manual)
                    }
                    .labelsHidden()
                }
            }

            // Scale bar details sit on their own full-width line so the six main controls keep a
            // stable two-column grid at any width; shown only while a bar is drawn.
            if scaleBar.mode != .off {
                HStack(spacing: 8) {
                    Text("Bar text")
                        .font(WorkbenchUIStyle.controlLabelFont)
                        .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                        .fixedSize()
                    Picker("", selection: Binding(
                        get: { scaleBar.color },
                        set: { color in
                            var next = scaleBar
                            next.color = color
                            onScaleBarChange(next)
                        }
                    )) {
                        Text("White").tag(HeatmapScaleBarColor.white)
                        Text("Black").tag(HeatmapScaleBarColor.black)
                    }
                    .labelsHidden()
                    .fixedSize()

                    if scaleBar.mode == .manual {
                        Text("Length")
                            .font(WorkbenchUIStyle.controlLabelFont)
                            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                            .fixedSize()
                        TextField("µm", text: $manualLengthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .onSubmit(commitManualLength)
                        Text("µm")
                            .font(WorkbenchUIStyle.controlLabelFont)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { manualLengthText = Self.format(scaleBar.manualLengthMicrometers) }
        .onChange(of: scaleBar.manualLengthMicrometers) { _, value in
            manualLengthText = Self.format(value)
        }
    }

    private func cell<Content: View>(_ label: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        WorkbenchPluginControlCell(label: label, labelWidth: rowLabelWidth, content: content)
    }

    private func commitManualLength() {
        guard let value = Double(manualLengthText.trimmingCharacters(in: .whitespaces)),
              value.isFinite, value > 0 else {
            manualLengthText = Self.format(scaleBar.manualLengthMicrometers)
            return
        }
        var next = scaleBar
        next.manualLengthMicrometers = value
        onScaleBarChange(next)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
