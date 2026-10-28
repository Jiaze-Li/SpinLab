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

    /// Accessibility name of the axis' label field; the visible caption is the shared "Label".
    var labelFieldAccessibilityName: String {
        switch self {
        case .x: return "X axis label"
        case .y: return "Y axis label"
        case .leftY: return "Left Y axis label"
        case .rightY: return "Right Y axis label"
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
    /// Which sub-modules to emit, so a mode component can place labels and ranges/ticks in
    /// different logical rows without a second implementation.
    struct Parts: OptionSet {
        let rawValue: Int
        static let labels = Parts(rawValue: 1)
        static let ranges = Parts(rawValue: 2)
        static let ticks = Parts(rawValue: 4)
        static let all: Parts = [.labels, .ranges, .ticks]
    }

    let model: PlotAxesModel
    let idPrefix: String
    var parts: Parts = .all

    var body: some View {
        if parts.contains(.labels), !model.labels.isEmpty {
            labelsGroup.workbenchFlowFill(maxGrowth: WorkbenchInputWidth.labelFieldMaxGrowth * CGFloat(model.labels.count))
        }
        if parts.contains(.ranges), !model.ranges.isEmpty { rangesGroup }
        if parts.contains(.ticks), !model.ticks.isEmpty { ticksGroup }
    }

    /// `Label  X [field]  Y [field]`: one shared caption (VC-11), each axis marker stays glued to
    /// its own field and wraps with it as a whole.
    private var labelsGroup: some View {
        WorkbenchControlGroup(id: "\(idPrefix).axisLabels") {
            WorkbenchControlRow(id: "\(idPrefix).axisLabels.row", label: "Label") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.planeRowSpacing) {
                    ForEach(model.labels, id: \.role) { label in
                        axisLabelUnit(label).workbenchFlowFill()
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func axisLabelUnit(_ label: PlotAxisLabelModel) -> some View {
        let id = "\(idPrefix).axisLabels.\(label.role.rawValue)"
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label.role.title)
                .workbenchTextRole(.label, id: id + "#marker")
                .fixedSize()
                .accessibilityHidden(true)
            LabelOverrideField(
                label: "", renderedDefault: label.rendered, currentValue: label.override,
                sourceResetToken: model.sourceResetToken,
                onCommit: { label.onCommit($0); model.onLabelCommitted() },
                fieldMaxWidth: .infinity)
                .workbenchAccessibilityName(label.role.labelFieldAccessibilityName, id: id + "#content")
                .workbenchProbed(id + "#content")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(id)
        .workbenchProbed(id)
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
