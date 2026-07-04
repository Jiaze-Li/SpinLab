import SwiftUI

// MARK: - CompactPlotStyleRow

/// Compact shared style row for Cartesian XY plot controls.
///
/// Keeps the render-mode picker, line/scatter appearance pickers, axis ranges,
/// and tick-density controls together while allowing the layout to wrap on
/// narrower widths.
struct CompactPlotStyleRow: View {
    @Binding var seriesRenderMode: SeriesRenderMode
    @Binding var globalPlotDefaults: [String: String]
    @Binding var chartStyleOverrides: [String: String]
    var onStyleChange: (() -> Void)?
    var activeLayout: WorkbenchPlotLayout? = nil
    var axisRangeOverride: AxisRangeOverride? = nil
    var onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil
    var sourceResetToken: String = ""

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalRow
            verticalRow
        }
    }

    private var horizontalRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            drawModePicker
            WorkbenchSeriesAppearanceControls(
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange
            )
            if let onAxisBoundUpdate {
                WorkbenchAxisRangeControls(
                    activeLayout: activeLayout,
                    axisRangeOverride: axisRangeOverride,
                    sourceResetToken: sourceResetToken,
                    onBoundUpdate: onAxisBoundUpdate
                )
                SharedPlotTickCountControls(
                    xTickCount: chartStyleOverrides["tickTargetX"].flatMap(Int.init) ?? 6,
                    yTickCount: chartStyleOverrides["tickTargetY"].flatMap(Int.init) ?? 5,
                    onXTickCountChange: { updateTickCount(key: "tickTargetX", value: $0) },
                    onYTickCountChange: { updateTickCount(key: "tickTargetY", value: $0) }
                )
            }
        }
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                drawModePicker
                WorkbenchSeriesAppearanceControls(
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange
                )
            }
            if let onAxisBoundUpdate {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    WorkbenchAxisRangeControls(
                        activeLayout: activeLayout,
                        axisRangeOverride: axisRangeOverride,
                        sourceResetToken: sourceResetToken,
                        onBoundUpdate: onAxisBoundUpdate
                    )
                    SharedPlotTickCountControls(
                        xTickCount: chartStyleOverrides["tickTargetX"].flatMap(Int.init) ?? 6,
                        yTickCount: chartStyleOverrides["tickTargetY"].flatMap(Int.init) ?? 5,
                        onXTickCountChange: { updateTickCount(key: "tickTargetX", value: $0) },
                        onYTickCountChange: { updateTickCount(key: "tickTargetY", value: $0) }
                    )
                }
            }
        }
    }

    private var drawModePicker: some View {
        HStack(spacing: 6) {
            Text("Draw")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Picker("", selection: Binding<SeriesRenderMode>(
                get: { seriesRenderMode },
                set: { newValue in
                    seriesRenderMode = newValue
                    onStyleChange?()
                }
            )) {
                Text("Line").tag(SeriesRenderMode.line)
                Text("Scatter").tag(SeriesRenderMode.scatter)
                Text("Line+Scatter").tag(SeriesRenderMode.lineAndScatter)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }

    private func updateTickCount(key: String, value: Int) {
        chartStyleOverrides[key] = "\(value)"
        onStyleChange?()
    }
}
