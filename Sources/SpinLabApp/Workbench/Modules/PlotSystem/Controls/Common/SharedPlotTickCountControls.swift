import SwiftUI

/// Shared axis tick-count stepper strip: one "label [n]" stepper per axis role.
///
/// Callers supply one entry per axis they actually have (X/Y, or X/L-Y/R-Y); the strip
/// knows nothing about which plot it serves. Valid range and clamping delegate to
/// PlotTickConfiguration.
struct SharedPlotTickCountControls: View {
    struct Entry: Identifiable {
        let id: String
        let label: String
        let count: Int
        let onChange: (Int) -> Void
    }

    let entries: [Entry]

    static let tickRange = PlotTickConfiguration.validRange

    var body: some View {
        WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
            ForEach(entries) { entry in
                tickStepper(entry)
            }
        }
    }

    @ViewBuilder
    private func tickStepper(_ entry: Entry) -> some View {
        HStack(spacing: 3) {
            Text(entry.label)
                .workbenchTextRole(.label)
                .fixedSize()
            Stepper(
                value: Binding(
                    get: { entry.count },
                    set: { entry.onChange(max(Self.tickRange.lowerBound, min(Self.tickRange.upperBound, $0))) }
                ),
                in: Self.tickRange
            ) {
                Text("\(entry.count)")
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(width: 16)
            }
            .frame(width: WorkbenchInputWidth.stepper)
            .workbenchControl(.stepper)
        }
    }
}
