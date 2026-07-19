import SwiftUI

// MARK: - AxisRangeFieldRow

/// One "label [min] – [max]" range row: an axis letter plus two shared
/// `PlotAxisBoundField` bound fields.
///
/// Shared by every Cartesian XY workflow via `CompactPlotStyleRow`'s
/// `CompactAxisRangeRow`, so callers never compose `PlotAxisBoundField`
/// directly for a min/max pair.
struct AxisRangeFieldRow: View {
    let axisLabel: String
    let minDebugName: String
    let maxDebugName: String
    let minPlaceholder: String
    let maxPlaceholder: String
    let minValue: Double?
    let maxValue: Double?
    /// Effective auto/explicit value for the min bound — used to validate a
    /// submitted max against it — and vice versa. `override ?? layout value`.
    let effectiveMinBound: Double?
    let effectiveMaxBound: Double?
    let sourceResetToken: String
    let onCommitMin: (Double?) -> Void
    let onCommitMax: (Double?) -> Void
    var debugLog: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(axisLabel)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            PlotAxisBoundField(
                identity: PlotAxisBoundIdentity(debugName: minDebugName, role: .lower),
                placeholder: minPlaceholder,
                currentValue: minValue,
                effectiveOppositeBound: effectiveMaxBound,
                sourceResetToken: sourceResetToken,
                debugLog: debugLog,
                onCommit: onCommitMin
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            PlotAxisBoundField(
                identity: PlotAxisBoundIdentity(debugName: maxDebugName, role: .upper),
                placeholder: maxPlaceholder,
                currentValue: maxValue,
                effectiveOppositeBound: effectiveMinBound,
                sourceResetToken: sourceResetToken,
                debugLog: debugLog,
                onCommit: onCommitMax
            )
        }
    }
}

// MARK: - Shared axis range debug helpers

func axisRangeFmtD(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "nil" }

func axisRangeLayoutDebugStr(_ layout: WorkbenchPlotLayout?) -> String {
    guard let layout else { return "xMin=nil xMax=nil yMin=nil yMax=nil" }
    return "xMin=\(String(format: "%g", layout.axisXMin)) xMax=\(String(format: "%g", layout.axisXMax)) yMin=\(String(format: "%g", layout.axisYMin)) yMax=\(String(format: "%g", layout.axisYMax))"
}
