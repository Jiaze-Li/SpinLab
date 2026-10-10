import SwiftUI

/// AFM workflow-specific Heatmap plugin controls: channel picker, Plane Level toggle, Line
/// Flatten order picker, Zero reference picker. Mounted via `HeatmapPlotControlsPanel`'s
/// generic `pluginControls` slot (Phase 1B) — Heatmap never sees these types. Uses the same
/// `WorkbenchPlotControlsPluginSection` / `ControlRow` primitives as the Cartesian XY
/// workflows' plugin controls.
struct AFMPlotControls: View {
    let channels: [CanonicalAFMChannel]
    let activeChannelID: String
    let planeLevelEnabled: Bool
    let lineFlattenOrder: AFMLineFlattenOrder
    let zeroReference: AFMZeroReference
    let onChannelChange: (String) -> Void
    let onPlaneLevelChange: (Bool) -> Void
    let onLineFlattenChange: (AFMLineFlattenOrder) -> Void
    let onZeroReferenceChange: (AFMZeroReference) -> Void

    private let rowLabelWidth: CGFloat = 74

    var body: some View {
        WorkbenchPlotControlsPluginSection {
            ControlRow(label: "Channel", labelWidth: rowLabelWidth) {
                HStack(spacing: 12) {
                    Picker("", selection: Binding(get: { activeChannelID }, set: onChannelChange)) {
                        ForEach(channels) { channel in
                            Text(channel.displayLabel).tag(channel.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(channels.isEmpty)
                    .frame(maxWidth: 160)

                    Toggle("Plane Level", isOn: Binding(get: { planeLevelEnabled }, set: onPlaneLevelChange))
                        .toggleStyle(.checkbox)
                }
            }

            SegmentedControlRow(
                label: "Line Flatten",
                labelWidth: rowLabelWidth,
                selection: Binding(get: { lineFlattenOrder }, set: onLineFlattenChange),
                pickerMaxWidth: 200
            ) {
                Text("Off").tag(AFMLineFlattenOrder.off)
                Text("0").tag(AFMLineFlattenOrder.order0)
                Text("1").tag(AFMLineFlattenOrder.order1)
                Text("2").tag(AFMLineFlattenOrder.order2)
            }

            SegmentedControlRow(
                label: "Zero",
                labelWidth: rowLabelWidth,
                selection: Binding(get: { zeroReference }, set: onZeroReferenceChange),
                pickerMaxWidth: 200
            ) {
                Text("None").tag(AFMZeroReference.none)
                Text("Mean").tag(AFMZeroReference.mean)
                Text("Minimum").tag(AFMZeroReference.minimum)
            }
        }
    }
}
