import SwiftUI

// MARK: - Metrics

/// Shared spacing / sizing tokens for every Controls Surface section (CS-27).
enum WorkbenchControlMetrics {
    static let groupSpacing: CGFloat = AppSpacing.lg
    /// Minimum gap between groups inside one logical Plot row; a justified row spreads leftover
    /// width on top of it, so tightening this only frees room for the row's own controls.
    static let planeRowSpacing: CGFloat = AppSpacing.sm
    static let lineSpacing: CGFloat = AppSpacing.md
    static let labelGap: CGFloat = AppSpacing.sm
    static let rowStackSpacing: CGFloat = AppSpacing.xs
    /// A label stays beside its input only if the input keeps at least this much width
    /// (or its own ideal width when smaller); otherwise the label moves above the input.
    static let comfortableInputWidth: CGFloat = 96
    /// Most extra space (beyond `groupSpacing`) a justified flow puts into one gap between
    /// groups. Flexible inputs grow first; this only bounds what is left, so justification
    /// can never be faked by blowing the gaps up.
    static let justifyMaxExtraGap: CGFloat = AppSpacing.lg * 3
    static let coordinateSpaceName = "workbench.controls.surface"
}

/// Input width presets for leaf inputs (CS-18). Leaf inputs use these instead of ad-hoc
/// `.frame(width:)` literals.
enum WorkbenchInputWidth {
    static let compact: CGFloat = 54
    static let standard: CGFloat = 96
    static let wide: CGFloat = 160
    /// Title template: ideal input width, and how far it may flex when there is room (ideal +
    /// growth = 340). Available keeps the rest of the line (CS-40).
    static let templateIdeal: CGFloat = 220
    static let templateMaxGrowth: CGFloat = 120
    /// Flexible Plot label fields (X / Y label) may grow this much beyond their ideal width.
    static let labelFieldMaxGrowth: CGFloat = 60
    /// Gap number field, Draw menu and the Line / Scatter menus of the Plot rows.
    static let gap: CGFloat = 58
    static let drawMenu: CGFloat = 110
    static let curveMenu: CGFloat = 66
    /// Content-fit menus (04 Content-fit sizing): the Heatmap Percentile preset fits its longest
    /// title, the Interpolation menu its abbreviated longest option.
    static let percentilePresetMenu: CGFloat = 132
    static let interpolationMenu: CGFloat = 156
    /// DualAxis Left / Right rows: choice menus (Line, Marker, Fill) and numeric preset menus (W, Size).
    static let seriesChoiceMenu: CGFloat = 76
    static let seriesPresetMenu: CGFloat = 60
    /// VC-4 minimums, measured on the interactive control itself.
    static let sliderMinimum: CGFloat = 80
    static let menuMinimum: CGFloat = 50
    static let stepper: CGFloat = 64
    static let hitTarget: CGFloat = 16
}

/// The three control text roles of `04_UI_RULES.md` VC-1.
enum WorkbenchTextRole: String {
    case label, value, hint
    var font: Font {
        switch self {
        case .label: return WorkbenchUIStyle.controlLabelFont
        case .value: return WorkbenchUIStyle.controlValueFont
        case .hint: return WorkbenchUIStyle.controlHintFont
        }
    }
}

/// Interactive control kinds that have a VC-4 minimum.
enum WorkbenchControlKind: String {
    case slider, textField, menu, stepper, iconButton
    var minimum: CGSize {
        switch self {
        case .slider: return CGSize(width: WorkbenchInputWidth.sliderMinimum, height: 0)
        case .textField: return CGSize(width: WorkbenchInputWidth.compact, height: 0)
        case .menu: return CGSize(width: WorkbenchInputWidth.menuMinimum, height: 0)
        case .stepper: return CGSize(width: WorkbenchInputWidth.stepper, height: 0)
        case .iconButton: return CGSize(width: WorkbenchInputWidth.hitTarget, height: WorkbenchInputWidth.hitTarget)
        }
    }
}

// MARK: - Planner (pure, unit-testable)

struct WorkbenchFlowItem: Equatable {
    var ideal: CGFloat
    var minimum: CGFloat
    var fills: Bool = false
    /// Most width a `fills` item may gain beyond `ideal`; nil = absorbs all leftover.
    var maxGrowth: CGFloat? = nil
}

/// How a line's leftover width is spent once flexible items are at their limit.
enum WorkbenchFlowDistribution: Equatable {
    /// Groups stay at the leading edge (default).
    case leading
    /// Leftover is spread over the gaps between the groups of a line, each gap gaining at
    /// most `maxExtraGap`. A line with one group stays leading, and so does the last line of a
    /// flow that wrapped (like justified text).
    case justified(maxExtraGap: CGFloat)
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
    static func plan(items: [WorkbenchFlowItem], available: CGFloat, spacing: CGFloat,
                     distribution: WorkbenchFlowDistribution = .leading) -> [WorkbenchFlowPlacement] {
        guard !items.isEmpty else { return [] }
        let limit = max(available, 0)
        var placements: [WorkbenchFlowPlacement] = []
        var x: CGFloat = 0
        var line = 0
        for (index, item) in items.enumerated() {
            let width = min(item.ideal, limit)
            if x > 0, x + width > limit + 0.001 {
                line += 1
                x = 0
            }
            placements.append(WorkbenchFlowPlacement(line: line, x: x, width: width, clipped: width + 0.001 < item.minimum))
            x += width + spacing
        }
        for lineIndex in 0...line {
            let members = placements.indices.filter { placements[$0].line == lineIndex }
            guard let last = members.last else { continue }
            var leftover = limit - (placements[last].x + placements[last].width)
            guard leftover > 0.5 else { continue }
            // ② Flexible items grow first, evenly, each up to its own cap.
            var growth: [Int: CGFloat] = [:]
            var open = members.filter { items[$0].fills }
            while leftover > 0.5, !open.isEmpty {
                let share = leftover / CGFloat(open.count)
                var stillOpen: [Int] = []
                for index in open {
                    let room = (items[index].maxGrowth ?? .infinity) - (growth[index] ?? 0)
                    let gain = min(share, room)
                    growth[index, default: 0] += gain
                    leftover -= gain
                    if room > share + 0.001 { stillOpen.append(index) }
                }
                open = stillOpen
            }
            // ③ What is left goes between the groups, bounded per gap.
            var extraGap: CGFloat = 0
            // A wrapped flow keeps its last line leading, like justified text.
            if case .justified(let maxExtraGap) = distribution, members.count > 1, leftover > 0.5, lineIndex < line || line == 0 {
                extraGap = min(leftover / CGFloat(members.count - 1), maxExtraGap)
            }
            var shift: CGFloat = 0
            for (position, index) in members.enumerated() {
                placements[index].x += shift + extraGap * CGFloat(position)
                let gain = growth[index] ?? 0
                placements[index].width += gain
                shift += gain
            }
        }
        return placements
    }

    /// Label beside input iff the input keeps a comfortable width. An `atomic` input cannot
    /// shrink (a stepper strip), so its comfortable width is its whole ideal width.
    static func labelBeside(labelWidth: CGFloat, gap: CGFloat, contentIdeal: CGFloat, available: CGFloat, atomic: Bool = false) -> Bool {
        let comfortable = atomic ? contentIdeal : min(contentIdeal, WorkbenchControlMetrics.comfortableInputWidth)
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
    private var _controls: [String: (kind: WorkbenchControlKind, frame: CGRect?)] = [:]
    private var _baselines: [String: CGFloat] = [:]
    private var _roles: [String: WorkbenchTextRole] = [:]
    private var _pairs: [String: [String: CGRect]] = [:]

    var frames: [String: CGRect] { lock.lock(); defer { lock.unlock() }; return _frames }

    func record(frame: CGRect, for id: String) {
        lock.lock(); _frames[id] = frame; lock.unlock()
    }
    /// Required minimum width of a row's input, measured by the shared layout itself.
    func record(minimum: CGFloat, for id: String) {
        lock.lock(); _minimums[id] = minimum; lock.unlock()
    }
    func register(control token: String, kind: WorkbenchControlKind) {
        lock.lock(); if _controls[token] == nil { _controls[token] = (kind, nil) }; lock.unlock()
    }
    func record(controlFrame frame: CGRect, for token: String) {
        lock.lock(); if let kind = _controls[token]?.kind { _controls[token] = (kind, frame) }; lock.unlock()
    }
    /// First-text-baseline offset from the top of a group, as placed by the shared flow.
    func record(baselineOffset: CGFloat, for id: String) {
        lock.lock(); _baselines[id] = baselineOffset; lock.unlock()
    }
    func record(pairMemberFrame frame: CGRect, token: String, pair: String) {
        lock.lock(); _pairs[pair, default: [:]][token] = frame; lock.unlock()
    }
    /// Members of a logical pair (CS-23) whose final frames do not share a line.
    var splitPairs: [String] {
        lock.lock(); defer { lock.unlock() }
        return _pairs.compactMap { pair, members in
            let frames = Array(members.values)
            for (i, a) in frames.enumerated() {
                for b in frames[(i + 1)...] where !(a.minY < b.maxY - 1 && b.minY < a.maxY - 1) {
                    return "pair \(pair) is split across lines"
                }
            }
            return nil
        }.sorted()
    }
    func record(role: WorkbenchTextRole, for id: String) {
        lock.lock(); _roles[id] = role; lock.unlock()
    }
    var baselineOffsets: [String: CGFloat] { lock.lock(); defer { lock.unlock() }; return _baselines }
    var roles: [String: WorkbenchTextRole] { lock.lock(); defer { lock.unlock() }; return _roles }
    func controlFrames(_ kind: WorkbenchControlKind) -> [CGRect] {
        lock.lock(); defer { lock.unlock() }
        return _controls.values.filter { $0.kind == kind }.compactMap(\.frame)
    }
    /// Interactive controls whose final size is below their VC-4 minimum (measured on the control).
    var undersizedControls: [String] {
        lock.lock(); defer { lock.unlock() }
        return _controls.compactMap { token, entry in
            guard let frame = entry.frame else { return nil }
            let min = entry.kind.minimum
            guard frame.width + 0.5 < min.width || frame.height + 0.5 < min.height else { return nil }
            return "\(entry.kind.rawValue) \(token) is \(Int(frame.width))x\(Int(frame.height)), minimum \(Int(min.width))x\(Int(min.height))"
        }.sorted()
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

    /// Probes only when an id is given.
    @ViewBuilder func workbenchProbed(ifNamed id: String?) -> some View {
        if let id { workbenchProbed(id) } else { self }
    }

    /// Applies a VC-1 text role (font + colour) and reports it to the layout probe.
    func workbenchTextRole(_ role: WorkbenchTextRole, id: String? = nil) -> some View {
        modifier(WorkbenchTextRoleModifier(role: role, id: id))
    }

    /// Declares an interactive control of a kind with a VC-4 minimum. Apply AFTER the control's
    /// own frame modifiers so the probe measures the control itself, not its parent.
    func workbenchControl(_ kind: WorkbenchControlKind) -> some View { modifier(WorkbenchControlModifier(kind: kind)) }

    /// Marks a member of a logical pair that must stay on one line (CS-23).
    func workbenchPairMember(_ pair: String) -> some View { modifier(WorkbenchPairMemberModifier(pair: pair)) }
}

private struct WorkbenchPairMemberModifier: ViewModifier {
    let pair: String
    @State private var token = UUID().uuidString
    @Environment(\.workbenchLayoutProbe) private var probe
    func body(content: Content) -> some View {
        content.background {
            if let probe {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { probe.record(pairMemberFrame: proxy.frame(in: .global), token: token, pair: pair) }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in probe.record(pairMemberFrame: frame, token: token, pair: pair) }
                }
            }
        }
    }
}

private struct WorkbenchTextRoleModifier: ViewModifier {
    let role: WorkbenchTextRole
    let id: String?
    @Environment(\.workbenchLayoutProbe) private var probe
    func body(content: Content) -> some View {
        content
            .font(role.font)
            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            .onAppear { if let id { probe?.record(role: role, for: id) } }
    }
}

private struct WorkbenchControlModifier: ViewModifier {
    let kind: WorkbenchControlKind
    @State private var token = UUID().uuidString
    @Environment(\.workbenchLayoutProbe) private var probe
    func body(content: Content) -> some View {
        content.background {
            if let probe {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            probe.register(control: token, kind: kind)
                            probe.record(controlFrame: proxy.frame(in: .global), for: token)
                        }
                        .onChange(of: proxy.size) { _, _ in probe.record(controlFrame: proxy.frame(in: .global), for: token) }
                }
            }
        }
    }
}

/// Checkbox whose title uses the label role like every other control label (VC-2).
struct WorkbenchCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    var id: String? = nil

    var body: some View {
        Toggle(isOn: $isOn) { Text(title).workbenchTextRole(.label, id: id) }
            .toggleStyle(.checkbox)
    }
}

/// Icon-only inline button with a hit area of at least the VC-4 minimum.
struct WorkbenchClearButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .frame(minWidth: WorkbenchInputWidth.hitTarget, minHeight: WorkbenchInputWidth.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear")
        .workbenchControl(.iconButton)
    }
}

// MARK: - Flow layout

private struct WorkbenchFillKey: LayoutValueKey {
    static let defaultValue: Bool = false
}

private struct WorkbenchMaxGrowthKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

extension View {
    /// Lets a group absorb leftover width on its line (e.g. a text field group). With
    /// `maxGrowth` the group gains at most that much beyond its ideal width (flexible, not
    /// unbounded); the rest of the line is left to the other groups.
    func workbenchFlowFill(_ fills: Bool = true, maxGrowth: CGFloat? = nil) -> some View {
        layoutValue(key: WorkbenchFillKey.self, value: fills)
            .layoutValue(key: WorkbenchMaxGrowthKey.self, value: maxGrowth)
    }
}

/// Wraps whole groups onto new lines by the width actually offered to it. `justified` is
/// opt-in: leftover width, after flexible groups reached their limit, is spread between the
/// groups of each line (bounded per gap) instead of pooling at the trailing edge.
struct WorkbenchControlFlow<Content: View>: View {
    var spacing: CGFloat = WorkbenchControlMetrics.groupSpacing
    var lineSpacing: CGFloat = WorkbenchControlMetrics.lineSpacing
    var justified: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.workbenchLayoutProbe) private var probe

    var body: some View {
        WorkbenchFlowLayout(
            spacing: spacing, lineSpacing: lineSpacing,
            distribution: justified ? .justified(maxExtraGap: WorkbenchControlMetrics.justifyMaxExtraGap) : .leading,
            probe: probe
        ) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkbenchFlowIDKey: LayoutValueKey {
    static let defaultValue: String? = nil
}

struct WorkbenchFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var distribution: WorkbenchFlowDistribution = .leading
    var probe: WorkbenchLayoutProbe? = nil

    private struct Arrangement {
        var placements: [WorkbenchFlowPlacement]
        var heights: [CGFloat]
        /// Vertical shift of each item inside its line so first text baselines line up (VC-5).
        var offsets: [CGFloat]
        var baselines: [CGFloat]
        var lineYs: [CGFloat]
        var firstBaseline: CGFloat
        var size: CGSize
    }

    private func items(_ subviews: Subviews) -> [WorkbenchFlowItem] {
        subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified).width
            return WorkbenchFlowItem(ideal: ideal, minimum: ideal, fills: subview[WorkbenchFillKey.self],
                                    maxGrowth: subview[WorkbenchMaxGrowthKey.self])
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let items = items(subviews)
        let available = width ?? items.reduce(0) { $0 + $1.ideal } + spacing * CGFloat(max(items.count - 1, 0))
        let placements = WorkbenchFlowPlanner.plan(items: items, available: available, spacing: spacing, distribution: distribution)
        var heights: [CGFloat] = []
        var baselines: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let proposal = ProposedViewSize(width: placements[index].width, height: nil)
            let size = subview.sizeThatFits(proposal)
            heights.append(size.height)
            baselines.append(subview.dimensions(in: ProposedViewSize(width: placements[index].width, height: size.height))[.firstTextBaseline])
        }
        let lineCount = (placements.map(\.line).max() ?? -1) + 1
        var lineBaselines = [CGFloat](repeating: 0, count: lineCount)
        for index in placements.indices {
            lineBaselines[placements[index].line] = max(lineBaselines[placements[index].line], baselines[index])
        }
        var offsets = [CGFloat](repeating: 0, count: placements.count)
        var lineHeights = [CGFloat](repeating: 0, count: lineCount)
        for index in placements.indices {
            let line = placements[index].line
            offsets[index] = lineBaselines[line] - baselines[index]
            lineHeights[line] = max(lineHeights[line], offsets[index] + heights[index])
        }
        var lineYs: [CGFloat] = []
        var y: CGFloat = 0
        for h in lineHeights { lineYs.append(y); y += h + lineSpacing }
        let totalHeight = max(y - lineSpacing, 0)
        let usedWidth = placements.map { $0.x + $0.width }.max() ?? 0
        return Arrangement(placements: placements, heights: heights, offsets: offsets, baselines: baselines, lineYs: lineYs,
                           firstBaseline: lineBaselines.first ?? 0,
                           size: CGSize(width: width ?? usedWidth, height: totalHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline, !subviews.isEmpty else { return nil }
        return bounds.minY + arrange(width: bounds.width, subviews: subviews).firstBaseline
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let placement = result.placements[index]
            if let probe, let id = subview[WorkbenchFlowIDKey.self] {
                probe.record(baselineOffset: result.baselines[index], for: id)
            }
            subview.place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + result.lineYs[placement.line] + result.offsets[index]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.width, height: result.heights[index])
            )
        }
    }
}

// MARK: - Group

/// One semantic unit of controls. Never split across lines by the flow (CS-23). The `title`
/// is always the group's accessibility label; it is drawn only when `titleVisible` (Specific
/// groups hide it, CS-18a).
struct WorkbenchControlGroup<Content: View>: View {
    let id: String
    var title: String? = nil
    var titleVisible: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchControlMetrics.rowStackSpacing) {
            if let title, titleVisible {
                Text(title)
                    .font(AppFontScale.groupHeader)
                    .accessibilityAddTraits(.isHeader)
                    .workbenchProbed(id + "#title")
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? id)
        .accessibilityIdentifier(id)
        .workbenchProbed(id)
        .layoutValue(key: WorkbenchFlowIDKey.self, value: id)
    }
}

// MARK: - Row (label + input)

private struct WorkbenchLabeledLayout: Layout {
    var id: String
    var atomic: Bool
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
            contentIdeal: contentIdeal.width, available: width, atomic: atomic)
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

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline else { return nil }
        let p = plan(width: bounds.width, subviews: subviews)
        let labelBaseline = subviews[0].dimensions(in: ProposedViewSize(p.labelSize))[.firstTextBaseline]
        if p.beside {
            let contentBaseline = subviews[1].dimensions(in: ProposedViewSize(p.contentSize))[.firstTextBaseline]
            return bounds.minY + max(labelBaseline, contentBaseline)
        }
        return bounds.minY + labelBaseline
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
    /// The input cannot be compressed (e.g. a stepper strip): the label moves above it unless
    /// the whole input fits beside the label.
    var atomic: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.workbenchLayoutProbe) private var probe

    var body: some View {
        Group {
            if let label {
                WorkbenchLabeledLayout(id: id, atomic: atomic, probe: probe) {
                    Text(label)
                        .workbenchTextRole(.label, id: id)
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
