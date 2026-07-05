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
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                drawRow
                VStack(alignment: .leading, spacing: 6) {
                    drawModePicker
                    WorkbenchSeriesAppearanceControls(
                        globalPlotDefaults: $globalPlotDefaults,
                        onStyleChange: onStyleChange
                    )
                }
            }
            if let onAxisBoundUpdate {
                CompactRangeTicksRow(
                    activeLayout: activeLayout,
                    axisRangeOverride: axisRangeOverride,
                    sourceResetToken: sourceResetToken,
                    xTickCount: chartStyleOverrides["tickTargetX"].flatMap(Int.init) ?? 6,
                    yTickCount: chartStyleOverrides["tickTargetY"].flatMap(Int.init) ?? 5,
                    onBoundUpdate: onAxisBoundUpdate,
                    onXTickCountChange: { updateTickCount(key: "tickTargetX", value: $0) },
                    onYTickCountChange: { updateTickCount(key: "tickTargetY", value: $0) }
                )
            }
        }
    }

    private var drawRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            drawModePicker
            WorkbenchSeriesAppearanceControls(
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange
            )
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

// MARK: - CompactRangeTicksRow

/// Compact "Range X [..] Y [..]  Ticks X [..] Y [..]" row.
///
/// Builds the X/Y range fields directly via `AxisRangeFieldRow` instead of composing
/// `WorkbenchAxisRangeControls`, whose own internal `ViewThatFits` (used to stack X/Y
/// on very narrow widths) caused this row to fall back to two lines even when there
/// was enough width for Range and Ticks side by side. A single `ViewThatFits` here
/// picks between one wide line and a Range-row/Ticks-row fallback.
private struct CompactRangeTicksRow: View {
    var activeLayout: WorkbenchPlotLayout?
    var axisRangeOverride: AxisRangeOverride?
    var sourceResetToken: String
    var xTickCount: Int
    var yTickCount: Int
    var onBoundUpdate: (AxisRangeBound, Double?) -> Void
    var onXTickCountChange: (Int) -> Void
    var onYTickCountChange: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                rangeRow
                ticksRow
            }
            VStack(alignment: .leading, spacing: 6) {
                rangeRow
                ticksRow
            }
        }
    }

    private var rangeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Range")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            axisFieldRow(
                axisLabel: "X",
                minDebugName: "xMin",
                maxDebugName: "xMax",
                minPlaceholder: formatAxisRangeValue(activeLayout?.axisXMin),
                maxPlaceholder: formatAxisRangeValue(activeLayout?.axisXMax),
                minValue: axisRangeOverride?.xMin,
                maxValue: axisRangeOverride?.xMax,
                minBound: .xMin,
                maxBound: .xMax
            )
            axisFieldRow(
                axisLabel: "Y",
                minDebugName: "yMin",
                maxDebugName: "yMax",
                minPlaceholder: formatAxisRangeValue(activeLayout?.axisYMin),
                maxPlaceholder: formatAxisRangeValue(activeLayout?.axisYMax),
                minValue: axisRangeOverride?.yMin,
                maxValue: axisRangeOverride?.yMax,
                minBound: .yMin,
                maxBound: .yMax
            )
        }
    }

    private var ticksRow: some View {
        SharedPlotTickCountControls(
            xTickCount: xTickCount,
            yTickCount: yTickCount,
            onXTickCountChange: onXTickCountChange,
            onYTickCountChange: onYTickCountChange
        )
    }

    private func axisFieldRow(
        axisLabel: String,
        minDebugName: String,
        maxDebugName: String,
        minPlaceholder: String,
        maxPlaceholder: String,
        minValue: Double?,
        maxValue: Double?,
        minBound: AxisRangeBound,
        maxBound: AxisRangeBound
    ) -> AxisRangeFieldRow {
        AxisRangeFieldRow(
            axisLabel: axisLabel,
            minDebugName: minDebugName,
            maxDebugName: maxDebugName,
            minPlaceholder: minPlaceholder,
            maxPlaceholder: maxPlaceholder,
            minValue: minValue,
            maxValue: maxValue,
            sourceResetToken: sourceResetToken,
            onCommitMin: { v in
                AxisRangeDebug.log("CompactRangeTicksRow onBoundUpdate bound=\(minBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onBoundUpdate(minBound, v)
            },
            onCommitMax: { v in
                AxisRangeDebug.log("CompactRangeTicksRow onBoundUpdate bound=\(maxBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onBoundUpdate(maxBound, v)
            }
        )
    }
}
