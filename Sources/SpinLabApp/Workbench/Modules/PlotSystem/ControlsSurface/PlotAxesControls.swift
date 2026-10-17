import SwiftUI

/// Axis role a Plot Mode can expose (CS-38a). Shared Axes is configured only by a list of
/// these roles; it never inspects which workflow supplied them.
enum PlotAxisRole: String {
    case x, y, leftY, rightY

    var title: String {
        switch self {
        case .x: return "X"
        case .y: return "Y"
        case .leftY: return "L-Y"
        case .rightY: return "R-Y"
        }
    }
}

struct PlotAxisLabelModel {
    var role: PlotAxisRole
    var rendered: String
    var override: String
    var onCommit: (String) -> Void
}

struct PlotAxisRangeModel {
    var role: PlotAxisRole
    var minDebugName: String
    var maxDebugName: String
    var layoutMin: Double?
    var layoutMax: Double?
    var overrideMin: Double?
    var overrideMax: Double?
    var onCommitMin: (Double?) -> Void
    var onCommitMax: (Double?) -> Void
    var debugLog: ((String) -> Void)? = nil
}

struct PlotAxisTickModel {
    var role: PlotAxisRole
    var count: Int
    var onChange: (Int) -> Void
}

/// Capability configuration of the Shared Axes module. An empty list removes the matching
/// sub-module (labels / ranges / ticks); an axis-free figure passes all three empty and
/// renders nothing.
struct PlotAxesModel {
    var sourceResetToken: String
    var labels: [PlotAxisLabelModel] = []
    var ranges: [PlotAxisRangeModel] = []
    var hasRangeOverride: Bool = false
    var onResetRanges: () -> Void = {}
    var ticks: [PlotAxisTickModel] = []
    /// Called after a label is committed (display-only re-render).
    var onLabelCommitted: () -> Void = {}

    var isEmpty: Bool { labels.isEmpty && ranges.isEmpty && ticks.isEmpty }
}

/// Shared Axes: axis labels, ranges (+Reset) and tick counts for the declared roles (CS-38a).
/// Emits flow-level groups so the owning mode component can arrange them with its own
/// modules.
struct PlotAxesControls: View {
    let model: PlotAxesModel
    let idPrefix: String

    var body: some View {
        if !model.labels.isEmpty { labelsGroup.workbenchFlowFill() }
        if !model.ranges.isEmpty { rangesGroup }
        if !model.ticks.isEmpty { ticksGroup }
    }

    private var labelsGroup: some View {
        WorkbenchControlGroup(id: "\(idPrefix).axisLabels") {
            // Related axes sit side by side when they fit; each label keeps its own field.
            WorkbenchControlFlow {
                ForEach(model.labels, id: \.role) { label in
                    WorkbenchControlRow(id: "\(idPrefix).axisLabels.\(label.role.rawValue)", label: "\(label.role.title) label") {
                        LabelOverrideField(
                            label: "", renderedDefault: label.rendered, currentValue: label.override,
                            sourceResetToken: model.sourceResetToken,
                            onCommit: { label.onCommit($0); model.onLabelCommitted() },
                            fieldMaxWidth: .infinity)
                    }
                    .workbenchFlowFill()
                }
            }
        }
    }

    private var rangesGroup: some View {
        WorkbenchControlGroup(id: "\(idPrefix).ranges") {
            WorkbenchControlRow(id: "\(idPrefix).ranges.row", label: "Range") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    ForEach(model.ranges, id: \.role) { range in
                        AxisRangeFieldRow(
                            axisLabel: range.role.title,
                            minDebugName: range.minDebugName, maxDebugName: range.maxDebugName,
                            minPlaceholder: formatPlotAxisRangeValue(range.layoutMin),
                            maxPlaceholder: formatPlotAxisRangeValue(range.layoutMax),
                            minValue: range.overrideMin, maxValue: range.overrideMax,
                            effectiveMinBound: range.overrideMin ?? range.layoutMin,
                            effectiveMaxBound: range.overrideMax ?? range.layoutMax,
                            sourceResetToken: model.sourceResetToken,
                            onCommitMin: range.onCommitMin, onCommitMax: range.onCommitMax,
                            debugLog: range.debugLog)
                    }
                    PlotRangeResetControl(hasActiveOverride: model.hasRangeOverride, onReset: model.onResetRanges, alwaysPresent: true)
                }
            }
        }
    }

    private var ticksGroup: some View {
        WorkbenchControlGroup(id: "\(idPrefix).ticks") {
            WorkbenchControlRow(id: "\(idPrefix).ticks.row", label: "Ticks", atomic: true) {
                SharedPlotTickCountControls(entries: model.ticks.map { tick in
                    .init(id: tick.role.rawValue, label: tick.role.title, count: tick.count, onChange: tick.onChange)
                })
            }
        }
    }
}
