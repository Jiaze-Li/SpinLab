import SwiftUI

// MARK: - Metrics

/// Shared spacing / sizing tokens for every Controls Surface section (CS-27).
enum WorkbenchControlMetrics {
    static let groupSpacing: CGFloat = AppSpacing.lg
    static let lineSpacing: CGFloat = AppSpacing.md
    static let labelGap: CGFloat = AppSpacing.sm
    static let rowStackSpacing: CGFloat = AppSpacing.xs
    /// A label stays beside its input only if the input keeps at least this much width
    /// (or its own ideal width when smaller); otherwise the label moves above the input.
    static let comfortableInputWidth: CGFloat = 96
    static let coordinateSpaceName = "workbench.controls.surface"
}

/// Input width presets for leaf inputs (CS-18). Leaf inputs use these instead of ad-hoc
/// `.frame(width:)` literals.
enum WorkbenchInputWidth {
    static let compact: CGFloat = 54
    static let standard: CGFloat = 96
    static let wide: CGFloat = 160
}

// MARK: - Planner (pure, unit-testable)

struct WorkbenchFlowItem: Equatable {
    var ideal: CGFloat
    var minimum: CGFloat
    var fills: Bool = false
}

struct WorkbenchFlowPlacement: Equatable {
    var line: Int
    var x: CGFloat
    var width: CGFloat
    /// True when `width` is below the item's required minimum (content would be clipped).
    var clipped: Bool
}

/// Greedy wrapping of whole groups by actual available width. Pure so geometry can be
/// verified without a view hierarchy.
enum WorkbenchFlowPlanner {
    static func plan(items: [WorkbenchFlowItem], available: CGFloat, spacing: CGFloat) -> [WorkbenchFlowPlacement] {
        guard !items.isEmpty else { return [] }
        let limit = max(available, 0)
        var placements: [WorkbenchFlowPlacement] = []
        var lineStarts: [Int] = [0]
        var x: CGFloat = 0
        var line = 0
        for (index, item) in items.enumerated() {
            let width = min(item.ideal, limit)
            if x > 0, x + width > limit + 0.001 {
                line += 1
                x = 0
                lineStarts.append(index)
            }
            placements.append(WorkbenchFlowPlacement(line: line, x: x, width: width, clipped: width + 0.001 < item.minimum))
            x += width + spacing
        }
        // Distribute leftover width on each line to `fills` items.
        for lineIndex in 0...line {
            let members = placements.indices.filter { placements[$0].line == lineIndex }
            guard let last = members.last else { continue }
            let used = placements[last].x + placements[last].width
            let leftover = limit - used
            let fillers = members.filter { items[$0].fills }
            guard leftover > 0.5, !fillers.isEmpty else { continue }
            let share = leftover / CGFloat(fillers.count)
            var shift: CGFloat = 0
            for index in members {
                placements[index].x += shift
                if items[index].fills {
                    placements[index].width += share
                    shift += share
                }
            }
        }
        return placements
    }

    /// Label beside input iff the input keeps a comfortable width.
    static func labelBeside(labelWidth: CGFloat, gap: CGFloat, contentIdeal: CGFloat, available: CGFloat) -> Bool {
        let comfortable = min(contentIdeal, WorkbenchControlMetrics.comfortableInputWidth)
        return labelWidth + gap + comfortable <= available + 0.001
    }
}

// MARK: - Layout probe (tests only; inert when no probe is installed)

/// Collects real layout facts from the shared containers so tests can verify geometry
/// from an actual SwiftUI layout pass.
final class WorkbenchLayoutProbe: @unchecked Sendable {
    struct Clip: Equatable { var id: String; var required: CGFloat; var given: CGFloat }
    private let lock = NSLock()
    private var _frames: [String: CGRect] = [:]
    private var _minimums: [String: CGFloat] = [:]

    var frames: [String: CGRect] { lock.lock(); defer { lock.unlock() }; return _frames }

    func record(frame: CGRect, for id: String) {
        lock.lock(); _frames[id] = frame; lock.unlock()
    }
    /// Required minimum width of a row's input, measured by the shared layout itself.
    func record(minimum: CGFloat, for id: String) {
        lock.lock(); _minimums[id] = minimum; lock.unlock()
    }
    /// Inputs whose final rendered width is below the width they require (= clipped).
    /// Evaluated against final frames, so speculative layout passes cannot pollute it.
    var clips: [Clip] {
        lock.lock(); defer { lock.unlock() }
        return _minimums.compactMap { id, required in
            guard let given = _frames[id + "#content"]?.width, given + 0.5 < required else { return nil }
            return Clip(id: id, required: required, given: given)
        }.sorted { $0.id < $1.id }
    }
}

private struct WorkbenchLayoutProbeKey: EnvironmentKey {
    static let defaultValue: WorkbenchLayoutProbe? = nil
}

extension EnvironmentValues {
    var workbenchLayoutProbe: WorkbenchLayoutProbe? {
        get { self[WorkbenchLayoutProbeKey.self] }
        set { self[WorkbenchLayoutProbeKey.self] = newValue }
    }
}

private struct WorkbenchProbeReporter: View {
    let id: String
    let probe: WorkbenchLayoutProbe
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { probe.record(frame: proxy.frame(in: .named(WorkbenchControlMetrics.coordinateSpaceName)), for: id) }
                .onChange(of: proxy.frame(in: .named(WorkbenchControlMetrics.coordinateSpaceName))) { _, frame in
                    probe.record(frame: frame, for: id)
                }
        }
    }
}

private struct WorkbenchProbedModifier: ViewModifier {
    let id: String
    @Environment(\.workbenchLayoutProbe) private var probe
    func body(content: Content) -> some View {
        content.background {
            if let probe { WorkbenchProbeReporter(id: id, probe: probe) }
        }
    }
}

extension View {
    func workbenchProbed(_ id: String) -> some View { modifier(WorkbenchProbedModifier(id: id)) }
}

// MARK: - Flow layout

private struct WorkbenchFillKey: LayoutValueKey {
    static let defaultValue: Bool = false
}

extension View {
    /// Lets a group absorb leftover width on its line (e.g. a text field group).
    func workbenchFlowFill(_ fills: Bool = true) -> some View {
        layoutValue(key: WorkbenchFillKey.self, value: fills)
    }
}

/// Wraps whole groups onto new lines by the width actually offered to it.
struct WorkbenchControlFlow<Content: View>: View {
    var spacing: CGFloat = WorkbenchControlMetrics.groupSpacing
    var lineSpacing: CGFloat = WorkbenchControlMetrics.lineSpacing
    @ViewBuilder let content: () -> Content
    @Environment(\.workbenchLayoutProbe) private var probe

    var body: some View {
        WorkbenchFlowLayout(spacing: spacing, lineSpacing: lineSpacing, probe: probe) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var probe: WorkbenchLayoutProbe? = nil

    private func items(_ subviews: Subviews) -> [WorkbenchFlowItem] {
        subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified).width
            return WorkbenchFlowItem(ideal: ideal, minimum: ideal, fills: subview[WorkbenchFillKey.self])
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (placements: [WorkbenchFlowPlacement], heights: [CGFloat], lineYs: [CGFloat], size: CGSize) {
        let items = items(subviews)
        let available = width ?? items.reduce(0) { $0 + $1.ideal } + spacing * CGFloat(max(items.count - 1, 0))
        let placements = WorkbenchFlowPlanner.plan(items: items, available: available, spacing: spacing)
        var heights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            heights.append(subview.sizeThatFits(ProposedViewSize(width: placements[index].width, height: nil)).height)
        }
        let lineCount = (placements.map(\.line).max() ?? -1) + 1
        var lineHeights = [CGFloat](repeating: 0, count: lineCount)
        for index in placements.indices {
            lineHeights[placements[index].line] = max(lineHeights[placements[index].line], heights[index])
        }
        var lineYs: [CGFloat] = []
        var y: CGFloat = 0
        for h in lineHeights { lineYs.append(y); y += h + lineSpacing }
        let totalHeight = max(y - lineSpacing, 0)
        let usedWidth = placements.map { $0.x + $0.width }.max() ?? 0
        return (placements, heights, lineYs, CGSize(width: width ?? usedWidth, height: totalHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let placement = result.placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + result.lineYs[placement.line]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.width, height: result.heights[index])
            )
        }
    }
}

// MARK: - Group

/// One semantic unit of controls. Never split across lines by the flow (CS-23).
struct WorkbenchControlGroup<Content: View>: View {
    let id: String
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchControlMetrics.rowStackSpacing) {
            if let title {
                Text(title)
                    .font(AppFontScale.groupHeader)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? id)
        .accessibilityIdentifier(id)
        .workbenchProbed(id)
    }
}

// MARK: - Row (label + input)

private struct WorkbenchLabeledLayout: Layout {
    var id: String
    var probe: WorkbenchLayoutProbe?

    private struct Plan { var beside: Bool; var labelSize: CGSize; var contentSize: CGSize; var size: CGSize }

    private func plan(width: CGFloat?, subviews: Subviews) -> Plan {
        let label = subviews[0]
        let content = subviews[1]
        let labelIdeal = label.sizeThatFits(.unspecified)
        let contentIdeal = content.sizeThatFits(.unspecified)
        guard let width else {
            return Plan(beside: true, labelSize: labelIdeal, contentSize: contentIdeal,
                        size: CGSize(width: labelIdeal.width + WorkbenchControlMetrics.labelGap + contentIdeal.width,
                                     height: max(labelIdeal.height, contentIdeal.height)))
        }
        let beside = WorkbenchFlowPlanner.labelBeside(
            labelWidth: labelIdeal.width, gap: WorkbenchControlMetrics.labelGap,
            contentIdeal: contentIdeal.width, available: width)
        if beside {
            let contentWidth = max(width - labelIdeal.width - WorkbenchControlMetrics.labelGap, 0)
            let proposed = content.sizeThatFits(ProposedViewSize(width: min(contentWidth, max(contentIdeal.width, contentWidth)), height: nil))
            return Plan(beside: true, labelSize: labelIdeal, contentSize: CGSize(width: contentWidth, height: proposed.height),
                        size: CGSize(width: width, height: max(labelIdeal.height, proposed.height)))
        } else {
            let proposed = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return Plan(beside: false, labelSize: labelIdeal, contentSize: CGSize(width: width, height: proposed.height),
                        size: CGSize(width: width, height: labelIdeal.height + WorkbenchControlMetrics.rowStackSpacing + proposed.height))
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(width: bounds.width, subviews: subviews)
        if let probe {
            probe.record(minimum: subviews[1].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width, for: id)
        }
        if p.beside {
            let labelBaseline = subviews[0].dimensions(in: ProposedViewSize(p.labelSize))[.firstTextBaseline]
            let contentBaseline = subviews[1].dimensions(in: ProposedViewSize(p.contentSize))[.firstTextBaseline]
            let lineTop = max(labelBaseline, contentBaseline)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + lineTop - labelBaseline), anchor: .topLeading,
                              proposal: ProposedViewSize(p.labelSize))
            subviews[1].place(at: CGPoint(x: bounds.minX + p.labelSize.width + WorkbenchControlMetrics.labelGap,
                                          y: bounds.minY + lineTop - contentBaseline), anchor: .topLeading,
                              proposal: ProposedViewSize(p.contentSize))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(p.labelSize))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + p.labelSize.height + WorkbenchControlMetrics.rowStackSpacing),
                              anchor: .topLeading, proposal: ProposedViewSize(p.contentSize))
        }
    }
}

/// Label + input. The label sits beside the input when the input keeps a comfortable
/// width, otherwise above it. Label text becomes the accessibility label (CS-25a).
struct WorkbenchControlRow<Content: View>: View {
    let id: String
    var label: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.workbenchLayoutProbe) private var probe

    var body: some View {
        Group {
            if let label {
                WorkbenchLabeledLayout(id: id, probe: probe) {
                    Text(label)
                        .font(WorkbenchUIStyle.controlLabelFont)
                        .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                        .fixedSize()
                        .accessibilityHidden(true)
                    content()
                        .accessibilityLabel(label)
                        .workbenchProbed(id + "#content")
                }
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(id)
        .workbenchProbed(id)
    }
}
