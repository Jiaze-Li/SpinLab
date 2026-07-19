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

/// Shared "Range X [..] Y [..]" row. Independent of series render mode / typography /
/// tick density — only takes axis range inputs. Paired with `CompactAxisTickCountRow`
/// for the "Ticks X [..] Y [..]" row.
/// Fixed, always-expanded single-line layout — no `ViewThatFits` width probing.
struct CompactAxisRangeRow: View {
    var activeLayout: WorkbenchPlotLayout? = nil
    var axisRangeOverride: AxisRangeOverride? = nil
    var onAxisBoundUpdate: (AxisRangeBound, Double?) -> Void
    var sourceResetToken: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Range")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            axisFieldRow(
                axisLabel: "X",
                minDebugName: "xMin",
                maxDebugName: "xMax",
                minPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisXMin),
                maxPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisXMax),
                minValue: axisRangeOverride?.xMin,
                maxValue: axisRangeOverride?.xMax,
                effectiveMinBound: axisRangeOverride?.xMin ?? activeLayout?.axisXMin,
                effectiveMaxBound: axisRangeOverride?.xMax ?? activeLayout?.axisXMax,
                minBound: .xMin,
                maxBound: .xMax
            )
            axisFieldRow(
                axisLabel: "Y",
                minDebugName: "yMin",
                maxDebugName: "yMax",
                minPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisYMin),
                maxPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisYMax),
                minValue: axisRangeOverride?.yMin,
                maxValue: axisRangeOverride?.yMax,
                effectiveMinBound: axisRangeOverride?.yMin ?? activeLayout?.axisYMin,
                effectiveMaxBound: axisRangeOverride?.yMax ?? activeLayout?.axisYMax,
                minBound: .yMin,
                maxBound: .yMax
            )
        }
    }

    private func axisFieldRow(
        axisLabel: String,
        minDebugName: String,
        maxDebugName: String,
        minPlaceholder: String,
        maxPlaceholder: String,
        minValue: Double?,
        maxValue: Double?,
        effectiveMinBound: Double?,
        effectiveMaxBound: Double?,
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
            effectiveMinBound: effectiveMinBound,
            effectiveMaxBound: effectiveMaxBound,
            sourceResetToken: sourceResetToken,
            onCommitMin: { v in
                AxisRangeDebug.log("CompactAxisRangeRow onBoundUpdate bound=\(minBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onAxisBoundUpdate(minBound, v)
            },
            onCommitMax: { v in
                AxisRangeDebug.log("CompactAxisRangeRow onBoundUpdate bound=\(maxBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onAxisBoundUpdate(maxBound, v)
            },
            debugLog: { AxisRangeDebug.log($0) }
        )
    }
}

// MARK: - CompactAxisTickCountRow

/// Shared "Ticks X [..] Y [..]" row wired to the typed per-tab `PlotTickOverride`.
/// Independent of axis range — see `CompactAxisRangeRow` for the paired row.
///
/// Takes already-resolved display counts rather than `PlotTickOverride` directly, so this
/// view stays independent of `chartStyleOverrides` — the caller resolves display precedence
/// (typed override → legacy chartStyleOverrides string → default) to match the render pipeline.
struct CompactAxisTickCountRow: View {
    let xTickCount: Int
    let yTickCount: Int
    let onTickCountUpdate: (PlotTickAxis, Int) -> Void

    var body: some View {
        SharedPlotTickCountControls(
            xTickCount: xTickCount,
            yTickCount: yTickCount,
            onXTickCountChange: { onTickCountUpdate(.x, PlotTickConfiguration.clamp($0)) },
            onYTickCountChange: { onTickCountUpdate(.y, PlotTickConfiguration.clamp($0)) }
        )
    }
}
