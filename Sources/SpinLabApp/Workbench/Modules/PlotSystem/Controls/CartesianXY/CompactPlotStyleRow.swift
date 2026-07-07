import SwiftUI

// MARK: - CompactPlotStyleRow

/// Shared style row for Cartesian XY plot controls: render-mode picker and
/// line/scatter appearance pickers. Fixed, always-expanded layout — no
/// `ViewThatFits` width probing.
struct CompactPlotStyleRow: View {
    @Binding var seriesRenderMode: SeriesRenderMode
    @Binding var globalPlotDefaults: [String: String]
    var onStyleChange: (() -> Void)?

    var body: some View {
        let _ = { () -> Void in
            guard WorkbenchPerformanceDiagnostics.isEnabled else { return }
            PerfCounters.styleRowBody += 1
            print("[PERF][count] Style controls body count=\(PerfCounters.styleRowBody)")
        }()
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
}

// MARK: - Equatable signature guard

/// Restricts equality to draw mode + the two style keys this row renders
/// (`lineWidth`, `pointRadius`), so unrelated dictionary churn (font size edits,
/// axis range, tab switches) doesn't force a rebuild via `.equatable()`.
extension CompactPlotStyleRow: Equatable {
    static func == (lhs: CompactPlotStyleRow, rhs: CompactPlotStyleRow) -> Bool {
        let isEqual = lhs.seriesRenderMode == rhs.seriesRenderMode
            && lhs.globalPlotDefaults["lineWidth"] == rhs.globalPlotDefaults["lineWidth"]
            && lhs.globalPlotDefaults["pointRadius"] == rhs.globalPlotDefaults["pointRadius"]
        if WorkbenchPerformanceDiagnostics.isEnabled {
            print(isEqual ? "[PERF][controls] style cache hit" : "[PERF][controls] style rebuild")
        }
        return isEqual
    }
}

// MARK: - CompactAxisRangeRow

/// Shared "Range X [..] Y [..]  Ticks X [..] Y [..]" row. Independent of series
/// render mode / typography — only takes axis range and tick-count inputs.
/// Fixed, always-expanded single-line layout — no `ViewThatFits` width probing.
struct CompactAxisRangeRow: View {
    @Binding var chartStyleOverrides: [String: String]
    var activeLayout: WorkbenchPlotLayout? = nil
    var axisRangeOverride: AxisRangeOverride? = nil
    var onAxisBoundUpdate: (AxisRangeBound, Double?) -> Void
    var sourceResetToken: String = ""

    private var xTickCount: Int { chartStyleOverrides["tickTargetX"].flatMap(Int.init) ?? 6 }
    private var yTickCount: Int { chartStyleOverrides["tickTargetY"].flatMap(Int.init) ?? 5 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            rangeRow
            ticksRow
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
            onXTickCountChange: { updateTickCount(key: "tickTargetX", value: $0) },
            onYTickCountChange: { updateTickCount(key: "tickTargetY", value: $0) }
        )
    }

    private func updateTickCount(key: String, value: Int) {
        chartStyleOverrides[key] = "\(value)"
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
                AxisRangeDebug.log("CompactAxisRangeRow onBoundUpdate bound=\(minBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onAxisBoundUpdate(minBound, v)
            },
            onCommitMax: { v in
                AxisRangeDebug.log("CompactAxisRangeRow onBoundUpdate bound=\(maxBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onAxisBoundUpdate(maxBound, v)
            }
        )
    }
}
