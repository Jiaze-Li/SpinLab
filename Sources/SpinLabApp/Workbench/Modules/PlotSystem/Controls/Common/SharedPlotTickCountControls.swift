import SwiftUI

/// Shared X/Y axis tick-count stepper controls.
///
/// Displays "Ticks X [n] Y [n]" and calls back when either count changes.
/// Reused by any plot workflow that controls tick density via strongly-typed
/// state. Valid range and clamping delegate to PlotTickConfiguration.
struct SharedPlotTickCountControls: View {
    let xTickCount: Int
    let yTickCount: Int
    let onXTickCountChange: (Int) -> Void
    let onYTickCountChange: (Int) -> Void

    static let tickRange = PlotTickConfiguration.validRange

    var body: some View {
        HStack(spacing: 6) {
            Text("Ticks")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            tickStepper(label: "X", count: xTickCount, onChange: onXTickCountChange)
            tickStepper(label: "Y", count: yTickCount, onChange: onYTickCountChange)
        }
    }

    @ViewBuilder
    private func tickStepper(label: String, count: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Stepper(
                value: Binding(
                    get: { count },
                    set: { onChange(max(Self.tickRange.lowerBound, min(Self.tickRange.upperBound, $0))) }
                ),
                in: Self.tickRange
            ) {
                Text("\(count)")
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(width: 16)
            }
            .frame(width: 64)
        }
    }
}
