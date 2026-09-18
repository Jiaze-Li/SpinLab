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

    var body: some View {
        WorkbenchPlotControlsPluginSection {
            ControlRow(label: "Channel") {
                Picker("", selection: Binding(get: { activeChannelID }, set: onChannelChange)) {
                    ForEach(channels) { channel in
                        Text(channel.displayLabel).tag(channel.id)
                    }
                }
                .labelsHidden()
                .disabled(channels.isEmpty)
                .frame(maxWidth: 200)
            }

            Toggle("Plane Level", isOn: Binding(get: { planeLevelEnabled }, set: onPlaneLevelChange))
                .toggleStyle(.checkbox)

            ControlRow(label: "Line Flatten") {
                Picker("", selection: Binding(get: { lineFlattenOrder }, set: onLineFlattenChange)) {
                    Text("Off").tag(AFMLineFlattenOrder.off)
                    Text("0").tag(AFMLineFlattenOrder.order0)
                    Text("1").tag(AFMLineFlattenOrder.order1)
                    Text("2").tag(AFMLineFlattenOrder.order2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            ControlRow(label: "Zero") {
                Picker("", selection: Binding(get: { zeroReference }, set: onZeroReferenceChange)) {
                    Text("None").tag(AFMZeroReference.none)
                    Text("Mean").tag(AFMZeroReference.mean)
                    Text("Minimum").tag(AFMZeroReference.minimum)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
    }
}
