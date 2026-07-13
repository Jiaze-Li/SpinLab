import SwiftUI

// MARK: - CompactTypographyRow

/// Shared typography row for Cartesian XY plot controls.
///
/// Uses the existing shared font-size picker semantics. Fixed, always-expanded
/// single-line layout — no `ViewThatFits` width probing.
struct CompactTypographyRow: View {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: (() -> Void)?
    /// Global Title visibility toggle, rendered at the trailing end of this row.
    /// `nil` (the default) omits the toggle entirely, so callers that don't wire
    /// title visibility through this row are unaffected.
    var showTitle: Binding<Bool>? = nil

    init(
        globalPlotDefaults: Binding<[String: String]>,
        onStyleChange: (() -> Void)? = nil,
        showTitle: Binding<Bool>? = nil
    ) {
        self._globalPlotDefaults = globalPlotDefaults
        self.onStyleChange = onStyleChange
        self.showTitle = showTitle
    }

    var body: some View {
        let _ = { () -> Void in
            guard WorkbenchPerformanceDiagnostics.isEnabled else { return }
            PerfCounters.typographyRowBody += 1
            print("[PERF][count] Typography controls body count=\(PerfCounters.typographyRowBody)")
        }()
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        horizontalRow(style: style)
    }

    private func horizontalRow(style: WorkbenchChartStyle) -> some View {
        HStack(spacing: 8) {
            Text("Font")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            SharedPlotFontSizePicker(
                label: "Title",
                current: style.titleFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "titleFontSize"),
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Axis",
                current: style.axisTitleFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "axisTitleFontSize"),
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Ticks",
                current: style.tickLabelFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "tickLabelFontSize"),
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Legend",
                current: style.legendFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "legendFontSize"),
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Point",
                current: style.pointLabelFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "pointLabelFontSize"),
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            if let showTitle {
                Spacer(minLength: 12)
                Toggle("Title", isOn: showTitle)
                    .toggleStyle(.checkbox)
                    .onChange(of: showTitle.wrappedValue) { _, _ in onStyleChange?() }
            }
        }
    }

}

// MARK: - Equatable signature guard

/// Restricts equality to the font-related keys this row actually renders, so a
/// tab switch or an unrelated style/geometry change (which reconstructs this
/// view with a structurally different but font-wise-identical `globalPlotDefaults`)
/// does not force a rebuild via `.equatable()`.
extension CompactTypographyRow: Equatable {
    private static let typographyKeys = [
        "titleFontSize", "axisTitleFontSize", "tickLabelFontSize",
        "legendFontSize", "pointLabelFontSize", "plotFontName", "plotBoldFontName",
    ]

    static func == (lhs: CompactTypographyRow, rhs: CompactTypographyRow) -> Bool {
        let fontsEqual = typographyKeys.allSatisfy { lhs.globalPlotDefaults[$0] == rhs.globalPlotDefaults[$0] }
        let titleEqual = lhs.showTitle?.wrappedValue == rhs.showTitle?.wrappedValue
        let isEqual = fontsEqual && titleEqual
        if WorkbenchPerformanceDiagnostics.isEnabled {
            print(isEqual ? "[PERF][controls] typography cache hit" : "[PERF][controls] typography rebuild")
        }
        return isEqual
    }
}
